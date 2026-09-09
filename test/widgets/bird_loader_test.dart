import 'package:fly_player/widgets/common/bird_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('BirdLoader 循环动画无异常', (tester) async {
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
    // 跨越多个相位采样（后退 / 成茧 / 扑翼 / 飞离）
    for (var i = 0; i < 8; i++) {
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
}
