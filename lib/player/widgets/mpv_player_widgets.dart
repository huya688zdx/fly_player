import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/app_theme.dart';

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

class PlayerPillButton extends StatelessWidget {
  final String label;
  final bool active;
  final bool dense;
  final VoidCallback onPressed;

  const PlayerPillButton({
    super.key,
    required this.label,
    required this.active,
    this.dense = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final compact = MediaQuery.of(context).size.width < 900;
    final horizontal = dense ? (compact ? 6.0 : 8.0) : (compact ? 8.0 : 10.0);
    final height = dense ? (compact ? 24.0 : 26.0) : (compact ? 28.0 : 30.0);
    final minWidth = dense ? (compact ? 28.0 : 32.0) : (compact ? 34.0 : 38.0);
    final fontSize = dense ? (compact ? 11.5 : 12.0) : (compact ? 12.0 : 13.0);
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth, minHeight: height),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: active ? colors.accentStrong : Colors.white,
          backgroundColor: active
              ? colors.accentSoft
              : colors.overlayScrim.withValues(alpha: 0.18),
          overlayColor: Colors.white.withValues(alpha: 0.08),
          padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: 0),
          minimumSize: Size(minWidth, height),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(
              color: active
                  ? colors.accent.withValues(alpha: 0.95)
                  : Colors.white.withValues(alpha: 0.18),
              width: active ? 1.1 : 0.9,
            ),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: compact ? 0.2 : 0.3,
          ),
        ),
      ),
    );
  }
}

class PlayerTopAssetButton extends StatelessWidget {
  final String assetName;
  final VoidCallback onPressed;

  const PlayerTopAssetButton({
    super.key,
    required this.assetName,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.width < 900;
    final iconSize = compact ? 19.0 : 21.0;
    return Theme(
      data: Theme.of(
        context,
      ).copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      child: IconButton(
        onPressed: onPressed,
        icon: SvgPicture.asset(
          assetName,
          width: iconSize,
          height: iconSize,
          fit: BoxFit.contain,
        ),
        color: Colors.white,
        iconSize: iconSize,
        splashRadius: compact ? 15 : 16,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.all(compact ? 3.5 : 4.5),
        constraints: BoxConstraints(
          minWidth: compact ? 26 : 28,
          minHeight: compact ? 26 : 28,
        ),
      ),
    );
  }
}

class PlayerBottomControlButton extends StatelessWidget {
  final IconData icon;
  final bool loading;
  final bool compact;
  final bool emphasis;
  final double scale;
  final double? minSizeOverride;
  final double? paddingOverride;
  final VoidCallback onPressed;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressEndCallback? onLongPressEnd;

  const PlayerBottomControlButton({
    super.key,
    required this.icon,
    this.loading = false,
    this.compact = false,
    this.emphasis = false,
    this.scale = 1.0,
    this.minSizeOverride,
    this.paddingOverride,
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
    final effectiveScale = scale.clamp(0.7, 1.0);
    final effectiveMinSize =
        minSizeOverride ?? (minSize * effectiveScale).clamp(22.0, 60.0);
    final effectivePadding = paddingOverride ?? (edge * effectiveScale);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: onLongPressStart,
      onLongPressEnd: onLongPressEnd,
      child: Theme(
        data: Theme.of(
          context,
        ).copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
        child: IconButton(
          onPressed: loading ? null : onPressed,
          icon: _PlayerControlIcon(
            icon: icon,
            loading: loading,
            emphasis: emphasis,
            scale: effectiveScale,
          ),
          color: Colors.white,
          iconSize: iconSize * effectiveScale,
          splashRadius: splashRadius * effectiveScale,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.all(effectivePadding),
          constraints: BoxConstraints(
            minWidth: effectiveMinSize,
            minHeight: effectiveMinSize,
          ),
        ),
      ),
    );
  }
}

class PlayerBottomAssetControlButton extends StatelessWidget {
  final String assetName;
  final bool compact;
  final bool emphasis;
  final double scale;
  final double? minSizeOverride;
  final double? paddingOverride;
  final VoidCallback onPressed;

  const PlayerBottomAssetControlButton({
    super.key,
    required this.assetName,
    this.compact = false,
    this.emphasis = false,
    this.scale = 1.0,
    this.minSizeOverride,
    this.paddingOverride,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final useCompact = compact || MediaQuery.of(context).size.width < 900;
    final iconSize = emphasis
        ? (useCompact ? 30.0 : 34.0)
        : (useCompact ? 22.0 : 26.0);
    final splashRadius = emphasis
        ? (useCompact ? 22.0 : 26.0)
        : (useCompact ? 16.0 : 20.0);
    final edge = emphasis ? 0.0 : (useCompact ? 6.0 : 8.0);
    final minSize = emphasis
        ? (useCompact ? 46.0 : 54.0)
        : (useCompact ? 34.0 : 40.0);
    final effectiveScale = scale.clamp(0.7, 1.0);
    final effectiveMinSize =
        minSizeOverride ?? (minSize * effectiveScale).clamp(22.0, 60.0);
    final effectivePadding = paddingOverride ?? (edge * effectiveScale);
    return Theme(
      data: Theme.of(
        context,
      ).copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      child: IconButton(
        onPressed: onPressed,
        icon: SvgPicture.asset(
          assetName,
          width: iconSize * effectiveScale,
          height: iconSize * effectiveScale,
          fit: BoxFit.contain,
        ),
        color: Colors.white,
        iconSize: iconSize * effectiveScale,
        splashRadius: splashRadius * effectiveScale,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.all(effectivePadding),
        constraints: BoxConstraints(
          minWidth: effectiveMinSize,
          minHeight: effectiveMinSize,
        ),
      ),
    );
  }
}

class _PlayerControlIcon extends StatelessWidget {
  final IconData icon;
  final bool loading;
  final bool emphasis;
  final double scale;

