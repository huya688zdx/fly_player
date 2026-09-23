import 'package:fly_player/providers/app_theme_provider.dart';
import 'package:fly_player/theme/dynamic_theme_seed_extractor.dart';
import 'package:fly_player/theme/visual_performance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('表现档位可持久化，手动选择覆盖自动档', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final provider = AppThemeProvider();
    await provider.load();

    expect(provider.visualPerformanceMode, AppVisualPerformanceMode.automatic);
    expect(provider.visualPerformanceTier, AppVisualPerformanceTier.balanced);

    await provider.setVisualPerformanceMode(AppVisualPerformanceMode.smooth);
    expect(provider.visualPerformanceTier, AppVisualPerformanceTier.smooth);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_theme_visual_performance_mode'), 'smooth');
  });

  test('流畅与均衡档拒绝全局运行时主题，完整档允许', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final provider = AppThemeProvider();
    await provider.load();
    const seed = DynamicThemeSeed(
      backgroundSeed: Color(0xFF203040),
      accentSeed: Color(0xFF506070),
      selectionSeed: Color(0xFF708090),
      linkSeed: Color(0xFF90A0B0),
      preferLightSurface: false,
    );

    await provider.setRuntimeDynamicTheme(
      pageKey: 'detail:test',
      seed: seed,
      broadcastToMain: false,
    );
    expect(provider.runtimeDynamicThemeSeed, isNull);

    await provider.setVisualPerformanceMode(AppVisualPerformanceMode.full);
    await provider.setRuntimeDynamicTheme(
      pageKey: 'detail:test',
      seed: seed,
      broadcastToMain: false,
    );
    expect(provider.runtimeDynamicThemeSeed, seed);
  });
}
