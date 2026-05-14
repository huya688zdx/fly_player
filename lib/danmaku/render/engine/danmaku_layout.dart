import 'dart:math' as math;
import 'dart:ui';

class DanmakuViewportRect {
  final Rect bounds;

  const DanmakuViewportRect(this.bounds);

  factory DanmakuViewportRect.fromSize(Size size) {
    return DanmakuViewportRect(Offset.zero & size);
  }

  double get width => bounds.width;
  double get height => bounds.height;
  Size get size => bounds.size;
}

class DanmakuExclusionZone {
  final double x;
  final double y;
  final double width;
  final double height;

  const DanmakuExclusionZone({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  Rect resolve(DanmakuViewportRect viewport) {
    return Rect.fromLTWH(
      viewport.bounds.left + (viewport.width * x),
      viewport.bounds.top + (viewport.height * y),
      viewport.width * width,
      viewport.height * height,
    );
  }
}

class DanmakuTrackLayout {
  final DanmakuViewportRect viewport;
  final double trackHeight;
  final List<double> topTrackYs;
  final List<double> bottomTrackOffsets;
  final List<Rect> exclusionRects;

  const DanmakuTrackLayout({
    required this.viewport,
    required this.trackHeight,
    required this.topTrackYs,
    required this.bottomTrackOffsets,
    required this.exclusionRects,
  });
}

class DanmakuScrollTrackItemSnapshot {
  final double width;
  final int startMs;
  final int durationMs;

  const DanmakuScrollTrackItemSnapshot({
    required this.width,
    required this.startMs,
    required this.durationMs,
  });

  bool isExpired(int timelineMs, double viewportWidth) {
    return xFor(timelineMs, viewportWidth) <= -width;
  }

  double xFor(int timelineMs, double viewportWidth) {
    final elapsedMs = (timelineMs - startMs).clamp(0, durationMs);
    final progress = durationMs <= 0 ? 1.0 : elapsedMs / durationMs;
    return viewportWidth - (progress * (viewportWidth + width));
  }
}

class DanmakuScrollTrackScheduler {
  static bool canAddToTrack({
    required List<DanmakuScrollTrackItemSnapshot> visibleItems,
    required double viewportWidth,
    required int timelineMs,
    required double newItemWidth,
    required int newItemDurationMs,
    required double minGap,
  }) {
    for (final item in visibleItems) {
      if (item.isExpired(timelineMs, viewportWidth)) continue;
      final x = item.xFor(timelineMs, viewportWidth);
      final existingTailX = x + item.width;
      if (existingTailX >= viewportWidth) {
        return false;
      }
      final remainingMs = math.max(
        1,
        item.startMs + item.durationMs - timelineMs,
      );
      final existingSpeed =
          (viewportWidth + item.width) / item.durationMs.clamp(1, 1 << 30);
      final newSpeed =
          (viewportWidth + newItemWidth) / newItemDurationMs.clamp(1, 1 << 30);
      final minSafeGap = math.max(
        minGap,
        (newSpeed - existingSpeed) > 0
            ? (newSpeed - existingSpeed) * remainingMs
            : newItemWidth * 0.20,
      );
      final availableGap = viewportWidth - existingTailX;
      if (availableGap < minSafeGap) {
        return false;
      }
    }
    return true;
  }
}

class DanmakuTrackLayoutEngine {
  static const DanmakuExclusionZone defaultSubjectSafeZone =
      DanmakuExclusionZone(x: 0.22, y: 0.28, width: 0.56, height: 0.42);

  static DanmakuTrackLayout compute({
    required Size viewportSize,
    required double trackHeight,
    required double areaRatio,
    required bool avoidSubtitleArea,
    required bool avoidCenterArea,
    required double subtitleReservedAreaRatio,
    DanmakuExclusionZone? dynamicExclusionZone,
  }) {
    final viewport = DanmakuViewportRect.fromSize(viewportSize);
    final normalizedAreaRatio = areaRatio.clamp(0.1, 1.0).toDouble();
    final edgePadding = (trackHeight * 0.18).clamp(4.0, 18.0);
    final subtitleReserveHeight = avoidSubtitleArea
        ? viewport.height * subtitleReservedAreaRatio.clamp(0.0, 0.5)
        : 0.0;
    final topAreaHeight = math.max(
      0.0,
      (viewport.height * normalizedAreaRatio) - edgePadding,
    );
    final bottomAreaHeight = math.max(
      0.0,
      (viewport.height * normalizedAreaRatio) - edgePadding,
    );
    final exclusionRects = <Rect>[
      if (avoidCenterArea)
        (dynamicExclusionZone ?? defaultSubjectSafeZone).resolve(viewport),
    ];

    final topTrackCount = trackHeight <= 0
        ? 0
        : (topAreaHeight / trackHeight).round().clamp(0, 1000);
    final bottomTrackCount = trackHeight <= 0
        ? 0
        : (bottomAreaHeight / trackHeight).round().clamp(0, 1000);

    final topTracks = <double>[];
    for (var index = 0; index < topTrackCount; index += 1) {
      final y = edgePadding + (index * trackHeight);
      final trackRect = Rect.fromLTWH(0, y, viewport.width, trackHeight);
      if (_intersectsAny(trackRect, exclusionRects)) {
        continue;
      }
      topTracks.add(y);
    }

    final bottomTracks = <double>[];
    for (var index = 0; index < bottomTrackCount; index += 1) {
      final offset =
          subtitleReserveHeight + edgePadding + (index * trackHeight);
      final top = viewport.height - offset - trackHeight;
      if (top < 0) break;
      final trackRect = Rect.fromLTWH(0, top, viewport.width, trackHeight);
      if (_intersectsAny(trackRect, exclusionRects)) {
        continue;
      }
      bottomTracks.add(offset);
    }

    return DanmakuTrackLayout(
      viewport: viewport,
      trackHeight: trackHeight,
      topTrackYs: List<double>.unmodifiable(topTracks),
      bottomTrackOffsets: List<double>.unmodifiable(bottomTracks),
      exclusionRects: List<Rect>.unmodifiable(exclusionRects),
    );
  }

  static bool _intersectsAny(Rect rect, List<Rect> exclusions) {
    for (final exclusion in exclusions) {
      if (rect.overlaps(exclusion)) {
        return true;
      }
    }
    return false;
  }
}
