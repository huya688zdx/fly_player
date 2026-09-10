import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../playback/playback_source.dart';
import '../../playback/weak_network_quality_recommender.dart';
import 'desktop_mpv_runtime.dart';

/// 只采样当前远程媒体；弱网提示不改变内核缓存策略，也不自动切换画质。
class DesktopWeakNetworkMonitor extends ChangeNotifier {
  DesktopWeakNetworkMonitor({
    required this.readProperty,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Future<String> Function(String) readProperty;
  final DateTime Function() _now;
  final List<DateTime> _rebuffers = [];
  MpvMediaSource? _source;
  Timer? _timer;
  int _generation = 0;
  bool _sampling = false;
  bool _disposed = false;
  bool _loading = true;
  bool _paused = false;
  bool _buffering = false;
  bool _completed = false;
  bool _hasProgress = false;
  bool _weak = false;
  bool _dismissed = false;
  Duration? _position;
  DateTime? _seekUntil;
  DateTime? _lastRebuffer;
  DateTime? _lastSpeedSample;
  double _speed = 0;
  Duration? estimatedResumeWait;

  bool get remote {
    final source = _source;
    if (source == null ||
        source.isDownloadedFile ||
        source.externalLocalSource) {
      return false;
    }
    final scheme = Uri.tryParse(source.url)?.scheme;
    return scheme == 'http' || scheme == 'https';
  }

  int get bytesPerSecond =>
      _lastSpeedSample == null ||
          _now().difference(_lastSpeedSample!) > const Duration(seconds: 4)
      ? 0
      : _speed.round();

  DesktopQualityChoice? get recommendation {
    final source = _source;
    if (!remote ||
        source == null ||
        !_weak ||
        _dismissed ||
        _loading ||
        _paused ||
        _completed ||
        bytesPerSecond <= 0) {
      return null;
    }
    final choices = DesktopMpvRuntime.qualityMenu(
      source,
    ).customGroups.values.expand((group) => group).toList();
    final current = choices
        .where((choice) => DesktopMpvRuntime.isCurrentQuality(source, choice))
        .firstOrNull;
    if (current == null) return null;
    final result = recommendWeakNetworkQuality(
      qualities: choices.map((choice) => choice.quality).toList(),
      currentQuality: current.quality,
      networkSpeedBytesPerSecond: bytesPerSecond,
    );
    if (result == null ||
        !isMeaningfulWeakNetworkDowngrade(
          currentQuality: current.quality,
          recommendedQuality: result.quality,
        )) {
      return null;
    }
    return choices
        .where((choice) => choice.quality == result.quality)
        .firstOrNull;
  }

  void setSource(MpvMediaSource source) {
    _generation++;
    _timer?.cancel();
    _source = source;
    _rebuffers.clear();
    _lastRebuffer = null;
    _lastSpeedSample = null;
    _seekUntil = null;
    _position = null;
    _loading = true;
    _paused = _buffering = _completed = _hasProgress = _weak = _dismissed =
        false;
    _speed = 0;
    estimatedResumeWait = null;
    if (remote) {
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(_sample()),
      );
    }
    notifyListeners();
  }

  void updatePlayback({
    required bool loading,
    required bool paused,
    required bool buffering,
    required bool completed,
  }) {
    final changed =
        _loading != loading ||
        _paused != paused ||
        _buffering != buffering ||
        _completed != completed;
    if (remote &&
        buffering &&
        !_buffering &&
        _hasProgress &&
        !loading &&
        !paused &&
        !completed) {
      final now = _now();
      _rebuffers.removeWhere(
        (time) => now.difference(time) >= const Duration(seconds: 45),
      );
      _rebuffers.add(now);
      _lastRebuffer = now;
      if (_rebuffers.length >= 2) _weak = true;
    }
    _loading = loading;
    _paused = paused;
    _buffering = buffering;
    _completed = completed;
    if (loading || paused || buffering || completed) _hasProgress = false;
    if (changed) notifyListeners();
  }

  void onPosition(Duration position) {
    if (_position != null && position < _position!) markSeek();
    if (!_loading &&
        !_paused &&
        !_buffering &&
        !_completed &&
        (_seekUntil == null || !_now().isBefore(_seekUntil!)) &&
        _position != null &&
        position > _position!) {
      _hasProgress = true;
    }
    _position = position;
  }

  void markSeek() {
    _hasProgress = false;
    _position = null;
    // seek 命令完成早于画面恢复；短暂屏蔽旧位置回调，之后仍须实际播放前进。
    _seekUntil = _now().add(const Duration(seconds: 3));
  }

  void dismiss() {
    _dismissed = true;
    notifyListeners();
  }

  Future<void> _sample() async {
    if (_disposed ||
        _sampling ||
        !remote ||
        _loading ||
        _paused ||
        _completed) {
      return;
    }
    _sampling = true;
    final generation = _generation;
    try {
      final values = await Future.wait([
        readProperty('cache-speed'),
        readProperty('demuxer-cache-duration'),
        readProperty('cache-pause-wait'),
      ]).timeout(const Duration(seconds: 2));
      if (_disposed || generation != _generation) return;
      final raw = double.tryParse(values[0]) ?? 0;
      final speed = raw.isFinite && raw > 0 && raw <= 256 * 1024 * 1024
          ? raw
          : 0.0;
      final previousSpeed = bytesPerSecond;
      _speed = speed <= 0
          ? 0
          : previousSpeed <= 0
          ? speed
          : _speed * 0.75 + speed * 0.25;
      _lastSpeedSample = _now();
      final cached = double.tryParse(values[1]) ?? 0;
      final target = double.tryParse(values[2]) ?? 0;
      final bitrate = _source!.bitrate;
      estimatedResumeWait =
          _buffering &&
              _speed > 0 &&
              bitrate > 0 &&
              cached.isFinite &&
              target.isFinite &&
              target > cached &&
              cached >= 0
          ? Duration(
              milliseconds: ((target - cached) * bitrate / (_speed * 8) * 1000)
                  .round(),
            )
          : null;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      // 不保留失效读数，断流或不支持统计时显示未知网速。
      _speed = 0;
      estimatedResumeWait = null;
    } finally {
      _sampling = false;
    }
    if (_disposed || generation != _generation) return;
    if (_lastRebuffer != null &&
        _now().difference(_lastRebuffer!) >= const Duration(seconds: 60)) {
      _weak = false;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    super.dispose();
  }
}
