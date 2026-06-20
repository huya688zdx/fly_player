# 公共详情模型设计（Phase 5）

> 前置调研：`docs/superpowers/research/2026-06-21-emby-api-shape.md`
> 上层设计：`docs/superpowers/specs/2026-06-20-public-media-frontend-design.md`

## 目标

为详情页（电影详情、剧集详情、人物详情）建立后端中立的**公共详情模型**和 `MediaBackend` 详情接口，让飞牛详情页逐步消费该模型，而不再直接吃 `getItemDetail()` 返回的裸 `Map<String,dynamic>`。

本阶段**只做飞牛**：新增公共模型 + 飞牛 mapper + backend 详情接口 + mapper 单测 + 入口壳层和只读展示区域迁移。不接入 Emby API，不迁移播放入口（Phase 6），不动下载、动作面板、片头片尾、FN Connect 等飞牛专属能力。

## 现状审计（真实字段，已核对代码）

详情相关文件仍强依赖飞牛，且把"展示"和"播放接线"混在同一批数据结构里：

- `lib/api/feiniu_api.dart`
  - `getItemDetail(itemGuid)` → `Map<String,dynamic>`，其中 `item` 键解析为 `PlayItem`，整体聚合为 `PlayInfoData`。
  - `getSeasonList(itemGuid)` / `getEpisodeList(seasonGuid)` → `List<MediaLibraryItem>`。
  - `getPersonDetail(personGuid)` → `PersonDetailProfile`。
- `lib/controllers/play_detail_data_loader.dart`：首屏聚合 `PlayDetailInitialData{ info(PlayInfoData), streamTrackData, streamOptions, personCredits(List<PersonCredit>), selectedStreamIndex, selectedSubtitleGuid, selectedAudioGuid, imdbId, trimId }`。
- `lib/pages/play_detail_page.dart`（2678 行）：电影/单集详情。读 `PlayInfoData`/`PlayItem`、`StreamTrackData`、`PersonCredit`，并直接持有 `Map`（`initialItemDetail`，含 `parent_guid`、`item` 等键）。
- `lib/pages/tv_detail_page.dart`（1635 行）：剧集详情。季列表是 `List<MediaLibraryItem>`，集渲染读裸 Map 的 `season_number`/`episode_number`。
- `lib/controllers/item_playback_launcher.dart`（539 行）：播放入口，依赖 `PlayInfoData`/`PlaybackStreamData`/`StreamTrackData` → **Phase 6**。

### `PlayItem` 字段的"展示半 / 播放半"切分

`PlayInfoData` + `PlayItem` 把两类关注点压在一起。Phase 5 公共详情模型只收"展示半"，"播放半"留页面侧到 Phase 6：

| 关注点 | 飞牛字段 | Phase 5 归属 |
| --- | --- | --- |
| 标题 | `title` / `tvTitle` / `parentTitle` / `ancestorName` | 公共模型 |
| 简介 | `overview` | 公共模型 |
| 图片 | `posters` / `backdrops` / `logos` / `stillPath` | 公共模型（`MediaImageRef`） |
| 评分 | `voteAverage` | 公共模型 |
| 日期/时长 | `releaseDate` / `airDate` / `runtime` / `duration` | 公共模型 |
| 季集编号 | `seasonNumber` / `episodeNumber` / `numberOf(Seasons/Episodes)` / `local...` | 公共模型 |
| 题材/地区 | `genres(List<int>)` / `productionCountries` | 公共模型 + 数据字典 |
| 角标 | `resolutions` / `audioTypes` / `colorRanges` | 公共模型 |
| 已看/收藏/续播 | `isWatched` / `isFavorite` / `watchedTs` / `ts` | 公共模型（展示态）；**写操作留页面侧** |
| 外部 ID | `trimId`(tmdb) / `imdbId` | 公共模型（`MediaExternalIds`） |
| **播放接线** | `mediaGuid` / `videoGuid` / `audioGuid` / `subtitleGuid` / `grandGuid` / `parentGuid` | **页面侧（Phase 6）** |
| **播放能力** | `canPlay` / `playError` / `playConfig(skipOpening/skipEnding)` | **页面侧（Phase 6）** |
| **轨道** | `StreamTrackData` / `StreamListOption` | **页面侧（Phase 6）** |

