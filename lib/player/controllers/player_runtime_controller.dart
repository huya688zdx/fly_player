import 'mpv_player_controller.dart';

class PlayerRuntimeStatusReaction {
  final bool showAutoFilterFallbackTip;
  final bool showSubtitleStatusTopTip;
  final bool clearSubtitleStatusTipSuppression;

  const PlayerRuntimeStatusReaction({
    this.showAutoFilterFallbackTip = false,
    this.showSubtitleStatusTopTip = false,
    this.clearSubtitleStatusTipSuppression = false,
  });
}

class PlayerRuntimeController {
  String lastPlayerStatusText = '';

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

  bool wantsPerformanceOverlayPolling({
    required bool performanceOverlayEnabled,
    required bool fpsOverlayEnabled,
    required bool playerReady,
  }) {
    return (performanceOverlayEnabled || fpsOverlayEnabled) && playerReady;
  }

  bool samePerformanceOverlayStats(
    MpvPerformanceOverlayStats left,
    MpvPerformanceOverlayStats right,
  ) {
    return left.cpuUsagePercent == right.cpuUsagePercent &&
        left.gpuUsagePercent == right.gpuUsagePercent &&
        left.estimatedVfFps == right.estimatedVfFps &&
        left.containerFps == right.containerFps &&
        left.displayFps == right.displayFps;
  }
}
