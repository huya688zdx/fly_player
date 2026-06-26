# Emby 前端适配公共抽象调研

## 背景

当前项目已经建立了 `lib/media_backend/` 公共后端层，Emby 已接入首页、搜索、分类列表、详情展示、播放解析、进度回写、收藏/已看、人物作品、选集和部分原生壳反向通道。但代码里仍存在两类问题：

- 一些页面已经有公共模型，却仍把公共模型转回飞牛旧模型再复用旧控制器。
- 一些功能飞牛和 Emby 语义相同，却在页面层通过 `MediaBackendKind.feiniu` 分支维护两套流程。

如果后续加入 Jellyfin、本地媒体库或其他播放后端，这些分支会继续扩散。建议下一阶段优先把“用户可见行为相同、后端实现不同”的能力收敛到公共接口或公共控制器，把飞牛私有能力保留在 capability 扩展点中。

## 已有公共层现状

| 范围 | 现有抽象 | 当前状态 |
| --- | --- | --- |
| 后端选择 | `MediaBackendProvider` / `BackendSessionProvider` | 已能按当前会话返回飞牛或 Emby backend。 |
| 首页和列表 | `MediaCatalog` / `MediaItemCard` / `MediaCatalogFilterSchema` / `MediaCatalogQuery` | 分类、首页、搜索、分类页已部分走公共模型。 |
| 详情展示 | `MediaDetail` / `MediaEpisodeSummary` / `MediaSeasonSummary` | Emby 详情已走中立模型，飞牛详情页仍大多消费原始 `PlayInfoData` / `Map`。 |
| 播放解析 | `MediaPlaybackRequest` / `MediaPlaybackBundle` / `MediaPlaybackResolution` | 飞牛和 Emby 都通过 `getPlayback` 解析，再由各自 bridge 装配 `MpvMediaSource`。 |
| 播放回写 | `reportPlaybackStart` / `reportPlaybackProgress` / `reportPlaybackStopped` | Emby 已实现，飞牛仍走既有原生重入和离线队列。 |
| 条目状态 | `setItemFavorite` / `setItemWatched` + capabilities | 电影详情页部分已接入，剧详情、季详情、合集、人物、长按菜单仍有飞牛直连路径。 |
| 原生壳回调 | `NativePlaybackReentry` | 已集中绑定飞牛/Emby 回调，但入口层仍有重复的解析和选集兜底逻辑。 |

## 补充调查：原生播放入口一致性

按当前规划，Flutter 播放器页会废弃，因此这里不再把 `MpvPlayerPage` 内部选集、下一集、mixin 拆分作为抽象目标。后续重点应放在原生壳入口、原生壳反向通道和传给原生端的 episode payload。

### 入口链路现状

| 入口 | 当前链路 | 主要问题 |
| --- | --- | --- |
| 单条目中立详情 | `play_detail_page.dart` 调 `ItemPlaybackLauncher.open` | launcher 内部自己绑定 `NativePlaybackReentry`，并在 Emby 分支自动补整季 episodes。 |
| 飞牛旧详情 | `play_detail_page.dart` 的 `_launchPlayer` 页面内绑定 reentry 后直接 `NativePlayerBridge.launch` | 绕过 `ItemPlaybackLauncher.open` 和 `maybeLaunch`，与中立详情不是同一套起播编排。 |
| 剧详情 | `tv_detail_page.dart` 页面内先绑定 `NativePlaybackReentry`，再调 `TvSeasonPlaybackLauncher.open` | 绑定职责在页面层，launcher 不负责 reentry 生命周期。 |
| 飞牛季页面 | `tv_season_detail_page.dart` 先 `_bindNativePlayerReentry()`，再调 `TvSeasonPlaybackLauncher.open`，并传 `_nativeEpisodesPayload()` | 页面手拼 episodes，字段比 `NativeReentrySupport` 的 episode map 少。 |
| Emby 季页面 | `tv_season_detail_page.dart` 先 `_bindEmbyNativePlayerReentry()`，再调 `TvSeasonPlaybackLauncher.open`，并传 `_neutralNativeEpisodesPayload()` | 页面手拼 episodes，字段比 `EmbyNativePickerSupport.nativeEpisodePayload()` 少。 |
| 下载列表 | `download_list_screen.dart` 页面内绑定 reentry，再调 `NativePlayerBridge.maybeLaunch` | 属于飞牛下载入口，但也在页面层重复承担原生起播编排。 |

