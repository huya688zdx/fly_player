import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/danmaku/models/danmaku_settings.dart';
import 'package:fly_player/desktop/playback/external_playback_host.dart';
import 'package:fly_player/desktop/playback/potplayer_session.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/playback/playback_source.dart';
import 'package:fly_player/providers/media_backend_provider.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Nas extends NasProvider {
  String account = 'A';
  String server = 'https://example.invalid';
  @override
  String get baseUrl => server;
  @override
  String get userName => account;
}

class _DirectHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}

void main() {
  for (final boundary in [
    'launch',
    'launchRejected',
    'snapshot',
    'configure',
    'activate',
    'subtitle',
  ]) {
    for (final scopeChange in [false, true]) {
      testWidgets(
        'Host ${scopeChange ? 'scope change' : 'stop / switch to builtin'} during $boundary releases launch',
        (tester) async {
          final directory = Directory.systemTemp.createTempSync(
            'external_fixture_',
          );
          final executable = File('${directory.path}/PotPlayerMini64.exe')
            ..writeAsBytesSync([0]);
          SharedPreferences.setMockInitialValues({
            'desktop_external_player_v1': jsonEncode({
              'enabled': true,
              'executablePath': executable.path,
            }),
            'player_danmaku_settings_v1': DanmakuSettings.defaults
                .copyWith(enabled: false)
                .encode(),
          });
          final nas = _Nas();
          final backend = MediaBackendProvider(nas);
          late BuildContext hostContext;
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<NasProvider>.value(value: nas),
                ChangeNotifierProvider.value(value: backend),
              ],
              child: MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: Builder(
                  builder: (context) {
                    hostContext = context;
                    return const Scaffold();
                  },
                ),
              ),
            ),
          );
          await tester.runAsync(
            () => IOOverrides.runZoned(
              () => HttpOverrides.runWithHttpOverrides(() async {
                await nas.reloadSettingsForTesting();
                final origin = await HttpServer.bind(
                  InternetAddress.loopbackIPv4,
                  0,
                );
                var originRequests = 0;
                var releasedSessions = 0;
                nas.server = 'http://127.0.0.1:${origin.port}';
                origin.listen((request) async {
                  if (request.method == 'POST') {
                    final body =
                        jsonDecode(await utf8.decoder.bind(request).join())
                            as Map;
                    if (body['req'] == 'media.quit') releasedSessions++;
                    request.response.headers.contentType = ContentType.json;
                    request.response.write(
                      jsonEncode({
                        'code': 0,
                        'data': {'result': 'succ'},
                      }),
                    );
                  } else {
                    originRequests++;
                    request.response.add([1, 2, 3]);
                  }
                  await request.response.close();
                });
                final source = MpvMediaSource(
                  itemGuid: 'same-item',
                  mediaGuid: 'same-media',
                  videoGuid: 'synthetic',
                  url: 'http://127.0.0.1:${origin.port}/synthetic.mkv',
                  headers: const {},
                  title: 'Synthetic only',
                  externalLocalSource: true,
                  subtitleTrackGuid: '',
                  danmakuAutoSearchAllowed: false,
                  playLink: 'synthetic-session',
                  startPosition: boundary == 'activate'
                      ? const Duration(seconds: 5)
                      : Duration.zero,
                );
                final entered = Completer<void>();
                final release = Completer<void>();
                final timers = <Timer>[];
                final calls = <String>[];
                var blocking = true;
                var alive = true;
                String? proxyUrl;
                tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
                  PotPlayerSession.channel,
                  (call) async {
                    calls.add(call.method);
                    final args = call.arguments as Map;
                    final rejectLaunch =
                        boundary == 'launchRejected' &&
                        blocking &&
                        call.method == 'launch';
                    if (call.method == 'launch') {
                      proxyUrl = args['url'] as String;
                      alive = true;
                    }
                    final sample = {
                      'alive': alive,
                      'file': proxyUrl,
                      'state': 2,
                      'positionMs': 5000,
                      'durationMs': 100000,
                    };
                    if (blocking &&
                        call.method ==
                            (boundary == 'launchRejected'
                                ? 'launch'
                                : boundary)) {
                      blocking = false;
                      entered.complete();
                      await release.future;
                    }
                    if (call.method == 'launch') {
                      return rejectLaunch ? null : 71;
                    }
                    if (call.method == 'snapshot') return sample;
                    if (call.method == 'close') alive = false;
                    return true;
                  },
                );
                try {
                  await runZoned(
                    () async {
                      final launching = ExternalPlaybackHost(
                        hostContext,
                      ).launch(source: source);
                      await entered.future.timeout(const Duration(seconds: 8));
                      final client = HttpClient()..findProxy = (_) => 'DIRECT';
                      try {
                        final response = await (await client.getUrl(
                          Uri.parse(proxyUrl!),
                        )).close();
                        expect(
                          await response.fold<List<int>>(
                            [],
                            (bytes, chunk) => bytes..addAll(chunk),
                          ),
                          [1, 2, 3],
                        );
                      } finally {
                        client.close(force: true);
                      }
                      expect(originRequests, 1);
                      if (scopeChange) {
                        nas.account = 'B';
                      } else {
                        await ExternalPlaybackHost.stop();
                      }
                      final callsAtCancel = calls.length;
                      release.complete();
                      expect(
                        await launching.timeout(const Duration(seconds: 8)),
                        isFalse,
                      );
                      expect(
                        releasedSessions,
                        scopeChange ? 0 : 1,
                        reason:
                            'Same-scope backend session release completes before launch returns',
                      );
                      expect(
                        calls
                            .skip(callsAtCancel)
                            .where(
                              (method) =>
                                  !['snapshot', 'close'].contains(method),
                            ),
                        isEmpty,
                      );
                      expect(timers.where((timer) => timer.isActive), isEmpty);
                      expect(
                        await ExternalPlaybackHost(
                          hostContext,
                        ).resume(itemGuid: source.itemGuid),
                        isFalse,
                      );
                      final proxy = Uri.parse(proxyUrl!);
                      await expectLater(
                        Socket.connect(
                          proxy.host,
                          proxy.port,
                          timeout: const Duration(seconds: 1),
                        ),
                        throwsA(isA<SocketException>()),
                      );
                      expect(
                        Directory.systemTemp
                            .listSync()
                            .whereType<Directory>()
                            .where(
                              (dir) => dir.path
                                  .split(Platform.pathSeparator)
                                  .last
                                  .startsWith('fly_external_player_'),
                            ),
                        isEmpty,
                      );
                      await ExternalPlaybackHost.stop();
                      expect(
                        await ExternalPlaybackHost(
                          hostContext,
                        ).launch(source: source),
                        isTrue,
                      );
                      await ExternalPlaybackHost.stop();
                      expect(timers.where((timer) => timer.isActive), isEmpty);
                    },
                    zoneSpecification: ZoneSpecification(
                      createPeriodicTimer:
                          (self, parent, zone, duration, callback) {
                            final timer = parent.createPeriodicTimer(
                              zone,
                              duration,
                              callback,
                            );
                            if (duration == const Duration(seconds: 1)) {
                              timers.add(timer);
                            }
                            return timer;
                          },
                    ),
                  );
                } finally {
                  if (!release.isCompleted) release.complete();
                  await ExternalPlaybackHost.stop();
                  for (final timer in timers) {
                    timer.cancel();
                  }
                  await origin.close(force: true);
                  tester.binding.defaultBinaryMessenger
                      .setMockMethodCallHandler(PotPlayerSession.channel, null);
                }
              }, _DirectHttpOverrides()),
              getSystemTempDirectory: () => directory,
            ),
          );
          await tester.pumpWidget(const SizedBox.shrink());
          backend.dispose();
          nas.dispose();
          directory.deleteSync(recursive: true);
        },
        skip: !Platform.isWindows,
      );
    }
  }
}
