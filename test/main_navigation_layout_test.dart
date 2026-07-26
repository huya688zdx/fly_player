import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main navigation extends page content behind floating bottom bar', () {
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

    expect(buildSource, contains('extendBody: true'));
    expect(buildSource, contains('_LiquidGlassBottomNavigation'));
  });
}
