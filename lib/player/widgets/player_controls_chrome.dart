import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../controllers/mpv_player_controller.dart';
import 'player_overlay_sections.dart';
import 'mpv_player_widgets.dart';

class PlayerControlsTopBar extends StatelessWidget {
  final bool visible;
  final bool compactUi;
  final bool showSystemStatus;
  final double titleFontSize;
  final String title;
  final String systemTimeLabel;
  final String systemNetworkType;
  final int? systemBatteryLevel;
  final bool systemBatteryCharging;
  final bool showDownloadedBadge;
  final bool danmakuEnabled;
  final bool collapseActionsToSubtitleAndMore;
  final VoidCallback onBack;
  final bool showPictureInPictureAction;
  final VoidCallback? onPictureInPicture;
  final bool showListenVideoAction;
  final bool listenVideoActive;
  final VoidCallback? onToggleListenVideo;
  final bool showFitModeAction;
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
    this.showSystemStatus = false,
    required this.titleFontSize,
    required this.title,
    this.systemTimeLabel = '',
    this.systemNetworkType = 'unknown',
    this.systemBatteryLevel,
    this.systemBatteryCharging = false,
    this.showDownloadedBadge = false,
    required this.danmakuEnabled,
    this.collapseActionsToSubtitleAndMore = false,
    required this.onBack,
    this.showPictureInPictureAction = false,
    this.onPictureInPicture,
    this.showListenVideoAction = false,
    this.listenVideoActive = false,
    this.onToggleListenVideo,
    this.showFitModeAction = true,
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
    final compactActionMode = collapseActionsToSubtitleAndMore;
    final titleStyle = TextStyle(
      color: Colors.white,
      fontSize: titleFontSize,
      fontWeight: FontWeight.w600,
    );
    final topActions = <Widget>[
      if (showPictureInPictureAction && onPictureInPicture != null)
        _PlayerTopGlassIconButton(
          icon: Icons.picture_in_picture_alt_outlined,
          compact: compactUi,
          onPressed: onPictureInPicture!,
        ),
      if (showListenVideoAction && onToggleListenVideo != null)
        _PlayerTopGlassAssetButton(
          assetName: 'assets/icons/listen_video.svg',
          compact: compactUi,
          active: listenVideoActive,
          tintWithForeground: true,
          onPressed: onToggleListenVideo!,
        ),
      if (!compactActionMode && onCaptureFrame != null)
        _PlayerTopGlassIconButton(
          icon: captureFrameBusy
              ? Icons.downloading_rounded
              : Icons.photo_camera_outlined,
          compact: compactUi,
          onPressed: onCaptureFrame!,
        ),
      if (!compactActionMode && abLoopLabel != null && onAbLoop != null)
        _PlayerTopGlassLabelButton(
          label: abLoopLabel!,
          compact: compactUi,
          active: abLoopActive,
          onPressed: onAbLoop!,
        )
      else if (!compactActionMode && showFitModeAction)
        _PlayerTopGlassIconButton(
          icon: Icons.fit_screen_outlined,
          compact: compactUi,
          onPressed: onFitMode,
        ),
      if (!compactActionMode && danmakuEnabled)
        _PlayerTopGlassAssetButton(
          assetName: 'assets/icons/player_danmaku_settings.svg',
          compact: compactUi,
          onPressed: onDanmakuSettings,
        ),
      if (!compactActionMode &&
          showCacheDownloadAction &&
          onCacheDownload != null)
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showSystemStatus) ...[
          _PlayerTopSystemStatusRow(
            compact: compactUi,
            timeLabel: systemTimeLabel,
            networkType: systemNetworkType,
            batteryLevel: systemBatteryLevel,
            charging: systemBatteryCharging,
          ),
          SizedBox(height: compactUi ? 6 : 8),
        ],
        Row(
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
                    _PlayerTopStatusBadge(
                      compact: compactUi,
                      label: AppLocalizations.of(context).playerDownloadedBadge,
                    ),
                    SizedBox(width: compactUi ? 8 : 10),
                  ],
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: compactActionMode ? 8 : (compactUi ? 12 : 16),
                      ),
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
        ),
      ],
    );
  }
}