这解释了“从季页面进入”和“从详细界面进入”感觉不统一：不是播放内核不同，而是入口编排、reentry 绑定位置、episodes payload 来源都不一致。

### 已有公共抽象

- `MediaBackend.getPlayback` / `MediaPlaybackRequest` 已经能表达飞牛和 Emby 的播放解析请求。
- `FeiniuPlaybackSourceBridge` / `EmbyPlaybackSourceBridge` 已经按各自 playback context 装配 `MpvMediaSource`。
- `NativePlayerBridge.bindReentry` 是统一的原生反向通道，处理 `resolvePlayback`、`loadEpisodePickerData`、`loadSeasonEpisodes`、`recordProgress`、`resolveSubtitleFile` 等回调。
- `NativePlaybackReentry.bind` 已经按 backend 分发飞牛和 Emby 的原生回调实现；Emby 没有 `reloadServerSession` 是合理差异，因为 Emby 直链播放没有飞牛转码会话重载协议。
- `NativePlayerBridge.maybeLaunch` 是已有的原生启动门面，能统一处理原生渲染器开关和弹幕预取。

### 仍未统一的层

- reentry bind 所有权不统一：`ItemPlaybackLauncher.open` 自己 bind，`TvSeasonPlaybackLauncher.open` 依赖页面先 bind，飞牛旧详情和下载列表也在页面层 bind。
- episodes payload 构造不统一：季页面手拼的 payload 字段少于 `NativeReentrySupport` / `EmbyNativePickerSupport` 的标准 episode map，容易导致原生选集面板、下一集、时长、已看、海报鉴权信息不一致。
- resolver 能力不统一：`TvSeasonPlaybackLauncher.resolveForNative` 支持 `audioTrackIndex`、`subtitleTrackIndex`、`preferredQualityResolution`，但 `ItemPlaybackLauncher` 的 Emby 原生重解析没有完整传递这些参数。
- source bridge 分发重复：`ItemPlaybackLauncher` 和 `TvSeasonPlaybackLauncher` 都做 `getPlayback` 后按 `FeiniuPlaybackContext` / `EmbyPlaybackContext` 选择 bridge。
- 原生起播门面不统一：部分入口用 `NativePlayerBridge.maybeLaunch`，飞牛旧详情仍直接调用 `NativePlayerBridge.launch`。

### 建议

- 抽 `NativePlaybackCoordinator` 或 `MediaNativePlaybackLauncher`：页面只提交 `PlaybackEntryContext`，由 coordinator 负责 bind reentry、解析播放源、装配 episodes、调用 `maybeLaunch`。
- 抽 `NativeEpisodePayloadBuilder`：飞牛和 Emby 分别复用 `NativeReentrySupport` / `EmbyNativePickerSupport` 的完整 episode map，不允许页面手拼精简字段。
- 抽统一 `MediaPlaybackResolver`：集中 `getPlayback` + source bridge 分发，`ItemPlaybackLauncher` / `TvSeasonPlaybackLauncher` / 原生 `resolvePlayback` 都复用它。
- 把轨道序号、字幕序号、首选分辨率等跨集继承参数纳入统一 resolver request，避免详情页入口和季页面入口能力不同。
- 收敛旧飞牛详情和下载列表的直接 `launch` / 页面 bind 路径，至少改为同一个 coordinator 的可选入口。

## 优先抽象项

### 1. 条目操作动作层

现状：

