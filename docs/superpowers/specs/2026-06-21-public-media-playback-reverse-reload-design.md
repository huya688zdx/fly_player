# Phase 6 桥接子阶段 B-4 设计：原生壳反向重载收口

日期：2026-06-21
前序：B-1（桥接器）`d80d8e0`/`cd3b4bd`、B-2（Item launcher）`99d338d`、B-3（TV launcher）`3acbc69`/`e567e8a`、切集状态修复 `24d51e4`/`6ff6509`/`bb4d0c0` 系列。
范围决策：用户 2026-06-21 选「B-4：反向重载收口（设计先行）」。

## 1. 背景：反向通道当前拓扑

原生壳（独立 task、无共享 FlutterEngine）经 `NativePlayerBridge.bindReentry`
（`lib/services/native_player_bridge.dart`）回调 Flutter 编排层。与**播放解析**相关的
反向方法有两条，其余（选集面板数据、外挂字幕落盘、进度回写、弹幕、设置同步）与播放源
解析无关，**不在 B-4 范围**。

### 路径 1：`resolvePlayback`（选集 / 切版本）—— 已在抽象上 ✅

`resolvePlayback` → 页面闭包（`tv_season_detail_page.dart:1364` / `tv_detail_page.dart` /
`item_playback_launcher.dart` / `play_detail_page.dart` / `download_list_screen.dart`）
→ `TvSeasonPlaybackLauncher.resolveForNative` / `ItemPlaybackLauncher.resolveForNative`
→ **`FeiniuMediaBackend.getPlayback(MediaPlaybackRequest)` + `FeiniuPlaybackSourceBridge.assemble`**。

B-2/B-3 已把这条迁到 getPlayback + 桥接器；切集轨道/画质继承也是通过中立
`MediaPlaybackRequest.preferred*` 字段流转。**这条路径已经收口。**

### 路径 2：`reloadServerSession`（转码态切音轨 / 字幕 / 画质）—— 未在抽象上 ❌

`reloadServerSession` → 页面闭包（`tv_season_detail_page.dart:1413` /
`tv_detail_page.dart:940` / `play_detail_page.dart:1439` / `item_playback_launcher.dart:127`，
四处闭包形状一致）→ **`NativeReentrySupport.reloadServerSession`**
（`lib/services/native_reentry_support.dart:339`）：

1. 解析 `currentLoadArgs`（即上次回传的 `MpvMediaSource.toMap()`）→ `MpvMediaSource.fromMap`；
2. 据此重建 `PlayerSourceSnapshot`（飞牛 raw facts：mediaGuid/videoGuid/proxySessionId/…）；
3. 直接调 **`PlayerSourceController.reloadServerPlaySession`**
   （`lib/player/controllers/player_source_controller.dart:346`）——「按所选音轨+字幕+画质
   重建服务端会话，**保留**未指定项」；
4. 把结果 `copyWith` 回 `MpvMediaSource`，`preserveEpisodesForServerReload` 并回 `episodes`，
   回传 `{'loadArgs': jsonEncode(...)}`，原生原地换源。

**问题**：这条路径完全绕过 `MediaBackend`。没有中立请求模型，飞牛/mpv 概念
（mediaGuid/videoGuid/proxySessionId/qualityIndex）裸流；将来接 Emby 时，
「转码态切轨/切画质重载会话」没有可复用的中立切口。

## 2. 设计张力：为什么不能直接搬进 backend

`PlayerSourceController.reloadServerPlaySession` 是 **player 层 + 飞牛专属 + 产出 mpv 态**
的深逻辑（`getStreamTrackData` → `getPlaybackStream` → `mergePlaybackQualitiesWithStreamTrackData`
→ track 选择 → `createServerPlaySession` → `buildPlayableSource` → 代理会话 / headers
→ `PlayerServerReloadResult`，约 150 行）。把它搬进 `FeiniuMediaBackend` 会同时撞上三条硬约束：

- `lib/media_backend` **不得构造 `MpvMediaSource`**（reload 结果就是新的 mpv 态）；
- **不迁 `MpvPlayerPage` 深层 / player 控制器深层逻辑**；
- 桥接器（mpv 装配）必须留在 player/controller 层。

且 reload 的**输入**是「当前 `MpvMediaSource`」（loadArgs），这本身是 player 层产物，
无法塞进中立 request。所以 B-4 **不是搬代码**，而是**在反向通道与 player 层之间补一个中立切口**。

## 3. 推荐方案 A：中立 reload 意图 + 命名「反向重载桥接器」（薄收口）

把 getPlayback+桥接器的「中立请求 / player 层桥接」分层**对称复刻**到 reload 路径，但只补
中立切口、不动 reload 内核：

### 3.1 中立模型（`lib/media_backend/playback/`）

新建 `media_session_reload.dart`：

```dart
/// 服务端会话重载意图（中立）：转码 / 服务端托管态下，只改指定项、保留其余。
/// 不出现 mediaGuid/videoGuid/proxySession 等后端私有名；audio/subtitle 用中立 trackId。
class MediaSessionReloadIntent {
  const MediaSessionReloadIntent({
    this.audioTrackId,          // null=保留当前音轨
    this.subtitleTrackId,       // null=保留；空串语义见 subtitleDisabled
    this.subtitleDisabled = false, // true=显式关闭字幕
    this.qualityIndex,          // null=保留当前画质；否则切到候选档序号
    this.startPosition,         // null=保留当前续播位
  });
  final String? audioTrackId;
  final String? subtitleTrackId;
  final bool subtitleDisabled;
  final int? qualityIndex;
  final Duration? startPosition;
}
```

