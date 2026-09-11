# 飞牛音乐（trim.music）前后端交互 API 清单

> 来源：NAS `192.168.6.120`（飞牛 fnOS，主机名 geqian688）
> 提取方式：前端 JS 路由映射表与全部调用点参数 + 后端 Go 二进制路由字符串与 json 绑定标签 + Unix Socket 实测探测（三重交叉验证）
> 标注说明：✅=从前端调用点直接观测到；〰=根据命名规律/后端标签推断；—=无参数
> 整理日期：2026-09-06

## 一、整体架构

| 组件 | 说明 |
|------|------|
| 前端 | React + Semi Design（Vite 打包），位于 `/usr/local/apps/@appcenter/trim.music/static/` |
| 后端 | Go (gin) 单二进制 `trim-music`（35MB），监听 Unix Socket `/var/run/trim_music.socket` |
| 网关 | fnOS nginx：`location /music` → 转发到上述 socket（`/usr/trim/nginx/conf/conf.d/trim_music.conf`） |
| 数据 | SQLite（音乐库/歌词/搜索索引），配置见应用目录下 `sqlite*.sql` |

### 访问入口

- 内网直连：`http://192.168.6.120:5666/music/...`（HTTPS 为 5667）✅ 实测可达
- 经 fnOS 主网关（5005 端口）：同路径，但需 fnOS 登录态（未登录返回 401）
- 后端所有路由注册前缀为 `/music/api/v1/...`，下文路径均省略该前缀

### 统一响应格式

```json
{"code": 0, "msg": "", "data": {...}}      // 成功
{"code": 99999, "msg": "INVALID TOKEN", "data": null}   // 未登录/token 失效
{"code": 100001, "msg": "unknown error", "data": null}  // 业务错误（如登录失败）
```

业务错误类型枚举（前端错误映射表）：`Unknown`、`InvalidArgs`、`AdminRequired`、`Forbidden`、`NotFound`、`AppAlreadyInitialized`

### 通用请求参数（列表类接口）

| 字段 | 位置 | 说明 |
|------|------|------|
| `page` | query | 页码，从 1 开始 |
| `size` | query | 每页条数（响应中对应 `pageSize`/`limit`） |
| `sort` | query | 排序字符串，格式 `"<field>,<order>"`，如 `title,asc` |

**sort 可用 field（前端观测到的取值）**：`title` / `name`（名称）、`trackNumber`（曲目号）、`trackCount`（歌曲数）、`newTrackAddedAt`（最近加入时间）、`releaseYear`（发行年份）、`createdAt`（创建时间，专辑接口会映射为 `newTrackAddedAt`）
**order**：`asc` / `desc`

**列表类统一响应 data**：`{list: [...], total, page, pageSize(或limit), hasMore, appliedSort}`

### 鉴权机制

1. **主鉴权：Cookie `music-token`**（`Path=/; SameSite=Strict`），登录成功后设置，浏览器自动携带。
2. **OAuth 登录流**：fnOS 授权码（clientId=`EDDLUH2WLY`，从 `sys/config` 获取）+ deviceId → `POST /user/auth-login` → 返回 `userToken` + 用户信息。
3. **临时令牌**：Header `X-Trim-Music-Temp-Token`，用于分享/外部播放器场景，由 `POST /user/temp-token` 签发。
4. **URL 传 token**：后端支持 query 参数 `token`（二进制含 `tokenQuery`），用于 `<audio>` 标签等无法带 Header 的场景。
5. **deviceId**：32 位 hex 字符串（`crypto.randomUUID()` 去掉 `-`，不足补 0）。

### 无需鉴权的公开端点（实测确认）

`GET /sys/config`、`GET /initialization/state`、`POST /initialization/prepare`、`POST /initialization/confirm`、`POST /user/auth-login`、`POST /user/password-login`

---

## 二、API 分组明细（含请求字段）

### album（专辑）
| 方法 | 路径 | 请求字段 |
|------|------|------|
| GET | `/album/list` | query：`page` ✅、`size` ✅、`sort` ✅ |
| GET | `/album/detail` | query：`guid` ✅ |
| GET | `/album/artist-detail/list` | query：歌手 guid 〰、`page` `size` `sort` ✅（分页模式同上） |

### artist（歌手）
| 方法 | 路径 | 请求字段 |
|------|------|------|
| GET | `/artist/list` | query：`page` ✅、`size` ✅、`sort` ✅ |
| GET | `/artist/list-all` | — |
| GET | `/artist/detail` | query：`guid` ✅ |
| POST | `/artist/create` | body：`{name}` 〰（前端传表单对象，未观测到展开字段） |

