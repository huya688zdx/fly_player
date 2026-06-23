import '../../api/emby_api.dart';
import '../detail/media_detail.dart';
import '../detail/media_episode_summary.dart';
import '../detail/media_season_summary.dart';
import '../detail/media_source_info.dart';
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

/// Emby 媒体后端适配器——**首页 + 详情展示首光阶段**。
///
/// 已实现首页读取（媒体库 / 预览 / 继续观看）、单条目详情展示（[getItemDetail]）、
/// 季集浏览与分类 / 媒体库列表（[queryCatalogItems] + [getCatalogFilterSchema]）；
/// 搜索 / 播放入口尚未实现，一律 throw [UnsupportedError]（由入口拦截，本阶段不在
/// Emby 态点开它们）。详情只承载展示信息，不含播放接线。
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
  Future<Map<String, dynamic>> getHomeSummary() async {
    // Emby 无专用计数端点；用 /Items 的 TotalRecordCount（Limit=0 不拉条目体）按类型并行取数。
    // total=电影+电视剧（对齐“全部影视”）；other 首光阶段恒 0（尚无非影视计数口径）。
    final counts = await Future.wait(<Future<int>>[
      api.getItemCount(
        serverUrl: _serverUrl,
        userId: _userId,
        accessToken: _token,
        includeItemTypes: 'Movie',
      ),
      api.getItemCount(
        serverUrl: _serverUrl,
        userId: _userId,
        accessToken: _token,
        includeItemTypes: 'Series',
      ),
      api.getItemCount(
        serverUrl: _serverUrl,
        userId: _userId,
        accessToken: _token,
        includeItemTypes: 'Movie,Series',
        favoritesOnly: true,
      ),
    ]);
    final movie = counts[0];
    final tv = counts[1];
    final favorite = counts[2];
    return <String, dynamic>{
      'total': movie + tv,
      'movie': movie,
      'tv': tv,
      'favorite': favorite,
      'other': 0,
    };
  }

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
    // Recursive + IncludeItemTypes：把库下的文件夹/合集拍平，直接出影片/剧集本身
    // （否则首页预览会显示无封面的中间文件夹，而非真正的条目）。
    final items = await api.getItems(
      serverUrl: _serverUrl,
      userId: _userId,
      accessToken: _token,
      parentId: catalogId,
      limit: limit,
      recursive: true,
      includeItemTypes: 'Movie,Series',
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
  Future<MediaCatalogFilterSchema> getCatalogFilterSchema(
    String catalogId,
  ) async {
    // Emby 列表页筛选维度：题材（库内真实题材，名字即显示名，用 plain）。排序字段沿用
    // 中立四列（显示名由 UI l10n 给，不下发文案）。地区 / 年代 / 清晰度等飞牛维度 Emby
    // 无简单查询口径，本阶段不开。题材取数失败（如旧服务器）时退化为仅排序、不报错。
    var genreOptions = const <MediaFilterOption>[];
    try {
      final genres = await api.getGenres(
        serverUrl: _serverUrl,
        userId: _userId,
        accessToken: _token,
        parentId: catalogId,
        includeItemTypes: 'Movie,Series',
      );
      genreOptions = genres
          .map((g) => (g['Name'] ?? '').toString().trim())
          .where((name) => name.isNotEmpty)
          .map((name) => MediaFilterOption(value: name, label: name))
          .toList(growable: false);
    } catch (_) {}
    return MediaCatalogFilterSchema(
      dimensions: <MediaFilterDimension>[
        if (genreOptions.isNotEmpty)
          MediaFilterDimension(
            key: 'genres',
            kind: MediaFilterDimensionKind.plain,
            options: genreOptions,
          ),
      ],
      sortOptions: const <MediaSortOption>[
        MediaSortOption(field: 'create_time'),
        MediaSortOption(field: 'release_date'),
        MediaSortOption(field: 'title'),
        MediaSortOption(field: 'vote_average'),
      ],
    );
  }

  @override
  Future<MediaItemCardPage> queryCatalogItems(MediaCatalogQuery query) async {
    final page = await api.getItemPage(
      serverUrl: _serverUrl,
      userId: _userId,
      accessToken: _token,
      parentId: query.catalogId,
      startIndex: (query.page - 1) * query.pageSize,
      limit: query.pageSize,
      recursive: true,
      includeItemTypes: _includeItemTypesFor(query.selection['type']),
      genres: (query.selection['genres'] ?? const <String>[]).join('|'),
      sortBy: _sortFieldFor(query.sortField),
      sortOrder: query.sortType.trim().toUpperCase() == 'ASC'
          ? 'Ascending'
          : 'Descending',
      fields: _cardFields,
    );
    return MediaItemCardPage(
      items: page.items
          .map((e) => mapEmbyItemCard(e, serverUrl: _serverUrl, token: _token))
          .toList(growable: false),
      total: page.totalRecordCount,
    );
  }

  /// 中立类型标签 → Emby `IncludeItemTypes`。空 / 全部影视 → `Movie,Series`；`TV` → `Series`；
  /// 未知标签（飞牛「其他」的 `Directory`/`Video`）透传，Emby 无此类型故返回空（口径对齐计数 0）。
  static String _includeItemTypesFor(List<String>? types) {
    if (types == null || types.isEmpty) return 'Movie,Series';
    final mapped = <String>{};
    for (final raw in types) {
      final key = raw.trim().toLowerCase();
      if (key == 'movie') {
        mapped.add('Movie');
      } else if (key == 'tv' || key == 'series') {
        mapped.add('Series');
      } else if (raw.trim().isNotEmpty) {
        mapped.add(raw.trim());
      }
    }
    return mapped.isEmpty ? 'Movie,Series' : mapped.join(',');
  }

  /// 中立排序字段 → Emby `SortBy`。
  static String _sortFieldFor(String field) {
    switch (field.trim()) {
      case 'release_date':
        return 'PremiereDate';
      case 'title':
        return 'SortName';
      case 'vote_average':
        return 'CommunityRating';
      case 'create_time':
      default:
        return 'DateCreated';
    }
  }

  @override
  Future<MediaDetail> getItemDetail(String itemId) async {
    final item = await api.getItem(
      serverUrl: _serverUrl,
      userId: _userId,
      accessToken: _token,
      itemId: itemId,
    );
    return mapEmbyItemDetail(item, serverUrl: _serverUrl, token: _token);
  }

  @override
  Future<MediaSourceInfo?> getItemSourceInfo(String itemId) async {
    // 单独取 MediaSources（含 Path/Size/MediaStreams）+ DateCreated；与 getItemDetail
    // 的展示字段拉取分开，避免详情字段里塞源信息。
    final item = await api.getItem(
      serverUrl: _serverUrl,
      userId: _userId,
      accessToken: _token,
      itemId: itemId,
      fields: 'MediaSources,DateCreated',
    );
    final info = mapEmbySourceInfo(item);
    return info.isEmpty ? null : info;
  }

  @override
  Future<List<MediaSeasonSummary>> getItemSeasons(String seriesId) async {
    final seasons = await api.getSeasons(
      serverUrl: _serverUrl,
      userId: _userId,
      accessToken: _token,
      seriesId: seriesId,
    );
    return seasons
        .map((s) => mapEmbySeason(s, serverUrl: _serverUrl, token: _token))
        .toList(growable: false);
  }

  @override
  Future<List<MediaEpisodeSummary>> getSeasonEpisodes(String seasonId) async {
    // 季是集的父级，故按 ParentId=季 取该季选集（契合只给 seasonId 的接口签名，
    // 无需 seriesId，也省一次往返）。Emby 默认按 IndexNumber 返回子项，故不强制 SortBy。
    final episodes = await api.getItems(
      serverUrl: _serverUrl,
      userId: _userId,
      accessToken: _token,
      parentId: seasonId,
      includeItemTypes: 'Episode',
      fields: 'Overview',
    );
    return episodes
        .map((e) => mapEmbyEpisode(e, serverUrl: _serverUrl, token: _token))
        .toList(growable: false);
  }

  @override
  Future<MediaPlaybackResolution> getPlayback(MediaPlaybackRequest request) =>
      _unsupported('getPlayback');

  Future<Never> _unsupported(String method) async {
    throw UnsupportedError('EmbyMediaBackend.$method 未实现（Emby 首页首光阶段）');
  }
}
