import '../../api/feiniu_api.dart';
import '../../api/item_list_request.dart';
import '../../api/person_list_request.dart';
import '../../models/person_credit.dart';
import '../../models/play_info.dart';
import '../../models/playback_stream.dart';
import '../../models/stream_track_data.dart';
import '../../playback/feiniu_playback_source_bridge.dart';
import '../../utils/playback_resume_position_resolver.dart';
import '../../utils/swallowed_error_logger.dart';
import '../detail/media_detail.dart';
import '../detail/media_episode_summary.dart';
import '../detail/media_season_summary.dart';
import '../detail/media_source_info.dart';
import '../detail/media_source_version.dart';
import '../filter/media_catalog_filter.dart';
import '../media_backend.dart';
import '../media_backend_capabilities.dart';
import '../media_catalog.dart';
import '../media_item_card.dart';
import '../playback/media_playback.dart';
import '../playback/media_playback_resolution.dart';
import '../playback/media_playback_selectors.dart';
import '../playback/media_playback_source_bridge.dart';
import 'feiniu_detail_mappers.dart';
import 'feiniu_media_mappers.dart';
import 'feiniu_playback_context.dart';
import 'feiniu_playback_mappers.dart';

/// 飞牛后端适配器：内部调用现有 [FeiniuApi]，把飞牛模型映射为公共模型。
///
/// 第一阶段不改变数据来源，只改变调用边界——首页等页面通过 [MediaBackend]
/// 间接访问飞牛，飞牛表现必须与迁移前一致。
class FeiniuMediaBackend implements MediaBackend {
  final FeiniuApi api;
  final Map<String, Map<String, dynamic>> _seasonDetailCache =
      <String, Map<String, dynamic>>{};
  final Map<String, Future<Map<String, dynamic>>> _seasonDetailInFlight =
      <String, Future<Map<String, dynamic>>>{};

  FeiniuMediaBackend(this.api);

  @override
  MediaBackendCapabilities get capabilities =>
      const MediaBackendCapabilities.feiniu();

  @override
  MediaPlaybackSourceBridge get playbackSourceBridge =>
      const FeiniuPlaybackSourceBridge();

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
  Future<List<MediaItemCard>> getNextUpItems({int limit = 20}) async =>
      const <MediaItemCard>[];

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
  Future<List<MediaItemCard>> getLatestItems({int limit = 20}) async {
    // 飞牛官方播放器无"最近添加"页，但 item/list 接口支持 create_time 倒序；
    // 不带 ancestor_guid 即全库查询。失败/排序不生效时返回空，行自然隐藏。
    try {
      final page = await api.getItemsPage(
        ItemListRequest(
          ancestorGuid: '',
          pageSize: limit,
          sortColumn: 'create_time',
          sortType: 'DESC',
          typeTags: const <String>['Movie', 'TV'],
        ).toJson(),
      );
      return page.items.map(mapFeiniuItemCard).toList(growable: false);
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'load feiniu latest items',
        error: error,
        stackTrace: stackTrace,
        source: 'feiniu_media_backend',
      );
      return const <MediaItemCard>[];
    }
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

  @override
  Future<MediaItemCardPage> queryChildItems(MediaCatalogQuery query) async =>
      // 飞牛合集页走自有 getItemsPage(ancestor/parent) 完整路径，不经本接口。
      const MediaItemCardPage();

