import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/emby/emby_media_backend.dart';
import 'package:fly_player/media_backend/feiniu/feiniu_media_backend.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/media_backend/session/media_backend_connection.dart';
import 'package:fly_player/providers/backend_session_provider.dart';
import 'package:fly_player/providers/media_backend_provider.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  testWidgets(
    'MediaBackendProvider exposes Feiniu backend for current NAS session',
    (tester) async {
      final nasProvider = NasProvider();
      await tester.pump();

      final provider = MediaBackendProvider(nasProvider);

      addTearDown(provider.dispose);
      addTearDown(nasProvider.dispose);

      final backend = provider.backend;

      expect(provider.nasProvider, same(nasProvider));
      expect(backend, isA<FeiniuMediaBackend>());
      expect(backend.capabilities.kind, MediaBackendKind.feiniu);
    },
  );

  testWidgets('reuses one backend instance within the same NAS session', (
    tester,
  ) async {
    final nasProvider = NasProvider();
    await nasProvider.updateSettings(
      baseUrl: 'http://nas-a',
      userName: 'u',
      password: 'p',
    );
    await tester.pump();

    final provider = MediaBackendProvider(nasProvider);
    addTearDown(provider.dispose);
    addTearDown(nasProvider.dispose);

    expect(provider.backend, same(provider.backend));
  });

  testWidgets('rebuilds backend when the NAS base url changes', (tester) async {
    final nasProvider = NasProvider();
    await nasProvider.updateSettings(
      baseUrl: 'http://nas-a',
      userName: 'u',
      password: 'p',
    );
    await tester.pump();

    final provider = MediaBackendProvider(nasProvider);
    addTearDown(provider.dispose);
    addTearDown(nasProvider.dispose);

    final first = provider.backend;

    await nasProvider.updateSettings(
      baseUrl: 'http://nas-b',
      userName: 'u',
      password: 'p',
    );
    await tester.pump();

    expect(provider.backend, isNot(same(first)));
  });

  testWidgets('routes to Emby backend when session kind is emby + authed', (
    tester,
  ) async {
    // 先把会话切到 emby（在创建 NasProvider 之前，避免 NasProvider 异步初始化与
    // saveActive 抢 SharedPreferences 实例）。
    final session = BackendSessionProvider(autoLoad: false);
    await session.saveActive(
      const MediaBackendConnection(
        kind: MediaBackendKind.emby,
        serverUrl: 'https://emby.example.test',
        userId: 'user-1',
        accessToken: 'tok',
      ),
    );
    expect(
      session.currentKind,
      MediaBackendKind.emby,
      reason: 'session 应切到 emby',
    );
    expect(session.currentConnection?.isAuthenticated, isTrue);

    final nasProvider = NasProvider();
    await tester.pump();

    final provider = MediaBackendProvider(nasProvider, session);
    addTearDown(provider.dispose);
    addTearDown(nasProvider.dispose);
    addTearDown(session.dispose);

    final backend = provider.backend;
    expect(backend, isA<EmbyMediaBackend>());
    expect(backend.capabilities.kind, MediaBackendKind.emby);
    expect(provider.backend, same(backend), reason: '同会话复用同实例');
  });

  testWidgets('falls back to Feiniu when emby session not authenticated', (
    tester,
  ) async {
    final session = BackendSessionProvider(autoLoad: false);
    await session.saveActive(
      const MediaBackendConnection(
        kind: MediaBackendKind.emby,
        serverUrl: 'https://emby.example.test',
        // accessToken 为空 → isAuthenticated 为 false → 回退飞牛
      ),
    );

    final nasProvider = NasProvider();
    await tester.pump();

    final provider = MediaBackendProvider(nasProvider, session);
    addTearDown(provider.dispose);
    addTearDown(nasProvider.dispose);
    addTearDown(session.dispose);

    expect(provider.backend, isA<FeiniuMediaBackend>());
  });
}
