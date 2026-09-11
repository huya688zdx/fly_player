# 飞牛影视（trim.media / fnTV）前后端 API 文档

> 来源：NAS `192.168.6.120`（飞牛 OS fnOS）上飞牛影视应用前端 JS bundle 静态分析 + 实机验证。
> 前端版本 0.9.7，媒体服务（mediasrv）0.8.41。分析日期 2026-09-05。

## 1. 服务架构

| 组件 | 位置 / 端口 |
|---|---|
| 后端进程 | `/usr/local/apps/@appcenter/trim.media/trim-media`（参数 `--port=8005`，`--static` 指向前端目录） |
| 对外入口 | `http://192.168.6.120:5666`（fnOS 主 nginx），`location /v` → `unix:/var/run/trim_media.sock` |
| 前端静态文件 | `/usr/local/apps/@appcenter/trim.media/static/`（Vite 构建产物，入口 `index.html`） |
| API 请求层 | bundle `assets/14a77ac952fc83b785b65592c335e16d-YegjoWFd.js`（base 前缀、签名、API 注册表都在此文件） |
| 主应用逻辑 | bundle `assets/74c95604043427f0bee1d0e16bfa53af-DsH45n0p.js` |

Web 端入口即 fnOS 桌面 → 飞牛影视，实际页面地址为 `http://NAS:5666/v/...`。

## 2. 通用约定

### 2.1 Base 前缀

| 前缀 | 用途 |
|---|---|
| `/v/api/v1` | 默认前缀（绝大多数接口） |
| `/v/api/v2` | 带 `channel:'v2'` 的调用：`PUT /sys/init`、`POST /user/loginByPassword`、`PUT /manager/user/create`、`POST /manager/user/:guid`、`POST /user/passwd` |
| `/v/api/intl/v1`、`/v/api/intl/v2` | 国际版区域下 `POST /login`、`POST /user/loginByPassword`、`POST /auth`、`GET /sys/config` 走 intl 前缀（CN 区域用 v1/v2） |

下文端点表均省略前缀，实际请求 = `/v/api/v1` + 路径。

### 2.2 响应格式

```json
{"code": 0, "msg": "", "data": {}}   // code == 0 表示成功
```
业务错误码举例：4096 SystemInternalError、4099 InsufficientDiskSpace、8192 ParameterError、65280 InvalidOperation、-2 Auth Failed（未登录/无权限）、5000 invalid sign（签名错误）。

### 2.3 请求头

| 头 | 值 | 说明 |
|---|---|---|
| `Authorization` | 登录 token 明文（无 Bearer 前缀） | 登录后由 cookie `Trim-MC-token` 保存，请求时原样放入此头 |
| `X-Trim-Client` | `web` | 客户端类型（可选 ios-main / android-tv 等） |
| `X-Trim-Client-Version` | `616` | 前端版本号 |
| `authx` | `nonce=..&timestamp=..&sign=..` | 请求签名（见 2.4） |

### 2.4 authx 签名算法（已实测验证，MD5 版通过）

```
apiKey = "16CCEB3D-AB42-077D-36A1-F355324E4237"   // 前端内置（XOR 169 混淆存储）
salt   = "NDzZTVxnRKP8Z0jXg1VAMonaG8akvh"

GET 请求:  payload_hash = MD5( urldecode(按key排序后的query串) )   // 无参数时为 MD5("")
其他请求:  payload_hash = MD5( JSON.stringify(body) )             // 无 body 时为 MD5("")

nonce     = 100000~999999 随机数
timestamp = 毫秒时间戳
sign  = MD5( salt + "_" + pathname + "_" + nonce + "_" + timestamp + "_" + payload_hash + "_" + apiKey )

authx = "nonce={nonce}&timestamp={timestamp}&sign={sign}"
```

免签名端点（无需 authx）：
- 精确匹配：`/v/api/v1/task/running`、`/v/api/v1/play/record`、`/v/api/v1/subtitle/upload`
- 前缀匹配：`/v/api/v1/sys/img/`、`/v/api/v1/img/`、`/v/api/v1/concat/`、`/v/api/v1/media/`

无登录 token 也可调的公开接口：`GET /sys/version`（实测直接返回版本）；`GET /server/info` 只需签名不需登录（实测通过）。
媒体库等用户数据接口：签名 + `Authorization` token 缺一不可（实测 `/mediadb/list` 有签名无 token 返回 `{"code":-2,"msg":"Auth Failed"}`）。

## 3. 端点全表（按前端 API 命名空间）

