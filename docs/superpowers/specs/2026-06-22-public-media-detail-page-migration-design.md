# Phase 5 续：详情页迁移设计（电影详情先行）

日期：2026-06-22
前序：Phase 5 详情后端骨架 `c2fffa6`+`c60292c`/`87c3377`/`dd8630d`（+Codex 修复 `63a91f7`/`8452fd7`）；Task 4/5 页面迁移当初**暂缓**（status doc「2026-06-21 Phase 5 Task 4/5 切口调查结论」）。
范围决策：用户 2026-06-22 选「先做详情页」（作为接 Emby 的前置——详情页必须改吃 `MediaBackend` 而非 `FeiniuApi`）。

## 1. 背景：当初为什么暂缓

status doc 记录的暂缓两大主因：
1. **重复请求**：`play_detail_page` 已加载完整 `PlayInfoData` + `_genresMapZhCn`；若再并行 `backend.getItemDetail()` 取一份 `MediaDetail`，是重复网络；若让 loader 产出 `MediaDetail` 则要改控制器与播放路径。
2. **展示/播放耦合**：`play_detail_page` 的 build 闭包（约 2110~2273）把展示字段与播放态交错算——`detailTitle`、`metaLineA`、能力角标（在 `selectedOption` 播放态与 `item.resolutions` 间二选一）、`creditItems`。
3. **tv_detail 下游契约**：季卡 `onTap` 把 `initialSeasonItems: _seasonItems`（`List<MediaLibraryItem>`）透传给下游 `tv_season_detail_page`，换成 `MediaSeasonSummary` 会破坏下游契约、涟漪到另一文件；且 `MediaSeasonSummary` 缺季卡消费字段。

## 2. 关键发现：主因 1 已不成立（可进程内零网络构造 MediaDetail）

已核对真实代码：

- `PlayDetailDataLoader.load()`（`play_detail_data_loader.dart:127`）一次性取 `getPlayInfo`(→`PlayInfoData`) + `getStreamTrackData` + `getItemDetail`(→Map，取 imdb/trim) + `getPersonList`(→`List<PersonCredit>`)——**与 `FeiniuMediaBackend.getItemDetail` 同源**。
- `play_detail_page` 已持 `_personCredits`(:128)、`_genresMapZhCn`(:146)、`_locateMapZhCn`(:147)、imdb（loader 出口）——**正是 `mapFeiniuItemDetail(info, {genresMap, regionNames, credits, imdbId})` 的全部入参**（`feiniu_detail_mappers.dart:20`，纯函数、不触网）。

> 结论：`MediaDetail` 可在**页面侧进程内**用现成 mapper 构造，**零额外网络、零重复请求**。当初「并行取会重复请求」「让 loader 产出要改播放路径」的暂缓理由消解——既不并行取、也不改 loader/播放路径，只在页面已有数据上加一次纯映射。

## 3. 范围决策：电影详情先行，TV / 人物详情单列后续

- **本期：`play_detail_page`（电影/单集详情）展示区迁移**——切口干净、零重复请求、`MediaDetail` 已覆盖其展示字段。
- **暂不迁：`tv_detail_page`**。两道坎需各自前置：
  1. `MediaSeasonSummary`（`mapFeiniuSeason` 当前只产 id/title/seasonNumber/numberOfEpisodes/localNumberOfEpisodes/primaryImage）**缺季卡消费字段**（`voteAverage`/`resolutions`/`watched`/`releaseDate`/集数角标）——须先校准模型（Codex 收口复审已提示，status doc）。
  2. 季 `onTap` 下游契约（`List<MediaLibraryItem>` → `tv_season_detail_page`）——迁移时只换**季卡渲染**读 `MediaSeasonSummary`，**保留下游 `MediaLibraryItem` 透传**不动，避免涟漪。
  → 单列「TV 详情迁移设计」，本设计不含。
- **暂不迁：人物详情**（`getPersonDetail`→`PersonDetailProfile`，较独立，后续单收口）。

## 4. 设计：play_detail_page 展示区迁移

### 4.1 切口：页面侧进程内构造 `_detail`

