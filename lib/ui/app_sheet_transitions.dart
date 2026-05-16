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
    return _AdaptiveSheetTransition(animation: animation, child: child);
  }

  static Widget buildDirectionalSheetTransition({
    required Widget child,
    required Animation<double> animation,
    required bool isCurrent,
    required bool isForward,
  }) {
    return _DirectionalSheetTransition(
      animation: animation,
      isCurrent: isCurrent,
      isForward: isForward,
      child: child,
    );
  }
}

class _AdaptiveSheetTransition extends StatefulWidget {
  final Animation<double> animation;
  final Widget child;

  const _AdaptiveSheetTransition({
    required this.animation,
    required this.child,
  });

  @override
  State<_AdaptiveSheetTransition> createState() =>
      _AdaptiveSheetTransitionState();
}

class _AdaptiveSheetTransitionState extends State<_AdaptiveSheetTransition> {
  late CurvedAnimation _curved;
  late Animation<Offset> _offset;
  bool _isLandscape = false;

  @override
  void initState() {
    super.initState();
    _curved = CurvedAnimation(
      parent: widget.animation,
      curve: AppMotion.sheetEnterCurve,
      reverseCurve: AppMotion.sheetExitCurve,
    );
    _offset = _buildOffsetTween(_isLandscape).animate(_curved);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    final isLandscape = media.size.width > media.size.height;
    if (isLandscape != _isLandscape) {
      _isLandscape = isLandscape;
      _offset = _buildOffsetTween(_isLandscape).animate(_curved);
    }
  }

  @override
  void didUpdateWidget(covariant _AdaptiveSheetTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      _curved.dispose();
      _curved = CurvedAnimation(
        parent: widget.animation,
        curve: AppMotion.sheetEnterCurve,
        reverseCurve: AppMotion.sheetExitCurve,
      );
      _offset = _buildOffsetTween(_isLandscape).animate(_curved);
    }
  }

  Tween<Offset> _buildOffsetTween(bool isLandscape) {
    final begin = isLandscape
        ? AppMotion.sheetLandscapeOffset
        : AppMotion.sheetPortraitOffset;
    return Tween<Offset>(begin: begin, end: Offset.zero);
  }

  @override
  void dispose() {
    _curved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curved,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}

class _DirectionalSheetTransition extends StatefulWidget {
  final Animation<double> animation;
  final bool isCurrent;
  final bool isForward;
  final Widget child;

  const _DirectionalSheetTransition({
    required this.animation,
    required this.isCurrent,
    required this.isForward,
    required this.child,
  });

  @override
  State<_DirectionalSheetTransition> createState() =>
      _DirectionalSheetTransitionState();
}

class _DirectionalSheetTransitionState
    extends State<_DirectionalSheetTransition> {
  CurvedAnimation? _curved;
  Animation<Offset>? _offset;

  @override
  void initState() {
    super.initState();
    if (widget.isCurrent) {
      _buildAnimations();
    }
  }

  @override
  void didUpdateWidget(covariant _DirectionalSheetTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    final animationChanged = oldWidget.animation != widget.animation;
    final directionChanged = oldWidget.isForward != widget.isForward;
    final currentChanged = oldWidget.isCurrent != widget.isCurrent;

    if (!widget.isCurrent) {
      if (_curved != null) {
        _curved!.dispose();
        _curved = null;
        _offset = null;
      }
      return;
    }

    if (_curved == null || animationChanged) {
      _curved?.dispose();
      _buildAnimations();
    } else if (directionChanged || currentChanged) {
      _offset = _buildOffsetTween().animate(_curved!);
    }
  }

  void _buildAnimations() {
    _curved = CurvedAnimation(
      parent: widget.animation,
      curve: AppMotion.sheetEnterCurve,
      reverseCurve: AppMotion.sheetExitCurve,
    );
    _offset = _buildOffsetTween().animate(_curved!);
  }

  Tween<Offset> _buildOffsetTween() {
    final begin = widget.isForward
        ? AppMotion.sheetForwardOffset
        : AppMotion.sheetBackwardOffset;
    return Tween<Offset>(begin: begin, end: Offset.zero);
  }

  @override
  void dispose() {
    _curved?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isCurrent) {
      return FadeTransition(
        opacity: ReverseAnimation(widget.animation),
        child: widget.child,
      );
    }
    return FadeTransition(
      opacity: _curved!,
      child: SlideTransition(position: _offset!, child: widget.child),
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
