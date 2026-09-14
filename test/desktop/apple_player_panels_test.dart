import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/playback/desktop_player_dialogs.dart';

void main() {
  testWidgets('iPhone player settings stay inside the safe area', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(568, 320);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(
      left: 44,
      right: 44,
      bottom: 21,
    );
    tester.view.padding = const FakeViewPadding(
      left: 44,
      right: 44,
      bottom: 21,
    );
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPadding);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => showPlayerOverlayPanel(
                  context,
                  builder: (_) =>
                      const SizedBox.expand(key: Key('settings-content')),
                  style: PlayerOverlayPanelStyle.sideDrawer,
                  barrierLabel: 'Close',
                ),
                child: const Text('Settings'),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byKey(const Key('settings-content')));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(299));
      expect(rect.left, greaterThanOrEqualTo(44));
      expect(rect.right, lessThanOrEqualTo(524));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
