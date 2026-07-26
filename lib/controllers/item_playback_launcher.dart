import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../l10n/generated/app_localizations.dart';
import '../media_backend/media_backend.dart';
import '../media_backend/media_backend_registry.dart';
import '../media_backend/playback/media_playback.dart';
import '../providers/media_backend_provider.dart';
import '../controllers/play_detail_data_loader.dart';
import '../danmaku/settings/danmaku_settings_store.dart';
import '../services/native_danmaku_prefetch.dart';
import '../services/native_playback_reentry.dart';
import '../services/native_player_bridge.dart';
import '../services/server_native_picker_support.dart';
import '../models/play_info.dart';
import '../playback/native_playback_host.dart';
import '../playback/playback_source.dart';
import '../providers/nas_provider.dart';
import '../theme/app_theme.dart';
import '../utils/api_url_helper.dart';
import '../utils/async_action_guard.dart';
import '../utils/detail_top_tip.dart';
import '../controllers/local_download_source_resolver.dart';
import '../models/media_library_item.dart';
import '../services/download_task_service.dart';

/// 负责从条目详情上下文构建并拉起播放器。
class ItemPlaybackLauncher {
  static final DetailTopTip _topTip = DetailTopTip();

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
        final l10n = AppLocalizations.of(context);
        final nas = context.read<NasProvider>();
        // 后端中立：取当前活动后端，由后端自己的桥接器装配最终播放 source。飞牛会话下
        // 返回的就是 FeiniuMediaBackend(FeiniuApi(nasProvider))，与旧直接构造等价、零回归。
        final backend = context.read<MediaBackendProvider>().backend;
        final isFeiniu = backend.capabilities.usesLegacyFeiniuFlow;
        final resolved = await _resolve(
          backend,
          itemGuid: itemGuid,
          l10n: l10n,
          fallbackTitle: fallbackTitle,
          startFromBeginning: startFromBeginning,
          resumePosition: resumePosition,
          qualityMediaGuid: qualityMediaGuid,
          overrideAudioGuid: audioTrackId,
          overrideSubtitleGuid: subtitleTrackId,
        );
        if (resolved == null) return null;
        final source = resolved.source;

