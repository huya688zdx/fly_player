import 'dart:async';

import '../l10n/generated/app_localizations.dart';
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
    required AppLocalizations l10n,
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
              l10n: l10n,
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
    // 每次 bind 建一个有状态的进度上报器：Emby 须先 PlaybackStart 建会话进度才持久化，
    // 故首帧进度先开会话；切集时停旧会话 + 开新会话。状态随 bind 闭包（每次起播独立）。
    final reporter = EmbyPlaybackReporter(backend);
    return NativePlayerBridge.bindReentry(
      onResolvePlayback: onResolvePlayback,
      onRecordProgress: reporter.report,
      onResolveSubtitleFile: (guid, {format}) =>
          backend.resolveExternalSubtitleFile(guid, format: format),
      onLoadEpisodePickerData: (currentLoadArgs, {seasonGuid}) =>
          EmbyNativePickerSupport.loadEpisodePickerData(
            backend,
            l10n: l10n,
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
}

/// Emby 进度上报器（每次 bind 一个实例，持当前播放会话状态）。
///
/// Emby 须先 `PlaybackStart` 建会话，之后 `Progress` 才被持久化（见 [EmbyApi.reportPlaybackStart]）。
/// 故首次收到某条目进度时先开会话；原生壳壳内切集（itemGuid 变）时停旧会话 + 开新会话，使每集
/// 的续播位都正确落定。原生壳无显式「播放结束」信号，最终停止不主动 Stopped——但末次 Progress
/// 已落定续播位、会话已注册，继续观看正常。progress 的 `ts` 为秒、`itemGuid`/`mediaGuid` 为 Emby
/// itemId / MediaSourceId（桥接器装进 MpvMediaSource、原生壳原样回传）。best-effort：静默吞错。
class EmbyPlaybackReporter {
  EmbyPlaybackReporter(this.backend);

  final MediaBackend backend;
  String _itemId = '';
  String _mediaId = '';
  int _lastTs = 0;

  Future<void> report(Map<String, dynamic> progress) async {
    final itemGuid = (progress['itemGuid'] ?? '').toString().trim();
    if (itemGuid.isEmpty) return;
    final mediaGuid = (progress['mediaGuid'] ?? '').toString().trim();
    final ts = (progress['ts'] as num?)?.toInt() ?? 0;
    try {
      if (itemGuid != _itemId) {
        // 切到新条目：先停旧会话（落定旧条目最终位），再为新条目开会话。
        if (_itemId.isNotEmpty) {
          await backend.reportPlaybackStopped(
            itemId: _itemId,
            mediaSourceId: _mediaId,
            positionSeconds: _lastTs,
          );
        }
        _itemId = itemGuid;
        await backend.reportPlaybackStart(
          itemId: itemGuid,
          mediaSourceId: mediaGuid,
          positionSeconds: ts,
        );
      }
      _mediaId = mediaGuid;
      _lastTs = ts;
      await backend.reportPlaybackProgress(
        itemId: itemGuid,
        mediaSourceId: mediaGuid,
        positionSeconds: ts,
      );
    } catch (_) {}
  }
}
