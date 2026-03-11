import 'package:flutter/material.dart';

class PlayerMarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const PlayerMarqueeText({super.key, required this.text, required this.style});

  @override
  State<PlayerMarqueeText> createState() => _PlayerMarqueeTextState();
}

class _PlayerMarqueeTextState extends State<PlayerMarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  int _loopVersion = 0;
  double _travel = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this);
  }

  @override
  void dispose() {
    _loopVersion++;
    _controller.dispose();
    super.dispose();
  }

  Future<void> _startLoop(double travel) async {
    if ((_travel - travel).abs() < 1 && _controller.isAnimating) return;
    _travel = travel;
    _loopVersion++;
    final version = _loopVersion;
    _controller.stop();
    _controller.value = 0;
    if (travel <= 0) return;

    while (mounted && version == _loopVersion) {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (!mounted || version != _loopVersion) return;
      final duration = Duration(
        milliseconds: (travel * 26).clamp(2600, 6200).round(),
      );
      try {
        await _controller.animateTo(
          travel,
          duration: duration,
          curve: Curves.linear,
        );
      } catch (_) {
        return;
      }
      if (!mounted || version != _loopVersion) return;
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      if (!mounted || version != _loopVersion) return;
      _controller.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final direction = Directionality.of(context);
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: direction,
        )..layout(maxWidth: double.infinity);

        final textWidth = painter.width;
        final availableWidth = constraints.maxWidth;
        final textHeight = painter.height;
        if (!availableWidth.isFinite ||
            availableWidth <= 0 ||
            !textWidth.isFinite ||
            textWidth <= 0 ||
            !textHeight.isFinite ||
            textHeight <= 0) {
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: widget.style,
          );
        }
        final needsScroll = textWidth > availableWidth + 2;

        if (!needsScroll) {
          if (_travel != 0 || _controller.isAnimating) {
            _loopVersion++;
            _travel = 0;
            _controller.stop();
            _controller.value = 0;
          }
          return SizedBox(
            width: availableWidth,
            height: textHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.text,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: widget.style,
              ),
            ),
          );
        }

        final travel = textWidth - availableWidth + 28;
        final marqueeWidth = textWidth * 2 + 28;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _startLoop(travel);
          }
        });

        final fadeWidth = availableWidth.clamp(12.0, 22.0) * 0.45;
        final leftFadeStop = (fadeWidth / availableWidth).clamp(0.0, 0.18);
        final rightFadeStop = (1 - leftFadeStop).clamp(0.82, 1.0);

        return SizedBox(
          width: availableWidth,
          height: textHeight,
          child: ClipRect(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) {
                return LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: const [
                    Colors.transparent,
                    Colors.black,
                    Colors.black,
                    Colors.transparent,
                  ],
                  stops: [0.0, leftFadeStop, rightFadeStop, 1.0],
                ).createShader(rect);
              },
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minHeight: textHeight,
                maxHeight: textHeight,
                minWidth: 0,
                maxWidth: marqueeWidth,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final offsetX = _controller.value.isFinite
                        ? _controller.value
                        : 0.0;
                    return Transform.translate(
                      offset: Offset(-offsetX, 0),
                      child: child,
                    );
                  },
                  child: SizedBox(
                    width: marqueeWidth,
                    height: textHeight,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 0,
                          top: 0,
                          child: Text(
                            widget.text,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: widget.style,
                          ),
                        ),
                        Positioned(
                          left: textWidth + 28,
                          top: 0,
                          child: Text(
                            widget.text,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: widget.style,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class PlayerTopIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const PlayerTopIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.width < 900;
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon),
      color: Colors.white,
      iconSize: compact ? 19 : 21,
      splashRadius: compact ? 15 : 16,
      padding: EdgeInsets.all(compact ? 3.5 : 4.5),
      constraints: BoxConstraints(
        minWidth: compact ? 26 : 28,
        minHeight: compact ? 26 : 28,
      ),
    );
  }
}

class PlayerBottomControlButton extends StatelessWidget {
  final IconData icon;
  final bool compact;
  final bool emphasis;
  final VoidCallback onPressed;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressEndCallback? onLongPressEnd;

  const PlayerBottomControlButton({
    super.key,
    required this.icon,
    this.compact = false,
    this.emphasis = false,
    required this.onPressed,
    this.onLongPressStart,
    this.onLongPressEnd,
  });

