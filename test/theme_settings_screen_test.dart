import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/providers/app_theme_provider.dart';
import 'package:fly_player/screens/theme_settings_screen.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/widgets/common/app_ambient_page.dart';

void main() {
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
