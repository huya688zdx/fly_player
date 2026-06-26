# 设计：Emby 播放接入（getPlayback + 桥接器 + entry-token）

> 状态：**设计待审**（2026-06-25）。分支 `feat/native-player-overhaul`。
> 本文是 Emby 第二后端的「最麻烦一块」——播放接入。前置抽象（Phase 6 播放层 + 飞牛收口）已收口、真机验证过；
> Emby `getPlayback` 现 `throw UnsupportedError`。本设计把它落地，并合并已待办的 entry-token 播放注入（原块 4）。

## 0. 一句话目标

让 Emby 条目（电影 / 单集）能播：`EmbyMediaBackend.getPlayback` 产出后端中立
`MediaPlaybackResolution`，新增 `EmbyPlaybackSourceBridge`（住 player 层）把它装配成
`MpvMediaSource`，`ItemPlaybackLauncher` 按后端类型分发桥接器。**对 fnos 中转域携带
`Cookie: entry-token` 过云端边缘闸。**

## 1. 已有抽象（复用，零改动）

播放链路早已后端中立化（见 `public-media-backend-phase6` 记忆 / 既有 spec）：

- 中立模型 `lib/media_backend/playback/media_playback.dart`：`MediaPlaybackRequest` /
  `MediaPlaybackBundle` / `MediaPlaybackSource` / `MediaPlaybackQuality` / `MediaPlaybackTrack` /
  `MediaPlaybackSession` + 枚举 `MediaPlaybackDeliveryKind{original,directLink,serverSession,transcoding}`。
- `MediaPlaybackResolution { bundle, backendContext }`，`backendContext` 是**不透明** `MediaPlaybackBackendContext`。
- 飞牛对位：`FeiniuPlaybackContext`（raw facts）+ `FeiniuPlaybackSourceBridge`（player 层装配 `MpvMediaSource`）。
- `ItemPlaybackLauncher._resolve`：`getPlayback` → downcast context → bridge.assemble → `MpvMediaSource`。

**Emby 只需写对位的两个新文件 + 一处 launcher 分发 + 一个 emby_api 取流方法。中立模型 / 飞牛侧 / 播放管线 headers 透传全不动。**

## 2. Emby 投递选型：直链直播（Static direct-stream）

Emby 出流有两条路：

| 路径 | 机制 | 取舍 |
|---|---|---|
| **A. 直链原文件** | `GET /Videos/{itemId}/stream?Static=true&MediaSourceId={msid}&api_key={token}` | mpv 直接吃原始容器，**所有内嵌音轨/字幕在 mpv 侧按轨道号切换**，无服务端会话、无 PlaySessionId 生命周期。 |
| B. PlaybackInfo + 转码 | `POST /Items/{itemId}/PlaybackInfo`（带 DeviceProfile）→ `MediaSources[].TranscodingUrl`（HLS .m3u8） | 仅当客户端播不了原文件才需要；引入转码会话（启停 check-in、服务端 transcode 进程、画质梯度）。 |

**本设计选 A（直链直播）**，对位飞牛「原画」投递（`MediaPlaybackDeliveryKind.directLink`）。理由：

- mpv 是远比任何 web 客户端强的播放器，原始容器几乎都能直接播——直链是自然且最稳的首版口径。
- 无服务端转码会话 = 无 PlaySessionId 启停生命周期、无画质梯度，**契合详情页选择器已落口径**（版本 + 音轨 + 字幕，**无画质档**，见 `2026-06-24-emby-version-audio-subtitle-selectors`）。
- 音轨/字幕切换走 mpv 客户端轨道号，与飞牛原画模式同构，复用现有播放器 UI。
- 版本切换 = 选 `MediaSourceId`（`MediaSourceVersion.id` 已建模）。

转码路径（B）留作后续（低端机 / 不兼容编码 / 远程限带宽时）——届时 `MediaPlaybackDeliveryKind.transcoding` + `MediaPlaybackSession` 已预留字段，按 PlaybackInfo 接。**首版不做。**

## 3. 架构对位（新增 3 文件 + 改 2 文件）

