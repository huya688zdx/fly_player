import 'package:fly_player/ui/main_navigation_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reserves floating bottom navigation space without safe area', () {
    expect(MainNavigationMetrics.contentBottomInset(0), 96);
  });

  test('reserves floating bottom navigation space with safe area', () {
    expect(MainNavigationMetrics.contentBottomInset(24), 112);
  });
}
