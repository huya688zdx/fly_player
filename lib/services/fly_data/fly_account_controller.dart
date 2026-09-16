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
import 'fly_media_address_selector.dart';
import 'fly_data_sync_store.dart';

/// Account, binding and address operations are serialized. Playback uses only
/// cached media access and never waits for this controller's network refresh.
class FlyAccountController extends ChangeNotifier with WidgetsBindingObserver {
  static const _loginModeKey = 'fly.login_mode';

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
  bool _disposed = false;
  Future<void>? _tail;
  Timer? _retry;
  DateTime? _notBefore;
  int _failures = 0;
  int _syncEpoch = 0;
  int get accountEpoch => _syncEpoch;
  FlyDataSession? get session => service.session;
  String get accountKey => session?.accountKey ?? '';
  bool isCurrentFlyAccount(String key, int epoch) =>
      !_disposed &&
      !legacyMode &&
      key.isNotEmpty &&
      accountKey == key &&
      accountEpoch == epoch;
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
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        legacyMode = prefs.getString(_loginModeKey) == 'media';
        if (legacyMode) {
          activeBindingId = '';
          // The local gate must not wait for a separate Fly credential read.
          _notify();
        }
        await service.restoreSession();
        if (session == null) return;
        final cache = prefs.getString('fly.bindings.$accountKey');
        if (cache != null) {
          bindings = (jsonDecode(cache) as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
        // Retain the account/list for an explicit return to Fly, but leave
        // the direct connection and its statistics under the local providers.
        if (legacyMode) return;
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
    bool rememberPassword = true,
    String? expectedInstanceId,
    String fnEntryToken = '',
  }) {
    _syncEpoch++;
    return _run(() async {
      await PlayStatsService.instance.drainForManualSync();
      await service.login(
        serverUrl: url,
        username: username,
        password: password,
        deviceName: deviceName,
        rememberPassword: rememberPassword,
        expectedInstanceId: expectedInstanceId,
        fnEntryToken: fnEntryToken,
      );
      await _rememberLoginMode('fly');
      legacyMode = false;
      activeBindingId = '';
      bindings = [];
      await _clearActiveAccess();
      await _refresh();
      message = service.loginHistoryWarning;
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
        activeBindingId = '';
        legacyMode = false;
        try {
          await _rememberLoginMode('fly');
        } finally {
          await _clearActiveAccess();
        }
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
      await _rememberLoginMode('media');
      legacyMode = true;
      _notify();
    });
  }

  Future<void> returnToFlyMode() {
    _syncEpoch++;
    return _run(() async {
      if (legacyMode) {
        _retry?.cancel();
        // A local media connection must not become a selected Fly binding or
        // claim its statistics. Keep saved access; source selection owns reuse.
        await PlayStatsService.instance.bindOwnerScope('');
        activeBindingId = '';
      }
      await _rememberLoginMode('fly');
      legacyMode = false;
    });
  }

  Future<void> _rememberLoginMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_loginModeKey, mode)) {
      throw StateError('无法保存登录方式，请重试。');
    }
  }

  Future<void> refresh() => _run(_refresh);
  Future<void> renewFnAccess(String entryToken) {
    final current = session, epoch = accountEpoch;
    return _run(() async {
      if (current == null ||
          !identical(current, session) ||
          epoch != accountEpoch ||
          legacyMode) {
        throw StateError('账号或服务地址已改变，请重新授权 FN 访问。');
      }
      await service.renewFnAccess(entryToken);
      await _refresh();
    });
  }

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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fly.bindings.$accountKey', jsonEncode(bindings));
    await prefs.setString('fly.active.$accountKey', activeBindingId);
  }

  Future<void> switchAddress(String url) => _run(() async {
    await service.switchAddress(url);
    await _refresh();
    message = service.loginHistoryWarning;
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
        .toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    // Preferences only order freshly authorized addresses. A removed endpoint
    // must never regain access just because it worked on a previous network.
    final selected = await selectFlyMediaAddress(
      addresses: addresses,
      kind: server['kind'] as String,
      expectedId: (server['remote_server_id'] ?? '').toString(),
      preferredAddress: prefs.getString(
        'fly.address.$accountKey.${binding['id']}',
      ),
      explicitAddress: address,
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
    await prefs.setString('fly.active.$accountKey', activeBindingId);
    await prefs.setString('fly.address.$accountKey.$activeBindingId', selected);
    await _rememberLoginMode('fly');
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
