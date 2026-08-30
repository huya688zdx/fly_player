import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'danmaku_benchmark_overlay.dart';

/// 桌面播放内核 PoC：libmpv 视频纹理、Flutter 弹幕层与最小控制层。
class PlaybackPocScreen extends StatefulWidget {
  const PlaybackPocScreen({
    super.key,
    required this.mediaUrl,
    required this.benchmarkComments,
    this.httpHeadersFilePath = '',
  });

  /// 为空时不打开媒体，但弹幕压测仍可独立运行。
  final String mediaUrl;

  /// 同屏弹幕条数；小于等于 0 时关闭压测层。
  final int benchmarkComments;

  /// 仓库外请求头 JSON object 文件的绝对路径。
  final String httpHeadersFilePath;

  @override
  State<PlaybackPocScreen> createState() => _PlaybackPocScreenState();
}

class _PlaybackPocScreenState extends State<PlaybackPocScreen> {
  final Player _player = Player();
  late final VideoController _videoController = VideoController(_player);
  late final StreamSubscription<String> _playerErrorSubscription;
  late final Timer _diagnosticsTimer;

  String? _visibleError;
  bool _isPreparingMedia = false;
  bool _diagnosticsRefreshInFlight = false;
  double? _dragPositionMilliseconds;
  String _hwdecCurrent = 'n/a';
  String _decoderFrameDrops = 'n/a';
  String _frameDrops = 'n/a';

