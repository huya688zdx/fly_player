import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/app_theme.dart';
import '../../theme/detail_tokens.dart';
import '../common/liquid_glass.dart';

enum DetailIconButtonStyle { top, circle }

class DetailIconButton extends StatelessWidget {
  final String iconAsset;
  final String? selectedIconAsset;
  final VoidCallback? onTap;
  final DetailIconButtonStyle style;
  final bool selected;

  const DetailIconButton({
    super.key,
    required this.iconAsset,
    this.selectedIconAsset,
    this.onTap,
    this.style = DetailIconButtonStyle.circle,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final accentForeground = Theme.of(context).colorScheme.onPrimary;
    final isTop = style == DetailIconButtonStyle.top;
    final isHeart = iconAsset.contains('heart.svg');
    final size = isTop
        ? DetailTokens.topButtonSize
        : DetailTokens.circleButtonSize;
    final radius = isTop
        ? DetailTokens.topButtonRadius
        : DetailTokens.circleButtonRadius;
    final iconSize = isTop
        ? DetailTokens.topButtonIconSize
        : DetailTokens.circleButtonIconSize;
    final resolvedIconAsset = selected && selectedIconAsset != null
        ? selectedIconAsset!
        : iconAsset;

    final accentSelected = selected && !isHeart;
    // 顶栏按钮压在 hero 图上 → 用更实的 strong 玻璃保证可读；其余用中性玻璃。
    final tone = accentSelected
        ? LiquidGlassTone.accent
        : (isTop ? LiquidGlassTone.strong : LiquidGlassTone.neutral);

    return LiquidGlass(
      radius: radius,
      tone: tone,
      selected: accentSelected,
      sheen: false,
      // 液态挡位下圆形按钮转真实背景模糊；其余挡位退化为静态磨砂。
      blurSigma: 16,
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: (isHeart && selected)
              ? Icon(Icons.favorite, color: colors.danger, size: 24)
              : SvgPicture.asset(
                  resolvedIconAsset,
                  width: iconSize,
                  height: iconSize,
                  colorFilter: ColorFilter.mode(
                    (selected && !isHeart)
                        ? accentForeground
                        : colors.textPrimary,
                    BlendMode.srcIn,
                  ),
                ),
        ),
      ),
    );
  }
}
