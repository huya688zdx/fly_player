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
| Phase 1: 公共模型和 Feiniu mapper | 进行中 | Claude 主实现，Codex 审查 | Task1: ef6405c / Task2: f40f06a | 单元测试 |
| Phase 2: FeiniuMediaBackend 和 Provider | 未开始 | Claude 主实现，Codex 审查 |  | 单元测试 + analyze |
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
- [ ] Task 3: Feiniu mapper
- [ ] Task 4: MediaBackend 接口和飞牛适配器

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
