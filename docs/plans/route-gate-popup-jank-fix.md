# 弹窗开/关整页重建掉帧修复方案：RouteTransitionGate 锚点化（RouteGateAnchor）

- 日期：2026-09-30
- 分支：`feature/fn-native-login`
- 状态：待实施
- 依据：`.zcode/perf/popup_jank_summary.md`（真机 profile 实测 + VM service timeline 逐组件打点）、本仓库源码逐处核验（行号均为本文写作时亲读核验，见 §4.1）、API 设计结论（已选定方案）
- 实测对象：TvSeasonDetailPage（弹窗 = `showModalBottomSheet` 选集弹窗 / "更多操作"弹窗）

---

## 1. 背景与根因

### 1.1 现象（真机实测，`.zcode/perf/popup_jank_summary.md`）

设备 2410CRP4CC（3200×2136，120Hz），profile 构建 `com.geqian.flyplayer.fly_player.profile`，分屏场景（左首页 / 右季详情）。`adb input tap` 驱动 + `log -t PERFDRV` 打标 + logcat 抓 `[PERF][FRAME]`（`main.dart` `_FrameTimingLogger`，jank 阈值 total>33.3ms）：

| 弹窗 | 动作 | 掉帧轮次 | total 范围 |
|---|---|---|---|
| 选集弹窗（showModalBottomSheet） | 打开 | 5/5 全部 | 39.5–46.9ms |
| 选集弹窗 | 关闭 | 5/5 全部 | 37.1–42.0ms |
| "更多操作"弹窗 | 打开 | 9/10 | 37.4–45.6ms |
| "更多操作"弹窗 | 关闭 | 5/5 全部 | 36.9–40.4ms |

关键观察（summary 原文）：
1. **确定性掉帧**：两类弹窗、每次开与关都掉 1–2 帧，与弹窗内容复杂度无关（1 个条目的"更多操作"与多行列表的选集弹窗幅度一样）→ 固定成本，瓶颈在弹窗开/关链路的公共开销。
2. 空闲基线 avgTotal 8.5–9.8ms（estFps 102–117），掉帧只集中在弹窗/路由转场帧。

### 1.2 根因（VM service timeline 逐组件打点 + SDK 源码核验）

最重帧 46.0ms（右栏引擎，T_OPEN_1）构成：

| 阶段 | 耗时 | 说明 |
|---|---|---|
| BUILD | 25.2ms | **TvSeasonDetailPage 整页重建 17.1ms（68%）**，弹窗自身内容仅 ~7ms |
| LAYOUT | 14.4ms | 重建页面的连带重排（RenderParagraph×18、_EpisodePoster×10…）+ 弹窗首次布局 |
| PAINT | 4.5ms | |
| COMPOSITING | 1.2ms | |

机制链路（已确证，可直接采信）：
- 弹窗（PopupRoute）push/pop 时，Flutter 框架私有 `_ModalScopeStatus`（SDK `packages/flutter/lib/src/widgets/routes.dart:1015`）的 `isCurrent`/`canPop` 翻转并通知依赖者；
- `lib/ui/route_transition_gate.dart` 的 `RouteTransitionGate.of(context)` 内部调 `ModalRoute.of(context)`（`route_transition_gate.dart:66`；`isTransitioning` 同，`:66`），**在调用处元素上注册 `_ModalScopeStatus` 依赖**；
- 用页面根 State 的 context 调用时，页面根 element 成为依赖者 → 每次弹窗开/关都触发整页重建 + 连带重排；
- 决定性排除法：TvSeasonDetailPage 是 buildScope 的直接 dirty root（非父级带动）；且 SDK `routes.dart` 的 `_page ??=` 缓存证明弹窗 push 不会经 `buildPage` 重建下层页——重建只能来自页面自身注册的依赖。

### 1.3 波及面（详见 §4 地面真值）

`RouteTransitionGate.of(` / `isTransitioning(` 共 21 处调用、8 个文件（本人 `rg` 核验，与调研清单一致）。其中 14 处用页面根 State 的 context（4 个详情页 + 首页），首页 `media_list_screen.dart:930` 是最重一处——`of()` 即使无转场也先注册依赖再立即 resolve（`route_transition_gate.dart:82-91`），因此触发点首次执行后页根**永久**成为依赖者，此后每次弹窗开/关必整页重建首页（实测主引擎 push poster-browse maxTotal 69ms 同类）。

**修复方向（已选定）**：新增叶子锚点组件 `RouteGateAnchor` 承接 `_ModalScopeStatus` 依赖，页面 State 经它拿到本页路由动画并构造等价 future，全部调用点逐处改造。备选"页面 State 缓存 body widget 实例"改动更大且只治标，不采用；RepaintBoundary 只隔离重绘、不隔离 build/layout，对本问题无效（summary §修复方向 3）。

---

## 2. 目标 / 非目标

### 目标
1. **G1**：弹窗（PopupRoute）开/关不再触发任何页面的整页重建——`_ModalScopeStatus` 翻转的通知只落到叶子锚点 element（O(1) 重建，子树经 identical 短路零重建）。
2. **G2**：21 处 gate 调用的**等待语义逐条等价**：无 ModalRoute 立即 resolve、稳定立即 resolve（零帧延迟）、primary+secondary 双动画"都稳定才放行"、同一路由可并发多次 await、`debugOverrideTransition` 测试钩子继续生效、await 后调用方 `mounted` 自查契约不变。
3. **G3**：机制收敛在 `lib/ui/route_transition_gate.dart` 单文件（不新增文件），`observer` / `anyRouteTransitioning` / debug 钩子原样保留。
4. **G4（验收指标）**：真机复测弹窗开/关 jank 帧从 37.8–46.0ms 降到 33.3ms 线以下，目标 ~12ms（BUILD 25.2→~8ms、LAYOUT 14.4→~3ms）；空闲基线不回归。

### 非目标
1. 不改 `observer` / `anyRouteTransitioning` / `_RouteTransitionWatch` 的计数机制（`app_theme_provider.dart:1242/1247`、`dynamic_page_theme_scope.dart:671` 等消费点不动）。
2. 不改任何页面的业务时序结构：网络发起时机、setState 内容、seq/modeBeforeGate/mounted 守卫、"IO 立即并发仅推迟应用"的设计（如 `tv_detail_page.dart:574` 有意未过闸的第二个 setState）一律原样。
3. 不做"重页面缓存 body widget 实例"类结构性防御（备选方案，见 summary）。
4. 不处理页面级转场自身的掉帧（如 push poster-browse 69ms 中的弹窗外因素，仅随锚点化顺带受益于首页不再整页重建）。
5. `lib/widgets/detail/immersive_detail_background.dart:580` 建议维持现状（理由见 §4.3 表末行），不属于必改项。

---

## 3. 方案设计

### 3.1 总体思路

```
旧行为：页面 State ──context──> RouteTransitionGate.of(context) ──> ModalRoute.of(context)
        └──────── 页面根 element 注册 _ModalScopeStatus 依赖（弹窗开/关 → 整页重建）✗

新行为：页面 build 根包 RouteGateAnchor(key: _gateKey, child: 页面根)
        锚点 build：_route = ModalRoute.of(context)  ← 依赖落在本叶子 element ✓
        页面 State：await _gateKey.currentState!.waitTransition()  ← 等价 future，零依赖
```

- 锚点是 ComponentElement、无 RenderObject，自身重建 O(1)；`build` 原样返回 `widget.child`（同一实例），`framework.dart:4014` 的 identical 短路保证子树零重建。
- 等价 future 的 completer/statusListener 挂在 route 的 `animation`/`secondaryAnimation` 对象上，**不依赖锚点元素存活**——页面 pop 后 await 仍能随动画 reverse→dismissed resolve，由调用方既有的 `mounted` 自查收尾（`play_detail_page.dart:1737` 等 unawaited 跨 pop 场景的正确性前提）。

### 3.2 `lib/ui/route_transition_gate.dart` 的改动

改动范围：新增两个静态核心 + 旧 API 改薄封装；`_activeTransitions`、debug 钩子、`observer`、`_isAnimating`、`_RouteTransitionWatch`、`_RouteTransitionGateObserver`（现 `:21-49`、`:51-55`、`:115-215`）**全部原样不动**。

