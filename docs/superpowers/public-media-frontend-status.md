# 公共媒体前端协作状态

本文档用于 Codex、Claude 和用户共享推进状态。每完成一块任务，就更新状态、提交 hash、验证命令和下一步负责人。

## 当前阶段

阶段：Phase 0，文档和协作基线已完成，等待用户确认是否开始 Phase 1。

目标：先建立公共前端抽象的设计、实施计划和可勾选状态看板，不改业务代码。

## 负责人约定

- Codex：架构边界、样板代码、最终集成、测试收口、提交。
- Claude：调用点清单、字段映射表、mapper 测试、简单页面迁移草案。
- User：确认阶段范围，决定是否扩大到详情页或播放器。

## 总进度

| 阶段 | 状态 | 负责人 | 提交 | 验证 |
| --- | --- | --- | --- | --- |
| Phase 0: 设计和协作基线 | 完成 | Codex | 本次文档提交 | 文档自查通过 |
| Phase 1: 公共模型和 Feiniu mapper | 未开始 | Codex 或 Claude |  | 单元测试 |
| Phase 2: FeiniuMediaBackend 和 Provider | 未开始 | Codex |  | 单元测试 + analyze |
| Phase 3: 首页迁移样板 | 未开始 | Codex |  | 首页测试 + 手动验证 |
| Phase 4: 分类页和搜索页迁移 | 未开始 | Claude 草案，Codex 集成 |  | 页面测试 + 手动验证 |
| Phase 5: 详情页迁移 | 未开始 | Codex |  | 电影/剧集详情手动验证 |
| Phase 6: 播放入口迁移 | 未开始 | Codex |  | 播放、音轨、字幕验证 |

## 当前可执行任务

- [x] 写公共媒体前端设计文档。
- [x] 写第一阶段实施计划。
- [x] 写共享状态看板。
- [ ] 用户确认是否按 Phase 1 开始实施。

## Claude 可先做的独立任务

- [ ] 扫描所有直接调用 `FeiniuApi(` 的文件，整理到本文档“调用点清单”。
- [ ] 扫描页面使用 `MediaItem` / `MediaLibraryItem` 字段的位置，整理字段依赖表。
- [ ] 根据计划 Task 3 编写 `feiniu_media_mappers_test.dart` 草案。
- [ ] 标记哪些调用点属于飞牛专属能力，不能公共化。

## Codex 下一步任务

- [ ] 等用户确认后执行计划 Task 1。
- [ ] 每个 Task 完成后跑对应测试。
- [ ] 每个 Task 完成后更新本文档状态并提交。

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
