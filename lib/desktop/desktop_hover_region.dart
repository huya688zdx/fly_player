import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'desktop_tokens.dart';

/// 全局指针位置 + 悬停自愈注册表。
///
/// 由 [DesktopPointerPositionTracker] 在指针移动/按下/滚轮时写入位置并广播；
/// [DesktopHoverRegion] 注册自身，任何指针事件与每一个产生帧的时机
/// （动画、布局变化）都会重校验所有悬停中的行。
///
/// 为什么需要它：指针静止而内容在指针下方移动（子页滑入挤压网格、路由
/// 转场、滚动、数据加载挤位）时，MouseRegion 的 exit 事件不会派发，行会
/// 卡在高亮；且空闲应用不产帧，任何「逐帧自续」校验也会饿死。因此校验
/// 必须挂在三类触发源上：指针事件、滚轮信号、持久帧回调。
class DesktopPointerPosition {
  DesktopPointerPosition._();

  static Offset? _position;
  static final List<VoidCallback> _listeners = <VoidCallback>[];
  static bool _frameHookInstalled = false;

  /// 最近一次已知的全局指针位置；未知时为 null（信任 MouseRegion 事件）。
  static Offset? get instance => _position;

  static void _update(Offset position) {
    _position = position;
    _validateAllHovering();
  }

  static void _ensureFrameHook() {
    if (_frameHookInstalled) return;
    _frameHookInstalled = true;
    // 每个产生帧的时机（动画 / 布局变化）都重校验一次；空闲不产帧也无需校验。
    SchedulerBinding.instance.addPersistentFrameCallback((elapsed) {
      _validateAllHovering();
    });
  }

  static void _validateAllHovering() {
    // 拷贝遍历：校验中的 setState 不会增删监听者，dispose 在树变化时才发生。
    for (final callback in List<VoidCallback>.of(_listeners)) {
      callback();
    }
  }

  static void _register(VoidCallback validate) {
    _listeners.add(validate);
    _ensureFrameHook();
  }

  static void _unregister(VoidCallback validate) {
    _listeners.remove(validate);
  }
}

/// 指针位置采集器：挂在窗口根部，透传所有指针事件（translucent 不参与命中）。
class DesktopPointerPositionTracker extends StatelessWidget {
  const DesktopPointerPositionTracker({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerHover: (event) =>
          DesktopPointerPosition._update(event.position),
      onPointerMove: (event) =>
          DesktopPointerPosition._update(event.position),
      onPointerDown: (event) =>
          DesktopPointerPosition._update(event.position),
      onPointerSignal: (event) {
        // 滚轮滚动不移动指针，但内容会在静止指针下方位移——同样触发重校验。
        if (event is PointerScrollEvent) {
          DesktopPointerPosition._update(event.position);
        }
      },
      child: child,
    );
  }
}

/// 带自愈校验的悬停容器：MouseRegion enter/exit + 指针事件 / 滚轮 / 帧回调
/// 三路重校验，指针不在本组件范围内立即熄灭（修「多行同时卡在高亮」）。
///
/// [onTap]/[onSecondaryTapUp] 任一非空时挂 opaque GestureDetector 承接点击；
/// 都为空则只做悬停视觉（内层控件自行处理点击，如海报卡的 InkWell）。
class DesktopHoverRegion extends StatefulWidget {
  const DesktopHoverRegion({
    super.key,
    required this.builder,
    this.onTap,
    this.onSecondaryTapUp,
    this.cursor = SystemMouseCursors.click,
  });

  final Widget Function(BuildContext context, bool hovering) builder;
  final VoidCallback? onTap;
  final void Function(Offset globalPosition)? onSecondaryTapUp;
  final MouseCursor cursor;

  @override
  State<DesktopHoverRegion> createState() => _DesktopHoverRegionState();
}

class _DesktopHoverRegionState extends State<DesktopHoverRegion> {
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    DesktopPointerPosition._register(_validateHover);
  }

  @override
  void dispose() {
    DesktopPointerPosition._unregister(_validateHover);
    super.dispose();
  }

  void _setHovering(bool value) {
    if (_hovering == value) return;
    setState(() => _hovering = value);
  }

  /// 指针真实位置若已知且不在本组件的全局矩形内，熄灭悬停。
  /// 被注册表在指针事件、滚轮、每个帧回调时调用；无变化时零 setState。
  void _validateHover() {
    if (!mounted || !_hovering) return;
    final pointer = DesktopPointerPosition.instance;
    if (pointer == null) return;
    final renderObject = context.findRenderObject();
    if (renderObject is RenderBox &&
        renderObject.attached &&
        renderObject.hasSize) {
      final bounds =
          renderObject.localToGlobal(Offset.zero) & renderObject.size;
      if (!bounds.contains(pointer)) {
        setState(() => _hovering = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasTap = widget.onTap != null || widget.onSecondaryTapUp != null;
    Widget child = MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => _setHovering(true),
      onExit: (_) => _setHovering(false),
      child: widget.builder(context, _hovering),
    );
    if (hasTap) {
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onSecondaryTapUp: widget.onSecondaryTapUp == null
            ? null
            : (details) => widget.onSecondaryTapUp!(details.globalPosition),
        child: child,
      );
    }
    return child;
  }
}

/// 桌面悬停反馈容器：轻微放大浮起（对应原型 .card-poster:hover）。
///
/// 只做缩放，不画描边——描边在深色海报上会显成一条突兀的亮线；
/// 悬停态经 [DesktopHoverRegion] 自愈校验，内容移动下不会卡住。
class HoverLift extends StatelessWidget {
  const HoverLift({
    super.key,
    required this.child,
    this.radius = DesktopTokens.cardRadius,
    this.enabled = true,
  });

  final Widget child;

  /// 保留参数以兼容既有调用点（此前用于描边圆角）。
  final double radius;

  /// 触屏布局可传 false，直接透出 child。
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return DesktopHoverRegion(
      builder: (context, hovering) => AnimatedScale(
        scale: hovering ? DesktopTokens.hoverLiftScale : 1.0,
        duration: DesktopTokens.hoverDuration,
        curve: Curves.easeOutCubic,
        child: child,
      ),
    );
  }
}
