import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/widgets/detail/detail_loading_skeleton.dart';

void main() {
  testWidgets('详情加载骨架在短高度横屏不发生纵向溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 853));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: DetailLoadingSkeleton()));

    expect(tester.takeException(), isNull);
  });
}