```dart
class RouteTransitionGate {
  RouteTransitionGate._();

  // 原样保留（原 :20-49）：_activeTransitions / debug 钩子字段与实现 /
  // anyRouteTransitioning / observer。
  static int _activeTransitions = 0;
  static bool? _debugTransitioningOverride;
  static Future<void>? _debugWaitOverride;

  static bool get anyRouteTransitioning =>
      _debugTransitioningOverride ?? _activeTransitions > 0;

  @visibleForTesting
  static void debugOverrideTransition({
    required bool isTransitioning,
    required Future<void> wait,
  }) {/* 原样（原 :29-36） */}

  @visibleForTesting
  static void debugResetTransitionOverride() {/* 原样（原 :38-42） */}

  static _RouteTransitionGateObserver? _observer;

  static NavigatorObserver get observer =>
      _observer ??= _RouteTransitionGateObserver();

  static bool _isAnimating(Animation<double>? animation) {/* 原样（原 :51-55） */}

  /// ★新增核心一：路由级判定。[debugOverrideTransition] 的 override 检查
  /// 收敛于此，旧 API 薄封装与 [RouteGateAnchorState.isTransitioning] 共用。
  static bool isRouteTransitioningRoute(ModalRoute<dynamic>? route) {
    final debugOverride = _debugTransitioningOverride;
    if (debugOverride != null) return debugOverride;
    if (route == null) return false;
    return _isAnimating(route.animation) ||
        _isAnimating(route.secondaryAnimation);
  }

  /// ★新增核心二：路由级等待。原 of()（原 :79-112）取 route 之后的全部逻辑
  /// 原样平移，仅把取 route 的方式从 context 换成参数，语义逐条不变：
  /// - 无路由 → 立即 resolve（等价原 :82-85 的 null 分支）；
  /// - primary/secondary 任一在动 → 挂起，status listener 挂在这两个
  ///   Animation 对象上（不依赖任何 element 存活，页面 pop 后仍能 resolve）；
  /// - "任一动画状态变化后重查两条、都稳定才放行"（原 :96-99）；
  /// - 每次调用独立 completer + 独立 listener，同一路由可并发多次 await，
  ///   resolve 时各自摘除，无共享可变状态；
  /// - 稳定路由立即 resolve（原 :90-92），切季等复用路径零帧延迟。
  static Future<void> waitForRoute(ModalRoute<dynamic>? route) {
    final debugOverride = _debugWaitOverride;
    if (debugOverride != null) return debugOverride;
    if (route == null) return Future<void>.value();
    final animations = <Animation<double>>[
      if (route.animation != null) route.animation!,
      if (route.secondaryAnimation != null) route.secondaryAnimation!,
    ];
    if (!animations.any(_isAnimating)) {
      return Future<void>.value();
    }
    final completer = Completer<void>();
    late final void Function(AnimationStatus) listener;
    listener = (AnimationStatus _) {
      // 任一动画状态变化后重查两条：primary 刚 completed 时 secondary
      // 可能又启动（快速连续导航），必须两条都稳定才放行。（原 :96-99）
      if (animations.any(_isAnimating)) {
        return;
      }
      for (final animation in animations) {
        animation.removeStatusListener(listener);
      }
      if (!completer.isCompleted) {
        completer.complete();
      }
    };
    for (final animation in animations) {
      animation.addStatusListener(listener);
    }
    return completer.future;
  }

  /// 旧 API：迁移期薄封装。`@Deprecated` 自 C1 即加——本仓库锁定的 lints 3.0.0
  /// / flutter_lints 3.0.2（pubspec.lock 亲验）**未启用**
  /// `deprecated_member_use_from_same_package` 与 `deprecated_member_use`（两个
  /// 包 lib/ 全目录 grep "deprecated" 零命中 + dart analyze 探针 "No issues
  /// found!"，证据见 §3.5/§9 第二轮 #1），`flutter analyze` 零输出，且为迁移期
  /// 21 处调用点提供 IDE 删除线提示。完成迁移后由清理 PR 删除（前置条件见
  /// §3.5/§6 C7）。
  ///
  /// override 检查必须先于 `ModalRoute.of`：`debugOverrideTransition` 生效时
  /// 不得触达调用处 element（不注册 `_ModalScopeStatus` 依赖），与旧实现
  /// （原 :64-65 / :80-81 的早退顺序先于 :66 / :82）完全一致——含副作用在内
  /// 逐条等价。（不能写成 `waitForRoute(ModalRoute.of(context))` 的单表达式：
  /// 实参先于核心内的 override 检查求值，override 生效时仍会注册依赖。）
  @Deprecated('在调用处 element 上注册 _ModalScopeStatus 依赖，弹窗开/关会触发'
      '整页重建；改用 RouteGateAnchor + RouteGateAnchorState.waitTransition')
  static Future<void> of(BuildContext context) {
    final debugOverride = _debugWaitOverride;
    if (debugOverride != null) return debugOverride;
    return waitForRoute(ModalRoute.of(context));
  }

  @Deprecated('同 of()；改用 RouteGateAnchorState.isTransitioning')
  static bool isTransitioning(BuildContext context) {
    final debugOverride = _debugTransitioningOverride;
    if (debugOverride != null) return debugOverride;
    return isRouteTransitioningRoute(ModalRoute.of(context));
  }
}

// _RouteTransitionWatch / _RouteTransitionGateObserver（原 :115-215）原样不动。
```

语义对照（旧 → 新，逐条）：

| 旧实现（行号：route_transition_gate.dart） | 新核心 | 等价性 |
|---|---|---|
| override 检查（:63-65、:79-81，早退于 `ModalRoute.of` 之前） | 核心入口内（锚点路径）+ 薄封装头部（context 路径）双处保留 | override 命中时两条路径都不触达 `ModalRoute.of`、不在调用处注册依赖——含副作用逐条一致；现有测试 `test/widgets/dynamic_page_theme_scope_headers_race_test.dart:84-87/:114-117` 不需改动即继续生效 |
| null 路由立即 resolve/false（:66-69、:82-85） | `waitForRoute(null)` / `isRouteTransitioningRoute(null)` | 逐条一致 |
| 双动画收集与稳定判定（:86-92、:51-55） | 平移 | 逐条一致（含 primary+secondary 两条） |
| completer + listener + 重查 + 摘除（:93-111） | 平移 | 逐条一致 |
| `ModalRoute.of(context)` 的依赖注册 | 移入锚点 build | 依赖落点从调用方 element 变为锚点叶子 element |

### 3.3 新增 `RouteGateAnchor` 锚点组件（最终形态）

加在同一文件 `lib/ui/route_transition_gate.dart` 底部（机制单文件）：

```dart
/// 路由门锚点：叶子组件，独自承接 [ModalRoute.of] 的 `_ModalScopeStatus` 依赖。
///
/// 弹窗（PopupRoute）push/pop 时 `_ModalScopeStatus.isCurrent/canPop` 翻转
/// （SDK routes.dart:1015-1073 updateShouldNotify），只有本锚点这个
/// ComponentElement 被标脏重建；锚点 build 原样返回 [child]
/// （framework.dart:4014 identical 短路），子树零重建。
/// 页面/组件 State 经 `GlobalKey<RouteGateAnchorState>` 取句柄。
///
/// ⚠ [child] 必须原样传入页面根 widget 实例；本组件 build 不得包装、换 key、
/// 拼新 widget，否则依赖翻转会连带重建被包子树，整页重建问题原样复活。
class RouteGateAnchor extends StatefulWidget {
  const RouteGateAnchor({super.key, this.child});

  /// 页面根子树。null 时锚点自身渲染 SizedBox.shrink（0×0 的 SizedBox，产生
  /// 一个零尺寸叶子 RenderConstrainedBox——SDK basic.dart:2744/:2763-2764；
  /// 布局 O(1)、无绘制内容），可作现有 Stack 的额外 child 使用。
  final Widget? child;

  @override
  RouteGateAnchorState createState() => RouteGateAnchorState();
}

class RouteGateAnchorState extends State<RouteGateAnchor> {
  ModalRoute<dynamic>? _route;

  /// 本锚点解析到的路由；不在任何 ModalRoute 下时为 null（门退化为立即放行）。
  ModalRoute<dynamic>? get route => _route;

  /// 等价旧 `RouteTransitionGate.isTransitioning(context)`，但依赖不落在调用方 element。
  bool get isTransitioning =>
      RouteTransitionGate.isRouteTransitioningRoute(_route);

  /// 等价旧 `RouteTransitionGate.of(context)`：无路由立即 resolve；已稳定立即
  /// resolve；同一路由可并发多次 await；debugOverrideTransition 经核心继续生效。
  Future<void> waitTransition() => RouteTransitionGate.waitForRoute(_route);

  @override
  Widget build(BuildContext context) {
    // 依赖注册落在本叶子 element：ModalRoute.of → InheritedModel.inheritFrom
    // 无 aspect 路径（inherited_model.dart:193-194）→ 全量依赖 _ModalScopeStatus。
    // 放 build 中：锚点每次重建（含依赖翻转触发的重建）都刷新依赖与 _route，
    // 无陈旧路由引用。
    _route = ModalRoute.of(context);
    return widget.child ?? const SizedBox.shrink();
  }
}
```

放置规则（逐条对应已核验的边界场景）：
1. **无条件包住页面根**：锚点不进任何条件分支，保证任何帧都在场（如 `tv_season_detail_page.dart:3043` 的 `DynamicPageThemeScope(...)` 外包一层）。也可作现有 Stack 的额外 child（child 缺省渲染 0×0 的 `SizedBox.shrink`——一个零尺寸叶子 RenderConstrainedBox，布局 O(1)、无绘制内容，并非"零 RenderObject"）。注意"任何帧都在场"必须对 build 的**所有早退分支**成立：背景快照处（§4.3）因 LayoutBuilder 存在尺寸非法帧的早退（`app_atmospheric_background.dart:277-282`），最终采用包住 build 返回整体的放置，Stack 额外 child 形态只适用于确无早退分支的场景。
2. **必须在页面子树之内**：4 个详情页都有 `DetailPresentation.pane` 形态（各页 `_isPane`），pane 经 `PlayerPaneHostScope.openRoute`（`lib/ui/player_pane_host_scope.dart:8`）或 `EmbeddedDetailLauncher` 的 MethodChannel（`lib/services/embedded_detail_launcher.dart:17`，副引擎/独立窗口）承载；页面坐落在其宿主树的某条 ModalRoute 下，子树内锚点解析到同一条路由——锚点绝不可提升到页面子树之外。
3. **多锚点互不干扰**：`waitForRoute` 无共享可变状态；同页可并存页根锚点 + widget 内部锚点（如 `DynamicPageThemeScope` 场景，见 §4.3）。
4. **非路由位置**：route 为 null，`waitTransition` 立即 resolve、`isTransitioning` false，与现行 `route_transition_gate.dart:66-69/:82-84` 一致；误放时建议 debug 断言提示。
5. **热重载/重建**：GlobalKey 存 State 的 final 字段，setState 重建与 reassemble 均保留锚点 State；`_route` 每次 build 重新解析，无陈旧引用。

