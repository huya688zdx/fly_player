# Emby 剧集系列页 + 季详情页接入计划

> 2026-06-23。承接 play_detail_page 公有化(电影详情已迁,S2-6 收口)。
> 目标:Emby 剧集系列 → 系列页(展示季)→ 季详情页(展示选集),复刻飞牛三页结构。
> 用户授权:「遇到性能问题可以重写飞牛的页面,兼容飞牛页面」——若同页中立体路撞性能,
> 允许重写飞牛页(但飞牛必须逐像素兼容)。

## 现状诊断

详情分发链:
`media_list_screen._openItemDetail` → `EmbeddedDetailLauncher.openItemDetail`(原生分屏/pane)
或回退 `PlayDetailScreen` → **`PlayDetailScreen._load` 判 mode** → `TvDetailPage` / `MediaCollectionDetailPage` / `PlayDetailPage`。

**阻断点**:`play_detail_screen.dart:69-80` 对所有非飞牛后端**强制 `DetailPageMode.movie`**
(注释:「TV/合集模式属后续切片」)。故 Emby 剧集当前走扁平电影中立体(无季/集)。

已就绪地基:
- 中立接口已含 `getItemSeasons(seriesId)` / `getSeasonEpisodes(seasonId)` + 模型
  `MediaSeasonSummary` / `MediaEpisodeSummary`(`lib/media_backend/detail/`)。飞牛已实现,
  **Emby 两方法仍 `_unsupported`**(`emby_media_backend.dart:175-180`)。
- `MediaDetail.type` 带稳定类型枚举(Movie/TV/Episode),可供分发判 TV。
- Emby API `getItems(parentId, includeItemTypes, fields, …)` 已具备;无季/集专用 helper。
  Emby 原生端点:`/Shows/{seriesId}/Seasons`、`/Shows/{seriesId}/Episodes?seasonId=`。

待改两张飞牛页(深绑 `FeiniuApi`/`PlayInfoData`/`MediaLibraryItem`):
- `tv_detail_page.dart`(1632 行):系列页,季卡栅格 + 描述/演职员/链接 + 收藏/已看/播放。
- `tv_season_detail_page.dart`(2374 行):季详情,季选择器 + 选集浏览器 + 下载 sheet +
  原生 playback launcher + reentry。**最重**。

## 打法(复刻 play_detail 已验证路径)

同页加中立渲染路 `_buildNeutralBody`,`_neutralDisplayOnly` 门控;飞牛成功分支整段不动、
逐像素;展示区复用同源组件;图源走 `DetailArtworkResolver`;播放/收藏/已看在 Emby 态占位禁用
(「播放功能即将到来」);下载/原生 reentry 在 Emby 态用 kind/`_data!=null` 守卫跳过。
**性能兜底**:若中立体与飞牛同页导致卡顿,改为重写飞牛页(拆共享组件,飞牛逐像素兼容)。

## 阶段划分(每步单测/实机 + pathspec 提交)

### Phase A — 后端能力(纯数据,无 UI,飞牛零影响)✅ 完成(2026-06-23)
- ✅ **A-1**(`5f90ba7`)Emby API 季查询 `getSeasons(seriesId)`(`/Shows/{id}/Seasons`,`UserId`/
  `api_key`,`Fields=ItemCounts,UserData`)。**集查询改走 `getItems(parentId=季)` 不另加端点**
  (见 A-3 取舍),原计划的 `getEpisodes(/Shows/Episodes)` 已删(死代码)。2 单测。
- ✅ **A-2**(`8260e1e`)Mappers `mapEmbySeason`→`MediaSeasonSummary`(`ChildCount` 充当总数+本地数,
  回退 `RecursiveItemCount`)、`mapEmbyEpisode`→`MediaEpisodeSummary`(RunTimeTicks→秒,
  watched/resume 取 `UserData`,图源 `api_key` 直链)。4 单测。
- ✅ **A-3**(`dbc0f1c`)`EmbyMediaBackend.getItemSeasons`(走 `getSeasons`)/`getSeasonEpisodes`
  (走 `getItems(parentId=seasonId, includeItemTypes='Episode')`——契合只给 seasonId 的接口签名,
  无需 seriesId、省一次往返;Emby 默认按 IndexNumber 返回子项)。替掉 `_unsupported`。3 单测。

