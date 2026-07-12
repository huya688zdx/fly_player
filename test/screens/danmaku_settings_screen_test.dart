import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/danmaku/models/danmaku_settings.dart';
import 'package:fly_player/danmaku/models/danmaku_saved_source.dart';
import 'package:fly_player/screens/danmaku_settings_screen.dart';
import 'package:fly_player/theme/app_theme.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('弹幕设置保存失败时恢复原值', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppThemeBuilder.buildFromColors(AppThemePalette.fallback),
        home: DanmakuSettingsScreen(
          saveSettings: (_) async => throw StateError('save failed'),
          settingsLoader: () async => DanmakuSettings.defaults,
          savedSourceLoader: () async => const <DanmakuSavedSource>[],
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    final before = tester.widget<Switch>(find.byType(Switch).first).value;
    await tester.tap(find.byType(Switch).first);
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.widget<Switch>(find.byType(Switch).first).value, before);
  });
}
