import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

class DesktopDanmakuMask {
  const DesktopDanmakuMask({
    required this.image,
    required this.frameWidth,
    required this.frameHeight,
    required this.inferenceMs,
    required this.totalMs,
  });

  final ui.Image image;
  final int frameWidth;
  final int frameHeight;
  final int inferenceMs;
  final int totalMs;

  void dispose() => image.dispose();
}

/// Windows MNN 人物分割入口。模型固定使用 512×512；[outputWidth] 只控制回传
/// 蒙版尺寸，不改变模型输入。
abstract final class DesktopDanmakuSegmenter {
  static bool get isSupported =>
      Platform.isWindows &&
      const bool.fromEnvironment('FLY_WINDOWS_AI_MASK', defaultValue: true);

  static const MethodChannel _channel = MethodChannel(
    'fly_player/desktop_danmaku_segmentation',
  );

  static Future<DesktopDanmakuMask?> segment(
    Player player, {
    required int outputWidth,
  }) async {
    if (!isSupported) return null;
    final stopwatch = Stopwatch()..start();
    final state = player.state;
    final bgra = await player.screenshot(
      format: null,
      includeLibassSubtitles: false,
    );
    if (bgra == null || bgra.isEmpty) return null;
    final rawWidth = state.videoParams.w ?? state.width ?? 0;
    final rawHeight = state.videoParams.h ?? state.height ?? 0;
    final geometry = _matchRawGeometry(
      bgra.length,
      candidates: <(int, int)>[
        (rawWidth, rawHeight),
        (rawHeight, rawWidth),
        (state.width ?? 0, state.height ?? 0),
      ],
    );
    if (geometry == null) return null;
    final (width, height, stride) = geometry;
    final displayWidth = state.width ?? width;
    final displayHeight = state.height ?? height;
    final result = await _channel.invokeMapMethod<String, Object?>('segment', {
      'bgra': bgra,
      'width': width,
      'height': height,
      'stride': stride,
      'displayWidth': displayWidth,
      'displayHeight': displayHeight,
      'outputWidth': outputWidth.clamp(64, 512),
    });
    final maskWidth = result?['width'] as int? ?? 0;
    final maskHeight = result?['height'] as int? ?? 0;
    final rgba = result?['rgba'] as Uint8List?;
    if (maskWidth <= 0 ||
        maskHeight <= 0 ||
        rgba == null ||
        rgba.length != maskWidth * maskHeight * 4) {
      return null;
    }
    final image = await _decodeRgba(rgba, maskWidth, maskHeight);
    return DesktopDanmakuMask(
      image: image,
      frameWidth: displayWidth,
      frameHeight: displayHeight,
      inferenceMs: result?['inferenceMs'] as int? ?? 0,
      totalMs: stopwatch.elapsedMilliseconds,
    );
  }

  static (int, int, int)? _matchRawGeometry(
    int byteLength, {
    required List<(int, int)> candidates,
  }) {
    for (final (width, height) in candidates) {
      if (width <= 0 || height <= 0 || byteLength % height != 0) continue;
      final stride = byteLength ~/ height;
      if (stride >= width * 4 && stride <= width * 4 + 64) {
        return (width, height, stride);
      }
    }
    return null;
  }

  static Future<ui.Image> _decodeRgba(Uint8List rgba, int width, int height) {
    final result = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      result.complete,
    );
    return result.future;
  }
}