```
lib/api/emby_api.dart                         (改) 新增 buildStreamUrl(itemId, mediaSourceId)  ── Codex 在改，走 stash 隔离
lib/media_backend/emby/emby_playback_context.dart   (新) EmbyPlaybackContext implements MediaPlaybackBackendContext
lib/media_backend/emby/emby_playback_mappers.dart   (新) Emby MediaSource/MediaStreams → 中立 bundle/source/track
lib/media_backend/emby/emby_media_backend.dart      (改) getPlayback 实装（删 _unsupported）
lib/player/controllers/emby_playback_source_bridge.dart (新) EmbyPlaybackSourceBridge：bundle+context → MpvMediaSource
lib/controllers/item_playback_launcher.dart         (改) _resolve 按活动后端 + 按 context 类型分发桥接器
```

### 3.1 `EmbyPlaybackContext`（不透明 raw facts）

桥接器装配 `MpvMediaSource` 所需的 Emby 私有事实，中立层不解读：

```dart
class EmbyPlaybackContext implements MediaPlaybackBackendContext {
  final String streamUrl;          // 已拼好的直链（含 api_key）
  final Map<String, String> headers; // entry-token cookie（fnos 中转）或空
  final EmbyMediaSourceRaw source; // 选中 MediaSource 原始（容器/编码/宽高/比特深等）
  final int? audioStreamIndex;     // 选中音轨在容器内的 stream index（→ mpv 轨道号）
  final int? subtitleStreamIndex;  // 选中字幕 stream index；关闭时 null
  final List<EmbyMediaStreamRaw> mediaStreams; // 全部流，供内嵌字幕序号换算 / 外挂识别
  // 标题/季集/poster/tmdb/duration 已进 bundle，不重复装这里
}
```

> 与飞牛 context 不同：Emby **不需要二次网络**——`getPlayback` 一次 `getPlaybackInfo`/`getItem(MediaSources)`
> 就拿全所需，桥接器纯本地装配（不像飞牛还要 `PlayerSourceController.buildInitialPlaybackResult` 二解析代理/会话）。

### 3.2 `emby_playback_mappers.dart`

复用详情页已写的 `mapEmbySourceVersions` 同源解析口径（`MediaSources[]` / `MediaStreams[]` / `Default*StreamIndex`），但产出**播放中立模型**而非详情模型：

- `mapEmbyPlaybackSource(source, streamUrl, headers)` → `MediaPlaybackSource`（delivery=directLink，width/height/codec/colorSpace/bitDepth 从 MediaStreams 视频流，reliableSeek=true，forceNativeProxy=false）。
- `mapEmbyPlaybackAudioTracks(streams)` / `mapEmbyPlaybackSubtitleTracks(streams)` → `List<MediaPlaybackTrack>`（id=stream Index 字符串，index=容器内 index，subtitleLocation=external/embedded 按 `IsExternal`）。
- `mapEmbyPlaybackBundle(item, source, ...)` → `MediaPlaybackBundle`（title/itemType/seriesId/seasonId/季集号/poster/tmdb/duration/startPosition + selected*）。
- 默认轨：`DefaultAudioStreamIndex` / `DefaultSubtitleStreamIndex`。

### 3.3 `EmbyMediaBackend.getPlayback`

```
1. item = api.getPlaybackItem(itemId)   // getItem(fields: MediaSources,MediaStreams,UserData)
2. 选 MediaSource：request.qualityId(=MediaSourceId) 优先，否则首个 source
3. 选音轨：selectPlaybackTrack(audioTrackId / preferredAudioTrackIndex / fallback=DefaultAudioStreamIndex)
4. 选字幕：同上 + explicitlyDisabled 三态
5. streamUrl = api.buildStreamUrl(itemId, msid)         // Static=true&api_key=
6. headers = _entryTokenHeaders(connection)             // 块4：fnos 中转加 Cookie
7. startPosition = resume(UserData.PlaybackPositionTicks ÷ 1e7,  request.resumePosition, startFromBeginning)
                   ── 复用 PlaybackResumePositionResolver（本地/网络对账，与飞牛同）
8. bundle = mapEmbyPlaybackBundle(...)
9. context = EmbyPlaybackContext(...)
10. return MediaPlaybackResolution(bundle, context)
```