- `MediaBackend` 已有 `setItemFavorite` / `setItemWatched`。
- `play_detail_page.dart` 的中立详情已使用 backend 写回。
- `tv_detail_page.dart`、`tv_season_detail_page.dart`、`media_collection_detail_page.dart`、`person_detail_screen.dart`、`media_item_action_sheet_controller.dart` 仍直接构造 `FeiniuApi` 或 `PlayDetailItemActions`。

建议：

- 新增 `MediaItemStateActionController`，输入 `MediaBackend`、`itemId`、当前状态、l10n，输出统一的状态和提示文案。
- `PlayDetailItemActions` 可以降级为飞牛实现细节，或被上述 controller 替代。
- 长按菜单改为消费公共 action target，而不是 `MediaLibraryItem`。

收益：

- 收藏、已看、取消已看、长按菜单可以同时支持 Emby。
- 第三个后端只需要实现 backend 状态接口，不需要改每个页面。

### 2. 公共列表条目动作目标

现状：

- 分类页、搜索页、首页等已经拿到 `MediaItemCard`。
- 但长按操作和部分导航仍要求 `MediaLibraryItem`，所以多个页面有 `_cardToMediaItem` / `_cardToActionItem` 之类的适配代码。

建议：

- 定义轻量 `MediaItemActionTarget`，字段只包含 action sheet 和导航真正需要的内容：`id`、`title`、`type`、`watched`、`favorite`、`seasonNumber`、`episodeNumber`、`seriesId`、`image`。
- `MediaItemActionSheetController.show` 改为接收该 target 或直接接收 `MediaItemCard`。
- 飞牛旧模型只在飞牛 API mapper 内部出现，不再作为公共 UI 控制器入参。

收益：

- 删除分类页、搜索页、合集页的模型回填逻辑。
- 避免新增后端时为了复用 UI 被迫伪造 `MediaLibraryItem`。

### 3. 详情打开与首屏预取

现状：

- 多个入口打开详情前会尝试 `FeiniuApi.getItemDetail(...).timeout(...)` 预取 `initialItemDetail`。
- Emby 入口通常跳过预取，让目标详情页自己走 `MediaBackend.getItemDetail`。

建议：

- 把预取封装为 `MediaDetailPrefetcher`：当前后端能快速提供首屏详情时返回公共 `MediaDetailSnapshot`，不能时返回 null。
- `AdaptiveDetailRequest` 不再携带飞牛原始 `Map<String, dynamic>`，改为携带公共快照。
- 飞牛详情页逐步迁移到公共快照首屏，再按需补飞牛私有播放/下载数据。

收益：

- 搜索、分类、收藏、合集、人物作品等入口使用同一套详情打开逻辑。
- Emby 后续可以安全加预取，不需要复制飞牛 `initialItemDetail` 语义。

### 4. 详情页中立渲染与飞牛渲染合流

现状：

- `play_detail_page.dart` 中非飞牛走 `_neutralDisplayOnly`，飞牛走旧 `PlayInfoData` / `Map` 路径。
- `tv_detail_page.dart`、`tv_season_detail_page.dart` 也有类似的中立/飞牛双路径。
- 许多 UI 行为相同：标题、海报、动态主题、播放按钮、收藏/已看、演职员、文件信息、选集。

建议：

- 先抽取不含飞牛私有数据的展示 controller，例如 `MediaDetailViewModel`、`SeriesDetailViewModel`、`SeasonDetailViewModel`。
- 飞牛 mapper 也产出这些 view model；飞牛专属下载、片头片尾、服务端转码配置通过 `capabilities` 和扩展面板挂载。
- 页面只按 view model 渲染，后端差异留给 data loader。

收益：

- 详情页不会继续形成“飞牛版页面 + Emby 版页面”。
- Emby 可自然获得飞牛已有的详情页交互，例如剧详情收藏/已看、季详情已看、刷新状态。

### 5. 播放入口与 source bridge 分发

现状：

- `ItemPlaybackLauncher` 和 `TvSeasonPlaybackLauncher` 都包含：读取 backend、构造 `MediaPlaybackRequest`、调用 `getPlayback`、按 context 类型选择 bridge、处理原生壳、处理 Emby 选集 payload、处理飞牛本地下载优先。
- 两个 launcher 的差异主要是入口上下文和 episode fallback。

