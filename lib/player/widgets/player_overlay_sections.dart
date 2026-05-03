import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import 'mpv_player_widgets.dart';

const Duration kPlayerOverlayFadeDuration = Duration(milliseconds: 180);
const Duration kPlayerOverlaySlideDuration = Duration(milliseconds: 220);

class PlayerTopBarAction {
  final IconData icon;
  final VoidCallback onPressed;

  const PlayerTopBarAction({required this.icon, required this.onPressed});
}

class PlayerActionBarItem {
  final String label;
  final VoidCallback onPressed;

  const PlayerActionBarItem({required this.label, required this.onPressed});
}

class PlayerStatusCardData {
  final String title;
  final String? message;

  const PlayerStatusCardData({required this.title, this.message});
}

class PlayerResumePromptData {
  final String message;
  final String restartLabel;
  final VoidCallback onRestart;
  final VoidCallback onDismiss;

  const PlayerResumePromptData({
    required this.message,
    required this.restartLabel,
    required this.onRestart,
    required this.onDismiss,
  });
}

class PlayerAutoPlayPromptData {
  final String message;
  final VoidCallback onSkip;
  final VoidCallback onReplay;

  const PlayerAutoPlayPromptData({
    required this.message,
    required this.onSkip,
    required this.onReplay,
  });
}

class PlayerChapterMarkerData {
  final String label;
  final double fraction;
  final bool active;
  final VoidCallback onTap;

  const PlayerChapterMarkerData({
    required this.label,
    required this.fraction,
    required this.active,
    required this.onTap,
  });
}

class PlayerPlaybackCompletedData {
  final String title;
  final String durationLabel;
  final List<String> posterUrls;
  final String token;
  final VoidCallback onReplay;
  final VoidCallback onBack;

  const PlayerPlaybackCompletedData({
    required this.title,
    required this.durationLabel,
    required this.posterUrls,
    required this.token,
    required this.onReplay,
    required this.onBack,
  });
}

class PlayerCloudDriveSheetData {
  final String? accountName;
  final bool directPlaySelected;
  final bool proxyPlaySelected;
  final bool directPlayEnabled;
  final bool proxyPlayEnabled;
  final VoidCallback? onDirectPlayPressed;
  final VoidCallback? onProxyPlayPressed;

  const PlayerCloudDriveSheetData({
    this.accountName,
    required this.directPlaySelected,
    required this.proxyPlaySelected,
    this.directPlayEnabled = true,
    this.proxyPlayEnabled = true,
    required this.onDirectPlayPressed,
    required this.onProxyPlayPressed,
  });
}

class PlayerTopBar extends StatelessWidget {
  final bool visible;
  final bool compact;
  final double height;
  final double titleFontSize;
  final String title;
  final VoidCallback onBack;
  final List<PlayerTopBarAction> actions;

