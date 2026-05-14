import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class DanmakuImageDisposer {
  static const Duration _disposeDelay = Duration(milliseconds: 260);

  static void deferDispose(ui.Image? image) {
    if (image == null) return;
    Future<void>.delayed(_disposeDelay, image.dispose);
  }
}

class _DanmakuRasterCacheEntry {
  _DanmakuRasterCacheEntry({
    required this.image,
    required this.width,
    required this.height,
  });

  final ui.Image image;
  final double width;
  final double height;
  int refs = 0;
}

class DanmakuRasterizedAsset {
  const DanmakuRasterizedAsset({
    required this.image,
    required this.width,
    required this.height,
    required this.cacheKey,
  });

  final ui.Image image;
  final double width;
  final double height;
  final String cacheKey;
}

class DanmakuRasterCache {
  static const int _maxEntries = 180;
  static final LinkedHashMap<String, _DanmakuRasterCacheEntry> _entries =
      LinkedHashMap<String, _DanmakuRasterCacheEntry>();

  static DanmakuRasterizedAsset resolve({
    required String text,
    required Color color,
    required double fontSize,
    required int fontWeight,
    required double strokeWidth,
    required double lineHeight,
    required double devicePixelRatio,
  }) {
    final cacheKey = _buildCacheKey(
      text: text,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      strokeWidth: strokeWidth,
      lineHeight: lineHeight,
      devicePixelRatio: devicePixelRatio,
    );
    final existingEntry = _entries.remove(cacheKey);
    if (existingEntry != null) {
      existingEntry.refs += 1;
      _entries[cacheKey] = existingEntry;
      return DanmakuRasterizedAsset(
        image: existingEntry.image,
        width: existingEntry.width,
        height: existingEntry.height,
        cacheKey: cacheKey,
      );
    }

    final paragraph = LocalDanmakuItem._buildParagraph(
      text: text,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      lineHeight: lineHeight,
    );
    final horizontalPadding = LocalDanmakuItem._horizontalRasterPadding(
      fontSize,
      strokeWidth,
    );
    final verticalPadding = LocalDanmakuItem._verticalRasterPadding(
      fontSize,
      strokeWidth,
    );
    final width = paragraph.maxIntrinsicWidth + (horizontalPadding * 2.0);
    final height = paragraph.height + (verticalPadding * 2.0);
    final image = LocalDanmakuItem._recordImage(
      paragraph: paragraph,
      text: text,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      lineHeight: lineHeight,
      strokeWidth: strokeWidth,
      devicePixelRatio: devicePixelRatio,
      horizontalPadding: horizontalPadding,
      verticalPadding: verticalPadding,
    );
    paragraph.dispose();

    final nextEntry = _DanmakuRasterCacheEntry(
      image: image,
      width: width,
      height: height,
    )..refs = 1;
    _entries[cacheKey] = nextEntry;
    _trim();
    return DanmakuRasterizedAsset(
      image: image,
      width: width,
      height: height,
      cacheKey: cacheKey,
    );
  }

  static void release(String cacheKey, ui.Image image) {
    final entry = _entries[cacheKey];
    if (entry == null || !identical(entry.image, image)) {
      DanmakuImageDisposer.deferDispose(image);
      return;
    }
    if (entry.refs > 0) {
      entry.refs -= 1;
    }
    _trim();
  }

  static String _buildCacheKey({
    required String text,
    required Color color,
    required double fontSize,
    required int fontWeight,
    required double strokeWidth,
    required double lineHeight,
    required double devicePixelRatio,
  }) {
    return <Object>[
      text,
      color.toARGB32(),
      fontSize.toStringAsFixed(2),
      fontWeight,
      strokeWidth.toStringAsFixed(2),
      lineHeight.toStringAsFixed(2),
      devicePixelRatio.toStringAsFixed(2),
    ].join('|');
  }

  static void _trim() {
    if (_entries.length <= _maxEntries) {
      return;
    }
    final staleKeys = <String>[];
    for (final entry in _entries.entries) {
      if (entry.value.refs == 0) {
        staleKeys.add(entry.key);
      }
      if (_entries.length - staleKeys.length <= _maxEntries) {
        break;
      }
    }
    for (final key in staleKeys) {
      final removed = _entries.remove(key);
      if (removed != null) {
        DanmakuImageDisposer.deferDispose(removed.image);
      }
    }
  }
}

enum LocalDanmakuItemType { scroll, top, bottom }

class LocalDanmakuContentItem<T> {
  final String text;
  final Color color;
  final LocalDanmakuItemType type;
  final T? extra;

  const LocalDanmakuContentItem(
    this.text, {
    required this.color,
    required this.type,
    this.extra,
  });
}

