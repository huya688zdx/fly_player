# 页面进入/退出/切换掉帧审计报告（2026-07-26）

## 方法

多智能体 workflow（25 个 agent）分 6 个维度并行扫描转场链路（转场层 / 详情页首帧 /
动态取色 / blur-saveLayer 残留 / 图片与 Hero / pop 与 provider 重建），产出 33 条
原始发现，去重后 27 条，其中 high/medium 19 条逐条经独立核查员对抗性验证（亲读
代码、以驳倒为目标）：**12 条成立、7 条驳回**，另有 8 条 low 未核实。

背景约束：全部路由转场 380ms（`AppMotion.routeEnter/routeExit`），Impeller-Vulkan
（无 raster cache），真机高刷 80-172fps（帧预算最低 8.3ms）。

## 成立的掉帧点与修复

### 1. 转场结构：整页 FadeTransition 贯穿 380ms（high，已修）

所有路由（12 处 `leftToRightPageTurnRoute` + pane/splitPane）收敛到
`_lightweightPageTransition`：alpha 0→1 淡入贯穿整个 380ms，整页级分数透明度在
Impeller 下每帧退化为整屏 saveLayer 离屏合成，且转场全程新旧两页叠绘。pop 首帧
还叠加下层页整棵子树重新 layout/paint——正是"退出 pop 掉帧"中上一轮修 BackdropFilter
后仍残留的"跨页合成"一半。

**修复**（`lib/ui/app_transitions.dart`）：淡入压缩到转场前 40%（约 150ms，
`Interval(0.0, 0.4)`），pop 反向同样只在头 40% 淡出；alpha 到 1.0/0.0 后
FadeTransition 跳过 OpacityLayer，saveLayer 只存在于转场头部一小段。同时修正了
声称有 secondaryAnimation 退场动效的脱节注释。

### 2. RouteTransitionGate 只看 primary animation，下层路由场景闸门失效（high，已修）

`isTransitioning`/`of()` 只查 `ModalRoute.animation`；当本页是转场中的**下层**路由
（被 push 覆盖 / pop 揭开）时 primary 恒为 completed，闸门零延迟放行，所有"等转场
结束再应用"的重活照样砸进转场窗口。

**修复**（`lib/ui/route_transition_gate.dart`）：两个 API 同时检查
`secondaryAnimation`；`of()` 在两条动画上挂共享监听，任一状态变化后重查两条，
全部稳定才 resolve（覆盖 primary 刚完成时 secondary 又启动的快速连续导航）。

### 3. play_detail 飞牛 Phase-1 无闸门（high，已修）

Phase-1 回调 setState（骨架→3500 行正文整树替换 + crossFadeSwitch 双树叠放 +
三个入场动画 controller + hero 大图开始下载）直接落在 380ms 转场中段；同文件
Phase-2 与 tv_detail/tv_season 都有闸门，唯独这里漏了。

**修复**（`lib/pages/play_detail_page.dart`）：Phase-2 与下载画质预取**先行发起**
（网络与转场并行），随后 `await RouteTransitionGate.of(context)` 后再 setState +
启动入场动画。

### 4. play_detail Emby/中立分支同款遗漏（medium，已修）

非飞牛分支 getItemDetail 回调 setState 无闸门，且描述/演职员一帧内全量挂载 +
三个 controller 同帧 forward。**修复**：setState 前加同款闸门（对齐 tv_detail
中立分支 `:323` 的既有模式）。

### 5. tv_detail 快路径后台刷新无闸门（medium，已修）

`initialItemDetail` 快路径 initState 即发起 `_refreshBaseDetail`，回包 50-200ms
必落转场窗口，无闸门整页重建（全文件唯一漏网的网络回调 setState）。
**修复**（`lib/pages/tv_detail_page.dart`）：成功与 catch 分支 setState 前均过闸。

### 6. 首页 pop 返回瞬间刷新续播行（high，已修）

`Navigator.push` 返回的 Future 在 pop 动画**第一帧前**就 resolve，
`_refreshContinueWatching` 的回包 setState 整页重建 CustomScrollView，与 pop
退场动画同窗叠加。**修复**（`lib/screens/media_list_screen.dart`）：应用结果前过闸
（依赖修复 2 才对下层路由生效），并用 `HomeDataSnapshot.itemsEqual`（guid+ts）
短路无变化的整页重建。

### 7. 动态主题 didUpdateWidget 绕过闸门 + Theme 结构性重挂载（high，已修）

