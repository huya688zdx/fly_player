# 公共媒体前端协作状态

本文档用于 Codex、Claude 和用户共享推进状态。每完成一块任务，就更新状态、提交 hash、验证命令和下一步负责人。

## 当前阶段

阶段：Phase 6 **桥接子阶段 B-1 交付收口**（用户 2026-06-21 选方案 B 分步）。Phase 5 详情骨架、Phase 6 播放后端骨架（Task 1~4）均已收口；Codex 深审通过（`b0b37ae`/`0eb9484`）。本轮交付 B-1：`getPlayback` 改返回 `MediaPlaybackResolution`（中立 bundle + 不透明后端上下文）+ 飞牛播放桥接器 `FeiniuPlaybackSourceBridge`（装配 `MpvMediaSource`），**全程可单测、线上 launcher 未改**。

**B-2（把 `ItemPlaybackLauncher` 单条目灰度切到 `getPlayback` + 桥接器）待用户实机放行后再开**——B-2 才碰线上播放链路，需 `flutter run` 验证单条目全路径。TV launcher / 本地下载优先 / 原生壳反向重载 / 进度写回仍不动。设计/计划：`specs/2026-06-21-public-media-playback-bridge-design.md`、`plans/2026-06-21-public-media-playback-bridge.md`。后端层已为 Emby 就绪：将来写 `EmbyMediaBackend.getPlayback`（附 Emby 上下文）+ `EmbyPlaybackSourceBridge` 即可，中立层无需改动。

Phase 6 第一阶段目标是把 `ItemPlaybackLauncher` / `TvSeasonPlaybackLauncher` 中重复的飞牛播放解析事实先抽象成公共 bundle：播放源、画质候选、音轨/字幕候选、默认选择、续播位置、headers 和后端会话句柄。入口控制器、`MpvMediaSource` 装配、本地下载优先、原生壳反向通道和播放进度写回暂不迁移。

目标：基于 Emby 官方 PlaybackInfo / HLS / playback check-in 形状评估播放入口边界，先落设计和实施计划，再按小任务执行公共播放模型与飞牛适配层。

设计文档：`docs/superpowers/specs/2026-06-21-public-media-playback-design.md`（公共播放 bundle 边界 + Emby 官方播放形状约束 + 飞牛适配层范围）。
实施计划：`docs/superpowers/plans/2026-06-21-public-media-playback.md`（Task 1 模型 → Task 2 selector → Task 3 飞牛 mapper → Task 4 backend 接口 → Task 5 看板）。

### Phase 6 设计要点（关键边界）

- 公共播放模型只表达后端中立播放事实，不出现 `mediaGuid` / `videoGuid` / `audioGuid` / `subtitleGuid` 字段名；飞牛私有 id 只在适配层内部映射为 `sourceId` / `videoTrackId` / `audioTrackId` / `subtitleTrackId`。
- `MediaBackend.getPlayback(MediaPlaybackRequest)` 返回 `MediaPlaybackBundle`，**不返回 `MpvMediaSource`**；mpv 装配留控制器 / player 层。
- `FeiniuMediaBackend` 只编排飞牛 API 和 mapper，不碰 `Navigator`、`BuildContext`、`NativePlayerBridge` 或播放器页面。
- Emby 官方 `PlaybackInfoResponse.MediaSources`、HLS stop、playback check-in 证明播放生命周期应独立设计；第一阶段只建模型和飞牛骨架，不实现 Emby。
- 本地下载优先、原生壳反向重载、弹幕预取、播放进度写回暂留现有 launcher，避免一次性重构播放器深层逻辑。

## 负责人约定

- Claude：主实现。负责公共模型、`MediaBackend` 接口、`FeiniuMediaBackend`、Provider、页面迁移框架和主要代码。
- Codex：审查收口。负责架构漏洞排查、测试补充、小逻辑修复、边界问题、验证命令、提交检查。
- User：确认阶段范围，决定是否扩大到详情页或播放器。

## 提交规则

- 完成一个小任务并且对应测试通过后，必须立刻单独提交。
- 不要把多个小任务攒到同一个 commit。
- 提交前只暂存当前小任务相关文件，不能夹带工作区里的其它改动。
- 提交前检查 `git status --short` 和 `git diff --cached --name-only`。
- 测试失败时不要标记完成，也不要提交完成状态；先修复，或在本文档写明阻塞、失败命令和错误摘要。
- 每次提交后在总进度表或当前任务记录里写入 commit hash 和测试命令。

## Claude 上下文压缩规则

Claude Code 不会自动压缩上下文。Claude 完成一个 Task 后，或者上下文偏长时，需要停止继续执行，并回答：

```text
建议现在压缩上下文。以下是可用于压缩后的继续摘要：
1. 当前目标：
2. 已阅读文档：
3. 已完成任务：
4. 修改过的文件：
5. 提交状态：
6. 测试结果：
7. 下一步：
8. 明确不要做：
```

用户完成压缩或新开窗口后，再继续下一个 Task。

## 总进度

| 阶段 | 状态 | 负责人 | 提交 | 验证 |
| --- | --- | --- | --- | --- |
| Phase 0: 设计和协作基线 | 完成 | Codex | 本次文档提交 | 文档自查通过 |
| Phase 1: 公共模型和 Feiniu mapper | 完成 | Claude 主实现，Codex 审查 | Task1: ef6405c / Task2: f40f06a / Task3: e97112b | 单元测试 |
| Phase 2: FeiniuMediaBackend 和 Provider | 完成 | Claude 主实现，Codex 审查 | Task4: 3986ef5 / Task5: 4b3002d | 单元测试 + analyze |
| Phase 3: 首页迁移样板 | 部分完成（catalogs+summary 已迁移，待手动验证） | Claude 主实现，Codex 验证 | 模型扩展: 1ff413b / 9e012b7；首页迁移: 180e8c0 | 首页单测通过；`flutter run` 手动验证待做 |
| Phase 4: 搜索页迁移（统一 MediaItemCard） | 完成（搜索页已验收通过；分类页滤镜体系另立设计、本期不动） | Claude 主实现，Codex 审查 | 设计 c849e2a / 模型 fa878ba / mapper 013d2fe / 收口 a68c95e / 搜索页 a8adf76 | media_backend 11 PASS + analyze；用户已验收通过（2026-06-20） |
| Phase 4.5: 分类页 filter 抽象 | 完成（分类页已迁到 schema 驱动 + queryCatalogItems + localizer；Codex 审查通过；用户实机验证通过 2026-06-20） | Claude 主实现，Codex 审查 | Task5-1: 38e3315 / Task5-2: 1dcedda / Task5-3: 15a3853 / Task5-4: 9b06e3d+5b6ea4b / Codex小修: 085d051 | media_backend+localizer 41 PASS + analyze（分类页 No issues）；用户已实机验收通过 |
| Phase 5: 详情页迁移 | 骨架完成（Task 1~3 + Codex 修复，已提交、可单测）；页面迁移（Task 4/5）调查后**暂缓**——无干净增量切口，建议连同 Emby 一起做 | Claude 主实现，Codex 审查 | 调研: 756f2eb / 设计+计划: e2c6d94 / Task1: c2fffa6+c60292c / Task2: 87c3377 / Task3: dd8630d / Codex修复: 63a91f7+8452fd7 | media_backend 52 PASS + analyze（No issues）；页面迁移暂缓（见下） |
| Phase 6: 播放入口迁移 | 后端骨架（Task 1~4）+ 桥接子阶段 **B-1** 完成（resolution+上下文+桥接器，已提交、可单测、线上 launcher 未改）；**B-2** 灰度翻单条目 launcher 待实机放行 | Claude 主实现，Codex 深审 | 骨架: 4fd3bc2/b591e92/09700cb/d0e3b60 + Codex修复 b0b37ae / 桥接设计计划: d80d8e0+5196882 / B-1 Task1: 8cc205b / B-1 Task2: cd3b4bd | media_backend+player 78 PASS + analyze（No issues） |

## 当前可执行任务

- [x] 写公共媒体前端设计文档。
- [x] 写第一阶段实施计划。
- [x] 写共享状态看板。
- [x] 用户确认按 Phase 1 开始实施。

## Phase 1 任务进度（Claude 主实现）

- [x] Task 1: 公共后端类型和能力模型
  - 新建 `lib/media_backend/media_backend_kind.dart`、`lib/media_backend/media_backend_capabilities.dart`、`test/media_backend/media_backend_capabilities_test.dart`
  - 测试：`flutter test test/media_backend/media_backend_capabilities_test.dart` → PASS
  - 提交：`ef6405c`
  - 下一步：Claude 执行 Task 2（公共首页模型 MediaImageRef / MediaCatalog / MediaItemSummary）
