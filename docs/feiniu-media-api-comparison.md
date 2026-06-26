# 飞牛影视 API 对比参考

本文档记录飞牛影视官方前端/后端接口与本项目 `FeiniuApi` 封装的对比结果，用于后续补齐 API、排查字段差异、设计 Flutter 端功能。

## 调研来源

当前调研基于 NAS 本机应用包和本项目源码。

官方飞牛影视服务：

```text
/var/apps/trim.media
/var/apps/trim.media/target -> /usr/local/apps/@appcenter/trim.media
/var/apps/trim.media/var    -> /usr/local/apps/@appdata/trim.media
```

官方服务进程：

```text
/usr/local/apps/@appcenter/trim.media/trim-media
  --port=8005
  --root=/usr/local/apps/@appdata/trim.media
  --meta=/vol1/@appmeta/trim.media
  --static=/usr/local/apps/@appcenter/trim.media
  --trim-appname=trim.media
  --trim-username=trim-media
  --log-dir=/usr/local/apps/@appdata/trim.media/logs
```

官方前端主要打包文件：

```text
/usr/local/apps/@appcenter/trim.media/static/assets/14a77ac952fc83b785b65592c335e16d-DZucoFP3.js
```

本项目封装入口：

```text
lib/api/feiniu_api.dart
```

## 基础结论

官方前端和本项目都使用同一套核心 API 前缀：

```text
/v/api/v1
```

官方前端打包代码中可见如下运行时常量：

```js
sh = "/v"
$ = "/v/api/v1"
```

本项目中对应常量：

```dart
static const String _apiPrefix = '/v/api/v1';
```

因此，本项目当前并不是另造了一套协议，而是在复用飞牛影视官方 API。差异主要在于：

1. 本项目只接入了播放器核心链路。
2. 官方前端还包含媒体库管理、刮削重扫、手动编辑、字幕上传、任务调度、系统设置、用户管理等后台能力。
3. 部分官方接口存在 `v2 channel` 或管理端路径，本项目暂未封装。

## 鉴权与请求头

官方前端可见：

```text
Trim-MC-token
Authorization
Authx
```

本项目请求拦截器当前会在登录后为常规 API 添加：

```dart
options.headers['Authorization'] = nasProvider.token;
options.headers['Trim-MC-token'] = nasProvider.token;
```

并在特定路径上添加：

```dart
options.headers['Authx'] = _buildAuthxHeader(options);
```

结论：

| 项目 | 官方前端 | 本项目 | 说明 |
|---|---|---|---|
| API 前缀 | `/v/api/v1` | `/v/api/v1` | 一致 |
| 登录 token | `Trim-MC-token` cookie/header | `Authorization` + `Trim-MC-token` header | 基本兼容 |
| 上传图片/字幕 | `Authorization` | 已用于普通请求；字幕上传暂未接入 | 后续上传功能需保留 `Authorization` |
| 公共签名 | `Authx` | 已实现 `_buildAuthxHeader` | 用于部分公开/特殊接口 |

## 响应结构

从本项目现有解析方式看，飞牛影视常规接口响应多为统一包裹结构：

```json
{
  "code": 0,
  "msg": "...",
  "data": {}
}
```

本项目已有的解析工具包括：

```text
_extractDataMap(...)
_extractDataList(...)
_requireSuccessPayload(...)
```

新增接口时建议继续复用这些解析方法，除非官方接口返回二进制、文件流、图片、字幕文本或特殊下载流。

## 本项目已接入接口

### 登录与用户数据

| 功能 | 方法 | 路径 | 本项目方法 |
|---|---:|---|---|
| 登录 | POST | `/v/api/v1/login` | `login`, `loginWithBaseUrl` |
| OAuth/Auth | POST | `/v/api/v1/auth` | `loginWithFnConnectOauthCode` |
| 用户信息 | GET | `/v/api/v1/user/info` | `getUserInfo` |
| 读取用户数据 | POST | `/v/api/v1/user/getData` | `getUserDataEntry`, `getUserDataJsonValue` |
| 写入用户数据 | POST | `/v/api/v1/user/setData` | `setUserDataValue`, `setUserDataJsonValue` |

