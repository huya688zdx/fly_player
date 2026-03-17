import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/detail_tokens.dart';
import '../../ui/adaptive_text.dart';

class DetailMetaLines extends StatelessWidget {
  final String metaLineA;
  final String metaLineB;
  final int metaLineAMaxLines;
  final int metaLineBMaxLines;

  const DetailMetaLines({
    super.key,
    required this.metaLineA,
    this.metaLineB = '',
    this.metaLineAMaxLines = 1,
    this.metaLineBMaxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metaSize = AdaptiveText.roleSize(DetailTokens.metaFontSize);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          metaLineA,
          maxLines: metaLineAMaxLines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: metaSize,
            fontWeight: FontWeight.w500,
            height: 1.28,
          ),
        ),
        if (metaLineB.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            metaLineB,
            maxLines: metaLineBMaxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: metaSize,
              fontWeight: FontWeight.w500,
              height: 1.28,
            ),
          ),
        ],
      ],
    );
  }
}
