# Emby API 接入参考

本文档整理 Emby 官方 API 文档入口、本项目 `EmbyApi` 当前接入范围，以及后续可补齐的接口方向。

## 官方文档

Emby 有官方开发者文档。当前推荐入口是：

```text
https://dev.emby.media/
```

官方开发者站点说明：REST API 文档已经迁移到该站点，并会随 Emby Server 版本更新；它支持搜索，并在接口页面中包含相关 schema 类型。

完整 REST API 索引：

```text
https://dev.emby.media/reference/RestAPI.html
```

Beta 版文档：

```text
https://betadev.emby.media/
```

旧入口：

```text
https://swagger.emby.media/
```

旧 Swagger 静态页面仍能访问，但官方社区里 Emby 团队成员已经说明 `swagger.emby.media/openapi.json` 属于过时入口，不建议继续作为主要参考。若需要 OpenAPI 文件，官方建议从 Emby SDK 发行包或仓库资源中获取：

```text
https://github.com/MediaBrowser/Emby.SDK/releases
https://github.com/MediaBrowser/Emby.SDK/tree/master/Resources/OpenApi
```

## API 基础路径

Emby API 通常通过服务器地址直接访问：

```text
http[s]://host:port/{apiPath}
```

旧 Wiki 中也提到过带 `/emby/{apiPath}` 的形式：

```text
http[s]://hostname:port/emby/{apiPath}
```

实际使用时要看服务器是否部署在子路径下。本项目的 `EmbyApi.normalizeServerUrl` 会保留非 Web 客户端路径，例如：

```text
https://host.example.test/emby
```

但会去掉从浏览器复制来的 Web UI 路径：

```text
/web
/web/index.html
```

## 鉴权方式

Emby 常见鉴权有两类：

1. 用户登录鉴权：适合客户端 App，用户输入用户名密码获取 `AccessToken`。
2. API Key 鉴权：适合集成服务或后台任务。

本项目采用用户登录鉴权。

### 登录

本项目使用：

```text
POST /Users/AuthenticateByName
```

请求体：

```json
{
  "Username": "用户名",
  "Pw": "密码"
}
```

请求头：

```text
X-Emby-Authorization: MediaBrowser Client=Fly Player, Device=Flutter, DeviceId=fly-player, Version=1.0.0
Accept: application/json
Content-Type: application/json
```

返回中取：

```text
AccessToken
User.Id
User.Name
ServerName
```

### 后续请求

本项目大多数请求使用 query 参数：

```text
api_key={AccessToken}
```

会话类接口额外携带：

```text
X-Emby-Authorization: MediaBrowser Client=Fly Player, Device=Flutter, DeviceId=fly-player, Version=1.0.0
```

这个头在 `/Sessions/Playing` 系列接口里很重要。项目实测注释里记录：只带 `api_key` 可能无法建立播放会话，导致续播进度不落库。

## FNOS 中转特殊处理

本项目支持通过飞牛 FN Connect 中转访问 Emby。

当 Emby 地址是 `*.fnos.net` 中转域名时，需要额外带：

```text
Cookie: entry-token={入口令牌}
```

项目中由 `EmbyApi` 的请求拦截器动态注入。注意：

1. 这个 cookie 不是 Emby 官方 API 的标准鉴权。
2. 它是飞牛中转网关需要的入口令牌。
3. 直连 Emby 地址时不需要带。
4. 视频直链是字符串拼接，不经过 Dio 拦截器，所以播放层需要另外传播放 headers。

相关工具：

```text
lib/utils/nas_image_headers.dart
```

## 本项目当前接入的 Emby API

本项目封装入口：

```text
lib/api/emby_api.dart
```

### 系统信息

| 功能 | 方法 | 路径 | 封装方法 |
|---|---:|---|---|
| 公共系统信息 | GET | `/System/Info/Public` | `getPublicSystemInfo` |

用途：

1. 登录前探测服务器是否可达。
2. 获取服务器名称 `ServerName`。

