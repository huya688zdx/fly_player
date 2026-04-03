import 'package:flutter/material.dart';

import 'app_motion.dart';

class AppTransitions {
  const AppTransitions._();

  static Widget _lightweightPageTransition(
    Widget child,
    Animation<double> animation, {
    Offset begin = const Offset(0.035, 0.0),
  }) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final slide = Tween<Offset>(begin: begin, end: Offset.zero).animate(curved);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(position: slide, child: child),
    );
  }

  // Generic route animation timing.
  static const Duration routeEnter = AppMotion.routeEnter;
  static const Duration routeExit = AppMotion.routeExit;
  static const Duration switchDuration = AppMotion.switchDuration;
  static const Duration contentSwitchDuration = AppMotion.contentSwitchDuration;
  static const Duration topBarFadeDuration = AppMotion.topBarFadeDuration;

  // Shared easing curves.
  static const Curve easeOut = AppMotion.easeOut;
  static const Curve easeIn = AppMotion.easeIn;
  static const Curve progressIn = AppMotion.progressIn;
  static const Curve progressOut = AppMotion.progressOut;

  // Progress widget animation timing.
  static const Duration progressSizeDuration = AppMotion.progressSizeDuration;
  static const Duration progressFadeDuration = AppMotion.progressFadeDuration;

  // Standard page transition used by main route changes.
  static Widget fadeSlideTransition(
    Widget child,
    Animation<double> animation, {
    Offset begin = const Offset(0.02, 0),
  }) {
    final curved = CurvedAnimation(parent: animation, curve: easeOut);
    final slide = Tween<Offset>(begin: begin, end: Offset.zero).animate(curved);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(position: slide, child: child),
    );
  }

  // Standard page route using fade + slight horizontal slide.
  static Route<T> fadeSlideRoute<T>(
    Widget page, {
    RouteSettings? settings,
    bool fullscreenDialog = false,
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      fullscreenDialog: fullscreenDialog,
      transitionDuration: routeEnter,
      reverseTransitionDuration: routeExit,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return _lightweightPageTransition(child, animation);
      },
    );
  }

  static Route<T> standardDetailRoute<T>(
    Widget page, {
    RouteSettings? settings,
    bool fullscreenDialog = false,
  }) {
    return leftToRightPageTurnRoute(
      page,
      settings: settings,
      fullscreenDialog: fullscreenDialog,
    );
  }

  // Card-like transition: new page slides in from the right, previous page
  // shifts slightly left and scales down, which keeps the transition feeling
  // like a full card stack instead of exposing a blank background.
  static Widget leftToRightPageTurnTransition(
    Widget child,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    BuildContext context,
  ) {
    return _lightweightPageTransition(
      child,
      animation,
      begin: const Offset(0.055, 0.0),
    );
  }

  // Dedicated route for item-to-detail navigation.
  static Route<T> leftToRightPageTurnRoute<T>(
    Widget page, {
    RouteSettings? settings,
    bool fullscreenDialog = false,
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      fullscreenDialog: fullscreenDialog,
      transitionDuration: routeEnter,
      reverseTransitionDuration: routeExit,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          leftToRightPageTurnTransition(
            child,
            animation,
            secondaryAnimation,
            context,
          ),
    );
  }

  static Page<T> paneCardPage<T>({
    required Widget child,
    required LocalKey key,
    String? name,
    Object? arguments,
    String? restorationId,
    bool maintainState = true,
    bool disableHero = true,
  }) {
    return AppPaneCardPage<T>(
      key: key,
      name: name,
      arguments: arguments,
      restorationId: restorationId,
      maintainState: maintainState,
      disableHero: disableHero,
      child: child,
    );
  }

  static Route<T> paneCardRoute<T>(
    Widget page, {
    RouteSettings? settings,
    bool maintainState = true,
    bool disableHero = true,
  }) {
    return AppPaneCardRoute<T>(
      builder: (_) => page,
      settings: settings,
      maintainState: maintainState,
      disableHero: disableHero,
    );
  }

  static Route<T> splitPaneHostRoute<T>(
    Widget page, {
    RouteSettings? settings,
    bool maintainState = true,
    bool disableHero = true,
  }) {
    return _AppSplitPaneHostRoute<T>(
      builder: (_) => page,
      settings: settings,
      maintainState: maintainState,
      disableHero: disableHero,
    );
  }

  // Dedicated route for immersive player pages. Avoid lateral page-turn so the
  // previous detail page does not leak from the edge during entry.
  static Route<T> playerRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      opaque: true,
      transitionDuration: AppMotion.playerRoute,
      reverseTransitionDuration: AppMotion.playerRoute,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
          reverseCurve: Curves.easeInOutCubic,
        );
        final scale = Tween<double>(begin: 1.02, end: 1.0).animate(curved);
        final slide = Tween<Offset>(
          begin: const Offset(0.0, 0.018),
          end: Offset.zero,
        ).animate(curved);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: slide,
            child: ScaleTransition(
              scale: scale,
              child: ColoredBox(color: Colors.black, child: child),
            ),
          ),
        );
      },
    );
  }

  // Pure fade helper for special cases.
  static Widget fadeTransitionBuilder(
    Widget child,
    Animation<double> animation,
  ) {
    return FadeTransition(opacity: animation, child: child);
  }

  // Shared cross-fade switcher for in-place content replacement.
  static Widget crossFadeSwitch({
    required String switchKey,
    required Widget child,
    Duration duration = contentSwitchDuration,
    Curve inCurve = Curves.easeOut,
    Curve outCurve = Curves.easeOut,
    Alignment alignment = Alignment.topLeft,
  }) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: inCurve,
      switchOutCurve: outCurve,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          fit: StackFit.passthrough,
          alignment: alignment,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: KeyedSubtree(key: ValueKey<String>(switchKey), child: child),
    );
  }

  static Widget fadeDownSwitch({
    required String switchKey,
    required Widget child,
    Duration duration = contentSwitchDuration,
    Curve inCurve = Curves.easeOut,
    Curve outCurve = Curves.easeOut,
    Alignment alignment = Alignment.topLeft,
    Offset begin = const Offset(0.0, -0.06),
  }) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: inCurve,
      switchOutCurve: outCurve,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          fit: StackFit.passthrough,
          alignment: alignment,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(parent: animation, curve: inCurve);
        final slide = Tween<Offset>(
          begin: begin,
          end: Offset.zero,
        ).animate(curved);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: KeyedSubtree(key: ValueKey<String>(switchKey), child: child),
    );
  }
}

