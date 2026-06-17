import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../controllers/play_detail_data_loader.dart';
import '../danmaku/settings/danmaku_settings_store.dart';
import '../services/native_danmaku_prefetch.dart';
import '../services/native_player_bridge.dart';
import '../services/native_reentry_support.dart';
import '../models/play_info.dart';
import '../models/playback_stream.dart';
import '../models/stream_track_data.dart';
import '../player/controllers/mpv_player_controller.dart';
import '../player/mpv_player_page.dart';
import '../player/controllers/player_source_controller.dart';
import '../providers/nas_provider.dart';
import '../services/app_log_service.dart';
import '../services/embedded_detail_launcher.dart';
import '../services/play_stats/play_stats.dart';
import '../ui/app_transitions.dart';
import '../utils/api_url_helper.dart';
import '../utils/app_error_reporter.dart';
import '../utils/app_exception.dart';
import '../utils/async_action_guard.dart';
import '../utils/player_artwork_path_resolver.dart';
import '../utils/playback_resume_position_resolver.dart';
import '../utils/player_title_formatter.dart';
import '../controllers/local_download_source_resolver.dart';
import '../models/media_library_item.dart';
import '../services/download_task_service.dart';
import '../utils/play_detail_track_selector.dart';

/// 负责从条目详情上下文构建并拉起播放器。
class ItemPlaybackLauncher {
  /// 创建一个条目播放拉起器实例。
  const ItemPlaybackLauncher();

  /// 加载播放所需数据并打开播放器页面。
  Future<PlayDetailPlayerReturnData?> open(
    BuildContext context, {
    required String itemGuid,
    String fallbackTitle = '',
    bool startFromBeginning = false,
    Duration? resumePosition,
  }) async {
    return AsyncActionGuard.run<PlayDetailPlayerReturnData?>(
      'item_playback:${itemGuid.trim()}:${startFromBeginning ? 'restart' : 'default'}',
      settleDuration: const Duration(milliseconds: 500),
      action: () async {
        final nas = context.read<NasProvider>();
        final resolved = await _resolve(
          nas,
          itemGuid: itemGuid,
          fallbackTitle: fallbackTitle,
          startFromBeginning: startFromBeginning,
          resumePosition: resumePosition,
        );
        if (resolved == null) return null;
        final source = resolved.source;
        final playInfo = resolved.playInfo;
        final title = resolved.title;

        if (!context.mounted) return null;
        // 灰度：原生渲染器开启时走纯原生播放壳，并注册反向通道（画质切换 + 续播回写；
        // 电影/单视频无选集）。maybeLaunch 内部判断开关 + 预取弹幕。
        final danmakuSettings = await const DanmakuSettingsStore().load();
        if (danmakuSettings.useNativeRenderer) {
          _bindReentry(nas, fallbackTitle: fallbackTitle);
          if (await NativePlayerBridge.maybeLaunch(source.toMap(), nas: nas)) {
            return null;
          }
        }
        if (!context.mounted) return null;
        final navigator = Navigator.of(context);
        final embeddedResult =
            await EmbeddedDetailLauncher.openFullscreenPlayer(
              context: context,
              title: title,
              source: source,
              initialPlayInfo: playInfo,
              startSource: PlayStartSource.manual,
            );
        if (embeddedResult.handled) {
          return embeddedResult.data;
        }
        final result = await navigator.push(
          AppTransitions.playerRoute(
            MpvPlayerPage(
              title: title,
              source: source,
              initialPlayInfo: playInfo,
              startSource: PlayStartSource.manual,
            ),
          ),
        );
        return result is PlayDetailPlayerReturnData ? result : null;
      },
    );
  }

