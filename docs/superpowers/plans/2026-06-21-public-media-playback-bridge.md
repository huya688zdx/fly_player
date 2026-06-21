# 公共播放桥接 + 单条目 launcher 灰度迁移 Implementation Plan（Phase 6 第二子阶段）

> 设计：`docs/superpowers/specs/2026-06-21-public-media-playback-bridge-design.md`
> 用户 2026-06-21 决策：**方案 B 分步**；上下文经 `getPlayback` 返回 `MediaPlaybackResolution { bundle, backendContext }` 承载（中立 bundle 不含上下文字段）。

**Goal:** B-1 交付可单测的飞牛播放桥接器（不碰线上 launcher）；B-2 再灰度把 `ItemPlaybackLauncher`（仅单条目）切到 `getPlayback` + 桥接器，需 `flutter run` 实机验证后才收口。

**Architecture:**
- 中立层（`lib/media_backend/playback/`）新增 `MediaPlaybackResolution`（bundle + 不透明 `MediaPlaybackBackendContext?`）与标记类型 `MediaPlaybackBackendContext`。`MediaBackend.getPlayback` 返回 `MediaPlaybackResolution`。
- 飞牛层（`lib/media_backend/feiniu/`）新增 `FeiniuPlaybackContext implements MediaPlaybackBackendContext`，持 `getPlayback` 已取的 raw facts（`FeiniuApi` / `PlayInfoData` / `PlaybackStreamData` / raw 选中画质·音轨·字幕 / directUrl），单次网络。
- 桥接器（`lib/player/controllers/`）新增 `FeiniuPlaybackSourceBridge`，downcast `FeiniuPlaybackContext`，复刻 launcher 的 `buildInitialPlaybackResult` + `MpvMediaSource` 装配。**media_backend 不依赖播放器层；桥接器单向依赖 media_backend。**

**Tech Stack:** Flutter / Dart，`flutter_test`，现成 `PlayerSourceController.buildInitialPlaybackResult` / `MpvMediaSource`。

---

## File Structure

- Create: `lib/media_backend/playback/media_playback_resolution.dart`（`MediaPlaybackResolution` + `MediaPlaybackBackendContext` 标记）
- Modify: `lib/media_backend/media_backend.dart`（`getPlayback` 返回 `MediaPlaybackResolution`）
- Create: `lib/media_backend/feiniu/feiniu_playback_context.dart`（`FeiniuPlaybackContext`）
- Modify: `lib/media_backend/feiniu/feiniu_media_backend.dart`（`getPlayback` 返回 resolution + 装上下文）
- Modify: `test/media_backend/feiniu_playback_backend_test.dart`（断言改 `.bundle`，新增上下文 raw facts 断言）
- Create: `lib/player/controllers/feiniu_playback_source_bridge.dart`（桥接器）
- Create: `test/player/feiniu_playback_source_bridge_test.dart`
- Modify: `docs/superpowers/public-media-frontend-status.md`

---

## 阶段 B-1（可单测，不碰播放链路）

### Task 1: 中立 resolution + 飞牛上下文，getPlayback 返回 resolution

**Files:**
- Create: `lib/media_backend/playback/media_playback_resolution.dart`
- Modify: `lib/media_backend/media_backend.dart`
- Create: `lib/media_backend/feiniu/feiniu_playback_context.dart`
- Modify: `lib/media_backend/feiniu/feiniu_media_backend.dart`
- Modify: `test/media_backend/feiniu_playback_backend_test.dart`

- [ ] **Step 1: 写失败测试**
  - 中立模型测试：`MediaPlaybackResolution` 持有 `bundle` 和 `backendContext`（`MediaPlaybackBackendContext?`）。
  - 改 `feiniu_playback_backend_test.dart` 现有 6 测试：`backend.getPlayback(...)` 返回 resolution，断言改 `result.bundle.xxx`。
  - 新增断言：`result.backendContext` 是 `FeiniuPlaybackContext`，且其 `playbackStream` / 选中 raw 画质·音轨·字幕 与 fake 输入一致（不泄漏到 bundle）。

- [ ] **Step 2: 运行确认失败**
  - `flutter test test\media_backend\feiniu_playback_backend_test.dart` → FAIL（缺类型 / 返回类型不符）。

