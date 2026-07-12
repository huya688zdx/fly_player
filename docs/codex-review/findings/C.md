<!-- CHECKPOINT
已审文件数: 26 / 26
最后完成: lib/danmaku/api/dandanplay_config.dart
下一个: 无
阶段: 已完成
更新时间: 2026-07-02 15:58
-->

# TASK C findings

## 契约小结: lib/services/gpu_profile_bridge.dart

| 方法名 | 方向 | Kotlin 对应点 | 状态 |
|---|---|---|---|
| `fly_player/system.getGpuProfile` | Dart -> Kotlin | 未找到；`FlutterHostActivity.registerSystemChannel` 仅处理播放器系统状态/会话等方法 | 孤儿 |

### [C-001] GPU 画像桥调用了原生未实现的方法
- 级别: P2
- 分类: 可维护性 / 死契约(M5)
- 位置: lib/services/gpu_profile_bridge.dart:38
- 问题: Dart 侧预取 GPU 画像时调用 `getGpuProfile`，但全仓仅找到该 Dart 调用，Kotlin 的 `fly_player/system` handler 未实现该方法，实际会进入 `notImplemented` 后被 catch 掉，导致 `_loaded` 永远不置 true，后续 `ensureLoaded()` 每次都会重试无效通道调用。
  ```dart
  final result = await _channel.invokeMapMethod<String, dynamic>(
    'getGpuProfile',
  );
  _isLikelyMali = result?['isLikelyMali'] == true;
  ```
- 建议方向: 要么在 `FlutterHostActivity.registerSystemChannel` 补齐 `getGpuProfile` 并返回 `detectDeviceProfile()` 的稳定 Map，要么删除/停用该 Dart 桥，避免保留单侧契约。
- 状态: 已确认

## 契约小结: lib/services/main_host_bridge.dart

| 方法名 | 方向 | Kotlin 对应点 | 状态 |
|---|---|---|---|
| `fly_player/main_host.switchPrimaryTab` | Dart -> Kotlin / Kotlin -> Dart 转发 | `FlutterHostActivity.registerMainHostChannel` / `dispatchMainHostMethod`；Dart handler 在 `MainNavigation` | OK |
| `fly_player/main_host.openPrimarySettings` | Dart -> Kotlin / Kotlin -> Dart 转发 | `FlutterHostActivity.registerMainHostChannel` / `openPrimarySettings`；Dart handler 在 `MainNavigation` | OK |

## 契约小结: lib/services/native_player_bridge.dart

| 方法名 | 方向 | Kotlin 对应点 | 状态 |
|---|---|---|---|
| `fly_player/native_player.launch` | Dart -> Kotlin | `FlutterHostActivity.registerNativePlayerChannel` | OK |
| `fly_player/native_player.bindReentryHost` | Dart -> Kotlin | `FlutterHostActivity.registerNativePlayerChannel` -> `NativePlayerReverseBridge.attach` | OK |
| `fly_player/native_player.unbindReentryHost` | Dart -> Kotlin | `FlutterHostActivity.registerNativePlayerChannel` -> `NativePlayerReverseBridge.detach` | OK |
| `resolvePlayback` / `reloadServerSession` / `loadEpisodePickerData` / `loadSeasonEpisodes` / `setEpisodePickerViewType` / `resolveSubtitleFile` / `recordProgress` / `recordNativeLog` | Kotlin -> Dart | `NativePlayerActivity` / `MpvPlaybackController` 经 `NativePlayerReverseBridge.dispatch`；Dart handler 覆盖 | OK |
| `searchDanmakuSource` / `loadDanmakuEpisode` / `importDanmakuFile` / `listSavedDanmakuSources` / `loadSavedDanmakuSource` | Kotlin -> Dart | `NativePlayerActivity` 弹幕面板；Dart handler 覆盖 | OK |
| `setUseNativeRenderer` / `persistMpvAdvanced` / `persistVideoAdjustments` / `persistDanmakuSettings` / `loadPlayerGlobalSettings` / `listSavedMpvPresets` / `applySavedMpvPreset` | Kotlin -> Dart | `NativePlayerActivity` 设置/预设同步；Dart handler 覆盖 | OK |

## 契约小结: lib/services/parallel_host_bridge.dart

| 方法名 | 方向 | Kotlin 对应点 | 状态 |
|---|---|---|---|
| `fly_player/embedding.getParallelHostContext` | Dart -> Kotlin | `FlutterHostActivity.registerEmbeddingChannel` -> `getParallelHostContext()` | OK |

