import 'poster_browse_rows.dart';

enum PosterBrowseScreenBody { loading, error, shell }

class PosterBrowseRowSelectionDecision {
  final bool selectImmediately;
  final bool loadCatalog;
  final bool settleItem;
  final bool invalidateFocus;
  final bool reloadCatalogs;

  const PosterBrowseRowSelectionDecision({
    required this.selectImmediately,
    required this.loadCatalog,
    required this.settleItem,
    required this.invalidateFocus,
    required this.reloadCatalogs,
  });
}

class PosterBrowseScreenPolicy {
  const PosterBrowseScreenPolicy._();

  static PosterBrowseScreenBody bodyFor({
    required bool loading,
    required bool hasRows,
    required bool hasFocusedItem,
  }) {
    if (loading) return PosterBrowseScreenBody.loading;
    if (!hasRows) return PosterBrowseScreenBody.error;
    return PosterBrowseScreenBody.shell;
  }

  static PosterBrowseRowSelectionDecision selectionFor(PosterBrowseRow row) {
    final hasItems = row.items.isNotEmpty;
    final isCatalogIndex = row.kind == PosterBrowseRowKind.catalogIndex;
    return PosterBrowseRowSelectionDecision(
      selectImmediately: true,
      loadCatalog:
          !hasItems &&
          row.kind == PosterBrowseRowKind.catalog &&
          row.loadState != PosterBrowseRowLoadState.loaded,
      settleItem: hasItems,
      invalidateFocus: !hasItems,
      reloadCatalogs:
          isCatalogIndex && row.loadState == PosterBrowseRowLoadState.failed,
    );
  }

  static T? settledItemFor<T>({
    required String? settledItemId,
    required String? focusedItemId,
    required Map<String, T> displayById,
    required T? focusedItem,
  }) {
    if (settledItemId == null || settledItemId != focusedItemId) {
      return focusedItem;
    }
    return displayById[settledItemId] ?? focusedItem;
  }

  static bool shouldSelectReloadedCatalog({
    required int catalogIndexRow,
    required int currentSelectedRow,
  }) {
    return catalogIndexRow == currentSelectedRow;
  }
}
