import 'package:fly_player/ui/main_navigation_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reserves floating bottom navigation space without safe area', () {
    expect(MainNavigationMetrics.contentBottomInset(0), 80);
  });

  test('reserves floating bottom navigation space with safe area', () {
    expect(MainNavigationMetrics.contentBottomInset(24), 96);
  });

  test('底部导航保持紧凑居中并为极窄屏保留边距', () {
    expect(MainNavigationMetrics.barWidthFor(384), 236);
    expect(MainNavigationMetrics.barWidthFor(800), 276);
    expect(MainNavigationMetrics.barWidthFor(240), 208);
    expect(MainNavigationMetrics.barWidthFor(24), 0);
  });
}
