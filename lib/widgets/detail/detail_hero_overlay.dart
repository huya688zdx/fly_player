import 'package:flutter/material.dart';

import '../../theme/detail_tokens.dart';
import 'detail_info_block.dart';

class DetailHeroOverlay extends StatelessWidget {
  final double height;
  final String title;
  final String subtitle;
  final double? titleFontSize;
  final double bottomInset;
  final bool useSoftGradient;

  const DetailHeroOverlay({
    super.key,
    required this.height,
    required this.title,
    this.subtitle = '',
    this.titleFontSize,
    this.bottomInset = 36,
    this.useSoftGradient = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = useSoftGradient
        ? const [
            Color(0x001A1E23),
            Color(0x0C1A1E23),
            Color(0x241A1E23),
            Color(0x451A1E23),
            Color(0x821A1E23),
            DetailTokens.pageBackground,
          ]
        : const [
            Color(0x001A1E23),
            Color(0x331A1E23),
            Color(0x771A1E23),
            Color(0x881A1E23),
            Color(0x991A1E23),
            DetailTokens.pageBackground,
          ];
    final stops = useSoftGradient
        ? const [0.0, 0.46, 0.68, 0.82, 0.92, 1.0]
        : const [0.0, 0.50, 0.74, 0.86, 0.92, 1.0];

    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            left: 0,
            right: 0,
            top: 0,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: colors,
                    stops: stops,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: DetailTokens.screenHorizontalPadding,
            right: DetailTokens.screenHorizontalPadding,
            bottom: bottomInset,
            child: DetailTitleBlock(
              title: title,
              subtitle: subtitle,
              titleFontSize: titleFontSize,
            ),
          ),
        ],
      ),
    );
  }
}