### 首页与媒体库

| 功能 | 方法 | 路径 | 本项目方法 |
|---|---:|---|---|
| 媒体库列表 | GET | `/v/api/v1/mediadb/list` | `getMediaList` |
| 媒体库汇总 | GET | `/v/api/v1/mediadb/sum` | `getMediaSummary` |
| 授权目录 | GET | `/v/api/v1/server/getAppAuthorizedDir` | `getAppAuthorizedDirs` |
| 服务信息 | GET | `/v/api/v1/server/info` | `getServerInfo` |
| 系统配置 | GET | `/v/api/v1/sys/config` | `getSystemConfig` |
| 系统版本 | GET | `/v/api/v1/sys/version` | `getSystemVersion` |

### 列表、搜索与标签

| 功能 | 方法 | 路径 | 本项目方法 |
|---|---:|---|---|
| 搜索 | GET | `/v/api/v1/search/list` | `searchList` |
| 项目列表 | POST | `/v/api/v1/item/list` | `getItemsPage`, `getItemsPageByRequest` |
| 收藏列表 | POST | `/v/api/v1/favorite/list` | `getFavoritePage` |
| 标签列表 | GET | `/v/api/v1/tag/list` | `getTagList` |
| 类型标签 | GET | `/v/api/v1/tag/genres` | `getTagGenresMap` |
| 国家/地区标签 | GET | `/v/api/v1/tag/iso3166` | `getTagIso3166Map` |
| 语言标签 | GET | `/v/api/v1/tag/iso6392` | `getTagIso6392Map` |

### 详情、剧集与人物

| 功能 | 方法 | 路径 | 本项目方法 |
|---|---:|---|---|
| 项目详情 | GET | `/v/api/v1/item/:guid` | `getItemDetail` |
| 季列表 | GET | `/v/api/v1/season/list/:guid` | `getSeasonList` |
| 集列表 | GET | `/v/api/v1/episode/list/:guid` | `getEpisodeList` |
| 流列表 | GET | `/v/api/v1/stream/list/:guid` | `getStreamTrackData` |
| 演职员 | POST | `/v/api/v1/person/list/:guid` | `getPersonList` |
| 人物详情 | GET | `/v/api/v1/person/:guid` | `getPersonDetail` |
| 人物作品 | POST | `/v/api/v1/person/item/list` | `getPersonItemList` |

### 播放与观看记录

| 功能 | 方法 | 路径 | 本项目方法 |
|---|---:|---|---|
| 播放列表 | GET | `/v/api/v1/play/list` | `getPlayList` |
| 播放信息 | POST | `/v/api/v1/play/info` | `getPlayInfo` |
| 创建播放会话 | POST | `/v/api/v1/play/play` | `createServerPlaySession` |
| 获取播放串流 | POST | `/v/api/v1/stream` | `getPlaybackStream` |
| 播放记录 | POST | `/v/api/v1/play/record` | `recordPlayback`, `resetPlaybackRecord` |
| 删除播放记录 | DELETE | `/v/api/v1/play/record` | `deletePlaybackRecord` |
| 播放配置 | POST | `/v/api/v1/play/setConfigByItem` | `setPlayConfigByItem` |
| 播放桥接 | POST | `/v/api/v1/media/p` | `checkPlayLinkExpired` 等 |
| 媒体文件信息 | GET | `/v/api/v1/mediadb/stream/metadata` | `getStreamMetadata` |

### 收藏、看过、下载与字幕

| 功能 | 方法 | 路径 | 本项目方法 |
|---|---:|---|---|
| 收藏 | PUT/DELETE | `/v/api/v1/item/favorite` | `setFavorite` |
| 看过 | POST/DELETE | `/v/api/v1/item/watched` | `setWatched` |
| 下载清晰度 | GET | `/v/api/v1/download/resolution/:guid` | `getDownloadResolutionOptions` |
| 创建下载任务 | PUT | `/v/api/v1/download/task` | `createDownloadTask` |
| 下载进度 | GET | `/v/api/v1/download/taskProgress` | `getDownloadTaskProgress` |
| 删除下载任务 | DELETE | `/v/api/v1/download/task/:taskId` | `deleteDownloadTask` |
| 字幕搜索 | POST | `/v/api/v1/subtitle/search` | `searchRemoteSubtitles` |
| 字幕下载到媒体库 | POST | `/v/api/v1/subtitle/download` | `downloadRemoteSubtitle` |
| 字幕文本下载 | GET | `/v/api/v1/subtitle/dl/:guid` | `downloadSubtitleText` |
| 删除字幕 | DELETE | `/v/api/v1/subtitle/del` | `deleteSubtitle` |