### track（歌曲，核心）
| 方法 | 路径 | 请求字段 |
|------|------|------|
| GET | `/track/list` | query：`page` `size` `sort` ✅ |
| GET | `/track/metadata` | query：`guid` ✅ |
| GET | `/track/album-detail/list` | query：`albumGUID` ✅、`page` ✅、`size` ✅、`sort` ✅ |
| GET | `/track/artist-detail/list` | query：`artistGUID` 〰、`page` `size` `sort` ✅ |
| GET | `/track/genre-detail/list` | query：`genreGUID` 〰、`page` `size` `sort` ✅ |
| GET | `/track/playlist-detail/list` | query：`playlistGUID` ✅、`page` ✅、`size` `sort` ✅ |
| GET | `/track/audio-info` | query：`guid` 〰 |
| GET | `/track/stream` | query：`guid` ✅（前端拼 `?guid=<id>`；可选 `token` 〰；支持 Range） |
| GET | `/track/hls/{guid}/preset.m3u8` | path：`guid` ✅ |
| GET | `/track/roam-start` | query：`deviceId` ✅ |
| GET | `/track/roam-next` | query：`deviceId` ✅、`relativeRoamId` ✅ |
| GET | `/track/roam-previous` | query：`deviceId` ✅、`relativeRoamId` ✅ |
| POST | `/track/transcode` | body：`{guid}` ✅、`{output}` ✅；`output` = `{...音质映射字段, channel}` ✅（音质字段含 `format`/`bitrate`/`quality` 〰，json 标签确认存在；`channel` 为声道数）。响应：`{status: ok\|failed, errmsg, errno}` ✅ |
| POST | `/track/transcode/heartbeat` | body：`{guid}` ✅、`{timestamp}` ✅ |
| POST | `/track/transcode/quit` | body：`{guid}` ✅ |
| POST | `/track/delete` | body：`{guid}` + `{isPermanent}` 〰（后端 form 标签存在 `isPermanent`） |
| POST | `/track/recover` | body：`{guid}` 〰 |

音频编解码枚举（转码/播放协商用）：`aac`、`mp3`、`ac3`、`eac3`、`dts`、`flac` 等

### genre（流派）
| 方法 | 路径 | 请求字段 |
|------|------|------|
| GET | `/genre/list` | query：`page` `size` `sort` ✅ |
| GET | `/genre/detail` | query：`guid` ✅ |
| POST | `/genre/create` | body：`{name}` 〰 |

### lyric（歌词）
| 方法 | 路径 | 请求字段 |
|------|------|------|
| GET | `/lyric/list` | query：`trackGUID` ✅ |

### favorite-track（收藏）
| 方法 | 路径 | 请求字段 |
|------|------|------|
| GET | `/favorite-track/list` | query：`page` ✅、`size` ✅、`sort` ✅ |
| POST | `/favorite-track/create` | body：`{trackGUID}` ✅ |
| POST | `/favorite-track/delete` | body：`{trackGUID}` ✅ |
| POST | `/favorite-track/purge-track` | body：`{trackGUID}` 〰 |
| GET | `/favorite-track/purge-track-count` | — |

### playlist（歌单）
| 方法 | 路径 | 请求字段 |
|------|------|------|
| GET | `/playlist/list` | — ✅ |
| GET | `/playlist/detail` | query：`guid` ✅ |
| GET | `/playlist/batch-detail` | query：`guids` ✅（**逗号分隔字符串**，前端 `guids.join(',')`） |
| POST | `/playlist/create` | body：`{name, ...}` ✅（表单对象，完整字段未观测） |
| POST | `/playlist/edit` | body：`{guid}` ✅ + 同 create 的字段 ✅ |
| POST | `/playlist/delete` | body：`{guid}` ✅ |
| POST | `/playlist/add-track` | body：`{guid}` ✅（歌单 guid）、`{trackGUIDs: []}` ✅（数组） |
| POST | `/playlist/remove-track` | body：`{guid}` ✅、`{trackGUIDs: []}` ✅ |
| POST | `/playlist/purge-track` | body：`{guid}` ✅ |
| GET | `/playlist/purge-track-count` | — |

### play-history（播放历史）
| 方法 | 路径 | 请求字段 |
|------|------|------|
| GET | `/play-history/list` | query：`page` ✅、`size` ✅（`sort` 〰） |
| POST | `/play-history/delete` | body：`{trackGUIDs: []}` ✅（数组） |