### 登录

| 功能 | 方法 | 路径 | 封装方法 |
|---|---:|---|---|
| 用户名密码登录 | POST | `/Users/AuthenticateByName` | `authenticateByName` |

返回模型：

```text
EmbyAuthenticateResult
```

字段：

```text
serverUrl
serverName
accessToken
userId
userName
```

### 媒体库视图

| 功能 | 方法 | 路径 | 封装方法 |
|---|---:|---|---|
| 当前用户媒体库 | GET | `/Users/{userId}/Views` | `getUserViews` |

返回：

```text
Items[]
```

这里的 `Items` 是 Emby 的 `BaseItemDto` 原始 Map，本项目在 media backend 层再转为统一模型。

### 条目列表

| 功能 | 方法 | 路径 | 封装方法 |
|---|---:|---|---|
| 条目列表 | GET | `/Users/{userId}/Items` | `getItems` |
| 条目分页 | GET | `/Users/{userId}/Items` | `getItemPage` |
| 条目计数 | GET | `/Users/{userId}/Items?Limit=0` | `getItemCount` |
| 单条详情 | GET | `/Users/{userId}/Items/{itemId}` | `getItem` |

常用 query 参数：

```text
api_key
ParentId
Limit
StartIndex
Recursive
IncludeItemTypes
Filters
Fields
SortBy
SortOrder
SearchTerm
Genres
PersonIds
```

本项目常用类型：

```text
Movie
Series
Season
Episode
Video
```

常用字段：

```text
Overview
Genres
People
ProviderIds
ProductionLocations
PremiereDate
CommunityRating
ItemCounts
UserData
MediaSources
MediaStreams
Path
ImageTags
BackdropImageTags
LogoImageTag
```

### 剧集

| 功能 | 方法 | 路径 | 封装方法 |
|---|---:|---|---|
| 系列的季列表 | GET | `/Shows/{seriesId}/Seasons` | `getSeasons` |

query 参数：

```text
api_key
UserId
Fields
```

本项目默认字段：

```text
ItemCounts,UserData
```

集列表目前通过通用 `/Users/{userId}/Items` 查询或 media backend 层组合完成，而不是单独封装 Emby 的每个 TV 专用端点。

### 题材

| 功能 | 方法 | 路径 | 封装方法 |
|---|---:|---|---|
| 题材列表 | GET | `/Genres` | `getGenres` |

query 参数：

```text
api_key
UserId
Recursive=true
SortBy=SortName
ParentId
IncludeItemTypes
```

### 继续观看

| 功能 | 方法 | 路径 | 封装方法 |
|---|---:|---|---|
| 继续观看 | GET | `/Users/{userId}/Items/Resume` | `getResumeItems` |

query 参数：

```text
api_key
Limit
Recursive=true
MediaTypes=Video
Fields
```

项目注释中说明：这个接口比 `/Items?Filters=IsResumable` 更适合作为首页继续观看来源。

### 视频直链

| 功能 | 方法 | 路径 | 封装方法 |
|---|---:|---|---|
| 静态视频直链 | GET | `/Videos/{itemId}/stream` | `buildStreamUrl` |
| 带容器后缀直链 | GET | `/Videos/{itemId}/stream.{container}` | `buildStreamUrl` |

query 参数：

```text
Static=true
MediaSourceId={mediaSourceId}
api_key={accessToken}
```

用途：

1. mpv 直接播放原文件。
2. 避免服务端转码。
3. 多版本条目通过 `MediaSourceId` 指定版本。

注意：

1. `buildStreamUrl` 只拼 URL，不发请求。
2. 如果走 `*.fnos.net` 中转，需要播放层额外传 `entry-token` cookie。
3. mpv 内部轨道选择依赖 Emby 返回的 `MediaSources/MediaStreams` 映射。

### 播放进度回传

