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

  /// 是否有任意路由正处于转场动画中。
  static bool get anyRouteTransitioning => _activeTransitions > 0;

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

  /// [context] 所在 [ModalRoute] 是否正处于转场（enter/exit 动画运行中）。
  ///
  /// 同时检查 primary 与 secondary 动画：本页作为转场中的下层路由时
  /// （之上正在 push 新页、或上层正被 pop 揭开本页），自己的 primary
  /// animation 恒为 completed，动的是 secondaryAnimation——只看 primary
  /// 会让闸门在这两种场景下失效，重活照样砸进转场窗口。
  static bool isTransitioning(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route == null) {
      return false;
    }
    return _isAnimating(route.animation) ||
        _isAnimating(route.secondaryAnimation);
  }

  /// 返回一个 Future：在 [context] 所在 [ModalRoute] 参与的转场动画
  /// （primary 与 secondary）全部结束时 resolve；若该路由已稳定则立即 resolve。
  ///
  /// 注意：调用方在 await 之后必须重新检查 `mounted`，因为转场期间 widget 可能
  /// 已被销毁（例如进入途中又快速 pop）。
  static Future<void> of(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route == null) {
      return Future<void>.value();
    }
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