class _PlayerTopSystemStatusRow extends StatelessWidget {
  final bool compact;
  final String timeLabel;
  final String networkType;
  final int? batteryLevel;
  final bool charging;

  const _PlayerTopSystemStatusRow({
    required this.compact,
    required this.timeLabel,
    required this.networkType,
    required this.batteryLevel,
    required this.charging,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.94),
      fontSize: compact ? 11.0 : 12.0,
      fontWeight: FontWeight.w600,
      height: 1,
      letterSpacing: 0.2,
    );
    final batteryText = batteryLevel == null || batteryLevel! < 0
        ? '--%'
        : '${batteryLevel!.clamp(0, 100)}%';
    return Row(
      children: [
        Text(
          timeLabel.trim().isEmpty ? '--:--' : timeLabel,
          style: textStyle.copyWith(
            fontSize: compact ? 11.5 : 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        Icon(
          _networkIconForType(networkType),
          size: compact ? 13.5 : 14.5,
          color: Colors.white.withValues(alpha: 0.94),
        ),
        SizedBox(width: compact ? 4 : 5),
        Text(_networkLabelForType(context, networkType), style: textStyle),
        SizedBox(width: compact ? 10 : 12),
        Icon(
          charging
              ? Icons.battery_charging_full_rounded
              : Icons.battery_std_rounded,
          size: compact ? 15.0 : 16.0,
          color: Colors.white.withValues(alpha: 0.94),
        ),
        SizedBox(width: compact ? 4 : 5),
        Text(batteryText, style: textStyle),
      ],
    );
  }

  IconData _networkIconForType(String type) {
    switch (type.trim().toLowerCase()) {
      case 'wifi':
      case 'ethernet':
      case 'online':
        return Icons.wifi_rounded;
      case 'cellular':
        return Icons.signal_cellular_alt_rounded;
      case 'bluetooth':
        return Icons.bluetooth_rounded;
      case 'offline':
        return Icons.portable_wifi_off_rounded;
      default:
        return Icons.network_check_rounded;
    }
  }

  String _networkLabelForType(BuildContext context, String type) {
    switch (type.trim().toLowerCase()) {
      case 'wifi':
        return 'WiFi';
      case 'ethernet':
        return 'LAN';
      case 'cellular':
        return '4G/5G';
      case 'bluetooth':
        return 'BT';
      case 'offline':
        return AppLocalizations.of(context).playerNetworkOffline;
      case 'online':
        return AppLocalizations.of(context).playerNetworkOnline;
      default:
        return '--';
    }
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
    final iconSize = compact ? 18.0 : 20.0;
    return _PlayerTopGlassButtonShell(
      compact: compact,
      onPressed: onPressed,
      child: Icon(icon, size: iconSize),
    );
  }
}

class _PlayerTopGlassAssetButton extends StatelessWidget {
  final String assetName;
  final bool compact;
  final bool active;
  final bool tintWithForeground;
  final VoidCallback onPressed;

  const _PlayerTopGlassAssetButton({
    required this.assetName,
    required this.compact,
    this.active = false,
    this.tintWithForeground = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isDanmakuAsset = assetName.contains('player_danmaku');
    final iconSize = isDanmakuAsset
        ? (compact ? 19.5 : 21.5)
        : (compact ? 17.0 : 19.0);
    return _PlayerTopGlassButtonShell(
      compact: compact,
      active: active,
      onPressed: onPressed,
      child: SvgPicture.asset(
        assetName,
        width: iconSize,
        height: iconSize,
        fit: BoxFit.contain,
        colorFilter: tintWithForeground
            ? ColorFilter.mode(
                active ? colors.accentStrong : Colors.white,
                BlendMode.srcIn,
              )
            : null,
      ),
    );
  }
}

class _PlayerTopGlassLabelButton extends StatelessWidget {
  final String label;
  final bool compact;
  final bool active;
  final VoidCallback onPressed;

