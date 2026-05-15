import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_motion.dart';

class AppSheetTransitions {
  const AppSheetTransitions._();

  static final ValueNotifier<int> _activeSheetCount = ValueNotifier<int>(0);

  static ValueListenable<int> get activeSheetCount => _activeSheetCount;

  static Future<T?> showAdaptiveSheet<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    bool barrierDismissible = true,
    String barrierLabel = '',
    Color barrierColor = Colors.transparent,
    bool useRootNavigator = false,
  }) {
    var closed = false;
    final effectiveBarrierLabel = barrierLabel.trim().isNotEmpty
        ? barrierLabel
        : MaterialLocalizations.of(context).modalBarrierDismissLabel;
    _activeSheetCount.value = _activeSheetCount.value + 1;
    var released = false;
    void releaseSheetSlot() {
      if (released) return;
      released = true;
      final next = _activeSheetCount.value - 1;
      _activeSheetCount.value = next < 0 ? 0 : next;
    }

    return showGeneralDialog<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      barrierDismissible: barrierDismissible,
      barrierLabel: effectiveBarrierLabel,
      barrierColor: barrierColor,
      transitionDuration: AppMotion.sheetTransition,
      pageBuilder: (dialogContext, _, __) {
        void closeWithResult(Object? result) {
          if (closed) return;
          closed = true;
          Navigator.of(dialogContext).pop(result as T?);
        }

        return _AdaptiveSheetScope(
          closeWithResult: closeWithResult,
          child: RepaintBoundary(child: Builder(builder: builder)),
        );
      },
      transitionBuilder: (context, animation, _, child) {
        return buildAdaptiveSheetTransition(context, animation, child);
      },
    ).whenComplete(() {
      closed = true;
      releaseSheetSlot();
    });
  }

  static void close<T>(BuildContext context, [T? result]) {
    maybeClose<T>(context, result);
  }

  static bool maybeClose<T>(BuildContext context, [T? result]) {
    final scope =
        context
                .getElementForInheritedWidgetOfExactType<_AdaptiveSheetScope>()
                ?.widget
            as _AdaptiveSheetScope?;
    if (scope == null) return false;
    scope.closeWithResult(result);
    return true;
  }

  static Future<T?> showBottomSurface<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    bool barrierDismissible = true,
    String barrierLabel = '',
    Color barrierColor = Colors.transparent,
    bool useRootNavigator = false,
  }) {
    return showAdaptiveSheet<T>(
      context,
      barrierDismissible: barrierDismissible,
      barrierLabel: barrierLabel,
      barrierColor: barrierColor,
      useRootNavigator: useRootNavigator,
      builder: (dialogContext) {
        return Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              if (barrierDismissible)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => close(dialogContext),
                    child: const SizedBox.expand(),
                  ),
                ),
              Align(
                alignment: Alignment.bottomCenter,
                child: builder(dialogContext),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget buildAdaptiveSheetTransition(
    BuildContext context,
    Animation<double> animation,
    Widget child,
  ) {
    final media = MediaQuery.of(context);
    final isLandscape = media.size.width > media.size.height;
    final curved = CurvedAnimation(
      parent: animation,
      curve: AppMotion.sheetEnterCurve,
      reverseCurve: AppMotion.sheetExitCurve,
    );
    final begin = isLandscape
        ? AppMotion.sheetLandscapeOffset
        : AppMotion.sheetPortraitOffset;
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: begin, end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  }

  static Widget buildDirectionalSheetTransition({
    required Widget child,
    required Animation<double> animation,
    required bool isCurrent,
    required bool isForward,
  }) {
    if (!isCurrent) {
      return FadeTransition(opacity: ReverseAnimation(animation), child: child);
    }

    final curved = CurvedAnimation(
      parent: animation,
      curve: AppMotion.sheetEnterCurve,
      reverseCurve: AppMotion.sheetExitCurve,
    );
    final begin = isForward
        ? AppMotion.sheetForwardOffset
        : AppMotion.sheetBackwardOffset;
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: begin, end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  }
}

class _AdaptiveSheetScope extends InheritedWidget {
  final void Function(Object? result) closeWithResult;

  const _AdaptiveSheetScope({
    required this.closeWithResult,
    required super.child,
  });

  @override
  bool updateShouldNotify(_AdaptiveSheetScope oldWidget) => false;
}
