import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/playback/desktop_player_hover_overlays.dart';

void main() {
  Future<void> pumpLayer(
    WidgetTester tester,
    ValueNotifier<PlayerHoverOverlaySnapshot> snapshot,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                const ColoredBox(color: Colors.black),
                PlayerHoverOverlayLayer(
                  snapshot: snapshot,
                  contentBuilder: (kind, size, snapshot) {
                    final isSettings = kind == PlayerHoverOverlayKind.settings;
                    return PlayerHoverOverlayContent(
                      width: isSettings
                          ? (size.width * 0.30).clamp(360.0, 410.0).toDouble()
                          : 164,
                      child: SizedBox(
                        width: double.infinity,
                        height: double.infinity,
                        child: Text(
                          kind.name,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    );
                  },
                  onPanelEnter: () {},
                  onPanelExit: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('无弹层快照时不渲染任何内容', (tester) async {
    final snapshot = ValueNotifier<PlayerHoverOverlaySnapshot>(
      const PlayerHoverOverlaySnapshot(),
    );
    await pumpLayer(tester, snapshot);
    expect(find.text('settings'), findsNothing);
    expect(find.byType(DesktopHoverGlass), findsNothing);
  });

  testWidgets('快照变化直接驱动重建（全屏路由下 setState 刷不到的场景）', (tester) async {
    final snapshot = ValueNotifier<PlayerHoverOverlaySnapshot>(
      const PlayerHoverOverlaySnapshot(),
    );
    await pumpLayer(tester, snapshot);

    snapshot.value = const PlayerHoverOverlaySnapshot(
      kind: PlayerHoverOverlayKind.speed,
      visible: true,
      anchor: Rect.fromLTWH(300, 500, 32, 32),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DesktopHoverGlass), findsOneWidget);
    expect(find.text('speed'), findsOneWidget);
  });

  testWidgets('设置悬浮卡四边留边：不贴窗口边、底边悬于控制条上方', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final snapshot = ValueNotifier<PlayerHoverOverlaySnapshot>(
      const PlayerHoverOverlaySnapshot(),
    );
    await pumpLayer(tester, snapshot);

    // 锚点取底栏音轨按钮附近：设置卡应在锚点位置原位放大（水平覆盖锚点）。
    const anchorDx = 1240.0;
    snapshot.value = const PlayerHoverOverlaySnapshot(
      kind: PlayerHoverOverlayKind.settings,
      visible: true,
      anchor: Rect.fromLTWH(anchorDx - 16, 800, 32, 32),
    );
    await tester.pumpAndSettle();

    final window = tester.getSize(find.byType(SizedBox).first);
    final glass = tester.getRect(find.byType(DesktopHoverGlass));

    expect(glass.top, 76);
    expect(glass.bottom, window.height - 84);
    expect(glass.left, greaterThanOrEqualTo(20), reason: '左缘至少留 20 边距');
    expect(glass.right, lessThanOrEqualTo(window.width - 20), reason: '右缘至少留 20 边距');
    expect(glass.left, lessThanOrEqualTo(anchorDx), reason: '设置卡应覆盖锚点（原位放大）');
    expect(glass.right, greaterThanOrEqualTo(anchorDx), reason: '设置卡应覆盖锚点（原位放大）');
  });

  testWidgets('可见性翻转驱动淡出，随后清空种类', (tester) async {
    final snapshot = ValueNotifier<PlayerHoverOverlaySnapshot>(
      const PlayerHoverOverlaySnapshot(
        kind: PlayerHoverOverlayKind.settings,
        visible: true,
      ),
    );
    await pumpLayer(tester, snapshot);
    expect(find.byType(DesktopHoverGlass), findsOneWidget);

    snapshot.value = snapshot.value.copyWith(visible: false);
    await tester.pumpAndSettle();
    // 动画结束后内容仍挂载但透明且不可命中，等待种类清空后卸载。
    snapshot.value = const PlayerHoverOverlaySnapshot();
    await tester.pumpAndSettle();
    expect(find.byType(DesktopHoverGlass), findsNothing);
  });
}
