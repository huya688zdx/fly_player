# 原生壳切集/换源 状态继承缺陷 修复计划

状态：计划（根因已坐实，待用户确认范围与顺序后实现）
日期：2026-06-21
范围：原生播放壳（`NativePlayerActivity.kt`）+ 反向通道（`native_reentry_support.dart` / `native_player_bridge.dart`）+ TV launcher 解析。**与 Phase 6 B-3 无关**，是既有缺陷。

> 约束沿用：不迁 `MpvPlayerPage` 深层 mixin；不改下载/本地播放/play stats（除非任务明确进入）；UI 不写 `if (isEmby)`；`lib/media_backend` 不构造 `MpvMediaSource`；小步单独提交。
> 协作提醒：Codex 正在改 `mpv/MpvPlaybackController.kt`（性能计数器采样，与本计划无关），本计划不碰该文件。

## 三个缺陷（用户报告）

A. 切到下一集后，画面已开始播放，中途仍弹 loading 转圈。
B. 切集前手动把字幕 1→2、音轨 2→1，切下一集后又回到字幕 1 / 音轨 2（回退到新集服务端默认）。
C. 切分辨率后，「下一集」失效、「选集」也消失。

---

## 缺陷 C：切画质丢 episodes（根因最清晰，风险最低）

### 链路与根因（已坐实）

1. 切画质：`NativePlayerActivity.requestQuality` → `requestServerReload`（5656）→ 反向通道 `reloadServerSession`（5698）→ 结果交 `applyEpisodeResult`（5701）。
2. `applyEpisodeResult`（5566）→ `applyLoadArgs(effectiveLoadArgs)` → `loadArgsMap = loadArgs`（2198，**整体替换**）。
3. Flutter `NativeReentrySupport.reloadServerSession`（`native_reentry_support.dart:339-449`）返回 `{'loadArgs': jsonEncode(newSource.toMap())}`。`newSource` 是 `MpvMediaSource`，**`episodes` 不是其字段**，`toMap()` 不含 `episodes`。
4. 于是替换后的 `loadArgsMap` 没有 `episodes` → `episodeList()`（5458-5460）返回空 → `showEpisodePicker` 报「无选集信息」（5466），`nextEpisodeGuidOrNull`/`hasNextEpisode` 返回 null → 「下一集」失效。

对比：选集 `requestEpisode` / 切版本 `requestVersion` 走 `resolvePlayback`，Flutter `onResolvePlayback` 里 **始终带 `episodes: _nativeEpisodesPayload()`**（`tv_season_detail_page.dart:1380`），故这两条不丢 episodes。**只有 `reloadServerSession` 这条丢。**

### 修复方案（Flutter 侧，单点、低风险）

`NativeReentrySupport.reloadServerSession` 已把 `currentLoadArgs` 解析成 `raw` map（:350）。在返回前，把 `raw` 里**非 `MpvMediaSource` 字段的透传键**并回 `newSource.toMap()`：

```dart
final newArgs = newSource.toMap();
// episodes 是选集面板/下一集的唯一数据源，且不属于 MpvMediaSource，会被 fromMap→toMap 丢掉。
final episodes = raw['episodes'];
if (episodes is List && episodes.isNotEmpty) newArgs['episodes'] = episodes;
return <String, dynamic>{'loadArgs': jsonEncode(newArgs)};
```

- 待审计：`raw` 里其它非 source 透传键是否也需保留（如 `localSubtitleFiles` / `posterLocalPath` / `isDownloadedFile`）。切画质走服务端转码场景，这些大多不适用，但需逐键确认避免顺带回归。结论写进实现记录。
- 备选（不采用）：native `applyEpisodeResult` 在 reload 分支把旧 `loadArgsMap["episodes"]` 合并进新 loadArgs。Flutter 侧改更集中，且 `resolvePlayback` 路径已证明「Flutter 负责带齐 loadArgs」是既定契约，故选 Flutter 侧。

### 测试 / 验证

- 单测：扩 `test/`（若有 reloadServerSession 覆盖）或新增——构造带 `episodes` 的 currentLoadArgs，断言返回 loadArgs 仍含 `episodes`。
- 实机：切画质后「选集」仍在、「下一集」可用、连播倒计时正常。

---

## 缺陷 B：音轨/字幕选择不继承到下一集（设计较重，跨层）

### 链路与根因（已坐实）

