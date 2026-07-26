# 删除 Flutter 播放链路 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 删除已废弃的 Flutter 播放页面、旧播放器宿主 Activity 与 Flutter 弹幕渲染层，同时保留并升格当前原生壳仍在使用的播放契约、设置存储、弹幕 API 与反向通道。

**Architecture:** 先把 `MpvMediaSource`、播放源装配、mpv 设置、截图/书签存储从 `lib/player/` 迁到平台无关位置，再把所有入口切到 `NativePlayerActivity` / `NativePlayerBridge`，最后删除 `/player`、`PlayerActivity`、`MpvPlayerPage` 与 Flutter 弹幕 render/controller。未来 Win/Mac/iOS 只实现 `PlaybackHost` 平台宿主，不依赖 Android `NativePlayerActivity`，也不恢复 Flutter 播放页。

**Tech Stack:** Flutter/Dart、Android Kotlin、MethodChannel、mpv native shell、flutter_test、Android Gradle unit/Kotlin compile。

---

## 0. 背景与硬约束

`docs/codex-review/FIX-PLAN.md` 第 2 节建议删除 Flutter 播放链路，但当前仓库不是“整个 `lib/player` 都可删”的状态。调查结论如下：

- `lib/player` 约 38250 行，其中 `MpvPlayerPage`、`page_parts/**`、旧播放器 widgets/services 可删除。
- `lib/danmaku/render` + `lib/danmaku/controller` 约 5051 行，属于 Flutter 弹幕渲染层，可随旧播放器删除。
- `lib/danmaku/api/`、`lib/danmaku/parser/danmaku_import_parser.dart`、`lib/danmaku/settings/danmaku_saved_source_store.dart`、`lib/services/native_danmaku_prefetch.dart` 是原生壳弹幕链路活代码，必须保留。
- `MpvMediaSource` 现在定义在 `lib/player/controllers/mpv_player_controller.dart`，但它是原生壳 `loadArgs` 契约核心，被 launcher、后端桥、下载、本地播放、反向换源、测试共同使用，必须先迁出。
- `MpvSettingsStore`、`MpvSettingsL10n`、`MpvAudioEqPresetStore`、`BookmarkStore`、`ScreenshotSettingsStore` 已被设置页、书签页、截图页、原生壳设置同步使用，不能随旧播放器删除。
- 外部本地视频入口 `ExternalLocalVideoActivity` 当前仍通过 `PlayerLaunchContract.buildExternalLocalVideoIntent()` 拉起 `PlayerActivity`，必须先改为直接拉起 `NativePlayerActivity`。
- `EmbeddedDetailLauncher.openFullscreenPlayer()` 的 Android 实现仍会创建 `PlayerActivity`，必须先切到原生壳或让调用方只走 `NativePlayerBridge`。

## 1. 文件结构目标

新增或迁移后的目标位置：

- Create: `lib/playback/playback_source.dart`
  - 承载 `MpvMediaSource`、`MpvVideoOutputBackend`、`createMpvLoadNonce()` 与 `toMap/fromMap/localFile`。
- Create: `lib/playback/player_source_controller.dart`
  - 从旧 `lib/player/controllers/player_source_controller.dart` 迁出飞牛播放源装配、服务端会话重载所需的纯逻辑。
- Create: `lib/playback/feiniu_playback_source_bridge.dart`
  - 从旧 `lib/player/controllers/feiniu_playback_source_bridge.dart` 迁出。
- Create: `lib/playback/emby_playback_source_bridge.dart`
  - 从旧 `lib/player/controllers/emby_playback_source_bridge.dart` 迁出。
- Create: `lib/playback/playback_host.dart`
  - 定义未来多平台播放宿主接口。
- Create: `lib/playback/native_playback_host.dart`
  - Android 当前实现，内部委托 `NativePlayerBridge`。