### 3.4 页面/组件接入范式

以 TvSeasonDetailPage 为例（另 3 个详情页 + 首页同模式；widget 内部锚点见 §4.3）：

```dart
class _TvSeasonDetailPageState extends State<TvSeasonDetailPage> ... {
  /// 存 final 字段：setState 重建与热重载都保留锚点 State。
  final GlobalKey<RouteGateAnchorState> _gateKey = GlobalKey<RouteGateAnchorState>();

  /// 统一入口。锚点已挂载（正常路径）：经叶子句柄等待，页根不注册任何依赖。
  /// 锚点未挂载（首帧竞态等不应发生的路径）：兜底走旧 API 保语义不破，
  /// 且必须留下全模式可观测痕迹（见下）。
  Future<void> _waitOwnTransition() {
    final gate = _gateKey.currentState;
    if (gate != null) {
      return gate.waitTransition();
    }
    // 兜底被触发的瞬间，页根 element 会经 of(context) 重新注册 _ModalScopeStatus
    // 依赖，整页重建无声复活——该痕迹不能只放在 assert 里（profile/release
    // 零输出）。logSwallowedError 无 debug 门控
    // （lib/utils/swallowed_error_logger.dart:6-31 → AppLogService.recordWarning
    // 落盘，lib/services/app_log_service.dart:372-404），profile 下可从导出日志
    // 确认兜底是否触发过（§8.2）。
    unawaited(logSwallowedError(
      action: 'route gate anchor missing',
      error: StateError('RouteGateAnchor 未挂载，回退 RouteTransitionGate.of；'
          '请确认锚点无条件包裹页面根'),
      stackTrace: StackTrace.current,
      source: 'route_transition_gate',
    ));
    assert(() {
      FlutterError.reportError(FlutterErrorDetails(
        exception: StateError('RouteGateAnchor 未挂载，回退 RouteTransitionGate.of'),
        library: 'fly_play',
        context: ErrorDescription('while waiting route transition'),
      ));
      return true;
    }());
    return RouteTransitionGate.of(context);
  }

  // 每个调用点只改一行：await RouteTransitionGate.of(context); → await _waitOwnTransition();
  // 其后的 mounted / seq / modeBeforeGate 等守卫全部原样保留（见 §4 各行）。

  @override
  Widget build(BuildContext context) {
    ...
    return RouteGateAnchor(            // :3043 原根外包一层，原根原样传入
      key: _gateKey,
      child: DynamicPageThemeScope(
        ...
      ),
    );
  }
}
```

兜底路径说明：4 个详情页与首页的 `_load`/`_loadSeasonData` 均由 initState 同步发起（`media_collection_detail_page.dart:110`、`play_detail_page.dart:473`、`tv_detail_page.dart:182`、`tv_season_detail_page.dart:219-220`、`media_list_screen.dart` 刷新只在导航返回/resume 后），而**全部 14 处 `of()` 调用都在真实网络 await 之后**（逐处核验见 §4），执行到 gate 时首帧早已完成、锚点必已挂载——兜底只覆盖理论竞态。

ignore 注释：本仓库锁定的 lints 3.0.0 **未启用** `deprecated_member_use_from_same_package`（§3.5/§9 第二轮 #1 探针实证），兜底与 21 处旧调用点在迁移期**均无需** `// ignore: deprecated_member_use_from_same_package`；若未来升级 flutter_lints 并显式启用该 lint，再在残留调用点统一补。

### 3.5 旧 API 去留

- **C1 即加 `@Deprecated` 薄封装并保留至清理 PR**：为迁移期 21 处调用点提供 IDE 删除线提示，`flutter analyze` 输出为零。已证伪第一轮的担忧（"info 级 lint 会打红 analyze"）：`deprecated_member_use_from_same_package`（及 `deprecated_member_use`）**不在本仓库启用的 lint 集内**。证据（第二轮 #1，全部亲跑）：① `pubspec.lock` 锁定 flutter_lints 3.0.2（direct dev）+ lints 3.0.0（transitive）；② `rg -n "deprecated" <pub cache>/flutter_lints-3.0.2/lib <pub cache>/lints-3.0.0/lib` 零命中——启用链 `flutter.yaml`（include `lints/recommended.yaml`）→ `core.yaml` 全覆盖，flutter.yaml 额外 13 条规则无一相关；③ 仓库 `analysis_options.yaml` 无 analyzer/errors 段、rules 全注释；④ 实测探针（flutter_lints ^3.0.0 + include flutter.yaml + 同包 `@Deprecated` 静态方法及其调用）`dart pub get && dart analyze` 输出 "No issues found!"（探针已删）。教训记录：第一轮只核了"analysis_options 未抑制"，漏了"lint 规则集本身不含该规则"——**未抑制≠启用**；`analyze.dart` 的 `--fatal-infos defaultsTo: true` 属实但对该 lint 无输入。
- **C7（迁移完成后）删除旧 API 的组合前置**：删除会使所有残留调用点编译失败，而 §4.3 建议 `immersive_detail_background.dart:580` 维持现状（仍调 `isTransitioning(context)`，:580 亲验）——两条分支必须显式二选一：**(a)** :580 维持现状 → C7 保留 `@Deprecated`、**永不删除** `isTransitioning`（`of` 可在兜底证伪后单独删除）；**(b)** :580 一并叶子化/迁移 → `of`/`isTransitioning` 都可在兜底证伪后删除，并把兜底改为"立即 resolve + assert"（接受弱化，见 §7）。
- **兜底可观测性（防无声复活）**：兜底路径被触发的瞬间，页根 element 会经 `of(context)` **永久重新注册** `_ModalScopeStatus` 依赖（直至 element 卸载），整页重建无声复活且生产零信号（`reportError` 在 assert 内）——因此兜底处以 `logSwallowedError` 落一条全模式可观测记录（`lib/utils/swallowed_error_logger.dart:6-31` → `AppLogService.recordWarning`/`record`，`lib/services/app_log_service.dart:372-404` 无 debug/release 门控、落盘可导出）；§8.2 复测时核对导出日志无 `route gate anchor missing` 记录，即为兜底未被触发的直接证据。

---

## 4. 逐调用点改法表

### 4.1 地面真值核对与盘点出入

本人核验命令与输出（`rg -n "RouteTransitionGate\.|isTransitioning\(" lib/ -g "!lib/ui/route_transition_gate.dart"`，24 行）：

- 21 处 gate 调用与任务给定地面真值**逐行一致**，无遗漏无多余；
- 另有 3 处相邻引用不在改造范围：`lib/main.dart:461`（observer 挂载）、`lib/providers/app_theme_provider.dart:1242/:1247` 与 `lib/widgets/detail/dynamic_page_theme_scope.dart:671`（`anyRouteTransitioning`，静态计数器、无 context、无 `_ModalScopeStatus` 依赖）；
- 四页面文件内没有任何 `RouteTransitionGate.isTransitioning` / `anyRouteTransitioning` 调用（`isTransitioning` 只在 gate `:63` 定义）。

盘点结果与地面真值/本人读码的出入（**以本人读码为准**，已在本表修正）：
1. API 设计结论 filesTouched 写 `dynamic_page_theme_scope.dart ":177/:394/:421/:580 附近共 4 处"`：实为 **3 处**（:177/:394/:421）；`:580` 属 `lib/widgets/detail/immersive_detail_background.dart`（地面真值包含、filesTouched 漏列该文件），本表已补。
2. 页面组盘点的 rewireNote 用了 `ofAnchor` 命名与"anchor initState 里 ModalRoute.of 回填"描述：被 API 设计结论最终形态取代——统一为 `RouteGateAnchorState` 句柄（GlobalKey），`ModalRoute.of` 在锚点 build 中解析。
3. 组件盘点用 `RouteTransitionAnchor` 名：统一为 `RouteGateAnchor`；锚点测试可见钩子形态已在 §5.2 测试 2 定死（`@visibleForTesting` 静态重建计数），不再悬空。
4. 组件盘点写 `app_atmospheric_background.dart ":211-214"`：gate 调用实为 **:213**（isTransitioning）/:214（of）；:211-212 是 Visibility/TickerMode 前置短路，非 gate 调用。
5. 任务材料称 jank "37.8-46.0ms"：summary 实测两类弹窗 total 范围为 36.9–46.9ms（表），46.0ms 为逐组件打点分析的 T_OPEN_1 帧；两者不矛盾，本文分别引用。
6. `play_detail_page.dart:221` 的 `_playerRouteActive` 是 `final bool _playerRouteActive = false;` 死常量（亲验），:1737 等处相关守卫恒不触发；改造触碰这些行时不必动它但应知晓。

### 4.2 页面组（14 处 `of()`，全部页面根 State context，逐处亲验）

统一改法（下表"改法"列不再重复）：页面 State 持 `final GlobalKey<RouteGateAnchorState> _gateKey`，build 根包 `RouteGateAnchor(key: _gateKey, child: <原根>)`，方法内加 §3.4 的 `_waitOwnTransition()` 统一入口，`await RouteTransitionGate.of(context);` 一行替换为 `await _waitOwnTransition();`；**await 之后的 mounted/seq/内容守卫与 setState 全部原样**。

