import '../../l10n/generated/app_localizations.dart';
import '../../media_backend/feiniu/feiniu_playback_context.dart';
import '../../media_backend/playback/media_playback.dart';
import '../../media_backend/playback/media_playback_resolution.dart';
import '../../media_backend/playback/media_playback_source_bridge.dart';
import '../../utils/player_artwork_path_resolver.dart';
import '../../utils/player_title_formatter.dart';
import '../../playback/playback_source.dart';
import 'player_source_controller.dart';

/// 飞牛播放桥接器：把后端中立 [MediaPlaybackBundle] + 飞牛不透明上下文
/// [FeiniuPlaybackContext] 装配成播放器最终的 [MpvMediaSource]。
///
/// 这是 `lib/media_backend`（后端中立）与 mpv 播放器层之间的桥。**桥接器单向依赖
/// media_backend**，media_backend 不反向依赖播放器。桥接器复刻 `ItemPlaybackLauncher`
/// 当前的 `buildInitialPlaybackResult` + `MpvMediaSource` 装配口径——续播位已由后端算入
/// `bundle.startPosition`，画质/轨道/直链/代理会话仍由 [PlayerSourceController] 用上下文
/// 的飞牛 raw facts 重新解析（不直接信任 `MediaPlaybackSource.url` 是最终可播 URL）。
class FeiniuPlaybackSourceBridge implements MediaPlaybackSourceBridge {
  const FeiniuPlaybackSourceBridge();

  @override
  Future<MediaPlaybackSourceResult> assemblePlaybackSource({
    required MediaPlaybackRequest request,
    required MediaPlaybackBundle bundle,
    required MediaPlaybackBackendContext? context,
    required AppLocalizations l10n,
  }) async {
    if (context is! FeiniuPlaybackContext) {
      throw StateError('飞牛播放桥接器收到不匹配的后端上下文');
    }
    final source = await assemble(
      request: request,
      bundle: bundle,
      context: context,
      l10n: l10n,
    );
    return MediaPlaybackSourceResult(
      source: source,
      legacySidecar: context.playInfo,
    );
  }