判断依据：Emby 的播放信息（直链、转码、音轨/字幕、默认轨道 index）集中在 `PlaybackInfoResponse.MediaSources`，与飞牛 `mediaGuid`/`StreamTrackData` 不是一一同形。把它混进详情模型会逼公共层提前固化某一后端的播放形状，违反"公共模型小而稳定"。

## 公共详情模型边界（`lib/media_backend/detail/`）

公共模型只表达详情页**展示**真正需要的信息，后端中立、命名不带飞牛/Emby 味道，字段尽量复用已有的 `MediaImageRef` 和 `MediaItemCard` 概念。

```text
class MediaDetail {
  String id;                       // 飞牛 guid / Emby Id
  String type;                     // Movie / TV / Episode / ...（UI 路由用稳定枚举）
  String title;
  String secondaryTitle;           // tvTitle，displayTitle getter 复刻飞牛回退
  String parentTitle;              // 季/剧集所属
  String overview;
  MediaImageRef primaryImage;      // posters
  MediaImageRef backdropImage;     // backdrops
  MediaImageRef logoImage;         // logos
  String rating;                   // voteAverage 原样字符串
  String releaseDate;
  String airDate;
  int runtimeMinutes;              // runtime
  int durationSeconds;             // duration
  int seasonNumber;
  int episodeNumber;
  int numberOfSeasons;
  int numberOfEpisodes;
  int localNumberOfSeasons;
  int localNumberOfEpisodes;
  List<String> genreLabels;        // 已用字典翻好的题材名（见下）
  List<String> regionLabels;       // productionCountries 翻好的地区名
  List<String> resolutions;
  List<String> audioTypes;
  List<String> colorRanges;
  bool watched;                    // isWatched（展示态快照）
  bool favorite;                   // isFavorite（展示态快照）
  int resumePositionSeconds;       // ts（续播位置）
  MediaExternalIds externalIds;
  List<MediaDetailPerson> cast;
  List<MediaDetailPerson> crew;
  // getter：displayTitle（副标题优先回退）
}

class MediaExternalIds {
  String tmdbId;   // trimId
  String imdbId;
}

class MediaDetailPerson {
  String id;       // person guid
  String name;
  String role;     // 角色名 / 职务
  String department;   // cast / crew 区分
  MediaImageRef avatar;
}

class MediaSeasonSummary {
  String id;
  String title;
  int seasonNumber;
  int numberOfEpisodes;
  int localNumberOfEpisodes;
  MediaImageRef primaryImage;
}

class MediaEpisodeSummary {
  String id;
  String title;
  int seasonNumber;
  int episodeNumber;
  String overview;
  String airDate;
  int durationSeconds;
  bool watched;
  int resumePositionSeconds;
  MediaImageRef primaryImage;   // stillPath
}
```

### 题材/地区 label 归属（沿用 Phase 4.5 双轨 label）

飞牛 `genres` 是 `List<int>`、`productionCountries` 是 ISO 码，名字要查字典。两种方案：

- 选项 A（采纳）：mapper 在适配层用 `getTagGenresMap` / `getTagIso3166Map` **翻好**，公共模型直接拿 `genreLabels` / `regionLabels`（已是显示文案）。详情页只读、无交互筛选，不需要 value/label 双轨，翻好更简单。
- 选项 B（不采纳）：模型存 raw id + 下发字典，UI 再翻。详情页没有筛选交互，多一层 localizer 是过度设计。

> 与 Phase 4.5 的区别：分类页筛选项需要 value（提交查询）+ label（显示），故走双轨；详情页题材/地区是纯展示，翻好即可。两者都不在 UI 写 `if(isEmby)`，都把字典留在适配层。

## `MediaBackend` 详情接口

```text
Future<MediaDetail> getItemDetail(String itemId);
Future<List<MediaSeasonSummary>> getItemSeasons(String seriesId);
Future<List<MediaEpisodeSummary>> getSeasonEpisodes(String seasonId);
```

