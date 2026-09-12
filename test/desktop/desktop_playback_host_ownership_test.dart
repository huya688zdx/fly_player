import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/playback/desktop_playback_host.dart';
import 'package:fly_player/desktop/playback/desktop_playback_session.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/media_backend/detail/media_episode_summary.dart';
import 'package:fly_player/media_backend/media_backend.dart';
import 'package:fly_player/media_backend/media_backend_capabilities.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/playback/playback_source.dart';
import 'package:fly_player/providers/media_backend_provider.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/services/playback_progress_offline_queue.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Test-only platform boundary for suspending the real client-id persistence.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

// These exercise the actual public Host and Navigator, with a controllable
// backend and inert sessions. Routes are removed before rendering a video page;
// decoder/video resources and Screen lifecycle are not simulated here.
void main() {
  for (final boundary in ['flush', 'clientId']) {
    for (final replacement in ['account', 'sameLink', 'unchanged']) {
      testWidgets('release rechecks $replacement after $boundary wait', (
        tester,
      ) async {
        final fixture = await _Fixture.mount(tester);
        fixture.backend.legacy = true;
        final released = <String>[];
        var beforeCleanup = <String>[];
        await tester.runAsync(
          () => HttpOverrides.runWithHttpOverrides(() async {
            final server = await HttpServer.bind(
              InternetAddress.loopbackIPv4,
              0,
            );
            fixture.nas.server = 'http://127.0.0.1:${server.port}';
            fixture.nas.configured = true;
            final entered = Completer<void>();
            final proceed = Completer<void>();
            server.listen((request) async {
              final body =
                  jsonDecode(await utf8.decoder.bind(request).join()) as Map;
              if (body['req'] == 'media.quit') {
                released.add(body['playLink'] as String);
              } else if (boundary == 'flush') {
                if (!entered.isCompleted) entered.complete();
                await proceed.future;
              }
              request.response.headers.contentType = ContentType.json;
              request.response.write(
                jsonEncode({
                  'code': 0,
                  'data': {'result': 'succ'},
                }),
              );
              await request.response.close();
            });
            try {
              expect(
                await fixture.host.launch(
                  source: _source('A').copyWith(playLink: 'shared-link'),
                  episodes: [
                    {'itemGuid': 'A'},
                  ],
                ),
                isTrue,
              );
              if (boundary == 'flush') {
                await PlaybackProgressOfflineQueue.enqueue({
                  'itemGuid': 'synthetic-item',
                  'mediaGuid': 'synthetic-media',
                  'ts': 20,
                  'duration': 100,
                });
              } else {
                SharedPreferencesStorePlatform.instance = _BlockedClientIdStore(
                  entered,
                  proceed,
                );
              }
              final release = fixture.sessions.single.dispose();
              await entered.future.timeout(const Duration(seconds: 4));
              Future<bool>? replacementLaunch;
              if (replacement == 'account') {
                fixture.nas.sessionUser = 'account-B';
              } else if (replacement == 'sameLink') {
                replacementLaunch = fixture.host.launch(
                  source: _source('B').copyWith(playLink: 'shared-link'),
                  episodes: [
                    {'itemGuid': 'B'},
                  ],
                );
              }
              proceed.complete();
              await release.timeout(const Duration(seconds: 4));
              if (replacementLaunch != null) {
                expect(
                  await replacementLaunch.timeout(const Duration(seconds: 4)),
                  isTrue,
                );
              }
              beforeCleanup = List.of(released);
            } finally {
              if (!proceed.isCompleted) proceed.complete();
              for (final session in fixture.sessions) {
                await session.dispose();
              }
              await server.close(force: true);
            }
          }, _DirectHttpOverrides()),
        );
        await fixture.close(tester);
        expect(
          beforeCleanup,
          replacement == 'unchanged' ? ['shared-link'] : isEmpty,
        );
        expect(released, replacement == 'account' ? isEmpty : ['shared-link']);
      });
    }
  }
  for (final scenario in [
    'metadata',
    'preframe',
    'sameLink',
    'scope',
    'unmounted',
  ]) {
    testWidgets(
      'accepted source is released once after $scenario cancellation',
      (tester) async {
        final fixture = await _Fixture.mount(tester);
        fixture.backend.legacy = true;
        final released = <String>[];
        var beforeCleanup = <String>[];
        bool? firstResult;
        bool? secondResult;
        await tester.runAsync(
          () => HttpOverrides.runWithHttpOverrides(() async {
            final server = await HttpServer.bind(
              InternetAddress.loopbackIPv4,
              0,
            );
            fixture.nas.server = 'http://127.0.0.1:${server.port}';
            fixture.nas.configured = true;
            final entered = Completer<void>();
            final releaseMetadata = Completer<void>();
            server.listen((request) async {
              if (request.method == 'GET') {
                if (!entered.isCompleted) entered.complete();
                await releaseMetadata.future;
                request.response.statusCode = 500;
              } else {
                final body =
                    jsonDecode(await utf8.decoder.bind(request).join()) as Map;
                if (body['req'] == 'media.quit') {
                  released.add(body['playLink'] as String);
                }
              }
              request.response.headers.contentType = ContentType.json;
              request.response.write(
                jsonEncode({
                  'code': 0,
                  'data': {'result': 'succ'},
                }),
              );
              await request.response.close();
            });
            try {
              final first = fixture.host.launch(
                source: _source('A').copyWith(playLink: 'link-A'),
                episodes: scenario == 'preframe'
                    ? [
                        {'itemGuid': 'A'},
                      ]
                    : null,
              );
              if (scenario == 'preframe') {
                firstResult = await first.timeout(const Duration(seconds: 4));
              } else {
                await entered.future.timeout(const Duration(seconds: 4));
              }
              if (scenario == 'unmounted') {
                await tester.pumpWidget(const SizedBox());
              } else if (scenario == 'scope') {
                fixture.nas.sessionUser = 'changed-account';
              } else {
                secondResult = await fixture.host
                    .launch(
                      source: _source('B').copyWith(
                        playLink: scenario == 'sameLink' ? 'link-A' : 'link-B',
                      ),
                      episodes: [
                        {'itemGuid': 'B'},
                      ],
                    )
                    .timeout(const Duration(seconds: 4));
              }
              if (!releaseMetadata.isCompleted) releaseMetadata.complete();
              firstResult ??= await first.timeout(const Duration(seconds: 4));
              beforeCleanup = List.of(released);
            } finally {
              if (!releaseMetadata.isCompleted) releaseMetadata.complete();
              for (final session in fixture.sessions) {
                await session.dispose();
              }
              await server.close(force: true);
            }
          }, _DirectHttpOverrides()),
        );
        await fixture.close(tester);
        expect(firstResult, scenario == 'preframe');
        if (scenario != 'scope' && scenario != 'unmounted') {
          expect(secondResult, isTrue);
        }
        expect(beforeCleanup, switch (scenario) {
          'metadata' || 'preframe' || 'unmounted' => ['link-A'],
          _ => isEmpty,
        });
        expect(released, switch (scenario) {
          'metadata' || 'preframe' => ['link-A', 'link-B'],
          'sameLink' || 'unmounted' => ['link-A'],
          _ => isEmpty,
        });
      },
    );
  }
  for (final firstCompletesFirst in [false, true]) {
    testWidgets(
      'latest launch wins when first completes $firstCompletesFirst',
      (tester) async {
        final fixture = await _Fixture.mount(tester);
        addTearDown(() => fixture.close(tester));
        {
          final first = fixture.host.launch(source: _source('A'));
          await tester.idle();
          expect(fixture.backend.pending.containsKey('A'), isTrue);
          final second = fixture.host.launch(source: _source('B'));
          await tester.idle();
          expect(fixture.backend.pending.containsKey('B'), isTrue);
          if (firstCompletesFirst) {
            fixture.backend.complete('A');
            await tester.idle();
            expect(await first, isFalse);
            fixture.backend.complete('B');
            await tester.idle();
            expect(await second, isTrue);
          } else {
            fixture.backend.complete('B');
            await tester.idle();
            expect(await second.timeout(const Duration(seconds: 3)), isTrue);
            fixture.backend.complete('A');
            await tester.idle();
            expect(await first.timeout(const Duration(seconds: 3)), isFalse);
          }
          expect(fixture.sessions.map((session) => session.source.itemGuid), [
            'B',
          ]);
          expect(fixture.observer.routes, hasLength(1));
          expect(fixture.sessions.single.disposed, isFalse);
        }
      },
    );
  }

  testWidgets('unmounted request creates no session after metadata returns', (
    tester,
  ) async {
    final fixture = await _Fixture.mount(tester);
    late Future<bool> launch;
    launch = fixture.host.launch(source: _source('A'));
    await tester.idle();
    await tester.pumpWidget(const SizedBox());
    fixture.backend.complete('A');
    await tester.idle();
    expect(await launch, isFalse);
    expect(fixture.sessions, isEmpty);
    await fixture.close(tester);
  });

  testWidgets('only the latest request continues after loading settings', (
    tester,
  ) async {
    final fixture = await _Fixture.mount(tester);
    addTearDown(() => fixture.close(tester));
    final first = fixture.host.launch(source: _source('A'));
    final second = fixture.host.launch(source: _source('B'));
    await tester.idle();
    expect(await first, isFalse);
    expect(fixture.backend.pending.keys, ['B']);
    fixture.backend.complete('B');
    await tester.idle();
    expect(await second, isTrue);
    expect(fixture.sessions, hasLength(1));
  });

  testWidgets('account scope change invalidates pending metadata', (
    tester,
  ) async {
    final fixture = await _Fixture.mount(tester);
    addTearDown(() => fixture.close(tester));
    final first = fixture.host.launch(source: _source('A'));
    await tester.idle();
    fixture.nas.sessionUser = 'account-B';
    fixture.backend.complete('A');
    await tester.idle();
    expect(await first, isFalse);
    expect(fixture.sessions, isEmpty);
    final second = fixture.host.launch(source: _source('B'), offline: true);
    await tester.idle();
    expect(await second, isTrue);
  });

  testWidgets(
    'retained session resumes repeatedly without a second allocation',
    (tester) async {
      final fixture = await _Fixture.mount(tester);
      addTearDown(() => fixture.close(tester));
      final launch = fixture.host.launch(source: _source('A'), offline: true);
      await tester.idle();
      expect(await launch, isTrue);
      final session = fixture.sessions.single;
      for (var index = 0; index < 3; index++) {
        await fixture.returnFromVideo(tester, session);
        expect(session.retainedByHost, isTrue);
        final resume = fixture.host.resume(itemGuid: 'A');
        await tester.idle();
        expect(await resume, isTrue);
        expect(session.active, isTrue);
        expect(fixture.sessions, hasLength(1));
        expect(session.disposeCount, 0);
      }
    },
  );

  for (final waitAtSeek in [false, true]) {
    testWidgets(
      'new launch supersedes resume waiting for ${waitAtSeek ? 'seek' : 'pause'}',
      (tester) async {
        final fixture = await _Fixture.mount(tester);
        addTearDown(() => fixture.close(tester));
        final launch = fixture.host.launch(source: _source('A'), offline: true);
        await tester.idle();
        expect(await launch, isTrue);
        final session = fixture.sessions.single;
        await fixture.returnFromVideo(tester, session);
        final pending = Completer<void>();
        if (waitAtSeek) {
          session.platformPlayer.seekPending = pending;
        } else {
          session.paused = pending.future;
        }
        final resume = fixture.host.resume(
          itemGuid: 'A',
          position: const Duration(seconds: 12),
        );
        await tester.idle();
        final replacement = fixture.host.launch(
          source: _source('B'),
          offline: true,
        );
        await tester.idle();
        pending.complete();
        await tester.idle();
        expect(await resume, isFalse);
        expect(await replacement, isTrue);
        expect(session.disposeCount, 1);
        expect(session.retainedByHost, isFalse);
        expect(
          session.platformPlayer.seeks,
          waitAtSeek ? [const Duration(seconds: 12)] : isEmpty,
        );
        expect(fixture.sessions.last.source.itemGuid, 'B');
        expect(fixture.sessions.last.retainedByHost, isTrue);
        expect(fixture.observer.routes, hasLength(1));
      },
    );
  }

  testWidgets('old route cleanup cannot clear a newer session slot', (
    tester,
  ) async {
    final fixture = await _Fixture.mount(tester);
    addTearDown(() => fixture.close(tester));
    final first = fixture.host.launch(source: _source('A'), offline: true);
    await tester.idle();
    expect(await first, isTrue);
    final old = fixture.sessions.single;
    final pausePending = Completer<void>();
    old.paused = pausePending.future;
    final second = fixture.host.launch(source: _source('B'), offline: true);
    await tester.idle(); // B is waiting for A's removed route to finish.
    final third = fixture.host.launch(source: _source('C'), offline: true);
    await tester.idle();
    expect(await third, isTrue);
    final current = fixture.sessions.last;
    expect(current.source.itemGuid, 'C');
    pausePending.complete();
    await tester.idle();
    await fixture.returnFromVideo(tester, current);
    expect(await second, isFalse);
    expect(old.disposeCount, 1);
    expect(current.retainedByHost, isTrue);
    expect(current.disposeCount, 0);
    final resume = fixture.host.resume(itemGuid: 'C');
    await tester.idle();
    expect(await resume, isTrue);
    expect(fixture.sessions.map((session) => session.source.itemGuid), [
      'A',
      'C',
    ]);
  });
}