复用中立 `selectPlaybackTrack` / `PlaybackResumePositionResolver`（飞牛已验证的选择/续播对账内核），**不重写选择逻辑**。

### 3.4 `EmbyPlaybackSourceBridge`（player 层）

纯本地装配 `MpvMediaSource`（无网络、无 `PlayerSourceController`）：

```dart
MpvMediaSource(
  loadNonce, itemGuid: bundle.itemId,
  seriesGuid: request.seriesId | bundle.seriesId, seasonGuid: bundle.seasonId,
  mediaGuid: bundle.selectedSource.id,           // = MediaSourceId
  mediaType: bundle.itemType,
  url: context.streamUrl, headers: context.headers,
  title: bundle.title, seriesTitle: bundle.seriesTitle,
  seasonNumber: bundle.seasonNumber, episodeNumber: bundle.episodeNumber,
  tmdbId: bundle.tmdbId, durationSeconds: bundle.durationSeconds,
  startPosition: bundle.startPosition,
  audioTrackIndex: context.audioStreamIndex,     // mpv 侧轨道号
  subtitleTrackIndex: embeddedSubtitleOrdinal,   // 内嵌按序号；外挂另议
  videoWidth/Height/codec/colorSpace/bitDepth: 从 bundle.selectedSource,
  reliableSeek: true, forceNativeProxy: false,
  playbackMode: <directLink 对应模式>,
  qualities: const [],                           // 首版无画质梯度
  audioTracks/subtitleTracks: <中立轨 → MpvMediaSource 期望结构的适配>,
)
```

**待校准点（实现期定）**：`MpvMediaSource` 的 `audioTracks`/`subtitleTracks`/`qualities` 字段当前是飞牛模型类型
（`PlaybackStreamData.audioStreams` 等）。Emby 没有这些飞牛 DTO。两条路：
- (a) 这些字段首版**置空**，播放能起、但播放器内「音轨/字幕/画质切换 UI」对 Emby 暂不可用（切轨要靠重发 getPlayback 的反向通道，本期不做——见 §5）；
- (b) 给 `MpvMediaSource` 这些字段引入中立类型 / 适配层。**(a) 是首版口径**（最小可播），(b) 留切轨反向通道一并做。

### 3.5 `ItemPlaybackLauncher._resolve` 解耦

现状硬编码飞牛：

```dart
final backend = FeiniuMediaBackend(FeiniuApi(nas));   // ← 改：取活动后端
final resolution = await backend.getPlayback(request);
final context = resolution.backendContext;
if (context is! FeiniuPlaybackContext) return null;   // ← 改：按类型分发
final source = await const FeiniuPlaybackSourceBridge().assemble(...);
```

改为：

```dart
final backend = context.read<MediaBackendProvider>().backend;   // 活动后端（飞牛/Emby）
final resolution = await backend.getPlayback(request);
final ctx = resolution.backendContext;
final MpvMediaSource source;
if (ctx is FeiniuPlaybackContext) {
  source = await const FeiniuPlaybackSourceBridge().assemble(...);
} else if (ctx is EmbyPlaybackContext) {
  source = await const EmbyPlaybackSourceBridge().assemble(...);
} else { return null; }
```

> `_resolve` 当前签名收 `NasProvider nas`；需改成也能拿 `MediaBackendProvider`（或在 `open`/`resolveForNative`
> 入口处读后端传入）。

**播放器路径（用户已拍板：走原生壳，体验与飞牛一致）**：Emby 与飞牛同样经
`NativePlayerBridge.maybeLaunch(source.toMap())` 拉起原生播放壳——只要 `EmbyPlaybackSourceBridge` 产出合法
`MpvMediaSource`（url + headers + 续播位 + 标题/季集），原生壳即可直链直播。**首版聚焦 Emby 电影（单条目）**：
单条目无选集、无画质梯度，原生壳不会触发选集对话框 / 画质切换，故反向通道（`_bindReentry`）对电影路径最小化：

