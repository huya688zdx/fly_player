import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/providers/app_theme_provider.dart';
import 'package:fly_player/screens/theme_settings_screen.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/widgets/common/app_ambient_page.dart';
import 'package:fly_player/widgets/app_atmospheric_background.dart';
import 'package:fly_player/widgets/settings/theme/theme_settings_preview_card.dart';

void main() {
  testWidgets('背景样式点击即生效，换配色和重新加载后保留选择', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(404, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final provider = AppThemeProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => provider,
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          theme: AppThemeBuilder.build(AppThemePreset.midnight),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ThemeSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(provider.backgroundStyle, AppBackgroundStyle.softMist);
    final option = find.byKey(
      const ValueKey<String>('background-style-auroraRibbon'),
    );
    await tester.scrollUntilVisible(
      option,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(option);
    await tester.pumpAndSettle();
    await tester.tap(option);
    await tester.pumpAndSettle();
    expect(provider.backgroundStyle, AppBackgroundStyle.auroraRibbon);
    final background = find
        .descendant(
          of: find.byType(AppAtmosphericBackground),
          matching: find.byType(AppAtmosphereSurface),
        )
        .first;
    expect(
      tester.widget<AppAtmosphereSurface>(background).style,
      AppBackgroundStyle.auroraRibbon,
    );
    await tester.runAsync(() => provider.applyPreset(AppThemePreset.forest));
    await tester.pumpAndSettle();
    expect(provider.backgroundStyle, AppBackgroundStyle.auroraRibbon);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_theme_background_style'), 'auroraRibbon');
    await tester.runAsync(() => provider.load());
    await tester.pumpAndSettle();
    expect(provider.backgroundStyle, AppBackgroundStyle.auroraRibbon);
    expect(provider.preset, AppThemePreset.forest);
    await tester.scrollUntilVisible(
      find.byType(ThemeSettingsPreviewCard),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    final preview = tester.widget<ThemeSettingsPreviewCard>(
      find.byType(ThemeSettingsPreviewCard),
    );
    expect(preview.backgroundStyle, AppBackgroundStyle.auroraRibbon);
    expect(
      preview.colors.toSignatureValues(),
      provider.selectedThemeBaseColors.toSignatureValues(),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('小窗口色板横向排列并可选色，末项可滚动到导航上方', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(404, 850);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 80);
    addTearDown(tester.view.reset);
    final provider = AppThemeProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => provider,
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          theme: AppThemeBuilder.build(AppThemePreset.midnight),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AppAmbientPage(
            shareBackground: true,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: ThemeSettingsScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(ThemeSettingsScreen));
    final l10n = AppLocalizations.of(context);
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text(l10n.themeBackgroundControlTitle),
      250,
      scrollable: scrollable,
    );
    final options = find
        .byWidgetPredicate(
          (widget) =>
              widget is Wrap &&
              widget.children.length == AppBackgroundTone.values.length &&
              widget.children.every((child) => child is Tooltip),
        )
        .first;
    await tester.ensureVisible(options);
    await tester.pumpAndSettle();
    expect(tester.getSize(options).height, lessThanOrEqualTo(51));
    expect(
      tester.getTopLeft(options).dy,
      greaterThan(
        tester.getBottomLeft(find.text(l10n.themeBackgroundControlSubtitle)).dy,
      ),
    );
    final chips = find.descendant(of: options, matching: find.byType(InkWell));
    await tester.tap(chips.at(2));
    await tester.pumpAndSettle();
    expect(provider.backgroundTone, AppBackgroundTone.ocean);

    final lastItem = find.text(l10n.themeNoSavedThemesSubtitle);
    await tester.scrollUntilVisible(lastItem, 300, scrollable: scrollable);
    await tester.drag(scrollable, const Offset(0, -850));
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(lastItem).dy, lessThanOrEqualTo(850 - 80));
    expect(tester.takeException(), isNull);
  });
}
