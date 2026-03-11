import 'package:flutter/material.dart';

import '../../theme/detail_tokens.dart';

class DetailTagChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool compact;
  final bool dropdown;

  const DetailTagChip({
    super.key,
    required this.label,
    this.selected = false,
    this.compact = false,
    this.dropdown = false,
  });

  @override
  Widget build(BuildContext context) {
    final height = compact
        ? DetailTokens.compactChipHeight
        : DetailTokens.chipHeight;
    final borderRadius = compact
        ? DetailTokens.compactChipRadius
        : DetailTokens.chipRadius;

    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10),
      decoration: BoxDecoration(
        color: DetailTokens.chipBackground,
        borderRadius: borderRadius,
        border: Border.all(
          color: selected
              ? DetailTokens.chipSelectedBorder
              : DetailTokens.chipBorder,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: selected
                  ? DetailTokens.chipSelectedText
                  : DetailTokens.chipText,
              fontSize: compact ? 9 : 14,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
          if (dropdown) ...[
            SizedBox(width: compact ? 2 : 4),
            Icon(
              Icons.keyboard_arrow_down,
              color: DetailTokens.textSecondary,
              size: compact ? 14 : 18,
            ),
          ],
        ],
      ),
    );
  }
}
