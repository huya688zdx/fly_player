import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../controllers/local_download_source_resolver.dart';
import '../controllers/play_detail_data_loader.dart';
import '../danmaku/settings/danmaku_settings_store.dart';
import '../services/download_task_service.dart';
import '../services/native_danmaku_prefetch.dart';
import '../services/native_player_bridge.dart';
import '../models/play_info.dart';
import '../models/playback_stream.dart';
import '../player/controllers/mpv_player_controller.dart';
import '../player/mpv_player_page.dart';
import '../player/controllers/player_source_controller.dart';
import '../providers/nas_provider.dart';
import '../services/app_log_service.dart';
import '../services/embedded_detail_launcher.dart';
import '../services/play_stats/play_stats.dart';
import '../ui/app_transitions.dart';
import '../utils/app_error_reporter.dart';
import '../utils/app_exception.dart';
import '../utils/async_action_guard.dart';
import '../utils/player_artwork_path_resolver.dart';
import '../utils/playback_resume_position_resolver.dart';
import '../utils/player_title_formatter.dart';
import '../utils/play_detail_track_selector.dart';
import '../models/stream_track_data.dart';

/// 负责从季度列表上下文拉起播放器。
class TvSeasonPlaybackLauncher {
  /// 创建一个季度播放拉起器实例。
  const TvSeasonPlaybackLauncher();

