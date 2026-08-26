import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main navigation floats over page content on a gradient scrim', () {
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

    // 内容延伸到导航条后方，底栏不再占用独立的实色横带。
    expect(buildSource, contains('extendBody: true'));
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

    // 托底是单层渐变（透明渐入 backgroundBase），不允许 BackdropFilter。
    expect(navigationSource, contains('LinearGradient'));
    expect(navigationSource, isNot(contains('BackdropFilter')));
    // 悬浮胶囊需要透明 Material 承载 InkResponse 水波纹。
    expect(navigationSource, contains('type: MaterialType.transparency'));
    // 选中块只靠填充色阶区分，不再有内层描边。
    final selectedChipStart = navigationSource.indexOf('// 选中块只靠填充色阶区分');
    expect(selectedChipStart, isNonNegative);
    final selectedChipSource = navigationSource.substring(
      selectedChipStart,
      navigationSource.indexOf('Row(', selectedChipStart),
    );
    expect(selectedChipSource, isNot(contains('Border.all')));

    final homeSource = File(
      'lib/screens/media_list_screen_widgets.dart',
    ).readAsStringSync();
    expect(homeSource, contains('MainNavigationMetrics.contentBottomInset'));

    // 设置页在主窗口下同样要为悬浮底栏预留滚动尾部留白。
    final settingsSource = File(
      'lib/screens/app_settings_screen.dart',
    ).readAsStringSync();
    expect(
      settingsSource,
      contains('MainNavigationMetrics.contentBottomInset'),
    );
  });
}
