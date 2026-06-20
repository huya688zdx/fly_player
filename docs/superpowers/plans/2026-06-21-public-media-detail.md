# 公共详情模型实施计划（Phase 5）

> 设计：`docs/superpowers/specs/2026-06-21-public-media-detail-design.md`
> 调研：`docs/superpowers/research/2026-06-21-emby-api-shape.md`
> 状态看板：`docs/superpowers/public-media-frontend-status.md`

**目标：** 给详情页建立后端中立的公共详情模型 + 飞牛 mapper + `MediaBackend` 详情接口，再把详情页的**入口壳层和只读展示区域**迁到公共模型；播放入口、轨道、下载、片头片尾、动作写回留页面侧（Phase 6 / 飞牛专属）。不接 Emby。

**协作：** Claude 主实现，Codex 审查收口。规则同 `2026-06-20-public-media-frontend.md`（每个小任务测试通过后立即单独提交；提交前 `git status --short` + `git diff --cached --name-only`，只暂存本任务文件，不夹带 `HANDOFF.md`）。

**顺序原则：** 模型 → mapper 单测 → backend 接口 → 入口壳层 → 电影详情展示 → 剧集详情/季集 → 人物详情。每步可编译、可单独提交、可单独回滚。

---

## Task 1：公共详情模型

**Files:**
- Create: `lib/media_backend/detail/media_detail.dart`（`MediaDetail` + `MediaExternalIds` + `MediaDetailPerson`，含 `displayTitle` getter + `copyWith`）
- Create: `lib/media_backend/detail/media_season_summary.dart`（`MediaSeasonSummary`）
- Create: `lib/media_backend/detail/media_episode_summary.dart`（`MediaEpisodeSummary`）
- Test: `test/media_backend/media_detail_models_test.dart`

**Steps:**
- [ ] 写失败测试：构造 `MediaDetail`，断言 `displayTitle`（secondaryTitle 优先回退）、`primaryImage.url`、`watched`/`favorite`、`copyWith(watched:)` 只改目标字段；构造季/集 summary 断言基础字段。
- [ ] 运行确认 FAIL。
- [ ] 实现纯数据模型（字段见设计文档；复用 `MediaImageRef`；命名后端中立）。
- [ ] 运行确认 PASS：`flutter test test\media_backend\media_detail_models_test.dart`
- [ ] `flutter analyze lib\media_backend\detail` → No issues
- [ ] 提交：`feat: add public media detail models`

## Task 2：飞牛详情 mapper

**Files:**
- Create: `lib/media_backend/feiniu/feiniu_detail_mappers.dart`
  - `mapFeiniuItemDetail(PlayInfoData info, {required Map<int,String> genresMap, required Map<String,String> regionNames, List<PersonCredit> credits})` → `MediaDetail`
  - `mapFeiniuSeason(MediaLibraryItem)` → `MediaSeasonSummary`
  - `mapFeiniuEpisode(MediaLibraryItem)` → `MediaEpisodeSummary`
- Test: `test/media_backend/feiniu_detail_mappers_test.dart`

**Steps:**
- [ ] 写失败测试（先核对 `PlayInfoData`/`PlayItem`/`PersonCredit`/`MediaLibraryItem` 真实构造签名再写 fixture）：
  - 电影详情：title/overview/posters→primaryImage/backdrops→backdropImage/voteAverage→rating/releaseDate/runtime/duration/`genres[28]`→`['动作']`/`productionCountries['US']`→`['美国']`/isWatched→watched/isFavorite→favorite/`ts`→resumePositionSeconds/trimId→externalIds.tmdbId。
  - 剧集详情：seasonNumber/episodeNumber/numberOf(Seasons/Episodes)/local 计数/secondaryTitle(tvTitle)/displayTitle 回退。
  - cast/crew：`PersonCredit` → `MediaDetailPerson`（name/role/avatar/department）。
  - 季/集：season_number/episode_number/stillPath→primaryImage。
  - **只搬展示半**：断言 mapper 不读 mediaGuid/videoGuid/audioGuid/subtitleGuid/canPlay/playConfig（这些不出现在 `MediaDetail`）。
- [ ] 运行确认 FAIL。
- [ ] 实现 mapper：字段搬运 + `genresMap`/`iso3166Map` 翻名；图片 `MediaImageRef(url:..., headers: const {})`（本期空 header）。
- [ ] 运行确认 PASS：`flutter test test\media_backend\feiniu_detail_mappers_test.dart`
- [ ] `flutter analyze lib\media_backend test\media_backend` → No issues
- [ ] 提交：`feat: map Feiniu detail to public media detail`

## Task 3：`MediaBackend` 详情接口 + 飞牛适配器

