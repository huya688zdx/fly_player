import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:media_kit/media_kit.dart';

import '../../danmaku/models/danmaku_comment.dart';
import '../../danmaku/models/danmaku_settings.dart';
import '../../danmaku/parser/danmaku_import_parser.dart';
import '../../services/app_log_service.dart';
import 'desktop_danmaku_lane_tracker.dart';
import 'desktop_danmaku_clock.dart';
import 'desktop_danmaku_raster_cache.dart';
import 'desktop_danmaku_segmenter.dart';

@visibleForTesting
({Rect source, Rect destination}) resolveDesktopDanmakuMaskRects({
  required Size frameSize,
  required Size maskSize,
  required Size canvasSize,
  required BoxFit fit,
}) {
  final fitted = applyBoxFit(fit, frameSize, canvasSize);
  final frameSource = Alignment.center.inscribe(
    fitted.source,
    Offset.zero & frameSize,
  );
  final source = Rect.fromLTRB(
    frameSource.left * maskSize.width / frameSize.width,
    frameSource.top * maskSize.height / frameSize.height,
    frameSource.right * maskSize.width / frameSize.width,
    frameSource.bottom * maskSize.height / frameSize.height,
  );
  final destination = Alignment.center.inscribe(
    fitted.destination,
    Offset.zero & canvasSize,
  );
  return (source: source, destination: destination);
}

class DesktopDanmakuPayload {
  const DesktopDanmakuPayload({
    required this.sourceLabel,
    required this.comments,
    this.sourceKey = '',
  });

  final String sourceLabel;
  final String sourceKey;
  final List<DanmakuComment> comments;

  // 文件读取、紧凑弹幕解码和排序统一放到工作 isolate，避免切集卡住界面。
  static Future<DesktopDanmakuPayload> load(String path) =>
      compute(_load, path);

  static Future<DesktopDanmakuPayload> _load(String path) async {
    final file = File(path);
    final raw = await file.readAsString();
    final normalized = raw.trimLeft();
    final decoded = normalized.startsWith('{') || normalized.startsWith('[')
        ? jsonDecode(raw)
        : null;
    if (decoded is Map && decoded['commentsCompact'] is List) {
      final comments = <DanmakuComment>[];
      for (final rawComment in decoded['commentsCompact'] as List) {
        if (rawComment is! List || rawComment.length < 5) continue;
        final text = '${rawComment[2] ?? ''}'.trim();
        if (text.isEmpty) continue;
        comments.add(
          DanmakuComment(
            id: '${rawComment[0] ?? ''}',
            timeMs: (rawComment[1] as num?)?.toInt() ?? 0,
            text: text,
            type: switch ((rawComment[3] as num?)?.toInt() ?? 0) {
              1 => DanmakuCommentType.top,
              2 => DanmakuCommentType.bottom,
              _ => DanmakuCommentType.scroll,
            },
            color: Color((rawComment[4] as num?)?.toInt() ?? 0xFFFFFFFF),
          ),
        );
      }
      comments.sort((left, right) => left.timeMs.compareTo(right.timeMs));
      return DesktopDanmakuPayload(
        sourceLabel: _sourceLabel(decoded, file.uri.pathSegments.last),
        sourceKey: '${decoded['sourceKey'] ?? ''}',
        comments: List<DanmakuComment>.unmodifiable(comments),
      );
    }
    final result = await DanmakuImportParser.parseFile(path);
    return DesktopDanmakuPayload(
      sourceLabel: result.sourceLabel,
      comments: result.comments,
    );
  }

  static String _sourceLabel(Map payload, String fallback) {
    final label = '${payload['sourceLabel'] ?? ''}'.trim();
    if (label.isNotEmpty) return label;
    final key = '${payload['sourceKey'] ?? ''}';
    if (key.startsWith('nas:')) return '服务弹幕';
    if (key.startsWith('dandan:')) return '弹弹play';
    return key.isEmpty ? fallback : key;
  }
}

/// Windows 播放器的 Flutter 弹幕层。
///
/// 只使用一个 CustomPaint，并直接读取 media_kit 的播放时钟；不会为每条弹幕创建 Widget。
/// 文本经 [DanmakuRasterCache] 栅格化成纹理，每帧只贴图；车道由
/// [DanmakuLaneTracker] 在弹幕出生时分配一次，终生不变。
class DesktopDanmakuOverlay extends StatefulWidget {
  const DesktopDanmakuOverlay({
    super.key,
    required this.player,
    required this.comments,
    required this.settings,
    required this.fit,
    required this.seekRevision,
  });