- Move: `lib/player/stores/mpv_settings_store.dart` → `lib/playback/settings/mpv_settings_store.dart`
- Move: `lib/player/mpv_settings_l10n.dart` → `lib/playback/settings/mpv_settings_l10n.dart`
- Move: `lib/player/stores/mpv_audio_eq_preset_store.dart` → `lib/playback/settings/mpv_audio_eq_preset_store.dart`
- Move: `lib/player/stores/bookmark_store.dart` → `lib/playback/bookmarks/bookmark_store.dart`
- Move: `lib/player/stores/screenshot_settings_store.dart` → `lib/playback/screenshots/screenshot_settings_store.dart`
- Delete after migration: `lib/player/mpv_player_page.dart`
- Delete after migration: `lib/player/page_parts/**`
- Delete after migration: `lib/player/widgets/**`
- Delete after migration: `lib/player/services/mpv_proxy_server.dart`
- Delete after migration: `lib/player/services/native_player_bridge.dart`
- Delete after migration: `lib/player/services/native_panel_bridge.dart`
- Delete after migration: `lib/player/services/native_player_launcher.dart`
- Delete after migration: `lib/player/services/player_runtime_preferences_store.dart`
- Delete after migration: `lib/player/models/player_host_launch_args.dart`
- Delete after migration: `lib/screens/player_host_screen.dart`
- Delete after migration: `lib/services/player_host_bridge.dart`
- Delete after migration: `lib/danmaku/controller/**`
- Delete after migration: `lib/danmaku/render/**`
- Delete after migration: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/PlayerActivity.kt`
- Delete after migration: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/FullscreenPlayerActivity.kt`

## 2. 多平台播放边界

新增 `PlaybackHost` 作为未来 Win/Mac/iOS 接入点：

```dart
import '../models/play_info.dart';
import '../providers/nas_provider.dart';
import 'playback_source.dart';

abstract interface class PlaybackHost {
  Future<bool> launch({
    required MpvMediaSource source,
    List<Map<String, dynamic>>? episodes,
    PlayInfoData? initialPlayInfo,
    String? danmakuFilePath,
    String? startSource,
    NasProvider? nas,
  });
}
```

Android 实现：

```dart
import '../models/play_info.dart';
import '../providers/nas_provider.dart';
import '../services/native_player_bridge.dart';
import 'playback_host.dart';
import 'playback_source.dart';

final class NativePlaybackHost implements PlaybackHost {
  const NativePlaybackHost();

  @override
  Future<bool> launch({
    required MpvMediaSource source,
    List<Map<String, dynamic>>? episodes,
    PlayInfoData? initialPlayInfo,
    String? danmakuFilePath,
    String? startSource,
    NasProvider? nas,
  }) {
    return NativePlayerBridge.maybeLaunch(
      source.toMap(),
      episodes: episodes,
      initialPlayInfo: initialPlayInfo?.toJson(),
      danmakuFilePath: danmakuFilePath,
      startSource: startSource,
      nas: nas,
    );
  }
}
```

平台策略：

- Android：继续使用 `fly_player/native_player` MethodChannel 和 `NativePlayerActivity`。
- iOS：实现 `PlaybackHost`，由 Swift/Objective-C 宿主接 `loadArgs` JSON；播放器内核可选 libmpv、AVPlayer 或后续确定的 native player。
- macOS/Windows：实现 `PlaybackHost`，由桌面平台窗口接 `loadArgs` JSON；播放器内核优先围绕 mpv，Dart 侧不关心窗口实现。
- Dart 业务层：只依赖 `PlaybackHost` 和 `MpvMediaSource`，不写 `Platform.isAndroid` 分支，不直接引用 `NativePlayerActivity`。

## 3. 分阶段任务

### Task 1: 抽离播放源契约

**Files:**
- Create: `lib/playback/playback_source.dart`
- Modify: `lib/player/controllers/mpv_player_controller.dart`
- Modify imports in: `lib/controllers/**`, `lib/services/native_reentry_support.dart`, `lib/services/embedded_detail_launcher.dart`, `lib/media_backend/playback/media_playback_source_bridge.dart`, `lib/ui/player_pane_host_scope.dart`, tests under `test/`
- Test: `test/mpv_player_controller_test.dart`
- Test: `test/mpv_local_file_subtitle_test.dart`
- Test: `test/player_host_launch_args_test.dart`

- [ ] **Step 1: Write import-boundary expectation**

Run before editing:

```powershell
rg -n "import '../player/controllers/mpv_player_controller.dart'|import '../../player/controllers/mpv_player_controller.dart'|package:fly_player/player/controllers/mpv_player_controller.dart" lib test
```

Expected: existing references are printed. These references must point to `lib/playback/playback_source.dart` after this task.

- [ ] **Step 2: Move source-only code**

Create `lib/playback/playback_source.dart` containing:

```dart
import '../models/playback_stream.dart';
import '../models/stream_track_data.dart';
import '../utils/local_subtitle_bundle.dart';

int createMpvLoadNonce() {
  return DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
}

abstract final class MpvVideoOutputBackend {
  static const String texture = 'texture';
  static const String surface = 'surface';
  static const String defaultValue = String.fromEnvironment(
    'FLY_PLAYER_VIDEO_OUTPUT_BACKEND',
    defaultValue: texture,
  );

  static String normalize(String? value) {
    return switch (value?.trim().toLowerCase()) {
      surface => surface,
      texture => texture,
      _ => defaultValue,
    };
  }
}
```

