import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/session_exit_bridge.dart';

class NasProvider extends ChangeNotifier {
  static const MethodChannel _sessionStateChannel = MethodChannel(
    'fly_player/session_state',
  );
  static _NasProviderBootstrapSnapshot? _bootstrapSnapshot;

  String _baseUrl = '';
  String _resolvedBaseUrl = '';
  String _userName = '';
  String _password = '';
  String _token = '';
  bool _rememberPassword = true;
  bool _isReady = false;

  String get baseUrl =>
      _resolvedBaseUrl.isNotEmpty ? _resolvedBaseUrl : _baseUrl;
  String get sourceBaseUrl => _baseUrl;
  String get resolvedBaseUrl => _resolvedBaseUrl;
  String get userName => _userName;
  String get password => _password;
  String get token => _token;
  bool get rememberPassword => _rememberPassword;
  bool get isReady => _isReady;

  bool get isConfigured => _baseUrl.isNotEmpty && _token.isNotEmpty;

  NasProvider() {
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
    _loadSettings();
  }

  Future<void> _handleSessionStateMethodCall(MethodCall call) async {
    if (call.method != 'loggedOut') return;
    await _applyLoggedOutState(notify: true);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('base_url') ?? '';
    _resolvedBaseUrl = prefs.getString('resolved_base_url') ?? '';
    _userName = prefs.getString('user_name') ?? '';
    _password = prefs.getString('password') ?? '';
    _token = prefs.getString('token') ?? '';
    if (_token.isEmpty && _resolvedBaseUrl.isNotEmpty) {
      _resolvedBaseUrl = '';
      await prefs.remove('resolved_base_url');
    }
    _rememberPassword = prefs.getBool('remember_password') ?? true;
    _isReady = true;
    _cacheBootstrapSnapshot();
    notifyListeners();
  }

  Future<void> updateSettings({
    required String baseUrl,
    String? resolvedBaseUrl,
    required String userName,
    required String password,
    bool rememberPassword = true,
    String? token,
  }) async {
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
    await prefs.setString('password', _password);
    await prefs.setBool('remember_password', _rememberPassword);
    await prefs.setString('token', _token);

    _cacheBootstrapSnapshot();
    notifyListeners();
  }

  Future<void> updateToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    _token = token;
    await prefs.setString('token', _token);
    _cacheBootstrapSnapshot();
    notifyListeners();
  }

  Future<void> _applyLoggedOutState({bool notify = true}) async {
    final prefs = await SharedPreferences.getInstance();
    _token = '';
    _resolvedBaseUrl = '';
    await prefs.remove('token');
    await prefs.remove('resolved_base_url');
    _cacheBootstrapSnapshot();
    if (notify) {
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _applyLoggedOutState(notify: true);
    await SessionExitBridge.logoutAndResetParallelUi();
  }

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