  /// 加载播放数据并打开播放器页面。
  Future<PlayDetailPlayerReturnData?> open(
    BuildContext context, {
    required String itemGuid,
    required String seriesTitle,
    String seriesGuid = '',
    List<Map<String, dynamic>>? episodes,
  }) async {
    return AsyncActionGuard.run<PlayDetailPlayerReturnData?>(
      'tv_season_playback:${itemGuid.trim()}',
      settleDuration: const Duration(milliseconds: 500),
      action: () async {
        final provider = context.read<NasProvider>();
        final resolved = await _resolveWithProvider(
          provider,
          itemGuid: itemGuid,
          seriesTitle: seriesTitle,
          seriesGuid: seriesGuid,
        );
        if (resolved == null) return null;
        final source = resolved.source;
        final playInfo = resolved.playInfo;
        final title = resolved.title;

        if (!context.mounted) return null;
        // 灰度：原生渲染器开启时走纯原生播放壳（无 Hybrid Composition，弹幕丝滑、二级
        // 界面不卡）。maybeLaunch 内部判断开关 + 预取弹幕；episodes 透传供原生壳「选集」。
        // 返回 true 表示已交给原生壳，不再 push Flutter 播放器。
        if (await NativePlayerBridge.maybeLaunch(
          source.toMap(),
          episodes: episodes,
          nas: provider,
        )) {
          return null;
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

  /// 原生壳「选集」反向链路：仅解析新一集（不启动 Activity），把可播 loadArgs + 预取好的
  /// 弹幕文件路径回传给**已存在**的原生壳实例原地 `load` 换源。
  ///
  /// 关键：早期实现走 `open → NativePlayerBridge.launch → startActivity`，但 singleTask
  /// 在跨 task 重新 start 时被系统**重建** Activity（每次切集 onDestroy+releaseMpv+重建
  /// mpv），连续切集时多个 mpv/Vulkan surface 交叠直接闪退。改为「只解析、回传、原地换源」
  /// 后，Activity / mpv 实例全程复用，彻底消除重建。
  Future<Map<String, dynamic>?> resolveForNative(
    BuildContext context, {
    required String itemGuid,
    required String seriesTitle,
    String seriesGuid = '',
    List<Map<String, dynamic>>? episodes,
    int? qualityIndex,
    String? qualityMediaGuid,
    int? startPositionMs,
    String? subtitleGuid,
    String? audioGuid,
  }) async {
    return AsyncActionGuard.run<Map<String, dynamic>?>(
      'tv_season_resolve:${itemGuid.trim()}',
      settleDuration: const Duration(milliseconds: 300),
      action: () async {
        // Bug fix(季页面播下载集走网络)：有本地下载记录时优先播本地文件。
        // qualityIndex 非空为切画质请求，本地文件无多画质，跳过走 NAS 重新解析。
        // context.read 在第一个 await 之前捕获，避免 async gap 警告。
        final provider = context.read<NasProvider>();
        if (qualityIndex == null) {
          await DownloadTaskService.instance.initialize();
          final localRecord = DownloadTaskService.instance
              .downloadedRecordForItem(itemGuid.trim());
          if (localRecord != null) {
            final local = await resolveLocalDownloadSource(
              localRecord,
              provider,
              startPositionMs: startPositionMs,
            );
            if (local != null) {
              final loadArgs = <String, dynamic>{
                ...local.source.toMap(),
                if (episodes != null && episodes.isNotEmpty)
                  'episodes': episodes,
                if (startPositionMs != null) 'startPositionMs': startPositionMs,
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
        final resolved = await _resolveWithProvider(
          provider,
          itemGuid: itemGuid,
          seriesTitle: seriesTitle,
          seriesGuid: seriesGuid,
          qualityIndex: qualityIndex,
          qualityMediaGuid: qualityMediaGuid,
          overrideSubtitleGuid: subtitleGuid,
          overrideAudioGuid: audioGuid,
        );
        if (resolved == null) return null;
        final loadArgs = <String, dynamic>{
          ...resolved.source.toMap(),
          if (episodes != null && episodes.isNotEmpty) 'episodes': episodes,
          // 切画质：保持当前播放位置（覆盖按 NAS 续播位解析出的起点）。
          if (startPositionMs != null) 'startPositionMs': startPositionMs,
        };
        // 弹幕预取（与 maybeLaunch 内逻辑一致，resolveToFile 内部按 settings.enabled 判断）。
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
  /// 仅在开头同步读取一次 NasProvider，之后纯异步网络请求，不再触碰 context。
  Future<({MpvMediaSource source, PlayInfoData playInfo, String title})?>
  _resolveWithProvider(
    NasProvider provider, {
    required String itemGuid,
    required String seriesTitle,
    required String seriesGuid,
    int? qualityIndex,
    String? qualityMediaGuid,
    String? overrideSubtitleGuid,
    String? overrideAudioGuid,
  }) async {
    final api = FeiniuApi(provider);
    final playInfo = await api.getPlayInfo(itemGuid);
    StreamTrackData? trackData;
    try {
      trackData = await api.getStreamTrackData(itemGuid);
    } catch (error, stackTrace) {
      unawaited(
        AppErrorReporter.report(
          error,
          action: 'load stream track data',
          source: 'tv_season_playback_launcher',
          stackTrace: stackTrace,
          fallbackKind: AppExceptionKind.noData,
          level: AppLogLevel.warning,
          details: 'itemGuid=$itemGuid',
        ),
      );
    }
    final playbackStream = await api.getPlaybackStream(playInfo.mediaGuid);
    final mergedQualities = mergePlaybackQualitiesWithStreamTrackData(
      playbackStream.qualities,
      trackData,
    );
    PlaybackQualityOption? initialQuality;
    final normalizedQualityMediaGuid = qualityMediaGuid?.trim() ?? '';
    if (normalizedQualityMediaGuid.isNotEmpty) {
      for (final quality in mergedQualities) {
        if (quality.mediaGuid.trim() == normalizedQualityMediaGuid) {
          initialQuality = quality;
          break;
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

    final selectedAudio = PlayDetailTrackSelector.selectedOrFirstAudio(
      selectedAudioGuid: overrideAudioGuid?.trim().isNotEmpty == true
          ? overrideAudioGuid
          : playInfo.audioGuid,
      audioTracks: playbackStream.audioStreams,
    );
    final subtitleTracks = PlayDetailTrackSelector.mergeSubtitleTracks(
      primaryTracks: playbackStream.subtitleStreams,
      extraTracks: trackData?.subtitlesForMedia(playInfo.mediaGuid) ?? const [],
    );
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

    final effectiveDuration = playInfo.item.duration;
    final sourceTs = playInfo.ts > 0 ? playInfo.ts : playInfo.item.watchedTs;
    final playbackCompleted =
        effectiveDuration > 0 &&
        ((effectiveDuration - sourceTs) <= 0 || playInfo.item.isWatched == 1);
    final resume = await PlaybackResumePositionResolver.resolve(
      videoIds: <String>[playInfo.item.guid, itemGuid],
      durationSeconds: effectiveDuration,
      networkPositionSeconds: sourceTs,
      networkPositionAvailable: true,
      networkCompleted: playbackCompleted,
    );
    final effectiveTs = resume.position.inSeconds;
    final initialPlayback = await const PlayerSourceController()
        .buildInitialPlaybackResult(
          api: api,
          directUrl: api.getStreamUrl(playInfo.mediaGuid),
          mediaGuid: playInfo.mediaGuid,
          videoGuid: playbackVideoGuid,
          playbackStream: playbackStream,
          quality: initialQuality,
          selectedAudio: selectedAudio,
          selectedSubtitle: selectedSubtitle,
          startPosition: Duration(seconds: effectiveTs),
        );
    final playableSource = initialPlayback.playableSource;
    final resolvedStartPosition =
        !playableSource.reliableSeek && effectiveTs > 0
        ? Duration.zero
        : resume.position;
    final title = formatPlayerTitleFromPlayItem(
      playInfo.item,
      fallbackTitle: seriesTitle,
    );

    final source = MpvMediaSource(
      loadNonce: createMpvLoadNonce(),
      itemGuid: playInfo.item.guid,
      seriesGuid: seriesGuid.trim().isNotEmpty
          ? seriesGuid.trim()
          : playInfo.grandGuid.trim(),
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
          : seriesTitle,
      seasonNumber: playInfo.item.seasonNumber,
      tmdbId: playInfo.item.trimId,
      episodeNumber: playInfo.item.episodeNumber,
      startPosition: resolvedStartPosition,
      audioTrackIndex: selectedAudio?.index,
      subtitleTrackIndex: embeddedSubtitleTrackIndex,
      audioTrackGuid: selectedAudio?.guid ?? playInfo.audioGuid,
      subtitleTrackGuid:
          selectedSubtitle?.guid ??
          (overrideSubtitleGuid ?? playInfo.subtitleGuid),
      resolution: playbackResolution,
      bitrate: playbackBitrate,
      durationSeconds: effectiveDuration,
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
}
