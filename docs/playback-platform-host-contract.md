# Playback Platform Host Contract

本文档定义 Flutter 业务层与各平台播放器宿主之间的边界。业务层只负责组装后端中立的播放事实，不依赖 Android Activity 或具体窗口实现。

## Dart side

- `MediaBackend.getPlayback()` 返回后端中立的播放事实。
- 后端 bridge 负责组装 `MpvMediaSource`。
- 播放入口通过 `PlaybackHost.launch()` 启动平台播放器。
- `MpvMediaSource.toMap()` 产生传给平台宿主的 `loadArgs` JSON；字段兼容性由播放契约测试与平台实现共同维护。

## Platform side

- 平台宿主接收 `loadArgs` JSON，并创建或复用平台播放器窗口。
- 平台宿主通过反向通道回报播放进度、播放状态和错误。
- 平台宿主需要支持通过 `resolvePlayback` / `reloadServerSession` 请求换源或服务器会话重载。
- 平台宿主不得把飞牛或 Emby 的判断泄漏到通用播放窗口；后端差异应在 Dart bridge 和 loadArgs 中完成装配。

## Compatibility

- Android 使用 `NativePlayerActivity`，Dart 侧实现为 `NativePlaybackHost`。
- iOS、macOS、Windows 应在 `PlaybackHost` 后实现等价的宿主行为。
- 新平台可以使用 libmpv、AVPlayer 或其他原生内核，但不得恢复 Flutter 播放页面作为平台兜底。
- 未来平台若不能启动宿主，应返回 `false`，由调用方展示统一的播放失败反馈。

