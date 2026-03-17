import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/app_theme.dart';
import '../controllers/mpv_player_controller.dart';
import 'mpv_player_widgets.dart';

class PlayerControlsTopBar extends StatelessWidget {
  final bool visible;
  final bool compactUi;
  final double titleFontSize;
  final String title;
  final bool danmakuEnabled;
  final VoidCallback onBack;
  final VoidCallback onFitMode;
  final bool captureFrameBusy;
  final VoidCallback? onCaptureFrame;
  final String? abLoopLabel;
  final bool abLoopActive;
  final VoidCallback? onAbLoop;
  final VoidCallback onDanmakuSettings;
  final VoidCallback onMore;

  const PlayerControlsTopBar({
    super.key,
    required this.visible,
    required this.compactUi,
    required this.titleFontSize,
    required this.title,
    required this.danmakuEnabled,
    required this.onBack,
    required this.onFitMode,
    this.captureFrameBusy = false,
    this.onCaptureFrame,
    this.abLoopLabel,
    this.abLoopActive = false,
    this.onAbLoop,
    required this.onDanmakuSettings,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return const SizedBox.shrink();
    }
    final spacing = compactUi ? 8.0 : 10.0;
    final titleStyle = TextStyle(
      color: Colors.white,
      fontSize: titleFontSize,
      fontWeight: FontWeight.w600,
    );
    final topActions = <Widget>[
      if (onCaptureFrame != null)
        _PlayerTopGlassIconButton(
          icon: captureFrameBusy
              ? Icons.downloading_rounded
              : Icons.photo_camera_outlined,
          compact: compactUi,
          onPressed: onCaptureFrame!,
        ),
      if (abLoopLabel != null && onAbLoop != null)
        _PlayerTopGlassPillButton(
          label: abLoopLabel!,
          compact: compactUi,
          active: abLoopActive,
          onPressed: onAbLoop!,
        )
      else
        _PlayerTopGlassIconButton(
          icon: Icons.fit_screen_outlined,
          compact: compactUi,
          onPressed: onFitMode,
        ),
      if (danmakuEnabled)
        _PlayerTopGlassAssetButton(
          assetName: 'assets/icons/player_danmaku_settings.svg',
          compact: compactUi,
          onPressed: onDanmakuSettings,
        ),
      _PlayerTopGlassIconButton(
        icon: Icons.more_horiz_rounded,
        compact: compactUi,
        onPressed: onMore,
      ),
    ];
    return Row(
      children: [
        _PlayerTopGlassIconButton(
          icon: Icons.arrow_back_ios_new_rounded,
          compact: compactUi,
          onPressed: onBack,
        ),
        SizedBox(width: compactUi ? 12 : 14),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: compactUi ? 12 : 16),
            child: PlayerMarqueeText(text: title, style: titleStyle),
          ),
        ),
        Wrap(
          spacing: spacing,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: topActions,
        ),
      ],
    );
  }
}

class _PlayerTopGlassIconButton extends StatelessWidget {
  final IconData icon;
  final bool compact;
  final VoidCallback onPressed;

  const _PlayerTopGlassIconButton({
    required this.icon,
    required this.compact,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final size = compact ? 34.0 : 38.0;
    final iconSize = compact ? 18.0 : 20.0;
    return SizedBox(
      width: size,
      height: size,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: colors.overlayScrim.withValues(alpha: 0.24),
          overlayColor: Colors.white.withValues(alpha: 0.08),
          padding: EdgeInsets.zero,
          minimumSize: Size(size, size),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Icon(icon, size: iconSize),
      ),
    );
  }
}

class _PlayerTopGlassAssetButton extends StatelessWidget {
  final String assetName;
  final bool compact;
  final VoidCallback onPressed;

