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
    // 跨越多个相位采样（盘旋 / 悬停 / 飞离 / 归来）
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
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('logo 品牌配色', (tester) async {
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
