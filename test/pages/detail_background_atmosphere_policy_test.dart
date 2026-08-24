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

  test('季详情只由共享沉浸背景绘制海报与正文交界', () {
    final source = File(
      'lib/pages/tv_season_detail_page.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('final heroFogShadow =')));
    expect(
      source,
      isNot(contains('height: topContentInset + 10 + pullDownShift')),
      reason: '季详情仍在共享 ImmersiveDetailBackground 之外重复绘制交界阴影',
    );
  });

  test('季详情使用当前海报图片启用动态取色', () {
    final source = File(
      'lib/pages/tv_season_detail_page.dart',
    ).readAsStringSync();

    expect(source, contains('imageUrl: dynamicThemeImageUrl'));
    expect(source, contains('imageHeaders: dynamicThemeImages.headers'));
    expect(source, contains('enabled: dynamicThemeEnabled'));
    expect(source, isNot(contains('enabled: false')));
  });
}