### user / 用户与账户管理
| 方法 | 路径 | 前端调用名 | 说明 |
|---|---|---|---|
| POST | /login | user.login | 登录（OAuth 网页跳转流程） |
| POST | /user/loginByPassword | user.loginByPassword | 账号密码登录（v2 channel） |
| POST | /user/logout | user.logout | 退出登录 |
| GET | /user/info | user.info | 当前用户信息 |
| POST | /user/info | user.updateInfo | 修改当前用户信息 |
| POST | /user/passwd | user.updatePassword | 修改密码（v2 channel） |
| POST | /auth | user.auth | 鉴权校验 |
| PUT | /manager/user/create | user.create | 创建用户（管理员） |
| GET | /manager/user/list | user.list | 用户列表（管理员） |
| POST | /manager/user/:guid | user.update | 修改指定用户 |
| DELETE | /manager/user/:guid | user.delete | 删除指定用户 |
| POST | /manager/user/unlock | user.unlock | 解锁用户 |
| GET | /manager/template/permission | user.defaultPermission | 默认权限模板 |
| POST | /manager/template/permission | user.updateDefaultPermission | 更新默认权限模板 |
| POST | /user/getData | userData.getUserData | 读取用户偏好数据 |
| POST | /user/setData | userData.setUserData | 写入用户偏好数据 |

### sys / 系统初始化与配置
| 方法 | 路径 | 前端调用名 | 说明 |
|---|---|---|---|
| GET | /sys/config | sys.config | 读取系统配置 |
| PUT | /sys/init | sys.init / initV2 | 初始化（v2 channel 走 /v/api/v2） |
| GET | /sys/version | sys.version | 版本号（**免登录实测通过**，返回 app 与 mediasrv 版本） |
| GET | /sys/options | sys.options | 系统选项 |

### server / 服务器信息（设置页"服务器"）
| 方法 | 路径 | 前端调用名 | 说明 |
|---|---|---|---|
| GET | /server/info | server.info | 服务器信息（**实测仅需签名**：名称、区域、GPU、元数据目录等） |
| POST | /server/info | server.update | 修改服务器信息 |
| GET | /server/gpu/list | server.gpuList | GPU 列表 |
| POST | /server/path | server.paths | 服务器路径查询 |
| GET | /server/pools | server.pools | 存储池列表 |
| GET | /server/allVols | server.allVols | 全部卷 |
| GET | /server/getAppAuthorizedDir | server.getAppAuthorizedDir | 应用授权目录 |
| GET | /server/oauthStatus | server.oauthStatus | OAuth 状态 |

### mdb / 媒体库管理（设置页"媒体库"）
| 方法 | 路径 | 前端调用名 | 说明 |
|---|---|---|---|
| GET | /mdb/list | mdb.list | 媒体库列表 |
| PUT | /mdb/create | mdb.create | 创建媒体库 |
| POST | /mdb/:guid | mdb.update | 修改媒体库 |
| DELETE | /mdb/:guid | mdb.del | 删除媒体库 |
| GET | /mdb/:guid | mdb.details | 媒体库详情 |
| POST | /mdb/scan/:guid | mdb.scan | 扫描指定媒体库 |
| POST | /mdb/scanall | mdb.scanAll | 扫描全部媒体库 |
| POST | /mdb/refresh | mdb.refresh | 刷新媒体库元数据 |
| POST | /mdb/setSort | mdb.setSort | 设置排序 |
| POST | /mdb/getPoster | mdb.getPoster | 获取海报候选 |
| POST | /mdb/setPoster | mdb.setPoster | 设置海报 |
| POST | /mdb/iptv/temp/upload | mdb.iptvTempUpload | IPTV 源临时上传（specialApi） |
| DELETE | /item/:guid | mdb.delItem | 删除媒体条目 |
| GET | /media/itemfile/:guid | mdb.files | 媒体库文件列表 |

### mediadb / 媒体库数据
| 方法 | 路径 | 前端调用名 | 说明 |
|---|---|---|---|
| GET | /mediadb/list | mediadb.list | 媒体库数据列表 |
| GET | /mediadb/sum | mediadb.sum | 统计汇总 |

### media / 媒体查询与播放链接
| 方法 | 路径 | 前端调用名 | 说明 |
|---|---|---|---|
| POST | /media | media.query / media.getPlayLink / media.quit | 同一路径三种用途，由 body 区分；`/v/api/v1/media/` 前缀整体免签名 |