- [x] Task 2: 公共首页模型
  - 新建 `lib/media_backend/media_image_ref.dart`、`media_catalog.dart`、`media_item_summary.dart`、`test/media_backend/media_frontend_models_test.dart`
  - 测试：`flutter test test/media_backend/media_frontend_models_test.dart` → PASS
  - 提交：`f40f06a`
  - 下一步：Claude 执行 Task 3（Feiniu mapper，将 MediaItem/MediaLibraryItem 映射到公共模型）
- [x] Task 3: Feiniu mapper
  - 新建 `lib/media_backend/feiniu/feiniu_media_mappers.dart`、`test/media_backend/feiniu_media_mappers_test.dart`
  - 已核对真实模型：`MediaItem(id/name/type?/path?)`、`MediaLibraryItem.displayTitle`（tvTitle 为空回退 title），与计划假设一致
  - 测试：`flutter test test/media_backend/feiniu_media_mappers_test.dart` → PASS
  - 提交：`e97112b`
  - 下一步：Claude 执行 Task 4（MediaBackend 接口 + FeiniuMediaBackend 适配器）
- [x] Task 4: MediaBackend 接口和飞牛适配器
  - 新建 `lib/media_backend/media_backend.dart`、`lib/media_backend/feiniu/feiniu_media_backend.dart`、`test/media_backend/feiniu_media_backend_test.dart`
  - 已核对 FeiniuApi 方法签名一致：`getMediaList()`、`getMediaSummary()`、`getPlayList({forceRefresh})`、`getItemsByCategoryGuid(guid,{page,limit})`
  - 测试：`flutter test test/media_backend/` → 6 PASS；`flutter analyze lib/media_backend/` → No issues
  - 提交：`3986ef5`
  - 下一步：Claude 执行 Task 5（Provider 注入 main.dart，不迁移页面）

## Phase 2 任务进度（Claude 主实现）

- [x] Task 4: 见上（接口 + 飞牛适配器）
- [x] Task 5: MediaBackendProvider 注入 main.dart
  - 新建 `lib/providers/media_backend_provider.dart`；在 `lib/main.dart` 的 `MultiProvider` 用 `ChangeNotifierProxyProvider<NasProvider, MediaBackendProvider>` 注入
  - 注意：`main.dart` 工作区已有大量无关未提交改动，采用 `git stash push -- lib/main.dart` 隔离 → 在干净 HEAD 上编辑 → 仅提交本任务改动 → `git stash pop` 恢复无关改动（两处改动区域不重叠，pop 无冲突）
  - 验证：`flutter analyze lib/main.dart lib/providers/media_backend_provider.dart` → No issues；pop 后 `flutter analyze lib/main.dart` → No issues，无冲突标记
  - 提交：`4b3002d`
  - 下一步：Claude 执行 Task 6（首页 media_list_screen 迁移样板）
### 建议调整（已被用户确认采纳 — 2026-06-20）

- 背景：Task 6 准备阶段发现**计划与规格冲突**。计划 Task 6 让首页改调 `backend` 后把公共模型「转回」旧 `MediaItem`/`MediaLibraryItem`，但原 `MediaItemSummary` 刻意精简，缺少首页卡片实际消费的字段：`media_list_screen.dart` 用到 `seasonNumber`/`episodeNumber`(674/675/690/691/637)、`numberOfSeasons`/`numberOfEpisodes`(632/635/636)、`releaseDate`(622)，`media_list_screen_widgets.dart` 用到 `voteAverage`(540)。精简模型转回旧模型会让这些字段归零，违反规格「首页视觉表现没有变化」。
- 用户决策：选 **Option A — 扩展公共条目模型**（后端中立展示字段），而非缩小迁移范围或暂停。
- 已实施（提交 `1ff413b`）：
  - `MediaItemSummary` 新增后端中立展示字段：`secondaryTitle`、`rating`、`seasonNumber`、`episodeNumber`、`numberOfSeasons`、`numberOfEpisodes`、`releaseDate`、`posterWidth`、`posterHeight`；新增 `displayTitle`(副标题优先回退)/`hasPosterSize`/`isLandscapePoster` getter。新字段均为可选带默认，向后兼容已有用例与 Codex 测试。
  - 类型选择：`rating`/`releaseDate` 保留 String 原样，季集数/海报宽高用 int，确保 Task 6「转回旧模型」对首页展示字段**无损**。
  - `mapFeiniuItemSummary`：`title` 改回原始 `title` + 新增 `secondaryTitle=tvTitle`，由公共 `displayTitle` getter 复刻飞牛回退语义；并填入全部新展示字段。
  - 测试：`feiniu_media_mappers_test.dart` 新增「无损往返」用例。`flutter test test/media_backend/` → 8 PASS；`flutter analyze lib/media_backend/` → No issues。
  - 边界：`posterList`/`meta` 等首页未直接消费的字段不进公共模型，避免泄漏后端私有结构。

### 第二次建议调整（已被用户确认采纳 — 2026-06-20）：Task 6 缩小范围

- 背景：Task 6 实施时进一步发现，**即使按 Option A 扩展了 `MediaItemSummary`，首页 item/继续观看链路仍无法无损迁移**。审计 `media_list_screen.dart` + `media_list_screen_widgets.dart` 发现还读取精简模型不携带的字段：
  - `item.ts`/`item.watchedTs`（386、705）= **续播进度/位置**，丢失会破坏继续观看续播。
  - `firstAirDate`/`lastAirDate`（620-624）= 年份区间。
  - `localNumberOfSeasons`/`localNumberOfEpisodes`（630-634）= 季/集角标（优先本地计数）。
  - `resolutions`（widgets:541）= 清晰度角标（4K/1080p）。
  - 要全部覆盖需把公共模型膨胀成 `MediaLibraryItem` 克隆，直接违反规格「公共模型必须小而稳定/不搬私有字段」。
- 用户决策：选 **Option B — 缩小 Task 6 范围**。本期只迁移**无损链路**，富 item 模型留待后续连同 Emby 形状一起设计。

- [x] Task 6: 首页 catalogs + summary 迁移到 MediaBackend（缩小范围版）
  - 改动文件：`lib/screens/media_list_screen.dart`（工作区此前的无关改动已被 `83319eb` 提交并入分支，文件回到干净状态，**无需 stash 隔离**，仅提交本文件）。
  - 做法：`_fetchHomeData()`/`_backgroundRefresh()` 用 `context.read<MediaBackendProvider>().backend`，`getCatalogs()`（分类）+ `getHomeSummary()`（概要）走 backend；`getPlayList()`（继续观看）和 `getItemsByCategoryGuid()`（分类条目）**仍走 FeiniuApi**。公共 `MediaCatalog` 经本文件内 `static _catalogToMediaItem()` 转回 `MediaItem` 喂现有 UI；转换函数仅限本文件，不扩散。`_refreshContinueWatching()`(337) 未动。
  - 无损保障：为避免分类条缩略图退化（主机最多叠 2 张海报，原读 `category.posters` 列表），先给 `MediaCatalog` 补 `posters: List<MediaImageRef>`（提交 `9e012b7`），转回时完整还原 `posters`+`path`。catalog→MediaItem 仅丢 `meta`，已核实任何分类消费端（`CategoryItemsScreen` 只用 id+name、`/screen/category` 路由接收端、首页分类条）均未使用 `meta`。
  - 测试：`flutter analyze lib/screens/media_list_screen.dart` → No issues；`flutter test test/home_scroll_physics_test.dart test/main_navigation_layout_test.dart` → PASS；`flutter test test/media_backend/` → 9 PASS。
  - 提交：模型扩展 `9e012b7`、首页迁移 `180e8c0`。
  - **待人工验证（交用户/Codex）**：`flutter run` 登录飞牛后确认——① 首页分类条标题/缩略图（含 2 张叠图）与迁移前一致；② 继续观看进度条/续播位置正常（仍走 FeiniuApi，预期不变）；③ 分类预览与点击进入分类页正常；④ 后台刷新（`_backgroundRefresh`）不改变可见数据。
  - 遗留/下一步建议：
    - 富 item 公共模型（含续播进度 resumePosition、清晰度、年份区间、本地季集计数）留到后续阶段，最好连同 Emby 实际字段一起设计，避免现在按飞牛形状定型。
    - Codex 风险 2（`MediaImageRef.headers` 为空）：本期图片仍走旧 NAS 鉴权路径，未受影响；待页面直接消费公共图片引用时再在适配层补 headers。
    - ~~Codex Task5 审查：`MediaBackendProvider.backend` 每次读取新建 `FeiniuApi`/`FeiniuMediaBackend`，首页每次刷新会各读 1 次；建议后续在 Provider 内缓存 backend 实例或按 NAS 会话变更重建，避免重复创建 Dio。~~ **已收尾（提交 `9a55927`）**：`MediaBackendProvider` 按 `nasProvider.baseUrl` 缓存 backend 实例（FeiniuApi 构造时把 baseUrl 烤进 Dio，token 拦截器每请求动态读取；故缓存键取 baseUrl），同会话内多页面复用同一实例并连带复用 FeiniuApi 标签/题材共享缓存，baseUrl 变更（重登/FN Connect 切换/登出清 resolvedBaseUrl）时才重建。新增缓存复用 + baseUrl 变更重建两条单测。`flutter test test/media_backend/ --concurrency=1` → 31 PASS；`flutter analyze lib/providers/media_backend_provider.dart test/media_backend/media_backend_provider_test.dart` → No issues。