  @override
  Widget build(BuildContext context) {
    final useCompact = compact || MediaQuery.of(context).size.width < 900;
    final iconSize = emphasis
        ? (useCompact ? 40.0 : 46.0)
        : (useCompact ? 24.0 : 28.0);
    final splashRadius = emphasis
        ? (useCompact ? 22.0 : 26.0)
        : (useCompact ? 16.0 : 20.0);
    final edge = emphasis ? 0.0 : (useCompact ? 6.0 : 8.0);
    final minSize = emphasis
        ? (useCompact ? 46.0 : 54.0)
        : (useCompact ? 34.0 : 40.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: onLongPressStart,
      onLongPressEnd: onLongPressEnd,
      child: IconButton(
        onPressed: onPressed,
        icon: _PlayerControlIcon(icon: icon, emphasis: emphasis),
        color: Colors.white,
        iconSize: iconSize,
        splashRadius: splashRadius,
        padding: EdgeInsets.all(edge),
        constraints: BoxConstraints(minWidth: minSize, minHeight: minSize),
      ),
    );
  }
}

class _PlayerControlIcon extends StatelessWidget {
  final IconData icon;
  final bool emphasis;

  const _PlayerControlIcon({required this.icon, required this.emphasis});

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.width < 900;
    final iconSize = emphasis
        ? (compact ? 34.0 : 40.0)
        : (compact ? 24.0 : 28.0);
    return Icon(icon, size: iconSize);
  }
}

class PlayerActionTextButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressEndCallback? onLongPressEnd;

  const PlayerActionTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.onLongPressStart,
    this.onLongPressEnd,
  });

  @override
  Widget build(BuildContext context) {
    if (label == '\u91CD\u8F7D') {
      return const SizedBox.shrink();
    }

    final useCompact = MediaQuery.of(context).size.width < 900;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: onLongPressStart,
      onLongPressEnd: onLongPressEnd,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: Colors.transparent,
          overlayColor: Colors.white.withValues(alpha: 0.08),
          padding: EdgeInsets.symmetric(
            horizontal: useCompact ? 4 : 6,
            vertical: useCompact ? 2 : 4,
          ),
          minimumSize: Size(0, useCompact ? 24 : 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: useCompact ? 13 : 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class PlayerProgressIconButton extends StatelessWidget {
  final VoidCallback onPressed;

  const PlayerProgressIconButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.width < 900;
    return IconButton(
      onPressed: onPressed,
      icon: SizedBox.square(
        dimension: compact ? 18 : 20,
        child: const CustomPaint(painter: _OrientationPanelPainter()),
      ),
      color: Colors.white.withValues(alpha: 0.92),
      iconSize: compact ? 20 : 22,
      splashRadius: compact ? 17 : 18,
      padding: EdgeInsets.all(compact ? 3 : 4),
      constraints: BoxConstraints(
        minWidth: compact ? 24 : 28,
        minHeight: compact ? 24 : 28,
      ),
    );
  }
}

class _OrientationPanelPainter extends CustomPainter {
  const _OrientationPanelPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..isAntiAlias = true;

    final leftRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.1,
        size.height * 0.1,
        size.width * 0.48,
        size.height * 0.8,
      ),
      Radius.circular(size.width * 0.12),
    );
    final rightRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.42,
        size.height * 0.1,
        size.width * 0.48,
        size.height * 0.8,
      ),
      Radius.circular(size.width * 0.12),
    );

    canvas.drawRRect(leftRect, strokePaint);
    canvas.drawRRect(rightRect, strokePaint);

    final divider = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final dividerRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.47,
        size.height * 0.18,
        size.width * 0.06,
        size.height * 0.64,
      ),
      Radius.circular(size.width * 0.04),
    );
    canvas.drawRRect(dividerRect, divider);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class PlayerProgressChapterMarker {
  final double fraction;
  final bool active;

  const PlayerProgressChapterMarker({
    required this.fraction,
    this.active = false,
  });
}

class PlayerTimelineBar extends StatefulWidget {
  final double value;
  final List<PlayerProgressChapterMarker> chapterMarkers;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  const PlayerTimelineBar({
    super.key,
    required this.value,
    this.chapterMarkers = const <PlayerProgressChapterMarker>[],
    this.onChangeStart,
    this.onChanged,
    this.onChangeEnd,
  });

  @override
  State<PlayerTimelineBar> createState() => _PlayerTimelineBarState();
}

class _PlayerTimelineBarState extends State<PlayerTimelineBar> {
  static const double _chapterSnapThreshold = 18;
  bool _dragging = false;
  double _dragValue = 0;

