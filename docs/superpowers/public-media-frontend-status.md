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
| Phase 2: FeiniuMediaBackend 和 Provider | 进行中 | Claude 主实现，Codex 审查 | Task4: 3986ef5 / Task5: 4b3002d | 单元测试 + analyze |
| Phase 3: 首页迁移样板 | 未开始 | Claude 主实现，Codex 验证 |  | 首页测试 + 手动验证 |
| Phase 4: 分类页和搜索页迁移 | 未开始 | Claude 主实现，Codex 审查 |  | 页面测试 + 手动验证 |
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

- [ ] Task 6: 首页 media_list_screen 迁移样板（待实施）
  - 已具备无损前提：`MediaItemSummary` 扩展完成后，公共模型可无损转回 `MediaLibraryItem` 首页展示字段。
  - 计划做法：`_fetchHomeData()`/`_backgroundRefresh()` 改用 `context.read<MediaBackendProvider>().backend`，公共模型经本地临时转换函数转回旧模型喂现有 UI；转换函数仅限本文件，不扩散。
  - 注意 1（main.dart 同款隔离）：`media_list_screen.dart` 工作区已有无关未提交改动（hunk 在 line 27/214-226/311-323/563-572），需 `git stash push -- <file>` 隔离后再改、提交、`git stash pop`；但本文件未提交改动与改动点更接近，pop 前需确认无冲突。
  - 注意 2（Codex 风险 2 图片 headers）：本任务把公共模型转回旧模型，图片仍走旧 NAS 鉴权路径，`MediaImageRef.headers` 留空不影响；待页面直接消费公共图片引用时再在适配层补 headers。
  - 注意 3（Codex 风险 / Task5 审查）：`MediaBackendProvider.backend` 每次读取新建 `FeiniuApi`，首页若频繁读取建议先缓存 backend 实例，避免重复创建 Dio。

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