## Phase 4 设计决策与任务进度（Claude 主实现）

### 设计讨论结论（用户已确认 — 2026-06-20）

- 背景：用户确认进入 Phase 4「富 item 公共模型」设计讨论。审计了 `category_items_screen.dart` 和 `search_screen.dart` 两个目标页的真实字段消费。
- 字段审计（搜索/分类卡片消费的 `MediaLibraryItem` 字段合集）：`guid`/`displayTitle`/`type`、`poster`+`posterList`、`posterWidth/Height`、`voteAverage`、`watched`、`resolutions`、`firstAirDate/releaseDate/lastAirDate`（年份区间）、`localNumberOfSeasons/Episodes`+`numberOf...`+`episodeNumber`（季/集角标，本地计数优先）、`numberOfItem`（person 作品数）。这些全是**后端中立的卡片展示概念**，Emby 卡片同样具备，可干净定型。
- 两处硬耦合（不属于「模型」问题，本期不强行抽象）：
  1. **动作面板** `MediaItemActionSheetController.show(item: MediaLibraryItem)`：审计确认其对 item 仅消费 `guid`、`watched`、以及 `defaultTitle()` 用的 `type`/`seasonNumber`/`episodeNumber`/`tvTitle`/`title`——**全在富模型覆盖范围内**。搜索页迁移时用本文件内局部 `_cardToActionItem(MediaItemCard)` 转回最小 `MediaLibraryItem` 喂面板，无损、不扩散（复刻 Task 6 模式）。
  2. **分类页滤镜/排序/标签体系**（`ItemListRequest` 带 genres/locate(ISO3166)/decade/resolution/color_range/audio_type/recognition_status + 排序列 + getUserListSetting）：深度飞牛形状、与 Emby 差异极大，是另一套 filter 查询抽象，**本期不动，另立设计**。
- 用户决策：
  1. 模型形状 → **统一 `MediaItemCard`**（home/search/category 卡片共用一个富模型）。`MediaItemSummary` 当前仅挂在 `MediaBackend.getContinueWatching`/`getCatalogPreviewItems`（Task 6 决定暂不调用），页面零消费，可安全演进/替换为 `MediaItemCard`，不留两个重叠模型。
  2. Phase 4 范围 → **仅搜索页先行**。分类页滤镜体系另立设计、本期不迁。

### MediaItemCard 字段清单（统一富模型）

`id` / `title` / `secondaryTitle` / `type` / `primaryImage` / `posters[]` / `backdropImage` / `durationSeconds` / `watched` / `rating` / `releaseDate` / `firstAirDate` / `lastAirDate` / `seasonNumber` / `episodeNumber` / `numberOfSeasons` / `numberOfEpisodes` / `localNumberOfSeasons` / `localNumberOfEpisodes` / `numberOfItem` / `posterWidth` / `posterHeight` / `resolutions[]`；getter：`displayTitle`（副标题优先回退）/`hasPosterSize`/`isLandscapePoster`；含 `copyWith()`（搜索页本地 watched 变更需要）。

### 子任务拆分（每步可编译、单独提交）

- [x] Task 4-1：新建 `lib/media_backend/media_item_card.dart`（统一富模型，23 展示字段 + copyWith + displayTitle/hasPosterSize/isLandscapePoster）+ `test/media_backend/media_item_card_test.dart`
  - 测试：`flutter test test/media_backend/media_item_card_test.dart` → 4 PASS；`flutter analyze` → No issues
  - 提交：`fa878ba`
- [x] Task 4-2：`mapFeiniuItemCard(MediaLibraryItem)` mapper（无损映射全部展示字段，含 posterList/firstAirDate/lastAirDate/local 计数/numberOfItem/resolutions）+ 单测
  - 测试：`flutter test test/media_backend/feiniu_media_mappers_test.dart` → 5 PASS；`flutter analyze` → No issues
  - 提交：`013d2fe`
- [x] Task 4-3：`MediaBackend.searchItems(query)` 接口 + `FeiniuMediaBackend` 实现（走 `api.searchList`）；将 `getContinueWatching`/`getCatalogPreviewItems` 返回类型统一迁到 `MediaItemCard`，**删除 `MediaItemSummary` 及其 mapper/测试**（真正统一，无重叠模型）
  - 测试：`flutter test test/media_backend/` → 11 PASS；`flutter analyze lib/media_backend test/media_backend` → No issues
  - 提交：`a68c95e`
- [x] Task 4-4：搜索页迁移（`_results: List<MediaItemCard>`，读取走 `context.read<MediaBackendProvider>().backend.searchItems`，展示/详情跳转/字幕全用 card 字段，动作面板用本文件局部 `_cardToActionItem` 转回最小 `MediaLibraryItem`，本地 watched 变更用 `card.copyWith(watched:)`）
  - 无损保障：动作面板只消费 guid/watched/type/season&episode/标题字段，`_cardToActionItem` 全部回填；`getItemDetail` 详情预取仍走 FeiniuApi（详情页本期不迁）。`_cardToActionItem` 仅限搜索页本文件、不扩散。
  - 测试：`flutter analyze lib/screens/search_screen.dart` → No issues。
  - 提交：`a8adf76`
  - **已验收（用户 2026-06-20 确认通过）**：搜索结果标题/封面/评分/清晰度/已观看角标、年份区间与季/集副标题、详情跳转、动作面板与本地角标更新均与迁移前一致。

### 明确不做

- 不碰分类页滤镜/排序/标签体系（飞牛专属，另立设计）。
- 不在 UI 写 `if (isEmby)`；不接 Emby API。
- `_cardToActionItem` 局部转换仅限搜索页本文件，不扩散。

## Phase 4.5 分类页 filter 抽象设计与任务进度（Claude 主实现）

### 设计讨论结论（用户已确认 — 2026-06-20）

- 用户选「分类页 filter 抽象」优先于详情页迁移（详情页评估：~7790 行 UI、30 处 `FeiniuApi(`、裸 `Map`，宜等 Emby 形状一起设计）。
- 现状审计：分类页查询 = `ItemListRequest`（ancestorGuid/page/pageSize/sortColumn/sortType/typeTags/tags）；9 维度（type/genres/locate/decade/resolution/color_range/audio_type/recognition_status/watched）；排序 create_time/release_date/title/vote_average × ASC/DESC；选项来自 `getTagList` + `getTagGenresMap`(id→名) + `getTagIso3166Map`(code→名)；视图偏好 `getUserListSetting/setUserListSetting`。
- 决策 1（本地化归属）→ **双轨 label**。决策 2（视图偏好）→ **不纳入**（viewType/sort 偏好留飞牛 API，filter 抽象只聚焦查询）。

### 双轨 label 机制

- 职责划分：backend 负责**结构 + 后端数据字典**，UI 负责 **l10n 文案 + 渲染**，维度的 `kind` 是桥梁。
  - `MediaFilterOption{value, label}`：`plain` 类（已可直接显示，如 color_range）适配层填好 `label`；需 app 文案的维度（genre id / ISO code / 枚举 token）`label` 留空、`value=raw`，UI 按 `kind`+`value` 本地化。
  - genre 名（id→名）、region 名（code→名）是**后端数据**（非 l10n），随 schema 下发（`genreNames`/`regionNames`），UI localizer 用它们 + app l10n 合成 label。
  - 枚举类（decade/resolution/audioType/recognitionStatus/watched/mediaType）文案走 app l10n（复用 `category_items_screen` 现有 labeler）。

### 公共模型（`lib/media_backend/filter/`）

```
enum MediaFilterDimensionKind { plain, genre, region, decade, resolution, audioType, colorRange, recognitionStatus, watched, mediaType }
class MediaFilterOption { String value; String label; }
class MediaFilterDimension { String key; MediaFilterDimensionKind kind; List<MediaFilterOption> options; bool multiSelect; }
class MediaSortOption { String field; }            // label 走 UI l10n
class MediaCatalogFilterSchema { List<MediaFilterDimension> dimensions; List<MediaSortOption> sortOptions; Map<String,String> genreNames; Map<String,String> regionNames; }
class MediaCatalogQuery { String catalogId; Map<String,List<String>> selection; String sortField; String sortType; int page; int pageSize; }
class MediaItemCardPage { List<MediaItemCard> items; int total; }   // 复用 MediaItemCard
```

### backend 方法

- `getCatalogFilterSchema(catalogId)` → schema（适配层合成 getTagList + genresMap + iso3166Map + 静态维度 type/decade/watched）。
- `queryCatalogItems(MediaCatalogQuery)` → MediaItemCardPage（适配层把 selection 转回 `ItemListRequest`：genres→int、recognition_status/watched→`'$v'`、type→typeTags；调 `getItemsPageByRequest`，map `MediaItemCard`）。

