# Emby 详情页首光 设计

> 2026-06-22。用户决策:**只做展示(首光)** + **新建中立详情屏,按后端路由**。
> 上游:`2026-06-22-emby-home-first-light-design.md`(首页首光已收口)。

## 1. 目标与非目标

**目标**:在 Emby 态点开影片,能进入一个详情页看到——背景图 / 海报 / logo / 标题 / 简介 /
题材 / 地区 / 评分 / 年份 / 时长 / 演职员。数据全部走 `MediaBackend.getItemDetail()`
返回的中立 `MediaDetail`,不再把 Emby id 灌进飞牛 API(那正是「六小时没有权限」的来源)。

**非目标(本切片明确不做)**:
- 不做播放。Emby `getPlayback` 仍 throw `UnsupportedError`;详情屏播放入口为占位提示
  (能力门控,非 `if(isEmby)`)。完整播放是后续独立切片(需 Emby getPlayback + bridge,
  与「不构造 MpvMediaSource、不迁播放器深层 mixin」约束另行设计)。
- 不做剧集季集浏览。本切片只覆盖电影(Movie)详情;Series 季集树是后续切片。
- 不动飞牛 `play_detail_page`(~7790 行)。飞牛态详情页路径**完全不变**。
- 不写下载 / play stats / 收藏写回(那些是飞牛私有写路径)。

## 2. 架构:中立详情屏 + 后端路由

### 2.1 路由切口(数据层分支,非 UI if)

`media_list_screen._openItemDetail()` 已经按 person/item 分流。在 item 分支内,按
`backend.capabilities.kind` 分流:
- `feiniu` → 现有 `EmbeddedDetailLauncher.openItemDetail` / `PlayDetailScreen`(原路不变)。
- 其它(emby)→ `Navigator.push(MediaDetailScreen(...))`。

这是**导航/数据层分支**,与首页 `_loadCategoryItems` 按 kind 选数据源同模式;UI 渲染层不写
`if(isEmby)`。飞牛不经过新屏,新屏不经过飞牛 launcher / 原生 DetailActivity。

### 2.2 中立详情屏 `MediaDetailScreen`

新建 `lib/screens/media_detail_screen.dart`。
- 入参:`itemId`、可选 `initialCard`(列表已有的 `MediaItemCard`,用于首屏占位:标题/海报/背景,
  避免白屏)、`heroTag`。
- 取数:`context.read<MediaBackendProvider>().backend.getItemDetail(itemId)`,得 `MediaDetail`。
- 渲染:复用现有详情组件,从 `MediaDetail` 直接喂——
  - 背景:`ImmersiveDetailBackground`(背景图 `detail.backdropImage`/`primaryImage`)。
  - 头部:海报 `detail.primaryImage` + logo `detail.logoImage`(无 logo 回退标题文本)。
  - 元信息:年份(`releaseDate`)/ 时长(`runtimeMinutes`/`durationSeconds`)/ 评分(`rating`)。
  - 题材 + 地区:`detail.genreLabels` / `detail.regionLabels` → `DetailTagChip`。
  - 简介:`detail.overview` → `DescriptionSection`。
  - 演职员:`detail.people` → `CreditsSection`(经 `CreditPersonPresenter` 出文案,
    与飞牛页同一展示逻辑)。
  - 播放入口:占位按钮「播放功能即将到来」(disabled),门控用 backend 能力,不写 isEmby。
- 图片:`MediaImageRef.url` 已是 Emby `?api_key=` 自鉴权直链(首页首光同款),走现有图片
  加载器的自鉴权分支即可,无需 NAS token。

> 为何不复用 `play_detail_page`:它的展示半身与播放态(selectedOption / 清晰度选择器 /
> 轨道选择器 / capabilityLabels)深度交织,且整页围绕飞牛 `PlayInfoData`/`StreamTrackData`
> 装配。塞后端分支风险高、易回归飞牛播放。中立屏只消费 `MediaDetail`,隔离干净。

