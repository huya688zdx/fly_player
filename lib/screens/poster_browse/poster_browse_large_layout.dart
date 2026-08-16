import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../media_backend/media_image_request.dart';
import '../../media_backend/media_item_card.dart';
import 'poster_browse_display_item.dart';
import 'poster_browse_landscape_gesture_panel.dart';
import 'poster_browse_media_info.dart';
import 'poster_browse_row_status.dart';
import 'poster_browse_rows.dart';

class PosterBrowseLargeLayout extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final currentRow = _selectedRowOrNull(rows);
    final currentItems = currentRow == null
        ? const <PosterBrowseDisplayItem>[]
        : currentRow.items.map(displayItemOf).toList(growable: false);

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportHeight = constraints.maxHeight;
          final showMediaInfo = viewportHeight >= 600;
          final compressChrome = viewportHeight < 412;
          final verticalInset = compressChrome ? 8.0 : null;

          return Padding(
            padding: EdgeInsets.fromLTRB(
              28,
              verticalInset ?? 16,
              28,
              verticalInset ?? 22,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BackButton(onPressed: onBack),
                Expanded(
                  child: showMediaInfo
                      ? Padding(
                          padding: const EdgeInsets.only(
                            left: 36,
                            right: 36,
                            top: 24,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 560),
                              child: focusedItem == null
                                  ? const SizedBox.shrink()
                                  : PosterBrowseMediaInfo(
                                      item: focusedItem!,
                                      logoRequest: logoRequest,
                                      secondaryLabel: secondaryLabel,
                                      metaWidgets: metaWidgets,
                                      compact: viewportHeight < 900,
                                      onPlay: onPlay,
                                      onDetail: onDetail,
                                    ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                _RowSelector(
                  rows: rows,
                  selectedRow: selectedRow,
                  onSelectRow: onSelectRow,
                ),
                SizedBox(height: compressChrome ? 8 : 14),
                SizedBox(
                  height: 264,
                  child: _buildTrackArea(context, currentRow, currentItems),
                ),
              ],
            ),
          );
        },
      ),
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

  Widget _buildTrackArea(
    BuildContext context,
    PosterBrowseRow? currentRow,
    List<PosterBrowseDisplayItem> currentItems,
  ) {
    if (currentItems.isNotEmpty) {
      return PosterBrowseLandscapeGesturePanel(
        items: currentItems,
        focusedIndex: focusedIndex,
        showProgress: currentRow?.kind == PosterBrowseRowKind.continueWatching,
        imageOf: imageOf,
        secondaryLabelOf: secondaryLabelOf,
        onItemTap: onSelectItem,
        collapsedContent: focusedItem == null
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.fromLTRB(36, 0, 36, 4),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: PosterBrowseMediaInfo(
                      key: ValueKey(
                        'poster_browse_collapsed_info_${focusedItem!.card.id}',
                      ),
                      item: focusedItem!,
                      logoRequest: logoRequest,
                      secondaryLabel: secondaryLabel,
                      metaWidgets: metaWidgets,
                      compact: true,
                      collapsed: true,
                      onPlay: onPlay,
                      onDetail: onDetail,
                    ),
                  ),
                ),
              ),
      );
    }

    return PosterBrowseRowStatus(row: currentRow, onRetry: onRetryCurrentRow);
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