  /// 注册画质/续播反向通道（捕获 nas，脱离 widget context）。单视频/电影无选集。
  void _bindReentry(NasProvider nas, {String fallbackTitle = ''}) {
    NativePlayerBridge.bindReentry(
      onResolvePlayback:
          (
            itemGuid, {
            qualityIndex,
            qualityMediaGuid,
            startPositionMs,
            subtitleGuid,
            audioGuid,
          }) => resolveForNative(
            nas,
            itemGuid: itemGuid,
            fallbackTitle: fallbackTitle,
            qualityIndex: qualityIndex,
            qualityMediaGuid: qualityMediaGuid,
            startPositionMs: startPositionMs,
            subtitleGuid: subtitleGuid,
            audioGuid: audioGuid,
          ),
      onRecordProgress: (progress) =>
          NativeReentrySupport.recordProgress(nas, progress),
      onResolveSubtitleFile: (guid, {format}) =>
          NativeReentrySupport.resolveSubtitleFile(nas, guid, format: format),
      onReloadServerSession:
          (
            currentLoadArgs, {
            audioGuid,
            subtitleGuid,
            qualityIndex,
            startPositionMs,
          }) => NativeReentrySupport.reloadServerSession(
            nas,
            currentLoadArgs: currentLoadArgs,
            audioGuid: audioGuid,
            subtitleGuid: subtitleGuid,
            qualityIndex: qualityIndex,
            startPositionMs: startPositionMs,
          ),
      onLoadEpisodePickerData: (currentLoadArgs, {seasonGuid}) =>
          NativeReentrySupport.loadEpisodePickerData(
            nas,
            currentLoadArgs: currentLoadArgs,
            seasonGuid: seasonGuid ?? '',
          ),
      onLoadSeasonEpisodes: (seasonGuid) =>
          NativeReentrySupport.loadSeasonEpisodes(nas, seasonGuid: seasonGuid),
      onSetEpisodePickerViewType: (viewType) =>
          NativeReentrySupport.setEpisodePickerViewType(nas, viewType),
    );
  }

  /// 只解析（不启动 Activity）：原生壳画质切换时回到这里重解析指定档，回传 loadArgs+弹幕。
  Future<Map<String, dynamic>?> resolveForNative(
    NasProvider nas, {
    required String itemGuid,
    String fallbackTitle = '',
    int? qualityIndex,
    String? qualityMediaGuid,
    int? startPositionMs,
    String? subtitleGuid,
    String? audioGuid,
    List<Map<String, dynamic>>? episodes,
  }) async {
    return AsyncActionGuard.run<Map<String, dynamic>?>(
      'item_resolve:${itemGuid.trim()}',
      settleDuration: const Duration(milliseconds: 300),
      action: () async {
        // Bug fix(季页面播下载集走网络)：先查本地下载记录，有则播本地文件。
        // qualityIndex 非空说明是切画质，本地文件没有多画质，跳过直接走 NAS。
        if (qualityIndex == null) {
          await DownloadTaskService.instance.initialize();
          final localRecord = DownloadTaskService.instance
              .downloadedRecordForItem(itemGuid.trim());
          if (localRecord != null) {
            final local = await resolveLocalDownloadSource(
              localRecord,
              nas,
              startPositionMs: startPositionMs,
            );
            if (local != null) {
              final loadArgs = <String, dynamic>{
                ...local.source.toMap(),
                if (startPositionMs != null) 'startPositionMs': startPositionMs,
                // Bug 2 fix(下载视频切集后选集消失)：本地路由也带上 episodes。
                if (episodes != null && episodes.isNotEmpty)
                  'episodes': episodes,
              };
              final settings = await const DanmakuSettingsStore().load();
              final danmakuFile = await NativeDanmakuPrefetch.resolveToFile(
                seriesTitle: (loadArgs['seriesTitle'] ?? '').toString(),
                seasonNumber: (loadArgs['seasonNumber'] as num?)?.toInt() ?? 0,
                episodeNumber:
                    (loadArgs['episodeNumber'] as num?)?.toInt() ?? 0,
                tmdbId: (loadArgs['tmdbId'] ?? '').toString(),
                settings: settings,
                itemGuid: (loadArgs['itemGuid'] ?? '').toString(),
                mediaGuid: (loadArgs['mediaGuid'] ?? '').toString(),
                seasonGuid: (loadArgs['seasonGuid'] ?? '').toString(),
              );
              return <String, dynamic>{
                'loadArgs': jsonEncode(loadArgs),
                if (danmakuFile != null && danmakuFile.isNotEmpty)
                  'danmakuFile': danmakuFile,
              };
            }
          }
        }
        final resolved = await _resolve(
          nas,
          itemGuid: itemGuid,
          fallbackTitle: fallbackTitle,
          qualityIndex: qualityIndex,
          qualityMediaGuid: qualityMediaGuid,
          overrideSubtitleGuid: subtitleGuid,
          overrideAudioGuid: audioGuid,
        );
        if (resolved == null) return null;
        final loadArgs = <String, dynamic>{
          ...resolved.source.toMap(),
          if (startPositionMs != null) 'startPositionMs': startPositionMs,
          if (episodes != null && episodes.isNotEmpty) 'episodes': episodes,
        };
        final settings = await const DanmakuSettingsStore().load();
        final danmakuFile = await NativeDanmakuPrefetch.resolveToFile(
          seriesTitle: (loadArgs['seriesTitle'] ?? '').toString(),
          seasonNumber: (loadArgs['seasonNumber'] as num?)?.toInt() ?? 0,
          episodeNumber: (loadArgs['episodeNumber'] as num?)?.toInt() ?? 0,
          tmdbId: (loadArgs['tmdbId'] ?? '').toString(),
          settings: settings,
          itemGuid: (loadArgs['itemGuid'] ?? '').toString(),
          mediaGuid: (loadArgs['mediaGuid'] ?? '').toString(),
          seasonGuid: (loadArgs['seasonGuid'] ?? '').toString(),
        );
        return <String, dynamic>{
          'loadArgs': jsonEncode(loadArgs),
          if (danmakuFile != null && danmakuFile.isNotEmpty)
            'danmakuFile': danmakuFile,
        };
      },
    );
  }

