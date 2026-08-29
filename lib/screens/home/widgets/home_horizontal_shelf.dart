import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../desktop/desktop.dart';
import '../../../theme/app_theme.dart';
import '../../../ui/layout_adaptive.dart';

/// 首页内容的连续横向媒体架。
///
/// 非桌面档（窗口宽度 < 桌面侧栏断点）输出与旧版逐字节一致；桌面档额外提供
/// 悬停出现的左右滚动箭头（内容溢出且可向该方向滚动时才可见）。
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
  bool _shelfHovering = false;
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_syncArrowState);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_syncArrowState);
    _scrollController.dispose();
    super.dispose();
  }

  void _syncArrowState() {
    if (!mounted) return;
    var canScrollLeft = false;
    var canScrollRight = false;
    if (_scrollController.hasClients) {
      final position = _scrollController.position;
      if (position.hasContentDimensions && position.maxScrollExtent.isFinite) {
        canScrollLeft = position.pixels > 0;
        canScrollRight = position.pixels < position.maxScrollExtent - 0.5;
      }
    }
    if (canScrollLeft == _canScrollLeft && canScrollRight == _canScrollRight) {
      return;
    }
    setState(() {
      _canScrollLeft = canScrollLeft;
      _canScrollRight = canScrollRight;
    });
  }

  /// 点击箭头时按约 0.8 视口宽度翻页滚动。
  void _scrollByViewport({required bool forward}) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (!position.maxScrollExtent.isFinite) return;
    final delta = position.viewportDimension * 0.8;
    final target = forward ? position.pixels + delta : position.pixels - delta;
    _scrollController.animateTo(
      target.clamp(0.0, position.maxScrollExtent),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
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
        if (!_isPositiveFinite(height)) {
          return const SizedBox.shrink();
        }

        Widget buildListView({ScrollController? controller}) =>
            ListView.separated(
              key: PageStorageKey<String>('home-shelf-${widget.storageKey}'),
              controller: controller,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.zero,
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

        // 桌面档：整架悬停时出现左右滚动箭头；非桌面档保持旧输出（不挂 controller）。
        if (!MediaLayoutProfile.of(context).isDesktopTier) {
          return SizedBox(height: height, child: buildListView());
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncArrowState();
        });
        return SizedBox(
          height: height,
          child: MouseRegion(
            onEnter: (_) => setState(() => _shelfHovering = true),
            onExit: (_) => setState(() => _shelfHovering = false),
            child: Stack(
              children: <Widget>[
                buildListView(controller: _scrollController),
                _ShelfArrow(
                  visible: _shelfHovering && _canScrollLeft,
                  icon: Icons.chevron_left,
                  alignLeft: true,
                  onTap: () => _scrollByViewport(forward: false),
                ),
                _ShelfArrow(
                  visible: _shelfHovering && _canScrollRight,
                  icon: Icons.chevron_right,
                  alignLeft: false,
                  onTap: () => _scrollByViewport(forward: true),
                ),
              ],
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

/// 桌面档横向架的悬停滚动箭头：圆形 34px，surfaceStrong 底、selection hover。
class _ShelfArrow extends StatefulWidget {
  const _ShelfArrow({
    required this.visible,
    required this.icon,
    required this.alignLeft,
    required this.onTap,
  });

  final bool visible;
  final IconData icon;

  /// true 贴左缘，false 贴右缘。
  final bool alignLeft;
  final VoidCallback onTap;

  @override
  State<_ShelfArrow> createState() => _ShelfArrowState();
}

class _ShelfArrowState extends State<_ShelfArrow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final button = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          width: 34,
          height: 34,
          duration: DesktopTokens.hoverDuration,
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _hovering ? colors.selection : colors.surfaceStrong,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: .24),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(widget.icon, size: 20, color: colors.textPrimary),
        ),
      ),
    );
    // Positioned 必须是 Stack 子级的直接父数据层，淡入淡出放在其内部。
    final alignment = widget.alignLeft
        ? Alignment.centerLeft
        : Alignment.centerRight;
    return Positioned(
      left: widget.alignLeft ? 4 : null,
      right: widget.alignLeft ? null : 4,
      top: 0,
      bottom: 0,
      child: AnimatedOpacity(
        opacity: widget.visible ? 1 : 0,
        duration: DesktopTokens.hoverDuration,
        child: IgnorePointer(
          ignoring: !widget.visible,
          child: Align(alignment: alignment, child: button),
        ),
      ),
    );
  }
}
