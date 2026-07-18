import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/feiniu_api.dart';
import '../services/detail_runtime_cache.dart';
import '../services/play_stats/play_stats.dart';
import '../services/playback_progress_offline_queue.dart';
import '../services/secure_credential_store.dart';
import '../services/session_exit_bridge.dart';
import '../theme/dynamic_theme_seed_extractor.dart';
import '../utils/swallowed_error_logger.dart';

class NasProvider extends ChangeNotifier with WidgetsBindingObserver {
  static const MethodChannel _sessionStateChannel = MethodChannel(
    'fly_player/session_state',
  );
  static const String _playStatsOwnerKeyPref = 'play_stats_owner_key';
  static const String _passwordCredentialKey = 'nas_session.password';
  static const String _tokenCredentialKey = 'nas_session.token';
  static _NasProviderBootstrapSnapshot? _bootstrapSnapshot;

  String _baseUrl = '';
  String _resolvedBaseUrl = '';
  String _userName = '';
  String _password = '';
  String _token = '';
  bool _rememberPassword = true;
  bool _isReady = false;
  Object? _lastLoadFailure;
  StackTrace? _lastLoadFailureStackTrace;
  Future<void>? _loadSettingsInFlight;
  int? _loadSettingsInFlightBarrier;
  int _mutationBarrier = 0;
  Future<void> _operationTail = Future<void>.value();
  bool _disposed = false;

  String get baseUrl =>
      _resolvedBaseUrl.isNotEmpty ? _resolvedBaseUrl : _baseUrl;
  String get sourceBaseUrl => _baseUrl;
  String get resolvedBaseUrl => _resolvedBaseUrl;
  String get userName => _userName;
  String get password => _password;
  String get token => _token;
  bool get rememberPassword => _rememberPassword;
  bool get isReady => _isReady;
  bool get hasLoadFailure =>
      _lastLoadFailure != null || _lastLoadFailureStackTrace != null;

  bool get isConfigured => _baseUrl.isNotEmpty && _token.isNotEmpty;