- `FeiniuMediaBackend` 作为薄适配层：`getItemDetail` 调 `api.getItemDetail` 拿 `PlayInfoData`，mapper 只搬"展示半"到 `MediaDetail`；题材/地区在适配层用 `genresMap`/`iso3166Map` 翻名；cast/crew 由 `PersonCredit` 列表映射。
- `getItemSeasons` / `getSeasonEpisodes` 调 `api.getSeasonList` / `api.getEpisodeList`（返回 `List<MediaLibraryItem>`），mapper 映射到季/集 summary。
- 人物详情页（`getPersonDetail` → `PersonDetailProfile`）较独立，可在 Phase 5 末或后续单独收口，不阻塞电影/剧集详情。

## 哪些飞牛能力**暂留页面侧**（Phase 5 不迁移）

以下能力本期保持现状，详情页继续直接调 `FeiniuApi` / 现有控制器，**不进公共模型**：

1. **播放入口**：`item_playback_launcher.dart`、`PlayInfoData` 的 `mediaGuid`/`videoGuid`/`audioGuid`/`subtitleGuid`、`StreamTrackData`、`canPlay`/`playError` → Phase 6。
2. **音轨/字幕/清晰度轨道选择**：`getStreamTrackData` / `StreamListOption` / `play_detail_track_selector` → Phase 6。
3. **片头片尾配置**：`PlayConfig.skipOpening/skipEnding`（capabilities `supportsIntroOutroConfig`）→ 留页面侧。
4. **下载**：`play_detail_download_sheet_controller`、`getDownloadResolutionOptions`、`createDownloadTask` 等 → 留页面侧。
5. **动作面板的写操作**：收藏/已看切换（`MediaItemActionSheetController`、`play_detail_item_actions`）。`MediaDetail.watched/favorite` 只携带**展示态快照**供首屏渲染，**写回仍走飞牛 API**；本地切换后用 `copyWith` 更新快照（复刻搜索页/分类页模式）。
6. **FN Connect / 远程访问**：不动。
7. **续播 `ts` 写回 / 播放进度 check-in**：只读 `resumePositionSeconds` 展示，写回属播放统计/播放器 → 不动。

> 迁移策略：先迁**入口壳层 + 只读展示区域**（标题/简介/海报/评分/年份/题材/演职员/季集列表渲染），把上述 1–7 当作详情页本地的飞牛能力保留。等详情模型稳定、Emby mapper 落地后，再逐项评估能否上移。

## mapper 边界（`lib/media_backend/feiniu/`）

- 所有飞牛→公共详情的字段搬运集中在 `feiniu_media_mappers.dart`（或新建 `feiniu_detail_mappers.dart`），不扩散到页面。
- mapper 只做字段映射 + 字典翻名，不调网络、不持状态。
- 图片：本期沿用旧 NAS 鉴权路径，`MediaImageRef.headers` 可暂留空（与 Phase 3/4 一致）；待页面直接消费公共图片引用且需要鉴权 header 时，在适配层补齐（Codex 风险 2）。
- 单测锁住：电影详情、剧集详情、季列表、集列表、图片 URL、评分、年份、题材/地区翻名、已看/收藏/续播、外部 ID、cast/crew。

## 明确不做

- 不接 Emby API；不写 `EmbyApi`、`EmbyMediaBackend`。
- 不在任何 UI 文件写 `if (isEmby)`。
- 不让 `MediaBackend.getItemDetail` 返回 `Map<String,dynamic>`（会把飞牛裸 Map 问题复制到公共层）。
- 不把播放接线字段（`mediaGuid`/轨道/`canPlay`/`playConfig`）放进公共详情模型。
- 不迁移播放入口、轨道选择、下载、片头片尾、FN Connect、播放进度写回。
- 不动 Phase 1–4.5 已提交的 `lib/media_backend` 逻辑（除非明确 bug，先说明原因）。
- 不夹带工作区其它改动（含未跟踪 `HANDOFF.md`）。

## 验收口径

- 每个 Task：mapper 单测 PASS + `flutter analyze`（改动文件 No issues）+ 单独提交。
- 页面迁移 Task：`flutter run` 登录飞牛人工验证——电影/剧集/人物详情的标题、海报/背景、评分、年份、时长、题材/地区、简介、演职员、季/集列表、已看/收藏角标、续播位置、播放入口、下载、动作面板均与迁移前一致。