### search（搜索）
| 方法 | 路径 | 请求字段 |
|------|------|------|
| GET | `/search/track` | query：`q` ✅（关键词）、`page` ✅、`size` ✅ |
| GET | `/search/album` | query：`q` ✅、`page` ✅、`size` ✅ |
| GET | `/search/artist` | query：`q` ✅、`page` ✅、`size` ✅ |
| GET | `/search/playlist` | query：`q` ✅、`page` ✅、`size` ✅ |
| GET | `/search/suggest` | query：`q` ✅ |
| POST | `/search/index/rebuild` | — |

### shared-library（音乐库管理，设置页）
| 方法 | 路径 | 请求字段 |
|------|------|------|
| GET | `/shared-library/list` | — ✅ |
| GET | `/shared-library/detail` | query：`guid` ✅ |
| POST | `/shared-library/create` | body：`{path}` ✅、`{autoDownloadLyric}` ✅（bool）、`{metadataPreference}` ✅ |
| POST | `/shared-library/edit` | body：`{guid}` ✅、`{path}` ✅、`{autoDownloadLyric}` ✅、`{metadataPreference}` ✅ |
| POST | `/shared-library/delete` | body：`{guid}` ✅ |
| POST | `/shared-library/scan` | body：`{guid}` ✅ |
| POST | `/shared-library/scan-all` | — ✅ |

`metadataPreference` 枚举：`CloudPreferred`（云端优先）/ `LocalOnly`（仅本地）

### settings（设置）
| 方法 | 路径 | 请求字段 |
|------|------|------|
| GET | `/settings/server` | — ✅（返回 `{name, lang}` ✅） |
| POST | `/settings/server` | body：`{name}` ✅、`{lang}` ✅ |
| GET | `/settings/user` | — ✅（返回默认权限 `defaultSharedLibraryAccess`） |
| POST | `/settings/user` | body：`{defaultSharedLibraryAccess: {mode, guids}}` ✅；`mode` 枚举：`all` / `partial` / `none`，`partial` 时 `guids` 为音乐库 guid 数组 ✅ |

### user（用户与登录）
| 方法 | 路径 | 请求字段 |
|------|------|------|
| POST | `/user/auth-login` | 🔓 body：`{code}` ✅（fnOS OAuth 授权码）、`{deviceId}` ✅。响应：`{userToken, user}` ✅ |
| POST | `/user/password-login` | 🔓 body：`{username}` ✅、`{password}` ✅（实测字段确认，凭据错误返回 100001） |
| GET | `/user/me` | — ✅ |
| POST | `/user/logout` | — ✅ |
| GET | `/user/exists` | query：`username` ✅（响应含 `isExist` ✅） |
| GET | `/user/list` | — ✅（管理员） |
| POST | `/user/create` | body：`{username}` ✅、`{password}` ✅、`{sharedLibraryAccess: {mode, guids}}` ✅ |
| POST | `/user/edit` | body：`{guid}` ✅、`{username}` ✅、`{password}` ✅（可选，改密码时才传）、`{sharedLibraryAccess}` ✅ |
| POST | `/user/delete` | body：`{guid}` ✅ |
| POST | `/user/passwd-change` | body：`{password}` ✅ |
| POST | `/user/unbanned` | body：`{guid}` ✅ |
| POST | `/user/temp-token` | body：（签发临时令牌；参数未观测，前端 Web 未调用）—；配套 Header `X-Trim-Music-Temp-Token` |

### app-center（fnOS 应用中心联动）
| 方法 | 路径 | 请求字段 |
|------|------|------|
| GET | `/app-center/authed-dir/list` | — ✅ |
| GET | `/app-center/authed-dir/sub/list` | query：`parent` ✅（父目录路径） |
| POST | `/app-center/authed-dir/sub/create` | body：`{parent}` 〰（json 标签确认）+ 子目录信息 |

### task（后台任务）
| 方法 | 路径 | 请求字段 |
|------|------|------|
| GET | `/task/list` | — ✅ |
| POST | `/task/cancel` | body：`{taskId}` ✅ |
| POST | `/task/delete` | body：`{taskId}` ✅ |
| POST | `/task/retry` | body：`{taskId}` ✅ |

### static（静态资源）
| 方法 | 路径 | 请求字段 |
|------|------|------|
| GET | `/static/cover` | query：`coverId` ✅、`size` ✅（可选，数字） |
| POST | `/static/cover/track` | body：批量 cover 查询（字段未观测） |
| POST | `/static/cover/playlist` | body：批量 cover 查询（字段未观测） |

