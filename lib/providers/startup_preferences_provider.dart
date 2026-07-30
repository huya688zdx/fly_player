import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef StartupPreferenceLoader = Future<bool> Function();
typedef StartupPreferenceSaver = Future<bool> Function(bool value);

class StartupPreferencesProvider extends ChangeNotifier {
  static const String preferenceKey = 'startup_open_poster_home';

  final StartupPreferenceLoader? _loadPreference;
  final StartupPreferenceSaver? _savePreference;

  bool _isReady = false;
  bool _openPosterHomeOnStartup = false;

  StartupPreferencesProvider({
    bool autoLoad = true,
    StartupPreferenceLoader? loadPreference,
    StartupPreferenceSaver? savePreference,
  }) : _loadPreference = loadPreference,
       _savePreference = savePreference {
    if (autoLoad) unawaited(load());
  }

  bool get isReady => _isReady;
  bool get openPosterHomeOnStartup => _openPosterHomeOnStartup;

  Future<void> load() async {
    var nextValue = false;
    try {
      nextValue = _loadPreference != null
          ? await _loadPreference()
          : await _loadStoredPreference();
    } catch (_) {
      nextValue = false;
    }
    final changed = !_isReady || nextValue != _openPosterHomeOnStartup;
    _openPosterHomeOnStartup = nextValue;
    _isReady = true;
    if (changed) notifyListeners();
  }

  Future<void> setOpenPosterHomeOnStartup(bool value) async {
    if (_isReady && value == _openPosterHomeOnStartup) return;
    final previous = _openPosterHomeOnStartup;
    _openPosterHomeOnStartup = value;
    _isReady = true;
    notifyListeners();
    try {
      final saved = await _persistPreference(value);
      if (!saved) {
        throw StateError('启动目的地偏好保存失败');
      }
    } catch (_) {
      try {
        await _persistPreference(previous);
      } catch (_) {
        // 保留原始异常；Provider 状态仍回滚到更新前。
      }
      _openPosterHomeOnStartup = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<bool> _persistPreference(bool value) async {
    if (_savePreference != null) return _savePreference(value);
    final prefs = await SharedPreferences.getInstance();
    return prefs.setBool(preferenceKey, value);
  }

  static Future<bool> _loadStoredPreference() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(preferenceKey) ?? false;
  }
}
