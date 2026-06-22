import '../../api/emby_api.dart';
import '../detail/media_detail.dart';
import '../detail/media_episode_summary.dart';
import '../detail/media_season_summary.dart';
import '../filter/media_catalog_filter.dart';
import '../media_backend.dart';
import '../media_backend_capabilities.dart';
import '../media_backend_kind.dart';
import '../media_catalog.dart';
import '../media_item_card.dart';
import '../playback/media_playback.dart';
import '../playback/media_playback_resolution.dart';
import '../session/media_backend_connection.dart';
import 'emby_media_mappers.dart';

/// Emby 媒体后端适配器——**首页首光阶段**。
///
/// 只实现首页读取（媒体库 / 预览 / 继续观看）；详情 / 季集 / 搜索 / 筛选 / 播放入口尚未
/// 实现，一律 throw [UnsupportedError]（由 gate / 入口拦截，本阶段不在 Emby 态点开它们）。
/// 飞牛专属能力（下载 / FN Connect / 片头片尾）在 [capabilities] 中关闭。
class EmbyMediaBackend implements MediaBackend {
  EmbyMediaBackend({required this.api, required this.connection});

  final EmbyApi api;
  final MediaBackendConnection connection;

  static const String _cardFields =
      'PrimaryImageAspectRatio,Overview,PremiereDate';

  String get _serverUrl => connection.serverUrl;
  String get _userId => connection.userId;
  String get _token => connection.accessToken;

  @override
  MediaBackendCapabilities get capabilities => const MediaBackendCapabilities(
    kind: MediaBackendKind.emby,
    supportsDownloadTasks: false,
    supportsFnConnect: false,
    supportsIntroOutroConfig: false,
  );

  @override
  Future<List<MediaCatalog>> getCatalogs() async {
    final views = await api.getUserViews(
      serverUrl: _serverUrl,
      userId: _userId,
      accessToken: _token,
    );
    return views
        .map((v) => mapEmbyView(v, serverUrl: _serverUrl, token: _token))
        .toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>> getHomeSummary() async =>
      const <String, dynamic>{};

  @override
  Future<List<MediaItemCard>> getContinueWatching({
    bool forceRefresh = false,
  }) async {
    final items = await api.getItems(
      serverUrl: _serverUrl,
      userId: _userId,
      accessToken: _token,
      isResumable: true,
      recursive: true,
      limit: 20,
      sortBy: 'DatePlayed',
      sortOrder: 'Descending',
      fields: _cardFields,
    );
    return items
        .map((e) => mapEmbyItemCard(e, serverUrl: _serverUrl, token: _token))
        .toList(growable: false);
  }

  @override
  Future<List<MediaItemCard>> getCatalogPreviewItems(
    String catalogId, {
    int page = 1,
    int limit = 30,
  }) async {
    final items = await api.getItems(
      serverUrl: _serverUrl,
      userId: _userId,
      accessToken: _token,
      parentId: catalogId,
      limit: limit,
      fields: _cardFields,
    );
    return items
        .map((e) => mapEmbyItemCard(e, serverUrl: _serverUrl, token: _token))
        .toList(growable: false);
  }

  @override
  Future<List<MediaItemCard>> searchItems(String query) =>
      _unsupported('searchItems');

  @override
  Future<MediaCatalogFilterSchema> getCatalogFilterSchema(String catalogId) =>
      _unsupported('getCatalogFilterSchema');

  @override
  Future<MediaItemCardPage> queryCatalogItems(MediaCatalogQuery query) =>
      _unsupported('queryCatalogItems');

  @override
  Future<MediaDetail> getItemDetail(String itemId) =>
      _unsupported('getItemDetail');

  @override
  Future<List<MediaSeasonSummary>> getItemSeasons(String seriesId) =>
      _unsupported('getItemSeasons');

  @override
  Future<List<MediaEpisodeSummary>> getSeasonEpisodes(String seasonId) =>
      _unsupported('getSeasonEpisodes');

  @override
  Future<MediaPlaybackResolution> getPlayback(MediaPlaybackRequest request) =>
      _unsupported('getPlayback');

  Future<Never> _unsupported(String method) async {
    throw UnsupportedError('EmbyMediaBackend.$method 未实现（Emby 首页首光阶段）');
  }
}
