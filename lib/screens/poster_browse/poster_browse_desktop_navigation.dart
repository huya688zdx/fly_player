import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../desktop/desktop_environment.dart';
import '../../desktop/desktop_horizontal_wheel.dart';

/// 宽、窄窗口共用整页滚轮和方向键入口。
class PosterBrowseDesktopNavigation extends StatefulWidget {
  const PosterBrowseDesktopNavigation({
    super.key,
    required this.selectedRow,
    required this.rowCount,
    required this.focusedIndex,
    required this.itemCount,
    required this.onSelectRow,
    required this.onSelectItem,
    required this.onBack,
    required this.child,
    this.wrapItems = false,
  });

  final int selectedRow;
  final int rowCount;
  final int focusedIndex;
  final int itemCount;
  final ValueChanged<int> onSelectRow;
  final ValueChanged<int> onSelectItem;
  final VoidCallback onBack;
  final Widget child;
  final bool wrapItems;

  @override
  State<PosterBrowseDesktopNavigation> createState() =>
      _PosterBrowseDesktopNavigationState();
}

class _PosterBrowseDesktopNavigationState
    extends State<PosterBrowseDesktopNavigation> {
  final _focusNode = FocusNode();
  int? _targetIndex;
  int? _targetRow;

  @override
  void didUpdateWidget(covariant PosterBrowseDesktopNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedRow != oldWidget.selectedRow ||
        widget.itemCount != oldWidget.itemCount ||
        widget.focusedIndex != oldWidget.focusedIndex) {
      _targetIndex = null;
      _targetRow = null;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _stepItem(int direction) {
    if (widget.itemCount < 2) return;
    final current = _targetIndex ?? widget.focusedIndex;
    final next = current + direction;
    final target = widget.wrapItems
        ? next % widget.itemCount
        : next.clamp(0, widget.itemCount - 1);
    if (target == current) return;
    _targetIndex = target;
    widget.onSelectItem(target);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      _stepItem(key == LogicalKeyboardKey.arrowRight ? 1 : -1);
    } else if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      if (widget.rowCount == 0) return KeyEventResult.handled;
      final current = _targetRow ?? widget.selectedRow;
      final target = (current + (key == LogicalKeyboardKey.arrowDown ? 1 : -1))
          .clamp(0, widget.rowCount - 1);
      if (target != current) {
        _targetRow = target;
        _targetIndex = null;
        widget.onSelectRow(target);
      }
    } else if (key == LogicalKeyboardKey.escape) {
      widget.onBack();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    if (!DesktopEnvironment.isDesktopPlatform) return widget.child;
    return Focus(
      autofocus: true,
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) {
          if (!_focusNode.hasFocus) _focusNode.requestFocus();
        },
        onPointerSignal: (event) => handleDesktopHorizontalWheel(
          event,
          (delta) => _stepItem(delta.sign.toInt()),
        ),
        child: widget.child,
      ),
    );
  }
}
