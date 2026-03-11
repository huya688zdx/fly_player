import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NasProvider extends ChangeNotifier {
  String _baseUrl = '';
  String _userName = '';
  String _password = '';
  String _token = '';
  bool _rememberPassword = true;
  bool _isReady = false;

  String get baseUrl => _baseUrl;
  String get userName => _userName;
  String get password => _password;
  String get token => _token;
  bool get rememberPassword => _rememberPassword;
  bool get isReady => _isReady;

  bool get isConfigured => _baseUrl.isNotEmpty && _token.isNotEmpty;

  NasProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('base_url') ?? '';
    _userName = prefs.getString('user_name') ?? '';
    _password = prefs.getString('password') ?? '';
    _token = prefs.getString('token') ?? '';
    _rememberPassword = prefs.getBool('remember_password') ?? true;
    _isReady = true;
    notifyListeners();
  }

  Future<void> updateSettings({
    required String baseUrl,
    required String userName,
    required String password,
    bool rememberPassword = true,
    String? token,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = baseUrl;
    _userName = userName;
    _rememberPassword = rememberPassword;
    _password = rememberPassword ? password : '';
    if (token != null) _token = token;

    await prefs.setString('base_url', _baseUrl);
    await prefs.setString('user_name', _userName);
    await prefs.setString('password', _password);
    await prefs.setBool('remember_password', _rememberPassword);
    await prefs.setString('token', _token);
    
    notifyListeners();
  }

  Future<void> updateToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    _token = token;
    await prefs.setString('token', _token);
    notifyListeners();
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    _token = '';
    await prefs.remove('token');
    notifyListeners();
  }
}