| where | flow（亲验） | 改法 | 风险 |
|---|---|---|---|
| `lib/pages/media_collection_detail_page.dart:143` | initState(:105)→`_load()` 非飞牛(Emby)分支：`backend.getItemDetail` + `_loadNeutralItems` 两个网络 await 后 mounted(:142)→gate→setState 中立详情+子项列表，骨架→正文 | build 根 :1071（`return DynamicPageThemeScope(`）外包锚点；:143 换 `_waitOwnTransition()`；mounted(:144) 原样 | **low**。纯机械；gate 已在两次网络 await 后锚点必已挂载，兜底分支仍写（理论竞态） |
| `lib/pages/media_collection_detail_page.dart:180` | 同 `_load()` 飞牛分支：getItemDetail/getUserListSetting/_loadItems 后 mounted(:178)→gate→setState 应用详情+列表+排序/视图偏好，注释明言"避免落在 380ms 转场窗口中段" | 同上，与 :143 共用**同一** `_gateKey`（勿各自新建） | **low**。同 :143 |
| `lib/pages/play_detail_page.dart:1546` | `_load()` 非飞牛展示半身分支：session.ensureReady + `backend.getItemDetail` 后区域本地化（:1537 `AppLocalizations.of(context)` 在 gate 之前，不属本改造），mounted(:1535)→gate→setState 骨架→正文；随后 `_handleDownloadTasksChanged`、`_headerFade/_actionsPop/_descriptionPop` 三个 forward、`unawaited(_loadNeutralSourceVersions)` | :1546 换 `_waitOwnTransition()`；后续链条全部原样 | **low**。机械替换；`_loadNeutralSourceVersions` 自带 endOfFrame+mounted+内容比对守卫，无耦合 |
| `lib/pages/play_detail_page.dart:1593` | `_load()` 飞牛 Phase 1：`_loadPlayInfo` 后 **unawaited(_loadPhase2)(:1589) 先发**，再 gate→setState 应用 `_data` 骨架→正文 + `_startEntryAnimations()`，注释明言"避免与 380ms enter 动画同窗叠加" | :1593 换 `_waitOwnTransition()`；`unawaited(_loadPhase2)` 在 gate 前 fire 的相对顺序保持不动 | **low**。机械替换；`_loadPhase2` 自带独立 gate(:1737)，两处共锚点互不依赖 |
| `lib/pages/play_detail_page.dart:1737` | `_loadPhase2()`（unawaited 运行）：并发取题材/地区/语言字典+轨道数据，多个 mounted/_playerRouteActive 检查后 gate(:1737)→双检查(:1738)→setState 应用轨道/选曲选轨/字典并 `_rebuildDetail`；finally 置 `_heroAsyncSectionsResolved` | :1737 换 `_waitOwnTransition()`；gate 后 `mounted\|\|_playerRouteActive` 双检查、setState、`unawaited(_refreshManualSubtitleEntries)`、finally 原样 | **medium**。该方法 unawaited、可跨越页面 pop 存活：future 的 completer/listener 必须挂在 route 动画上与锚点元素存活解耦（§3.2 waitForRoute 设计已满足），锚点随页卸载不得让 future 永不 resolve——否则轨道数据永不应用、finally 不跑、`_heroAsyncSectionsResolved` 卡死。测试须覆盖"转场中页面被 pop"（§5） |
| `lib/pages/tv_detail_page.dart:293` | `_load()` 飞牛全量分支（initialItemDetail 快路径 :275-287 提前 return 不经过）：`_loadItemDetail` 后 mounted(:290)→gate→setState(`_applyBaseDetail`,`_baseDetailIsFull=true`,`_loading=false`)，随后 `_startDeferredLoad()`，注释明言"避免落在 380ms 转场窗口中段" | :293 换 `_waitOwnTransition()`；其后 `_startDeferredLoad()`（内部 :492/:553 各有独立 gate）原样 | **low**。机械替换；快路径 :285 提前 return 不受影响 |
| `lib/pages/tv_detail_page.dart:321` | `_load()` 非飞牛→`_loadNeutral()`：`backend.getItemDetail` 后 mounted(:320)→gate→setState 中立详情，随后 `unawaited(_loadNeutralSeasons)` + `_descriptionVisible=true` + `_descriptionPopController.forward` 一并被推迟到转场外 | :321 换 `_waitOwnTransition()`；后续原样 | **low**。机械替换；`_loadNeutralSeasons` 自带 endOfFrame+内容比对守卫 |
| `lib/pages/tv_detail_page.dart:391` | `_refreshBaseDetail()` 成功分支（快路径 :286 unawaited 发起）：刷新回包后 mounted(:388)→gate→setState(`_applyBaseDetail`,`_baseDetailIsFull=true`,解除 `_suppressGlobalThemeSyncUntilFullDetail`,`_error=null`)，注释明言"回包大概率落在 380ms 进场转场内" | :391 换 `_waitOwnTransition()`；锚点 future 在转场中必须**真实等待**而非立即 resolve | **low**。机械替换；验收需覆盖 initialItemDetail 快路径（"稳定即立即 resolve"若被误做成"永不等待"，该处退回转场窗内整页重建） |
| `lib/pages/tv_detail_page.dart:401` | `_refreshBaseDetail()` catch 分支：刷新失败也 gate→setState 仅解除 `_suppressGlobalThemeSyncUntilFullDetail`（释放被压制的全局主题同步重活） | :401 换 `_waitOwnTransition()`；错误路径语义原样：失败也要等转场结束再放行主题同步 | **medium**。错误分支测试覆盖常薄：若锚点版在此语义偏差（抛错/提前 resolve），全局主题同步重活重回转场窗口且难察觉（仅 profile 打点可见）；需补"快路径+刷新失败"用例 |
| `lib/pages/tv_detail_page.dart:492` | `_startDeferredLoad()`→`_scheduleDescriptionReveal()`：gate→mounted(:493)→取消旧 `_deferredTimer`→180ms Timer→setState(描述可见+`_artworkReady`) + `_descriptionPopController.forward`，注释明言"180ms 起始延迟永远等转场结束后再起" | :492 换 `_waitOwnTransition()`；gate→timer→setState 串联顺序与 timer 内 mounted 检查原样 | **low**。注意 gate 与 180ms 延迟是**叠加**关系而非替代，改造不得把延迟折算进锚点 |
| `lib/pages/tv_detail_page.dart:553` | `_startDeferredLoad()`→`_loadDeferredSections()`：seasonItems/genres/locate/playInfo 四路并发 IO（:534-549），seasonItems 先回，mounted(:552)→gate→setState 应用季卡列表；其后 genres/locate/playInfo 的第二个 setState(:574) 今天就未过闸（有意设计） | :553 换 `_waitOwnTransition()`；:574 **不动**（勿顺手"补闸"造成行为变化） | **low**。唯一陷阱是顺手补闸 |
| `lib/pages/tv_season_detail_page.dart:999` | initState(:219 起)→`unawaited(_loadEpisodePickerModeSetting())`：`getPlaylistViewType` 回包后快照 `modeBeforeGate`(:998)→gate→mounted+mode 未被手动改过+不重复三重检查(:1000-1004)→setState 切换选集视图，注释明言"initState 发起的网络回包常落在 380ms 进场转场内" | :999 换 `_waitOwnTransition()`；**"快照(:998)→等待→重查(:1000-1004)"顺序是语义的一部分**（等待期间用户手动切换过则以手动为准），不得重排 | **medium**。竞态防线结构原样保留；需验证"手动切换 vs 服务端回包"竞争场景 |
| `lib/pages/tv_season_detail_page.dart:1128` | `_loadSeasonData()` 非飞牛→`_loadSeasonDataNeutral()`：季列表 best-effort + getItemDetail 回包后 seq+mounted 双检(:1127)→gate→双检(:1129)→setState 中立季详情，骨架→正文 | :1128 换 `_waitOwnTransition()`；gate 前后各一次 `seq != _seasonLoadSeq` 检查原样（防切季/重试旧回包竞态）；其后 showLoading 分支的复位/入场动画/后续加载原样 | **low**。此路径也会被切季复用：中立切季走缓存时 detail 可能同步返回，gate 在路由已稳时须**立即 resolve**，勿引入帧延迟 |
| `lib/pages/tv_season_detail_page.dart:2115` | `_loadSeasonData()` 飞牛分支（三入口：首入 showLoading=true(:220)、切季 showLoading=false(经 ：2305-2310 await `_loadSeasonData(..., showLoading: false)`)、重试(DetailStatusPage onRetry :3069)）：detail 与 playInfo await 完，双检(:2112)→gate→双检(:2116)→setState 应用季详情+播放信息（showLoading 清空选集区走骨架，否则直接换内容） | :2115 换 `_waitOwnTransition()`；seq 双检原样；其后 `_resetScrollToTop`/`_startEntryAnimations`/`_startDeferredLoad`/`_resolveEpisodeItems` 原样 | **medium**。**双语义调用点**：首入要真等待、切季要零延迟（注释明言"gate 立即返回，无额外延迟"是现网验收点）。`waitForRoute` 必须精确复刻 `_isAnimating` 判定（primary+secondary 两条，原 :51-55/:86-92 平移）与"稳定立即 resolve"（原 :90-92）——若给稳定路由引入哪怕一帧延迟，切季手感变慢；若反向误判，首入骨架→正文砸回转场窗口。两条路径都过 profile 验证 |

### 4.3 组件与首页组（7 处）