### item / 条目操作
| 方法 | 路径 | 前端调用名 | 说明 |
|---|---|---|---|
| POST | /item/list | item.list | 条目列表（首页/媒体墙分页） |
| GET | /item/:guid | item.info | 条目详情 |
| POST | /item/:guid/playing | item.playing | 上报正在播放 |
| POST | /item/refresh | item.refresh | 刷新条目 |
| POST | /item/watched | item.watched | 标记已看 |
| DELETE | /item/watched | item.delWatched | 取消已看 |
| PUT | /item/favorite | item.favorite | 加入收藏 |
| DELETE | /item/favorite | item.delFavorite | 取消收藏 |
| POST | /favorite/list | favorite.list | 收藏列表 |
| POST | /item/getEditDetail | item.getEditDetail | 编辑元数据-读取 |
| POST | /item/saveEditDetail | item.saveEditDetail | 编辑元数据-保存 |
| DELETE | /item/media/batch | item.batchDeleteMedia | 批量删除版本/文件 |

### movie / tv / season / episode / 详情页
| 方法 | 路径 | 前端调用名 | 说明 |
|---|---|---|---|
| GET | /movie/:guid | movie.info | 电影详情页 |
| GET | /tv/:guid | tv.info | 剧集详情页 |
| GET | /season/list/:guid | season.list | 剧集的季列表 |
| GET | /episode/list/:guid | episode.list | 季的集列表 |

### person / 演职人员
| 方法 | 路径 | 前端调用名 | 说明 |
|---|---|---|---|
| GET | /person/:guid | person.info | 人物详情 |
| POST | /person/list/:guid | person.listForItem | 条目的演职员列表 |
| POST | /person/item/list | person.list | 人物分页列表 |
| POST | /person/refresh | person.refresh | 刷新人物 |
| POST | /person/getEditDetail | person.getEditDetail | 编辑-读取 |
| POST | /person/saveEditDetail | person.saveEditDetail | 编辑-保存 |
| POST | /person/search | person.search | 人物搜索 |
| POST | /person/create | person.create | 创建人物 |

### play / 播放与会话
| 方法 | 路径 | 前端调用名 | 说明 |
|---|---|---|---|
| GET | /play/list | play.list | 继续观看/播放列表 |
| GET | /play/record | （读记录） | 播放记录（免签名） |
| POST | /play/record | play.addRecord | 上报播放进度（免签名） |
| DELETE | /play/record | play.delRecord | 删除播放记录 |
| POST | /play/info | play.info | 播放信息 |
| POST | /play/play | play.play | 发起播放 |
| POST | /play/quality | play.quality | 画质列表/切换 |
| POST | /play/setConfigByItem | play.setConfigByItem | 按条目设置播放配置 |

### media/p / 播放控制（同一路径多用途）
| 方法 | 路径 | 前端调用名 |
|---|---|---|
| POST | /media/p | play.resetQuality / play.resetAudio / play.resetSubtitle / play.quit / play.checkPlayLink / play.transcodeStatis |

### stream / 转码流
| 方法 | 路径 | 前端调用名 | 说明 |
|---|---|---|---|
| GET | /stream/list/:guid | stream.list | 某媒体的流信息（视频/音频轨） |
| POST | /stream | stream.playback | 发起转码播放 |

### subtitle / 字幕
| 方法 | 路径 | 前端调用名 | 说明 |
|---|---|---|---|
| POST | /subtitle/search | subtitle.search | 在线搜索字幕 |
| POST | /subtitle/download | subtitle.download | 下载字幕 |
| POST | /subtitle/predownload | subtitle.predownload | 预下载 |
| GET | /subtitle/dl/:guid | subtitle.dl | 字幕文件下载（specialApi） |
| PUT | /subtitle/mark | subtitle.mark | 字幕标记 |
| DELETE | /subtitle/del | subtitle.del | 删除字幕 |
| POST | /subtitle/upload/:media_guid | subtitle.upload | 上传字幕（免签名，specialApi） |

### scrap / 刮削
| 方法 | 路径 | 前端调用名 | 说明 |
|---|---|---|---|
| POST | /scrap/search | scrap.search | 刮削搜索 |
| POST | /scrap/rescrap | scrap.rescrap | 重新刮削 |
| POST | /scrap/rescrap/batch | scrap.batchRescrap | 批量重新刮削 |
| DELETE | /scrap/:guid | scrap.unscrap | 取消刮削 |
| POST | /scrap/removeFromBlackByPath | scrap.removeFromBlackByPath | 从黑名单移除 |

### search / 全局搜索
| 方法 | 路径 | 前端调用名 | 说明 |
|---|---|---|---|
| GET | /search/list | search.list | 搜索结果 |
| GET | /search/indexStatus | search.getIndexStatus | 索引状态 |
| POST | /search/rebuild | search.rebuild | 重建索引 |

