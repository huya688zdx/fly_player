# 页面跳转 / 取色 / 呈现性能改进计划

> 交付对象：执行模型（Opus 4.8）。本文档自包含：包含背景、文件地图、已确认的问题点（带 file:line）、
> 假设（需真机验证后才动手）、分阶段任务与验收标准。
> 范围：首页 → 剧集详情(tv_detail) → 季详情(tv_season_detail) → 集/电影详情(play_detail) 的进入/退出
> 帧率不稳、取色逻辑与颜色分配、页面结构与组件加载呈现。
> **不在范围**：播放器页（/player）、原生分屏、弹幕。

---

## 0. 背景与核心结论

用户感知：详情页进入/退出时帧率不稳（掉帧、卡顿感）。

读码结论：**单个环节都做过优化（缓存、warmUp、RepaintBoundary 都在），问题在于"进入页面的前 ~500ms
内多条独立的重活管线互相叠加，且没有任何一条与路由转场动画(380ms)协调"**。叠加的管线有：

1. 路由转场动画本身（380ms enter / 380ms exit）
2. 详情接口请求返回 → 全页 setState（骨架屏 → 正文整树替换）
3. 延迟分段加载：4 次串行 setState（每次全页重建）
4. 取色 seed 解析（90ms timer → native 通道）→ 本地 AnimatedTheme 140ms 全页 ThemeData.lerp
5. ambient tint 颜色动画：每 tick setState 重建**整个页面**（140ms ≈ 8 帧全页 build）
6. 全局运行时主题同步：120ms debounce + 32ms 延迟 → 重建 **MaterialApp.builder 下整棵 App 树**
   ——时间点恰好落在 380ms 转场窗口中段
7. 大图解码：hero 背景图最高 1440px 宽，进入时才开始请求+解码

这些时间常数（90/120/140/180/320/380ms）彼此独立设计，组合起来保证了转场期间总有重活在跑。

---

## 1. 文件地图（执行前先通读）

| 文件 | 作用 |
|---|---|
| `lib/main.dart` | URI 路由解析 `_buildRoute()`；`_FrameTimingLogger`（已有帧率日志，验证工具）；`MaterialApp.builder` 中的 `AppRuntimeColorScopeBuilder`（全局运行时颜色作用域） |
| `lib/ui/app_transitions.dart` | 所有路由转场；`leftToRightPageTurnRoute` 是详情页统一入口 |
| `lib/ui/app_motion.dart` | 时间常数：`routeEnter/routeExit = 380ms` |
| `lib/widgets/detail/dynamic_page_theme_scope.dart` | 页面级动态主题作用域（核心，809 行）：seed 解析、AnimatedTheme、ambient tint 动画、全局主题同步队列 |
| `lib/theme/dynamic_theme_seed_extractor.dart` | 图片 → 4 个 seed 色（native 通道优先，PaletteGenerator 兜底）；图片 URL 键的内存+SharedPreferences 持久缓存 |
| `lib/theme/dynamic_theme_runtime_controller.dart` | pageKey 键的第二层 seed 缓存（同样持久化到 prefs） |
| `lib/theme/dynamic_theme_mapper.dart` | seed → AppThemeColors（ColorScheme.fromSeed/HCT，~16ms/次，已有 LRU 缓存 + warmUp） |
| `lib/providers/app_theme_provider.dart` | `setRuntimeDynamicTheme`/`clearRuntimeDynamicTheme`（1482 行）：运行时主题栈、跨引擎广播、warm 后 publish |
| `lib/theme/app_theme.dart:1130-1319` | `AppRuntimeColorController` / `AppRuntimeColorScope(Builder)` / `DynamicPageThemeSnapshot` / `context.appColors` 取色优先级 |
| `lib/widgets/detail/immersive_detail_background.dart` | 详情页 hero 背景（视差/缩放/渐隐）；内含**第三套**独立取色（monet tint + 自有缓存 + PaletteGenerator） |
| `lib/pages/tv_detail_page.dart` (1586行) | 剧集详情（季列表入口） |
| `lib/pages/tv_season_detail_page.dart` (2393行) | 季详情（集列表） |
| `lib/pages/play_detail_page.dart` (2626行) | 集/电影详情 |
| `lib/pages/media_collection_detail_page.dart` (1330行) | 合集详情 |
| `lib/screens/media_list_screen.dart` (711行+parts) | 首页（缓存优先+后台刷新） |
| `lib/ui/media_poster_card.dart` | 海报卡（Image.network + cacheWidth + FilterQuality.none，已较优） |
| `lib/ui/adaptive_detail_navigator.dart` | 列表 → 详情的统一跳转入口（点击处，可做预取） |

