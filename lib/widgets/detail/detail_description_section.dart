import 'package:flutter/material.dart';

import 'description_section.dart';

class DetailDescriptionSection extends StatelessWidget {
  final String text;
  final VoidCallback onMoreTap;
  final int maxLines;
  final double baseFontSize;

  const DetailDescriptionSection({
    super.key,
    required this.text,
    required this.onMoreTap,
    this.maxLines = 4,
    this.baseFontSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    return DescriptionSection(
      text: text,
      onMoreTap: onMoreTap,
      maxLines: maxLines,
      baseFontSize: baseFontSize,
    );
  }
}
