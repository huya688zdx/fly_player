# Emby 官方 API 形状调研与 Phase 5 评估

## 结论

本次只做官方 API 调研和 Phase 5 评估，不接入 Emby，不修改业务代码。

Emby 的官方 REST API 形状可以支撑当前公共媒体前端继续推进，但详情页不宜直接在现有 `play_detail_page.dart` / `tv_detail_page.dart` 上替换数据源。建议先补一层公共详情模型和 mapper，再让飞牛详情页逐步消费该模型。播放入口应继续留到 Phase 6，因为 Emby 的播放信息、直链、转码、音轨和字幕都集中在 `PlaybackInfoResponse.MediaSources`，与飞牛现有 `PlayInfoData` / `StreamTrackData` 不是一一同形。

## 官方资料入口

- REST API 基础路径：`http[s]://hostname:port/emby/{apipath}`。认证方式分用户认证和 API Key；普通客户端应使用用户登录拿 `AccessToken`，后续请求带 `X-Emby-Token`。
  - 来源：https://dev.emby.media/doc/restapi/index.html
  - 用户认证：https://dev.emby.media/doc/restapi/User-Authentication.html
  - API Key：https://dev.emby.media/doc/restapi/API-Key-Authentication.html
- 官方建议用 Dashboard 打开的交互式 API Browser 对真实服务器试请求；静态文档适合先看 endpoint/参数/返回 DTO。
  - 来源：https://dev.emby.media/doc/restapi/index.html

## 关键 Endpoint

| 前端能力 | Emby endpoint | 官方返回/说明 | 对本项目的含义 |
| --- | --- | --- | --- |
| 列表、搜索、分类查询 | `GET /Users/{UserId}/Items` | 返回 `QueryResult<BaseItemDto>`；支持 `StartIndex`、`Limit`、`SearchTerm`、`ParentId`、`Fields`、`IncludeItemTypes`、`SortBy`、`SortOrder`、`Genres`、`Years`、`IsPlayed`、`EnableImages`、`EnableUserData` 等 | 可映射到现有 `MediaBackend.searchItems` / `queryCatalogItems`，但 filter schema 需按 Emby 能力重新设计，不能沿用飞牛 tag 体系 |
| 最近媒体 | `GET /Users/{UserId}/Items/Latest` | 返回 `BaseItemDto[]`；支持 `Limit`、`ParentId`、`Fields`、`IncludeItemTypes`、`MediaTypes`、`IsPlayed`、`EnableImages`、`EnableUserData` | 可作为首页“最近添加”或媒体库预览来源，和飞牛首页概要不是同形 |
| 详情 | `GET /Users/{UserId}/Items/{Id}` | 返回单个 `BaseItemDto`；字段包含 `Name`、`Overview`、`Genres`、`CommunityRating`、`RunTimeTicks`、`ProductionYear`、`PremiereDate`、`UserData`、`ImageTags`、`BackdropImageTags`、`People`、`Studios`、`MediaStreams` 等 | 应先定义公共 `MediaDetail`，不要让 UI 继续吃裸 `Map<String,dynamic>` |
| 剧集季/集 | `GET /Shows/{Id}/Seasons`、`GET /Shows/{Id}/Episodes` | TvShowsService 提供剧集季列表和集列表 | 可映射到 `MediaSeasonSummary` / `MediaEpisodeSummary`；当前 `tv_detail_page.dart` 还依赖 `MediaLibraryItem` 季列表，需要单独收口 |
| 图片 | `GET /Items/{Id}/Images`、`GET /Items/{Id}/Images/{Type}`，另有 user/person/genre/studio 等图片接口 | 图片 API 独立，列表 DTO 中也有 `ImageTags` / `BackdropImageTags` | `MediaImageRef` 必须能表达 Emby 图片 URL 和鉴权 header；后续页面直接消费公共图片前必须补齐 |
| 播放信息 | `GET /Items/{Id}/PlaybackInfo?UserId=...` | 返回 `PlaybackInfoResponse`，包含 `MediaSources`、`PlaySessionId`、`MediaStreams`、`DirectStreamUrl`、`TranscodingUrl`、`RequiredHttpHeaders`、默认音轨/字幕 index 等 | Phase 6 再迁；先只调研字段，不改播放器深层逻辑 |
| HLS | `/Videos/{Id}/master.m3u8` | 需要 `MediaSourceId`、`DeviceId`，可带音视频 codec/bitrate/字幕参数 | 和现有 mpv 直放/代理链路相关，不能混进 Phase 5 |
| 播放进度/已看 | `POST /Sessions/Playing/Stopped`、`POST /Users/{UserId}/PlayedItems/{Id}`、`DELETE /Users/{UserId}/PlayedItems/{Id}` | 官方播放 check-in 和手动已看/未看接口 | 动作面板和播放统计属于后续能力抽象，不应先塞进详情模型 |

