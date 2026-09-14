import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/playback/player_controls_auto_hide.dart';

void main() {
  testWidgets('a held seek gesture stays interactive beyond the hide delay', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _InteractionHarness()));
    final state = tester.state<_InteractionHarnessState>(
      find.byType(_InteractionHarness),
    );
    await tester.pump(const Duration(seconds: 2));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Slider)),
    );
    await gesture.moveBy(const Offset(50, 0));
    // A playback state notification can attempt to rearm the timer mid-drag.
    state.autoHide.schedule();
    await tester.pump(const Duration(seconds: 4));
    expect(state.visible, isTrue);
    await gesture.moveBy(const Offset(50, 0));
    await gesture.up();
    expect(state.seeks, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(state.visible, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(state.visible, isFalse);
  });

  testWidgets(
    'surface taps still hide visible controls and reveal hidden controls',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _InteractionHarness()));
      final state = tester.state<_InteractionHarnessState>(
        find.byType(_InteractionHarness),
      );
      await tester.tapAt(const Offset(100, 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(state.visible, isFalse);
      await tester.tapAt(const Offset(100, 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(state.visible, isTrue);
      await tester.pump(const Duration(seconds: 3));
      expect(state.visible, isFalse);
    },
  );

  testWidgets('only the last released or cancelled contact restarts hiding', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _InteractionHarness()));
    final state = tester.state<_InteractionHarnessState>(
      find.byType(_InteractionHarness),
    );
    state.autoHide.pointerDown(10);
    state.autoHide.pointerDown(11);
    state.autoHide.pointerEnded(10);
    await tester.pump(const Duration(seconds: 4));
    expect(state.visible, isTrue);
    state.autoHide.pointerEnded(11);
    await tester.pump(const Duration(seconds: 3));
    expect(state.visible, isFalse);
  });

  testWidgets('a cancelled seek releases the hold', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _InteractionHarness()));
    final state = tester.state<_InteractionHarnessState>(
      find.byType(_InteractionHarness),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Slider)),
    );
    await gesture.moveBy(const Offset(50, 0));
    await tester.pump(const Duration(seconds: 4));
    expect(state.visible, isTrue);
    await gesture.cancel();
    await tester.pump(const Duration(seconds: 3));
    expect(state.visible, isFalse);
  });
}

class _InteractionHarness extends StatefulWidget {
  const _InteractionHarness();

  @override
  State<_InteractionHarness> createState() => _InteractionHarnessState();
}

class _InteractionHarnessState extends State<_InteractionHarness> {
  bool visible = true;
  int seeks = 0;
  late final PlayerControlsAutoHide autoHide = PlayerControlsAutoHide(
    delay: const Duration(milliseconds: 2800),
    canHide: () => mounted && visible,
    onHide: () => setState(() => visible = false),
  );

  @override
  void initState() {
    super.initState();
    autoHide.schedule();
  }

  @override
  void dispose() {
    autoHide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Listener(
      onPointerDown: (event) => autoHide.pointerDown(event.pointer),
      onPointerUp: (event) => autoHide.pointerEnded(event.pointer),
      onPointerCancel: (event) => autoHide.pointerEnded(event.pointer),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () {},
        onTap: () {
          setState(() => visible = !visible);
          if (visible) {
            autoHide.schedule();
          } else {
            autoHide.cancel();
          }
        },
        child: Center(
          child: IgnorePointer(
            ignoring: !visible,
            child: SizedBox(
              height: 48,
              child: Slider(
                value: 0.5,
                onChanged: (_) {},
                onChangeEnd: (_) => seeks++,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
