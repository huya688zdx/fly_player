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
          label: '系统相册',
          description: '保存到 Pictures/FlyPlayer，适合普通截图查看。',
        ),
        ScreenshotSavePathOption(
          value: 'dcim',
          label: '相机目录',
          description: '保存到 DCIM/FlyPlayer，更容易被系统相册归类展示。',
        ),
        ScreenshotSavePathOption(
          value: 'app_pictures',
          label: '应用目录',
          description: '保存到应用专属图片目录，更干净，但部分图库不会直接扫描。',
        ),
        ScreenshotSavePathOption(
          value: customSavePathMode,
          label: '自定义目录',
          description: '保存到用户自己选择的文件夹，适合集中管理截图。',
        ),
      ];

  const ScreenshotSettingsStore();

  Future<ScreenshotSettingsData> load() async {
    final prefs = await SharedPreferences.getInstance();
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
    return includeSubtitles ? '携带字幕' : '仅画面';
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