建议：

- 抽出 `MediaPlaybackResolver`：负责 `getPlayback` + `FeiniuPlaybackSourceBridge` / `EmbyPlaybackSourceBridge` 分发。
- 抽出 `NativePlaybackLaunchAdapter`：负责原生壳 `maybeLaunch`、`episodes`、`nas`、reentry bind。
- 本地下载优先作为飞牛 backend 的可选 `LocalPlayableResolver`，不要写在通用 launcher 主流程里。

收益：

- 单条目、剧集、季详情、原生壳重解析共用同一条播放解析链。
- 新后端只增加 backend context + source bridge，不需要复制两个 launcher。

### 6. 原生壳选集/下一集入口一致性

现状：

- 原生壳的飞牛选集通过 `NativeReentrySupport` 接入，Emby 选集通过 `EmbyNativePickerSupport` 接入。
- 两边返回给原生端的协议大体对齐，但页面入口仍会自己构造 `episodes` payload。
- 季页面传给 `TvSeasonPlaybackLauncher.open` 的 payload 是页面手拼的精简字段；详情页入口则可能由 launcher 或 picker support 补整季 episodes。
- Flutter 播放器页已按后续规划排除，不作为本轮公共抽象目标。

建议：

- 抽出 `NativeEpisodePayloadBuilder`：
  - 飞牛实现复用 `NativeReentrySupport` 的完整 episode map。
  - Emby 实现复用 `EmbyNativePickerSupport.nativeEpisodePayload()`。
  - 页面只传当前条目、季、剧的上下文，不再直接拼 `Map<String, dynamic>`。
- 把 `loadEpisodePickerData`、`loadSeasonEpisodes`、`setEpisodePickerViewType` 归入一个 `NativeEpisodePickerAdapter` 协议，`NativePlaybackReentry` 只做 backend 分发。

收益：

- 从详情页、剧详情、季页面进入原生壳时，选集面板、下一集、时长、已看状态、海报鉴权字段一致。
- 后续后端只需要实现原生选集 adapter，不需要在多个页面复制 payload 构造。

### 7. 图片鉴权与图片解析

现状：

- 飞牛图片多通过 `NasProvider.baseUrl/token` 拼接或预取。
- Emby 图片多是带 `api_key` 的完整直链。
- 页面里仍有“传 NasProvider / token 为空 / Emby 直接透传”的分散注释和判断。

建议：

- 定义 `MediaImageResolver` 或扩展 `MediaImageRef`，支持：
  - 完整 URL 直接使用。
  - 相对路径由 backend 解析。
  - 可选 headers/cookie/token。
  - 动态主题取色、海报、logo、人物头像、原生壳图片共用同一入口。

收益：

- UI 不再知道飞牛和 Emby 的图片鉴权差异。
- 可减少 `NasProvider` 在中立页面里的残留读取。

### 8. 列表偏好和筛选持久化

现状：

- 分类页的筛选 schema 已公共化。
- 排序、视图偏好持久化仍是飞牛 `getUserListSetting/setUserListSetting`，Emby 跳过。

建议：

- 建立 `MediaListPreferenceStore`：
  - 飞牛实现同步到后端用户数据。
  - Emby 先用本地 SharedPreferences，key 包含 backend kind、server、userId、catalogId。
  - 如果后续确认 Emby 服务器侧 display preferences 可用，再在 Emby adapter 内替换实现。

收益：

- Emby 分类页也能记住宫格/列表、排序方式。
- 页面不需要判断 `_isFeiniuBackend` 才写偏好。

### 9. 收藏页 / 收藏查询

现状：

- `favorite_items_screen.dart` 完全基于 `FeiniuApi.getFavoritePage`、飞牛 tag schema、飞牛列表偏好。
- Emby backend 已有收藏/取消收藏能力，且 `EmbyApi.getItemCount` 已使用 `Filters=IsFavorite` 计数。

建议：