Android native 取色通道：`fly_player/theme_sampler` → `extractDynamicThemeSeed`（Kotlin 侧已存在）。

---

## 2. 已确认的问题点（按优先级）

### P1. ambient tint 动画每 tick 全页重建
`dynamic_page_theme_scope.dart:732-734`：
```dart
void _onColorAnimTick() {
  if (mounted) setState(() {});
}
```
`builder(context, animatedTint)` 包含整个页面（Scaffold + CustomScrollView + 全部 sliver）。
tint 140ms 动画期间每帧全页 build；且与 AnimatedTheme 的 ThemeData.lerp 同时进行。
**这是进入详情页时帧率不稳的最大单点。**

### P2. AnimatedTheme 全量 ThemeData.lerp
`dynamic_page_theme_scope.dart:799-806`：seed 应用时 `AnimatedTheme(duration: 140ms)` 包住整页。
ThemeData.lerp 每帧 lerp 全部 component themes，开销大且会令所有依赖 Theme.of 的 widget 每帧重建。
注意页面实际取色走 `context.appColors`（`DynamicPageThemeSnapshot`，app_theme.dart:1310），
Theme 数据只服务于 Material 组件——全量 lerp 的收益与成本不成比例。

### P3. 全局主题同步落在转场窗口内 + 重建整棵 App 树
链路：seed 解析完成 → `_scheduleGlobalThemeSync()`（120ms debounce，scope:570-587）
→ postFrame → `provider.setRuntimeDynamicTheme`（provider:576）→ warm 后
`AppRuntimeColorController.notifyListeners` → `AppRuntimeColorScopeBuilder.setState`
（app_theme.dart:1260-1271）→ **MaterialApp.builder 之下整树重建**。
进入页面后 ~120-250ms 触发，正处于 380ms 转场动画中段。退出时旧页 hold/restore 逻辑
（provider:705-803 的 restore_on_main / defer_top_clear）同样可能在 pop 动画期间 publish。

### P4. 页面初始化的重活与转场动画零协调
- 各详情页 `initState` 里立即 `_load()`（tv_detail:160, play_detail:333, tv_season:178）。
- tv_detail `_startDeferredLoad`（tv_detail:406-468）：180ms 后 description pop +
  之后每 140ms 一次串行 setState（seasonItems → genres → locateMap → playInfo，共 4+ 次全页重建），
  全部落在 380ms 转场窗口内。
- seed 解析 90ms timer（scope:271）也在窗口内。
- 没有任何代码引用 `ModalRoute.animation` 来推迟重活。

### P5. 大图在转场期间解码
`immersive_detail_background.dart:469`：hero 背景 cacheWidth clamp(560,1440)；进入页面才发请求。
没有 `precacheImage`。列表页点击时本可以用已知 URL 预取。另外取色用的 360px 小图
（tv_detail:1119-1126）与 hero 大图是两次独立请求。

### P6. 三套取色系统并存
1. `DynamicThemeSeedExtractor`（image-url 键缓存 + prefs 持久化）
2. `DynamicThemeRuntimeController`（pageKey 键缓存 + **另一份** prefs 持久化）
3. `ImmersiveDetailBackground` 自带 monet tint（`_immersiveTintCache` + 自己的 PaletteGenerator 兜底，
   immersive_detail_background.dart:11-30, 366-433）
1↔2 是双层缓存（可接受但每存一个 seed 都全量 JSON 重写各自 prefs blob，256 条 ×2）；
3 是真正的重复——tv_detail 已传 `ambientTintOverride` 把它短路，但其他页面 `useMonetTint=true` 时
会再跑一次 PaletteGenerator（UI isolate 上的量化）。

### P7. 巨型单 State 页面，任何 setState 全页重建
play_detail 2626 行 / tv_season 2393 行单 State。
`_handleDownloadTasksChanged() => setState((){})`（play_detail:359-362, tv_season:198-201）：
下载任务任何变化都全页重建，详情页可见期间下载进行中会持续触发。

### P8. 路由层同步 jsonDecode
`main.dart:296-313, 327-348`：`/detail/item`、`/detail/season` 无 payloadToken 时在 push 帧同步
jsonDecode 完整 detail JSON。已有 `DetailRoutePayloadStore` token 机制，但 fallback 路径仍存在
（原生壳冷启动路径用 query 传 JSON）。

### 备注（非问题，勿动）
- `DynamicThemeMapper` 的 scheme 缓存 + warmUp、provider 的 isWarm 检查：已是正确设计，保留。
- scope `dispose()` 不清全局主题（sticky theme，scope:176-189 注释）：刻意为之，保留。
- `ImmersiveDetailBackground` 的图层缓存（`_ensureImageLayers`）+ RepaintBoundary：已优化，保留。
- 滚动用 `ValueNotifier<double>` 只重建背景：已优化，保留。
- `MediaPosterCard` cacheWidth/FilterQuality.none/gaplessPlayback：已优化，保留。

