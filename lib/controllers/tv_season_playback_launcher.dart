import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../media_backend/emby/emby_playback_context.dart';
import '../media_backend/feiniu/feiniu_playback_context.dart';
import '../media_backend/media_backend.dart';
import '../media_backend/media_backend_kind.dart';
import '../media_backend/playback/media_playback.dart';
import '../player/controllers/emby_playback_source_bridge.dart';
import '../player/controllers/feiniu_playback_source_bridge.dart';
import '../providers/media_backend_provider.dart';
import '../controllers/local_download_source_resolver.dart';
import '../controllers/play_detail_data_loader.dart';
import '../danmaku/settings/danmaku_settings_store.dart';
import '../services/download_task_service.dart';
import '../services/native_danmaku_prefetch.dart';
import '../services/native_player_bridge.dart';
import '../models/play_info.dart';
import '../player/controllers/mpv_player_controller.dart';
import '../player/mpv_player_page.dart';
import '../providers/nas_provider.dart';
import '../services/embedded_detail_launcher.dart';
import '../services/play_stats/play_stats.dart';
import '../ui/app_transitions.dart';
import '../utils/async_action_guard.dart';

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
        // 后端中立：取活动后端，按 context 类型分发桥接器（与单条目 launcher 同口径）。
        final backend = context.read<MediaBackendProvider>().backend;
        final isFeiniu = backend.capabilities.kind == MediaBackendKind.feiniu;
        final resolved = await _resolveWithProvider(
          backend,
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
        // 返回 true 表示已交给原生壳，不再 push Flutter 播放器。Emby 封面 api_key 自鉴权直链，
        // 不走 NAS 鉴权预取，故不传 nas。
        if (await NativePlayerBridge.maybeLaunch(
          source.toMap(),
          episodes: episodes,
          nas: isFeiniu ? provider : null,
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
    int? audioTrackIndex,
    int? subtitleTrackIndex,
    String? preferredQualityResolution,
  }) async {
    return AsyncActionGuard.run<Map<String, dynamic>?>(
      'tv_season_resolve:${itemGuid.trim()}',
      settleDuration: const Duration(milliseconds: 300),
      action: () async {
        // Bug fix(季页面播下载集走网络)：有本地下载记录时优先播本地文件。
        // qualityIndex 非空为切画质请求，本地文件无多画质，跳过走 NAS 重新解析。
        // context.read 在第一个 await 之前捕获，避免 async gap 警告。
        final provider = context.read<NasProvider>();
        // 后端中立：取活动后端分发桥接器。本地下载优先仅飞牛（Emby 无下载能力）。
        final backend = context.read<MediaBackendProvider>().backend;
        final isFeiniu = backend.capabilities.kind == MediaBackendKind.feiniu;
        if (isFeiniu && qualityIndex == null) {
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
          backend,
          itemGuid: itemGuid,
          seriesTitle: seriesTitle,
          seriesGuid: seriesGuid,
          qualityIndex: qualityIndex,
          qualityMediaGuid: qualityMediaGuid,
          overrideSubtitleGuid: subtitleGuid,
          overrideAudioGuid: audioGuid,
          audioTrackIndex: audioTrackIndex,
          subtitleTrackIndex: subtitleTrackIndex,
          preferredQualityResolution: preferredQualityResolution,
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
  ///
  /// 后端中立：用传入的活动后端 [backend] 调 `getPlayback`，按返回的不透明上下文运行时类型
  /// 分发桥接器——飞牛 → [FeiniuPlaybackSourceBridge]（playInfo 为飞牛 PlayInfoData）；
  /// Emby → [EmbyPlaybackSourceBridge]（无 PlayInfoData，playInfo 为 null）。
  Future<({MpvMediaSource source, PlayInfoData? playInfo, String title})?>
  _resolveWithProvider(
    MediaBackend backend, {
    required String itemGuid,
    required String seriesTitle,
    required String seriesGuid,
    int? qualityIndex,
    String? qualityMediaGuid,
    String? overrideSubtitleGuid,
    String? overrideAudioGuid,
    int? audioTrackIndex,
    int? subtitleTrackIndex,
    String? preferredQualityResolution,
  }) async {
    // B-3：季/集播放解析改走后端中立 getPlayback + 飞牛桥接器装配 MpvMediaSource。
    // 与 B-2 单条目共用桥接器；TV 特有的两点经中立 request 字段表达：
    //   - seriesId：调用方显式剧集 guid 优先（桥接器回退 grandGuid）；
    //   - restartWhenCompleted=true：已看完的一集重新点播回到开头。
    // seriesTitle 同时充当 title 与 seriesTitle 字段回退，映射到 request.fallbackTitle。
    // 本地下载优先仍在 resolveForNative()；页面侧反向通道 / 弹幕预取 / 选集均不变。
    // overrideSubtitleGuid 三态映射到公共 request：null=默认，''=显式关闭，其余=指定轨。
    // 切集按序号继承轨道（Bug B）：native 传当前音轨/字幕序号；字幕 -1 = 继承「关闭」。
    final inheritSubtitleOff = subtitleTrackIndex == -1;
    final request = MediaPlaybackRequest(
      itemId: itemGuid,
      fallbackTitle: seriesTitle,
      seriesId: seriesGuid,
      restartWhenCompleted: true,
      qualityIndex: qualityIndex,
      qualityId: qualityMediaGuid,
      audioTrackId: overrideAudioGuid,
      subtitleTrackId:
          (overrideSubtitleGuid != null && overrideSubtitleGuid.isNotEmpty)
          ? overrideSubtitleGuid
          : null,
      subtitleTrackExplicitlyDisabled:
          overrideSubtitleGuid == '' || inheritSubtitleOff,
      preferredAudioTrackIndex:
          (audioTrackIndex != null && audioTrackIndex >= 0)
          ? audioTrackIndex
          : null,
      preferredSubtitleTrackIndex:
          (subtitleTrackIndex != null && subtitleTrackIndex >= 0)
          ? subtitleTrackIndex
          : null,
      preferredQualityResolution: preferredQualityResolution ?? '',
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
}