### Task 拆分（每步可编译、单独提交）

- [x] Task 5-1：filter 公共模型（上述 7 个类/枚举）+ 单测
- [x] Task 5-2：backend 接口 `getCatalogFilterSchema`/`queryCatalogItems` + `FeiniuMediaBackend` 实现（含 selection→ItemListRequest 类型回填）+ 单测
  - 改动文件：`lib/media_backend/media_backend.dart`、`lib/media_backend/feiniu/feiniu_media_backend.dart`、`lib/media_backend/feiniu/feiniu_media_mappers.dart`、`test/media_backend/feiniu_filter_mappers_test.dart`
  - 做法：`MediaBackend` 新增 filter schema 与分类查询接口；`FeiniuMediaBackend` 仅作为适配层调用 `getTagList`、`getTagGenresMap`、`getTagIso3166Map` 和 `getItemsPageByRequest`；selection→`ItemListRequest` 的飞牛字段回填集中在 `feiniu_media_mappers.dart`。
  - 无损保障：`type` 进入 `typeTags`，空选择回退 `Movie/TV/Directory/Video`；`genres` 回填为 int；`recognition_status`、`watched` 及其它维度保持字符串原样；schema 中 `decade`/`resolution` 的选项源键继续取飞牛复数 `decades`/`resolutions`。
  - 测试：`flutter test test/media_backend/feiniu_filter_mappers_test.dart` → 12 PASS；`flutter test test/media_backend/ --concurrency=1` → 28 PASS；`flutter analyze lib\media_backend test\media_backend` → No issues。
  - 提交：`1dcedda`
- [x] Task 5-3：UI 层 `CatalogFilterLocalizer`（按 kind+value+schema 字典+l10n 出 label，复用现有 labeler）+ 单测
  - 新增文件：`lib/ui/catalog_filter_localizer.dart`、`test/ui/catalog_filter_localizer_test.dart`
  - 放置位置：放 `lib/ui/`（与既有非 widget mapper `capability_badge_mapper.dart` 同层），保持 `lib/media_backend` 纯净、不引入 UI/l10n 依赖。
  - 做法：localizer 持有 `AppLocalizations l10n` + `MediaCatalogFilterSchema schema`，按 `MediaFilterDimensionKind` 逐项复刻 `category_items_screen` 既有 labeler 语义：
    - `plain`：option.label 非空用 label，否则回退 value。
    - `genre`：优先 `schema.genreNames[value]`，否则 value。
    - `region`：优先 `schema.regionNames[value]`，再试大写 ISO code（复刻分类页 `value.toUpperCase()` 查表），否则 value。
    - `decade`（Recent→`listFilterDecadeRecent`）/`resolution`（去尾部 p、Others→`commonOther`）/`audioType`（DolbySurround/Atmos/DTS/Stereo/Others）/`colorRange`（原样）/`recognitionStatus`（1/2/3）/`watched`（1/0）/`mediaType`（Movie/TV/Directory/Video）均逐项对齐分类页文案，未知值原样回退。
    - 附带 `dimensionTitle(dimension)`（维度分组标题）与 `sortLabel(field)`（排序字段文案，未知回退 createTime），供 Task 5-4 schema 驱动渲染复用，避免在页面里重写 labeler。
  - 无损保障：所有 l10n 走与分类页相同的 `AppLocalizations` getter，单测用 `l10n.xxx` 作断言基准（而非硬编码中文），保证与分类页显示同源同步；适配层不改、`lib/media_backend` Task 5-2 逻辑不动。
  - 测试：`flutter test test/ui/catalog_filter_localizer_test.dart` → 12 PASS；`flutter test test/media_backend/ --concurrency=1` → 28 PASS（未受影响）；`flutter analyze lib/media_backend test/media_backend lib/ui/catalog_filter_localizer.dart test/ui/catalog_filter_localizer_test.dart` → No issues。
  - 提交：`15a3853`
- [x] Task 5-4：分类页 `category_items_screen` 迁移（schema 驱动维度渲染 + `queryCatalogItems` 查询 + localizer）；`getUserListSetting` 视图偏好仍走飞牛 + analyze + 手动验证
  - 改动文件：`lib/media_backend/feiniu/feiniu_media_mappers.dart`（decade 修复）、`test/media_backend/feiniu_filter_mappers_test.dart`、`lib/screens/category_items_screen.dart`
  - **先修 Task 5-2 回归（提交 `9b06e3d`）**：`mapMediaQueryToItemListRequest` 原把 decade 走字符串 passthrough，但原生 `_buildRequest` 直接发 `getTagList` 下发的 int 年份（fixture `decades:[2020]` 为 int 证实），转字符串会改变 `/item/list` 线格式、可能让年代筛选回归。改为 decade 数值还原 int（与 genres 一致），`Recent` 等非数值保持字符串。新增单测覆盖。
  - 分类页迁移（提交 `5b6ea4b`）：
    - `_loadMeta` 改调 `backend.getCatalogFilterSchema(catalogId)` 拿维度 + genre/地区字典；`getUserListSetting` 视图/排序偏好仍走 `FeiniuApi`。
    - 9 个 `Set<dynamic> _selectedX` + `_buildRequest` → 统一 `Map<String,Set<String>> _selection` + `_buildQuery()` 产 `MediaCatalogQuery`；查询走 `backend.queryCatalogItems` 返回 `MediaItemCard`。
    - 筛选弹窗改为遍历 `_schema.dimensions` 的 schema 驱动渲染；维度标题 / 选项文案 / 排序文案 / 筛选摘要全部走 `CatalogFilterLocalizer`，删除页内 8 个飞牛 labeler（保留 `_resolutionLabel` 仅供卡片角标）。
    - 条目模型 `MediaLibraryItem` → `MediaItemCard`（复刻搜索页 Task 4-4）；动作面板用页内局部 `_cardToActionItem` 回填最小 `MediaLibraryItem`，本地 watched 变更用 `card.copyWith(watched:)`；详情预取 `getItemDetail` 仍走 `FeiniuApi`。
  - 无损保障：`_buildQuery`→mapper 产出的 `ItemListRequest` 与原生 `_buildRequest` 逐字段对齐（type 进 typeTags / 空回退全类型；genres、decade 发 int；recognition_status、watched 及其余维度字符串；排序/分页透传；`exclude_grouped_video` 默认 1）。type 锁定、续播/收藏动作、清晰度角标、年份区间与季集副标题均保留。
  - 测试：`flutter test test/media_backend/feiniu_filter_mappers_test.dart` → 13 PASS；`flutter test test/media_backend/ test/ui/catalog_filter_localizer_test.dart --concurrency=1` → 41 PASS；`flutter analyze lib/screens/category_items_screen.dart` → No issues；`flutter analyze`（全量）→ 17 条，全部在无关旧文件（play_detail_page/tv_detail_page duplicate import、download_list unused 等），分类页 / media_backend / localizer 均无问题。
  - 提交：decade 修复 `9b06e3d` / 分类页迁移 `5b6ea4b`
  - **实机验证（用户 2026-06-20 确认通过）**：分类页各维度筛选项文案、筛选/排序/翻页结果（含年代筛选发 int）、卡片标题/副标题/评分/清晰度/已观看角标与三种视图、长按动作面板与本地角标更新、详情跳转与 type 锁定入口、视图偏好均与迁移前一致。

### 明确不做

- viewType/sort 视图偏好留飞牛 API，不纳入本次抽象。
- 不接 Emby；UI 不写 `if(isEmby)`；适配层 selection→飞牛 tags 的类型转换仅限适配层。

## Phase 6 任务进度（Claude 主实现，Codex 深审）

播放后端骨架第一阶段：公共播放模型 + selector + 飞牛 mapper + `MediaBackend.getPlayback`。**全程不构造 `MpvMediaSource`、不导航、不触播放器深层 mixin。**

- [x] Task 1: 公共播放模型
  - 新建 `lib/media_backend/playback/media_playback.dart`（`MediaPlaybackRequest`/`Bundle`/`Source`/`Quality`/`Track`/`Session` + 3 枚举），全 `const`，字段名中立（无 `mediaGuid`/`videoGuid`/`Feiniu`/`Emby`）。
  - 测试：`test/media_backend/media_playback_models_test.dart` → 2 PASS；`flutter analyze` No issues。
  - 提交：`4fd3bc2`
- [x] Task 2: 公共播放选择器
  - 新建 `lib/media_backend/playback/media_playback_selectors.dart`：`selectPlaybackQuality`（id > index > default > first）、`selectPlaybackTrack`（explicitlyDisabled → null > preferred > default > first），纯函数。
  - 测试：`media_playback_selectors_test.dart` → 4 PASS；analyze No issues。
  - 提交：`b591e92`
