import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/danmaku_dynamic_occlusion.dart';
import '../../models/danmaku_settings.dart';
import 'local_danmaku_item.dart';

class LocalDanmakuPainter<T> extends CustomPainter {
  static const int _perfLogIntervalMs = 2000;
  final List<LocalDanmakuItem<T>> scrollItems;
  final List<LocalDanmakuItem<T>> staticItems;
  final ValueListenable<int> timelineListenable;
  final double devicePixelRatio;
  final double opacity;
  final ui.Image? maskImage;
  final double displayAreaRatio;
  final double captureAreaRatio;
  final DanmakuDynamicOcclusionRect? occlusionRect;
  final String occlusionMode;
  final ValueChanged<int>? onPaintElapsedUs;

  static final Paint _paint = Paint();
  static final Paint _maskPaint = Paint()
    ..blendMode = BlendMode.dstOut
    ..filterQuality = FilterQuality.low;
  static final Stopwatch _paintStopwatch = Stopwatch();
  static int _lastPerfLogWallClockMs = 0;

  LocalDanmakuPainter({
    required Listenable repaint,
    required this.scrollItems,
    required this.staticItems,
    required this.timelineListenable,
    required this.devicePixelRatio,
    required this.opacity,
    required this.maskImage,
    required this.displayAreaRatio,
    required this.captureAreaRatio,
    required this.occlusionRect,
    required this.occlusionMode,
    this.onPaintElapsedUs,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final wallClockMs = DateTime.now().millisecondsSinceEpoch;
    final shouldLogPerf =
        wallClockMs - _lastPerfLogWallClockMs >= _perfLogIntervalMs;
    final shouldMeasurePerf = shouldLogPerf || onPaintElapsedUs != null;
    if (shouldMeasurePerf) {
      _paintStopwatch
        ..reset()
        ..start();
    }
    final timelineMs = timelineListenable.value;
    final hasMask = maskImage != null;
    _paint.colorFilter = _resolveOpacityFilter(opacity);
    var activeScrollCount = 0;
    var activeStaticCount = 0;
    var visibleScrollCount = 0;
    var offRightScrollCount = 0;
    var offLeftTailScrollCount = 0;
    if (hasMask) {
      canvas.saveLayer(Offset.zero & size, Paint());
    }
    for (final item in scrollItems) {
      if (item.isExpired(timelineMs, size)) continue;
      activeScrollCount += 1;
      final x = item.xFor(size, timelineMs);
      final y = item.yFor(size);
      if (x >= size.width) {
        offRightScrollCount += 1;
        continue;
      } else if (x + item.width <= 0) {
        offLeftTailScrollCount += 1;
        continue;
      } else {
        visibleScrollCount += 1;
      }
      _paintImage(canvas, item, x, y);
    }
    for (final item in staticItems) {
      if (item.isExpired(timelineMs, size)) continue;
      activeStaticCount += 1;
      final x = item.xFor(size, timelineMs);
      final y = item.yFor(size);
      _paintImage(canvas, item, x, y);
    }
    final currentMask = maskImage;
    if (currentMask != null) {
      final destinationCoverage = clampDanmakuAreaRatio(displayAreaRatio);
      final sourceCoverage = resolveDanmakuMaskSourceCoverageRatio(
        displayAreaRatio: displayAreaRatio,
        captureAreaRatio: captureAreaRatio,
      );
      final src = Rect.fromLTWH(
        0,
        0,
        currentMask.width.toDouble(),
        currentMask.height.toDouble() * sourceCoverage,
      );
      final dst = Rect.fromLTWH(
        0,
        0,
        size.width,
        size.height * destinationCoverage,
      );
      canvas.drawImageRect(currentMask, src, dst, _maskPaint);
      canvas.restore();
    }
    if (shouldMeasurePerf) {
      _paintStopwatch.stop();
      final elapsedUs = _paintStopwatch.elapsedMicroseconds;
      onPaintElapsedUs?.call(elapsedUs);
    }
    if (shouldLogPerf) {
      _lastPerfLogWallClockMs = wallClockMs;
      debugPrint(
        '[DANMAKU][PAINT] elapsedUs=${_paintStopwatch.elapsedMicroseconds} '
        'activeScroll=$activeScrollCount activeStatic=$activeStaticCount '
        'visibleScroll=$visibleScrollCount offRight=$offRightScrollCount offLeftTail=$offLeftTailScrollCount '
        'total=${activeScrollCount + activeStaticCount} '
        'mask=$hasMask size=${size.width.toInt()}x${size.height.toInt()} '
        'opacity=${opacity.toStringAsFixed(3)} dpr=${devicePixelRatio.toStringAsFixed(2)}',
      );
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

  ColorFilter? _resolveOpacityFilter(double opacity) {
    if (opacity >= 0.999) {
      return null;
    }
    final alpha = (opacity.clamp(0.0, 1.0) * 255).round();
    return ColorFilter.mode(
      Color.fromARGB(alpha, 255, 255, 255),
      BlendMode.modulate,
    );
  }

  @override
  bool shouldRepaint(covariant LocalDanmakuPainter<T> oldDelegate) {
    return oldDelegate.scrollItems != scrollItems ||
        oldDelegate.staticItems != staticItems ||
        oldDelegate.devicePixelRatio != devicePixelRatio ||
        oldDelegate.opacity != opacity ||
        oldDelegate.maskImage != maskImage ||
        oldDelegate.displayAreaRatio != displayAreaRatio ||
        oldDelegate.captureAreaRatio != captureAreaRatio ||
        oldDelegate.occlusionRect != occlusionRect ||
        oldDelegate.occlusionMode != occlusionMode;
  }
}
