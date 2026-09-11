# FN Connect 登录飞牛影视：完整流程与第三方实现指南

> 基于 fnOS（192.168.6.120）前端代码逆向 + **端到端实测验证**（2026-09-06，全流程程序化跑通）。
> 可复用脚本：`E:\NAS\fnconnect_e2e2.py`（完整链路，一跑全通）。

## 0. 一图看懂

```
第三方客户端                fnOS 系统 (5666)                      飞牛影视后端 (trim.media)
    │  ① ws 加密登录            │                                     │
    │ ────────────────────────► │ /websocket (user.login)             │
    │  ◄── fnos-token ────────  │ accountsrv                          │
    │  ② 授权                   │                                     │
    │ ── POST /oauthapi/authorize ─►│ 发放 code（10 分钟内有效）        │
    │  ◄─ {code:"XXXXXXXX"} ─── │                                     │
    │  ③ 用 code 换媒体 token   │                                     │
    │ ── POST /v/api/v1/auth {source:'Trim-NAS', code} ──────────────► │ accountsrv 验证 code
    │  ◄─ {token:"32位hex"} ────│────────────────────────────────── │
    │  ④ 之后所有请求            │                                     │
    │ ── Authorization: <token> + authx 签名 ───────────────────────► │
```

## 1. 涉及的服务（nginx 路由已核实）

| 路径 | 后端 | 职责 |
|---|---|---|
| `/websocket` | trim_cgi unix socket | 系统 RPC（JSON over WebSocket，敏感请求加密信封） |
| `/oauthapi`、`/v1/accountapi` | trim.accountsrv.sock | **FN Connect OAuth 服务端**（authorize / app info / third-part token） |
| `/v` | trim_media.sock | 飞牛影视后端（`/v/api/v1/auth` 校验 code 发媒体 token） |
| `/trimfn` | trim-connect.sock | FN Connect 远程隧道（外网中转，全局 CORS，手机 App 用） |
| `/signin` | 静态页（/usr/trim/www） | 统一授权确认页（配合 `apps/oauth` 前端 chunk） |

## 2. 影视 Web 的官方流程（逆向自 `20e1b656` chunk）

1. 影视前端 `GET /v/api/v1/sys/config` → `nas_oauth: {app_id:"U1G8OGDF3Y", url:""}`；
   `url` 为空时 FN Connect 登录页就在**同源** `http://NAS:5666/signin`。
2. 弹窗（586×840）或整页跳转：
   `{url}/signin?client_id=U1G8OGDF3Y&redirect_uri={影视origin}/v/oauth/result&app_name=飞牛影视`
   （跳转前把来源页存进 sessionStorage `mc-oauth-redirect-uri`，登录后跳回）
3. `/signin` 页：
   - 未登录 → NAS 账号密码登录（RSA/AES 加密，见 §3）+ 可选 2FA；
   - 已登录 → 显示授权确认卡片（`GET /oauthapi/app/info?client_id=...&token=...` 取应用名，**实测该接口免鉴权可用**）。
4. 用户点"授权" → `POST /oauthapi/authorize`：
   ```json
   {"token":"<fnos-token>","client_id":"U1G8OGDF3Y","redirect_uri":".../v/oauth/result","state":"","response_type":"code"}
   ```
   响应：`{"code":0,"msg":"success","data":{"redirect_uri":"...","code":"UAAPZ69Emw"}}`
5. 浏览器跳转 `redirect_uri?code=UAAPZ69Emw` → 影视 `/v/oauth/result` 页（只显示"登录中"）。
6. 影视前端 `POST /v/api/v1/auth`（带 authx 签名，无需已有登录态）：
   ```json
   {"source":"Trim-NAS","code":"UAAPZ69Emw"}
   ```
   响应：`{"code":0,"data":{"token":"37bb5975126f4cc091e1352b0b8ce9c7"}}`
7. token 写入 cookie `Trim-MC-token`，之后所有媒体 API 请求带 `Authorization: <token>` + authx 签名。
   `GET /v/api/v1/user/info` 实测返回：
   ```json
   {"data":{"guid":"f8fb9581...","username":"geqian688","is_admin":1,
            "sources":[{"source":"Trim-NAS","source_id":"1000","source_name":"geqian688"}]}}
   ```
   `sources` 即 FN Connect 账号映射关系（系统 uid 1000 → 媒体用户）。

## 3. 程序化系统登录（加密 WebSocket RPC，实测通过）

连接 `ws://NAS:5666/websocket`（外网走 FN Connect 隧道域名）。

**握手：**
```
→ {"req":"util.getSI","reqid":"1"}                      → {"si":"72057907809943592","result":"succ"}
→ {"req":"util.crypto.getRSAPub","reqid":"2","si":...}  → {"pub":"-----BEGIN PUBLIC KEY...","si":...}
```

