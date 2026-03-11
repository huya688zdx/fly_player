import 'package:flutter/material.dart';

class AppTransitions {
  const AppTransitions._();

  // Generic route animation timing.
  static const Duration routeEnter = Duration(milliseconds: 280);
  static const Duration routeExit = Duration(milliseconds: 280);
  static const Duration switchDuration = Duration(milliseconds: 280);
  static const Duration contentSwitchDuration = Duration(milliseconds: 320);
  static const Duration topBarFadeDuration = Duration(milliseconds: 320);

  // Shared easing curves.
  static const Curve easeOut = Curves.linear;
  static const Curve easeIn = Curves.linear;
  static const Curve progressIn = Curves.linear;
  static const Curve progressOut = Curves.linear;

  // Progress widget animation timing.
  static const Duration progressSizeDuration = Duration(milliseconds: 340);
  static const Duration progressFadeDuration = Duration(milliseconds: 300);

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
  static Route<T> fadeSlideRoute<T>(Widget page) {
    return leftToRightPageTurnRoute(page);
  }

  // Page-turn-like transition entering from right, with a temporary dark mask.
  static Widget leftToRightPageTurnTransition(
    Widget child,
    Animation<double> animation,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: easeOut);
    final slide = Tween<Offset>(
      begin: const Offset(1.0, 0),
      end: Offset.zero,
    ).animate(curved);
    return SlideTransition(
      position: slide,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 10,
              offset: Offset(-2, 0),
            ),
          ],
        ),
        child: child,
      ),
    );
  }

  // Dedicated route for item-to-detail navigation.
  static Route<T> leftToRightPageTurnRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      transitionDuration: routeEnter,
      reverseTransitionDuration: routeExit,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          leftToRightPageTurnTransition(child, animation),
    );
  }

  // Dedicated route for immersive player pages. Avoid lateral page-turn so the
  // previous detail page does not leak from the edge during entry.
  static Route<T> playerRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
        return FadeTransition(
          opacity: curved,
          child: ColoredBox(color: Colors.black, child: child),
        );
      },
    );
  }

  // Unified bottom-sheet entrance used by selector/intro/media-detail drawers.
  static Future<T?> showDrawerSheet<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    bool isScrollControlled = true,
    bool useRootNavigator = false,
    bool enableDrag = true,
    bool isDismissible = true,
    Color backgroundColor = Colors.transparent,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      builder: builder,
      isScrollControlled: isScrollControlled,
      useRootNavigator: useRootNavigator,
      enableDrag: enableDrag,
      isDismissible: isDismissible,
      backgroundColor: backgroundColor,
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
