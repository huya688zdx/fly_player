import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/providers/app_theme_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('保存主题 JSON 损坏时保留原文备份，避免数据无迹丢失', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'app_theme_saved_themes_v1': '[invalid-json',
    });

    final provider = AppThemeProvider();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final prefs = await SharedPreferences.getInstance();

    expect(
      prefs.getString('app_theme_saved_themes_v1_corrupt_backup'),
      '[invalid-json',
    );
    provider.dispose();
  });
}
