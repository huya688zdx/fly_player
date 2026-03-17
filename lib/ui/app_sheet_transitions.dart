import 'package:flutter/material.dart';

import 'app_motion.dart';

class AppSheetTransitions {
  const AppSheetTransitions._();

  static Future<T?> showAdaptiveSheet<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    bool barrierDismissible = true,
    String barrierLabel = '',
    Color barrierColor = Colors.transparent,
    bool useRootNavigator = false,
  }) {
    final effectiveBarrierLabel = barrierLabel.trim().isNotEmpty
        ? barrierLabel
        : MaterialLocalizations.of(context).modalBarrierDismissLabel;

    return showGeneralDialog<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      barrierDismissible: barrierDismissible,
      barrierLabel: effectiveBarrierLabel,
      barrierColor: barrierColor,
      transitionDuration: AppMotion.sheetTransition,
      pageBuilder: (dialogContext, _, __) => builder(dialogContext),
      transitionBuilder: (dialogContext, animation, _, child) {
        return buildAdaptiveSheetTransition(dialogContext, animation, child);
      },
    );
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
                    onTap: () => Navigator.of(dialogContext).maybePop(),
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
