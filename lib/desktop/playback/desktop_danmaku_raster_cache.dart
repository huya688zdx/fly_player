import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 单条弹幕的预渲染位图：描边、填充各画一遍，经 `toImageSync` 栅格化成
/// GPU 纹理；每帧绘制只是一次贴图，避免逐帧重放描边路径。
class DanmakuRasterEntry {
  const DanmakuRasterEntry({
    required this.image,
    required this.width,
    required this.height,
    required this.padding,
  });

  final ui.Image image;

  /// 文本排版尺寸（逻辑像素），车道占位判定与居中对齐都以此为口径。
  final double width;
  final double height;

  /// 位图四周为描边溢出留出的出血边（逻辑像素），绘制时整体外扩。
  final double padding;
}

/// 光栅缓存的查找键，涵盖所有影响渲染结果的样式因子。
class DanmakuRasterKey {
  const DanmakuRasterKey({
    required this.text,
    required this.fontSize,
    required this.maxWidthPx,
    required this.fillColor,
    required this.strokeWidth,
    required this.bold,
    required this.fontFamily,
    required this.devicePixelRatio,
  });

  final String text;
  final double fontSize;

  /// 断行上限（已量化），窗口拖拽时避免键随像素级抖动失效。
  final int maxWidthPx;
  final int fillColor;
  final double strokeWidth;
  final bool bold;
  final String? fontFamily;

  /// 千分比，跨屏拖动窗口 DPR 变化时位图按新清晰度重建。
  final int devicePixelRatio;

  @override
  bool operator ==(Object other) =>
      other is DanmakuRasterKey &&
      other.text == text &&
      other.fontSize == fontSize &&
      other.maxWidthPx == maxWidthPx &&
      other.fillColor == fillColor &&
      other.strokeWidth == strokeWidth &&
      other.bold == bold &&
      other.fontFamily == fontFamily &&
      other.devicePixelRatio == devicePixelRatio;

  @override
  int get hashCode => Object.hash(
    text,
    fontSize,
    maxWidthPx,
    fillColor,
    strokeWidth,
    bold,
    fontFamily,
    devicePixelRatio,
  );
}

/// 弹幕文本光栅缓存（LRU）。
///
/// 每条弹幕只在首次出现时排版+描边渲染一次，之后每帧只 `drawImageRect`
/// 平移贴图，避免逐帧 TextPainter 排版打满 UI 线程、描边路径打满光栅线程。
class DanmakuRasterCache {
  DanmakuRasterCache({this.capacity = 512});

  final int capacity;
  final LinkedHashMap<DanmakuRasterKey, DanmakuRasterEntry> _entries =
      LinkedHashMap<DanmakuRasterKey, DanmakuRasterEntry>();

  DanmakuRasterEntry? lookup(DanmakuRasterKey key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    _entries[key] = entry;
    return entry;
  }

  void put(DanmakuRasterKey key, DanmakuRasterEntry entry) {
    _entries.remove(key)?.image.dispose();
    _entries[key] = entry;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first)?.image.dispose();
    }
  }

  void dispose() {
    for (final entry in _entries.values) {
      entry.image.dispose();
    }
    _entries.clear();
  }

  /// 按 (文本, 样式) 栅格化一张描边+填充的弹幕位图。
  static DanmakuRasterEntry build({
    required String text,
    required double fontSize,
    required int maxWidthPx,
    required int fillColor,
    required double strokeWidth,
    required bool bold,
    required String? fontFamily,
    required double devicePixelRatio,
  }) {
    // alpha 取自填充色高位，等价于弃用的 Color.alpha 读取。
    final alpha = (fillColor >> 24) & 0xFF;
    final fillPaint = Paint()
      ..color = Color(fillColor)
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = Colors.black.withAlpha((alpha * 0.82).round())
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    TextPainter makePainter(Paint paint) {
      return TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            height: 1.05,
            fontFamily: fontFamily,
            foreground: paint,
          ),
        ),
        maxLines: 1,
        textDirection: TextDirection.ltr,
        ellipsis: '…',
      )..layout(maxWidth: maxWidthPx.toDouble());
    }

    final fillPainter = makePainter(fillPaint);
    final strokePainter = makePainter(strokePaint);
    final width = fillPainter.width;
    final height = fillPainter.height;

    // 描边会溢出排版边界，位图四周留出血边避免裁切。
    final padding = strokeWidth / 2 + 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(devicePixelRatio)
      ..translate(padding, padding);
    strokePainter.paint(canvas, Offset.zero);
    fillPainter.paint(canvas, Offset.zero);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      ((width + padding * 2) * devicePixelRatio).ceil(),
      ((height + padding * 2) * devicePixelRatio).ceil(),
    );
    picture.dispose();
    fillPainter.dispose();
    strokePainter.dispose();
    return DanmakuRasterEntry(
      image: image,
      width: width,
      height: height,
      padding: padding,
    );
  }
}
