import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import 'player_system_controls.dart';

class PlayerAdjustmentOverlayData {
  final PlayerAdjustmentType type;
  final double value;

  const PlayerAdjustmentOverlayData({required this.type, required this.value});
}

class PlayerGestureTapCoordinator {
  Timer? pendingTapTimer;
  DateTime? lastTapTime;
  Offset? lastTapPosition;
  Offset? currentTapPosition;

  void clear({bool clearCurrentTapPosition = true}) {
    pendingTapTimer = null;
    lastTapTime = null;
    lastTapPosition = null;
    if (clearCurrentTapPosition) {
      currentTapPosition = null;
    }
  }

  void cancel() {
    pendingTapTimer?.cancel();
    clear();
  }

  void dispose() {
    pendingTapTimer?.cancel();
    clear();
  }
}

class PlayerGestureLayer extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final bool deferSingleTapForDoubleTap;
  final PlayerGestureTapCoordinator? tapCoordinator;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressEndCallback? onLongPressEnd;
  final VoidCallback? onLongPressCancel;
  final GestureDragStartCallback? onHorizontalDragStart;
  final GestureDragUpdateCallback? onHorizontalDragUpdate;
  final GestureDragEndCallback? onHorizontalDragEnd;
  final GestureDragCancelCallback? onHorizontalDragCancel;
  final GestureDragStartCallback? onVerticalDragStart;
  final GestureDragUpdateCallback? onVerticalDragUpdate;
  final GestureDragEndCallback? onVerticalDragEnd;
  final GestureDragCancelCallback? onVerticalDragCancel;

  const PlayerGestureLayer({
    super.key,
    this.child = const SizedBox.expand(),
    this.onTap,
    this.onDoubleTap,
    this.deferSingleTapForDoubleTap = true,
    this.tapCoordinator,
    this.onLongPressStart,
    this.onLongPressEnd,
    this.onLongPressCancel,
    this.onHorizontalDragStart,
    this.onHorizontalDragUpdate,
    this.onHorizontalDragEnd,
    this.onHorizontalDragCancel,
    this.onVerticalDragStart,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
    this.onVerticalDragCancel,
  });

  @override
  State<PlayerGestureLayer> createState() => _PlayerGestureLayerState();
}

class _PlayerGestureLayerState extends State<PlayerGestureLayer> {
  static const Duration _doubleTapMaxInterval = Duration(milliseconds: 300);
  static const double _doubleTapMaxDistance = 56;

  late final PlayerGestureTapCoordinator _localTapCoordinator =
      PlayerGestureTapCoordinator();

  PlayerGestureTapCoordinator get _tapCoordinator =>
      widget.tapCoordinator ?? _localTapCoordinator;

  @override
  void dispose() {
    if (widget.tapCoordinator == null) {
      _localTapCoordinator.dispose();
    }
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _tapCoordinator.currentTapPosition = details.localPosition;
  }

  void _handleTapCancel() {
    _tapCoordinator.currentTapPosition = null;
  }

  bool get _useNativeDeferredDoubleTapHandling =>
      widget.onDoubleTap != null && widget.deferSingleTapForDoubleTap;

  void _handleDeferredTap() {
    _clearTapTracking();
    widget.onTap?.call();
  }

  void _handleDeferredDoubleTap() {
    _clearTapTracking();
    widget.onDoubleTap?.call();
  }

