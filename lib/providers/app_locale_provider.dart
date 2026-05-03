import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLocaleMode {
  system('system'),
  zhCN('zh-CN');

  const AppLocaleMode(this.storageValue);

  final String storageValue;

  static AppLocaleMode fromStorageValue(String value) {
    for (final mode in values) {
      if (mode.storageValue == value) return mode;
    }
    return system;
  }
}

class AppLocaleProvider extends ChangeNotifier {
  static const String _localeModeKey = 'app_locale_mode';

  AppLocaleMode _mode = AppLocaleMode.system;
  bool _isReady = false;

  AppLocaleProvider() {
    unawaited(load());
  }

  AppLocaleMode get mode => _mode;
  bool get isReady => _isReady;

  Locale? get locale => switch (_mode) {
    AppLocaleMode.system => null,
    AppLocaleMode.zhCN => const Locale('zh', 'CN'),
  };

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final nextMode = AppLocaleMode.fromStorageValue(
      prefs.getString(_localeModeKey) ?? '',
    );
    final changed = !_isReady || nextMode != _mode;
    _mode = nextMode;
    _isReady = true;
    if (changed) notifyListeners();
  }

  Future<void> setMode(AppLocaleMode mode) async {
    if (_mode == mode && _isReady) return;
    _mode = mode;
    _isReady = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeModeKey, mode.storageValue);
  }
}
