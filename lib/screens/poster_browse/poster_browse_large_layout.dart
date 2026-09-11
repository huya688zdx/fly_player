import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../../desktop/desktop_environment.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../media_backend/media_image_request.dart';
import '../../media_backend/media_item_card.dart';
import 'poster_browse_display_item.dart';
import 'poster_browse_desktop_navigation.dart';
import 'poster_browse_landscape_gesture_panel.dart';
import 'poster_browse_media_info.dart';
import 'poster_browse_row_status.dart';
import 'poster_browse_rows.dart';

class PosterBrowseLargeLayout extends StatefulWidget {
  final List<PosterBrowseRow> rows;
  final PosterBrowseDisplayItem Function(MediaItemCard card) displayItemOf;
  final int selectedRow;
  final int focusedIndex;
  final PosterBrowseDisplayItem? focusedItem;
  final MediaImageRequest logoRequest;
  final String secondaryLabel;
  final List<Widget> metaWidgets;
  final MediaImageRequest Function(PosterBrowseDisplayItem item) imageOf;
  final String Function(PosterBrowseDisplayItem item) secondaryLabelOf;
  final void Function(int index) onSelectRow;
  final void Function(int index) onSelectItem;
  final VoidCallback onRetryCurrentRow;
  final VoidCallback onPlay;
  final VoidCallback onDetail;
  final VoidCallback onBack;

  const PosterBrowseLargeLayout({
    super.key,
    required this.rows,
    required this.displayItemOf,
    required this.selectedRow,
    required this.focusedIndex,
    required this.focusedItem,
    required this.logoRequest,
    required this.secondaryLabel,
    required this.metaWidgets,
    required this.imageOf,
    required this.secondaryLabelOf,
    required this.onSelectRow,
    required this.onSelectItem,
    required this.onRetryCurrentRow,
    required this.onPlay,
    required this.onDetail,
    required this.onBack,
  });

  @override
  State<PosterBrowseLargeLayout> createState() =>
      _PosterBrowseLargeLayoutState();
}

class _PosterBrowseLargeLayoutState extends State<PosterBrowseLargeLayout> {
  static const _horizontalVelocityThreshold = 360.0;
  static const _horizontalDistanceThreshold = 48.0;
  static const _maxTrackHeight = 264.0;
  static const _maxCardWidth = 116.0;
  static const _minCardWidth = 72.0;
  // 轨道 ListView 的上下内边距（6+6），卡片宽度要为它让位。
  static const _trackVerticalPadding = 12.0;
  // 标题最多两行、剧集副标题一行，再加两段间距；按 CJK 字体实际行高留足余量
  // （此前按 80px 估算，中文两行标题在矮视口下会 BOTTOM OVERFLOWED ~4px）。
  static const _cardVerticalBudget = 92.0;

  double _collapseProgress = 0;
  double _horizontalDragDistance = 0;

