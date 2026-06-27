import '../../media_backend/emby/emby_playback_mappers.dart';
import '../../media_backend/playback/media_playback.dart';
import '../../models/stream_track_data.dart';
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

    // 外挂字幕走原生壳反向通道下载 sub-add（preferExternalSubtitle 让壳走外挂文件路径）；
    // 内嵌字幕走 mpv sid = 内嵌序号 +1。
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
      // 系列名空（电影无系列）时回退条目标题——原生壳弹幕预取按 seriesTitle 匹配
      // DanDanPlay，空则不匹配；复刻飞牛桥「tvTitle | fallbackTitle」让电影也能出弹幕。
      seriesTitle: bundle.seriesTitle.trim().isNotEmpty
          ? bundle.seriesTitle
          : bundle.title,
      seasonNumber: bundle.seasonNumber,
      tmdbId: bundle.tmdbId,
      episodeNumber: bundle.episodeNumber,
      startPosition: resolvedStart,
      audioTrackIndex: audioTrackIndex,
      subtitleTrackIndex: subtitleTrackIndex,
      audioTrackGuid: selectedAudio?.id,
      // 显式关闭字幕落空串，避免回退服务端默认；否则带选中字幕 guid——内嵌为容器 Index（无
      // mpv- 前缀，原生回退到上面的序号），外挂为自包含 guid（原生据此反向通道下载 sub-add）。
      subtitleTrackGuid: request.subtitleTrackExplicitlyDisabled
          ? ''
          : _subtitleSelectionGuid(bundle, selectedSubtitle),
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
      // 播放器内音轨/字幕选择器读 loadArgs 的 audioTracks/subtitleTracks（原生壳 showTrackPicker
      // 用列表 1-based 位置当 mpv aid/sid）。用 bundle 中立轨道构造飞牛 DTO 点亮壳内切轨。
      // qualities 仍空（Emby 直链无画质梯度；版本切换在详情页选）。
      audioTracks: _audioTrackOptions(bundle),
      subtitleTracks: _subtitleTrackOptions(bundle),
      // 拖动 seek 预览缩略图（Emby 章节图）。中立 [MediaSeekThumbnail] → 播放器层
      // [MpvSeekThumbnail]，随 toMap 进 loadArgs 传原生壳。空则原生退回纯时间药丸。
      seekThumbnails: <MpvSeekThumbnail>[
        for (final thumb in bundle.seekThumbnails)
          MpvSeekThumbnail(
            positionMs: thumb.position.inMilliseconds,
            url: thumb.url,
          ),
      ],
    );
  }

  /// bundle 音轨 → 飞牛 [AudioTrackOption]（喂原生壳 showTrackPicker）。列表顺序 = 容器顺序
  /// = mpv aid 顺序，原生用 1-based 位置作 aid。Emby DisplayTitle（含语言/编码）放 title、
  /// language 留空，避免 picker 标签重复。
  List<AudioTrackOption> _audioTrackOptions(MediaPlaybackBundle bundle) {
    final source = bundle.selectedSource;
    return <AudioTrackOption>[
      for (final track in bundle.audioTracks)
        AudioTrackOption(
          mediaGuid: source.id,
          guid: track.id,
          title: track.label,
          codecName: track.codec,
          profile: '',
          language: '',
          audioType: '',
          channelLayout: '',
          channels: 0,
          sampleRate: 0,
          bps: 0,
          index: track.index ?? 0,
          isDefault: track.isDefault ? 1 : 0,
        ),
    ];
  }

  /// bundle 字幕 → 飞牛 [SubtitleTrackOption]，喂原生壳字幕面板。
  ///
  /// 内嵌字幕：guid = 容器 Index，isExternal=0；原生壳 `applySubtitleByGuid` 按「非外挂轨」
  /// 计数得 mpv sid（外挂轨被跳过、不占位），故内嵌 sid 不受外挂混入影响。位图字幕（pgs/sup/
  /// dvd 等）标 isBitmap=1——mpv 只能作内嵌轨播放、无法 sub-add 文本，故即便外挂位图也走内嵌。
  ///
  /// 外挂字幕（非位图）：guid = 自包含 [embyExternalSubtitleGuid]，isExternal=1/extraFile=1；
  /// 原生 `nativeSubtitleUsesExternalFile` 据此走外挂文件路径 → 反向通道 resolveSubtitleFile
  /// 解码 guid 下载 sub-add。外挂位图无法 sub-add 文本，跳过不发（避免面板里出现选不动的轨）。
  List<SubtitleTrackOption> _subtitleTrackOptions(MediaPlaybackBundle bundle) {
    final source = bundle.selectedSource;
    final options = <SubtitleTrackOption>[];
    for (final track in bundle.subtitleTracks) {
      final isExternal =
          track.subtitleLocation == MediaSubtitleLocation.external;
      final isBitmap = _isBitmapSubtitle(track.codec);
      // 外挂位图字幕无法 sub-add 文本，也无内嵌轨可选，跳过。
      if (isExternal && isBitmap) continue;
      options.add(
        SubtitleTrackOption(
          mediaGuid: source.id,
          guid: isExternal
              ? embyExternalSubtitleGuid(
                  itemId: bundle.itemId,
                  mediaSourceId: source.id,
                  index: track.index ?? 0,
                )
              : track.id,
          title: track.label,
          codecName: track.codec,
          format: track.codec,
          language: '',
          index: track.index ?? 0,
          isDefault: track.isDefault ? 1 : 0,
          forced: 0,
          isExternal: isExternal ? 1 : 0,
          extraFile: isExternal ? 1 : 0,
          isBitmap: isBitmap ? 1 : 0,
        ),
      );
    }
    return options;
  }

  /// 选中字幕的 source 级 guid：外挂 → 自包含 guid（与 [_subtitleTrackOptions] 一致，使初始
  /// 选中态能在面板列表命中并触发外挂下载）；内嵌 → 容器 Index；未选 → null。
  String? _subtitleSelectionGuid(
    MediaPlaybackBundle bundle,
    MediaPlaybackTrack? selectedSubtitle,
  ) {
    if (selectedSubtitle == null) return null;
    if (selectedSubtitle.subtitleLocation == MediaSubtitleLocation.external &&
        !_isBitmapSubtitle(selectedSubtitle.codec)) {
      return embyExternalSubtitleGuid(
        itemId: bundle.itemId,
        mediaSourceId: bundle.selectedSource.id,
        index: selectedSubtitle.index ?? 0,
      );
    }
    return selectedSubtitle.id;
  }

  static bool _isBitmapSubtitle(String codec) {
    final c = codec.trim().toLowerCase();
    return c.contains('pgs') ||
        c.contains('dvdsub') ||
        c.contains('dvbsub') ||
        c.contains('dvd_sub') ||
        c == 'xsub' ||
        c == 'sup';
  }

  /// 轨道在同类型列表中的 1-based 序号（按 id 匹配，对齐 mpv 轨道编号）；找不到回 null。
  int? _ordinalOf(List<MediaPlaybackTrack> tracks, String id) {
    final position = tracks.indexWhere((t) => t.id == id);
    return position < 0 ? null : position + 1;
  }
}