  const _PlayerTopGlassAssetButton({
    required this.assetName,
    required this.compact,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final size = compact ? 34.0 : 38.0;
    final iconSize = compact ? 17.0 : 19.0;
    return SizedBox(
      width: size,
      height: size,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: colors.overlayScrim.withValues(alpha: 0.24),
          overlayColor: Colors.white.withValues(alpha: 0.08),
          padding: EdgeInsets.zero,
          minimumSize: Size(size, size),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: SvgPicture.asset(
          assetName,
          width: iconSize,
          height: iconSize,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class _PlayerTopGlassPillButton extends StatelessWidget {
  final String label;
  final bool compact;
  final bool active;
  final VoidCallback onPressed;

  const _PlayerTopGlassPillButton({
    required this.label,
    required this.compact,
    required this.active,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final height = compact ? 34.0 : 38.0;
    final horizontal = compact ? 12.0 : 14.0;
    final minWidth = compact ? 48.0 : 54.0;
    final fontSize = compact ? 14.0 : 15.0;
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth, minHeight: height),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: active ? colors.accentStrong : Colors.white,
          backgroundColor: active
              ? colors.accentSoft
              : colors.overlayScrim.withValues(alpha: 0.24),
          overlayColor: Colors.white.withValues(alpha: 0.08),
          padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: 0),
          minimumSize: Size(minWidth, height),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(
              color: active
                  ? colors.accent.withValues(alpha: 0.92)
                  : Colors.white.withValues(alpha: 0.14),
              width: active ? 1.15 : 1.0,
            ),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

class PlayerControlsBottomPanel extends StatelessWidget {
  final bool panelVisible;
  final bool extendedChromeVisible;
  final bool compactUi;
  final bool isLandscape;
  final bool minimalSeekMode;
  final bool showStatusCard;
  final double timeFontSize;
  final Duration duration;
  final Duration clampedPosition;
  final Duration bufferedPosition;
  final List<MpvChapterItem> visibleChapters;
  final int activeChapterIndex;
  final List<PlayerProgressChapterMarker> extraProgressMarkers;
  final PlayerProgressRangeHighlight? progressHighlight;
  final MpvPlayerValue value;
  final Widget? statusCard;
  final Widget? bottomControls;
  final ValueChanged<double>? onTimelineChangeStart;
  final ValueChanged<double>? onTimelineChanged;
  final ValueChanged<double>? onTimelineChangeEnd;
  final VoidCallback? onTimelineInteractionStart;
  final VoidCallback? onTimelineInteractionEnd;
  final VoidCallback? onToggleOrientation;
  final String Function(Duration value) formatDuration;

  const PlayerControlsBottomPanel({
    super.key,
    required this.panelVisible,
    required this.extendedChromeVisible,
    required this.compactUi,
    required this.isLandscape,
    required this.minimalSeekMode,
    required this.showStatusCard,
    required this.timeFontSize,
    required this.duration,
    required this.clampedPosition,
    required this.bufferedPosition,
    required this.visibleChapters,
    required this.activeChapterIndex,
    this.extraProgressMarkers = const <PlayerProgressChapterMarker>[],
    this.progressHighlight,
    required this.value,
    required this.statusCard,
    required this.bottomControls,
    required this.onTimelineChangeStart,
    required this.onTimelineChanged,
    required this.onTimelineChangeEnd,
    required this.onTimelineInteractionStart,
    required this.onTimelineInteractionEnd,
    required this.onToggleOrientation,
    required this.formatDuration,
  });

  @override
  Widget build(BuildContext context) {
    if (!panelVisible) {
      return const SizedBox.shrink();
    }
    final markerData = duration.inMilliseconds <= 0
        ? const <PlayerProgressChapterMarker>[]
        : visibleChapters
              .where(
                (chapter) =>
                    chapter.time > Duration.zero && chapter.time < duration,
              )
              .map(
                (chapter) => PlayerProgressChapterMarker(
                  fraction:
                      chapter.time.inMilliseconds / duration.inMilliseconds,
                  active: chapter.index == activeChapterIndex,
                  kind: PlayerProgressMarkerKind.chapter,
                  snapTarget: true,
                ),
              )
              .toList(growable: false);
    final timelineMarkers = <PlayerProgressChapterMarker>[
      ...markerData,
      ...extraProgressMarkers,
    ];
    final orientationCallback = onToggleOrientation;
    return Transform.translate(
      offset: Offset(0, compactUi ? 4 : 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showStatusCard && extendedChromeVisible && statusCard != null)
            statusCard!,
          SizedBox(height: compactUi ? 5 : 7),
          Padding(
            padding: EdgeInsets.only(left: compactUi ? 2 : 4),
            child: Align(
              alignment: minimalSeekMode
                  ? Alignment.center
                  : Alignment.centerLeft,
              child: Transform.translate(
                offset: Offset(minimalSeekMode ? (compactUi ? 6 : 8) : 0, 0),
                child: Text(
                  '${formatDuration(clampedPosition)}/${formatDuration(duration)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: timeFontSize,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: compactUi ? 3 : 4),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: compactUi ? 34 : 36,
                  child: PlayerTimelineBar(
                    value: duration.inMilliseconds > 0
                        ? clampedPosition.inMilliseconds
                                  .clamp(0, duration.inMilliseconds)
                                  .toDouble() /
                              duration.inMilliseconds
                        : 0,
                    bufferedValue: duration.inMilliseconds > 0
                        ? bufferedPosition.inMilliseconds
                                  .clamp(0, duration.inMilliseconds)
                                  .toDouble() /
                              duration.inMilliseconds
                        : 0,
                    chapterMarkers: timelineMarkers,
                    progressHighlight: progressHighlight,
                    onInteractionStart: onTimelineInteractionStart,
                    onInteractionEnd: onTimelineInteractionEnd,
                    onChangeStart: onTimelineChangeStart,
                    onChanged: onTimelineChanged,
                    onChangeEnd: onTimelineChangeEnd,
                  ),
                ),
              ),
              SizedBox(width: compactUi ? 2 : 4),
              if (!minimalSeekMode && orientationCallback != null)
                PlayerProgressIconButton(onPressed: orientationCallback),
            ],
          ),
          SizedBox(height: compactUi ? 2 : 4),
          if (extendedChromeVisible && bottomControls != null) bottomControls!,
        ],
      ),
    );
  }
}