- [ ] **Step 3: 实现**
  - `MediaPlaybackBackendContext`：空标记 `abstract class`（或 `abstract interface class`）。
  - `MediaPlaybackResolution`：`final MediaPlaybackBundle bundle; final MediaPlaybackBackendContext? backendContext;` const 构造。
  - `MediaBackend.getPlayback` 返回 `Future<MediaPlaybackResolution>`。
  - `FeiniuPlaybackContext implements MediaPlaybackBackendContext`：持 `FeiniuApi api`、`PlayInfoData playInfo`、`PlaybackStreamData playbackStream`、`PlaybackQualityOption? selectedQuality`、`AudioTrackOption? selectedAudio`、`SubtitleTrackOption? selectedSubtitle`、`String directUrl`、`String effectiveSourceId`、`String videoTrackId`。
  - `FeiniuMediaBackend.getPlayback`：编排不变，但**额外保留选中的 raw option**（当前只算了公共 selected，需回找 raw 音轨/字幕——已有 `_rawQualityFor`，照葫芦补 `_rawAudioFor` / `_rawSubtitleFor` 按 guid 匹配），装进 `FeiniuPlaybackContext`，返回 `MediaPlaybackResolution(bundle, context)`。

- [ ] **Step 4: 运行测试** → PASS。
- [ ] **Step 5: 全 media_backend 套件** `flutter test test\media_backend\ --concurrency=1` → all PASS。
- [ ] **Step 6: analyze** `flutter analyze lib\media_backend test\media_backend` → No issues。
- [ ] **Step 7: 提交**
  ```bash
  git status --short
  git add lib/media_backend/playback/media_playback_resolution.dart lib/media_backend/media_backend.dart lib/media_backend/feiniu/feiniu_playback_context.dart lib/media_backend/feiniu/feiniu_media_backend.dart test/media_backend/feiniu_playback_backend_test.dart
  git diff --cached --name-only
  git commit -m "feat: return playback resolution with opaque backend context"
  ```

### Task 2: 飞牛播放桥接器（装配 MpvMediaSource，不碰 launcher）

**Files:**
- Create: `lib/player/controllers/feiniu_playback_source_bridge.dart`
- Test: `test/player/feiniu_playback_source_bridge_test.dart`

- [ ] **Step 1: 审计现有装配口径**（写桥接器前必读，逐字复刻，勿臆造）：
  - `lib/controllers/item_playback_launcher.dart` `_resolve()` 尾段（约 391~459+）：`PlaybackResumePositionResolver` 已在 backend 算过 → 桥接器用 `bundle.startPosition`；`buildInitialPlaybackResult(...)` 入参全来自上下文 raw facts；`resolvedStartPosition = !reliableSeek && initialSeconds>0 ? Duration.zero : ...`；`MpvMediaSource(...)` 全字段（loadNonce/itemGuid/seriesGuid/seasonGuid/posterPath/mediaGuid/videoGuid/directLinkQualityIndex/videoWidth/videoHeight/proxySessionId/playLink/serverSessionHlsTimeSeconds/url/headers/title/seriesTitle/seasonNumber/tmdbId/episodeNumber/startPosition/audioTrackIndex/subtitleTrackIndex/audioTrackGuid/subtitleTrackGuid/resolution...）。
  - `embeddedSubtitleTrackIndex` 计算（launcher 371~389）、`playbackVideoGuid` / `playbackResolution` / `playbackBitrate` 口径。
  - `PlayerInitialPlaybackResult` 字段（playableSource/mediaGuid/videoGuid/playLink/serverSessionHlsTimeSeconds/playbackMode）。

- [ ] **Step 2: 写失败测试**
  - fake `FeiniuApi`（复用 backend test 的 seam 思路）+ 构造一个 `FeiniuPlaybackContext` + 对应 `MediaPlaybackBundle`，调 `FeiniuPlaybackSourceBridge().assemble(bundle: ..., context: ...)`，断言产出 `MpvMediaSource` 关键字段与 launcher 现有口径一致（原画路径、直链路径各一例；headers/mediaGuid/videoGuid/directLinkQualityIndex/startPosition/轨道 index+guid）。

