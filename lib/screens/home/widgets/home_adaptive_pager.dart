import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../home_responsive_layout.dart';

/// 按当前可用宽度完整分页的首页卡片容器。
class HomeAdaptivePager<T> extends StatefulWidget {
  const HomeAdaptivePager({
    super.key,
    required this.items,
    required this.itemId,
    required this.itemBuilder,
    required this.idealItemWidth,
    required this.itemAspectRatio,
    this.gap = 10,
    this.maxColumns = 5,
    this.textLinesHeight = 44,
    this.onFirstVisibleItemIdChanged,
  });

  final List<T> items;
  final String Function(T item) itemId;
  final Widget Function(BuildContext context, T item, double width) itemBuilder;
  final double idealItemWidth;
  final double itemAspectRatio;
  final double gap;
  final int maxColumns;
  final double textLinesHeight;
  final ValueChanged<String>? onFirstVisibleItemIdChanged;

  @override
  State<HomeAdaptivePager<T>> createState() => _HomeAdaptivePagerState<T>();
}

class _HomeAdaptivePagerState<T> extends State<HomeAdaptivePager<T>> {
  late PageController _controller;
  List<String> _lastItemIds = const <String>[];
  int _lastColumns = -1;
  double _lastCardWidth = -1;
  int _currentPage = 0;
  int _firstVisibleIndex = 0;
  String? _firstVisibleId;
  int _controllerGeneration = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final layout = HomeResponsiveLayout.resolve(
          availableWidth: constraints.maxWidth,
          itemCount: widget.items.length,
          idealCardWidth: widget.idealItemWidth,
          gap: widget.gap,
          textScale: textScale,
          maxColumns: widget.maxColumns,
        );
        if (layout.columns == 0) {
          return const SizedBox.shrink();
        }

        final ids = widget.items.map(widget.itemId).toList(growable: false);
        _restoreControllerIfNeeded(layout, ids);

        final textHeight =
            widget.textLinesHeight * textScale.clamp(1.0, 1.5).toDouble();
        final pageHeight =
            layout.cardWidth / widget.itemAspectRatio + textHeight;
        final hasIndicator = layout.pageCount > 1;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              height: pageHeight,
              child: PageView.builder(
                key: ValueKey<String>(
                  'home-pager-generation-$_controllerGeneration',
                ),
                controller: _controller,
                itemCount: layout.pageCount,
                onPageChanged: (page) => _handlePageChanged(page, layout),
                itemBuilder: (context, page) {
                  final start = page * layout.columns;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (var slot = 0; slot < layout.columns; slot++) ...[
                        if (slot > 0) SizedBox(width: layout.gap),
                        _buildSlot(
                          context,
                          itemIndex: start + slot,
                          cardWidth: layout.cardWidth,
                          cardHeight: pageHeight,
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
            if (hasIndicator) ...<Widget>[
              const SizedBox(height: 8),
              _PageIndicator(
                currentPage: _currentPage,
                pageCount: layout.pageCount,
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildSlot(
    BuildContext context, {
    required int itemIndex,
    required double cardWidth,
    required double cardHeight,
  }) {
    if (itemIndex >= widget.items.length) {
      return SizedBox(width: cardWidth, height: cardHeight);
    }
    return SizedBox(
      width: cardWidth,
      height: cardHeight,
      child: widget.itemBuilder(context, widget.items[itemIndex], cardWidth),
    );
  }

  void _restoreControllerIfNeeded(
    HomeResponsiveLayout layout,
    List<String> ids,
  ) {
    if (_lastColumns == layout.columns &&
        _lastCardWidth == layout.cardWidth &&
        listEquals(_lastItemIds, ids)) {
      return;
    }

    final previousFirstId = _firstVisibleId;
    var restoreIndex = _firstVisibleIndex;
    final rememberedId = _firstVisibleId;
    if (rememberedId != null) {
      final rememberedIndex = ids.indexOf(rememberedId);
      if (rememberedIndex >= 0) {
        restoreIndex = rememberedIndex;
      }
    }
    restoreIndex = restoreIndex.clamp(0, ids.length - 1).toInt();
    _currentPage = layout.pageForFirstItem(restoreIndex);
    _firstVisibleIndex = _currentPage * layout.columns;
    _firstVisibleId = ids[_firstVisibleIndex];
    final restoredFirstId = _firstVisibleId!;
    _lastColumns = layout.columns;
    _lastCardWidth = layout.cardWidth;
    _lastItemIds = ids;

    final oldController = _controller;
    _controller = PageController(initialPage: _currentPage);
    _controllerGeneration++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldController.dispose();
      if (mounted && previousFirstId != restoredFirstId) {
        widget.onFirstVisibleItemIdChanged?.call(restoredFirstId);
      }
    });
  }

  void _handlePageChanged(int page, HomeResponsiveLayout layout) {
    final firstIndex = (page * layout.columns).clamp(
      0,
      widget.items.length - 1,
    );
    final firstId = widget.itemId(widget.items[firstIndex]);
    setState(() {
      _currentPage = page;
      _firstVisibleIndex = firstIndex;
      _firstVisibleId = firstId;
    });
    widget.onFirstVisibleItemIdChanged?.call(firstId);
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.currentPage, required this.pageCount});

  final int currentPage;
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '第 ${currentPage + 1} 页，共 $pageCount 页',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List<Widget>.generate(pageCount, (index) {
          final selected = index == currentPage;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: selected ? 16 : 5,
            height: 5,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: selected ? scheme.primary : scheme.outlineVariant,
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }),
      ),
    );
  }
}
