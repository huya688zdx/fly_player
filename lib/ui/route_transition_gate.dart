import 'dart:async';

import 'package:flutter/widgets.dart';

/// 路由转场闸门：让页面把"重活"推迟到自己的进入转场动画结束之后再跑，
/// 避免与 380ms 的 enter/exit 动画在同一窗口内叠加导致掉帧。
///
/// 用法：
/// ```dart
/// await RouteTransitionGate.of(context); // 转场结束（或本就稳定）后 resolve
/// if (!mounted) return;
/// setState(() { /* 应用已就绪的结果 */ });
/// ```
///
/// 另外通过 [observer] 维护全局 [anyRouteTransitioning] 标志，供没有合适
/// context 的全局调度（如全局主题同步 flush）判断当前是否有路由正在转场。
class RouteTransitionGate {
  RouteTransitionGate._();

  // 当前正在跑 enter/exit 动画的 PageRoute 数量，由 [observer] 维护。
  static int _activeTransitions = 0;
  static bool? _debugTransitioningOverride;
  static Future<void>? _debugWaitOverride;

  /// 是否有任意路由正处于转场动画中。
  static bool get anyRouteTransitioning =>
      _debugTransitioningOverride ?? _activeTransitions > 0;

  @visibleForTesting
  static void debugOverrideTransition({
    required bool isTransitioning,
    required Future<void> wait,
  }) {
    _debugTransitioningOverride = isTransitioning;
    _debugWaitOverride = wait;
  }

  @visibleForTesting
  static void debugResetTransitionOverride() {
    _debugTransitioningOverride = null;
    _debugWaitOverride = null;
  }

  static _RouteTransitionGateObserver? _observer;

  /// 维护 [anyRouteTransitioning] 的 NavigatorObserver。挂到
  /// `MaterialApp.navigatorObservers` 即可。
  static NavigatorObserver get observer =>
      _observer ??= _RouteTransitionGateObserver();

  static bool _isAnimating(Animation<double>? animation) {
    final status = animation?.status;
    return status == AnimationStatus.forward ||
        status == AnimationStatus.reverse;
  }

  /// 路由级判定：[route] 是否正处于转场（enter/exit 动画运行中）。
  ///
  /// [debugOverrideTransition] 的 override 检查收敛于此，旧 API 薄封装与
  /// [RouteGateAnchorState.isTransitioning] 共用。
  ///
  /// 同时检查 primary 与 secondary 动画：本页作为转场中的下层路由时
  /// （之上正在 push 新页、或上层正被 pop 揭开本页），自己的 primary
  /// animation 恒为 completed，动的是 secondaryAnimation——只看 primary
  /// 会让闸门在这两种场景下失效，重活照样砸进转场窗口。
  static bool isRouteTransitioningRoute(ModalRoute<dynamic>? route) {
    final debugOverride = _debugTransitioningOverride;
    if (debugOverride != null) return debugOverride;
    if (route == null) return false;
    return _isAnimating(route.animation) ||
        _isAnimating(route.secondaryAnimation);
  }

  /// 路由级等待：返回一个 Future，在 [route] 参与的转场动画（primary 与
  /// secondary）全部结束时 resolve；[route] 为 null 或已稳定则立即 resolve。
  ///
  /// - status listener 挂在 [route] 的两个 [Animation] 对象上（不依赖任何
  ///   element 存活，页面 pop 后 await 仍能随动画结束 resolve）；
  /// - 任一动画状态变化后重查两条、都稳定才放行（primary 刚 completed 时
  ///   secondary 可能又启动）；
  /// - 每次调用独立 completer + 独立 listener，同一路由可并发多次 await，
  ///   resolve 时各自摘除，无共享可变状态；
  /// - 稳定路由立即 resolve，切季等复用路径零帧延迟。
  ///
  /// 注意：调用方在 await 之后必须重新检查 `mounted`，因为转场期间 widget 可能
  /// 已被销毁（例如进入途中又快速 pop）。
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
      // 可能又启动（快速连续导航），必须两条都稳定才放行。
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

