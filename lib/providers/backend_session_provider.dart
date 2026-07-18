import 'dart:async';

import 'package:flutter/widgets.dart';

import '../media_backend/media_backend_kind.dart';
import '../media_backend/session/media_backend_connection.dart';
import '../services/media_backend_connection_store.dart';
import '../services/secure_credential_store.dart';
import '../utils/swallowed_error_logger.dart';

class BackendSessionUnavailableException implements Exception {
  final Object? cause;
  final StackTrace? stackTrace;

  const BackendSessionUnavailableException({this.cause, this.stackTrace});

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
    _disposed = true;
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
  Object? _lastLoadFailure;
  StackTrace? _lastLoadFailureStackTrace;
  Future<void>? _loadInFlight;
  int? _loadInFlightBarrier;
  int _mutationBarrier = 0;
  Future<void> _operationTail = Future<void>.value();
  bool _disposed = false;

  bool get isReady => _isReady;
  bool get hasLoadFailure => _lastLoadFailure != null;
  MediaBackendKind get currentKind =>
      _snapshot?.activeKind ?? MediaBackendKind.feiniu;
  MediaBackendConnection? get currentConnection => _snapshot?.activeConnection;
  bool get isConfigured => currentConnection?.isAuthenticated ?? false;

  Future<void> load() => _startOrJoinLoad();

  Future<void> _startOrJoinLoad() {
    final currentLoad = _loadInFlight;
    final currentBarrier = _mutationBarrier;
    if (currentLoad != null && _loadInFlightBarrier == currentBarrier) {
      return currentLoad;
    }

    final completer = Completer<void>();
    final loadFuture = completer.future;
    _loadInFlight = loadFuture;
    _loadInFlightBarrier = currentBarrier;
    unawaited(_runLoadGeneration(loadFuture, completer));
    return loadFuture;
  }

  Future<void> _enqueueOperation(Future<void> Function() operation) {
    final completer = Completer<void>();
    _operationTail = _operationTail.then<void>((_) async {
      try {
        await operation();
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _enqueueMutation(Future<void> Function() operation) {
    _mutationBarrier++;
    return _enqueueOperation(operation);
  }

  Future<void> _runLoadGeneration(
    Future<void> loadFuture,
    Completer<void> completer,
  ) async {
    try {
      await _enqueueOperation(() => _performLoad(loadFuture));
      _clearLoadIfCurrent(loadFuture);
      completer.complete();
    } on SecureCredentialUnavailableException catch (error, stackTrace) {
      await logSwallowedError(
        action: 'load backend session credentials',
        error: error,
        stackTrace: stackTrace,
        source: 'backend_session_provider',
      );
      completer.complete();
    } catch (error, stackTrace) {
      _clearLoadIfCurrent(loadFuture);
      await logSwallowedError(
        action: 'load backend session credentials',
        error: error,
        stackTrace: stackTrace,
        source: 'backend_session_provider',
      );
      completer.completeError(error, stackTrace);
    }
  }

  void _clearLoadIfCurrent(Future<void> loadFuture) {
    if (!identical(_loadInFlight, loadFuture)) return;
    _loadInFlight = null;
    _loadInFlightBarrier = null;
  }

  Future<void> _performLoad(Future<void> loadFuture) async {
    _beginLoadAttempt();
    try {
      final nextSnapshot = await MediaBackendConnectionStore.load();
      _snapshot = nextSnapshot;
      _isReady = true;
      _clearLoadFailure();
      if (!_disposed) notifyListeners();
    } on SecureCredentialUnavailableException catch (error, stackTrace) {
      _clearLoadIfCurrent(loadFuture);
      _recordLoadFailure(error, stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    } catch (error, stackTrace) {
      _clearLoadIfCurrent(loadFuture);
      _recordLoadFailure(error, stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _loadSafely() async {
    try {
      await load();
    } catch (_) {
      // 加载代次已在统一边界记录状态和日志；自动入口只负责阻止异常逃逸。
    }
  }

  Future<void> retryLoad() => _loadSafely();

  void _beginLoadAttempt() {
    if (!hasLoadFailure) return;
    _clearLoadFailure();
    if (!_disposed) notifyListeners();
  }

  void _recordLoadFailure(Object error, StackTrace stackTrace) {
    _lastLoadFailure = error;
    _lastLoadFailureStackTrace = stackTrace;
    if (!_disposed) notifyListeners();
  }

  void _clearLoadFailure() {
    _lastLoadFailure = null;
    _lastLoadFailureStackTrace = null;
  }

  /// 等待会话从磁盘就绪后返回；已就绪则立即返回。
  ///
  /// 分屏详情等**副引擎冷启动**时，构造里的 `load()` 可能尚未完成，此时直接读
  /// [MediaBackendProvider] 会暂时默认回飞牛（[currentKind] fallback）→ Emby 条目被按飞牛
  /// 查询报 noData。页面在读后端前先 `await ensureReady()` 即可拿到磁盘上的当前后端。
  Future<void> ensureReady() async {
    final currentLoad = _loadInFlight;
    if (currentLoad == null) {
      await _operationTail;
      if (_isReady) return;
    }
    try {
      await load();
    } catch (error, stackTrace) {
      throw BackendSessionUnavailableException(
        cause: _lastLoadFailure ?? error,
        stackTrace: _lastLoadFailureStackTrace ?? stackTrace,
      );
    }
    if (!_isReady) {
      throw BackendSessionUnavailableException(
        cause: _lastLoadFailure,
        stackTrace: _lastLoadFailureStackTrace,
      );
    }
  }

  Future<void> saveActive(MediaBackendConnection connection) =>
      _enqueueMutation(() async {
        await MediaBackendConnectionStore.saveActive(connection);
        _snapshot = await MediaBackendConnectionStore.load();
        _isReady = true;
        _clearLoadFailure();
        if (!_disposed) notifyListeners();
      });

  Future<void> saveConnection(MediaBackendConnection connection) =>
      _enqueueMutation(() async {
        await MediaBackendConnectionStore.saveConnection(connection);
        _snapshot = await MediaBackendConnectionStore.load();
        _isReady = true;
        _clearLoadFailure();
        if (!_disposed) notifyListeners();
      });
}
