import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/detail_tokens.dart';

enum DetailIconButtonStyle { top, circle }

class DetailIconButton extends StatelessWidget {
  final String iconAsset;
  final VoidCallback? onTap;
  final DetailIconButtonStyle style;
  final bool selected;

  const DetailIconButton({
    super.key,
    required this.iconAsset,
    this.onTap,
    this.style = DetailIconButtonStyle.circle,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
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

    final background = isTop
        ? DetailTokens.topButtonBackground
        : ((selected && !isHeart)
              ? DetailTokens.primaryButton
              : DetailTokens.circleButtonBackground);

    final border = isTop
        ? DetailTokens.topButtonBorder
        : DetailTokens.circleButtonBorder;

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
              ? const Icon(Icons.favorite, color: Color(0xFFFF3D57), size: 24)
              : SvgPicture.asset(
                  iconAsset,
                  width: iconSize,
                  height: iconSize,
                ),
        ),
      ),
    );
  }
}