  void _handleTap() {
    final now = DateTime.now();
    final tapPosition = _tapCoordinator.currentTapPosition;
    final hasPendingTap = _tapCoordinator.pendingTapTimer?.isActive ?? false;

    if (widget.onDoubleTap == null) {
      widget.onTap?.call();
      return;
    }

    final withinInterval =
        _tapCoordinator.lastTapTime != null &&
        now.difference(_tapCoordinator.lastTapTime!) <= _doubleTapMaxInterval;
    final withinDistance =
        tapPosition != null &&
        _tapCoordinator.lastTapPosition != null &&
        (tapPosition - _tapCoordinator.lastTapPosition!).distance <=
            _doubleTapMaxDistance;

    if (!widget.deferSingleTapForDoubleTap) {
      if (hasPendingTap && withinInterval && withinDistance) {
        _tapCoordinator.pendingTapTimer?.cancel();
        _clearTapTracking();
        widget.onDoubleTap?.call();
        return;
      }

      _tapCoordinator.pendingTapTimer?.cancel();
      widget.onTap?.call();
      _tapCoordinator.lastTapTime = now;
      _tapCoordinator.lastTapPosition = tapPosition;
      _tapCoordinator.pendingTapTimer = Timer(_doubleTapMaxInterval, () {
        _tapCoordinator.pendingTapTimer = null;
        _clearTapTracking(clearCurrentTapPosition: false);
      });
      return;
    }

    if (hasPendingTap && withinInterval && withinDistance) {
      _tapCoordinator.pendingTapTimer?.cancel();
      _clearTapTracking();
      widget.onDoubleTap?.call();
      return;
    }

    if (hasPendingTap) {
      _tapCoordinator.pendingTapTimer?.cancel();
      final pendingSingleTap = widget.onTap;
      _clearTapTracking(clearCurrentTapPosition: false);
      pendingSingleTap?.call();
    }

    _tapCoordinator.lastTapTime = now;
    _tapCoordinator.lastTapPosition = tapPosition;
    _tapCoordinator.pendingTapTimer = Timer(_doubleTapMaxInterval, () {
      _tapCoordinator.pendingTapTimer = null;
      final singleTap = widget.onTap;
      _clearTapTracking(clearCurrentTapPosition: false);
      singleTap?.call();
    });
  }

  void _clearTapTracking({bool clearCurrentTapPosition = true}) {
    _tapCoordinator.clear(clearCurrentTapPosition: clearCurrentTapPosition);
  }

  void _cancelPendingTapRecognition() {
    _tapCoordinator.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _handleTapDown,
      onTapCancel: _handleTapCancel,
      onTap: _useNativeDeferredDoubleTapHandling
          ? _handleDeferredTap
          : _handleTap,
      onDoubleTap: _useNativeDeferredDoubleTapHandling
          ? _handleDeferredDoubleTap
          : null,
      onLongPressStart: widget.onLongPressStart == null
          ? null
          : (details) {
              _cancelPendingTapRecognition();
              widget.onLongPressStart?.call(details);
            },
      onLongPressEnd: widget.onLongPressEnd,
      onLongPressCancel: widget.onLongPressCancel,
      onHorizontalDragStart: widget.onHorizontalDragStart == null
          ? null
          : (details) {
              _cancelPendingTapRecognition();
              widget.onHorizontalDragStart?.call(details);
            },
      onHorizontalDragUpdate: widget.onHorizontalDragUpdate,
      onHorizontalDragEnd: widget.onHorizontalDragEnd,
      onHorizontalDragCancel: widget.onHorizontalDragCancel,
      onVerticalDragStart: widget.onVerticalDragStart == null
          ? null
          : (details) {
              _cancelPendingTapRecognition();
              widget.onVerticalDragStart?.call(details);
            },
      onVerticalDragUpdate: widget.onVerticalDragUpdate,
      onVerticalDragEnd: widget.onVerticalDragEnd,
      onVerticalDragCancel: widget.onVerticalDragCancel,
      child: widget.child,
    );
  }
}

class PlayerGestureOverlay extends StatelessWidget {
  final PlayerAdjustmentOverlayData? adjustment;
  final bool speedBoostActive;
  final String? statusMessage;
  final bool statusLoading;