- [x] Task 3: 飞牛播放 mapper
  - 新建 `lib/media_backend/feiniu/feiniu_playback_mappers.dart`：`mapFeiniuPlaybackQualities` / `mapFeiniuAudioTracks` / `mapFeiniuSubtitleTracks` / `mapFeiniuPlaybackSource`。飞牛 `media_guid`/`video_guid`/`guid` 只在适配层内部映射为中立 id；字幕三态（embedded / external / 双标志 local）忠实复刻 `local_subtitle_bundle` 签名；headers 由 `responseHeaders` 派生 + 显式 headers 覆盖 + `requestUserAgent` 兜底。
  - 测试：`feiniu_playback_mappers_test.dart` → 9 PASS；全套件 67 PASS；analyze No issues。
  - 提交：`09700cb`
- [x] Task 4: `MediaBackend.getPlayback` 接口 + 飞牛编排
  - `MediaBackend` 加 `getPlayback(MediaPlaybackRequest)`；`FeiniuMediaBackend.getPlayback` 复刻 `ItemPlaybackLauncher._resolve()` 的编排（`effectiveSourceId = qualityId ?? mediaGuid`、`startFromBeginning` 时 `resetPlaybackRecord`、best-effort `getStreamTrackData`、`getPlaybackStream` + `mergePlaybackQualitiesWithStreamTrackData`、Task 2/3 selector/mapper、`PlaybackResumePositionResolver`（`ts>0?ts:watchedTs`）），但去掉 `MpvMediaSource`/`PlayerSourceController`/导航；字幕额外内联 guid 去重（避免引入 l10n 依赖）。
  - 测试：`feiniu_playback_backend_test.dart`（fake seam）→ 6 PASS；全套件 73 PASS；`flutter analyze lib/media_backend test/media_backend` No issues。
  - 提交：`d0e3b60`

### 桥接子阶段 B-1（方案 B 分步，用户 2026-06-21 决策；已完成、可单测、线上 launcher 未改）

> 决策：方案 B 分步；上下文经 `getPlayback` 返回 `MediaPlaybackResolution { bundle, backendContext }` 承载（中立 bundle 不含上下文字段）。设计 `d80d8e0` / 计划 `5196882`。

- [x] B-1 Task 1: 中立 resolution + 飞牛上下文
  - 新建 `lib/media_backend/playback/media_playback_resolution.dart`（`MediaPlaybackResolution` + 标记 `MediaPlaybackBackendContext`）、`lib/media_backend/feiniu/feiniu_playback_context.dart`（`FeiniuPlaybackContext` 持 api/playInfo/playbackStream/选中 raw 画质·音轨·字幕/mergedQualities/字幕轨/effectiveSourceId/videoTrackId/directUrl）。`MediaBackend.getPlayback` 返回 `MediaPlaybackResolution`；`FeiniuMediaBackend` 补 `_rawAudioFor`/`_rawSubtitleFor` 回找 raw 档，单次网络装上下文。中立 bundle 仍不含 raw 字段。
  - 验证：`feiniu_playback_backend_test.dart` 6 PASS（含上下文 raw facts 断言）；全套件 75 PASS；analyze No issues。
  - 提交：`8cc205b`
- [x] B-1 Task 2: 飞牛播放桥接器
  - 新建 `lib/player/controllers/feiniu_playback_source_bridge.dart`：`assemble({request, bundle, context}) → MpvMediaSource`，复刻 `ItemPlaybackLauncher._resolve()` 的 `buildInitialPlaybackResult` + `MpvMediaSource` 装配（续播位用 `bundle.startPosition`；画质/直链/代理会话/headers 由 `PlayerSourceController` 用上下文 raw facts 重新解析，不信任 `MediaPlaybackSource.url`）。桥接器单向依赖 media_backend，不导航。
  - 验证：`test/player/feiniu_playback_source_bridge_test.dart` 3 PASS（原画路径字段一致 / 显式关字幕落空串 / 外挂字幕 preferExternal）；`test/media_backend/ test/player/` 78 PASS；analyze No issues。
  - 提交：`cd3b4bd`

**B-2（灰度翻单条目 launcher，需实机，待用户放行）**：把 `ItemPlaybackLauncher._resolve()` 改成 `getPlayback` + `FeiniuPlaybackSourceBridge`，`open()`/`resolveForNative()` 两出口走桥接器产物。TV launcher / 本地下载优先 / 原生壳反向重载 / 进度写回不动。需 `flutter run` 实机验证单条目：默认播放、续播、画质切换、音轨切换、字幕关闭/切换、外部字幕、原生壳重载。

### Phase 6 后端骨架 Codex 深审（历史记录）

- 2026-06-21 Phase 6 Task 1~4 Codex 深审：
  - 审查范围：`lib/media_backend/playback/media_playback.dart`、`media_playback_selectors.dart`、`lib/media_backend/feiniu/feiniu_playback_mappers.dart`、`lib/media_backend/feiniu/feiniu_media_backend.dart`、对应 `test/media_backend/*playback*`。
  - 结论：公共 playback 模型未发现飞牛/Emby 私有字段进入公开命名；`FeiniuMediaBackend.getPlayback` 未构造 `MpvMediaSource`，未引入 `BuildContext`/导航/`NativePlayerBridge`/播放器页面；没有 UI `if (isEmby)` 或 Emby API 接入。`getPlayback` 当前仍是“后端播放事实 bundle”，不是最终 mpv load 参数，桥接阶段必须继续由 player/controller 层调用 `PlayerSourceController.buildInitialPlaybackResult`。
  - Codex 小修提交：`b0b37ae`。修复点：`selectPlaybackQuality` 原先 fallback 为“第一个 default”，与旧入口 `PlayerSourceController.preferredInitialQuality` 的“直链 default → 任意直链 → 原画 → default → first”不一致；且 `qualityId` 命中同 source 多档时会选列表第一档，旧入口切版本会优先该 source 的原画/default。已改 selector 并补 2 条回归测试。
  - 验证：`flutter test test\media_backend\media_playback_selectors_test.dart` → 6 PASS；`flutter test test\media_backend\ --concurrency=1` → 75 PASS；`flutter analyze lib\media_backend test\media_backend` → No issues。
  - 桥接建议：可以开下一子阶段，但应先做“桥接器 + 单条目 launcher 灰度迁移”，不要一次性迁 `TvSeasonPlaybackLauncher`、本地下载、原生反向重载全部路径；桥接器必须明确使用 bundle 的 raw/selected facts 重新调用 `PlayerSourceController.buildInitialPlaybackResult`，不要直接信任 `MediaPlaybackSource.url` 是最终可播 URL。

## Codex 审查记录

- 2026-06-20 Task 1~4 审查：
  - 审查提交：`ef6405c`、`f40f06a`、`e97112b`、`3986ef5`、`937af46`
  - 结论：已提交的公共模型、Feiniu mapper、`MediaBackend` 接口和 `FeiniuMediaBackend` 适配器未发现阻塞问题；未发现 UI 中新增 `if (isEmby)`；未发现接入 Emby API；`FeiniuMediaBackend` 目前保持为薄适配层，没有夹带 UI 业务逻辑。
  - 风险 1：`test/media_backend/feiniu_media_backend_test.dart` 当前只验证 capabilities，没有实际覆盖 `FeiniuMediaBackend` 对 `FeiniuApi` 的转发、分页参数和 mapper 输出。Task 5/6 迁移页面前，建议补一个可测试的 API seam，或让适配器依赖更小的协议接口。
  - 风险 2：`MediaImageRef` 已有 headers 字段，但 Task 3/4 的 Feiniu mapper/adapter 目前输出空 headers。首页或详情页改为直接消费公共图片引用前，需要在 Feiniu 适配层补齐 NAS 图片鉴权 headers，避免迁移后封面预热/展示丢 token。
  - 工作区检查：`git diff --cached --name-only` 为空；当前仍有大量非本任务未提交改动，Codex 未回滚、未暂存、未夹带。
  - 验证：`flutter test test/media_backend/ --concurrency=1` → PASS；`flutter analyze lib/media_backend/` → No issues；`flutter analyze` → FAIL（38 条，均不在 `lib/media_backend`，包含既有/其它工作区文件的 duplicate import、unused、prefer_const 等）。
- 2026-06-20 Task 5 审查：
  - 审查提交：`4b3002d`
  - 结论：`MediaBackendProvider` 注入位置正确，未迁移页面，未新增 UI 后端分支；`ChangeNotifierProxyProvider` 当前依赖同一个 `NasProvider` 实例，生命周期暂无阻塞问题。
  - 补测：新增 `test/media_backend/media_backend_provider_test.dart`，验证 provider 使用当前 `NasProvider` 暴露 Feiniu 后端能力；测试中等待 `NasProvider` 异步初始化完成后再释放，避免测试清理阶段误触已 dispose provider。
  - 仍需关注：`MediaBackendProvider.backend` 每次读取都会创建新的 `FeiniuApi`/`FeiniuMediaBackend`；如果 Task 6 页面频繁读取 backend，建议改为缓存实例或在 Provider 内按 NAS 会话变更重建，避免重复创建 Dio。
  - 验证：`flutter test test/media_backend/media_backend_provider_test.dart` → PASS；`flutter analyze test/media_backend/media_backend_provider_test.dart` → No issues；`flutter test test/media_backend/ --concurrency=1` → 7 PASS。