## BaseItemDto 到现有公共模型的初步映射

| 公共字段 | Emby 字段候选 | 备注 |
| --- | --- | --- |
| `MediaItemCard.id` | `Id` | 用 Emby item id，不用 `Guid` 当主键 |
| `title` | `Name` | `OriginalTitle` 可作为详情补充，不放卡片 |
| `type` | `Type` 或 `MediaType` | 官方建议尽量看属性而不是过度依赖 `Type`；UI 路由仍需要稳定类型枚举 |
| `primaryImage` | `/Items/{Id}/Images/Primary` 或 `PrimaryImageItemId` + image tag | 应由 Emby mapper 生成完整 URL；headers 带 `X-Emby-Token` 或 token query |
| `backdropImage` / `posters` | `BackdropImageTags`、`ImageTags` | 多图需要按 tag/index 拼 URL |
| `durationSeconds` | `RunTimeTicks / 10_000_000` | Emby 使用 ticks |
| `watched` | `UserData.Played` | 需请求时启用 `EnableUserData` |
| `resumePositionSeconds`（建议新增） | `UserData.PlaybackPositionTicks / 10_000_000` | 当前 `MediaItemCard` 没有续播字段；详情/首页继续观看需要单独设计 |
| `rating` | `CommunityRating` 或 `CriticRating` | 建议 mapper 格式化为展示字符串 |
| `releaseDate` / 年份 | `PremiereDate`、`ProductionYear`、`EndDate` | 电影/剧集显示规则需统一 |
| 季/集编号 | `ParentIndexNumber`、`IndexNumber`、`SeasonName`、`SeriesName` | 剧集详情和播放入口都要用 |
| 清晰度/音频/字幕角标 | `MediaStreams`、`VideoCodec`、`AudioCodec`、`Width`、`Height` | 适配层可以提炼为后端中立展示标签 |

## Phase 5 当前代码风险

本次扫描确认详情相关文件仍强依赖飞牛：

- `lib/pages/play_detail_page.dart`：多处 `FeiniuApi`，并直接持有 `PlayInfoData`、`StreamTrackData`、`Map<String,dynamic>`。播放、音轨/字幕、下载预取和详情渲染混在同一页面里。
- `lib/pages/tv_detail_page.dart`：多处 `FeiniuApi`，季列表仍是 `List<MediaLibraryItem>`，基础详情是裸 `Map<String,dynamic>`。
- `lib/controllers/item_playback_launcher.dart`：播放入口依赖 `PlayInfoData`、`PlaybackStreamData`、`StreamTrackData`、季集 `Map`，这是 Phase 6 范围。
- `lib/screens/play_detail_screen.dart` / `lib/pages/play_detail_entry_page.dart`：入口仍通过 `Map<String,dynamic>` 判断详情页模式。

因此 Phase 5 如果直接“页面改读 backend”，会把 Emby 字段、飞牛字段和播放器字段一起压进一个大 PR，风险很高。

## 推荐路线

### 推荐方案：先详情模型，后页面迁移

1. 新增公共详情模型，但不接 Emby：
   - `MediaDetail`
   - `MediaDetailPerson`
   - `MediaDetailExternalIds`
   - `MediaSeasonSummary`
   - `MediaEpisodeSummary`
