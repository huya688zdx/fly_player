import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/danmaku/models/danmaku_settings.dart';
import 'package:fly_player/desktop/playback/external_playback_host.dart';
import 'package:fly_player/desktop/playback/potplayer_session.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/media_backend/session/media_backend_connection.dart';
import 'package:fly_player/playback/playback_source.dart';
import 'package:fly_player/providers/backend_session_provider.dart';
import 'package:fly_player/providers/media_backend_provider.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Nas extends NasProvider {
  String account = 'A';
  String server = 'https://synthetic.invalid';
  @override
  String get baseUrl => server;
  @override
  String get userName => account;
}

class _Session extends BackendSessionProvider {
  _Session() : super(autoLoad: false);
  String account = 'A';
  String server = 'https://synthetic.invalid';
  @override
  MediaBackendKind get currentKind => MediaBackendKind.emby;
  @override
  MediaBackendConnection get currentConnection => MediaBackendConnection(
    kind: currentKind,
    serverUrl: server,
    userId: account,
    accessToken: 'synthetic-unused-token',
  );
}

void main() {
  for (final neutral in [false, true]) {
    testWidgets(
      '${neutral ? 'neutral backend' : 'download'} start position uses only a ready current scoped session',
      (tester) async {
        final directory = Directory.systemTemp.createTempSync(
          'external_position_',
        );
        final executable = File('${directory.path}/PotPlayerMini64.exe')
          ..writeAsBytesSync([0]);
        final media = File('${directory.path}/synthetic.mkv')
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
        final session = _Session();
        final backend = MediaBackendProvider(nas, neutral ? session : null);
        late BuildContext hostContext;
        final sample = <String, Object>{
          'alive': true,
          'file': media.path,
          'state': 2,
          'positionMs': 45000,
          'durationMs': 100000,
        };
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          PotPlayerSession.channel,
          (call) async {
            if (call.method == 'launch') return 83;
            if (call.method == 'snapshot') return Map.of(sample);
            return true;
          },
        );
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
        await tester.runAsync(() async {
          await nas.reloadSettingsForTesting();
          final host = ExternalPlaybackHost(hostContext);
          final source = MpvMediaSource(
            itemGuid: 'shared-id',
            mediaGuid: 'media-id',
            videoGuid: 'video-id',
            url: media.path,
            headers: const {},
            title: 'Synthetic',
            externalLocalSource: true,
            isDownloadedFile: !neutral,
            subtitleTrackGuid: '',
            danmakuAutoSearchAllowed: false,
          );
          try {
            expect(await host.launch(source: source), isTrue);
            expect(
              host.positionForLaunch(itemGuid: 'shared-id'),
              const Duration(seconds: 45),
              reason: 'Same-session quality change keeps sampled position',
            );
            expect(host.positionForLaunch(itemGuid: 'different-item'), isNull);
            expect(
              ExternalPlaybackHost.status.value!.source.subtitleTrackGuid,
              '',
            );
            final ready = ExternalPlaybackHost.status.value!;
            for (final phase in [
              ExternalPlaybackPhase.ended,
              ExternalPlaybackPhase.disconnected,
              ExternalPlaybackPhase.preparing,
            ]) {
              ExternalPlaybackHost.status.value = ready.withPhase(phase);
              expect(
                host.positionForLaunch(itemGuid: 'shared-id'),
                isNull,
                reason: '$phase is display-only history',
              );
            }
            ExternalPlaybackHost.status.value = ready;
            nas.account = 'B';
            session.account = 'B';
            expect(host.positionForLaunch(itemGuid: 'shared-id'), isNull);
            nas.account = 'A';
            session.account = 'A';
            nas.server = 'https://other.invalid';
            session.server = nas.server;
            expect(host.positionForLaunch(itemGuid: 'shared-id'), isNull);
            nas.server = 'https://synthetic.invalid';
            session.server = nas.server;
            // End A naturally through the public control path, retaining its history.
            sample['alive'] = false;
            expect(
              await ExternalPlaybackHost.setPaused(true, itemGuid: 'shared-id'),
              isFalse,
            );
            expect(
              ExternalPlaybackHost.status.value!.phase,
              ExternalPlaybackPhase.ended,
            );
            expect(
              host.positionForLaunch(itemGuid: 'shared-id'),
              isNull,
              reason: 'Completed episode replays using resolved progress',
            );
            nas.account = 'B';
            session.account = 'B';
            const resolvedBPosition = Duration(seconds: 12);
            expect(
              host.positionForLaunch(itemGuid: 'shared-id') ??
                  resolvedBPosition,
              resolvedBPosition,
            );
            await ExternalPlaybackHost.stop();
            expect(
              host.positionForLaunch(itemGuid: 'shared-id'),
              isNull,
              reason:
                  'Switch to builtin does not inherit historical external status',
            );
          } finally {
            await ExternalPlaybackHost.stop();
          }
        });
        await tester.pumpWidget(const SizedBox.shrink());
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          PotPlayerSession.channel,
          null,
        );
        backend.dispose();
        session.dispose();
        nas.dispose();
        directory.deleteSync(recursive: true);
      },
      skip: !Platform.isWindows,
    );
  }
}