**Files:**
- Modify: `lib/media_backend/media_backend.dart`（新增 `getItemDetail`/`getItemSeasons`/`getSeasonEpisodes`）
- Modify: `lib/media_backend/feiniu/feiniu_media_backend.dart`（实现：调 `api.getItemDetail`/`getSeasonList`/`getEpisodeList` + `getTagGenresMap`/`getTagIso3166Map`，交 mapper）
- Test: `test/media_backend/feiniu_detail_backend_test.dart`（沿用 capabilities/转发口径；如无 fake seam，以 mapper 单测兜底转发行为）

**注意：** `MediaBackend.getItemDetail` 公共接口名会与 `FeiniuApi.getItemDetail` 同名但返回类型不同（`MediaDetail` vs `Map`），属正常分层；适配层内部仍调 `api.getItemDetail`。

**Steps:**
- [ ] 接口新增三个方法（返回公共模型，不返回 Map）。
- [ ] 适配器实现（薄适配层，不夹带 UI 逻辑）。
- [ ] 运行：`flutter test test\media_backend\ --concurrency=1` → 全 PASS
- [ ] `flutter analyze lib\media_backend test\media_backend` → No issues
- [ ] 提交：`feat: add media detail backend interface`

## Task 4：详情入口壳层迁移（只换数据来源，不动展示）

**Files:**
- Modify: `lib/pages/play_detail_page.dart`（或入口 `play_detail_screen.dart` / `play_detail_entry_page.dart`，取最小改动面）

**范围（极小步）：** 仅把详情**首屏只读字段**的数据来源从裸 `Map`/`PlayItem` 切到 `backend.getItemDetail` 返回的 `MediaDetail`；播放、轨道、下载、动作面板、片头片尾**全部保持现状走 FeiniuApi**。若一次切不动，可先并行持有 `MediaDetail`（喂展示）+ 原 `PlayInfoData`（喂播放），逐字段替换。

**Steps:**
- [ ] 选定最小迁移切口（建议先迁标题/简介/评分/年份/题材/地区这类纯文本只读区）。
- [ ] 用 `context.read<MediaBackendProvider>().backend.getItemDetail` 取 `MediaDetail` 喂展示；播放半保留。
- [ ] `flutter analyze lib\pages\play_detail_page.dart` → No issues
- [ ] `flutter run` 人工验证电影详情展示与迁移前一致（标题/海报/背景/评分/年份/题材/简介/演职员/已看收藏角标/续播/播放入口/下载/动作面板）。
- [ ] 提交：`refactor: load movie detail display via media backend`

## Task 5：剧集详情季/集列表迁移

**Files:**
- Modify: `lib/pages/tv_detail_page.dart`

**范围：** 季列表/集列表从 `List<MediaLibraryItem>` 改读 `MediaSeasonSummary`/`MediaEpisodeSummary`；集渲染不再读裸 Map 的 `season_number`/`episode_number`。播放入口/动作面板保留飞牛。

**Steps:**
- [ ] `_seasonItems` 改为 `List<MediaSeasonSummary>`，集列表改 `MediaEpisodeSummary`；走 `backend.getItemSeasons`/`getSeasonEpisodes`。
- [ ] 集动作面板用页内局部转换回最小 `MediaLibraryItem`（复刻搜索页/分类页 `_cardToActionItem` 模式）。
- [ ] `flutter analyze lib\pages\tv_detail_page.dart` → No issues
- [ ] `flutter run` 人工验证剧集详情季/集列表、季集角标、选集跳转、动作面板与迁移前一致。
- [ ] 提交：`refactor: load tv seasons/episodes via media backend`

## Task 6（可选 / 末位）：人物详情收口

**Files:**
- 评估 `getPersonDetail`/`PersonDetailProfile` → 公共 `MediaPersonDetail` 模型是否本期纳入。
- 若纳入：新增模型 + mapper + backend 接口 + detail/person 页面壳层迁移，按 Task 1–4 同样节奏拆小步。
- 若不纳入：在状态看板标记"人物详情留后续"，给出原因。

## Task 7：更新状态看板

**Files:**
- Modify: `docs/superpowers/public-media-frontend-status.md`

每完成一个 Task：状态、提交 hash、测试命令、下一步负责人写回看板（可与该 Task 同次提交）。

---

## 自查清单

- [ ] 没有引入 Emby API 调用，没有 `if (isEmby)`。
- [ ] `MediaBackend.getItemDetail` 返回 `MediaDetail`，不返回 `Map`。
- [ ] 播放接线字段（mediaGuid/轨道/canPlay/playConfig）没进公共详情模型。
- [ ] 飞牛播放入口、下载、片头片尾、动作写回、FN Connect 保持原状。
- [ ] 详情页视觉表现没有变化（人工验证）。
- [ ] 每个完成任务都有提交 hash 写入状态看板。
- [ ] 没有夹带工作区其它改动（含 `HANDOFF.md`）。
