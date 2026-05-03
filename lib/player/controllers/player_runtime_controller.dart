import 'mpv_player_controller.dart';

/// 描述消费底层播放器状态文本后的界面反应。
class PlayerRuntimeStatusReaction {
  final bool showAutoFilterFallbackTip;
  final bool showSubtitleStatusTopTip;
  final bool clearSubtitleStatusTipSuppression;

  /// 根据需要触发的界面动作构造反应对象。
  const PlayerRuntimeStatusReaction({
    this.showAutoFilterFallbackTip = false,
    this.showSubtitleStatusTopTip = false,
    this.clearSubtitleStatusTipSuppression = false,
  });
}

/// 负责解释底层运行时状态并生成界面侧动作。
class PlayerRuntimeController {
  String lastPlayerStatusText = '';

  /// 消费一条播放器状态文本并返回界面应执行的动作。
  PlayerRuntimeStatusReaction consumeStatusText({
    required String currentStatusText,
    required DateTime now,
    required DateTime? subtitleStatusTipSuppressedUntil,
    required String autoFilterFallbackStatusText,
  }) {
    final previousStatusText = lastPlayerStatusText;
    lastPlayerStatusText = currentStatusText;
    final normalizedStatusText = currentStatusText.trim().toLowerCase();
    final statusChanged = previousStatusText != currentStatusText;
    final showAutoFilterFallbackTip =
        statusChanged && currentStatusText == autoFilterFallbackStatusText;
    if (!statusChanged) {
      return PlayerRuntimeStatusReaction(
        showAutoFilterFallbackTip: showAutoFilterFallbackTip,
      );
    }
    final subtitleStatusChanged =
        normalizedStatusText == 'subtitle track changed' ||
        normalizedStatusText == 'external subtitle loaded';
    if (!subtitleStatusChanged) {
      return PlayerRuntimeStatusReaction(
        showAutoFilterFallbackTip: showAutoFilterFallbackTip,
      );
    }
    final statusTipSuppressed =
        subtitleStatusTipSuppressedUntil != null &&
        now.isBefore(subtitleStatusTipSuppressedUntil);
    return PlayerRuntimeStatusReaction(
      showAutoFilterFallbackTip: showAutoFilterFallbackTip,
      showSubtitleStatusTopTip: !statusTipSuppressed,
      clearSubtitleStatusTipSuppression: statusTipSuppressed,
    );
  }

  /// 判断当前是否需要轮询性能叠层数据。
  bool wantsPerformanceOverlayPolling({
    required bool performanceOverlayEnabled,
    required bool playerReady,
  }) {
    return performanceOverlayEnabled && playerReady;
  }

  /// 判断两份性能叠层统计是否等价。
  bool samePerformanceOverlayStats(
    MpvPerformanceOverlayStats left,
    MpvPerformanceOverlayStats right,
  ) {
    return left.cpuUsagePercent == right.cpuUsagePercent &&
        left.appMemoryUsedBytes == right.appMemoryUsedBytes &&
        left.systemMemoryTotalBytes == right.systemMemoryTotalBytes;
  }
}
