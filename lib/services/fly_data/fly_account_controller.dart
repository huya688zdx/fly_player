import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../media_backend/session/media_backend_connection.dart';
import '../../providers/backend_session_provider.dart';
import '../../providers/nas_provider.dart';
import '../media_backend_connection_store.dart';
import '../play_stats/play_stats_service.dart';
import 'fly_data_service.dart';
import 'fly_media_identity.dart';
import 'fly_data_sync_store.dart';

/// Account, binding and address operations are serialized. Playback uses only
/// cached media access and never waits for this controller's network refresh.
class FlyAccountController extends ChangeNotifier with WidgetsBindingObserver {
  FlyAccountController({
    required this.nas,
    required this.backendSession,
    FlyDataService? service,
    bool autoLoad = true,
    DateTime Function()? now,
  }) : service = service ?? FlyDataService.instance,
       now = now ?? DateTime.now {
    if (autoLoad) {
      WidgetsBinding.instance.addObserver(this);
      PlayStatsService.instance.onSessionFinished = scheduleSync;
      unawaited(restore());
    }
  }
  final NasProvider nas;
  final BackendSessionProvider backendSession;
  final FlyDataService service;
  final DateTime Function() now;
  bool ready = false, busy = false, legacyMode = false;
  String? message;
  String activeBindingId = '';
  List<Map<String, dynamic>> bindings = [];
  List<Map<String, dynamic>> servers = [];
  bool _disposed = false;
  Future<void>? _tail;
  Timer? _retry;
  DateTime? _notBefore;
  int _failures = 0;
  int _syncEpoch = 0;
  FlyDataSession? get session => service.session;
  String get accountKey => session?.accountKey ?? '';
  Map<String, dynamic>? get activeBinding {
    for (final binding in bindings) {
      if (binding['id'] == activeBindingId) return binding;
    }
    return null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<T> _run<T>(Future<T> Function() action) {
    final result = (_tail ?? Future<void>.value()).then((_) async {
      if (_disposed) throw StateError('页面已关闭。');
      busy = true;
      message = null;
      _notify();
      try {
        return await action();
      } catch (error) {
        message = safeMessage(error);
        rethrow;
      } finally {
        busy = false;
        _notify();
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> restore() async {
    try {
      await _run(() async {
        await service.restoreSession();
        if (session == null) return;
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        final cache = prefs.getString('fly.bindings.$accountKey');
        if (cache != null) {
          bindings = (jsonDecode(cache) as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
        final selectedId = prefs.getString('fly.active.$accountKey') ?? '';
        activeBindingId = '';
        // Recover only this account's selected access; another saved account
        // cannot become the active media backend during a delayed restore.
        final snapshot = await MediaBackendConnectionStore.load();
        for (final connection in snapshot.connections) {
          if (connection.accountKey == accountKey &&
              connection.bindingId == selectedId &&
              connection.isAuthenticated &&
              bindings.any(
                (b) =>
                    b['id'] == selectedId &&
                    ['active', 'offline'].contains(b['status']) &&
                    b['revision'] == connection.bindingRevision,
              )) {
            await _applyConnection(connection);
            activeBindingId = selectedId;
            break;
          }
        }
        if (activeBindingId.isEmpty) await _clearActiveAccess();
      });
    } catch (_) {
      /* message is already retained, no credentials in errors */
    } finally {
      ready = true;
      _notify();
    }
    unawaited(backgroundRefresh());
  }

  Future<void> login({
    required String url,
    required String username,
    required String password,
    required String deviceName,
  }) {
    _syncEpoch++;
    return _run(() async {
      await PlayStatsService.instance.drainForManualSync();
      await service.login(
        serverUrl: url,
        username: username,
        password: password,
        deviceName: deviceName,
      );
      legacyMode = false;
      activeBindingId = '';
      bindings = [];
      servers = [];
      await _clearActiveAccess();
      await _refresh();
    });
  }

  Future<void> logout() {
    _syncEpoch++;
    return _run(() async {
      _retry?.cancel();
      await PlayStatsService.instance.drainForManualSync();
      try {
        await service.logout();
      } finally {
        bindings = [];
        servers = [];
        activeBindingId = '';
        legacyMode = false;
        await _clearActiveAccess();
      }
    });
  }

  Future<void> enterLegacyMode() {
    _syncEpoch++;
    return _run(() async {
      _retry?.cancel();
      if (backendSession.currentConnection?.bindingId.isNotEmpty == true ||
          (await SharedPreferences.getInstance()).containsKey(
            'fly.nas_compat_binding',
          )) {
        await _clearActiveAccess();
      }
      await PlayStatsService.instance.bindOwnerScope('');
      legacyMode = true;
      _notify();
    });
  }

  Future<void> refresh() => _run(_refresh);
  Future<void> _refresh() async {
    if (session == null) return;
    await service.switchAddress(session!.serverUrl);
    final response = await service.request('/bindings');
    final next = (response['items'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    for (final binding in next) {
      final active = backendSession.currentConnection;
      if (activeBindingId == binding['id'] &&
          active != null &&
          active.bindingRevision != binding['revision']) {
        await MediaBackendConnectionStore.removeBinding(
          accountKey,
          binding['id'] as String,
        );
        await _clearActiveAccess();
      }
      if (binding['status'] == 'unbound' ||
          binding['status'] == 'reauth_required') {
        await MediaBackendConnectionStore.removeBinding(
          accountKey,
          binding['id'] as String,
        );
        if (activeBindingId == binding['id']) {
          await _clearActiveAccess();
        }
      }
    }
    bindings = next;
    servers = ((await service.request('/servers'))['items'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fly.bindings.$accountKey', jsonEncode(bindings));
    await prefs.setString('fly.active.$accountKey', activeBindingId);
  }

  Future<void> switchAddress(String url) => _run(() async {
    await service.switchAddress(url);
    await _refresh();
  });
  Future<void> createServer(Map<String, dynamic> data) => _run(() async {
    await service.request('/servers', body: data);
    await _refresh();
  });
  Future<void> createBinding(Map<String, dynamic> data) => _run(() async {
    await service.request('/bindings', body: data);
    await _refresh();
  });
  Future<void> reauthorize(
    Map<String, dynamic> binding, {
    required String username,
    required String password,
  }) => _run(() async {
    await service.request(
      '/bindings/${binding['id']}/reauthorize',
      body: {
        'expected_revision': binding['revision'],
        'username': username,
        'password': password,
      },
    );
    await _refresh();
  });
  Future<void> unbind(Map<String, dynamic> binding) => _run(() async {
    await service.request(
      '/bindings/${binding['id']}/unbind',
      body: {'expected_revision': binding['revision']},
    );
    await _refresh();
  });
  Future<void> syncCatalog(Map<String, dynamic> binding) => _run(() async {
    await service.request(
      '/bindings/${binding['id']}/sync',
      body: <String, dynamic>{},
    );
    message = '目录同步任务已排队，可稍后刷新查看。';
  });

  Future<void> activate(
    Map<String, dynamic> binding, {
    String? address,
  }) => _run(() async {
    if (!['active', 'offline'].contains(binding['status'])) {
      throw StateError('此绑定需要重新授权。');
    }
    final access = await service.request(
      '/bindings/${binding['id']}/device-access',
      body: {'expected_revision': binding['revision']},
    );
    if (access['binding_id'] != binding['id'] ||
        access['binding_revision'] != binding['revision']) {
      throw StateError('绑定版本已改变，请刷新。');
    }
    final server = Map<String, dynamic>.from(access['server'] as Map);
    final addresses = (server['addresses'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((e) => e['purpose'] != 'nas_api')
        .toList();
    addresses.sort(
      (a, b) => ((a['priority'] as num?)?.toInt() ?? 0).compareTo(
        (b['priority'] as num?)?.toInt() ?? 0,
      ),
    );
    if (addresses.isEmpty) throw StateError('管理员需登记客户端 LAN、HTTPS 或 VPN 媒体地址。');
    final selected = address ?? addresses.first['base_url'] as String;
    if (!addresses.any((e) => e['base_url'] == selected)) {
      throw StateError('媒体地址不在已授权的地址集中。');
    }
    await verifyFlyMediaAddress(
      address: selected,
      kind: server['kind'] as String,
      expectedId: (server['remote_server_id'] ?? '').toString(),
    );
    final connection = MediaBackendConnection.fromJson({
      'kind': server['kind'],
      'serverUrl': selected,
      'displayName': binding['label'],
      'userName': access['remote_username'],
      'userId': access['remote_user_id'],
      'accessToken': access['access_token'],
      'bindingId': binding['id'],
      'bindingRevision': access['binding_revision'],
      'accountKey': accountKey,
      'rememberSecret': false,
    });
    await _applyConnection(connection);
    activeBindingId = binding['id'] as String;
    legacyMode = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fly.active.$accountKey', activeBindingId);
    await prefs.setString('fly.address.$accountKey.$activeBindingId', selected);
    scheduleSync();
  });

  Future<void> _applyConnection(MediaBackendConnection connection) async {
    await PlayStatsService.instance.bindMediaBinding(
      accountKey: connection.accountKey,
      bindingId: connection.bindingId,
      backendKind: connection.kind.name,
    );
    if (connection.kind.name == 'feiniu') {
      // Mark the compatibility copy before writing it, so a crash/restart can
      // still clear it when this binding is invalid or the account changes.
      await (await SharedPreferences.getInstance()).setString(
        'fly.nas_compat_binding',
        connection.storageId,
      );
      await nas.updateSettings(
        baseUrl: connection.serverUrl,
        userName: connection.userName,
        password: '',
        token: connection.accessToken,
        rememberPassword: false,
      );
    } else {
      await _clearNasAccess();
    }
    await backendSession.saveActive(connection);
    final prefs = await SharedPreferences.getInstance();
    final key = 'fly.used_bindings.${connection.accountKey}';
    final used = {...?prefs.getStringList(key), connection.bindingId};
    await prefs.setStringList(key, used.toList());
  }

  Future<void> _clearNasAccess() async {
    await nas.updateSettings(
      baseUrl: '',
      userName: '',
      password: '',
      token: '',
      rememberPassword: false,
    );
    await (await SharedPreferences.getInstance()).remove(
      'fly.nas_compat_binding',
    );
  }

  Future<void> _clearActiveAccess() async {
    activeBindingId = '';
    // Clear the compatibility copy while the old binding still owns its scope;
    // NasProvider then cannot rebind statistics to a legacy media account.
    await _clearNasAccess();
    await PlayStatsService.instance.bindOwnerScope('');
    await backendSession.clearActive();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(backgroundRefresh());
  }

  Future<void> backgroundRefresh() async {
    if (_disposed || session == null || legacyMode) return;
    if (busy || (_notBefore != null && now().isBefore(_notBefore!))) {
      scheduleSync();
      return;
    }
    _notBefore = now().add(const Duration(seconds: 30));
    final epoch = _syncEpoch;
    try {
      await _run(() async {
        await _refresh();
        if (_disposed || legacyMode || epoch != _syncEpoch) return;
        final current = session;
        Object? firstError;
        Future<void> upload(Future<void> Function() send) async {
          try {
            await send();
          } on FlyNoFactsToSync {
            /* An unused binding must not block other facts. */
          } catch (error) {
            firstError ??= error;
          }
        }

        if (activeBindingId.isNotEmpty) {
          await upload(() async {
            await service.syncNow();
          });
        }
        final used =
            (await SharedPreferences.getInstance()).getStringList(
              'fly.used_bindings.$accountKey',
            ) ??
            [];
        for (final bindingId in used) {
          if (_disposed ||
              legacyMode ||
              epoch != _syncEpoch ||
              !identical(current, session)) {
            return;
          }
          if (bindingId == activeBindingId) continue;
          // A retained unbound binding can still own facts captured offline;
          // uploading those facts never requests new media access.
          if (!bindings.any((b) => b['id'] == bindingId)) continue;
          await upload(() => service.syncStoredBinding(bindingId));
        }
        if (firstError != null) throw firstError!;
      });
      _failures = 0;
    } catch (error) {
      message = safeMessage(error);
      _notify();
      _failures = (_failures + 1).clamp(1, 5);
      _notBefore = now().add(Duration(seconds: 30 * (1 << _failures)));
      scheduleSync();
    }
  }

  void scheduleSync() {
    if (_disposed || session == null || legacyMode) return;
    _retry?.cancel();
    final remaining = _notBefore?.difference(now()) ?? Duration.zero;
    _retry = Timer(
      remaining > const Duration(seconds: 2)
          ? remaining
          : const Duration(seconds: 2),
      () => unawaited(backgroundRefresh()),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    PlayStatsService.instance.onSessionFinished = null;
    super.dispose();
  }

  static String safeMessage(Object error) => error is StateError
      ? error.message.toString()
      : error is FormatException
      ? error.message
      : '连接未完成，本地记录已保留。请核对服务地址或稍后重试。';
}