  bool get _hasMedia => widget.mediaUrl.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _playerErrorSubscription = _player.stream.error.listen((_) {
      _setVisibleError('播放内核报告错误，请检查媒体地址与请求头配置。');
    });
    _diagnosticsTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_refreshDiagnostics()),
    );
    if (_hasMedia) {
      _isPreparingMedia = true;
      unawaited(_openConfiguredMedia());
    }
  }

  @override
  void dispose() {
    _diagnosticsTimer.cancel();
    unawaited(_playerErrorSubscription.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _openConfiguredMedia() async {
    Map<String, String>? httpHeaders;
    if (widget.httpHeadersFilePath.isNotEmpty) {
      try {
        final source = await File(widget.httpHeadersFilePath).readAsString();
        final decoded = jsonDecode(source);
        if (decoded is! Map<String, dynamic> ||
            decoded.values.any((value) => value is! String)) {
          _setVisibleError('请求头文件必须是 JSON object，且所有键和值都是字符串。');
          _finishPreparingMedia();
          return;
        }
        httpHeaders = decoded.map(
          (key, value) => MapEntry(key, value as String),
        );
      } on FileSystemException {
        _setVisibleError('无法读取请求头文件，请确认 POC_HTTP_HEADERS_FILE 指向仓库外的可读文件。');
        _finishPreparingMedia();
        return;
      } on FormatException {
        _setVisibleError('请求头文件不是合法的 JSON object。');
        _finishPreparingMedia();
        return;
      } catch (_) {
        _setVisibleError('请求头文件加载失败。');
        _finishPreparingMedia();
        return;
      }
    }

    try {
      await _player.open(Media(widget.mediaUrl, httpHeaders: httpHeaders));
    } catch (_) {
      _setVisibleError('媒体打开失败，请检查媒体地址与请求头配置。');
    } finally {
      _finishPreparingMedia();
    }
  }

  void _finishPreparingMedia() {
    if (mounted) {
      setState(() => _isPreparingMedia = false);
    }
  }

  void _setVisibleError(String message) {
    if (mounted) {
      setState(() => _visibleError = message);
    }
  }

  Future<void> _refreshDiagnostics() async {
    if (_diagnosticsRefreshInFlight) return;
    final platform = _player.platform;
    if (platform is! NativePlayer) return;

    _diagnosticsRefreshInFlight = true;
    try {
      final values = await Future.wait(<Future<String>>[
        _readNativeProperty(platform, 'hwdec-current'),
        _readNativeProperty(platform, 'decoder-frame-drop-count'),
        _readNativeProperty(platform, 'frame-drop-count'),
      ]);
      if (!mounted) return;
      setState(() {
        _hwdecCurrent = values[0];
        _decoderFrameDrops = values[1];
        _frameDrops = values[2];
      });
    } finally {
      _diagnosticsRefreshInFlight = false;
    }
  }

  Future<String> _readNativeProperty(
    NativePlayer player,
    String property,
  ) async {
    try {
      final value = (await player.getProperty(property)).trim();
      return value.isEmpty ? 'n/a' : value;
    } catch (_) {
      return 'n/a';
    }
  }

  Future<void> _seekRelative(Duration offset) async {
    var target = _player.state.position.inMicroseconds + offset.inMicroseconds;
    if (target < 0) target = 0;
    final duration = _player.state.duration.inMicroseconds;
    if (duration > 0 && target > duration) target = duration;
    await _player.seek(Duration(microseconds: target));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _buildVideoLayer(),
          _buildDanmakuLayer(),
          _buildControlLayer(),
        ],
      ),
    );
  }

  Widget _buildVideoLayer() {
    if (!_hasMedia) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              '未提供媒体地址\n'
              '请通过 POC_MEDIA_URL 传入本地文件绝对路径或网络地址。\n'
              '弹幕压测仍可独立运行。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF9AA6B6),
                fontSize: 16,
                height: 1.7,
              ),
            ),
          ),
        ),
      );
    }
    return Video(
      controller: _videoController,
      fit: BoxFit.contain,
      controls: NoVideoControls,
    );
  }

  Widget _buildDanmakuLayer() {
    return IgnorePointer(
      child: RepaintBoundary(
        child: widget.benchmarkComments > 0
            ? DanmakuBenchmarkOverlay(commentCount: widget.benchmarkComments)
            : const SizedBox.expand(),
      ),
    );
  }

  Widget _buildControlLayer() {
    return SafeArea(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (_visibleError != null)
            Align(
              alignment: Alignment.topCenter,
              child: _buildErrorBanner(_visibleError!),
            ),
          Align(alignment: Alignment.topRight, child: _buildDiagnosticsPanel()),
          Align(alignment: Alignment.bottomCenter, child: _buildControlBar()),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      margin: const EdgeInsets.all(18),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xE65A1F25),
        border: Border.all(color: const Color(0x80FF8A92)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }

  Widget _buildDiagnosticsPanel() {
    return Container(
      margin: const EdgeInsets.all(18),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xCC0B111C),
        border: Border.all(color: const Color(0x24FFFFFF)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'hwdec: $_hwdecCurrent\n'
        'decoder drops: $_decoderFrameDrops\n'
        'frame drops: $_frameDrops',
        style: const TextStyle(
          color: Color(0xFFB7C1CE),
          fontSize: 11,
          height: 1.45,
          fontFeatures: <ui.FontFeature>[ui.FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  Widget _buildControlBar() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 1200),
      margin: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xE60B111C),
        border: Border.all(color: const Color(0x2EFFFFFF)),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x66000000), blurRadius: 24),
        ],
      ),
      child: StreamBuilder<Duration>(
        stream: _player.stream.duration,
        initialData: _player.state.duration,
        builder: (context, durationSnapshot) {
          final duration = durationSnapshot.data ?? Duration.zero;
          return StreamBuilder<Duration>(
            stream: _player.stream.position,
            initialData: _player.state.position,
            builder: (context, positionSnapshot) {
              final position = positionSnapshot.data ?? Duration.zero;
              return _buildProgressControls(position, duration);
            },
          );
        },
      ),
    );
  }

  Widget _buildProgressControls(Duration position, Duration duration) {
    final durationMilliseconds = duration.inMilliseconds;
    final positionMilliseconds = position.inMilliseconds
        .clamp(0, durationMilliseconds > 0 ? durationMilliseconds : 0)
        .toDouble();
    final sliderValue = (_dragPositionMilliseconds ?? positionMilliseconds)
        .clamp(0.0, durationMilliseconds.toDouble());
    final canSeek = _hasMedia && durationMilliseconds > 0;

    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: const Color(0xFF5E8BFF),
        inactiveTrackColor: const Color(0x33FFFFFF),
        thumbColor: Colors.white,
        overlayColor: const Color(0x335E8BFF),
        trackHeight: 4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Slider(
            value: sliderValue,
            max: durationMilliseconds > 0 ? durationMilliseconds.toDouble() : 1,
            onChanged: canSeek
                ? (value) {
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
              StreamBuilder<bool>(
                stream: _player.stream.playing,
                initialData: _player.state.playing,
                builder: (context, snapshot) {
                  final playing = snapshot.data ?? false;
                  return IconButton(
                    tooltip: playing ? '暂停' : '播放',
                    onPressed: _hasMedia
                        ? () => unawaited(_player.playOrPause())
                        : null,
                    icon: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    ),
                    color: Colors.white,
                  );
                },
              ),
              IconButton(
                tooltip: '后退 10 秒',
                onPressed: _hasMedia
                    ? () =>
                          unawaited(_seekRelative(const Duration(seconds: -10)))
                    : null,
                icon: const Icon(Icons.replay_10_rounded),
                color: Colors.white,
              ),
              IconButton(
                tooltip: '前进 10 秒',
                onPressed: _hasMedia
                    ? () =>
                          unawaited(_seekRelative(const Duration(seconds: 10)))
                    : null,
                icon: const Icon(Icons.forward_10_rounded),
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Text(
                '${_formatDuration(position)} / ${_formatDuration(duration)}',
                style: const TextStyle(
                  color: Color(0xFFD9E0E8),
                  fontSize: 12,
                  fontFeatures: <ui.FontFeature>[
                    ui.FontFeature.tabularFigures(),
                  ],
                ),
              ),
              if (_isPreparingMedia) ...<Widget>[
                const SizedBox(width: 14),
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
              const Spacer(),
              Text(
                widget.benchmarkComments > 0
                    ? '弹幕压测 ${widget.benchmarkComments} 条'
                    : '弹幕压测关闭',
                style: const TextStyle(color: Color(0xFF7E8A9A), fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}
