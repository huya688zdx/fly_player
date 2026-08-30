import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../playback/playback_source.dart';
import '../../theme/app_theme.dart';

const Duration _controlsHideDelay = Duration(milliseconds: 2800);
const Duration _controlsAnimationDuration = Duration(milliseconds: 220);
const List<double> _playbackRates = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/// Windows 桌面正式播放页。
///
/// 当前阶段只负责单个媒体源的基础播放控制。[episodes] 与 [danmakuFilePath]
/// 保留给后续产品化接入，本页不会切集或解析弹幕。
class DesktopPlaybackScreen extends StatefulWidget {
  const DesktopPlaybackScreen({
    super.key,
    required this.source,
    this.episodes,
    this.danmakuFilePath,
  });

  final MpvMediaSource source;
  final List<Map<String, dynamic>>? episodes;
  final String? danmakuFilePath;

  @override
  State<DesktopPlaybackScreen> createState() => _DesktopPlaybackScreenState();
}

class _DesktopPlaybackScreenState extends State<DesktopPlaybackScreen> {
  late final Player _player;
  late final VideoController _videoController;
  late final StreamSubscription<String> _errorSubscription;
  late final StreamSubscription<bool> _playingSubscription;
  late final StreamSubscription<double> _volumeSubscription;

  Timer? _controlsHideTimer;
  String? _errorMessage;
  bool _isLoading = true;
  bool _isPlaying = false;
  bool _controlsVisible = true;
  double _volume = 100;
  double _lastAudibleVolume = 100;
  double _playbackRate = 1;
  double? _dragPositionMilliseconds;

  @override
  void initState() {
    super.initState();
    MediaKit.ensureInitialized();
    _player = Player();
    _videoController = VideoController(_player);
    _playbackRate = _validPlaybackRate(widget.source.playbackSpeed);
    _volume = _player.state.volume;
    if (_volume > 0) _lastAudibleVolume = _volume;

    _errorSubscription = _player.stream.error.listen((_) {
      _showGenericError('播放发生错误，请检查媒体是否仍可访问。');
    });
    _playingSubscription = _player.stream.playing.listen(_onPlayingChanged);
    _volumeSubscription = _player.stream.volume.listen(_onVolumeChanged);
    unawaited(_openSource());
  }

