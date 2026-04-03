part of mpv_player_page;

const int _episodePickerRangeSize = 30;
const String _playlistViewTypeCard = 'card';
const String _playlistViewTypeButton = 'button';

class _PreparedEpisodeSwitchResult {
  final MediaLibraryItem episode;
  final PlayInfoData? playInfo;
  final MpvMediaSource source;
  final String subtitleSourceMediaGuid;
  final bool resumeProgressFullyWatched;
  final String preparedFromItemGuid;
  final String preparedSeasonGuid;
  final String preferenceSignature;

  const _PreparedEpisodeSwitchResult({
    required this.episode,
    required this.playInfo,
    required this.source,
    required this.subtitleSourceMediaGuid,
    required this.resumeProgressFullyWatched,
    required this.preparedFromItemGuid,
    required this.preparedSeasonGuid,
    required this.preferenceSignature,
  });
}

extension _MpvPlayerEpisodeMixin on _MpvPlayerPageState {
  TvEpisodePickerMode _episodePickerModeFromSetting(String? viewType) {
    return viewType == _playlistViewTypeButton
        ? TvEpisodePickerMode.grid
        : TvEpisodePickerMode.list;
  }

  String _playlistViewTypeFromMode(TvEpisodePickerMode mode) {
    return mode == TvEpisodePickerMode.grid
        ? _playlistViewTypeButton
        : _playlistViewTypeCard;
  }

  Future<TvEpisodePickerMode> _loadEpisodePickerMode() async {
    final provider = context.read<NasProvider>();
    if (!provider.isConfigured) return _episodePickerMode;
    try {
      final viewType = await FeiniuApi(provider).getPlaylistViewType();
      final mode = _episodePickerModeFromSetting(viewType);
      if (!mounted) {
        _episodePickerMode = mode;
        return mode;
      }
      if (_episodePickerMode != mode) {
        _updatePlayerState(() => _episodePickerMode = mode);
      }
      return mode;
    } catch (_) {
      return _episodePickerMode;
    }
  }

  Future<void> _persistEpisodePickerMode(TvEpisodePickerMode mode) async {
    final provider = context.read<NasProvider>();
    if (!provider.isConfigured) {
      if (!mounted) {
        _episodePickerMode = mode;
      } else if (_episodePickerMode != mode) {
        _updatePlayerState(() => _episodePickerMode = mode);
      }
      return;
    }
    final saved = await FeiniuApi(
      provider,
    ).setPlaylistViewType(_playlistViewTypeFromMode(mode));
    if (!saved) {
      _showTransientMessage('选集视图保存失败');
      throw StateError('episode picker mode save failed');
    }
    if (!mounted) {
      _episodePickerMode = mode;
      return;
    }
    if (_episodePickerMode != mode) {
      _updatePlayerState(() => _episodePickerMode = mode);
    }
  }

  Future<void> _showEpisodeSheet() async {
    _hideSpeedDialOverlay(restoreAutoHide: false);
    final modeFuture = _loadEpisodePickerMode();
    final episodesFuture = _ensureEpisodeItems();
    final seasonItemsFuture = _loadEpisodeSeasonItems();
    final episodes = await episodesFuture;
    final seasonItems = await seasonItemsFuture;
    if (!mounted) return;

    final currentSeasonGuid = _episodePickerCurrentSeasonGuid();
    final initialSeasonGuid = currentSeasonGuid.isNotEmpty
        ? currentSeasonGuid
        : (episodes.isNotEmpty ? episodes.first.parentGuid.trim() : '');
    if (episodes.length <= 1 && seasonItems.length <= 1) return;

    _overlayState.cancelAutoHide();
    final restoreControls = _controlsVisible;
    if (restoreControls) {
      _hideControlsImmediately();
    }
    final provider = context.read<NasProvider>();
    final playbackState = _episodePickerPlaybackState();
    final initialMode = await modeFuture;
    if (!mounted) return;
    try {
      final initialSeasonData = _buildEpisodePickerSeasonSheetData(
        seasonGuid: initialSeasonGuid,
        episodes: episodes,
        playbackState: playbackState,
      );
      final result = await EpisodePickerSheet.show(
        context,
        barrierTitle: '选集',
        seriesTitle: buildEpisodePickerSeriesTitle(
          episodes,
          fallbackSeriesTitle: _currentSeriesTitle,
        ),
        initialSeasonData: initialSeasonData,
        initialSeasonGuid: initialSeasonData.seasonGuid,
        initialMode: initialMode,
        rangeSize: _episodePickerRangeSize,
        onModeChanged: _persistEpisodePickerMode,
        baseUrl: provider.baseUrl,
        token: provider.token,
        seasonLoader: (seasonGuid) =>
            _loadEpisodePickerSeasonSheetData(seasonGuid, playbackState),
        seasons: buildEpisodePickerSeasonOptions(
          seasonItems,
          selectedSeasonGuid: initialSeasonData.seasonGuid,
        ),
      );
      if (!mounted || result == null || result.itemId == _currentItemGuid) {
        return;
      }

      final targetSeasonGuid = result.seasonGuid.trim();
      final selectedEpisodes =
          targetSeasonGuid.isEmpty ||
              targetSeasonGuid == initialSeasonData.seasonGuid
          ? episodes
          : await _loadEpisodeItemsForSeason(targetSeasonGuid);
      if (!mounted) return;

      final selected = selectedEpisodes.cast<MediaLibraryItem?>().firstWhere(
        (episode) => episode?.guid == result.itemId,
        orElse: () => null,
      );
      if (selected == null) return;
      await _switchToEpisode(selected);
    } finally {
      if (mounted && restoreControls) {
        _showControls();
      }
    }
  }

  Future<void> _showNextEpisode() async {
    final nextEpisode = await _nextEpisodeOrNull();
    if (nextEpisode == null) {
      _showTransientMessage('已经是最后一集了');
      return;
    }
    await _switchToEpisode(nextEpisode);
  }

  Future<void> _showPreviousEpisode() async {
    final previousEpisode = await _previousEpisodeOrNull();
    if (previousEpisode == null) {
      _showTransientMessage('已经是第一集了');
      return;
    }
    await _switchToEpisode(previousEpisode);
  }

  Future<MediaLibraryItem?> _nextEpisodeOrNull() async {
    final episodes = await _ensureEpisodeItems();
    if (!mounted || episodes.isEmpty) return null;

    final currentIndex = episodes.indexWhere(
      (episode) => episode.guid == _currentItemGuid,
    );
    if (currentIndex < 0 || currentIndex + 1 >= episodes.length) {
      return null;
    }
    return episodes[currentIndex + 1];
  }

  Future<MediaLibraryItem?> _previousEpisodeOrNull() async {
    final episodes = await _ensureEpisodeItems();
    if (!mounted || episodes.isEmpty) return null;

    final currentIndex = episodes.indexWhere(
      (episode) => episode.guid == _currentItemGuid,
    );
    if (currentIndex <= 0) {
      return null;
    }
    return episodes[currentIndex - 1];
  }

  bool _hasNextEpisodeInLoadedItems() {
    if (_episodeItems.isEmpty) return true;
    final currentIndex = _episodeItems.indexWhere(
      (episode) => episode.guid == _currentItemGuid,
    );
    if (currentIndex < 0) return true;
    return currentIndex + 1 < _episodeItems.length;
  }

  bool _hasPreviousEpisodeInLoadedItems() {
    if (_episodeItems.isEmpty) return _currentEpisodeNumber > 1;
    final currentIndex = _episodeItems.indexWhere(
      (episode) => episode.guid == _currentItemGuid,
    );
    if (currentIndex < 0) return _currentEpisodeNumber > 1;
    return currentIndex > 0;
  }

  bool _shouldShowEpisodeEntry() {
    if (_episodeItems.length > 1) return true;
    if (_episodeItems.length == 1) return false;
    if (_localDownloadedEpisodeCountHint() > 1) return true;
    if (_episodeListLoading) return true;
    if (_currentSeasonGuid.trim().isNotEmpty) return true;
    if (widget.source.seasonGuid.trim().isNotEmpty) return true;
    if (_currentEpisodeNumber > 0) return true;
    if (widget.source.episodeNumber > 0) return true;
    return false;
  }

