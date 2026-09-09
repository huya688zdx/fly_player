import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Windows 桌面统一滚动行为：纵向列表使用细窄、可拖拽的自绘滚动条；
/// 横向 shelf 不渲染滚动条，移动端沿用 Flutter 默认行为。
/// 尊重 [ScrollBehavior.scrollbars] 开关：悬浮卡/弹窗内关闭滚动条时不再强制绘制。
class DesktopScrollBehavior extends MaterialScrollBehavior {
  const DesktopScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final desktop =
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
    if (!desktop ||
        details.direction == AxisDirection.left ||
        details.direction == AxisDirection.right) {
      return child;
    }
    return DesktopScrollbar(controller: details.controller, child: child);
  }
}

class DesktopScrollbar extends StatefulWidget {
  const DesktopScrollbar({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollController? controller;
  final Widget child;

  @override
  State<DesktopScrollbar> createState() => _DesktopScrollbarState();
}

class _DesktopScrollbarState extends State<DesktopScrollbar> {
  ScrollController? _listenedController;
  bool _hovered = false;
  bool _dragging = false;
  double _dragStartY = 0;
  double _dragStartPixels = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncController();
  }

  @override
  void didUpdateWidget(covariant DesktopScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  void _syncController() {
    final next = widget.controller ?? PrimaryScrollController.maybeOf(context);
    if (identical(next, _listenedController)) return;
    _listenedController?.removeListener(_refresh);
    _listenedController = next;
    _listenedController?.addListener(_refresh);
  }

  @override
  void dispose() {
    _listenedController?.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final controller = _listenedController;
        final position = controller?.positions.length == 1
            ? controller!.positions.single
            : null;
        final trackHeight = constraints.maxHeight;
        if (position != null &&
            (!position.hasContentDimensions || !position.hasPixels)) {
          return widget.child;
        }
        final maxScroll = position?.maxScrollExtent ?? 0;
        final viewport = position?.viewportDimension ?? trackHeight;
        if (!trackHeight.isFinite ||
            trackHeight <= 0 ||
            !maxScroll.isFinite ||
            !viewport.isFinite ||
            maxScroll <= 0) {
          return widget.child;
        }
        final thumbHeight = (trackHeight * viewport / (viewport + maxScroll))
            .clamp(34.0, trackHeight);
        final travel = (trackHeight - thumbHeight).clamp(0.0, trackHeight);
        if (!travel.isFinite || travel <= 0 || !maxScroll.isFinite) {
          return widget.child;
        }
        final thumbTop =
            (position!.pixels.clamp(0.0, maxScroll) / maxScroll) * travel;
        final active = _hovered || _dragging;
        return Stack(
          children: <Widget>[
            Positioned.fill(child: widget.child),
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: 6,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    final target = details.localPosition.dy - thumbHeight / 2;
                    controller!.animateTo(
                      (target / travel).clamp(0.0, 1.0) * maxScroll,
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                    );
                  },
                  onVerticalDragStart: (details) {
                    setState(() => _dragging = true);
                    _dragStartY = details.localPosition.dy;
                    _dragStartPixels = position.pixels;
                  },
                  onVerticalDragUpdate: (details) {
                    final delta = details.localPosition.dy - _dragStartY;
                    if (travel > 0) {
                      controller!.jumpTo(
                        (_dragStartPixels + delta * maxScroll / travel).clamp(
                          0.0,
                          maxScroll,
                        ),
                      );
                    }
                  },
                  onVerticalDragEnd: (_) => setState(() => _dragging = false),
                  onVerticalDragCancel: () => setState(() => _dragging = false),
                  child: Stack(
                    children: <Widget>[
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 120),
                        curve: Curves.easeOut,
                        top: thumbTop,
                        left: active ? 1.5 : 2,
                        right: active ? 1.5 : 2,
                        height: thumbHeight,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          decoration: BoxDecoration(
                            color: active
                                ? const Color(0xC78AB9FF)
                                : const Color(0x6B8AB9FF),
                            borderRadius: BorderRadius.circular(99),
                            boxShadow: active
                                ? const <BoxShadow>[
                                    BoxShadow(
                                      color: Color(0x596EA8FF),
                                      blurRadius: 8,
                                    ),
                                  ]
                                : const <BoxShadow>[],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