---

## 3. 分阶段执行计划

> 原则：每阶段独立可验证、可单独提交。先测量后改动；改完跑 `flutter analyze` + 既有测试。
> 真机验证手段：debug 包已有 `_FrameTimingLogger`（main.dart:89-200），
> 过滤 `[PERF][FRAME]` 看 jank 行与 summary（slow60/jank30/avgBuild/maxBuild）。

### Phase 0 — 基线测量（不改行为）
1. 给 `_FrameTimingLogger` 增加"窗口标记"能力：提供静态方法
   `markWindow(String label)`，此后 N 帧（如 90 帧）单独汇总输出
   `[PERF][FRAME][WINDOW][label]`。在 Navigator push/pop 时打标
   （可用 `NavigatorObserver` 挂在 MaterialApp 上，label 用 route name）。
2. 真机走一遍固定路径并记录基线：首页→剧集详情→季详情→集详情→逐级返回；首页→电影详情→返回。
   每步记录 window summary（avgBuild/maxBuild/jank30）。
3. 把基线数字写进本文档末尾的"测量记录"节。

验收：能输出按路由切分的帧统计；基线数据已记录。

### Phase 1 — 转场协调（预期收益最大）
目标：380ms 转场窗口内只跑转场动画 + 骨架/已缓存内容，重活推迟到 `animation.isCompleted`。

1. 新建 `lib/ui/route_transition_gate.dart`：
   - `RouteTransitionGate.of(context)`：返回一个 `Future<void>`，在当前 `ModalRoute`
     的 enter 动画完成（`animation.isCompleted` 或 status==completed）时 resolve；
     若 route 已稳定则立即 resolve。同时提供同步 getter `isTransitioning`。
2. 详情页接入（四个页面同改）：
   - `_load()` 中**网络请求照常立即发**（不要推迟 IO），但**首次 setState 应用结果**
     若仍在转场中则等 gate 再 setState（结果先存字段）。骨架屏在转场期间保持稳定。
   - `_startDeferredLoad` 的 180ms 起始 timer 改为 `await gate` 后再起（即分段 pop 动画
     永远在转场结束后才开始）。
   - 串行分段加载的 4 次 setState 合并：genres/locateMap 两个静态 map 与 playInfo
     可以 `Future.wait` 后一次 setState（它们互不依赖；140ms 人为间隔删除）。
3. `DynamicPageThemeScope`：
   - `_scheduleResolve` 的 90ms timer 保留，但 `_resolve` 成功后若 `isTransitioning`，
     本地 seed 应用与 `_syncGlobalRuntimeTheme` 一律等 gate（缓存命中走 initState 同步路径的不受影响——
     进入时已有 seed 的页面第一帧就是终态，这是现状中最好的路径，保持）。
   - `_flushGlobalThemeSync` 前检查：若 navigator 有 route 在转场，postFrame 改为等转场完成后 flush。
     （实现可让 gate 暴露全局静态 `anyRouteTransitioning`，由 NavigatorObserver 维护。）
4. 退出路径：pop 时 `setRuntimeDynamicTheme`/restore 的 publish 同样过 gate，
   避免 pop 动画期间整树重建。

验收：Phase 0 同路径重测，push/pop 窗口的 jank30 显著下降（目标：转场窗口内 maxBuild < 16ms，
jank30 = 0~1）；视觉上骨架→内容的切换发生在转场结束后，无突兀（pop 动画期间页面静止是预期行为）。

### Phase 2 — 取色应用路径瘦身
1. **tint 动画去全页化**：`DynamicPageThemeScope` 把 `ambientTint` 从 builder 参数改为
   `ValueListenable<Color?>`（保留旧参数一个过渡版本也可，但目标是四个详情页都改为
   把 listenable 直接传给 `ImmersiveDetailBackground`，由背景内部 `ValueListenableBuilder` 消费）。
   删除 `_onColorAnimTick` 的 setState；AnimationController 驱动 ValueNotifier 更新即可
   ——背景已有 RepaintBoundary，tint 动画就只重绘背景层。