## 契约小结: lib/services/parallel_window_settings_bridge.dart

| 方法名 | 方向 | Kotlin 对应点 | 状态 |
|---|---|---|---|
| `fly_player/embedding.getParallelWindowSettings` | Dart -> Kotlin | `FlutterHostActivity.registerEmbeddingChannel` -> `ParallelWindowCoordinator.settingsMap()` | OK |
| `fly_player/embedding.updateParallelWindowSettings` | Dart -> Kotlin | `FlutterHostActivity.registerEmbeddingChannel`；参数 `enabled/preferredPrimaryPaneSide/preferredPlaybackPrimaryPaneSide/splitRatioPreset/defaultPlaybackFullscreen/immersiveStatusBar` 匹配 | OK |

## 契约小结: lib/services/player_host_bridge.dart

| 方法名 | 方向 | Kotlin 对应点 | 状态 |
|---|---|---|---|
| `fly_player/player_host.consumeInitialPlayerArgs` | Dart -> Kotlin | `FlutterHostActivity.registerPlayerHostChannel` | OK |
| `fly_player/player_host.finishPlayerActivity` | Dart -> Kotlin | `FlutterHostActivity.registerPlayerHostChannel`；参数 `result` 匹配 | OK |
| `fly_player/player_host.switchPlayerLayoutMode` | Dart -> Kotlin | `FlutterHostActivity.registerPlayerHostChannel`；参数 `title/source/initialPlayInfo/startSource/targetMode/result` 匹配 | OK |
| `fly_player/player_host.syncPlayerLaunchState` | Dart -> Kotlin | `FlutterHostActivity.registerPlayerHostChannel`；参数 `title/source/initialPlayInfo/startSource` 匹配 | OK |
| `fly_player/player_host.isSystemMultiWindowActive` | Dart -> Kotlin | `FlutterHostActivity.registerPlayerHostChannel` | OK |
| `fly_player/player_host.isPictureInPictureSupported` | Dart -> Kotlin | `FlutterHostActivity.registerPlayerHostChannel` | OK |
| `fly_player/player_host.enterPictureInPicture` | Dart -> Kotlin | `FlutterHostActivity.registerPlayerHostChannel` | OK |

## 契约小结: lib/services/player_system_session_bridge.dart

| 方法名 | 方向 | Kotlin 对应点 | 状态 |
|---|---|---|---|
| `fly_player/system.playerSessionStart` | Dart -> Kotlin | `FlutterHostActivity.registerSystemChannel` | OK |
| `fly_player/system.playerSessionUpdate` | Dart -> Kotlin | `FlutterHostActivity.registerSystemChannel` | OK |
| `fly_player/system.playerSessionStop` | Dart -> Kotlin | `FlutterHostActivity.registerSystemChannel` | OK |
| `systemPlay` / `systemPause` / `systemSeekTo` / `systemSkipToPrevious` / `systemSkipToNext` | Kotlin -> Dart | `FlutterHostActivity.dispatchSystemPlaybackCommand`；Dart handler `_handleSystemPlaybackMethodCall` 覆盖 | OK |

## 契约小结: lib/services/runtime_theme_session_bridge.dart

| 方法名 | 方向 | Kotlin 对应点 | 状态 |
|---|---|---|---|
| `fly_player/system.getRuntimeThemeSessionId` | Dart -> Kotlin | `FlutterHostActivity.registerSystemChannel` | OK |

## 契约小结: lib/services/runtime_theme_sync_bridge.dart

| 方法名 | 方向 | Kotlin 对应点 | 状态 |
|---|---|---|---|
| `fly_player/runtime_theme_sync.pushRuntimeThemeToMain` | Dart -> Kotlin | `FlutterHostActivity.registerRuntimeThemeSyncChannel`；payload 透传并要求 `pageKey` | OK |
| `fly_player/runtime_theme_sync.clearRuntimeThemeOnMain` | Dart -> Kotlin | `FlutterHostActivity.registerRuntimeThemeSyncChannel`；参数 `pageKey` 匹配 | OK |
| `fly_player/runtime_theme_sync.getActiveRuntimeTheme` | Dart -> Kotlin | `FlutterHostActivity.registerRuntimeThemeSyncChannel` | OK |
| `applyRuntimeDynamicTheme` / `clearRuntimeDynamicTheme` | Kotlin -> Dart | `FlutterHostActivity.dispatchRuntimeThemeSync`；`AppThemeProvider` handler 覆盖 | OK |

