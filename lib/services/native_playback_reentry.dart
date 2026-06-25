import 'dart:async';

import '../media_backend/media_backend.dart';
import '../media_backend/media_backend_kind.dart';
import '../providers/nas_provider.dart';
import 'emby_native_picker_support.dart';
import 'native_player_bridge.dart';
import 'native_reentry_support.dart';

/// 原生壳 `onResolvePlayback` 回调签名（与 [NativePlayerBridge.bindReentry] 一致）。
typedef ResolvePlaybackHandler =
    Future<Map<String, dynamic>?> Function(
      String itemGuid, {
      int? qualityIndex,
      String? qualityMediaGuid,
      int? startPositionMs,
      String? subtitleGuid,
      String? audioGuid,
      int? audioTrackIndex,
      int? subtitleTrackIndex,
      String? preferredQualityResolution,
    });

/// 统一原生壳反向通道注册——所有播放入口的单一接线点。
///
/// 各入口（单条目 / 季详情 / 剧详情 / 下载）曾各自调 [NativePlayerBridge.bindReentry] 并按
/// 后端类型重复接线：飞牛接 [NativeReentrySupport]、Emby 接 [EmbyNativePickerSupport]+backend。
/// 重复的 9 个回调样板散落多处、且每个入口绑的回调集不一致（有的漏选集、有的漏进度回写），
/// 导致「从某入口进播放没选集 / 没进度」这类按入口而异的缺陷。
///
/// 这里把「回调 → 后端实现」的映射收成**单一事实源**：调用方只给 [onResolvePlayback]（各入口
/// 的重解析逻辑，本就因入口而异）+ 可选 [fallbackEpisodes]，其余标准回调（进度回写 / 外挂字幕 /
/// 服务端会话重载 / 选集三件套）按 [backend] 类型统一接线。
///
/// - 飞牛：与各入口原本逐一绑定的回调等价（零行为变化，主路径逐像素不变）。
/// - Emby：每个入口都获得**完整**回调集（进度回写 + 选集 + 跨季 + 外挂字幕），消除入口间不一致。
///   Emby 直链直播无服务端转码会话，故不绑 `onReloadServerSession`（原生壳侧回退、不切转码档）。
class NativePlaybackReentry {
  const NativePlaybackReentry._();

  /// 注册反向通道，返回持有者 token（dispose 时传给 [NativePlayerBridge.unbindReentry]）。
  ///
  /// [nas] 供飞牛回调捕获（Emby 分支忽略）；[fallbackEpisodes] 为选集面板静态兜底列表
  /// （季/剧详情入口提供本季列表，单条目入口可省——选集数据由后端按 seriesGuid 派生）。
  static Object bind({
    required MediaBackend backend,
    required NasProvider nas,
    required ResolvePlaybackHandler onResolvePlayback,
    List<Map<String, dynamic>> Function()? fallbackEpisodes,
  }) {
    if (backend.capabilities.kind == MediaBackendKind.feiniu) {
      return NativePlayerBridge.bindReentry(
        onResolvePlayback: onResolvePlayback,
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
              fallbackEpisodes:
                  fallbackEpisodes?.call() ?? const <Map<String, dynamic>>[],
            ),
        onLoadSeasonEpisodes: (seasonGuid) =>
            NativeReentrySupport.loadSeasonEpisodes(
              nas,
              seasonGuid: seasonGuid,
            ),
        onSetEpisodePickerViewType: (viewType) =>
            NativeReentrySupport.setEpisodePickerViewType(nas, viewType),
      );
    }
    return NativePlayerBridge.bindReentry(
      onResolvePlayback: onResolvePlayback,
      onRecordProgress: (progress) => _reportEmbyProgress(backend, progress),
      onResolveSubtitleFile: (guid, {format}) =>
          backend.resolveExternalSubtitleFile(guid, format: format),
      onLoadEpisodePickerData: (currentLoadArgs, {seasonGuid}) =>
          EmbyNativePickerSupport.loadEpisodePickerData(
            backend,
            currentLoadArgs: currentLoadArgs,
            seasonGuid: seasonGuid ?? '',
            fallbackEpisodes:
                fallbackEpisodes?.call() ?? const <Map<String, dynamic>>[],
          ),
      onLoadSeasonEpisodes: (seasonGuid) =>
          EmbyNativePickerSupport.loadSeasonEpisodes(
            backend,
            seasonGuid: seasonGuid,
          ),
      onSetEpisodePickerViewType: (viewType) =>
          EmbyNativePickerSupport.setEpisodePickerViewType(viewType),
    );
  }

  /// Emby 原生壳回传进度 → `/Sessions/Playing/Progress`（更新续播位）。best-effort：断网 /
  /// 令牌过期静默吞，不阻断播放。progress 的 `ts` 为秒、`itemGuid`/`mediaGuid` 为 Emby
  /// itemId / MediaSourceId（桥接器装进 MpvMediaSource、原生壳原样回传）。
  static Future<void> _reportEmbyProgress(
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
}