2. **替换 AnimatedTheme**：页面实际取色走 `context.appColors`（DynamicPageThemeSnapshot），
   Material 组件才用 Theme。改为：
   - `AppThemeColors` 增加静态 `lerp`（逐 Color.lerp），动画期间 lerp 的是 extension 颜色集，
     `DynamicPageThemeSnapshot` 每帧发新 colors（这本身仍会重建依赖者，所以配合：）
   - 实测两个方案取其优：(a) 干脆去掉 140ms 主题过渡动画，seed 应用一次到位
     （转场后应用，配合 Phase 1，用户感知是"页面进来后颜色淡入"，可仅给背景 tint 保留动画）；
     (b) 保留动画但只动画 snapshot colors，ThemeData 一次性切换。
     倾向 (a)：最简单且转场后单次重建可接受。
3. **统一 ImmersiveDetailBackground 取色**：删除其内部 monet tint 提取
   （`_refreshMonetTint`/`_extractTintWithPalette`/`_immersiveTintCache`），
   所有调用方一律由 `DynamicPageThemeScope` 传 `ambientTintOverride`（或上面的 listenable）。
   先 grep `useMonetTint: true` 的调用点确认覆盖。
4. **seed 持久缓存写放大**（低优先）：两个控制器各自全量 JSON 重写 prefs blob。
   改为只在 `AppLifecycleState.paused`/页面销毁时 flush 一次（已有 `flushPendingWrites` 钩子），
   120ms debounce 改为 2s+ 或仅生命周期 flush。

验收：进入有缓存 seed 的详情页：除转场外零额外全页 build；进入无缓存页：seed 应用恰好 1 次全页
build（+1 次全局 scope 重建，转场后）。tint 动画期间 `[PERF][FRAME]` 无 build 尖峰。

### Phase 3 — 页面重建粒度
1. 下载监听去全页化：play_detail / tv_season 的 `_handleDownloadTasksChanged` 全页 setState
   改为把"当前 item 的下载状态"收敛成局部 widget（`ListenableBuilder` 包按钮/行，或比较新旧
   record 不变则跳过 setState）。
2. 四个详情页的 build 拆分为 section 子 widget（每个 section 接收纯数据参数，const 化可缓存）：
   不追求一次拆完，优先 play_detail（最大）。拆分以"setState 来源"为界：header/操作行/简介/
   分集列表/演职员/文件信息各自独立。**注意保持现有动画行为不变**（pop 动画 controller 可以下放）。
3. `_RouteErrorScreen`、骨架屏等保持现状。

验收：`flutter analyze` 通过；既有 `test/` 全绿；详情页可见期间下载进行中，
`[PERF][FRAME]` 不再出现周期性全页 build。

### Phase 4 — 图像管线
1. **点击预取**：`AdaptiveDetailNavigator.open`（及首页 onTap 路径）在 push 前对目标 hero 背景
   发起 `precacheImage`（用与详情页相同的 URL+cacheWidth 计算逻辑——抽一个共享 helper，
   确保 URL/cacheWidth 完全一致才能命中 ImageCache）。列表页已有 item 数据，URL 可得。
   注意：fire-and-forget，不阻塞导航。
2. **小图占位**：`ImmersiveDetailBackground` 支持先显示 360px 取色图（多数情况已在缓存），
   大图 ready 后淡入替换（`frameBuilder` 已有淡入，加一层 lowRes child 即可）。
3. 评估 `PaintingBinding.imageCache.maximumSizeBytes`：1440px 背景 + 海报墙，默认 100MB 偏小
   导致反复 decode；可提到 ~200MB（真机验证内存）。

验收：二次进入同一详情页背景图即时显示；首次进入转场期间无大图 decode 尖峰
（Phase 0 工具 + timeline 查 `Image decode`）。

### Phase 5 — 取色质量与颜色分配（可选，与性能无关）
现状：native 返回 4 seed；Dart 兜底用 PaletteGenerator 16 色 + HSL clamp 派生，
accent==background 时人工 hue ±30/−20（seed_extractor.dart:251-266）。
1. 评估 native `extractDynamicThemeSeed` 返回多个**互异色相**的 swatch（主色/次色/第三色 + 各自
   population），Dart 侧按色相距离分配 accent/selection/link，不再用人工 hue shift。
2. `preferLightSurface` 阈值（lightness>=0.62）在亮色海报上易误判，结合 population 加权平均亮度。
3. 改动需要带 `dyn_seed_v1`/`dyn_v5` 缓存版本号升级（两处 `_persistentCacheVersion` + `_cacheVersion`），
   否则旧缓存污染新逻辑。

验收：抽 20 张不同风格海报截图对比新旧配色（亮/暗/灰/高饱和），无明显劣化、撞色减少。

---

## 4. 执行注意事项

- **每阶段先真机测量再下结论**：P1-P5 是读码推断的主因排序，Phase 0 的数据可能调整优先级
  （例如若 raster 而非 build 是瓶颈，则 Phase 4 提前）。