## 契约小结: lib/services/session_exit_bridge.dart

| 方法名 | 方向 | Kotlin 对应点 | 状态 |
|---|---|---|---|
| `fly_player/embedding.logoutAndResetParallelUi` | Dart -> Kotlin | `FlutterHostActivity.registerEmbeddingChannel` | OK |

## 契约小结: lib/services/embedded_detail_launcher.dart

| 方法名 | 方向 | Kotlin 对应点 | 状态 |
|---|---|---|---|
| `fly_player/embedding.canOpenEmbeddedDetail` | Dart -> Kotlin | `FlutterHostActivity.registerEmbeddingChannel` | OK |
| `fly_player/embedding.isParallelWindowSupported` | Dart -> Kotlin | `FlutterHostActivity.registerEmbeddingChannel` | OK |
| `fly_player/embedding.openItemDetail` | Dart -> Kotlin | `FlutterHostActivity.registerEmbeddingChannel`；参数 `itemGuid/seriesGuid/initialItemDetail` 匹配 | OK |
| `fly_player/embedding.openSeasonDetail` | Dart -> Kotlin | `FlutterHostActivity.registerEmbeddingChannel`；参数 `parentGuid/seriesTitle/backdropPath/seasonItem` 匹配 | OK |
| `fly_player/embedding.openSecondaryRoute` | Dart -> Kotlin | `FlutterHostActivity.registerEmbeddingChannel`；参数 `routeName` 匹配 | OK |
| `fly_player/embedding.openFullscreenPlayer` | Dart -> Kotlin | `FlutterHostActivity.registerEmbeddingChannel`；参数 `title/source/initialPlayInfo/startSource` 匹配 | OK |
| `fly_player/embedding.closeRightPane` | Dart -> Kotlin | `FlutterHostActivity.registerEmbeddingChannel` | OK |
| `fly_player/embedding.reportBrowseSnapshot` | Dart -> Kotlin | `FlutterHostActivity.registerEmbeddingChannel` | OK |

## 契约小结: lib/services/detail_route_payload_store.dart

| 方法名 | 方向 | Kotlin 对应点 | 状态 |
|---|---|---|---|
| `fly_player/embedding.readDetailRoutePayload` | Dart -> Kotlin | `FlutterHostActivity.registerEmbeddingChannel`；参数 `token` 匹配 | OK |

## 契约小结: lib/player/services/native_player_bridge.dart

| 方法名 | 方向 | Kotlin 对应点 | 状态 |
|---|---|---|---|
| `fly_player/native_player.launchPlayer` | Dart -> Kotlin | 未找到；Kotlin 当前仅处理 `launch` | 孤儿 |
| `fly_player/native_player.getEpisodeData` | Dart -> Kotlin | 未找到 | 孤儿 |
| `fly_player/native_player.applyMpvSetting` | Dart -> Kotlin | 未找到 | 孤儿 |
| `fly_player/native_player.pause` / `resume` / `seek` / `setSpeed` / `setAudioTrack` / `setSubtitleTrack` / `close` | Dart -> Kotlin | 未在 `fly_player/native_player` handler 中实现；同名能力存在于 per-view `fly_player/mpv_view_$viewId/methods` 或原生壳内部，不是该 channel | 孤儿 |
| `fly_player/native_player/events` | Kotlin -> Dart | 未找到 EventChannel 注册 | 孤儿 |

### [C-002] player/services 下的 NativePlayerBridge 与当前原生壳契约平行失效
- 级别: P1
- 分类: 可维护性 / 重复(M2) / 死契约(M5)
- 位置: lib/player/services/native_player_bridge.dart:235
- 问题: 仓库同时存在 `lib/services/native_player_bridge.dart` 和本文件两个 `NativePlayerBridge`，且都使用 `fly_player/native_player`，但本文件维护的是另一套未实现契约：Dart 调用 `launchPlayer` 并监听 `fly_player/native_player/events`，Kotlin `registerNativePlayerChannel` 只处理 `launch`、`bindReentryHost`、`unbindReentryHost`。这些方法若被重新接入会直接 `notImplemented`/无事件。
  ```dart
  final MethodChannel _methodChannel = const MethodChannel(
    'fly_player/native_player',
  );
  final EventChannel _eventChannel = const EventChannel(
    'fly_player/native_player/events',
  );
  await _methodChannel.invokeMethod<void>('launchPlayer', args.toMap());
  ```
