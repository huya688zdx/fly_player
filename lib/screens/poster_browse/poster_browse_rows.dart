import '../../media_backend/media_catalog.dart';
import '../../media_backend/media_item_card.dart';

/// 大屏海报浏览页的一行分类；行标题由 UI 按 [kind] 或目录元数据处理。
enum PosterBrowseRowKind { continueWatching, latest, catalog }

/// 目录行的按需加载状态。
enum PosterBrowseRowLoadState { idle, loading, loaded, failed }

/// 大屏海报浏览页的一行。
class PosterBrowseRow {
  final PosterBrowseRowKind kind;
  final String title;
  final String catalogId;
  final List<MediaItemCard> items;
  final PosterBrowseRowLoadState loadState;

  const PosterBrowseRow({
    required this.kind,
    this.title = '',
    this.catalogId = '',
    required this.items,
    this.loadState = PosterBrowseRowLoadState.loaded,
  });

  PosterBrowseRow copyWith({
    List<MediaItemCard>? items,
    PosterBrowseRowLoadState? loadState,
  }) {
    return PosterBrowseRow(
      kind: kind,
      title: title,
      catalogId: catalogId,
      items: items ?? this.items,
      loadState: loadState ?? this.loadState,
    );
  }
}

/// 行组装纯函数：继续观看在前，随后保留后端提供的全部目录元数据。
List<PosterBrowseRow> buildPosterBrowseRows({
  required List<MediaItemCard> continueWatching,
  required List<MediaCatalog> catalogs,
}) {
  return <PosterBrowseRow>[
    if (continueWatching.isNotEmpty)
      PosterBrowseRow(
        kind: PosterBrowseRowKind.continueWatching,
        items: continueWatching,
      ),
    for (final catalog in catalogs)
      PosterBrowseRow(
        kind: PosterBrowseRowKind.catalog,
        title: catalog.title,
        catalogId: catalog.id,
        items: const <MediaItemCard>[],
        loadState: PosterBrowseRowLoadState.idle,
      ),
  ];
}