  double get _displayValue => _dragging ? _dragValue : widget.value;

  void _begin(double localDx, double width) {
    final next = _resolveFraction(localDx, width);
    _dragging = true;
    _dragValue = next;
    widget.onChangeStart?.call(next);
    widget.onChanged?.call(next);
    setState(() {});
  }

  void _update(double localDx, double width) {
    if (!_dragging) return;
    final next = _resolveFraction(localDx, width);
    if ((next - _dragValue).abs() < 0.0005) return;
    _dragValue = next;
    widget.onChanged?.call(next);
    setState(() {});
  }

  void _end() {
    if (!_dragging) return;
    final target = _dragValue;
    _dragging = false;
    widget.onChangeEnd?.call(target);
    setState(() {});
  }

  double _resolveFraction(double localDx, double width) {
    if (width <= 0) return 0;
    final fraction = (localDx / width).clamp(0.0, 1.0);
    if (widget.chapterMarkers.isEmpty) return fraction;

    PlayerProgressChapterMarker? nearestMarker;
    double nearestDistance = double.infinity;
    for (final marker in widget.chapterMarkers) {
      final markerDx = marker.fraction.clamp(0.0, 1.0) * width;
      final distance = (markerDx - localDx).abs();
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestMarker = marker;
      }
    }
    if (nearestMarker != null && nearestDistance <= _chapterSnapThreshold) {
      return nearestMarker.fraction.clamp(0.0, 1.0);
    }
    return fraction;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (details) => _begin(details.localPosition.dx, width),
          onTapUp: (_) => _end(),
          onHorizontalDragStart: (details) =>
              _begin(details.localPosition.dx, width),
          onHorizontalDragUpdate: (details) =>
              _update(details.localPosition.dx, width),
          onHorizontalDragEnd: (_) => _end(),
          onHorizontalDragCancel: _end,
          child: CustomPaint(
            size: Size(width, 34),
            painter: _PlayerTimelinePainter(
              value: _displayValue.clamp(0.0, 1.0),
              markers: widget.chapterMarkers,
            ),
          ),
        );
      },
    );
  }
}

class _PlayerTimelinePainter extends CustomPainter {
  final double value;
  final List<PlayerProgressChapterMarker> markers;

  const _PlayerTimelinePainter({required this.value, required this.markers});

  @override
  void paint(Canvas canvas, Size size) {
    const trackHeight = 4.0;
    const thumbRadius = 9.0;
    final trackTop = (size.height - trackHeight) / 2;
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, trackTop, size.width, trackHeight),
      const Radius.circular(999),
    );
    final inactivePaint = Paint()
      ..color = Colors.white24
      ..isAntiAlias = true;
    canvas.drawRRect(trackRect, inactivePaint);

    final progressWidth = size.width * value;
    if (progressWidth > 0) {
      final activeRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, trackTop, progressWidth.clamp(0.0, size.width), trackHeight),
        const Radius.circular(999),
      );
      final activePaint = Paint()
        ..color = const Color(0xFF1E7BFF)
        ..isAntiAlias = true;
      canvas.drawRRect(activeRect, activePaint);
    }

    for (final marker in markers) {
      final fraction = marker.fraction.clamp(0.0, 1.0);
      final dx = size.width * fraction;
      final lineWidth = marker.active ? 2.4 : 1.8;
      final lineHeight = marker.active ? 10.0 : 8.0;
      final lineRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(dx, size.height / 2),
          width: lineWidth,
          height: lineHeight,
        ),
        const Radius.circular(999),
      );
      final linePaint = Paint()
        ..color = Colors.white.withValues(alpha: marker.active ? 0.96 : 0.84)
        ..isAntiAlias = true;
      final strokePaint = Paint()
        ..color = const Color(0xCC0B1117)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.45
        ..isAntiAlias = true;
      canvas.drawRRect(lineRect, linePaint);
      canvas.drawRRect(lineRect, strokePaint);
    }

    final thumbCenter = Offset(progressWidth.clamp(0.0, size.width), size.height / 2);
    final thumbPaint = Paint()
      ..color = Colors.white
      ..isAntiAlias = true;
    canvas.drawCircle(thumbCenter, thumbRadius, thumbPaint);
  }

  @override
  bool shouldRepaint(covariant _PlayerTimelinePainter oldDelegate) {
    return oldDelegate.value != value || oldDelegate.markers != markers;
  }
}