- [ ] **Step 3: 运行确认失败** → FAIL（缺桥接器）。

- [ ] **Step 4: 实现 `FeiniuPlaybackSourceBridge`**
  - `Future<MpvMediaSource> assemble({required MediaPlaybackBundle bundle, required FeiniuPlaybackContext context})`。
  - 内部调 `const PlayerSourceController().buildInitialPlaybackResult(api: context.api, directUrl: context.directUrl, mediaGuid: context.effectiveSourceId, videoGuid: context.videoTrackId, playbackStream: context.playbackStream, quality: context.selectedQuality, selectedAudio: context.selectedAudio, selectedSubtitle: context.selectedSubtitle, startPosition: bundle.startPosition)`。
  - 复刻 `embeddedSubtitleTrackIndex` / `resolvedStartPosition` / `playbackResolution` / `playbackBitrate` 计算，装 `MpvMediaSource`，标题/封面用 `formatPlayerTitleFromPlayItem` / `resolvePlayerArtworkPathForPlayItem`（输入 `context.playInfo.item`）。
  - **不导航、不打开页面**，只返回 `MpvMediaSource`。

- [ ] **Step 5: 运行测试** → PASS。
- [ ] **Step 6: analyze** `flutter analyze lib\player\controllers\feiniu_playback_source_bridge.dart test\player\feiniu_playback_source_bridge_test.dart` → No issues。
- [ ] **Step 7: 提交**
  ```bash
  git add lib/player/controllers/feiniu_playback_source_bridge.dart test/player/feiniu_playback_source_bridge_test.dart
  git diff --cached --name-only
  git commit -m "feat: assemble MpvMediaSource via Feiniu playback bridge"
  ```

### Task 3: B-1 看板收口

- [ ] 更新 `docs/superpowers/public-media-frontend-status.md`：记 Task 1/2 commit + 验证；标注 B-2 待实机放行。
- [ ] `git diff -- docs/...` 仅状态更新。
- [ ] 提交 `docs: record Phase 6 playback bridge B-1 progress`。

---

## 阶段 B-2（灰度翻单条目 launcher，需实机，**另行确认后再开**）

> B-1 收口后，单独向用户确认再执行 B-2。B-2 才碰线上播放链路。

- [ ] 把 `ItemPlaybackLauncher._resolve()` 改成：`final resolution = await backend.getPlayback(MediaPlaybackRequest(...))` → `final source = await FeiniuPlaybackSourceBridge().assemble(bundle: resolution.bundle, context: resolution.backendContext as FeiniuPlaybackContext)`。
- [ ] `open()` 用 `source` 走 `MpvPlayerPage`；`resolveForNative()` 用 `source` 产原生壳 map（两出口都从桥接器产物来）。
- [ ] 保留：本地下载优先（`local_download_source_resolver`）、弹幕预取、进度写回、原生壳重载字段——本阶段不抽，仍在 launcher 内对接 `source`。
- [ ] **不动 `TvSeasonPlaybackLauncher`。**
- [ ] `flutter analyze` 全量无新增问题；`flutter test test/media_backend/ test/player/ --concurrency=1` PASS。
- [ ] **`flutter run` 实机验证单条目**：默认播放、续播位、画质切换、音轨切换、字幕关闭/切换、外部字幕、原生壳反向重载，全部与迁移前一致。
- [ ] 看板记 B-2 收口 + 实机结论。

---

## Self-Review Checklist

- [ ] 中立 `MediaPlaybackBundle` 仍不含 raw / 飞牛字段；上下文只在 `MediaPlaybackResolution.backendContext`，类型为 `MediaPlaybackBackendContext`（无飞牛命名）。
- [ ] `lib/media_backend` 不 import `package:flutter/material.dart`、`MpvMediaSource`、`PlayerSourceController`、`Navigator`。
- [ ] 桥接器住 `lib/player/controllers/`，单向依赖 `lib/media_backend`。
- [ ] 桥接器用 raw facts 调 `buildInitialPlaybackResult`，不直接信任 `MediaPlaybackSource.url`。
- [ ] B-1 不修改任何 launcher 文件。
- [ ] `HANDOFF.md` 保持未跟踪未暂存。
