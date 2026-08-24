import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main navigation uses an opaque dock outside page content', () {
    final source = File('lib/main.dart').readAsStringSync();
    final stateStart = source.indexOf('class _MainNavigationState');
    expect(stateStart, isNonNegative);

    final buildStart = source.indexOf(
      'Widget build(BuildContext context)',
      stateStart,
    );
    expect(buildStart, isNonNegative);

    final buildSource = source.substring(
      buildStart,
      source.indexOf('class _LiquidGlassNavDestination', buildStart),
    );

    expect(buildSource, contains('extendBody: false'));
    expect(buildSource, contains('_LiquidGlassBottomNavigation'));

    final navigationSource = source.substring(
      source.indexOf('class _LiquidGlassBottomNavigation'),
    );
    expect(navigationSource, contains('MainNavigationMetrics.barHeight'));
    expect(navigationSource, contains('MainNavigationMetrics.barWidthFor'));
    expect(
      navigationSource,
      contains('MainNavigationMetrics.outerBottomPadding'),
    );
    expect(
      navigationSource,
      isNot(contains('ValueListenableBuilder<LiquidGlassLevel>')),
    );
    expect(
      navigationSource,
      contains('final selectedSurface = Color.alphaBlend'),
    );
    expect(
      navigationSource,
      isNot(contains('colors.navBarBackground.withValues')),
    );
    expect(
      navigationSource,
      isNot(contains('type: MaterialType.transparency')),
    );

    final homeSource = File(
      'lib/screens/media_list_screen_widgets.dart',
    ).readAsStringSync();
    expect(homeSource, contains('MainNavigationMetrics.contentBottomInset'));
  });
}