Then move the complete existing `MpvMediaSource` class from `lib/player/controllers/mpv_player_controller.dart` into the same file, including `copyWith`, `localFile`, `toMap`, `fromMap`, and helper serializers. Keep behavior byte-for-byte except import paths.

- [ ] **Step 3: Update old controller imports**

In `lib/player/controllers/mpv_player_controller.dart`, remove `MpvMediaSource`, `MpvVideoOutputBackend`, and `createMpvLoadNonce()`, then import:

```dart
import '../../playback/playback_source.dart';
```

- [ ] **Step 4: Update all external imports**

Replace imports of `mpv_player_controller.dart` with `playback_source.dart` in files that only need `MpvMediaSource` or `createMpvLoadNonce()`. Keep `mpv_player_controller.dart` imports only inside old Flutter player code that still needs `MpvPlayerController`.

Verification command:

```powershell
rg -n "import '../player/controllers/mpv_player_controller.dart'|import '../../player/controllers/mpv_player_controller.dart'|package:fly_player/player/controllers/mpv_player_controller.dart" lib test
```

Expected: only old Flutter player implementation files still match.

- [ ] **Step 5: Run focused tests**

```powershell
flutter test test/mpv_player_controller_test.dart test/mpv_local_file_subtitle_test.dart test/player_host_launch_args_test.dart --concurrency=1
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```powershell
git add lib/playback/playback_source.dart lib/player/controllers/mpv_player_controller.dart lib test
git commit -m "refactor: extract playback source contract"
```

### Task 2: 迁出播放装配与后端桥

**Files:**
- Create: `lib/playback/player_source_controller.dart`
- Create: `lib/playback/feiniu_playback_source_bridge.dart`
- Create: `lib/playback/emby_playback_source_bridge.dart`
- Modify: `lib/media_backend/feiniu/feiniu_media_backend.dart`
- Modify: `lib/media_backend/emby/emby_media_backend.dart`
- Modify: `lib/media_backend/playback/media_playback_source_bridge.dart`
- Modify: `lib/services/native_reentry_support.dart`
- Test: `test/player_source_controller_test.dart`
- Test: `test/player/feiniu_playback_source_bridge_test.dart`
- Test: `test/player/emby_playback_source_bridge_test.dart`
- Test: `test/services/native_reentry_support_test.dart`

- [ ] **Step 1: Move pure playback source logic**

Move `PlayerSourceController`, `PlayerSourceSnapshot`, `PlayerServerReloadRequest`, `PlayerServerReloadResult`, `PlayableSource` and related pure helper types from `lib/player/controllers/player_source_controller.dart` to `lib/playback/player_source_controller.dart`.

The new file must import:

```dart
import '../api/feiniu_api.dart';
import '../models/playback_stream.dart';
import '../models/stream_track_data.dart';
import 'playback_source.dart';
```

- [ ] **Step 2: Move backend bridges**

Move:

```text
lib/player/controllers/feiniu_playback_source_bridge.dart
lib/player/controllers/emby_playback_source_bridge.dart
```

to:

```text
lib/playback/feiniu_playback_source_bridge.dart
lib/playback/emby_playback_source_bridge.dart
```

Update their imports to use:

```dart
import 'playback_source.dart';
import 'player_source_controller.dart';
```

- [ ] **Step 3: Update backend providers**

In `lib/media_backend/feiniu/feiniu_media_backend.dart`, replace:

```dart
import '../../player/controllers/feiniu_playback_source_bridge.dart';
```

with:

```dart
import '../../playback/feiniu_playback_source_bridge.dart';
```

In `lib/media_backend/emby/emby_media_backend.dart`, replace:

```dart
import '../../player/controllers/emby_playback_source_bridge.dart';
```

with:

```dart
import '../../playback/emby_playback_source_bridge.dart';
```

- [ ] **Step 4: Update tests**

Replace package imports in bridge/source tests from `player/controllers/...` to `playback/...`.

Run:

```powershell
flutter test test/player_source_controller_test.dart test/player/feiniu_playback_source_bridge_test.dart test/player/emby_playback_source_bridge_test.dart test/services/native_reentry_support_test.dart --concurrency=1
```

Expected: all tests pass.

- [ ] **Step 5: Boundary check**

```powershell
rg -n "player/controllers/(feiniu_playback_source_bridge|emby_playback_source_bridge|player_source_controller)" lib test
```

Expected: no matches outside old Flutter player files.

- [ ] **Step 6: Commit**

```powershell
git add lib/playback lib/media_backend lib/services/native_reentry_support.dart test
git commit -m "refactor: move playback source assembly out of player ui"
```

### Task 3: 迁出活的设置、书签与截图存储

**Files:**
- Create directory: `lib/playback/settings/`
- Create directory: `lib/playback/bookmarks/`
- Create directory: `lib/playback/screenshots/`
- Move: `lib/player/stores/mpv_settings_store.dart`
- Move: `lib/player/mpv_settings_l10n.dart`
- Move: `lib/player/stores/mpv_audio_eq_preset_store.dart`
- Move: `lib/player/stores/bookmark_store.dart`
- Move: `lib/player/stores/screenshot_settings_store.dart`
- Modify imports in: `lib/screens/app_settings_screen.dart`, `lib/screens/mpv_player_settings_screen.dart`, `lib/services/native_player_bridge.dart`, `lib/services/storage_management_service.dart`, `lib/ui/mpv_audio_eq_advanced_panel.dart`, `lib/ui/mpv_audio_eq_editor.dart`, `lib/screens/bookmark_manager_screen.dart`, `lib/screens/screenshot_settings_screen.dart`
- Test: `test/mpv_settings_screen_test.dart`
- Test: `test/screenshot_settings_store_test.dart`

- [ ] **Step 1: Move files without changing public APIs**

Move files to:

```text
lib/playback/settings/mpv_settings_store.dart
lib/playback/settings/mpv_settings_l10n.dart
lib/playback/settings/mpv_audio_eq_preset_store.dart
lib/playback/bookmarks/bookmark_store.dart
lib/playback/screenshots/screenshot_settings_store.dart
```

Do not rename classes. Existing persisted SharedPreferences keys must remain unchanged.

- [ ] **Step 2: Update imports**

Replace old imports:

```dart
import '../player/stores/mpv_settings_store.dart';
import '../player/mpv_settings_l10n.dart';
import '../player/stores/mpv_audio_eq_preset_store.dart';
import '../player/stores/bookmark_store.dart';
import '../player/stores/screenshot_settings_store.dart';
```

with imports under `../playback/...` or `../../playback/...` according to file depth.

- [ ] **Step 3: Verify no app code imports live stores from `lib/player`**

```powershell
rg -n "player/(stores/(mpv_settings_store|mpv_audio_eq_preset_store|bookmark_store|screenshot_settings_store)|mpv_settings_l10n)" lib test
```

Expected: no matches outside deleted old Flutter player files.

- [ ] **Step 4: Run focused tests**

```powershell
flutter test test/mpv_settings_screen_test.dart test/screenshot_settings_store_test.dart --concurrency=1
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/playback lib/screens lib/services lib/ui test
git commit -m "refactor: move active playback stores out of player ui"
```

### Task 4: 引入平台播放宿主接口

**Files:**
- Create: `lib/playback/playback_host.dart`
- Create: `lib/playback/native_playback_host.dart`
- Modify: `lib/controllers/item_playback_launcher.dart`
- Modify: `lib/controllers/tv_season_playback_launcher.dart`
- Modify: `lib/pages/play_detail_page.dart`
- Modify: `lib/screens/download_list_screen.dart`
- Test: `test/media_backend/multi_backend_abstraction_boundary_test.dart`

- [ ] **Step 1: Add `PlaybackHost` interface**

Create `lib/playback/playback_host.dart` with:

```dart
import '../models/play_info.dart';
import '../providers/nas_provider.dart';
import 'playback_source.dart';

