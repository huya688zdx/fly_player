import 'package:flutter/material.dart';

import 'desktop_tokens.dart';

/// 桌面悬停反馈容器：轻微放大浮起（对应原型 .card-poster:hover）。
///
/// 只做缩放，不画描边——描边在深色海报上会显成一条突兀的亮线；
/// 颜色反馈交给卡片自身的图片/标题 hover 态。
class HoverLift extends StatefulWidget {
  const HoverLift({super.key, required this.child, this.enabled = true});

  final Widget child;

  /// 触屏布局可传 false，直接透出 child。
  final bool enabled;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedScale(
        scale: _hovering ? DesktopTokens.hoverLiftScale : 1.0,
        duration: DesktopTokens.hoverDuration,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