2. 在 `FeiniuMediaBackend` 增加详情读取接口，内部仍调用 `FeiniuApi.getItemDetail` / `getSeasonList` / `getEpisodeList`，mapper 只做飞牛到公共模型转换。
3. 给飞牛 mapper 补单测，锁住电影详情、剧集详情、季列表、集列表、图片、评分、年份、已观看/续播等字段。
4. 先迁入口壳层和只读展示区域，保留播放入口、下载、动作面板等飞牛专属功能。
5. 等详情模型稳定后，再写 Emby mapper；如果字段缺口明确，再小步扩展公共模型。

优点：不让 UI 出现 `if (isEmby)`，也不让公共模型被某个后端的原始 DTO 污染。缺点是 Phase 5 会多一个模型/mapper 阶段，看起来比直接改页面慢，但更可验证。

### 不推荐方案：先写 EmbyApi 再接页面

这样会同时引入网络客户端、认证、DTO、mapper、UI 迁移和播放边界，任何失败都难以定位。当前项目目标是公共前端抽象，不是马上上线 Emby。

### 不推荐方案：让 `MediaBackend.getItemDetail` 返回 `Map<String,dynamic>`

这会把现有飞牛裸 Map 问题复制到公共层。后续 Emby 也会被迫伪造飞牛 key，如 `season_number`、`backdrops`、`poster_list`，违背公共模型边界。

## 需要向真实 Emby 服务器确认的样本

如果用户能提供测试服务器，建议只用官方 API Browser 或只读 curl 抓脱敏 JSON，不提交 token/server/user：

- Movie：`/Users/{UserId}/Items/{Id}`，带 `Fields=Genres,People,Studios,ProviderIds,MediaStreams,Overview,PrimaryImageAspectRatio`
- Series：`/Users/{UserId}/Items/{Id}`
- Season：`/Shows/{SeriesId}/Seasons?UserId={UserId}&Fields=...`
- Episode：`/Shows/{SeriesId}/Episodes?UserId={UserId}&SeasonId={SeasonId}&Fields=...`
- Search：`/Users/{UserId}/Items?SearchTerm=...&IncludeItemTypes=Movie,Series,Episode&EnableImages=true&EnableUserData=true`
- PlaybackInfo：`/Items/{Id}/PlaybackInfo?UserId={UserId}`

## 下一步建议

1. 先写 Phase 5 设计文档：定义公共详情模型边界、飞牛 mapper 边界、页面保留飞牛能力的范围。
2. 再写 Phase 5 实施计划，按“模型 -> mapper 单测 -> backend 接口 -> 入口壳层 -> 电影详情展示 -> 剧集详情展示”的顺序拆任务。
3. 暂不新增 `EmbyApi` 代码。真实 Emby DTO 可以先以脱敏 JSON fixture 进入 mapper 测试设计，但需要用户确认测试数据来源。
4. Phase 6 单独设计播放入口：`PlaybackInfoResponse.MediaSources`、音轨/字幕、HLS/直链、播放进度 check-in、mpv 代理兼容要一起看。

## 本次查证来源

- REST API Documentation：https://dev.emby.media/doc/restapi/index.html
- User Authentication：https://dev.emby.media/doc/restapi/User-Authentication.html
- API-Key Authentication：https://dev.emby.media/doc/restapi/API-Key-Authentication.html
- Item Types：https://dev.emby.media/doc/restapi/Item-Types.html
- Items query：https://dev.emby.media/reference/RestAPI/ItemsService/getUsersByUseridItems.html
- Latest items：https://dev.emby.media/reference/RestAPI/UserLibraryService/getUsersByUseridItemsLatest.html
- Item detail：https://dev.emby.media/reference/RestAPI/UserLibraryService/getUsersByUseridItemsById.html
- ImageService：https://dev.emby.media/reference/RestAPI/ImageService.html
- TvShowsService：https://dev.emby.media/reference/RestAPI/TvShowsService.html
- PlaybackInfo：https://dev.emby.media/reference/RestAPI/MediaInfoService/getItemsByIdPlaybackinfo.html
- HLS：https://dev.emby.media/doc/restapi/Http-Live-Streaming.html
- Playback check-ins：https://dev.emby.media/doc/restapi/Playback-Check-ins.html
