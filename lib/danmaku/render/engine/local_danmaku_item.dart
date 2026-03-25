import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

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

  LocalDanmakuItem({
    required this.content,
    required this.width,
    required this.height,
    required this.trackPosition,
    required this.startMs,
    required this.durationMs,
    required this.image,
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
    image.dispose();
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
    final paragraph = _buildParagraph(
      text: content.text,
      color: content.color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      lineHeight: lineHeight,
    );
    final horizontalPadding = _horizontalRasterPadding(fontSize, strokeWidth);
    final verticalPadding = _verticalRasterPadding(fontSize, strokeWidth);
    final width = paragraph.maxIntrinsicWidth + (horizontalPadding * 2.0);
    final height = paragraph.height + (verticalPadding * 2.0);
    final image = _recordImage(
      paragraph: paragraph,
      text: content.text,
      color: content.color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      lineHeight: lineHeight,
      strokeWidth: strokeWidth,
      devicePixelRatio: devicePixelRatio,
      horizontalPadding: horizontalPadding,
      verticalPadding: verticalPadding,
    );
    paragraph.dispose();
    return LocalDanmakuItem<T>(
      content: content,
      width: width,
      height: height,
      trackPosition: trackPosition,
      startMs: startMs,
      durationMs: durationMs,
      image: image,
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
    return math.max(strokeWidth + 1.0, fontSize * 0.18);
  }
}