  @override
  Future<MediaItemCardPage> queryFavoriteItems(MediaCatalogQuery query) async {
    final tags = <String, dynamic>{
      for (final entry in query.selection.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value,
    };
    final page = await api.getFavoritePage(
      tags: tags,
      sortType: query.sortType,
      sortColumn: query.sortField,
      page: query.page,
      pageSize: query.pageSize,
    );
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

  String _detailText(Map<String, dynamic> detail, String key) {
    final direct = (detail[key] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;
    final nested = detail['item'];
    return nested is Map<String, dynamic>
        ? (nested[key] ?? '').toString().trim()
        : '';
  }

  bool _isValidSeriesId(
    String candidate, {
    required String itemId,
    required String seasonId,
    required String ancestorId,
  }) {
    final value = candidate.trim();
    return value.isNotEmpty &&
        value != itemId &&
        value != seasonId &&
        value != ancestorId;
  }

  Future<Map<String, dynamic>> _loadSeasonDetail(String seasonId) {
    final cached = _seasonDetailCache[seasonId];
    if (cached != null) return Future<Map<String, dynamic>>.value(cached);
    final existing = _seasonDetailInFlight[seasonId];
    if (existing != null) return existing;

    late final Future<Map<String, dynamic>> future;
    future = api
        .getItemDetail(seasonId)
        .then((detail) {
          _seasonDetailCache[seasonId] = detail;
          return detail;
        })
        .whenComplete(() {
          if (identical(_seasonDetailInFlight[seasonId], future)) {
            _seasonDetailInFlight.remove(seasonId);
          }
        });
    _seasonDetailInFlight[seasonId] = future;
    return future;
  }

  Future<String> _resolveSeriesId({
    required String itemId,
    required PlayItem item,
    required PlayInfoData? info,
    required Map<String, dynamic> rawDetail,
  }) async {
    final normalizedItemId = itemId.trim();
    final itemType = item.type.trim();
    final type = (itemType.isNotEmpty ? itemType : info?.type ?? '')
        .trim()
        .toLowerCase();
    if (type == 'tv' || type == 'series') {
      final ownId = item.guid.trim();
      return ownId.isNotEmpty ? ownId : normalizedItemId;
    }
    if (type != 'episode') return '';

    final ancestorId = _detailText(rawDetail, 'ancestor_guid');
    final infoParentId = info?.parentGuid.trim() ?? '';
    final rawParentId = _detailText(rawDetail, 'parent_guid');
    final seasonId = infoParentId.isNotEmpty ? infoParentId : rawParentId;
    final directCandidate = info?.grandGuid.trim() ?? '';
    if (_isValidSeriesId(
      directCandidate,
      itemId: normalizedItemId,
      seasonId: seasonId,
      ancestorId: ancestorId,
    )) {
      return directCandidate;
    }
    if (seasonId.isEmpty ||
        seasonId == normalizedItemId ||
        seasonId == ancestorId) {
      return '';
    }

    try {
      final seasonDetail = await _loadSeasonDetail(seasonId);
      final parentCandidate = _detailText(seasonDetail, 'parent_guid');
      final seasonAncestorId = _detailText(seasonDetail, 'ancestor_guid');
      final effectiveAncestorId = ancestorId.isNotEmpty
          ? ancestorId
          : seasonAncestorId;
      return _isValidSeriesId(
            parentCandidate,
            itemId: normalizedItemId,
            seasonId: seasonId,
            ancestorId: effectiveAncestorId,
          )
          ? parentCandidate
          : '';
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'resolve feiniu episode series parent',
        id: itemId,
        error: error,
        stackTrace: stackTrace,
        source: 'feiniu_media_backend',
      );
      return '';
    }
  }

  @override
  Future<MediaDetail> getItemDetail(String itemId) async {
    final rawDetail = await api.getItemDetail(itemId);
    final rawItem = extractFeiniuDetailPlayItem(rawDetail);
    PlayInfoData? info;
    Object? playInfoError;
    StackTrace? playInfoStackTrace;
    try {
      info = await api.getPlayInfo(itemId);
    } catch (error, stackTrace) {
      playInfoError = error;
      playInfoStackTrace = stackTrace;
      if (rawItem == null) rethrow;
    }
    if (playInfoError != null) {
      await logSwallowedError(
        action: 'load feiniu item play info for detail',
        id: itemId,
        error: playInfoError,
        stackTrace: playInfoStackTrace ?? StackTrace.current,
        source: 'feiniu_media_backend',
      );
    }
    final imdbId = extractFeiniuImdbId(rawDetail);
    var credits = const <PersonCredit>[];
    try {
      credits = await api.getPersonList(itemId, request: _creditsRequest);
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'load feiniu item credits',
        id: itemId,
        error: error,
        stackTrace: stackTrace,
        source: 'feiniu_media_backend',
      );
      // 演职员失败不阻断详情展示（复刻详情页 best-effort 语义）。
    }
    // 题材 / 地区字典 best-effort：失败回空 map，详情仍可看（题材退化为原始 id），
    // 复刻旧 play_detail_page 的 `.catchError((_) => const {})` 降级，避免字典请求
    // 失败让整个详情打不开。
    Map<int, String> genresMap;
    try {
      genresMap = await api.getTagGenresMap(lan: 'zh-CN');
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'load feiniu genre dictionary',
        id: itemId,
        error: error,
        stackTrace: stackTrace,
        source: 'feiniu_media_backend',
      );
      genresMap = const <int, String>{};
    }
    Map<String, String> regionNames;
    try {
      regionNames = await api.getTagIso3166Map(lan: 'zh-CN');
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'load feiniu region dictionary',
        id: itemId,
        error: error,
        stackTrace: stackTrace,
        source: 'feiniu_media_backend',
      );
      regionNames = const <String, String>{};
    }
    final normalizedItemId = itemId.trim();
    final item = rawItem?.guid.trim() == normalizedItemId
        ? rawItem!
        : info?.item ?? rawItem!;
    final seriesId = await _resolveSeriesId(
      itemId: normalizedItemId,
      item: item,
      info: info,
      rawDetail: rawDetail,
    );
    final networkPosition = info?.ts ?? 0;
    return mapFeiniuPlayItemDetail(
      item,
      seriesId: seriesId,
      resumePositionSeconds: networkPosition > 0
          ? networkPosition
          : item.watchedTs,
      genresMap: genresMap,
      regionNames: regionNames,
      credits: credits,
      imdbId: imdbId,
    );
  }

  @override
  Future<MediaSourceInfo?> getItemSourceInfo(String itemId) async {
    final info = await api.getStreamMetadata(itemId);
    return mapFeiniuSourceInfo(info);
  }

  @override
  Future<List<MediaSourceVersion>> getItemSourceVersions(String itemId) async {
    final trackData = await api.getStreamTrackData(itemId);
    return mapFeiniuSourceVersions(trackData);
  }

  @override
  Future<List<MediaItemCard>> getPersonItems(String personId) async {
    final page = await api.getPersonItemList(personGuid: personId, job: '');
    return page.items.map(mapFeiniuItemCard).toList(growable: false);
  }

  @override
  Future<void> reportPlaybackProgress({
    required String itemId,
    required String mediaSourceId,
    required int positionSeconds,
    bool isPaused = false,
  }) async {
    // 飞牛进度回写走自有 NativeReentrySupport 通道（含离线队列 + 本地 play stats），不经本接口。
  }

  @override
  Future<String?> resolveExternalSubtitleFile(
    String trackId, {
    String? format,
  }) async {
    // 飞牛外挂字幕解析走自有 NativeReentrySupport.resolveSubtitleFile（NAS guid → 下载），
    // 不经本接口。
    return null;
  }

  @override
  Future<bool> setItemFavorite(String itemId, {required bool favorite}) {
    return api.setFavorite(itemId, favorite: favorite);
  }

  @override
  Future<bool> setItemWatched(String itemId, {required bool watched}) {
    return api.setWatched(itemId, watched: watched);
  }

  @override
  Future<void> reportPlaybackStart({
    required String itemId,
    required String mediaSourceId,
    int positionSeconds = 0,
  }) async {
    // 飞牛进度走自有 NativeReentrySupport 通道，无会话握手，空操作。
  }

  @override
  Future<void> reportPlaybackStopped({
    required String itemId,
    required String mediaSourceId,
    required int positionSeconds,
  }) async {
    // 飞牛进度走自有 NativeReentrySupport 通道，无会话握手，空操作。
  }

  @override
  Future<String> resolveSeriesPlaybackTarget(String seriesId) async {
    // 飞牛 launcher/NAS 自行把系列 guid 解析成续看单集，故原样返回。
    return seriesId;
  }

  @override
  Future<MediaEpisodeSummary?> resolveSeriesNextUpEpisode(
    String seriesId,
  ) async {
    // 飞牛系列页按键文案走自有 PlayInfo（_tvPrimaryLabel），不经本接口。
    return null;
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

  @override
  Future<MediaPlaybackResolution> getPlayback(
    MediaPlaybackRequest request,
  ) async {
    final playInfo = await api.getPlayInfo(request.itemId);
    // 多版本切换：带 qualityId 时按该版本媒体取流，否则用条目默认媒体 mediaGuid。
    // 复刻 ItemPlaybackLauncher 的 effectiveMediaGuid 口径。
    final qualityId = request.qualityId?.trim() ?? '';
    final effectiveSourceId = qualityId.isNotEmpty
        ? qualityId
        : playInfo.mediaGuid;

    if (request.startFromBeginning) {
      await api.resetPlaybackRecord(
        itemGuid: playInfo.item.guid,
        mediaGuid: effectiveSourceId,
      );
    }

    // best-effort：轨道字典失败不阻断播放（复刻 launcher 的 try/catch 降级）。
    StreamTrackData? trackData;
    try {
      trackData = await api.getStreamTrackData(request.itemId);
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'load feiniu stream track data',
        id: request.itemId,
        error: error,
        stackTrace: stackTrace,
        source: 'feiniu_media_backend',
      );
      trackData = null;
    }

    final playbackStream = await api.getPlaybackStream(effectiveSourceId);
    final mergedQualities = mergePlaybackQualitiesWithStreamTrackData(
      playbackStream.qualities,
      trackData,
    );

    final qualities = mapFeiniuPlaybackQualities(mergedQualities);
    final selectedQuality = selectPlaybackQuality(
      qualities: qualities,
      qualityId: request.qualityId,
      qualityIndex: request.qualityIndex,
      preferredResolution: request.preferredQualityResolution,
    );
    // 回找选中画质对应的飞牛原始档，用于 source 的投递方式与视频轨。
    final rawSelectedQuality = _rawQualityFor(mergedQualities, selectedQuality);

    final audioTracks = mapFeiniuAudioTracks(playbackStream.audioStreams);
    final selectedAudio = selectPlaybackTrack(
      tracks: audioTracks,
      preferredTrackId: request.audioTrackId,
      preferredTrackIndex: request.preferredAudioTrackIndex,
      fallbackTrackId: playInfo.audioGuid,
    );

    final mergedSubtitleStreams = _mergeSubtitleStreams(
      primary: playbackStream.subtitleStreams,
      extra: trackData?.subtitlesForMedia(effectiveSourceId) ?? const [],
    );
    final subtitleTracks = mapFeiniuSubtitleTracks(mergedSubtitleStreams);
    final selectedSubtitle = selectPlaybackTrack(
      tracks: subtitleTracks,
      preferredTrackId: request.subtitleTrackId,
      preferredTrackIndex: request.preferredSubtitleTrackIndex,
      fallbackTrackId: playInfo.subtitleGuid,
      explicitlyDisabled: request.subtitleTrackExplicitlyDisabled,
    );

    final videoTrackId = rawSelectedQuality?.videoGuid.trim().isNotEmpty == true
        ? rawSelectedQuality!.videoGuid.trim()
        : (playbackStream.videoStream?.guid.trim().isNotEmpty == true
              ? playbackStream.videoStream!.guid.trim()
              : playInfo.videoGuid.trim());

    final source = mapFeiniuPlaybackSource(
      sourceId: effectiveSourceId,
      videoTrackId: videoTrackId,
      playbackStream: playbackStream,
      selectedQuality: rawSelectedQuality,
      candidateUrl: api.getStreamUrl(effectiveSourceId),
      headers: const <String, String>{},
    );

    // 续播位置：复刻 launcher 的网络优先口径——startFromBeginning 归零，
    // 否则 request.resumePosition ?? (ts > 0 ? ts : item.watchedTs)。
    final networkPositionSeconds = request.startFromBeginning
        ? 0
        : request.resumePosition?.inSeconds ??
              (playInfo.ts > 0 ? playInfo.ts : playInfo.item.watchedTs);
    // restartWhenCompleted（剧集场景）：已看完的一集重新点播回到开头，复刻 TV launcher 的
    // `networkCompleted: playbackCompleted` + 默认归零。默认 false 时维持单条目「永不归零」。
    final durationSeconds = playInfo.item.duration;
    final networkCompleted =
        request.restartWhenCompleted &&
        durationSeconds > 0 &&
        ((durationSeconds - networkPositionSeconds) <= 0 ||
            playInfo.item.isWatched == 1);
    final resume = await PlaybackResumePositionResolver.resolve(
      videoIds: <String>[playInfo.item.guid, request.itemId],
      durationSeconds: durationSeconds,
      networkPositionSeconds: networkPositionSeconds,
      networkPositionAvailable: true,
      networkCompleted: networkCompleted,
      resetCompletedToBeginning: request.restartWhenCompleted,
    );

    final item = playInfo.item;
    final bundle = MediaPlaybackBundle(
      itemId: item.guid,
      title: item.title.trim().isNotEmpty ? item.title : request.fallbackTitle,
      itemType: item.type,
      seriesId: playInfo.grandGuid.trim(),
      seasonId: playInfo.parentGuid,
      seriesTitle: item.tvTitle.trim().isNotEmpty
          ? item.tvTitle.trim()
          : request.fallbackTitle.trim(),
      seasonNumber: item.seasonNumber,
      episodeNumber: item.episodeNumber,
      posterUrl: item.posters,
      tmdbId: item.trimId,
      durationSeconds: item.duration,
      startPosition: resume.position,
      selectedSource: source,
      selectedQuality: selectedQuality,
      selectedAudioTrack: selectedAudio,
      selectedSubtitleTrack: selectedSubtitle,
      qualities: qualities,
      audioTracks: audioTracks,
      subtitleTracks: subtitleTracks,
      session: const MediaPlaybackSession(),
    );

    // 不透明后端上下文：装入桥接器装配 MpvMediaSource 所需的飞牛 raw facts，
    // 单次网络（这里的 playbackStream / 选中 raw 档都已取过）。raw 结构不进 bundle。
    final context = FeiniuPlaybackContext(
      api: api,
      playInfo: playInfo,
      playbackStream: playbackStream,
      selectedQuality: rawSelectedQuality,
      selectedAudio: _rawAudioFor(playbackStream.audioStreams, selectedAudio),
      selectedSubtitle: _rawSubtitleFor(
        mergedSubtitleStreams,
        selectedSubtitle,
      ),
      mergedQualities: mergedQualities,
      subtitleTracks: mergedSubtitleStreams,
      effectiveSourceId: effectiveSourceId,
      videoTrackId: videoTrackId,
      directUrl: api.getStreamUrl(effectiveSourceId),
    );

    return MediaPlaybackResolution(bundle: bundle, backendContext: context);
  }

  /// 回找公共画质对应的飞牛原始档（按 mediaGuid + directLinkQualityIndex 匹配）。
  PlaybackQualityOption? _rawQualityFor(
    List<PlaybackQualityOption> rawQualities,
    MediaPlaybackQuality? selected,
  ) {
    if (selected == null) return null;
    for (final quality in rawQualities) {
      if (quality.mediaGuid == selected.sourceId &&
          quality.directLinkQualityIndex == selected.directLinkIndex) {
        return quality;
      }
    }
    return null;
  }

  /// 回找公共音轨对应的飞牛原始档（按 guid 匹配）。
  AudioTrackOption? _rawAudioFor(
    List<AudioTrackOption> rawTracks,
    MediaPlaybackTrack? selected,
  ) {
    if (selected == null) return null;
    for (final track in rawTracks) {
      if (track.guid == selected.id) return track;
    }
    return null;
  }

  /// 回找公共字幕对应的飞牛原始档（按 guid 匹配）。
  SubtitleTrackOption? _rawSubtitleFor(
    List<SubtitleTrackOption> rawTracks,
    MediaPlaybackTrack? selected,
  ) {
    if (selected == null) return null;
    for (final track in rawTracks) {
      if (track.guid == selected.id) return track;
    }
    return null;
  }

  /// 合并主字幕流与轨道字典里的额外字幕，按 guid 去重（复刻
  /// PlayDetailTrackSelector.mergeSubtitleTracks 的纯去重逻辑，不引入 l10n 依赖）。
  List<SubtitleTrackOption> _mergeSubtitleStreams({
    required List<SubtitleTrackOption> primary,
    required List<SubtitleTrackOption> extra,
  }) {
    if (primary.isEmpty) return List<SubtitleTrackOption>.from(extra);
    if (extra.isEmpty) return List<SubtitleTrackOption>.from(primary);
    final merged = <SubtitleTrackOption>[];
    final seenGuids = <String>{};
    for (final track in <SubtitleTrackOption>[...primary, ...extra]) {
      final guid = track.guid.trim();
      if (guid.isEmpty || !seenGuids.add(guid)) continue;
      merged.add(track);
    }
    return merged;
  }
}
