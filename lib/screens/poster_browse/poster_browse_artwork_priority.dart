import '../../media_backend/media_item_card.dart';

/// 按循环轮播的可见优先级排列素材任务：中心、左邻、右邻，再向两侧展开。
///
/// 只改变请求顺序，不增加任务数量或并发度。
List<MediaItemCard> prioritizePosterBrowseArtworkItems({
  required List<MediaItemCard> items,
  int? centerIndex,
  int? limit,
}) {
  if (items.isEmpty || limit == 0) return const <MediaItemCard>[];

  final maxItems = limit == null || limit < 0 ? items.length : limit;
  final orderedIndices = <int>[];
  if (centerIndex == null) {
    orderedIndices.addAll(List<int>.generate(items.length, (index) => index));
  } else {
    final center = _positiveModulo(centerIndex, items.length);
    final seenIndices = <int>{};
    for (var distance = 0; seenIndices.length < items.length; distance += 1) {
      final candidates = distance == 0
          ? <int>[center]
          : <int>[
              _positiveModulo(center - distance, items.length),
              _positiveModulo(center + distance, items.length),
            ];
      for (final index in candidates) {
        if (seenIndices.add(index)) orderedIndices.add(index);
      }
    }
  }

  final seenIds = <String>{};
  final result = <MediaItemCard>[];
  for (final index in orderedIndices) {
    final item = items[index];
    final id = item.id.trim();
    if (id.isEmpty || !seenIds.add(id)) continue;
    result.add(item);
    if (result.length >= maxItems) break;
  }
  return result;
}

int _positiveModulo(int value, int length) {
  final remainder = value % length;
  return remainder < 0 ? remainder + length : remainder;
}
