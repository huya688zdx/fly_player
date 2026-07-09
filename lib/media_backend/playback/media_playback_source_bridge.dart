import '../../l10n/generated/app_localizations.dart';
import '../../player/controllers/mpv_player_controller.dart';
import 'media_playback.dart';
import 'media_playback_resolution.dart';

/// 播放桥接结果。
///
/// [legacySidecar] 仅供飞牛遗留族把既有 PlayInfoData 继续传给旧 Flutter 播放器路径。
/// 服务器族后端应保持为空。
class MediaPlaybackSourceResult {
  final MpvMediaSource source;
  final Object? legacySidecar;

  const MediaPlaybackSourceResult({required this.source, this.legacySidecar});
}

/// 把后端中立播放事实装配成 mpv 最终 source 的桥接器。
///
/// 调用方只依赖本接口；具体 backend context 的 downcast 留在对应后端桥接器内部。
abstract interface class MediaPlaybackSourceBridge {
  Future<MediaPlaybackSourceResult> assemblePlaybackSource({
    required MediaPlaybackRequest request,
    required MediaPlaybackBundle bundle,
    required MediaPlaybackBackendContext? context,
    required AppLocalizations l10n,
  });
}
