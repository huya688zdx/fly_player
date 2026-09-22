import 'package:shared_preferences/shared_preferences.dart';

import '../models/danmaku_settings.dart';

class DanmakuSettingsStore {
  static const String _prefKey = 'player_danmaku_settings_v1';

  const DanmakuSettingsStore();

  // 仅保存在本播放器，账号键包含服务实例与用户标识。
  Future<bool> loadFlyAiConsent(String accountKey) async {
    if (accountKey.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('fly_danmaku_ai_consent:$accountKey') ?? false;
  }

  Future<void> saveFlyAiConsent(String accountKey, bool allowed) async {
    if (accountKey.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('fly_danmaku_ai_consent:$accountKey', allowed);
  }

  Future<DanmakuSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey) ?? '';
    return DanmakuSettings.decode(raw);
  }

  Future<void> save(DanmakuSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, settings.encode());
  }

  /// 增量回写「弹幕显示偏好」子集（供原生壳改完弹幕设置后反向同步）。只认显示偏好键，
  /// 不动 enabled/source/AI 等会话或数据键。对齐原生 danmakuPrefKeys。
  Future<DanmakuSettings> savePatch(Map<String, Object?> patch) async {
    final current = await load();
    bool? boolOf(String k) => patch.containsKey(k) ? patch[k] == true : null;
    double? doubleOf(String k) => (patch[k] as num?)?.toDouble();
    int? intOf(String k) => (patch[k] as num?)?.toInt();
    final next = current.copyWith(
      scrollEnabled: boolOf('scrollEnabled'),
      topEnabled: boolOf('topEnabled'),
      bottomEnabled: boolOf('bottomEnabled'),
      colorEnabled: boolOf('colorEnabled'),
      hideDuplicate: boolOf('hideDuplicate'),
      avoidSubtitleArea: boolOf('avoidSubtitleArea'),
      opacity: doubleOf('opacity'),
      density: doubleOf('density'),
      fontScale: doubleOf('fontScale'),
      fontThickness: doubleOf('fontThickness'),
      speed: doubleOf('speed'),
      displayAreaRatio: doubleOf('displayAreaRatio'),
      targetFrameRateHz: intOf('targetFrameRateHz'),
    );
    await save(next);
    return next;
  }
}