  Future<List<MediaLibraryItem>> _ensureEpisodeItems() async {
    if (_episodeItems.isNotEmpty) {
      final currentSeasonGuid = _episodePickerCurrentSeasonGuid();
      if (currentSeasonGuid.isEmpty ||
          _episodeItems.any(
            (episode) =>
                episode.guid == _currentItemGuid ||
                episode.parentGuid.trim() == currentSeasonGuid,
          )) {
        return _episodeItems;
      }
    }
    if (_episodeListLoading) return _episodeItems;

    final provider = context.read<NasProvider>();
    final localItems = await _loadLocalDownloadedEpisodeItems();
    if (localItems.length > 1 && !provider.isConfigured) {
      return localItems;
    }

    final seasonGuid = await _resolveSeasonGuid();
    if (!mounted || seasonGuid.isEmpty) {
      if (localItems.isNotEmpty) {
        return localItems;
      }
      _showTransientMessage('当前片源没有可用选集列表');
      return const <MediaLibraryItem>[];
    }

    _episodeListLoading = true;
    try {
      final items = await _loadEpisodeItemsForSeason(
        seasonGuid,
        fallbackLocalItems: localItems,
        updateCurrentSeasonState: true,
      );
      return items;
    } catch (error) {
      if (localItems.isNotEmpty) {
        return localItems;
      }
      if (mounted) {
        _showTransientMessage('加载选集列表失败: $error');
      }
      return const <MediaLibraryItem>[];
    } finally {
      _episodeListLoading = false;
    }
  }

  void _invalidateEpisodePickerSeasonCache({bool clearCurrentItems = false}) {
    _episodeSeasonItems = null;
    _episodeItemsBySeasonGuid.clear();
    _episodeItemsInflightBySeason.clear();
    if (clearCurrentItems) {
      _episodeItems = const <MediaLibraryItem>[];
    }
  }

  Future<String> _resolveSeriesGuid() async {
    if (_currentSourceIsDownloadedFile) return '';
    final existing = _currentSeriesGuid.trim();
    if (existing.isNotEmpty) return existing;

    final sourceSeriesGuid = widget.source.seriesGuid.trim();
    if (sourceSeriesGuid.isNotEmpty) {
      if (mounted) {
        _updatePlayerState(() => _currentSeriesGuid = sourceSeriesGuid);
      } else {
        _currentSeriesGuid = sourceSeriesGuid;
      }
      return sourceSeriesGuid;
    }

    final initialSeriesGuid = widget.initialPlayInfo?.grandGuid.trim() ?? '';
    if (initialSeriesGuid.isNotEmpty) {
      if (mounted) {
        _updatePlayerState(() => _currentSeriesGuid = initialSeriesGuid);
      } else {
        _currentSeriesGuid = initialSeriesGuid;
      }
      return initialSeriesGuid;
    }

    final provider = context.read<NasProvider>();
    if (!provider.isConfigured || _currentItemGuid.trim().isEmpty) return '';
    try {
      final playInfo = await FeiniuApi(provider).getPlayInfo(_currentItemGuid);
      final seriesGuid = playInfo.grandGuid.trim();
      if (mounted && seriesGuid.isNotEmpty) {
        _updatePlayerState(() => _currentSeriesGuid = seriesGuid);
      } else if (seriesGuid.isNotEmpty) {
        _currentSeriesGuid = seriesGuid;
      }
      return seriesGuid;
    } catch (error, stackTrace) {
      unawaited(
        AppErrorReporter.report(
          error,
          action: 'resolve series guid',
          source: 'mpv_player_episode',
          stackTrace: stackTrace,
          fallbackKind: AppExceptionKind.noData,
          level: AppLogLevel.warning,
          details: 'itemGuid=$_currentItemGuid',
        ),
      );
      return '';
    }
  }

  Future<List<MediaLibraryItem>> _loadEpisodeSeasonItems() async {
    final cached = _episodeSeasonItems;
    if (cached != null) return cached;
    if (_currentSourceIsDownloadedFile) return const <MediaLibraryItem>[];

    final provider = context.read<NasProvider>();
    if (!provider.isConfigured) return const <MediaLibraryItem>[];
    final api = FeiniuApi(provider);
    final candidateSeriesGuids = <String>[
      widget.source.seriesGuid.trim(),
      _currentSeriesGuid.trim(),
      widget.initialPlayInfo?.grandGuid.trim() ?? '',
    ];
    final seasonParentSeriesGuid = await _resolveSeriesGuidFromCurrentSeason(
      api,
    );
    if (seasonParentSeriesGuid.isNotEmpty) {
      candidateSeriesGuids.insert(0, seasonParentSeriesGuid);
    }
    final resolvedSeriesGuid = await _resolveSeriesGuid();
    if (resolvedSeriesGuid.isNotEmpty) {
      candidateSeriesGuids.insert(0, resolvedSeriesGuid);
    }
    final refreshedSeriesGuid = await _refreshEpisodePickerSeriesGuid(api);
    if (refreshedSeriesGuid.isNotEmpty) {
      candidateSeriesGuids.insert(0, refreshedSeriesGuid);
    }
    if (!mounted && candidateSeriesGuids.every((guid) => guid.isEmpty)) {
      return const <MediaLibraryItem>[];
    }
    if (mounted && candidateSeriesGuids.every((guid) => guid.isEmpty)) {
      return const <MediaLibraryItem>[];
    }

    try {
      final seasons = await _loadBestEpisodeSeasonList(
        api,
        candidateSeriesGuids,
      );
      _episodeSeasonItems = List<MediaLibraryItem>.unmodifiable(seasons);
      return _episodeSeasonItems!;
    } catch (error, stackTrace) {
      unawaited(
        AppErrorReporter.report(
          error,
          action: 'load episode seasons',
          source: 'mpv_player_episode',
          stackTrace: stackTrace,
          fallbackKind: AppExceptionKind.noData,
          level: AppLogLevel.warning,
          details:
              'seriesGuids=${candidateSeriesGuids.where((guid) => guid.isNotEmpty).join(",")}',
        ),
      );
      return const <MediaLibraryItem>[];
    }
  }

  Future<String> _refreshEpisodePickerSeriesGuid(FeiniuApi api) async {
    final itemGuid = _currentItemGuid.trim();
    if (itemGuid.isEmpty) return '';
    try {
      final playInfo = await api.getPlayInfo(itemGuid);
      final seriesGuid = playInfo.grandGuid.trim();
      if (seriesGuid.isEmpty) return '';
      if (mounted) {
        _updatePlayerState(() => _currentSeriesGuid = seriesGuid);
      } else {
        _currentSeriesGuid = seriesGuid;
      }
      return seriesGuid;
    } catch (_) {
      return '';
    }
  }

  Future<String> _resolveSeriesGuidFromCurrentSeason(FeiniuApi api) async {
    final candidateSeasonGuid = [
      _currentSeasonGuid.trim(),
      widget.source.seasonGuid.trim(),
      widget.initialPlayInfo?.parentGuid.trim() ?? '',
    ].firstWhere((guid) => guid.isNotEmpty, orElse: () => '');
    if (candidateSeasonGuid.isEmpty) return '';
    try {
      final detail = await api.getItemDetail(candidateSeasonGuid);
      final item = detail['item'];
      final itemMap = item is Map<String, dynamic> ? item : detail;
      final seriesGuid = (itemMap['parent_guid'] ?? '').toString().trim();
      if (seriesGuid.isEmpty) return '';
      if (mounted) {
        _updatePlayerState(() => _currentSeriesGuid = seriesGuid);
      } else {
        _currentSeriesGuid = seriesGuid;
      }
      return seriesGuid;
    } catch (_) {
      return '';
    }
  }

  Future<List<MediaLibraryItem>> _loadBestEpisodeSeasonList(
    FeiniuApi api,
    Iterable<String> candidateSeriesGuids,
  ) async {
    var best = const <MediaLibraryItem>[];
    final tried = <String>{};
    for (final rawGuid in candidateSeriesGuids) {
      final guid = rawGuid.trim();
      if (guid.isEmpty || !tried.add(guid)) continue;
      List<MediaLibraryItem> seasons;
      try {
        seasons = await api.getSeasonList(guid);
      } catch (_) {
        continue;
      }
      if (_seasonListScore(seasons) > _seasonListScore(best)) {
        best = seasons;
      }
      if (_seasonListScore(best) > 1) {
        return best;
      }
    }
    return best;
  }

  int _seasonListScore(List<MediaLibraryItem> seasons) {
    if (seasons.isEmpty) return 0;
    return seasons
        .map((season) => season.guid.trim())
        .where((guid) => guid.isNotEmpty)
        .toSet()
        .length;
  }

  String _episodePickerCurrentSeasonGuid() {
    final current = _currentSeasonGuid.trim();
    if (current.isNotEmpty) return current;
    return widget.source.seasonGuid.trim();
  }

