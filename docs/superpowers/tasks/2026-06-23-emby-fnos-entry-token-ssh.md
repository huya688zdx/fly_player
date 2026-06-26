# 任务：SSH 进飞牛 NAS 摸清 Emby 反向代理 / entry-token 转发机制

> 给 Codex 的交接。目标是把"App 登录/使用藏在飞牛 FN Connect 反向代理后的 Emby"这件事彻底打通。
> App 侧已黑盒探到关键机制（见下），但 `entry-token` 的**签发与校验细节**只能进 NAS 看内部转发配置才能定论。

---

## 0. 一句话目标

让 Flutter App（fly_player）像登录飞牛一样，登录并使用 `https://embyserver4-9.geqian688.fnos.net` 这台 Emby。
它藏在飞牛 FN Connect 反向代理后面，外网唯一入口就是这个 `*.fnos.net` 中转域名。

**需要 Codex 产出**：`entry-token` 到底怎么签发、怎么校验、是否按服务隔离、TTL 多久、有没有可用 API 直接换取（最好不依赖 WebView）。据此给出 App 端可靠实现方案。

---

## 1. 访问信息

- FN ID：`geqian688`
- NAS 中转域：`https://geqian688.fnos.net`（https 443）
- 内网：`192.168.6.120`，NAS https 端口 `5667`、http `5666`
- 公网 IPv4：`183.217.101.25`（Emby 端口 8096/8920 未对外转发，外网仅 fnos 中转可达）
- 公网 IPv6：`2409:8a38:8423:5990:a28c:fdff:fee5:cb3`、`...a069:df01:80c4:d1d7`
- Emby 发布服务：`https://embyserver4-9.geqian688.fnos.net`（Emby `4.9.0.42`，ServerName `geqian688`）
- NAS 账号：用户名 `geqian688` / 密码 `gj2513114864gj`（SSH 可能需 root 或 sudo；**此密码已在聊天明文出现，事后务必轮换**）

> SSH 建议从内网 `192.168.6.120` 接入（默认 22 端口；若关闭需在飞牛"终端/SSH"设置里开）。

---

## 2. 已确证事实（App 侧黑盒实测，2026-06-23）

1. **Emby 发布服务边缘闸只认 `Cookie: entry-token=<值>`**（作用域 `.geqian688.fnos.net`）：
   - 带 `entry-token` → `GET /System/Info/Public` 返回 200（真 Emby JSON）；`/Users/AuthenticateByName`、`/Users/Public` 等所有路径/方法均放行。
   - 不带 / 用 NAS 登录 token / `mode=relay` cookie / Authorization 头 → 一律 **403 HTML「FN Connect 暂无权限访问该服务」**（nginx，`Server: nginx`）。
2. **NAS 自身中转 `geqian688.fnos.net` 是另一套**：`mode=relay` cookie + `POST /v/api/v1/login {userName,password}` 可直接拿 NAS token（飞牛 App 就这么登录）。但这个 NAS token **当 entry-token 用对 Emby 无效**（仍 403）。
3. **飞牛桌面页 `geqian688.fnos.net/` 上可见的 cookie**：`mode, language, fnos-long-token, fnos-token, entry-token`（均非 httpOnly，可被 JS 读）。
4. **疑点（待 SSH 定论）**：把桌面页读到的 `entry-token` 拿去登录 Emby 子域，App 报"返回信息不完整"（= authenticateByName 收到的不是预期 JSON，疑似 403/200 HTML）。怀疑**桌面那一份 entry-token 对 emby 子服务无效 / 需访问该发布服务时单独签发**。需要确认 entry-token 是**全局一份**还是**按发布服务隔离**。
5. `entry-token` 是**会话级 cookie（会过期）**。
6. Emby 的 8096/8920 未对外，外网只能走 fnos 中转 → 直连方案对该用户不可行。

> 复现脚本/命令记录在本仓库 git 历史与会话记录；可用 `curl -k` 直接验证（带 `Cookie: entry-token=<真值>`）。

---

## 3. SSH 上要查的核心问题（按优先级）

