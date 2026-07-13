import '../../models/playback_stream.dart';

class WeakNetworkQualityRecommendation {
  final PlaybackQualityOption quality;

  const WeakNetworkQualityRecommendation({required this.quality});
}

WeakNetworkQualityRecommendation? recommendWeakNetworkQuality({
  required List<PlaybackQualityOption> qualities,
  required PlaybackQualityOption currentQuality,
  required int networkSpeedBytesPerSecond,
}) {
  if (qualities.isEmpty) return null;
  final sorted = List<PlaybackQualityOption>.from(qualities)
    ..sort(_compareQualityPreference);

  if (networkSpeedBytesPerSecond > 0) {
    final maxSafeBitrateBitsPerSecond = (networkSpeedBytesPerSecond * 8 * 0.9)
        .floor();
    for (final quality in sorted) {
      if (quality.bitrate <= 0) continue;
      if (quality.bitrate > maxSafeBitrateBitsPerSecond) continue;
      if (_sameQuality(quality, currentQuality)) {
        return null;
      }
      return WeakNetworkQualityRecommendation(quality: quality);
    }
  }

  final fallback = _nextLowerKnownBitrateQuality(
    sorted: sorted,
    currentQuality: currentQuality,
  );
  if (fallback == null || _sameQuality(fallback, currentQuality)) {
    return null;
  }
  return WeakNetworkQualityRecommendation(quality: fallback);
}

bool isMeaningfulWeakNetworkDowngrade({
  required PlaybackQualityOption currentQuality,
  required PlaybackQualityOption recommendedQuality,
}) {
  if (currentQuality.bitrate <= 0 || recommendedQuality.bitrate <= 0) {
    return false;
  }
  return recommendedQuality.bitrate <= (currentQuality.bitrate * 0.8).floor();
}

String formatWeakNetworkSpeedLabel(int bytesPerSecond) {
  if (bytesPerSecond <= 0) return '-- KB/s';
  const kb = 1024.0;
  const mb = kb * 1024.0;
  if (bytesPerSecond >= mb.toInt()) {
    final value = bytesPerSecond / mb;
    final digits = value >= 10 ? 0 : 1;
    return '${value.toStringAsFixed(digits)} MB/s';
  }
  final value = bytesPerSecond / kb;
  final digits = value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} KB/s';
}

String buildWeakNetworkBufferingDetails({
  required int networkSpeedBytesPerSecond,
  Duration? estimatedResumeWait,
}) {
  final speedLabel = formatWeakNetworkSpeedLabel(networkSpeedBytesPerSecond);
  final etaLabel = _formatWeakNetworkEta(estimatedResumeWait);
  if (etaLabel == null) {
    return '\u5f53\u524d\u7f51\u901f $speedLabel';
  }
  return '\u5f53\u524d\u7f51\u901f $speedLabel \u00b7 \u9884\u8ba1\u6062\u590d $etaLabel';
}

PlaybackQualityOption? _nextLowerKnownBitrateQuality({
  required List<PlaybackQualityOption> sorted,
  required PlaybackQualityOption currentQuality,
}) {
  if (sorted.isEmpty) return null;
  final currentIndex = sorted.indexWhere(
    (quality) => _sameQuality(quality, currentQuality),
  );
  if (currentIndex >= 0) {
    for (var index = currentIndex + 1; index < sorted.length; index += 1) {
      final candidate = sorted[index];
      if (candidate.bitrate <= 0) continue;
      if (currentQuality.bitrate > 0 &&
          candidate.bitrate >= currentQuality.bitrate) {
        continue;
      }
      return candidate;
    }
  }
  if (currentQuality.bitrate > 0) {
    for (final candidate in sorted) {
      if (candidate.bitrate <= 0) continue;
      if (candidate.bitrate < currentQuality.bitrate) {
        return candidate;
      }
    }
    return null;
  }
  for (final candidate in sorted.reversed) {
    if (candidate.bitrate > 0 && !_sameQuality(candidate, currentQuality)) {
      return candidate;
    }
  }
  return null;
}

int _compareQualityPreference(
  PlaybackQualityOption left,
  PlaybackQualityOption right,
) {
  if (left.bitrate != right.bitrate) {
    return right.bitrate.compareTo(left.bitrate);
  }
  final resolutionOrder = _resolutionOrder(
    right,
  ).compareTo(_resolutionOrder(left));
  if (resolutionOrder != 0) {
    return resolutionOrder;
  }
  if (left.isOriginalProxy != right.isOriginalProxy) {
    return left.isOriginalProxy ? -1 : 1;
  }
  if (left.isDefault != right.isDefault) {
    return right.isDefault.compareTo(left.isDefault);
  }
  return left.resolution.compareTo(right.resolution);
}

int _resolutionOrder(PlaybackQualityOption quality) {
  final match = RegExp(
    r'(\d{3,4})',
  ).firstMatch(quality.resolution.toLowerCase());
  return int.tryParse(match?.group(1) ?? '') ?? -1;
}

bool _sameQuality(PlaybackQualityOption left, PlaybackQualityOption right) {
  return left.source == right.source &&
      left.mediaGuid == right.mediaGuid &&
      left.videoGuid == right.videoGuid &&
      left.resolution == right.resolution &&
      left.bitrate == right.bitrate &&
      left.directLinkQualityIndex == right.directLinkQualityIndex;
}

String? _formatWeakNetworkEta(Duration? estimatedResumeWait) {
  if (estimatedResumeWait == null) return null;
  final seconds = (estimatedResumeWait.inMilliseconds / 1000).ceil();
  final normalizedSeconds = seconds <= 0 ? 1 : seconds;
  return '$normalizedSeconds\u79d2';
}
