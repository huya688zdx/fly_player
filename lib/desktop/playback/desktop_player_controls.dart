import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../theme/app_theme.dart';
import 'desktop_semantics_safe_slider.dart';

Widget _tooltipOrChild({
  required String message,
  required Widget child,
  required bool enabled,
}) {
  return enabled && message.trim().isNotEmpty
      ? Tooltip(message: message, child: child)
      : child;
}

/// 桌面播放器控制层（对齐 design/desktop 原型 .pl-top / .pl-bottom）：
/// 顶栏只留返回 + 标题与一个设置齿轮；弹幕开关 / 倍速 / 选集 / 清晰度
/// 以文字与徽标按钮放底栏，后接字幕 / 音轨 / 书签 / 截图 / 全屏图标。
///
/// 只消费 media_kit 的中立状态，不依赖 Android PlatformView 或 MethodChannel。
class DesktopPlayerControls extends StatefulWidget {
  const DesktopPlayerControls({
    super.key,
    required this.player,
    required this.videoState,
    required this.title,
    required this.subtitle,
    required this.resolution,
    required this.playing,
    required this.loading,
    required this.volume,
    required this.rate,
    required this.nowPlayingLabel,
    required this.playTooltip,
    required this.pauseTooltip,
    required this.muteTooltip,
    required this.speedTooltip,
    required this.fullscreenTooltip,
    required this.settingsTooltip,
    required this.prevTooltip,
    required this.bookmarkTooltip,
    required this.episodeLabel,
    required this.subtitleLabel,
    required this.audioTooltip,
    required this.screenshotLabel,
    required this.danmakuEnabled,
    required this.danmakuLabel,
    required this.onBack,
    required this.onToggle,
    required this.onSeek,
    required this.onVolume,
    required this.onMute,
    required this.onRate,
    required this.onScreenshot,
    required this.onToggleDanmaku,
    required this.onSettings,
    this.onNext,
    this.onPrevious,
    this.onEpisodes,
    this.onAudio,
    this.onSubtitle,
    this.onQuality,
    this.onAudioAt,
    this.onSubtitleAt,
    this.onQualityAt,
    this.onSpeedAt,
    this.onEpisodesAt,
    this.onSettingsAt,
    this.onHoverSpeed,
    this.onHoverEpisodes,
    this.onHoverQuality,
    this.onHoverSubtitle,
    this.onHoverAudio,
    this.onHoverSettings,
    this.onHoverExit,
    this.onAddBookmark,
  });

  final Player player;
  final VideoState videoState;
  final String title;
  final String subtitle;
  final String resolution;
  final bool playing;
  final bool loading;
  final double volume;
  final double rate;
  final String nowPlayingLabel;
  final String playTooltip;
  final String pauseTooltip;
  final String muteTooltip;
  final String speedTooltip;
  final String fullscreenTooltip;
  final String settingsTooltip;

  /// 上一集按钮提示（无上一集时不显示按钮）。
  final String prevTooltip;

  /// 添加书签按钮提示（空串时不显示按钮）。
  final String bookmarkTooltip;
  final String episodeLabel;
  final String subtitleLabel;

  /// 音轨按钮提示（空串时不显示按钮）。
  final String audioTooltip;
  final String screenshotLabel;
  final bool danmakuEnabled;

  /// 弹幕开关按钮提示（点击直接开/关）。
  final String danmakuLabel;
  final VoidCallback onBack;
  final VoidCallback onToggle;
  final Future<void> Function(Duration) onSeek;
  final ValueChanged<double> onVolume;
  final VoidCallback onMute;
  final ValueChanged<double> onRate;
  final VoidCallback onScreenshot;
  final VoidCallback onToggleDanmaku;
  final VoidCallback onSettings;
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;
  final VoidCallback? onEpisodes;
  final VoidCallback? onAudio;
  final VoidCallback? onSubtitle;
  final VoidCallback? onQuality;
  final ValueChanged<Rect>? onAudioAt;
  final ValueChanged<Rect>? onSubtitleAt;
  final ValueChanged<Rect>? onQualityAt;
  final ValueChanged<Rect>? onSpeedAt;
  final ValueChanged<Rect>? onEpisodesAt;
  final ValueChanged<Rect>? onSettingsAt;
  final ValueChanged<Rect>? onHoverSpeed;
  final ValueChanged<Rect>? onHoverEpisodes;
  final ValueChanged<Rect>? onHoverQuality;
  final ValueChanged<Rect>? onHoverSubtitle;
  final ValueChanged<Rect>? onHoverAudio;
  final ValueChanged<Rect>? onHoverSettings;
  final VoidCallback? onHoverExit;
  final VoidCallback? onAddBookmark;

