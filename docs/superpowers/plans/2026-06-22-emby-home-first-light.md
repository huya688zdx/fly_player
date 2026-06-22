# Emby 首页首光 实施计划

设计：`docs/superpowers/specs/2026-06-22-emby-home-first-light-design.md`
日期：2026-06-22
原则：每步可编译、单测、**pathspec 提交**（防 Codex 并行 stage 夹带）；提交前查 `git status --short`、`git diff --cached --name-only`；不碰 Codex 的 `BackendSessionProvider`/store/登录页；不夹带 `HANDOFF.md`/`MpvPlaybackController.kt`。1–3 纯数据层无需真服；4–6 需用户 Emby 服实机验证。

## Task 1：EmbyApi 读端点

- `lib/api/emby_api.dart`：加 `getUserViews({serverUrl, userId, accessToken})`（`GET /Users/{uid}/Views`）、`getItems({serverUrl, userId, accessToken, parentId, limit, isResumable, fields})`（`GET /Users/{uid}/Items`）。URL 带 `?api_key={token}`。返回 `List<Map<String,Object?>>`（BaseItemDto 原样，映射留 mapper）。复用现有 `_dio`/`normalizeServerUrl`/`_jsonHeaders`。
- `test/api/emby_api_test.dart`：用 `Dio` + `DioAdapter`（或注入 fake）喂脱敏 JSON fixture，断言 URL 拼装（含 api_key/ParentId/Limit）与解析。
- 验证：`flutter test test/api/emby_api_test.dart`；`flutter analyze lib/api/emby_api.dart test/api/emby_api_test.dart`。

## Task 2：Emby mappers

- `lib/media_backend/emby/emby_media_mappers.dart`：`mapEmbyView(Map, {serverUrl, token}) → MediaCatalog`、`mapEmbyItemCard(Map, {serverUrl, token}) → MediaItemCard`。图片：`/Items/{Id}/Images/Primary?tag={ImageTags.Primary}&api_key={token}`；`durationSeconds = RunTimeTicks ~/ 10000000`；`watched = UserData.Played == true`；title=`Name`；type=`Type`/`CollectionType`。
- `test/media_backend/emby_media_mappers_test.dart`：fixture 断言字段映射 + 图片 URL + ticks + Played。
- 验证：`flutter test test/media_backend/emby_media_mappers_test.dart`；analyze。

## Task 3：EmbyMediaBackend

- `lib/media_backend/emby/emby_media_backend.dart`：`class EmbyMediaBackend implements MediaBackend`，构造持 `EmbyApi` + 连接（serverUrl/userId/accessToken）。实现 `getCatalogs`（getUserViews→mapEmbyView）/`getHomeSummary`（`{}`）/`getContinueWatching`（getItems isResumable→mapEmbyItemCard）/`getCatalogPreviewItems`（getItems parentId→card）。**其余方法（getItemDetail/getItemSeasons/getSeasonEpisodes/searchItems/getCatalogFilterSchema/queryCatalogItems/getPlayback）throw `UnsupportedError('Emby <方法> 未实现（首页首光阶段）')`**。
- `test/media_backend/emby_media_backend_test.dart`：fake EmbyApi（覆写 getUserViews/getItems，构造只配 Dio）+ 编排断言；并断言未实现方法 throw。
- 验证：`flutter test test/media_backend/`；analyze。

## Task 4：Provider 按 kind 路由

- `lib/providers/media_backend_provider.dart`：构造改为 `MediaBackendProvider(this.nasProvider, this.sessionProvider)`；`backend` getter 按 `sessionProvider.currentKind` 选——`emby && currentConnection.isAuthenticated` → 缓存 `EmbyMediaBackend(EmbyApi(), connection)`（缓存键含 kind+serverUrl+token）；否则现有 Feiniu 分支不变。
- `lib/main.dart`：`ChangeNotifierProxyProvider<NasProvider, MediaBackendProvider>` → `ChangeNotifierProxyProvider2<NasProvider, BackendSessionProvider, MediaBackendProvider>`。**仅改这两处路由接线**，不碰 Codex 其它。
- `test/providers/media_backend_provider_test.dart`：扩——feiniu kind→FeiniuMediaBackend（现状保持）；emby kind+认证→EmbyMediaBackend；kind 变更清缓存。
- 验证：`flutter test test/providers/`；`flutter analyze lib/providers lib/main.dart`；全量 analyze 对比基线。

## Task 5：首页加载层 Emby 分支

- `lib/screens/media_list_screen.dart`：`_fetchHomeData`/`_backgroundRefresh`/`_refreshContinueWatching` 里，按 `context.read<BackendSessionProvider>().currentKind`（数据层，非 UI 渲染）——Emby 时继续观看走 `backend.getContinueWatching()`、分类预览走 `backend.getCatalogPreviewItems()`；**飞牛分支保持 `FeiniuApi(provider)` 直连不变**（零回归）。`_catalogToMediaItem` 与卡片渲染两后端共用。
- 验证：`flutter analyze lib/screens/media_list_screen.dart`；**用户 `flutter run`（Emby 账号登录）实机验证**首页分类条 + 预览 + 继续观看显示；切回飞牛账号验证飞牛首页零回归。

## Task 6：图片鉴权核对 + 看板 + 收口

- 实机核对 Emby 分类条/卡片缩略图能否加载（api_key 自鉴权 URL 是否被首页图片加载器破坏）。若破坏→退 `MediaImageRef.headers` 方案，图片 widget 读 headers。
- 更新 `docs/superpowers/public-media-frontend-status.md`：Emby 首页首光记录、提交、验证、待 Codex 深审。

## 明确不做

- 见设计 §7。EmbyMediaBackend 未实现方法一律 throw；不改飞牛首页；UI 不写 `if(isEmby)`；不碰 Codex 未提交改动；不提交真实凭据。
