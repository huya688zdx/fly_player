import '../../media_backend/media_backend.dart';
import '../../media_backend/media_item_card.dart';

class PosterBrowseCatalogSession {
  PosterBrowseCatalogSession({required this.backend, required this.itemLimit});

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
    late final Future<List<MediaItemCard>> request;
    request = backend
        .getCatalogPreviewItems(catalogId, limit: itemLimit)
        .then(
          (items) {
            final result = List<MediaItemCard>.unmodifiable(
              items.take(itemLimit),
            );
            if (_generation == generation) {
              _cache[key] = result;
              if (identical(_inFlight[key], request)) {
                _inFlight.remove(key);
              }
            }
            return result;
          },
          onError: (Object error, StackTrace stackTrace) {
            if (_generation == generation &&
                identical(_inFlight[key], request)) {
              _inFlight.remove(key);
            }
            return Future<List<MediaItemCard>>.error(error, stackTrace);
          },
        );
    _inFlight[key] = request;
    return request;
  }

  void clear() {
    _generation += 1;
    _cache.clear();
    _inFlight.clear();
  }
}