  @override
  State<DesktopPlayerControls> createState() => _DesktopPlayerControlsState();
}

class _DesktopPlayerControlsState extends State<DesktopPlayerControls> {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final veryCompact = constraints.maxWidth < 560;
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const _ChromeAtmosphere(),
            SafeArea(
              minimum: EdgeInsets.fromLTRB(
                compact ? 14 : 20,
                compact ? 10 : 14,
                compact ? 14 : 20,
                compact ? 10 : 14,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _buildTopBar(),
                  const Spacer(),
                  _buildBottomChrome(
                    colors: colors,
                    compact: compact,
                    veryCompact: veryCompact,
                  ),
                ],
              ),
            ),
            // 中央大播放钮（.pl-center/.pl-big）：暂停且非缓冲时浮现。
            IgnorePointer(
              ignoring: widget.playing || widget.loading,
              child: AnimatedOpacity(
                opacity: !widget.playing && !widget.loading ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: Center(
                  child: _BigPlayButton(
                    accent: colors.accent,
                    playTooltip: widget.playTooltip,
                    onPressed: widget.loading ? null : widget.onToggle,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 顶栏（.pl-top）：返回 + 标题块 | 设置齿轮
  // ---------------------------------------------------------------------------

  Widget _buildTopBar() {
    final title = widget.title.trim().isEmpty
        ? widget.nowPlayingLabel
        : widget.title.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        _DarkIconButton(
          icon: Icons.arrow_back_rounded,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: widget.onBack,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _MarqueeText(
                text: title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                  shadows: <Shadow>[
                    Shadow(color: Color(0xA8000000), blurRadius: 10),
                  ],
                ),
              ),
              if (widget.subtitle.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 3),
                Text(
                  widget.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 14),
        _GearButton(
          tooltip: widget.settingsTooltip,
          onPressed: widget.onSettings,
          onAnchor: widget.onSettingsAt,
          onHoverEnter: widget.onHoverSettings,
          onHoverExit: widget.onHoverExit,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 底栏（.pl-bottom）：进度行（悬停时间提示）+ 控制行
  // ---------------------------------------------------------------------------

  Widget _buildBottomChrome({
    required AppThemeColors colors,
    required bool compact,
    required bool veryCompact,
  }) {
    return StreamBuilder<Duration>(
      stream: widget.player.stream.duration,
      initialData: widget.player.state.duration,
      builder: (context, durationSnapshot) {
        return StreamBuilder<Duration>(
          stream: widget.player.stream.position,
          initialData: widget.player.state.position,
          builder: (context, positionSnapshot) {
            return StreamBuilder<Duration>(
              stream: widget.player.stream.buffer,
              initialData: widget.player.state.buffer,
              builder: (context, bufferSnapshot) {
                final duration = durationSnapshot.data ?? Duration.zero;
                final position = positionSnapshot.data ?? Duration.zero;
                final buffer = bufferSnapshot.data ?? Duration.zero;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      height: 26,
                      child: _DesktopTimeline(
                        position: position,
                        duration: duration,
                        buffered: buffer,
                        accent: colors.accent,
                        onSeek: widget.onSeek,
                      ),
                    ),
                    SizedBox(height: compact ? 2 : 4),
                    Row(
                      children: <Widget>[
                        _CtrlIconButton(
                          icon: widget.playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          tooltip: widget.playing
                              ? widget.pauseTooltip
                              : widget.playTooltip,
                          loading: widget.loading,
                          spinner: colors.accentStrong,
                          onPressed: widget.onToggle,
                        ),
                        if (widget.onPrevious != null) ...<Widget>[
                          const SizedBox(width: 2),
                          _CtrlIconButton(
                            icon: Icons.skip_previous_rounded,
                            tooltip: widget.prevTooltip,
                            onPressed: widget.onPrevious!,
                          ),
                        ],
                        if (widget.onNext != null) ...<Widget>[
                          const SizedBox(width: 2),
                          _CtrlIconButton(
                            icon: Icons.skip_next_rounded,
                            tooltip: widget.episodeLabel,
                            onPressed: widget.onNext!,
                          ),
                        ],
                        const SizedBox(width: 6),
                        _CtrlIconButton(
                          icon: widget.volume <= 0
                              ? Icons.volume_off_rounded
                              : widget.volume < 45
                              ? Icons.volume_down_rounded
                              : Icons.volume_up_rounded,
                          tooltip: widget.muteTooltip,
                          onPressed: widget.onMute,
                        ),
                        if (!compact) ...<Widget>[
                          const SizedBox(width: 2),
                          SizedBox(
                            width: 86,
                            child: DesktopSemanticsSafeSlider(
                              value: widget.volume.clamp(0, 100).toDouble(),
                              min: 0,
                              max: 100,
                              onChanged: widget.onVolume,
                              activeColor: colors.accent,
                              inactiveColor: Colors.white.withValues(
                                alpha: 0.18,
                              ),
                              semanticsLabel: '音量',
                              semanticsValue: '${widget.volume.round()}%',
                              trackHeight: 2.5,
                              thumbRadius: 5,
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        if (!veryCompact) _buildTimeText(position, duration),
                        const Spacer(),
                        _buildRightActions(
                          colors: colors,
                          compact: compact,
                          veryCompact: veryCompact,
                        ),
                      ],
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  /// 时间显示（.pl-time：当前白色加粗，总时长 60% 白）。
  Widget _buildTimeText(Duration position, Duration duration) {
    return Text.rich(
      TextSpan(
        children: <TextSpan>[
          TextSpan(
            text: _formatDuration(position),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const TextSpan(text: ' / '),
          TextSpan(text: _formatDuration(duration)),
        ],
      ),
      maxLines: 1,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.6),
        fontSize: 12,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        shadows: const <Shadow>[Shadow(color: Colors.black, blurRadius: 8)],
      ),
    );
  }

  /// 右侧动作组：弹幕徽标 + 倍速/选集/清晰度文字钮 + 图标钮（.plc-right）。
  Widget _buildRightActions({
    required AppThemeColors colors,
    required bool compact,
    required bool veryCompact,
  }) {
    final actions = <Widget>[
      _DanmakuBadgeButton(
        enabled: widget.danmakuEnabled,
        accent: colors.accent,
        tooltip: widget.danmakuLabel,
        onPressed: widget.onToggleDanmaku,
      ),
      _SpeedButton(
        rate: widget.rate,
        tooltip: widget.speedTooltip,
        onAnchor: widget.onSpeedAt,
        onHoverEnter: widget.onHoverSpeed,
        onHoverExit: widget.onHoverExit,
      ),
      if (widget.onEpisodes != null)
        _CtrlTextButton(
          label: widget.episodeLabel,
          onPressed: widget.onEpisodes!,
          onAnchor: widget.onEpisodesAt,
          onHoverEnter: widget.onHoverEpisodes,
          onHoverExit: widget.onHoverExit,
        ),
      if (widget.onQuality != null && !veryCompact)
        _CtrlTextButton(
          label: widget.resolution,
          onPressed: widget.onQuality!,
          onAnchor: widget.onQualityAt,
          onHoverEnter: widget.onHoverQuality,
          onHoverExit: widget.onHoverExit,
        ),
      if (widget.onSubtitle != null && !veryCompact)
        _CtrlIconButton(
          icon: Icons.subtitles_outlined,
          tooltip: widget.subtitleLabel,
          onPressed: widget.onSubtitle!,
          onAnchor: widget.onSubtitleAt,
          onHoverEnter: widget.onHoverSubtitle,
          onHoverExit: widget.onHoverExit,
        ),
      if (widget.onAudio != null && widget.audioTooltip.isNotEmpty && !compact)
        _CtrlIconButton(
          icon: Icons.audiotrack_rounded,
          tooltip: widget.audioTooltip,
          onPressed: widget.onAudio!,
          onAnchor: widget.onAudioAt,
          onHoverEnter: widget.onHoverAudio,
          onHoverExit: widget.onHoverExit,
        ),
      if (widget.onAddBookmark != null &&
          widget.bookmarkTooltip.isNotEmpty &&
          !compact)
        _CtrlIconButton(
          icon: Icons.bookmark_add_outlined,
          tooltip: widget.bookmarkTooltip,
          onPressed: widget.onAddBookmark!,
        ),
      _CtrlIconButton(
        icon: Icons.photo_camera_outlined,
        tooltip: widget.screenshotLabel,
        onPressed: widget.onScreenshot,
      ),
      _CtrlIconButton(
        icon: widget.videoState.isFullscreen()
            ? Icons.fullscreen_exit_rounded
            : Icons.fullscreen_rounded,
        tooltip: widget.fullscreenTooltip,
        onPressed: () => unawaited(widget.videoState.toggleFullscreen()),
      ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var index = 0; index < actions.length; index++) ...<Widget>[
            if (index > 0) const SizedBox(width: 2),
            actions[index],
          ],
        ],
      ),
    );
  }

  String _formatDuration(Duration value) {
    final safe = value < Duration.zero ? Duration.zero : value;
    final hours = safe.inHours;
    final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}

class _ChromeAtmosphere extends StatelessWidget {
  const _ChromeAtmosphere();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: 108,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Color(0xA8000000),
                    Color(0x42000000),
                    Color(0x00000000),
                  ],
                ),
              ),
            ),
          ),
          Spacer(),
          SizedBox(
            height: 142,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Color(0x00000000),
                    Color(0x4D000000),
                    Color(0xB8000000),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 返回按钮（.icon-btn.dark）：暗色玻璃圆角方钮。
class _DarkIconButton extends StatelessWidget {
  const _DarkIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _tooltipOrChild(
      message: tooltip,
      enabled: true,
      child: _HoverSurface(
        builder: (hovered) => SizedBox.square(
          dimension: 36,
          child: Material(
            color: hovered ? const Color(0xB3060B14) : const Color(0x99020810),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
              side: BorderSide(
                color: Colors.white.withValues(alpha: hovered ? 0.24 : 0.14),
              ),
            ),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(11),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

/// 顶栏设置齿轮（.pl-tbtn.sq）：顶栏右侧唯一按钮，打开设置抽屉。
class _GearButton extends StatelessWidget {
  const _GearButton({
    required this.tooltip,
    required this.onPressed,
    this.onAnchor,
    this.onHoverEnter,
    this.onHoverExit,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final ValueChanged<Rect>? onAnchor;
  final ValueChanged<Rect>? onHoverEnter;
  final VoidCallback? onHoverExit;

  @override
  Widget build(BuildContext context) {
    return _tooltipOrChild(
      message: tooltip,
      enabled: onHoverEnter == null,
      child: _HoverSurface(
        onEnter: onHoverEnter,
        onExit: onHoverExit,
        builder: (hovered) => SizedBox.square(
          dimension: 32,
          child: Material(
            color: hovered
                ? Colors.white.withValues(alpha: 0.24)
                : Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: () {
                final object = context.findRenderObject();
                if (onAnchor != null && object is RenderBox && object.hasSize) {
                  onAnchor!(object.localToGlobal(Offset.zero) & object.size);
                } else {
                  onPressed();
                }
              },
              borderRadius: BorderRadius.circular(10),
              child: const Icon(
                Icons.settings_outlined,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 中央大播放钮（.pl-big）：暂停时浮现，悬停染 accent。
class _BigPlayButton extends StatelessWidget {
  const _BigPlayButton({
    required this.accent,
    required this.playTooltip,
    required this.onPressed,
  });

  final Color accent;
  final String playTooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: playTooltip,
      child: _HoverSurface(
        builder: (hovered) => SizedBox.square(
          dimension: 76,
          child: Material(
            color: hovered ? accent : Colors.black.withValues(alpha: 0.45),
            shape: CircleBorder(
              side: BorderSide(
                color: hovered ? accent : Colors.white.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
            child: InkWell(
              onTap: onPressed,
              customBorder: const CircleBorder(),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 34,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 底栏图标钮（.pl-btn）：38px 透明底，悬停白 14% 底。
class _CtrlIconButton extends StatelessWidget {
  const _CtrlIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.loading = false,
    this.spinner = Colors.white,
    this.onAnchor,
    this.onHoverEnter,
    this.onHoverExit,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool loading;
  final Color spinner;
  final ValueChanged<Rect>? onAnchor;
  final ValueChanged<Rect>? onHoverEnter;
  final VoidCallback? onHoverExit;

  @override
  Widget build(BuildContext context) {
    return _tooltipOrChild(
      message: tooltip,
      enabled: onHoverEnter == null,
      child: _HoverSurface(
        onEnter: onHoverEnter,
        onExit: onHoverExit,
        builder: (hovered) => Builder(
          builder: (buttonContext) => SizedBox.square(
            dimension: 38,
            child: Material(
              color: hovered
                  ? Colors.white.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: loading
                    ? null
                    : () {
                        final object = buttonContext.findRenderObject();
                        if (onAnchor != null &&
                            object is RenderBox &&
                            object.hasSize) {
                          onAnchor!(
                            object.localToGlobal(Offset.zero) & object.size,
                          );
                        } else {
                          onPressed();
                        }
                      },
                borderRadius: BorderRadius.circular(10),
                child: Center(
                  child: loading
                      ? SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: spinner,
                          ),
                        )
                      : Icon(
                          icon,
                          color: Colors.white.withValues(alpha: 0.88),
                          size: 20,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 底栏文字钮（.pl-btn.pl-txt）：选集 / 清晰度 / 倍速。
class _CtrlTextButton extends StatelessWidget {
  const _CtrlTextButton({
    required this.label,
    required this.onPressed,
    this.onAnchor,
    this.onHoverEnter,
    this.onHoverExit,
  });

  final String label;
  final VoidCallback onPressed;
  final ValueChanged<Rect>? onAnchor;
  final ValueChanged<Rect>? onHoverEnter;
  final VoidCallback? onHoverExit;

  @override
  Widget build(BuildContext context) {
    return _HoverSurface(
      onEnter: onHoverEnter,
      onExit: onHoverExit,
      builder: (hovered) => Material(
        color: hovered
            ? Colors.white.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () {
            if (onAnchor == null) {
              onPressed();
              return;
            }
            final object = context.findRenderObject();
            if (object is RenderBox && object.hasSize) {
              onAnchor!(object.localToGlobal(Offset.zero) & object.size);
            } else {
              onPressed();
            }
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 弹幕开关（.pl-btn > span.on）：38px 方钮内嵌「弹」徽标，
/// 开启时 accent 底、关闭时白 25% 底。
class _DanmakuBadgeButton extends StatelessWidget {
  const _DanmakuBadgeButton({
    required this.enabled,
    required this.accent,
    required this.tooltip,
    required this.onPressed,
  });

  final bool enabled;
  final Color accent;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: _HoverSurface(
        builder: (hovered) => Material(
          color: hovered
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: enabled
                      ? accent
                      : Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(5),
                ),
                alignment: Alignment.center,
                child: const Text(
                  '弹',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 倍速按钮（.pl-btn.pl-txt + .pl-lb）：文字显示当前倍速，弹层选择。
class _SpeedButton extends StatelessWidget {
  const _SpeedButton({
    required this.rate,
    required this.tooltip,
    this.onAnchor,
    this.onHoverEnter,
    this.onHoverExit,
  });

  final double rate;
  final String tooltip;
  final ValueChanged<Rect>? onAnchor;
  final ValueChanged<Rect>? onHoverEnter;
  final VoidCallback? onHoverExit;

  @override
  Widget build(BuildContext context) {
    return _tooltipOrChild(
      message: tooltip,
      enabled: false,
      child: _HoverSurface(
        onEnter: onHoverEnter,
        onExit: onHoverExit,
        builder: (hovered) => Material(
          color: hovered
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () {
              final object = context.findRenderObject();
              if (onAnchor != null && object is RenderBox && object.hasSize) {
                onAnchor!(object.localToGlobal(Offset.zero) & object.size);
              }
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              child: Text(
                '${_formatRate(rate)}x',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _formatRate(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(1)
        : value.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
  }
}

/// 进度条（.pl-progress）：4.5px 轨道 + 缓冲 + accent 填充，
/// 悬停放大轨道、浮现白色手柄与上方时间提示（.plp-tip）。
class _DesktopTimeline extends StatefulWidget {
  const _DesktopTimeline({
    required this.position,
    required this.duration,
    required this.buffered,
    required this.accent,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final Duration buffered;
  final Color accent;
  final Future<void> Function(Duration) onSeek;

  @override
  State<_DesktopTimeline> createState() => _DesktopTimelineState();
}

class _DesktopTimelineState extends State<_DesktopTimeline> {
  bool _hovered = false;
  bool _dragging = false;
  double _dragValue = 0;
  double _hoverDx = 0;

  double get _durationMs => widget.duration.inMilliseconds.toDouble();

  double get _positionFraction {
    if (_durationMs <= 0) return 0;
    final position = _dragging
        ? _dragValue
        : widget.position.inMilliseconds / _durationMs;
    return position.clamp(0, 1).toDouble();
  }

  double get _bufferFraction {
    if (_durationMs <= 0) return 0;
    return (widget.buffered.inMilliseconds / _durationMs)
        .clamp(0, 1)
        .toDouble();
  }

  double _fraction(double dx, double width) {
    if (width <= 0) return 0;
    return (dx / width).clamp(0, 1).toDouble();
  }

  void _begin(double dx, double width) {
    setState(() {
      _dragging = true;
      _dragValue = _fraction(dx, width);
    });
  }

  void _update(double dx, double width) {
    if (!_dragging) return;
    setState(() => _dragValue = _fraction(dx, width));
  }

  void _end() {
    if (!_dragging) return;
    final target = Duration(
      milliseconds: (_dragValue * widget.duration.inMilliseconds).round(),
    );
    setState(() => _dragging = false);
    unawaited(widget.onSeek(target));
  }

  String _tipLabel(double width) {
    final fraction = _dragging ? _dragValue : _fraction(_hoverDx, width);
    final target = Duration(milliseconds: (fraction * _durationMs).round());
    final safe = target < Duration.zero ? Duration.zero : target;
    final hours = safe.inHours;
    final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (event) => setState(() {
        _hovered = true;
        _hoverDx = event.localPosition.dx;
      }),
      onHover: (event) => setState(() => _hoverDx = event.localPosition.dx),
      onExit: (_) => setState(() => _hovered = false),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: (details) => _begin(details.localPosition.dx, width),
            onTapUp: (_) => _end(),
            onTapCancel: () => setState(() => _dragging = false),
            onHorizontalDragStart: (details) =>
                _begin(details.localPosition.dx, width),
            onHorizontalDragUpdate: (details) =>
                _update(details.localPosition.dx, width),
            onHorizontalDragEnd: (_) => _end(),
            onHorizontalDragCancel: () => setState(() => _dragging = false),
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                CustomPaint(
                  painter: _TimelinePainter(
                    position: _positionFraction,
                    buffered: _bufferFraction,
                    emphasized: _hovered || _dragging,
                    accent: widget.accent,
                  ),
                  size: Size(width, constraints.maxHeight),
                ),
                if (_hovered &&
                    !_dragging &&
                    _durationMs > 0 &&
                    width.isFinite &&
                    width > 60)
                  Positioned(
                    left: (_hoverDx.clamp(34, width - 34)),
                    top: -14,
                    child: FractionalTranslation(
                      translation: const Offset(-0.5, 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xEB0A0E16),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Text(
                          _tipLabel(width),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            fontFeatures: <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  const _TimelinePainter({
    required this.position,
    required this.buffered,
    required this.emphasized,
    required this.accent,
  });

  final double position;
  final double buffered;
  final bool emphasized;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final trackHeight = emphasized ? 5.5 : 4.5;
    final top = (size.height - trackHeight) / 2;
    final radius = Radius.circular(trackHeight);
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, top, size.width, trackHeight),
      radius,
    );
    canvas.drawRRect(
      track,
      Paint()..color = Colors.white.withValues(alpha: 0.18),
    );
    final bufferedWidth = size.width * buffered.clamp(0, 1);
    if (bufferedWidth > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, top, bufferedWidth, trackHeight),
          radius,
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.32),
      );
    }
    final progressWidth = size.width * position.clamp(0, 1);
    if (progressWidth > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, top, progressWidth, trackHeight),
          radius,
        ),
        Paint()..color = accent,
      );
    }
    final thumb = Offset(progressWidth.clamp(0, size.width), size.height / 2);
    if (emphasized) {
      canvas.drawCircle(thumb, 6.5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) {
    return oldDelegate.position != position ||
        oldDelegate.buffered != buffered ||
        oldDelegate.emphasized != emphasized ||
        oldDelegate.accent != accent;
  }
}

class _HoverSurface extends StatefulWidget {
  const _HoverSurface({required this.builder, this.onEnter, this.onExit});

  final Widget Function(bool hovered) builder;
  final ValueChanged<Rect>? onEnter;
  final VoidCallback? onExit;

  @override
  State<_HoverSurface> createState() => _HoverSurfaceState();
}

class _HoverSurfaceState extends State<_HoverSurface> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _hovered = true);
        final object = context.findRenderObject();
        if (widget.onEnter != null && object is RenderBox && object.hasSize) {
          widget.onEnter!(object.localToGlobal(Offset.zero) & object.size);
        }
      },
      onExit: (_) {
        setState(() => _hovered = false);
        widget.onExit?.call();
      },
      child: AnimatedScale(
        scale: _hovered ? 1.08 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: widget.builder(_hovered),
      ),
    );
  }
}

class _MarqueeText extends StatefulWidget {
  const _MarqueeText({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _travel = 0;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this);
  }

  @override
  void dispose() {
    _generation++;
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run(double travel) async {
    if ((_travel - travel).abs() < 1 && _controller.isAnimating) return;
    _travel = travel;
    final generation = ++_generation;
    _controller
      ..stop()
      ..value = 0;
    while (mounted && generation == _generation && travel > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      if (!mounted || generation != _generation) return;
      try {
        await _controller.animateTo(
          travel,
          duration: Duration(
            milliseconds: (travel * 25).clamp(2400, 6200).round(),
          ),
          curve: Curves.linear,
        );
      } catch (_) {
        return;
      }
      if (!mounted || generation != _generation) return;
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted || generation != _generation) return;
      _controller.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          textDirection: Directionality.of(context),
          maxLines: 1,
        )..layout(maxWidth: double.infinity);
        final available = constraints.maxWidth;
        if (!available.isFinite || painter.width <= available + 2) {
          _generation++;
          _travel = 0;
          _controller
            ..stop()
            ..value = 0;
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: widget.style,
          );
        }
        final travel = painter.width - available + 28;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_run(travel));
        });
        return ClipRect(
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => const LinearGradient(
              colors: <Color>[
                Colors.transparent,
                Colors.black,
                Colors.black,
                Colors.transparent,
              ],
              stops: <double>[0, 0.035, 0.965, 1],
            ).createShader(rect),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (_, child) => Transform.translate(
                offset: Offset(-_controller.value, 0),
                child: child,
              ),
              child: Text(
                '${widget.text}        ${widget.text}',
                maxLines: 1,
                overflow: TextOverflow.visible,
                softWrap: false,
                style: widget.style,
              ),
            ),
          ),
        );
      },
    );
  }
}