  @override
  Widget build(BuildContext context) {
    final currentRow = _selectedRowOrNull(widget.rows);
    final currentItems = currentRow == null
        ? const <PosterBrowseDisplayItem>[]
        : currentRow.items.map(widget.displayItemOf).toList(growable: false);

    final content = GestureDetector(
      key: const ValueKey('poster_browse_full_horizontal_swipe_surface'),
      behavior: HitTestBehavior.opaque,
      supportedDevices: DesktopEnvironment.isDesktopPlatform
          ? const {
              PointerDeviceKind.touch,
              PointerDeviceKind.stylus,
              PointerDeviceKind.invertedStylus,
              PointerDeviceKind.trackpad,
            }
          : null,
      onHorizontalDragStart: currentItems.length > 1
          ? (_) => _horizontalDragDistance = 0
          : null,
      onHorizontalDragUpdate: currentItems.length > 1
          ? (details) {
              _horizontalDragDistance +=
                  details.primaryDelta ?? details.delta.dx;
            }
          : null,
      onHorizontalDragEnd: currentItems.length > 1
          ? (details) =>
                _handlePrimaryHorizontalDragEnd(details, currentItems.length)
          : null,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewportHeight = constraints.maxHeight;
            final showMediaInfo = viewportHeight >= 600;
            final compressChrome = viewportHeight < 412;
            final verticalInset = compressChrome ? 8.0 : null;
            final collapseProgress = _collapseProgress.clamp(0.0, 1.0);
            final topInset = verticalInset ?? 16.0;
            final bottomInset = verticalInset ?? 22.0;
            final selectorSpacing = compressChrome ? 8.0 : 14.0;
            final expandedTrackHeight = _trackHeightFor(
              viewportHeight: viewportHeight,
              topInset: topInset,
              bottomInset: bottomInset,
              selectorSpacing: selectorSpacing,
              collapseProgress: 0,
            );
            final trackHeight = _trackHeightFor(
              viewportHeight: viewportHeight,
              topInset: topInset,
              bottomInset: bottomInset,
              selectorSpacing: selectorSpacing,
              collapseProgress: collapseProgress,
            );
            final trackSlideDistance = trackHeight + selectorSpacing + 48;
            // 按展开态的真实剩余高度约束信息，动画中保持同一尺寸。
            final infoHeight =
                (viewportHeight -
                        topInset -
                        bottomInset -
                        72 -
                        expandedTrackHeight -
                        selectorSpacing -
                        48 -
                        16)
                    .clamp(0.0, viewportHeight);
            final cardWidth =
                ((expandedTrackHeight -
                            _trackVerticalPadding -
                            (_cardVerticalBudget +
                                (DesktopEnvironment.isDesktopPlatform
                                    ? 20
                                    : 0))) /
                        1.5)
                    .clamp(_minCardWidth, _maxCardWidth)
                    .toDouble();

            return Padding(
              padding: EdgeInsets.fromLTRB(28, topInset, 28, bottomInset),
              child: Stack(
                children: [
                  if (showMediaInfo)
                    Positioned(
                      key: const ValueKey('poster_browse_primary_media_info'),
                      left: 36,
                      right: 36,
                      top: 48 + 24,
                      // 同一份信息随进度移到左下方，不再叠放淡入的副本。
                      bottom:
                          (expandedTrackHeight + selectorSpacing + 48 + 16) *
                              (1 - collapseProgress) +
                          34 * collapseProgress,
                      child: Align(
                        alignment: Alignment(-1, collapseProgress),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: 560,
                            maxHeight: infoHeight,
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: (constraints.maxWidth - 128).clamp(
                                0.0,
                                560.0,
                              ),
                              child: _buildAnimatedPrimaryMediaInfo(
                                viewportHeight,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _BackButton(onPressed: widget.onBack),
                      const Spacer(),
                      if (collapseProgress < 0.999)
                        IgnorePointer(
                          ignoring: collapseProgress > 0,
                          child: Transform.translate(
                            offset: Offset(
                              0,
                              // 间距收缩已推动分类栏下移，扣除这部分以同步海报位移。
                              (trackSlideDistance - selectorSpacing) *
                                  collapseProgress,
                            ),
                            child: Align(
                              alignment: Alignment.bottomLeft,
                              heightFactor: 1 - collapseProgress,
                              child: _RowSelector(
                                rows: widget.rows,
                                selectedRow: widget.selectedRow,
                                onSelectRow: widget.onSelectRow,
                              ),
                            ),
                          ),
                        ),
                      SizedBox(
                        height: selectorSpacing * (1 - collapseProgress),
                      ),
                      SizedBox(
                        height: trackHeight,
                        child: _buildTrackArea(
                          context,
                          currentRow,
                          currentItems,
                          cardWidth,
                          showMediaInfo: showMediaInfo,
                          trackSlideFactor: trackHeight > 0
                              ? trackSlideDistance / trackHeight
                              : 1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    return PosterBrowseDesktopNavigation(
      selectedRow: widget.selectedRow,
      rowCount: widget.rows.length,
      focusedIndex: widget.focusedIndex,
      itemCount: currentItems.length,
      onSelectRow: widget.onSelectRow,
      onSelectItem: widget.onSelectItem,
      onBack: widget.onBack,
      child: content,
    );
  }

  PosterBrowseRow? _selectedRowOrNull(List<PosterBrowseRow> visibleRows) {
    if (visibleRows.isEmpty) {
      return null;
    }
    if (widget.selectedRow < 0 || widget.selectedRow >= visibleRows.length) {
      return visibleRows.first;
    }
    return visibleRows[widget.selectedRow];
  }

  Widget _buildTrackArea(
    BuildContext context,
    PosterBrowseRow? currentRow,
    List<PosterBrowseDisplayItem> currentItems,
    double cardWidth, {
    required bool showMediaInfo,
    required double trackSlideFactor,
  }) {
    if (currentItems.isNotEmpty) {
      return PosterBrowseLandscapeGesturePanel(
        items: currentItems,
        focusedIndex: widget.focusedIndex,
        showProgress: currentRow?.kind == PosterBrowseRowKind.continueWatching,
        imageOf: widget.imageOf,
        secondaryLabelOf: widget.secondaryLabelOf,
        onItemTap: widget.onSelectItem,
        onCollapseProgressChanged: _handleCollapseProgressChanged,
        cardWidth: cardWidth,
        trackSlideFactor: trackSlideFactor,
        showDesktopControls: DesktopEnvironment.isDesktopPlatform,
        collapsedContent: showMediaInfo || widget.focusedItem == null
            ? const SizedBox.shrink()
            : Padding(
                key: ValueKey(
                  'poster_browse_collapsed_content_${widget.focusedItem!.card.id}',
                ),
                padding: const EdgeInsets.fromLTRB(36, 0, 36, 4),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: PosterBrowseMediaInfo(
                      key: ValueKey(
                        'poster_browse_collapsed_info_${widget.focusedItem!.card.id}',
                      ),
                      item: widget.focusedItem!,
                      logoRequest: widget.logoRequest,
                      secondaryLabel: widget.secondaryLabel,
                      metaWidgets: widget.metaWidgets,
                      compact: true,
                      collapsed: true,
                      onPlay: widget.onPlay,
                      onDetail: widget.onDetail,
                    ),
                  ),
                ),
              ),
      );
    }

    return PosterBrowseRowStatus(
      row: currentRow,
      onRetry: widget.onRetryCurrentRow,
    );
  }

  void _handleCollapseProgressChanged(double progress) {
    // 终点必须精确传递，否则极小的残余进度会让分类栏一直忽略点击。
    if (_collapseProgress == progress) return;
    setState(() => _collapseProgress = progress);
  }

  double _trackHeightFor({
    required double viewportHeight,
    required double topInset,
    required double bottomInset,
    required double selectorSpacing,
    required double collapseProgress,
  }) {
    final selectorExtent = (48 + selectorSpacing) * (1 - collapseProgress);
    return (viewportHeight - topInset - bottomInset - 48 - selectorExtent)
        .clamp(
          0.0,
          _maxTrackHeight + (DesktopEnvironment.isDesktopPlatform ? 24 : 0),
        )
        .toDouble();
  }

  Widget _buildAnimatedPrimaryMediaInfo(double viewportHeight) {
    final focusedItem = widget.focusedItem;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.bottomLeft,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      child: focusedItem == null
          ? const SizedBox.shrink(
              key: ValueKey('poster_browse_primary_info_empty'),
            )
          : PosterBrowseMediaInfo(
              key: ValueKey(
                'poster_browse_primary_info_${focusedItem.card.id}',
              ),
              item: focusedItem,
              logoRequest: widget.logoRequest,
              secondaryLabel: widget.secondaryLabel,
              metaWidgets: widget.metaWidgets,
              compact: viewportHeight < 900,
              stableLayout: true,
              onPlay: widget.onPlay,
              onDetail: widget.onDetail,
            ),
    );
  }

  void _handlePrimaryHorizontalDragEnd(DragEndDetails details, int itemCount) {
    final velocity =
        details.primaryVelocity ?? details.velocity.pixelsPerSecond.dx;
    final shouldMove =
        velocity.abs() > _horizontalVelocityThreshold ||
        _horizontalDragDistance.abs() >= _horizontalDistanceThreshold;
    if (!shouldMove) return;

    final moveForward = velocity.abs() > _horizontalVelocityThreshold
        ? velocity < 0
        : _horizontalDragDistance < 0;
    final focusedIndex = widget.focusedIndex.clamp(0, itemCount - 1);
    final targetIndex = (focusedIndex + (moveForward ? 1 : -1)).clamp(
      0,
      itemCount - 1,
    );
    if (targetIndex != focusedIndex) {
      widget.onSelectItem(targetIndex);
    }
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _BackButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: const Icon(Icons.arrow_back),
      color: Colors.white,
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.24),
      ),
    );
  }
}

class _RowSelector extends StatelessWidget {
  final List<PosterBrowseRow> rows;
  final int selectedRow;
  final void Function(int index) onSelectRow;

  const _RowSelector({
    required this.rows,
    required this.selectedRow,
    required this.onSelectRow,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 48,
      child: SingleChildScrollView(
        key: const ValueKey('poster_browse_row_selector_scroll'),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var index = 0; index < rows.length; index++) ...[
              if (index > 0) const SizedBox(width: 10),
              _RowChip(
                label: _rowLabel(AppLocalizations.of(context), rows[index]),
                selected: index == selectedRow,
                onTap: () => onSelectRow(index),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _rowLabel(AppLocalizations l10n, PosterBrowseRow row) {
    switch (row.kind) {
      case PosterBrowseRowKind.continueWatching:
        return l10n.posterBrowseRowContinue;
      case PosterBrowseRowKind.latest:
        return l10n.posterBrowseRowLatest;
      case PosterBrowseRowKind.catalog:
        return row.title;
      case PosterBrowseRowKind.catalogIndex:
        return l10n.posterBrowseRowCatalogs;
    }
  }
}

class _RowChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RowChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected
        ? theme.colorScheme.onPrimary
        : Colors.white.withValues(alpha: 0.78);
    final background = selected
        ? theme.colorScheme.primary.withValues(alpha: 0.92)
        : Colors.white.withValues(alpha: 0.12);

    return Semantics(
      button: true,
      selected: selected,
      child: SizedBox(
        height: 48,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.primary
                      : Colors.white.withValues(alpha: 0.14),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