| 功能 | 方法 | 路径 | 封装方法 |
|---|---:|---|---|
| 播放开始 | POST | `/Sessions/Playing` | `reportPlaybackStart` |
| 播放进度 | POST | `/Sessions/Playing/Progress` | `reportPlaybackProgress` |
| 播放停止 | POST | `/Sessions/Playing/Stopped` | `reportPlaybackStopped` |

query 参数：

```text
api_key={accessToken}
```

请求体核心字段：

```json
{
  "ItemId": "itemId",
  "MediaSourceId": "mediaSourceId",
  "PositionTicks": 123456789,
  "PlayMethod": "DirectStream",
  "CanSeek": true
}
```

`Progress` 额外带：

```json
{
  "IsPaused": false,
  "EventName": "TimeUpdate"
}
```

注意：

1. `PositionTicks` 是 100ns 单位。
2. 1 秒 = `10,000,000` ticks。
3. 必须先调用 `reportPlaybackStart` 建立播放会话，再回传 `Progress`，否则续播位可能不落库。
4. 会话接口建议携带 `X-Emby-Authorization`，否则部分版本可能无法正确建立客户端会话。

### 外挂字幕

| 功能 | 方法 | 路径 | 封装方法 |
|---|---:|---|---|
| 字幕直链 | GET | `/Videos/{itemId}/{mediaSourceId}/Subtitles/{index}/Stream.{ext}` | `buildSubtitleUrl` |
| 下载字幕文本 | GET | 同上 | `downloadSubtitleText` |

query 参数：

```text
api_key={accessToken}
```

参数说明：

```text
itemId        Emby 条目 ID
mediaSourceId 媒体源 ID
index         MediaStreams 中字幕流的 Index
ext           srt / ass / vtt 等目标格式
```

## 项目中间层映射

`EmbyApi` 保持低层封装，返回原始 `Map<String, Object?>`。实际转换为项目统一模型发生在 media backend 层：

```text
lib/media_backend/emby/
```

测试中可见图片 URL 格式：

```text
/Items/{itemId}/Images/Primary?tag={tag}&api_key={token}
/Items/{itemId}/Images/Backdrop?tag={tag}&api_key={token}
/Items/{itemId}/Images/Logo?tag={tag}&api_key={token}
```

这些图片接口目前多由 mapper 拼接，不在 `EmbyApi` 中显式封装。

## 与飞牛影视 API 的差异

Emby 是标准媒体服务器 API，飞牛影视是飞牛自己的媒体库 API。两者在概念上能映射，但字段完全不同。

| 概念 | Emby | 飞牛影视 |
|---|---|---|
| 登录 token | `AccessToken` | `token` / `Trim-MC-token` |
| API 前缀 | 无固定 `/v/api/v1`，直接按模块路径 | `/v/api/v1` |
| 用户库 | `/Users/{userId}/Views` | `/mediadb/list` |
| 列表 | `/Users/{userId}/Items` | `/item/list` |
| 详情 | `/Users/{userId}/Items/{itemId}` | `/item/{guid}` |
| 季 | `/Shows/{seriesId}/Seasons` | `/season/list/{guid}` |
| 播放 | `/Videos/{itemId}/stream` | `/stream`, `/play/play` |
| 播放回传 | `/Sessions/Playing*` | `/play/record` |
| 图片 | `/Items/{id}/Images/{type}` | 通常为服务端返回 poster path 或飞牛图片路径 |
| 字幕 | `/Videos/.../Subtitles/...` | `/subtitle/*` |

## 官方文档里值得优先看的服务

如果后续要补接口，建议先看这些官方分类：

| 官方服务 | 用途 |
|---|---|
| `SystemService` | 系统信息、公开信息 |
| `UserService` | 登录、用户信息 |
| `UserViewsService` | 当前用户媒体库视图 |
| `UserLibraryService` | 用户媒体库浏览 |
| `ItemsService` | 条目详情、列表查询 |
| `GenresService` | 题材 |
| `TvShowsService` | 剧集、季、集 |
| `ImageService` | 海报、背景、Logo |
| `VideosService` / `VideoService` | 视频流 |
| `SessionsService` | 播放会话、远程控制 |
| `PlaystateService` | 播放状态、已看、收藏等 |
| `SubtitleService` | 字幕流与字幕下载 |
| `MediaInfoService` | 播放信息、转码能力 |