1. 切下一集：`requestEpisode`（5501）→ `resolvePlayback` 只带 `mapOf("itemGuid" to itemGuid)`（5516），**不带 audioGuid/subtitleGuid**。
2. Flutter `onResolvePlayback(itemGuid)`（audioGuid=null、subtitleGuid=null）→ `resolveForNative` → `_resolveWithProvider` 用**新一集自己的** `playInfo.audioGuid` / `playInfo.subtitleGuid`（服务端默认）。
3. native `applyLoadArgs` 把 `selectedAudioGuid/selectedSubtitleGuid` **复位为新集初值**（2200-2201）。
4. 结果：用户在上一集手动选的轨道丢失，新集回到其服务端默认。

根因本质：飞牛**每集 guid 独立**，不能跨集传 guid 继承。

### 修复方案（用户定调：按**轨道序号**继承，不做语言匹配）

> 用户意图：直接沿用「当前正在播放的是第几条轨道」。例：当前音轨 3、字幕 2，切集后仍取第 3 条音轨、第 2 条字幕；新集没有第 3/第 2 条 → 回退默认（第 1 条 / 服务端默认）。简单、可预期。

- native：切集 `resolvePlayback` 时带上**当前音轨序号 + 当前字幕序号**（在 `audioTracks`/`subtitleTracks` 列表里 `selectedAudioGuid`/`selectedSubtitleGuid` 的下标；字幕关闭=序号缺省/特殊值表示「关」）。
- Flutter：解析新集候选后，按序号取第 N 条；越界 → 回退默认；字幕「关」态 → 保持关闭。
- 公共层落点：给 `MediaPlaybackRequest` 加中立 `preferredAudioTrackIndex` / `preferredSubtitleTrackIndex`（序号，可空），扩 `selectPlaybackTrack`：`preferredTrackId`（guid）优先 → 否则 `preferredIndex` 命中且在范围内取该条 → 否则 default → first。纯函数、可单测、Emby 同样受益；**不构造 `MpvMediaSource`**。
- 序号一致性：native 面板列表顺序 = `loadArgs.audioTracks/subtitleTracks` 顺序 = Flutter `_resolveWithProvider` 用 `playbackStream` 构造候选的顺序（同源 mapper），故下标跨集对齐。需在实现时核对两端排序一致。
- 覆盖面：手动切下一集、**自动连播**（`requestEpisode(autoPlayAfterLoad=true)`）、**下一集预取**（`nextEpisodePreload*`）三条都要带序号偏好，否则预取命中仍丢继承。
- 模式差异：新集原画代理 → 序号选中后落 `audioTrackIndex/subtitleTrackIndex` + guid；服务端托管 → 序号映射到该集对应 guid 后照常 reload 烧录。两端都从「选中候选」自然产出，无需特判。

### 风险

- 字幕「关闭」态跨集：上一集关字幕，下一集应保持关闭（序号偏好需能表达「关」，复用 `subtitleTrackExplicitlyDisabled`）。
- 序号越界回退默认必须稳，避免选空 / 选错。
- 实机验证多集轨道数不一致（如某集无第 3 音轨）时正确回退。

### 测试 / 验证

- `selectPlaybackTrack` 单测：preferredIndex 命中取该条、越界回退默认、guid 优先于 index、字幕关闭态保持。
- 实机：切集/连播/预取命中后，音轨字幕序号与上一集一致；新集缺该序号则回默认；上一集关字幕则下一集仍关闭。

---

## 缺陷 A：切集后画面已播仍显示 loading（native 状态时序，调查较重）

### 现状（已定位显隐逻辑，根因待复现确认）

- `updateOverlays`（6071-6086）：`showLoading = !nativeLibLoaded || buffering || (!visualPlaybackReady && error==null) || error!=null`。
- `episodeSwitchInFlight` 期间，未达 `visualPlaybackReady && !buffering && !ended` 前 early-return，期间 loadingSpinner 维持上面算出的可见性。
- 症状「画面已开始播放仍弹 loading」= 原地换源（不重建 surface）后，首帧已出但 `buffering` 仍为真 / `visualPlaybackReady` 滞后翻转，导致 spinner 盖在已播画面上。

### 计划（先复现 + 定位，再修）

1. 复现并加日志：在切集后打 `buffering` / `visualPlaybackReady` / `playbackPhase` 时间线（已有 `TRKDBG` 风格日志可循），确认是哪个标志在首帧后仍卡住。
2. 根因落在 `MpvPlayerState` 的 `buffering`/`visualPlaybackReady` 派生（native 播放状态层）——原地 `load` 新文件时事件序列与首次加载不同。
3. 修复方向（复现后定）：原地换源后，以「首帧已渲染」为准及时落 loading（例如 `visualPlaybackReady` 后即便短暂 `buffering` 也不再盖 spinner，或换源时重置 buffering 基线）。改动限于 overlay 显隐判定 / 状态派生，**不动** mpv 加载内核流程。

### 风险