  Future<List<MediaLibraryItem>> _loadEpisodeItemsForSeason(
    String seasonGuid, {
    List<MediaLibraryItem> fallbackLocalItems = const <MediaLibraryItem>[],
    bool updateCurrentSeasonState = false,
  }) async {
    final normalizedSeasonGuid = seasonGuid.trim();
    if (normalizedSeasonGuid.isEmpty) return fallbackLocalItems;

    final cached = _episodeItemsBySeasonGuid[normalizedSeasonGuid];
    if (cached != null) {
      if (updateCurrentSeasonState && mounted) {
        _applyLoadedEpisodeItems(normalizedSeasonGuid, cached);
      }
      return cached;
    }

    final inflight = _episodeItemsInflightBySeason[normalizedSeasonGuid];
    if (inflight != null) {
      final items = await inflight;
      if (updateCurrentSeasonState && mounted) {
        _applyLoadedEpisodeItems(normalizedSeasonGuid, items);
      }
      return items;
    }

    final provider = context.read<NasProvider>();
    if (!provider.isConfigured) return fallbackLocalItems;

    final future = () async {
      final items = await FeiniuApi(
        provider,
      ).getEpisodeList(normalizedSeasonGuid);
      items.sort((a, b) {
        final byEpisode = _episodeSortOrder(a).compareTo(_episodeSortOrder(b));
        if (byEpisode != 0) return byEpisode;
        return a.guid.compareTo(b.guid);
      });
      final frozen = List<MediaLibraryItem>.unmodifiable(items);
      _episodeItemsBySeasonGuid[normalizedSeasonGuid] = frozen;
      return frozen;
    }();
    _episodeItemsInflightBySeason[normalizedSeasonGuid] = future;
    try {
      final items = await future;
      if (updateCurrentSeasonState && mounted) {
        _applyLoadedEpisodeItems(normalizedSeasonGuid, items);
      }
      return items;
    } catch (_) {
      if (fallbackLocalItems.isNotEmpty) {
        return fallbackLocalItems;
      }
      rethrow;
    } finally {
      _episodeItemsInflightBySeason.remove(normalizedSeasonGuid);
    }
  }

  void _applyLoadedEpisodeItems(
    String seasonGuid,
    List<MediaLibraryItem> items,
  ) {
    String? currentPoster;
    for (final item in items) {
      if (item.guid == _currentItemGuid) {
        final poster = item.poster.trim();
        if (poster.isNotEmpty) {
          currentPoster = poster;
        }
        break;
      }
    }
    _updatePlayerState(() {
      _currentSeasonGuid = seasonGuid;
      _episodeItems = items;
      if ((currentPoster ?? '').isNotEmpty) {
        _currentPosterPath = currentPoster!;
      }
    });
  }

  String _preferredEpisodeGuidForPicker(List<MediaLibraryItem> episodes) {
    final currentGuid = _currentItemGuid.trim();
    if (currentGuid.isNotEmpty) {
      for (final episode in episodes) {
        if (episode.guid == currentGuid) return currentGuid;
      }
    }
    for (final episode in episodes) {
      if (episode.ts > 0 || episode.watchedTs > 0 || episode.watched == 1) {
        return episode.guid;
      }
    }
    return episodes.isNotEmpty ? episodes.first.guid : '';
  }

  String _seasonLabelForGuid(
    String seasonGuid, {
    List<MediaLibraryItem> episodes = const <MediaLibraryItem>[],
  }) {
    final normalizedSeasonGuid = seasonGuid.trim();
    final seasonItems = _episodeSeasonItems ?? const <MediaLibraryItem>[];
    for (final season in seasonItems) {
      if (season.guid == normalizedSeasonGuid) {
        return buildEpisodePickerSeasonLabel(season);
      }
    }
    if (episodes.isNotEmpty) {
      return buildEpisodePickerSeasonLabel(episodes.first);
    }
    return '';
  }