MpvMediaSource _source(String id) => MpvMediaSource(
  itemGuid: id,
  mediaGuid: '$id-media',
  videoGuid: '$id-video',
  seasonGuid: id,
  mediaType: 'episode',
  url: 'https://media.invalid/$id',
  headers: const {},
  title: id,
  externalLocalSource: true,
  danmakuAutoSearchAllowed: false,
);

class _Fixture {
  final nas = _Nas();
  final backend = _Backend();
  late final _BackendProvider provider = _BackendProvider(nas, backend);
  final observer = _Observer();
  final sessions = <_Session>[];
  late DesktopPlaybackHost host;

  static Future<_Fixture> mount(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final fixture = _Fixture();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<NasProvider>.value(value: fixture.nas),
          ChangeNotifierProvider<MediaBackendProvider>.value(
            value: fixture.provider,
          ),
        ],
        child: MaterialApp(
          navigatorObservers: [fixture.observer],
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              fixture.host = DesktopPlaybackHost(
                context,
                createSession: (source, {danmakuFilePath}) {
                  final session = _Session(source);
                  fixture.sessions.add(session);
                  return session;
                },
              );
              return const Scaffold();
            },
          ),
        ),
      ),
    );
    await tester.idle();
    return fixture;
  }

  Future<void> close(WidgetTester tester) async {
    for (final route in observer.routes.toList()) {
      if (route.isActive) route.navigator!.removeRoute(route);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    final disposing = [for (final session in sessions) session.dispose()];
    await tester.idle();
    await Future.wait(disposing);
    provider.dispose();
    nas.dispose();
  }

  Future<void> returnFromVideo(WidgetTester tester, _Session session) async {
    session.active = false;
    session.ready = true;
    final route = observer.routes.last;
    route.navigator!.removeRoute(route);
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.idle();
  }
}

