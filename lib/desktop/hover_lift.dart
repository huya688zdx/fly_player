import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'desktop_tokens.dart';

/// 桌面悬停反馈容器：轻微上浮 + accent 光晕描边（对应原型 .card-poster:hover）。
///
/// 颜色经 [AppThemeColors] 读取，7 套预设与亮暗模式自动跟随；
/// 主题扩展缺失（纯测试环境）时退化为仅缩放，不抛错。
class HoverLift extends StatefulWidget {
  const HoverLift({
    super.key,
    required this.child,
    this.radius = DesktopTokens.cardRadius,
    this.glow = true,
    this.enabled = true,
  });

  final Widget child;

  /// 描边圆角，默认对齐 MediaPosterCard 的 10px。
  final double radius;

  final bool glow;

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
    final colors = Theme.of(context).extension<AppThemeColors>();
    final glowColor = colors?.selection ?? Colors.transparent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedScale(
        scale: _hovering ? DesktopTokens.hoverLiftScale : 1.0,
        duration: DesktopTokens.hoverDuration,
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: DesktopTokens.hoverDuration,
          curve: Curves.easeOutCubic,
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(
              color: glowColor.withValues(
                alpha: _hovering && widget.glow ? 0.55 : 0.0,
              ),
              width: 1.2,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