  const PlayerGestureOverlay({
    super.key,
    required this.adjustment,
    required this.speedBoostActive,
    this.statusMessage,
    this.statusLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final adjustmentData = adjustment;
    final status = statusMessage?.trim() ?? '';
    final media = MediaQuery.of(context);
    if (adjustmentData == null && !speedBoostActive && status.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (status.isNotEmpty) const SafeArea(child: SizedBox.expand()),
            if (status.isNotEmpty)
              Positioned(
                top: _statusBannerTopOffset(media),
                left: 16,
                right: 16,
                child: Center(
                  child: _StatusBanner(
                    message: status,
                    showSpinner: statusLoading,
                  ),
                ),
              ),
            if (adjustmentData != null)
              Positioned.fill(
                child: Center(
                  child: _AdjustmentIndicator(data: adjustmentData),
                ),
              ),
            if (speedBoostActive)
              const Positioned(
                top: 18,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Center(child: _SpeedBoostIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

double _statusBannerTopOffset(MediaQueryData media) {
  final shortestSide = media.size.shortestSide;
  final isLandscape = media.orientation == Orientation.landscape;
  final width = media.size.width;
  final adaptiveSpacing = (shortestSide * (isLandscape ? 0.085 : 0.105)).clamp(
    34.0,
    56.0,
  );
  final compactBoost = width < 900 ? 12.0 : 6.0;
  final visualDrop = isLandscape ? 14.0 : 10.0;
  return media.padding.top + adaptiveSpacing + compactBoost + visualDrop;
}

class PlayerLoadingOverlay extends StatelessWidget {
  final bool visible;
  final String message;
  final String? secondaryMessage;

  const PlayerLoadingOverlay({
    super.key,
    required this.visible,
    this.message = '',
    this.secondaryMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return const SizedBox.shrink();
    }

    final colors = context.appColors;
    final media = MediaQuery.of(context);
    final scale = (media.size.shortestSide / 411).clamp(0.72, 1.12);
    final spinnerSize = 18.0 * scale;
    final textSize = 14.0 * scale;
    final spacing = 14.0 * scale;
    final primaryMessage = message.trim().isEmpty
        ? AppLocalizations.of(context).playerLoadingVideo
        : message;
    final details = secondaryMessage?.trim() ?? '';

    return IgnorePointer(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: spinnerSize,
              height: spinnerSize,
              child: CircularProgressIndicator(
                strokeWidth: 2.4 * scale,
                valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
              ),
            ),
            SizedBox(height: spacing),
            Text(
              primaryMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: textSize,
                fontWeight: FontWeight.w500,
                height: 1.2,
                shadows: const <Shadow>[
                  Shadow(
                    color: Color(0x90000000),
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
            if (details.isNotEmpty) ...[
              SizedBox(height: 8.0 * scale),
              Text(
                details,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: 11.8 * scale,
                  fontWeight: FontWeight.w400,
                  height: 1.25,
                  shadows: const <Shadow>[
                    Shadow(
                      color: Color(0x90000000),
                      blurRadius: 10,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class PlayerWeakNetworkSuggestionOverlay extends StatelessWidget {
  final bool visible;
  final String title;
  final String subtitle;
  final VoidCallback onSwitch;
  final VoidCallback onDismiss;

  const PlayerWeakNetworkSuggestionOverlay({
    super.key,
    required this.visible,
    required this.title,
    required this.subtitle,
    required this.onSwitch,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return _PlayerEdgeNoticeOverlay(
      visible: visible,
      child: _PlayerWeakNetworkSuggestionCard(
        title: title,
        subtitle: subtitle,
        onSwitch: onSwitch,
        onDismiss: onDismiss,
      ),
    );
  }
}

class PlayerSkipPromptOverlay extends StatelessWidget {
  final bool visible;
  final String label;
  final int countdownSeconds;
  final VoidCallback onClose;

  const PlayerSkipPromptOverlay({
    super.key,
    required this.visible,
    required this.label,
    required this.countdownSeconds,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = countdownSeconds > 0
        ? l10n.playerSkipPromptCountdown(countdownSeconds, label)
        : l10n.playerSkipPromptSoon(label);

    return _PlayerEdgeNoticeOverlay(
      visible: visible,
      child: _PlayerEdgeNoticeCard(
        title: title,
        subtitle: l10n.playerSkipPromptDismissSubtitle,
        onClose: onClose,
      ),
    );
  }
}

class PlayerCenterMessageOverlay extends StatelessWidget {
  final String? message;

  const PlayerCenterMessageOverlay({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    final text = message?.trim() ?? '';
    final media = MediaQuery.of(context);
    final liftOffset = (media.size.height * 0.12).clamp(56.0, 104.0);
    return IgnorePointer(
      child: _PlayerCenterNoticeOverlay(
        visible: text.isNotEmpty,
        verticalLift: liftOffset,
        child: _PlayerEdgeNoticeCard(title: text, centerText: true),
      ),
    );
  }
}

class _PlayerCenterNoticeOverlay extends StatelessWidget {
  final bool visible;
  final double verticalLift;
  final Widget child;

  const _PlayerCenterNoticeOverlay({
    required this.visible,
    required this.verticalLift,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.center,
        child: Transform.translate(
          offset: Offset(0, -verticalLift),
          child: IgnorePointer(
            ignoring: !visible,
            child: AnimatedSlide(
              offset: visible ? Offset.zero : const Offset(0, 0.08),
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerEdgeNoticeOverlay extends StatelessWidget {
  final bool visible;
  final Widget child;

  const _PlayerEdgeNoticeOverlay({required this.visible, required this.child});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scale = (media.size.shortestSide / 411).clamp(0.74, 0.92);
    final leftOffset = 18.0 * scale;
    final bottomOffset = 140.0 * scale;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(left: leftOffset, bottom: bottomOffset),
        child: Align(
          alignment: Alignment.bottomLeft,
          child: IgnorePointer(
            ignoring: !visible,
            child: AnimatedSlide(
              offset: visible ? Offset.zero : const Offset(-0.2, 0),
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerEdgeNoticeCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onClose;
  final bool centerText;

  const _PlayerEdgeNoticeCard({
    required this.title,
    this.subtitle,
    this.onClose,
    this.centerText = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final media = MediaQuery.of(context);
    final scale = (media.size.shortestSide / 411).clamp(0.74, 0.92);
    final maxWidth = (media.size.width * 0.42).clamp(220.0, 320.0);
    final hasClose = onClose != null;
    final subtitleText = subtitle?.trim() ?? '';

    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.backgroundElevated.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(15 * scale),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              15 * scale,
              11 * scale,
              hasClose ? 8 * scale : 15 * scale,
              11 * scale,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: centerText
                        ? CrossAxisAlignment.center
                        : CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        textAlign: centerText
                            ? TextAlign.center
                            : TextAlign.left,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.6 * scale,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      if (subtitleText.isNotEmpty) ...[
                        SizedBox(height: 5 * scale),
                        Text(
                          subtitleText,
                          textAlign: centerText
                              ? TextAlign.center
                              : TextAlign.left,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 11.1 * scale,
                            fontWeight: FontWeight.w400,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (hasClose) ...[
                  SizedBox(width: 6 * scale),
                  IconButton(
                    onPressed: onClose,
                    splashRadius: 15 * scale,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.close_rounded,
                      color: colors.textPrimary.withValues(alpha: 0.9),
                      size: 17 * scale,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerWeakNetworkSuggestionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onSwitch;
  final VoidCallback onDismiss;

  const _PlayerWeakNetworkSuggestionCard({
    required this.title,
    required this.subtitle,
    required this.onSwitch,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final media = MediaQuery.of(context);
    final scale = (media.size.shortestSide / 411).clamp(0.74, 0.92);
    final maxWidth = (media.size.width * 0.48).clamp(236.0, 332.0);

    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.backgroundElevated.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(16 * scale),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              15 * scale,
              12 * scale,
              15 * scale,
              12 * scale,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.8 * scale,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
                if (subtitle.trim().isNotEmpty) ...[
                  SizedBox(height: 5 * scale),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 11.1 * scale,
                      fontWeight: FontWeight.w400,
                      height: 1.25,
                    ),
                  ),
                ],
                SizedBox(height: 10 * scale),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: onDismiss,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.textSecondary,
                        padding: EdgeInsets.symmetric(
                          horizontal: 10 * scale,
                          vertical: 7 * scale,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(
                        '\u6682\u4e0d',
                        style: TextStyle(
                          fontSize: 11.4 * scale,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    SizedBox(width: 6 * scale),
                    FilledButton(
                      onPressed: onSwitch,
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.accent,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          horizontal: 12 * scale,
                          vertical: 8 * scale,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(
                        '\u5207\u6362',
                        style: TextStyle(
                          fontSize: 11.6 * scale,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String message;
  final bool showSpinner;

  const _StatusBanner({required this.message, required this.showSpinner});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final media = MediaQuery.of(context);
    final scale = (media.size.shortestSide / 411).clamp(0.8, 1.02);
    final maxWidth = (media.size.width * 0.8).clamp(240.0, 420.0);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.backgroundElevated.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(14 * scale),
          border: Border.all(
            color: colors.borderSubtle.withValues(alpha: 0.85),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 16 * scale,
            vertical: 13 * scale,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (showSpinner) ...[
                SizedBox(
                  width: 15 * scale,
                  height: 15 * scale,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.1 * scale,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      colors.accentStrong,
                    ),
                  ),
                ),
                SizedBox(width: 10 * scale),
              ],
              Flexible(
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  strutStyle: StrutStyle(
                    fontSize: 13.4 * scale,
                    height: 1.32,
                    forceStrutHeight: true,
                  ),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.4 * scale,
                    fontWeight: FontWeight.w500,
                    height: 1.32,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdjustmentIndicator extends StatelessWidget {
  final PlayerAdjustmentOverlayData data;

  const _AdjustmentIndicator({required this.data});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final media = MediaQuery.of(context);
    final scale = (media.size.shortestSide / 411).clamp(0.76, 1.0);
    final panelWidth = (media.size.width * 0.44).clamp(210.0, 280.0) * scale;
    final iconSize = 24.0 * scale;
    final barHeight = 6.0 * scale;
    final icon = switch (data.type) {
      PlayerAdjustmentType.brightness => Icons.wb_sunny_rounded,
      PlayerAdjustmentType.volume =>
        data.value <= 0.01 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      width: panelWidth,
      padding: EdgeInsets.symmetric(
        horizontal: 14 * scale,
        vertical: 11 * scale,
      ),
      decoration: BoxDecoration(
        color: colors.backgroundElevated.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(15 * scale),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: iconSize),
          SizedBox(width: 12 * scale),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: barHeight,
                child: LinearProgressIndicator(
                  value: data.value.clamp(0.0, 1.0),
                  backgroundColor: Colors.white.withValues(alpha: 0.14),
                  valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeedBoostIndicator extends StatefulWidget {
  const _SpeedBoostIndicator();

  @override
  State<_SpeedBoostIndicator> createState() => _SpeedBoostIndicatorState();
}

class _SpeedBoostIndicatorState extends State<_SpeedBoostIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final media = MediaQuery.of(context);
    final scale = (media.size.shortestSide / 411).clamp(0.76, 1.0);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.backgroundElevated.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(15 * scale),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16 * scale,
          vertical: 9 * scale,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '2X',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15 * scale,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(width: 8 * scale),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List<Widget>.generate(2, (index) {
                    final offsetSeed = (_controller.value + index * 0.24) % 1.0;
                    final opacity = (1.0 - (offsetSeed - 0.5).abs() * 1.7)
                        .clamp(0.25, 1.0);
                    return Transform.translate(
                      offset: Offset(offsetSeed * 6, 0),
                      child: Opacity(
                        opacity: opacity,
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