### Q1. 反向代理（nginx）如何校验 entry-token？
- 找到处理 `*.fnos.net` / `embyserver4-9.geqian688.fnos.net` 的 nginx 配置与（可能的）lua/njs 鉴权逻辑。
- 看 `entry-token` 在哪被校验：`auth_request`？lua 读 cookie 查 redis/db？校验通过后回源到哪个内网地址端口（Emby 真实地址，可能是 docker 容器 `127.0.0.1:8096`）。
- 弄清 **403「暂无权限」页**由谁返回（哪段 location / 哪个 lua 分支）。

### Q2. entry-token 怎么签发？是否按服务隔离？
- 谁写入 `entry-token` cookie（哪个服务/接口/lua），写入时作用域、TTL、与 `fnos-token`/`fnos-long-token` 的关系。
- **关键**：同一个 entry-token 是对该账号下**所有**发布服务通用，还是**每个发布服务一份**（解释疑点 #4）。
- 存储在哪（redis/sqlite/内存）→ 能否据此判断 token 有效性与归属服务。

### Q3. 有没有可直接换取 entry-token 的 API？（决定 App 实现走 API 还是 WebView）
- 是否存在「拿 NAS 账号/NAS token + 目标服务标识 → 换 entry-token」的内部/公开接口。
- 飞牛桌面点「Emby Server」应用图标时，前端跳转/请求的**启动链接**是什么（这条链路应该就是为该服务签发 entry-token 的正路）。可在桌面 SPA 代码或后端日志里找该 launch/authorize 接口。

### Q4. Emby 发布服务在飞牛里的真实形态
- `docker ps` 看 Emby 容器与端口映射；反代回源地址。
- 飞牛"反向代理 / 应用中心"对该服务的配置项（是否勾了"需要登录验证"等）。

---

## 4. 建议排查命令（起手式）

```bash
# 网络/服务概览
ip a; ss -ltnp | grep -E '443|5667|8096|8920'
systemctl list-units --type=service | grep -iE 'fn|trim|relay|connect|nginx'
ps aux | grep -iE 'relay|connect|fnos|trim|nginx|lua' | grep -v grep
docker ps    # 找 Emby 容器与端口

# nginx 全量配置 + 定位相关 server/location
nginx -T 2>/dev/null | grep -nE 'fnos|embyserver|entry-token|auth_request|proxy_pass|lua' 
find /etc /usr/local /opt /usr/trim /var -name '*.conf' 2>/dev/null | xargs grep -lE 'fnos|embyserver|entry-token' 2>/dev/null

# 关键字全盘搜（entry-token 的签发/校验代码）
grep -rniE 'entry-token|entry_token' /etc /usr /opt /var /usr/trim 2>/dev/null | head -50
grep -rniE 'fnos-token|fnos_long_token|relay' /usr /opt /usr/trim 2>/dev/null | head -50

# 飞牛后端/FN Connect agent 的二进制与配置位置（飞牛代码多在 /usr/trim 或类似）
ls -la /usr/trim 2>/dev/null; ls -la /opt 2>/dev/null
journalctl -u nginx --since "10 min ago" --no-pager | tail -50   # 触发一次 403 后看日志归属
```

> 排查时可在另一端用 `curl -k -H 'Cookie: entry-token=<桌面读到的值>' https://embyserver4-9.geqian688.fnos.net/System/Info/Public` 实时对照通/不通，配合 nginx access/error log 定位是哪段配置放行/拦截。

---

## 5. 期望产出（写回结论，供 App 实现）

1. entry-token 的**签发方**（接口/服务）+ 入参 + 作用域/TTL + **是否按服务隔离**。
2. 校验逻辑落点（便于理解何为"有效 token"）。
3. **首选**：一条可被 App（Dart/Dio）直接调用的「换 entry-token」API（含签名/鉴权要求），这样可彻底摆脱 WebView。
4. **次选**：若必须走网页，确认飞牛桌面"打开 Emby 应用"的 launch URL，App 用 WebView 走这条链路、在落到 emby 子域时抓 entry-token。
5. Emby 回源真实地址端口（备用：若能在 App 侧也做等价回源/直连）。

---

## 6. App 侧已完成改动（块 1–3）与待办

