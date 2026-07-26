import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/detail_tokens.dart';
import '../common/liquid_glass.dart';

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
    final colors = context.appColors;
    final height = compact
        ? DetailTokens.compactChipHeight
        : DetailTokens.chipHeight;
    final radius = compact ? 4.0 : 9.0;

    return LiquidGlass(
      radius: radius,
      tone: selected ? LiquidGlassTone.accent : LiquidGlassTone.neutral,
      selected: selected,
      sheen: false,
      // 液态挡位下版本/标签 chip 转真实背景模糊；其余挡位退化为静态磨砂。
      blurSigma: compact ? 10 : 14,
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10),
      child: SizedBox(
        height: height,
        // Row 取最小宽度、纵向居中（SizedBox 紧高度 + crossAxisAlignment.center）；
        // 不要用 Center——它在 Wrap 的松约束下会横向撑满，使 chip 变全宽换行。
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? colors.selectionStrong : colors.chipText,
                fontSize: compact ? 9 : 14,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
            if (dropdown) ...[
              SizedBox(width: compact ? 2 : 4),
              Icon(
                Icons.keyboard_arrow_down,
                color: colors.textSecondary,
                size: compact ? 14 : 18,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