- 建议方向: 删除或隔离这套旧桥；若仍需要 native player launcher，应改为复用 `lib/services/native_player_bridge.dart` 的 `launch`/反向 reentry 契约，并避免两个同名类共享同一 channel 名但维护不同方法表。
- 状态: 已确认

## 契约小结: lib/player/services/native_panel_bridge.dart

| 方法名 | 方向 | Kotlin 对应点 | 状态 |
|---|---|---|---|
| `fly_player/native_panels.showEpisodePicker` | Dart -> Kotlin | 未找到 channel 注册；本文件也无调用方 | 孤儿 |
| `fly_player/native_panels.showSettings` | Dart -> Kotlin | 未找到 channel 注册；本文件也无调用方 | 孤儿 |
| `fly_player/native_panels.showQualitySheet` | Dart -> Kotlin | 未找到 channel 注册；本文件也无调用方 | 孤儿 |
| `fly_player/native_panels.showSpeedSheet` | Dart -> Kotlin | 未找到 channel 注册；本文件也无调用方 | 孤儿 |
| `fly_player/native_panels.showAudioTrackSheet` | Dart -> Kotlin | 未找到 channel 注册；本文件也无调用方 | 孤儿 |
| `fly_player/native_panels.showSubtitleTrackSheet` | Dart -> Kotlin | 未找到 channel 注册；本文件也无调用方 | 孤儿 |

### [C-003] NativePanelBridge 保留了未注册且未使用的 native_panels 契约
- 级别: P2
- 分类: 可维护性 / 死代码(M5) / 死契约(M5)
- 位置: lib/player/services/native_panel_bridge.dart:36
- 问题: 本文件创建 `fly_player/native_panels` 并定义一组原生面板方法，但全仓没有 Kotlin `MethodChannel("fly_player/native_panels")` 注册，也没有 Dart 调用方引用 `NativePanelBridge`。当前靠 `enabled=false` 避免触发，实际是一套不可用的残留桥。
  ```dart
  static const MethodChannel _channel = MethodChannel(
    'fly_player/native_panels',
  );
  static bool enabled = false;
  ```
- 建议方向: 如果原生面板路线已废弃，删除该桥；如果计划恢复，先在 Kotlin 侧集中注册 channel 并补齐调用方，再移除默认关闭的死开关。
- 状态: 已确认

## 契约小结: lib/services/storage_access_service.dart

| 方法名 | 方向 | Kotlin 对应点 | 状态 |
|---|---|---|---|
| `fly_player/storage.hasFileAccess` / `requestFileAccess` / `openFileAccessSettings` / `getPrimaryStorageRoot` | Dart -> Kotlin | `FlutterHostActivity.registerStorageChannel` | OK |
| `fly_player/storage.getScopedTreeRoot` / `requestScopedTreeAccess` / `listScopedTreeEntries` / `readScopedFileBytes` | Dart -> Kotlin | `FlutterHostActivity.registerStorageChannel`；参数 `directoryId/allowedExtensions/identifier` 匹配 | OK |
| `fly_player/storage.getScreenshotCustomDirectory` / `requestScreenshotCustomDirectory` / `clearScreenshotCustomDirectory` | Dart -> Kotlin | `FlutterHostActivity.registerStorageChannel` | OK |
| `fly_player/storage.listScreenshotLibrary` / `readScreenshotFileBytes` / `deleteScreenshotFiles` | Dart -> Kotlin | `FlutterHostActivity.registerStorageChannel`；参数 `sourceKind/pathOrIdentifier/items` 匹配 | OK |

### [C-004] 截图/文件读取通过 MethodChannel 传整段字节
- 级别: P1
- 分类: 性能 / 数据编解码
- 位置: lib/services/storage_access_service.dart:316
- 问题: Dart 侧 `readScreenshotFileBytes` 直接请求 `Uint8List`，Kotlin storage handler 对应分支也直接 `result.success(screenshotLibraryController.readFileBytes(...))`。截图可能是多 MB 大图，MethodChannel 会把整段字节序列化回 Dart，触发路径是打开全屏截图/预览读取原图时；这类大对象按任务 C 要求应避免通过通道传输。
  ```dart
  return _channel.invokeMethod<Uint8List>(
    'readScreenshotFileBytes',
    <String, Object?>{
      'sourceKind': trimmedSource,
      'pathOrIdentifier': trimmedPath,
    },
  );
  ```
  Kotlin 侧同一 handler 直接返回整段 `ByteArray`：
  ```kotlin
  "readScreenshotFileBytes" -> {
      val sourceKind = call.argument<String>("sourceKind").orEmpty()
      val pathOrIdentifier = call.argument<String>("pathOrIdentifier").orEmpty()
      result.success(
          screenshotLibraryController.readFileBytes(
  ```
