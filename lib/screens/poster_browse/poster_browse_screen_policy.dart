import 'poster_browse_rows.dart';

enum PosterBrowseScreenBody { loading, error, shell }

class PosterBrowseRowSelectionDecision {
  final bool selectImmediately;
  final bool loadCatalog;
  final bool settleItem;

  const PosterBrowseRowSelectionDecision({
    required this.selectImmediately,
    required this.loadCatalog,
    required this.settleItem,
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
    return PosterBrowseRowSelectionDecision(
      selectImmediately: true,
      loadCatalog:
          !hasItems &&
          row.kind == PosterBrowseRowKind.catalog &&
          row.loadState != PosterBrowseRowLoadState.loaded,
      settleItem: hasItems,
    );
  }
}
