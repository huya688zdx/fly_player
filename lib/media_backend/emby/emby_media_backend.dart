import 'dart:io';

import '../../api/emby_api.dart';
import '../../utils/nas_image_headers.dart';
import '../../utils/playback_resume_position_resolver.dart';
import '../detail/media_detail.dart';
import '../detail/media_episode_summary.dart';
import '../detail/media_season_summary.dart';
import '../detail/media_source_info.dart';
import '../detail/media_source_version.dart';
import '../filter/media_catalog_filter.dart';
import '../media_backend.dart';
import '../media_backend_capabilities.dart';
import '../media_backend_kind.dart';
import '../media_catalog.dart';
import '../media_item_card.dart';
import '../playback/media_playback.dart';
import '../playback/media_playback_resolution.dart';
import '../playback/media_playback_selectors.dart';
import '../session/media_backend_connection.dart';
import 'emby_media_mappers.dart';
import 'emby_playback_context.dart';
import 'emby_playback_mappers.dart';

/// Emby 媒体后端适配器——**首页 + 详情展示首光阶段**。
///
/// 已实现首页读取（媒体库 / 预览 / 继续观看）、搜索（[searchItems]）、单条目详情展示
/// （[getItemDetail]）、季集浏览与分类 / 媒体库列表（[queryCatalogItems] +
/// [getCatalogFilterSchema]）；播放入口（[getPlayback]）尚未实现，throw [UnsupportedError]
/// （由入口拦截）。详情只承载展示信息，不含播放接线。
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
    // Emby 官方「继续观看」专用端点（/Items/Resume），比 Filters=IsResumable 可靠：返回
    // 任意 Emby 客户端播放留下的续播进度，已按最近播放排序。
    final items = await api.getResumeItems(
      serverUrl: _serverUrl,
      userId: _userId,
      accessToken: _token,
      limit: 20,
      fields: _cardFields,
    );
    return items
        .map((e) => mapEmbyItemCard(e, serverUrl: _serverUrl, token: _token))
        .map(_continueWatchingCard)
        .toList(growable: false);
  }

  /// 续播行是横版卡：电影用 backdrop（竖版海报塞横版会变形），剧集 Primary 本身是横版剧照
  /// 保持不动。其余无 backdrop 的保持 Primary。
  MediaItemCard _continueWatchingCard(MediaItemCard card) {
    final isEpisode = card.type.trim().toLowerCase() == 'episode';
    if (!isEpisode && card.backdropImage.isNotEmpty) {
      return card.copyWith(primaryImage: card.backdropImage);
    }
    return card;
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
  Future<List<MediaItemCard>> searchItems(String query) async {
    final term = query.trim();
    if (term.isEmpty) return const <MediaItemCard>[];
    // 复用分页查询的 SearchTerm；Recursive 拍平库结构，限影片/剧集/单集（主内容）。
    final page = await api.getItemPage(
      serverUrl: _serverUrl,
      userId: _userId,
      accessToken: _token,
      searchTerm: term,
      recursive: true,
      includeItemTypes: 'Movie,Series,Episode',
      limit: 60,
      fields: _cardFields,
    );
    return page.items
        .map((e) => mapEmbyItemCard(e, serverUrl: _serverUrl, token: _token))
        .toList(growable: false);
  }

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
  Future<List<MediaItemCard>> getPersonItems(String personId) async {
    final id = personId.trim();
    if (id.isEmpty) return const <MediaItemCard>[];
    // 该人物参与的影片 / 剧集（PersonIds），按上映日期倒序。人物本身的姓名 / 简介 / 照片
    // 由 getItemDetail(personId) 提供（人物在 Emby 也是 BaseItemDto）。
    final page = await api.getItemPage(
      serverUrl: _serverUrl,
      userId: _userId,
      accessToken: _token,
      personIds: id,
      recursive: true,
      includeItemTypes: 'Movie,Series',
      sortBy: 'PremiereDate',
      sortOrder: 'Descending',
      limit: 200,
      fields: _cardFields,
    );
    return page.items
        .map((e) => mapEmbyItemCard(e, serverUrl: _serverUrl, token: _token))
        .toList(growable: false);
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
  Future<List<MediaSourceVersion>> getItemSourceVersions(String itemId) async {
    // 与 getItemSourceInfo 同一拉取（MediaSources 含每源 MediaStreams + Default*StreamIndex），
    // 但保留所有源映射成可选版本 + 音轨 / 字幕轨。
    final item = await api.getItem(
      serverUrl: _serverUrl,
      userId: _userId,
      accessToken: _token,
      itemId: itemId,
      fields: 'MediaSources,DateCreated',
    );
    return mapEmbySourceVersions(item);
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
  Future<String> resolveSeriesPlaybackTarget(String seriesId) async {
    return (await resolveSeriesNextUpEpisode(seriesId))?.id ?? '';
  }

  @override
  Future<MediaEpisodeSummary?> resolveSeriesNextUpEpisode(
    String seriesId,
  ) async {
    // 系列页主播放键的「续看/首集」解析：系列 guid 不能直接 getPlayback（无 MediaSources），
    // 须定到具体单集。
    final target = seriesId.trim();
    // 最准来源：「继续观看」(/Items/Resume) 已按**最近播放**排序，取本系列最近在看的那一集，
    // 直接反映最新进度（按键文案随每次播放更新）。比按季顺序扫 resume>0 准——后者会卡在更早
    // 那集（如 ep1 残留进度）而非最近的 ep2。
    final resume = await getContinueWatching();
    for (final card in resume) {
      if (card.type.toLowerCase() == 'episode' &&
          card.seriesId.trim() == target &&
          card.episodeNumber > 0) {
        return MediaEpisodeSummary(
          id: card.id,
          title: card.title,
          seasonNumber: card.seasonNumber,
          episodeNumber: card.episodeNumber,
          primaryImage: card.primaryImage,
          durationSeconds: card.durationSeconds,
          watched: card.watched,
        );
      }
    }
    // 回退（本系列无续看记录＝没播过）：按季号升序扫各季，记下最早的「首个未看」与「首集」回退。
    final seasons = await getItemSeasons(target);
    if (seasons.isEmpty) return null;
    final sorted = [...seasons]
      ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
    MediaEpisodeSummary? firstEpisode;
    MediaEpisodeSummary? firstUnwatched;
    for (final season in sorted) {
      final episodes = await getSeasonEpisodes(season.id);
      if (episodes.isEmpty) continue;
      firstEpisode ??= episodes.first;
      for (final episode in episodes) {
        if (episode.resumePositionSeconds > 0) return episode;
        firstUnwatched ??= episode.watched ? null : episode;
      }
    }
    return firstUnwatched ?? firstEpisode;
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
      // UserData 必须显式请求：列表端点默认不回 PlaybackPositionTicks/Played，缺它则
      // resolveSeriesNextUpEpisode 判不出续看集（全 resume=0）退回首集、选集面板「已看」标记也丢。
      fields: 'Overview,UserData',
    );
    return episodes
        .map((e) => mapEmbyEpisode(e, serverUrl: _serverUrl, token: _token))
        .toList(growable: false);
  }

  @override
  Future<MediaPlaybackResolution> getPlayback(
    MediaPlaybackRequest request,
  ) async {
    // 直链直播（static direct-stream）：一次取数（条目 + MediaSources）即得全部播放事实，
    // 中立 bundle 自足、桥接器纯本地装配 MpvMediaSource（见
    // docs/superpowers/specs/2026-06-25-emby-playback-design.md）。
    final item = await api.getItem(
      serverUrl: _serverUrl,
      userId: _userId,
      accessToken: _token,
      itemId: request.itemId,
      // MediaSources 含每源 MediaStreams + Default*StreamIndex；ProviderIds 取 tmdb；
      // UserData（续播位 PlaybackPositionTicks）在用户域端点默认返回，无需显式 Fields。
      fields: 'MediaSources,ProviderIds,DateCreated',
    );

    final sources = _mediaSources(item);
    if (sources.isEmpty) {
      throw StateError('Emby 条目 ${request.itemId} 无 MediaSources，无法播放');
    }
    // 多版本：qualityId（= MediaSourceId）命中则取该版本，否则首源。
    final qualityId = request.qualityId?.trim() ?? '';
    final source = qualityId.isNotEmpty
        ? sources.firstWhere(
            (s) => (s['Id'] ?? '').toString() == qualityId,
            orElse: () => sources.first,
          )
        : sources.first;
    final mediaSourceId = (source['Id'] ?? '').toString();
    final container = (source['Container'] ?? '').toString().trim();

    final tracks = mapEmbyPlaybackTracks(source);
    final selectedAudio = selectPlaybackTrack(
      tracks: tracks.audio,
      preferredTrackId: request.audioTrackId,
      preferredTrackIndex: request.preferredAudioTrackIndex,
      fallbackTrackId: embyDefaultAudioId(source),
    );
    final selectedSubtitle = selectPlaybackTrack(
      tracks: tracks.subtitle,
      preferredTrackId: request.subtitleTrackId,
      preferredTrackIndex: request.preferredSubtitleTrackIndex,
      fallbackTrackId: embyDefaultSubtitleId(source),
      explicitlyDisabled: request.subtitleTrackExplicitlyDisabled,
    );

    final streamUrl = api.buildStreamUrl(
      serverUrl: _serverUrl,
      itemId: request.itemId,
      mediaSourceId: mediaSourceId,
      accessToken: _token,
      container: container,
    );
    final playbackSource = mapEmbyPlaybackSource(
      source,
      url: streamUrl,
      headers: _entryTokenHeaders(),
    );

    // 续播位：网络优先（UserData.PlaybackPositionTicks），与飞牛同走对账器（本地 play stats
    // 兜底）。startFromBeginning 归零；restartWhenCompleted 时已看完的条目回到开头。
    final durationSeconds = _ticksToSeconds(item['RunTimeTicks']);
    final userData = item['UserData'];
    final networkPositionSeconds = request.startFromBeginning
        ? 0
        : (request.resumePosition?.inSeconds ??
              (userData is Map
                  ? _ticksToSeconds(userData['PlaybackPositionTicks'])
                  : 0));
    final networkCompleted =
        request.restartWhenCompleted &&
        durationSeconds > 0 &&
        ((durationSeconds - networkPositionSeconds) <= 0 ||
            (userData is Map && userData['Played'] == true));
    final resume = await PlaybackResumePositionResolver.resolve(
      videoIds: <String>[request.itemId],
      durationSeconds: durationSeconds,
      networkPositionSeconds: networkPositionSeconds,
      networkPositionAvailable: true,
      networkCompleted: networkCompleted,
      resetCompletedToBeginning: request.restartWhenCompleted,
    );

    final title = (item['Name'] ?? '').toString().trim();
    final bundle = MediaPlaybackBundle(
      itemId: request.itemId,
      title: title.isNotEmpty ? title : request.fallbackTitle,
      itemType: (item['Type'] ?? '').toString(),
      seriesId: (item['SeriesId'] ?? '').toString(),
      seasonId: (item['SeasonId'] ?? '').toString(),
      seriesTitle: (item['SeriesName'] ?? '').toString(),
      seasonNumber: _asInt(item['ParentIndexNumber']),
      episodeNumber: _asInt(item['IndexNumber']),
      posterUrl: _primaryImageUrl(request.itemId),
      tmdbId: _tmdbId(item['ProviderIds']),
      durationSeconds: durationSeconds,
      startPosition: resume.position,
      selectedSource: playbackSource,
      selectedAudioTrack: selectedAudio,
      selectedSubtitleTrack: selectedSubtitle,
      qualities: const <MediaPlaybackQuality>[],
      audioTracks: tracks.audio,
      subtitleTracks: tracks.subtitle,
      session: const MediaPlaybackSession(),
    );

    return MediaPlaybackResolution(
      bundle: bundle,
      backendContext: const EmbyPlaybackContext(),
    );
  }

  @override
  Future<void> reportPlaybackProgress({
    required String itemId,
    required String mediaSourceId,
    required int positionSeconds,
    bool isPaused = false,
  }) async {
    // 更新 Emby UserData.PlaybackPositionTicks（续播位），使跨会话 / 跨客户端续播一致。
    // 秒 → 100ns ticks。best-effort：调用方静默吞错（断网 / 令牌过期不阻断播放）。
    await api.reportPlaybackProgress(
      serverUrl: _serverUrl,
      userId: _userId,
      accessToken: _token,
      itemId: itemId,
      mediaSourceId: mediaSourceId,
      positionTicks: positionSeconds < 0 ? 0 : positionSeconds * 10000000,
      isPaused: isPaused,
    );
  }

  @override
  Future<void> reportPlaybackStart({
    required String itemId,
    required String mediaSourceId,
    int positionSeconds = 0,
  }) async {
    // 建立播放会话——之后的进度回写才会被 Emby 持久化。best-effort：调用方静默吞错。
    await api.reportPlaybackStart(
      serverUrl: _serverUrl,
      userId: _userId,
      accessToken: _token,
      itemId: itemId,
      mediaSourceId: mediaSourceId,
      positionTicks: positionSeconds < 0 ? 0 : positionSeconds * 10000000,
    );
  }

  @override
  Future<void> reportPlaybackStopped({
    required String itemId,
    required String mediaSourceId,
    required int positionSeconds,
  }) async {
    await api.reportPlaybackStopped(
      serverUrl: _serverUrl,
      userId: _userId,
      accessToken: _token,
      itemId: itemId,
      mediaSourceId: mediaSourceId,
      positionTicks: positionSeconds < 0 ? 0 : positionSeconds * 10000000,
    );
  }

  @override
  Future<String?> resolveExternalSubtitleFile(
    String trackId, {
    String? format,
  }) async {
    // 桥接器把外挂字幕轨编码成自包含 guid（itemId/mediaSourceId/streamIndex），这里无状态
    // 解码 → 直链下载字幕全文 → 落临时文件供原生壳 sub-add。下载经 EmbyApi 的 dio（entry-token
    // cookie 由拦截器注入），故无需手动塞 header。失败返回 null（旁路能力，壳侧回退无外挂字幕）。
    final ref = parseEmbyExternalSubtitleGuid(trackId);
    if (ref == null) return null;
    final ext = _subtitleExtension(format);
    try {
      final text = await api.downloadSubtitleText(
        serverUrl: _serverUrl,
        itemId: ref.itemId,
        mediaSourceId: ref.mediaSourceId,
        streamIndex: ref.streamIndex,
        accessToken: _token,
        format: ext,
      );
      if (text.trim().isEmpty) return null;
      final safeName = '${ref.itemId}_${ref.mediaSourceId}_${ref.streamIndex}'
          .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final filePath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'fly_player_emby_sub_$safeName.$ext';
      final file = File(filePath);
      await file.writeAsString(text, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// 字幕格式 → URL 扩展名 / 落盘扩展名。Emby `Stream.{ext}` 端点认 srt / ass / ssa / vtt /
  /// sub；codec `subrip` 映射成 srt，未知回退 srt。
  static String _subtitleExtension(String? format) {
    final normalized = (format ?? '').trim().toLowerCase();
    switch (normalized) {
      case 'subrip':
      case 'srt':
        return 'srt';
      case 'ass':
        return 'ass';
      case 'ssa':
        return 'ssa';
      case 'webvtt':
      case 'vtt':
        return 'vtt';
      case 'sub':
        return 'sub';
      default:
        return 'srt';
    }
  }

  /// 过 fnos 边缘闸的播放 headers：`*.fnos.net` 中转域名加 `Cookie: entry-token=<值>`
  /// （播放直链由 mpv 取流，不经 EmbyApi 拦截器，故在此显式注入）；直连地址不加。
  Map<String, String> _entryTokenHeaders() {
    final token = connection.entryToken.trim();
    if (token.isEmpty || !usesFnConnectRelayCookie(_serverUrl)) {
      return const <String, String>{};
    }
    return <String, String>{'Cookie': mergeEntryTokenCookie('', token)};
  }

  String _primaryImageUrl(String itemId) =>
      '$_serverUrl/Items/${itemId.trim()}/Images/Primary?api_key=$_token';

  static List<Map<String, Object?>> _mediaSources(Map<String, Object?> item) {
    final raw = item['MediaSources'];
    if (raw is! List) return const <Map<String, Object?>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, Object?>.from(e))
        .toList(growable: false);
  }

  static String _tmdbId(Object? providerIds) {
    if (providerIds is! Map) return '';
    for (final entry in providerIds.entries) {
      if ((entry.key?.toString().toLowerCase() ?? '') == 'tmdb') {
        return (entry.value ?? '').toString().trim();
      }
    }
    return '';
  }

  /// Emby `RunTimeTicks` / `PlaybackPositionTicks`（100ns 单位）→ 秒。
  static int _ticksToSeconds(Object? ticks) {
    final value = ticks is num ? ticks : num.tryParse('${ticks ?? ''}');
    if (value == null || value <= 0) return 0;
    return (value ~/ 10000000).toInt();
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }
}