## 官方前端存在但本项目暂未接入的接口

以下接口来自官方前端打包路由和后端二进制字符串。实际参数需要在接入前通过浏览器 DevTools 或抓日志再次确认。

### 媒体库管理 `/mdb/*`

| 功能 | 方法 | 路径 | 用途推测 |
|---|---:|---|---|
| 扫描指定媒体库 | POST | `/v/api/v1/mdb/scan/:guid` | 后台触发媒体库扫描 |
| 扫描全部媒体库 | POST | `/v/api/v1/mdb/scanall` | 全库扫描 |
| 创建媒体库 | PUT | `/v/api/v1/mdb/create` | 新建媒体库配置 |
| 更新媒体库 | POST | `/v/api/v1/mdb/:guid` | 修改媒体库配置 |
| 删除媒体库 | DELETE | `/v/api/v1/mdb/:guid` | 删除媒体库配置 |
| 媒体库列表 | GET | `/v/api/v1/mdb/list` | 管理端媒体库列表 |
| 媒体库详情 | GET | `/v/api/v1/mdb/:guid` | 管理端详情 |
| 设置排序 | POST | `/v/api/v1/mdb/setSort` | 媒体库排序 |
| 获取海报 | POST | `/v/api/v1/mdb/getPoster` | 媒体库海报 |
| 设置海报 | POST | `/v/api/v1/mdb/setPoster` | 修改媒体库海报 |
| 刷新媒体库 | POST | `/v/api/v1/mdb/refresh` | 重新刷新配置/资源 |
| IPTV 临时上传 | POST | `/v/api/v1/mdb/iptv/temp/upload` | IPTV 相关 |

### 刮削与重识别 `/scrap/*`

| 功能 | 方法 | 路径 | 用途推测 |
|---|---:|---|---|
| 搜索刮削结果 | POST | `/v/api/v1/scrap/search` | 手动识别时搜索候选 |
| 重新刮削 | POST | `/v/api/v1/scrap/rescrap` | 对单个项目重刮 |
| 取消刮削/解除识别 | DELETE | `/v/api/v1/scrap/:guid` | 移除识别结果 |
| 按路径移出黑名单 | POST | `/v/api/v1/scrap/removeFromBlackByPath` | 修正误黑名单 |
| 批量重新刮削 | POST | `/v/api/v1/scrap/rescrap/batch` | 批量重刮 |

这些接口对“App 内手动修刮削”很有价值，建议后续优先研究。

### 项目编辑与刷新

| 功能 | 方法 | 路径 | 本项目状态 |
|---|---:|---|---|
| 当前播放状态 | GET/POST | `/v/api/v1/item/:guid/playing` | 未接 |
| 获取编辑详情 | POST | `/v/api/v1/item/getEditDetail` | 未接 |
| 保存编辑详情 | POST | `/v/api/v1/item/saveEditDetail` | 未接 |
| 刷新条目 | POST | `/v/api/v1/item/refresh` | 未接 |
| 批量媒体信息 | POST | `/v/api/v1/item/media/batch` | 未接 |
| 文件条目详情 | GET | `/v/api/v1/itemfile/:guid` | 未接 |
| 删除条目 | DELETE | `/v/api/v1/item/:guid` | 未接 |

### 人物编辑与搜索

