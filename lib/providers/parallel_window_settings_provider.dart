import 'package:flutter/foundation.dart';

import '../services/parallel_window_settings_bridge.dart';

class ParallelWindowSettingsProvider extends ChangeNotifier {
  bool _isReady = false;
  bool _enabled = true;
  String _preferredPrimaryPaneSide = 'left';
  String _preferredPlaybackPrimaryPaneSide = 'right';
  String _splitRatioPreset = 'balanced';
  bool _defaultPlaybackFullscreen = true;
  bool _immersiveStatusBar = true;

  bool get isReady => _isReady;
  bool get enabled => _enabled;
  String get preferredPrimaryPaneSide => _preferredPrimaryPaneSide;
  String get preferredPlaybackPrimaryPaneSide =>
      _preferredPlaybackPrimaryPaneSide;
  String get splitRatioPreset => _splitRatioPreset;
  bool get defaultPlaybackFullscreen => _defaultPlaybackFullscreen;
  bool get immersiveStatusBar => _immersiveStatusBar;
  bool get primaryOnLeft => _preferredPrimaryPaneSide == 'left';
  bool get playbackPrimaryOnLeft => _preferredPlaybackPrimaryPaneSide == 'left';

  ParallelWindowSettingsProvider() {
    load();
  }

  Future<void> load() async {
    final settings = await ParallelWindowSettingsBridge.load();
    _enabled = settings.enabled;
    _preferredPrimaryPaneSide = settings.preferredPrimaryPaneSide;
    _preferredPlaybackPrimaryPaneSide =
        settings.preferredPlaybackPrimaryPaneSide;
    _splitRatioPreset = settings.splitRatioPreset;
    _defaultPlaybackFullscreen = settings.defaultPlaybackFullscreen;
    _immersiveStatusBar = settings.immersiveStatusBar;
    _isReady = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    notifyListeners();
    final settings = await ParallelWindowSettingsBridge.save(
      enabled: _enabled,
      preferredPrimaryPaneSide: _preferredPrimaryPaneSide,
      preferredPlaybackPrimaryPaneSide: _preferredPlaybackPrimaryPaneSide,
      splitRatioPreset: _splitRatioPreset,
      defaultPlaybackFullscreen: _defaultPlaybackFullscreen,
      immersiveStatusBar: _immersiveStatusBar,
    );
    _enabled = settings.enabled;
    _preferredPrimaryPaneSide = settings.preferredPrimaryPaneSide;
    _preferredPlaybackPrimaryPaneSide =
        settings.preferredPlaybackPrimaryPaneSide;
    _splitRatioPreset = settings.splitRatioPreset;
    _defaultPlaybackFullscreen = settings.defaultPlaybackFullscreen;
    _immersiveStatusBar = settings.immersiveStatusBar;
    _isReady = true;
    notifyListeners();
  }

  Future<void> setPreferredPrimaryPaneSide(String value) async {
    final normalized = value == 'right' ? 'right' : 'left';
    _preferredPrimaryPaneSide = normalized;
    notifyListeners();
    final settings = await ParallelWindowSettingsBridge.save(
      enabled: _enabled,
      preferredPrimaryPaneSide: _preferredPrimaryPaneSide,
      preferredPlaybackPrimaryPaneSide: _preferredPlaybackPrimaryPaneSide,
      splitRatioPreset: _splitRatioPreset,
      defaultPlaybackFullscreen: _defaultPlaybackFullscreen,
      immersiveStatusBar: _immersiveStatusBar,
    );
    _enabled = settings.enabled;
    _preferredPrimaryPaneSide = settings.preferredPrimaryPaneSide;
    _preferredPlaybackPrimaryPaneSide =
        settings.preferredPlaybackPrimaryPaneSide;
    _splitRatioPreset = settings.splitRatioPreset;
    _defaultPlaybackFullscreen = settings.defaultPlaybackFullscreen;
    _immersiveStatusBar = settings.immersiveStatusBar;
    _isReady = true;
    notifyListeners();
  }

