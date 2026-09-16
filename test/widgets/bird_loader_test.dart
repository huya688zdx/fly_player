import 'dart:ui' as ui;

import 'package:fly_player/widgets/common/bird_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('BirdLoader 循环动画无异常', (tester) async {
    // 直接解码正式资源，避免 errorBuilder 回退后仍把资源损坏判为通过。
    await tester.runAsync(() async {
      final data = await rootBundle.load(
        'assets/refresh/shoujo_bird_loading.webp',
      );
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      try {
        expect(codec.frameCount, greaterThan(1));
        expect(codec.repetitionCount, -1);
        var duration = Duration.zero;
        for (var i = 0; i < codec.frameCount; i++) {
          final frame = await codec.getNextFrame();
          duration += frame.duration;
          expect(frame.image.width, 512);
          expect(frame.image.height, 512);
          frame.image.dispose();
        }
        expect(duration, const Duration(milliseconds: 8700));
      } finally {
        codec.dispose();
      }
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: BirdLoader(size: 96))),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/refresh/shoujo_bird_loading.webp',
    );
    // 覆盖两轮完整时序（伸手 / 自抱 / 成茧 / 扑翼 / 飞离）。
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 900));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduce-motion 下定格悬停帧且不动画', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(body: Center(child: BirdLoader(size: 64))),
        ),
      ),
    );
    await tester.pump();
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/refresh/shoujo_bird_loading_static.png',
    );
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('logo 样式保持兼容', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: ColoredBox(
          color: Color(0xFF09111C),
          child: BirdLoader(size: 32, style: BirdLoaderStyle.logo),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('BirdGlyph 使用青鸟短循环并保留尺寸颜色和静态模式', (tester) async {
    await tester.runAsync(() async {
      final data = await rootBundle.load('assets/refresh/bluebird_glyph.webp');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      try {
        expect(codec.frameCount, greaterThan(1));
        expect(codec.repetitionCount, -1);
        var duration = Duration.zero;
        for (var i = 0; i < codec.frameCount; i++) {
          final frame = await codec.getNextFrame();
          duration += frame.duration;
          expect(frame.image.width, 128);
          expect(frame.image.height, 128);
          frame.image.dispose();
        }
        expect(duration, const Duration(milliseconds: 600));
      } finally {
        codec.dispose();
      }
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: BirdGlyph(color: Colors.white)),
      ),
    );
    var image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/refresh/bluebird_glyph.webp',
    );
    expect(tester.getSize(find.byType(BirdGlyph)), const Size(20, 20));
    expect(image.color, Colors.white);
    expect(image.colorBlendMode, BlendMode.srcIn);
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(home: Center(child: BirdGlyph())),
      ),
    );
    image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/refresh/bluebird_glyph_static.png',
    );
    expect(image.color, isNull);
    expect(tester.takeException(), isNull);
  });
}