| where | flow（亲验，除注明外） | 改法 | 风险 |
|---|---|---|---|
| `lib/screens/media_list_screen.dart:930` | `_MediaListScreenState._refreshContinueWatching()`：详情页 push 返回（push 的 Future 在 pop 转场首帧前 resolve）、分屏 pane 打开或 app resumed 后拉"继续观看"，gate(:930)→mounted+refreshLoadKey 双检(:931)→setState 合并 home 数据（含 itemImageRequests/backdropImageRequests）。触发点 :242/:1258/:1307/:1360（盘点材料）；首页根 = `_buildScreen`（part 文件 `media_list_screen_widgets.dart:4`）返回 `AppAtmosphericBackground > Scaffold`（:35-37，亲验）；移动端在根导航器 home PageRoute 内、桌面端在 DesktopShell 嵌套 Navigator 内容路由内（盘点材料），两种情况 `ModalRoute.of` 均非空 | State 持 `_gateKey`，`_buildScreen` 返回处（`media_list_screen_widgets.dart:35`）外包 `RouteGateAnchor(key: _gateKey, child: AppAtmosphericBackground(...))`；:930 换 `await _waitOwnTransition()`（同 §3.4 范式） | **medium**。本组最重：`of()` 无转场也先注册依赖（:82-91），四个触发点首次任一执行后页根**永久**成为依赖者，每次弹窗开/关（长按菜单、筛选 sheet 等）都整页重建首页——与实测的 17.1ms+14.4ms 同类、幅度更大（桌面 push 69.5ms）。锚点随首页首帧建好，刷新只发生在导航返回/resume 后，可用性安全；桌面嵌套路由下锚点解析到嵌套内容路由，与现状一致 |
| `lib/widgets/app_atmospheric_background.dart:213` | `_AppAtmosphereSnapshotState._ensureSnapshot()` 的 addPostFrameCallback 内（:208-233；快照仅 Android+softMist 实例化，:138-147 亲验）：`Visibility`+`TickerMode` 前置短路(:211-212)后 `isTransitioning` 判断(:213)——Android 全屏背景截图前，若本路由正在转场则等转场结束再截图，注释明言"隐藏标签和转场首帧没有可截图的绘制层" | 快照 State 持 `final GlobalKey<RouteGateAnchorState> _gateKey`；**包住 build 返回整体**（`build` 的 `LayoutBuilder` 外层，:274）：`return RouteGateAnchor(key: _gateKey, child: LayoutBuilder(...))`——**不用** Stack 额外 child：build 在尺寸非法帧经 :277-282 早退 `return widget.child`（亲验，第二轮 #4），该形态下锚点在这些帧不在树、违反"任何帧都在场"不变量；:213 → `_gateKey.currentState?.isTransitioning ?? false`（包根后 currentState 在快照存活期间恒非空，`?? false` 仅剩理论兜底） | **low**。本组最轻：依赖落在快照元素上，弹窗通知只重建 LayoutBuilder+Stack+Opacity/RawImage 一小段，`widget.child`（AppAtmosphereSurface 同一实例 :133-137）被 identical 短路、不重绘——低收益，为统一模式仍搬迁。句柄 null（postFrame 时尚未挂载）→ false → 立即截图，等价 route==null 语义，只失去"转场首帧不截图"保护、不崩溃 |
| `lib/widgets/app_atmospheric_background.dart:214` | 同上：`await RouteTransitionGate.of(context)` 等本路由 primary+secondary 全部结束后才 toImage 截图和 setState；await 后 mounted(:215)→endOfFrame(:216)→再次 mounted(:217)→:220 可见性重查 | :214 → `await _gateKey.currentState?.waitTransition()`（句柄 null → await null 立即完成）；**与 :213 取同一句柄**（避免两处各自解析路由）；mounted 链(:215/:217)不能少。不可达性推演（第二轮 #4，未运行时验证）：:213/:214 仅从 `_ensureSnapshot`（:283-285 调用，早退帧到不了）调度的 postFrame 回调执行，回调在调度帧末触发（`binding.dart:1350-1351`）且当帧元素树仍完整（当帧移除的元素在 finalizeTree/`framework.dart:3339-3344` 已卸载、锚点当帧在场）——即使按旧 Stack 形态，"早退帧跳过保护"的后果链也不可达；包根放置使该推理不再必要 | **low**。同上；注册只发生在首次截图流程执行时（页面进场转场中必然执行一次） |
| `lib/widgets/detail/dynamic_page_theme_scope.dart:177` | `_DynamicPageThemeScopeState.didUpdateWidget`：props 变化(:136-154)且命中缓存 seed 时，若本页处于转场中走 `_applyResolvedSeedSetState`(:178) 推迟，否则直接翻 `_seed`；注释(:173-175)明言"转场中段直接切会引发整页 Theme 切换"。该 scope 是 6 个页面正文的根包装（tv_season:3043、tv_detail:1586、play_detail:3186、media_collection:1071、person_detail_screen:827 亲验；poster_browse（`lib/screens/poster_browse/poster_browse_screen.dart`，盘点材料 :1055 未亲验）），build 输出 `Theme > DynamicPageThemeSnapshot > Builder`（:818-824 亲验） | scope State 持 `final GlobalKey<RouteGateAnchorState> _gateAnchorKey`；在其 build 输出内（`DynamicPageThemeSnapshot` 的 child 处）包锚点叶子：`RouteGateAnchor(key: _gateAnchorKey, child: Builder(...))`；:177 → `_gateAnchorKey.currentState?.isTransitioning ?? false`（句柄 null → 视为未转场，对齐 ModalRoute.of==null 语义） | **medium**。`didUpdateWidget` 只在首次 build 后发生，句柄必可用；`initState` 命中缓存的同步路径(:114-118)不经闸门直接赋 `_seed` 是既有设计勿动；`didChangeDependencies`(:125-130) 的 `context.watch<AppThemeProvider>` + `_syncGlobalRuntimeTheme`（稳态经 :540-548 签名早退）必须保留 |
| `lib/widgets/detail/dynamic_page_theme_scope.dart:394` | `_applyResolvedSeedSetState`（异步 seed 应用入口，didUpdateWidget:178、_restoreCachedSeedIfNeeded、_resolve 多条路径调用——盘点材料）：`!mounted \|\| _seed == seed` 早退(:391)→`isTransitioning`(:394)→转场中走推迟(:395-404)，否则 setState(:406-411) | :394 → 同一 `_gateAnchorKey` 句柄读 `isTransitioning`；与 :177 共用一次句柄读取（今天两处连续查询、注册幂等，改造后亦应共用） | **medium**。调用方有 4 条异步路径，句柄需全路径可用；推迟分支的 requestVersion/pageKey/url/headers 快照(:398-401)原样 |
| `lib/widgets/detail/dynamic_page_theme_scope.dart:421` | `_applyResolvedSeedAfterTransition`：`await RouteTransitionGate.of(context)` 等本路由转场全部结束，再过五重守卫(:422-428：!mounted / !enabled / requestVersion 漂移 / pageKey-url-headers 任一漂移 / `_seed == seed`)→setState 应用 seed | :421 → `await _gateAnchorKey.currentState?.waitTransition()`（null → 立即 resolve = 视为未转场）；五重守卫逐字原样 | **medium**。五重守卫是"转场期间目标已变化"的唯一竞态防线，不可精简；`waitForRoute` 在 resolve 前摘除 listener（原 :101-106 平移）避免泄漏，已满足 |
| `lib/widgets/detail/immersive_detail_background.dart:580` | `_BackgroundImage.build` 的 `Image.network` frameBuilder(:569-589) 内：本路由转场中直接返回 child 跳过 180ms AnimatedOpacity 淡入（注释 :576-579：转场已把整页包在 FadeTransition，再叠一层分数透明度会在 hero 大图上叠加离屏合成，恰逢首帧纹理上传，是 push 尾段丢帧点）。依赖落点特殊：frameBuilder 的 context 是 Image widget 自身 element（近叶子；SDK `image.dart:1437` `_ImageState.build` 内调用，盘点材料核验），非 background State 的 context | **建议维持现状，仅加注释记录**。理由：依赖本就落在 Image element 叶子，弹窗开/关只重建该 element（重跑 `_ImageState.build`，ImageStream 同 provider 走缓存，无 layout/重绘变化），是全部调用点中最轻之一；若强行叶子化需把"转场中跳过淡入"决策下沉为叶子 State 组件并保持 element 位置/key 稳定（否则 AnimatedOpacity 淡入进度重置），收益/风险比差。若坚持迁移：frameBuilder 返回叶子组件、由其持有依赖决定 AnimatedOpacity vs child，排最后处理；**与 C7② 的组合约束（第二轮 #2）**：本行维持现状则旧 `isTransitioning` 不可删除（§3.5 分支 (a)） | **low**（维持现状零风险；叶子化则有淡入进度重置风险）。决策只在图片解码帧时刻有意义（恰是页面进场转场中），弹窗开/关期间该值稳定。TvSeason/Play/Tv 三个详情页各有一处该组件实例（盘点材料：tv_season:1850/3217、play_detail:3243、tv_detail:954/1733），每页注册一个 Image element |

### 4.4 相邻引用（本次不动但必须保留）

1. `lib/main.dart:461`：`RouteTransitionGate.observer` 挂载（`_appNavigatorObservers`，亲验）不变；`_RouteTransitionWatch` 计数/退场回收（gate `:115-215`）原样。
2. `anyRouteTransitioning` 消费点：`app_theme_provider.dart:1242/:1247`、`dynamic_page_theme_scope.dart:671`（`_flushGlobalThemeSyncWhenStable` 把全局主题 flush 推迟出转场窗口，亲验）——静态计数器、无 context、无 `_ModalScopeStatus` 依赖，不受锚点化影响，但重构 gate 时不得破坏其语义。
3. `DynamicPageThemeScope` 的 6 个宿主页面中，person_detail/poster_browse 两个页面的 State **没有** gate 调用（地面真值确认），无需页根锚点——scope 内部锚点已覆盖其正文。
4. 页根锚点与 scope 内部锚点并存（如 tv_season：:3043 页根锚点套在 `DynamicPageThemeScope` 外，scope 内部另有一枚）互不干扰：`waitForRoute` 无共享可变状态，两枚锚点各自解析同一条页面路由。

