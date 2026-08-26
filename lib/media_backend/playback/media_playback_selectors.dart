import 'media_playback.dart';

/// 公共播放选择器：纯函数复刻入口控制器当前的画质/轨道选择规则，
/// 不依赖后端 DTO、播放器或 UI。
///
/// 提炼成纯函数后，飞牛适配层和将来的 Emby 适配层共用同一套选择语义，
/// 避免规则散落在各自的入口控制器里。

/// 选择画质候选。
///
/// 规则（优先级从高到低）：
/// - `qualityId` 非空且命中 → 用同 source 的原画 / 默认档，找不到再用同 source 第一档
///   （复刻入口控制器切版本时优先原画的口径）。
/// - `qualityIndex` 在范围内 → 用它。
/// - `preferredResolution` 非空且命中（分辨率字符串相等）→ 用第一条匹配档（跨集继承
///   「当前分辨率」，如 1080p 转码档；找不到则回退默认梯度，对齐「找不到回默认」）。
/// - 否则按入口控制器初始画质口径回退：直链默认档 → 任意直链档 → 原画档 →
///   第一个默认档 → 第一档，列表为空则 `null`。
MediaPlaybackQuality? selectPlaybackQuality({
  required List<MediaPlaybackQuality> qualities,
  String? qualityId,
  int? qualityIndex,
  String? preferredResolution,
}) {
  if (qualities.isEmpty) return null;

  final id = qualityId?.trim() ?? '';
  if (id.isNotEmpty) {
    MediaPlaybackQuality? firstMatched;
    for (final quality in qualities) {
      if (quality.id != id && quality.sourceId != id) continue;
      firstMatched ??= quality;
      if (quality.isDefault ||
          quality.delivery == MediaPlaybackDeliveryKind.original) {
        return quality;
      }
    }
    if (firstMatched != null) return firstMatched;
  }

  if (qualityIndex != null &&
      qualityIndex >= 0 &&
      qualityIndex < qualities.length) {
    return qualities[qualityIndex];
  }

  final res = preferredResolution?.trim() ?? '';
  if (res.isNotEmpty) {
    for (final quality in qualities) {
      if (quality.resolution.trim() == res) return quality;
    }
  }

  for (final quality in qualities) {
    if (quality.delivery == MediaPlaybackDeliveryKind.directLink &&
        quality.isDefault) {
      return quality;
    }
  }
  for (final quality in qualities) {
    if (quality.delivery == MediaPlaybackDeliveryKind.directLink) {
      return quality;
    }
  }
  for (final quality in qualities) {
    if (quality.delivery == MediaPlaybackDeliveryKind.original) return quality;
  }
  for (final quality in qualities) {
    if (quality.isDefault) return quality;
  }
  return qualities.first;
}

/// 选择音轨 / 字幕候选。
///
/// 规则（优先级从高到低）：
/// - `explicitlyDisabled == true` → `null`（用于显式关闭字幕）。
/// - `preferredTrackId`（显式 guid）非空且命中 → 用它。
/// - `preferredTrackIndex` 在范围内 → 用第 N 条（跨集按序号继承「当前第几条轨道」）。
/// - `fallbackTrackId`（服务端默认 guid）非空且命中 → 用它。
/// - 否则回退到第一个 `isDefault == true`，再否则第一个，列表为空则 `null`。
///
/// `preferredTrackId` 表达「用户显式指定的某条轨道」，`fallbackTrackId` 表达「后端给的
/// 默认轨道」——两者分开，使按序号继承（[preferredTrackIndex]）能压过服务端默认，而显式
/// 指定仍最高优先。序号越界时自然落到默认，对齐「找不到对应序号就回默认」。
MediaPlaybackTrack? selectPlaybackTrack({
  required List<MediaPlaybackTrack> tracks,
  String? preferredTrackId,
  int? preferredTrackIndex,
  String? fallbackTrackId,
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

  if (preferredTrackIndex != null &&
      preferredTrackIndex >= 0 &&
      preferredTrackIndex < tracks.length) {
    return tracks[preferredTrackIndex];
  }

  final fallbackId = fallbackTrackId?.trim() ?? '';
  if (fallbackId.isNotEmpty) {
    for (final track in tracks) {
      if (track.id == fallbackId) return track;
    }
  }

  for (final track in tracks) {
    if (track.isDefault) return track;
  }
  return tracks.first;
}
