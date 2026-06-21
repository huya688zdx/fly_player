# Phase 6 桥接子阶段 B-4 实施计划：原生壳反向重载收口

设计：`docs/superpowers/specs/2026-06-21-public-media-playback-reverse-reload-design.md`
日期：2026-06-21
原则：每个 Task 可编译、可单测、单独提交；提交前查 `git status --short` 与
`git diff --cached --name-only`，只暂存当前 Task 文件，不夹带 `HANDOFF.md` /
`MpvPlaybackController.kt` 等工作区未跟踪/Codex 改动文件。

## Task 1：中立 reload 意图模型（不碰任何调用方）

**改动文件**
- 新建 `lib/media_backend/playback/media_session_reload.dart`：`MediaSessionReloadIntent`
  （`audioTrackId` / `subtitleTrackId` / `subtitleDisabled` / `qualityIndex` / `startPosition`，
  全 `const`、中立命名，无 `mediaGuid`/`Feiniu`/`mpv`）。附字段 doc（三态字幕约定）。
- 新建 `test/media_backend/media_session_reload_test.dart`：默认值（保留语义）/ 显式各项 /
  字幕三态（切轨 vs 关闭 vs 保留）。

**验证**
- `flutter test test/media_backend/media_session_reload_test.dart`
- `flutter analyze lib/media_backend/playback/media_session_reload.dart test/media_backend/media_session_reload_test.dart` → No issues

**提交**：单独提交。此 Task 无任何调用方消费 → 零行为变化。

## Task 2：reload 桥接器 + 反向通道改吃中立意图

**改动文件**
- `lib/services/native_reentry_support.dart`：`reloadServerSession` 签名改为
  `(NasProvider nas, {required String currentLoadArgs, required MediaSessionReloadIntent intent})`；
  内部把 `intent` 映射成现有 `PlayerServerReloadRequest`
  （`audioGuid: intent.audioTrackId`、`subtitleGuid: intent.subtitleDisabled ? '' :
  intent.subtitleTrackId`、`quality: source.qualities[intent.qualityIndex]`、
  `startPosition: intent.startPosition ?? source.startPosition`）。**reload 内核调用、
  `preserveEpisodesForServerReload`、返回形状全不变。** 更新类/方法 doc 定位为「飞牛反向重载
  桥接器（Emby 可复用切口）」。
- `lib/services/native_player_bridge.dart`：`bindReentry` 的 `onReloadServerSession` 函数类型
  收为 `(String currentLoadArgs, MediaSessionReloadIntent intent)`；`case 'reloadServerSession'`
  把 channel args（带 key=override / 空串=关闭 / 不带=保留）组装成 `MediaSessionReloadIntent`
  再下发。**channel 协议（Kotlin 侧仍发 audioGuid/subtitleGuid/qualityIndex/startPositionMs）不变。**
- 4 处页面闭包改为 `(currentLoadArgs, intent) => NativeReentrySupport.reloadServerSession(
  nas, currentLoadArgs: currentLoadArgs, intent: intent)`：
  - `lib/pages/tv_season_detail_page.dart:1413`
  - `lib/pages/tv_detail_page.dart:940`
  - `lib/pages/play_detail_page.dart:1439`
  - `lib/controllers/item_playback_launcher.dart:127`

**测试**
- 若有现成 reload 单测则扩；否则补「intent→PlayerServerReloadRequest 映射 + 三态字幕」
  纯函数断言（把映射抽成可测静态助手，避免引入 FeiniuApi fake）。
- 既有 `test/services/native_reentry_support_test.dart`（`preserveEpisodesForServerReload`）
  保持通过。

**验证**
- `flutter analyze lib/services/native_reentry_support.dart lib/services/native_player_bridge.dart
  lib/pages/tv_season_detail_page.dart lib/pages/tv_detail_page.dart lib/pages/play_detail_page.dart
  lib/controllers/item_playback_launcher.dart` → No issues
- 全量 `flutter analyze`（对比基线 17 条，零新增）
- `flutter test test/media_backend/ test/services/ --concurrency=1`

**提交**：单独提交。

## Task 3：看板更新 + 交付实机验证

- 更新 `docs/superpowers/public-media-frontend-status.md`：B-4 记录、提交 hash、测试命令、
  待用户实机验证清单。
- 交用户 `flutter run` 实机验证原生壳转码态：切音轨（不动画质/字幕）、切字幕、关字幕、
  切画质（保留音轨/字幕）、续播位不丢、选集面板不清空（回归 Bug C 点）。
- 验证通过后交 Codex 深审收口。

**提交**：看板更新单独提交。

## 明确不做

- 不搬 `reloadServerPlaySession` 内核进 `media_backend`（备选 B 留 Emby）。
- `lib/media_backend` 不构造 `MpvMediaSource`；不接 Emby；UI 不写 `if (isEmby)`。
- 不动原生 Kotlin channel 协议；不碰 `MpvPlaybackController.kt`、`HANDOFF.md`。
- 不动选集面板 / 外挂字幕 / 进度回写 / 弹幕 / 设置同步等其余反向方法。
- 不改下载、本地播放、play stats。
