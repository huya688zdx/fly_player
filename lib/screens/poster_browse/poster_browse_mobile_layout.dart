import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../media_backend/media_image_request.dart';
import '../../media_backend/media_item_card.dart';
import 'poster_browse_arc_carousel.dart';
import 'poster_browse_display_item.dart';
import 'poster_browse_media_info.dart';
import 'poster_browse_rows.dart';

class PosterBrowseMobileLayout extends StatelessWidget {
  final List<PosterBrowseRow> rows;
  final PosterBrowseDisplayItem Function(MediaItemCard card) displayItemOf;
  final int selectedRow;
  final int focusedIndex;
  final PosterBrowseDisplayItem focusedItem;
  final MediaImageRequest logoRequest;
  final String secondaryLabel;
  final List<Widget> metaWidgets;
  final MediaImageRequest Function(PosterBrowseDisplayItem item) imageOf;
  final String Function(PosterBrowseDisplayItem item) secondaryLabelOf;
  final void Function(int index) onSelectRow;
  final void Function(int index) onSelectItem;
  final void Function(int index) onCenteredTap;
  final VoidCallback onPlay;
  final VoidCallback onDetail;
  final VoidCallback onBack;

  const PosterBrowseMobileLayout({
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
    required this.onCenteredTap,
    required this.onPlay,
    required this.onDetail,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final visibleRows = rows.take(2).toList(growable: false);
    final currentRow = _selectedRowOrNull(visibleRows);
    final currentItems = currentRow == null
        ? const <PosterBrowseDisplayItem>[]
        : currentRow.items.map(displayItemOf).toList(growable: false);
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => _buildForSize(
          size: constraints.biggest,
          visibleRows: visibleRows,
          currentRow: currentRow,
          currentItems: currentItems,
        ),
      ),
    );
  }

  Widget _buildForSize({
    required Size size,
    required List<PosterBrowseRow> visibleRows,
    required PosterBrowseRow? currentRow,
    required List<PosterBrowseDisplayItem> currentItems,
  }) {
    final compactHeight = size.height < 520;
    final isLandscape = size.width > size.height;
    final carouselHeight = compactHeight ? 236.0 : 258.0;
    final infoTop = compactHeight ? 54.0 : 92.0;
    final infoMaxWidth = isLandscape
        ? (size.width * 0.44).clamp(300.0, 390.0).toDouble()
        : size.width.clamp(0.0, 390.0).toDouble();
    final carouselPanel = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, compactHeight ? 6 : 14),
          child: _RowSelector(
            rows: visibleRows,
            selectedRow: selectedRow,
            onSelectRow: onSelectRow,
          ),
        ),
        currentItems.isEmpty
            ? const SizedBox.shrink()
            : SizedBox(
                key: const ValueKey('poster_browse_mobile_carousel'),
                height: carouselHeight,
                child: PosterBrowseArcCarousel(
                  items: currentItems,
                  initialIndex: focusedIndex,
                  showProgress:
                      currentRow?.kind == PosterBrowseRowKind.continueWatching,
                  imageOf: imageOf,
                  secondaryLabelOf: secondaryLabelOf,
                  onSettled: onSelectItem,
                  onCenteredTap: onCenteredTap,
                ),
              ),
      ],
    );

    return Stack(
      children: [
        Positioned(left: 8, top: 6, child: _BackButton(onPressed: onBack)),
        Positioned(
          left: 24,
          right: 24,
          top: infoTop,
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: infoMaxWidth),
              child: PosterBrowseMediaInfo(
                item: focusedItem,
                logoRequest: logoRequest,
                secondaryLabel: secondaryLabel,
                metaWidgets: metaWidgets,
                compact: true,
                onPlay: onPlay,
                onDetail: onDetail,
              ),
            ),
          ),
        ),
        if (isLandscape)
          Positioned(
            left: infoMaxWidth + 48,
            right: 0,
            top: 0,
            bottom: 0,
            child: carouselPanel,
          )
        else
          carouselPanel,
      ],
    );
  }

  PosterBrowseRow? _selectedRowOrNull(List<PosterBrowseRow> visibleRows) {
    if (visibleRows.isEmpty) {
      return null;
    }
    if (selectedRow < 0 || selectedRow >= visibleRows.length) {
      return visibleRows.first;
    }
    return visibleRows[selectedRow];
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
    if (rows.length < 2) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 18,
      runSpacing: 8,
      children: [
        for (var index = 0; index < rows.length; index++)
          _RowButton(
            label: _rowLabel(AppLocalizations.of(context), rows[index]),
            selected: index == selectedRow,
            onTap: () => onSelectRow(index),
          ),
      ],
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
    }
  }
}

class _RowButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RowButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Text(
          label,
          style: theme.textTheme.titleMedium?.copyWith(
            color: selected ? Colors.white : Colors.white54,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
