import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 媒体无图默认占位(全 App 统一样式:「胶片齿孔」)。
///
/// 设计要点:
/// - 颜色全部来自 `context.appColors` 主题 token(accent / surfaceStrong / surface…),
///   动态取色(详情页 palette_generator)换色时占位自动同频,无需单独适配;
/// - 视觉分层:强调色渐变底 + 左右胶片齿孔条 + 斜向光泽 + 中心细线胶片图标;
/// - 性能:整块占位是一次 [CustomPainter] 的纯矢量绘制——无 BackdropFilter/模糊、
///   无位图解码、无逐帧动画(方案 C 本身无动效),列表滚动场景零光栅放大;
///   齿孔用单个 Path 批量填充,整卡 draw call 常数级。
///
/// 用法:组件充满父级约束,圆角由调用方的 ClipRRect/Decoration 负责。
/// 浅深色自适应:以 backgroundBase 亮度判断,与旧 _PosterPlaceholder 同口径。
class MediaPlaceholder extends StatelessWidget {
  const MediaPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLight = colors.backgroundBase.computeLuminance() >= .58;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: const Alignment(-.35, -1),
          end: const Alignment(.35, 1),
          colors: <Color>[
            Color.alphaBlend(
              colors.accent.withValues(alpha: isLight ? .14 : .16),
              colors.surfaceStrong,
            ),
            Color.alphaBlend(
              colors.accent.withValues(alpha: isLight ? .05 : .06),
              colors.surface,
            ),
            Color.alphaBlend(
              colors.accentStrong.withValues(alpha: isLight ? .03 : .04),
              colors.surface,
            ),
          ],
          stops: const <double>[0, .58, 1],
        ),
      ),
      child: CustomPaint(
        painter: _FilmEdgePainter(
          edgeLine: colors.accent.withValues(alpha: isLight ? .24 : .22),
          perforation: isLight
              ? const Color(0x2E182132)
              : Colors.white.withValues(alpha: .15),
          sheen: isLight
              ? Colors.black.withValues(alpha: .035)
              : Colors.white.withValues(alpha: .055),
          glyph: colors.accentStrong.withValues(alpha: isLight ? .78 : .9),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _FilmEdgePainter extends CustomPainter {
  const _FilmEdgePainter({
    required this.edgeLine,
    required this.perforation,
    required this.sheen,
    required this.glyph,
  });

  final Color edgeLine;
  final Color perforation;
  final Color sheen;
  final Color glyph;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;

    // 左右齿孔条:宽随卡片宽度(14%),超高窄卡按高度封顶避免挤掉中间图标。
    final stripW = math.min(size.width * .14, size.height * .26);

    _paintSheen(canvas, rect);
    _paintPerforations(canvas, size, stripW, left: true);
    _paintPerforations(canvas, size, stripW, left: false);
    _paintEdgeLines(canvas, size, stripW);
    _paintGlyph(canvas, size);
  }

  void _paintSheen(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: const Alignment(-.8, -1),
        end: const Alignment(.8, 1),
        colors: <Color>[
          sheen.withValues(alpha: 0),
          sheen,
          sheen.withValues(alpha: 0),
        ],
        stops: const <double>[.34, .5, .66],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  void _paintPerforations(
    Canvas canvas,
    Size size,
    double stripW, {
    required bool left,
  }) {
    // 齿孔按高度均匀分行,行高收敛在 9~20 逻辑像素,行数封顶避免极端长图爆炸。
    final targetCell = size.height * .14;
    final rows = math.max(
      2,
      (size.height / targetCell.clamp(9.0, 20.0)).round(),
    );
    final cellH = size.height / rows;
    final dotW = math.min(stripW * .42, 6.5);
    final dotH = math.min(cellH * .42, 4.5);
    if (dotW <= 1 || dotH <= 1) return;
    final r = math.min(1.6, dotH / 2);

    final path = Path();
    for (int i = 0; i < rows; i++) {
      final cy = cellH * (i + .5);
      final cx = left ? stripW / 2 : size.width - stripW / 2;
      path.addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, cy), width: dotW, height: dotH),
          Radius.circular(r),
        ),
      );
    }
    canvas.drawPath(path, Paint()..color = perforation);
  }

  void _paintEdgeLines(Canvas canvas, Size size, double stripW) {
    final paint = Paint()
      ..color = edgeLine
      ..strokeWidth = 1;
    canvas.drawLine(Offset(stripW, 0), Offset(stripW, size.height), paint);
    canvas.drawLine(
      Offset(size.width - stripW, 0),
      Offset(size.width - stripW, size.height),
      paint,
    );
  }

  /// 中心细线胶片图标(圆角片框 + 双列齿孔 + 播放三角),几何定义在 36×36
  /// 视图框内,按卡片短边比例缩放,与设计稿「胶片齿孔」方案一致。
  void _paintGlyph(Canvas canvas, Size size) {
    final g = (size.shortestSide * .19).clamp(18.0, 30.0);
    final s = g / 36;
    final center = Offset(size.width / 2, size.height / 2);
    final origin = center - Offset(g / 2, g / 2);
    Offset p(double x, double y) => origin + Offset(x * s, y * s);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.05, g * 1.5 / 36)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = glyph;

    // 片框
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          p(6.75, 9.75).dx,
          p(6.75, 9.75).dy,
          p(29.25, 26.25).dx,
          p(29.25, 26.25).dy,
        ),
        Radius.circular(3.2 * s),
      ),
      stroke,
    );
    // 双列齿孔(实心小块)
    final fill = Paint()..color = glyph;
    const holes = <(double, double)>[
      (10.2, 12.7),
      (10.2, 16.8),
      (10.2, 20.9),
      (23.4, 12.7),
      (23.4, 16.8),
      (23.4, 20.9),
    ];
    for (final (hx, hy) in holes) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(p(hx, hy).dx, p(hx, hy).dy, 2.4 * s, 2.4 * s),
          Radius.circular(.7 * s),
        ),
        fill,
      );
    }
    // 播放三角
    final triangle = Path()
      ..moveTo(p(16, 14.6).dx, p(16, 14.6).dy)
      ..lineTo(p(16, 21.4).dx, p(16, 21.4).dy)
      ..lineTo(p(22, 18).dx, p(22, 18).dy)
      ..close();
    canvas.drawPath(triangle, fill);
  }

  @override
  bool shouldRepaint(_FilmEdgePainter oldDelegate) {
    return edgeLine != oldDelegate.edgeLine ||
        perforation != oldDelegate.perforation ||
        sheen != oldDelegate.sheen ||
        glyph != oldDelegate.glyph;
  }
}
