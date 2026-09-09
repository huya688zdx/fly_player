# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Build / Run / Test

```bash
flutter pub get                  # Install dependencies
flutter run                      # Run debug build on connected device
flutter build apk --debug        # Build debug APK
flutter analyze                  # Static analysis (Dart + Flutter lints)
flutter test                     # Run all tests
flutter test test/some_test.dart # Run a single test file
```

## Architecture

Fly Player is a Flutter-based Android media player that uses **mpv** as its native playback kernel via `mpv-android`. It connects to Feiniu NAS for media browsing and playback.

### Routing

All navigation is URI-based, resolved in `lib/main.dart` `_buildRoute()`. Key routes:
- `/` — main tabbed shell (Home + Settings)
- `/detail/item`, `/detail/season`, `/detail/person`, `/detail/host` — media detail pages
- `/screen/*` — secondary screens (search, favorites, downloads, settings, etc.)
- `/parallel/placeholder` — placeholder for split-pane secondary window

### State management

Four top-level providers (`lib/providers/`): `NasProvider` (NAS connection + auth), `AppThemeProvider`, `AppLocaleProvider`, `ParallelWindowSettingsProvider`. All set up in `FlyPlayerApp.build()` via `MultiProvider`.

### Player architecture

实际播放走平台宿主接口 `lib/playback/playback_host.dart`。Android 实现通过 `NativePlaybackHost` / `NativePlayerBridge` 拉起 `NativePlayerActivity`，原生壳只消费 `MpvMediaSource.toMap()` 产出的 loadArgs JSON 与反向通道回调。新增后端不得直接依赖 Android Activity；新增平台只实现 `PlaybackHost`。

### Danmaku module (`lib/danmaku/`)

弹幕数据源、设置、导入解析和原生壳回调仍由 Flutter 侧维护；已删除旧 Flutter render/controller 层。弹幕网络请求走 `lib/danmaku/api/`，不得直接通过 `feiniu_api.dart`。

### Android native side

Kotlin code under `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/`:
- `mpv/` — native mpv bridge: playback controller, proxy server, video output, track selection, diagnostics, playback recovery, danmaku dynamic occlusion (Paddle Lite segmentation)
- Top-level Activities: `MainActivity` (home host), `NativePlayerActivity`, `DetailActivity`, `ExternalLocalVideoActivity`, `FullscreenScreenshotActivity`
- `ParallelWindowCoordinator` / `ParallelFlutterEngineRegistry` — manage multi-window split-pane with separate Flutter engines
- `PlaybackSessionManager` / `PlaybackSessionCoordinator` — manage playback state across Activity transitions and PIP
- mpv native libs are bundled in `jniLibs/arm64-v8a/` (only arm64-v8a ABI is built)

### Key Flutter services (`lib/services/`)

- `feiniu_api.dart` (`lib/api/`) — Feiniu NAS API client (Dio-based)
- `mpv_proxy_server.dart` — local HTTP proxy used by the native playback path
- `play_stats/` — playback statistics with SQLite persistence (via `sqflite`)
- `*_bridge.dart` files — MethodChannel bridges to Android native code
- `download_task_service.dart` — download queue management

### Dynamic theming

The app supports per-detail-page dynamic theming via `palette_generator`. `DynamicThemeRuntimeController` and `DynamicThemeSeedExtractor` cache extracted color seeds. `AppRuntimeColorScopeBuilder` overlays dynamic colors onto the Material theme at runtime.

### Configuration

App requires Feiniu NAS credentials on first launch (stored in SharedPreferences). DanDanPlay API credentials are injected via Gradle build config (`local.properties` or `.look/local.properties`).

## Tests

24 test files in `test/`, primarily focused on player controllers, danmaku parsing, play stats, and settings stores. Tests use `flutter_test` SDK. No integration/e2e tests found in the repo.

### Desktop module (`lib/desktop/`)

Windows/macOS/Linux 桌面端浏览与管理 UI（播放页暂缓，见 `design/desktop/IMPLEMENTATION_PLAN.md`）。基础模块提供 `DesktopEnvironment`（平台判定）、`DesktopBreakpoints`（≥1024 侧栏 / ≥1180 分屏）、`DesktopSplitController`（浏览|详情 分屏状态与 42/58、50/50、35/65 预设）、`HoverLift`（悬停浮起）、`showDesktopContextMenu`（右键菜单，复用移动端动作表）。颜色一律 `context.appColors`；桌面布局分支必须先过 `DesktopEnvironment.isDesktopPlatform` + 宽度断点，保证 Android 行为不变。

已落地：`DesktopShell`/`DesktopSideBar`（≥1024px 侧栏替代底部胶囊导航，Ctrl+K/数字键/Esc 快捷键）、`DesktopDetailPaneHost`（「浏览|详情」分屏，实现 `PlayerPaneHostController`，复用 `DetailPresentation.pane` 详情页与 `EmbeddedDetailLauncher` Flutter 侧 pane 通道）、首页/设置桌面密度档。播放入口在 `*playback_launcher` 有桌面守卫（内核选型未定）。

凭据存储：Android 走 `fly_player/secret_store` 原生通道；Windows 由 `lib/services/secure_credential_store_windows.dart` 的 DPAPI 后端承担（`SecureCredentialStore` 按平台选默认后端）。新平台接入时必须同步补 `SecureCredentialBackend` 实现，否则 NasProvider 启动恢复凭据会抛「加载失败」。

储存管理：Android 走 `fly_player/storage` 原生通道；桌面端由 `lib/services/storage_management_host.dart` 的 Dart 等价宿主承担（`StorageManagementService` 按平台选默认宿主，三桌面平台通用，Android 专属统计按 0/未受限返回）。播放内核接入后桌面播放缓存统计在该宿主内补齐；业务层禁止直连通道。

截图与文件访问面同理：`StorageAccessService` 经 `lib/services/storage_access_host.dart` 分发（Android 透传通道，桌面端 `DesktopStorageAccessHost` 按「无截图入库管线/无运行时权限」惰性语义返回，桌面截图走播放器内另存为对话框）；`primaryStorageRoot` 与 Scoped Tree 系列仍为 Android 专属直连（外部存储导出 / SAF 浏览），桌面端不可达，接入桌面语义时迁移进宿主。