abstract interface class PlaybackHost {
  Future<bool> launch({
    required MpvMediaSource source,
    List<Map<String, dynamic>>? episodes,
    PlayInfoData? initialPlayInfo,
    String? danmakuFilePath,
    String? startSource,
    NasProvider? nas,
  });
}
```

- [ ] **Step 2: Add Android-backed implementation**

Create `lib/playback/native_playback_host.dart` with:

```dart
import '../models/play_info.dart';
import '../providers/nas_provider.dart';
import '../services/native_player_bridge.dart';
import 'playback_host.dart';
import 'playback_source.dart';

final class NativePlaybackHost implements PlaybackHost {
  const NativePlaybackHost();

  @override
  Future<bool> launch({
    required MpvMediaSource source,
    List<Map<String, dynamic>>? episodes,
    PlayInfoData? initialPlayInfo,
    String? danmakuFilePath,
    String? startSource,
    NasProvider? nas,
  }) {
    return NativePlayerBridge.maybeLaunch(
      source.toMap(),
      episodes: episodes,
      initialPlayInfo: initialPlayInfo?.toJson(),
      danmakuFilePath: danmakuFilePath,
      startSource: startSource,
      nas: nas,
    );
  }
}
```

- [ ] **Step 3: Replace direct launch call sites**

In launcher files, replace direct `NativePlayerBridge.maybeLaunch(source.toMap(), ...)` with:

```dart
const playbackHost = NativePlaybackHost();
if (await playbackHost.launch(
  source: source,
  episodes: effectiveEpisodes,
  initialPlayInfo: playInfo,
  nas: isFeiniu ? provider : null,
)) {
  return null;
}
```

Use the existing local variable names in each file. Keep `NativePlayerBridge.bindReentry` references until Task 8 because the reentry channel remains Android-specific.

- [ ] **Step 4: Run boundary test**

```powershell
flutter test test/media_backend/multi_backend_abstraction_boundary_test.dart --concurrency=1
```

Expected: pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/playback lib/controllers lib/pages lib/screens test/media_backend/multi_backend_abstraction_boundary_test.dart
git commit -m "refactor: introduce playback host boundary"
```