- 属 native 播放状态层（与深层 mpv 相邻），改判定可能影响正常缓冲转圈；须实机验证弱网真缓冲时 loading 仍正常显示。
- 与 Codex 的 `MpvPlaybackController.kt` 改动不重叠（其为性能计数器），但若根因落在 state 派生需与 Codex 协调避免同文件冲突。

---

## 执行顺序（用户 2026-06-21 决定）

1. **缺陷 C** 先做：单点、低风险、Flutter 侧、可单测，立竿见影。
2. **缺陷 B** 次之：按**轨道序号**继承（见上，用户定调，不做语言匹配），跨 native+Flutter，单独提交。
3. **缺陷 A** 待定：用户暂未要求，先复现加日志定位再决定；涉及 native 状态层，与 Codex 协调。

每个缺陷独立提交；提交前查 `git status --short` / `git diff --cached --name-only`，不夹带 `HANDOFF.md` 与工作区里 Codex 的 `MpvPlaybackController.kt`。

---

## 实施记录

### 缺陷 C —— 已完成（待实机验证）

- `NativeReentrySupport.reloadServerSession` 重载后并回 `episodes`，抽成纯静态
  `preserveEpisodesForServerReload(previousLoadArgs, reloadedLoadArgs)`，从重载前 `raw`
  取 `episodes` 补进新 source map。
- 审计结论：只有 `episodes` 是「选集/下一集」依赖的非 `MpvMediaSource` 透传键；`itemGuid`/
  `seasonGuid`/`seriesGuid`/季集号等都是 source 字段、`toMap` 自带，无需额外保留。
- 测试：`test/services/native_reentry_support_test.dart` 3 PASS（并回 / 无 episodes 不写空键 /
  空列表不并回）。`flutter analyze` 干净。
- 提交：`24d51e4`。

### 缺陷 B —— 已完成（待实机验证，按轨道序号继承）

- **B1 公共层** `6ff6509`：`MediaPlaybackRequest` 加中立 `preferredAudioTrackIndex` /
  `preferredSubtitleTrackIndex`；`selectPlaybackTrack` 优先级改为
  `explicitlyDisabled → preferredTrackId(显式guid) → preferredTrackIndex(序号) → fallbackTrackId(服务端默认) → isDefault → first`，
  序号继承压过服务端默认、越界回退默认；`getPlayback` 两处调用拆出 `fallbackTrackId`（保持
  open 现状行为）。selector 单测 +5。
- **B2 Flutter 接线** `4dcb55b`：`TvSeasonPlaybackLauncher.resolveForNative/_resolveWithProvider`
  + 桥接器 `onResolvePlayback` + 两个 TV 页面回调串起 `audioTrackIndex`/`subtitleTrackIndex`；
  字幕 `-1` = 继承「关闭」（映射 `subtitleTrackExplicitlyDisabled`），`>=0` = 继承序号。
  单条目/电影/下载三个 `onResolvePlayback` 闭包补声明两参数以匹配桥接器函数类型（本期不接继承）。
  切集高亮判定（查 `audioGuid/subtitleGuid/qualityIndex`）不受影响——继承走新 index 参数、不动这三者。
- **B3 原生壳** `8812333`：`NativePlayerActivity` 加 `inheritAudioTrackIndex()`（找不到→不带）/
  `inheritSubtitleTrackIndex()`（关闭→-1；本地字幕/找不到→不带）/ `episodeResolveArgs(itemGuid)`；
  `requestEpisode` 与 `preloadNextEpisodeIfNeeded` 的 `resolvePlayback` 均改用 `episodeResolveArgs`
  带上当前序号；`selectAudioFromPanel`/`selectSubtitleFromPanel` 切轨时 `clearNextEpisodePreload()`，
  避免预取按旧序号过期。`gradlew :app:compileLiteDebugKotlin` BUILD SUCCESSFUL（仅历史警告）。
- 序号对齐依据：native `audioTracks/subtitleTracks` 列表顺序 = Flutter 用 `playbackStream` 构造
  候选的顺序（同源 mapper），故跨集下标一致。
- 已知小限制：预取命中后若用户在极短窗口内再改轨，已由切轨清预取覆盖；多数路径无碍。

### 缺陷 A —— 未动（用户暂未要求）

待用户要求后，先复现 + 加 `buffering`/`visualPlaybackReady` 时间线日志定位，再改 overlay 判定。

## 实机验证清单（交用户）

- C：切画质后「选集」仍在、「下一集」可用、连播倒计时正常。
- B：切下一集后音轨/字幕序号与上一集一致（例：音轨 3 字幕 2 → 仍 3/2）；新集缺该序号回默认；
  上一集关字幕则下一集仍关闭；自动连播（含预取命中）同样继承；切轨后再连播用新选择。