- 在 `MediaBackend` 增加 `queryFavoriteItems(MediaCatalogQuery query)` 或更通用的 `queryLibraryItems` 支持 `favoritesOnly`。
- 收藏页改用 `MediaItemCardPage`、公共筛选 schema 和公共 action sheet。
- 飞牛保留 favorite-only 的 tag schema；Emby 用 `Filters=IsFavorite` + `IncludeItemTypes=Movie,Series,Episode`。

收益：

- Emby 可补齐收藏页。
- 收藏页不再是飞牛专属屏幕。

### 10. 合集 / 集合详情

现状：

- `media_collection_detail_page.dart` 仍是飞牛专属：加载详情、加载合集内条目、收藏/已看、排序偏好、打开子条目都走 `FeiniuApi`。

建议：

- 抽象 `MediaCollectionDetail` 或复用 `MediaDetail + queryChildren(parentId)`。
- 在 `MediaBackend` 增加 `queryChildItems(parentId, query)`，用于合集、文件夹、特殊集合。
- 飞牛 adapter 映射原合集接口；Emby adapter 可通过 parentId/recursive 查询合集子项。

收益：

- Emby 的 Collection/BoxSet 可以使用同一页面。
- 第三个后端的“集合/文件夹/歌单”也有落点。

### 11. 下载与离线

现状：

- `DownloadTaskService`、下载列表、下载 action 全部绑定飞牛 NAS 和服务端下载任务。
- Emby `capabilities.supportsDownloadTasks=false`，详情页只提示不可用。

建议：

- 区分两类能力：
  - `supportsServerDownloadTasks`：飞牛 NAS 服务端下载。
  - `supportsDirectFileDownload`：前端用直链下载到本机。
- 增加可选接口 `createLocalDownloadSource(itemId, selectors)`，返回 URL、headers、文件名、字幕/图片候选。
- 飞牛保留现有服务端任务；Emby 可基于 `buildStreamUrl` 和 `RequiredHttpHeaders` 做本地下载。

收益：

- Emby 可补齐“下载到设备”这一用户能力，但不伪装成飞牛 NAS 服务端下载。
- 下载 UI 可以按能力展示不同文案和队列类型。

### 12. 字幕能力

现状：

- 播放期外挂字幕文件解析已通过 `resolveExternalSubtitleFile` 支持 Emby。
- 飞牛还有远程字幕搜索、下载、删除等管理能力，页面/播放器设置里仍直接使用 `FeiniuApi`。

建议：

- 抽象为可选 `MediaSubtitleBackend`：
  - `listAvailableSubtitles(itemId/mediaSourceId)`
  - `resolveSubtitleFile(trackId)`
  - `searchRemoteSubtitles(...)`
  - `attachRemoteSubtitle(...)`
  - `deleteSubtitle(...)`
- Emby 初期只实现 `resolveSubtitleFile` 和内置/外挂轨道展示；远程搜索是否支持由 capability 控制。

收益：

- 播放器字幕设置页不会写死飞牛。
- Emby 已能做的外挂字幕加载可以在更多入口稳定使用。

### 13. 播放统计与进度补偿

现状：

- Emby 的播放进度回写已接入 backend。
- 飞牛有离线进度队列、本地 play stats、backfill 等服务，很多仍接收 `NasProvider` / `FeiniuApi`。

建议：

- 将“本地播放统计”和“后端续播位同步”分开：
  - 本地统计只依赖 `itemId/backendKind/serverKey`。
  - 后端同步只调用 `MediaBackend.reportPlayback*`。
- backfill 做成 per-backend adapter。飞牛可从 NAS 补元数据，Emby 可从 `getItem` / `getItemPage` 补元数据。

收益：

- Emby 播放记录、统计报表、续播刷新可以一致。
- 离线队列不会继续只认飞牛 NAS。

## 飞牛已有但 Emby 可以补齐的功能