- 分屏/双引擎：`syncGlobalTheme`/`RuntimeThemeSyncBridge` 涉及跨引擎广播（原生壳分屏），
  改全局同步时机时**不要改变广播协议与顺序**，只改本地 publish 的调度时机。
- `deferLocalThemeApplyUntilGlobalSync`（pane 模式）路径较绕，Phase 1/2 改动后必须手测
  原生壳分屏下副栏详情页换色无闪烁。
- 时间常数集中在 `AppMotion` 与各页 `static const Duration`，调整时全局 grep 防止遗漏配对值
  （如 `globalSyncLocalApplyDelay` 32ms 与 provider 侧 delay 的配对）。
- 编译验证：`flutter analyze` + `flutter test`；Kotlin 侧若动 theme_sampler，用
  PowerShell 跑 `gradlew compileFullDebugKotlin`（需关沙箱）。

## 5. 测量记录（Phase 0 填写）

| 场景 | avgBuild | maxBuild | jank30 | 备注 |
|---|---|---|---|---|
| （基线）首页→剧集详情 push | | | | |
| （基线）剧集→季详情 push | | | | |
| （基线）季→集详情 push | | | | |
| （基线）逐级 pop ×3 | | | | |
| （基线）首页→电影详情 push/pop | | | | |

### 5.1 真机实测（2026-06-12，profile 包，含 Phase 0/1/2/3.1/4.3 + 认证修复）

平板真机走 首页→详情(嵌入 /detail/host)→返回→播放器，profile 模式 `[PERF][FRAME][WINDOW]`：

| 窗口 | jank30 | avgBuild | maxBuild | avgRaster | **maxRaster** | maxTotal |
|---|---|---|---|---|---|---|
| 首次 push /detail/host | 4 | **0.9ms** | 23.2ms | 6.8ms | **94.7ms** | 152.9ms |
| pop → push /（返回首页） | 5 | 2.6ms | 52.2ms | 4.5ms | 53.4ms | 119.3ms |
| push /player | 7 | 3.6ms | 64.0ms | 4.5ms | 33.3ms | 117.8ms |
| **二次** push /detail/host | **1** | 1.2ms | 18.6ms | 4.1ms | **14.6ms** | 37.4ms |

逐帧拆分（首次详情）：`jank total=152.9ms build=4.9ms raster=94.7ms`、`133.1ms build=0.9ms raster=86.7ms`。

**4.1/4.2 后复测（profile 包，同设备）**：首次详情 `[WINDOW][push /detail/host]` maxRaster
**94.7→62.1ms（−35%）**、jank30 4→3、avgBuild 0.9→1.5ms（仍极低）。最差帧
`total=133.1ms build=0.8ms raster=62.1ms`——build 已归零，残余 62ms 纯是 1440px 大图首帧
raster（GPU 解码+上传），但已垫在可见低清之下，**感知上的空白/突兀消失**（用户确认 OK）。
要再压这 62ms 只能降 hero 解码尺寸（画质换性能）或预栅格化，超出本计划范围。
另：返回首页单帧 `raster=126ms build=0.1ms` 是海报墙重新合成（非详情，属另一项）。

**结论（关键）**：
1. **build 侧已彻底收敛** —— avgBuild 0.9~3.6ms，maxBuild 多为单帧 18~64ms。Phase 0/1/2/3.1
   把详情进入期的重活管线（整树替换/串行分段/tint 动画/全局主题/下载监听）全部消除，
   **build 不再是瓶颈**，验证有效。
2. **唯一残余瓶颈 = 首次 hero 大图的 raster/decode 单帧尖峰**（maxRaster 86~94ms，单帧；
   出现在 `placeholder route=/parallel/placeholder` 即嵌入详情引擎首帧）。这正是 **Phase 4.1
   点击预取 / 4.2 低清占位** 的靶心。
3. **Phase 4.3（256MB 缓存）已见效** —— 二次进同详情页 maxRaster 94.7→14.6ms、jank30 4→1，
   重复进入已顺滑；首次进入的冷 decode 仍需 4.1/4.2 才能消。

→ 据此，**下一步最高 ROI 是 Phase 4.1/4.2**（消首次 hero raster 尖峰），其复杂度（跨页统一
hero-URL helper）此时是值得投入的；Phase 3.2（拆 section）按数据**不必做**（build 已非瓶颈）。

**2026-06-12 真机实测（平板 2136x3200，全部 Phase 落地后；adb 驱动）**：
- 测试设备浏览全走 **pane/分屏模式**（无全屏路由 push），上表的手机式 push/pop 窗口在此设备
  只在分屏副栏引擎出现。实测可得：
