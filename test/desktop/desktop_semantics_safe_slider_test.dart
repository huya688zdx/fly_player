import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/playback/desktop_semantics_safe_slider.dart';

void main() {
  const sliderKey = ValueKey<String>('safe-slider');

  Future<void> pumpSlider(
    WidgetTester tester, {
    required ValueChanged<double> onChanged,
    ValueChanged<double>? onChangeEnd,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            // 设置卡（Column crossAxisAlignment: start）给滑块的是有界松宽度
            // 约束——正是滑块宽度曾塌成 0 的场景，回归用。
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DesktopSemanticsSafeSlider(
                    key: sliderKey,
                    value: 0,
                    min: -10,
                    max: 10,
                    divisions: 200,
                    onChanged: onChanged,
                    onChangeEnd: onChangeEnd,
                    activeColor: const Color(0xFF6EA8FF),
                    inactiveColor: const Color(0x28FFFFFF),
                    semanticsLabel: '音频延迟',
                    semanticsValue: '0.0 秒',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('有界松约束下滑块占满可用宽度', (tester) async {
    await pumpSlider(tester, onChanged: (_) {});
    final box = tester.renderObject<RenderBox>(find.byKey(sliderKey));
    expect(box.size.width, 400);
    expect(box.size.height, 28);
  });

  testWidgets('按住横向拖动可更新并提交数值', (tester) async {
    double? changed;
    double? ended;
    await pumpSlider(
      tester,
      onChanged: (value) => changed = value,
      onChangeEnd: (value) => ended = value,
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(sliderKey)),
    );
    await gesture.moveBy(const Offset(200, 0));
    await gesture.up();
    await tester.pump();
    expect(changed, isNotNull);
    expect(ended, closeTo(10, 0.05));
  });
}