### tag / 标签与字典
| 方法 | 路径 | 前端调用名 | 说明 |
|---|---|---|---|
| GET | /tag/list | tag.list | 自定义标签 |
| GET | /tag/genres | tag.genres | 类型字典 |
| GET | /tag/iso6391 | tag.iso6391 | 语言代码 639-1 |
| GET | /tag/iso6392 | tag.iso6392 | 语言代码 639-2 |
| GET | /tag/iso3166 | tag.iso3166 | 国家地区代码 |
| POST | /tag/custom/create | tag.customCreate | 创建自定义标签 |
| POST | /tag/custom/genres/batch | tag.customGenresBatch | 批量自定义类型 |

### task / 任务中心
| 方法 | 路径 | 前端调用名 | 说明 |
|---|---|---|---|
| GET | /task/running | task.running | 运行中任务（免签名） |
| GET | /task/schedule/list | task.schedule | 计划任务列表 |
| POST | /task/schedule/getSetting | task.getSetting | 计划任务设置读取 |
| POST | /task/schedule/set | task.set | 计划任务设置保存 |
| GET | /task/uselessList | task.uselessList | 无用文件列表 |
| POST | /task/removeUseless | task.removeUseless | 清理无用文件 |
| POST | /task/stop | task.stop | 停止任务 |

### image / 临时图片（编辑元数据用）
| 方法 | 路径 | 前端调用名 | 说明 |
|---|---|---|---|
| GET | /image/temp/:filename | image.preview | 预览临时图片 |
| POST | /image/temp/upload | image.upload | 上传临时图片 |
| POST | /image/temp/delete | image.delete | 删除临时图片 |
| POST | /image/temp/getFromCloud | image.getFromCloud | 从 TMDB 等云端拉图 |
| POST | /image/temp/genScreenshot | image.genScreenshot | 从视频生成截图 |

### 其他
| 方法 | 路径 | 前端调用名 | 说明 |
|---|---|---|---|
| GET | /fileViewAdmin/list | fileViewAdminApi.list | 文件视图（管理员） |
| GET | /test/extractSubtitle | test.extractSubtitle | 测试：从文件提取字幕 |

## 4. 图片与流媒体辅助端点（非 JSON 接口）

| 路径前缀 | 说明 |
|---|---|
| `/v/api/v1/sys/img` | 海报/图片服务（免签名前缀） |
| `/v/api/v1/sys/rimg` | 图片服务（rimg，带尺寸处理） |
| `/v/api/v1/sys/progressThumb` | 播放进度条缩略图 |
| `/v/api/v1/img/` | 图片输出（免签名前缀） |
| `/v/api/v1/concat/` | 视频流拼接输出（免签名前缀） |
| `/v/api/v1/media/` | 媒体文件流输出（免签名前缀） |
| `/v/api/v1/image/temp` | 临时图片基路径 |

## 5. 实测验证记录（2026-09-05）

| 请求 | 结果 |
|---|---|
| `GET /v/api/v1/sys/version`（无任何头） | `{"code":0,"data":{"version":"0.9.7","mediasrvVersion":"0.8.41"}}` |
| `GET /v/api/v1/server/info`（按 2.4 构造 authx，MD5） | `{"code":0,"data":{"name":"搁浅的小屋","region":"CN","gpu_acc":1,...}}` |
| 同上但 sign 用 SHA256 | `{"code":5000,"msg":"invalid sign"}` → 证实哈希为 MD5 |
| `GET /v/api/v1/mediadb/list`（有签名、无 token） | `{"code":-2,"msg":"Auth Failed"}` → 用户数据需再带 `Authorization` |
| `GET /v/api/v1/__bogus__/test` | `{"message":"Not Implemented, please update."}` → 与真实端点可区分 |

可复用的签名调用示例脚本：`E:\NAS\verify_authx.py`（`build_authx()` 函数可直接复用）。

## 6. 后续调用建议

1. `POST /user/loginByPassword`（body 形如 `{"username":..,"password":..}`，v2 channel）拿到 token；
2. 之后所有请求带 `Authorization: <token>` + `authx` 签名 + `X-Trim-Client: web` + `X-Trim-Client-Version: 616`；
3. 免签名前缀（`/media/`、`/sys/img/` 等）与 `GET /sys/version`、`GET /server/info` 可直接访问。

## 附：分析路径

- 前端文件已下载到本地：`E:\NAS\fntv_frontend\`
- 提取脚本：`extract_api.py`、`extract_endpoints.py`、`dump_registry.py` 等（`E:\NAS\`）
- NAS 侧入口：SSH `geqian688@192.168.6.120:22`，辅助脚本 `E:\NAS\nas_ssh.py`