  /// 解析一集的可播 source（含轨道/续播位/标题），open 与 resolveForNative 共用。
  Future<({MpvMediaSource source, PlayInfoData playInfo, String title})?>
  _resolve(
    NasProvider nas, {
    required String itemGuid,
    String fallbackTitle = '',
    bool startFromBeginning = false,
    Duration? resumePosition,
    int? qualityIndex,
    String? qualityMediaGuid,
    String? overrideSubtitleGuid,
    String? overrideAudioGuid,
  }) async {
    final api = FeiniuApi(nas);
    final playInfo = await api.getPlayInfo(itemGuid);
    // 多版本切换：带 qualityMediaGuid 时按该版本媒体取流（原画 + 该版本字幕/音轨），
    // 否则用条目默认媒体 playInfo.mediaGuid。切版本不再回退到默认媒体的原画/字幕。
    final normalizedQualityMediaGuid = qualityMediaGuid?.trim() ?? '';
    final effectiveMediaGuid = normalizedQualityMediaGuid.isNotEmpty
        ? normalizedQualityMediaGuid
        : playInfo.mediaGuid;
    if (startFromBeginning) {
      await api.resetPlaybackRecord(
        itemGuid: playInfo.item.guid,
        mediaGuid: effectiveMediaGuid,
      );
    }
    StreamTrackData? trackData;
    try {
      trackData = await api.getStreamTrackData(itemGuid);
    } catch (error, stackTrace) {
      unawaited(
        AppErrorReporter.report(
          error,
          action: 'load stream track data',
          source: 'item_playback_launcher',
          stackTrace: stackTrace,
          fallbackKind: AppExceptionKind.noData,
          level: AppLogLevel.warning,
          details: 'itemGuid=$itemGuid',
        ),
      );
    }
    final playbackStream = await api.getPlaybackStream(effectiveMediaGuid);
    final mergedQualities = mergePlaybackQualitiesWithStreamTrackData(
      playbackStream.qualities,
      trackData,
    );
    // Bug 2 fix(版本相同)：优先用 qualityMediaGuid 在 mergedQualities 里 match，
    // 避免 qualityIndex 在 NAS 重新拉取时顺序不同导致选错版本。
    PlaybackQualityOption? initialQuality;
    if (normalizedQualityMediaGuid.isNotEmpty) {
      // 切版本优先选该版本的原画档（isDefault/原画代理），保证走原画而不是转码档。
      for (final q in mergedQualities) {
        if (q.mediaGuid.trim() == normalizedQualityMediaGuid &&
            (q.isDefault == 1 || q.isOriginalProxy)) {
          initialQuality = q;
          break;
        }
      }
      if (initialQuality == null) {
        for (final q in mergedQualities) {
          if (q.mediaGuid.trim() == normalizedQualityMediaGuid) {
            initialQuality = q;
            break;
          }
        }
      }
    }
    if (initialQuality == null &&
        qualityIndex != null &&
        qualityIndex >= 0 &&
        qualityIndex < mergedQualities.length) {
      initialQuality = mergedQualities[qualityIndex];
    }
    initialQuality ??= PlayerSourceController.preferredInitialQuality(
      mergedQualities,
    );

    // 音轨重载（原生壳转码切音轨）：overrideAudioGuid 非空覆盖服务端默认；音轨无"关闭"。
    final selectedAudio = PlayDetailTrackSelector.selectedOrFirstAudio(
      selectedAudioGuid: overrideAudioGuid?.trim().isNotEmpty == true
          ? overrideAudioGuid
          : playInfo.audioGuid,
      audioTracks: playbackStream.audioStreams,
    );
    final subtitleTracks = PlayDetailTrackSelector.mergeSubtitleTracks(
      primaryTracks: playbackStream.subtitleStreams,
      extraTracks: trackData?.subtitlesForMedia(effectiveMediaGuid) ?? const [],
    );
    // 字幕重载（原生壳转码切字幕）：overrideSubtitleGuid 非空覆盖服务端默认；
    // 空串=显式关闭（不可走 selectedOrFirst，否则会回退到第一条）；null=沿用默认。
    final selectedSubtitle = overrideSubtitleGuid == null
        ? PlayDetailTrackSelector.selectedOrFirstSubtitle(
            selectedSubtitleGuid: playInfo.subtitleGuid,
            subtitleTracks: subtitleTracks,
          )
        : overrideSubtitleGuid.isEmpty
        ? null
        : PlayDetailTrackSelector.selectedOrFirstSubtitle(
            selectedSubtitleGuid: overrideSubtitleGuid,
            subtitleTracks: subtitleTracks,
          );

    final playbackVideoGuid =
        initialQuality?.videoGuid.trim().isNotEmpty == true
        ? initialQuality!.videoGuid.trim()
        : (playbackStream.videoStream?.guid.trim().isNotEmpty == true
              ? playbackStream.videoStream!.guid.trim()
              : playInfo.videoGuid.trim());
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

    final resume = await PlaybackResumePositionResolver.resolve(
      videoIds: <String>[playInfo.item.guid, itemGuid],
      durationSeconds: playInfo.item.duration,
      networkPositionSeconds: startFromBeginning
          ? 0
          : resumePosition?.inSeconds ??
                (playInfo.ts > 0 ? playInfo.ts : playInfo.item.watchedTs),
      networkPositionAvailable: true,
      resetCompletedToBeginning: false,
    );
    final initialSeconds = resume.position.inSeconds;
    final initialPlayback = await const PlayerSourceController()
        .buildInitialPlaybackResult(
          api: api,
          directUrl: api.getStreamUrl(effectiveMediaGuid),
          mediaGuid: effectiveMediaGuid,
          videoGuid: playbackVideoGuid,
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
      playInfo.item,
      fallbackTitle: fallbackTitle,
    );

    final source = MpvMediaSource(
      loadNonce: createMpvLoadNonce(),
      itemGuid: playInfo.item.guid,
      seriesGuid: playInfo.grandGuid.trim(),
      seasonGuid: playInfo.parentGuid,
      posterPath: resolvePlayerArtworkPathForPlayItem(playInfo.item),
      mediaGuid: initialPlayback.mediaGuid,
      mediaType: playInfo.item.type,
      ancestorName: playInfo.item.ancestorName,
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
      seriesTitle: playInfo.item.tvTitle.trim().isNotEmpty
          ? playInfo.item.tvTitle.trim()
          : fallbackTitle.trim(),
      seasonNumber: playInfo.item.seasonNumber,
      tmdbId: playInfo.item.trimId,
      episodeNumber: playInfo.item.episodeNumber,
      startPosition: resolvedStartPosition,
      audioTrackIndex: selectedAudio?.index,
      subtitleTrackIndex: embeddedSubtitleTrackIndex,
      audioTrackGuid: selectedAudio?.guid ?? playInfo.audioGuid,
      // override 非空（含空串=关闭）时以 override 为准，避免关闭后回退到服务端默认轨。
      subtitleTrackGuid:
          selectedSubtitle?.guid ??
          (overrideSubtitleGuid ?? playInfo.subtitleGuid),
      resolution: playbackResolution,
      bitrate: playbackBitrate,
      durationSeconds: playInfo.item.duration,
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
      qualities: mergedQualities,
    );

    return (source: source, playInfo: playInfo, title: title);
  }

