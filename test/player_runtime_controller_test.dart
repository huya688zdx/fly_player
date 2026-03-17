import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/player/controllers/mpv_player_controller.dart';
import 'package:fly_player/player/controllers/player_runtime_controller.dart';

void main() {
  group('PlayerRuntimeController', () {
    test('detects auto-filter fallback and subtitle status reactions', () {
      final controller = PlayerRuntimeController();

      final autoFilterReaction = controller.consumeStatusText(
        currentStatusText: 'Auto performance fallback: filters disabled',
        now: DateTime(2026, 1, 2),
        subtitleStatusTipSuppressedUntil: null,
        autoFilterFallbackStatusText:
            'Auto performance fallback: filters disabled',
      );
      expect(autoFilterReaction.showAutoFilterFallbackTip, isTrue);
      expect(autoFilterReaction.showSubtitleStatusTopTip, isFalse);

      final suppressedSubtitleReaction = controller.consumeStatusText(
        currentStatusText: 'subtitle track changed',
        now: DateTime(2026, 1, 2, 12, 0, 0),
        subtitleStatusTipSuppressedUntil: DateTime(2026, 1, 2, 12, 0, 5),
        autoFilterFallbackStatusText:
            'Auto performance fallback: filters disabled',
      );
      expect(
        suppressedSubtitleReaction.clearSubtitleStatusTipSuppression,
        isTrue,
      );
      expect(suppressedSubtitleReaction.showSubtitleStatusTopTip, isFalse);

      final subtitleReaction = controller.consumeStatusText(
        currentStatusText: 'external subtitle loaded',
        now: DateTime(2026, 1, 2, 12, 1, 0),
        subtitleStatusTipSuppressedUntil: DateTime(2026, 1, 2, 12, 0, 5),
        autoFilterFallbackStatusText:
            'Auto performance fallback: filters disabled',
      );
      expect(subtitleReaction.showSubtitleStatusTopTip, isTrue);
      expect(subtitleReaction.clearSubtitleStatusTipSuppression, isFalse);
    });

    test('computes overlay polling and stat equality', () {
      final controller = PlayerRuntimeController();
      const left = MpvPerformanceOverlayStats(
        cpuUsagePercent: 12,
        gpuUsagePercent: 34,
        estimatedVfFps: 24,
        containerFps: 24,
        displayFps: 60,
      );
      const right = MpvPerformanceOverlayStats(
        cpuUsagePercent: 12,
        gpuUsagePercent: 34,
        estimatedVfFps: 24,
        containerFps: 24,
        displayFps: 60,
      );
      const different = MpvPerformanceOverlayStats(
        cpuUsagePercent: 12,
        gpuUsagePercent: 35,
        estimatedVfFps: 24,
        containerFps: 24,
        displayFps: 60,
      );

      expect(
        controller.wantsPerformanceOverlayPolling(
          performanceOverlayEnabled: true,
          fpsOverlayEnabled: false,
          playerReady: true,
        ),
        isTrue,
      );
      expect(
        controller.wantsPerformanceOverlayPolling(
          performanceOverlayEnabled: false,
          fpsOverlayEnabled: true,
          playerReady: false,
        ),
        isFalse,
      );
      expect(controller.samePerformanceOverlayStats(left, right), isTrue);
      expect(controller.samePerformanceOverlayStats(left, different), isFalse);
    });
  });
}
