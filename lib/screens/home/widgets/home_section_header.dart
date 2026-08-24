import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// 首页区块的统一标题行。
class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader({super.key, required this.title});

  final String title;

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
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.15,
            ),
          ),
        ),
      ],
    );
  }
}
