import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

typedef PlayerSpeedDialLabelBuilder = String Function(double speed);

class PlayerSpeedDialScale {
  static const double minSpeed = 0.5;
  static const double maxSpeed = 8.0;
  static const double startAngle = math.pi * 0.54;
  static const double sweepAngle = math.pi * 0.92;
  static const List<double> keySpeeds = <double>[1.0, 2.0, 4.0, 8.0];
  static const List<double> labelSpeeds = <double>[0.5, 1.0, 1.5, 2.0, 4.0, 8.0];
  static const List<_SpeedDialSegment> _segments = <_SpeedDialSegment>[
    _SpeedDialSegment(
      min: 0.5,
      max: 2.0,
      step: 0.1,
      normalizedStart: 0.0,
      normalizedSpan: 0.58,
    ),
    _SpeedDialSegment(
      min: 2.0,
      max: 4.0,
      step: 0.25,
      normalizedStart: 0.58,
      normalizedSpan: 0.25,
    ),
    _SpeedDialSegment(
      min: 4.0,
      max: 8.0,
      step: 0.5,
      normalizedStart: 0.83,
      normalizedSpan: 0.17,
    ),
  ];

  static final List<double> tickSpeeds = _buildTickSpeeds();

  static List<double> _buildTickSpeeds() {
    final ticks = <double>[];
    for (final segment in _segments) {
      var current = segment.min;
      while (current <= segment.max + 0.0001) {
        final normalized = double.parse(current.toStringAsFixed(2));
        if (ticks.isEmpty || (ticks.last - normalized).abs() > 0.001) {
          ticks.add(normalized);
        }
        current += segment.step;
      }
    }
    return ticks;
  }

  static double normalizeSpeed(double speed) {
    final clamped = speed.clamp(minSpeed, maxSpeed).toDouble();
    final segment = _segmentForSpeed(clamped);
    final stepped = _snapToStep(
      clamped,
      min: segment.min,
      max: segment.max,
      step: segment.step,
    );
    return double.parse(stepped.toStringAsFixed(2));
  }

  static bool isKeySpeed(double speed) {
    return keySpeeds.any((candidate) => (candidate - speed).abs() < 0.001);
  }

  static bool isLabelSpeed(double speed) {
    return labelSpeeds.any((candidate) => (candidate - speed).abs() < 0.001);
  }

  static bool isMajorTick(double speed) {
    return isLabelSpeed(speed) || (speed - 0.75).abs() < 0.001;
  }

  static double speedToAngle(double speed) {
    return startAngle + sweepAngle * speedToNormalized(speed);
  }

  static double speedToNormalized(double speed) {
    final normalizedSpeed = normalizeSpeed(speed);
    final segment = _segmentForSpeed(normalizedSpeed);
    final factor =
        (normalizedSpeed - segment.min) / (segment.max - segment.min);
    return segment.normalizedStart + factor * segment.normalizedSpan;
  }

  static double angleToSpeed(double angle) {
    final clampedAngle = angle.clamp(startAngle, startAngle + sweepAngle);
    final normalized =
        (clampedAngle - startAngle).toDouble() / sweepAngle.toDouble();
    return normalizeSpeed(_speedFromNormalized(normalized));
  }

  static double? speedForOffset(Offset localPosition, Size size) {
    final geometry = _SpeedDialGeometry.fromSize(size);
    final vector = localPosition - geometry.center;
    final horizontalLimit = geometry.trackThickness * 2.8;
    if (localPosition.dx < size.width - geometry.radius - horizontalLimit) {
      return null;
    }
    if (vector.dx >= geometry.trackThickness * 2.2) {
      return null;
    }
    var angle = math.atan2(vector.dy, vector.dx);
    if (angle < 0) {
      angle += math.pi * 2;
    }
    return angleToSpeed(angle);
  }

  static double _speedFromNormalized(double normalized) {
    for (final segment in _segments) {
      final upper = segment.normalizedStart + segment.normalizedSpan;
      if (normalized <= upper + 0.0001) {
        final local =
            (normalized - segment.normalizedStart) / segment.normalizedSpan;
        final speed = segment.min + (segment.max - segment.min) * local;
        return speed.clamp(segment.min, segment.max).toDouble();
      }
    }
    return maxSpeed;
  }

  static _SpeedDialSegment _segmentForSpeed(double speed) {
    return _segments.firstWhere(
      (segment) => speed <= segment.max + 0.0001,
      orElse: () => _segments.last,
    );
  }

  static double _snapToStep(
    double value, {
    required double min,
    required double max,
    required double step,
  }) {
    final rounded = ((value - min) / step).round();
    final snapped = min + rounded * step;
    return snapped.clamp(min, max).toDouble();
  }
}

class PlayerSpeedDialOverlay extends StatelessWidget {
  final bool visible;
  final double speed;
  final ValueChanged<double> onSpeedChanged;
  final VoidCallback onDismiss;
  final PlayerSpeedDialLabelBuilder labelBuilder;