---

## 5. 测试计划

### 5.1 现有覆盖（本人 grep + 读码确认）

- `test/widgets/dynamic_page_theme_scope_headers_race_test.dart`：唯一引用 RouteTransitionGate 的既有测试。用 `debugOverrideTransition(isTransitioning/wait)`（:84-87、:114-117，亲验）人为开/关转场窗口，覆盖 DynamicPageThemeScope 时序约束；`:31/:162` 的 `debugResetTransitionOverride` 是 tearDown 隔离约定。它没碰 `of()` 对真实路由动画的 resolve 时机、无 ModalRoute 分支。**核心重构后不需改动即继续生效**（override 检查收敛进核心，薄封装与锚点都先查 override）——改造 `dynamic_page_theme_scope.dart` 后必须重跑。
- `test/widgets/async_gap_lifecycle_test.dart`：纯源码文本断言（async gap 后 `if (!mounted) return;` 契约）——本方案保留所有 mounted 自查，不受影响。
- `test/widgets/catalog_query_sheet_reuse_test.dart:23-48`：同款文本断言先例 + :50 起的弹窗 widget 测试写法（_app harness / tap / pumpAndSettle），可作新增测试的写法参照。

### 5.2 新增测试

**文件一：`test/widgets/route_transition_gate_anchor_rebuild_test.dart`**

1. **弹窗 push/pop 期间页面根 State 不重建（showModalBottomSheet 与 showDialog 各一轮）**——黄金测试。埋点页面（Stateful，根 build 计数自增）作为 `MaterialApp.home`，`navigatorObservers` 传 `RouteTransitionGate.observer`（对齐生产 `main.dart:461`）；页面根经 `RouteGateAnchor` 注册本页路由依赖（即 §3.4 改造后的取 future 路径）。每轮：弹窗打开 → 小步 pump 进转场中途（不硬编码弹窗时长）→ pumpAndSettle → pop → pumpAndSettle，断言根 build 计数全程不变。**修复前此测试必红**：页根 element 经 `ModalRoute.of`（gate :66）注册 `_ModalScopeStatus` 依赖（SDK routes.dart:1015，本机 SDK 3.41.6 已复核同位置），弹窗开/关翻转 isCurrent 触发整页重建（实测 17.1ms BUILD）。**灵敏度演示（第二轮 #5）**：常驻 harness 按改造后形态构建，"必红"是反事实叙述——实现时先写一个一次性旧式对照变体（同款 harness 但页根 State 直接 `await RouteTransitionGate.of(context)`），断言弹窗开/关时根 build 计数增长（测试红），验证 harness 灵敏度后即删除；该变体不进常驻套件。
2. **锚点叶子承接依赖并在翻转时被通知，页面根不受影响**。同一 harness 的第二组断言：钩子形态定死为 `RouteGateAnchorState` 上的 `@visibleForTesting static int debugRebuildCount`——在锚点 `build` 内 `assert(() { debugRebuildCount++; return true; }())` 自增（release 零成本；测试文件 `setUp` 清零，对齐 `debugResetTransitionOverride` 的 tearDown 隔离约定）。断言弹窗每轮 push/pop `debugRebuildCount` 均增长（≥ 轮次）且页面根 build 计数不动。注意：`Element._dependencies` 为私有（framework.dart），无公开 API 从测试侧检查依赖集合，必须经锚点自身计数观测。

**文件二：`test/widgets/route_transition_gate_of_timing_test.dart`**

3. **gate future 在转场动画结束后才 resolve（primary+secondary 双动画语义）**：① push 二级页，转场中途调用 `RouteTransitionGate.of(二级页 context)`，假时钟下 await 未完成、pumpAndSettle 后完成；② 底层页 context 在上层 push 弹窗/页面期间（secondaryAnimation 在动）同样等转场结束才 resolve（gate :86-92）；③ 快速连续 push 两页：底层页 future 必须等**两条动画都 completed**（:95-99 状态变化重查逻辑，现无任何测试）。resolve 观测用 flag + then()，逐 pump 断言。同一组断言对 `RouteGateAnchorState.waitTransition()` 与核心 `waitForRoute()` 各跑一遍（三者同走核心，等价性回归保护）。
4. **无 ModalRoute 的 context 立即 resolve 且 isTransitioning 为 false**：用 Navigator 之上的 context（MaterialApp.builder，`ModalRoute.of` 返回 null）调 `of()` 与 `isTransitioning`（gate :66-69/:82-84 null 分支，现无测试）：future 在下一次 pump 即完成、false，不挂起不报错。锚点的 route==null 退化路径同验。
5. **debugOverrideTransition 短路语义不变**：① 真实转场进行中强制 `isTransitioning:false + wait=已完成 future` → 立即返回/立即 resolve（短路优先于真实动画）；② 路由完全稳定时强制 wait=未完成 Completer → 挂起直至 complete；③ `debugResetTransitionOverride` 后恢复读真实路由。tearDown 用 reset，对齐 race test :30-36 既有约定。

**补充（可选，仅作辅助）**：仓库有源码文本断言先例（§5.1），可加一条"页面根 State 不再以自身 context 调 `RouteTransitionGate.of`"的文本契约断言，但不替代行为测试。

### 5.3 运行命令

```bash
# 新增两个测试文件
flutter test test/widgets/route_transition_gate_anchor_rebuild_test.dart test/widgets/route_transition_gate_of_timing_test.dart

# 改造 dynamic_page_theme_scope.dart 后必跑（override 钩子经核心仍生效的回归）
flutter test test/widgets/dynamic_page_theme_scope_headers_race_test.dart

# 全量（README.md:105-114：限制并发降内存）
flutter analyze
flutter test --concurrency=1
```

基础设施已核对：flutter_test 在 dev_dependencies、另有 fake_async ^1.3.3、无 mocktail（pubspec.yaml，亲验）；测试落 `test/widgets/`，与既有 gate 行为测试（`dynamic_page_theme_scope_headers_race_test.dart` 等）同目录。勘误（评审处理记录 #2）：`test/ui/` 并非无 pumpWidget 先例——`rg -n "pumpWidget" test/ui/` 实测命中 `test/ui/media_layout_profile_test.dart:73`，原表述有误；但 gate 相关行为测试的既有先例集中在 `test/widgets/`，落点结论不变。

---

## 6. 实施步骤顺序与提交切分建议

| 提交 | 内容 | 要点 |
|---|---|---|
| C1 | `lib/ui/route_transition_gate.dart`：抽核心 `waitForRoute`/`isRouteTransitioningRoute` + 新增 `RouteGateAnchor`/`RouteGateAnchorState` + 旧 API 改 `@Deprecated` 薄封装 | **零调用点改动**的纯机械重构；`flutter analyze` + 现有测试全绿即合（`@Deprecated` 对 analyze 零输出：本仓库 lints 3.0.0 未启用 `deprecated_member_use_from_same_package`，探针实证见 §3.5/§9 第二轮 #1） |
| C2 | 新增两个测试文件（§5.2 全部 5 例） | 先于调用点迁移落地，锁定核心/锚点语义；黄金测试在 C1 后即为绿（harness 自用锚点） |
| C3 | `tv_season_detail_page.dart` 迁移（:999/:1128/:2115 + :3043 包锚点） | 实测对象先行：提交后立即按 §8.2 真机复测，验证收益（BUILD 25.2→~8ms）再继续 |
| C4 | 其余三详情页迁移：`media_collection_detail_page.dart`（:143/:180 + :1071）、`play_detail_page.dart`（:1546/:1593/:1737 + :3186）、`tv_detail_page.dart`（:293/:321/:391/:401/:492/:553 + :1586） | 严格按 §4.2 各行改法与"原样保留"清单 |
| C5 | `media_list_screen.dart:930`（锚点包 `media_list_screen_widgets.dart:35` 返回根） | 首页收益最大的一处；桌面+移动两种形态各过一遍弹窗开关 |
| C6 | `dynamic_page_theme_scope.dart`（:177/:394/:421 + build 内锚点叶子）与 `app_atmospheric_background.dart`（:213/:214 + Stack 额外 child 锚点） | 必重跑 `dynamic_page_theme_scope_headers_race_test.dart`；Android 真机验证 softMist 背景截图正常 |
| C7（后续独立 PR，可选） | ① `immersive_detail_background.dart:580` 的决策落地（维持现状注释 或 叶子化）；② 删除旧 API 并把兜底改立即 resolve | **组合陷阱（第二轮 #2）**：:580 维持现状时 `isTransitioning` 永远有调用者，直接删除会编译失败——删除前置条件 = :580 一并叶子化（或改走锚点句柄）**且**兜底路径证伪（黄金测试长期绿 + 导出日志无 `route gate anchor missing` 记录）；若 :580 维持现状，则 C7 不删 `isTransitioning`、仅删 `of`（兜底证伪后），见 §3.5 分支 (a)/(b) |

顺序理由：先机制后调用点（C1/C2 可独立 review）；实测页面最先迁移以便尽早拿到真机数据定标；首页单独一刀（触发点 4 个、桌面/移动双形态，问题面独立）；widget 组最后（现有测试直接回归）。每个提交独立可回滚。

