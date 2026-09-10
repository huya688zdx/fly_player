import 'package:fly_player/ui/main_navigation_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reserves floating bottom navigation space without safe area', () {
    expect(MainNavigationMetrics.contentBottomInset(0), 72);
  });

  test('reserves floating bottom navigation space with safe area', () {
    expect(MainNavigationMetrics.contentBottomInset(24), 88);
  });

  test('底部导航扩大点击宽度并保留两侧边距', () {
    expect(MainNavigationMetrics.barHeight, greaterThanOrEqualTo(48));
    expect(MainNavigationMetrics.barWidthFor(384), 352);
    expect(MainNavigationMetrics.barWidthFor(800), 360);
    expect(MainNavigationMetrics.barWidthFor(240), 208);
    expect(MainNavigationMetrics.barWidthFor(24), 0);
  });
}
