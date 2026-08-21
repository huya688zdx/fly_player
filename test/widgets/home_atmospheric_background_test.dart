import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/widgets/app_atmospheric_background.dart';

void main() {
  testWidgets('首页动态背景保持暗中性底并叠加三种独立取色光晕', (tester) async {
    const warmRed = Color(0xFFD85867);
    const coldBlue = Color(0xFF4B7FD8);
    const amber = Color(0xFFD49A32);
    final base = AppThemePalette.colorsFor(AppThemePreset.midnight);
    final dynamic = base.copyWith(
      backgroundBase: const Color(0xFF3E5F37),
      accent: warmRed,
      selection: coldBlue,
      link: amber,
    );
    final palette = AppAtmospherePalette.resolve(
      baseColors: base,
      effectiveColors: dynamic,
      hasDynamicTheme: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AppAtmosphericBackground(
          palette: palette,
          child: const SizedBox.expand(),
        ),
      ),
    );

    expect(palette.base.computeLuminance(), lessThan(.06));
    expect(palette.accentGlow, warmRed.withValues(alpha: .22));
    expect(palette.selectionGlow, coldBlue.withValues(alpha: .17));
    expect(palette.linkGlow, amber.withValues(alpha: .13));
    expect(
      find.byKey(const ValueKey<String>('app-atmosphere-accent')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('app-atmosphere-selection')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('app-atmosphere-link')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('未进入动态取色时仍保留主题自带的克制多色氛围', (tester) async {
    final base = AppThemePalette.colorsFor(AppThemePreset.midnight);
    final palette = AppAtmospherePalette.resolve(
      baseColors: base,
      effectiveColors: base,
      hasDynamicTheme: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AppAtmosphericBackground(
          palette: palette,
          child: const SizedBox.expand(),
        ),
      ),
    );

    expect(palette.base, base.backgroundBase);
    expect(palette.accentGlow.a, greaterThan(0));
    expect(palette.selectionGlow.a, greaterThan(0));
    expect(palette.linkGlow.a, greaterThan(0));
    expect(
      find.byKey(const ValueKey<String>('app-atmosphere-accent')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('app-atmosphere-selection')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('app-atmosphere-link')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  test('选中图标按钮使用低饱和填充和协调前景，而不是直铺原始取色', () {
    final base = AppThemePalette.colorsFor(AppThemePreset.midnight);
    final colors = base.copyWith(selection: const Color(0xFF35C8F2));
    final active = AppTonalControlPalette.resolve(colors: colors, active: true);
    final inactive = AppTonalControlPalette.resolve(
      colors: colors,
      active: false,
    );

    expect(active.fill, isNot(colors.selection));
    expect(active.foreground, isNot(colors.selection));
    expect(active.border, isNot(colors.selection));
    expect(inactive.foreground, colors.textSecondary);
  });
}