- 页面新增 `MediaDetail? _detail;`。在首屏 `load()` 完成、`_personCredits` + `_genresMapZhCn` + `_locateMapZhCn` 均就绪后，调
  `_detail = mapFeiniuItemDetail(info, genresMap: _genresMapZhCn, regionNames: _locateMapZhCn, credits: _personCredits, imdbId: <loader 的 imdbId>)`。
  状态刷新（`refreshAfterItemStateChange`）后同样重建 `_detail`。
- **loader 不改**（保持 `PlayInfoData` 出口，播放路径零触碰）；**字典加载不改**（页面仍各自 `getTagGenresMap`/`getTagIso3166Map`）。`_detail` 只是在已有数据上加一层纯映射快照。

### 4.2 展示字段迁移（build 闭包从 `info.item` 改读 `_detail`）

| 展示项 | 现状源 | 迁移后源 |
| --- | --- | --- |
| 标题 | `info.item.title`/`displayTitle` | `_detail!.displayTitle` |
| 简介 | `info.item.overview` | `_detail!.overview` |
| 海报/背景/logo | `info.item.posters`/`backdrops`/`logos` | `_detail!.primaryImage/backdropImage/logoImage`（本期 headers 仍空、走旧 NAS 鉴权路径，与 Phase 3/4 一致） |
| 评分/年份/时长 | `info.item.voteAverage`/`releaseDate`/`runtime`/`duration` | `_detail!.rating`/`releaseDate`/`runtimeMinutes`/`durationSeconds` |
| 季集编号 | `info.item.seasonNumber`/… | `_detail!.seasonNumber`/… |
| 题材/地区行 | `PlayDetailFormatters.metaLineA(item, genreMap:_genresMapZhCn, locateMap:_locateMapZhCn)` | 新增 `metaLineA` 中立入参重载，吃 `_detail!.genreLabels`/`regionLabels`（mapper 已翻好）+ 年份，**把字典查询从展示层移走** |
| 演职员 | `_personCredits` | `_detail!.people` |
| 已看/收藏角标 | `info.item.isWatched`/`isFavorite` | `_detail!.watched`/`favorite`（展示态快照；本地切换后 `_detail = _detail!.copyWith(...)`，写回仍走飞牛 API） |
| 续播进度 | `info.ts>0?ts:watchedTs` | `_detail!.resumePositionSeconds`（mapper 已复刻同语义） |
| 能力角标（清晰度/音频/色域） | `selectedOption`(播放态) ?? `info.item.resolutions`… | **选择逻辑保留**；仅把 `item` 侧来源换 `_detail!.resolutions/audioTypes/colorRanges`（展示半）。`selectedOption` 侧不动（播放态，Phase 6） |

### 4.3 保留不动（页面侧飞牛能力，本期/Phase 6 不迁）

播放入口 launcher、`selectedOption`/`_streamOptions`/轨道选择、下载、片头片尾、动作面板**写操作**、FN Connect、进度写回——全部保持现状直接调飞牛。`_detail.watched/favorite` 只是展示态快照，写回不经它。

## 5. 任务拆分（每步可编译、单独提交、`flutter run` 人工验证）

- **Task 1：页面侧构造 `_detail`（无 UI 改动）**。新增字段 + 首屏/刷新后构造 + 一条断言型 debug（或单测覆盖「页面已有数据 → mapFeiniuItemDetail 产出非空 detail，关键展示字段与 info.item 一致」）。build 闭包仍读旧源 → **零行为变化**。
- **Task 2：纯展示字段迁移**（标题/简介/海报背景logo/评分年份时长/季集编号/演职员/已看收藏/续播）。这些不碰播放态。`PlayDetailFormatters.metaLineA` 加中立入参路径（吃 genreLabels/regionLabels）。`flutter run` 验证电影/单集详情展示与迁移前一致。
- **Task 3：能力角标来源迁移**（`item` 侧 → `_detail`，保留 `selectedOption` 选择逻辑）。`flutter run` 验证清晰度/音频/色域角标一致。
- **Task 4：看板更新 + 交付实机验证**。

> tv_detail / 人物详情 / 图片 headers 不在本计划，单列后续。

## 5.1 实现中发现的等价坑（2026-06-22，实测记录）

