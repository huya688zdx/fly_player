import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home feed uses clamping physics to avoid top stretch overscroll', () {
    final source = File(
      'lib/screens/media_list_screen_widgets.dart',
    ).readAsStringSync();

    final refreshIndex = source.indexOf('return RefreshIndicator(');
    expect(refreshIndex, isNonNegative);

    final homeFeedSource = source.substring(
      refreshIndex,
      source.indexOf('  Widget _buildHomeSection', refreshIndex),
    );

    expect(homeFeedSource, contains('ClampingScrollPhysics'));
    expect(homeFeedSource, isNot(contains('ReducedOverscrollPhysics')));
    expect(homeFeedSource, isNot(contains('BouncingScrollPhysics')));
  });
}
