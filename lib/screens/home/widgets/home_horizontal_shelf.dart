import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 首页内容的连续横向媒体架。
class HomeHorizontalShelf<T> extends StatelessWidget {
  const HomeHorizontalShelf({
    super.key,
    required this.storageKey,
    required this.items,
    required this.itemBuilder,
    required this.idealItemWidth,
    required this.minItemWidth,
    required this.maxItemWidth,
    required this.itemAspectRatio,
    this.textLinesHeight = 44,
    this.gap = 12,
  });

  final String storageKey;
  final List<T> items;
  final Widget Function(BuildContext context, T item, double width) itemBuilder;
  final double idealItemWidth;
  final double minItemWidth;
  final double maxItemWidth;
  final double itemAspectRatio;
  final double textLinesHeight;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty ||
        !_isPositiveFinite(idealItemWidth) ||
        !_isPositiveFinite(minItemWidth) ||
        !_isPositiveFinite(maxItemWidth) ||
        !_isPositiveFinite(itemAspectRatio) ||
        !_isNonNegativeFinite(textLinesHeight) ||
        !_isNonNegativeFinite(gap)) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (!_isPositiveFinite(maxWidth)) {
          return const SizedBox.shrink();
        }

        final configuredUpper = math.min(idealItemWidth, maxItemWidth);
        final configuredLower = math.min(minItemWidth, configuredUpper);
        final lowerBound = math.min(maxWidth, configuredLower);
        final upperBound = math.min(maxWidth, configuredUpper);
        if (lowerBound <= 0 || upperBound <= 0) {
          return const SizedBox.shrink();
        }

        final fraction = maxWidth >= 700
            ? .28
            : maxWidth >= 500
            ? .40
            : .56;
        final cardWidth = (maxWidth * fraction).clamp(lowerBound, upperBound);
        if (!_isPositiveFinite(cardWidth)) {
          return const SizedBox.shrink();
        }

        final textScaler = MediaQuery.textScalerOf(context);
        final bodyRatio = textScaler.scale(14) / 14;
        final metadataRatio = textScaler.scale(12) / 12;
        if (!_isPositiveFinite(bodyRatio) ||
            !_isPositiveFinite(metadataRatio)) {
          return const SizedBox.shrink();
        }
        final textHeightRatio = math
            .max(bodyRatio, metadataRatio)
            .clamp(1.0, double.infinity);
        final height =
            cardWidth / itemAspectRatio + textLinesHeight * textHeightRatio;
        if (!_isPositiveFinite(height)) {
          return const SizedBox.shrink();
        }

        return SizedBox(
          height: height,
          child: ListView.separated(
            key: PageStorageKey<String>('home-shelf-$storageKey'),
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: items.length,
            separatorBuilder: (context, index) => SizedBox(width: gap),
            itemBuilder: (context, index) => SizedBox(
              width: cardWidth,
              child: itemBuilder(context, items[index], cardWidth),
            ),
          ),
        );
      },
    );
  }

  static bool _isPositiveFinite(double value) => value.isFinite && value > 0;

  static bool _isNonNegativeFinite(double value) =>
      value.isFinite && value >= 0;
}
