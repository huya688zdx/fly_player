# 公共播放入口抽象设计（Phase 6）

> 前置详情设计：`docs/superpowers/specs/2026-06-21-public-media-detail-design.md`
> Emby API 调研：`docs/superpowers/research/2026-06-21-emby-api-shape.md`
> 上层设计：`docs/superpowers/specs/2026-06-20-public-media-frontend-design.md`

## 目标

为播放入口建立后端中立的公共播放模型和解析接口，让飞牛当前的 `PlayInfoData` / `PlaybackStreamData` / `StreamTrackData` 组合先收敛到一个可测试的播放 bundle，再逐步服务 `ItemPlaybackLauncher` / `TvSeasonPlaybackLauncher`。

本阶段第一步只做**播放后端骨架**：公共播放模型 + 飞牛 mapper + `MediaBackend` 播放解析接口 + 单测。不接入 Emby API，不迁移 `MpvPlayerPage` 深层 mixin，不重构播放器生命周期，不改下载、本地播放和原生壳反向通道。

## 现状审计

当前播放入口主要有两条链路：

- `lib/controllers/item_playback_launcher.dart`
  - `open()` / `resolveForNative()` / `_resolve()`。
  - `_resolve()` 直接 `new FeiniuApi(nas)`，依次调用 `getPlayInfo`、可选 `resetPlaybackRecord`、best-effort `getStreamTrackData`、`getPlaybackStream`，再合并清晰度、选择音轨/字幕、解析续播位、调用 `PlayerSourceController.buildInitialPlaybackResult()`，最后构造 `MpvMediaSource`。
- `lib/controllers/tv_season_playback_launcher.dart`
  - `open()` / `resolveForNative()` / `_resolveWithProvider()`。
  - 逻辑与单条目高度相似，但多了 `seriesTitle`、`seriesGuid`、`episodes` 透传和剧集续播完成态判断。

两条链路共同消费的飞牛结构：

- `PlayInfoData`：条目、默认 `mediaGuid` / `videoGuid` / `audioGuid` / `subtitleGuid`、父子层级、续播 `ts`。
- `PlaybackStreamData`：当前媒体的 file/video/audio/subtitle/qualities/directLink/headers/cloudStorage。
- `StreamTrackData`：跨多版本媒体的文件、视频、音轨、字幕索引。
- `PlaybackQualityOption` / `AudioTrackOption` / `SubtitleTrackOption`：当前播放器和 UI 直接使用的轨道选项。
- `MpvMediaSource`：播放器最终 load 参数，包含 Feiniu id、可播 URL、headers、本地代理、画质/轨道、弹幕搜索元数据、原生壳重载字段。

问题不是“拿不到数据”，而是**解析、选择、播放器装配混在入口控制器里**。如果直接把入口控制器改成读 Emby，会把 Emby `PlaybackInfoResponse.MediaSources`、飞牛 `mediaGuid`、mpv proxy、本地下载、原生反向通道和进度回写塞进同一个大改动。

## Emby 官方播放形状对 Phase 6 的约束

官方播放相关资料显示，Emby 与飞牛不是同形接口：

- `GET /Items/{Id}/PlaybackInfo?UserId=...`
  - 返回 `PlaybackInfoResponse`。
  - 关键字段包括 `MediaSources`、`PlaySessionId`、`ErrorCode`。
  - `MediaSourceInfo` 中包含 `MediaStreams`、`RequiredHttpHeaders`、`DirectStreamUrl`、`AddApiKeyToDirectStreamUrl`、`TranscodingUrl`、`DefaultAudioStreamIndex`、`DefaultSubtitleStreamIndex`、`ItemId`、codec、码率、尺寸等。
  - 来源：https://dev.emby.media/reference/RestAPI/MediaInfoService/getItemsByIdPlaybackinfo.html
- HLS 播放可走 `/Videos/{Id}/master.m3u8`。
  - 需要 `Id`、`MediaSourceId`、`DeviceId`。
  - 可带 `AudioCodec`、`VideoCodec`、`AudioStreamIndex`、`SubtitleStreamIndex`、`VideoBitrate`、`MaxWidth`、`MaxHeight` 等转码参数。
  - 播放结束后需要停止 HLS 转码会话。
  - 来源：https://dev.emby.media/doc/restapi/Http-Live-Streaming.html
- 播放生命周期不是单纯“打开 URL”。
  - 官方有 playback started / progress / stopped check-in。
  - 来源：https://dev.emby.media/doc/restapi/Playback-Check-ins.html

因此公共层不能把飞牛的 `mediaGuid` / `videoGuid` 原样提升为公共字段，也不能让 UI 按 `if (isEmby)` 分支判断 HLS、直链或转码。公共模型需要表达的是：播放源、画质候选、音轨/字幕候选、默认选择、续播位置、后端会话句柄和所需 headers。

