import 'dart:math' as math;

import 'package:flutter/material.dart';

enum DesktopPlayerMotionKind {
  danmaku,
  speed,
  episodes,
  quality,
  subtitle,
  audio,
  fullscreen,
  repeat,
  bookmark,
  screenshot,
  settings,
  volume,
}

/// 透明图标只绘制笔画；交互时运行一次，静止时不保留动画帧回调。
class DesktopPlayerMotionIcon extends StatefulWidget {
  const DesktopPlayerMotionIcon({
    super.key,
    required this.kind,
    this.selected = false,
    this.hovered = false,
    this.label = '',
  });

  final DesktopPlayerMotionKind kind;
  final bool selected;
  final bool hovered;
  final String label;

  @override
  State<DesktopPlayerMotionIcon> createState() =>
      _DesktopPlayerMotionIconState();
}

class _DesktopPlayerMotionIconState extends State<DesktopPlayerMotionIcon>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: 1,
  );
  bool _entering = true;

  @override
  void didUpdateWidget(DesktopPlayerMotionIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected ||
        oldWidget.hovered != widget.hovered ||
        oldWidget.label != widget.label) {
      _entering = oldWidget.selected != widget.selected
          ? widget.selected
          : widget.hovered;
      _motion.duration = Duration(milliseconds: _entering ? 420 : 300);
      if (MediaQuery.disableAnimationsOf(context)) {
        _motion.value = 1;
      } else {
        _motion.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size(widget.kind == DesktopPlayerMotionKind.speed ? 44 : 28, 28),
      painter: _MotionPainter(
        motion: _motion,
        kind: widget.kind,
        selected: widget.selected,
        hovered: widget.hovered,
        entering: _entering,
        label: widget.label,
      ),
    ),
  );
}

class _MotionPainter extends CustomPainter {
  _MotionPainter({
    required this.motion,
    required this.kind,
    required this.selected,
    required this.hovered,
    required this.entering,
    required this.label,
  }) : super(repaint: motion);

  final Animation<double> motion;
  final DesktopPlayerMotionKind kind;
  final bool selected, hovered, entering;
  final String label;