  const _PlayerTopGlassLabelButton({
    required this.label,
    required this.compact,
    required this.active,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return _PlayerTopGlassButtonShell(
      compact: compact,
      active: active,
      onPressed: onPressed,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          style: TextStyle(
            color: active ? colors.accentStrong : Colors.white,
            fontSize: compact ? 13.5 : 14.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

class _PlayerTopGlassButtonShell extends StatelessWidget {
  final bool compact;
  final bool active;
  final VoidCallback onPressed;
  final Widget child;

  const _PlayerTopGlassButtonShell({
    required this.compact,
    this.active = false,
    required this.onPressed,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final size = compact ? 34.0 : 38.0;
    return SizedBox(
      width: size,
      height: size,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: active ? colors.accentStrong : Colors.white,
          backgroundColor: active
              ? colors.accentSoft
              : colors.overlayScrim.withValues(alpha: 0.24),
          overlayColor: Colors.white.withValues(alpha: 0.08),
          padding: const EdgeInsets.all(6),
          minimumSize: Size(size, size),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(compact ? 12 : 14),
            side: BorderSide(
              color: active
                  ? colors.accent.withValues(alpha: 0.92)
                  : Colors.white.withValues(alpha: 0.14),
              width: active ? 1.15 : 1.0,
            ),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: child,
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
    final timeLabel =
        '${formatDuration(clampedPosition)}/${formatDuration(duration)}';
    final referenceTimeLabel =
        '${formatDuration(duration)}/${formatDuration(duration)}';
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
    final progressButtonGap = orientationCallback == null
        ? 0.0
        : (compactUi ? 2.0 : 4.0);
    final progressButtonSlot = orientationCallback == null
        ? 0.0
        : (compactUi ? 24.0 : 28.0);
    final timeLabelStyle = TextStyle(
      color: Colors.white,
      fontSize: timeFontSize,
      fontWeight: FontWeight.w500,
    );
    return Transform.translate(
      offset: Offset(0, isLandscape ? (compactUi ? 4 : 6) : 0),
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
            padding: EdgeInsets.only(
              left: compactUi ? 2 : 4,
              right: progressButtonSlot + progressButtonGap,
            ),
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
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      IgnorePointer(
                        child: Opacity(
                          opacity: 0,
                          child: Text(
                            referenceTimeLabel,
                            style: timeLabelStyle,
                          ),
                        ),
                      ),
                      Text(
                        timeLabel,
                        textAlign: TextAlign.center,
                        style: timeLabelStyle,
                      ),
                    ],
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
              if (progressButtonGap > 0) SizedBox(width: progressButtonGap),
              if (progressButtonSlot > 0)
                SizedBox(
                  width: progressButtonSlot,
                  height: progressButtonSlot,
                  child: Visibility(
                    visible: !minimalSeekMode && orientationCallback != null,
                    maintainState: true,
                    maintainAnimation: true,
                    maintainSize: true,
                    child: orientationCallback == null
                        ? const SizedBox.shrink()
                        : IgnorePointer(
                            ignoring: minimalSeekMode,
                            child: PlayerProgressIconButton(
                              onPressed: orientationCallback,
                            ),
                          ),
                  ),
                ),
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

class PlayerFloatingLockButton extends StatelessWidget {
  final bool visible;
  final bool compact;
  final bool locked;
  final VoidCallback onPressed;

  const PlayerFloatingLockButton({
    super.key,
    required this.visible,
    required this.compact,
    required this.locked,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: kPlayerOverlayFadeDuration,
        curve: Curves.easeOutCubic,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 16 : 18),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: compact ? 12 : 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: _PlayerTopGlassButtonShell(
            compact: compact,
            active: locked,
            onPressed: onPressed,
            child: Icon(
              locked ? Icons.lock_rounded : Icons.lock_open_rounded,
              size: compact ? 18 : 20,
            ),
          ),
        ),
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
