import '../../api/feiniu_api.dart';
import '../../media_backend/media_backend.dart';
import '../../media_backend/media_backend_kind.dart';
import '../../media_backend/media_catalog.dart';
import '../../media_backend/media_image_ref.dart';
import '../../media_backend/media_item_card.dart';
import '../../models/media_library_item.dart';
import '../../utils/swallowed_error_logger.dart';
import 'poster_browse_rows.dart';

/// 将飞牛播放列表项映射为大屏浏览所需的卡片，并保留续播相关富字段。
MediaItemCard cardFromLibraryItem(MediaLibraryItem item) {
  final tvTitle = item.tvTitle.trim();
  final ancestorName = item.ancestorName.trim();
  final cleanSeriesTitle = tvTitle.isNotEmpty && tvTitle != ancestorName
      ? tvTitle
      : '';
  return MediaItemCard(
    id: item.guid,
    title: item.title,
    secondaryTitle: cleanSeriesTitle,
    type: item.type,
    seriesId: '',
    primaryImage: MediaImageRef(url: item.poster),
    posters: item.posterList
        .map((poster) => MediaImageRef(url: poster))
        .toList(growable: false),
    backdropImage: item.backdropUrl.trim().isNotEmpty
        ? MediaImageRef(url: item.backdropUrl)
        : MediaImageRef.empty,
    durationSeconds: item.duration,
    watched: item.watched > 0,
    resumePositionSeconds: item.ts > 0 ? item.ts : item.watchedTs,
    rating: item.voteAverage,
    releaseDate: item.releaseDate,
    overview: item.overview,
    seasonNumber: item.seasonNumber,
    episodeNumber: item.episodeNumber,
    numberOfSeasons: item.numberOfSeasons,
    numberOfEpisodes: item.numberOfEpisodes,
    localNumberOfSeasons: item.localNumberOfSeasons,
    localNumberOfEpisodes: item.localNumberOfEpisodes,
    posterWidth: item.posterWidth,
    posterHeight: item.posterHeight,
    resolutions: item.resolutions,
  );
}

/// 并行加载继续观看与全部目录；任一数据源失败都不会阻断另一数据源。
class PosterBrowseLoader {
  const PosterBrowseLoader();

  Future<List<PosterBrowseRow>> load({
    required MediaBackend backend,
    required FeiniuApi api,
    int rowItemLimit = 20,
  }) async {
    final isFeiniu = backend.capabilities.kind == MediaBackendKind.feiniu;
    var continueWatching = const <MediaItemCard>[];
    var catalogs = const <MediaCatalog>[];
    var catalogsLoadFailed = false;

    await Future.wait<void>(<Future<void>>[
      () async {
        try {
          continueWatching = await _loadContinueWatching(
            backend,
            api,
            isFeiniu: isFeiniu,
          );
        } catch (error, stackTrace) {
          await logSwallowedError(
            action: 'poster browse load continue watching',
            error: error,
            stackTrace: stackTrace,
            source: 'poster_browse_loader',
          );
        }
      }(),
      () async {
        try {
          catalogs = await backend.getCatalogs();
        } catch (error, stackTrace) {
          catalogsLoadFailed = true;
          await logSwallowedError(
            action: 'poster browse load catalogs',
            error: error,
            stackTrace: stackTrace,
            source: 'poster_browse_loader',
          );
        }
      }(),
    ]);

    return buildPosterBrowseRows(
      continueWatching: continueWatching.take(rowItemLimit).toList(),
      catalogs: catalogs,
      catalogsLoadFailed: catalogsLoadFailed,
    );
  }

  Future<List<MediaCatalog>> loadCatalogs(MediaBackend backend) {
    return backend.getCatalogs();
  }

  Future<List<MediaItemCard>> _loadContinueWatching(
    MediaBackend backend,
    FeiniuApi api, {
    required bool isFeiniu,
  }) async {
    if (isFeiniu) {
      final items = await api.getPlayList();
      return items.map(cardFromLibraryItem).toList(growable: false);
    }
    return backend.getContinueWatching();
  }
}