  @override
  void paint(Canvas canvas, Size size) {
    final q = motion.value;
    final wave = math.sin(q * math.pi);
    final direction = entering ? 1.0 : -1.0;
    final ink = selected
        ? const Color(0xFF8CBCFF)
        : hovered
        ? Colors.white
        : const Color(0xFFE1E7EF);
    final pen = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.save();
    canvas.scale(size.height / 130);
    canvas.translate((size.width * 130 / size.height - 200) / 2, -35);

    void line(
      double x,
      double y,
      double endX,
      double endY, [
      double width = 6,
    ]) {
      pen.strokeWidth = width;
      canvas.drawLine(Offset(x, y), Offset(endX, endY), pen);
    }

    void screen([double inset = 0]) {
      pen.strokeWidth = 6;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(43 + inset, 54 + inset, 157 - inset, 143 - inset),
          const Radius.circular(11),
        ),
        pen,
      );
    }

    void text(String value, double y, double fontSize) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            color: ink,
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(100 - painter.width / 2, y - painter.height / 2),
      );
    }

    switch (kind) {
      case DesktopPlayerMotionKind.bookmark:
        final lift = 7 * wave;
        canvas.drawPath(
          Path()
            ..moveTo(61, 55 - lift)
            ..lineTo(113, 55 - lift)
            ..lineTo(113, 146 - lift)
            ..lineTo(87, 130 - lift)
            ..lineTo(61, 146 - lift)
            ..close(),
          pen,
        );
        final arm = 12 + 6 * wave;
        line(140 - arm, 75, 140 + arm, 75);
        line(140, 75 - arm, 140, 75 + arm);
        break;
      case DesktopPlayerMotionKind.screenshot:
        canvas.drawPath(
          Path()
            ..moveTo(49, 67)
            ..lineTo(73, 67)
            ..lineTo(82, 52)
            ..lineTo(118, 52)
            ..lineTo(127, 67)
            ..lineTo(151, 67)
            ..quadraticBezierTo(157, 67, 157, 74)
            ..lineTo(157, 140)
            ..quadraticBezierTo(157, 146, 150, 146)
            ..lineTo(50, 146)
            ..quadraticBezierTo(43, 146, 43, 140)
            ..lineTo(43, 74)
            ..quadraticBezierTo(43, 67, 49, 67)
            ..close(),
          pen,
        );
        canvas.drawCircle(const Offset(100, 105), 25 - 10 * wave, pen);
        canvas.drawCircle(const Offset(139, 80), 3, Paint()..color = ink);
        break;
      case DesktopPlayerMotionKind.settings:
        canvas.save();
        canvas.translate(100, 100);
        // 八齿齿轮转过一个齿距，终点与静止轮廓重合，退出时反转。
        canvas.rotate(
          direction * Curves.easeOutCubic.transform(q) * math.pi / 4,
        );
        final gear = Path();
        for (var tooth = 0; tooth < 8; tooth++) {
          for (var point = 0; point < 4; point++) {
            final angle = (tooth + point / 4) * math.pi / 4;
            final radius = point == 1 || point == 2 ? 50.0 : 39.0;
            final x = radius * math.cos(angle), y = radius * math.sin(angle);
            if (tooth == 0 && point == 0) {
              gear.moveTo(x, y);
            } else {
              gear.lineTo(x, y);
            }
          }
        }
        canvas.drawPath(gear..close(), pen);
        canvas.drawCircle(Offset.zero, 17, pen);
        canvas.restore();
        break;
      case DesktopPlayerMotionKind.volume:
        canvas.drawPath(
          Path()
            ..moveTo(47, 85)
            ..lineTo(69, 85)
            ..lineTo(96, 63)
            ..lineTo(96, 137)
            ..lineTo(69, 115)
            ..lineTo(47, 115)
            ..close(),
          pen,
        );
        if (label == 'muted') {
          final arm = 12 + 4 * wave;
          line(132 - arm, 100 - arm, 132 + arm, 100 + arm);
          line(132 - arm, 100 + arm, 132 + arm, 100 - arm);
        } else {
          for (var i = 0; i < (label == 'low' ? 1 : 2); i++) {
            final radius = 30.0 + i * 22 + (i + 1) * 3 * wave;
            canvas.drawArc(
              Rect.fromCircle(center: const Offset(96, 100), radius: radius),
              -.75 - .15 * wave,
              1.5 + .3 * wave,
              false,
              pen,
            );
          }
        }
        break;
      case DesktopPlayerMotionKind.danmaku:
        screen();
        canvas.save();
        canvas.clipRect(const Rect.fromLTRB(54, 65, 146, 134));
        for (var j = 0; j < 3; j++) {
          final origin = [59.0, 99.0, 62.0][j];
          final length = [39.0, 38.0, 51.0][j];
          final x = 53 + (origin - 53 - direction * q * 120) % 120;
          for (final offset in [-120.0, 0.0, 120.0]) {
            line(x + offset, 79 + j * 22, x + offset + length, 79 + j * 22);
          }
        }
        canvas.restore();
        break;
      case DesktopPlayerMotionKind.speed:
        canvas.save();
        canvas.clipRect(const Rect.fromLTRB(10, 65, 190, 133));
        final dy = direction * Curves.easeOutCubic.transform(q) * 72;
        text(label, 99 - dy, 50);
        text(label, 99 - dy + direction * 72, 50);
        canvas.restore();
        break;
      case DesktopPlayerMotionKind.episodes:
        for (var j = 0; j < 3; j++) {
          final local = ((q - j * .12) / .76).clamp(0.0, 1.0);
          final offset = -direction * math.sin(local * math.pi) * 27;
          final x = 50 + offset, y = 59.0 + j * 36;
          pen.strokeWidth = 4;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x, y, 15, 15),
              const Radius.circular(3),
            ),
            pen,
          );
          line(x + 33, y + 7, x + 95 - offset.abs() * .45, y + 7);
        }
        break;
      case DesktopPlayerMotionKind.quality:
        screen(9 * wave);
        text('HD', 99, 45 + 4 * wave);
        break;
      case DesktopPlayerMotionKind.subtitle:
        screen();
        final strokes = [
          (60.0, 76.0, 26.0),
          (98.0, 76.0, 28.0),
          (60.0, 101.0, 78.0),
          (60.0, 121.0, 59.0),
        ];
        for (var j = 0; j < strokes.length; j++) {
          final (x, y, length) = strokes[j];
          final local = ((q - j * .075) / .7).clamp(0.0, 1.0);
          final factor = entering
              ? .15 + .85 * Curves.easeOutCubic.transform(local)
              : 1 - .85 * math.sin(local * math.pi);
          line(x, y, x + length * factor, y, 5);
        }
        break;
      case DesktopPlayerMotionKind.audio:
        final tilt = direction * wave * 9;
        final left = 132 - wave * 19, right = 118 + wave * 13;
        final fill = Paint()..color = ink;
        canvas.drawOval(Rect.fromLTWH(49, left - 12, 28, 21), fill);
        canvas.drawOval(Rect.fromLTWH(117, right - 12, 28, 21), fill);
        pen.strokeWidth = 7;
        canvas.drawPath(
          Path()
            ..moveTo(74, left)
            ..lineTo(74, 66 + tilt)
            ..lineTo(141, 51 - tilt)
            ..lineTo(141, right),
          pen,
        );
        line(76, 79 + tilt, 140, 64 - tilt, 8);
        break;
      case DesktopPlayerMotionKind.fullscreen:
        final amount = selected ? 12.0 : 0.0;
        final gap = amount + 7 * wave;
        for (final sx in [-1, 1]) {
          for (final sy in [-1, 1]) {
            final x = 100 + sx * (40 + gap), y = 100 + sy * (35 + gap);
            pen.strokeWidth = 7;
            canvas.drawPath(
              Path()
                ..moveTo(x - sx * 23, y)
                ..lineTo(x, y)
                ..lineTo(x, y - sy * 23),
              pen,
            );
          }
        }
        break;
      case DesktopPlayerMotionKind.repeat:
        canvas.save();
        canvas.translate(100, 99);
        canvas.rotate(direction * wave * .18);
        canvas.translate(-100, -99);
        pen.strokeWidth = 6;
        canvas.drawPath(
          Path()
            ..moveTo(45, 90)
            ..cubicTo(45, 58, 66, 48, 96, 48)
            ..lineTo(146, 48),
          pen,
        );
        canvas.drawPath(
          Path()
            ..moveTo(155, 108)
            ..cubicTo(155, 140, 134, 152, 104, 152)
            ..lineTo(54, 152),
          pen,
        );
        line(133, 36, 146, 48);
        line(146, 48, 133, 60);
        line(66, 140, 54, 152);
        line(54, 152, 66, 164);
        text(label == 'A' ? 'A' : 'AB', 99, 35);
        canvas.restore();
        break;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MotionPainter oldDelegate) =>
      oldDelegate.kind != kind ||
      oldDelegate.selected != selected ||
      oldDelegate.hovered != hovered ||
      oldDelegate.entering != entering ||
      oldDelegate.label != label ||
      oldDelegate.motion != motion;
}