- `resolveForNative`（切档重解析）：本就调 `_resolve`，随 `_resolve` 后端分发而 Emby-aware（无画质档时返回原源）。
- `onRecordProgress`：飞牛 `NativeReentrySupport.recordProgress` 向飞牛 API 写回——Emby 首版**仅本地 play stats**，
  不向 Emby 上报（进度回写留后续，见 §5）。
- 选集 / 切集继承（`loadSeasonEpisodes` / `onLoadEpisodePickerData`）：飞牛 API 专属，**电影路径不触发**；
  Emby 单集（TV）连播留 `TvSeasonPlaybackLauncher` 后续分块。

## 4. entry-token 播放注入（合并原「块 4」计划）

源出 `docs/superpowers/plans/2026-06-23-emby-fnos-playback-entry-token.md`。要点照搬：

- `getPlayback` 装 bundle 时，对 `*.fnos.net` 主机给 `headers['Cookie'] = ...entry-token=<值>`。
- 复用 `usesFnConnectRelayCookie`（`lib/utils/nas_image_headers.dart`）判主机；token 取 `connection.entryToken`。
- cookie 合并语义与 `EmbyApi._mergeEntryTokenCookie` 一致——**抽公共工具**避免两份实现（`nas_image_headers.dart` 加 `mergeEntryTokenCookie`，EmbyApi 与 getPlayback 共用）。
- 直连地址（非 fnos）entryToken 空 / 主机不匹配 → 不加，零影响。
- 播放管线 headers 端到端透传（`MediaPlayback.headers` → `PlaybackStream.headers` 合 `Cookie` → `MpvPlaybackController` loadfile）**已确认可复用，无需改管线**。
- **过期处理（块 4.4）**：entry-token 会话级、播放中可能失效 → 上游返 403 HTML。识别该 403 并触发重抓（与登录路径 403 重抓一致）——**首版先打通可播，过期重抓留作收尾子任务**。

## 5. 范围界定：本期做 / 不做

**做（首版可播）**：
- **Emby 电影（单条目）经原生壳直链直播**，过 fnos 边缘闸，续播位（读）生效。
- 详情页「播放」按钮从占位「即将到来」改为真起播（走 `ItemPlaybackLauncher` → `maybeLaunch` 原生壳）。
- 详情页已选的版本 / 音轨 / 字幕作为 `MediaPlaybackRequest` 入参传入起播。

**不做（后续分块，明确缺口）**：
- **播放器内切音轨/字幕/版本**：依赖重发 `getPlayback` 的反向通道，与 §3.4(b) 的 `MpvMediaSource` 中立轨道字段一并做。Emby 单条目无画质梯度，原生壳画质切换不触发。
- **转码（HLS）**：见 §2，低端机/不兼容编码留作 `delivery=transcoding` 分块。
- **进度回写 Emby**（`/Sessions/Playing/Progress` check-in）：play stats 本地仍记，但不向 Emby 上报续播。**续播读已做**（UserData.PlaybackPositionTicks），**写**留后续——否则下次进来续播位不更新。
- **剧集连播 / 选集**（TV launcher 的 Emby 化）：`TvSeasonPlaybackLauncher` 另排。
- **弹幕**：Emby 起播暂不预取弹幕（飞牛专属 NativeDanmakuPrefetch 链路）。

> 取舍逻辑：先用最短可信路径让 Emby「能播一个文件」（直链 + Flutter 播放器 + 续播读），把原生壳 / 反向通道 / 转码 / 进度回写 / 连播这些**深绑飞牛或需双向通道**的能力拆成后续分块，逐块真机验证。符合「先把能播证明出来」。

## 6. 分块实现顺序（每块 pathspec 单独提交）

> emby_api.dart 有 Codex 未提交改动（entry-token 拦截器）——凡动它走 **stash 隔离提交**
> （`git stash push -- <Codex 文件>` → 编辑我的区 → `git commit -F - -- <我的文件>` → `git stash pop`）。
> 每块提交前 `git status --short` + `git diff --cached --name-only` 复核，**绝不夹带 Codex/未跟踪文件**。

