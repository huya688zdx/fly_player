import '../../media_backend/media_catalog.dart';
import '../../media_backend/media_item_card.dart';

/// 大屏海报浏览页的一行分类。行标题由 UI 按 [kind] 取 l10n（catalog 行用 [catalogTitle]）。
enum PosterBrowseRowKind { continueWatching, latest, catalog }

/// 大屏海报浏览页的一"行"。
class PosterBrowseRow {
  final PosterBrowseRowKind kind;
  final String catalogId;
  final String catalogTitle;
  final List<MediaItemCard> items;

  const PosterBrowseRow({
    required this.kind,
    required this.items,
    this.catalogId = '',
    this.catalogTitle = '',
  });
}

/// 行组装纯函数：继续观看 → 最近添加 → 各媒体库；空行整行剔除，不留占位。
List<PosterBrowseRow> buildPosterBrowseRows({
  required List<MediaItemCard> continueWatching,
  required List<MediaItemCard> latestItems,
  required List<MediaCatalog> catalogs,
  required Map<String, List<MediaItemCard>> catalogItems,
}) {
  final rows = <PosterBrowseRow>[
    if (continueWatching.isNotEmpty)
      PosterBrowseRow(
        kind: PosterBrowseRowKind.continueWatching,
        items: continueWatching,
      ),
    if (latestItems.isNotEmpty)
      PosterBrowseRow(kind: PosterBrowseRowKind.latest, items: latestItems),
  ];
  for (final catalog in catalogs) {
    final items = catalogItems[catalog.id] ?? const <MediaItemCard>[];
    if (items.isEmpty) continue;
    rows.add(
      PosterBrowseRow(
        kind: PosterBrowseRowKind.catalog,
        catalogId: catalog.id,
        catalogTitle: catalog.title,
        items: items,
      ),
    );
  }
  return rows;
}
