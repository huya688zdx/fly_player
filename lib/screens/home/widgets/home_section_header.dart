import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// 首页区块的统一标题行。
class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader({super.key, required this.title, this.trailingText});

  final String title;
  final String? trailingText;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (trailingText case final text?) ...<Widget>[
          const SizedBox(width: 12),
          Text(
            text,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ],
    );
  }
}
