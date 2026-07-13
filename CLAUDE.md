# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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
