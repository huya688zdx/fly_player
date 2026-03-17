import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/detail_tokens.dart';
import '../../ui/capability_badge_mapper.dart';

class CapabilityBadge extends StatelessWidget {
  final String label;

  const CapabilityBadge({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
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
        child: SvgPicture.asset(asset, fit: BoxFit.contain),
      );
    }
    return Container(
      height: badgeHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: DetailTokens.compactChipRadius,
        border: Border.all(color: const Color(0xFFD6DEE8), width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        normalized,
        style: const TextStyle(
          color: Color(0xFFD6DEE8),
          fontSize: 9,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}