| 功能 | 方法 | 路径 | 本项目状态 |
|---|---:|---|---|
| 刷新人物 | POST | `/v/api/v1/person/refresh` | 未接 |
| 获取人物编辑详情 | POST | `/v/api/v1/person/getEditDetail` | 未接 |
| 保存人物编辑详情 | POST | `/v/api/v1/person/saveEditDetail` | 未接 |
| 搜索人物 | POST | `/v/api/v1/person/search` | 未接 |
| 创建人物 | POST | `/v/api/v1/person/create` | 未接 |

### 播放增强

| 功能 | 方法 | 路径 | 本项目状态 |
|---|---:|---|---|
| 设置播放质量 | POST | `/v/api/v1/play/quality` | 未接 |
| 重置清晰度 | POST | `/v/api/v1/media/p` | 部分接入 |
| 重置音轨 | POST | `/v/api/v1/media/p` | 可复用桥接，但未显式封装 |
| 重置字幕 | POST | `/v/api/v1/media/p` | 可复用桥接，但未显式封装 |
| 退出播放 | POST | `/v/api/v1/media/p` | 可复用桥接，但未显式封装 |
| 转码统计 | POST | `/v/api/v1/media/p` | 未接 |

官方前端把多种播放控制都复用到 `/media/p`，通过请求体中的 `req` 区分动作。本项目已有 `checkPlayLinkExpired` 使用该桥接方式，后续可扩展。

### 字幕增强

| 功能 | 方法 | 路径 | 本项目状态 |
|---|---:|---|---|
| 预下载字幕 | POST | `/v/api/v1/subtitle/predownload` | 未接 |
| 标记字幕 | PUT | `/v/api/v1/subtitle/mark` | 未接 |
| 上传字幕 | POST | `/v/api/v1/subtitle/upload/:media_guid` | 未接 |

官方上传字幕前端片段显示上传请求使用 `FormData`，并显式添加：

```js
headers: { Authorization: token }
```

Flutter 接入建议使用 `MultipartFile`，并保留现有 token header。

### 系统与图片

| 功能 | 方法 | 路径 | 本项目状态 |
|---|---:|---|---|
| 初始化 | PUT | `/v/api/v1/sys/init` | 未接 |
| 选项 | GET | `/v/api/v1/sys/options` | 未接 |
| 图片 | GET | `/v/api/v1/sys/img` | 未接 |
| 远程图片/重定向图片 | GET | `/v/api/v1/sys/rimg` | 未接 |
| 进度缩略图 | GET | `/v/api/v1/sys/progressThumb` | 未接 |

当前项目图片下载主要走服务端返回的 poster path，再用 `downloadImageBytes` 拉取。若要完全复刻官方图片体验，需要进一步比较 `/sys/img`、`/sys/rimg`、`/sys/progressThumb` 的参数。

### 服务端设置

| 功能 | 方法 | 路径 | 本项目状态 |
|---|---:|---|---|
| 更新服务信息 | POST | `/v/api/v1/server/info` | 未接 |
| GPU 列表 | GET | `/v/api/v1/server/gpu/list` | 未接 |
| 路径选择 | POST | `/v/api/v1/server/path` | 未接 |
| 存储池 | GET | `/v/api/v1/server/pools` | 未接 |
| OAuth 状态 | GET | `/v/api/v1/server/oauthStatus` | 未接 |
| 全部卷 | GET | `/v/api/v1/server/allVols` | 未接 |

这些接口更偏后台配置，不是播放器主流程。只有在 App 内做媒体库管理时才需要接。

### 标签与自定义分类

| 功能 | 方法 | 路径 | 本项目状态 |
|---|---:|---|---|
| ISO 639-1 语言 | GET | `/v/api/v1/tag/iso6391` | 未接 |
| 创建自定义标签 | POST | `/v/api/v1/tag/custom/create` | 未接 |
| 批量自定义类型 | POST | `/v/api/v1/tag/custom/genres/batch` | 未接 |

本项目目前已有 `iso6392`。如果只用于字幕语言，`iso6392` 通常够用；如果官方筛选 UI 使用二字母语言码，则需要补 `iso6391`。

### 任务管理

