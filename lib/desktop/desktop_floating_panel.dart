import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// PC 端通用悬浮小窗外壳。
///
/// 业务方只提供内容；圆角、玻璃背景、边框、阴影和滚动条样式在这里统一。
class DesktopFloatingPanel extends StatelessWidget {
  const DesktopFloatingPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0x78070D16),
            borderRadius: radius,
            border: Border.all(color: const Color(0x14FFFFFF)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x70000000),
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