> 分支 `feat/native-player-overhaul`。机制说明见 `docs/superpowers/plans/2026-06-23-emby-fnos-playback-entry-token.md`（块 4 mpv 播放待办）。

| 文件 | 改动 |
|---|---|
| `lib/api/emby_api.dart` | `normalizeServerUrl` 剥 `/web/index.html`、`#!`、query；新增 `entryTokenProvider`，拦截器对 `*.fnos.net` 注入 `Cookie: entry-token=…`；加 `[EmbyApi][REQ/RESP/ERR]` 诊断日志 |
| `lib/media_backend/session/media_backend_connection.dart` | 新增持久化字段 `entryToken` |
| `lib/providers/media_backend_provider.dart` | 数据层 `EmbyApi(entryTokenProvider: () => session.currentConnection?.entryToken)` |
| `lib/screens/connection_screen.dart` | Emby 登录：fnos 主机先抓 entry-token（WebView），存入连接；403 自动重抓一次重试 |
| `lib/screens/emby_fn_entry_login_page.dart`（新） | WebView 抓取页：登录后跳目标 Emby 主机，仅在**非拦截页**落到目标主机时抓 `entry-token`；带 `[EmbyEntry]` 诊断日志 |
| `test/...` | emby_api / connection / connection_test 已同步更新，全套 313 测试通过 |

**当前卡点**：见 #2 疑点 #4——桌面读到的 entry-token 用于 Emby 登录失败。等本任务查清签发/隔离机制后，据 #5 结论调整 `emby_fn_entry_login_page.dart`（改抓正确来源）或改为 API 换取，再继续块 4 播放。

**已知 App 行为预期**：entry-token 拿对后，浏览（列表/详情/图片）即可用；播放（块 4）需把同一 cookie 注入 `getPlayback` 的 `headers`（管线已端到端透传到 mpv）。

---

## 7. 安全

- 用户在聊天明文给过 NAS 账号密码（`geqian688`/`gj2513114864gj`）→ **任务完成后提醒其轮换密码**。
- 排查只读为主；改动 NAS 配置前先确认并备份。

---

## 8. SSH 排查结论（2026-06-23，经 `127.0.0.1:2233` 端口转发）

> 本轮只读排查；未修改 NAS 配置。SSH 入口与文档内网直连不同：使用本机 `127.0.0.1:2233` 端口转发接入，登录用户在 `Administrators` 组内，`sudo` 可用。

### 8.1 Emby 真实形态与回源

- Emby 不是 Docker 容器，而是飞牛应用中心安装的原生应用：
  - 进程：`/var/apps/EmbyServer4-9/target/system/EmbyServer`
  - 数据目录：`/var/apps/EmbyServer4-9/var`（指向 `/vol1/@appdata/EmbyServer4-9`）
  - 监听：`*:8096`
- `appcenter.app` 记录：
  - `id=83`
  - `app_name=EmbyServer4-9`
  - `name=Emby`
  - `status=running`
  - `native_app=false`
  - `is_docker=false`
- `appcenter.app_service` 记录：
  - `id=92`
  - `service_name=EmbyServer4-9.Application`
  - `title=Emby Server`
  - `type=url`
  - `url/default_url=http://${host}:8096/web/index.html`
  - `is_admin=false`
  - `gateway_prefix/gateway_socket/full_url` 为空
- 因此 Emby 对 FN Connect 的本地回源就是 `http://127.0.0.1:8096` / `http://<NAS-host>:8096` 这一类本机 8096 服务。

### 8.2 本地 nginx 不负责 entry-token 校验

- 飞牛本地 nginx 配置在 `/usr/trim/nginx/conf/`。
- `/usr/trim/nginx/conf/conf.d/trimcon.conf` 中：
  - `/trimcon/cookie` 只写 `Set-Cookie: mode=relay; Path=/; HttpOnly`
  - `/trimfn` 代理到 `http://unix:/var/run/trim-connect.sock`
  - 没有 `entry-token` 校验逻辑
- `nginx -T` 未发现 `entry-token`、`auth_request`、lua/njs 相关配置。
- 结论：`entry-token` 的签发/校验不在本地 nginx；校验更可能发生在 FN Connect 的 `trim-connect/pxy` 链路或云端边缘。

