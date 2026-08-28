import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/app_theme.dart';
import '../../theme/detail_tokens.dart';
import '../../ui/capability_badge_mapper.dart';

class CapabilityBadge extends StatelessWidget {
  final String label;
  final bool onImage;

  const CapabilityBadge({super.key, required this.label, this.onImage = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final foreground = onImage ? const Color(0xFFF2F5F8) : colors.chipText;
    final normalized = CapabilityBadgeMapper.normalize(label);
    if (normalized.isEmpty) return const SizedBox.shrink();
    final asset = CapabilityBadgeMapper.badgeAsset(normalized);
    final uiScale = (MediaQuery.textScalerOf(context).scale(12) / 12).clamp(
      0.95,
      1.35,
    );
    final badgeHeight = (DetailTokens.compactBadgeHeight * uiScale).clamp(
      13.0,
      24.0,
    );
    if (asset != null) {
      return SizedBox(
        height: badgeHeight,
        child: SvgPicture.asset(
          asset,
          fit: BoxFit.contain,
          colorFilter: ColorFilter.mode(foreground, BlendMode.srcIn),
        ),
      );
    }
    return Container(
      height: badgeHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: DetailTokens.compactChipRadius,
        border: Border.all(color: foreground.withValues(alpha: 0.76), width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        normalized,
        style: TextStyle(
          color: foreground,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}
