import '../../danmaku/models/danmaku_comment.dart';
import '../../danmaku/models/danmaku_settings.dart';

class _LaneLease {
  const _LaneLease(this.comment, this.width, this.lifetimeMs);

  final DanmakuComment comment;
  final double width;
  final int lifetimeMs;
  int get endMs => comment.timeMs + lifetimeMs;
}

/// 按实际绘制行统一占位，出生时决定车道，满载时丢弃而不延迟冒出。
class DanmakuLaneTracker {
  final Map<DanmakuComment, int> _lanes = {};
  List<List<_LaneLease>> _rows = [];
  Object? _commentsKey;
  DanmakuSettings? _settingsKey;
  int _laneCount = 0;
  double _canvasWidth = 0;

  void beginFrame({
    required List<DanmakuComment> comments,
    required DanmakuSettings settings,
    required int laneCount,
    double canvasWidth = 0,
    int? oldestTimeMs,
  }) {
    if (!identical(comments, _commentsKey) ||
        settings != _settingsKey ||
        laneCount != _laneCount ||
        canvasWidth != _canvasWidth) {
      _commentsKey = comments;
      _settingsKey = settings;
      _laneCount = laneCount;
      _canvasWidth = canvasWidth;
      reset();
    }
    if (oldestTimeMs != null) {
      _lanes.removeWhere((comment, _) => comment.timeMs < oldestTimeMs);
      for (final row in _rows) {
        row.removeWhere((lease) => lease.endMs < oldestTimeMs);
      }
    }
  }

  void reset() {
    _lanes.clear();
    _rows = List.generate(_laneCount, (_) => <_LaneLease>[]);
  }

  bool isRejected(DanmakuComment comment) => _lanes[comment] == -1;

  /// 被过滤的弹幕在本次生命周期内不再尝试入场。
  void reject(DanmakuComment comment) => _lanes[comment] = -1;

  /// 既检查入场间距，也检查前车离屏时的间距，阻止长弹幕追尾。
  int laneForScroll({
    required DanmakuComment comment,
    required int nowMs,
    required double width,
    required double canvasWidth,
    required int lifetimeMs,
    double gapPx = 20,
  }) {
    return _resolve(comment, width, lifetimeMs, (lease) {
      final elapsed = comment.timeMs - lease.comment.timeMs;
      if (elapsed >= lease.lifetimeMs) return true;
      if (lease.comment.type != DanmakuCommentType.scroll) return false;
      final previousSpeed = (canvasWidth + lease.width) / lease.lifetimeMs;
      final speed = (canvasWidth + width) / lifetimeMs;
      final gap = previousSpeed * elapsed - lease.width;
      final remaining = lease.lifetimeMs - elapsed;
      return gap >= gapPx && gap + (previousSpeed - speed) * remaining >= gapPx;
    });
  }

  /// 固定弹幕等待整行清空，避免与仍在屏内的滚动弹幕相交。
  int laneForFixed({
    required DanmakuComment comment,
    required int nowMs,
    required int lifetimeMs,
  }) {
    return _resolve(
      comment,
      0,
      lifetimeMs,
      (lease) => lease.endMs <= comment.timeMs,
    );
  }

  int _resolve(
    DanmakuComment comment,
    double width,
    int lifetimeMs,
    bool Function(_LaneLease) isFree,
  ) {
    final existing = _lanes[comment];
    if (existing != null) return existing;
    for (var lane = 0; lane < _laneCount; lane++) {
      final rowIndex = comment.type == DanmakuCommentType.bottom
          ? _laneCount - 1 - lane
          : lane;
      final row = _rows[rowIndex];
      row.removeWhere((lease) => lease.endMs <= comment.timeMs);
      if (!row.every(isFree)) continue;
      row.add(_LaneLease(comment, width, lifetimeMs));
      _lanes[comment] = lane;
      return lane;
    }
    _lanes[comment] = -1;
    return -1;
  }
}