class _Observer extends NavigatorObserver {
  final routes = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) routes.add(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.remove(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.remove(route);
}

class _BackendProvider extends MediaBackendProvider {
  _BackendProvider(super.nasProvider, this.value);
  final MediaBackend value;
  @override
  MediaBackend get backend => value;
}

class _Backend implements MediaBackend {
  bool legacy = false;
  final pending = <String, Completer<List<MediaEpisodeSummary>>>{};
  @override
  MediaBackendCapabilities get capabilities => legacy
      ? const MediaBackendCapabilities.feiniu()
      : const MediaBackendCapabilities.server(kind: MediaBackendKind.emby);
  @override
  Future<List<MediaEpisodeSummary>> getSeasonEpisodes(String seasonId) =>
      (pending[seasonId] = Completer()).future;
  void complete(String id) => pending[id]!.complete([]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Session implements DesktopPlaybackSession {
  _Session(this.source);
  final platformPlayer = _Player();
  @override
  late final player = Player(platformPlayer: platformPlayer);
  @override
  MpvMediaSource source;
  @override
  String? danmakuFilePath;
  @override
  bool ready = false;
  @override
  bool active = true;
  @override
  bool disposed = false;
  @override
  bool retainedByHost = false;
  @override
  Future<void> paused = Future.value();
  @override
  FutureOr<void> Function(MpvMediaSource)? releaseSource;
  @override
  Future<void> Function()? disposeResources;
  int disposeCount = 0;
  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    disposeCount++;
    await paused;
    await releaseSource?.call(source);
    await disposeResources?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Nas extends NasProvider {
  String sessionUser = 'account-A';
  String server = 'https://media.invalid';
  bool configured = false;
  @override
  String get baseUrl => server;
  @override
  String get token => 'synthetic-test-token';
  @override
  bool get isConfigured => configured;
  @override
  String get userName => sessionUser;
}

class _Player extends PlatformPlayer {
  _Player() : super(configuration: const PlayerConfiguration());
  final seeks = <Duration>[];
  Completer<void>? seekPending;
  @override
  Future<void> seek(Duration duration) async {
    seeks.add(duration);
    await seekPending?.future;
  }
}

class _DirectHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}

class _BlockedClientIdStore extends InMemorySharedPreferencesStore {
  _BlockedClientIdStore(this.entered, this.proceed) : super.withData({});
  final Completer<void> entered;
  final Completer<void> proceed;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.playback_client_id') {
      if (!entered.isCompleted) entered.complete();
      await proceed.future;
    }
    return super.setValue(valueType, key, value);
  }
}
