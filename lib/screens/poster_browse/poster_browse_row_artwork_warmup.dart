import 'dart:async';
import 'dart:math' as math;

import '../../media_backend/media_item_card.dart';
import 'poster_browse_artwork_enricher.dart';

typedef PosterBrowseArtworkLoad =
    Future<PosterBrowseEnrichment> Function(MediaItemCard card);
typedef PosterBrowseArtworkLoaded =
    void Function(MediaItemCard card, PosterBrowseEnrichment enrichment);
typedef PosterBrowseArtworkLoadError =
    void Function(MediaItemCard card, Object error, StackTrace stackTrace);

/// 继续观看整行的后台素材补全队列。
///
/// 只保留少量并发请求，避免一次为整行条目同时拉取详情；每项完成后立即交给页面提交，
/// 因此不需要用户点击卡片才能看到剧集/电影的竖版主海报。
class PosterBrowseRowArtworkWarmup {
  final int maxConcurrent;

  const PosterBrowseRowArtworkWarmup({this.maxConcurrent = 2})
    : assert(maxConcurrent > 0);

  Future<void> run({
    required List<MediaItemCard> items,
    required PosterBrowseArtworkLoad load,
    required PosterBrowseArtworkLoaded onLoaded,
    required bool Function() isActive,
    PosterBrowseArtworkLoadError? onError,
  }) async {
    final seen = <String>{};
    final queue = <MediaItemCard>[
      for (final item in items)
        if (seen.add(item.id.trim())) item,
    ];
    if (queue.isEmpty || !isActive()) return;

    var nextIndex = 0;
    Future<void> worker() async {
      while (isActive()) {
        if (nextIndex >= queue.length) return;
        final card = queue[nextIndex];
        nextIndex += 1;
        try {
          final enrichment = await load(card);
          if (!isActive()) return;
          onLoaded(card, enrichment);
        } catch (error, stackTrace) {
          if (!isActive()) return;
          onError?.call(card, error, stackTrace);
        }
      }
    }

    final workerCount = math.min(maxConcurrent, queue.length);
    await Future.wait<void>(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );
  }
}