- 分屏副栏引擎冷启动+详情 push 窗口：`[WINDOW][push /detail/host]` frames=90 **jank30=1**
  avgBuild=1.3ms maxBuild=42.6ms avgTotal=7.1ms——唯一重帧是转场后单次正文 swap（Phase 1 设计内）。
- pane 模式右栏切详情（placeholder 引擎）：seed 缓存命中、`flush apply=1` 单次应用；
  jank 大头是 **raster 73.8ms（hero 大图首次 decode/upload）**+ 一次 30ms swap build。
  → 残余瓶颈在图像管线（Phase 4.1 预取可解但被 URL helper 阻塞；4.3 的 256MB 缓存已覆盖二次进入）。
- 结论：build 侧已收敛（转场窗口 jank30≤1），首次进页的 raster 尖峰是下一个目标。

---

## 6. 执行状态（持续更新）

### Phase 0 — 已完成（代码）
- `_FrameTimingLogger`（`lib/main.dart`）新增 `markWindow(label)`：标记后单独汇总 90 帧，
  输出 `[PERF][FRAME][WINDOW][label]`（slow60/jank30/avgBuild/maxBuild/avgRaster/maxRaster/...）。
- 新增 `_PerfNavigatorObserver`，在路由 push/pop 时自动打窗口标记（label 为路由 path）；
  仅 debug 安装。挂在 `MaterialApp.navigatorObservers`（`_appNavigatorObservers`）。
- **待你做**：真机 `flutter run`，走固定路径，过滤 `PERF.*WINDOW` 把数字填进上表。

### Phase 1 — 已完成（代码），待真机验证
- 新增 `lib/ui/route_transition_gate.dart`：
  - `RouteTransitionGate.of(context)` → 转场动画结束（或本就稳定）时 resolve 的 Future；
  - `RouteTransitionGate.isTransitioning(context)`；
  - 全局 `RouteTransitionGate.anyRouteTransitioning`，由 `RouteTransitionGate.observer`
    （NavigatorObserver，**release 也安装**）维护。
- 四个详情页接入：把"骨架→正文"整树替换推迟到转场结束后再 setState（IO 照常立即发）：
  - `tv_detail`：网络基础详情 swap 过 gate；描述 pop 的 180ms timer 过 gate；
    分段加载 genres/locate/playInfo 改并发 `Future.wait` 后**单次** setState（删除 3×140ms 串行间隔）。
  - `play_detail`：基础 info swap + 入场动画过 gate（phase2/预取在 gate 前先发 IO）；
    `_loadPhase2` 删除 240ms 人为延迟、轨道数据 setState 过 gate。
  - `tv_season`：首屏主 setState 过 gate（切季 showLoading=false 时 gate 立即返回，无副作用）。
  - `media_collection`：唯一的大 setState 过 gate。
- `DynamicPageThemeScope`：
  - 全局主题同步 flush（重建 MaterialApp.builder 下整树，P3）改为 `_flushGlobalThemeSyncWhenStable`：
    有路由转场时逐帧推迟，直到无转场再 flush（进入/退出两条路径都收口）。
  - 异步解析得到的 seed 本地应用（AnimatedTheme/tint，P2）经 `_applyResolvedSeedSetState`：
    转场中则等 gate 再 setState。**initState 命中缓存的同步路径不变**（第一帧即终态）。
  - `deferLocalThemeApplyUntilGlobalSync`（pane/分屏）路径未改，仍走原 deferred-local-apply。
- **未改**：tv_detail 的 `initialItemDetail` 同步首帧路径（保持第一帧终态）。
- 验证：`flutter analyze` 全绿（仅 6 条与本次无关的既有告警）；`flutter test` 89/90 通过，
  唯一失败 `play_stats_report_screen_test`「switches range...」为**既有失败**（裸 MaterialApp 缺
  localizationsDelegates，与本次改动无关，已在干净基线复现）。
- **待你做**：真机重测 Phase 0 同路径，对比 push/pop 窗口 jank30/maxBuild；
  **重点手测原生壳分屏副栏详情页换色无闪烁**（执行注意事项里点名的回归风险点）。

### Phase 2 — 已完成 2.1/2.2/2.3（代码），待真机验证；2.4 未做
- **2.1 tint 去全页化**：读码发现 ambientTint 实际只有 `tv_season` 用（派生 heroFogBase/
  heroFogShadow 并散布到整页，非仅背景；tv_detail/play_detail 的 `enableBottomFade=false`，
  tint 是 no-op）。因此 listenable 方案不成立（tv_season 整页都依赖 tint 值）。改为**直接删除
  140ms tint 过渡动画**：`DynamicPageThemeScope` 移除 `_colorAnimController`/`_colorTween`/
  `_onColorAnimTick(setState)`/`_animatedAmbientTint`/`TickerProviderStateMixin`，build 里把
  `ambientTint` 一次性传给 builder。seed 已在转场后单次应用（Phase 1），故 tint 也一次到位，
  零 tint 驱动重建（比"只重绘背景"更彻底）。代价：fog 不再有 140ms 淡入（一次到位），符合
  计划 option (a)。
