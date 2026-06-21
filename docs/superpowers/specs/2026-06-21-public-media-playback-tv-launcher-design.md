# Phase 6 桥接子阶段 B-3 设计：TvSeasonPlaybackLauncher 迁移

状态：设计（待用户 / Codex 确认后再动业务代码）
日期：2026-06-21
前置：B-2 已把 `ItemPlaybackLauncher._resolve()` 切到 `getPlayback + FeiniuPlaybackSourceBridge` 并实机验证通过（`99d338d`）。

## 1. 目标与范围

把 `TvSeasonPlaybackLauncher._resolveWithProvider()`（仅季/集内部网络解析）切到与 B-2 相同的
`FeiniuMediaBackend.getPlayback() + FeiniuPlaybackSourceBridge.assemble()` 路径，返回形状
`({MpvMediaSource source, PlayInfoData playInfo, String title})` 保持不变。

**只迁内部解析逻辑（第 205~427 行 `_resolveWithProvider`）。** 以下一律不动：

- `open()` 的原生壳分支 `NativePlayerBridge.maybeLaunch(source.toMap(), episodes: episodes, nas: provider)`（带选集 episodes，且 TV 不判 `useNativeRenderer`、不在 launcher 内 `_bindReentry`）。
- `resolveForNative()` 的本地下载优先分支、弹幕预取、`loadArgs` 组装、`jsonEncode`。
- 页面侧反向通道注册（`tv_detail_page.dart:907`、`tv_season_detail_page.dart:1363` 的 `bindReentry`）——TV 的反向通道在页面层，不在 launcher 内，与 B-2 的 Item 不同。
- 进度写回、TV 选集导航、`EmbeddedDetailLauncher`、`MpvPlayerPage` push。

## 2. 现状审计（TV launcher `_resolveWithProvider` vs B-2 桥接器/backend）

逐字段比对 `tv_season_playback_launcher.dart:205~427` 与 `feiniu_media_backend.dart:getPlayback`
+ `feiniu_playback_source_bridge.dart:assemble`，**已确认口径一致**的部分：

| 关注点 | TV launcher | backend + 桥接器 | 结论 |
|---|---|---|---|
| `effectiveMediaGuid` | `qualityMediaGuid` 非空优先，否则 `playInfo.mediaGuid` | `effectiveSourceId = qualityId ?? mediaGuid` | 一致 |
| 画质选择 | guid 命中原画/default → guid 任意 → qualityIndex → `preferredInitialQuality` | `selectPlaybackQuality`（Codex `b0b37ae` 已对齐 `preferredInitialQuality` + qualityIndex） | 一致 |
| 音轨选择 | `selectedOrFirstAudio(override ?? playInfo.audioGuid)` | `selectPlaybackTrack(preferredTrackId: audioTrackId ?? playInfo.audioGuid)` | 一致 |
| 字幕三态 | `override==null` 默认 / `''` 关 / guid 指定 | request 三态映射（同 B-2） | 一致 |
| `preferExternalSubtitle` / `embeddedSubtitleTrackIndex` | 见 312~333 | 桥接器逐字复刻（45~66） | 一致 |
| `playbackVideoGuid` 回退链 | `quality.videoGuid → videoStream.guid → playInfo.videoGuid` | `context.videoTrackId`（backend 211~215 同回退链） | 一致 |
| `playbackResolution` / `playbackBitrate` | 见 302~311 | 桥接器逐字复刻（34~43） | 一致 |
| 续播 `videoIds` | `[playInfo.item.guid, itemGuid]` | `[playInfo.item.guid, request.itemId]`（backend:233） | 一致 |
| 续播网络位 | `ts > 0 ? ts : item.watchedTs` | 同口径（backend:230~231） | 一致 |
| `resolvedStartPosition` | `!reliableSeek && ts>0 ? Duration.zero : resume.position` | 桥接器 68~85 同语义 | 一致 |
| `effectiveDuration` | `playInfo.item.duration` | `playInfo.item.duration`（backend:234） | 一致 |
| `MpvMediaSource` 其余字段 | 370~424 | 桥接器 91~147 逐字段对齐 | 一致（仅 seriesGuid 例外，见缺口 1） |

## 3. 两个模型缺口（必须先补，才能安全迁移）

### 缺口 1：`seriesGuid` 显式覆盖

- TV launcher：`seriesGuid: seriesGuid.trim().isNotEmpty ? seriesGuid.trim() : playInfo.grandGuid.trim()`（370~376）——调用方页面传入的 `seriesGuid` 优先，回退 `grandGuid`。
- 桥接器当前：写死 `seriesGuid: playInfo.grandGuid.trim()`（94）。`bundle.seriesId` 也只由 backend 从 `grandGuid` 填（backend:245），**没有显式覆盖通道**。
- 来源性质：TV 的 `seriesGuid` 是**请求侧导航上下文**（页面已知的剧集 id），不是后端 DTO 派生。Emby 同样有 series id 概念。

