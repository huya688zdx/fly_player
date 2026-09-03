import 'package:flutter/material.dart';

/// 避开 Windows 推入路由中 Material Slider 的无障碍节点崩溃。
class DesktopSemanticsSafeSlider extends StatefulWidget {
  const DesktopSemanticsSafeSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.activeColor,
    required this.inactiveColor,
    required this.semanticsLabel,
    required this.semanticsValue,
    this.divisions,
    this.onChangeEnd,
    this.trackHeight = 3,
    this.thumbRadius = 6,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final Color activeColor;
  final Color inactiveColor;
  final String semanticsLabel;
  final String semanticsValue;
  final double trackHeight;
  final double thumbRadius;

  @override
  State<DesktopSemanticsSafeSlider> createState() =>
      _DesktopSemanticsSafeSliderState();
}

class _DesktopSemanticsSafeSliderState
    extends State<DesktopSemanticsSafeSlider> {
  double? _interactionValue;
  bool _hovered = false;

  double get _safeValue => (_interactionValue ?? widget.value)
      .clamp(widget.min, widget.max)
      .toDouble();

  double get _step {
    final divisions = widget.divisions;
    if (divisions != null && divisions > 0) {
      return (widget.max - widget.min) / divisions;
    }
    return (widget.max - widget.min) / 20;
  }

  double _valueForPosition(double dx, double width) {
    if (width <= 0 || widget.max <= widget.min) return widget.min;
    var fraction = (dx / width).clamp(0.0, 1.0).toDouble();
    if (Directionality.of(context) == TextDirection.rtl) {
      fraction = 1 - fraction;
    }
    var value = widget.min + (widget.max - widget.min) * fraction;
    final divisions = widget.divisions;
    if (divisions != null && divisions > 0) {
      final step = (widget.max - widget.min) / divisions;
      value = widget.min + ((value - widget.min) / step).round() * step;
    }
    return value.clamp(widget.min, widget.max).toDouble();
  }

  void _change(double dx, double width) {
    final value = _valueForPosition(dx, width);
    setState(() => _interactionValue = value);
    widget.onChanged(value);
  }

  void _endInteraction() {
    final value = _safeValue;
    setState(() => _interactionValue = null);
    widget.onChangeEnd?.call(value);
  }

  void _adjust(double delta) {
    final value = (_safeValue + delta).clamp(widget.min, widget.max).toDouble();
    widget.onChanged(value);
    widget.onChangeEnd?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final range = widget.max - widget.min;
    final fraction = range <= 0 ? 0.0 : (_safeValue - widget.min) / range;
    return Semantics(
      slider: true,
      label: widget.semanticsLabel,
      value: widget.semanticsValue,
      increasedValue: (_safeValue + _step)
          .clamp(widget.min, widget.max)
          .toStringAsFixed(1),
      decreasedValue: (_safeValue - _step)
          .clamp(widget.min, widget.max)
          .toStringAsFixed(1),
      onIncrease: () => _adjust(_step),
      onDecrease: () => _adjust(-_step),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: SizedBox(
          height: 28,
          child: LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) =>
                  _change(details.localPosition.dx, constraints.maxWidth),
              onTapUp: (_) => _endInteraction(),
              onTapCancel: () => setState(() => _interactionValue = null),
              onHorizontalDragStart: (details) =>
                  _change(details.localPosition.dx, constraints.maxWidth),
              onHorizontalDragUpdate: (details) =>
                  _change(details.localPosition.dx, constraints.maxWidth),
              onHorizontalDragEnd: (_) => _endInteraction(),
              onHorizontalDragCancel: () =>
                  setState(() => _interactionValue = null),
              child: CustomPaint(
                painter: _DesktopSafeSliderPainter(
                  fraction: fraction.clamp(0, 1).toDouble(),
                  activeColor: widget.activeColor,
                  inactiveColor: widget.inactiveColor,
                  trackHeight: widget.trackHeight,
                  thumbRadius: widget.thumbRadius,
                  emphasized: _hovered || _interactionValue != null,
                  rtl: Directionality.of(context) == TextDirection.rtl,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopSafeSliderPainter extends CustomPainter {
  const _DesktopSafeSliderPainter({
    required this.fraction,
    required this.activeColor,
    required this.inactiveColor,
    required this.trackHeight,
    required this.thumbRadius,
    required this.emphasized,
    required this.rtl,
  });

  final double fraction;
  final Color activeColor;
  final Color inactiveColor;
  final double trackHeight;
  final double thumbRadius;
  final bool emphasized;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final start = thumbRadius;
    final width = (size.width - thumbRadius * 2).clamp(0.0, double.infinity);
    final progress = width * fraction;
    final y = size.height / 2;
    final radius = Radius.circular(trackHeight);
    final track = Rect.fromLTWH(start, y - trackHeight / 2, width, trackHeight);
    canvas.drawRRect(
      RRect.fromRectAndRadius(track, radius),
      Paint()..color = inactiveColor,
    );
    final activeLeft = rtl ? start + width - progress : start;
    if (progress > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(activeLeft, track.top, progress, trackHeight),
          radius,
        ),
        Paint()..color = activeColor,
      );
    }
    final thumbX = rtl ? start + width - progress : start + progress;
    if (emphasized) {
      canvas.drawCircle(
        Offset(thumbX, y),
        thumbRadius + 5,
        Paint()..color = activeColor.withValues(alpha: 0.16),
      );
    }
    canvas.drawCircle(
      Offset(thumbX, y),
      thumbRadius,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _DesktopSafeSliderPainter oldDelegate) {
    return oldDelegate.fraction != fraction ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.trackHeight != trackHeight ||
        oldDelegate.thumbRadius != thumbRadius ||
        oldDelegate.emphasized != emphasized ||
        oldDelegate.rtl != rtl;
  }
}