  /// 装配 [MpvMediaSource]。不导航、不打开页面，只返回 source。
  Future<MpvMediaSource> assemble({
    required MediaPlaybackRequest request,
    required MediaPlaybackBundle bundle,
    required FeiniuPlaybackContext context,
    required AppLocalizations l10n,
  }) async {
    final api = context.api;
    final playInfo = context.playInfo;
    final item = playInfo.item;
    final playbackStream = context.playbackStream;
    final initialQuality = context.selectedQuality;
    final selectedAudio = context.selectedAudio;
    final selectedSubtitle = context.selectedSubtitle;
    final subtitleTracks = context.subtitleTracks;

    final playbackResolution =
        initialQuality?.isDirectLink == true &&
            initialQuality!.resolution.trim().isNotEmpty
        ? initialQuality.resolution.trim()
        : (playbackStream.videoStream?.resolutionType.trim().isNotEmpty == true
              ? playbackStream.videoStream!.resolutionType.trim()
              : '');
    final playbackBitrate = initialQuality?.isDirectLink == true
        ? initialQuality!.bitrate
        : (playbackStream.videoStream?.bps ?? 0);

    final preferExternalSubtitle =
        selectedSubtitle != null &&
        (selectedSubtitle.isExternal == 1 ||
            selectedSubtitle.extraFile == 1 ||
            selectedSubtitle.guid.startsWith('local:'));
    final embeddedSubtitleTrackIndex =
        selectedSubtitle == null || preferExternalSubtitle
        ? null
        : () {
            final embeddedTracks = subtitleTracks
                .where((track) {
                  if (track.guid.trim().isEmpty) return false;
                  if (track.guid.startsWith('local:')) return false;
                  return track.isExternal != 1 && track.extraFile != 1;
                })
                .toList(growable: false);
            final ordinal = embeddedTracks.indexWhere(
              (track) => track.guid == selectedSubtitle.guid,
            );
            if (ordinal < 0) return null;
            return ordinal + 1;
          }();

    final initialSeconds = bundle.startPosition.inSeconds;
    final initialPlayback = await const PlayerSourceController()
        .buildInitialPlaybackResult(
          api: api,
          directUrl: context.directUrl,
          mediaGuid: context.effectiveSourceId,
          videoGuid: context.videoTrackId,
          playbackStream: playbackStream,
          quality: initialQuality,
          selectedAudio: selectedAudio,
          selectedSubtitle: selectedSubtitle,
          startPosition: Duration(seconds: initialSeconds),
        );
    final playableSource = initialPlayback.playableSource;
    final resolvedStartPosition =
        !playableSource.reliableSeek && initialSeconds > 0
        ? Duration.zero
        : Duration(seconds: initialSeconds);
    final title = formatPlayerTitleFromPlayItem(
      item,
      fallbackTitle: request.fallbackTitle,
      l10n: l10n,
    );

    return MpvMediaSource(
      loadNonce: createMpvLoadNonce(),
      itemGuid: item.guid,
      // 显式 seriesId（剧集/季页面已知）优先，回退条目自身 grandGuid；Item 路径不传 →
      // 空 → 回退 grandGuid，与 B-2 行为一致。
      seriesGuid: request.seriesId.trim().isNotEmpty
          ? request.seriesId.trim()
          : playInfo.grandGuid.trim(),
      seasonGuid: playInfo.parentGuid,
      posterPath: resolvePlayerArtworkPathForPlayItem(item),
      mediaGuid: initialPlayback.mediaGuid,
      mediaType: item.type,
      ancestorName: item.ancestorName,
      videoGuid: initialPlayback.videoGuid,
      directLinkQualityIndex: initialQuality?.isDirectLink == true
          ? initialQuality!.directLinkQualityIndex
          : null,
      videoWidth: playbackStream.videoStream?.width ?? 0,
      videoHeight: playbackStream.videoStream?.height ?? 0,
      proxySessionId: playableSource.proxySessionId,
      playLink: initialPlayback.playLink,
      serverSessionHlsTimeSeconds: initialPlayback.serverSessionHlsTimeSeconds,
      url: playableSource.url,
      headers: playableSource.headers,
      title: title,
      seriesTitle: item.tvTitle.trim().isNotEmpty
          ? item.tvTitle.trim()
          : request.fallbackTitle.trim(),
      seasonNumber: item.seasonNumber,
      tmdbId: item.trimId,
      episodeNumber: item.episodeNumber,
      startPosition: resolvedStartPosition,
      audioTrackIndex: selectedAudio?.index,
      subtitleTrackIndex: embeddedSubtitleTrackIndex,
      audioTrackGuid: selectedAudio?.guid ?? playInfo.audioGuid,
      // 显式关闭字幕（subtitleTrackExplicitlyDisabled）时落空串，避免回退到服务端默认轨；
      // 复刻 launcher 的 `selectedSubtitle?.guid ?? (overrideSubtitleGuid ?? subtitleGuid)`。
      subtitleTrackGuid:
          selectedSubtitle?.guid ??
          (request.subtitleTrackExplicitlyDisabled
              ? ''
              : playInfo.subtitleGuid),
      resolution: playbackResolution,
      bitrate: playbackBitrate,
      durationSeconds: item.duration,
      videoCodecName: playbackStream.videoStream?.codecName ?? '',
      videoProfile: playbackStream.videoStream?.profile ?? '',
      colorSpace: playbackStream.videoStream?.colorSpace ?? '',
      colorTransfer: playbackStream.videoStream?.colorTransfer ?? '',
      colorPrimaries: playbackStream.videoStream?.colorPrimaries ?? '',
      bitDepth: playbackStream.videoStream?.bitDepth ?? 0,
      preferExternalSubtitle: preferExternalSubtitle,
      forceNativeProxy: playableSource.forceNativeProxy,
      reliableSeek: playableSource.reliableSeek,
      seekProbeSummary: playableSource.seekProbeSummary,
      playbackMode: initialPlayback.playbackMode,
      playbackSpeed: 1.0,
      audioTracks: playbackStream.audioStreams,
      subtitleTracks: subtitleTracks,
      qualities: context.mergedQualities,
    );
  }
}