| 功能 | 方法 | 路径 | 本项目状态 |
|---|---:|---|---|
| 运行中任务 | GET | `/v/api/v1/task/running` | 已接 |
| 计划任务列表 | GET | `/v/api/v1/task/schedule/list` | 未接 |
| 获取计划设置 | POST | `/v/api/v1/task/schedule/getSetting` | 未接 |
| 设置计划任务 | POST | `/v/api/v1/task/schedule/set` | 未接 |
| 停止任务 | POST | `/v/api/v1/task/stop` | 未接 |
| 无用任务列表 | GET | `/v/api/v1/task/uselessList` | 未接 |
| 清理无用任务 | POST | `/v/api/v1/task/removeUseless` | 未接 |

### 用户与管理模板

| 功能 | 方法 | 路径 | 本项目状态 |
|---|---:|---|---|
| 用户名密码登录 v2 | POST | `/v/api/v1/user/loginByPassword` | 未接 |
| 登出 | POST | `/v/api/v1/user/logout` | 未接 |
| 更新当前用户信息 | POST | `/v/api/v1/user/info` | 未接 |
| 修改密码 | POST | `/v/api/v1/user/passwd` | 未接 |
| 创建用户 | PUT | `/v/api/v1/manager/user/create` | 未接 |
| 用户列表 | GET | `/v/api/v1/manager/user/list` | 未接 |
| 更新用户 | POST | `/v/api/v1/manager/user/:guid` | 未接 |
| 删除用户 | DELETE | `/v/api/v1/manager/user/:guid` | 未接 |
| 解锁用户 | POST | `/v/api/v1/manager/user/unlock` | 未接 |
| 默认权限模板 | GET | `/v/api/v1/manager/template/permission` | 未接 |
| 更新默认权限模板 | POST | `/v/api/v1/manager/template/permission` | 未接 |

这些属于管理端能力，普通播放器不需要优先接入。

## 本项目存在但官方静态路由表不明显的接口

| 路径 | 说明 |
|---|---|
| `/v/api/v1/auth` | 官方用户路由表中存在 `auth`，但常规前端登录更多使用 `/login`、`/user/loginByPassword` |
| `/v/api/v1/download/resolution` | 后端二进制可见 download route，官方静态片段未完整展开 |
| `/v/api/v1/download/task` | 同上 |
| `/v/api/v1/download/taskProgress` | 同上 |
| `/v/api/v1/mediadb/stream/metadata` | 本项目用于文件媒体信息，官方静态路由表未直接显示 |
| `/v/api/v1/media/p` | 官方前端用于多种播放桥接动作，本项目只封装了部分 |

这类接口不能简单认为“非官方”，更可能是官方前端按模块懒加载、压缩后未被简表完全展开，或由后端二进制路由提供但 UI 使用较少。

## 接入优先级建议

### P0：播放器体验直接相关

1. `/play/quality`
2. `/media/p` 的 resetQuality/resetAudio/resetSubtitle/quit/transcodeStatis
3. `/subtitle/upload/:media_guid`
4. `/subtitle/mark`
5. `/subtitle/predownload`
6. `/sys/progressThumb`

这些可以增强播放页、字幕页、清晰度切换和进度条预览。

### P1：修刮削与媒体信息维护

1. `/scrap/search`
2. `/scrap/rescrap`
3. `/scrap/rescrap/batch`
4. `/item/getEditDetail`
5. `/item/saveEditDetail`
6. `/item/refresh`
7. `/person/search`
8. `/person/refresh`

这些适合做“在 App 内修正识别结果”的功能。

### P2：媒体库后台管理

1. `/mdb/list`
2. `/mdb/scan/:guid`
3. `/mdb/scanall`
4. `/mdb/create`
5. `/mdb/:guid`
6. `/server/path`
7. `/server/allVols`
8. `/server/pools`

这些适合做媒体库管理页。如果 App 定位仍是播放器，可以暂缓。

### P3：管理员与系统设置

1. `/manager/user/*`
2. `/manager/template/permission`
3. `/sys/init`
4. `/sys/options`
5. `/task/schedule/*`

这些风险较高，需要权限判断、错误处理、二次确认和较完整 UI。

## Flutter 端新增接口建议

### 代码位置

继续放在：

```text
lib/api/feiniu_api.dart
```

