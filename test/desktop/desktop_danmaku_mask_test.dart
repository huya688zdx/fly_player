import 'package:fly_player/desktop/playback/desktop_danmaku_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