- 2026-06-20 Task 6 审查：
  - 审查提交：`1ff413b`、`9e012b7`、`180e8c0`、`746eb8e`
  - 结论：缩小范围后的 Task 6 未发现阻塞问题。`media_list_screen.dart` 仅把首页分类入口和概要改为通过 `MediaBackendProvider.backend` 获取；继续观看、分类预览和 `_refreshContinueWatching()` 仍保留 `FeiniuApi`，与“富 item 链路暂不迁移”的决策一致。
  - 架构检查：未发现 UI 中新增 `if (isEmby)`；未接入 Emby API；`MediaCatalog -> MediaItem` 过渡转换仅存在于 `media_list_screen.dart`，未扩散到其它文件；`MediaCatalog.posters` 属于前端展示概念，用于保持首页分类叠图无损，不是飞牛私有字段。
  - 风险/后续：`MediaItemSummary` 在 `1ff413b` 先扩展了一批展示字段，随后 Task 6 又缩小为不迁移富 item 链路；这些字段目前暂时未被首页使用，建议后续继续以 Emby 实际字段一起校准，避免公共模型继续向 `MediaLibraryItem` 形状膨胀。`MediaBackendProvider.backend` 仍是每次读取新建实例，Task 6 每次加载会读取一次，暂无阻塞，但后续迁移更多页面前仍建议缓存。
  - 工作区检查：`git diff --cached --name-only` 为空；`lib/media_backend`、`test/media_backend`、`lib/screens/media_list_screen.dart`、本状态文档在审查前均无未提交改动；其它大量未提交文件与本次审查无关，Codex 未回滚、未暂存、未夹带。
  - 验证：`flutter analyze lib/screens/media_list_screen.dart` → No issues；`flutter test test/home_scroll_physics_test.dart test/main_navigation_layout_test.dart --concurrency=1` → PASS；`flutter test test/media_backend/ --concurrency=1` → 9 PASS；`flutter analyze` → FAIL（19 条，均不在 Task 6 相关文件，主要为既有 duplicate import、unused、prefer_const、use_build_context_synchronously）。
- 2026-06-20 Phase 4 审查：
  - 审查提交：`c849e2a`、`fa878ba`、`013d2fe`、`a68c95e`、`a8adf76`、`3789e0c`
  - 结论：未发现阻塞问题。`MediaItemCard` 覆盖搜索/分类卡片展示字段，字段命名保持后端中立；`mapFeiniuItemCard` 只在适配层搬运飞牛字段；搜索结果读取已从 `FeiniuApi.searchList` 迁到 `MediaBackend.searchItems`。
  - 架构检查：未发现搜索页新增 `if (isEmby)` 或 Emby API；`search_screen.dart` 剩余 `FeiniuApi.getItemDetail` 仅用于详情页本期未迁移的预取入口，动作面板 `_cardToActionItem` 局部回转只在本文件内使用，未扩散。分类页仍保留飞牛 API，符合“分类页滤镜体系另立设计、本期不动”的范围。
  - 风险/后续：`MediaItemCard` 已包含较完整的富卡片字段，后续迁移分类页时不要继续按飞牛筛选/排序字段膨胀模型，应单独设计查询/filter 抽象。`FeiniuMediaBackend.searchItems` 仍缺少可替换 fake seam，适配器转发行为主要靠 mapper 单测和页面分析兜底。
  - 工作区检查：`git diff --cached --name-only` 为空；`lib/media_backend`、`test/media_backend`、`lib/screens/search_screen.dart`、本状态文档在审查前均无未提交改动；其它未提交工作区文件与本次审查无关，Codex 未回滚、未暂存、未夹带。
  - 验证：`flutter test test/media_backend/ --concurrency=1` → 11 PASS；`flutter analyze lib/media_backend test/media_backend lib/screens/search_screen.dart` → No issues；`flutter analyze lib/screens/search_screen.dart` → No issues；`flutter analyze` → FAIL（19 条，均不在 Phase 4 相关文件，主要为既有 duplicate import、unused、prefer_const、use_build_context_synchronously）。
- 2026-06-20 Phase 4.5 Task 5-1 审查：
  - 审查提交：`ccc058d`、`38e3315`
  - 结论：filter 公共模型未发现阻塞问题。`MediaFilterDimensionKind`、`MediaFilterOption`、`MediaCatalogFilterSchema`、`MediaCatalogQuery`、`MediaItemCardPage` 均保持纯数据结构；没有接入 Emby API，也没有把飞牛 API 调用放进公共模型。
  - 架构检查：双轨 label 设计落在 `kind/value/label` 与 `genreNames/regionNames` 字典上，适合后续 UI localizer 接管文案；`MediaItemCardPage` 复用 `MediaItemCard`，没有新增第二套条目模型。公共模型中出现的 `genres`/`locate`/`create_time` 等目前主要在注释和默认值中，未绑定具体 Feiniu 类。
  - 风险/后续：`MediaCatalogQuery.sortField` 默认 `create_time` 带飞牛字段味道，虽然后续 schema 会下发可用排序字段，但 Task 5-2/5-4 最好由调用方或 schema 显式给默认排序，避免公共层默认值固化飞牛命名。
  - 工作区检查：`git diff --cached --name-only` 为空；`lib/media_backend`、`test/media_backend`、本状态文档在审查前除本次文档更新外无未提交改动；其它未提交文件与本次审查无关，Codex 未回滚、未暂存、未夹带。
  - 验证：`flutter test test/media_backend/ --concurrency=1` → 16 PASS；`flutter analyze lib/media_backend test/media_backend` → No issues；`flutter analyze` → FAIL（19 条，均不在 Phase 4.5 Task 5-1 相关文件）。单独并行启动 `flutter test test/media_backend/media_catalog_filter_test.dart` 曾因 Flutter startup/native-assets 锁超时，但该测试已在整组串行测试中通过。
- 2026-06-20 Phase 4.5 Task 5-2 审查与收口：
  - 实现提交：`1dcedda`
  - 结论：未发现阻塞问题。公共 `MediaBackend` 只新增 schema/query 两个分类筛选能力；公共模型仍为纯数据结构，未出现飞牛/Emby 私有模型泄漏；未接入 Emby API；未在 UI 中新增 `if (isEmby)`。
  - 架构检查：`FeiniuMediaBackend` 保持薄适配层，只负责调用现有 FeiniuApi 并把结果交给 mapper；飞牛专属的 selection→`ItemListRequest` 字段转换集中在 `feiniu_media_mappers.dart`，未扩散到页面。`type` 默认回退、`genres` int 化、`recognition_status`/`watched` 字符串化、`decades/resolutions` 源键到 `decade/resolution` 提交键均已用单测覆盖。
  - 风险/后续：排序字段 `create_time`、`release_date`、`title`、`vote_average` 仍是 Feiniu 当前分类页字段，作为 Feiniu schema 下发可接受；Task 5-4 迁移分类页时应从 schema/页面状态显式选择排序，不要在 UI 里硬编码后端类型分支。图片 headers、播放入口和视图偏好仍未进入本 Task 范围。
  - 工作区检查：实现提交前 `git diff --cached --name-only` 仅包含 `lib/media_backend/media_backend.dart`、`lib/media_backend/feiniu/feiniu_media_backend.dart`、`lib/media_backend/feiniu/feiniu_media_mappers.dart`、`test/media_backend/feiniu_filter_mappers_test.dart`；其它大量未提交工作区文件与本次收口无关，Codex 未回滚、未暂存、未夹带。
  - 验证：`flutter test test/media_backend/feiniu_filter_mappers_test.dart` → 12 PASS；`flutter test test/media_backend/ --concurrency=1` → 28 PASS；`flutter analyze lib\media_backend test\media_backend` → No issues；`flutter analyze` → FAIL（19 条，均不在 Task 5-2 相关文件，主要为既有 duplicate import、unused、prefer_const、use_build_context_synchronously）。
