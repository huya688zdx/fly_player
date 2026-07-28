import '../../api/feiniu_api.dart';
import '../../media_backend/media_backend.dart';
import '../../media_backend/media_backend_kind.dart';
import '../../media_backend/media_image_ref.dart';
import '../../media_backend/media_item_card.dart';
import '../../models/media_library_item.dart';
import '../../utils/swallowed_error_logger.dart';
import 'poster_browse_rows.dart';

/// 飞牛继续观看旁路（getPlayList 保留 ts/duration 富字段）→ 公共卡片。
///
/// 仅映射本页面（大屏海报浏览页）用到的字段，非全量搬运；全量映射见 `mapFeiniuItemCard`
/// （`lib/media_backend/feiniu/feiniu_media_mappers.dart`）。
MediaItemCard cardFromLibraryItem(MediaLibraryItem item) {
  return MediaItemCard(
    id: item.guid,
    title: item.title,
    secondaryTitle: item.tvTitle,
    type: item.type,
    seriesId: item.ancestorGuid,
    // item.poster 为空串时 MediaImageRef(url: '') 与 MediaImageRef.empty 语义等价
    // （见 MediaImageRef.isEmpty），故此处不必像 backdropImage 那样显式判空。
    primaryImage: MediaImageRef(url: item.poster),
    posters: item.posterList
        .map((p) => MediaImageRef(url: p))
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

/// 页面数据加载：继续观看与最近添加并行，单源失败该行隐藏；全部行为空视为整页失败（由页面判定）。
class PosterBrowseLoader {
  const PosterBrowseLoader();

  Future<List<PosterBrowseRow>> load({
    required MediaBackend backend,
    required FeiniuApi api,
    int rowItemLimit = 20,
  }) async {
    var continueWatching = const <MediaItemCard>[];
    var latest = const <MediaItemCard>[];
    await Future.wait<void>(<Future<void>>[
      () async {
        try {
          continueWatching = await _loadContinueWatching(backend, api);
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
          latest = await backend.getLatestItems(limit: rowItemLimit);
        } catch (error, stackTrace) {
          await logSwallowedError(
            action: 'poster browse load latest items',
            error: error,
            stackTrace: stackTrace,
            source: 'poster_browse_loader',
          );
        }
      }(),
    ]);

    return buildPosterBrowseRows(
      continueWatching: continueWatching.take(rowItemLimit).toList(),
      latestItems: latest.take(rowItemLimit).toList(),
    );
  }

  /// 数据层按后端能力选源（与首页 _loadContinueWatching 同款分流），UI 不判后端。
  Future<List<MediaItemCard>> _loadContinueWatching(
    MediaBackend backend,
    FeiniuApi api,
  ) async {
    if (backend.capabilities.kind == MediaBackendKind.feiniu) {
      final items = await api.getPlayList();
      return items.map(cardFromLibraryItem).toList(growable: false);
    }
    return backend.getContinueWatching();
  }
}
