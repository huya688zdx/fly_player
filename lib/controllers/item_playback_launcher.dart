import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../media_backend/feiniu/feiniu_media_backend.dart';
import '../media_backend/feiniu/feiniu_playback_context.dart';
import '../media_backend/playback/media_playback.dart';
import '../player/controllers/feiniu_playback_source_bridge.dart';
import '../controllers/play_detail_data_loader.dart';
import '../danmaku/settings/danmaku_settings_store.dart';
import '../services/native_danmaku_prefetch.dart';
import '../services/native_player_bridge.dart';
import '../services/native_reentry_support.dart';
import '../models/play_info.dart';
import '../player/controllers/mpv_player_controller.dart';
import '../player/mpv_player_page.dart';
import '../providers/nas_provider.dart';
import '../services/embedded_detail_launcher.dart';
import '../services/play_stats/play_stats.dart';
import '../ui/app_transitions.dart';
import '../utils/api_url_helper.dart';
import '../utils/async_action_guard.dart';
import '../controllers/local_download_source_resolver.dart';
import '../models/media_library_item.dart';
import '../services/download_task_service.dart';

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
    // B-2：单条目播放解析改走后端中立 getPlayback + 飞牛桥接器装配 MpvMediaSource。
    // 本地下载优先仍在 resolveForNative()；TV launcher / 原生反向通道 / 进度写回不变。
    // overrideSubtitleGuid 三态映射到公共 request：null=默认，''=显式关闭，其余=指定轨。
    final request = MediaPlaybackRequest(
      itemId: itemGuid,
      fallbackTitle: fallbackTitle,
      startFromBeginning: startFromBeginning,
      resumePosition: resumePosition,
      qualityIndex: qualityIndex,
      qualityId: qualityMediaGuid,
      audioTrackId: overrideAudioGuid,
      subtitleTrackId:
          (overrideSubtitleGuid != null && overrideSubtitleGuid.isNotEmpty)
          ? overrideSubtitleGuid
          : null,
      subtitleTrackExplicitlyDisabled: overrideSubtitleGuid == '',
    );

    final backend = FeiniuMediaBackend(FeiniuApi(nas));
    final resolution = await backend.getPlayback(request);
    final context = resolution.backendContext;
    if (context is! FeiniuPlaybackContext) return null;

    final source = await const FeiniuPlaybackSourceBridge().assemble(
      request: request,
      bundle: resolution.bundle,
      context: context,
    );
    return (source: source, playInfo: context.playInfo, title: source.title);
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