- 建议方向: 原生侧返回可访问的文件路径/URI/临时句柄，Dart 用文件/平台图片管线加载；若必须传 bytes，也应把读取放后台线程并限制尺寸或分块。
- 状态: 已确认

## 契约小结: lib/services/storage_management_service.dart

| 方法名 | 方向 | Kotlin 对应点 | 状态 |
|---|---|---|---|
| `fly_player/storage.getStorageOverview` | Dart -> Kotlin | `FlutterHostActivity.registerStorageChannel` | OK |
| `fly_player/storage.hasFileAccess` / `requestFileAccess` | Dart -> Kotlin | `FlutterHostActivity.registerStorageChannel` | OK |
| `fly_player/storage.clearStorageAction` | Dart -> Kotlin | `FlutterHostActivity.registerStorageChannel`；参数 `action` 匹配 | OK |
| `fly_player/storage.promoteCachedMedia` | Dart -> Kotlin | `FlutterHostActivity.registerStorageChannel`；参数 `itemGuid/mediaGuid/videoGuid/resourceKey/targetMode` 匹配 | OK |

## 契约小结: lib/services/download_task_service.dart

| 方法名 | 方向 | Kotlin 对应点 | 状态 |
|---|---|---|---|
| `fly_player/storage.readLocalVideoMetadata` | Dart -> Kotlin | `FlutterHostActivity.registerStorageChannel`；参数 `path` 匹配，Kotlin 侧后台线程读取 | OK |

## 契约小结: lib/providers/nas_provider.dart

| 方法名 | 方向 | Kotlin 对应点 | 状态 |
|---|---|---|---|
| `fly_player/session_state.loggedOut` | Kotlin -> Dart | `FlutterHostActivity.dispatchSessionState("loggedOut")`；Dart handler `_handleSessionStateMethodCall` 覆盖 | OK |

## 契约小结: lib/screens/detail_host_screen.dart

| 方法名 | 方向 | Kotlin 对应点 | 状态 |
|---|---|---|---|
| `fly_player/detail_host.replaceRoute` | Kotlin -> Dart | `DetailActivity` / `ParallelFlutterEngineRegistry` 主动 invoke；Dart handler 覆盖 | OK |
| `fly_player/detail_host.popInPane` | Kotlin -> Dart | `DetailActivity.requestPopInPane`；Dart handler 覆盖并返回 bool | OK |
| `fly_player/detail_host.setRouteStack` | Kotlin -> Dart | `ParallelFlutterEngineRegistry.prepareSplitDetailRoute`；参数 `routeNames` 匹配 | OK |

## 契约小结: lib/screens/player_host_screen.dart

| 方法名 | 方向 | Kotlin 对应点 | 状态 |
|---|---|---|---|
| `fly_player/player_host_state.replaceSource` | Kotlin -> Dart | `PlayerActivity.onNewIntent` / `replaceSourceInPlace`；Dart handler 覆盖 | OK |
| `fly_player/player_host_state.replaceRightPaneRoute` | Kotlin -> Dart | `PlayerActivity.replaceRightPaneRouteInPlace`；参数 `routeName` 匹配 | OK |
| `fly_player/player_host_state.layoutModeChanged` | Kotlin -> Dart | `PlayerActivity.notifyPlayerHostLayoutModeChanged`；参数 `layoutMode/initialRightPaneRoute` 匹配 | OK |
| `fly_player/player_host_state.systemMultiWindowModeChanged` | Kotlin -> Dart | `FlutterHostActivity.notifyPlayerHostSystemWindowMode`；参数 `active` 匹配 | OK |
| `fly_player/player_host_state.pictureInPictureModeChanged` | Kotlin -> Dart | `PlayerActivity.onPictureInPictureModeChanged`；参数 `active` 匹配 | OK |

## 契约小结: lib/screens/screenshot_preview_screen.dart

