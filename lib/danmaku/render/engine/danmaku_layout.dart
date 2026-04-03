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
    final edgePadding = (trackHeight * 0.18).clamp(3.0, 10.0);
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
        : (topAreaHeight / trackHeight).floor().clamp(0, 1000);
    final bottomTrackCount = trackHeight <= 0
        ? 0
        : (bottomAreaHeight / trackHeight).floor().clamp(0, 1000);

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