模型建议放在：

```text
lib/models/
```

如果新增功能较多，建议按模块拆分：

```text
lib/api/feiniu_media_admin_api.dart
lib/api/feiniu_scrap_api.dart
lib/api/feiniu_subtitle_api.dart
```

但短期内为了复用 token、Authx、baseUrl 和错误处理，仍可先放在 `FeiniuApi` 内。

### 请求封装模式

新增方法建议保持现有风格：

```dart
Future<Map<String, dynamic>> refreshItem(String itemGuid) async {
  final response = await _dio.post(
    '$_apiPrefix/item/refresh',
    data: <String, dynamic>{'item_guid': itemGuid.trim()},
  );
  return _extractDataMap(response.data, 'item refresh');
}
```

对于文件上传：

```dart
Future<Map<String, dynamic>> uploadSubtitle({
  required String mediaGuid,
  required String filePath,
}) async {
  final form = FormData.fromMap(<String, dynamic>{
    'file': await MultipartFile.fromFile(filePath),
  });
  final response = await _dio.post(
    '$_apiPrefix/subtitle/upload/$mediaGuid',
    data: form,
  );
  return _extractDataMap(response.data, 'subtitle upload');
}
```

上传类接口要注意：

1. 保持 `Authorization` header。
2. 不要手动覆盖 Dio 的 multipart `Content-Type`。
3. Android 端如果来自 SAF 文件，可能需要先复制到临时文件再上传。

### `/media/p` 桥接动作

官方前端把多个动作都映射到：

```text
POST /v/api/v1/media/p
```

本项目已有：

```dart
checkPlayLinkExpired(...)
```

后续可以抽一个通用方法：

```dart
Future<Map<String, dynamic>> callMediaBridge({
  required String req,
  required Map<String, dynamic> payload,
}) async {
  final response = await _dio.post(
    _playMediaBridgePath,
    data: <String, dynamic>{
      'req': req,
      ...payload,
    },
  );
  return _extractDataMap(response.data, req);
}
```

再在上层封装：

```text
media.checkPlayLink
media.resetQuality
media.resetAudio
media.resetSubtitle
media.quit
media.transcodeStatis
```

具体 `req` 字符串需要通过 DevTools 或后端日志进一步确认。

## 需要二次确认的点

以下内容不能只靠静态打包文件确定，接入前建议实际抓一次请求：

1. 请求体字段名，例如 `item_guid`、`media_guid`、`guid`、`lan` 是否固定。
2. 部分 POST 接口是否需要 `channel=v2`。
3. `/scrap/*` 的候选结果字段结构。
4. `/item/getEditDetail` 与 `/item/saveEditDetail` 的完整 schema。
5. `/server/path` 返回的是路径列表、树结构，还是路径校验结果。
6. `/sys/img`、`/sys/rimg`、`/sys/progressThumb` 的 query 参数。
7. 管理员接口是否要求当前用户具备额外权限。

## 推荐抓包方式

在官方飞牛影视 Web 页面中打开浏览器 DevTools：

1. Network 面板筛选 `Fetch/XHR`。
2. 执行一次目标操作，例如“刷新识别”“上传字幕”“修改刮削信息”。
3. 记录：
   - URL
   - Method
   - Request Headers
   - Request Payload
   - Response JSON
4. 对照本文补 Flutter 方法和 model。

如果在 NAS 上排查服务日志，可查看：

```text
/usr/local/apps/@appdata/trim.media/logs
```

## 总结

本项目当前已经覆盖飞牛影视的“客户端播放器核心 API”。官方前端额外覆盖的是“媒体服务器管理 API”。

短期最值得补齐的是：

```text
/v/api/v1/play/quality
/v/api/v1/subtitle/upload/:media_guid
/v/api/v1/subtitle/mark
/v/api/v1/subtitle/predownload
/v/api/v1/scrap/search
/v/api/v1/scrap/rescrap
/v/api/v1/item/getEditDetail
/v/api/v1/item/saveEditDetail
/v/api/v1/item/refresh
```

这几组接口能直接提升播放、字幕和刮削修正体验，投入产出比最高。
