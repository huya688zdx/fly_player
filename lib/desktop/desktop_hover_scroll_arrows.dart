import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'desktop_hover_region.dart';
import 'desktop_tokens.dart';

/// 横向媒体架的鼠标翻页入口，悬停且内容可滚动时显示。
/// 按钮完整位于列表内侧，点击按约 0.8 视口宽度翻页。
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

  /// 页面水平留白；用于限制按钮的内缩量，最多 6px。
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
    return DesktopHoverRegion(
      builder: (context, hovering) {
        final arrowsVisible = hovering && (_canScrollLeft || _canScrollRight);
        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            NotificationListener<ScrollMetricsNotification>(
              onNotification: (_) {
                // 改变窗口或分屏宽度不会触发 ScrollController 的滚动监听。
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _syncArrowState(),
                );
                return false;
              },
              child: widget.child,
            ),
            Positioned(
              left: math.min(widget.edgePadding, 6),
              top: 0,
              bottom: 0,
              width: 40,
              child: Center(
                child: _ScrollArrow(
                  visible: arrowsVisible,
                  enabled: _canScrollLeft,
                  icon: Icons.chevron_left,
                  onTap: () => _scrollByViewport(forward: false),
                ),
              ),
            ),
            Positioned(
              right: math.min(widget.edgePadding, 6),
              top: 0,
              bottom: 0,
              width: 40,
              child: Center(
                child: _ScrollArrow(
                  visible: arrowsVisible,
                  enabled: _canScrollRight,
                  icon: Icons.chevron_right,
                  onTap: () => _scrollByViewport(forward: true),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 自带控制器的横向滚动行宿主：桌面档（[enabled]）把 builder 产物接上
/// [HoverScrollArrows]（居中圆形按钮）；非桌面档原样透出，零改动。
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

  /// 页面水平留白，传给箭头容器确定内缩量。
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

/// 圆形翻页按钮，隐藏时不拦截卡片点击。
class _ScrollArrow extends StatefulWidget {
  const _ScrollArrow({
    required this.visible,
    required this.enabled,
    required this.icon,
    required this.onTap,
  });

  final bool visible;
  final bool enabled;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_ScrollArrow> createState() => _ScrollArrowState();
}

class _ScrollArrowState extends State<_ScrollArrow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final isLeft = widget.icon == Icons.chevron_left;
    final hovering = widget.enabled && _hovering;
    final foreground = isLight ? colors.surface : colors.textPrimary;
    final neutralScrim = HSLColor.fromColor(
      colors.overlayScrim,
    ).withSaturation(0).toColor();
    return IgnorePointer(
      ignoring: !widget.visible,
      child: AnimatedOpacity(
        opacity: widget.visible ? 1 : 0,
        duration: DesktopTokens.hoverDuration,
        child: MouseRegion(
          cursor: widget.enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: Tooltip(
            message: widget.enabled
                ? (isLeft ? '向左翻页' : '向右翻页')
                : (isLeft ? '已到最左侧' : '已到最右侧'),
            child: Semantics(
              button: true,
              enabled: widget.enabled,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.enabled ? widget.onTap : null,
                child: AnimatedContainer(
                  width: 40,
                  height: 48,
                  duration: DesktopTokens.hoverDuration,
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      neutralScrim,
                      foreground,
                      hovering ? 0.12 : 0,
                    )!.withValues(alpha: isLight ? 0.74 : 0.64),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: foreground.withValues(
                        alpha: hovering ? 0.3 : 0.16,
                      ),
                      width: 0.8,
                    ),
                  ),
                  child: Icon(
                    widget.icon,
                    size: 24,
                    color: foreground.withValues(
                      alpha: widget.enabled ? 0.94 : 0.38,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