## 3. Emby 适配层

### 3.1 `EmbyApi.getItem(itemId)`(Task 1)

`GET /Users/{userId}/Items/{itemId}`,`api_key` 自鉴权,带 `Fields=` 拉详情所需字段
(Overview / Genres / People / ProviderIds / ProductionYear 等)。返回单个 `BaseItemDto`
原样 `Map`(字段映射留 mapper),复用现有 `_asMap` / `_jsonHeaders` 风格。

### 3.2 `mapEmbyItemDetail`(Task 2)

`BaseItemDto` → `MediaDetail`:
- `id`/`type`(Type)/`title`(Name)/`overview`(Overview)。
- `primaryImage`/`backdropImage`/`logoImage`:复用 `_primaryImage`/`_backdropImage` 同款
  `?api_key=` URL;logo 取 `ImageTags.Logo`。
- `rating`:`CommunityRating` 文本(与卡片 `_ratingText` 同口径)。
- `releaseDate`:`PremiereDate`,或回退 `ProductionYear`。
- `runtimeMinutes`/`durationSeconds`:`RunTimeTicks`(100ns)→ 秒/分钟。
- `genreLabels`:`Genres[]`(Emby 已是显示名,无需字典翻译)。
- `regionLabels`:`ProductionLocations[]`(若有)。
- `people`:`People[]` → `MediaDetailPerson`(id=Id、name=Name、role=Role、
  department=Type(Actor/Director/...)、avatar=`/Items/{Id}/Images/Primary?tag={PrimaryImageTag}&api_key=`)。
- `externalIds`:`ProviderIds.Tmdb`/`ProviderIds.Imdb`。
- `watched`/`favorite`/`resumePositionSeconds`:`UserData`(Played / IsFavorite / PlaybackPositionTicks)。

### 3.3 `EmbyMediaBackend.getItemDetail`(Task 3)

去掉 `_unsupported('getItemDetail')`,改为 `api.getItem(...)` → `mapEmbyItemDetail(...)`。
`getItemSeasons`/`getSeasonEpisodes`/`getPlayback`/搜索/筛选**仍 throw**(本切片不覆盖)。

## 4. 任务拆分(每步可编译 + 单测 + pathspec 提交)

- **Task 1**:`EmbyApi.getItem(itemId)` + `test/api/emby_api_test.dart` 增用例。
- **Task 2**:`mapEmbyItemDetail` 进 `emby_media_mappers.dart` + `emby_media_mappers_test.dart` 增用例。
- **Task 3**:`EmbyMediaBackend.getItemDetail` 接线 + `emby_media_backend_test.dart`(fake 返回详情 Map,
  断言 getItemDetail 不再 throw、字段映射正确;其余方法仍 throwsUnsupportedError)。
- **Task 4**:`MediaDetailScreen` 中立详情屏 + smoke/widget 测试(fake backend 喂 MediaDetail,
  断言标题/简介/题材/演职员渲染,播放入口为占位)。
- **Task 5**:`media_list_screen._openItemDetail` 按 kind 路由到中立屏 + 看板更新 + 实机验证。

## 5. 约束复述(本切片必须遵守)

- 不接 Emby API 范围外能力;UI 不写 `if(isEmby)`(路由分支在数据/导航层)。
- `lib/media_backend` 不构造 `MpvMediaSource`、不导航、不碰 BuildContext。
- 不改下载 / 本地播放 / play stats;不迁 MpvPlayerPage 深层 mixin。
- 每个小任务单独提交,用 **pathspec 提交**(`git commit -m ... -- <自己的文件路径>`),
  防 Codex 并行 stage 夹带;提交前查 `git status --short` 和 `git diff --cached --name-only`。
- 不夹带 `HANDOFF.md`、`.codex-remote-attachments/`、`MpvPlaybackController.kt` 及其它 Codex 未提交文件。
- 不提交任何真实 server/token/userId/password,测试用脱敏 fixture/fake。
