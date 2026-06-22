# Emby 首页首光（first light）读取切片设计

日期：2026-06-22
范围决策：用户 2026-06-22 要「接 Emby 首页 API 看效果」，并确认①有真 Emby 测试服可实机验证、②由 Claude 连 Provider 路由一起做。
前序：`research/2026-06-21-emby-api-shape.md`、Codex 登录后端 `specs/2026-06-21-public-media-login-backend-design.md`。

## 1. 目标

让首页在 Emby 后端激活时，端到端拉取并显示 Emby 媒体库（Views）分类条 + 其预览条目，证明
「认证会话 → Provider 路由 → EmbyMediaBackend → 公共首页渲染」整条链路通。**只做首页读取**，
不接详情、播放、搜索、筛选。

## 2. 现状（已核实）

- ✅ Codex 已落地：`EmbyApi`（**仅认证**：`getPublicSystemInfo` / `authenticateByName`→token+userId）、
  `BackendSessionProvider`（`currentKind`/`currentConnection`：serverUrl/accessToken/userId/userName/`isConfigured`）、
  连接 store、连接模型。
- ❌ 缺：EmbyApi **无任何读端点**；**无 `EmbyMediaBackend`**；`MediaBackendProvider:32` **写死 Feiniu**、未按 kind 路由。
- ⚠️ 首页坑（`media_list_screen`）：`backend.getCatalogs()`/`getHomeSummary()` 走 backend（会路由到 Emby ✓），
  但**继续观看 `api.getPlayList()` + 分类预览 `api.getItemsByCategoryGuid()` 是 FeiniuApi 直连**
  （Task 6 为保飞牛续播进度刻意没走 backend）。Emby 激活时这两条会打到飞牛 → 失败。

## 3. 范围

**做（IN）**
- EmbyApi 读端点：`getUserViews`（`GET /Users/{uid}/Views` → 媒体库分类）、`getItems`（`GET /Users/{uid}/Items?ParentId=&Limit=&Fields=` → 某库预览/最近）。统一鉴权：URL 带 `?api_key={token}`（Emby 支持，自鉴权、免 header）。
- Emby mappers：`BaseItemDto → MediaCatalog`（库）/`MediaItemCard`（条目）。图片 URL 由 `Id`+`ImageTags.Primary` 拼 `/Items/{id}/Images/Primary?api_key={token}`；`RunTimeTicks/1e7→秒`；`UserData.Played→watched`。
- `EmbyMediaBackend implements MediaBackend`：实现 `getCatalogs` / `getHomeSummary`（返回空 map 占位）/ `getContinueWatching`（`/Items?Filters=IsResumable` 或空）/ `getCatalogPreviewItems`；**其余方法（详情/季集/筛选/搜索/getPlayback）throw `UnsupportedError`**，由后续阶段实现。
- `MediaBackendProvider` 按 `BackendSessionProvider.currentKind` 路由：emby+已认证 → `EmbyMediaBackend(EmbyApi, connection)`；否则 Feiniu（现状）。`main.dart` 把该 provider 从 `ProxyProvider<NasProvider>` 升为依赖 `NasProvider`+`BackendSessionProvider`。
- 首页数据加载层：Emby 激活时**不走 FeiniuApi 直连**的继续观看/分类预览，改走 `backend.getContinueWatching()`/`getCatalogPreviewItems()`；**飞牛分支保持 FeiniuApi 直连不变**（保住续播进度，零回归）。

**不做（OUT，本切片）**
- Emby 详情、播放、搜索、分类筛选（EmbyMediaBackend 对应方法 throw `UnsupportedError`，由 gate / 入口拦截，不在本切片点开）。
- 不改飞牛首页任何行为（飞牛分支零改动）。
- 不接 Emby 图片 header 鉴权路线（先用 `api_key` 自鉴权 URL；若实测首页图片加载器破坏该 URL，再退到 `MediaImageRef.headers`）。

## 4. 边界决策

1. **「首页数据源按后端选择」放数据加载层、不放 UI 渲染**：`media_list_screen._fetchHomeData` 当前已直接 `FeiniuApi(provider)`，本就是数据层分支。改成「Feiniu 走 FeiniuApi 直连续播；Emby 走 backend」——判定用 `BackendSessionProvider.currentKind`（或 backend 能力位），**不在 UI widget 写 `if(isEmby)`**。卡片渲染、`_catalogToMediaItem` 转换对两后端一致。
   - 为什么不统一走 `backend.getContinueWatching`：飞牛续播进度（`ts`/`watchedTs`）不在 `MediaItemCard`，统一走会让**飞牛首页丢续播进度条**（Task 6 暂缓富 item 模型的原因）。故保飞牛直连、Emby 走 backend，是当前不回归飞牛的唯一选择。
2. **EmbyMediaBackend 未实现方法 throw `UnsupportedError`**：本切片只点亮首页，详情/播放入口在 Emby 态不可达（由后续 gate 拦截）。明确抛错好过返回假数据。
3. **Provider 路由与 Codex Task 8 重叠**：Codex 登录后端 Task 8 也是「Provider factory 收口」。本切片由 Claude 实现路由；提交前 `git diff --cached` 复核、pathspec 提交，且**只动 `MediaBackendProvider`+`main.dart` 路由部分**，不碰 Codex 的 `BackendSessionProvider`/store/登录页。若 Codex 已先改，复用其成果、避免重复。

## 5. 图片鉴权

Emby 图片 URL 直接带 `?api_key={token}` 自鉴权（最简、免 header）。风险：首页图片加载器（`ApiUrlHelper.imageCandidates` + 飞牛 token 拼接）可能对已含 query 的 URL 再追加飞牛 token、或走飞牛 origin 改写。**Task 6 验证点**：实机看 Emby 分类条缩略图能否加载；若被破坏，退到 `MediaImageRef.headers` 方案 + 图片 widget 读 headers（Codex 风险 2 的兑现）。

## 6. 任务拆分（每步可编译、单测、单独 pathspec 提交）

1. **EmbyApi 读端点** `getUserViews` / `getItems`（带 api_key），fixture 单测（脱敏 JSON，不触真服）。
2. **Emby mappers** `mapEmbyView→MediaCatalog` / `mapEmbyItemCard→MediaItemCard`（图片 URL / ticks / Played），单测。
3. **EmbyMediaBackend**（首页四法实现 + 其余 `UnsupportedError`），fake EmbyApi 编排单测。
4. **Provider 路由**（`MediaBackendProvider` 依赖 `BackendSessionProvider` 按 kind 选；`main.dart` 升 ProxyProvider2），单测；analyze。
5. **首页加载层 Emby 分支**（继续观看/分类预览 Emby 走 backend、飞牛不变），**实机验证**。
6. **图片鉴权实机核对** + 看板更新 + 交 Codex 深审。

> 1–3 纯数据层、无需真服务器；4–6 需用户 Emby 服 `flutter run` 验证。

## 7. 明确不做

- 不接 Emby 详情/播放/搜索/筛选（对应方法 throw）。
- 不改飞牛首页行为；不在 UI 写 `if(isEmby)`。
- 不碰 Codex 的 `BackendSessionProvider`/连接 store/登录页；不夹带 `HANDOFF.md`/`MpvPlaybackController.kt`/Codex 未提交改动。
- 不提交真实 server/token/userId/password；测试用脱敏 fixture / fake client。