  const PlayerTopBar({
    super.key,
    required this.visible,
    required this.compact,
    required this.height,
    required this.titleFontSize,
    required this.title,
    required this.onBack,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, -0.12),
      duration: kPlayerOverlaySlideDuration,
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: kPlayerOverlayFadeDuration,
        curve: Curves.easeOutCubic,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: EdgeInsets.only(top: compact ? 1 : 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                PlayerTopIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onPressed: onBack,
                ),
                SizedBox(width: compact ? 4 : 6),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: PlayerMarqueeText(
                      text: title,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: titleFontSize,
                        fontWeight: FontWeight.w600,
                        height: 1.12,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: compact ? 4 : 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: actions
                      .map(
                        (action) => Padding(
                          padding: EdgeInsets.only(left: compact ? 2 : 4),
                          child: PlayerTopIconButton(
                            icon: action.icon,
                            onPressed: action.onPressed,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PlayerSeekPanel extends StatelessWidget {
  final bool visible;
  final bool compact;
  final double timeFontSize;
  final double sliderHeight;
  final double topGap;
  final double bottomGap;
  final double progressButtonSlot;
  final String timeLabel;
  final double sliderMax;
  final double sliderValue;
  final bool showOrientationButton;
  final bool centerTimeLabel;
  final double horizontalInset;
  final double timeHorizontalInset;
  final PlayerStatusCardData? statusCard;
  final PlayerResumePromptData? resumePrompt;
  final PlayerAutoPlayPromptData? autoPlayPrompt;
  final List<PlayerChapterMarkerData> chapterMarkers;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final VoidCallback onOrientationPressed;

  const PlayerSeekPanel({
    super.key,
    required this.visible,
    required this.compact,
    required this.timeFontSize,
    required this.sliderHeight,
    required this.topGap,
    required this.bottomGap,
    required this.progressButtonSlot,
    required this.timeLabel,
    required this.sliderMax,
    required this.sliderValue,
    required this.showOrientationButton,
    required this.centerTimeLabel,
    required this.horizontalInset,
    required this.timeHorizontalInset,
    this.statusCard,
    this.resumePrompt,
    this.autoPlayPrompt,
    this.chapterMarkers = const <PlayerChapterMarkerData>[],
    this.onChangeStart,
    this.onChanged,
    this.onChangeEnd,
    required this.onOrientationPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, 0.12),
      duration: kPlayerOverlaySlideDuration,
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: kPlayerOverlayFadeDuration,
        curve: Curves.easeOutCubic,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (statusCard != null) _PlayerStatusCard(data: statusCard!),
            if (resumePrompt != null) ...[
              if (statusCard != null) const SizedBox(height: 10),
              _PlayerResumePrompt(data: resumePrompt!),
            ],
            if (autoPlayPrompt != null) ...[
              if (statusCard != null || resumePrompt != null)
                const SizedBox(height: 10),
              _PlayerAutoPlayPrompt(data: autoPlayPrompt!),
            ],
            SizedBox(height: topGap),
            Padding(
              padding: centerTimeLabel
                  ? EdgeInsets.symmetric(horizontal: horizontalInset)
                  : EdgeInsets.only(
                      left: timeHorizontalInset,
                      right: horizontalInset,
                    ),
              child: Align(
                alignment: centerTimeLabel
                    ? Alignment.center
                    : Alignment.centerLeft,
                child: Text(
                  timeLabel,
                  textAlign: centerTimeLabel
                      ? TextAlign.center
                      : TextAlign.left,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: timeFontSize,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            SizedBox(height: compact ? 8 : 10),
            if (chapterMarkers.isNotEmpty) ...[
              Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalInset),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: compact ? 28 : 30,
                        child: _PlayerChapterChipList(
                          compact: compact,
                          markers: chapterMarkers,
                        ),
                      ),
                    ),
                    SizedBox(width: compact ? 8 : 10),
                    SizedBox(width: progressButtonSlot),
                  ],
                ),
              ),
              SizedBox(height: compact ? 6 : 8),
            ],
            Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalInset),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: sliderHeight,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2.2,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 8,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 14,
                                ),
                                activeTrackColor: colors.accent,
                                inactiveTrackColor: Colors.white24,
                                thumbColor: Colors.white,
                                overlayColor: colors.accentSoft,
                              ),
                              child: Slider(
                                min: 0,
                                max: sliderMax <= 0 ? 1 : sliderMax,
                                value: sliderMax <= 0
                                    ? 0
                                    : sliderValue.clamp(0, sliderMax),
                                allowedInteraction: SliderInteraction.slideOnly,
                                onChangeStart: sliderMax <= 0
                                    ? null
                                    : onChangeStart,
                                onChanged: sliderMax <= 0 ? null : onChanged,
                                onChangeEnd: sliderMax <= 0
                                    ? null
                                    : onChangeEnd,
                              ),
                            ),
                          ),
                          if (chapterMarkers.isNotEmpty && sliderMax > 0)
                            Positioned.fill(
                              child: _PlayerSliderChapterMarkers(
                                markers: chapterMarkers,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: compact ? 8 : 10),
                  SizedBox(
                    width: progressButtonSlot,
                    height: progressButtonSlot,
                    child: IgnorePointer(
                      ignoring: !showOrientationButton,
                      child: AnimatedOpacity(
                        opacity: showOrientationButton ? 1 : 0,
                        duration: kPlayerOverlayFadeDuration,
                        curve: Curves.easeOutCubic,
                        child: PlayerProgressIconButton(
                          onPressed: onOrientationPressed,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: bottomGap),
          ],
        ),
      ),
    );
  }
}

class _PlayerChapterChipList extends StatelessWidget {
  final bool compact;
  final List<PlayerChapterMarkerData> markers;