## Phase 6 第一阶段范围

### 做

1. 新增 `lib/media_backend/playback/` 公共模型：
   - `MediaPlaybackRequest`
   - `MediaPlaybackBundle`
   - `MediaPlaybackSource`
   - `MediaPlaybackQuality`
   - `MediaPlaybackTrack`
   - `MediaPlaybackSession`
   - 相关 enum（track kind、delivery kind、subtitle location）。
2. 新增飞牛播放 mapper：
   - 把 `PlayInfoData` + `PlaybackStreamData` + 可选 `StreamTrackData` 映射为公共播放 bundle。
   - 保留飞牛字段在适配层内部；公共字段用 `sourceId`、`videoTrackId`、`audioTrackId`、`subtitleTrackId` 等中立命名。
3. 在 `MediaBackend` 增加播放解析接口：
   - `Future<MediaPlaybackBundle> getPlayback(MediaPlaybackRequest request);`
   - `FeiniuMediaBackend` 内部编排飞牛 API，复刻现有 best-effort 轨道加载和 `startFromBeginning` 重置语义。
4. 用单测锁住：
   - 默认媒体选择。
   - qualityMediaId / qualityIndex 覆盖规则。
   - 音轨/字幕默认选择与显式关闭字幕。
   - `getStreamTrackData` 失败时不阻断播放 bundle。
   - 续播 `ts > 0 ? ts : watchedTs`。
   - headers、直链/服务器会话候选不丢失。

### 不做

- 不接入 Emby API，不写 `EmbyMediaBackend`。
- 不改 `MpvPlayerPage` 深层 mixin。
- 不迁移本地下载优先逻辑。
- 不改原生壳 `NativePlayerBridge`、反向重载、弹幕预取。
- 不改播放进度写回 / play stats / check-in。
- 不把 `MpvMediaSource` 放进公共 `media_backend` 模型。
- 不在 UI 或控制器里新增 `if (isEmby)`。

## 公共播放模型边界

### `MediaPlaybackRequest`

请求表达“用户想如何开始/重载一次播放”，不表达具体后端 DTO。

```dart
class MediaPlaybackRequest {
  final String itemId;
  final String fallbackTitle;
  final bool startFromBeginning;
  final Duration? resumePosition;
  final int? qualityIndex;
  final String? qualityId;
  final String? audioTrackId;
  final String? subtitleTrackId;
  final bool subtitleTrackExplicitlyDisabled;
}
```

- `itemId`：飞牛 item guid / Emby item id。
- `qualityId`：飞牛可映射到 media guid；Emby 可映射到 media source id 或质量候选 id。公共层不叫 `mediaGuid`。
- `subtitleTrackExplicitlyDisabled`：解决当前 `overrideSubtitleGuid == ''` 的语义，避免公共层把“关闭字幕”误当“选默认字幕”。

### `MediaPlaybackBundle`

播放解析结果。它不是播放器 load 参数，而是**后端中立播放事实**。

```dart
class MediaPlaybackBundle {
  final String itemId;
  final String title;
  final String itemType;
  final String seriesId;
  final String seasonId;
  final String seriesTitle;
  final int seasonNumber;
  final int episodeNumber;
  final String posterUrl;
  final String tmdbId;
  final int durationSeconds;
  final Duration startPosition;
  final MediaPlaybackSource selectedSource;
  final MediaPlaybackQuality? selectedQuality;
  final MediaPlaybackTrack? selectedAudioTrack;
  final MediaPlaybackTrack? selectedSubtitleTrack;
  final List<MediaPlaybackQuality> qualities;
  final List<MediaPlaybackTrack> audioTracks;
  final List<MediaPlaybackTrack> subtitleTracks;
  final MediaPlaybackSession session;
}
```

- 字段保留播放器装配需要的通用元数据，但不出现 `guid` 命名。
- `posterUrl` 先是字符串，后续如需要鉴权 headers 再升级为 `MediaImageRef` 或增加 `posterHeaders`。
- `selectedSource` 描述“选中的后端播放源”，但不直接等价于 mpv 最终 URL；Feiniu 仍可能需要 `PlayerSourceController` 进一步决定代理/直链/服务端会话。

### `MediaPlaybackSource`

```dart
enum MediaPlaybackDeliveryKind {
  original,
  directLink,
  serverSession,
  transcoding,
}

class MediaPlaybackSource {
  final String id;
  final String videoTrackId;
  final MediaPlaybackDeliveryKind delivery;
  final String url;
  final Map<String, String> headers;
  final int width;
  final int height;
  final String videoCodec;
  final String videoProfile;
  final String colorSpace;
  final String colorTransfer;
  final String colorPrimaries;
  final int bitDepth;
  final bool reliableSeek;
  final bool forceNativeProxy;
}
```