### Task 5: 外部本地视频改走原生壳

**Files:**
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/PlayerLaunchContract.kt`
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/ExternalLocalVideoActivity.kt`
- Test: Android compile

- [ ] **Step 1: Add native loadArgs builder**

In `PlayerLaunchContract.kt`, add:

```kotlin
fun buildExternalLocalVideoLoadArgs(
    uri: Uri,
    title: String,
    sizeBytes: Long = 0L,
): HashMap<String, Any?> {
    val normalizedTitle = title.trim().ifEmpty { "Local Video" }
    val stableId = externalLocalVideoId(uri, normalizedTitle, sizeBytes)
    val loadNonce = (System.currentTimeMillis() and 0x7fffffff).toInt().coerceAtLeast(1)
    return hashMapOf(
        "loadNonce" to loadNonce,
        "itemGuid" to stableId,
        "seriesGuid" to "",
        "seasonGuid" to "",
        "posterPath" to "",
        "mediaGuid" to "$stableId-media",
        "mediaType" to "local",
        "ancestorName" to "",
        "videoGuid" to "$stableId-video",
        "url" to uri.toString(),
        "headers" to hashMapOf<String, String>(),
        "title" to normalizedTitle,
        "seriesTitle" to "",
        "seasonNumber" to 0,
        "tmdbId" to "",
        "episodeNumber" to 0,
        "startPositionMs" to 0L,
        "videoWidth" to 0,
        "videoHeight" to 0,
        "resolution" to "",
        "bitrate" to 0,
        "durationSeconds" to 0,
        "videoCodecName" to "",
        "videoProfile" to "",
        "colorSpace" to "",
        "colorTransfer" to "",
        "colorPrimaries" to "",
        "bitDepth" to 0,
        "isDownloadedFile" to true,
        "externalLocalSource" to true,
        "danmakuAutoSearchAllowed" to false,
        "externalLocalFileSizeBytes" to sizeBytes.coerceAtLeast(0L),
        "preferExternalSubtitle" to false,
        "forceNativeProxy" to false,
        "extremePlaybackEnabled" to false,
        "reliableSeek" to true,
        "seekProbeSummary" to "external-local",
        "playbackMode" to "originalQuality",
        "playbackSpeed" to 1.0,
        "listenVideoModeEnabled" to false,
        "audioTracks" to arrayListOf<HashMap<String, Any?>>(),
        "subtitleTracks" to arrayListOf<HashMap<String, Any?>>(),
        "qualities" to arrayListOf<HashMap<String, Any?>>(),
    )
}
```

- [ ] **Step 2: Preserve old method during transition**

Change `buildExternalLocalVideoIntent()` to call `buildExternalLocalVideoLoadArgs()` internally. This preserves any remaining old callers until Task 7 removes them.

- [ ] **Step 3: Launch `NativePlayerActivity` directly**

In `ExternalLocalVideoActivity.kt`, replace `PlayerLaunchContract.buildExternalLocalVideoIntent(...)` usage with:

```kotlin
val loadArgs = PlayerLaunchContract.buildExternalLocalVideoLoadArgs(
    uri = uri,
    title = displayName,
    sizeBytes = querySizeBytes(uri),
)
val launchIntent = Intent(this, NativePlayerActivity::class.java).apply {
    addFlags(
        Intent.FLAG_ACTIVITY_CLEAR_TOP or
            Intent.FLAG_ACTIVITY_SINGLE_TOP or
            Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
            Intent.FLAG_GRANT_READ_URI_PERMISSION,
    )
    putExtra(NativePlayerActivity.EXTRA_LOAD_ARGS, org.json.JSONObject(loadArgs).toString())
    if (!sourceIntent?.type.isNullOrBlank()) {
        setDataAndType(uri, sourceIntent?.type)
    } else {
        data = uri
    }
    clipData = ClipData.newUri(contentResolver, displayName, uri)
}
```

If `JSONObject(HashMap)` serializes nested `ArrayList<HashMap<...>>` correctly in local compile but not runtime testing, replace it with the project’s existing JSON helper if one exists; otherwise add a small private `toJsonObject` helper in `ExternalLocalVideoActivity.kt` that recursively maps `Map` and `List`.

- [ ] **Step 4: Compile Android**

```powershell
cd android
.\gradlew.bat :app:compileFullDebugKotlin
```

Expected: build successful.

- [ ] **Step 5: Commit**

```powershell
git add android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/PlayerLaunchContract.kt android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/ExternalLocalVideoActivity.kt
git commit -m "refactor: route external local video to native player"
```

### Task 6: 移除 Flutter 播放器 fallback 入口

**Files:**
- Modify: `lib/controllers/item_playback_launcher.dart`
- Modify: `lib/controllers/tv_season_playback_launcher.dart`
- Modify: `lib/pages/play_detail_page.dart`
- Modify: `lib/screens/download_list_screen.dart`
- Modify: `lib/services/embedded_detail_launcher.dart`
- Test: `flutter analyze`

- [ ] **Step 1: Remove `MpvPlayerPage` imports from launchers**

Remove:

```dart
import '../player/mpv_player_page.dart';
import '../ui/app_transitions.dart';
import '../services/embedded_detail_launcher.dart';
```

from launcher files when they only serve old playback fallback.

- [ ] **Step 2: Replace fallback with explicit failure result**

After `PlaybackHost.launch(...)` returns `false`, return `null` and show the existing “准备播放失败/无法启动播放器” top tip where a `BuildContext` is available. Do not push `MpvPlayerPage`.

For non-UI launchers, use:

```dart
return null;
```

because current `NativePlayerBridge.preferNativePlayerShell` is `true`; a false result means platform channel failure.

- [ ] **Step 3: Stop using `EmbeddedDetailLauncher.openFullscreenPlayer` for playback**

In `lib/services/embedded_detail_launcher.dart`, remove `openFullscreenPlayer` after all call sites are gone.

Verify:

```powershell
rg -n "openFullscreenPlayer|MpvPlayerPage\\(" lib
```

Expected: matches only inside old player files scheduled for deletion, or no matches.

- [ ] **Step 4: Analyze**

```powershell
flutter analyze
```

Expected: no new analyzer errors from removed imports or dead references.

- [ ] **Step 5: Commit**

```powershell
git add lib/controllers lib/pages lib/screens lib/services
git commit -m "refactor: remove flutter player fallback launches"
```

### Task 7: 删除旧 Flutter 播放宿主

**Files:**
- Modify: `lib/main.dart`
- Delete: `lib/screens/player_host_screen.dart`
- Delete: `lib/services/player_host_bridge.dart`
- Delete: `lib/player/models/player_host_launch_args.dart`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Delete: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/PlayerActivity.kt`
- Delete: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/FullscreenPlayerActivity.kt`
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/ActivityEmbeddingInstaller.kt`
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/FlutterHostActivity.kt`
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/ParallelWindowCoordinator.kt`
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/PlaybackSessionManager.kt`

- [ ] **Step 1: Remove `/player` route**

In `lib/main.dart`, remove:

```dart
import 'screens/player_host_screen.dart';
```

Remove the `/player` branch:

```dart
if (uri != null && uri.path == '/player') {
  return AppTransitions.leftToRightPageTurnRoute<void>(
    const PlayerActivityRoute(),
    settings: settings,
  );
}
```

Delete `PlayerActivityRoute`.

- [ ] **Step 2: Remove player host channels**

In `FlutterHostActivity.kt`, delete `registerPlayerHostChannel`, `registerPlayerHostStateChannel`, and overrides that only serve `PlayerActivity`. Keep `registerNativePlayerChannel`.

Verify no references:

