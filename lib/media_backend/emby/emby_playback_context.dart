import '../playback/media_playback_resolution.dart';

/// Emby 播放的不透明后端上下文。
///
/// 与飞牛 [FeiniuPlaybackContext] 不同：Emby `getPlayback` 一次取数（getItem + MediaSources）
/// 即得全部播放事实，**中立 [MediaPlaybackBundle] 已自足**——直链 url + headers（entry-token）
/// + 续播位 + 各轨道 index 都装在 bundle 里，桥接器纯本地装配 `MpvMediaSource`，无需二次网络、
/// 无需额外 raw facts（飞牛要 `PlayerSourceController.buildInitialPlaybackResult` 再解析代理/会话）。
///
/// 本类型因此是**后端分发标记**：`ItemPlaybackLauncher` 据其运行时类型选 `EmbyPlaybackSourceBridge`
/// （对位飞牛据 `FeiniuPlaybackContext` 选飞牛桥）。预留字段供日后转码会话 / 外挂字幕直链扩展。
class EmbyPlaybackContext implements MediaPlaybackBackendContext {
  const EmbyPlaybackContext();
}
