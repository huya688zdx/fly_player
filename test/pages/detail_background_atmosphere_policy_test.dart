import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('电影、系列与季详情正文不以不透明底色遮住动态取色背景', () {
    const detailPagePaths = <String>[
      'lib/pages/play_detail_page.dart',
      'lib/pages/tv_detail_page.dart',
      'lib/pages/tv_season_detail_page.dart',
    ];

    for (final path in detailPagePaths) {
      final source = File(path).readAsStringSync();

      expect(
        source,
        isNot(contains('color: colors.backgroundBase')),
        reason: '$path 的正文仍会盖住动态取色晕染',
      );
    }
  });
}
