import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'local_danmaku_item.dart';

class LocalDanmakuPainter<T> extends CustomPainter {
  final List<LocalDanmakuItem<T>> scrollItems;
  final List<LocalDanmakuItem<T>> staticItems;
  final ValueListenable<int> timelineListenable;
  final double devicePixelRatio;
  final ui.Image? maskImage;
  final double maskCoverageRatio;

  static final Paint _paint = Paint();
  static final Paint _maskPaint = Paint()
    ..blendMode = BlendMode.dstOut
    ..filterQuality = FilterQuality.low;

  LocalDanmakuPainter({
    required Listenable repaint,
    required this.scrollItems,
    required this.staticItems,
    required this.timelineListenable,
    required this.devicePixelRatio,
    required this.maskImage,
    required this.maskCoverageRatio,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final timelineMs = timelineListenable.value;
    final hasMask = maskImage != null;
    if (hasMask) {
      canvas.saveLayer(Offset.zero & size, Paint());
    }
    for (final item in scrollItems) {
      if (item.isExpired(timelineMs, size)) continue;
      final x = item.xFor(size, timelineMs);
      final y = item.yFor(size);
      _paintImage(canvas, item, x, y);
    }
    for (final item in staticItems) {
      if (item.isExpired(timelineMs, size)) continue;
      final x = item.xFor(size, timelineMs);
      final y = item.yFor(size);
      _paintImage(canvas, item, x, y);
    }
    final currentMask = maskImage;
    if (currentMask != null) {
      final src = Rect.fromLTWH(
        0,
        0,
        currentMask.width.toDouble(),
        currentMask.height.toDouble(),
      );
      final dst = Rect.fromLTWH(
        0,
        0,
        size.width,
        size.height * maskCoverageRatio.clamp(0.1, 1.0),
      );
      canvas.drawImageRect(currentMask, src, dst, _maskPaint);
      canvas.restore();
    }
  }

  void _paintImage(
    Canvas canvas,
    LocalDanmakuItem<T> item,
    double dx,
    double dy,
  ) {
    if (devicePixelRatio == 1.0) {
      canvas.drawImage(item.image, Offset(dx, dy), _paint);
      return;
    }
    final src = Rect.fromLTWH(
      0,
      0,
      item.image.width.toDouble(),
      item.image.height.toDouble(),
    );
    final dst = Rect.fromLTWH(dx, dy, item.width, item.height);
    canvas.drawImageRect(item.image, src, dst, _paint);
  }

  @override
  bool shouldRepaint(covariant LocalDanmakuPainter<T> oldDelegate) {
    return oldDelegate.scrollItems != scrollItems ||
        oldDelegate.staticItems != staticItems ||
        oldDelegate.devicePixelRatio != devicePixelRatio ||
        oldDelegate.maskImage != maskImage ||
        oldDelegate.maskCoverageRatio != maskCoverageRatio;
  }
}