---

## 7. 风险与回归面

1. **语义漂移（等待对象改变）**：迁移时若某调用点旧 context 实际解析到别的路由（如弹窗内容透传下层页 context），统一换成"本处锚点"会改变等待对象。已逐处亲验：14 处 `of()` 均为页面根 State 自身 context、无跨路由传参；:580 的 frameBuilder context 是 Image element。迁移 PR 仍需逐处对照 §4 表。
2. **锚点 build 形态回归（无声复活）**：后人改动锚点 build 返回形态（包装/换 key/拼新 widget）会让整页重建问题无声复活。对策：`RouteGateAnchor` doc comment 显著警告（§3.3）+ §5.2 黄金测试固化"弹窗开/关时页根 build 不再执行"。
3. **SDK 私有机制依赖**：锚点依赖 `ModalRoute.of` → `_ModalScopeStatus`（私有类）的依赖注册行为，本机 SDK（`F:\software\flutter_Sdk\flutter`，commit db50e20168d，2026-03-25）已核验；Flutter 升级后需复核（黄金测试即复核手段）。
4. **兜底路径的双重风险**：① 若清理 PR 直接删除旧 API，兜底需改为立即 resolve + assert，弱化极端路径语义——对策：旧 API 保留到兜底可被证伪删除之后（§3.5）。② 兜底一旦在生产触发，页根 element 经 `of(context)` **永久重新注册** `_ModalScopeStatus` 依赖（直至 element 卸载），整页重建无声复活，且 `reportError` 在 assert 内、profile/release 零信号——§7.2 的 doc 警告与 §5.2 黄金测试都覆盖不到该通道。对策：兜底处 `logSwallowedError` 落全模式可观测痕迹（§3.4/§3.5），§8.2 复测核对导出日志；若长期零触发再按 §3.5 走 C7 弱化方案。
5. **动画 listener 不 resolve 的极端面不变**：路由被 removeRoute 强拆且动画无状态变化时 completer 永不完成——与现行实现完全一致（原 :93-111 平移），本次不新增风险面；`play_detail_page.dart:1737` 的 unawaited 跨 pop 场景依赖"listener 挂动画不挂锚点元素"，§5.2 测试 3 覆盖。
6. **切季零延迟回归**：`tv_season:2115` 同一处承担"首入真等待 / 切季零延迟"双语义；`waitForRoute` 稳定即立即 resolve（原 :90-92 平移），若引入帧延迟切季手感变慢。验收覆盖两条路径（§8.3）。
7. **错误分支覆盖薄**：`tv_detail:401`（刷新失败释放主题同步压制）语义偏差难察觉（仅 profile 可见）。对策：补"快路径+刷新失败"用例。
8. **顺手改坏的既有设计**：`tv_detail:574` 第二个 setState 有意未过闸、`dynamic_page_theme_scope` initState 缓存同步路径(:114-118)不经闸门、`play_detail:1589` 的 `unawaited(_loadPhase2)` 相对顺序——迁移时全部不动。
9. **文本契约测试**：`async_gap_lifecycle_test.dart` 验证的 mounted 契约全量保留，不受影响。

---

## 8. 验证方式

### 8.1 静态与单测（每提交必跑）

```bash
flutter analyze
flutter test test/widgets/route_transition_gate_anchor_rebuild_test.dart test/widgets/route_transition_gate_of_timing_test.dart
flutter test test/widgets/dynamic_page_theme_scope_headers_race_test.dart   # C6 必跑
flutter test --concurrency=1                                                # 合并前全量
```

### 8.2 真机复测（adb + logcat + PERFDRV，手法出自 `.zcode/perf/popup_jank_summary.md`）

1. **构建**：`flutter run --profile`（包 `com.geqian.flyplayer.fly_player.profile`），设备 2410CRP4CC（120Hz）。
2. **场景**：与实测对齐——分屏（左首页 / 右"小林家的龙女仆 第1季"季详情，右栏引擎源 placeholder route=/parallel/placeholder，主窗 main route=/）。
3. **驱动与打标**：每次动作前 `adb shell log -t PERFDRV T_OPEN_x / T_CLOSE_x` 打标，`adb input tap` 驱动选集弹窗与"更多操作"弹窗开/关各 ≥5 轮；注意标记→tap 有一次 adb 往返（约 100–250ms），帧时间按"转场期间"窗口解读。
4. **采集**：`adb logcat` 带时间戳抓 `[PERF][FRAME]`（`main.dart` `_FrameTimingLogger`，jank 阈值 total>33.3ms）；分析沿用 summary 手法：去重 logcat 多 buffer 重复行 → 按时间排序 → jank 帧归因到最近标记。
5. **验收指标**：
   - 弹窗开/关 jank 帧从 37.8–46.0ms（summary 实测 36.9–46.9ms）降到 **33.3ms 线以下，目标 ~12ms**；
   - 对应 BUILD 25.2→~8ms、LAYOUT 14.4→~3ms（预期值出自 summary §修复方向）；
   - 空闲基线不回归（avgTotal 8.5–9.8ms、estFps 102–117）。
6. **手动回归清单**：4 个详情页进场（骨架→正文时机不早不迟）、tv_season 切季手感（零延迟）、tv_detail 快路径 + 刷新失败、描述区 180ms reveal 节奏、首页 push 返回续看刷新、Android softMist 背景截图正常、桌面 pane 内详情页弹窗开关、导出应用日志核对无 `route gate anchor missing` 记录（兜底未被触发的直接证据，§3.5）。

### 8.3 VM timeline 复核（可选，C3 后执行一次）

临时开启 `debugProfileBuildsEnabled + debugProfileLayoutsEnabled`（69b77118 手法，分析完还原），`flutter run --profile` 附 VM service：`setVMTimelineFlags(["Dart","Embedder"])` → 弹窗开/关 ×2 → `getVMTimeline`，确认弹窗帧 BUILD 中**不再出现 TvSeasonDetailPage 整页重建**（根因验收的直接证据；锚点 element 自身重建应为 <1ms 量级）。

---

## 9. 评审处理记录

### 第一轮（2026-09-30）

| # | 意见（severity） | 核验结论 | 处理方式 |
|---|---|---|---|
| 1 | C1 给旧 API 加 `@Deprecated` 时 21 处旧调用点尚未迁移，`deprecated_member_use_from_same_package`（info 级）在每处报出，而 `flutter analyze` 默认 `--fatal-infos=true`，C1"analyze 全绿即合"必失败（medium） | **成立**。亲验：本地 SDK `F:/software/flutter_Sdk/flutter/packages/flutter_tools/lib/src/commands/analyze.dart` 中 `argParser.addFlag('fatal-infos', ..., defaultsTo: true)`；仓库根 `analysis_options.yaml` include `package:flutter_lints/flutter.yaml`（3.0.0）且 rules 全部注释、无该 lint 抑制 | 采纳"C7 再加 `@Deprecated`"方案（而非迁移期在 21 处旧调用点补 ignore——避免 8 文件噪音与事后清理）：§3.2 薄封装改为普通封装、§3.5 重写去留策略、§3.4 明确 ignore 补加时点、§6 C1/C7 行与验收口径同步修正。**⚠ 已被第二轮 #1 推翻**：该 lint 实际未启用（"未抑制"≠"启用"，第一轮核验不完整），暂缓策略撤销、`@Deprecated` 恢复 C1 即加——见第二轮表 #1 |
| 2 | §5.3"`test/ui/` 无 pumpWidget 先例"不实（low） | **成立**。`rg -n "pumpWidget" test/ui/` 实测命中 `test/ui/media_layout_profile_test.dart:73` | §5.3 已勘误并注明亲验命令；"新测试落 `test/widgets/`"结论不变（gate 行为测试先例在该目录） |
| 3 | 文档两处（§4.1 第 3 条、§5.2 测试 2）引用不存在的"开放问题"章节，锚点测试钩子形态悬空（low） | **成立**（文档内自检：两处引用存在，§1-§8 无该节） | 定死形态，不再引用：`RouteGateAnchorState.@visibleForTesting static int debugRebuildCount`（build 内 assert 自增、setUp 清零），写入 §5.2 测试 2；§4.1 引用改为指向 §5.2 |
| 4 | 薄封装单表达式 `isRouteTransitioningRoute(ModalRoute.of(context))` 的实参先于核心内 override 检查求值——`debugOverrideTransition` 生效时仍调 `ModalRoute.of` 注册依赖，与旧实现（:64-65/:80-81 早退于 :66/:82 之前）不一致，§3.2"逐条一致"表述不准（low） | **成立**。旧实现顺序经全文亲读确认（route_transition_gate.dart:64-66、:80-82）；Dart 实参先于调用求值，单表达式薄封装必然先触达 `ModalRoute.of` | §3.2 薄封装改为"先查 override、再调 `ModalRoute.of`"的块体，并加注释说明不能用单表达式；§3.2 语义对照表该行改为"含副作用逐条一致" |
| 5 | 兜底路径生产触发一次即让页根永久重新注册依赖、整页重建无声复活；`reportError` 在 assert 内 profile/release 零输出，§7.2 防复活手段覆盖不到该通道（low） | **成立**（§4.2 已核验 14 处 `of()` 均在网络 await 之后，兜底属理论竞态，severity 低合理） | 采纳"留 profile 可观测痕迹"：§3.4 兜底改为 `unawaited(logSwallowedError(...))` + assert 报告双通道——亲验 `lib/utils/swallowed_error_logger.dart:6-31` → `AppLogService.recordWarning`/`record`（`lib/services/app_log_service.dart:372-404`）无 debug 门控、落盘可导出；§3.5 增"兜底可观测性"条目、§7 第 4 条改为"双重风险"、§8.2 回归清单加"导出日志核对无 `route gate anchor missing`" |