### download（下载）
| 方法 | 路径 | 请求字段 |
|------|------|------|
| GET | `/download/track` | query：`guid` 〰（Web 前端未调用，参数为推断；后端含 `quality`/`bitrate`/`format` json 标签） |
| GET | `/download/track/detail` | query：`guid`/任务 id 〰 |
| POST | `/download/track/transcode/prepare` | body：`{guid, quality/format, bitrate}` 〰 |
| GET | `/download/track/transcode/file` | query：任务 id 〰 |
| GET | `/download/track/transcode/status` | query：任务 id 〰 |
| POST | `/download/track/transcode/delete` | body：任务 id 〰 |

### sys / event / folder-view（系统与上报）
| 方法 | 路径 | 请求字段 |
|------|------|------|
| GET | `/sys/config` | 🔓 —。响应：`{nasOAuth:{clientId:"EDDLUH2WLY"}, serverGUID, serverName, serverVersion, mediasrvVersion}` ✅ |
| GET | `/sys/info` | — |
| POST | `/event/report` | body：`{events: [ {eventType, occurredAt, payload} ]}` ✅（数组可批量，navigator.sendBeacon 亦走此接口），事件类型见下表 |
| GET | `/folder-view/list` | query：`path` 〰（Web 前端未调用） |

**event.report 事件类型与 payload**（前端枚举实测）：

| eventType | payload |
|-----------|---------|
| `track_play`（播放） | `{trackGUID}` ✅，`occurredAt` 为开始时间戳 |
| `lyric_offset_change`（歌词偏移调整） | `{trackGUID, lyricGUID, offset}` ✅（offset 单位毫秒，取整） |
| `lyric_preference_change`（歌词偏好） | 〰（同上结构） |
| `sorting_change`（列表排序变更） | `{id, sorting}` ✅ |

---

## 三、云端适配器接口（后端作为客户端调用飞牛官方云）

这些路径在后端二进制中注册，但**不走本地路由**（实测返回静态回退），是元数据刮削的云端适配器：

- `/api/v1/search/tracks/best` — 云端歌曲最佳匹配
- `/api/v1/search/lyrics/best` — 云端歌词最佳匹配
- `/api/v1/detail/album/`、`/api/v1/detail/artist/`、`/api/v1/detail/lyrics/` — 云端详情
- `/api/v1/rejudge/album` — 专辑元数据重新判定（纠错）

> 二进制内证据：`official api adapter[searchTracks]`、`[searchLyrics]`、`[rejudgeAlbum]`、`cloud api default adapter initialized, baseURL=%s`

## 四、其他说明

1. **前端 JS 中还出现** `/api/stream/info?fileId=...`、`/api/stream/hls?fileId=...&bitrate=...&format=aac`、`/api/stream/unified?fileId=...&quality=...`、`/stream/audio`、`/stream/pcm` —— 这些指向 fnOS 媒体服务（mediasrv，版本 0.8.41）体系的外链/云盘文件流，不是 trim-music 本体路由（实测本机无此路由）。
2. **开发者接口**：二进制含 `/music/__dev` 前缀与 `app.enable-dev-apis` 配置项，仅在开启 dev 模式时注册。
3. **字段命名核对**：后端 Go json 绑定标签与前端字段完全一致（已核对 `guid/guids/parent/username/password/autoDownloadLyric/metadataPreference/trackGUID/lyricGUID/deviceId/taskId/events/payload/offset/output/quality/bitrate/channel/coverId/size/sort/token/isPermanent` 等）。
4. **方法探测方法说明**：所有路由的存在性与 HTTP 方法通过 Unix socket 实测验证——返回 JSON（401 INVALID TOKEN）= 路由存在且方法正确；返回 HTML = 方法/路径不匹配（回落到 SPA 静态页）。
5. **实测示例**（可直接在浏览器/内网验证）：

```bash
# 公开配置（无需登录）
curl "http://192.168.6.120:5666/music/api/v1/sys/config"

# 未带 token 调受保护接口 → {"code":99999,"msg":"INVALID TOKEN"}
curl "http://192.168.6.120:5666/music/api/v1/track/list?page=1&size=30&sort=title,asc"

# 登录拿 token（音乐应用自有账号）
curl -X POST "http://192.168.6.120:5666/music/api/v1/user/password-login" \
  -H "Content-Type: application/json" \
  -d '{"username":"<音乐应用账号>","password":"<密码>"}'

# 带 token 请求（Cookie 方式）
curl "http://192.168.6.120:5666/music/api/v1/track/list?page=1&size=30" \
  -H "Cookie: music-token=<token>"

# 音频流（同样支持 token query 参数）
curl "http://192.168.6.120:5666/music/api/v1/track/stream?guid=<歌曲guid>&token=<token>"
```