  const _PlayerControlIcon({
    required this.icon,
    this.loading = false,
    required this.emphasis,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.width < 900;
    final iconSize = emphasis
        ? (compact ? 34.0 : 40.0)
        : (compact ? 24.0 : 28.0);
    final effectiveScale = scale.clamp(0.7, 1.0);
    if (loading) {
      final spinnerSize = (iconSize * effectiveScale * 0.58).clamp(14.0, 26.0);
      return SizedBox.square(
        dimension: spinnerSize,
        child: CircularProgressIndicator(
          strokeWidth: emphasis ? 2.6 : 2.2,
          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
    }
    return Icon(icon, size: iconSize * effectiveScale);
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

class PlayerActionIconChipButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const PlayerActionIconChipButton({
    super.key,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final useCompact = MediaQuery.of(context).size.width < 900;
    final size = useCompact ? 36.0 : 40.0;
    return SizedBox(
      width: size,
      height: size,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: colors.accentSoft,
          overlayColor: Colors.white.withValues(alpha: 0.08),
          padding: EdgeInsets.zero,
          minimumSize: Size(size, size),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(color: colors.accent, width: 1.2),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Icon(
          icon,
          size: useCompact ? 18 : 20,
          color: colors.accentStrong,
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

enum PlayerProgressMarkerKind { chapter, bookmark, abLoop }

class PlayerProgressChapterMarker {
  final double fraction;
  final bool active;
  final PlayerProgressMarkerKind kind;
  final bool snapTarget;

  const PlayerProgressChapterMarker({
    required this.fraction,
    this.active = false,
    this.kind = PlayerProgressMarkerKind.chapter,
    this.snapTarget = true,
  });
}

class PlayerProgressRangeHighlight {
  final double startFraction;
  final double endFraction;
  final bool active;

  const PlayerProgressRangeHighlight({
    required this.startFraction,
    required this.endFraction,
    this.active = true,
  });
}

class PlayerTimelineBar extends StatefulWidget {
  final double value;
  final double bufferedValue;
  final List<PlayerProgressChapterMarker> chapterMarkers;
  final PlayerProgressRangeHighlight? progressHighlight;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final VoidCallback? onInteractionStart;
  final VoidCallback? onInteractionEnd;

  const PlayerTimelineBar({
    super.key,
    required this.value,
    this.bufferedValue = 0,
    this.chapterMarkers = const <PlayerProgressChapterMarker>[],
    this.progressHighlight,
    this.onChangeStart,
    this.onChanged,
    this.onChangeEnd,
    this.onInteractionStart,
    this.onInteractionEnd,
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
    if (!_dragging) {
      widget.onInteractionStart?.call();
    }
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
    widget.onInteractionEnd?.call();
    setState(() {});
  }

  void _cancel() {
    if (!_dragging) return;
    _dragging = false;
    widget.onInteractionEnd?.call();
    setState(() {});
  }

  double _resolveFraction(double localDx, double width) {
    if (width <= 0) return 0;
    final fraction = (localDx / width).clamp(0.0, 1.0);
    final snapMarkers = widget.chapterMarkers
        .where((marker) => marker.snapTarget)
        .toList(growable: false);
    if (snapMarkers.isEmpty) return fraction;

    PlayerProgressChapterMarker? nearestMarker;
    double nearestDistance = double.infinity;
    for (final marker in snapMarkers) {
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
    final colors = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (details) => _begin(details.localPosition.dx, width),
          onTapUp: (_) => _end(),
          onTapCancel: _cancel,
          onHorizontalDragStart: (details) =>
              _begin(details.localPosition.dx, width),
          onHorizontalDragUpdate: (details) =>
              _update(details.localPosition.dx, width),
          onHorizontalDragEnd: (_) => _end(),
          onHorizontalDragCancel: _cancel,
          child: CustomPaint(
            size: Size(width, 34),
            painter: _PlayerTimelinePainter(
              value: _displayValue.clamp(0.0, 1.0),
              bufferedValue: widget.bufferedValue.clamp(0.0, 1.0),
              markers: widget.chapterMarkers,
              progressHighlight: widget.progressHighlight,
              activeColor: colors.accent,
              bufferedColor: Colors.white.withValues(alpha: 0.24),
              inactiveColor: Colors.white.withValues(alpha: 0.12),
              highlightColor: colors.accentSoft.withValues(alpha: 0.78),
            ),
          ),
        );
      },
    );
  }
}

class _PlayerTimelinePainter extends CustomPainter {
  final double value;
  final double bufferedValue;
  final List<PlayerProgressChapterMarker> markers;
  final PlayerProgressRangeHighlight? progressHighlight;
  final Color activeColor;
  final Color bufferedColor;
  final Color inactiveColor;
  final Color highlightColor;

  const _PlayerTimelinePainter({
    required this.value,
    required this.bufferedValue,
    required this.markers,
    required this.progressHighlight,
    required this.activeColor,
    required this.bufferedColor,
    required this.inactiveColor,
    required this.highlightColor,
  });

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
      ..color = inactiveColor
      ..isAntiAlias = true;
    canvas.drawRRect(trackRect, inactivePaint);

    final highlight = progressHighlight;
    if (highlight != null && highlight.active) {
      final start = (size.width * highlight.startFraction.clamp(0.0, 1.0))
          .clamp(0.0, size.width);
      final end = (size.width * highlight.endFraction.clamp(0.0, 1.0)).clamp(
        0.0,
        size.width,
      );
      if (end > start) {
        final highlightRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(start, trackTop, end - start, trackHeight),
          const Radius.circular(999),
        );
        final highlightPaint = Paint()
          ..color = highlightColor
          ..isAntiAlias = true;
        canvas.drawRRect(highlightRect, highlightPaint);
      }
    }

    final bufferedWidth = size.width * bufferedValue.clamp(0.0, 1.0);
    if (bufferedWidth > 0) {
      final bufferedRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          0,
          trackTop,
          bufferedWidth.clamp(0.0, size.width),
          trackHeight,
        ),
        const Radius.circular(999),
      );
      final bufferedPaint = Paint()
        ..color = bufferedColor
        ..isAntiAlias = true;
      canvas.drawRRect(bufferedRect, bufferedPaint);
    }

    final progressWidth = size.width * value;
    if (progressWidth > 0) {
      final activeRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          0,
          trackTop,
          progressWidth.clamp(0.0, size.width),
          trackHeight,
        ),
        const Radius.circular(999),
      );
      final activePaint = Paint()
        ..color = activeColor
        ..isAntiAlias = true;
      canvas.drawRRect(activeRect, activePaint);
    }

    for (final marker in markers) {
      final fraction = marker.fraction.clamp(0.0, 1.0);
      final dx = size.width * fraction;
      switch (marker.kind) {
        case PlayerProgressMarkerKind.chapter:
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
            ..color = Colors.white.withValues(
              alpha: marker.active ? 0.96 : 0.84,
            )
            ..isAntiAlias = true;
          final strokePaint = Paint()
            ..color = const Color(0xCC0B1117)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.45
            ..isAntiAlias = true;
          canvas.drawRRect(lineRect, linePaint);
          canvas.drawRRect(lineRect, strokePaint);
        case PlayerProgressMarkerKind.bookmark:
          final center = Offset(dx, trackTop - 2.0);
          final radius = marker.active ? 3.4 : 2.8;
          final fillPaint = Paint()
            ..color = activeColor.withValues(alpha: marker.active ? 0.96 : 0.84)
            ..isAntiAlias = true;
          final outlinePaint = Paint()
            ..color = const Color(0xCC0B1117)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8
            ..isAntiAlias = true;
          canvas.drawCircle(center, radius, fillPaint);
          canvas.drawCircle(center, radius, outlinePaint);
        case PlayerProgressMarkerKind.abLoop:
          final lineWidth = 2.6;
          final lineHeight = marker.active ? 12.0 : 10.0;
          final lineRect = RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(dx, size.height / 2),
              width: lineWidth,
              height: lineHeight,
            ),
            const Radius.circular(999),
          );
          final linePaint = Paint()
            ..color = highlightColor.withValues(
              alpha: marker.active ? 0.98 : 0.88,
            )
            ..isAntiAlias = true;
          final strokePaint = Paint()
            ..color = const Color(0xCC0B1117)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.5
            ..isAntiAlias = true;
          canvas.drawRRect(lineRect, linePaint);
          canvas.drawRRect(lineRect, strokePaint);
      }
    }

    final thumbCenter = Offset(
      progressWidth.clamp(0.0, size.width),
      size.height / 2,
    );
    final thumbPaint = Paint()
      ..color = Colors.white
      ..isAntiAlias = true;
    canvas.drawCircle(thumbCenter, thumbRadius, thumbPaint);
  }

  @override
  bool shouldRepaint(covariant _PlayerTimelinePainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.bufferedValue != bufferedValue ||
        oldDelegate.markers != markers ||
        oldDelegate.progressHighlight != progressHighlight ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.bufferedColor != bufferedColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.highlightColor != highlightColor;
  }
}