### 第二轮（2026-09-30）

| # | 意见（severity） | 核验结论 | 处理方式 |
|---|---|---|---|
| 1 | `deprecated_member_use_from_same_package` 在本仓库根本未启用（pubspec.lock 锁 lints 3.0.0；lints/flutter_lints 包全目录 grep 零命中；analysis_options 无 analyzer/errors 段；dart analyze 探针 "No issues found!"），第一轮"未抑制"核验漏了"未启用"，"C1 不得加 @Deprecated"的整套暂缓策略建立在错误论断上，且 §9 把它标为"亲验成立"（medium） | **成立，第一轮结论被推翻**。全部证据本轮独立重跑：① `sed -n '185,192p;328,335p' pubspec.lock` → flutter_lints 3.0.2（direct dev）/ lints 3.0.0（transitive）；② `rg -n "deprecated" <pub cache>/flutter_lints-3.0.2/lib <pub cache>/lints-3.0.0/lib` → exit=1 零命中（启用链 flutter.yaml → lints/recommended.yaml → core.yaml 全覆盖，flutter.yaml 仅额外 13 条无关规则，亲读）；③ `analysis_options.yaml` 亲读无 errors 段；④ 实测探针（`%TEMP%/lint_probe_r2`：flutter_lints ^3.0.0 + include flutter.yaml + 同包 `@Deprecated` 静态方法及其调用）`dart pub get && dart analyze` → **"No issues found!"**（Dart SDK 3.11.4，探针已删）；⑤ SDK `analyze.dart` 的 `--fatal-infos defaultsTo: true` 本身属实，但该 lint 不产生任何 info 输入，第一轮据此推理是"前提真、结论错" | 撤销第一轮暂缓：§3.2 恢复 C1 即加 `@Deprecated`（保留"先查 override 再调 ModalRoute.of"的块体，那是第一轮的有效产出）、§3.4 ignore 段改为"迁移期均无需 ignore"、§3.5 重写（记录教训"未抑制≠启用"）、§6 C1 行恢复 `@Deprecated`；第一轮表 #1 已加推翻标注 |
| 2 | C7②"旧调用点已清零"前置与 §4.3":580 维持现状"互相矛盾：直接删除旧 API 会让 :580 仍在调的 `isTransitioning(context)` 编译失败，方案未指出该组合陷阱（low） | **成立**。`rg -n "RouteTransitionGate" lib/widgets/detail/immersive_detail_background.dart` 重确认 :580 `RouteTransitionGate.isTransitioning(context)` 存在 | §3.5 改为显式二选一分支：(a) :580 维持现状 → C7 保留 `@Deprecated`、**永不删除** `isTransitioning`；(b) :580 一并叶子化后才可删。§6 C7② 前置条件重写、§4.3 表末行加组合约束交叉引用 |
| 3 | "SizedBox.shrink 零 RenderObject"不精确：它是 0×0 的 SizedBox，会 build 出一个零尺寸叶子 RenderConstrainedBox（low） | **成立**。SDK `basic.dart:2744` `const SizedBox.shrink(...) : width = 0.0, height = 0.0`；`basic.dart:2763-2764` `createRenderObject → RenderConstrainedBox(additionalConstraints)`（亲读） | §3.3 代码注释、§3.3 放置规则 1、§4.3 快照行三处统一改为"零尺寸叶子 RenderConstrainedBox（布局 O(1)、无绘制内容）" |
| 4 | 快照 build 的 LayoutBuilder 在尺寸非法帧早退 `return widget.child`（:274-281）不经过 Stack——Stack 额外 child 形态的锚点在该帧不在树，`_gateKey.currentState` 为 null，违反"任何帧都在场"（low） | **部分成立**。事实成立：早退分支亲验于 `app_atmospheric_background.dart:274-282`（:281 `return widget.child`，:283-285 才调 `_ensureSnapshot`）。但所指后果链经推演不可达（未运行时验证）：:213/:214 仅从 `_ensureSnapshot` 调度的 postFrame 回调执行，回调在调度帧末触发（`binding.dart:1350-1351`）且早退帧根本不调度；回调触发时当帧元素树仍完整（当帧移除的元素在 finalizeTree/`framework.dart:3339-3344` 已卸载，锚点当帧刚 build 在场），句柄读取时锚点在场 | 采纳更稳妥放置消除该边缘：§4.3 快照改法改为**包住 build 返回整体**（`LayoutBuilder` 外层），锚点全帧在场，使"任何帧都在场"对所有早退分支成立；§3.3 放置规则 1 补"早退分支"约束说明；不可达性推演记录于 §4.3 |
| 5 | "修复前此测试必红"是反事实叙述而非可执行工件：黄金测试 harness 按改造后形态构建，计划无旧式对照变体，红性无法作为测试产物演示；但测试 2 debugRebuildCount + 测试 1 组合已覆盖"空转通过"担忧（low） | **成立**（文档内自检：§5.2 测试 1 无对照变体设计） | §5.2 测试 1 增"灵敏度演示"实现步骤：一次性旧式对照变体（同款 harness、页根直接 `await RouteTransitionGate.of(context)`，弹窗开/关时根 build 计数应增长=红）验证 harness 灵敏度后删除，不进常驻套件 |
| 6 | 关键论断全面核验记录（非问题，供采信）：锚点机制端到端成立（routes.dart:1320/:1231、inherited_model.dart:193-194、framework.dart:5074-5079/4014）、rg 24 行与 §4.1 逐行一致、21 处调用点抽查精确命中、4 详情页 build 单一 return 无早退、gate 原语义逐条未变、测试约定属实（测试未执行——文件尚不存在）、logSwallowedError/initState 起点/analyze.dart:118/perf 数字均相符（low） | **采信**。与本方案自身核验记录一致处不再重复；其中测试部分评审声明未运行（只读核验），与本文 §5"proposed 为设计"口径一致 | 正文无需修改；作为第三方复核记录留存于本表 |

---

## 10. 实施与验收记录（2026-09-30 夜间自动执行）

**实施**：C1-C6 全部落地，工作区未提交（留待人工评审）。
改动文件（12）：`lib/ui/route_transition_gate.dart`（核心+锚点+@Deprecated 薄封装）、4 个详情页、`lib/screens/media_list_screen.dart` + `media_list_screen_widgets.dart`、`lib/widgets/detail/dynamic_page_theme_scope.dart`、`lib/widgets/app_atmospheric_background.dart`、`analysis_options.yaml`（见偏差）、新增 `test/widgets/route_transition_gate_anchor_rebuild_test.dart` 与 `route_transition_gate_of_timing_test.dart`；另 `lib/main.dart` 移除 69b77118 临时打点（履行该提交"分析完成后移除"的承诺，10 行删除）。

**门禁**：
- `flutter analyze`：0 issue（14s；`analysis_options.yaml` 增加 `analyzer.exclude: build/**` 后——build/ 为 gitignore 草稿目录，522 个 issue 全在其内，实施文件本身零 issue。此为唯一一次授权越界，理由与批准记录见工作流升级问答）。
- 定向测试 11/11 通过（首跑曾 6 过 5 挂 + 30 分钟超时：5 个失败均为**测试自身 bug**，实现零改动——①`await showDialog` future 构成死锁，观测 gate future 必须 flag+then；②SDK 真值：PopupRoute 压页面时下层 secondaryAnimation 恒 dismissed，`canTransitionTo` 不认弹窗，组②改为双 PageRouteBuilder 载体；③override 用例的前置条件在 MaterialPageRoute+PageRouteBuilder 组合下永不成立，改用 Material×Material 组合。修复者已在测试文件头注释记录陷阱）。
- 全量 `flutter test --concurrency=1`：1411 过 / 10 挂。**经 HEAD 基线 worktree 对照（F:/fp_baseline，已清理），10 个失败在 HEAD 原样复现**——全部为分支既有问题（connection/provider_gate 系登录改版、desktop 系布局/主题），本次实施零回归。

**真机复测**（2410CRP4CC，120Hz，分屏左首页/右季详情，adb+PERFDRV 手法同 §8.2）：

| 指标 | 修复前 | 修复后 |
|---|---|---|
| 选集弹窗打开 | 5/5 必挂，39.5-46.9ms（build 主导） | 首开 1 帧 43.3ms（一次性预热：弹窗内容首建+图片解码），开 2-8 **全零** |
| 选集弹窗关闭 | 5/5 必挂，37.1-42.0ms | 8 次中 1 帧边缘 33.6ms（build 仅 2.9ms、raster 28ms，GPU 合成波动非重建），其余全零 |
| "更多操作"弹窗开/关 | 9/10 + 5/5 必挂，36.9-45.6ms | 10 次**全零** |
| 锚点兜底遥测 `route gate anchor missing` | — | **零触发** |

结论：验收达标（G4）——修复前确定性 build 主导掉帧（整页重建 17.1ms/25.2ms BUILD）已消失，23 次弹窗动作仅 2 帧边缘越线且均为一次性/GPU 波动性质。

**遗留**：① C7 为后续独立 PR（§6）；② §8.2 第 6 条人工回归清单待用户有空过一遍；③ 全量 10 个既有失败不在本次范围，属分支登录改版中的已知状态。

**工具产物**：`.zcode/perf/`（retest_logcat.txt、retest2_logcat.txt、analyze_jank.py、baseline_out.txt 等）。
