import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'desktop_tokens.dart';

/// 桌面档横向滚动架的悬浮箭头容器：左右两端各覆盖一条**整行高**的
/// 透明黑渐变按钮，悬停整架时出现（内容溢出且可向该方向滚动时才可见），
/// 点击按约 0.8 视口宽度翻页。
///
/// 按钮经 [edgePadding] 向行外延伸过页面水平留白、贴住内容区边缘
/// （渐变从窗口边起），避免按钮悬浮在海报中间；命中区从行边缘开始。
/// [child] 须把 [scrollController] 挂到实际滚动的视图上。
class HoverScrollArrows extends StatefulWidget {
  const HoverScrollArrows({
    super.key,
    required this.scrollController,
    required this.child,
    this.edgePadding = 0,
  });

  final ScrollController scrollController;
  final Widget child;

  /// 行两侧被页面水平内边距占掉的宽度；按钮向该方向延伸贴边。
  final double edgePadding;

  @override
  State<HoverScrollArrows> createState() => _HoverScrollArrowsState();
}

class _HoverScrollArrowsState extends State<HoverScrollArrows> {
  bool _hovering = false;
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_syncArrowState);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncArrowState();
    });
  }

  @override
  void didUpdateWidget(covariant HoverScrollArrows oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_syncArrowState);
      widget.scrollController.addListener(_syncArrowState);
      _syncArrowState();
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_syncArrowState);
    super.dispose();
  }

  void _syncArrowState() {
    if (!mounted) return;
    var canScrollLeft = false;
    var canScrollRight = false;
    if (widget.scrollController.hasClients) {
      final position = widget.scrollController.position;
      if (position.hasContentDimensions && position.maxScrollExtent.isFinite) {
        canScrollLeft = position.pixels > 0;
        canScrollRight = position.pixels < position.maxScrollExtent - 0.5;
      }
    }
    if (canScrollLeft == _canScrollLeft && canScrollRight == _canScrollRight) {
      return;
    }
    setState(() {
      _canScrollLeft = canScrollLeft;
      _canScrollRight = canScrollRight;
    });
  }

  /// 点击箭头时按约 0.8 视口宽度翻页滚动。
  void _scrollByViewport({required bool forward}) {
    if (!widget.scrollController.hasClients) return;
    final position = widget.scrollController.position;
    if (!position.maxScrollExtent.isFinite) return;
    final delta = position.viewportDimension * 0.8;
    final target = forward ? position.pixels + delta : position.pixels - delta;
    widget.scrollController.animateTo(
      target.clamp(0.0, position.maxScrollExtent),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      // 负向定位的按钮要画出 Stack 之外（盖住页面留白贴到窗口边），关裁剪。
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          widget.child,
          Positioned(
            left: -widget.edgePadding,
            top: 0,
            bottom: 0,
            width: _stripWidth + widget.edgePadding,
            child: _ScrollArrow(
              visible: _hovering && _canScrollLeft,
              icon: Icons.chevron_left,
              alignLeft: true,
              onTap: () => _scrollByViewport(forward: false),
            ),
          ),
          Positioned(
            right: -widget.edgePadding,
            top: 0,
            bottom: 0,
            width: _stripWidth + widget.edgePadding,
            child: _ScrollArrow(
              visible: _hovering && _canScrollRight,
              icon: Icons.chevron_right,
              alignLeft: false,
              onTap: () => _scrollByViewport(forward: true),
            ),
          ),
        ],
      ),
    );
  }

  /// 按钮基础宽度（不含向外延伸的留白）：整行高命中区，足够避免误触。
  static const double _stripWidth = 48;
}

/// 自带控制器的横向滚动行宿主：桌面档（[enabled]）把 builder 产物接上
/// [HoverScrollArrows]（整行高渐变按钮）；非桌面档原样透出，零改动。
/// 控制器由宿主持有与销毁，调用方只需把 controller 挂到滚动视图上。
class HoverScrollRow extends StatefulWidget {
  const HoverScrollRow({
    super.key,
    required this.enabled,
    required this.builder,
    this.edgePadding = 0,
  });

  final bool enabled;
  final Widget Function(ScrollController controller) builder;

  /// 行两侧被页面/卡片水平内边距占掉的宽度；按钮向外延伸贴边。
  final double edgePadding;

  @override
  State<HoverScrollRow> createState() => _HoverScrollRowState();
}

class _HoverScrollRowState extends State<HoverScrollRow> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.builder(_controller);
    if (!widget.enabled) return child;
    return HoverScrollArrows(
      scrollController: _controller,
      edgePadding: widget.edgePadding,
      child: child,
    );
  }
}

/// 边缘滚动按钮：透明黑渐变条带 + 居中箭头；不可见时淡出并忽略指针。
class _ScrollArrow extends StatefulWidget {
  const _ScrollArrow({
    required this.visible,
    required this.icon,
    required this.alignLeft,
    required this.onTap,
  });

  final bool visible;
  final IconData icon;

  /// true 贴左缘，false 贴右缘。
  final bool alignLeft;
  final VoidCallback onTap;

  @override
  State<_ScrollArrow> createState() => _ScrollArrowState();
}

class _ScrollArrowState extends State<_ScrollArrow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedOpacity(
          opacity: widget.visible ? 1 : 0,
          duration: DesktopTokens.hoverDuration,
          child: AnimatedContainer(
            duration: DesktopTokens.hoverDuration,
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: widget.alignLeft
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                end: widget.alignLeft
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                colors: <Color>[
                  Colors.black.withValues(alpha: _hovering ? .58 : .34),
                  Colors.transparent,
                ],
              ),
            ),
            child: Center(
              child: Icon(widget.icon, size: 26, color: colors.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
