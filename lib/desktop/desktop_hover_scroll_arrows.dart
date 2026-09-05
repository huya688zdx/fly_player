import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'desktop_hover_region.dart';
import 'desktop_tokens.dart';

/// 桌面档横向滚动架的悬浮箭头容器：悬停整架时，左右两端各出现一个
/// **垂直居中的悬浮胶囊按钮**（深色主题下背后衬一条贴边的窄渐变），
/// 内容溢出且可向该方向滚动时才可见，点击按约 0.8 视口宽度翻页。
///
/// 按钮的命中区经 [edgePadding] 向行外延伸过页面水平留白、贴住窗口边，
/// 视觉胶囊则收在命中区内、不挡整行海报；命中区从行边缘开始。
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
    // 整架悬停检测走自愈校验容器：内容移动（分屏挤压、转场）下不会卡在
    // 「箭头常显」；校验边界按按钮外伸量外扩——鼠标挪到伸出至页面留白的
    // 按钮上时悬停维持，按钮不再「闪一下就被清」。
    return DesktopHoverRegion(
      hoverBoundsInsets: EdgeInsets.symmetric(horizontal: widget.edgePadding),
      builder: (context, hovering) {
        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            widget.child,
            Positioned(
              left: -widget.edgePadding,
              top: 0,
              bottom: 0,
              width: _stripWidth + widget.edgePadding,
              child: _ScrollArrow(
                visible: hovering && _canScrollLeft,
                icon: Icons.chevron_left,
                alignLeft: true,
                stripWidth: _stripWidth + widget.edgePadding,
                onTap: () => _scrollByViewport(forward: false),
              ),
            ),
            Positioned(
              right: -widget.edgePadding,
              top: 0,
              bottom: 0,
              width: _stripWidth + widget.edgePadding,
              child: _ScrollArrow(
                visible: hovering && _canScrollRight,
                icon: Icons.chevron_right,
                alignLeft: false,
                stripWidth: _stripWidth + widget.edgePadding,
                onTap: () => _scrollByViewport(forward: true),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 按钮命中区基础宽度（不含向外延伸的留白）：整行高、足够避免误触。
const double _stripWidth = 48;

/// 自带控制器的横向滚动行宿主：桌面档（[enabled]）把 builder 产物接上
/// [HoverScrollArrows]（居中悬浮胶囊按钮）；非桌面档原样透出，零改动。
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

/// 边缘滚动按钮：整行高、贴窗口边的透明命中区 + 垂直居中的悬浮胶囊。
/// 深色主题下胶囊用主题 scrim 半透明填充，背后衬一条贴边的窄渐变，
/// 提高亮色海报上的可读性；浅色主题用磨砂白胶囊、不衬渐变。
/// 不可见时淡出并忽略指针。
class _ScrollArrow extends StatefulWidget {
  const _ScrollArrow({
    required this.visible,
    required this.icon,
    required this.alignLeft,
    required this.stripWidth,
    required this.onTap,
  });

  final bool visible;
  final IconData icon;

  /// true 贴左缘，false 贴右缘。
  final bool alignLeft;

  /// 命中区总宽度（含向外延伸的页面留白），用于收进量自适应。
  final double stripWidth;
  final VoidCallback onTap;

  @override
  State<_ScrollArrow> createState() => _ScrollArrowState();
}

/// 悬浮胶囊的视觉尺寸：40×64 全圆角，向命中区的窗口侧边缘收进 12px。
const double _pillWidth = 40;
const double _pillHeight = 64;
const double _pillInset = 12;

class _ScrollArrowState extends State<_ScrollArrow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final pillColor = isLight
        ? Colors.white.withValues(alpha: _hovering ? 0.95 : 0.85)
        : colors.overlayScrim.withValues(alpha: _hovering ? 0.95 : 0.78);
    // 命中区比胶囊宽（延伸过页面留白）；留白不足时（设置页 edgePadding=0，
    // 命中区仅 _stripWidth 宽）收进量压到最小 4，避免胶囊溢出命中区。
    final double inset = math.min(
      _pillInset,
      math.max(4.0, (widget.stripWidth - _pillWidth) / 2),
    );
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double pillHeight = math.min(
                _pillHeight,
                constraints.maxHeight,
              );
              return Stack(
                children: <Widget>[
                  if (!isLight)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: widget.alignLeft
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            end: widget.alignLeft
                                ? Alignment.centerLeft
                                : Alignment.centerRight,
                            colors: <Color>[
                              Colors.transparent,
                              colors.overlayScrim.withValues(alpha: 0.30),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Align(
                    alignment: widget.alignLeft
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: AnimatedScale(
                      scale: widget.visible ? 1 : 0.88,
                      duration: DesktopTokens.hoverDuration,
                      curve: Curves.easeOutCubic,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: inset),
                        child: AnimatedContainer(
                          width: _pillWidth,
                          height: pillHeight,
                          duration: DesktopTokens.hoverDuration,
                          curve: Curves.easeOutCubic,
                          decoration: BoxDecoration(
                            color: pillColor,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: isLight
                                  ? Colors.black.withValues(alpha: 0.08)
                                  : colors.borderSubtle,
                            ),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: isLight ? 0.12 : 0.25,
                                ),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              widget.icon,
                              size: 22,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
