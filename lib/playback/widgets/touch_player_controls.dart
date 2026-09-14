import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';

/// Touch controls for the shared media_kit host. All playback stays in the host.
class TouchPlayerControls extends StatefulWidget {
  const TouchPlayerControls({
    super.key,
    required this.title,
    required this.playing,
    required this.loading,
    required this.position,
    required this.duration,
    required this.rate,
    required this.isFullscreen,
    required this.danmakuEnabled,
    required this.onBack,
    required this.onToggle,
    required this.onSeek,
    required this.onFullscreen,
    required this.onSettings,
    required this.onSpeed,
    required this.onDanmaku,
    required this.onAudio,
    required this.onSubtitle,
    required this.onScreenshot,
    this.onEpisodes,
    this.onPrevious,
    this.onNext,
    this.onQuality,
    this.qualityLabel = '',
  });

  final String title;
  final bool playing;
  final bool loading;
  final Duration position;
  final Duration duration;
  final double rate;
  final bool isFullscreen;
  final bool danmakuEnabled;
  final VoidCallback onBack;
  final VoidCallback onToggle;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onFullscreen;
  final VoidCallback onSettings;
  final VoidCallback onSpeed;
  final VoidCallback onDanmaku;
  final VoidCallback onAudio;
  final VoidCallback onSubtitle;
  final VoidCallback onScreenshot;
  final VoidCallback? onEpisodes;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onQuality;
  final String qualityLabel;

  @override
  State<TouchPlayerControls> createState() => _TouchPlayerControlsState();
}

class _TouchPlayerControlsState extends State<TouchPlayerControls> {
  double? _dragPosition;

  Widget _button(IconData icon, String label, VoidCallback? onPressed) {
    return IconButton(
      icon: Icon(icon),
      tooltip: label,
      color: Colors.white,
      disabledColor: Colors.white38,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      onPressed: onPressed,
    );
  }

  Widget _action(
    String label,
    VoidCallback onPressed, {
    bool selected = false,
  }) {
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: selected ? context.appColors.accent : Colors.white,
        minimumSize: const Size(48, 48),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }

  String _time(Duration value) {
    final seconds = value.inSeconds.clamp(0, 1 << 31);
    final minutes = (seconds ~/ 60 % 60).toString().padLeft(2, '0');
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    return seconds >= 3600
        ? '${seconds ~/ 3600}:$minutes:$remainder'
        : '$minutes:$remainder';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final maximum = widget.duration.inMilliseconds.clamp(1, 1 << 53).toDouble();
    final position =
        (_dragPosition ?? widget.position.inMilliseconds.toDouble()).clamp(
          0.0,
          maximum,
        );
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xAA000000), Colors.transparent, Color(0xCC000000)],
          stops: [0, 0.4, 1],
        ),
      ),
      child: SafeArea(
        minimum: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _button(
                  Icons.arrow_back_rounded,
                  MaterialLocalizations.of(context).backButtonTooltip,
                  widget.onBack,
                ),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _button(
                  Icons.settings_outlined,
                  l10n.desktopPlaybackMoreOptions,
                  widget.onSettings,
                ),
              ],
            ),
            const Spacer(),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: context.appColors.accent,
                inactiveTrackColor: Colors.white38,
                thumbColor: Colors.white,
                trackHeight: 3,
              ),
              child: Slider(
                value: position,
                max: maximum,
                semanticFormatterCallback: (value) =>
                    _time(Duration(milliseconds: value.round())),
                onChanged: widget.loading || widget.duration <= Duration.zero
                    ? null
                    : (value) => setState(() => _dragPosition = value),
                onChangeEnd: (value) {
                  setState(() => _dragPosition = null);
                  widget.onSeek(Duration(milliseconds: value.round()));
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    _time(Duration(milliseconds: position.round())),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const Spacer(),
                  Text(
                    _time(widget.duration),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                if (widget.onPrevious != null)
                  _button(
                    Icons.skip_previous_rounded,
                    l10n.desktopPlaybackPrevEpisodeTooltip,
                    widget.onPrevious,
                  ),
                if (widget.loading)
                  const SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  )
                else
                  _button(
                    widget.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    widget.playing
                        ? l10n.desktopPlaybackPauseTooltip
                        : l10n.desktopPlaybackPlayTooltip,
                    widget.onToggle,
                  ),
                if (widget.onNext != null)
                  _button(
                    Icons.skip_next_rounded,
                    l10n.playerEpisodeAction,
                    widget.onNext,
                  ),
                const Spacer(),
                _button(
                  widget.isFullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  widget.isFullscreen
                      ? l10n.desktopPlaybackExitFullscreenTooltip
                      : l10n.desktopPlaybackFullscreenTooltip,
                  widget.onFullscreen,
                ),
              ],
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _action('${widget.rate}×', widget.onSpeed),
                  if (widget.onEpisodes != null)
                    _action(l10n.playerEpisodeAction, widget.onEpisodes!),
                  if (widget.onQuality != null)
                    _action(widget.qualityLabel, widget.onQuality!),
                  _action(l10n.playerSubtitleAction, widget.onSubtitle),
                  _action(l10n.playerAudioTrackAction, widget.onAudio),
                  _action(
                    l10n.settingsDanmakuTitle,
                    widget.onDanmaku,
                    selected: widget.danmakuEnabled,
                  ),
                  _action(
                    l10n.desktopPlaybackScreenshotAction,
                    widget.onScreenshot,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
