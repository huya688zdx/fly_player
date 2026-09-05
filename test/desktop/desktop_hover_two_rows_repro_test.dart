import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/desktop.dart';

// Repro investigation for "hover one spot, two adjacent rows both lit":
// while an animation (settings entrance reveal / sub-page squeeze / scroll)
// moves rows under a parked pointer, the hover state must self-heal so that
// at most one row is lit. The shift is triggered through the shared notifier
// directly (NO synthetic pointer events), which is exactly what happens in
// the real app: the physical pointer stays put while content reflows.
void main() {
  setUp(() {
    DesktopPointerPosition.debugResetForTest();
  });

  // Flipping `shifted` animates both rows up by 60px over 320ms (settings
  // reveal / squeeze moving rows onto a parked pointer).
  Widget harness(ValueNotifier<bool> shifted) {
    Widget row(int index) {
      return DesktopHoverRegion(
        key: ValueKey<String>('row-$index'),
        onTap: () {},
        builder: (context, hovering) => ColoredBox(
          key: ValueKey<String>('row-$index-box'),
          color: hovering ? Colors.red : Colors.blue,
          child: const SizedBox(width: 300, height: 60),
        ),
      );
    }

    return MaterialApp(
      home: DesktopPointerPositionTracker(
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ValueListenableBuilder<bool>(
              valueListenable: shifted,
              builder: (context, value, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: value ? -60 : 0),
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      builder: (context, offset, child) => Transform.translate(
                        offset: Offset(0, offset),
                        child: child,
                      ),
                      child: Column(children: <Widget>[row(0), row(1)]),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Color colorOf(WidgetTester tester, String key) =>
      tester.widget<ColoredBox>(find.byKey(ValueKey<String>(key))).color;

  testWidgets('pointer moving between adjacent rows lights at most one', (
    tester,
  ) async {
    final shifted = ValueNotifier<bool>(false);
    addTearDown(shifted.dispose);
    await tester.pumpWidget(harness(shifted));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    // Row 0: y 0..60, row 1: y 60..120. Pointer starts in row 0.
    await gesture.addPointer(location: const Offset(150, 30));
    addTearDown(gesture.removePointer);
    await gesture.moveTo(const Offset(150, 30));
    await tester.pump();
    expect(colorOf(tester, 'row-0-box'), Colors.red);
    expect(colorOf(tester, 'row-1-box'), Colors.blue);

    await gesture.moveTo(const Offset(150, 90));
    await tester.pump();
    expect(
      colorOf(tester, 'row-0-box'),
      Colors.blue,
      reason: 'row 0 must clear',
    );
    expect(
      colorOf(tester, 'row-1-box'),
      Colors.red,
      reason: 'row 1 must light',
    );
  });

  testWidgets(
    'content shifts under parked pointer: old row clears, row under pointer lights',
    (tester) async {
      final shifted = ValueNotifier<bool>(false);
      addTearDown(shifted.dispose);
      await tester.pumpWidget(harness(shifted));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      // Pointer parked at y=90: initially inside row 1 (0..120).
      await gesture.addPointer(location: const Offset(150, 90));
      addTearDown(gesture.removePointer);
      await gesture.moveTo(const Offset(150, 90));
      await tester.pumpAndSettle();
      expect(colorOf(tester, 'row-1-box'), Colors.red);

      // Pointer does NOT move (no pointer events from here on): flip the
      // notifier directly. Rows animate up 60px, from (0..120) to (-60..60);
      // pointer y=90 ends up OUTSIDE both rows, so both must clear
      // (frame-callback self-heal) — never two rows lit.
      shifted.value = true;
      for (var i = 0; i < 24; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final r0 = colorOf(tester, 'row-0-box');
        final r1 = colorOf(tester, 'row-1-box');
        final lit = (r0 == Colors.red ? 1 : 0) + (r1 == Colors.red ? 1 : 0);
        expect(
          lit,
          lessThanOrEqualTo(1),
          reason: 'frame $i has multiple rows lit: row0=$r0 row1=$r1',
        );
      }
      await tester.pumpAndSettle();
      expect(
        colorOf(tester, 'row-0-box'),
        Colors.blue,
        reason: 'rows moved away from the parked pointer',
      );
      expect(
        colorOf(tester, 'row-1-box'),
        Colors.blue,
        reason: 'rows moved away from the parked pointer',
      );
    },
  );
}