  /// 旧 API：迁移期薄封装，改用 `RouteGateAnchor` +
  /// `RouteGateAnchorState.waitTransition`（完成迁移后由清理 PR 删除）。
  ///
  /// override 检查必须先于 `ModalRoute.of`：`debugOverrideTransition` 生效时
  /// 不得触达调用处 element（不注册 `_ModalScopeStatus` 依赖），与旧实现的
  /// 早退顺序一致。不能把整个方法体写成单表达式的
  /// `waitForRoute(ModalRoute.of(context))`——实参先于 [waitForRoute] 内的
  /// override 检查求值，override 生效时仍会在调用处注册依赖。
  @Deprecated(
    '在调用处 element 上注册 _ModalScopeStatus 依赖，弹窗开/关会触发'
    '整页重建；改用 RouteGateAnchor + RouteGateAnchorState.waitTransition',
  )
  static Future<void> of(BuildContext context) {
    final debugOverride = _debugWaitOverride;
    if (debugOverride != null) return debugOverride;
    return waitForRoute(ModalRoute.of(context));
  }

  /// 旧 API：迁移期薄封装，改用 `RouteGateAnchorState.isTransitioning`。
  /// override 检查先于 `ModalRoute.of`，理由同 [of]。
  @Deprecated('同 of()；改用 RouteGateAnchorState.isTransitioning')
  static bool isTransitioning(BuildContext context) {
    final debugOverride = _debugTransitioningOverride;
    if (debugOverride != null) return debugOverride;
    return isRouteTransitioningRoute(ModalRoute.of(context));
  }
}

/// 跟踪单条路由动画对全局计数器的贡献，避免重复加减。
class _RouteTransitionWatch {
  _RouteTransitionWatch(this.animation, this._onDismissed) {
    animation.addStatusListener(_onStatus);
    _apply(animation.status);
  }

  final Animation<double> animation;
  final VoidCallback _onDismissed;
  bool _counting = false;
  bool _disposed = false;

  void sync() => _apply(animation.status);

  void _onStatus(AnimationStatus status) => _apply(status);

  void _apply(AnimationStatus status) {
    if (_disposed) {
      return;
    }
    final animating =
        status == AnimationStatus.forward || status == AnimationStatus.reverse;
    if (animating && !_counting) {
      _counting = true;
      RouteTransitionGate._activeTransitions++;
    } else if (!animating && _counting) {
      _counting = false;
      RouteTransitionGate._activeTransitions--;
    }
    // 完全退场（reverse 结束）后这条路由不会再回来，回收监听避免泄漏。
    if (status == AnimationStatus.dismissed) {
      _onDismissed();
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    animation.removeStatusListener(_onStatus);
    if (_counting) {
      _counting = false;
      RouteTransitionGate._activeTransitions--;
    }
  }
}

class _RouteTransitionGateObserver extends NavigatorObserver {
  final Map<Route<dynamic>, _RouteTransitionWatch> _watches =
      <Route<dynamic>, _RouteTransitionWatch>{};

  void _watch(Route<dynamic>? route) {
    if (route is! ModalRoute) {
      return;
    }
    final animation = route.animation;
    if (animation == null) {
      return;
    }
    final existing = _watches[route];
    if (existing != null) {
      existing.sync();
      return;
    }
    _watches[route] = _RouteTransitionWatch(animation, () => _unwatch(route));
  }

  void _unwatch(Route<dynamic>? route) {
    final watch = _watches.remove(route);
    watch?.dispose();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _watch(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    // 被 pop 的路由开始反向退场；被揭开的下层路由可能反向回到前台。
    _watch(route);
    _watch(previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _unwatch(route);
    _watch(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _unwatch(oldRoute);
    _watch(newRoute);
  }
}

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

  /// 锚点 build 执行次数计数：在 [build] 的 assert 内自增（release 零成本），
  /// 供测试断言「依赖翻转只重建锚点本身、不波及页面根」；测试侧 setUp 清零。
  @visibleForTesting
  static int debugRebuildCount = 0;

  @override
  Widget build(BuildContext context) {
    // 依赖注册落在本叶子 element：ModalRoute.of → InheritedModel.inheritFrom
    // 无 aspect 路径（inherited_model.dart:193-194）→ 全量依赖 _ModalScopeStatus。
    // 放 build 中：锚点每次重建（含依赖翻转触发的重建）都刷新依赖与 _route，
    // 无陈旧路由引用。
    _route = ModalRoute.of(context);
    assert(() {
      debugRebuildCount++;
      return true;
    }());
    return widget.child ?? const SizedBox.shrink();
  }
}