详情数据到达触发 props 变化时，`DynamicPageThemeScope.didUpdateWidget` 命中 seed
缓存直接翻 `_seed`，绕过 `_applyResolvedSeedSetState` 的转场闸门；且 build 里
`Theme` 是条件包裹，seed null→非 null 是元素树**结构**变化，整棵页面子树被
re-inflate（State 全部重建）。

**修复**（`lib/widgets/detail/dynamic_page_theme_scope.dart`）：didUpdateWidget
命中路径转场中改走 `_applyResolvedSeedAfterTransition`；build 始终包 `Theme`
（无 seed 时透传 parentTheme），主题落地只是 data 变化不再重挂载。

### 8. 首帧冷跑 2 次 ColorScheme.fromSeed（high，部分修复）

initState 同步命中 seed 缓存时，首帧 build 内冷跑 2 次 HCT 求解（各 ~16ms，项目
自己的 profile 注释背书）+ 整套 ThemeData 构建；microtask 预热对同帧 build 无效。
持久化 seed 缓存预载 256 条而 scheme 缓存仅 32 条 LRU，"seed 热 scheme 冷"是常态。

**已修**：`_schemeCacheMaxSize` 32→96（`lib/theme/dynamic_theme_mapper.dart`），
覆盖一次会话的浏览深度。**补修（2026-07-26 第二轮）**：新增
`DetailThemePrewarmer`（`lib/ui/detail_theme_prewarmer.dart`），在
`AdaptiveDetailNavigator.open`（收藏/题材/人物作品/选集/合集全走此口，按
`AdaptiveDetailRequest.themePageKey`）与首页 `_openItemDetail` 两分支的 push 前，
按目标页 pageKey 查 seed 缓存并预热 scheme——seed 命中时详情首帧 build 纯缓存
命中，不再冷跑 2×~16ms HCT。**遗留**：持久化缓存加载后 idle 分片预热最近 N 条
（优先级低，tap 预热已覆盖主路径）。

### 9. Emby 图片请求原图（high，已修）

`_imageUrl` 不带尺寸参数，backdrop 常见 1920~3840 宽数 MB JPEG，下载/解码/纹理
上传恰落转场窗口；飞牛管线的 w=1200 + 预取 + 低清铺底三道防护对 Emby 全部失效。

**修复**（`lib/media_backend/emby/emby_media_mappers.dart`）：按用途加
`maxWidth`（Backdrop 1280 / Primary 400 / 头像 360 / Logo 800）+ `quality=90`；
URL 即 ImageCache 缓存键，预取与展示天然同参。测试断言已同步更新。
**补修（2026-07-26 第二轮，H-019/H-021 方向）**：
- `AdaptiveDetailRequest` 新增中立 `heroImageRefs`（`MediaImageRef` 列表），
  `_maybePrecacheHero` 对完整直链按背景组件同款缓存键
  （`DetailHeroImage.directUrlPrecacheProvider`，不再以 NAS token 为前提）push 前
  预取；飞牛相对路径回退旧 `heroBackdropPath` 管线。卡片与详情的 backdrop URL 由
  同一 mapper 函数产出（同 tag + maxWidth=1280），逐字节一致必命中。
- `MediaLibraryItem` 新增 `backdropUrl` 直链字段，首页 `_cardToMediaItem` 与收藏页
  `_cardToLibraryItem` 桥接时保留（原先丢弃）；首页 Emby 回退 push 分支、收藏页、
  题材页、人物作品页均在点击时传入图引用。
- 低清铺底对 Emby 生效：play_detail / tv_detail 中立分支在有 backdrop 时用海报
  直链垫底（列表网格已加载过同 URL，多数纯缓存命中）；
  `ImmersiveDetailBackground` 低清层放行自鉴权 URL（`api_key=`，原先空 NAS token
  直接不建层）。

### 10. 背景大图 180ms 淡入撞转场尾段（medium，已修）

大图首帧就绪常落 push 转场内，`AnimatedOpacity` 淡入在 hero 区域（最高 78% 屏高、
低清+大图两张位图）叠加离屏合成，恰逢首帧纹理上传（项目注释自证 ~90ms 尖峰）。
**修复**（`lib/widgets/detail/immersive_detail_background.dart`）：转场中跳过淡入
直接不透明呈现（缓存命中的 `wasSynchronouslyLoaded` 快路径不动）。
**补修（2026-07-26 第三轮）**：主图首帧就绪后延时 260ms（盖过 180ms 淡入，避免
中途露底色）卸载低清铺底层，不再永久参与每帧合成；URL 换源/兜底切换时复位重挂。