  NasProvider() {
    WidgetsBinding.instance.addObserver(this);
    final bootstrap = _bootstrapSnapshot;
    if (bootstrap != null) {
      _baseUrl = bootstrap.baseUrl;
      _resolvedBaseUrl = bootstrap.resolvedBaseUrl;
      _userName = bootstrap.userName;
      _password = bootstrap.password;
      _token = bootstrap.token;
      _rememberPassword = bootstrap.rememberPassword;
      _isReady = true;
    }
    _sessionStateChannel.setMethodCallHandler(_handleSessionStateMethodCall);
    unawaited(_loadSettingsSafely());
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _sessionStateChannel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadSettingsSafely());
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(DynamicThemeSeedExtractor.flushPendingWrites());
    }
  }

  @visibleForTesting
  Future<void> reloadSettingsForTesting() => _startOrJoinSettingsLoad();

  @visibleForTesting
  static void resetBootstrapForTesting() {
    _bootstrapSnapshot = null;
  }

  Future<void> _handleSessionStateMethodCall(MethodCall call) async {
    if (call.method != 'loggedOut') return;
    await _enqueueMutation(() => _applyLoggedOutState(notify: true));
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

  Future<void> _loadSettings() async {
    if (_disposed) return;
    final prefs = await SharedPreferences.getInstance();
    // 跨 isolate 同步登录态：分屏副栏是独立 Flutter 引擎(独立 isolate)，其
    // SharedPreferences 在首次读取后会内存缓存。若副栏引擎在主引擎登录“之前”就被
    // 预热(warmIfEligible)，它缓存的是空 token；主引擎随后登录只更新自己 isolate 的
    // 缓存与磁盘 XML，副栏 isolate 不会自动感知 → 分屏唤起时仍判未登录、落到登录页。
    // 故每次加载先 reload() 从磁盘重读，确保副栏被 resume 时拿到主引擎写入的最新会话。
    await prefs.reload();
    if (_disposed) return;
    final nextBaseUrl = prefs.getString('base_url') ?? '';
    var nextResolvedBaseUrl = prefs.getString('resolved_base_url') ?? '';
    final nextUserName = prefs.getString('user_name') ?? '';
    final legacyPassword = prefs.getString('password') ?? '';
    final legacyToken = prefs.getString('token') ?? '';
    final restoredToken = await _restoreCredential(
      _tokenCredentialKey,
      legacyValue: legacyToken,
      currentValue: _token,
      shouldKeep: true,
    );
    if (_disposed) return;
    if (!restoredToken.available) {
      throw const SecureCredentialUnavailableException(_tokenCredentialKey);
    }
    if (legacyToken.isNotEmpty) {
      await prefs.remove('token');
    }
    final restoredPassword = await _restoreCredential(
      _passwordCredentialKey,
      legacyValue: legacyPassword,
      currentValue: _password,
      shouldKeep: prefs.getBool('remember_password') ?? true,
    );
    if (restoredPassword.available && legacyPassword.isNotEmpty) {
      await prefs.remove('password');
    }
    if (_disposed) return;
    final nextPassword = restoredPassword.value;
    final nextToken = restoredToken.value;
    if (nextToken.isEmpty && nextResolvedBaseUrl.isNotEmpty) {
      nextResolvedBaseUrl = '';
      await prefs.remove('resolved_base_url');
    }
    final nextRememberPassword = prefs.getBool('remember_password') ?? true;
    final changed =
        _baseUrl != nextBaseUrl ||
        _resolvedBaseUrl != nextResolvedBaseUrl ||
        _userName != nextUserName ||
        _password != nextPassword ||
        _token != nextToken ||
        _rememberPassword != nextRememberPassword ||
        !_isReady ||
        hasLoadFailure;

    _baseUrl = nextBaseUrl;
    _resolvedBaseUrl = nextResolvedBaseUrl;
    _userName = nextUserName;
    _password = nextPassword;
    _token = nextToken;
    _rememberPassword = nextRememberPassword;
    await _syncPlayStatsOwner(prefs);
    if (_disposed) return;
    _isReady = true;
    _clearLoadFailure();
    _cacheBootstrapSnapshot();
    if (changed) {
      notifyListeners();
    }
    // 启动 / 回前台（resumed 会重走 _loadSettings）时重放断网期间积压的进度。
    // isConfigured 内部已判 token，未登录不动队列。
    if (isConfigured) {
      unawaited(PlaybackProgressOfflineQueue.flush(this));
    }
  }

  Future<void> _loadSettingsSafely() async {
    try {
      await _startOrJoinSettingsLoad();
    } catch (_) {
      // 加载代次已在统一边界记录状态和日志；自动入口只负责阻止异常逃逸。
    }
  }

  Future<void> _startOrJoinSettingsLoad() {
    final currentLoad = _loadSettingsInFlight;
    final currentBarrier = _mutationBarrier;
    if (currentLoad != null && _loadSettingsInFlightBarrier == currentBarrier) {
      return currentLoad;
    }

    final completer = Completer<void>();
    final loadFuture = completer.future;
    _loadSettingsInFlight = loadFuture;
    _loadSettingsInFlightBarrier = currentBarrier;
    unawaited(_runSettingsLoadGeneration(loadFuture, completer));
    return loadFuture;
  }

  Future<void> _runSettingsLoadGeneration(
    Future<void> loadFuture,
    Completer<void> completer,
  ) async {
    try {
      await _enqueueOperation(() => _performSettingsLoad(loadFuture));
      _clearSettingsLoadIfCurrent(loadFuture);
      completer.complete();
    } on SecureCredentialUnavailableException catch (error, stackTrace) {
      await logSwallowedError(
        action: 'load NAS session settings',
        error: error,
        stackTrace: stackTrace,
        source: 'nas_provider',
      );
      completer.complete();
    } catch (error, stackTrace) {
      _clearSettingsLoadIfCurrent(loadFuture);
      await logSwallowedError(
        action: 'load NAS session settings',
        error: error,
        stackTrace: stackTrace,
        source: 'nas_provider',
      );
      completer.completeError(error, stackTrace);
    }
  }

  void _clearSettingsLoadIfCurrent(Future<void> loadFuture) {
    if (!identical(_loadSettingsInFlight, loadFuture)) return;
    _loadSettingsInFlight = null;
    _loadSettingsInFlightBarrier = null;
  }

  Future<void> _performSettingsLoad(Future<void> loadFuture) async {
    _beginLoadAttempt();
    try {
      await _loadSettings();
    } on SecureCredentialUnavailableException catch (error, stackTrace) {
      _clearSettingsLoadIfCurrent(loadFuture);
      _recordLoadFailure(error, stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    } catch (error, stackTrace) {
      _clearSettingsLoadIfCurrent(loadFuture);
      _recordLoadFailure(error, stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> retryLoad() => _loadSettingsSafely();

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

  Future<void> updateSettings({
    required String baseUrl,
    String? resolvedBaseUrl,
    required String userName,
    required String password,
    bool rememberPassword = true,
    String? token,
  }) => _enqueueMutation(() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = baseUrl;
    _resolvedBaseUrl = resolvedBaseUrl?.trim() ?? '';
    _userName = userName;
    _rememberPassword = rememberPassword;
    _password = rememberPassword ? password : '';
    if (token != null) _token = token;

    await prefs.setString('base_url', _baseUrl);
    await prefs.setString('resolved_base_url', _resolvedBaseUrl);
    await prefs.setString('user_name', _userName);
    await prefs.setBool('remember_password', _rememberPassword);
    await _writeOrDelete(_passwordCredentialKey, _password);
    await _writeOrDelete(_tokenCredentialKey, _token);
    await prefs.remove('password');
    await prefs.remove('token');
    await _syncPlayStatsOwner(prefs);

    _cacheBootstrapSnapshot();
    if (!_disposed) notifyListeners();
  });

  Future<void> updateToken(String token) => _enqueueMutation(() async {
    final prefs = await SharedPreferences.getInstance();
    _token = token;
    await _writeOrDelete(_tokenCredentialKey, _token);
    await prefs.remove('token');
    _cacheBootstrapSnapshot();
    if (!_disposed) notifyListeners();
  });

  Future<void> _applyLoggedOutState({bool notify = true}) async {
    final prefs = await SharedPreferences.getInstance();
    _token = '';
    _resolvedBaseUrl = '';
    await SecureCredentialStore.delete(_tokenCredentialKey);
    await prefs.remove('token');
    await prefs.remove('resolved_base_url');
    await _syncPlayStatsOwner(prefs);
    DetailRuntimeCache.instance.clearAll();
    FeiniuApi.clearSharedResourceCache();
    _cacheBootstrapSnapshot();
    if (notify && !_disposed) {
      notifyListeners();
    }
  }

  Future<void> logout() => _enqueueMutation(() async {
    await _applyLoggedOutState(notify: true);
    await SessionExitBridge.logoutAndResetParallelUi();
  });

  void _cacheBootstrapSnapshot() {
    _bootstrapSnapshot = _NasProviderBootstrapSnapshot(
      baseUrl: _baseUrl,
      resolvedBaseUrl: _resolvedBaseUrl,
      userName: _userName,
      password: _password,
      token: _token,
      rememberPassword: _rememberPassword,
    );
  }

  Future<void> _syncPlayStatsOwner(SharedPreferences prefs) async {
    final nextOwnerKey = _currentPlayStatsOwnerKey();
    await PlayStatsService.instance.bindOwnerScope(nextOwnerKey);
    if (nextOwnerKey.isEmpty) {
      await prefs.remove(_playStatsOwnerKeyPref);
      return;
    }
    await prefs.setString(_playStatsOwnerKeyPref, nextOwnerKey);
  }

  String _currentPlayStatsOwnerKey() {
    if (_token.trim().isEmpty) {
      return '';
    }
    final normalizedBaseUrl =
        (_resolvedBaseUrl.isNotEmpty ? _resolvedBaseUrl : _baseUrl)
            .trim()
            .toLowerCase();
    final normalizedUserName = _userName.trim().toLowerCase();
    if (normalizedBaseUrl.isEmpty || normalizedUserName.isEmpty) {
      return '';
    }
    return '$normalizedBaseUrl|$normalizedUserName';
  }

  Future<({String value, bool available})> _restoreCredential(
    String key, {
    required String legacyValue,
    required String currentValue,
    required bool shouldKeep,
  }) async {
    if (!shouldKeep) {
      await SecureCredentialStore.delete(key);
      return (value: '', available: true);
    }
    final stored = await SecureCredentialStore.read(key);
    if (stored.isUnavailable) {
      return (value: currentValue, available: false);
    }
    if (stored.value.isNotEmpty) {
      return (value: stored.value, available: true);
    }
    if (legacyValue.isNotEmpty) {
      await SecureCredentialStore.write(key, legacyValue);
      return (value: legacyValue, available: true);
    }
    return (value: '', available: true);
  }

  Future<void> _writeOrDelete(String key, String value) async {
    if (value.isEmpty) {
      await SecureCredentialStore.delete(key);
    } else {
      await SecureCredentialStore.write(key, value);
    }
  }
}

class _NasProviderBootstrapSnapshot {
  final String baseUrl;
  final String resolvedBaseUrl;
  final String userName;
  final String password;
  final String token;
  final bool rememberPassword;

  const _NasProviderBootstrapSnapshot({
    required this.baseUrl,
    required this.resolvedBaseUrl,
    required this.userName,
    required this.password,
    required this.token,
    required this.rememberPassword,
  });
}
