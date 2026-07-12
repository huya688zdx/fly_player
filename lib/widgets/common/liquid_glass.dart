import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 纯色面板（原 iOS26 液态玻璃，现已退化为纯色）。
///
/// 原实现用「半透明磨砂渐变 + 镜面高光 + 可选 [BackdropFilter] 实时模糊」模拟玻璃，
/// 但真实模糊会在**页面转场 / 滚动时逐帧重栅格、明显掉帧**，且产品上决定回归纯色风格。
/// 现统一渲染为**单一实色填充 + 细边**，按 [LiquidGlassTone] / `selected` 区分语义。
/// 调用点与 `sheen`/`blurSigma` 入参保持不变（仅不再生效），便于日后需要时恢复。
///
/// 色彩跟随 [AppColors]，selected/accent 用强调色以保留选中可读性。
enum LiquidGlassTone {
  /// 中性面板：用于多数 chip/卡片。
  neutral,

  /// 强调面板：带强调色，用于选中/高亮态。
  accent,

  /// 更实面板：压在图像/繁忙背景上需要遮挡时（顶栏按钮等）。
  strong,
}

/// 产出纯色面板的 [BoxDecoration]（实色填充 + 细边）。
///
/// [overBlur] 已废弃（保留入参仅为兼容旧调用），不再影响渲染。
BoxDecoration liquidGlassDecoration(
  BuildContext context, {
  double radius = 14,
  LiquidGlassTone tone = LiquidGlassTone.neutral,
  bool selected = false,
  bool overBlur = false,
}) {
  final colors = context.appColors;

  final Color fill;
  final Color border;
  switch (tone) {
    case LiquidGlassTone.accent:
      fill = colors.accentSoft;
      border = colors.accentStrong.withValues(alpha: 0.45);
    case LiquidGlassTone.strong:
      fill = selected ? colors.accentSoft : colors.surfaceStrong;
      border = selected
          ? colors.accentStrong.withValues(alpha: 0.45)
          : colors.borderStrong;
    case LiquidGlassTone.neutral:
      fill = selected ? colors.accentSoft : colors.surfaceStrong;
      border = selected
          ? colors.accentStrong.withValues(alpha: 0.45)
          : colors.borderSubtle;
  }

  return BoxDecoration(
    color: fill,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: border, width: selected ? 0.9 : 0.7),
  );
}

/// 兼容保留：原镜面高光叠层，纯色风格下不再绘制任何内容。
///
/// 仍被少数调用点单独叠加（如主播放按钮），渲染空占位以保持其布局/手势语义不变。
class LiquidGlassSheen extends StatelessWidget {
  final double radius;

  const LiquidGlassSheen({super.key, this.radius = 14});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// 纯色面板容器：实色底 + 可选点击涟漪。
///
/// `sheen` / `blurSigma` 入参保留但不再生效（纯色风格无高光、无实时模糊）。
class LiquidGlass extends StatelessWidget {
  final Widget child;
  final double radius;
  final LiquidGlassTone tone;
  final bool selected;

  /// 已废弃：纯色风格下不绘制镜面高光。保留入参仅为兼容旧调用。
  final bool sheen;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  /// 已废弃：纯色风格下不启用实时背景模糊。保留入参仅为兼容旧调用。
  final double blurSigma;

  const LiquidGlass({
    super.key,
    required this.child,
    this.radius = 14,
    this.tone = LiquidGlassTone.neutral,
    this.selected = false,
    this.sheen = true,
    this.padding,
    this.onTap,
    this.blurSigma = 0,
  });

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    Widget content = padding == null
        ? child
        : Padding(padding: padding!, child: child);

    Widget box = DecoratedBox(
      decoration: liquidGlassDecoration(
        context,
        radius: radius,
        tone: tone,
        selected: selected,
      ),
      child: content,
    );

    if (onTap != null) {
      box = Material(
        type: MaterialType.transparency,
        child: InkWell(onTap: onTap, borderRadius: br, child: box),
      );
    }

    return RepaintBoundary(
      child: ClipRRect(borderRadius: br, child: box),
    );
  }
}