### 11. 弹幕设置页 pop 返回冗余重载（medium，已修）

pop 动画第一帧前 `await push` 即返回，随即 `loadAll` 全量反序列化弹幕源库 +
整页 setState 落在退场转场里；且该次重载是冗余的——管理页内任何增删已经
`store.changes` 监听触发过 `_load`。**修复**（`lib/screens/danmaku_settings_screen.dart`）：
删除 pop 后的 `await _load()`。**遗留**：本页只消费一个 int 计数，store 可提供
轻量 `count()` 免全量物化。

### 12. 平行窗口入站主题绕过转场收口（medium，已修）

pane 侧推来新 seed 时 `_publishRuntimeDynamicThemeToScope` 直接
notifyListeners → 全库 433 处 `context.appColors` 依赖方同帧 rebuild（≈整棵
App 树），若主窗口恰在转场中直接砸进动画窗口；Scope 侧全局 flush 有
`anyRouteTransitioning` 收口，入站桥路径绕过了它。
**修复**（`lib/providers/app_theme_provider.dart`）：发布收口点转场中用 postFrame
轮询推迟到稳定，单一 scheduled 标志合并多次入站，天然应用最新种子。

另修：`dynamic_page_theme_scope.dart` 5 处转场帧内裸 `debugPrint` 补 `kDebugMode`
包裹（release 仍执行字符串插值+logcat 写入，low-3）。

## 被驳回的指控（7 条，未改动）

- **详情页 section pop 动画与转场同窗**：主体已被既有闸门/320ms 定时器挡在窗口外。
- **底部弹层整屏 saveLayer**：saveLayer 范围由实际绘制 bounds 决定，透明 barrier
  不计入；barrierColor 也并非 transparent。
- **_ProviderGate watch 引发整页重建**：child 是 final 字段同一实例，
  `Element.updateChild` 身份短路，这正是 Provider 官方 child-caching 模式。
- **PaletteGenerator UI isolate 全图量化**：兜底可达路径全部是带 w=320/360 的
  服务端缩图；会失败的场景（entry-token）Dart 侧同样 401 根本跑不到量化。
- **列表图批量淡入 saveLayer**：指控张冠李戴——海报卡组件本就无淡入。
- **合集列表缩略图解码原图**：该页数据源纯飞牛（w=280），且有闸门挡在转场外
  （Emby 接入时需补 `cacheWidth`，前瞻项）。
- **Hero 飞行重解码**：全仓 Hero 均无目标端配对，飞行从未发生（heroTag 透传链
  是死代码，可择机删除或补目标端）。

## 待办（未修，按价值排序）

~~1. 取色预热前置~~、~~2. Emby precache 链路~~：均已于 2026-07-26 第二轮落地
（见发现 8 / 发现 9 的"补修"段）。
~~3. 低清铺底层就绪后卸载~~：第三轮落地（见发现 10 的"补修"段）。
~~4. low 项~~ 第三轮处置：tv_season 选集视图设置回调已过闸（等待期间用户手动
切换过则不覆盖）；seed 持久化 debounce 写盘已挂调度器 idle 位（两个取色缓存）；
`enableRealtimeBlur` 死代码已删（连带 `_blurImageLayer`/`BackdropFilter` 分支，
与"回归纯色"决策一致）。**判不修**：`_buildRoute` 兜底同步 jsonDecode——仅旧式
无 payload-token 回退链路才携带内联 JSON（常规导航走 payload store 不解码），
改造需动三个路由壳契约，收益/风险不成比例；heroTag 透传（13 文件 45 处）留待
"补 Hero 目标端 or 整体拆除"一并决策，不做半截清理。

5. **实机验收**：DevTools raster/UI 线程帧时长 + saveLayer 计数对比修复前后
   （进详情页、pop 返回、Emby 详情三条路径）。

## 验证状态

- `flutter analyze`：0 告警。
- `flutter test`：444/444 通过（4 条 Emby 图片 URL 断言按新格式同步更新）。
- 第二轮补修后复验：`flutter analyze` 0 告警、`flutter test` 445/445 通过。
- 第三轮（低清卸载 + low 项）后复验：`flutter analyze` 0 告警、全量测试通过。
- 实机帧率验证未做（无设备），见待办 5。