- **2.2 替换 AnimatedTheme**：`AnimatedTheme(140ms)` → 直接 `Theme(data:)`，不再每帧 lerp
  全套组件主题。
- **2.3 统一 ImmersiveDetailBackground 取色**：`useMonetTint` 全项目从未传 true（死代码），
  删除其内部 monet 提取（`_refreshMonetTint`/`_extractTintWithPalette`/`_deriveTintColor`/
  `_immersiveTintCache` 及 palette_generator/seed_extractor 依赖与 `useMonetTint` 参数）。
  tint 一律由调用方经 `ambientTintOverride`/`bottomFadeTintColor` 传入。
- 五个调用点（含 person_detail）已适配；`flutter analyze` 全绿（仅 6 条无关既有告警）；
  `flutter test` 89/90（唯一失败仍是既有的 play_stats_report_screen_test）。
- **2.4（seed prefs 写放大，低优先）未做**：两个控制器各自 120ms debounce 全量重写 prefs blob，
  计划改为仅生命周期 flush。涉及持久化时机 + 分屏双引擎，单独评估。
- **待你做**：真机看进详情页时 `[PERF][FRAME]` 是否还有 tint 动画期的 build 尖峰（应消失）；
  **确认 tv_season 顶部 fog 颜色仍正确**（现在一次到位、无淡入）；分屏副栏换色仍无闪烁。

### Phase 3 — 已完成 3.1（代码），待真机验证；3.2 暂缓
- **3.1 下载监听去全页化**（P7）：`_handleDownloadTasksChanged` 原本在下载服务每次
  `notifyListeners()`（**任意**任务的每个进度 tick）都 `setState(() {})` 整页重建。改为只在
  本页实际消费的下载态变化时才 setState：
  - `play_detail`：本页只关心“当前 item 是否有已下载可用记录”（PlayActionBar 角标 +
    FileInfoSection 切本地文件）。新增字段 `_downloadedRecordSignatureForCurrentItem`
    （`id|filePath|status` 签名），签名不变则 return，不重建。PlayActionBar 另有局部
    `AnimatedBuilder(animation:_downloadTaskService)` 兜底（line ~2331），不受影响。
  - `tv_season`：本页下载态**唯一**出口是 `_isCurrentSeasonFullyDownloaded()`（line ~2246 的
    `downloaded:`，一个 bool）。新增 `_seasonFullyDownloadedCache`，bool 不翻转则不重建。
  - 关键：`downloadedRecordForItem`/`actionStateForItem` 都只反映**状态类别**（已下载/下载中/
    暂停/失败），**不含进度数值**，故按签名/bool gating 不会漏掉任何可见状态变化；进度条类
    UI 本就不在这两页（在下载列表页）。每帧 build 仍取实时值，gating 只决定“下载通知是否触发
    重建”，其它 setState 照常显示正确数据 → 无漏更新风险。
  - 验证：`flutter analyze` 两页全绿（39.7s, No issues）。
  - **待你做**：详情页可见期间后台跑下载，确认 `[PERF][FRAME]` 不再出现周期性全页 build；
    下载完成时 PlayActionBar 角标 / FileInfoSection / 季“全部已下载”态仍正确切换。
- **3.2 巨型 build 拆 section 子 widget — 暂缓**：play_detail 2626 行 / tv_season 2393 行单 build，
  拆 section 是大改且高回归风险（动画/滚动/pop controller 下放），且 play_detail 本分支有未提交
  WIP 混在同文件，拆分会让独立提交困难。计划原文也说“不追求一次拆完”。建议等真机基线确认
  3.1 已显著降低下载期 jank 后，再按 Phase 0 数据决定是否值得拆、以及优先拆哪个 section。

### Phase 4 — 已完成 4.3（代码），待真机验证；4.1/4.2 阻塞待评估
- **4.3 ImageCache 上限提升**：`main()` 在 `ensureInitialized()` 后设
  `PaintingBinding.instance.imageCache.maximumSizeBytes = 256<<20`（256MB）。默认 100MB 偏小，
  hero 背景最高 1440px（解码后 ~4-5MB）叠加首页海报墙，进出详情/滚动时 hero 反复被驱逐再 decode。
  `flutter analyze lib/main.dart` 全绿。**待你做**：真机核内存占用（256MB 是否过激，必要时降到 192MB）；
  timeline 看二次进同详情页是否还有大图 `Image decode` 尖峰。