- `id`：飞牛 media guid / Emby media source id。
- `videoTrackId`：飞牛 video guid / Emby video stream index 或 stream id 的公共封装。
- `url`：可以是当前后端给出的候选 URL；后续 launcher 桥接到 `MpvMediaSource` 时仍可根据本地代理和 player controller 改写。
- `headers`：必须保留；Emby `RequiredHttpHeaders` 和飞牛直链 headers 都不能丢。

### `MediaPlaybackQuality`

```dart
class MediaPlaybackQuality {
  final String id;
  final String sourceId;
  final String videoTrackId;
  final String label;
  final String resolution;
  final int bitrate;
  final bool isDefault;
  final MediaPlaybackDeliveryKind delivery;
  final int? directLinkIndex;
}
```

### `MediaPlaybackTrack`

```dart
enum MediaPlaybackTrackKind { audio, subtitle }

enum MediaSubtitleLocation {
  embedded,
  external,
  local,
}

class MediaPlaybackTrack {
  final String id;
  final MediaPlaybackTrackKind kind;
  final int? index;
  final String label;
  final String language;
  final String codec;
  final String title;
  final bool isDefault;
  final MediaSubtitleLocation? subtitleLocation;
}
```

### `MediaPlaybackSession`

```dart
class MediaPlaybackSession {
  final String id;
  final bool serverManaged;
  final bool requiresStop;
  final int hlsTimeSeconds;
}
```

- 飞牛可映射当前 `proxySessionId` / server session HLS 时间等。
- Emby 可映射 `PlaySessionId`，后续用于 stopped/progress check-in 和转码停止。
- 第一阶段只建模型，不实现生命周期调度。

## 飞牛适配层职责

`FeiniuMediaBackend.getPlayback(request)` 应该只做后端编排和模型映射：

1. `api.getPlayInfo(request.itemId)`。
2. 根据 `request.qualityId` 选择有效 source id，否则使用 `playInfo.mediaGuid`。
3. 若 `request.startFromBeginning`，调用 `api.resetPlaybackRecord(itemGuid, mediaGuid)`，复刻现有单条目入口行为。
4. best-effort 调 `api.getStreamTrackData(itemId)`，失败上报 warning 但不阻断。
5. `api.getPlaybackStream(effectiveSourceId)`。
6. `mergePlaybackQualitiesWithStreamTrackData(playbackStream.qualities, trackData)`。
7. 用公共 selector 选择 quality / audio / subtitle。
8. 用 `PlaybackResumePositionResolver.resolve(...)` 算起播位置。
9. 返回 `MediaPlaybackBundle`。

注意：

- `FeiniuMediaBackend` 不构造 `MpvMediaSource`。
- `FeiniuMediaBackend` 不调用 `Navigator`、`BuildContext`、`NativePlayerBridge`。
- `FeiniuMediaBackend` 不处理本地下载优先；本地下载是设备本地能力，仍留 launcher。
- 若需要复用 `PlayerSourceController.preferredInitialQuality` 的规则，优先把纯选择规则提炼到 `lib/media_backend/playback/media_playback_selectors.dart` 或 `lib/utils/`，不要让 `lib/media_backend` 反向依赖播放器 UI 控制器。

## 后续迁移分界

第一阶段完成后，`ItemPlaybackLauncher` 仍可保持现状。第二阶段才考虑新增一个桥接器：

```text
MediaPlaybackBundle + Feiniu raw playback facts
  -> PlayerSourceController.buildInitialPlaybackResult(...)
  -> MpvMediaSource
```

桥接器应放在 `lib/controllers/` 或 `lib/player/controllers/`，而不是 `lib/media_backend/`。这样公共 backend 层不依赖 mpv，播放器层也不需要知道 Emby/飞牛原始 DTO。

## 验收口径

第一阶段：

- `flutter test test/media_backend/ --concurrency=1` 全 PASS。
- `flutter analyze lib/media_backend test/media_backend` No issues。
- 新公共模型不含 `mediaGuid`、`videoGuid`、`audioGuid`、`subtitleGuid`、`Feiniu`、`Emby` 字段名。
- `FeiniuMediaBackend` 仍是适配层，没有导航、Widget、UI 文案或播放器深层逻辑。

后续入口迁移阶段（另行确认后）：

- 单条目播放、剧集播放、画质切换、音轨切换、字幕关闭/切换、外部字幕、本地下载优先、原生壳反向重载、弹幕预取、续播位置均需 `flutter run` 实机验证。
