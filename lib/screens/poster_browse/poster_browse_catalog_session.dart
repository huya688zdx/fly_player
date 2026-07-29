import 'dart:async';

import '../../media_backend/media_backend.dart';
import '../../media_backend/media_item_card.dart';

class PosterBrowseCatalogSession {
  PosterBrowseCatalogSession({required this.backend, required int itemLimit})
    : itemLimit = RangeError.checkNotNegative(itemLimit, 'itemLimit');

  final MediaBackend backend;
  final int itemLimit;
  final Map<String, List<MediaItemCard>> _cache =
      <String, List<MediaItemCard>>{};
  final Map<String, Future<List<MediaItemCard>>> _inFlight =
      <String, Future<List<MediaItemCard>>>{};
  int _generation = 0;

  Future<List<MediaItemCard>> load(String catalogId) {
    final key = catalogId.trim();
    final cached = _cache[key];
    if (cached != null) {
      return Future<List<MediaItemCard>>.value(cached);
    }
    final inFlight = _inFlight[key];
    if (inFlight != null) {
      return inFlight;
    }

    final generation = _generation;
    final completer = Completer<List<MediaItemCard>>();
    final request = completer.future;
    _inFlight[key] = request;
    _loadRequest(
      catalogId: catalogId,
      key: key,
      generation: generation,
      request: request,
    ).then(completer.complete, onError: completer.completeError);
    return request;
  }

  Future<List<MediaItemCard>> _loadRequest({
    required String catalogId,
    required String key,
    required int generation,
    required Future<List<MediaItemCard>> request,
  }) async {
    try {
      final items = await backend.getCatalogPreviewItems(
        catalogId,
        limit: itemLimit,
      );
      final result = List<MediaItemCard>.unmodifiable(
        items.take(itemLimit).toList(),
      );
      if (_generation == generation) {
        _cache[key] = result;
      }
      return result;
    } finally {
      if (_generation == generation && identical(_inFlight[key], request)) {
        _inFlight.remove(key);
      }
    }
  }

  void clear() {
    _generation += 1;
    _cache.clear();
    _inFlight.clear();
  }
}