- **4.2 低清占位 — 已完成（代码），主修复**：§5.1 真机证明残余瓶颈是首次 hero 大图冷光栅单帧
  尖峰(~90ms)，且出现在**嵌入详情引擎**(独立 isolate/独立 ImageCache)。低清占位在详情引擎**内部**
  生效，对嵌入/整页都有效，故是这台设备的正解。`ImmersiveDetailBackground` 新增 `lowResUrls`：
  `_ensureImageLayers` 多建一个 `_LowResBackgroundImage`(cacheWidth 480、不淡入、失败透明)垫在主图
  之下、与主图同 `Transform.scale` 对齐；大图就绪由 frameBuilder 淡入用不透明像素覆盖低清。三页
  (tv_detail/play_detail/tv_season)各传 `imageCandidates(baseUrl, backdropPath, width:360)`(多在取色
  缓存里；未命中也只是极小图，开销可忽略)。
- **4.1 整页点击预取 — 已完成（代码），同引擎路径**：新增 `lib/ui/detail_hero_image.dart`
  集中 hero 的 provider/cacheWidth 算法——`ResizeImage(NetworkImage(url,headers), width:cacheWidth)`
  与背景 `Image.network(cacheWidth)` 缓存键逐字段一致(Flutter 内部即如此构造，故能命中)。
  `AdaptiveDetailRequest` 加 `heroBackdropPath`(item/season/library 工厂从 initialItemDetail/
  backdropPath 填)，`open()` 在**非 pane** 路径 push 前 `precacheImage` 抢跑大图(fire-and-forget、
  吞错、不阻塞导航、`context.mounted` 守卫)。**关键限制**：嵌入(pane)详情走独立引擎独立 ImageCache，
  主引擎预取进不去 → 嵌入路径**不预取**(直接 return)，靠 4.2 兜底；4.1 只惠及同引擎整页(手机/整页)。
- 验证：改动文件 `flutter analyze` 全绿(全项目 6 条既有告警均在未改文件)；`flutter test` 89/90
  (唯一失败仍是既有 play_stats_report_screen_test)。已提交 commit `76488cb`。
- **待你做**：真机看进详情页 hero 是否先出低清、再淡入大图(不再有空白单帧)；profile timeline 看
  首次详情 `maxRaster` 是否下降/尖峰是否被低清遮住；手机整页路径看预取是否让大图落地即显示。

### Phase 5 — 已完成（代码），待真机验证（取色质量，与性能无关）
用户要求：莫奈取色 + 颜色分配优化 + 更舒适美观。选择：柔和舒适风格 / 允许亮色表面 /
保持原生路径（性能不退）。
- **关键判断**：4 个 seed 下游喂 `ColorScheme.fromSeed`（本身即 HCT 色调调和），故取色层无需重写
  HCT；真正要改的是“挑哪几个 seed”。莫奈不比 Palette 重（都在缩略图量化+已缓存+工作线程），
  故在**原生 Kotlin 主路径**（off-main-thread）+ Dart 兜底**同步升级算法**，不加依赖、不动架构。
- **评分+互异色相分配**（替代旧 vibrant/muted 固定取 + 人工 ±30° hue-shift）：对全部量化 swatch
  做 Monet 式评分（彩度×人口对数权重，近灰强罚/极端调弱罚），accent 取最高分；selection/link 取与
  已选**色相距离 ≥32°** 的真实图像色，无第二色相则退回**同色相不同明度**（tonalSibling，比撞色和谐）。
- **柔和**：强调/选中/链接彩度上限整体收一档（accent 0.22-0.58→0.20-0.50 等）；暗表面背景彩度亦收。
- **允许亮色**：`preferLightSurface` 由“单一 swatch lightness≥0.62”改为**人口加权亮度 ≥0.60**，更稳、
  亮海报能出亮主题。
- 原生 `ThemeColorSampler.buildSeedMap` + Dart `_extractUncached` 同算法落地（删除 firstAccepted/
  normalizeCandidate/lastResort/shiftHue 旧逻辑）。缓存版本三处升级：`dyn_seed_v1→v2`、`dyn_v5→v6`、
  `dyn_page_seed_v1→v2`，失效旧 seed。
- 验证：改动文件 analyze 全绿；`flutter test` 89/90（唯一失败仍是既有 play_stats）；Kotlin
  `compileFullDebugKotlin` BUILD SUCCESSFUL。已提交 commit `41b0c5d`。
- **待你做**：真机抽不同风格海报（亮/暗/灰/高饱和/双主色）对比新旧配色——重点看 accent 与 selection/
  link 是否不再撞色、亮海报是否出亮主题、整体是否更柔和不刺眼。