- 2026-06-20 Phase 4.5 Task 5-3 审查：
  - 审查提交：`15a3853`、`34bfed1`
  - 结论：未发现阻塞问题。`CatalogFilterLocalizer` 放在 `lib/ui/`，依赖 `AppLocalizations` 与 `MediaCatalogFilterSchema`，没有把 UI/l10n 依赖反灌进 `lib/media_backend`；未接入 Emby API，未在 UI 中新增 `if (isEmby)` 或运行时后端分支。
  - 架构检查：localizer 按 `MediaFilterDimensionKind` 处理 `plain`、genre、region、decade、resolution、audioType、colorRange、recognitionStatus、watched、mediaType，并提供 `dimensionTitle` 与 `sortLabel`，可供 Task 5-4 复用，避免分类页迁移时继续散落 labeler。对照 `category_items_screen` 现有 `_resolutionLabel`、`_audioLabel`、`_decadeLabel`、`_typeLabel`、`_recognitionStatusLabel`、`_watchedLabel`、`_sortLabelFor`，语义一致。
  - 风险/后续：Task 5-4 使用时仍需确认筛选摘要、弹窗标题、排序菜单和未知值回退全部改为走 localizer；当前 Task 5-3 只提供工具类，不迁移页面，因此还没有人工 UI 验证。
  - 工作区检查：审查时 `git diff --cached --name-only` 为空；`git status --short` 仅剩未跟踪 `HANDOFF.md`，与本次审查无关，Codex 未暂存、未提交。
  - 验证：`flutter test test/ui/catalog_filter_localizer_test.dart` → 12 PASS；`flutter test test/media_backend/ --concurrency=1` → 28 PASS；`flutter analyze lib\media_backend test\media_backend lib\ui\catalog_filter_localizer.dart test\ui\catalog_filter_localizer_test.dart` → No issues；`flutter analyze` → FAIL（17 条，均不在 Task 5-3 相关文件，主要为既有 duplicate import、unused、prefer_const、use_build_context_synchronously）。
- 2026-06-20 Phase 4.5 Task 5-4 审查：
  - 审查提交：`9b06e3d`、`5b6ea4b`、`0fe5866`
  - Codex 小修提交：`085d051`
  - 结论：未发现阻塞问题。分类页条目查询已从 `FeiniuApi.getItemsPageByRequest` 迁到 `MediaBackend.queryCatalogItems`，筛选 schema 通过 `MediaBackend.getCatalogFilterSchema` 获取，展示文案通过 `CatalogFilterLocalizer` 统一处理；未接入 Emby API，未在 UI 中新增 `if (isEmby)`。
  - 架构检查：`FeiniuApi` 残留仅用于本阶段明确保留的视图/排序偏好 `getUserListSetting`/`setUserListSetting`、详情页预取 `getItemDetail` 和动作面板内部飞牛操作；filter selection→飞牛 `ItemListRequest` 转换仍集中在适配层 mapper。`MediaLibraryItem` 仅作为动作面板局部回填模型使用，未重新成为列表数据源。
  - Codex 小修：原 Task 5-4 已拿到 `MediaCatalogFilterSchema.sortOptions`，但排序菜单仍使用页面内静态飞牛字段列表；已改为 `_sortColumns` 优先读取 schema.sortOptions，schema 为空时才回退旧字段，避免排序字段继续硬编码在 UI。
  - 风险/后续：当前仍需 `flutter run` 登录飞牛人工验证筛选/排序/翻页、type 锁定入口、三种视图、动作面板和详情跳转。图片 headers、详情页公共模型、播放入口不属于 Phase 4.5 范围。
  - 工作区检查：审查前 `git status --short` 仅剩未跟踪 `HANDOFF.md`；Codex 小修提交前 `git diff --cached --name-only` 仅包含 `lib/screens/category_items_screen.dart`，未夹带其它文件。
  - 验证：`flutter test test/media_backend/feiniu_filter_mappers_test.dart` → 13 PASS；`flutter test test/media_backend/ test/ui/catalog_filter_localizer_test.dart --concurrency=1` → 41 PASS；`flutter analyze lib/screens/category_items_screen.dart lib/media_backend test/media_backend lib/ui/catalog_filter_localizer.dart test/ui/catalog_filter_localizer_test.dart` → No issues；`flutter analyze` → FAIL（17 条，均不在 Phase 4.5 相关文件，主要为既有 duplicate import、unused、prefer_const、use_build_context_synchronously）。
- 2026-06-21 Phase 5 Emby 官方 API 形状调研：
  - 调研提交：`756f2eb`
  - 文档：`docs/superpowers/research/2026-06-21-emby-api-shape.md`
  - 结论：Emby 官方 REST API 可以支撑继续做公共媒体前端抽象；列表/搜索/分类主要落在 `GET /Users/{UserId}/Items`，详情落在 `GET /Users/{UserId}/Items/{Id}`，剧集季/集落在 `GET /Shows/{Id}/Seasons` / `GET /Shows/{Id}/Episodes`，图片走 ImageService，播放信息走 `GET /Items/{Id}/PlaybackInfo`。
  - 架构判断：Phase 5 不宜直接把详情页改成读 Emby 或 `Map<String,dynamic>`；应先定义公共 `MediaDetail` / `MediaSeasonSummary` / `MediaEpisodeSummary` 等模型，再写 Feiniu mapper 和 `MediaBackend` 详情接口。页面迁移时保留下载、动作面板、播放入口等飞牛专属能力；播放入口继续留到 Phase 6。
  - 风险：`play_detail_page.dart`、`tv_detail_page.dart`、`item_playback_launcher.dart` 仍混有大量 `FeiniuApi`、`PlayInfoData`、`StreamTrackData` 和裸 Map。若一次性迁移，会把详情展示、播放、音轨/字幕、下载和 Emby DTO 绑定到同一批改动里。
  - 工作区检查：调研提交前暂存区仅包含新增研究文档；未修改 `lib/` 代码；工作区仍有未跟踪 `HANDOFF.md`，与本任务无关、未暂存。
  - 下一步建议：先写 Phase 5 设计文档和实施计划；不新增 `EmbyApi` 代码；如有真实 Emby 测试服，仅用官方 API Browser 或只读 curl 抓脱敏样本，严禁提交 token/server/user。
- 2026-06-21 Phase 5 设计 + 实施计划：
  - 文档：设计 `docs/superpowers/specs/2026-06-21-public-media-detail-design.md`、计划 `docs/superpowers/plans/2026-06-21-public-media-detail.md`。
  - 实地审计（已核对代码）：`getItemDetail`→`Map`（`item` 键解析 `PlayItem`，聚合 `PlayInfoData`）；`PlayItem` 33 字段切分为"展示半/播放半"；`getSeasonList`/`getEpisodeList`→`List<MediaLibraryItem>`；`getPersonDetail`→`PersonDetailProfile`；首屏聚合在 `play_detail_data_loader.dart` 的 `PlayDetailInitialData`。
  - 边界结论：公共 `MediaDetail`/`MediaSeasonSummary`/`MediaEpisodeSummary`/`MediaDetailPerson`/`MediaExternalIds` 只收展示半；播放接线（mediaGuid/轨道/canPlay/playConfig）+ 下载 + 片头片尾 + 动作写回 + FN Connect + 续播写回留页面侧（Phase 6 / 飞牛专属）。题材/地区在适配层翻好（非双轨）。
  - 未改业务代码；仅新增两份文档 + 本看板更新。
  - 下一步：等用户确认，从计划 Task 1（公共详情模型 + 单测）开始主实现，每步单独提交。
- 2026-06-21 Phase 5 Task 1~3 实现（模型/mapper/backend 骨架，Claude 主实现）：
  - Task 1（公共详情模型）：新建 `lib/media_backend/detail/media_detail.dart`（`MediaDetail`+`MediaExternalIds`+`MediaDetailPerson`，含 `displayTitle`+`copyWith`）、`media_season_summary.dart`、`media_episode_summary.dart` + `test/media_backend/media_detail_models_test.dart`（6 PASS）。提交 `c2fffa6`。
    - 实现中修正：审计发现详情页演职员是**扁平** `_personCredits`（渲染"Cast and crew"合并区），故把模型 cast/crew 拆分改为单一 `people` 列表（每人带 `department` 区分，兼容 Emby `People[].Type`），反映真实消费。提交 `c60292c`。
  - Task 2（飞牛 detail mapper）：新建 `lib/media_backend/feiniu/feiniu_detail_mappers.dart`（`mapFeiniuItemDetail`/`mapFeiniuSeason`/`mapFeiniuEpisode`）+ `test/media_backend/feiniu_detail_mappers_test.dart`（7 PASS）。提交 `87c3377`。
    - 关键映射：`PlayInfoData`→`MediaDetail` **只搬展示半**；题材/地区在适配层翻好（`genresMap`/`iso3166Map`，未命中原样回退、地区大写查表）；`info.ts`→续播；`item.trimId`→tmdbId、`imdbId` 由调用方传入；演职员 `PersonCredit`→扁平 `people`（name 空回退 originalName，role/job 保留）。
  - Task 3（backend 详情接口）：`MediaBackend` 新增 `getItemDetail`/`getItemSeasons`/`getSeasonEpisodes`；`FeiniuMediaBackend` 实现（`getItemDetail` 装配 `getPlayInfo`+`getItemDetail`(取 imdbId)+`getPersonList`(best-effort)+字典）。imdb 提取助手 `extractFeiniuImdbId` 放 mapper 层避免 backend 反向依赖 UI 控制器 + `test/media_backend/feiniu_detail_backend_test.dart`（3 PASS）。提交 `dd8630d`。
  - 验证：`flutter test test/media_backend/ --concurrency=1` → 47 PASS；`flutter analyze lib/media_backend test/media_backend` → No issues。
  - 数据来源审计（真实）：详情页数据 = `getPlayInfo`(→PlayInfoData) + `getItemDetail`(→Map，仅取 imdb/trim) + `getPersonList`(→PersonCredit) + `getStreamTrackData`(轨道，Phase 6) + 字典。
  - 下一步：Task 4 电影详情入口壳层迁移（改 `lib/pages/play_detail_page.dart` 只读展示区数据来源，播放/轨道/下载/动作面板/片头片尾保留飞牛）——属页面级改动，需 `flutter run` 实机验证，建议先经用户/Codex 确认切口后再动。