## 后续可补接口建议

### P0：播放器体验

1. `POST /Items/{itemId}/PlaybackInfo`
2. `POST /Sessions/Playing/Ping`
3. `POST /Sessions/Playing/Stopped` 已有，可继续完善错误重试
4. `POST /Users/{userId}/PlayedItems/{itemId}`
5. `DELETE /Users/{userId}/PlayedItems/{itemId}`
6. `POST /Users/{userId}/FavoriteItems/{itemId}`
7. `DELETE /Users/{userId}/FavoriteItems/{itemId}`

说明：

当前项目直接拼静态播放 URL，适合 mpv 直链播放。若要更完整支持转码、码率选择、字幕/音轨服务端选择，需要研究 `PlaybackInfo`。

### P1：图片与缓存

1. 显式封装 `/Items/{itemId}/Images/{imageType}`
2. 支持 `Primary`、`Backdrop`、`Logo`、`Thumb`
3. 支持 `tag`、`maxWidth`、`maxHeight`、`quality`
4. 对 `*.fnos.net` 图片请求继续带 `entry-token`

### P2：条目状态

1. 已看/未看
2. 收藏/取消收藏
3. 用户评分
4. 清除续播位

这些能力应放在统一媒体后端抽象中，避免飞牛和 Emby 两套 UI 分裂。

### P3：管理能力

1. 刷新元数据
2. 识别/重新识别
3. 修改图片
4. 媒体库扫描
5. 任务状态

这些属于管理端功能，权限和破坏性更高，建议最后接。

## 接入注意事项

### 1. 不要把 `api_key` 打进日志

Emby 静态播放 URL 和图片 URL 都可能把 token 放在 query 中。日志打印 URL 时要脱敏。

### 2. `X-Emby-Authorization` 和 `api_key` 不是一回事

`api_key` 表示访问授权；`X-Emby-Authorization` 表示客户端身份。播放会话类接口最好两个都带。

### 3. `DeviceId` 应保持稳定

当前默认：

```text
fly-player
```

这对单设备开发能工作，但正式场景建议生成并持久化设备唯一 ID，否则多个设备可能在 Emby 会话里互相覆盖。

### 4. URL 子路径要保留

如果用户的 Emby 部署在：

```text
https://example.com/emby
```

请求应拼成：

```text
https://example.com/emby/Users/...
```

不能强行去掉 `/emby`。

### 5. FNOS 中转要区分 API 请求和播放直链

Dio API 请求可由拦截器自动加 `entry-token` cookie；播放 URL 是给 mpv 的，需要在播放 headers 里手动加。

## 建议的文档使用方式

1. 查完整官方接口：先看 `https://dev.emby.media/reference/RestAPI.html`。
2. 查本项目已接：看本文“本项目当前接入的 Emby API”。
3. 新增接口：优先在 `EmbyApi` 加低层方法，再在 `lib/media_backend/emby/` 做模型映射。
4. 写测试：参考 `test/api/emby_api_test.dart`、`test/api/emby_api_playback_test.dart`、`test/api/emby_api_catalog_test.dart`。

## 快速清单

当前本项目 Emby 后端已经能完成：

```text
登录
列出媒体库
首页分类预览
条目分页
搜索
题材筛选
详情页
季列表
继续观看
静态直链播放
播放进度回传
外挂字幕下载
海报/背景/Logo URL 拼接
```

尚未系统接入：

```text
PlaybackInfo
服务端转码播放
播放质量选择
收藏/已看状态写入
图片接口显式封装
元数据刷新
媒体库扫描
管理端任务
```
