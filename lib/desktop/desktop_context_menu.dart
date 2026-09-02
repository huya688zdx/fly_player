import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'desktop_floating_panel.dart';

/// 桌面右键菜单项（移动端长按动作表的桌面形态；动作集合复用
/// media_item_action_sheet_controller，本模块只负责展示与触发）。
class DesktopContextMenuEntry {
  final String label;
  final IconData icon;
  final bool destructive;
  final VoidCallback? onSelected;

  const DesktopContextMenuEntry({
    required this.label,
    required this.icon,
    this.destructive = false,
    this.onSelected,
  });
}

/// 当前打开的菜单会话；全局同一时刻只保留一个，重入时先收起旧菜单。
_DesktopContextMenuSession? _activeSession;

/// 在全局坐标 [position] 弹出桌面右键菜单（PC 形态）：
///
/// - 菜单左上角贴住指针，贴近窗口边缘时整块收进窗口内；
/// - 非模态：点击菜单外部、任意滚轮、Esc 都会关闭，页面滚动不会被输入屏障锁死；
/// - 外观复用 [DesktopFloatingPanel]（玻璃小窗），文字/危险色跟随主题 token。
///
/// 返回的 Future 在菜单关闭时完成；选中动作会先关菜单再回调 onSelected。
Future<void> showDesktopContextMenu(
  BuildContext context, {
  required Offset position,
  required List<DesktopContextMenuEntry> entries,
}) {
  if (entries.isEmpty) return Future<void>.value();
  _activeSession?.dismiss();
  final session = _DesktopContextMenuSession(
    anchor: position,
    entries: List<DesktopContextMenuEntry>.unmodifiable(entries),
  );
  _activeSession = session;
  session._attach(Overlay.of(context, rootOverlay: true));
  return session._done.future;
}

class _DesktopContextMenuSession {
  _DesktopContextMenuSession({required this.anchor, required this.entries});

  final Offset anchor;
  final List<DesktopContextMenuEntry> entries;

  final Completer<void> _done = Completer<void>();
  final GlobalKey _panelKey = GlobalKey();
  OverlayEntry? _entry;

  void _attach(OverlayState overlay) {
    _entry = OverlayEntry(
      builder: (_) => _DesktopContextMenuSurface(session: this),
    );
    overlay.insert(_entry!);
  }

  void dismiss() {
    final entry = _entry;
    if (entry == null) return;
    _entry = null;
    if (identical(_activeSession, this)) _activeSession = null;
    entry.remove();
    if (!_done.isCompleted) _done.complete();
  }

  void _select(int index) {
    dismiss();
    entries[index].onSelected?.call();
  }
}

/// 菜单的贴屏外壳：负责“点外部 / 滚轮 / Esc 关闭”三条交互，不经过路由，
/// 因此不会像 showMenu 的模态 barrier 一样把整页输入锁住。
class _DesktopContextMenuSurface extends StatefulWidget {
  const _DesktopContextMenuSurface({required this.session});

  final _DesktopContextMenuSession session;

  @override
  State<_DesktopContextMenuSurface> createState() =>
      _DesktopContextMenuSurfaceState();
}

class _DesktopContextMenuSurfaceState extends State<_DesktopContextMenuSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 130),
  )..forward();
  late final Animation<double> _entranceCurve = CurvedAnimation(
    parent: _entrance,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _entrance.dispose();
    super.dispose();
  }

  bool _handleKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      widget.session.dismiss();
      return true;
    }
    return false;
  }

  bool _isInsidePanel(Offset globalPosition) {
    final box = widget.session._panelKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    return box.size.contains(box.globalToLocal(globalPosition));
  }

  /// 菜单外任意按下即关闭；菜单内按下交给条目自身的 InkWell 处理。
  void _handlePointerDown(PointerDownEvent event) {
    if (_isInsidePanel(event.position)) return;
    widget.session.dismiss();
  }

  /// 滚轮只负责收起菜单（菜单内滚轮留给超高菜单自身滚动），页面输入随即恢复。
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (_isInsidePanel(event.position)) return;
    widget.session.dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return Positioned.fill(
      child: Listener(
        onPointerDown: _handlePointerDown,
        onPointerSignal: _handlePointerSignal,
        child: GestureDetector(
          // 吞掉菜单外的点击/右键（仅用于关闭），不向页面透传误触。
          behavior: HitTestBehavior.opaque,
          child: FadeTransition(
            opacity: _entranceCurve,
            child: CustomSingleChildLayout(
              delegate: _ContextMenuLayoutDelegate(anchor: session.anchor),
              child: ScaleTransition(
                alignment: Alignment.topLeft,
                scale: Tween<double>(
                  begin: 0.96,
                  end: 1,
                ).animate(_entranceCurve),
                child: _DesktopContextMenuPanel(
                  key: session._panelKey,
                  entries: session.entries,
                  onSelected: session._select,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 指针锚点定位：菜单左上角贴住指针，溢出窗口边缘时平移收进留白内。
class _ContextMenuLayoutDelegate extends SingleChildLayoutDelegate {
  const _ContextMenuLayoutDelegate({required this.anchor});

  /// 菜单与窗口边缘的最小留白。
  static const double margin = 8;

  final Offset anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      maxWidth: math.max(0, constraints.maxWidth - margin * 2),
      maxHeight: math.max(0, constraints.maxHeight - margin * 2),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxX = math.max(margin, size.width - margin - childSize.width);
    final maxY = math.max(margin, size.height - margin - childSize.height);
    return Offset(
      anchor.dx.clamp(margin, maxX).toDouble(),
      anchor.dy.clamp(margin, maxY).toDouble(),
    );
  }

  @override
  bool shouldRelayout(covariant _ContextMenuLayoutDelegate oldDelegate) {
    return oldDelegate.anchor != anchor;
  }
}

class _DesktopContextMenuPanel extends StatelessWidget {
  const _DesktopContextMenuPanel({
    super.key,
    required this.entries,
    required this.onSelected,
  });

  final List<DesktopContextMenuEntry> entries;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return DesktopFloatingPanel(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 196, maxWidth: 292),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (var i = 0; i < entries.length; i++)
                _ContextMenuOption(
                  entry: entries[i],
                  onTap: () => onSelected(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContextMenuOption extends StatelessWidget {
  const _ContextMenuOption({required this.entry, required this.onTap});

  final DesktopContextMenuEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // 面板是固定深色玻璃（见 DesktopFloatingPanel），悬停态统一用白色低透明。
    final foreground = entry.destructive ? colors.danger : colors.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      hoverColor: Colors.white.withValues(alpha: 0.07),
      highlightColor: Colors.white.withValues(alpha: 0.10),
      splashFactory: NoSplash.splashFactory,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        child: Row(
          // min：菜单宽度跟随最宽条目收缩（196~292 之间），不强行撑满。
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              entry.icon,
              size: 17,
              color: foreground.withValues(alpha: 0.9),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                entry.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, height: 1.2, color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