- 2026-06-21 Phase 5 Task 1~3 Codex 审查 + 修复（Claude 修）：
  - Codex 提 3 条（2×P1 已核实为真并修，1×P2 已补测）：
  - **P1 续播回退（已修，提交 `63a91f7`）**：mapper 只取裸 `info.ts`/`item.ts`，但 `play_detail_page.dart:1054/1245/2122` 实为 `ts > 0 ? ts : item.watchedTs`、`tv_season_detail_page.dart:511/522` 实为 `episode.ts > 0 ? episode.ts : episode.watchedTs`。`ts==0 && watchedTs>0` 时会丢续播。改：`MediaDetail.resumePositionSeconds = info.ts>0 ? info.ts : item.watchedTs`；`MediaEpisodeSummary = item.ts>0 ? item.ts : item.watchedTs`。补 2 条 mapper 单测。
  - **P1 字典阻断详情（已修，提交 `63a91f7`）**：`getItemDetail` 直接 await 题材/地区字典，任一失败会让整个详情打不开；旧 `play_detail_page.dart:687-694` 实为 `.catchError((_) => const {})` 降级。改：字典 best-effort，失败回空 map（与演职员 best-effort 一致），详情仍可看、题材退化为原始 id。
  - **P2 orchestration 无真实覆盖（已补，提交 `8452fd7`）**：原仅测 `extractFeiniuImdbId`。新增 `_FakeFeiniuApi extends FeiniuApi`（覆写 `getPlayInfo`/`getItemDetail`/`getPersonList`/字典/`getSeasonList`/`getEpisodeList`，构造只配 Dio、无网络）+ 3 条编排测试：getItemDetail 正确装配 playInfo+imdb+credits+字典并传 mapper、字典失败 best-effort 详情仍可读、季/集转发映射。注：本 fake seam 当前仅覆盖 detail 三方法；searchItems/queryCatalogItems 等其余适配器方法的 fake 覆盖仍是横切缺口，建议后续统一为整个 `FeiniuMediaBackend` 设计一次可注入 seam。
  - 验证：`flutter test test/media_backend/ --concurrency=1` → 52 PASS；`flutter analyze lib/media_backend test/media_backend` → No issues。
- 2026-06-21 Phase 5 Task 4/5 切口调查结论（Claude，未改业务代码）：
  - 动手前审计两个目标页的展示数据流，确认**没有干净的增量切口**，强行迁移风险高且无法在本会话实机验证：
  - **Task 4 `play_detail_page.dart`（2110~2273 build 闭包）**：展示字段与播放态在同一闭包内交错计算——`detailTitle`(2155) 依赖 `item.type/title/displayTitle`；`metaLineA`(2138) 走 `PlayDetailFormatters.metaLineA(item, genreMap:_genresMapZhCn, locateMap:_locateMapZhCn)`；能力角标(2197) 在 `selectedOption`(播放态) 与 `item.resolutions/colorRanges/audioTypes` 间二选一；`creditItems`(2257) 由 `_personCredits` 构造。把展示改读 `MediaDetail` 必然触碰 `selectedOption`/`_streamOptions`/轨道/下载记录等播放耦合代码。且页面已自行加载 `_genresMapZhCn`(686) 与完整 `PlayInfoData`，并行再取一份 `MediaDetail` 会重复请求；让 loader 产出 `MediaDetail` 则要改控制器与播放路径。
  - **Task 5 `tv_detail_page.dart`（1478~1553 季卡片）**：季卡片本身较独立（读 `season.voteAverage/poster/resolutions/watched/guid`），但 `onTap` 把原始 `initialSeasonItems: _seasonItems`（`List<MediaLibraryItem>`）透传给下游 `tv_season_detail_page`。把 `_seasonItems` 换成 `MediaSeasonSummary` 会破坏下游页面契约，涟漪到另一文件。
  - 结论：与 Emby 调研建议一致（详情页迁移宜等接 Emby 时连同字段形状一起做）。**骨架（公共详情模型 + mapper + backend 接口，52 PASS、Codex 已审）作为 Phase 5 交付，页面迁移暂缓**，等 Phase 6 播放入口或 Emby 接入时，由第二后端倒逼出真正的展示/播放分层，再连同下游一起迁。
  - 备选（若坚持现在迁页面）：只能走「页面并行持有 `MediaDetail`(展示)+`PlayInfoData`(播放)」的大改，需逐字段替换 build 闭包并 `flutter run` 反复验证；当前单后端下该改动只是增加间接层、收益有限。
- 2026-06-21 Phase 5 收口 Codex 复审：
  - 复审结论：Task 1~3 的公共详情骨架未发现新的阻塞问题；上次 Codex 提出的续播回退与字典 best-effort 已由 `63a91f7` 修复，backend 编排测试已由 `8452fd7` 补上。
  - 验证：`flutter test test/media_backend/ --concurrency=1` → 52 PASS；`flutter analyze lib/media_backend test/media_backend` → No issues；`git status --short` 仅剩未跟踪 `HANDOFF.md`。
  - Follow-up：既然 Task 4/5 页面迁移暂缓，Phase 5 可以作为“公共详情后端骨架”收口；但不要过度声明“公共详情模型无需改动”。旧 `tv_detail_page` 季卡片仍消费 `voteAverage`、`resolutions`、`watched`、`releaseDate/episodeCount` 等中立展示字段，而当前 `MediaSeasonSummary` 只有 id/title/seasonNumber/count/image。未来真正迁页面或接 Emby 时，应先校准 `MediaSeasonSummary` 字段，再动 UI。

## Claude 下一步任务

- [x] Phase 5 骨架（Task 1~3 + Codex 修复）完成并收口（用户 2026-06-21 选 A）。
- [ ] Phase 5 页面迁移（Task 4/5）暂缓，等真正接 Emby 时再做（届时连同下游 `tv_season_detail_page` / 播放路径一起设计）。
- [ ] 待用户确认下一个方向（Phase 6 播放入口 / Emby 接入 / 其它）后再开新 Task。
- [ ] 每完成一个小任务且测试通过后，立即单独提交。
- [ ] 上下文偏长时输出压缩摘要并停止继续执行。

## Codex 下一步任务

- [ ] 检查 Claude 已完成的 Task。
- [ ] 查找公共模型泄漏、UI 分支、Provider 生命周期、测试缺口、夹带文件等问题。
- [ ] 只做小范围修复或补测试。
- [ ] 跑相关测试和 `flutter analyze`，把审查结果写回本文档。
- [ ] 小范围修复测试通过后，立即单独提交。

## 调用点清单

待 Claude 或 Codex 更新。初步已知高风险区域：

- `lib/screens/media_list_screen.dart`
- `lib/screens/category_items_screen.dart`
- `lib/screens/search_screen.dart`
- `lib/screens/play_detail_screen.dart`
- `lib/pages/play_detail_page.dart`
- `lib/pages/tv_detail_page.dart`
- `lib/controllers/item_playback_launcher.dart`
- `lib/player/page_parts/core/mpv_player_episode_mixin.dart`
- `lib/player/page_parts/core/mpv_player_runtime_mixin.dart`
- `lib/player/page_parts/view/mpv_player_options_mixin.dart`

## 字段依赖表

待 Claude 或 Codex 更新。初步字段：

- 飞牛条目 id：`guid`
- 飞牛媒体库 id：`id` / `guid`
- 类型：`type`
- 标题：`title` / `tv_title` / `parent_title`
- 图片：`poster` / `posters` / `backdrops` / `poster_list`
- 层级：`parent_guid` / `ancestor_guid` / `ancestor_name`
- 播放：`media_guid` / `video_guid` / `audio_guid` / `subtitle_guid`
- 进度：`ts` / `watched_ts` / `watched`

## 禁止事项

- 不要在 UI 文件里添加 `if (isEmby)`。
- 不要把 Emby 字段提前放进公共模型。
- 不要在第一阶段改下载任务。
- 不要在第一阶段迁移播放器深层逻辑。
- 不要同时让两个模型修改同一个文件。
