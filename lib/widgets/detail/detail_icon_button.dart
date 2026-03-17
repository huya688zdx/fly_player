import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/app_theme.dart';
import '../../theme/detail_tokens.dart';

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

    final background = isTop
        ? colors.surface.withValues(alpha: 0.36)
        : ((selected && !isHeart)
              ? colors.accent
              : colors.backgroundElevated.withValues(alpha: 0.82));

    final border = isTop ? colors.borderStrong : colors.borderStrong;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: border),
        ),
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
