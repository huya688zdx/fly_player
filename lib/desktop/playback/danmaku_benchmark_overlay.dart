import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

const int _benchmarkLaneCount = 14;
const int _slowFrameMicros = 16670;
const Duration _benchmarkCrossingDuration = Duration(seconds: 12);
const Duration _warmupDuration = Duration(seconds: 10);
const Duration _sampleDuration = Duration(seconds: 60);
const Duration _statsRefreshInterval = Duration(seconds: 1);

/// 弹幕压测覆盖层：记录 Flutter 合成弹幕时的帧耗时。
///
/// 每条文本只布局一次，并录制为 [ui.Picture] 后逐帧重放。Picture 保存的是
/// Canvas 绘制指令，不是已经光栅化的位图缓存，因此测到的 raster 耗时仍包含
/// 指令重放与光栅化成本。
///
/// 动画直接通知 [CustomPainter] 重绘，不会逐帧触发组件重建。调用方可按页面
/// 层级需要在外部包裹 [IgnorePointer] 和 [RepaintBoundary]。
class DanmakuBenchmarkOverlay extends StatefulWidget {
  const DanmakuBenchmarkOverlay({super.key, required this.commentCount})
    : assert(commentCount >= 0);

  /// 同屏循环滚动的弹幕条数。
  final int commentCount;

  @override
  State<DanmakuBenchmarkOverlay> createState() =>
      _DanmakuBenchmarkOverlayState();
}