  Future<void> setPreferredPlaybackPrimaryPaneSide(String value) async {
    final normalized = value == 'left' ? 'left' : 'right';
    _preferredPlaybackPrimaryPaneSide = normalized;
    notifyListeners();
    final settings = await ParallelWindowSettingsBridge.save(
      enabled: _enabled,
      preferredPrimaryPaneSide: _preferredPrimaryPaneSide,
      preferredPlaybackPrimaryPaneSide: _preferredPlaybackPrimaryPaneSide,
      splitRatioPreset: _splitRatioPreset,
      defaultPlaybackFullscreen: _defaultPlaybackFullscreen,
      immersiveStatusBar: _immersiveStatusBar,
    );
    _enabled = settings.enabled;
    _preferredPrimaryPaneSide = settings.preferredPrimaryPaneSide;
    _preferredPlaybackPrimaryPaneSide =
        settings.preferredPlaybackPrimaryPaneSide;
    _splitRatioPreset = settings.splitRatioPreset;
    _defaultPlaybackFullscreen = settings.defaultPlaybackFullscreen;
    _immersiveStatusBar = settings.immersiveStatusBar;
    _isReady = true;
    notifyListeners();
  }

  Future<void> setSplitRatioPreset(String value) async {
    final normalized = switch (value) {
      'equal' => 'equal',
      'focus_detail' => 'focus_detail',
      'focus_home' => 'focus_home',
      _ => 'balanced',
    };
    _splitRatioPreset = normalized;
    notifyListeners();
    final settings = await ParallelWindowSettingsBridge.save(
      enabled: _enabled,
      preferredPrimaryPaneSide: _preferredPrimaryPaneSide,
      preferredPlaybackPrimaryPaneSide: _preferredPlaybackPrimaryPaneSide,
      splitRatioPreset: _splitRatioPreset,
      defaultPlaybackFullscreen: _defaultPlaybackFullscreen,
      immersiveStatusBar: _immersiveStatusBar,
    );
    _enabled = settings.enabled;
    _preferredPrimaryPaneSide = settings.preferredPrimaryPaneSide;
    _preferredPlaybackPrimaryPaneSide =
        settings.preferredPlaybackPrimaryPaneSide;
    _splitRatioPreset = settings.splitRatioPreset;
    _defaultPlaybackFullscreen = settings.defaultPlaybackFullscreen;
    _immersiveStatusBar = settings.immersiveStatusBar;
    _isReady = true;
    notifyListeners();
  }

  Future<void> setDefaultPlaybackFullscreen(bool value) async {
    _defaultPlaybackFullscreen = value;
    notifyListeners();
    final settings = await ParallelWindowSettingsBridge.save(
      enabled: _enabled,
      preferredPrimaryPaneSide: _preferredPrimaryPaneSide,
      preferredPlaybackPrimaryPaneSide: _preferredPlaybackPrimaryPaneSide,
      splitRatioPreset: _splitRatioPreset,
      defaultPlaybackFullscreen: _defaultPlaybackFullscreen,
      immersiveStatusBar: _immersiveStatusBar,
    );
    _enabled = settings.enabled;
    _preferredPrimaryPaneSide = settings.preferredPrimaryPaneSide;
    _preferredPlaybackPrimaryPaneSide =
        settings.preferredPlaybackPrimaryPaneSide;
    _splitRatioPreset = settings.splitRatioPreset;
    _defaultPlaybackFullscreen = settings.defaultPlaybackFullscreen;
    _immersiveStatusBar = settings.immersiveStatusBar;
    _isReady = true;
    notifyListeners();
  }

  Future<void> setImmersiveStatusBar(bool value) async {
    _immersiveStatusBar = value;
    notifyListeners();
    final settings = await ParallelWindowSettingsBridge.save(
      enabled: _enabled,
      preferredPrimaryPaneSide: _preferredPrimaryPaneSide,
      preferredPlaybackPrimaryPaneSide: _preferredPlaybackPrimaryPaneSide,
      splitRatioPreset: _splitRatioPreset,
      defaultPlaybackFullscreen: _defaultPlaybackFullscreen,
      immersiveStatusBar: _immersiveStatusBar,
    );
    _enabled = settings.enabled;
    _preferredPrimaryPaneSide = settings.preferredPrimaryPaneSide;
    _preferredPlaybackPrimaryPaneSide =
        settings.preferredPlaybackPrimaryPaneSide;
    _splitRatioPreset = settings.splitRatioPreset;
    _defaultPlaybackFullscreen = settings.defaultPlaybackFullscreen;
    _immersiveStatusBar = settings.immersiveStatusBar;
    _isReady = true;
    notifyListeners();
  }
}