class AppPaneCardPage<T> extends Page<T> {
  final Widget child;
  final bool maintainState;
  final bool disableHero;

  const AppPaneCardPage({
    required this.child,
    required LocalKey key,
    super.name,
    super.arguments,
    super.restorationId,
    this.maintainState = true,
    this.disableHero = true,
  }) : super(key: key);

  @override
  Route<T> createRoute(BuildContext context) {
    return _AppPageBasedPaneCardRoute<T>(page: this);
  }
}

class AppPaneCardRoute<T> extends PageRoute<T> {
  final WidgetBuilder builder;
  @override
  final bool maintainState;
  final bool disableHero;

  AppPaneCardRoute({
    required this.builder,
    super.settings,
    this.maintainState = true,
    this.disableHero = true,
    super.allowSnapshotting = true,
    super.barrierDismissible = false,
  });

  @override
  Duration get transitionDuration => AppTransitions.routeEnter;

  @override
  Duration get reverseTransitionDuration => AppTransitions.routeExit;

  @override
  DelegatedTransitionBuilder? get delegatedTransition => null;

  Widget _buildPageContent(BuildContext context) {
    final child = builder(context);
    if (!disableHero) return child;
    return HeroMode(enabled: false, child: child);
  }

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _buildPageContent(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return AppTransitions.leftToRightPageTurnTransition(
      child,
      animation,
      secondaryAnimation,
      context,
    );
  }

  @override
  String get debugLabel => '${super.debugLabel}(${settings.name})';
}

class _AppPageBasedPaneCardRoute<T> extends PageRoute<T> {
  _AppPageBasedPaneCardRoute({
    required AppPaneCardPage<T> page,
    super.allowSnapshotting = true,
  }) : super(settings: page);

  AppPaneCardPage<T> get _page => settings as AppPaneCardPage<T>;

  @override
  Duration get transitionDuration => AppTransitions.routeEnter;

  @override
  Duration get reverseTransitionDuration => AppTransitions.routeExit;

  @override
  DelegatedTransitionBuilder? get delegatedTransition => null;

  @override
  bool get maintainState => _page.maintainState;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  Widget _buildPageContent(BuildContext context) {
    if (!_page.disableHero) return _page.child;
    return HeroMode(enabled: false, child: _page.child);
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _buildPageContent(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return AppTransitions.leftToRightPageTurnTransition(
      child,
      animation,
      secondaryAnimation,
      context,
    );
  }

  @override
  String get debugLabel => '${super.debugLabel}(${settings.name})';
}

class _AppSplitPaneHostRoute<T> extends PageRoute<T> {
  final WidgetBuilder builder;
  @override
  final bool maintainState;
  final bool disableHero;

  _AppSplitPaneHostRoute({
    required this.builder,
    super.settings,
    this.maintainState = true,
    this.disableHero = true,
    super.allowSnapshotting = true,
    super.barrierDismissible = false,
  });

  @override
  Duration get transitionDuration => AppTransitions.routeEnter;

  @override
  Duration get reverseTransitionDuration => AppTransitions.routeExit;

  @override
  DelegatedTransitionBuilder? get delegatedTransition => null;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  Widget _buildPageContent(BuildContext context) {
    final child = builder(context);
    if (!disableHero) return child;
    return HeroMode(enabled: false, child: child);
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _buildPageContent(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return AppTransitions.leftToRightPageTurnTransition(
      child,
      animation,
      secondaryAnimation,
      context,
    );
  }

  @override
  String get debugLabel => '${super.debugLabel}(${settings.name})';
}