class _DanmakuBenchmarkOverlayState extends State<DanmakuBenchmarkOverlay>
    with SingleTickerProviderStateMixin {
  final Stopwatch _benchmarkClock = Stopwatch();
  final List<int> _buildSamples = <int>[];
  final List<int> _rasterSamples = <int>[];
  final List<int> _totalSamples = <int>[];
  final ValueNotifier<_BenchmarkSnapshot> _snapshot =
      ValueNotifier<_BenchmarkSnapshot>(
        const _BenchmarkSnapshot.empty(status: '预热中 10 秒'),
      );

  late final AnimationController _animation;
  late List<_CachedDanmaku> _cachedDanmaku;
  Timer? _statsTimer;
  bool _timingsCallbackAttached = false;
  bool _collectionClosed = false;
  int _lastStatsUpdateMicros = -_statsRefreshInterval.inMicroseconds;

  int get _measurementDurationMicros =>
      _warmupDuration.inMicroseconds + _sampleDuration.inMicroseconds;

  @override
  void initState() {
    super.initState();
    _cachedDanmaku = _recordDanmaku(widget.commentCount);
    _animation = AnimationController(
      vsync: this,
      duration: _benchmarkCrossingDuration,
    )..repeat();
    _restartMeasurement();
  }

  @override
  void didUpdateWidget(covariant DanmakuBenchmarkOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.commentCount == widget.commentCount) {
      return;
    }

    final oldCache = _cachedDanmaku;
    _cachedDanmaku = _recordDanmaku(widget.commentCount);
    _disposePictures(oldCache);
    // 数量改变后旧样本不再代表当前负载，重新执行预热和固定采样窗口。
    _restartMeasurement();
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _detachTimingsCallback();
    _benchmarkClock.stop();
    _animation.dispose();
    _disposePictures(_cachedDanmaku);
    _snapshot.dispose();
    super.dispose();
  }

  void _restartMeasurement() {
    _statsTimer?.cancel();
    _buildSamples.clear();
    _rasterSamples.clear();
    _totalSamples.clear();
    _collectionClosed = false;
    _lastStatsUpdateMicros = -_statsRefreshInterval.inMicroseconds;
    _benchmarkClock
      ..reset()
      ..start();
    _snapshot.value = const _BenchmarkSnapshot.empty(status: '预热中 10 秒');
    _attachTimingsCallback();
    _statsTimer = Timer.periodic(_statsRefreshInterval, _onStatsTimer);
  }

  void _attachTimingsCallback() {
    if (_timingsCallbackAttached) {
      return;
    }
    WidgetsBinding.instance.addTimingsCallback(_onTimings);
    _timingsCallbackAttached = true;
  }

  void _detachTimingsCallback() {
    if (!_timingsCallbackAttached) {
      return;
    }
    WidgetsBinding.instance.removeTimingsCallback(_onTimings);
    _timingsCallbackAttached = false;
  }

  void _onTimings(List<FrameTiming> timings) {
    final elapsedMicros = _benchmarkClock.elapsedMicroseconds;
    if (elapsedMicros < _warmupDuration.inMicroseconds ||
        elapsedMicros >= _measurementDurationMicros) {
      return;
    }

    for (final timing in timings) {
      _buildSamples.add(timing.buildDuration.inMicroseconds);
      _rasterSamples.add(timing.rasterDuration.inMicroseconds);
      _totalSamples.add(timing.totalSpan.inMicroseconds);
    }
  }

  void _onStatsTimer(Timer timer) {
    final elapsedMicros = _benchmarkClock.elapsedMicroseconds;
    if (!_collectionClosed && elapsedMicros >= _measurementDurationMicros) {
      _collectionClosed = true;
      _detachTimingsCallback();
    }

    // Timer.periodic 在事件循环拥堵后可能连续补发，显式限制文本更新频率。
    if (elapsedMicros - _lastStatsUpdateMicros <
        _statsRefreshInterval.inMicroseconds) {
      return;
    }
    _lastStatsUpdateMicros = elapsedMicros;
    final snapshot = _createSnapshot(elapsedMicros);
    _snapshot.value = snapshot;

    if (_collectionClosed) {
      debugPrint('DANMAKU_BENCHMARK_RESULT\n${_formatSnapshot(snapshot)}');
      timer.cancel();
    }
  }

  _BenchmarkSnapshot _createSnapshot(int elapsedMicros) {
    late final String status;
    if (elapsedMicros < _warmupDuration.inMicroseconds) {
      final remainingMicros = _warmupDuration.inMicroseconds - elapsedMicros;
      final remainingSeconds =
          (remainingMicros + Duration.microsecondsPerSecond - 1) ~/
          Duration.microsecondsPerSecond;
      status = '预热中 $remainingSeconds 秒';
    } else if (!_collectionClosed) {
      var sampledSeconds =
          (elapsedMicros - _warmupDuration.inMicroseconds) ~/
          Duration.microsecondsPerSecond;
      if (sampledSeconds < 0) {
        sampledSeconds = 0;
      } else if (sampledSeconds > _sampleDuration.inSeconds) {
        sampledSeconds = _sampleDuration.inSeconds;
      }
      status = '采样中 $sampledSeconds/${_sampleDuration.inSeconds} 秒';
    } else {
      status = '采样完成（固定 ${_sampleDuration.inSeconds} 秒）';
    }

    return _BenchmarkSnapshot(
      status: status,
      sampleCount: _totalSamples.length,
      build: _MetricStats.fromSamples(_buildSamples),
      raster: _MetricStats.fromSamples(_rasterSamples),
      total: _MetricStats.fromSamples(_totalSamples),
    );
  }

  List<_CachedDanmaku> _recordDanmaku(int count) {
    final cached = <_CachedDanmaku>[];
    for (var index = 0; index < count; index++) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: '$index · 弹幕压测 —— 绘制指令基准 Benchmark 0123',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            shadows: <Shadow>[Shadow(blurRadius: 2, offset: Offset(1, 1))],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final size = Size(textPainter.width, textPainter.height);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder, Offset.zero & size);
      // 这里只录制 TextPainter.paint 发出的绘制指令，不会生成位图光栅缓存。
      textPainter.paint(canvas, Offset.zero);
      final picture = recorder.endRecording();
      textPainter.dispose();

      cached.add(
        _CachedDanmaku(
          picture: picture,
          width: size.width,
          lane: index % _benchmarkLaneCount,
          phase: (index * 37 % 100) / 100,
        ),
      );
    }
    return cached;
  }

  void _disposePictures(List<_CachedDanmaku> cached) {
    for (final item in cached) {
      item.picture.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: CustomPaint(
            painter: _DanmakuPainter(
              cached: _cachedDanmaku,
              animation: _animation,
            ),
          ),
        ),
        Positioned(
          left: 12,
          top: 12,
          child: ValueListenableBuilder<_BenchmarkSnapshot>(
            valueListenable: _snapshot,
            builder: (context, snapshot, child) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                color: Colors.black54,
                child: Text(
                  _formatSnapshot(snapshot),
                  softWrap: false,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatSnapshot(_BenchmarkSnapshot snapshot) {
    return '${snapshot.status} · ${widget.commentCount} 条 · '
        '样本 ${snapshot.sampleCount}\n'
        '耗时(μs)     p50     p95     p99  >16.67ms\n'
        '${snapshot.build.format('build')}\n'
        '${snapshot.raster.format('raster')}\n'
        '${snapshot.total.format('total')}';
  }
}

class _CachedDanmaku {
  const _CachedDanmaku({
    required this.picture,
    required this.width,
    required this.lane,
    required this.phase,
  });

  final ui.Picture picture;
  final double width;
  final int lane;

  /// 0..1 起始相位，避免同车道弹幕在同一帧出发。
  final double phase;
}

class _DanmakuPainter extends CustomPainter {
  _DanmakuPainter({required this.cached, required this.animation})
    : super(repaint: animation);

  final List<_CachedDanmaku> cached;
  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final laneHeight = size.height / _benchmarkLaneCount;
    for (final item in cached) {
      final progress = (animation.value + item.phase) % 1.0;
      final x = size.width - progress * (size.width + item.width);
      final y = item.lane * laneHeight;
      canvas
        ..save()
        ..translate(x, y)
        ..drawPicture(item.picture)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_DanmakuPainter oldDelegate) =>
      !identical(oldDelegate.cached, cached) ||
      !identical(oldDelegate.animation, animation);
}

class _BenchmarkSnapshot {
  const _BenchmarkSnapshot({
    required this.status,
    required this.sampleCount,
    required this.build,
    required this.raster,
    required this.total,
  });

  const _BenchmarkSnapshot.empty({required this.status})
    : sampleCount = 0,
      build = const _MetricStats.empty(),
      raster = const _MetricStats.empty(),
      total = const _MetricStats.empty();

  final String status;
  final int sampleCount;
  final _MetricStats build;
  final _MetricStats raster;
  final _MetricStats total;
}

class _MetricStats {
  const _MetricStats({
    required this.p50,
    required this.p95,
    required this.p99,
    required this.overBudgetRatio,
  });

  const _MetricStats.empty()
    : p50 = null,
      p95 = null,
      p99 = null,
      overBudgetRatio = null;

  factory _MetricStats.fromSamples(List<int> samples) {
    if (samples.isEmpty) {
      return const _MetricStats.empty();
    }

    final sorted = List<int>.of(samples)..sort();
    var overBudgetCount = 0;
    for (final value in sorted) {
      if (value > _slowFrameMicros) {
        overBudgetCount++;
      }
    }

    return _MetricStats(
      p50: _percentile(sorted, 0.50),
      p95: _percentile(sorted, 0.95),
      p99: _percentile(sorted, 0.99),
      overBudgetRatio: overBudgetCount * 100 / sorted.length,
    );
  }

  final int? p50;
  final int? p95;
  final int? p99;
  final double? overBudgetRatio;

  static int _percentile(List<int> sorted, double percentile) {
    final index = (sorted.length * percentile).ceil() - 1;
    return sorted[index];
  }

  String format(String label) {
    final ratio = overBudgetRatio == null
        ? '-'
        : '${overBudgetRatio!.toStringAsFixed(1)}%';
    return '${label.padRight(10)}'
        '${_formatValue(p50)}'
        '${_formatValue(p95)}'
        '${_formatValue(p99)}'
        '${ratio.padLeft(10)}';
  }

  String _formatValue(int? value) => (value?.toString() ?? '-').padLeft(8);
}
