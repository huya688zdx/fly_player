import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/app_theme.dart';
import '../controllers/mpv_player_controller.dart';
import 'player_overlay_sections.dart';
import 'mpv_player_widgets.dart';

class PlayerControlsTopBar extends StatelessWidget {
  final bool visible;
  final bool compactUi;
  final double titleFontSize;
  final String title;
  final bool showDownloadedBadge;
  final bool danmakuEnabled;
  final bool collapseActionsToSubtitleAndMore;
  final VoidCallback onBack;
  final VoidCallback onFitMode;
  final bool captureFrameBusy;
  final VoidCallback? onCaptureFrame;
  final bool showCacheDownloadAction;
  final bool cacheDownloadBusy;
  final VoidCallback? onCacheDownload;
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
    this.showDownloadedBadge = false,
    required this.danmakuEnabled,
    this.collapseActionsToSubtitleAndMore = false,
    required this.onBack,
    required this.onFitMode,
    this.captureFrameBusy = false,
    this.onCaptureFrame,
    this.showCacheDownloadAction = false,
    this.cacheDownloadBusy = false,
    this.onCacheDownload,
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
    final topActions = collapseActionsToSubtitleAndMore
        ? <Widget>[
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
          ]
        : <Widget>[
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
            if (showCacheDownloadAction && onCacheDownload != null)
              _PlayerTopGlassIconButton(
                icon: cacheDownloadBusy
                    ? Icons.downloading_rounded
                    : Icons.download_rounded,
                compact: compactUi,
                onPressed: onCacheDownload!,
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
          child: Row(
            children: [
              if (showDownloadedBadge) ...[
                _PlayerTopStatusBadge(compact: compactUi, label: '已下载'),
                SizedBox(width: compactUi ? 8 : 10),
              ],
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: compactUi ? 12 : 16),
                  child: PlayerMarqueeText(text: title, style: titleStyle),
                ),
              ),
            ],
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

class _PlayerTopStatusBadge extends StatelessWidget {
  final bool compact;
  final String label;

  const _PlayerTopStatusBadge({required this.compact, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final vertical = compact ? 5.0 : 6.0;
    final horizontal = compact ? 10.0 : 12.0;
    final fontSize = compact ? 13.0 : 14.0;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.overlayScrim.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: horizontal,
          vertical: vertical,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
      ),
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
  static const Duration _minimalSeekTransitionDuration = Duration(
    milliseconds: 220,
  );

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
  final PlayerResumePromptData? resumePrompt;
  final PlayerAutoPlayPromptData? autoPlayPrompt;
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
    this.resumePrompt,
    this.autoPlayPrompt,
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
          if (extendedChromeVisible && resumePrompt != null)
            _PlayerResumePromptCard(data: resumePrompt!),
          if (extendedChromeVisible && autoPlayPrompt != null)
            Align(
              alignment: Alignment.centerRight,
              child: _PlayerAutoPlayPromptCard(data: autoPlayPrompt!),
            ),
          SizedBox(height: compactUi ? 5 : 7),
          Padding(
            padding: EdgeInsets.only(left: compactUi ? 2 : 4),
            child: SizedBox(
              width: double.infinity,
              child: AnimatedAlign(
                duration: _minimalSeekTransitionDuration,
                curve: Curves.easeOutCubic,
                alignment: minimalSeekMode
                    ? Alignment.center
                    : Alignment.centerLeft,
                child: AnimatedSlide(
                  duration: _minimalSeekTransitionDuration,
                  curve: Curves.easeOutCubic,
                  offset: minimalSeekMode
                      ? Offset.zero
                      : Offset(compactUi ? -0.04 : -0.06, 0),
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
          if (bottomControls != null)
            Visibility(
              visible: extendedChromeVisible,
              maintainState: minimalSeekMode,
              maintainAnimation: minimalSeekMode,
              maintainSize: minimalSeekMode,
              child: bottomControls!,
            ),
        ],
      ),
    );
  }
}

class _PlayerResumePromptCard extends StatelessWidget {
  final PlayerResumePromptData data;

  const _PlayerResumePromptCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return _PlayerPromptCardShell(
      maxWidth: 360,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              data.message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: data.onRestart,
            style: TextButton.styleFrom(
              foregroundColor: colors.accentStrong,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
              minimumSize: const Size(0, 22),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              data.restartLabel,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _PlayerPromptCloseButton(onPressed: data.onDismiss),
        ],
      ),
    );
  }
}

class _PlayerAutoPlayPromptCard extends StatelessWidget {
  final PlayerAutoPlayPromptData data;

  const _PlayerAutoPlayPromptCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return _PlayerPromptCardShell(
      maxWidth: 420,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              data.message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _PlayerPromptCloseButton(onPressed: data.onSkip),
          IconButton(
            onPressed: data.onReplay,
            icon: const Icon(Icons.check_rounded),
            color: colors.accentStrong,
            iconSize: 18,
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            splashRadius: 14,
          ),
        ],
      ),
    );
  }
}

class _PlayerPromptCardShell extends StatelessWidget {
  final double maxWidth;
  final Widget child;

  const _PlayerPromptCardShell({required this.maxWidth, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth, minHeight: 42),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.only(left: 12, right: 6, top: 7, bottom: 7),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colors.surfaceSubtle.withValues(alpha: 0.26),
          colors.overlayScrim.withValues(alpha: 0.52),
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.surfaceStrong.withValues(alpha: 0.42)),
      ),
      child: child,
    );
  }
}

class _PlayerPromptCloseButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _PlayerPromptCloseButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return IconButton(
      onPressed: onPressed,
      icon: const Icon(Icons.close_rounded),
      color: colors.textSecondary.withValues(alpha: 0.92),
      iconSize: 15,
      padding: const EdgeInsets.all(2),
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      splashRadius: 13,
    );
  }
}