| 方法名 | 方向 | Kotlin 对应点 | 状态 |
|---|---|---|---|
| `fly_player/embedding.consumeFullscreenScreenshotPayload` | Dart -> Kotlin | `FlutterHostActivity.registerEmbeddingChannel`；参数 `token` 匹配 | OK |
| `fly_player/embedding.openFullscreenScreenshot` | Dart -> Kotlin | `FlutterHostActivity.registerEmbeddingChannel`；参数 `items/initialIndex` 匹配 | OK |

### [C-005] 截图页面内重复创建 embedding 通道并散落方法名
- 级别: P2
- 分类: 约束违规(C5) / 可维护性
- 位置: lib/screens/screenshot_preview_screen.dart:34
- 问题: 同一个 screen 文件内两处直接创建 `MethodChannel('fly_player/embedding')`，并在页面逻辑里直接调用 `consumeFullscreenScreenshotPayload`、`openFullscreenScreenshot`。按 C5，通道创建和方法名应收敛在桥接文件/服务/store 中；页面内重复 new channel 会让契约分散，后续改 channel 名或参数时容易漏改。
  ```dart
  static const MethodChannel _embeddingChannel = MethodChannel(
    'fly_player/embedding',
  );
  ...
  static const MethodChannel _embeddingChannel = MethodChannel(
    'fly_player/embedding',
  );
  ```
- 建议方向: 抽到 `*_bridge.dart` 或复用现有 `EmbeddedDetailLauncher`/专门的截图 embedding bridge，页面只调用语义化方法。
- 状态: 已确认

## 契约小结: lib/theme/dynamic_theme_seed_extractor.dart

| 方法名 | 方向 | Kotlin 对应点 | 状态 |
|---|---|---|---|
| `fly_player/theme_sampler.extractDynamicThemeSeed` | Dart -> Kotlin | `FlutterHostActivity.registerThemeSamplerChannel`；参数 `imageUrl/token` 和返回 `backgroundSeed/accentSeed/selectionSeed/linkSeed/preferLightSurface` 匹配 | OK |

## 契约小结: lib/player/controllers/mpv_player_controller.dart

| 方法名 | 方向 | Kotlin 对应点 | 状态 |
|---|---|---|---|
| `fly_player/mpv_view_$viewId/methods` | Dart -> Kotlin | `MpvPlayerView.methodChannel` 同 viewId 注册 | OK |
| `getState` / `getDanmakuOcclusionState` / `getTrackSnapshot` / `getPlaybackDiagnostics` / `getPerformanceOverlayStats` / `getChapters` / `captureFrame` | Dart -> Kotlin | `MpvPlayerView.onMethodCall` 覆盖 | OK |
| `load` / `play` / `pause` / `seek` / `hintNativeDanmakuSeek` | Dart -> Kotlin | `MpvPlayerView.onMethodCall` 覆盖；参数 `positionMs` 匹配 | OK |
| `setAudioTrack` / `setSubtitleTrack` / `setExternalSubtitleFile` / `setSubtitleDelay` / `setAudioDelay` / `setSubtitlePosition` / `setSubtitleScale` / `resetSubtitleStyle` | Dart -> Kotlin | `MpvPlayerView.onMethodCall` 覆盖；参数 key 匹配 | OK |
| `setDecoderMode` / `setDisplayAspectRatioMode` / `setSpeed` / `setVideoAdjustments` / `setMpvAdvancedSettings` / `setListenVideoMode` | Dart -> Kotlin | `MpvPlayerView.onMethodCall` 覆盖 | OK |
| `setDanmakuOcclusionConfig` / `setDanmakuOcclusionSamplingPaused` / `setDanmakuHasOnScreenComments` / `setDanmakuPayload` / `setNativeDanmakuPayload` / `setNativeDanmakuOcclusion` / `clearDanmaku` / `clearNativeDanmaku` | Dart -> Kotlin | `MpvPlayerView.onMethodCall` 覆盖 | OK |
| `fly_player/mpv_view_$viewId/events` | Kotlin -> Dart | `MpvPlayerView.eventChannel` 发 `playerState` / `danmakuOcclusionState`；Dart `_handleEvent` 覆盖 | OK |

## 契约小结: lib/player/mpv_player_page.dart