```powershell
rg -n "player_host|playerHostStateChannel|PlayerActivityRoute|PlayerHostScreen|PlayerHostBridge" lib android/app/src/main/kotlin
```

Expected: no matches.

- [ ] **Step 3: Remove manifest activities**

In `AndroidManifest.xml`, delete `<activity android:name=".PlayerActivity" ...>` and `<activity android:name=".FullscreenPlayerActivity" ...>`.

- [ ] **Step 4: Remove embedding rules and old coordinator state**

Remove `PlayerActivity` / `FullscreenPlayerActivity` references from:

```text
android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/ActivityEmbeddingInstaller.kt
android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/ParallelWindowCoordinator.kt
android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/PlaybackSessionManager.kt
```

Keep `NativePlayerActivity` split rules and native split state.

- [ ] **Step 5: Compile Android and analyze Flutter**

```powershell
flutter analyze
cd android
.\gradlew.bat :app:compileFullDebugKotlin
```

Expected: both pass.

- [ ] **Step 6: Commit**

```powershell
git add lib android/app/src/main
git commit -m "refactor: remove legacy flutter player host"
```

### Task 8: 删除 Flutter 播放 UI 和 Flutter 弹幕渲染层

**Files:**
- Delete: `lib/player/mpv_player_page.dart`
- Delete: `lib/player/page_parts/**`
- Delete: `lib/player/widgets/**`
- Delete: `lib/player/controllers/mpv_player_controller.dart`
- Delete old player-only controllers after import checks
- Delete: `lib/player/services/mpv_proxy_server.dart`
- Delete: `lib/player/services/native_player_bridge.dart`
- Delete: `lib/player/services/native_panel_bridge.dart`
- Delete: `lib/player/services/native_player_launcher.dart`
- Delete: `lib/player/services/player_runtime_preferences_store.dart`
- Delete: `lib/player/models/player_runtime_preferences.dart`
- Delete: `lib/danmaku/controller/**`
- Delete: `lib/danmaku/render/**`
- Modify: `pubspec.yaml`
- Modify tests that target deleted Flutter UI

- [ ] **Step 1: Confirm no app imports old player UI**

```powershell
rg -n "lib/player|../player|../../player|package:fly_player/player" lib test
```

Expected: matches only for files being deleted or for migrated files already moved under `lib/playback`.

- [ ] **Step 2: Delete old UI files**

Delete `MpvPlayerPage`, `page_parts`, old widgets, old services, and player-only models/controllers that no longer have imports.

- [ ] **Step 3: Delete Flutter danmaku render/controller**

Delete:

```text
lib/danmaku/controller/danmaku_controller.dart
lib/danmaku/render/**
```

Do not delete:

```text
lib/danmaku/api/**
lib/danmaku/cache/**
lib/danmaku/models/**
lib/danmaku/parser/danmaku_import_parser.dart
lib/danmaku/settings/**
```

- [ ] **Step 4: Remove unused dependency**

In `pubspec.yaml`, remove:

```yaml
canvas_danmaku: ^0.3.1
```

Run:

```powershell
flutter pub get
```

Expected: dependency resolution succeeds.

- [ ] **Step 5: Remove obsolete tests**

Delete tests that only cover deleted Flutter UI/controller behavior:

```text
test/player_runtime_preferences_store_test.dart
test/player_runtime_controller_test.dart
test/player_ui_controller_test.dart
test/player_controls_chrome_test.dart
test/player_listen_video_presentation_test.dart
test/player_subtitle_controller_test.dart
test/player_session_controller_test.dart
```

Keep tests for migrated contracts:

```text
test/mpv_player_controller_test.dart
test/mpv_local_file_subtitle_test.dart
test/player_source_controller_test.dart
test/player/feiniu_playback_source_bridge_test.dart
test/player/emby_playback_source_bridge_test.dart
```

Rename `test/mpv_player_controller_test.dart` to `test/playback_source_test.dart` after imports are updated.

- [ ] **Step 6: Full verification**

```powershell
flutter analyze
flutter test --concurrency=1
cd android
.\gradlew.bat :app:compileFullDebugKotlin
```

Expected: all pass.

- [ ] **Step 7: Commit**

```powershell
git add lib test pubspec.yaml pubspec.lock android/app/src/main
git commit -m "refactor: delete deprecated flutter playback chain"
```

### Task 9: 文档与评审计划收口

