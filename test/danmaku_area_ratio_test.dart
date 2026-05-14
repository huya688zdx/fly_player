import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/danmaku/models/danmaku_settings.dart';
import 'package:fly_player/danmaku/render/engine/danmaku_layout.dart';

void main() {
  group('resolveDanmakuCaptureAreaRatio', () {
    test('maps preset display areas to the next capture tier', () {
      expect(resolveDanmakuCaptureAreaRatio(0.10), 0.25);
      expect(resolveDanmakuCaptureAreaRatio(0.25), 0.50);
      expect(resolveDanmakuCaptureAreaRatio(0.50), 0.75);
      expect(resolveDanmakuCaptureAreaRatio(0.75), 1.0);
      expect(resolveDanmakuCaptureAreaRatio(1.0), 1.0);
    });

    test('rounds legacy values up to the next preset tier', () {
      expect(resolveDanmakuCaptureAreaRatio(0.33), 0.75);
      expect(resolveDanmakuCaptureAreaRatio(0.74), 1.0);
    });
  });

  group('resolveDanmakuMaskSourceCoverageRatio', () {
    test(
      'only uses the top portion of the capture mask that matches display area',
      () {
        expect(
          resolveDanmakuMaskSourceCoverageRatio(
            displayAreaRatio: 0.25,
            captureAreaRatio: 0.50,
          ),
          0.5,
        );
      },
    );

    test('keeps the full mask when display and capture areas match', () {
      expect(
        resolveDanmakuMaskSourceCoverageRatio(
          displayAreaRatio: 0.50,
          captureAreaRatio: 0.50,
        ),
        1.0,
      );
    });
  });

  group('resolveDanmakuViewportMotionDurationScale', () {
    test('slightly speeds up small devices', () {
      expect(resolveDanmakuViewportMotionDurationScale(320), 0.9);
      expect(resolveDanmakuViewportMotionDurationScale(360), 0.9);
    });

    test('keeps the reference short side unchanged', () {
      expect(resolveDanmakuViewportMotionDurationScale(420), 1.0);
    });

    test('slows down larger devices with a capped scale', () {
      expect(resolveDanmakuViewportMotionDurationScale(600), 1.4);
      expect(resolveDanmakuViewportMotionDurationScale(840), 1.4);
    });

    test('falls back to neutral scale for invalid inputs', () {
      expect(resolveDanmakuViewportMotionDurationScale(0), 1.0);
      expect(resolveDanmakuViewportMotionDurationScale(-1), 1.0);
    });
  });

  group('resolveDanmakuDensityCapacityScale', () {
    test('keeps full capacity unchanged', () {
      expect(resolveDanmakuDensityCapacityScale(1.0), 1.0);
    });

    test('uses eased scaling for smaller display areas', () {
      expect(resolveDanmakuDensityCapacityScale(0.25), 0.5);
      expect(
        resolveDanmakuDensityCapacityScale(0.5),
        closeTo(0.70710678, 0.000001),
      );
    });

    test('clamps invalid capacity to zero', () {
      expect(resolveDanmakuDensityCapacityScale(0), 0.0);
      expect(resolveDanmakuDensityCapacityScale(-1), 0.0);
    });
  });

  group('DanmakuTrackLayoutEngine', () {
    test(
      'keeps quarter-screen presets from losing a full row on small layouts',
      () {
        final quarterLayout = DanmakuTrackLayoutEngine.compute(
          viewportSize: const Size(800, 600),
          trackHeight: 48,
          areaRatio: 0.25,
          avoidSubtitleArea: false,
          avoidCenterArea: false,
          subtitleReservedAreaRatio: 0.16,
        );
        final fullLayout = DanmakuTrackLayoutEngine.compute(
          viewportSize: const Size(800, 600),
          trackHeight: 48,
          areaRatio: 1.0,
          avoidSubtitleArea: false,
          avoidCenterArea: false,
          subtitleReservedAreaRatio: 0.16,
        );

        expect(quarterLayout.topTrackYs.length, 3);
        expect(fullLayout.topTrackYs.length, 12);
      },
    );

    test('reduces available rows as configured font scale grows', () {
      final normalLayout = DanmakuTrackLayoutEngine.compute(
        viewportSize: const Size(1280, 720),
        trackHeight: 36,
        areaRatio: 0.5,
        avoidSubtitleArea: true,
        avoidCenterArea: false,
        subtitleReservedAreaRatio: 0.16,
      );
      final largeFontLayout = DanmakuTrackLayoutEngine.compute(
        viewportSize: const Size(1280, 720),
        trackHeight: 52,
        areaRatio: 0.5,
        avoidSubtitleArea: true,
        avoidCenterArea: false,
        subtitleReservedAreaRatio: 0.16,
      );

      expect(
        largeFontLayout.topTrackYs.length,
        lessThan(normalLayout.topTrackYs.length),
      );
      expect(
        largeFontLayout.topTrackYs.toSet().length,
        largeFontLayout.topTrackYs.length,
      );
    });
  });

  group('DanmakuScrollTrackScheduler', () {
    test(
      'blocks a new scroll item while the previous tail is still entering',
      () {
        final canAdd = DanmakuScrollTrackScheduler.canAddToTrack(
          visibleItems: const <DanmakuScrollTrackItemSnapshot>[
            DanmakuScrollTrackItemSnapshot(
              width: 200,
              startMs: 0,
              durationMs: 5000,
            ),
          ],
          viewportWidth: 1000,
          timelineMs: 0,
          newItemWidth: 400,
          newItemDurationMs: 5000,
          minGap: 20,
        );

        expect(canAdd, isFalse);
      },
    );

    test('blocks a faster new item that would catch the previous item', () {
      final canAdd = DanmakuScrollTrackScheduler.canAddToTrack(
        visibleItems: const <DanmakuScrollTrackItemSnapshot>[
          DanmakuScrollTrackItemSnapshot(
            width: 200,
            startMs: 0,
            durationMs: 5000,
          ),
        ],
        viewportWidth: 1000,
        timelineMs: 1000,
        newItemWidth: 400,
        newItemDurationMs: 5000,
        minGap: 20,
      );

      expect(canAdd, isFalse);
    });

    test('allows a new scroll item after safe same-lane spacing opens', () {
      final canAdd = DanmakuScrollTrackScheduler.canAddToTrack(
        visibleItems: const <DanmakuScrollTrackItemSnapshot>[
          DanmakuScrollTrackItemSnapshot(
            width: 200,
            startMs: 0,
            durationMs: 5000,
          ),
        ],
        viewportWidth: 1000,
        timelineMs: 2000,
        newItemWidth: 400,
        newItemDurationMs: 5000,
        minGap: 20,
      );

      expect(canAdd, isTrue);
    });
  });
}
