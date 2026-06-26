# 待定计划：Emby（fnos 中转）播放携带 entry-token（第 4 块）

> 状态：**待实现（依赖 Emby 播放接入）**。第 1–3 块（抓取 / 存储 / Emby HTTP 携带 entry-token）已完成。
> 本文件记录第 4 块——让 **mpv 播放**也能过飞牛云端 FN Connect 边缘闸——的设计，等 `EmbyMediaBackend.getPlayback` 接入后再做。

## 背景与已证结论

藏在飞牛反向代理后的 Emby 发布服务（`embyserver4-9.geqian688.fnos.net` 这类 `*.<fnId>.fnos.net`）受飞牛**云端 FN Connect 边缘闸**保护。实测（2026-06-23，用真账号）结论：

- 唯一被边缘闸认的凭据是 **`Cookie: entry-token=<值>`**（作用域 `.<fnId>.fnos.net`，覆盖所有子域）。
- NAS 登录 token、`mode=relay`、各种 Authorization 头**都不被认**（全 403「FN Connect 暂无权限访问该服务」）。
- 带上 `entry-token` 后，Emby 的 `System/Info`、`Users/Public`、`AuthenticateByName`、以及（推断）所有 `/Videos/.../stream` 播放路径都正常放行。
- `entry-token` 由真实入口流程（`fnos.net/<fnId>` SPA）登录后签发，**会话级、会过期**、非 httpOnly（可从 cookie 读）。

第 1–3 块已经把 `entry-token` 抓取（WebView）、持久化（`MediaBackendConnection.entryToken`）、注入 Emby HTTP 请求（`EmbyApi` 拦截器对 `*.fnos.net` 加 `Cookie: entry-token=…`）打通。**浏览（列表/详情/图片）已能工作；播放还没接入。**

## 播放管线现状（已确认可复用）

`headers: Map<String,String>` 在播放链路里端到端透传，无需改管线，只要在源头把 cookie 放进去：

1. `MediaPlayback.headers`（`lib/media_backend/playback/media_playback.dart:123`）——注释已明确「Emby `RequiredHttpHeaders` 与飞牛直链 headers 都不能丢」。
2. `PlaybackStream.headers`（`lib/models/playback_stream.dart:320`）——会把 `cookies` 合成 `headers['Cookie']`。
3. 原生 `MpvPlaybackController`（`...mpv/MpvPlaybackController.kt:1363`）——`loadfile` 直接带 `headers`。

即：**只要让 `EmbyMediaBackend.getPlayback` 产出的 bundle 的 `headers` 里含 `Cookie: entry-token=<值>`，播放就能过闸。**

## 待办（实现顺序）

### 4.1 实现 `EmbyMediaBackend.getPlayback`（前置，非本计划重点）
- 现状：`lib/media_backend/emby/emby_media_backend.dart:205` `throw UnsupportedError`。
- 产出中立 `MediaPlaybackResolution`：拼直链 `"$serverUrl/Videos/{itemId}/stream?..."` 或走 `PlaybackInfo`，`api_key=accessToken`。
- 这是 Emby 播放接入主任务，单独排期；本计划只关心它产出的 `headers`。

### 4.2 注入 entry-token 到播放 headers（本计划核心，约 1 处改动 + 测试）
在 `getPlayback` 组装 bundle 时，对 `*.fnos.net` 主机加 cookie：

```dart
final headers = <String, String>{...既有 Emby 必需头...};
final entryToken = connection.entryToken.trim();
if (entryToken.isNotEmpty && usesFnConnectRelayCookie(connection.serverUrl)) {
  headers['Cookie'] = _mergeEntryTokenCookie(headers['Cookie'] ?? '', entryToken);
}
```
- 复用 `usesFnConnectRelayCookie`（`lib/utils/nas_image_headers.dart`）。
- `_mergeEntryTokenCookie` 与 `EmbyApi` 内同语义（去重后追加 `entry-token=<值>`）——考虑抽到公共工具（如 `nas_image_headers.dart`）供 `EmbyApi`/`getPlayback` 共用，避免两份实现。
- 直连地址（非 fnos）：`entryToken` 为空 / 主机不匹配 → 不加，零影响。

### 4.3 校验原生侧确实转发 Cookie
- `MpvPlaybackController` 已把 `headers` 透传给 mpv（`--http-header-fields` 等价路径）。需真机确认 `Cookie` 头被 mpv 带到上游（飞牛中转对 `Cookie` 大小写 / 多值的处理）。
- 若 mpv 的 header 注入对 `Cookie` 有坑，回退方案：让本地代理 `mpv_proxy_server.dart` 注入（飞牛直链已有按 host 注入 header 的位置，可比照加 `entry-token`）。

### 4.4 过期 / 失效处理（播放期）
- `entry-token` 是会话级，播放中或重进可能已失效 → 上游返回 403「暂无权限」HTML（非视频）。
- 需要在播放失败诊断里识别该 403，提示「FN Connect 入口令牌已过期，请重新登录 Emby」，并触发 `EmbyFnEntryLoginPage` 重抓（与登录路径 `_authenticateEmby` 的 403 重抓一致，考虑抽公共重抓入口）。
- 续播 / 切集 / 切画质都会重发 `getPlayback`，届时读到的是刷新后的 `connection.entryToken`。

## 测试计划
- 单测：`getPlayback` 对 fnos 主机产出的 `headers['Cookie']` 含 `entry-token=<值>`；对直连主机不含。
- 单测：`entryToken` 为空时不加 Cookie。
- 真机：用 `embyserver4-9.geqian688.fnos.net` 实测能播放；过期后能弹重登并恢复。

## 风险 / 待确认
- mpv 是否可靠转发 `Cookie` 头到上游（4.3）。
- 中转对 Range 请求（拖动进度）是否同样只认 `entry-token`（预期是，闸在边缘、与方法/路径无关，但需真机验证拖动 + 多段加载）。
- entry-token 作用域 `.<fnId>.fnos.net`：播放直链主机必须在该域下（Emby 子域满足）。若 Emby 返回的播放直链指向**另一个**主机（如单独的 media 子域），需确认其也在 `.<fnId>.fnos.net` 下，否则 cookie 不被发送。

## 关联
- 第 1–3 块改动：`emby_api.dart`（entry-token 拦截器）、`media_backend_connection.dart`（`entryToken` 字段）、`media_backend_provider.dart`（注入）、`connection_screen.dart`（登录抓取 + 403 重抓）、`emby_fn_entry_login_page.dart`（WebView 抓取页）。
- 抓取机制实测脚本与结论：见本次会话记录。
