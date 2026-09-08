/// 弹幕只在刷新帧推进；异步进度采样不直接改变在屏位置。
class DesktopDanmakuClock {
  DesktopDanmakuClock({
    required Duration position,
    required this.advancing,
    required this.rate,
  }) : _positionUs = position.inMicroseconds.toDouble();

  bool advancing;
  double rate;
  double _positionUs;
  double _correctionUs = 0;
  int _elapsedUs = 0;
  int _nextFrameUs = 0;

  Duration get position => Duration(microseconds: _positionUs.round());

  /// 大幅跳转立即重新定位，普通采样仅更新渐进校准目标。
  bool synchronize(Duration sample) {
    final error = sample.inMicroseconds - _positionUs;
    final jumped = error.abs() > 700000;
    if (jumped || !advancing) {
      _positionUs = sample.inMicroseconds.toDouble();
      _correctionUs = 0;
    } else {
      // 容忍异步采样的短时延迟，不把视频帧节奏叠加到弹幕上。
      _correctionUs = error.abs() > 50000 ? error : 0;
    }
    return jumped;
  }

  bool tick(Duration elapsed, {required int frameRate}) {
    final nowUs = elapsed.inMicroseconds;
    final deltaUs = (nowUs - _elapsedUs).clamp(0, 1000000000);
    _elapsedUs = nowUs;
    if (!advancing) {
      _nextFrameUs = nowUs;
      return false;
    }
    final advance = deltaUs * rate;
    // 只改变不超过 2% 的移动速度，禁止进度消息造成瞬时回跳。
    final correction = _correctionUs.clamp(-advance * 0.02, advance * 0.02);
    _positionUs += advance + correction;
    _correctionUs -= correction;

    final intervalUs = 1000000 ~/ frameRate;
    if (nowUs + 1000 < _nextFrameUs) return false;
    // 保留帧率相位，迟到时跳过过期的期限，不从当前帧重新起算。
    final steps = ((nowUs + 1000 - _nextFrameUs) ~/ intervalUs) + 1;
    _nextFrameUs += steps * intervalUs;
    return true;
  }
}