  @override
  void dispose() {
    _controlsHideTimer?.cancel();
    unawaited(_errorSubscription.cancel());
    unawaited(_playingSubscription.cancel());
    unawaited(_volumeSubscription.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _openSource() async {
    if (widget.source.url.trim().isEmpty) {
      _showGenericError('媒体地址不可用。');
      _finishLoading();
      return;
    }

    try {
      await _player.open(
        Media(widget.source.url, httpHeaders: widget.source.headers),
        play: false,
      );
      if (widget.source.startPosition > Duration.zero) {
        await _player.seek(widget.source.startPosition);
      }
      await _player.setRate(_playbackRate);
      if (!widget.source.startPaused) {
        await _player.play();
      }
    } catch (_) {
      _showGenericError('无法开始播放，请检查媒体与网络状态。');
    } finally {
      _finishLoading();
    }
  }

  double _validPlaybackRate(double value) {
    return value.isFinite && value > 0 ? value : 1;
  }

  void _finishLoading() {
    if (mounted) setState(() => _isLoading = false);
  }

  void _showGenericError(String message) {
    if (mounted) setState(() => _errorMessage = message);
  }

  void _onPlayingChanged(bool playing) {
    if (!mounted) return;
    setState(() {
      _isPlaying = playing;
      if (!playing) _controlsVisible = true;
    });
    if (playing) {
      _scheduleControlsHide();
    } else {
      _controlsHideTimer?.cancel();
    }
  }

  void _onVolumeChanged(double volume) {
    if (!mounted) return;
    setState(() {
      _volume = volume.clamp(0.0, 100.0).toDouble();
      if (_volume > 0) _lastAudibleVolume = _volume;
    });
  }

  void _wakeControls({bool scheduleHide = true}) {
    if (!_controlsVisible && mounted) {
      setState(() => _controlsVisible = true);
    }
    _controlsHideTimer?.cancel();
    if (scheduleHide && _isPlaying) _scheduleControlsHide();
  }

  void _scheduleControlsHide() {
    _controlsHideTimer?.cancel();
    _controlsHideTimer = Timer(_controlsHideDelay, () {
      if (mounted && _isPlaying) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  Future<void> _togglePlayback() async {
    _wakeControls();
    await _player.playOrPause();
  }

  Future<void> _seekRelative(Duration offset) async {
    _wakeControls();
    var target = _player.state.position.inMicroseconds + offset.inMicroseconds;
    if (target < 0) target = 0;
    final duration = _player.state.duration.inMicroseconds;
    if (duration > 0 && target > duration) target = duration;
    await _player.seek(Duration(microseconds: target));
  }

  Future<void> _setVolume(double value) async {
    _wakeControls();
    final next = value.clamp(0.0, 100.0).toDouble();
    setState(() {
      _volume = next;
      if (next > 0) _lastAudibleVolume = next;
    });
    await _player.setVolume(next);
  }

  Future<void> _toggleMute() async {
    await _setVolume(_volume > 0 ? 0 : _lastAudibleVolume);
  }

  Future<void> _setPlaybackRate(double value) async {
    _wakeControls();
    setState(() => _playbackRate = value);
    await _player.setRate(value);
  }

  Future<void> _leavePlayer(VideoState videoState) async {
    _wakeControls();
    if (videoState.isFullscreen()) {
      await videoState.exitFullscreen();
      return;
    }
    if (mounted) await Navigator.of(context).maybePop();
  }

  KeyEventResult _handleKeyEvent(VideoState videoState, KeyEvent event) {
    final isInitialPress = event is KeyDownEvent;
    final isRepeatablePress = isInitialPress || event is KeyRepeatEvent;
    if (!isRepeatablePress) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space && isInitialPress) {
      unawaited(_togglePlayback());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      unawaited(_seekRelative(const Duration(seconds: -10)));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      unawaited(_seekRelative(const Duration(seconds: 10)));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && isInitialPress) {
      unawaited(_leavePlayer(videoState));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ColoredBox(
        color: Colors.black,
        child: Video(
          controller: _videoController,
          fit: BoxFit.contain,
          // 使用自建控制层，明确关闭 media_kit 的默认 controls。
          controls: _buildVideoControls,
        ),
      ),
    );
  }

  Widget _buildVideoControls(VideoState videoState) {
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) => _handleKeyEvent(videoState, event),
      child: MouseRegion(
        opaque: true,
        cursor: _controlsVisible
            ? SystemMouseCursors.basic
            : SystemMouseCursors.none,
        onEnter: (_) => _wakeControls(),
        onHover: (_) => _wakeControls(),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _buildStatusLayer(),
            IgnorePointer(
              ignoring: !_controlsVisible,
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1 : 0,
                duration: _controlsAnimationDuration,
                curve: Curves.easeOutCubic,
                child: SafeArea(
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      Align(
                        alignment: Alignment.topCenter,
                        child: _buildTopBar(videoState),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: _buildBottomBar(videoState),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusLayer() {
    if (_isLoading) {
      return const Center(
        child: SizedBox.square(
          dimension: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: Color(0xFF63A0FF),
          ),
        ),
      );
    }
    if (_errorMessage == null) return const SizedBox.shrink();

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xE60D1624),
          border: Border.all(color: const Color(0x66D64545)),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: Color(0x99000000), blurRadius: 30),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline_rounded, color: Color(0xFFFF8A92)),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                _errorMessage!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(VideoState videoState) {
    final subtitle = _subtitle;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 34),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xD9000000), Color(0x00000000)],
        ),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: videoState.isFullscreen() ? '退出全屏' : '返回',
            onPressed: () => unawaited(_leavePlayer(videoState)),
            icon: const Icon(Icons.arrow_back_rounded),
            color: Colors.white,
            style: _iconButtonStyle,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  widget.source.title.trim().isEmpty
                      ? '正在播放'
                      : widget.source.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.15,
                  ),
                ),
                if (subtitle.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xA8FFFFFF),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0x24FFFFFF),
              border: Border.all(color: const Color(0x2EFFFFFF)),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              _resolutionLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(VideoState videoState) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 46, 20, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0x00000000), Color(0xE6000000)],
        ),
      ),
      child: StreamBuilder<Duration>(
        stream: _player.stream.duration,
        initialData: _initialDuration,
        builder: (context, durationSnapshot) {
          final duration = durationSnapshot.data ?? _initialDuration;
          return StreamBuilder<Duration>(
            stream: _player.stream.position,
            initialData: _player.state.position,
            builder: (context, positionSnapshot) {
              final position = positionSnapshot.data ?? Duration.zero;
              return _buildTimelineAndButtons(videoState, position, duration);
            },
          );
        },
      ),
    );
  }

  Widget _buildTimelineAndButtons(
    VideoState videoState,
    Duration position,
    Duration duration,
  ) {
    final colors = context.appColors;
    final durationMilliseconds = duration.inMilliseconds;
    final positionMilliseconds = position.inMilliseconds
        .clamp(0, durationMilliseconds > 0 ? durationMilliseconds : 0)
        .toDouble();
    final sliderValue = (_dragPositionMilliseconds ?? positionMilliseconds)
        .clamp(0.0, durationMilliseconds.toDouble());
    final canSeek = durationMilliseconds > 0;

    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: colors.accent,
        inactiveTrackColor: const Color(0x38FFFFFF),
        secondaryActiveTrackColor: const Color(0x5CFFFFFF),
        thumbColor: Colors.white,
        overlayColor: colors.accentSoft,
        trackHeight: 4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Slider(
            value: sliderValue,
            max: canSeek ? durationMilliseconds.toDouble() : 1,
            onChanged: canSeek
                ? (value) {
                    _wakeControls();
                    setState(() => _dragPositionMilliseconds = value);
                  }
                : null,
            onChangeEnd: canSeek
                ? (value) {
                    setState(() => _dragPositionMilliseconds = null);
                    unawaited(
                      _player.seek(Duration(milliseconds: value.round())),
                    );
                  }
                : null,
          ),
          Row(
            children: <Widget>[
              IconButton(
                tooltip: _isPlaying ? '暂停 (Space)' : '播放 (Space)',
                onPressed: () => unawaited(_togglePlayback()),
                icon: Icon(
                  _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 24,
                ),
                color: Colors.white,
                style: _iconButtonStyle,
              ),
              IconButton(
                tooltip: '后退 10 秒 (←)',
                onPressed: () =>
                    unawaited(_seekRelative(const Duration(seconds: -10))),
                icon: const Icon(Icons.replay_10_rounded, size: 21),
                color: Colors.white,
                style: _iconButtonStyle,
              ),
              IconButton(
                tooltip: '前进 10 秒 (→)',
                onPressed: () =>
                    unawaited(_seekRelative(const Duration(seconds: 10))),
                icon: const Icon(Icons.forward_10_rounded, size: 21),
                color: Colors.white,
                style: _iconButtonStyle,
              ),
              const SizedBox(width: 10),
              Text(
                '${_formatDuration(position)}  /  ${_formatDuration(duration)}',
                style: const TextStyle(
                  color: Color(0xBFFFFFFF),
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: _volume > 0 ? '静音' : '恢复音量',
                onPressed: () => unawaited(_toggleMute()),
                icon: Icon(
                  _volume <= 0
                      ? Icons.volume_off_rounded
                      : _volume < 45
                      ? Icons.volume_down_rounded
                      : Icons.volume_up_rounded,
                  size: 20,
                ),
                color: Colors.white,
                style: _iconButtonStyle,
              ),
              SizedBox(
                width: 104,
                child: Slider(
                  value: _volume.clamp(0, 100),
                  max: 100,
                  onChanged: (value) => unawaited(_setVolume(value)),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<double>(
                tooltip: '播放速度',
                color: const Color(0xF20D1624),
                surfaceTintColor: Colors.transparent,
                onOpened: () => _wakeControls(scheduleHide: false),
                onCanceled: _wakeControls,
                onSelected: (value) => unawaited(_setPlaybackRate(value)),
                itemBuilder: (context) => _playbackRates
                    .map(
                      (rate) => PopupMenuItem<double>(
                        value: rate,
                        child: Text(
                          '${_formatRate(rate)}x',
                          style: TextStyle(
                            color: rate == _playbackRate
                                ? colors.accentStrong
                                : Colors.white,
                            fontSize: 13,
                            fontWeight: rate == _playbackRate
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
                child: _textControlButton('${_formatRate(_playbackRate)}x'),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: videoState.isFullscreen() ? '退出全屏' : '全屏',
                onPressed: () {
                  _wakeControls();
                  unawaited(videoState.toggleFullscreen());
                },
                icon: Icon(
                  videoState.isFullscreen()
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  size: 22,
                ),
                color: Colors.white,
                style: _iconButtonStyle,
              ),
            ],
          ),
        ],
      ),
    );
  }

  ButtonStyle get _iconButtonStyle => IconButton.styleFrom(
    fixedSize: const Size.square(40),
    hoverColor: const Color(0x24FFFFFF),
    highlightColor: const Color(0x30FFFFFF),
    disabledForegroundColor: const Color(0x4DFFFFFF),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );

  Widget _textControlButton(String label) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.25,
        ),
      ),
    );
  }

  Duration get _initialDuration => widget.source.durationSeconds > 0
      ? Duration(seconds: widget.source.durationSeconds)
      : Duration.zero;

  String get _subtitle {
    final parts = <String>[];
    if (widget.source.seriesTitle.trim().isNotEmpty) {
      parts.add(widget.source.seriesTitle.trim());
    }
    if (widget.source.seasonNumber > 0 || widget.source.episodeNumber > 0) {
      final season = widget.source.seasonNumber > 0
          ? 'S${widget.source.seasonNumber.toString().padLeft(2, '0')}'
          : '';
      final episode = widget.source.episodeNumber > 0
          ? 'E${widget.source.episodeNumber.toString().padLeft(2, '0')}'
          : '';
      parts.add('$season$episode');
    }
    return parts.join(' · ');
  }

  String get _resolutionLabel {
    final resolution = widget.source.resolution.trim();
    if (resolution.isNotEmpty) return resolution;
    if (widget.source.videoWidth > 0 && widget.source.videoHeight > 0) {
      return '${widget.source.videoWidth}×${widget.source.videoHeight}';
    }
    return '原画';
  }

  String _formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  String _formatRate(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(1)
        : value.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
  }
}