### 8.3 签发入口：桌面 WebSocket RPC `exchangeEntryToken`

- 桌面主站前端文件：`/usr/trim/www/assets/index-CMZOY5-G.js`
- 前端明确有：
  - 写 cookie：`ja.set("entry-token", token, { domain: "." + window.location.host })`
  - 读 cookie：`ja.get("entry-token")`
- 在 `*.fnos.net` / `*.fnnas.cn` / `*.fynas.net` / `*.5ddd.com` 域名下，桌面启动时会调用：
  - RPC 名称：`appcgi.sac.entry.v1.exchangeEntryToken`
  - 调用形态：`pe.sac.exchangeEntryToken({ data: { token: oldEntryToken? } })`
  - 返回：`data.token`
  - 前端再把返回值写入 `entry-token` cookie
- 这个调用没有传 `service_id`、`service_name`、Emby host 或端口，只有可选旧 `entry-token`。据此判断：`entry-token` 至少在桌面签发阶段不是按 Emby 服务单独签发，而是当前 FN Connect 登录态/域名下的入口 token。

### 8.4 传输层：不是普通 `/v/api/v1/*` HTTP API

- 桌面 RPC 走 WebSocket：
  - URL：`wss://<host>/websocket?type=main`
  - 消息基本形态：`{"reqid":"...","req":"...","data":{...}}`
- 桌面主连接预检：
  - `util.crypto.getRSAPub`
  - `user.authToken`
  - 后续请求会经过前端 `rx` 拦截器，部分请求使用 RSA/AES 包装或带会话 secret 签名。
- 实测：
  - `POST /v/api/v1/login` 可以拿到现有 App 使用的 NAS REST token。
  - 但把这个 REST token 直接发给 WebSocket `user.authToken` 会返回 `errno=65534`，后续 `appcgi.sac.entry.v1.exchangeEntryToken` 也失败。
- 结论：现有 `FeiniuApi.login()` 的 REST token 不能直接换 `entry-token`。若要彻底摆脱 WebView，需要在 App 内额外实现飞牛桌面的 WebSocket 登录/加密握手；否则继续使用 WebView 是更稳的路径。

### 8.5 TTL 与作用域

- 前端写 `entry-token` 时没有设置 `expires`，因此浏览器层面是会话 cookie。
- `fnos-long-token` 前端设置为 30 天，但它是另一套登录保活 token，不能当 `entry-token` 使用。
- 后端 `entry-token` 的内部 TTL 未在 nginx、PostgreSQL 配置表或明文配置中找到；相关逻辑在闭源 Go 二进制 `trim-connect/pxy` 内。
- App 侧应按“会话级、可能过期”处理：请求遇到 FN Connect 403 时重新走 `exchangeEntryToken` 所在页面链路刷新。

### 8.6 对 App 实现的建议

1. 当前最可靠方案仍是 WebView：
   - 先进入 `https://<fnId>.fnos.net/` 完成飞牛桌面登录。
   - 等桌面主站执行 `appcgi.sac.entry.v1.exchangeEntryToken` 并写入 `entry-token`。
   - 再访问 `https://embyserver4-9.<fnId>.fnos.net/...`，此时同一 `.fnos.net` 作用域 cookie 会被带给 Emby 子域。
2. 不建议把 `/v/api/v1/login` 返回的 NAS token 当作 `entry-token` 或 WebSocket `user.authToken` 使用，已验证不通。
3. 如果后续要做无 WebView 方案，需要新增一套 Dart WebSocket 客户端，复刻桌面前端：
   - 建立 `/websocket?type=main`
   - `util.crypto.getRSAPub`
   - 完成飞牛 WebSocket 登录/`user.authToken` 需要的加密会话
   - 调用 `appcgi.sac.entry.v1.exchangeEntryToken`
   - 取 `data.token` 作为 Emby 请求的 `Cookie: entry-token=<value>`
4. 桌面签发接口本身没有服务入参，因此本轮证据不支持“每个发布服务单独一份 token”的假设；之前失败更像是抓取时机/来源不对，或抓到了旧/未刷新 token。
