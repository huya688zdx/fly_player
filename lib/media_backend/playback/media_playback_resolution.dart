import 'media_playback.dart';

/// 后端播放解析的不透明上下文标记。
///
/// 各后端适配层可携带「桥接到播放器所需的私有 raw facts」，但对中立层完全不透明
/// （无飞牛 / Emby 命名、无字段约定）。只有对应后端的桥接器知道真实类型并 downcast。
/// 这样中立 [MediaPlaybackBundle] 保持纯净，raw facts 不泄漏进公共模型。
abstract interface class MediaPlaybackBackendContext {}

/// `MediaBackend.getPlayback` 的返回：中立播放 bundle + 不透明后端上下文。
///
/// [bundle] 是后端中立的播放事实（页面 / 中立 launcher 消费）。
/// [backendContext] 由后端桥接器消费，装配播放器最终 source；中立层不解读它。
class MediaPlaybackResolution {
  final MediaPlaybackBundle bundle;
  final MediaPlaybackBackendContext? backendContext;

  const MediaPlaybackResolution({required this.bundle, this.backendContext});
}
