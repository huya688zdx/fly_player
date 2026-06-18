import 'package:shared_preferences/shared_preferences.dart';

class ScreenshotSettingsData {
  final bool includeSubtitles;
  final String savePathMode;

  const ScreenshotSettingsData({
    required this.includeSubtitles,
    required this.savePathMode,
  });
}

class ScreenshotSavePathOption {
  final String value;
  final String label;
  final String description;

  const ScreenshotSavePathOption({
    required this.value,
    required this.label,
    required this.description,
  });
}

class ScreenshotSettingsStore {
  static const String includeSubtitlesKey = 'screenshot_include_subtitles';
  static const String savePathModeKey = 'screenshot_save_path_mode';

  static const bool defaultIncludeSubtitles = false;
  static const String defaultSavePathMode = 'pictures';
  static const String customSavePathMode = 'custom';

  static const List<ScreenshotSavePathOption> savePathOptions =
      <ScreenshotSavePathOption>[
        ScreenshotSavePathOption(
          value: 'pictures',
          label: 'Pictures',
          description: 'Save to Pictures/FlyPlayer.',
        ),
        ScreenshotSavePathOption(
          value: 'dcim',
          label: 'DCIM',
          description: 'Save to DCIM/FlyPlayer.',
        ),
        ScreenshotSavePathOption(
          value: 'app_pictures',
          label: 'App pictures',
          description: 'Save to the app-specific pictures directory.',
        ),
        ScreenshotSavePathOption(
          value: customSavePathMode,
          label: 'Custom folder',
          description: 'Save to a folder selected by the user.',
        ),
      ];

  const ScreenshotSettingsStore();

  Future<ScreenshotSettingsData> load() async {
    final prefs = await SharedPreferences.getInstance();
    // 原生播放器会直接写入同一份 FlutterSharedPreferences，这里先刷新以读到其改动。
    await prefs.reload();
    final includeSubtitles =
        prefs.getBool(includeSubtitlesKey) ?? defaultIncludeSubtitles;
    final rawSavePathMode =
        prefs.getString(savePathModeKey) ?? defaultSavePathMode;
    return ScreenshotSettingsData(
      includeSubtitles: includeSubtitles,
      savePathMode: _normalizeSavePathMode(rawSavePathMode),
    );
  }

  Future<ScreenshotSettingsData> saveIncludeSubtitles(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(includeSubtitlesKey, value);
    final current = await load();
    return ScreenshotSettingsData(
      includeSubtitles: value,
      savePathMode: current.savePathMode,
    );
  }

  Future<ScreenshotSettingsData> savePathMode(String value) async {
    final normalized = _normalizeSavePathMode(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(savePathModeKey, normalized);
    final current = await load();
    return ScreenshotSettingsData(
      includeSubtitles: current.includeSubtitles,
      savePathMode: normalized,
    );
  }

  String subtitleModeLabel(bool includeSubtitles) {
    return includeSubtitles ? 'With subtitles' : 'Image only';
  }

  String savePathLabel(String value) {
    final normalized = _normalizeSavePathMode(value);
    for (final option in savePathOptions) {
      if (option.value == normalized) return option.label;
    }
    return savePathOptions.first.label;
  }

  String savePathDescription(String value) {
    final normalized = _normalizeSavePathMode(value);
    for (final option in savePathOptions) {
      if (option.value == normalized) return option.description;
    }
    return savePathOptions.first.description;
  }

  String _normalizeSavePathMode(String value) {
    for (final option in savePathOptions) {
      if (option.value == value) return option.value;
    }
    return defaultSavePathMode;
  }
}
