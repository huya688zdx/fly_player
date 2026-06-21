# Phase 5 续：详情页迁移实施计划（电影详情先行）

设计：`docs/superpowers/specs/2026-06-22-public-media-detail-page-migration-design.md`
日期：2026-06-22
原则：每个 Task 可编译、单独提交；提交前查 `git status --short` 与 `git diff --cached --name-only`，**用 pathspec 提交**（`git commit -- <自己的文件>`，防 Codex 并行 stage 夹带）；不夹带 `HANDOFF.md`/`MpvPlaybackController.kt`/login-backend 文档。

## Task 1：页面侧进程内构造 `_detail`（无 UI 改动，零行为变化）

**改动文件**
- `lib/pages/play_detail_page.dart`：
  - 新增 `MediaDetail? _detail;`（import `media_backend/detail/media_detail.dart` + `media_backend/feiniu/feiniu_detail_mappers.dart`）。
  - 在首屏数据就绪处（`_genresMapZhCn`/`_locateMapZhCn`/`_personCredits`/imdb 均已 set 之后）构造
    `_detail = mapFeiniuItemDetail(info, genresMap: _genresMapZhCn, regionNames: _locateMapZhCn, credits: _personCredits, imdbId: <imdb>)`；状态刷新后同样重建。
  - build 闭包**仍读旧源**（本 Task 不改 UI）。
- 测试：新增 `test/pages/play_detail_detail_mapping_test.dart`（或就近）——纯函数断言：给定 `PlayInfoData` + credits + 字典 → `mapFeiniuItemDetail` 产出的 `MediaDetail` 关键展示字段（title/displayTitle/overview/rating/resolutions/people/watched/resumePositionSeconds）与 `info.item` 对应值一致。**不触网**（直接构造 `PlayInfoData`/`PlayItem` fixture，复用 Phase 5 mapper 测试的构造方式）。

**验证**：`flutter test <新测试>`；`flutter analyze lib/pages/play_detail_page.dart <测试>` → No issues。

**提交**：pathspec 单独提交。

## Task 2：纯展示字段迁移（不碰播放态）

**改动文件**
- `lib/utils/play_detail_formatters.dart`：`metaLineA` 增加中立入参路径——接受已翻好的 `genreLabels`/`regionLabels`（+ 年份/必要字段），不再在 formatter 内查 `genreMap`/`locateMap`。保留旧签名或就地改调用方（按 analyze 实际）。补/改 formatter 单测。
- `lib/pages/play_detail_page.dart` build 闭包：标题/简介/海报背景logo/评分年份时长/季集编号/演职员（`creditItems` ← `_detail!.people`）/已看收藏角标（← `_detail!.watched/favorite`，本地切换 `_detail = _detail!.copyWith(...)`）/续播进度（← `_detail!.resumePositionSeconds`）改读 `_detail`。`metaLineA` 改用中立路径喂 `_detail!.genreLabels/regionLabels`。

**验证**：`flutter analyze`（改动文件零新增）；**`flutter run` 人工验证**电影/单集详情上述展示项与迁移前一致。

**提交**：pathspec 单独提交。

## Task 3：能力角标来源迁移

**改动文件**
- `lib/pages/play_detail_page.dart`：清晰度/音频/色域角标的 `item` 侧来源（`info.item.resolutions/audioTypes/colorRanges`）改读 `_detail!.resolutions/audioTypes/colorRanges`；**保留 `selectedOption`（播放态）选择逻辑不动**。

**验证**：`flutter analyze`；`flutter run` 验证角标在「有/无选中清晰度」两种态下均与迁移前一致。

**提交**：pathspec 单独提交。

## Task 4：看板更新 + 交付实机验证

- 更新 `docs/superpowers/public-media-frontend-status.md`：Phase 5 详情页电影迁移记录、提交 hash、测试命令、待实机验证清单（注意避开 Codex 并行编辑该文件，`MM` 时先等其落定）。
- 交用户 `flutter run` 全量验证电影/单集详情。验证通过后交 Codex 深审。

**提交**：pathspec 单独提交。

## 明确不做

- 不接 Emby；不改 loader/播放路径；不并行 `backend.getItemDetail`。
- 不迁播放入口、轨道、下载、片头片尾、动作面板写操作、FN Connect、进度写回。
- 不迁 `tv_detail_page` / 人物详情（单列后续）；不动图片 headers。
- 不夹带工作区无关/Codex 文件。
