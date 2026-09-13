import 'package:shared_preferences/shared_preferences.dart';

/// The verified-source switch belongs to the existing OP/ED settings page.
/// Authentication is checked separately and is never stored as a preference.
class FlyOpedSettings {
  static const enabledKey = 'player_fly_oped_enabled';

  static Future<bool> load() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(enabledKey) ?? true;
    } catch (_) {
      // Preference failure disables this enhancement, never original playback.
      return false;
    }
  }

  static Future<void> save(bool enabled) async {
    await (await SharedPreferences.getInstance()).setBool(enabledKey, enabled);
  }
}
