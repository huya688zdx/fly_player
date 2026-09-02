import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// PC 端通用悬浮小窗外壳。
///
/// 业务方只提供内容；圆角、玻璃背景、边框、阴影和滚动条样式在这里统一。
class DesktopFloatingPanel extends StatelessWidget {
  const DesktopFloatingPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final radius = BorderRadius.circular(18);
    final panelColor = isLight
        ? Color.alphaBlend(
            colors.accent.withValues(alpha: 0.045),
            colors.surface,
          ).withValues(alpha: 0.96)
        : const Color(0x78070D16);
    final borderColor = isLight
        ? colors.accent.withValues(alpha: 0.16)
        : const Color(0x14FFFFFF);
    final shadowColor = isLight
        ? colors.overlayScrim.withValues(alpha: 0.16)
        : const Color(0x70000000);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: panelColor,
            borderRadius: radius,
            border: Border.all(color: borderColor),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: shadowColor,
                blurRadius: 30,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
