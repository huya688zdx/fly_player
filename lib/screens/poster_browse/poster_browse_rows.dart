import '../../media_backend/media_item_card.dart';

/// 大屏海报浏览页的一行分类。行标题由 UI 按 [kind] 取 l10n。
enum PosterBrowseRowKind { continueWatching, latest }

/// 大屏海报浏览页的一"行"。
class PosterBrowseRow {
  final PosterBrowseRowKind kind;
  final List<MediaItemCard> items;

  const PosterBrowseRow({required this.kind, required this.items});
}

/// 行组装纯函数：继续观看 → 最近添加；空行整行剔除，不留占位。
List<PosterBrowseRow> buildPosterBrowseRows({
  required List<MediaItemCard> continueWatching,
  required List<MediaItemCard> latestItems,
}) {
  return <PosterBrowseRow>[
    if (continueWatching.isNotEmpty)
      PosterBrowseRow(
        kind: PosterBrowseRowKind.continueWatching,
        items: continueWatching,
      ),
    if (latestItems.isNotEmpty)
      PosterBrowseRow(kind: PosterBrowseRowKind.latest, items: latestItems),
  ];
}
