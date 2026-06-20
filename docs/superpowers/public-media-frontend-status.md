# 公共媒体前端协作状态

本文档用于 Codex、Claude 和用户共享推进状态。每完成一块任务，就更新状态、提交 hash、验证命令和下一步负责人。

## 当前阶段

阶段：Phase 1 进行中，用户已确认按实施计划从 Task 1 开始主实现。

目标：建立公共模型、Feiniu mapper、MediaBackend 接口和适配器（Task 1~4），保持飞牛体验不退化。

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
| Phase 4: 搜索页迁移（统一 MediaItemCard） | 完成（搜索页已迁移，待手动验证；分类页滤镜体系另立设计、本期不动） | Claude 主实现，Codex 审查 | 设计 c849e2a / 模型 fa878ba / mapper 013d2fe / 收口 a68c95e / 搜索页 a8adf76 | media_backend 11 PASS + analyze；flutter run 手动验证待做 |
| Phase 5: 详情页迁移 | 未开始 | Claude 主实现，Codex 审查 |  | 电影/剧集详情手动验证 |
| Phase 6: 播放入口迁移 | 未开始 | Claude 主实现，Codex 深审 |  | 播放、音轨、字幕验证 |

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
    - Codex Task5 审查：`MediaBackendProvider.backend` 每次读取新建 `FeiniuApi`/`FeiniuMediaBackend`，首页每次刷新会各读 1 次；建议后续在 Provider 内缓存 backend 实例或按 NAS 会话变更重建，避免重复创建 Dio。

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
  - **待人工验证（交用户/Codex）**：`flutter run` 登录飞牛后确认——① 搜索结果标题/封面/评分/清晰度/已观看角标与迁移前一致；② 年份区间与季/集副标题正确（电影、单季剧、多季剧、person 作品数）；③ 点击进入详情（item / person）正常；④ 长按动作面板（标记已观看/收藏）正常且本地角标即时更新。

### 明确不做

- 不碰分类页滤镜/排序/标签体系（飞牛专属，另立设计）。
- 不在 UI 写 `if (isEmby)`；不接 Emby API。
- `_cardToActionItem` 局部转换仅限搜索页本文件，不扩散。

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

## Claude 下一步任务

- [ ] 等用户确认后，从实施计划 Task 1 开始主实现。
- [ ] 每完成一个 Task，运行计划里的对应测试。
- [ ] 每完成一个 Task，更新本文档状态、测试结果、提交 hash。
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
