import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/glass_quality.dart';

/// iOS26 液态玻璃（静态实现）。
///
/// 用「半透明磨砂渐变 + 镜面高光 + 发丝边」模拟玻璃质感，**不使用
/// [BackdropFilter]**——实时高斯模糊会在滚动区逐帧重算、严重掉帧。本实现开销
/// 近似普通装饰容器，配合 [RepaintBoundary] 可被缓存为静态层，滚动零额外开销。
///
/// 色彩跟随 [AppColors]，按背景明度自适应深/浅两套透明度。
enum LiquidGlassTone {
  /// 中性磨砂：通透、低调，用于多数 chip/卡片。
  neutral,

  /// 强调玻璃：带强调色暖晕，用于选中/高亮态。
  accent,

  /// 更实玻璃：底色更不透明，用于压在图像/繁忙背景上需要遮挡时。
  strong,
}

/// 产出磨砂玻璃的 [BoxDecoration]（渐变填充 + 半透明白发丝边）。
///
/// [overBlur] 为 true 时表示底下有真实 [BackdropFilter] 背景模糊，填充会调得更
/// 通透，让模糊后的背景透出来——这才是“真玻璃”而非“磨砂白板”。
BoxDecoration liquidGlassDecoration(
  BuildContext context, {
  double radius = 14,
  LiquidGlassTone tone = LiquidGlassTone.neutral,
  bool selected = false,
  bool overBlur = false,
}) {
  final colors = context.appColors;
  final isLight = colors.backgroundBase.computeLuminance() >= 0.58;

  // 模糊态下边沿略减弱、填充更通透；纯静态态保持原值。
  final edgeAlpha = selected
      ? (isLight ? 0.85 : 0.30)
      : (isLight ? 0.66 : (overBlur ? 0.22 : 0.16));

  // 模糊态对白色填充的衰减系数（背景已被模糊折射，无需再用白色铺底）。
  final double t = overBlur ? 0.55 : 1.0;

  final List<Color> fill;
  switch (tone) {
    case LiquidGlassTone.strong:
      fill = <Color>[
        Colors.white.withValues(alpha: (isLight ? 0.72 : 0.22) * t),
        colors.navBarBackground.withValues(
          alpha: overBlur ? (isLight ? 0.62 : 0.46) : (isLight ? 0.90 : 0.84),
        ),
        colors.accentSoft.withValues(alpha: isLight ? 0.22 : 0.16),
      ];
    case LiquidGlassTone.accent:
      fill = <Color>[
        Colors.white.withValues(alpha: (isLight ? 0.48 : 0.22) * t),
        colors.accentSoft.withValues(
          alpha: overBlur ? (isLight ? 0.26 : 0.30) : (isLight ? 0.32 : 0.22),
        ),
        colors.accent.withValues(alpha: isLight ? 0.16 : 0.12),
      ];
    case LiquidGlassTone.neutral:
      final boost = selected ? 0.08 : 0.0;
      fill = <Color>[
        Colors.white.withValues(alpha: ((isLight ? 0.42 : 0.16) + boost) * t),
        Colors.white.withValues(alpha: ((isLight ? 0.30 : 0.10) + boost) * t),
        colors.accentSoft.withValues(alpha: isLight ? 0.12 : 0.07),
      ];
  }

  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: Colors.white.withValues(alpha: edgeAlpha),
      width: selected ? 0.9 : 0.7,
    ),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: fill,
    ),
  );
}

/// 镜面高光叠层：左上径向反光 + 顶沿发丝高光。
///
/// 可单独叠在**实心**控件（如主操作按钮）上，赋予玻璃质感而不磨砂。务必放在
/// [IgnorePointer] 语义下（本组件已自带）或 Stack 顶层且不拦截手势。
class LiquidGlassSheen extends StatelessWidget {
  final double radius;

  const LiquidGlassSheen({super.key, this.radius = 14});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLight = colors.backgroundBase.computeLuminance() >= 0.58;
    return IgnorePointer(
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.8, -0.95),
                  radius: 1.3,
                  colors: <Color>[
                    Colors.white.withValues(alpha: isLight ? 0.36 : 0.14),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 1,
            right: 1,
            top: 1,
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(radius),
                ),
                color: Colors.white.withValues(alpha: isLight ? 0.60 : 0.24),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 液态玻璃容器：磨砂底 + 可选镜面高光 + 可选点击涟漪。
///
/// 用于卡片、chip、分段段、信息块等。主操作按钮（需保留实心强调色）请改用
/// [LiquidGlassSheen] 单独叠加，不要用本容器。
class LiquidGlass extends StatelessWidget {
  final Widget child;
  final double radius;
  final LiquidGlassTone tone;
  final bool selected;

  /// 是否叠加镜面高光（默认开）。
  final bool sheen;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  /// 真实背景模糊强度（sigma）声明。`0` = 该面**永不**模糊（滚动区卡片应取 0）；
  /// `>0` 表示「在 [LiquidGlassLevel.liquid] 挡位下用此 sigma 做真模糊」。是否真正
  /// 启用由全局 [liquidGlassLevel] 挡位门控——非 liquid 挡位一律退化为静态磨砂。
  /// 故只把它设在**不在滚动列表内**的小面积常驻控件（导航条/详情按钮/弹层等）。
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
    return ValueListenableBuilder<LiquidGlassLevel>(
      valueListenable: liquidGlassLevel,
      builder: (context, level, _) => _buildForLevel(context, level),
    );
  }

  Widget _buildForLevel(BuildContext context, LiquidGlassLevel level) {
    final br = BorderRadius.circular(radius);
    final bool blur = level.usesRealBlur && blurSigma > 0;
    final bool showSheen = sheen && level.drawsSheen;
    Widget content = padding == null
        ? child
        : Padding(padding: padding!, child: child);

    if (showSheen) {
      // passthrough：把外层约束原样传给非定位子（高光层用 Positioned.fill），
      // 这样「是否叠高光」不会改变子内容的布局——父给紧约束就填满、给松约束就
      // 按内容收缩，挡位切换时尺寸/对齐保持一致（否则默认 loose+topStart 会让
      // 全宽卡片在开高光时收缩并左上对齐）。
      content = Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          Positioned.fill(child: LiquidGlassSheen(radius: radius)),
          content,
        ],
      );
    }

    Widget box = DecoratedBox(
      decoration: liquidGlassDecoration(
        context,
        radius: radius,
        tone: tone,
        selected: selected,
        overBlur: blur,
      ),
      child: content,
    );

    if (onTap != null) {
      box = Material(
        type: MaterialType.transparency,
        child: InkWell(onTap: onTap, borderRadius: br, child: box),
      );
    }

    if (blur) {
      box = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: box,
      );
    }

    return RepaintBoundary(
      child: ClipRRect(borderRadius: br, child: box),
    );
  }
}
