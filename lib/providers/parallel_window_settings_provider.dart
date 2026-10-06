import 'package:flutter/foundation.dart';

import '../services/parallel_window_settings_bridge.dart';

class ParallelWindowSettingsProvider extends ChangeNotifier {
  final Future<ParallelWindowSettings> Function(
    ParallelWindowSettings settings,
  )?
  _saveSettings;
  bool _isReady = false;

  /// 默认关闭：分屏由用户在设置中开启（安卓真宿主 load 会覆盖为存储值）。
  bool _enabled = false;
  String _preferredPrimaryPaneSide = 'left';
  String _preferredPlaybackPrimaryPaneSide = 'right';
  String _splitRatioPreset = 'balanced';
  bool _defaultPlaybackFullscreen = true;
  bool _immersiveStatusBar = true;
  bool _floatingMiniPlayerEnabled = false;

  bool get isReady => _isReady;
  bool get enabled => _enabled;
  String get preferredPrimaryPaneSide => _preferredPrimaryPaneSide;
  String get preferredPlaybackPrimaryPaneSide =>
      _preferredPlaybackPrimaryPaneSide;
  String get splitRatioPreset => _splitRatioPreset;
  bool get defaultPlaybackFullscreen => _defaultPlaybackFullscreen;
  bool get immersiveStatusBar => _immersiveStatusBar;
  bool get floatingMiniPlayerEnabled => _floatingMiniPlayerEnabled;
  bool get primaryOnLeft => _preferredPrimaryPaneSide == 'left';
  bool get playbackPrimaryOnLeft => _preferredPlaybackPrimaryPaneSide == 'left';

  ParallelWindowSettingsProvider({
    bool autoLoad = true,
    Future<ParallelWindowSettings> Function(ParallelWindowSettings settings)?
    saveSettings,
  }) : _saveSettings = saveSettings {
    if (autoLoad) {
      load();
    }
  }

  Future<void> load() async {
    final settings = await ParallelWindowSettingsBridge.load();
    _applySettings(settings);
    _isReady = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) =>
      _persistSettings(_currentSettings().copyWith(enabled: value));

  Future<void> setPreferredPrimaryPaneSide(String value) {
    final normalized = value == 'right' ? 'right' : 'left';
    return _persistSettings(
      _currentSettings().copyWith(preferredPrimaryPaneSide: normalized),
    );
  }

  Future<void> setPreferredPlaybackPrimaryPaneSide(String value) {
    final normalized = value == 'left' ? 'left' : 'right';
    return _persistSettings(
      _currentSettings().copyWith(preferredPlaybackPrimaryPaneSide: normalized),
    );
  }

  Future<void> setSplitRatioPreset(String value) {
    final normalized = switch (value) {
      'equal' => 'equal',
      'focus_detail' => 'focus_detail',
      'focus_home' => 'focus_home',
      _ => 'balanced',
    };
    return _persistSettings(
      _currentSettings().copyWith(splitRatioPreset: normalized),
    );
  }

  Future<void> setDefaultPlaybackFullscreen(bool value) => _persistSettings(
    _currentSettings().copyWith(defaultPlaybackFullscreen: value),
  );

  Future<void> setImmersiveStatusBar(bool value) =>
      _persistSettings(_currentSettings().copyWith(immersiveStatusBar: value));

  /// 悬浮小窗开关（悬浮小窗方案 3.6）：开启后播放页显示模式入口按「悬浮窗 → PiP」让位。
  Future<void> setFloatingMiniPlayerEnabled(bool value) => _persistSettings(
    _currentSettings().copyWith(floatingMiniPlayerEnabled: value),
  );

  ParallelWindowSettings _currentSettings() {
    return ParallelWindowSettings(
      enabled: _enabled,
      preferredPrimaryPaneSide: _preferredPrimaryPaneSide,
      preferredPlaybackPrimaryPaneSide: _preferredPlaybackPrimaryPaneSide,
      splitRatioPreset: _splitRatioPreset,
      defaultPlaybackFullscreen: _defaultPlaybackFullscreen,
      immersiveStatusBar: _immersiveStatusBar,
      floatingMiniPlayerEnabled: _floatingMiniPlayerEnabled,
    );
  }

  void _applySettings(ParallelWindowSettings settings) {
    _enabled = settings.enabled;
    _preferredPrimaryPaneSide = settings.preferredPrimaryPaneSide;
    _preferredPlaybackPrimaryPaneSide =
        settings.preferredPlaybackPrimaryPaneSide;
    _splitRatioPreset = settings.splitRatioPreset;
    _defaultPlaybackFullscreen = settings.defaultPlaybackFullscreen;
    _immersiveStatusBar = settings.immersiveStatusBar;
    _floatingMiniPlayerEnabled = settings.floatingMiniPlayerEnabled;
  }

  Future<void> _persistSettings(ParallelWindowSettings next) async {
    final previous = _currentSettings();
    _applySettings(next);
    notifyListeners();
    try {
      final saved = _saveSettings != null
          ? await _saveSettings(next)
          : await ParallelWindowSettingsBridge.save(
              enabled: next.enabled,
              preferredPrimaryPaneSide: next.preferredPrimaryPaneSide,
              preferredPlaybackPrimaryPaneSide:
                  next.preferredPlaybackPrimaryPaneSide,
              splitRatioPreset: next.splitRatioPreset,
              defaultPlaybackFullscreen: next.defaultPlaybackFullscreen,
              immersiveStatusBar: next.immersiveStatusBar,
              floatingMiniPlayerEnabled: next.floatingMiniPlayerEnabled,
            );
      _applySettings(saved);
      _isReady = true;
      notifyListeners();
    } catch (_) {
      _applySettings(previous);
      notifyListeners();
      rethrow;
    }
  }
}
