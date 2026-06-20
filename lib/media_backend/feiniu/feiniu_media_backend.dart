import '../../api/feiniu_api.dart';
import '../../api/person_list_request.dart';
import '../../models/person_credit.dart';
import '../detail/media_detail.dart';
import '../detail/media_episode_summary.dart';
import '../detail/media_season_summary.dart';
import '../filter/media_catalog_filter.dart';
import '../media_backend.dart';
import '../media_backend_capabilities.dart';
import '../media_catalog.dart';
import '../media_item_card.dart';
import 'feiniu_detail_mappers.dart';
import 'feiniu_media_mappers.dart';

/// 飞牛后端适配器：内部调用现有 [FeiniuApi]，把飞牛模型映射为公共模型。
///
/// 第一阶段不改变数据来源，只改变调用边界——首页等页面通过 [MediaBackend]
/// 间接访问飞牛，飞牛表现必须与迁移前一致。
class FeiniuMediaBackend implements MediaBackend {
  final FeiniuApi api;

  const FeiniuMediaBackend(this.api);

  @override
  MediaBackendCapabilities get capabilities =>
      const MediaBackendCapabilities.feiniu();

  @override
  Future<List<MediaCatalog>> getCatalogs() async {
    final items = await api.getMediaList();
    return items.map(mapFeiniuCatalog).toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>> getHomeSummary() => api.getMediaSummary();

  @override
  Future<List<MediaItemCard>> getContinueWatching({
    bool forceRefresh = false,
  }) async {
    final items = await api.getPlayList(forceRefresh: forceRefresh);
    return items.map(mapFeiniuItemCard).toList(growable: false);
  }

  @override
  Future<List<MediaItemCard>> getCatalogPreviewItems(
    String catalogId, {
    int page = 1,
    int limit = 30,
  }) async {
    final items = await api.getItemsByCategoryGuid(
      catalogId,
      page: page,
      limit: limit,
    );
    return items.map(mapFeiniuItemCard).toList(growable: false);
  }

  @override
  Future<List<MediaItemCard>> searchItems(String query) async {
    final items = await api.searchList(query);
    return items.map(mapFeiniuItemCard).toList(growable: false);
  }

  @override
  Future<MediaCatalogFilterSchema> getCatalogFilterSchema(
    String catalogId,
  ) async {
    final hasAncestor = catalogId.trim().isNotEmpty;
    final tagOptions = await api.getTagList(
      ancestorGuid: hasAncestor ? catalogId : '',
      isFavorite: 0,
    );
    final genresMap = await api.getTagGenresMap(lan: 'zh-CN');
    final regionNames = await api.getTagIso3166Map(lan: 'zh-CN');
    return mapFeiniuFilterSchema(
      tagOptions: tagOptions,
      genresMap: genresMap,
      regionNames: regionNames,
    );
  }

  @override
  Future<MediaItemCardPage> queryCatalogItems(MediaCatalogQuery query) async {
    final request = mapMediaQueryToItemListRequest(query);
    final page = await api.getItemsPageByRequest(request);
    return MediaItemCardPage(
      items: page.items.map(mapFeiniuItemCard).toList(growable: false),
      total: page.total,
    );
  }

  /// 演职员分页参数，复刻详情页 data loader 的取数口径。
  static const PersonListRequest _creditsRequest = PersonListRequest(
    page: 1,
    pageSize: 200,
  );

  @override
  Future<MediaDetail> getItemDetail(String itemId) async {
    final info = await api.getPlayInfo(itemId);
    final rawDetail = await api.getItemDetail(itemId);
    final imdbId = extractFeiniuImdbId(rawDetail);
    var credits = const <PersonCredit>[];
    try {
      credits = await api.getPersonList(itemId, request: _creditsRequest);
    } catch (_) {
      // 演职员失败不阻断详情展示（复刻详情页 best-effort 语义）。
    }
    // 题材 / 地区字典 best-effort：失败回空 map，详情仍可看（题材退化为原始 id），
    // 复刻旧 play_detail_page 的 `.catchError((_) => const {})` 降级，避免字典请求
    // 失败让整个详情打不开。
    final genresMap = await api
        .getTagGenresMap(lan: 'zh-CN')
        .catchError((_) => const <int, String>{});
    final regionNames = await api
        .getTagIso3166Map(lan: 'zh-CN')
        .catchError((_) => const <String, String>{});
    return mapFeiniuItemDetail(
      info,
      genresMap: genresMap,
      regionNames: regionNames,
      credits: credits,
      imdbId: imdbId,
    );
  }

  @override
  Future<List<MediaSeasonSummary>> getItemSeasons(String seriesId) async {
    final seasons = await api.getSeasonList(seriesId);
    return seasons.map(mapFeiniuSeason).toList(growable: false);
  }

  @override
  Future<List<MediaEpisodeSummary>> getSeasonEpisodes(String seasonId) async {
    final episodes = await api.getEpisodeList(seasonId);
    return episodes.map(mapFeiniuEpisode).toList(growable: false);
  }
}