  const PlayerSpeedDialOverlay({
    super.key,
    required this.visible,
    required this.speed,
    required this.onSpeedChanged,
    required this.onDismiss,
    required this.labelBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return const SizedBox.shrink();
    }
    final colors = context.appColors;
    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;

    return LayoutBuilder(
      builder: (context, constraints) {
        final shortestSide = math.min(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        final phoneSizedViewport = shortestSide < 520;
        final phoneLandscape = phoneSizedViewport && isLandscape;
        final widthByViewport =
            constraints.maxWidth *
            (phoneSizedViewport
                ? (isLandscape ? 0.20 : 0.34)
                : (isLandscape ? 0.32 : 0.40));
        final widthByHeight =
            constraints.maxHeight *
            (phoneSizedViewport
                ? (isLandscape ? 0.44 : 0.34)
                : (isLandscape ? 0.60 : 0.40));
        final widthByShortSide =
            shortestSide *
            (phoneSizedViewport
                ? (isLandscape ? 0.48 : 0.70)
                : (isLandscape ? 0.64 : 0.78));
        final dialWidth = math
            .min(widthByViewport, math.min(widthByHeight, widthByShortSide))
            .clamp(
              phoneLandscape ? 116.0 : (phoneSizedViewport ? 128.0 : 150.0),
              phoneLandscape ? 188.0 : (phoneSizedViewport ? 220.0 : 268.0),
            );
        final heightByViewport =
            constraints.maxHeight *
            (phoneSizedViewport
                ? (isLandscape ? 0.52 : 0.40)
                : (isLandscape ? 0.60 : 0.46));
        final heightByShortSide =
            shortestSide *
            (phoneSizedViewport
                ? (isLandscape ? 0.94 : 0.90)
                : (isLandscape ? 1.02 : 0.96));
        final dialHeight = math
            .min(heightByViewport, heightByShortSide)
            .clamp(
              phoneLandscape ? 220.0 : (phoneSizedViewport ? 240.0 : 280.0),
              phoneLandscape ? 340.0 : (phoneSizedViewport ? 360.0 : 430.0),
            );
        final rightInset = phoneSizedViewport
            ? (isLandscape ? 14.0 : 12.0)
            : (isLandscape ? 18.0 : 16.0);

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDismiss,
                child: ColoredBox(
                  color: colors.overlayScrim.withValues(alpha: 0.1),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: EdgeInsets.only(
                  right: rightInset,
                  top: media.padding.top * 0.15,
                ),
                child: SizedBox(
                  width: dialWidth,
                  height: dialHeight,
                  child: _PlayerSpeedDialSurface(
                    width: dialWidth,
                    height: dialHeight,
                    speed: speed,
                    labelBuilder: labelBuilder,
                    onSpeedChanged: onSpeedChanged,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PlayerSpeedDialSurface extends StatelessWidget {
  final double width;
  final double height;
  final double speed;
  final ValueChanged<double> onSpeedChanged;
  final PlayerSpeedDialLabelBuilder labelBuilder;

  const _PlayerSpeedDialSurface({
    required this.width,
    required this.height,
    required this.speed,
    required this.onSpeedChanged,
    required this.labelBuilder,
  });

  void _handleDrag(Offset localPosition, Size size) {
    final nextSpeed = PlayerSpeedDialScale.speedForOffset(localPosition, size);
    if (nextSpeed == null) return;
    onSpeedChanged(nextSpeed);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(width, height);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _handleDrag(details.localPosition, size),
            onPanStart: (details) => _handleDrag(details.localPosition, size),
            onPanUpdate: (details) => _handleDrag(details.localPosition, size),
            child: CustomPaint(
              size: size,
              painter: _PlayerSpeedDialPainter(
                colors: context.appColors,
                speed: speed,
                labelBuilder: labelBuilder,
                textDirection: Directionality.of(context),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PlayerSpeedDialPainter extends CustomPainter {
  final AppThemeColors colors;
  final double speed;
  final PlayerSpeedDialLabelBuilder labelBuilder;
  final TextDirection textDirection;

  const _PlayerSpeedDialPainter({
    required this.colors,
    required this.speed,
    required this.labelBuilder,
    required this.textDirection,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = _SpeedDialGeometry.fromSize(size);
    final currentAngle = PlayerSpeedDialScale.speedToAngle(speed);
    final inactiveArcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = geometry.trackThickness
      ..color = colors.borderStrong.withValues(alpha: 0.56);
    final activeArcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = geometry.trackThickness
      ..color = colors.accent.withValues(alpha: 0.96);
    final glowArcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = geometry.trackThickness + 6
      ..color = colors.accentSoft.withValues(alpha: 0.48);

    canvas.drawArc(
      geometry.arcRect,
      PlayerSpeedDialScale.startAngle,
      PlayerSpeedDialScale.sweepAngle,
      false,
      inactiveArcPaint,
    );
    canvas.drawArc(
      geometry.arcRect,
      PlayerSpeedDialScale.startAngle,
      currentAngle - PlayerSpeedDialScale.startAngle,
      false,
      glowArcPaint,
    );
    canvas.drawArc(
      geometry.arcRect,
      PlayerSpeedDialScale.startAngle,
      currentAngle - PlayerSpeedDialScale.startAngle,
      false,
      activeArcPaint,
    );

    for (final tickSpeed in PlayerSpeedDialScale.tickSpeeds) {
      final tickAngle = PlayerSpeedDialScale.speedToAngle(tickSpeed);
      final isActive = tickSpeed <= speed + 0.0001;
      final isMajor = PlayerSpeedDialScale.isMajorTick(tickSpeed);
      final tickPaint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = isMajor ? 2.6 : 1.5
        ..color = isActive
            ? colors.accent.withValues(alpha: isMajor ? 0.98 : 0.82)
            : colors.textMuted.withValues(alpha: isMajor ? 0.74 : 0.48);
      final outer = geometry.pointOnArc(
        tickAngle,
        geometry.radius - geometry.trackThickness * 0.15,
      );
      final inner = geometry.pointOnArc(
        tickAngle,
        geometry.radius - geometry.trackThickness * (isMajor ? 1.55 : 1.02),
      );
      canvas.drawLine(inner, outer, tickPaint);
    }

    for (final labelSpeed in PlayerSpeedDialScale.labelSpeeds) {
      final labelAngle = PlayerSpeedDialScale.speedToAngle(labelSpeed);
      final labelPosition = geometry.pointOnArc(
        labelAngle,
        geometry.radius - geometry.trackThickness * 3.0,
      );
      final textPainter = TextPainter(
        text: TextSpan(
          text: labelBuilder(labelSpeed),
          style: TextStyle(
            color: (labelSpeed - speed).abs() < 0.001
                ? colors.textPrimary
                : colors.textSecondary.withValues(alpha: 0.84),
            fontSize: PlayerSpeedDialScale.isKeySpeed(labelSpeed) ? 12.0 : 10.6,
            fontWeight: PlayerSpeedDialScale.isKeySpeed(labelSpeed)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: textDirection,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(
          labelPosition.dx - textPainter.width / 2,
          labelPosition.dy - textPainter.height / 2,
        ),
      );
    }

    final currentLabelPosition = geometry.pointOnArc(
      currentAngle,
      geometry.radius + geometry.trackThickness * 1.25,
    );
    final currentLabelPainter = TextPainter(
      text: TextSpan(
        text: labelBuilder(speed).toUpperCase(),
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: geometry.trackThickness * 0.92,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          shadows: <Shadow>[
            Shadow(
              color: colors.overlayScrim.withValues(alpha: 0.62),
              blurRadius: 8,
              offset: const Offset(0, 1),
            ),
          ],
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: textDirection,
    )..layout();
    currentLabelPainter.paint(
      canvas,
      Offset(
        currentLabelPosition.dx - currentLabelPainter.width / 2,
        currentLabelPosition.dy - currentLabelPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _PlayerSpeedDialPainter oldDelegate) {
    return oldDelegate.speed != speed ||
        oldDelegate.colors != colors ||
        oldDelegate.textDirection != textDirection;
  }
}

class _SpeedDialGeometry {
  final Offset center;
  final double radius;
  final double trackThickness;
  final Rect arcRect;

  const _SpeedDialGeometry({
    required this.center,
    required this.radius,
    required this.trackThickness,
    required this.arcRect,
  });

  factory _SpeedDialGeometry.fromSize(Size size) {
    final compact = size.width < 170;
    final phoneLandscapeCompact = size.width < 190 && size.height < 380;
    final radius = math.min(
      size.width * (phoneLandscapeCompact ? 0.72 : (compact ? 0.76 : 0.81)),
      size.height * (phoneLandscapeCompact ? 0.46 : (compact ? 0.48 : 0.50)),
    );
    final center = Offset(
      size.width +
          radius * (phoneLandscapeCompact ? 0.10 : (compact ? 0.05 : 0.02)),
      size.height * (phoneLandscapeCompact ? 0.53 : 0.50),
    );
    final trackThickness =
        (size.width *
                (phoneLandscapeCompact ? 0.038 : (compact ? 0.040 : 0.044)))
            .clamp(
              phoneLandscapeCompact ? 7.0 : (compact ? 9.0 : 11.0),
              phoneLandscapeCompact ? 11.0 : (compact ? 14.0 : 17.0),
            );
    return _SpeedDialGeometry(
      center: center,
      radius: radius,
      trackThickness: trackThickness,
      arcRect: Rect.fromCircle(center: center, radius: radius),
    );
  }

  Offset pointOnArc(double angle, double radius) {
    return Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * radius,
    );
  }
}

class _SpeedDialSegment {
  final double min;
  final double max;
  final double step;
  final double normalizedStart;
  final double normalizedSpan;

  const _SpeedDialSegment({
    required this.min,
    required this.max,
    required this.step,
    required this.normalizedStart,
    required this.normalizedSpan,
  });
}