  final Player player;
  final List<DanmakuComment> comments;
  final DanmakuSettings settings;
  final BoxFit fit;
  final int seekRevision;

  @override
  State<DesktopDanmakuOverlay> createState() => _DesktopDanmakuOverlayState();
}

class _DesktopDanmakuOverlayState extends State<DesktopDanmakuOverlay>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);
  final DanmakuRasterCache _rasterCache = DanmakuRasterCache();
  final DanmakuLaneTracker _laneTracker = DanmakuLaneTracker();
  late final Ticker _ticker;
  late final StreamSubscription<Duration> _positionSubscription;
  late final StreamSubscription<bool> _playingSubscription;
  late final StreamSubscription<double> _rateSubscription;
  late final StreamSubscription<bool> _bufferingSubscription;

  late final DesktopDanmakuClock _motionClock;
  Duration _clock = Duration.zero;
  Duration _tickerOffset = Duration.zero;
  int _tickGapPeakUs = 0;
  bool _playing = false;
  bool _buffering = false;
  double _rate = 1;
  int _sampleFrames = 0;
  int _slowFrames = 0;
  int _buildTotalUs = 0;
  int _rasterTotalUs = 0;
  int _peakUs = 0;
  Duration _lastStatsAt = Duration.zero;
  Timer? _maskTimer;
  DesktopDanmakuMask? _mask;
  bool _maskInFlight = false;
  int _maskGeneration = 0;
  bool _maskFailureLogged = false;
  int _lastMaskInferenceMs = 0;
  int _lastMaskTotalMs = 0;

  @override
  void initState() {
    super.initState();
    _playing = widget.player.state.playing;
    _buffering = widget.player.state.buffering;
    _rate = widget.player.state.rate;
    _motionClock = DesktopDanmakuClock(
      position: widget.player.state.position,
      advancing: _playing && !_buffering,
      rate: _rate,
    );
    _ticker = createTicker(_onTick);
    _updateTicker();
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    _positionSubscription = widget.player.stream.position.listen((position) {
      final jumped = _motionClock.synchronize(position);
      if (jumped) {
        _laneTracker.reset();
        _maskGeneration++;
        _replaceMask(null);
      }
      // 连续播放只由 Ticker 请求绘制，消除异步消息插入的不等距帧。
      if (jumped || !_motionClock.advancing) _repaint.value += 1;
    });
    _bufferingSubscription = widget.player.stream.buffering.listen((buffering) {
      _buffering = buffering;
      _motionClock.advancing = _playing && !_buffering;
      _updateTicker();
      _repaint.value += 1;
    });
    _playingSubscription = widget.player.stream.playing.listen((playing) {
      _playing = playing;
      _motionClock.advancing = _playing && !_buffering;
      _updateTicker();
      _repaint.value += 1;
    });
    _rateSubscription = widget.player.stream.rate.listen((rate) {
      _rate = rate.isFinite && rate > 0 ? rate : 1;
      _motionClock.rate = _rate;
    });
    _updateMaskTimer();
  }

  @override
  void didUpdateWidget(covariant DesktopDanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateTicker();
    if (oldWidget.seekRevision != widget.seekRevision) {
      _maskGeneration++;
      _replaceMask(null);
    }
    if (oldWidget.settings.aiSampleIntervalMs !=
        widget.settings.aiSampleIntervalMs) {
      _maskTimer?.cancel();
      _maskTimer = null;
    }
    _updateMaskTimer();
  }

  void _updateMaskTimer() {
    final shouldRun =
        DesktopDanmakuSegmenter.isSupported &&
        widget.settings.enabled &&
        widget.settings.avoidCenterArea &&
        widget.comments.isNotEmpty;
    if (!shouldRun) {
      _maskTimer?.cancel();
      _maskTimer = null;
      _maskGeneration++;
      _replaceMask(null);
      return;
    }
    if (_maskTimer != null) return;
    unawaited(_updateMask());
    _maskTimer = Timer.periodic(
      Duration(
        milliseconds: widget.settings.aiSampleIntervalMs.clamp(200, 500),
      ),
      (_) => unawaited(_updateMask()),
    );
  }

  Future<void> _updateMask() async {
    if (_maskInFlight || !_playing || _buffering) return;
    _maskInFlight = true;
    final generation = _maskGeneration;
    try {
      final next = await DesktopDanmakuSegmenter.segment(
        widget.player,
        outputWidth: widget.settings.aiInputWidth,
      );
      if (!mounted || generation != _maskGeneration) {
        next?.dispose();
        return;
      }
      if (next != null) {
        _maskFailureLogged = false;
        _lastMaskInferenceMs = next.inferenceMs;
        _lastMaskTotalMs = next.totalMs;
      }
      _replaceMask(next);
    } catch (error) {
      if (mounted && generation == _maskGeneration) {
        _replaceMask(null);
        if (!_maskFailureLogged) {
          _maskFailureLogged = true;
          debugPrint('[desktop-danmaku] AI 遮罩暂不可用：$error');
        }
      }
    } finally {
      _maskInFlight = false;
    }
  }

  void _replaceMask(DesktopDanmakuMask? next) {
    if (identical(_mask, next)) return;
    _mask?.dispose();
    _mask = next;
    _repaint.value += 1;
  }

  void _updateTicker() {
    final shouldTick =
        _motionClock.advancing &&
        widget.settings.enabled &&
        widget.comments.isNotEmpty;
    if (shouldTick == _ticker.isActive) return;
    if (shouldTick) {
      // Ticker 重新开始时从零计时，接上旧帧时间，保持时钟与绘制期限连续。
      _tickerOffset = _clock;
      _ticker.start();
    } else {
      _ticker.stop();
    }
  }

  // Flutter 整个播放页面的耗时，不等同于弹幕耗时或视频解码帧率。
  void _onFrameTimings(List<FrameTiming> timings) {
    if (!mounted ||
        !_playing ||
        _buffering ||
        !widget.settings.enabled ||
        widget.comments.isEmpty) {
      return;
    }
    final refreshRate = View.of(context).display.refreshRate;
    final budgetUs = 1000000 / (refreshRate > 0 ? refreshRate : 60);
    for (final timing in timings) {
      final buildUs = timing.buildDuration.inMicroseconds;
      final rasterUs = timing.rasterDuration.inMicroseconds;
      _sampleFrames++;
      _buildTotalUs += buildUs;
      _rasterTotalUs += rasterUs;
      final longestUs = math.max(buildUs, rasterUs);
      _peakUs = math.max(_peakUs, longestUs);
      if (longestUs > budgetUs) _slowFrames++;
    }
    if (_clock - _lastStatsAt >= const Duration(seconds: 30)) {
      _recordFrameStats();
    }
  }

  void _recordFrameStats() {
    if (_sampleFrames == 0) return;
    unawaited(
      AppLogService.instance.record(
        level: AppLogLevel.info,
        source: 'desktop.danmaku.performance',
        error: '弹幕开启时的播放页面帧耗时',
        details:
            '采样帧=$_sampleFrames，超刷新预算帧=$_slowFrames '
            '(${(_slowFrames * 100 / _sampleFrames).toStringAsFixed(1)}%)，'
            'UI均值=${(_buildTotalUs / _sampleFrames / 1000).toStringAsFixed(2)}ms，'
            '光栅均值=${(_rasterTotalUs / _sampleFrames / 1000).toStringAsFixed(2)}ms，'
            '单阶段峰值=${(_peakUs / 1000).toStringAsFixed(2)}ms，'
            '刷新回调间隔峰值=${(_tickGapPeakUs / 1000).toStringAsFixed(2)}ms，'
            '弹幕目标帧率=${widget.settings.targetFrameRateHz}，'
            'AI推理=${_lastMaskInferenceMs}ms，'
            'AI取帧至蒙版=${_lastMaskTotalMs}ms，'
            '播放位置=${_currentPosition().inSeconds}s；'
            '统计整个Flutter页面，不代表视频解码帧率，也不能单独归因于弹幕。',
      ),
    );
    _sampleFrames = _slowFrames = _buildTotalUs = _rasterTotalUs = _peakUs = 0;
    _lastStatsAt = _clock;
    _tickGapPeakUs = 0;
  }

  void _onTick(Duration elapsed) {
    elapsed += _tickerOffset;
    if (_motionClock.advancing &&
        widget.settings.enabled &&
        widget.comments.isNotEmpty) {
      _tickGapPeakUs = math.max(
        _tickGapPeakUs,
        (elapsed - _clock).inMicroseconds,
      );
    }
    _clock = elapsed;
    final paintDue = _motionClock.tick(
      elapsed,
      frameRate: normalizeDanmakuFrameRateHz(widget.settings.targetFrameRateHz),
    );
    if (paintDue && widget.settings.enabled && widget.comments.isNotEmpty) {
      _repaint.value += 1;
    }
  }

  Duration _currentPosition() => _motionClock.position;

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    _recordFrameStats();
    _maskTimer?.cancel();
    _maskGeneration++;
    _mask?.dispose();
    _ticker.dispose();
    unawaited(_positionSubscription.cancel());
    unawaited(_playingSubscription.cancel());
    unawaited(_rateSubscription.cancel());
    unawaited(_bufferingSubscription.cancel());
    _rasterCache.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.settings.enabled || widget.comments.isEmpty) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _DesktopDanmakuPainter(
            comments: widget.comments,
            settings: widget.settings,
            positionProvider: _currentPosition,
            rasterCache: _rasterCache,
            laneTracker: _laneTracker,
            devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
            maskProvider: () => _mask,
            fit: widget.fit,
            repaint: _repaint,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _DesktopDanmakuPainter extends CustomPainter {
  _DesktopDanmakuPainter({
    required this.comments,
    required this.settings,
    required this.positionProvider,
    required this.rasterCache,
    required this.laneTracker,
    required this.devicePixelRatio,
    required this.maskProvider,
    required this.fit,
    required Listenable repaint,
  }) : super(repaint: repaint);

  static final Paint _imagePaint = Paint()..filterQuality = FilterQuality.low;

  final List<DanmakuComment> comments;
  final DanmakuSettings settings;
  final Duration Function() positionProvider;
  final DanmakuRasterCache rasterCache;
  final DanmakuLaneTracker laneTracker;
  final double devicePixelRatio;
  final DesktopDanmakuMask? Function() maskProvider;
  final BoxFit fit;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || comments.isEmpty) return;
    final mask = maskProvider();
    final useMask = settings.avoidCenterArea && mask != null;
    if (useMask) canvas.saveLayer(Offset.zero & size, Paint());
    final preciseNowMs = positionProvider().inMicroseconds / 1000;
    final nowMs = preciseNowMs.floor();
    final scrollLifetimeMs = (9000 / settings.speed).round();
    final fixedLifetimeMs = (4200 / settings.speed).round();
    final maximumLifetimeMs = math.max(scrollLifetimeMs, fixedLifetimeMs);
    final fontSize = (22 * settings.fontScale).clamp(13.0, 36.0).toDouble();
    final laneHeight = fontSize * 1.2 + 2.2 * settings.fontThickness + 6;
    var areaHeight = size.height * settings.displayAreaRatio;
    if (settings.avoidSubtitleArea) {
      areaHeight = math.min(areaHeight, size.height * 0.76);
    }
    if (settings.avoidCenterArea && !Platform.isWindows) {
      areaHeight = math.min(areaHeight, size.height * 0.46);
    }
    final rawLaneCount = math.max(1, (areaHeight / laneHeight).floor());
    final laneCount = math.max(
      1,
      (rawLaneCount * settings.density.clamp(0.2, 1.0)).round(),
    );
    laneTracker.beginFrame(
      comments: comments,
      settings: settings,
      laneCount: laneCount,
      canvasWidth: size.width,
      oldestTimeMs: nowMs - maximumLifetimeMs,
    );
    // 稀疏档位仍覆盖所选区域，底部弹幕保持在区域底端。
    final rowStride = laneCount > 1
        ? math.max(laneHeight, (areaHeight - laneHeight) / (laneCount - 1))
        : 0.0;
    final duplicateTexts = <String>{};

    // 断行上限量化到 32px，窗口拖拽时缓存键不至于逐像素失效。
    final maxWidthPx = ((size.width * 0.72) / 32).ceil() * 32;
    final alpha = (settings.opacity.clamp(0.1, 1.0) * 255).round();
    final strokeWidth = 2.2 * settings.fontThickness;
    final bold = settings.fontThickness >= 1.2;
    // Windows 上不指定字体会让每次排版都扫系统字体回退链，钉死中文字体。
    final fontFamily = defaultTargetPlatform == TargetPlatform.windows
        ? 'Microsoft YaHei'
        : null;

    var index = _lowerBound(nowMs - maximumLifetimeMs);
    while (index < comments.length) {
      final comment = comments[index++];
      if (comment.timeMs > nowMs) break;
      if (!_typeEnabled(comment.type) || laneTracker.isRejected(comment)) {
        continue;
      }
      final ageMs = nowMs - comment.timeMs;
      final lifetimeMs = comment.type == DanmakuCommentType.scroll
          ? scrollLifetimeMs
          : fixedLifetimeMs;
      if (ageMs < 0 || ageMs >= lifetimeMs) continue;
      final normalizedText = comment.text.trim().toLowerCase();
      if (settings.hideDuplicate && !duplicateTexts.add(normalizedText)) {
        // 记住淘汰结果，否则前一条离屏后，重复项会从半途冒出。
        laneTracker.reject(comment);
        continue;
      }
      final fillColor = (settings.colorEnabled ? comment.color : Colors.white)
          .withAlpha(alpha)
          .toARGB32();
      final key = DanmakuRasterKey(
        text: comment.text,
        fontSize: fontSize,
        maxWidthPx: maxWidthPx,
        fillColor: fillColor,
        strokeWidth: strokeWidth,
        bold: bold,
        fontFamily: fontFamily,
        devicePixelRatio: (devicePixelRatio * 1000).round(),
      );
      final entry =
          rasterCache.lookup(key) ??
          () {
            final built = DanmakuRasterCache.build(
              text: comment.text,
              fontSize: fontSize,
              maxWidthPx: maxWidthPx,
              fillColor: fillColor,
              strokeWidth: strokeWidth,
              bold: bold,
              fontFamily: fontFamily,
              devicePixelRatio: devicePixelRatio,
            );
            rasterCache.put(key, built);
            return built;
          }();
      // 车道出生时分配一次，终生不变；-1 为出生即淘汰，不再重试。
      final lane = comment.type == DanmakuCommentType.scroll
          ? laneTracker.laneForScroll(
              comment: comment,
              nowMs: nowMs,
              width: entry.width,
              canvasWidth: size.width,
              lifetimeMs: scrollLifetimeMs,
            )
          : laneTracker.laneForFixed(
              comment: comment,
              nowMs: nowMs,
              lifetimeMs: fixedLifetimeMs,
            );
      if (lane < 0) continue;
      final progress = (preciseNowMs - comment.timeMs) / lifetimeMs;
      final Offset offset;
      if (comment.type == DanmakuCommentType.scroll) {
        final x = size.width - progress * (size.width + entry.width);
        offset = Offset(x, lane * rowStride + strokeWidth / 2 + 2);
      } else {
        final y = comment.type == DanmakuCommentType.top
            ? lane * rowStride
            : (laneCount - 1 - lane) * rowStride;
        offset = Offset(
          (size.width - entry.width) / 2,
          math.max(0, y) + strokeWidth / 2 + 2,
        );
      }
      final dst = Rect.fromLTWH(
        offset.dx - entry.padding,
        offset.dy - entry.padding,
        entry.width + entry.padding * 2,
        entry.height + entry.padding * 2,
      );
      canvas.drawImageRect(
        entry.image,
        Rect.fromLTWH(
          0,
          0,
          entry.image.width.toDouble(),
          entry.image.height.toDouble(),
        ),
        dst,
        _imagePaint,
      );
    }
    if (useMask) {
      final sourceSize = Size(
        mask.frameWidth.toDouble(),
        mask.frameHeight.toDouble(),
      );
      final maskRects = resolveDesktopDanmakuMaskRects(
        frameSize: sourceSize,
        maskSize: Size(
          mask.image.width.toDouble(),
          mask.image.height.toDouble(),
        ),
        canvasSize: size,
        fit: fit,
      );
      canvas.drawImageRect(
        mask.image,
        maskRects.source,
        maskRects.destination,
        Paint()
          ..blendMode = BlendMode.dstOut
          ..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
    }
  }

  bool _typeEnabled(DanmakuCommentType type) => switch (type) {
    DanmakuCommentType.scroll => settings.scrollEnabled,
    DanmakuCommentType.top => settings.topEnabled,
    DanmakuCommentType.bottom => settings.bottomEnabled,
  };

  int _lowerBound(int targetMs) {
    var low = 0;
    var high = comments.length;
    while (low < high) {
      final mid = low + ((high - low) >> 1);
      if (comments[mid].timeMs < targetMs) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  @override
  bool shouldRepaint(covariant _DesktopDanmakuPainter oldDelegate) {
    return oldDelegate.comments != comments ||
        oldDelegate.settings != settings ||
        oldDelegate.fit != fit;
  }
}
