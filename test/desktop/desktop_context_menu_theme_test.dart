import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/desktop_context_menu.dart';
import 'package:fly_player/desktop/desktop_floating_panel.dart';
import 'package:fly_player/theme/app_theme.dart';

void main() {
  testWidgets(
    'desktop menu inherits page-local runtime colors and cancels on Esc',
    (tester) async {
      const accent = Color(0xff32a867);
      var selected = false;
      await tester.pumpWidget(
        MaterialApp(
          home: AppRuntimeColorScope(
            colors: AppThemePalette.fallback.copyWith(accent: accent),
            hasRuntimeColors: true,
            child: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDesktopContextMenu(
                    context,
                    position: const Offset(20, 60),
                    entries: [
                      DesktopContextMenuEntry(
                        label: '选择',
                        icon: Icons.check,
                        onSelected: () => selected = true,
                      ),
                    ],
                  ),
                  child: const Text('菜单'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('菜单'));
      await tester.pumpAndSettle();
      expect(
        tester.element(find.byType(DesktopFloatingPanel)).appColors.accent,
        accent,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(DesktopFloatingPanel), findsNothing);
      expect(selected, false);
      await tester.tap(find.text('菜单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择'));
      await tester.pumpAndSettle();
      expect(selected, true);
      expect(find.byType(DesktopFloatingPanel), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