> **执行顺序调整(B↔C)**:B-1(分发翻到 TvDetailPage)若先于 C(TvDetailPage 中立体)做,
> Emby 剧集会进一张还不能渲染 Emby 的页 → 中途可见损坏。故**先做 C(TvDetailPage 中立体,
> 此时分发仍把 Emby 剧集当 movie,不可达、无回归)**,C 就绪后再翻 B-1 一次性上线 + 实机验。
> 飞牛两序皆零影响(B-1 只改非飞牛分支,C 只加 kind 门控的中立分支)。

### Phase B — 分发打通(Emby 系列进 TV 页)✅ 完成(2026-06-23,`9167f0b`)
- ✅ **B-1** `PlayDetailScreen._load` 非飞牛分支:读 `backend.getItemDetail(itemId).type`,
  `series`/`tv` → `DetailPageMode.tv`(进 TvDetailPage 中立体),其余 → movie;带 `seriesGuid`
  的条目(选集)恒 movie(同飞牛 `_resolveMode` 口径);判型失败退 movie。**飞牛分支 100% 不动。**
  目标页自行按 backend 重取详情(`_itemDetail` 留 null)。

### Phase C — TvDetailPage 中立体(系列页展示季)✅ 完成(2026-06-23,`829cf75`)
合并为一提交(C-1/2/3 自洽、页面在 B-1 前对 Emby 不可达,拆分不可独立测):
- ✅ 中立状态 `_neutralDisplayOnly`/`_neutralDetail`/`_neutralSeasons`;`_load` 顶部按 backend kind
  早分流到 `_loadNeutral`(走 `getItemDetail`+`getItemSeasons`,飞牛分支整段不动)。
- ✅ `_buildNeutralBody`:沉浸背景 + hero(logo)+ DetailMetaLines + 播放占位「即将到来」+ 描述
  (复用飞牛 pop 动画)+ 季栅格(`_buildNeutralSeasonGrid`,MediaPosterCard + `DetailArtworkResolver`
  直链)+ CreditsSection + LinkSection + 顶栏。动态取色图源用 Emby 完整直链。
- ✅ 季卡点击:`_seasonItemFromSummary` 由 `MediaSeasonSummary` 造最小 `MediaLibraryItem`(海报存
  Emby 完整直链)→ `AdaptiveDetailRequest.season` 导航。
- 顺带清理:删 3 处预存重复 import。`flutter analyze` 该文件净。**飞牛零触碰(早返回门控)。**
- **注**:在 B-1 翻分发前对 Emby 不可达,故本步不单独实机;C+D 都就绪后随 B-1 一次性验。

### Phase D — TvSeasonDetailPage 中立体(季详情展示选集)✅ 完成(2026-06-23,`895fbdc`)
- ✅ `_loadSeasonData` 顶部按 backend kind 早分流到 `_loadSeasonDataNeutral`(季列表 `getItemSeasons`
  + 目标季 `getItemDetail` + 选集 `getSeasonEpisodes`);`_switchSeasonNeutral` 切季重取选集。
- ✅ `_buildNeutralSeasonBody`:沉浸背景 + hero + DetailMetaLines(季号/年/评分)+ 播放占位 + 描述 +
  `TvEpisodeBrowserSection`(选集卡由 `MediaEpisodeSummary` 经 `_neutralEpisodeCardEntries` 构建,
  已看/续播进度/时长)+ CreditsSection + LinkSection + 顶栏。选集点击 → `AdaptiveDetailRequest.item`
  (Emby 选集 type=Episode → movie 中立体);简介浮层走中立 overview。
- ✅ 下载 sheet / 原生 reentry / playback launcher / picker sheet 在 Emby 态全跳过(早返回门控)。
  **飞牛分支整段不进(早返回)。** analyze 净、309 全量测试过。

### Phase E — 收尾(实机待验)
全链路实机:Emby 剧集 → 系列页季栅格 → 点季进季详情 → 选集浏览器 + 切季 + 点选集进集详情 → 占位播放;
飞牛三页(电影/系列/季)零回归。验后补看板 + 记忆。

## 约束(全程,同 play_detail)
- 飞牛日常主路径每步逐像素不变;不动下载/play stats/播放器深层 mixin。
- `lib/media_backend` 不构造 `MpvMediaSource`、不导航、不碰 BuildContext;UI 不写 `if(isEmby)`
  (数据/导航层按 kind 分支可以)。
- Emby 播放本次不做(占位);只做展示 + 导航。
- 每个小任务 **pathspec 提交**;提交前查 `git status --short`/`--cached`;不夹带 Codex 未提交文件
  (`MpvPlaybackController.kt`/`HANDOFF.md`/`.codex-remote-attachments/`);不提交真实凭据(脱敏 fixture)。
- 上下文偏长时输出压缩摘要并停。