  const _PlayerChapterChipList({required this.compact, required this.markers});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.zero,
      itemCount: markers.length,
      separatorBuilder: (_, __) => SizedBox(width: compact ? 6 : 8),
      itemBuilder: (context, index) {
        final marker = markers[index];
        final active = marker.active;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: marker.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 12,
              vertical: compact ? 5 : 6,
            ),
            decoration: BoxDecoration(
              color: active
                  ? colors.accent
                  : colors.backgroundElevated.withValues(alpha: 0.86),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: active ? colors.accentStrong : colors.borderSubtle,
              ),
            ),
            child: Text(
              marker.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 11 : 12,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlayerSliderChapterMarkers extends StatelessWidget {
  final List<PlayerChapterMarkerData> markers;

  const _PlayerSliderChapterMarkers({required this.markers});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width <= 0) return const SizedBox.shrink();
        return Stack(
          children: markers.map((marker) {
            final clamped = marker.fraction.clamp(0.0, 1.0);
            final left = ((clamped * width) - 9).clamp(0.0, width - 18);
            final color = marker.active
                ? colors.accent
                : Colors.white.withAlpha(190);
            return Positioned(
              left: left,
              top: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: marker.onTap,
                child: SizedBox(
                  width: 18,
                  child: Center(
                    child: Container(
                      width: 2,
                      height: marker.active ? 10 : 8,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class PlayerActionBar extends StatelessWidget {
  final bool visible;
  final bool compact;
  final bool paused;
  final bool completed;
  final double height;
  final bool showNextButton;
  final double horizontalInset;
  final VoidCallback onTogglePlayback;
  final VoidCallback onNextEpisode;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressEndCallback? onLongPressEnd;
  final List<PlayerActionBarItem> items;

  const PlayerActionBar({
    super.key,
    required this.visible,
    required this.compact,
    required this.paused,
    this.completed = false,
    required this.height,
    required this.showNextButton,
    required this.horizontalInset,
    required this.onTogglePlayback,
    required this.onNextEpisode,
    this.onLongPressStart,
    this.onLongPressEnd,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: kPlayerOverlayFadeDuration,
          curve: Curves.easeOutCubic,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalInset),
            child: Row(
              children: [
                PlayerBottomControlButton(
                  icon: completed
                      ? Icons.replay_rounded
                      : (paused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded),
                  compact: compact,
                  emphasis: true,
                  onPressed: onTogglePlayback,
                ),
                SizedBox(width: compact ? 0 : 2),
                if (showNextButton)
                  PlayerBottomControlButton(
                    icon: Icons.skip_next_rounded,
                    compact: compact,
                    onPressed: onNextEpisode,
                  ),
                SizedBox(width: compact ? 10 : 14),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: compact ? 6 : 8,
                      runSpacing: compact ? 6 : 8,
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: items
                          .map(
                            (item) => PlayerActionTextButton(
                              label: item.label,
                              onPressed: item.onPressed,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PlayerPlaybackCompletedPanel extends StatelessWidget {
  final bool compact;
  final PlayerPlaybackCompletedData data;

  const PlayerPlaybackCompletedPanel({
    super.key,
    required this.compact,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final posterWidth = compact ? 220.0 : 280.0;
    final posterHeight = compact ? 124.0 : 158.0;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: compact ? 320 : 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                width: posterWidth,
                height: posterHeight,
                child: _PlayerCompletionPoster(
                  urls: data.posterUrls,
                  token: data.token,
                  durationLabel: data.durationLabel,
                ),
              ),
            ),
            SizedBox(height: compact ? 12 : 16),
            Text(
              data.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 13 : 16,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            ),
            SizedBox(height: compact ? 16 : 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: _PlayerCompletionButton(
                    label: l10n.playerReplayAction,
                    icon: Icons.replay_rounded,
                    filled: false,
                    compact: compact,
                    onPressed: data.onReplay,
                  ),
                ),
                SizedBox(width: compact ? 10 : 14),
                Expanded(
                  child: _PlayerCompletionButton(
                    label: l10n.playerBackAction,
                    icon: Icons.home_outlined,
                    filled: true,
                    compact: compact,
                    onPressed: data.onBack,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class PlayerCloudDriveSheet extends StatelessWidget {
  final PlayerCloudDriveSheetData data;

  const PlayerCloudDriveSheet({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(
                compact ? 16 : 18,
                compact ? 16 : 18,
                compact ? 16 : 18,
                compact ? 14 : 16,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[Color(0xFF0A1624), Color(0xFF13345E)],
                ),
                border: Border.all(color: const Color(0x403E8CFF)),
              ),
              child: Row(
                children: [
                  Container(
                    width: compact ? 46 : 52,
                    height: compact ? 46 : 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.94),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.cloud_queue_rounded,
                      color: const Color(0xFF1E7BFF),
                      size: compact ? 26 : 30,
                    ),
                  ),
                  SizedBox(width: compact ? 12 : 14),
                  Expanded(
                    child: Text(
                      l10n.playerCloudDrivePlayingFile,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 17 : 19,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: compact ? 16 : 18),
            Text(
              l10n.playerCloudDriveModeDescription,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.84),
                fontSize: compact ? 13.5 : 14.5,
                height: 1.45,
              ),
            ),
            SizedBox(height: compact ? 18 : 20),
            _CloudDriveModeCard(
              title: l10n.playerCloudDriveDirectTitle,
              subtitle: l10n.playerCloudDriveDirectSubtitle,
              selected: data.directPlaySelected,
              recommended: true,
              enabled: data.directPlayEnabled,
              onPressed: data.onDirectPlayPressed,
            ),
            SizedBox(height: compact ? 12 : 14),
            _CloudDriveModeCard(
              title: l10n.playerCloudDriveProxyTitle,
              subtitle: l10n.playerCloudDriveProxySubtitle,
              selected: data.proxyPlaySelected,
              recommended: false,
              enabled: data.proxyPlayEnabled,
              onPressed: data.onProxyPlayPressed,
            ),
          ],
        );
      },
    );
  }
}

class _CloudDriveModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final bool recommended;
  final bool enabled;
  final VoidCallback? onPressed;

  const _CloudDriveModeCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.recommended,
    this.enabled = true,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabledColor = enabled
        ? Colors.white
        : Colors.white.withValues(alpha: 0.4);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: enabled ? onPressed : null,
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: enabled
                ? const Color(0x26000000)
                : Colors.white.withValues(alpha: 0.04),
            border: Border.all(
              color: selected
                  ? const Color(0xFF2F7BF0)
                  : Colors.white.withValues(alpha: enabled ? 0.22 : 0.1),
              width: selected ? 1.6 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? const Color(0xFF2F7BF0)
                      : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF5CA0FF)
                        : Colors.white.withValues(alpha: enabled ? 0.28 : 0.14),
                  ),
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 22,
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected
                                  ? const Color(0xFF4E95FF)
                                  : enabledColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (recommended) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              AppLocalizations.of(
                                context,
                              ).playerRecommendedBadge,
                              style: const TextStyle(
                                color: Color(0xFFBAC5D4),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: enabled
                            ? Colors.white.withValues(alpha: 0.76)
                            : Colors.white.withValues(alpha: 0.34),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerStatusCard extends StatelessWidget {
  final PlayerStatusCardData data;

  const _PlayerStatusCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xA6000000),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            data.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if ((data.message ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                data.message!,
                style: const TextStyle(color: Color(0xFFFF9A9A), fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlayerCompletionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final bool compact;
  final VoidCallback onPressed;

  const _PlayerCompletionButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.compact,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor = filled
        ? const Color(0xFF2F7BF0)
        : const Color(0xFF141821);
    return SizedBox(
      height: compact ? 52 : 58,
      child: TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: backgroundColor,
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: Icon(icon, size: compact ? 22 : 26),
        label: Text(
          label,
          style: TextStyle(
            fontSize: compact ? 14 : 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _PlayerCompletionPoster extends StatefulWidget {
  final List<String> urls;
  final String token;
  final String durationLabel;

  const _PlayerCompletionPoster({
    required this.urls,
    required this.token,
    required this.durationLabel,
  });

  @override
  State<_PlayerCompletionPoster> createState() =>
      _PlayerCompletionPosterState();
}

class _PlayerCompletionPosterState extends State<_PlayerCompletionPoster> {
  int _urlIndex = 0;

  @override
  void didUpdateWidget(covariant _PlayerCompletionPoster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urls != widget.urls || oldWidget.token != widget.token) {
      _urlIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.urls.isEmpty || widget.token.trim().isEmpty
        ? const ColoredBox(color: Color(0xFF20242D))
        : Image.network(
            widget.urls[_urlIndex],
            fit: BoxFit.cover,
            headers: <String, String>{
              'Authorization': widget.token,
              'Trim-MC-token': widget.token,
            },
            errorBuilder: (context, error, stackTrace) {
              if (_urlIndex + 1 < widget.urls.length) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() => _urlIndex++);
                });
              }
              return const ColoredBox(color: Color(0xFF20242D));
            },
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.12),
                  Colors.black.withValues(alpha: 0.36),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: 12,
          bottom: 10,
          child: Text(
            widget.durationLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _PlayerResumePrompt extends StatelessWidget {
  final PlayerResumePromptData data;

  const _PlayerResumePrompt({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.only(left: 12, right: 4, top: 5, bottom: 5),
      decoration: BoxDecoration(
        color: const Color(0xE9323942),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              data.message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: data.onRestart,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF2F8DFF),
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0),
              minimumSize: const Size(0, 20),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              data.restartLabel,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            onPressed: data.onDismiss,
            icon: const Icon(Icons.close_rounded),
            color: Colors.white70,
            iconSize: 14,
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            splashRadius: 12,
          ),
        ],
      ),
    );
  }
}

class _PlayerAutoPlayPrompt extends StatelessWidget {
  final PlayerAutoPlayPromptData data;

  const _PlayerAutoPlayPrompt({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.only(left: 12, right: 6, top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xE91E2430),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
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
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: data.onSkip,
            icon: const Icon(Icons.close_rounded),
            color: Colors.white70,
            iconSize: 16,
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            splashRadius: 14,
          ),
          IconButton(
            onPressed: data.onReplay,
            icon: const Icon(Icons.check_rounded),
            color: const Color(0xFF68A6FF),
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