- 与 `MediaPlaybackRequest` 同层、同「中立命名」纪律。
- 字幕三态沿用既有约定：`subtitleTrackId` 非空=切到该轨；`subtitleDisabled==true`=关闭；
  两者皆空/false=保留服务端默认。

### 3.2 player 层桥接（沿用现有文件，正名为「反向重载桥接器」）

`NativeReentrySupport.reloadServerSession` **正式定位为「飞牛反向重载桥接器」**——
它就是 reload 路径上 `FeiniuPlaybackSourceBridge` 的对位物：消费中立
`MediaSessionReloadIntent` + 当前 `MpvMediaSource`，调飞牛 `reloadServerPlaySession`
内核，产出新 `MpvMediaSource`。改动仅两点：

1. 签名从松散命名参数（`audioGuid/subtitleGuid/qualityIndex/startPositionMs`）改为接收
   `MediaSessionReloadIntent intent`（+ `currentLoadArgs`）。内部把
   `intent.audioTrackId`→`request.audioGuid`、`subtitleDisabled?'':intent.subtitleTrackId`
   →`request.subtitleGuid`、`intent.qualityIndex`、`intent.startPosition` 映射给现有
   `PlayerServerReloadRequest`（飞牛私有名只在桥接器内部出现，对齐 `FeiniuPlaybackSourceBridge`
   把中立 request 映射成飞牛调用的纪律）。
2. 类/方法 doc 注明：这是 Emby 可复用的反向重载切口；接 Emby 时新增
   `EmbyReentrySupport.reloadServerSession`（或统一 `MediaPlaybackReloadBridge` 接口的
   Emby 实现），消费同一 `MediaSessionReloadIntent`，UI / 原生侧 / 反向通道**零改动**。

### 3.3 反向通道接线（`native_player_bridge.dart` + 4 处页面闭包）

- `bindReentry` 的 `onReloadServerSession` 函数类型签名从 4 个松散命名参数收成
  `(String currentLoadArgs, MediaSessionReloadIntent intent)`；`case 'reloadServerSession'`
  处把 channel args（`audioGuid`/`subtitleGuid`/`qualityIndex`/`startPositionMs` 的
  「带 key=override，空串=关闭」语义）组装成 `MediaSessionReloadIntent` 再下发。
- 4 处页面闭包（tv_season / tv_detail / play_detail / item_launcher）相应改为
  `(currentLoadArgs, intent) => NativeReentrySupport.reloadServerSession(nas,
  currentLoadArgs: currentLoadArgs, intent: intent)`。**原生 Kotlin 侧 channel 协议不变**
  （仍发 audioGuid/subtitleGuid/qualityIndex/startPositionMs），组装中立意图发生在 Dart 入口。

### 3.4 收口后效果

- 反向通道两条播放解析路径都经中立请求模型（`MediaPlaybackRequest` /
  `MediaSessionReloadIntent`）流转；飞牛 raw facts 只在 player 层桥接器内部出现。
- Emby reuse：getPlayback+assemble（已就绪）+ reload 桥接（本期补切口）两个 seam 齐活，
  接 Emby 时各加一个后端实现即可，反向通道协议 / UI / 原生侧不改。
- reload 内核（`reloadServerPlaySession`）原地不动——零行为变化、零回归面。

## 4. 已否决的备选

- **备选 B：把 `reloadServerPlaySession` 搬进 `FeiniuMediaBackend.reloadPlaybackSession`，
  返回中立 bundle + context，桥接器 reassemble 出 mpv 态。** 对称性最强，但要把 player 层
  150 行深逻辑拆成「事实采集（backend）/ 会话创建 + mpv 装配（桥接器）」两段——
  撞「不迁深层」「media_backend 不构造 mpv」约束，回归面大，单后端下纯增间接层、收益有限。
  **留待真正接 Emby、由第二后端倒逼时再做**（与 Phase 5 页面迁移暂缓同一判断逻辑）。
- **备选 C：维持现状，只补 doc。** 不补中立模型则 reload 路径始终是抽象外的孤儿，
  与 B-2/B-3 收口目标不一致；否决。

## 5. 测试与验证

- 新增 `test/media_backend/media_session_reload_test.dart`：意图模型字段 / 三态字幕默认值。
- `NativeReentrySupport.reloadServerSession` 既有行为（含 `preserveEpisodesForServerReload`
  并回 episodes）必须保持——若有现成 reload 单测则扩断言；新增 fake seam 成本高，
  优先靠「意图→`PlayerServerReloadRequest` 映射」的纯函数单测 + analyze 兜底。
- `flutter analyze`（全量，对比基线 17 条历史无关项，零新增）。
- 交用户 `flutter run` 实机验证：原生壳转码态切音轨 / 切字幕 / 关字幕 / 切画质，
  各自只改目标项、保留其余、续播位不丢、选集面板（episodes）不清空（回归 Bug C 验证点）。

## 6. 明确不做

- 不搬 `reloadServerPlaySession` 内核进 `media_backend`（备选 B 留给 Emby）。
- `lib/media_backend` 不构造 `MpvMediaSource`；不接 Emby；UI 不写 `if (isEmby)`。
- 不动选集面板数据、外挂字幕落盘、进度回写、弹幕、设置同步等其余反向方法。
- 不动原生 Kotlin 侧 channel 协议（仍发 guid/index）；不碰 `MpvPlaybackController.kt`、
  不夹带 `HANDOFF.md`。
- 不改下载、本地播放、play stats。
