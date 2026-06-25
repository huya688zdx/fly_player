import '../../media_backend/playback/media_playback.dart';
import 'mpv_player_controller.dart';
import 'player_source_controller.dart' show PlayerPlaybackMode;

/// Emby 播放桥接器：把后端中立 [MediaPlaybackBundle] 装配成播放器最终的 [MpvMediaSource]。
///
/// 对位 [FeiniuPlaybackSourceBridge]，住 player 层、单向依赖 media_backend。与飞牛桥不同：
/// Emby `getPlayback` 一次取数即自足，bundle 已含可播直链 url + headers（entry-token）+ 续播位
/// + 轨道，**桥接器纯本地装配、无二次网络、无 `PlayerSourceController`**（飞牛要再解析代理/会话）。
/// 故 [EmbyPlaybackContext] 仅作分发标记，assemble 不需要它。
///
/// 直链直播口径（见 `docs/superpowers/specs/2026-06-25-emby-playback-design.md`）：mpv 直接吃
/// 原始容器，音轨/字幕按 **mpv 轨道号**（1-based、同类型内序号）选择——原生
/// `resolveRequestedTrackId` 在无 `mpv-*:` guid 时把 `trackIndex` 直接当 `aid`/`sid`，而 mpv
/// 按容器内顺序给同类型轨道编号 1,2,…，与 Emby `MediaStreams` 的 Index 顺序一致，故取序号 +1。
class EmbyPlaybackSourceBridge {
  const EmbyPlaybackSourceBridge();

  /// 装配 [MpvMediaSource]。不导航、不打开页面，只返回 source。
  Future<MpvMediaSource> assemble({
    required MediaPlaybackRequest request,
    required MediaPlaybackBundle bundle,
  }) async {
    final source = bundle.selectedSource;
    final selectedAudio = bundle.selectedAudioTrack;
    final selectedSubtitle = bundle.selectedSubtitleTrack;

    // mpv aid：选中音轨在音轨列表中的 1-based 序号（容器顺序 = mpv 编号顺序）。
    final audioTrackIndex = selectedAudio == null
        ? null
        : _ordinalOf(bundle.audioTracks, selectedAudio.id);

    // 外挂字幕首版不 sideload（留后续）；内嵌字幕走 mpv sid = 内嵌序号 +1。
    final preferExternalSubtitle =
        selectedSubtitle?.subtitleLocation == MediaSubtitleLocation.external;
    final subtitleTrackIndex =
        (selectedSubtitle == null || preferExternalSubtitle)
        ? null
        : _ordinalOf(
            bundle.subtitleTracks
                .where(
                  (t) => t.subtitleLocation == MediaSubtitleLocation.embedded,
                )
                .toList(growable: false),
            selectedSubtitle.id,
          );

    // 续播守卫：直链 reliableSeek 恒 true；照搬飞牛——不可靠 seek 且有起播位则归零。
    final startSeconds = bundle.startPosition.inSeconds;
    final resolvedStart = !source.reliableSeek && startSeconds > 0
        ? Duration.zero
        : bundle.startPosition;

    return MpvMediaSource(
      loadNonce: createMpvLoadNonce(),
      itemGuid: bundle.itemId,
      // 显式 seriesId（剧集/季页面已知）优先，回退 bundle 自身系列 id。
      seriesGuid: request.seriesId.trim().isNotEmpty
          ? request.seriesId.trim()
          : bundle.seriesId,
      seasonGuid: bundle.seasonId,
      posterPath: bundle.posterUrl,
      mediaGuid: source.id,
      mediaType: bundle.itemType,
      videoGuid: source.videoTrackId,
      videoWidth: source.width,
      videoHeight: source.height,
      url: source.url,
      headers: source.headers,
      title: bundle.title,
      seriesTitle: bundle.seriesTitle,
      seasonNumber: bundle.seasonNumber,
      tmdbId: bundle.tmdbId,
      episodeNumber: bundle.episodeNumber,
      startPosition: resolvedStart,
      audioTrackIndex: audioTrackIndex,
      subtitleTrackIndex: subtitleTrackIndex,
      audioTrackGuid: selectedAudio?.id,
      // 显式关闭字幕落空串，避免回退服务端默认；否则带选中字幕 id（无 mpv- 前缀，原生回退到
      // 上面的序号）。
      subtitleTrackGuid: request.subtitleTrackExplicitlyDisabled
          ? ''
          : selectedSubtitle?.id,
      resolution: source.height > 0 ? '${source.height}p' : '',
      durationSeconds: bundle.durationSeconds,
      videoCodecName: source.videoCodec,
      videoProfile: source.videoProfile,
      colorSpace: source.colorSpace,
      colorTransfer: source.colorTransfer,
      colorPrimaries: source.colorPrimaries,
      bitDepth: source.bitDepth,
      preferExternalSubtitle: preferExternalSubtitle,
      forceNativeProxy: source.forceNativeProxy,
      reliableSeek: source.reliableSeek,
      // 直链原文件 = 原画模式（mpv 整文件直播，无服务端转码/画质梯度）。
      playbackMode: PlayerPlaybackMode.originalQuality,
      // audioTracks/subtitleTracks/qualities 首版置空（飞牛 DTO 类型，Emby 无；播放器内切轨
      // UI 留反向通道分块再接，见设计 §3.4/§5）。
    );
  }

  /// 轨道在同类型列表中的 1-based 序号（按 id 匹配，对齐 mpv 轨道编号）；找不到回 null。
  int? _ordinalOf(List<MediaPlaybackTrack> tracks, String id) {
    final position = tracks.indexWhere((t) => t.id == id);
    return position < 0 ? null : position + 1;
  }
}
