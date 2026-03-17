import 'package:shared_preferences/shared_preferences.dart';

import '../models/danmaku_settings.dart';

class DanmakuSettingsStore {
  static const String _prefKey = 'player_danmaku_settings_v1';

  const DanmakuSettingsStore();

  Future<DanmakuSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey) ?? '';
    return DanmakuSettings.decode(raw);
  }

  Future<void> save(DanmakuSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, settings.encode());
  }
}