| 方法名 | 方向 | Kotlin 对应点 | 状态 |
|---|---|---|---|
| `fly_player/system.setPlayerOrientation` | Dart -> Kotlin | `FlutterHostActivity.registerSystemChannel`；参数 `mode` 匹配 | OK |
| `fly_player/system.setPlayerImmersiveMode` | Dart -> Kotlin | `FlutterHostActivity.registerSystemChannel`；参数 `enabled` 匹配 | OK |
| `fly_player/system.getPlayerStatusSnapshot` | Dart -> Kotlin | `FlutterHostActivity.registerSystemChannel`；返回 `batteryLevel/charging/networkType` 匹配 | OK |

### [C-006] 播放器页面直接持有 system channel 且方法名散落在 mixin 中
- 级别: P2
- 分类: 约束违规(C5) / 可维护性
- 位置: lib/player/mpv_player_page.dart:339
- 问题: `MpvPlayerPage` 在页面类里直接创建 `MethodChannel('fly_player/system')`，后续 `mpv_player_runtime_mixin.dart` 直接用该静态 channel 调用 `setPlayerOrientation`、`setPlayerImmersiveMode`、`getPlayerStatusSnapshot`。这违反 C5 中“页面/widget 内直接 new channel 属于违规；通道名、方法名字符串应有单一定义点”的约束。
  ```dart
  static const MethodChannel _systemChannel = MethodChannel(
    'fly_player/system',
  );
  ```
- 建议方向: 抽出 `PlayerSystemBridge`/`PlayerHostSystemBridge` 一类桥接文件，统一封装方向、沉浸模式、状态快照等 system 方法，页面 mixin 只调用语义化 API。
- 状态: 已确认

## 契约小结: lib/player/widgets/player_system_controls.dart

| 方法名 | 方向 | Kotlin 对应点 | 状态 |
|---|---|---|---|
| `fly_player/system.getPlaybackSystemState` | Dart -> Kotlin | `FlutterHostActivity.registerSystemChannel`；返回 `brightness/volume` 匹配 | OK |
| `fly_player/system.setPlaybackBrightness` | Dart -> Kotlin | `FlutterHostActivity.registerSystemChannel`；参数 `value` 匹配 | OK |
| `fly_player/system.setPlaybackVolume` | Dart -> Kotlin | `FlutterHostActivity.registerSystemChannel`；参数 `value` 匹配 | OK |

### [C-007] widget 目录内直接创建 system channel
- 级别: P2
- 分类: 约束违规(C5) / 可维护性
- 位置: lib/player/widgets/player_system_controls.dart:13
- 问题: `PlayerSystemController` 放在 `lib/player/widgets/` 下并直接创建 `MethodChannel('fly_player/system')`，与 `MpvPlayerPage`、`GpuProfileBridge`、`PlayerSystemSessionBridge` 等共享同一通道但各自散落方法名。C5 明确要求页面/widget 内不直接 new channel，通道名和方法名应集中定义。
  ```dart
  class PlayerSystemController {
    static const MethodChannel _channel = MethodChannel('fly_player/system');
  ```
- 建议方向: 将亮度/音量读取与设置迁移到统一 system bridge/service，widget 侧通过注入或普通 Dart API 调用。
- 状态: 已确认

## 契约小结: lib/danmaku/api/dandanplay_config.dart

| 方法名 | 方向 | Kotlin 对应点 | 状态 |
|---|---|---|---|
| `fly_player/secret_store.getDanDanPlayConfig` | Dart -> Kotlin | `FlutterHostActivity.registerSecretStoreChannel` | OK |
| `fly_player/secret_store.clearDanDanPlayConfig` | Dart -> Kotlin | `FlutterHostActivity.registerSecretStoreChannel` | OK |

## 总结

TASK C 已完成第一轮逐文件评审与第二轮自复核，共确认 7 条问题。
问题分布：死契约/旧桥 3 条，MethodChannel 大对象传输 1 条，C5 通道收敛违规 3 条。
优先处理建议：
1. C-002：清理 `lib/player/services/native_player_bridge.dart` 旧原生播放器桥，避免同名 channel 双契约继续误导接入。
2. C-004：改造截图/文件 bytes 通道，避免多 MB 图片通过 MethodChannel 传输并在 handler 中同步读文件。
3. C-001：补齐或删除 `getGpuProfile`，避免启动阶段持续重试单侧契约。
4. C-006/C-007：把播放器 system channel 收敛到统一 bridge/service。
5. C-005：把截图全屏 embedding 调用收敛出页面文件。