**方案**：`MediaPlaybackRequest` 新增中立可选字段 `seriesId`（默认 `''`）。桥接器装配 `seriesGuid` 改为：
`request.seriesId.trim().isNotEmpty ? request.seriesId.trim() : playInfo.grandGuid.trim()`。
Item 路径不传 → 空 → 回退 `grandGuid`，**B-2 行为零变化**。

### 缺口 2：已看完 → 从头重播

- TV launcher：
  ```
  playbackCompleted = duration > 0 && ((duration - sourceTs) <= 0 || item.isWatched == 1)
  resolve(..., networkCompleted: playbackCompleted)   // resetCompletedToBeginning 用默认 true
  ```
  即「已看完的集」重新点播 → `_normalizePosition` 归零，从头播。
- backend.getPlayback：`networkCompleted` 默认 `false` + 显式 `resetCompletedToBeginning: false`（backend:237）→ **永不归零**，返回 clamp 后的网络位置。
- 关键事实（git 核对）：`ItemPlaybackLauncher` 迁移前（`99d338d^:391`）就已是 `resetCompletedToBeginning: false`、无 `networkCompleted`。所以 **backend 对 Item 是忠实复刻、无回归；而 TV 与 Item 在这一点上本来就不同**——TV 已看完会从头，电影/单条目则停在网络位。
- `_normalizePosition` 语义（`playback_resume_position_resolver.dart:91~107`）：仅当 `resetCompletedToBeginning && (completed || clamped>=duration)` 时归零。

**方案**：`MediaPlaybackRequest` 新增中立可选字段 `restartWhenCompleted`（默认 `false` = Item/B-2 现状）。`getPlayback` 据此分流：

- `restartWhenCompleted == false`（默认）：维持现状 `resetCompletedToBeginning: false`、不传 networkCompleted。Item 路径零变化。
- `restartWhenCompleted == true`（TV 传）：计算
  `completed = duration>0 && ((duration - networkPositionSeconds) <= 0 || item.isWatched == 1)`，
  传 `networkCompleted: completed, resetCompletedToBeginning: true`，复刻 TV 旧行为。

该字段是后端中立的播放意图（「若已播完则本次从头」），Emby 重播同样适用，命名不含飞牛/Emby 私有语义。逻辑放 backend（`isWatched` 是后端事实，桥接器只拿到已算好的 `bundle.startPosition`，无法再判 completed）。

## 4. seriesTitle / title fallback（无缺口，复用 fallbackTitle）

TV 的 `seriesTitle` 参数同时充当：
- `title = formatPlayerTitleFromPlayItem(item, fallbackTitle: seriesTitle)`；
- `MpvMediaSource.seriesTitle = item.tvTitle非空 ? item.tvTitle : seriesTitle`。

桥接器对 `request.fallbackTitle` 的两处用法（86~89、112~114）与之**完全对应**。因此 B-3 只需把 TV 的 `seriesTitle` 作为 `request.fallbackTitle` 传入，无需新字段。

## 5. 不改动清单（强约束）

- 不接 Emby API；UI 不写 `if (isEmby)`。
- `lib/media_backend` 不构造 `MpvMediaSource`（两个新字段是纯数据；backend 续播分流不构造 source）。桥接器仍留 `lib/player/controllers/`。
- 不动本地下载优先、页面侧 `bindReentry`、弹幕预取、进度写回、TV 选集、原生壳 `maybeLaunch(episodes)`。
- 不动 `MpvPlayerPage` 深层 mixin、下载、本地播放、play stats。
- 两个新 request 字段默认值必须保持 Item/B-2 行为不变（`seriesId=''`、`restartWhenCompleted=false`）。

## 6. 风险

- R1（续播归零语义）：缺口 2 若漏补，TV 已看完的集迁移后会停在结尾、几乎立即结束，属可见回归。必须在 B-3 Task 1 先补字段并单测覆盖「completed→归零」与「默认 false→不归零」两路。
- R2（seriesGuid 漂移）：缺口 1 若漏补，下游消费 `MpvMediaSource.seriesGuid`（选集/反向通道/续播 key 关联）的逻辑可能取错剧集 id。需单测覆盖「显式 seriesId 覆盖」与「空回退 grandGuid」。
- R3（实机验证）：launcher 改动属播放路径，单测 + analyze 不足以判全，必须 `flutter run` 实机验证 TV 季/集：默认播放、续播位、**已看完集从头重播**、画质/音轨/字幕切换、外部字幕、原生壳选集与切集换源、原生壳画质切换回传。
- R4（口径再核对）：迁移落地后需对 source.toMap() 关键字段（seriesGuid/seasonGuid/tmdbId/seasonNumber/episodeNumber）与迁移前做一次对比，确认原生壳选集/弹幕预取读取的 loadArgs 不变。

## 7. 关联文档

- B-1/B-2 设计：`specs/2026-06-21-public-media-playback-bridge-design.md`
- B-1/B-2 计划：`plans/2026-06-21-public-media-playback-bridge.md`
- 本期计划：`plans/2026-06-21-public-media-playback-tv-launcher.md`
- 状态看板：`docs/superpowers/public-media-frontend-status.md`