class LocalDanmakuItem<T> {
  final LocalDanmakuContentItem<T> content;
  final double width;
  final double height;
  double trackPosition;
  final int startMs;
  final int durationMs;
  final ui.Image image;
  final String? rasterCacheKey;

  LocalDanmakuItem({
    required this.content,
    required this.width,
    required this.height,
    required this.trackPosition,
    required this.startMs,
    required this.durationMs,
    required this.image,
    this.rasterCacheKey,
  });

  bool get isScroll => content.type == LocalDanmakuItemType.scroll;
  bool get isTop => content.type == LocalDanmakuItemType.top;
  bool get isBottom => content.type == LocalDanmakuItemType.bottom;

  bool isExpired(int timelineMs, Size viewportSize) {
    final elapsedMs = timelineMs - startMs;
    if (elapsedMs < 0) return false;
    if (!isScroll) {
      return elapsedMs >= durationMs;
    }
    return xFor(viewportSize, timelineMs) <= -width;
  }

  double xFor(Size viewportSize, int timelineMs) {
    if (!isScroll) {
      return (viewportSize.width - width) / 2;
    }
    final elapsedMs = (timelineMs - startMs).clamp(0, durationMs);
    final progress = durationMs <= 0 ? 1.0 : elapsedMs / durationMs;
    return viewportSize.width - (progress * (viewportSize.width + width));
  }

  double yFor(Size viewportSize) {
    if (isBottom) {
      return viewportSize.height - trackPosition - height;
    }
    return trackPosition;
  }

  void dispose() {
    final cacheKey = rasterCacheKey;
    if (cacheKey != null) {
      DanmakuRasterCache.release(cacheKey, image);
      return;
    }
    DanmakuImageDisposer.deferDispose(image);
  }

  static LocalDanmakuItem<T> rasterize<T>({
    required LocalDanmakuContentItem<T> content,
    required double trackPosition,
    required int startMs,
    required int durationMs,
    required double fontSize,
    required int fontWeight,
    required double strokeWidth,
    required double lineHeight,
    required double devicePixelRatio,
  }) {
    final rasterAsset = DanmakuRasterCache.resolve(
      text: content.text,
      color: content.color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      lineHeight: lineHeight,
      strokeWidth: strokeWidth,
      devicePixelRatio: devicePixelRatio,
    );
    return LocalDanmakuItem<T>(
      content: content,
      width: rasterAsset.width,
      height: rasterAsset.height,
      trackPosition: trackPosition,
      startMs: startMs,
      durationMs: durationMs,
      image: rasterAsset.image,
      rasterCacheKey: rasterAsset.cacheKey,
    );
  }

  static ui.Paragraph _buildParagraph({
    required String text,
    required Color color,
    required double fontSize,
    required int fontWeight,
    required double lineHeight,
  }) {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textAlign: TextAlign.left,
              fontWeight: FontWeight.values[fontWeight],
              textDirection: TextDirection.ltr,
              maxLines: 1,
            ),
          )
          ..pushStyle(
            ui.TextStyle(color: color, fontSize: fontSize, height: lineHeight),
          )
          ..addText(text);

    return builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
  }

  static ui.Image _recordImage({
    required ui.Paragraph paragraph,
    required String text,
    required Color color,
    required double fontSize,
    required int fontWeight,
    required double lineHeight,
    required double strokeWidth,
    required double devicePixelRatio,
    required double horizontalPadding,
    required double verticalPadding,
  }) {
    final width = paragraph.maxIntrinsicWidth + (horizontalPadding * 2.0);
    final height = paragraph.height + (verticalPadding * 2.0);
    final offset = Offset(horizontalPadding, verticalPadding);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(devicePixelRatio);

    if (strokeWidth > 0) {
      final strokeBuilder =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(
                textAlign: TextAlign.left,
                fontWeight: FontWeight.values[fontWeight],
                textDirection: TextDirection.ltr,
                maxLines: 1,
              ),
            )
            ..pushStyle(
              ui.TextStyle(
                fontSize: fontSize,
                height: lineHeight,
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = strokeWidth
                  ..color = Colors.black,
              ),
            )
            ..addText(text);
      final strokeParagraph = strokeBuilder.build()
        ..layout(const ui.ParagraphConstraints(width: double.infinity));
      canvas.drawParagraph(strokeParagraph, offset);
      strokeParagraph.dispose();
    }

    canvas.drawParagraph(paragraph, offset);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      (width * devicePixelRatio).ceil(),
      (height * devicePixelRatio).ceil(),
    );
    picture.dispose();
    return image;
  }

  static double _horizontalRasterPadding(double fontSize, double strokeWidth) {
    return math.max(strokeWidth + 1.0, fontSize * 0.10);
  }

  static double _verticalRasterPadding(double fontSize, double strokeWidth) {
    return math.max(strokeWidth + 1.0, fontSize * 0.38);
  }
}
