import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../desktop/desktop.dart';
import '../../../ui/layout_adaptive.dart';

/// 首页内容的连续横向媒体架。
///
/// 桌面设备在窄窗口和分屏下仍保留鼠标翻页；卡片密度按可用宽度调整。
class HomeHorizontalShelf<T> extends StatefulWidget {
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
  State<HomeHorizontalShelf<T>> createState() => _HomeHorizontalShelfState<T>();
}

class _HomeHorizontalShelfState<T> extends State<HomeHorizontalShelf<T>> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final widget = this.widget;
    if (widget.items.isEmpty ||
        !_isPositiveFinite(widget.idealItemWidth) ||
        !_isPositiveFinite(widget.minItemWidth) ||
        !_isPositiveFinite(widget.maxItemWidth) ||
        !_isPositiveFinite(widget.itemAspectRatio) ||
        !_isNonNegativeFinite(widget.textLinesHeight) ||
        !_isNonNegativeFinite(widget.gap)) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (!_isPositiveFinite(maxWidth)) {
          return const SizedBox.shrink();
        }

        final configuredUpper = math.min(
          widget.idealItemWidth,
          widget.maxItemWidth,
        );
        final configuredLower = math.min(widget.minItemWidth, configuredUpper);
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
            cardWidth / widget.itemAspectRatio +
            widget.textLinesHeight * textHeightRatio;

        // 桌面档卡片悬浮放大（HoverLift 1.03）：视口留上下头部并关闭裁剪，
        // 放大边缘才不会被裁切；非桌面档保持旧输出（零回归）。
        final desktopTier = MediaLayoutProfile.of(context).isDesktopTier;
        final listPadding = desktopTier
            ? const EdgeInsets.symmetric(vertical: 8)
            : EdgeInsets.zero;

        Widget buildListView({ScrollController? controller}) =>
            ListView.separated(
              key: PageStorageKey<String>('home-shelf-${widget.storageKey}'),
              controller: controller,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              clipBehavior: desktopTier ? Clip.none : Clip.hardEdge,
              padding: listPadding,
              itemCount: widget.items.length,
              separatorBuilder: (context, index) => SizedBox(width: widget.gap),
              itemBuilder: (context, index) => SizedBox(
                width: cardWidth,
                child: widget.itemBuilder(
                  context,
                  widget.items[index],
                  cardWidth,
                ),
              ),
            );

        // 鼠标翻页属于桌面设备能力，不随布局降到窄屏档而关闭。
        if (!desktopTier && !DesktopEnvironment.isDesktopPlatform) {
          return SizedBox(height: height, child: buildListView());
        }

        return SizedBox(
          height: height + (desktopTier ? 16 : 0),
          child: HoverScrollArrows(
            scrollController: _scrollController,
            // 按钮保持在列表可命中范围内。
            edgePadding: MediaLayoutProfile.of(context).pageHorizontalPadding,
            child: buildListView(controller: _scrollController),
          ),
        );
      },
    );
  }

  static bool _isPositiveFinite(double value) => value.isFinite && value > 0;

  static bool _isNonNegativeFinite(double value) =>
      value.isFinite && value >= 0;
}
