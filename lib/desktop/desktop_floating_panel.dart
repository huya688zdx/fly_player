import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// PC 端通用悬浮小窗外壳。
///
/// 业务方只提供内容；圆角、玻璃背景、边框、阴影和滚动条样式在这里统一。
/// 外壳同时吞掉空白处的单击/右键（双击的第一下随之被吞，背景的双击识别器
/// 记不上任何点按）：点击不再穿透到底下的播放器画面（误触播放暂停、双击
/// 全屏、右键菜单），玻璃圆角以外的四角死区也一并覆盖；内部控件在命中
/// 路径上更深，竞技场优先，不受影响。
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
    return DesktopPanelGestureShield(
      child: ClipRRect(
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
                  offset: const Offset(0, 14),
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
      ),
    );
  }
}

/// 悬浮面板手势屏蔽：面板空白处的单击/右键就地吞掉，不再落到面板底下的
/// 处理器上。双击同样到不了背景——第一下已被这里的单击识别器赢下，背景的
/// 双击识别器在第一下就被拒绝，记不上任何一次点按。（这里刻意不注册
/// onDoubleTap：双击识别器每次点按都会留下 300ms 记账 Timer，无收益。）
/// 命中测试先走子级，面板内部按钮、滑块、列表不受影响。
class DesktopPanelGestureShield extends StatelessWidget {
  const DesktopPanelGestureShield({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () {},
    onSecondaryTapUp: (_) {},
    child: child,
  );
}