| 功能 | 飞牛现状 | Emby 可行路径 | 建议优先级 |
| --- | --- | --- | --- |
| 收藏页 | `getFavoritePage` + 收藏筛选 | `Users/{userId}/Items` + `Filters=IsFavorite` | 高 |
| 长按菜单收藏/已看 | `MediaItemActionSheetController` 直连飞牛 | 复用 `MediaBackend.setItemFavorite/setItemWatched` | 高 |
| 剧详情收藏/已看 | `tv_detail_page.dart` 直连飞牛 | 对 Series 调 `FavoriteItems`；已看状态按 Emby PlayedItems 能力和实际返回校验 | 高 |
| 季详情已看 | `tv_season_detail_page.dart` 直连飞牛 | 对 Season 或其 episodes 批量标记，需先确认 Emby 对 Season PlayedItems 的行为 | 中 |
| 收藏人物 | `person_detail_screen.dart` 直连飞牛 | Person 在 Emby 也是 item，可尝试 `FavoriteItems/{personId}`，失败则 capability 降级 | 中 |
| 合集详情 | 飞牛合集页完整 | Emby Collection/BoxSet 可按 parent/collection 查询子项 | 中 |
| 分类页视图/排序偏好 | 飞牛服务端用户数据 | Emby 先本地持久化，后续再考虑服务端 display preferences | 中 |
| 原生播放入口一致性 / 原生壳选集信息完整度 | 飞牛原生选集和 reentry 能力较完整，但入口仍有页面直连路径 | 用统一 `NativePlaybackCoordinator` + `NativeEpisodePayloadBuilder` 收敛 Emby 和飞牛入口 | 高 |
| 本地下载到设备 | 飞牛服务端下载任务 | Emby direct stream URL + headers 可做本地下载队列 | 中 |
| 字幕文件落地 | 飞牛 subtitle guid 下载 | Emby 已有 `downloadSubtitleText`，可扩展到字幕管理 UI | 中 |
| 播放统计元数据回填 | 飞牛从 NAS playInfo/item detail 补 | Emby 可从 `getItem` / `getItemPage` 补 | 低 |

## 暂不建议公共化的飞牛私有能力

这些能力即使后续做 UI，也应作为 capability 插件式挂载，不应进入核心公共模型：

- FN Connect 登录/中转域名发现。
- 飞牛 NAS 服务端下载任务、服务端授权目录。
- 飞牛片头片尾配置。
- 飞牛服务端播放会话重载、转码档位私有协议。
- 飞牛标签字典里的识别状态、颜色范围、音频类型等私有筛选维度。公共层可以表达维度，但不要把字段名写死进 UI。

## 建议实施顺序

1. 先收敛条目状态动作：把收藏/已看 controller 改成 backend 驱动，覆盖详情页、剧详情、季详情、长按菜单。
2. 再收敛 action target：让列表、搜索、收藏、合集都直接消费公共条目模型，不再伪造 `MediaLibraryItem`。
3. 接着补 Emby 收藏页：新增 favorite query，复用分类页公共筛选和 action sheet。
4. 抽播放 resolver 和原生起播 coordinator：减少 `ItemPlaybackLauncher` / `TvSeasonPlaybackLauncher` 重复，并统一详情页、剧详情、季页面、下载列表进入原生壳的编排。
5. 逐步把飞牛详情页迁移到公共 view model，最后合并中立详情和飞牛详情的 UI 渲染路径。

## 风险和验证点

- Emby 对 Series、Season、Person 的 `PlayedItems` / `FavoriteItems` 行为需要真机或 mock API 分别验证；不要只按 Movie/Episode 推断。
- 下载能力要区分“NAS 服务端下载”和“下载到设备的本地下载”，否则 UI 文案和队列状态会混乱。
- 飞牛旧页面迁移到公共 view model 时，必须对比原 `PlayInfoData` 首屏字段，避免海报、标题、续播、下载状态回归。
- 原生壳要按入口分别验证：单条目详情、剧详情、季页面、下载列表的选集面板、下一集、跨集轨道/字幕/分辨率继承应保持一致。
- 每次抽象都应保留 capability 降级：不支持的后端隐藏入口或给出统一不可用提示，而不是落到飞牛默认路径。