**Files:**
- Modify: `docs/codex-review/FIX-PLAN.md`
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`
- Modify or create: `docs/playback-platform-host-contract.md`

- [ ] **Step 1: Update `FIX-PLAN.md`废弃区说明**

Replace the broad deletion note with a precise statement:

```markdown
Flutter 播放页面、旧 PlayerActivity 宿主、Flutter 弹幕 render/controller 已删除；播放契约已迁至 `lib/playback/`。`lib/danmaku/api/`、弹幕源 store、弹幕导入 parser、mpv 设置/书签/截图 store 为活代码，不属于废弃区。
```

- [ ] **Step 2: Update project guidance**

In `AGENTS.md` and `CLAUDE.md`, replace the old `MpvPlayerPage` mixin architecture section with:

```markdown
### Player architecture

实际播放走平台宿主接口 `lib/playback/playback_host.dart`。Android 实现通过 `NativePlaybackHost` / `NativePlayerBridge` 拉起 `NativePlayerActivity`，原生壳只消费 `MpvMediaSource.toMap()` 产出的 loadArgs JSON 与反向通道回调。新增后端不得直接依赖 Android Activity；新增平台只实现 `PlaybackHost`。
```

- [ ] **Step 3: Add platform host contract doc**

Create `docs/playback-platform-host-contract.md` with sections:

```markdown
# Playback Platform Host Contract

## Dart side
- `MediaBackend.getPlayback()` returns backend-neutral playback facts.
- Backend bridge assembles `MpvMediaSource`.
- UI launchers call `PlaybackHost.launch()`.

## Platform side
- Platform host receives `loadArgs` JSON.
- Platform host reports progress through reentry callbacks.
- Platform host requests source reload through `resolvePlayback` / `reloadServerSession`.

## Compatibility
- Android uses `NativePlayerActivity`.
- iOS/macOS/Windows must implement equivalent host behavior behind `PlaybackHost`.
```

- [ ] **Step 4: Verify docs mention no old route**

```powershell
rg -n "MpvPlayerPage|/player|PlayerActivity|Flutter 播放器" AGENTS.md CLAUDE.md docs
```

Expected: matches only historical migration docs or explicitly marked removed references.

- [ ] **Step 5: Commit**

```powershell
git add docs AGENTS.md CLAUDE.md
git commit -m "docs: document native playback host contract"
```

## 4. Final Verification

Run after all tasks:

```powershell
flutter pub get
flutter analyze
flutter test --concurrency=1
cd android
.\gradlew.bat :app:compileFullDebugKotlin
.\gradlew.bat :app:testFullDebugUnitTest
```

Expected:

- Flutter analysis has no errors introduced by deleted player imports.
- Flutter tests pass after obsolete UI-only tests are removed or migrated.
- Android Kotlin compile succeeds with no `PlayerActivity` / `FullscreenPlayerActivity` references.
- Android unit tests pass.

Manual smoke tests on Android:

- 从详情页播放电影，进入 `NativePlayerActivity`。
- 从剧集详情播放一集，原生壳选集面板可见，切集原地换源。
- 从下载列表播放已下载文件，原生壳播放本地文件。
- 从系统文件管理器用 Fly Player 打开本地视频，直接进入 `NativePlayerActivity`。
- 原生壳内切画质/音轨/字幕后，反向通道能重载或本地切轨。
- 原生壳弹幕自动匹配、手动导入、已保存弹幕源加载可用。
- 设置页修改 mpv 画质/音频设置后，原生壳能读取最新设置。

## 5. Rollback Strategy

每个任务独立提交。若任一阶段发现播放回归：

- 回滚最近一个任务提交。
- 不回滚已经完成并通过验证的契约迁移提交。
- 若 Task 7/8 失败，保留旧 Flutter 宿主，继续使用 Task 1-6 的新 `lib/playback` 边界。

## 6. Self-Review

Spec coverage:

- 覆盖 `FIX-PLAN.md` 三项确认：旧宿主入口、`MpvMediaSource` 抽离、弹幕 API/store/parser 保留。
- 覆盖当前发现的额外风险：外部本地视频、嵌入式 fallback、活 store 误删、未来多平台边界。
- 覆盖删除后的验证：Flutter analyze/test、Android Kotlin compile/unit test、真机烟测。

Placeholder scan:

- 本计划不使用空白承诺式标记或空泛“补错误处理”步骤。
- 每个任务都有明确文件、命令和预期结果。

Type consistency:

- `PlaybackHost.launch()` 使用 `MpvMediaSource`、`PlayInfoData`、`NasProvider`，与现有 `NativePlayerBridge.maybeLaunch()` 参数保持可映射。
- `MpvMediaSource` 迁移保持类名和序列化字段不变，Android `loadArgs` 不需要同步改字段。
