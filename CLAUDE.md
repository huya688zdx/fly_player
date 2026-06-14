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
- `/player` — the mpv player page
- `/screen/*` — secondary screens (search, favorites, downloads, settings, etc.)
- `/parallel/placeholder` — placeholder for split-pane secondary window

### State management

Four top-level providers (`lib/providers/`): `NasProvider` (NAS connection + auth), `AppThemeProvider`, `AppLocaleProvider`, `ParallelWindowSettingsProvider`. All set up in `FlyPlayerApp.build()` via `MultiProvider`.

### Player architecture (critical)

`MpvPlayerPage` in `lib/player/mpv_player_page.dart` is the central widget. It uses a **part-file mixin pattern** — the widget class mixes in ~20 mixins, each declared via `part` directives pointing to `page_parts/*/`. This breaks the player into independently maintainable concerns:

| Mixin file | Concern |
|---|---|
| `mpv_player_view_mixin.dart` | Video view, overlay stacking, gesture layer |
| `mpv_player_runtime_mixin.dart` | Playback lifecycle, source switching, resume |
| `mpv_player_source_mixin.dart` | Stream resolution/quality switching |
| `mpv_player_episode_mixin.dart` | Episode browser and navigation |
| `mpv_player_options_mixin.dart` | Overflow menu and action sheet options |
| `mpv_player_playback_feedback_mixin.dart` | Speed, quality change, error toasts |
| `mpv_player_ab_loop_mixin.dart` | A-B repeat loop UI |
| `mpv_player_bookmark_mixin.dart` | Bookmark creation and management |
| `mpv_player_system_session_mixin.dart` | Android media session / PIP integration |
| `mpv_player_danmaku_mixin.dart` | Danmaku overlay bridge and lifecycle |
| `mpv_player_danmaku_settings_mixin.dart` | Danmaku settings drawer |
| `mpv_player_danmaku_sources_mixin.dart` | Danmaku source selection (DanDanPlay etc.) |
| `mpv_player_danmaku_pages_mixin.dart` | Danmaku management pages |
| `mpv_player_danmaku_widgets.dart` | Danmaku-related UI widgets |
| `mpv_player_settings_drawer_mixin.dart` | Main settings drawer host |
| `mpv_player_settings_intro_outro_mixin.dart` | OP/ED skip configuration |
| `mpv_player_settings_video_info_mixin.dart` | Video/audio track info display |
| `mpv_player_settings_mpv_mixin.dart` | Advanced mpv settings |
| `mpv_player_audio_drawer_mixin.dart` | Audio track and EQ settings |
| `mpv_player_subtitle_drawer_mixin.dart` | Subtitle track and styling |
| `mpv_player_video_adjust_mixin.dart` | Video zoom/crop/adjust |

When adding player features, follow this pattern: create a new mixin `part` file and mix it into `MpvPlayerPage`.

### Danmaku module (`lib/danmaku/`)

Architected as an independent overlay system separate from mpv. Key principles (from `lib/danmaku/README.md`):
- Data sources, settings, and rendering are three separate layers
- Danmaku overlay uses a single `CustomPaint` + `RepaintBoundary` (never one widget per comment)
- Always `IgnorePointer` — must not interfere with player gestures
- Danmaku network requests go through `lib/danmaku/api/`, never through `feiniu_api.dart`
- See the README for the full architecture rationale and planned iteration order

### Android native side

Kotlin code under `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/`:
- `mpv/` — native mpv bridge: playback controller, proxy server, video output, track selection, diagnostics, playback recovery, danmaku dynamic occlusion (Paddle Lite segmentation)
- Top-level Activities: `MainActivity` (home host), `PlayerActivity`, `FullscreenPlayerActivity`, `DetailActivity`, `ExternalLocalVideoActivity`, `FullscreenScreenshotActivity`
- `ParallelWindowCoordinator` / `ParallelFlutterEngineRegistry` — manage multi-window split-pane with separate Flutter engines
- `PlaybackSessionManager` / `PlaybackSessionCoordinator` — manage playback state across Activity transitions and PIP
- mpv native libs are bundled in `jniLibs/arm64-v8a/` (only arm64-v8a ABI is built)

### Key Flutter services (`lib/services/`)

- `feiniu_api.dart` (`lib/api/`) — Feiniu NAS API client (Dio-based)
- `mpv_proxy_server.dart` — local HTTP proxy for forwarding playback streams to mpv
- `play_stats/` — playback statistics with SQLite persistence (via `sqflite`)
- `*_bridge.dart` files — MethodChannel bridges to Android native code
- `download_task_service.dart` — download queue management

### Dynamic theming

The app supports per-detail-page dynamic theming via `palette_generator`. `DynamicThemeRuntimeController` and `DynamicThemeSeedExtractor` cache extracted color seeds. `AppRuntimeColorScopeBuilder` overlays dynamic colors onto the Material theme at runtime.

### Configuration

App requires Feiniu NAS credentials on first launch (stored in SharedPreferences). DanDanPlay API credentials are injected via Gradle build config (`local.properties` or `.look/local.properties`).

## Tests

24 test files in `test/`, primarily focused on player controllers, danmaku parsing, play stats, and settings stores. Tests use `flutter_test` SDK. No integration/e2e tests found in the repo.
