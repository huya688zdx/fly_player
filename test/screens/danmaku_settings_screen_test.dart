import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/danmaku/models/danmaku_settings.dart';
import 'package:fly_player/danmaku/models/danmaku_saved_source.dart';
import 'package:fly_player/screens/danmaku_settings_screen.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/widgets/app_atmospheric_background.dart';
import 'package:fly_player/widgets/common/app_ambient_page.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('弹幕设置不等待来源统计，保存失败时恢复原值', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final savedSources = Completer<List<DanmakuSavedSource>>();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppThemeBuilder.buildFromColors(
          AppThemePalette.fallback,
        ).copyWith(platform: TargetPlatform.android),
        home: DanmakuSettingsScreen(
          saveSettings: (_) async => throw StateError('save failed'),
          settingsLoader: () async => DanmakuSettings.defaults,
          savedSourceLoader: () => savedSources.future,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('弹幕管理'), findsOneWidget);
    expect(find.byType(Switch), findsWidgets);
    savedSources.complete(const <DanmakuSavedSource>[]);
    await tester.pump();

    final card = tester.widget<Material>(
      find
          .ancestor(of: find.text('弹幕管理'), matching: find.byType(Material))
          .first,
    );
    expect(card.color!.a, closeTo(0.16, 0.01));
    final backButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.arrow_back_rounded),
    );
    expect(backButton.style!.backgroundColor!.resolve({})!.a, lessThan(0.2));
    expect(find.byType(AppAtmosphericBackground), findsOneWidget);
    expect(
      AppAmbientPage.sharesBackgroundOf(tester.element(find.byType(Scaffold))),
      isFalse,
    );

    final before = tester.widget<Switch>(find.byType(Switch).first).value;
    await tester.tap(find.byType(Switch).first);
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.widget<Switch>(find.byType(Switch).first).value, before);
  });
}