  /// 加载整季剧集列表,供原生壳「选集」对话框使用。
  /// NAS 未连接或 seasonGuid 空时返回空列表(由调用方回退到本地组集)。
  /// 每集携带 `downloaded` 标记(已下载本地文件可用)。
  Future<List<Map<String, dynamic>>> loadSeasonEpisodes(
    NasProvider nas,
    String seasonGuid,
  ) async {
    if (seasonGuid.trim().isEmpty || !nas.isConfigured) return const [];
    try {
      final episodes = await FeiniuApi(nas).getEpisodeList(seasonGuid.trim());
      final service = DownloadTaskService.instance;
      // 原生壳无 NasProvider：封面给完整 NAS 图片 URL（转码流视频在 CDN，原生自拼会取错
      // origin）+ token（图片需 NAS 鉴权头）。
      final token = nas.token;
      String posterUrl(String raw) {
        if (raw.trim().isEmpty) return '';
        final candidates = ApiUrlHelper.imageCandidates(
          nas.baseUrl,
          raw,
          width: 320,
        );
        return candidates.isNotEmpty ? candidates.first : '';
      }

      return <Map<String, dynamic>>[
        for (final MediaLibraryItem ep in episodes)
          () {
            // 已下载的集优先用本地封面（file://，离线也能显示、无需 token）。
            final record = service.downloadedRecordForItem(ep.guid);
            final localCover = record != null
                ? service.resolveExistingLocalCover(record)
                : '';
            final usingLocal = localCover.isNotEmpty;
            return <String, dynamic>{
              'itemGuid': ep.guid,
              'episodeNumber': ep.episodeNumber,
              // Bug 1 fix(选集标题全变剧名)：用集自身标题 ep.title，displayTitle 会回退
              // 成 tvTitle(剧名)。去掉文件扩展名；原生壳 episodeLabel 再拼 "第N集"。
              'title': ep.title.trim().replaceAll(
                RegExp(
                  r'\.(mkv|mp4|m4v|avi|ts|flv|mov)$',
                  caseSensitive: false,
                ),
                '',
              ),
              'poster': usingLocal ? localCover : posterUrl(ep.poster),
              'imageAuth': usingLocal ? '' : token,
              'duration': ep.duration,
              'watched': ep.watched,
              'downloaded': record != null,
            };
          }(),
      ];
    } catch (_) {
      return const [];
    }
  }
}
