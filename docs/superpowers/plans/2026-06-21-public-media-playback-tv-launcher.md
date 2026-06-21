# Phase 6 桥接子阶段 B-3 实施计划：TvSeasonPlaybackLauncher 迁移

设计：`docs/superpowers/specs/2026-06-21-public-media-playback-tv-launcher-design.md`
日期：2026-06-21
原则：每个 Task 可编译、可单测、单独提交；提交前查 `git status --short` 与 `git diff --cached --name-only`，只暂存当前 Task 文件，不夹带 `HANDOFF.md` 等未跟踪文件。

## Task 1：补两个中立 request 字段 + 桥接器/backend 分流（不碰 launcher）

**改动文件**
- `lib/media_backend/playback/media_playback.dart`：`MediaPlaybackRequest` 加可选字段
  - `final String seriesId;`（默认 `''`）
  - `final bool restartWhenCompleted;`（默认 `false`）
  - 补构造参数与字段文档（中立措辞，禁止 `seriesGuid`/`Feiniu`/`Emby`）。
- `lib/player/controllers/feiniu_playback_source_bridge.dart`：`seriesGuid` 装配改为
  `request.seriesId.trim().isNotEmpty ? request.seriesId.trim() : playInfo.grandGuid.trim()`。
- `lib/media_backend/feiniu/feiniu_media_backend.dart`：`getPlayback` 续播分流——
  - `restartWhenCompleted == false`：维持现状（`resetCompletedToBeginning: false`）。
  - `restartWhenCompleted == true`：算 `completed = duration>0 && ((duration - networkPositionSeconds) <= 0 || item.isWatched == 1)`，传 `networkCompleted: completed, resetCompletedToBeginning: true`。

**测试**
- `test/player/feiniu_playback_source_bridge_test.dart`：加 2 条——显式 `seriesId` 覆盖 → `source.seriesGuid` 为该值；`seriesId` 空 → 回退 `grandGuid`（保 Item 现状）。
- `test/media_backend/feiniu_playback_backend_test.dart`：加 2 条——`restartWhenCompleted: true` 且 `isWatched==1`（或 ts>=duration）→ `bundle.startPosition == Duration.zero`；`restartWhenCompleted: false`（默认）→ 维持网络位（不归零），保 B-2 现状。

**验证**
- `flutter test test/media_backend/ test/player/ --concurrency=1`
- `flutter analyze lib/media_backend lib/player/controllers/feiniu_playback_source_bridge.dart test/media_backend test/player`

**提交**：单独提交（模型 + 桥接器 + backend + 测试）。此 Task **不改任何 launcher**，Item/B-2 路径默认值下行为零变化。

## Task 2：TvSeasonPlaybackLauncher._resolveWithProvider 切桥接器

**改动文件**：`lib/controllers/tv_season_playback_launcher.dart`

把 `_resolveWithProvider`（205~427）内部网络解析整体替换为：

```
final request = MediaPlaybackRequest(
  itemId: itemGuid,
  fallbackTitle: seriesTitle,          // 同时充当 title 与 seriesTitle 回退（见设计 §4）
  seriesId: seriesGuid,                // 缺口 1：显式剧集 id 优先
  restartWhenCompleted: true,          // 缺口 2：TV 已看完 → 从头重播
  qualityIndex: qualityIndex,
  qualityId: qualityMediaGuid,
  audioTrackId: overrideAudioGuid,
  subtitleTrackId: (overrideSubtitleGuid != null && overrideSubtitleGuid.isNotEmpty)
      ? overrideSubtitleGuid : null,
  subtitleTrackExplicitlyDisabled: overrideSubtitleGuid == '',
);
final backend = FeiniuMediaBackend(FeiniuApi(provider));
final resolution = await backend.getPlayback(request);
final context = resolution.backendContext;
if (context is! FeiniuPlaybackContext) return null;
final source = await const FeiniuPlaybackSourceBridge()
    .assemble(request: request, bundle: resolution.bundle, context: context);
return (source: source, playInfo: context.playInfo, title: source.title);
```

- 返回形状 `({source, playInfo, title})` 不变；`open()` 与 `resolveForNative()` 两出口无需改。
- 删除因 body 抽走而未用的 import（`stream_track_data` / `play_detail_track_selector` / `playback_resume_position_resolver` / `player_artwork_path_resolver` / `player_title_formatter` / `playback_stream` / `app_log_service` / `app_error_reporter` / `app_exception` / `player_source_controller` 等，按 analyze 实际未用清单删）。
- **不动**：`open()` 原生壳 `maybeLaunch(episodes)`、`resolveForNative()` 本地下载优先 + 弹幕预取 + loadArgs、页面侧反向通道。

**验证**
- `flutter analyze lib/controllers/tv_season_playback_launcher.dart` → No issues
- 全量 `flutter analyze`（对比基线 17 条历史无关项，不应新增）
- `flutter test test/media_backend/ test/player/ --concurrency=1`（+ 既有 playback 测试）

**提交**：单独提交。

## Task 3：看板更新 + 交付实机验证

- 更新 `docs/superpowers/public-media-frontend-status.md`：B-3 记录、提交 hash、测试命令、待用户实机验证清单（设计 §6 R3）。
- 交用户 `flutter run` 实机验证 TV 季/集：默认播放、续播位、**已看完集从头重播**、画质/音轨/字幕切换、外部字幕、原生壳选集 + 切集换源、原生壳画质回传。
- 验证通过后由用户确认，再考虑后续（Codex 深审 / 下一阶段）。

**提交**：看板更新单独提交。

## 明确不做

- 不接 Emby；不写 `if (isEmby)`。
- `lib/media_backend` 不构造 `MpvMediaSource`。
- 不动下载、本地播放、play stats、`MpvPlayerPage` 深层 mixin。
- 不动 TV 页面侧反向通道、选集导航、弹幕预取、进度写回。
- 不夹带 `HANDOFF.md` 或其它工作区未跟踪/无关文件。