实现 Task 1/2 时枚举 build 闭包，发现详情页的**显示逻辑**多处带飞牛口味，直接换 `_detail`
会引入细微行为差异。据此把展示字段分三类：

**A. 零等价坑、已迁（Task 2 `1fc6fb7`）**
- `detailTitle`：迁 `_detail`，但**内联复刻** `tvTitle 优先` 逻辑，绕开 `MediaDetail.displayTitle`
  （后者「皆空回退 `'Unknown'`」与旧 `''` 不同）。
- `overview`、`logoImage.url`：逐字段等价直迁。

**B. 带等价坑 / 缺模型字段 → 需 UI 层 presenter 或留飞牛路径**
- **演职员**：`creditItems` 用 `PersonCredit.displayName`（皆空回退「未知」，mapper 的 `name`
  回退空串）+ `displaySubTitle`（飞牛专属 job→中文 映射：director→导演 等）。这些是**显示逻辑**，
  不应进中立模型。Emby-ready 做法：在 `lib/ui/` 加 `CreditPersonPresenter`（类比 Phase 4.5
  `CatalogFilterLocalizer`），在 `MediaDetailPerson.name/role/department` 上**复刻**displayName/
  displaySubTitle 语义；creditItems 经 presenter 读 `_detail.people`。中等任务，Emby 复用同一 presenter。
- **题材/地区行 `metaLineA`**：`genreNamesFromIds` **丢弃字典查不到的题材**，mapper 的
  `genreLabels` 把未知 id 保留成数字串——直接换会在缺字典时显示数字。且 `metaLineB` 用
  `ancestorName`，`MediaDetail` 无此字段。→ 留飞牛路径；Emby 分支自建 metaLine（Emby 直接返回
  题材名，无未知 id 问题），不阻塞。
- **海报/背景主题路径** `_dynamicThemePathForPlayItem`：用 `stillPath`（`MediaDetail` 无此字段）
  且签名吃 `PlayItem`。→ 留飞牛路径（若要迁需给模型补 stillPath，宜与 Emby 一起定）。

**C. 播放半 / 交互态 → 不迁（本设计范围外）**
- 能力角标（清晰度/音频/色域）：与 `selectedOption`（播放态）二选一，属 Task 3 / 播放半。
- 已看/收藏按钮、进度条、`playError`：交互态 / 播放逻辑。

> 结论：MediaDetail **数据**已可零网络供页面消费（A 类已证），但页面的**显示逻辑**（displayName/
> displaySubTitle/displayTitle/metaLine genre 处理）是飞牛口味，干净迁移需 UI 层 presenter（B 类）
> 或与 Emby 共同定字段（stillPath/ancestorName）。这与「详情页深层显示宜连同 Emby 一起做」的
> 原判一致——A 类清掉证明了切口，B/C 类按需推进或留待 Emby。

## 6. 测试与验证

- mapper 已有单测（Phase 5）覆盖字段映射；本期页面侧构造可加一条「页面输入 → detail 展示字段」纯断言（不触网）。
- 每个 Task：`flutter analyze`（改动文件零新增，对比基线 17 条）+ 单独提交。
- 页面 Task 必须 `flutter run` 登录飞牛人工验证：电影/单集详情标题、海报/背景、评分、年份、时长、题材/地区、简介、演职员、已看/收藏角标、续播位置、清晰度/音频/色域角标，均与迁移前一致；播放入口、下载、动作面板、片头片尾不回归。

## 7. 明确不做

- 不接 Emby；不写 `EmbyApi`/`EmbyMediaBackend`；UI 不写 `if (isEmby)`。
- 不改 loader 的 `PlayInfoData` 出口、不改播放路径、不并行 `backend.getItemDetail`（避免重复请求）。
- 不迁播放入口、轨道选择、下载、片头片尾、动作面板写操作、FN Connect、进度写回。
- 不迁 `tv_detail_page`（待先校准 `MediaSeasonSummary` + 处理下游契约，单列设计）、不迁人物详情。
- 不动图片 headers（本期沿用旧 NAS 鉴权路径）。
- 不夹带 `HANDOFF.md`、`MpvPlaybackController.kt` 或 Codex 并行的 login-backend 改动。
