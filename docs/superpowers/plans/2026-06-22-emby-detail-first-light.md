# Emby 详情页首光 实施计划

> 配套设计:`docs/superpowers/specs/2026-06-22-emby-detail-first-light-design.md`。
> 范围:只做展示 + 新建中立详情屏按后端路由。每步单测 + pathspec 单独提交。

## Task 1 — `EmbyApi.getItem(itemId)`

- 文件:`lib/api/emby_api.dart`、`test/api/emby_api_test.dart`。
- 实现:`GET /Users/{userId}/Items/{itemId}?api_key=&Fields=Overview,Genres,People,ProviderIds,ProductionLocations`,
  返回单个 `BaseItemDto` `Map`(用 `_asMap`,非 `Items` 数组)。
- 测试:fake Dio adapter 返回单条目 JSON,断言 URL/query/返回 Map。
- 提交:`flutter test test/api/emby_api_test.dart` → PASS 后 pathspec 提交两文件。

## Task 2 — `mapEmbyItemDetail`

- 文件:`lib/media_backend/emby/emby_media_mappers.dart`、`test/media_backend/emby_media_mappers_test.dart`。
- 实现:`BaseItemDto → MediaDetail`(字段口径见设计 §3.2),复用 `_primaryImage`/`_backdropImage`,
  新增 logo / people / 外部 ID / UserData 抽取。
- 测试:喂含 Genres/People/ProviderIds/RunTimeTicks 的 Map,断言各字段 + 演职员头像 URL 自鉴权。
- 提交:`flutter test test/media_backend/emby_media_mappers_test.dart` → PASS 后 pathspec 提交。

## Task 3 — `EmbyMediaBackend.getItemDetail`

- 文件:`lib/media_backend/emby/emby_media_backend.dart`、`test/media_backend/emby_media_backend_test.dart`。
- 实现:`getItemDetail` 改为 `api.getItem` + `mapEmbyItemDetail`;fake api 增 `getItem`(记录 lastItemId)。
- 测试:断言 getItemDetail 返回正确 MediaDetail、不再 throw;getItemSeasons/getSeasonEpisodes/getPlayback/
  searchItems 仍 throwsUnsupportedError。
- 提交:`flutter test test/media_backend/emby_media_backend_test.dart` → PASS 后 pathspec 提交。

## Task 4 — 中立详情屏 `MediaDetailScreen`

- 文件:`lib/screens/media_detail_screen.dart`、`test/screens/media_detail_screen_test.dart`。
- 实现:StatefulWidget,`initState` 调 backend.getItemDetail;加载态骨架 / 错误态重试 / 成功态用
  复用组件(`ImmersiveDetailBackground`/`DetailHeader`/`DetailMetaLines`/`DescriptionSection`/
  `DetailTagChip`/`CreditsSection`)从 `MediaDetail` 渲染;播放入口占位「即将到来」disabled。
  演职员文案走 `CreditPersonPresenter`。
- 测试:用 fake `MediaBackend`(只实现 getItemDetail,其余 throw)+ `MediaBackendProvider` 注入,
  pump 后断言标题/简介/题材/演职员文字出现、播放按钮为占位态。
- 提交:`flutter test test/screens/media_detail_screen_test.dart` + `flutter analyze` → PASS 后 pathspec 提交。

## Task 5 — 路由接线 + 看板

- 文件:`lib/screens/media_list_screen.dart`、`docs/superpowers/public-media-frontend-status.md`。
- 实现:`_openItemDetail` item 分支按 `backend.capabilities.kind`——非飞牛 push `MediaDetailScreen`
  (传 itemId + 当前 card 占位 + heroTag),飞牛走原路。person 分支不动。
- 验证:`flutter analyze lib/screens/media_list_screen.dart`;实机:Emby 态点开影片进详情、
  飞牛态详情页无回归。
- 提交:pathspec 提交;实机通过后更新看板,交 Codex 深审。

## 风险与边界

- `initialCard` 占位字段(海报/背景/标题)来自列表 `MediaItemCard`,与详情可能短暂不一致,
  详情到达即覆盖——可接受(飞牛页同样有 initialItemDetail 占位)。
- 演职员头像在 Emby 为 `?api_key=` 直链,依赖图片加载器自鉴权分支(首页首光已验证可用)。
- 若某影片无 People/Genres,对应区块应空态隐藏,不报错。