        if (!context.mounted) return null;
        // 灰度：原生渲染器开启时走纯原生播放壳，经统一 binder 注册反向通道——飞牛绑全功能、
        // Emby 绑完整回调集（进度/选集/外挂字幕），由 NativePlaybackReentry 按后端统一接线。
        // 单条目无选集静态兜底（剧集的选集数据由后端按 loadArgs 的 seriesGuid 派生）；
        // onResolvePlayback 按后端走各自重解析（飞牛带本地下载+弹幕，Emby 直链重解析）。
        if (NativePlayerBridge.preferNativePlayerShell) {
          NativePlaybackReentry.bind(
            backend: backend,
            nas: nas,
            l10n: l10n,
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
                }) => isFeiniu
                ? resolveForNative(
                    nas,
                    backend: backend,
                    itemGuid: itemGuid,
                    fallbackTitle: fallbackTitle,
                    qualityIndex: qualityIndex,
                    qualityMediaGuid: qualityMediaGuid,
                    startPositionMs: startPositionMs,
                    subtitleGuid: subtitleGuid,
                    audioGuid: audioGuid,
                    l10n: l10n,
                  )
                : _resolveServerForNative(
                    backend,
                    itemGuid: itemGuid,
                    fallbackTitle: fallbackTitle,
                    qualityMediaGuid: qualityMediaGuid,
                    startPositionMs: startPositionMs,
                    subtitleGuid: subtitleGuid,
                    audioGuid: audioGuid,
                    l10n: l10n,
                  ),
          );
          // 服务器族单集起播：带上本季 episodes，否则原生壳「选集 / 下一集」不亮（壳侧靠
          // loadArgs.episodes 渲染选集面板 + 算下一集；空则预取被跳过、回调不触发）。
          // 飞牛单集走 _launchPlayer 自带 episodes，故此处只为服务器族加载。
          final serverEpisodes = isFeiniu
              ? null
              : await _serverNativeEpisodes(backend, source);
          // 服务器族封面由后端给出可直接消费的 URL，不走 NAS 鉴权预取，故只飞牛传 nas。
          if (await const NativePlaybackHost().launch(
            source: source,
            episodes: serverEpisodes,
            nas: isFeiniu ? nas : null,
          )) {
            return null;
          }
        }
        if (!context.mounted) return null;
        if (context.mounted) {
          _topTip.show(
            context,
            message: l10n.detailPlayInfoFailed,
            color: context.appColors.danger,
          );
        }
        return null;
      },
    );
  }

  /// 服务器族原生壳重解析：按指定版本/轨道重解析 source、回传 loadArgs（无飞牛 PlayInfo）。
  /// 单集回传时带上本季 episodes——否则壳内切集后「选集 / 下一集」会清空。
  ///
  /// 弹幕：与 `maybeLaunch`/`TvSeasonPlaybackLauncher.resolveForNative` 对齐，切集也要按新集
  /// 重取弹幕。否则壳内切集走这条路只解析视频、不取弹幕——表现为「首次起播有弹幕、壳内切集没」，
  /// 且切回已匹配过的老集也不挂载（resolveToFile 第1步按 mediaKey 命中 active 源会恢复）。
  Future<Map<String, dynamic>?> _resolveServerForNative(
    MediaBackend backend, {
    required String itemGuid,
    required AppLocalizations l10n,
    String fallbackTitle = '',
    String? qualityMediaGuid,
    int? startPositionMs,
    String? subtitleGuid,
    String? audioGuid,
  }) async {
    final resolved = await _resolve(
      backend,
      itemGuid: itemGuid,
      l10n: l10n,
      fallbackTitle: fallbackTitle,
      qualityMediaGuid: qualityMediaGuid,
      overrideSubtitleGuid: subtitleGuid,
      overrideAudioGuid: audioGuid,
    );
    if (resolved == null) return null;
    final episodes = await _serverNativeEpisodes(backend, resolved.source);
    final loadArgs = <String, dynamic>{
      ...resolved.source.toMap(),
      if (episodes != null && episodes.isNotEmpty) 'episodes': episodes,
      if (startPositionMs != null) 'startPositionMs': startPositionMs,
    };
    // 弹幕预取（与 resolveForNative 内逻辑一致，resolveToFile 内部按 settings.enabled 判断）。
    final settings = await const DanmakuSettingsStore().load();
    final danmakuFile = await NativeDanmakuPrefetch.resolveToFile(
      seriesTitle: (loadArgs['seriesTitle'] ?? '').toString(),
      itemTitle: (loadArgs['title'] ?? '').toString(),
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
  }

  /// 服务器族单集起播 / 切集：加载本季选集映射成原生壳选集行，点亮壳内「选集 / 下一集」。非单集
  /// 或无 seasonGuid 返回 null（电影 / 单视频无选集）。失败静默（壳侧回退无选集）。
  Future<List<Map<String, dynamic>>?> _serverNativeEpisodes(
    MediaBackend backend,
    MpvMediaSource source,
  ) async {
    if (source.mediaType.toLowerCase() != 'episode') return null;
    final seasonGuid = source.seasonGuid.trim();
    if (seasonGuid.isEmpty) return null;
    try {
      final episodes = await backend.getSeasonEpisodes(seasonGuid);
      if (episodes.isEmpty) return null;
      return ServerNativePickerSupport.nativeEpisodePayload(
        episodes,
        seasonGuid,
      );
    } catch (_) {
      return null;
    }
  }

  /// 只解析（不启动 Activity）：原生壳画质切换时回到这里重解析指定档，回传 loadArgs+弹幕。
  Future<Map<String, dynamic>?> resolveForNative(
    NasProvider nas, {
    MediaBackend? backend,
    required String itemGuid,
    String fallbackTitle = '',
    int? qualityIndex,
    String? qualityMediaGuid,
    int? startPositionMs,
    String? subtitleGuid,
    String? audioGuid,
    List<Map<String, dynamic>>? episodes,
    required AppLocalizations l10n,
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
              l10n: l10n,
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
                itemTitle: (loadArgs['title'] ?? '').toString(),
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
        // 原生壳画质切换反向通道目前仅飞牛走（服务器族用最小反向通道 _resolveServerForNative）。
        final resolved = await _resolve(
          backend ?? MediaBackendRegistry.createLegacyFeiniu(nas),
          itemGuid: itemGuid,
          fallbackTitle: fallbackTitle,
          qualityIndex: qualityIndex,
          qualityMediaGuid: qualityMediaGuid,
          overrideSubtitleGuid: subtitleGuid,
          overrideAudioGuid: audioGuid,
          l10n: l10n,
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
          itemTitle: (loadArgs['title'] ?? '').toString(),
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
  /// 后端中立：用传入的活动后端 [backend] 调 `getPlayback`，再交给后端自己的桥接器装配。
  /// overrideSubtitleGuid 三态映射到公共 request：null=默认，''=显式关闭，其余=指定轨。
  Future<({MpvMediaSource source, PlayInfoData? playInfo, String title})?>
  _resolve(
    MediaBackend backend, {
    required String itemGuid,
    required AppLocalizations l10n,
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
    final assembled = await backend.playbackSourceBridge.assemblePlaybackSource(
      request: request,
      bundle: resolution.bundle,
      context: resolution.backendContext,
      l10n: l10n,
    );
    final source = assembled.source;
    final playInfo = assembled.legacySidecar;
    return (
      source: source,
      playInfo: playInfo is PlayInfoData ? playInfo : null,
      title: source.title,
    );
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

      // 已下载的集优先用本地封面（file://，离线也能显示、无需 token）。
      // 封面解析已改异步（目录扫描），这里按下标先并发解析一遍再组装，避免循环内串行 await。
      final records = episodes
          .map(
            (MediaLibraryItem ep) => service.downloadedRecordForItem(ep.guid),
          )
          .toList(growable: false);
      final localCovers = await Future.wait(<Future<String>>[
        for (final record in records)
          record == null
              ? Future<String>.value('')
              : service.resolveExistingLocalCover(record),
      ]);
      return <Map<String, dynamic>>[
        for (var index = 0; index < episodes.length; index++)
          () {
            final MediaLibraryItem ep = episodes[index];
            final record = records[index];
            final localCover = localCovers[index];
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
