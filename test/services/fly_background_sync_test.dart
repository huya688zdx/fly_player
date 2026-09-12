import 'package:fake_async/fake_async.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/providers/backend_session_provider.dart';
import 'package:fly_player/services/fly_data/fly_account_controller.dart';
import 'package:fly_player/services/fly_data/fly_data_service.dart';
import 'package:fly_player/services/play_stats/play_stats_database.dart';
import 'package:fly_player/services/secure_credential_store.dart';

class _Service extends FlyDataService {
  _Service()
    : super(database: SqflitePlayStatsDatabase(), drainWrites: () async {}) {
    session = FlyDataSession(
      serverUrl: 'https://test.example',
      userId: 'alice',
      username: 'alice',
      deviceId: 'd',
      deviceName: 'd',
      token: 't',
      installationId: 'i',
      serviceInstanceId: 'instance',
    );
  }
  int attempts = 0;
  @override
  Future<void> switchAddress(String value) async {}
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    bool patch = false,
  }) async => {
    'items': path == '/bindings'
        ? [
            {'id': 'binding', 'status': 'active', 'revision': 1},
          ]
        : [],
  };
  @override
  Future<Map<String, dynamic>> syncNow() async {
    attempts++;
    if (attempts == 1) throw StateError('offline');
    return {'status': 'applied'};
  }
}

class _CancelService extends _Service {
  final entered = Completer<void>(), release = Completer<void>();
  final stored = <String>[];
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    bool patch = false,
  }) async => {
    'items': path == '/bindings'
        ? [
            for (final id in ['a', 'b'])
              {'id': id, 'revision': 1, 'status': 'active'},
          ]
        : [],
  };
  @override
  Future<void> syncStoredBinding(String bindingId) async {
    stored.add(bindingId);
    if (!entered.isCompleted) entered.complete();
    await release.future;
  }

  @override
  Future<void> logout() async {
    session = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'logout request cancels later scope uploads while an earlier receipt is in flight',
    () async {
      SharedPreferences.setMockInitialValues({
        'fly.used_bindings.instance|alice': ['a', 'b'],
        'fly.used_bindings.instance|other': ['foreign'],
      });
      SecureCredentialStore.setBackendForTesting(
        MemorySecureCredentialBackend(),
      );
      final nas = NasProvider(),
          backend = BackendSessionProvider(autoLoad: false);
      await nas.reloadSettingsForTesting();
      final service = _CancelService();
      final account = FlyAccountController(
        nas: nas,
        backendSession: backend,
        service: service,
        autoLoad: false,
      );
      try {
        final sync = account.backgroundRefresh();
        await service.entered.future;
        final logout = account.logout();
        service.release.complete();
        await sync;
        await logout;
        expect(service.stored, ['a']);
        expect(account.session, isNull);
      } finally {
        account.dispose();
        nas.dispose();
        backend.dispose();
      }
    },
  );
  test(
    'playback end during backoff neither drops pending retry nor hammers offline service',
    () async {
      SharedPreferences.setMockInitialValues({});
      SecureCredentialStore.setBackendForTesting(
        MemorySecureCredentialBackend(),
      );
      final nas = NasProvider(),
          backend = BackendSessionProvider(autoLoad: false);
      await nas.reloadSettingsForTesting();
      fakeAsync((async) {
        final service = _Service();
        final account = FlyAccountController(
          nas: nas,
          backendSession: backend,
          service: service,
          autoLoad: false,
          now: async.getClock(DateTime(2026)).now,
        )..activeBindingId = 'binding';
        account.backgroundRefresh();
        async.flushMicrotasks();
        expect(service.attempts, 1);
        async.elapse(const Duration(seconds: 5));
        account.scheduleSync();
        async.elapse(const Duration(seconds: 54));
        async.flushMicrotasks();
        expect(service.attempts, 1);
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(service.attempts, 2);
        account.dispose();
      });
      nas.dispose();
      backend.dispose();
    },
  );
}
