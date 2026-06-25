import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../media_backend/emby/emby_playback_context.dart';
import '../media_backend/feiniu/feiniu_media_backend.dart';
import '../media_backend/feiniu/feiniu_playback_context.dart';
import '../media_backend/media_backend.dart';
import '../media_backend/media_backend_kind.dart';
import '../media_backend/playback/media_playback.dart';
import '../player/controllers/emby_playback_source_bridge.dart';
import '../player/controllers/feiniu_playback_source_bridge.dart';
import '../providers/media_backend_provider.dart';
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
    // 详情页已选的版本 / 音轨 / 字幕（Emby 多版本起播用；飞牛调用方不传，保持旧默认解析）。
    String? qualityMediaGuid,
    String? audioTrackId,
    String? subtitleTrackId,
  }) async {
    return AsyncActionGuard.run<PlayDetailPlayerReturnData?>(
      'item_playback:${itemGuid.trim()}:${startFromBeginning ? 'restart' : 'default'}',
      settleDuration: const Duration(milliseconds: 500),
      action: () async {
        final nas = context.read<NasProvider>();
        // 后端中立：取当前活动后端（飞牛 / Emby），按其上下文类型分发桥接器。飞牛会话下
        // 返回的就是 FeiniuMediaBackend(FeiniuApi(nasProvider))，与旧直接构造等价、零回归。
        final backend = context.read<MediaBackendProvider>().backend;
        final isFeiniu = backend.capabilities.kind == MediaBackendKind.feiniu;
        final resolved = await _resolve(
          backend,
          itemGuid: itemGuid,
          fallbackTitle: fallbackTitle,
          startFromBeginning: startFromBeginning,
          resumePosition: resumePosition,
          qualityMediaGuid: qualityMediaGuid,
          overrideAudioGuid: audioTrackId,
          overrideSubtitleGuid: subtitleTrackId,
        );
        if (resolved == null) return null;
        final source = resolved.source;
        final playInfo = resolved.playInfo;
        final title = resolved.title;

        if (!context.mounted) return null;
        // 灰度：原生渲染器开启时走纯原生播放壳，并注册反向通道。飞牛绑全功能反向通道（画质
        // 切换 + 续播回写 + 选集）；Emby 绑最小反向通道（仅重解析，进度回写/选集首版不做）。
        // Emby 封面是 api_key 自鉴权直链，不走 NAS 鉴权预取，故 maybeLaunch 不传 nas。
        final danmakuSettings = await const DanmakuSettingsStore().load();
        if (danmakuSettings.useNativeRenderer) {
          if (isFeiniu) {
            _bindReentry(nas, fallbackTitle: fallbackTitle);
            if (await NativePlayerBridge.maybeLaunch(
              source.toMap(),
              nas: nas,
            )) {
              return null;
            }
          } else {
            _bindEmbyReentry(backend, fallbackTitle: fallbackTitle);
            if (await NativePlayerBridge.maybeLaunch(source.toMap())) {
              return null;
            }
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
            // 单条目无选集，序号/画质继承不适用；声明以匹配桥接器函数类型。
            audioTrackIndex,
            subtitleTrackIndex,
            preferredQualityResolution,
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
      onReloadServerSession: (currentLoadArgs, intent) =>
          NativeReentrySupport.reloadServerSession(
            nas,
            currentLoadArgs: currentLoadArgs,
            intent: intent,
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

  /// 注册 Emby 最小反向通道（捕获活动后端，脱离 widget context）。首版只接「重解析」——
  /// 进度回写 / 选集 / 服务端会话重载 Emby 首版不做（电影单条目不触发），故余下回调不绑，
  /// 用最小绑定替换掉可能残留的飞牛回调（bindReentry 以最近一次为准）。
  void _bindEmbyReentry(MediaBackend backend, {String fallbackTitle = ''}) {
    NativePlayerBridge.bindReentry(
      onResolvePlayback:
          (
            itemGuid, {
            qualityIndex,
            qualityMediaGuid,
            startPositionMs,
            subtitleGuid,
            audioGuid,
            audioTrackIndex,
            subtitleTrackIndex,
            preferredQualityResolution,
          }) => _resolveEmbyForNative(
            backend,
            itemGuid: itemGuid,
            fallbackTitle: fallbackTitle,
            qualityMediaGuid: qualityMediaGuid,
            startPositionMs: startPositionMs,
            subtitleGuid: subtitleGuid,
            audioGuid: audioGuid,
          ),
      onRecordProgress: (progress) => _reportEmbyProgress(backend, progress),
    );
  }

  /// 原生壳回传进度 → Emby `/Sessions/Playing/Progress`（更新续播位）。best-effort：
  /// 断网 / 令牌过期静默吞，不阻断播放。progress 的 `ts` 为秒、`itemGuid`/`mediaGuid` 为
  /// Emby itemId / MediaSourceId（桥接器装进 MpvMediaSource、原生壳原样回传）。
  Future<void> _reportEmbyProgress(
    MediaBackend backend,
    Map<String, dynamic> progress,
  ) async {
    final itemGuid = (progress['itemGuid'] ?? '').toString().trim();
    if (itemGuid.isEmpty) return;
    final mediaGuid = (progress['mediaGuid'] ?? '').toString().trim();
    final ts = (progress['ts'] as num?)?.toInt() ?? 0;
    try {
      await backend.reportPlaybackProgress(
        itemId: itemGuid,
        mediaSourceId: mediaGuid,
        positionSeconds: ts,
      );
    } catch (_) {}
  }

  /// Emby 原生壳重解析：按指定版本/轨道重解析 source、回传 loadArgs（无飞牛 PlayInfo / 弹幕）。
  Future<Map<String, dynamic>?> _resolveEmbyForNative(
    MediaBackend backend, {
    required String itemGuid,
    String fallbackTitle = '',
    String? qualityMediaGuid,
    int? startPositionMs,
    String? subtitleGuid,
    String? audioGuid,
  }) async {
    final resolved = await _resolve(
      backend,
      itemGuid: itemGuid,
      fallbackTitle: fallbackTitle,
      qualityMediaGuid: qualityMediaGuid,
      overrideSubtitleGuid: subtitleGuid,
      overrideAudioGuid: audioGuid,
    );
    if (resolved == null) return null;
    final loadArgs = <String, dynamic>{
      ...resolved.source.toMap(),
      if (startPositionMs != null) 'startPositionMs': startPositionMs,
    };
    return <String, dynamic>{'loadArgs': jsonEncode(loadArgs)};
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
        // 原生壳画质切换反向通道目前仅飞牛走（Emby 用最小反向通道 _resolveEmbyForNative）。
        final resolved = await _resolve(
          FeiniuMediaBackend(FeiniuApi(nas)),
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
  ///
  /// 后端中立：用传入的活动后端 [backend] 调 `getPlayback`，按返回的不透明上下文运行时类型
  /// 分发桥接器——飞牛 → [FeiniuPlaybackSourceBridge]（playInfo 为飞牛 PlayInfoData）；
  /// Emby → [EmbyPlaybackSourceBridge]（无 PlayInfoData，playInfo 为 null）。
  /// overrideSubtitleGuid 三态映射到公共 request：null=默认，''=显式关闭，其余=指定轨。
  Future<({MpvMediaSource source, PlayInfoData? playInfo, String title})?>
  _resolve(
    MediaBackend backend, {
    required String itemGuid,
    String fallbackTitle = '',
    bool startFromBeginning = false,
    Duration? resumePosition,
    int? qualityIndex,
    String? qualityMediaGuid,
    String? overrideSubtitleGuid,
    String? overrideAudioGuid,
  }) async {
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

    final resolution = await backend.getPlayback(request);
    final context = resolution.backendContext;
    if (context is FeiniuPlaybackContext) {
      final source = await const FeiniuPlaybackSourceBridge().assemble(
        request: request,
        bundle: resolution.bundle,
        context: context,
      );
      return (source: source, playInfo: context.playInfo, title: source.title);
    }
    if (context is EmbyPlaybackContext) {
      final source = await const EmbyPlaybackSourceBridge().assemble(
        request: request,
        bundle: resolution.bundle,
      );
      return (source: source, playInfo: null, title: source.title);
    }
    return null;
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