| 块 | 内容 | 文件 | 测试 |
|---|---|---|---|
| P-1 | emby_api `buildStreamUrl` + `getPlaybackItem`（getItem fields=MediaSources,MediaStreams,UserData） | emby_api.dart（stash 隔离） | URL/参数 + 字段单测 |
| P-2 | 中立 `EmbyPlaybackContext` + `emby_playback_mappers`（source/track/bundle 映射） | 2 新文件 | mapper 单测（多源/默认轨/续播 ticks） |
| P-3 | `EmbyMediaBackend.getPlayback` 实装（删 _unsupported） | emby_media_backend.dart | backend 单测（选源/选轨/entry-token header/直连无 header） |
| P-4 | `EmbyPlaybackSourceBridge` 装配 MpvMediaSource | 新文件 | bridge 单测（url/headers/startPosition/轨道号） |
| P-5 | `ItemPlaybackLauncher._resolve` 后端分发 + 详情页「播放」起播接线 | item_playback_launcher.dart, play_detail_page.dart | （真机为主，分发分支可单测） |
| P-6 | entry-token 公共工具抽取（EmbyApi + getPlayback 共用） | nas_image_headers.dart, emby_api.dart, getPlayback | merge 语义单测 |

## 7. 测试计划

- 单测：`buildStreamUrl` 含 `Static=true&MediaSourceId&api_key`；`getPlayback` 对 fnos 主机 `headers['Cookie']` 含 `entry-token`、对直连主机不含、entryToken 空时不加。
- 单测：mapper 选默认音轨/字幕、版本切换换 source、续播 ticks→秒、explicitlyDisabled 三态。
- 单测：launcher 按 context 类型分发到对应桥接器（飞牛 context → 飞牛桥、Emby context → Emby 桥）。
- 真机：`embyserver4-9.geqian688.fnos.net` 实测能播电影 + 单集；拖动进度（Range）正常；续播位生效；**飞牛播放零回归**（launcher 分发改动后飞牛主路径逐项复验）。

## 8. 风险 / 待确认

- **mpv 转发 `Cookie` 头**（块 4.3）：需真机确认 mpv 把 `Cookie` 带到上游；若有坑回退到 `mpv_proxy_server.dart` 按 host 注入。
- **Range 请求过闸**：拖动 / 多段加载是否同样只认 entry-token（预期是，闸在边缘与方法无关，需真机验证拖动）。
- **mpv 轨道号 ↔ Emby stream index 对齐**：内嵌音轨/字幕在 mpv 的编号是否与 Emby `MediaStreams` index 一致（容器内顺序），需真机核对选中轨是否正确生效。
- **`MpvMediaSource` 轨道字段类型**（§3.4）：飞牛 DTO 类型，Emby 首版置空（播放器内切轨 UI 暂不可用），是否可接受 / 是否要本块就引入中立轨道字段——**倾向首版置空，反向通道分块再处理**。
- **外挂字幕**：Emby `MediaStreams[IsExternal]` 有独立 `DeliveryUrl`，首版仅内嵌字幕走 mpv 轨道号；外挂 sideload 留后续。
- **entry-token 直链主机域**：Emby 返回的播放直链必须在 `.<fnId>.fnos.net` 域下 cookie 才发送；若指向独立 media 子域需确认其也在该域（块 4 风险点）。

## 9. 关联

- 前置抽象：`public-media-backend-phase6` 记忆、`docs/superpowers/specs/2026-06-21-public-media-playback-*.md`。
- entry-token 机制：`emby-fnos-entry-token` 记忆、`docs/superpowers/plans/2026-06-23-emby-fnos-playback-entry-token.md`（块 4，本设计 §4 合并）。
- 详情页选择器（版本/音轨/字幕入参来源）：`docs/superpowers/plans/2026-06-24-emby-version-audio-subtitle-selectors.md`。
- 协作：Claude 主实现、Codex 审查/补测；emby_api.dart 并行作业走 stash 隔离。
</content>
</invoke>
