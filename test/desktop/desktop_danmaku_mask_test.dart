import 'dart:io';
import 'package:fly_player/danmaku/models/danmaku_settings.dart';
import 'package:fly_player/desktop/playback/desktop_player_panels.dart';
import 'package:fly_player/desktop/playback/desktop_danmaku_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Windows lite 隐藏 AI 遮挡入口并保留普通弹幕设置', (tester) async {
    if (!Platform.isWindows) return;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopDanmakuSettingsPanel(
            settings: DanmakuSettings.defaults,
            onChanged: (_) async {},
          ),
        ),
      ),
    );
    expect(find.text('滚动弹幕'), findsOneWidget);
    expect(
      find.text('主体穿透遮挡'),
      const bool.fromEnvironment('FLY_WINDOWS_AI_MASK', defaultValue: true)
          ? findsOneWidget
          : findsNothing,
    );
  });

  test('AI 弹幕蒙版按视频 cover 区域裁剪左右源像素', () {
    final rects = resolveDesktopDanmakuMaskRects(
      frameSize: const Size(1920, 1080),
      maskSize: const Size(320, 180),
      canvasSize: const Size(400, 400),
      fit: BoxFit.cover,
    );

    expect(rects.source, const Rect.fromLTWH(70, 0, 180, 180));
    expect(rects.destination, const Rect.fromLTWH(0, 0, 400, 400));
  });
}
