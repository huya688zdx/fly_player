import 'dart:async';

import 'package:flutter/widgets.dart';

import '../media_backend/media_backend_kind.dart';
import '../media_backend/session/media_backend_connection.dart';
import '../services/media_backend_connection_store.dart';
import '../services/secure_credential_store.dart';
import '../utils/swallowed_error_logger.dart';

class BackendSessionUnavailableException implements Exception {
  const BackendSessionUnavailableException();

  @override
  String toString() =>
      'Backend session credentials are temporarily unavailable';
}

class BackendSessionProvider extends ChangeNotifier
    with WidgetsBindingObserver {
  final bool _observeLifecycle;

  BackendSessionProvider({bool autoLoad = true})
    : _observeLifecycle = autoLoad {
    if (autoLoad) {
      // 仅在真实运行（autoLoad）时挂生命周期观察；单测构造 autoLoad:false 不挂，
      // 避免依赖 WidgetsBinding。回前台时从磁盘重读，使分屏副栏拿到主引擎切换后的
      // 当前后端（store.load 已 prefs.reload，与 NasProvider 跨 isolate 同步一致）。
      WidgetsBinding.instance.addObserver(this);
      unawaited(_loadSafely());
    }
  }

  @override
  void dispose() {
    if (_observeLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadSafely());
    }
  }

  MediaBackendConnectionSnapshot? _snapshot;
  bool _isReady = false;

  bool get isReady => _isReady;
  MediaBackendKind get currentKind =>
      _snapshot?.activeKind ?? MediaBackendKind.feiniu;
  MediaBackendConnection? get currentConnection => _snapshot?.activeConnection;
  bool get isConfigured => currentConnection?.isAuthenticated ?? false;

  Future<void> load() async {
    try {
      final nextSnapshot = await MediaBackendConnectionStore.load();
      _snapshot = nextSnapshot;
      _isReady = true;
      notifyListeners();
    } on SecureCredentialUnavailableException catch (error, stackTrace) {
      await logSwallowedError(
        action: 'load backend session credentials',
        error: error,
        stackTrace: stackTrace,
        source: 'backend_session_provider',
      );
    }
  }

  Future<void> _loadSafely() async {
    try {
      await load();
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'load backend session credentials',
        error: error,
        stackTrace: stackTrace,
        source: 'backend_session_provider',
      );
    }
  }

  /// 等待会话从磁盘就绪后返回；已就绪则立即返回。
  ///
  /// 分屏详情等**副引擎冷启动**时，构造里的 `load()` 可能尚未完成，此时直接读
  /// [MediaBackendProvider] 会暂时默认回飞牛（[currentKind] fallback）→ Emby 条目被按飞牛
  /// 查询报 noData。页面在读后端前先 `await ensureReady()` 即可拿到磁盘上的当前后端。
  Future<void> ensureReady() async {
    if (_isReady) return;
    try {
      await load();
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'load backend session credentials',
        error: error,
        stackTrace: stackTrace,
        source: 'backend_session_provider',
      );
      throw const BackendSessionUnavailableException();
    }
    if (!_isReady) {
      throw const BackendSessionUnavailableException();
    }
  }

  Future<void> saveActive(MediaBackendConnection connection) async {
    await MediaBackendConnectionStore.saveActive(connection);
    _snapshot = await MediaBackendConnectionStore.load();
    _isReady = true;
    notifyListeners();
  }

  Future<void> saveConnection(MediaBackendConnection connection) async {
    await MediaBackendConnectionStore.saveConnection(connection);
    _snapshot = await MediaBackendConnectionStore.load();
    _isReady = true;
    notifyListeners();
  }
}
