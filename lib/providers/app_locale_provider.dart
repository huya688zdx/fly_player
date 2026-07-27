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

  /// 无 BuildContext 场景（如原生播放壳桥接）读取持久化的语言覆盖值：system 模式
  /// 返回 null（调用方应回退平台语言），zhCN 返回固定的 `zh-CN`。直接读
  /// SharedPreferences，不依赖 Provider 实例是否已构建/load 完成。
  static Future<Locale?> loadStoredLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = AppLocaleMode.fromStorageValue(
      prefs.getString(_localeModeKey) ?? '',
    );
    return switch (mode) {
      AppLocaleMode.system => null,
      AppLocaleMode.zhCN => const Locale('zh', 'CN'),
    };
  }
}
