import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_background_policy.dart';

void main() {
  test('手机横屏使用竖版封面并限制解码尺寸与预取范围', () {
    final spec = PosterBrowseBackgroundPolicy.resolve(
      logicalSize: const Size(844, 390),
      devicePixelRatio: 3,
    );

    expect(spec.usePosterImages, isTrue);
    expect(spec.fit, BoxFit.contain);
    expect(spec.alignment, Alignment.centerRight);
    expect(spec.requestWidth, 720);
    expect(spec.cacheWidth, 720);
    expect(spec.prefetchRadius, 1);
  });

  test('大屏使用横版背景并按视口限制解码宽度', () {
    final spec = PosterBrowseBackgroundPolicy.resolve(
      logicalSize: const Size(1920, 1080),
      devicePixelRatio: 2,
    );

    expect(spec.usePosterImages, isFalse);
    expect(spec.fit, BoxFit.cover);
    expect(spec.alignment, Alignment.center);
    expect(spec.requestWidth, 1440);
    expect(spec.cacheWidth, 1440);
    expect(spec.prefetchRadius, 2);
  });

  test('手机竖屏仍使用横版背景且解码宽度不会无限放大', () {
    final spec = PosterBrowseBackgroundPolicy.resolve(
      logicalSize: const Size(390, 844),
      devicePixelRatio: 3,
    );

    expect(spec.usePosterImages, isFalse);
    expect(spec.cacheWidth, 1170);
    expect(spec.prefetchRadius, 2);
  });
}
