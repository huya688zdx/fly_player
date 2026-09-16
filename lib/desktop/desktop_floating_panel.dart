import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// PC 端通用悬浮小窗外壳。
///
/// 业务方只提供内容；圆角、玻璃背景、边框、阴影和滚动条样式在这里统一。
/// 外壳同时吞掉空白处的单击/右键：点击不再穿透到底下的播放器画面（误触
/// 播放暂停、右键菜单），玻璃圆角以外的四角死区也一并覆盖；内部控件在
/// 命中路径上更深，竞技场优先，不受影响。
///
/// 双击不在外壳的拦截范围内：Flutter 的双击识别器在 PointerRouter 层记账，
/// 第一下抬手无视竞技场结果直接 hold 整个点按序列，第二下直接触发
/// onDoubleTap，任何命中挡板都拦不住——需要业务回调按自身状态忽略
/// （见播放页视频区 onDoubleTap）。
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
                child: ScrollbarTheme(
                  data: ScrollbarTheme.of(context).copyWith(
                    trackVisibility: const WidgetStatePropertyAll(false),
                    thickness: WidgetStateProperty.resolveWith(
                      (states) =>
                          states.contains(WidgetState.hovered) ||
                              states.contains(WidgetState.dragged)
                          ? 5
                          : 3,
                    ),
                    radius: const Radius.circular(999),
                    crossAxisMargin: 2,
                    mainAxisMargin: 4,
                    thumbColor: WidgetStateProperty.resolveWith(
                      (states) => colors.textSecondary.withValues(
                        alpha:
                            states.contains(WidgetState.hovered) ||
                                states.contains(WidgetState.dragged)
                            ? 0.70
                            : 0.35,
                      ),
                    ),
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 悬浮面板手势屏蔽：面板空白处的单击/右键就地吞掉，不再落到面板底下的
/// 处理器上。命中测试先走子级，面板内部按钮、滑块、列表不受影响。
/// 双击拦不住（识别器在 PointerRouter 层记账、绕过竞技场），由业务回调
/// 自行按状态忽略；这里刻意也不注册 onDoubleTap——它每次点按都会留下
/// 300ms 记账 Timer，对测试与帧调度只有额外负担。
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