  EpisodePickerSeasonSheetData _buildEpisodePickerSeasonSheetData({
    required String seasonGuid,
    required List<MediaLibraryItem> episodes,
    required EpisodePickerPlaybackState playbackState,
  }) {
    final normalizedSeasonGuid = seasonGuid.trim().isNotEmpty
        ? seasonGuid.trim()
        : (episodes.isNotEmpty ? episodes.first.parentGuid.trim() : '');
    return EpisodePickerSeasonSheetData(
      seasonGuid: normalizedSeasonGuid,
      seasonLabel: _seasonLabelForGuid(
        normalizedSeasonGuid,
        episodes: episodes,
      ),
      preferredItemId: _preferredEpisodeGuidForPicker(episodes),
      items: episodes
          .map(
            (episode) => buildEpisodePickerSheetItem(
              episode,
              playbackState: playbackState,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<EpisodePickerSeasonSheetData> _loadEpisodePickerSeasonSheetData(
    String seasonGuid,
    EpisodePickerPlaybackState playbackState,
  ) async {
    try {
      final episodes = await _loadEpisodeItemsForSeason(seasonGuid);
      return _buildEpisodePickerSeasonSheetData(
        seasonGuid: seasonGuid,
        episodes: episodes,
        playbackState: playbackState,
      );
    } catch (error) {
      if (mounted) {
        _showTransientMessage('加载该季选集失败: $error');
      }
      return _buildEpisodePickerSeasonSheetData(
        seasonGuid: seasonGuid,
        episodes: const <MediaLibraryItem>[],
        playbackState: playbackState,
      );
    }
  }

  int _episodeSortOrder(MediaLibraryItem item) {
    if (item.episodeNumber > 0) return item.episodeNumber;
    if (item.numberOfItem > 0) return item.numberOfItem;
    return 1 << 20;
  }

  int _localDownloadedEpisodeCountHint() {
    return _localDownloadedEpisodeRecordsSync().length;
  }

  Future<List<MediaLibraryItem>> _loadLocalDownloadedEpisodeItems() async {
    if (!_currentSourceIsDownloadedFile) return const <MediaLibraryItem>[];
    await DownloadTaskService.instance.initialize();
    final records = _localDownloadedEpisodeRecordsSync();
    if (records.isEmpty) return const <MediaLibraryItem>[];
    final items =
        records.map(_localEpisodeItemFromRecord).toList(growable: false)
          ..sort((a, b) {
            final byEpisode = _episodeSortOrder(
              a,
            ).compareTo(_episodeSortOrder(b));
            if (byEpisode != 0) return byEpisode;
            return a.guid.compareTo(b.guid);
          });
    if (mounted) {
      _updatePlayerState(() => _episodeItems = items);
    }
    return items;
  }

  List<DownloadTaskRecord> _localDownloadedEpisodeRecordsSync() {
    if (!_currentSourceIsDownloadedFile) return const <DownloadTaskRecord>[];
    final service = DownloadTaskService.instance;
    final currentRecord = _currentDownloadedEpisodeRecordSync();
    if (currentRecord == null) return const <DownloadTaskRecord>[];
    final groupId = currentRecord.groupId.trim();
    if (groupId.isEmpty) {
      return <DownloadTaskRecord>[currentRecord];
    }
    final groupedRecords = service.downloadedRecords
        .where((record) => record.groupId.trim() == groupId)
        .toList(growable: false);
    if (groupedRecords.isEmpty) {
      return <DownloadTaskRecord>[currentRecord];
    }
    final byItem = <String, DownloadTaskRecord>{};
    for (final record in groupedRecords) {
      final itemKey = record.itemGuid.trim().isNotEmpty
          ? record.itemGuid.trim()
          : record.id;
      final existing = byItem[itemKey];
      if (existing == null ||
          _compareLocalDownloadedRecordPriority(record, existing) > 0) {
        byItem[itemKey] = record;
      }
    }
    final collapsed = byItem.values.toList(growable: false)
      ..sort(_sortLocalDownloadedRecords);
    return collapsed;
  }

  DownloadTaskRecord? _currentDownloadedEpisodeRecordSync() {
    if (!_currentSourceIsDownloadedFile) return null;
    final service = DownloadTaskService.instance;
    final normalizedItemGuid = _currentItemGuid.trim();
    final preferredResolution = _currentResolution.trim();
    if (normalizedItemGuid.isNotEmpty) {
      final exact = preferredResolution.isEmpty
          ? service.downloadedRecordForItem(normalizedItemGuid)
          : service.downloadedRecordForItem(
              normalizedItemGuid,
              resolution: preferredResolution,
            );
      if (exact != null) return exact;
      final any = service.downloadedRecordForItem(normalizedItemGuid);
      if (any != null) return any;
    }
    final normalizedPath = _normalizedCurrentLocalFilePath();
    if (normalizedPath.isEmpty) return null;
    for (final record in service.downloadedRecords) {
      if (record.filePath.trim() == normalizedPath) {
        return record;
      }
    }
    return null;
  }

  String _normalizedCurrentLocalFilePath() {
    final normalizedUrl = _currentUrl.trim();
    if (normalizedUrl.isEmpty ||
        !normalizedUrl.toLowerCase().startsWith('file:')) {
      return '';
    }
    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null) return '';
    try {
      return uri.toFilePath();
    } catch (_) {
      return '';
    }
  }

  int _sortLocalDownloadedRecords(DownloadTaskRecord a, DownloadTaskRecord b) {
    final byEpisode = _localDownloadedEpisodeNumberFor(
      a,
    ).compareTo(_localDownloadedEpisodeNumberFor(b));
    if (byEpisode != 0) return byEpisode;
    final byCreated = a.createdAtMs.compareTo(b.createdAtMs);
    if (byCreated != 0) return byCreated;
    return a.title.compareTo(b.title);
  }

  int _compareLocalDownloadedRecordPriority(
    DownloadTaskRecord candidate,
    DownloadTaskRecord current,
  ) {
    final preferredResolution = _currentResolution.trim().toLowerCase();
    final candidateMatchesPreferred =
        preferredResolution.isNotEmpty &&
        candidate.resolution.trim().toLowerCase() == preferredResolution;
    final currentMatchesPreferred =
        preferredResolution.isNotEmpty &&
        current.resolution.trim().toLowerCase() == preferredResolution;
    if (candidateMatchesPreferred != currentMatchesPreferred) {
      return candidateMatchesPreferred ? 1 : -1;
    }
    final byResolution = _localDownloadedResolutionScore(
      candidate,
    ).compareTo(_localDownloadedResolutionScore(current));
    if (byResolution != 0) return byResolution;
    return candidate.updatedAtMs.compareTo(current.updatedAtMs);
  }

  int _localDownloadedResolutionScore(DownloadTaskRecord record) {
    final match = RegExp(r'(\d{3,4})').firstMatch(record.resolution);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  int _localDownloadedEpisodeNumberFor(DownloadTaskRecord record) {
    if (record.itemGuid.trim().isNotEmpty &&
        record.itemGuid.trim() == _currentItemGuid.trim() &&
        _currentEpisodeNumber > 0) {
      return _currentEpisodeNumber;
    }
    for (final text in <String>[record.title, record.fileName]) {
      final titleMatch = RegExp(r'第\s*(\d{1,4})\s*[集话話]').firstMatch(text);
      if (titleMatch != null) {
        final value = int.tryParse(titleMatch.group(1) ?? '');
        if (value != null && value > 0) return value;
      }
      final seasonEpisodeMatch = RegExp(
        r'[sS]\d{1,2}[eE](\d{1,4})',
      ).firstMatch(text);
      if (seasonEpisodeMatch != null) {
        final value = int.tryParse(seasonEpisodeMatch.group(1) ?? '');
        if (value != null && value > 0) return value;
      }
      final episodeMatch = RegExp(
        r'\b[eE][pP]?\s*0*(\d{1,4})\b',
      ).firstMatch(text);
      if (episodeMatch != null) {
        final value = int.tryParse(episodeMatch.group(1) ?? '');
        if (value != null && value > 0) return value;
      }
    }
    return 1 << 20;
  }

  MediaLibraryItem _localEpisodeItemFromRecord(DownloadTaskRecord record) {
    final poster =
        [
              ...record.posterUrls,
              ...record.groupPosterUrls,
              _currentPosterPath,
              widget.source.posterPath,
            ]
            .map((value) => value.trim())
            .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final episodeNumber = _localDownloadedEpisodeNumberFor(record);
    return MediaLibraryItem(
      guid: record.itemGuid.trim().isNotEmpty
          ? record.itemGuid.trim()
          : record.id,
      title: record.title.trim().isNotEmpty
          ? record.title.trim()
          : record.fileName.trim(),
      tvTitle: record.groupTitle.trim(),
      type: _currentMediaType.trim().isNotEmpty ? _currentMediaType : 'Episode',
      poster: poster,
      releaseDate: '',
      firstAirDate: '',
      lastAirDate: '',
      voteAverage: '',
      overview: '',
      watched: 0,
      watchedTs: 0,
      ts: 0,
      duration: record.itemGuid.trim() == _currentItemGuid.trim()
          ? _durationSeconds
          : 0,
      seasonNumber: _currentSeasonNumber,
      episodeNumber: episodeNumber >= (1 << 20) ? 0 : episodeNumber,
      numberOfSeasons: 0,
      numberOfEpisodes: 0,
      localNumberOfSeasons: 0,
      localNumberOfEpisodes: 0,
      parentGuid: record.groupId.trim(),
      parentTitle: record.groupTitle.trim(),
      ancestorGuid: '',
      ancestorName: record.groupTitle.trim(),
      path: record.filePath.trim(),
      resolutions: record.resolution.trim().isEmpty
          ? const <String>[]
          : <String>[record.resolution.trim()],
    );
  }

  Future<String> _resolveSeasonGuid() async {
    final existing = _currentSeasonGuid.trim();
    if (existing.isNotEmpty) return existing;
    final sourceSeasonGuid = widget.source.seasonGuid.trim();
    if (sourceSeasonGuid.isNotEmpty) {
      if (mounted) {
        _updatePlayerState(() => _currentSeasonGuid = sourceSeasonGuid);
      } else {
        _currentSeasonGuid = sourceSeasonGuid;
      }
      return sourceSeasonGuid;
    }
    final initialSeasonGuid = widget.initialPlayInfo?.parentGuid.trim() ?? '';
    if (initialSeasonGuid.isNotEmpty) {
      if (mounted) {
        _updatePlayerState(() => _currentSeasonGuid = initialSeasonGuid);
      } else {
        _currentSeasonGuid = initialSeasonGuid;
      }
      return initialSeasonGuid;
    }
    try {
      final api = FeiniuApi(context.read<NasProvider>());
      final detail = await api.getItemDetail(_currentItemGuid);
      final seasonGuid = (detail['parent_guid'] ?? '').toString().trim();
      if (mounted && seasonGuid.isNotEmpty) {
        _updatePlayerState(() => _currentSeasonGuid = seasonGuid);
      }
      return seasonGuid;
    } catch (error, stackTrace) {
      unawaited(
        AppErrorReporter.report(
          error,
          action: 'resolve season guid',
          source: 'mpv_player_episode',
          stackTrace: stackTrace,
          fallbackKind: AppExceptionKind.noData,
          level: AppLogLevel.warning,
          details: 'itemGuid=$_currentItemGuid',
        ),
      );
      return '';
    }
  }

  EpisodePickerPlaybackState _episodePickerPlaybackState() {
    final value = _controller.value.value;
    final position = _displayPosition(value);
    final durationSeconds = _durationSeconds > 0
        ? _durationSeconds
        : value.duration.inSeconds;
    return EpisodePickerPlaybackState(
      currentItemGuid: _currentItemGuid,
      isPlaying: !value.paused,
      currentPositionSeconds: position.inSeconds,
      currentDurationSeconds: durationSeconds,
    );
  }

  String _playerTitleForItem(PlayItem item) {
    return formatPlayerTitleFromPlayItem(item, fallbackTitle: _currentTitle);
  }

  PlaybackQualityOption? _matchPreferredQuality(
    List<PlaybackQualityOption> qualities,
  ) {
    if (qualities.isEmpty) return null;
    PlaybackQualityOption? exactDirectLinkQuality;
    PlaybackQualityOption? exactMediaAndVideo;
    PlaybackQualityOption? exactResolutionAndBitrate;
    PlaybackQualityOption? exactResolution;
    for (final quality in qualities) {
      if (_currentDirectLinkQualityIndex != null &&
          quality.directLinkQualityIndex == _currentDirectLinkQualityIndex) {
        exactDirectLinkQuality = quality;
      }
      final matchesMedia =
          _currentMediaGuid.trim().isNotEmpty &&
          quality.mediaGuid.trim() == _currentMediaGuid.trim();
      final matchesVideo =
          _currentVideoGuid.trim().isNotEmpty &&
          quality.videoGuid.trim() == _currentVideoGuid.trim();
      final matchesResolution =
          _currentResolution.isNotEmpty &&
          _normalizeQualityResolution(quality.resolution) ==
              _normalizeQualityResolution(_currentResolution);
      final matchesBitrate =
          _currentBitrate > 0 && quality.bitrate == _currentBitrate;
      if (matchesMedia && matchesVideo) {
        exactMediaAndVideo = quality;
      }
      if (matchesResolution && matchesBitrate) {
        exactResolutionAndBitrate = quality;
      }
      if (matchesResolution) {
        exactResolution = quality;
      }
    }
    if (exactDirectLinkQuality != null) return exactDirectLinkQuality;
    if (exactMediaAndVideo != null) return exactMediaAndVideo;
    if (exactResolutionAndBitrate != null) return exactResolutionAndBitrate;
    if (exactResolution != null) return exactResolution;
    for (final quality in qualities) {
      if (quality.isDefault == 1) return quality;
    }
    return qualities.first;
  }

  PlaybackQualityOption? _preferredQualityForEpisodeSwitch(
    List<PlaybackQualityOption> qualities,
  ) {
    if (qualities.isEmpty) return null;
    if (_playbackMode.isServerManaged || _playbackMode.isDirectLink) {
      return _matchPreferredQuality(qualities);
    }
    return PlayerSourceController.preferredInitialQuality(qualities);
  }

  String _pickEpisodeBaseMediaGuid({
    required PlayInfoData info,
    required StreamTrackData? trackData,
  }) {
    final infoMediaGuid = info.mediaGuid.trim();
    if (infoMediaGuid.isNotEmpty) return infoMediaGuid;

    final options = trackData?.options ?? const [];
    if (options.isEmpty) return '';

    for (final option in options) {
      if (_currentResolution.isNotEmpty &&
          option.resolutionType.trim() == _currentResolution) {
        return option.mediaGuid.trim();
      }
    }
    return options.first.mediaGuid.trim();
  }

  String _normalizeEpisodeTrackText(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _normalizeEpisodeSubtitleFormat(SubtitleTrackOption track) {
    return _normalizeEpisodeTrackText(
      track.format.isNotEmpty ? track.format : track.codecName,
    );
  }

  int _episodeSubtitleMatchScore(
    SubtitleTrackOption candidate,
    SubtitleTrackOption current,
  ) {
    var score = 0;
    if (candidate.index == current.index) score += 32;
    if (candidate.isExternal == current.isExternal) score += 24;
    if (candidate.extraFile == current.extraFile) score += 18;
    if (_normalizeEpisodeTrackText(candidate.language) ==
        _normalizeEpisodeTrackText(current.language)) {
      score += 20;
    }
    if (_normalizeEpisodeSubtitleFormat(candidate) ==
        _normalizeEpisodeSubtitleFormat(current)) {
      score += 10;
    }
    if (_normalizeEpisodeTrackText(candidate.title) ==
        _normalizeEpisodeTrackText(current.title)) {
      score += 8;
    }
    if (candidate.forced == current.forced) score += 4;
    if (candidate.isBitmap == current.isBitmap) score += 2;
    if (candidate.isDefaultOption && current.isDefaultOption) score += 1;
    return score;
  }

  String? _pickEpisodeSubtitleGuid({
    required String? preferredGuid,
    required List<SubtitleTrackOption> tracks,
  }) {
    final normalizedPreferred = preferredGuid?.trim() ?? '';
    if (normalizedPreferred.isEmpty) return '';
    for (final track in tracks) {
      if (track.guid == normalizedPreferred) {
        return normalizedPreferred;
      }
    }

    final currentTrack = _currentSubtitleTrack();
    if (currentTrack != null) {
      SubtitleTrackOption? best;
      var bestScore = -1;
      for (final candidate in tracks) {
        final score = _episodeSubtitleMatchScore(candidate, currentTrack);
        if (score <= bestScore) continue;
        best = candidate;
        bestScore = score;
      }
      if (best != null && bestScore > 0) {
        return best.guid;
      }
    }

    for (final track in tracks) {
      if (track.isDefaultOption) return track.guid;
    }
    return tracks.isNotEmpty ? tracks.first.guid : '';
  }

  String _episodeSwitchLoadingMessage(MediaLibraryItem episode) {
    final episodeLabel = episode.episodeNumber > 0
        ? '第 ${episode.episodeNumber} 集'
        : episode.title.trim();
    if (episodeLabel.isEmpty) {
      return '正在准备播放...';
    }
    return '正在切换到 $episodeLabel...';
  }

  String _nextEpisodePreloadPreferenceSignature() {
    return <String>[
      _playbackMode.name,
      _currentResolution.trim(),
      (_currentDirectLinkQualityIndex ?? -1).toString(),
      (_normalizedAudioGuid() ?? '').trim(),
      (_normalizedSubtitleGuid() ?? '').trim(),
      _extremePlaybackEnabled ? '1' : '0',
      _currentSourceIsDownloadedFile ? '1' : '0',
    ].join('|');
  }

  bool _isExtremePlaybackApplicableForUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;
    final host = uri.host.trim().toLowerCase();
    return host.isNotEmpty && host != '127.0.0.1' && host != 'localhost';
  }

  DownloadTaskRecord? _localDownloadedRecordForEpisode(
    MediaLibraryItem episode,
  ) {
    return _localDownloadedEpisodeRecordsSync()
        .cast<DownloadTaskRecord?>()
        .firstWhere(
          (record) => record?.itemGuid.trim() == episode.guid.trim(),
          orElse: () => null,
        );
  }

  void _beginEpisodeSwitchLoading(
    MediaLibraryItem episode, {
    required bool shouldResumePlayback,
  }) {
    final currentPosition = _displayPosition(_controller.value.value);
    _updatePlayerState(() => _uiController.qualitySwitchLoading = true);
    _uiController.pendingLoadingTransition = true;
    _markAwaitingVisualPlaybackStart(
      currentPosition,
      targetPaused: !shouldResumePlayback,
    );
    _showSubtitleSwitchMessage(_episodeSwitchLoadingMessage(episode));
  }

  void _invalidateNextEpisodePreload() {
    _nextEpisodePreloadGeneration++;
    _nextEpisodePreloadInFlight = false;
    _prefetchedNextEpisodeSwitchResult = null;
  }

  bool _matchesPrefetchedEpisodeSwitchResult(
    _PreparedEpisodeSwitchResult prepared,
    MediaLibraryItem episode,
  ) {
    return prepared.source.itemGuid.trim() == episode.guid.trim() &&
        prepared.preparedFromItemGuid == _currentItemGuid.trim() &&
        prepared.preparedSeasonGuid == _currentSeasonGuid.trim() &&
        prepared.preferenceSignature ==
            _nextEpisodePreloadPreferenceSignature();
  }

  _PreparedEpisodeSwitchResult? _prefetchedEpisodeSwitchResultFor(
    MediaLibraryItem episode,
  ) {
    final prepared = _prefetchedNextEpisodeSwitchResult;
    if (prepared == null) return null;
    if (_matchesPrefetchedEpisodeSwitchResult(prepared, episode)) {
      return prepared;
    }
    _invalidateNextEpisodePreload();
    return null;
  }

  Future<void> _preloadNextEpisodeIfNeeded(MediaLibraryItem nextEpisode) async {
    if (!_autoPlayEnabled ||
        !_nextEpisodePreloadEnabled ||
        _exitInProgress ||
        _completionActionInFlight ||
        _playbackCompleted) {
      return;
    }
    if (_prefetchedEpisodeSwitchResultFor(nextEpisode) != null ||
        _nextEpisodePreloadInFlight) {
      return;
    }

    final expectedCurrentItemGuid = _currentItemGuid.trim();
    final generation = ++_nextEpisodePreloadGeneration;
    _nextEpisodePreloadInFlight = true;
    try {
      final prepared = await _prepareEpisodeSwitchResult(nextEpisode);
      if (!mounted || generation != _nextEpisodePreloadGeneration) {
        return;
      }
      if (_currentItemGuid.trim() != expectedCurrentItemGuid) {
        return;
      }
      _prefetchedNextEpisodeSwitchResult = prepared;
    } catch (error, stackTrace) {
      if (generation == _nextEpisodePreloadGeneration) {
        _prefetchedNextEpisodeSwitchResult = null;
      }
      unawaited(
        AppLogService.instance.record(
          level: AppLogLevel.info,
          error: error,
          stackTrace: stackTrace,
          source: 'player_next_episode_preload',
          details:
              'currentItem=$expectedCurrentItemGuid nextItem=${nextEpisode.guid.trim()}',
        ),
      );
    } finally {
      if (generation == _nextEpisodePreloadGeneration) {
        _nextEpisodePreloadInFlight = false;
      }
    }
  }

  Future<_PreparedEpisodeSwitchResult> _prepareEpisodeSwitchResult(
    MediaLibraryItem episode, {
    DownloadTaskRecord? localRecord,
  }) async {
    final normalizedGuid = episode.guid.trim();
    if (normalizedGuid.isEmpty) {
      throw const AppException(
        kind: AppExceptionKind.fatal,
        action: 'switch episode',
        message: 'missing item guid',
      );
    }
    final resolvedLocalRecord =
        localRecord ??
        (_currentSourceIsDownloadedFile
            ? _localDownloadedRecordForEpisode(episode)
            : null);
    if (resolvedLocalRecord != null) {
      return _prepareLocalDownloadedEpisodeSwitchResult(
        episode,
        resolvedLocalRecord,
      );
    }
    return _prepareRemoteEpisodeSwitchResult(episode);
  }

  Future<_PreparedEpisodeSwitchResult> _prepareRemoteEpisodeSwitchResult(
    MediaLibraryItem episode,
  ) async {
    final api = FeiniuApi(context.read<NasProvider>());
    final info = await api.getPlayInfo(episode.guid);
    final trackData = await api.getStreamTrackData(episode.guid);
    final baseMediaGuid = _pickEpisodeBaseMediaGuid(
      info: info,
      trackData: trackData,
    );
    if (baseMediaGuid.isEmpty) {
      throw const AppException(
        kind: AppExceptionKind.fatal,
        action: 'switch episode',
        message: 'missing media guid',
      );
    }

    final initialStream = await api.getPlaybackStream(baseMediaGuid);
    final initialQualities = mergePlaybackQualitiesWithStreamTrackData(
      initialStream.qualities,
      trackData,
    );
    final preferredQuality = _preferredQualityForEpisodeSwitch(
      initialQualities,
    );
    final targetMediaGuid =
        preferredQuality?.mediaGuid.trim().isNotEmpty == true
        ? preferredQuality!.mediaGuid.trim()
        : baseMediaGuid;
    final playbackStream = targetMediaGuid == baseMediaGuid
        ? initialStream
        : await api.getPlaybackStream(targetMediaGuid);
    final mergedQualities = mergePlaybackQualitiesWithStreamTrackData(
      playbackStream.qualities,
      trackData,
    );
    final subtitlePlaybackStream = baseMediaGuid == targetMediaGuid
        ? playbackStream
        : await api.getPlaybackStream(baseMediaGuid);
    final mergedSubtitleTracks = PlayDetailTrackSelector.mergeSubtitleTracks(
      primaryTracks: subtitlePlaybackStream.subtitleStreams,
      extraTracks: trackData.subtitlesForMedia(baseMediaGuid),
    );
    final streamUrl = api.getStreamUrl(targetMediaGuid);
    if (streamUrl.trim().isEmpty) {
      throw const AppException(
        kind: AppExceptionKind.fatal,
        action: 'switch episode',
        message: 'missing stream url',
      );
    }

    final selectedAudioGuid = _pickAudioGuid(
      preferredGuid: _normalizedAudioGuid() ?? info.audioGuid,
      tracks: playbackStream.audioStreams,
    );
    final selectedSubtitleGuid =
        _pickEpisodeSubtitleGuid(
          preferredGuid: _normalizedSubtitleGuid() ?? info.subtitleGuid,
          tracks: mergedSubtitleTracks,
        ) ??
        '';
    final selectedAudio = _audioTrackByGuid(
      selectedAudioGuid,
      playbackStream.audioStreams,
    );
    final selectedSubtitle = mergedSubtitleTracks
        .cast<SubtitleTrackOption?>()
        .firstWhere(
          (track) => track?.guid == selectedSubtitleGuid,
          orElse: () => null,
        );

    final sourceTs = info.ts > 0 ? info.ts : info.item.watchedTs;
    final durationSeconds = info.item.duration > 0
        ? info.item.duration
        : episode.duration;
    final rawResumeStartPosition = Duration(
      seconds: durationSeconds > 0
          ? sourceTs.clamp(0, durationSeconds)
          : sourceTs,
    );
    final resumeProgressFullyWatched = _completionController
        .isProgressFullyWatched(
          startPosition: rawResumeStartPosition,
          durationSeconds: durationSeconds,
        );
    final resumeStartPosition = _completionController.normalizedStartPosition(
      startPosition: rawResumeStartPosition,
      durationSeconds: durationSeconds,
    );
    final initialPlayback = await _sourceController.buildInitialPlaybackResult(
      api: api,
      directUrl: streamUrl,
      mediaGuid: targetMediaGuid,
      videoGuid: playbackStream.videoStream?.guid.trim().isNotEmpty == true
          ? playbackStream.videoStream!.guid.trim()
          : preferredQuality?.videoGuid ?? info.videoGuid.trim(),
      playbackStream: playbackStream,
      quality: preferredQuality,
      selectedAudio: selectedAudio,
      selectedSubtitle: selectedSubtitle,
      startPosition: resumeStartPosition,
    );
    final playableSource = initialPlayback.playableSource;
    final resolvedResumeStartPosition =
        !playableSource.reliableSeek && resumeStartPosition > Duration.zero
        ? Duration.zero
        : resumeStartPosition;
    final resolvedMediaGuid = initialPlayback.playbackMode.isServerManaged
        ? targetMediaGuid
        : initialPlayback.mediaGuid;
    final resolvedVideoGuid =
        initialPlayback.playbackMode.isServerManaged ||
            initialPlayback.playbackMode.isDirectLink
        ? (preferredQuality?.videoGuid.trim().isNotEmpty == true
              ? preferredQuality!.videoGuid.trim()
              : initialPlayback.videoGuid)
        : initialPlayback.videoGuid;
    final resolvedResolution =
        initialPlayback.playbackMode.isServerManaged ||
            initialPlayback.playbackMode.isDirectLink
        ? (preferredQuality?.resolution.trim().isNotEmpty == true
              ? preferredQuality!.resolution.trim()
              : (playbackStream.videoStream?.resolutionType.trim().isNotEmpty ==
                        true
                    ? playbackStream.videoStream!.resolutionType.trim()
                    : ''))
        : (playbackStream.videoStream?.resolutionType.trim().isNotEmpty == true
              ? playbackStream.videoStream!.resolutionType.trim()
              : preferredQuality?.resolution ?? '');
    final resolvedBitrate =
        initialPlayback.playbackMode.isServerManaged ||
            initialPlayback.playbackMode.isDirectLink
        ? (preferredQuality?.bitrate ?? playbackStream.videoStream?.bps ?? 0)
        : (playbackStream.videoStream?.bps ?? preferredQuality?.bitrate ?? 0);
    final resolvedSeasonGuid = info.parentGuid.trim().isNotEmpty
        ? info.parentGuid.trim()
        : (episode.parentGuid.trim().isNotEmpty
              ? episode.parentGuid.trim()
              : _currentSeasonGuid.trim());
    final resolvedSeriesGuid = info.grandGuid.trim().isNotEmpty
        ? info.grandGuid.trim()
        : _currentSeriesGuid.trim();
    final source = widget.source.copyWith(
      itemGuid: episode.guid.trim(),
      seriesGuid: resolvedSeriesGuid,
      seasonGuid: resolvedSeasonGuid,
      posterPath: episode.poster.trim(),
      mediaGuid: resolvedMediaGuid,
      mediaType: info.item.type,
      ancestorName: info.item.ancestorName,
      videoGuid: resolvedVideoGuid,
      directLinkQualityIndex: initialPlayback.playbackMode.isDirectLink
          ? preferredQuality?.directLinkQualityIndex
          : null,
      videoWidth: playbackStream.videoStream?.width ?? 0,
      videoHeight: playbackStream.videoStream?.height ?? 0,
      proxySessionId: playableSource.proxySessionId,
      playLink: initialPlayback.playLink,
      url: playableSource.url,
      headers: playableSource.headers,
      title: _playerTitleForItem(info.item),
      seriesTitle: info.item.tvTitle.trim(),
      seasonNumber: info.item.seasonNumber,
      tmdbId: info.item.trimId,
      episodeNumber: info.item.episodeNumber > 0
          ? info.item.episodeNumber
          : episode.episodeNumber,
      startPosition: resolvedResumeStartPosition,
      audioTrackGuid: selectedAudio?.guid,
      clearAudioTrackGuid: selectedAudio == null,
      subtitleTrackGuid: selectedSubtitleGuid.isEmpty
          ? null
          : selectedSubtitleGuid,
      clearSubtitleTrackGuid: selectedSubtitleGuid.isEmpty,
      resolution: resolvedResolution,
      bitrate: resolvedBitrate,
      durationSeconds: durationSeconds,
      localSubtitleFiles: const <String, String>{},
      videoCodecName: playbackStream.videoStream?.codecName ?? '',
      videoProfile: playbackStream.videoStream?.profile ?? '',
      colorSpace: playbackStream.videoStream?.colorSpace ?? '',
      colorTransfer: playbackStream.videoStream?.colorTransfer ?? '',
      colorPrimaries: playbackStream.videoStream?.colorPrimaries ?? '',
      bitDepth: playbackStream.videoStream?.bitDepth ?? 0,
      isDownloadedFile: false,
      preferExternalSubtitle: false,
      forceNativeProxy: playableSource.forceNativeProxy,
      extremePlaybackEnabled:
          _extremePlaybackEnabled &&
          _isExtremePlaybackApplicableForUrl(playableSource.url),
      reliableSeek: playableSource.reliableSeek,
      seekProbeSummary: playableSource.seekProbeSummary,
      playbackMode: initialPlayback.playbackMode,
      playbackSpeed: _playbackSpeed,
      listenVideoModeEnabled: _listenVideoModeEnabled,
      audioTracks: playbackStream.audioStreams,
      subtitleTracks: mergedSubtitleTracks,
      qualities: mergedQualities,
    );
    return _PreparedEpisodeSwitchResult(
      episode: episode,
      playInfo: info,
      source: source,
      subtitleSourceMediaGuid: baseMediaGuid,
      resumeProgressFullyWatched: resumeProgressFullyWatched,
      preparedFromItemGuid: _currentItemGuid.trim(),
      preparedSeasonGuid: _currentSeasonGuid.trim(),
      preferenceSignature: _nextEpisodePreloadPreferenceSignature(),
    );
  }

  Future<_PreparedEpisodeSwitchResult>
  _prepareLocalDownloadedEpisodeSwitchResult(
    MediaLibraryItem episode,
    DownloadTaskRecord record,
  ) async {
    final path = record.filePath.trim();
    if (path.isEmpty || !File(path).existsSync()) {
      throw const FileSystemException('local video file missing');
    }

    final provider = context.read<NasProvider>();
    final api = FeiniuApi(provider);
    PlayInfoData? playInfo;
    StreamTrackData? trackData;
    PlaybackStreamData? playbackStream;

    if (provider.isConfigured && record.itemGuid.trim().isNotEmpty) {
      try {
        playInfo = await api.getPlayInfo(record.itemGuid.trim());
      } catch (_) {}
      try {
        trackData = await api.getStreamTrackData(record.itemGuid.trim());
      } catch (_) {}
    }

    final resolvedMediaGuid = record.mediaGuid.trim().isNotEmpty
        ? record.mediaGuid.trim()
        : (playInfo?.mediaGuid.trim().isNotEmpty == true
              ? playInfo!.mediaGuid.trim()
              : record.itemGuid.trim());

    if (resolvedMediaGuid.isNotEmpty) {
      try {
        playbackStream = await api.getPlaybackStream(resolvedMediaGuid);
      } catch (_) {}
    }

    final playItem = playInfo?.item;
    final trackVideo = resolvedMediaGuid.isEmpty
        ? null
        : trackData?.videoForMedia(resolvedMediaGuid);
    final playbackVideo = playbackStream?.videoStream;
    final audioTracks = playbackStream?.audioStreams.isNotEmpty == true
        ? playbackStream!.audioStreams
        : (resolvedMediaGuid.isEmpty
              ? const <AudioTrackOption>[]
              : trackData?.audiosForMedia(resolvedMediaGuid) ??
                    const <AudioTrackOption>[]);
    final selectedAudio = PlayDetailTrackSelector.selectedOrFirstAudio(
      selectedAudioGuid: _normalizedAudioGuid() ?? playInfo?.audioGuid ?? '',
      audioTracks: audioTracks,
    );
    final durationSeconds = playItem?.duration ?? episode.duration;
    final sourceTs = playInfo == null
        ? 0
        : (playInfo.ts > 0 ? playInfo.ts : playItem?.watchedTs ?? 0);
    final rawResumeStartPosition = Duration(
      seconds: durationSeconds > 0
          ? sourceTs.clamp(0, durationSeconds)
          : sourceTs,
    );
    final resumeProgressFullyWatched = _completionController
        .isProgressFullyWatched(
          startPosition: rawResumeStartPosition,
          durationSeconds: durationSeconds,
        );
    final resumeStartPosition = _completionController.normalizedStartPosition(
      startPosition: rawResumeStartPosition,
      durationSeconds: durationSeconds,
    );
    final fallbackTitle = episode.title.trim().isNotEmpty
        ? episode.title.trim()
        : (record.title.trim().isNotEmpty
              ? record.title.trim()
              : _currentTitle);
    final title = playItem == null
        ? fallbackTitle
        : formatPlayerTitleFromPlayItem(playItem, fallbackTitle: fallbackTitle);
    final resolvedSeasonGuid = (playInfo?.parentGuid.trim().isNotEmpty == true)
        ? playInfo!.parentGuid.trim()
        : (_currentSeasonGuid.trim().isNotEmpty
              ? _currentSeasonGuid.trim()
              : episode.parentGuid.trim());
    final resolvedSeriesGuid = (playInfo?.grandGuid.trim().isNotEmpty == true)
        ? playInfo!.grandGuid.trim()
        : _currentSeriesGuid.trim();
    final localSource = MpvMediaSource.localFile(
      filePath: path,
      itemGuid: episode.guid.trim(),
      seriesGuid: resolvedSeriesGuid,
      seasonGuid: resolvedSeasonGuid,
      posterPath: episode.poster.trim().isNotEmpty
          ? episode.poster.trim()
          : _currentPosterPath.trim(),
      mediaGuid: resolvedMediaGuid,
      mediaType:
          playItem?.type ??
          (_currentMediaType.trim().isNotEmpty ? _currentMediaType : 'Episode'),
      ancestorName: playItem?.ancestorName ?? record.groupTitle.trim(),
      videoGuid: trackVideo?.guid.trim().isNotEmpty == true
          ? trackVideo!.guid.trim()
          : (playbackVideo?.guid.trim().isNotEmpty == true
                ? playbackVideo!.guid.trim()
                : resolvedMediaGuid),
      title: title,
      seriesTitle: (playItem?.tvTitle ?? record.groupTitle).trim(),
      seasonNumber: playItem?.seasonNumber ?? _currentSeasonNumber,
      tmdbId: playItem?.trimId ?? _currentTmdbId,
      episodeNumber: playItem?.episodeNumber ?? episode.episodeNumber,
      startPosition: resumeStartPosition,
      audioTrackGuid: selectedAudio?.guid ?? playInfo?.audioGuid,
      subtitleTrackGuid: playInfo?.subtitleGuid,
      resolution: record.resolution.trim().isNotEmpty
          ? record.resolution.trim()
          : (playbackVideo?.resolutionType.trim().isNotEmpty == true
                ? playbackVideo!.resolutionType.trim()
                : trackVideo?.resolutionType ?? _currentResolution),
      bitrate: playbackVideo?.bps ?? trackVideo?.bps ?? 0,
      durationSeconds: durationSeconds,
      videoWidth: playbackVideo?.width ?? trackVideo?.width ?? 0,
      videoHeight: playbackVideo?.height ?? trackVideo?.height ?? 0,
      videoCodecName: playbackVideo?.codecName ?? trackVideo?.codecName ?? '',
      videoProfile: playbackVideo?.profile ?? trackVideo?.profile ?? '',
      colorSpace: playbackVideo?.colorSpace ?? trackVideo?.colorSpace ?? '',
      colorTransfer:
          playbackVideo?.colorTransfer ?? trackVideo?.colorTransfer ?? '',
      colorPrimaries:
          playbackVideo?.colorPrimaries ?? trackVideo?.colorPrimaries ?? '',
      bitDepth: playbackVideo?.bitDepth ?? trackVideo?.bitDepth ?? 0,
      audioTracks: audioTracks,
      subtitleTracks: const <SubtitleTrackOption>[],
      qualities: mergePlaybackQualitiesWithStreamTrackData(
        const <PlaybackQualityOption>[],
        trackData,
      ),
      playbackSpeed: _playbackSpeed,
    );
    return _PreparedEpisodeSwitchResult(
      episode: episode,
      playInfo: playInfo,
      source: localSource,
      subtitleSourceMediaGuid: localSource.mediaGuid,
      resumeProgressFullyWatched: resumeProgressFullyWatched,
      preparedFromItemGuid: _currentItemGuid.trim(),
      preparedSeasonGuid: _currentSeasonGuid.trim(),
      preferenceSignature: _nextEpisodePreloadPreferenceSignature(),
    );
  }

  List<MediaLibraryItem> _episodeItemsForAppliedSource(
    MpvMediaSource source,
    MediaLibraryItem fallbackEpisode,
  ) {
    final normalizedSeasonGuid = source.seasonGuid.trim();
    final cached = normalizedSeasonGuid.isEmpty
        ? null
        : _episodeItemsBySeasonGuid[normalizedSeasonGuid];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    if (_episodeItems.any((episode) => episode.guid == fallbackEpisode.guid)) {
      return _episodeItems;
    }
    return const <MediaLibraryItem>[];
  }

  Future<void> _applyPreparedEpisodeSwitchResult(
    _PreparedEpisodeSwitchResult prepared, {
    required bool fromAutoPlay,
    required bool shouldResumePlayback,
  }) async {
    final oldSessionId = _activeProxySessionId;
    final oldSubtitleSessionId = _activeSubtitleProxySessionId;
    final previousSeriesGuid = _currentSeriesGuid.trim();
    final previousSourceWasDownloaded = _currentSourceIsDownloadedFile;
    final shouldPromptForAutoPlay =
        fromAutoPlay && prepared.resumeProgressFullyWatched;
    final source = prepared.source.copyWith(
      loadNonce: _issueNextLoadNonce(),
      playbackSpeed: _playbackSpeed,
      extremePlaybackEnabled:
          _extremePlaybackEnabled &&
          _isExtremePlaybackApplicableForUrl(prepared.source.url),
    );
    final nextEpisodeItems = _episodeItemsForAppliedSource(
      source,
      prepared.episode,
    );
    final sourceChangedSeries =
        previousSeriesGuid != source.seriesGuid.trim() ||
        previousSourceWasDownloaded != source.isDownloadedFile;
    if (sourceChangedSeries) {
      _invalidateEpisodePickerSeasonCache(clearCurrentItems: true);
    }
    _invalidateNextEpisodePreload();
    _invalidateReturnDetailPrefetch();
    await _submitPlaybackRecord(force: true);
    await _finishPlayStatsSession(fromAutoPlay ? 'auto_next' : 'item_switch');
    _completionController.clear();
    _cancelScheduledProxyRelease(source.proxySessionId);
    _updatePlayerState(() {
      _serverFallbackSubtitleGuids.clear();
      _subtitleFailureNoticeShownGuids.clear();
      _currentItemGuid = source.itemGuid;
      _currentMediaType = source.mediaType;
      _currentAncestorName = source.ancestorName;
      _currentTitle = source.title;
      _currentSeriesGuid = source.seriesGuid;
      _currentSeriesTitle = source.seriesTitle;
      _currentSeasonGuid = source.seasonGuid;
      _currentSeasonNumber = source.seasonNumber;
      _currentEpisodeNumber = source.episodeNumber;
      _currentTmdbId = source.tmdbId;
      _currentPosterPath = source.posterPath;
      _activeProxySessionId = source.proxySessionId;
      _activeSubtitleProxySessionId = null;
      _currentPlayLink = source.playLink;
      _currentUrl = source.url;
      _currentHeaders = source.headers;
      _episodeItems = nextEpisodeItems;
      _currentReliableSeek = source.reliableSeek;
      _currentSeekProbeSummary = source.seekProbeSummary;
      _currentMediaGuid = source.mediaGuid;
      _subtitleSourceMediaGuid = prepared.subtitleSourceMediaGuid;
      _currentVideoGuid = source.videoGuid;
      _currentDirectLinkQualityIndex = source.directLinkQualityIndex;
      _currentVideoWidth = source.videoWidth;
      _currentVideoHeight = source.videoHeight;
      _currentVideoCodecName = source.videoCodecName;
      _currentVideoProfile = source.videoProfile;
      _currentColorSpace = source.colorSpace;
      _currentColorTransfer = source.colorTransfer;
      _currentColorPrimaries = source.colorPrimaries;
      _currentBitDepth = source.bitDepth;
      _currentResolution = source.resolution;
      _currentBitrate = source.bitrate;
      _durationSeconds = source.durationSeconds;
      _audioTracks = source.audioTracks;
      _subtitleTracks = source.subtitleTracks;
      _qualities = source.qualities;
      _currentAudioGuid = source.audioTrackGuid;
      _currentSubtitleGuid = source.subtitleTrackGuid;
      _subtitleExplicitlyDisabled = false;
      _pendingExternalSubtitlePath = null;
      _playbackMode = source.playbackMode;
      _pendingSubtitleSelectionRefresh = true;
      _pendingReloadAutoplayRefresh =
          shouldResumePlayback && !shouldPromptForAutoPlay;
      _watchedMarkedForCurrentItem = false;
      _resumeStartPosition = source.startPosition;
      _uiController.lastRecordedSecond = -1;
    });
    _syncDanmakuMediaContext(triggerAutoLoad: _danmakuController.ready);
    unawaited(_loadIntroOutroConfigForItem(source.itemGuid));
    if (shouldPromptForAutoPlay) {
      _completionController.requestPauseAfterReadyForAutoPlayPrompt();
    }
    _gestureController.resetSeekTracking();
    _setResumePromptVisibility(
      _shouldShowResumePrompt(
        startPosition: source.startPosition,
        durationSeconds: source.durationSeconds,
      ),
    );
    unawaited(_prefetchReturnDetailDataIfNeeded());

    if (oldSessionId != null &&
        oldSessionId.isNotEmpty &&
        oldSessionId != source.proxySessionId) {
      _scheduleProxySessionRelease(oldSessionId);
    }
    if (oldSubtitleSessionId != null && oldSubtitleSessionId.isNotEmpty) {
      _scheduleProxySessionRelease(oldSubtitleSessionId);
    }

    unawaited(
      _startPlayStatsSession(
        startSource: fromAutoPlay
            ? PlayStartSource.autoNext
            : PlayStartSource.manualSwitch,
        info: prepared.playInfo,
        source: source,
        startPositionMs: source.startPosition.inMilliseconds,
      ),
    );
    _markAwaitingVisualPlaybackStart(
      source.startPosition,
      targetPaused: shouldPromptForAutoPlay ? true : !shouldResumePlayback,
    );
    _controller.prepareForSourceLoad(
      source,
      paused: shouldPromptForAutoPlay ? true : !shouldResumePlayback,
    );
    await _controller.reload(source);
    _showControls();
  }

  Future<void> _switchToEpisode(
    MediaLibraryItem episode, {
    bool fromAutoPlay = false,
  }) async {
    if (episode.guid.trim().isEmpty || episode.guid == _currentItemGuid) return;
    final shouldResumePlayback =
        fromAutoPlay || !_controller.value.value.paused;
    var reloadStarted = false;
    _beginEpisodeSwitchLoading(
      episode,
      shouldResumePlayback: shouldResumePlayback,
    );
    try {
      final prepared =
          _prefetchedEpisodeSwitchResultFor(episode) ??
          await _prepareEpisodeSwitchResult(episode);
      await _applyPreparedEpisodeSwitchResult(
        prepared,
        fromAutoPlay: fromAutoPlay,
        shouldResumePlayback: shouldResumePlayback,
      );
      reloadStarted = true;
    } catch (error) {
      _showTransientMessage('切换剧集失败: $error');
    } finally {
      if (!reloadStarted) {
        _cancelPendingLoadingTransition();
      }
    }
  }

  Future<void> _switchToLocalDownloadedEpisode(
    MediaLibraryItem episode,
    DownloadTaskRecord record, {
    bool fromAutoPlay = false,
  }) async {
    final path = record.filePath.trim();
    if (path.isEmpty || !File(path).existsSync()) {
      _showTransientMessage('本地视频文件不存在');
      return;
    }

    final shouldResumePlayback =
        fromAutoPlay || !_controller.value.value.paused;
    var reloadStarted = false;
    _beginEpisodeSwitchLoading(
      episode,
      shouldResumePlayback: shouldResumePlayback,
    );
    try {
      final prepared =
          _prefetchedEpisodeSwitchResultFor(episode) ??
          await _prepareEpisodeSwitchResult(episode, localRecord: record);
      await _applyPreparedEpisodeSwitchResult(
        prepared,
        fromAutoPlay: fromAutoPlay,
        shouldResumePlayback: shouldResumePlayback,
      );
      reloadStarted = true;
    } catch (error) {
      _showTransientMessage('切换剧集失败: $error');
    } finally {
      if (!reloadStarted) {
        _cancelPendingLoadingTransition();
      }
    }
  }
}