**建加密通道：**
- 生成随机 AES-256-CBC key（32 字节）+ IV（16 字节）
- RSA-OAEP(SHA-256) 加密 AES key → `rsa`（信封带 `"v":1`；旧客户端 JSEncrypt 用 PKCS1v1.5、不带 v）
- 之后敏感请求整体加密发送：
```json
{"req":"encrypted","iv":"<IV 的 base64>","rsa":"<RSA(key) 的 base64>","aes":"<AES-256-CBC(JSON(真实请求)) 的 base64>","si":"...","v":1}
```
- 服务端响应同样是 `{req:"encrypted","aes":...}`，用**同一 key/IV** 解密。

**登录：**
```json
{"req":"user.login","user":"<账号>","password":"<密码>","stay":2,
 "deviceType":"pc","deviceName":"Windows-Python","did":"<uuid>","si":"..."}
```
注意：字段名是 **`user`**（不是 username）；`stay:2` 表示信任设备；`did` 是设备唯一 ID（客户端持久化）。
响应：`{"result":"succ","uid":1000,"admin":true,"token":"...","longToken":"...","secret":"...","machineId":"...","backId":"..."}`

- **2FA**：若响应含 `isTwofaEnforced/isBindTwofaSecret`，需再发 `user.2fa.loginVerify`
  `{code|email+emailCode, accessToken, isTrustedDevice, stay, deviceName, deviceType, did}` → 换正式 token。
- **免密续登**：保存 `longToken`（30 天），重连时发
  `{req:"user.tokenLogin","token":"<longToken>","deviceType":...,"deviceName":...,"did":...}` 直接换新 token。
- **会话保活**：每 60 秒 `{req:"user.active"}`；密码类请求都必须走加密信封。

## 4. 第三方对接的三条路线

### 路线 A：Web / WebView 应用（官方同款，推荐）
1. 把用户浏览器引到 `http://NAS:5666/signin?client_id=<你的client_id>&redirect_uri=<你的回调>&app_name=<应用名>&state=<防重放>`；
2. 用户在系统页登录（密码/2FA/手机确认）并点"授权"；
3. 回调收到 `?code=...&state=...`；
4. 你的后端调 `POST /oauthapi/third-part/token` 换系统级 token（该端点专为第三方准备，系统内还有 `/debug/token-exchange` 开发者工具页生成示例 curl）；
   —— 如果目标是登录**飞牛影视**，则改为调 `POST /v/api/v1/auth {source:'Trim-NAS', code}` 拿媒体 token（本次实测即此路线）。
5. 拥有自己 client_id 的注册入口在 fnOS 的 FN Connect 相关设置（应用类型枚举含 `INBUILT / THIRD_PARTY / TEMPORARY`）。

### 路线 B：原生客户端全自动（本次实测跑通）
按 §3 加密登录拿 fnos-token → §2 步骤 4/6 换媒体 token。适合个人工具、自动化脚本，全程无浏览器。
关键实现要点：`iv` 用 **base64**、先 `getSI` 再 `getRSAPub`、登录字段名 `user`、信封带 `si` 与 `v:1`——这四点错一个服务端就静默不响应或报 8192。

### 路线 C：最简（不走 FN Connect）
直接 `POST /v/api/v2/user/loginByPassword`（影视后端自己的密码登录，v2 通道 + authx 签名）→ token。
适合只需要操作影视库的个人脚本；缺点是第三方代码要接触明文密码，且享受不到 FN Connect 的统一设备管理/撤销。

## 5. 错误码速查（实测）

| 码 | 含义 | 出处 |
|---|---|---|
| 10001 | 参数缺失（client_id/redirect_uri/response_type/token） | /oauthapi/authorize |
| 11001 | invalid request（third-part/token 请求体不合法） | /oauthapi/third-part/token |
| 11004 | auth error（code 无效/过期/source 不匹配） | /v/api/v1/auth |
| -1 | Invalid Params（缺 source 或 code） | /v/api/v1/auth |
| 8192 | ParameterError（加密信封内参数不合法，如字段名错误） | websocket RPC |
| 10003 | notLoggedIn（app/info 无 token，实测空 token 也放行） | /oauthapi/app/info |

## 6. 安全说明（对你 NAS 的改动）

- 本次验证用你的账号登录了两次系统（产生了 2 个会话 token + 1 个长效 token），
  可在 fnOS **设置 → 账号/授权设备**（`appcgi.accountsrv.v1.token.list/revoke`）里查看并吊销。
- `/oauthapi/authorize` 会为 `U1G8OGDF3Y`（trim.media）建立授权记录，同样可在授权管理中移除。
- 测试脚本 `fnconnect_e2e2.py` 中含明文密码，仅限本机使用，注意保管。

## 附：证据文件

| 文件 | 内容 |
|---|---|
| `fnconnect_e2e2.py` | 端到端可运行脚本（登录→授权→换 token→验证） |
| `fnconnect_variants.py` | 加密信封格式排查过程（iv 编码/si/v 字段） |
| `fnconnect_web/` | 系统登录页全部前端 chunk + 分析上下文 |
| `fntv_frontend/assets/20e1b656...js` | 影视端 OAuth 交接逻辑（原文） |
| `oauth_flow.txt` / `fnconnect_ctx.txt` | 逆向上下文摘录 |
