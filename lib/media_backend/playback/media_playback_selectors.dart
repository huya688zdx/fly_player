import 'media_playback.dart';

/// 公共播放选择器：纯函数复刻入口控制器当前的画质/轨道选择规则，
/// 不依赖后端 DTO、播放器或 UI。
///
/// 提炼成纯函数后，飞牛适配层和将来的 Emby 适配层共用同一套选择语义，
/// 避免规则散落在各自的入口控制器里。

/// 选择画质候选。
///
/// 规则（优先级从高到低）：
/// - `qualityId` 非空且命中 → 用它（优先于下标）。
/// - `qualityIndex` 在范围内 → 用它。
/// - 否则回退到第一个 `isDefault == true`，再否则第一个，列表为空则 `null`。
MediaPlaybackQuality? selectPlaybackQuality({
  required List<MediaPlaybackQuality> qualities,
  String? qualityId,
  int? qualityIndex,
}) {
  if (qualities.isEmpty) return null;

  final id = qualityId?.trim() ?? '';
  if (id.isNotEmpty) {
    for (final quality in qualities) {
      if (quality.id == id) return quality;
    }
  }

  if (qualityIndex != null &&
      qualityIndex >= 0 &&
      qualityIndex < qualities.length) {
    return qualities[qualityIndex];
  }

  for (final quality in qualities) {
    if (quality.isDefault) return quality;
  }
  return qualities.first;
}

/// 选择音轨 / 字幕候选。
///
/// 规则：
/// - `explicitlyDisabled == true` → `null`（用于显式关闭字幕）。
/// - `preferredTrackId` 非空且命中 → 用它。
/// - 否则回退到第一个 `isDefault == true`，再否则第一个，列表为空则 `null`。
MediaPlaybackTrack? selectPlaybackTrack({
  required List<MediaPlaybackTrack> tracks,
  String? preferredTrackId,
  bool explicitlyDisabled = false,
}) {
  if (explicitlyDisabled) return null;
  if (tracks.isEmpty) return null;

  final id = preferredTrackId?.trim() ?? '';
  if (id.isNotEmpty) {
    for (final track in tracks) {
      if (track.id == id) return track;
    }
  }

  for (final track in tracks) {
    if (track.isDefault) return track;
  }
  return tracks.first;
}
