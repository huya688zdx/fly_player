part of '../../mpv_player_page.dart';

const int _episodePickerRangeSize = 30;
const String _playlistViewTypeCard = 'card';
const String _playlistViewTypeButton = 'button';
const String _localDownloadedSeasonKeyPrefix = 'local-download:';

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
  EpisodePickerPresenterLabels get _episodePickerLabels =>
      EpisodePickerPresenterLabels.fromL10n(AppLocalizations.of(context));

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

  Future<TvEpisodePickerMode> _loadEpisodePickerMode({
    bool updateUi = true,
  }) async {
    final provider = context.read<NasProvider>();
    if (!provider.isConfigured) return _episodePickerMode;
    try {
      final viewType = await FeiniuApi(provider).getPlaylistViewType();
      final mode = _episodePickerModeFromSetting(viewType);
      if (!mounted) {
        _episodePickerMode = mode;
        return mode;
      }
      if (updateUi && _episodePickerMode != mode) {
        _updatePlayerState(() => _episodePickerMode = mode);
      }
      return mode;
    } catch (_) {
      return _episodePickerMode;
    }
  }

  Future<void> _persistEpisodePickerMode(TvEpisodePickerMode mode) async {
    final provider = context.read<NasProvider>();
    final saveFailedMessage = AppLocalizations.of(
      context,
    ).playerEpisodeViewSaveFailed;
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
      _showTransientMessage(saveFailedMessage);
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

  void _scheduleEpisodePickerPrefetch({Duration? delay}) {
    if (_externalLocalSource) {
      _episodePickerPrefetchTimer?.cancel();
      _episodePickerPrefetchTimer = null;
      _episodePickerPrefetchInFlight = false;
      return;
    }
    final effectiveDelay =
        delay ??
        (_currentSourceIsDownloadedFile
            ? Duration.zero
            : _MpvPlayerPageState._episodePickerPrefetchDelay);
    _episodePickerPrefetchTimer?.cancel();
    _episodePickerPrefetchInFlight = false;
    final generation = ++_episodePickerPrefetchGeneration;
    _episodePickerPrefetchTimer = Timer(effectiveDelay, () {
      _episodePickerPrefetchTimer = null;
      if (!mounted ||
          _exitInProgress ||
          generation != _episodePickerPrefetchGeneration) {
        return;
      }
      unawaited(_prefetchEpisodePickerDataIfNeeded(generation: generation));
    });
  }

  Future<void> _prefetchEpisodePickerDataIfNeeded({
    required int generation,
  }) async {
    if (_externalLocalSource ||
        !mounted ||
        _exitInProgress ||
        generation != _episodePickerPrefetchGeneration ||
        _episodePickerPrefetchInFlight ||
        _episodeSheetVisible ||
        !_shouldShowEpisodeEntry()) {
      return;
    }

    final provider = context.read<NasProvider>();
    final currentSeasonGuid = _episodePickerCurrentSeasonGuid();
    final hasCurrentSeasonItems = _cachedEpisodeItemsForEpisodePicker(
      preferredSeasonGuid: currentSeasonGuid,
    ).isNotEmpty;
    final needsSeasonList =
        provider.isConfigured && _episodeSeasonItems == null;
    if (hasCurrentSeasonItems && !needsSeasonList) {
      return;
    }

    _episodePickerPrefetchInFlight = true;
    try {
      await Future.wait<void>(<Future<void>>[
        if (!hasCurrentSeasonItems)
          _prefetchCurrentEpisodePickerSeason(generation: generation),
        if (needsSeasonList)
          () async {
            await _loadEpisodeSeasonItems();
          }(),
      ]);
    } finally {
      if (generation == _episodePickerPrefetchGeneration) {
        _episodePickerPrefetchInFlight = false;
      }
    }
  }

  Future<void> _prefetchCurrentEpisodePickerSeason({
    required int generation,
  }) async {
    if (generation != _episodePickerPrefetchGeneration) return;
    final preferredSeasonGuid = _episodePickerCurrentSeasonGuid();
    if (_cachedEpisodeItemsForEpisodePicker(
      preferredSeasonGuid: preferredSeasonGuid,
    ).isNotEmpty) {
      return;
    }

    final provider = context.read<NasProvider>();
    final localItems = await _loadLocalDownloadedEpisodeItems(updateUi: false);
    if (!mounted || generation != _episodePickerPrefetchGeneration) return;
    if (!provider.isConfigured) {
      if (!mounted ||
          localItems.isEmpty ||
          _episodeItemsMatchPickerSeason(_episodeItems, preferredSeasonGuid)) {
        return;
      }
      _updatePlayerState(() => _episodeItems = localItems);
      return;
    }

    final seasonGuid = await _resolveSeasonGuid();
    if (!mounted ||
        generation != _episodePickerPrefetchGeneration ||
        seasonGuid.isEmpty) {
      if (!mounted ||
          localItems.isEmpty ||
          _episodeItemsMatchPickerSeason(_episodeItems, preferredSeasonGuid)) {
        return;
      }
      _updatePlayerState(() => _episodeItems = localItems);
      return;
    }

    try {
      final items = await _loadEpisodeItemsForSeason(
        seasonGuid,
        fallbackLocalItems: localItems,
        updateCurrentSeasonState: true,
      );
      if (!mounted ||
          generation != _episodePickerPrefetchGeneration ||
          items.isEmpty ||
          _episodeItemsMatchPickerSeason(_episodeItems, seasonGuid)) {
        return;
      }
      _applyLoadedEpisodeItems(seasonGuid, items);
    } catch (_) {
      if (!mounted ||
          generation != _episodePickerPrefetchGeneration ||
          localItems.isEmpty ||
          _episodeItemsMatchPickerSeason(_episodeItems, preferredSeasonGuid)) {
        return;
      }
      _updatePlayerState(() => _episodeItems = localItems);
    }
  }

  bool _episodeItemsMatchPickerSeason(
    List<MediaLibraryItem> items,
    String seasonGuid,
  ) {
    if (items.isEmpty) return false;
    final normalizedSeasonGuid = seasonGuid.trim();
    final currentItemGuid = _currentItemGuid.trim();
    if (normalizedSeasonGuid.isNotEmpty &&
        items.any(
          (episode) => episode.parentGuid.trim() == normalizedSeasonGuid,
        )) {
      return true;
    }
    if (currentItemGuid.isEmpty ||
        !items.any((episode) => episode.guid == currentItemGuid)) {
      return false;
    }
    if (normalizedSeasonGuid.isEmpty) return true;
    return items.every((episode) => episode.parentGuid.trim().isEmpty);
  }

  List<MediaLibraryItem> _cachedEpisodeItemsForEpisodePicker({
    String preferredSeasonGuid = '',
  }) {
    if (_episodeItemsMatchPickerSeason(_episodeItems, preferredSeasonGuid)) {
      return _episodeItems;
    }

    final normalizedSeasonGuid = preferredSeasonGuid.trim();
    if (normalizedSeasonGuid.isNotEmpty) {
      final cached = _episodeItemsBySeasonGuid[normalizedSeasonGuid];
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
      for (final items in _episodeItemsBySeasonGuid.values) {
        if (_episodeItemsMatchPickerSeason(items, normalizedSeasonGuid)) {
          return items;
        }
      }
      return const <MediaLibraryItem>[];
    }

    final currentItemGuid = _currentItemGuid.trim();
    if (currentItemGuid.isNotEmpty) {
      for (final items in _episodeItemsBySeasonGuid.values) {
        if (items.any((episode) => episode.guid == currentItemGuid)) {
          return items;
        }
      }
    }
    return const <MediaLibraryItem>[];
  }

  bool _shouldWarmupEpisodePickerSheet(String preferredSeasonGuid) {
    if (_cachedEpisodeItemsForEpisodePicker(
      preferredSeasonGuid: preferredSeasonGuid,
    ).isEmpty) {
      return true;
    }
    final provider = context.read<NasProvider>();
    if (!provider.isConfigured) return false;
    return _episodeSeasonItems == null;
  }

  Future<void> _showEpisodeSheet() async {
    if (_externalLocalSource) return;
    _hideSpeedDialOverlay(restoreAutoHide: false);
    unawaited(_loadEpisodePickerMode(updateUi: true));

    _overlayState.cancelAutoHide();
    final restoreControls = _controlsVisible;
    if (restoreControls) {
      _hideControlsImmediately();
    }
    final provider = context.read<NasProvider>();
    final playbackState = _episodePickerPlaybackState();
    final initialSeasonData = _episodePickerInitialSeasonData(playbackState);

    final shouldWarmup = _shouldWarmupEpisodePickerSheet(
      initialSeasonData.seasonGuid,
    );
    try {
      _updatePlayerState(() => _episodeSheetVisible = true);
      unawaited(_syncDanmakuDynamicOcclusionConfig());
      final result = await EpisodePickerSheet.show(
        context,
        barrierTitle: AppLocalizations.of(context).playerEpisodePickerTitle,
        seriesTitle: _episodePickerSeriesTitle(initialSeasonData),
        initialSeasonData: initialSeasonData,
        initialSeasonGuid: initialSeasonData.seasonGuid,
        initialMode: _episodePickerMode,
        rangeSize: _episodePickerRangeSize,
        onModeChanged: _persistEpisodePickerMode,
        baseUrl: provider.baseUrl,
        token: provider.token,
        seasonLoader: (seasonGuid) =>
            _loadEpisodePickerSeasonSheetData(seasonGuid, playbackState),
        warmupLoader: shouldWarmup
            ? () => _loadEpisodePickerWarmupData(
                playbackState,
                preferredSeasonGuid: initialSeasonData.seasonGuid,
              )
            : null,
        seasons: _episodePickerInitialSeasonOptions(
          selectedSeasonGuid: initialSeasonData.seasonGuid,
        ),
      );
      if (!mounted || result == null || result.itemId == _currentItemGuid) {
        return;
      }

      final selected = await _resolveEpisodePickerSelection(
        result,
        fallbackSeasonGuid: initialSeasonData.seasonGuid,
      );
      if (!mounted || selected == null) return;
      await _switchToEpisode(selected);
    } finally {
      if (mounted && _episodeSheetVisible) {
        _updatePlayerState(() => _episodeSheetVisible = false);
        unawaited(_syncDanmakuDynamicOcclusionConfig());
        unawaited(_startOrUpdateSystemPlaybackSession(force: true));
      }
      if (mounted && !restoreControls) {
        _scheduleControlsAutoHide();
      }
    }
  }

  Future<MediaLibraryItem?> _resolveEpisodePickerSelection(
    EpisodePickerSheetResult result, {
    required String fallbackSeasonGuid,
  }) async {
    final targetItemId = result.itemId.trim();
    if (targetItemId.isEmpty) return null;

    MediaLibraryItem? findSelected(Iterable<MediaLibraryItem> episodes) {
      for (final episode in episodes) {
        if (episode.guid == targetItemId) return episode;
      }
      return null;
    }

    final targetSeasonGuid = result.seasonGuid.trim().isNotEmpty
        ? result.seasonGuid.trim()
        : fallbackSeasonGuid.trim();
    final cachedSelected = findSelected(
      _cachedEpisodeItemsForEpisodePicker(
        preferredSeasonGuid: targetSeasonGuid,
      ),
    );
    if (cachedSelected != null) return cachedSelected;

    var localItems = const <MediaLibraryItem>[];
    if (_currentSourceIsDownloadedFile) {
      localItems = await _loadLocalDownloadedEpisodeItems(updateUi: false);
      final localSelected = findSelected(localItems);
      if (localSelected != null) return localSelected;
    }

    final selectedEpisodes = await _loadEpisodeItemsForSeason(
      targetSeasonGuid,
      fallbackLocalItems: localItems,
    );
    return findSelected(selectedEpisodes);
  }

  Future<void> _showNextEpisode() async {
    if (_externalLocalSource) return;
    final lastEpisodeMessage = AppLocalizations.of(context).playerEpisodeLast;
    final nextEpisode = await _nextEpisodeOrNull();
    if (nextEpisode == null) {
      _showTransientMessage(lastEpisodeMessage);
      return;
    }
    await _switchToEpisode(nextEpisode);
  }

  Future<void> _showPreviousEpisode() async {
    if (_externalLocalSource) return;
    final firstEpisodeMessage = AppLocalizations.of(context).playerEpisodeFirst;
    final previousEpisode = await _previousEpisodeOrNull();
    if (previousEpisode == null) {
      _showTransientMessage(firstEpisodeMessage);
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
    if (_externalLocalSource) return false;
    if (_episodeItems.length > 1) return true;
    if (_currentSourceIsDownloadedFile &&
        (_episodePickerPrefetchTimer != null ||
            _episodePickerPrefetchInFlight)) {
      return true;
    }
    if (_localDownloadedEpisodeCountHint() > 1) return true;
    if (_episodeListLoading) return true;
    if (_currentSeasonGuid.trim().isNotEmpty) return true;
    if (widget.source.seasonGuid.trim().isNotEmpty) return true;
    if (_currentEpisodeNumber > 0) return true;
    if (widget.source.episodeNumber > 0) return true;
    return false;
  }

  bool _canReuseLoadedEpisodeItems(
    List<MediaLibraryItem> items,
    String seasonGuid,
  ) {
    if (items.isEmpty) return false;
    final normalizedSeasonGuid = seasonGuid.trim();
    if (normalizedSeasonGuid.isEmpty) return true;
    if (_episodeItemsMatchPickerSeason(items, normalizedSeasonGuid)) {
      return true;
    }
    final provider = context.read<NasProvider>();
    if (_currentSourceIsDownloadedFile && provider.isConfigured) {
      return false;
    }
    return items.any((episode) => episode.guid == _currentItemGuid);
  }

  Future<List<MediaLibraryItem>> _ensureEpisodeItems() async {
    final currentSeasonGuid = _episodePickerCurrentSeasonGuid();
    if (_canReuseLoadedEpisodeItems(_episodeItems, currentSeasonGuid)) {
      return _episodeItems;
    }
    if (_episodeListLoading) return _episodeItems;

    final provider = context.read<NasProvider>();
    final l10n = AppLocalizations.of(context);
    final localItems = await _loadLocalDownloadedEpisodeItems();
    if (localItems.length > 1 && !provider.isConfigured) {
      return localItems;
    }

    final seasonGuid = await _resolveSeasonGuid();
    if (!mounted || seasonGuid.isEmpty) {
      if (localItems.isNotEmpty) {
        return localItems;
      }
      _showTransientMessage(l10n.playerEpisodeNoAvailableList);
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
        _showTransientMessage(l10n.playerEpisodeLoadListFailed('$error'));
      }
      return const <MediaLibraryItem>[];
    } finally {
      _episodeListLoading = false;
    }
  }

  Future<List<MediaLibraryItem>> _loadEpisodeItemsForPicker() async {
    final currentSeasonGuid = _episodePickerCurrentSeasonGuid();
    if (_canReuseLoadedEpisodeItems(_episodeItems, currentSeasonGuid)) {
      return _episodeItems;
    }
    if (_episodeListLoading) {
      return _episodeItems;
    }

    final provider = context.read<NasProvider>();
    final localItems = await _loadLocalDownloadedEpisodeItems(updateUi: false);
    if (localItems.length > 1 && !provider.isConfigured) {
      return localItems;
    }

    final seasonGuid = await _resolveSeasonGuid();
    if (!mounted || seasonGuid.isEmpty) {
      return localItems;
    }

    try {
      return await _loadEpisodeItemsForSeason(
        seasonGuid,
        fallbackLocalItems: localItems,
        updateCurrentSeasonState: false,
      );
    } catch (_) {
      return localItems;
    }
  }

  EpisodePickerSeasonSheetData _episodePickerInitialSeasonData(
    EpisodePickerPlaybackState playbackState,
  ) {
    final currentSeasonGuid = _episodePickerCurrentSeasonGuid();
    final cachedEpisodes = _cachedEpisodeItemsForEpisodePicker(
      preferredSeasonGuid: currentSeasonGuid,
    );
    if (cachedEpisodes.isNotEmpty) {
      final seasonGuid = currentSeasonGuid.isNotEmpty
          ? currentSeasonGuid
          : cachedEpisodes.first.parentGuid.trim();
      return _buildEpisodePickerSeasonSheetData(
        seasonGuid: seasonGuid,
        episodes: cachedEpisodes,
        playbackState: playbackState,
      );
    }
    if (_currentSourceIsDownloadedFile) {
      final localEpisodes = _localDownloadedEpisodeItemsSync();
      if (localEpisodes.length > 1) {
        final seasonGuid = _localEpisodePickerSeasonGuid(
          localEpisodes,
          currentSeasonGuid,
        );
        return _buildEpisodePickerSeasonSheetData(
          seasonGuid: seasonGuid,
          episodes: localEpisodes,
          playbackState: playbackState,
        );
      }
    }
    final fallbackEpisode = _episodePickerFallbackEpisode();
    final fallbackSeasonGuid = fallbackEpisode.parentGuid.trim();
    return _buildEpisodePickerSeasonSheetData(
      seasonGuid: fallbackSeasonGuid,
      episodes: <MediaLibraryItem>[fallbackEpisode],
      playbackState: playbackState,
    );
  }

  String _episodePickerSeriesTitle(EpisodePickerSeasonSheetData initialData) {
    final cachedEpisodes = _cachedEpisodeItemsForEpisodePicker(
      preferredSeasonGuid: initialData.seasonGuid,
    );
    if (cachedEpisodes.isNotEmpty) {
      return buildEpisodePickerSeriesTitle(
        cachedEpisodes,
        fallbackSeriesTitle: _currentSeriesTitle,
      );
    }
    if (_currentSeriesTitle.trim().isNotEmpty) {
      return _currentSeriesTitle.trim();
    }
    final heading = initialData.seasonLabel.trim();
    return heading.isNotEmpty ? heading : _currentTitle.trim();
  }

  List<TvEpisodeSeasonOptionData> _episodePickerInitialSeasonOptions({
    required String selectedSeasonGuid,
  }) {
    final seasonItems = _episodeSeasonItems;
    if (seasonItems != null && seasonItems.isNotEmpty) {
      return buildEpisodePickerSeasonOptions(
        seasonItems,
        selectedSeasonGuid: selectedSeasonGuid,
        labels: _episodePickerLabels,
      );
    }
    if (_currentSourceIsDownloadedFile) {
      final localEpisodes = _localDownloadedEpisodeItemsSync();
      if (localEpisodes.isNotEmpty) {
        return _localEpisodePickerSeasonOptions(
          seasonGuid: _localEpisodePickerSeasonGuid(
            localEpisodes,
            selectedSeasonGuid,
          ),
          episodes: localEpisodes,
        );
      }
    }
    return const <TvEpisodeSeasonOptionData>[];
  }

  Future<EpisodePickerSheetWarmupData> _loadEpisodePickerWarmupData(
    EpisodePickerPlaybackState playbackState, {
    required String preferredSeasonGuid,
  }) async {
    final provider = context.read<NasProvider>();
    final localItems = await _loadLocalDownloadedEpisodeItems(updateUi: false);
    if (_currentSourceIsDownloadedFile &&
        localItems.length > 1 &&
        !provider.isConfigured) {
      final resolvedSeasonGuid = _localEpisodePickerSeasonGuid(
        localItems,
        preferredSeasonGuid,
      );
      return EpisodePickerSheetWarmupData(
        seasonData: _buildEpisodePickerSeasonSheetData(
          seasonGuid: resolvedSeasonGuid,
          episodes: localItems,
          playbackState: playbackState,
        ),
        seasons: _localEpisodePickerSeasonOptions(
          seasonGuid: resolvedSeasonGuid,
          episodes: localItems,
        ),
      );
    }
    final episodes = await _loadEpisodeItemsForPicker();
    final seasonItems = await _loadEpisodeSeasonItems();
    final normalizedPreferredSeasonGuid = preferredSeasonGuid.trim();
    final resolvedSeasonGuid =
        normalizedPreferredSeasonGuid.isNotEmpty &&
            !_isLocalDownloadedSeasonKey(normalizedPreferredSeasonGuid)
        ? normalizedPreferredSeasonGuid
        : (episodes.isNotEmpty ? episodes.first.parentGuid.trim() : '');
    return EpisodePickerSheetWarmupData(
      seasonData: _buildEpisodePickerSeasonSheetData(
        seasonGuid: resolvedSeasonGuid,
        episodes: episodes,
        playbackState: playbackState,
      ),
      seasons: buildEpisodePickerSeasonOptions(
        seasonItems,
        selectedSeasonGuid: resolvedSeasonGuid,
        labels: _episodePickerLabels,
      ),
    );
  }

  List<TvEpisodeSeasonOptionData> _localEpisodePickerSeasonOptions({
    required String seasonGuid,
    required List<MediaLibraryItem> episodes,
  }) {
    final normalizedSeasonGuid = seasonGuid.trim();
    if (normalizedSeasonGuid.isEmpty) {
      return const <TvEpisodeSeasonOptionData>[];
    }
    final label = _seasonLabelForGuid(normalizedSeasonGuid, episodes: episodes);
    if (label.trim().isEmpty) return const <TvEpisodeSeasonOptionData>[];
    return <TvEpisodeSeasonOptionData>[
      TvEpisodeSeasonOptionData(
        guid: normalizedSeasonGuid,
        label: label.trim(),
        selected: true,
      ),
    ];
  }

  String _localEpisodePickerSeasonGuid(
    List<MediaLibraryItem> episodes,
    String preferredSeasonGuid,
  ) {
    final normalizedPreferredSeasonGuid = preferredSeasonGuid.trim();
    if (_isLocalDownloadedSeasonKey(normalizedPreferredSeasonGuid)) {
      return normalizedPreferredSeasonGuid;
    }
    final localSeasonGuid = episodes.isNotEmpty
        ? episodes.first.parentGuid.trim()
        : '';
    if (localSeasonGuid.isNotEmpty) return localSeasonGuid;
    return normalizedPreferredSeasonGuid;
  }

  MediaLibraryItem _episodePickerFallbackEpisode() {
    return MediaLibraryItem(
      guid: _currentItemGuid.trim().isNotEmpty
          ? _currentItemGuid.trim()
          : widget.source.itemGuid.trim(),
      title: _currentTitle.trim().isNotEmpty
          ? _currentTitle.trim()
          : widget.title,
      tvTitle: _currentSeriesTitle.trim(),
      type: _currentMediaType.trim().isNotEmpty
          ? _currentMediaType.trim()
          : 'episode',
      poster: _currentPosterPath.trim(),
      releaseDate: '',
      firstAirDate: '',
      lastAirDate: '',
      voteAverage: '',
      overview: '',
      watched: 0,
      watchedTs: 0,
      ts: 0,
      duration: _durationSeconds > 0
          ? _durationSeconds
          : widget.source.durationSeconds,
      seasonNumber: _currentSeasonNumber > 0
          ? _currentSeasonNumber
          : widget.source.seasonNumber,
      episodeNumber: _currentEpisodeNumber > 0
          ? _currentEpisodeNumber
          : widget.source.episodeNumber,
      numberOfSeasons: 0,
      numberOfEpisodes: 0,
      localNumberOfSeasons: 0,
      localNumberOfEpisodes: 0,
      parentGuid: _episodePickerCurrentSeasonGuid(),
      parentTitle: '',
      ancestorGuid: _currentSeriesGuid.trim(),
      ancestorName: _currentSeriesTitle.trim(),
      path: '',
    );
  }

  void _invalidateEpisodePickerSeasonCache({bool clearCurrentItems = false}) {
    _episodePickerPrefetchTimer?.cancel();
    _episodePickerPrefetchTimer = null;
    _episodePickerPrefetchGeneration++;
    _episodePickerPrefetchInFlight = false;
    _episodeSeasonItems = null;
    _episodeItemsBySeasonGuid.clear();
    _episodeItemsInflightBySeason.clear();
    if (clearCurrentItems) {
      _episodeItems = const <MediaLibraryItem>[];
    }
  }

  Future<String> _resolveSeriesGuid() async {
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

    final cacheGeneration = _episodePickerPrefetchGeneration;
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
      final frozen = List<MediaLibraryItem>.unmodifiable(seasons);
      if (cacheGeneration == _episodePickerPrefetchGeneration) {
        _episodeSeasonItems = frozen;
      }
      return frozen;
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
    final candidateSeasonGuid =
        [
          _currentSeasonGuid.trim(),
          widget.source.seasonGuid.trim(),
          widget.initialPlayInfo?.parentGuid.trim() ?? '',
        ].firstWhere(
          (guid) => guid.isNotEmpty && !_isLocalDownloadedSeasonKey(guid),
          orElse: () => '',
        );
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

  bool _isLocalDownloadedSeasonKey(String value) {
    return value.trim().startsWith(_localDownloadedSeasonKeyPrefix);
  }

  String _remoteEpisodePickerSeasonGuid() {
    final current = _currentSeasonGuid.trim();
    if (current.isNotEmpty && !_isLocalDownloadedSeasonKey(current)) {
      return current;
    }
    final sourceSeasonGuid = widget.source.seasonGuid.trim();
    if (sourceSeasonGuid.isNotEmpty &&
        !_isLocalDownloadedSeasonKey(sourceSeasonGuid)) {
      return sourceSeasonGuid;
    }
    final initialSeasonGuid = widget.initialPlayInfo?.parentGuid.trim() ?? '';
    if (initialSeasonGuid.isNotEmpty &&
        !_isLocalDownloadedSeasonKey(initialSeasonGuid)) {
      return initialSeasonGuid;
    }
    return '';
  }

  String _episodePickerCurrentSeasonGuid() {
    final remoteSeasonGuid = _remoteEpisodePickerSeasonGuid();
    if (remoteSeasonGuid.isNotEmpty) return remoteSeasonGuid;
    if (_currentSourceIsDownloadedFile) {
      final currentRecord = _currentDownloadedEpisodeRecordSync();
      if (currentRecord != null) {
        final groupKey = _localDownloadedSeasonKey(currentRecord);
        if (groupKey.isNotEmpty) return groupKey;
      }
    }
    return '';
  }

  Future<List<MediaLibraryItem>> _loadEpisodeItemsForSeason(
    String seasonGuid, {
    List<MediaLibraryItem> fallbackLocalItems = const <MediaLibraryItem>[],
    bool updateCurrentSeasonState = false,
  }) async {
    final normalizedSeasonGuid = seasonGuid.trim();
    if (normalizedSeasonGuid.isEmpty) return fallbackLocalItems;
    final cacheGeneration = _episodePickerPrefetchGeneration;

    if (_isLocalDownloadedSeasonKey(normalizedSeasonGuid)) {
      final localItems = await _loadLocalDownloadedEpisodeItems(
        updateUi: false,
      );
      return localItems.isNotEmpty ? localItems : fallbackLocalItems;
    }

    final cached = _episodeItemsBySeasonGuid[normalizedSeasonGuid];
    if (cached != null) {
      if (updateCurrentSeasonState &&
          mounted &&
          cacheGeneration == _episodePickerPrefetchGeneration) {
        _applyLoadedEpisodeItems(normalizedSeasonGuid, cached);
      }
      return cached;
    }

    final inflight = _episodeItemsInflightBySeason[normalizedSeasonGuid];
    if (inflight != null) {
      final items = await inflight;
      if (updateCurrentSeasonState &&
          mounted &&
          cacheGeneration == _episodePickerPrefetchGeneration) {
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
      if (cacheGeneration == _episodePickerPrefetchGeneration) {
        _episodeItemsBySeasonGuid[normalizedSeasonGuid] = frozen;
      }
      return frozen;
    }();
    _episodeItemsInflightBySeason[normalizedSeasonGuid] = future;
    try {
      final items = await future;
      if (updateCurrentSeasonState &&
          mounted &&
          cacheGeneration == _episodePickerPrefetchGeneration) {
        _applyLoadedEpisodeItems(normalizedSeasonGuid, items);
      }
      return items;
    } catch (_) {
      if (fallbackLocalItems.isNotEmpty) {
        return fallbackLocalItems;
      }
      rethrow;
    } finally {
      if (identical(
        _episodeItemsInflightBySeason[normalizedSeasonGuid],
        future,
      )) {
        _episodeItemsInflightBySeason.remove(normalizedSeasonGuid);
      }
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
        return buildEpisodePickerSeasonLabel(
          season,
          labels: _episodePickerLabels,
        );
      }
    }
    if (episodes.isNotEmpty) {
      return buildEpisodePickerSeasonLabel(
        episodes.first,
        labels: _episodePickerLabels,
      );
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
              labels: _episodePickerLabels,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<EpisodePickerSeasonSheetData> _loadEpisodePickerSeasonSheetData(
    String seasonGuid,
    EpisodePickerPlaybackState playbackState,
  ) async {
    final l10n = AppLocalizations.of(context);
    try {
      final episodes = await _loadEpisodeItemsForSeason(seasonGuid);
      return _buildEpisodePickerSeasonSheetData(
        seasonGuid: seasonGuid,
        episodes: episodes,
        playbackState: playbackState,
      );
    } catch (error) {
      if (mounted) {
        _showTransientMessage(l10n.playerEpisodeLoadSeasonFailed('$error'));
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

  Future<List<MediaLibraryItem>> _loadLocalDownloadedEpisodeItems({
    bool updateUi = true,
  }) async {
    if (!_currentSourceIsDownloadedFile) return const <MediaLibraryItem>[];
    await DownloadTaskService.instance.initialize();
    final records = _localDownloadedEpisodeRecordsSync();
    if (records.isEmpty) return const <MediaLibraryItem>[];
    final frozen = _buildLocalDownloadedEpisodeItems(records);
    if (frozen.isEmpty) return const <MediaLibraryItem>[];
    if (updateUi && mounted) {
      final resolvedSeasonGuid = frozen.first.parentGuid.trim();
      _updatePlayerState(() {
        if (_currentSeasonGuid.trim().isEmpty &&
            resolvedSeasonGuid.isNotEmpty) {
          _currentSeasonGuid = resolvedSeasonGuid;
        }
        _episodeItems = frozen;
      });
    }
    return frozen;
  }

  List<MediaLibraryItem> _localDownloadedEpisodeItemsSync() {
    if (!_currentSourceIsDownloadedFile) return const <MediaLibraryItem>[];
    final records = _localDownloadedEpisodeRecordsSync();
    if (records.isEmpty) return const <MediaLibraryItem>[];
    return _buildLocalDownloadedEpisodeItems(records);
  }

  List<MediaLibraryItem> _buildLocalDownloadedEpisodeItems(
    List<DownloadTaskRecord> records,
  ) {
    if (records.isEmpty) return const <MediaLibraryItem>[];
    final resolvedSeasonGuid = _resolvedLocalDownloadedSeasonGuid(records);
    final items =
        records
            .map(
              (record) => _localEpisodeItemFromRecord(
                record,
                seasonGuid: resolvedSeasonGuid,
              ),
            )
            .toList(growable: false)
          ..sort((a, b) {
            final byEpisode = _episodeSortOrder(
              a,
            ).compareTo(_episodeSortOrder(b));
            if (byEpisode != 0) return byEpisode;
            return a.guid.compareTo(b.guid);
          });
    final frozen = List<MediaLibraryItem>.unmodifiable(items);
    for (final cacheKey in _localDownloadedEpisodeCacheKeys(
      records,
      preferredSeasonGuid: resolvedSeasonGuid,
    )) {
      _episodeItemsBySeasonGuid[cacheKey] = frozen;
    }
    return frozen;
  }

  List<DownloadTaskRecord> _localDownloadedEpisodeRecordsSync() {
    if (!_currentSourceIsDownloadedFile) return const <DownloadTaskRecord>[];
    final service = DownloadTaskService.instance;
    final currentRecord = _currentDownloadedEpisodeRecordSync();
    if (currentRecord == null) return const <DownloadTaskRecord>[];
    final groupCandidates = _localDownloadedGroupCandidates(currentRecord);
    if (groupCandidates.isEmpty) {
      return <DownloadTaskRecord>[currentRecord];
    }
    final groupedRecords = service.downloadedRecords
        .where(
          (record) => _matchesLocalDownloadedGroup(
            candidate: record,
            currentRecord: currentRecord,
            groupCandidates: groupCandidates,
          ),
        )
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

  Set<String> _localDownloadedGroupCandidates(
    DownloadTaskRecord currentRecord,
  ) {
    return <String>{
      currentRecord.groupId.trim(),
      _localDownloadedGroupDirectoryPath(currentRecord),
      _currentSeasonGuid.trim(),
      widget.source.seasonGuid.trim(),
      widget.initialPlayInfo?.parentGuid.trim() ?? '',
    }..removeWhere((value) => value.isEmpty);
  }

  bool _matchesLocalDownloadedGroup({
    required DownloadTaskRecord candidate,
    required DownloadTaskRecord currentRecord,
    required Set<String> groupCandidates,
  }) {
    if (candidate.id == currentRecord.id) return true;
    if (groupCandidates.contains(candidate.groupId.trim())) {
      return true;
    }
    if (groupCandidates.contains(
      _localDownloadedGroupDirectoryPath(candidate),
    )) {
      return true;
    }
    return false;
  }

  String _localDownloadedSeasonKey(DownloadTaskRecord record) {
    final groupId = record.groupId.trim();
    if (groupId.isNotEmpty) {
      return '$_localDownloadedSeasonKeyPrefix$groupId';
    }
    final groupDirectory = _localDownloadedGroupDirectoryPath(record);
    if (groupDirectory.isNotEmpty) {
      return '$_localDownloadedSeasonKeyPrefix$groupDirectory';
    }
    final itemGuid = record.itemGuid.trim();
    if (itemGuid.isNotEmpty) {
      return '$_localDownloadedSeasonKeyPrefix$itemGuid';
    }
    final recordId = record.id.trim();
    if (recordId.isNotEmpty) {
      return '$_localDownloadedSeasonKeyPrefix$recordId';
    }
    return '';
  }

  String _localDownloadedGroupDirectoryPath(DownloadTaskRecord record) {
    final path = record.filePath.trim();
    if (path.isEmpty) return '';
    final videoFile = File(path);
    final episodeDirectory = videoFile.parent;
    final fileName = _localDownloadedLastPathSegment(videoFile.path);
    final directoryName = _localDownloadedLastPathSegment(
      episodeDirectory.path,
    );
    final baseName = _localDownloadedFileNameBase(fileName);
    if (directoryName == baseName || directoryName.startsWith('${baseName}_')) {
      return episodeDirectory.parent.path;
    }
    return episodeDirectory.path;
  }

  String _localDownloadedLastPathSegment(String path) {
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized.split('/').where((value) => value.isNotEmpty);
    if (segments.isEmpty) return '';
    return segments.last;
  }

  String _localDownloadedFileNameBase(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot <= 0) return fileName;
    return fileName.substring(0, lastDot);
  }

  String _localDownloadedGroupKey(DownloadTaskRecord record) {
    final seasonKey = _localDownloadedSeasonKey(record);
    if (seasonKey.isNotEmpty) return seasonKey;
    final itemGuid = record.itemGuid.trim();
    if (itemGuid.isNotEmpty) return itemGuid;
    return record.id.trim();
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

  int _localDownloadedSeasonNumberFor(DownloadTaskRecord record) {
    final textCandidates = <String>[
      record.groupTitle,
      record.title,
      record.fileName,
    ];
    for (final text in textCandidates) {
      final seasonNumber = _localDownloadedSeasonNumberFromText(text);
      if (seasonNumber > 0) return seasonNumber;
    }
    if (_currentSeasonNumber > 0) return _currentSeasonNumber;
    if (widget.source.seasonNumber > 0) return widget.source.seasonNumber;
    for (final text in textCandidates) {
      if (_localDownloadedTextLooksSpecialSeason(text)) return 0;
    }
    return -1;
  }

  int _localDownloadedSeasonNumberFromText(String text) {
    final chineseSeasonNumber = _localDownloadedNumberBetweenMarkers(
      text,
      0x7b2c,
      0x5b63,
    );
    if (chineseSeasonNumber > 0) return chineseSeasonNumber;

    final seasonEpisodeMatch = RegExp(
      r'\b[sS]\s*0*(\d{1,3})\s*[eE]\s*0*\d{1,4}\b',
    ).firstMatch(text);
    if (seasonEpisodeMatch != null) {
      final value = int.tryParse(seasonEpisodeMatch.group(1) ?? '');
      if (value != null && value > 0) return value;
    }

    final seasonMatch = RegExp(
      r'\bseason\s*0*(\d{1,3})\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (seasonMatch != null) {
      final value = int.tryParse(seasonMatch.group(1) ?? '');
      if (value != null && value > 0) return value;
    }

    final shortSeasonMatch = RegExp(r'\b[sS]\s*0*(\d{1,3})\b').firstMatch(text);
    if (shortSeasonMatch != null) {
      final value = int.tryParse(shortSeasonMatch.group(1) ?? '');
      if (value != null && value > 0) return value;
    }
    return -1;
  }

  int _localDownloadedNumberBetweenMarkers(
    String text,
    int startMarker,
    int endMarker,
  ) {
    final units = text.codeUnits;
    for (var index = 0; index < units.length; index++) {
      if (units[index] != startMarker) continue;
      final buffer = StringBuffer();
      final end = math.min(units.length, index + 12);
      for (var cursor = index + 1; cursor < end; cursor++) {
        final unit = units[cursor];
        if (unit >= 0x30 && unit <= 0x39) {
          buffer.writeCharCode(unit);
          continue;
        }
        if (unit == endMarker) {
          if (buffer.isEmpty) break;
          final value = int.tryParse(buffer.toString());
          if (value != null && value > 0) return value;
          break;
        }
        if (_isLocalDownloadedSeasonWhitespace(unit)) continue;
        if (buffer.isNotEmpty) break;
      }
    }
    return -1;
  }

  bool _isLocalDownloadedSeasonWhitespace(int unit) {
    return unit == 0x09 ||
        unit == 0x0a ||
        unit == 0x0d ||
        unit == 0x20 ||
        unit == 0x3000;
  }

  bool _localDownloadedTextLooksSpecialSeason(String text) {
    final normalized = text.toLowerCase();
    if (RegExp(r'\b(sp|special|ova|oad)\b').hasMatch(normalized)) {
      return true;
    }
    return _containsCodeUnitSequence(text, const <int>[0x7279, 0x522b]) ||
        _containsCodeUnitSequence(text, const <int>[0x7279, 0x5225]);
  }

  bool _containsCodeUnitSequence(String text, List<int> sequence) {
    if (sequence.isEmpty) return true;
    final units = text.codeUnits;
    if (units.length < sequence.length) return false;
    for (var index = 0; index <= units.length - sequence.length; index++) {
      var matched = true;
      for (var offset = 0; offset < sequence.length; offset++) {
        if (units[index + offset] != sequence[offset]) {
          matched = false;
          break;
        }
      }
      if (matched) return true;
    }
    return false;
  }

  String _resolvedLocalDownloadedSeasonGuid(List<DownloadTaskRecord> records) {
    final candidates = <String>[
      for (final record in records) _localDownloadedGroupKey(record),
    ];
    return candidates.firstWhere((value) => value.isNotEmpty, orElse: () => '');
  }

  List<String> _localDownloadedEpisodeCacheKeys(
    List<DownloadTaskRecord> records, {
    String preferredSeasonGuid = '',
  }) {
    final keys = <String>{
      preferredSeasonGuid.trim(),
      for (final record in records) _localDownloadedGroupKey(record),
    }..removeWhere((value) => value.isEmpty);
    return keys.toList(growable: false);
  }

  MediaLibraryItem _localEpisodeItemFromRecord(
    DownloadTaskRecord record, {
    String seasonGuid = '',
  }) {
    // 离线选集优先用已落盘的本地封面（在线 URL 离线打不开）；都没有才退在线/source。
    final localCover = DownloadTaskService.instance.resolveExistingLocalCover(
      record,
    );
    final poster = localCover.isNotEmpty
        ? localCover
        : [
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
      tvTitle: _currentSeriesTitle.trim().isNotEmpty
          ? _currentSeriesTitle.trim()
          : record.groupTitle.trim(),
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
      seasonNumber: _localDownloadedSeasonNumberFor(record),
      episodeNumber: episodeNumber >= (1 << 20) ? 0 : episodeNumber,
      numberOfSeasons: 0,
      numberOfEpisodes: 0,
      localNumberOfSeasons: 0,
      localNumberOfEpisodes: 0,
      parentGuid: seasonGuid.trim().isNotEmpty
          ? seasonGuid.trim()
          : _localDownloadedSeasonKey(record),
      parentTitle: record.groupTitle.trim(),
      ancestorGuid: _currentSeriesGuid.trim(),
      ancestorName: _currentSeriesTitle.trim().isNotEmpty
          ? _currentSeriesTitle.trim()
          : record.groupTitle.trim(),
      path: record.filePath.trim(),
      resolutions: record.resolution.trim().isEmpty
          ? const <String>[]
          : <String>[record.resolution.trim()],
    );
  }

  Future<String> _resolveSeasonGuid() async {
    final existing = _currentSeasonGuid.trim();
    if (existing.isNotEmpty && !_isLocalDownloadedSeasonKey(existing)) {
      return existing;
    }
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
    final l10n = AppLocalizations.of(context);
    final episodeLabel = episode.episodeNumber > 0
        ? l10n.playerEpisodeNumberLabel(episode.episodeNumber)
        : episode.title.trim();
    if (episodeLabel.isEmpty) {
      return l10n.playerEpisodePreparingPlayback;
    }
    return l10n.playerEpisodeSwitchingTo(episodeLabel);
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
    final episodeGuid = episode.guid.trim();
    final episodePath = episode.path.trim();
    return _localDownloadedEpisodeRecordsSync()
        .cast<DownloadTaskRecord?>()
        .firstWhere((record) {
          if (record == null) return false;
          if (record.itemGuid.trim().isNotEmpty &&
              record.itemGuid.trim() == episodeGuid) {
            return true;
          }
          if (record.id.trim().isNotEmpty && record.id.trim() == episodeGuid) {
            return true;
          }
          if (episodePath.isNotEmpty && record.filePath.trim() == episodePath) {
            return true;
          }
          return false;
        }, orElse: () => null);
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
        localRecord ?? _preferredDownloadedRecordForEpisode(episode);
    if (resolvedLocalRecord != null) {
      return _prepareLocalDownloadedEpisodeSwitchResult(
        episode,
        resolvedLocalRecord,
      );
    }
    return _prepareRemoteEpisodeSwitchResult(episode);
  }

  DownloadTaskRecord? _preferredDownloadedRecordForEpisode(
    MediaLibraryItem episode,
  ) {
    final service = DownloadTaskService.instance;
    final episodeGuid = episode.guid.trim();
    final preferredResolution = _currentResolution.trim();
    if (episodeGuid.isNotEmpty) {
      final preferred = service.downloadedRecordForItem(
        episodeGuid,
        resolution: preferredResolution,
      );
      if (preferred != null) return preferred;
      final any = service.downloadedRecordForItem(episodeGuid);
      if (any != null) return any;
    }
    if (_currentSourceIsDownloadedFile) {
      final grouped = _localDownloadedRecordForEpisode(episode);
      if (grouped != null) return grouped;
    }
    return null;
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
    final fallbackAudioTracks = record.audioTracks;
    final audioTracks = playbackStream?.audioStreams.isNotEmpty == true
        ? playbackStream!.audioStreams
        : (resolvedMediaGuid.isEmpty
              ? fallbackAudioTracks
              : trackData?.audiosForMedia(resolvedMediaGuid) ??
                    fallbackAudioTracks);
    final selectedAudio = PlayDetailTrackSelector.selectedOrFirstAudio(
      selectedAudioGuid: _normalizedAudioGuid() ?? playInfo?.audioGuid ?? '',
      audioTracks: audioTracks,
    );
    final fallbackSubtitleTracks = record.subtitleTracks;
    final subtitleTracks = resolvedMediaGuid.isEmpty
        ? fallbackSubtitleTracks
        : trackData?.subtitlesForMedia(resolvedMediaGuid) ??
              fallbackSubtitleTracks;
    final networkDurationSeconds = playItem?.duration ?? episode.duration;
    final sourceTs = playInfo == null
        ? 0
        : (playInfo.ts > 0 ? playInfo.ts : playItem?.watchedTs ?? 0);
    final networkCompleted =
        playInfo != null &&
        networkDurationSeconds > 0 &&
        ((networkDurationSeconds - sourceTs) <= 0 || playItem?.isWatched == 1);
    final resume = await PlaybackResumePositionResolver.resolve(
      videoIds: <String>[
        playItem?.guid ?? '',
        episode.guid,
        record.itemGuid,
        record.id,
      ],
      durationSeconds: networkDurationSeconds,
      networkPositionSeconds: sourceTs,
      networkPositionAvailable: playInfo != null,
      networkCompleted: networkCompleted,
    );
    final durationSeconds = resume.effectiveDurationSeconds;
    final rawResumeStartPosition = Duration(seconds: resume.position.inSeconds);
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
      subtitleTracks: subtitleTracks,
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
    final pausedAfterReload = shouldPromptForAutoPlay
        ? true
        : !shouldResumePlayback;
    final effectiveSource = source.copyWith(startPaused: pausedAfterReload);
    _markAwaitingVisualPlaybackStart(
      effectiveSource.startPosition,
      targetPaused: pausedAfterReload,
    );
    _controller.prepareForSourceLoad(
      effectiveSource,
      paused: pausedAfterReload,
    );
    _enablePlaybackProgressTransitionCompletion(
      targetPaused: pausedAfterReload,
    );
    await _controller.reload(effectiveSource);
    _showControls();
  }

  Future<void> _switchToEpisode(
    MediaLibraryItem episode, {
    bool fromAutoPlay = false,
  }) async {
    if (_externalLocalSource) return;
    if (episode.guid.trim().isEmpty || episode.guid == _currentItemGuid) return;
    final shouldResumePlayback =
        fromAutoPlay || !_controller.value.value.paused;
    var reloadStarted = false;
    final l10n = AppLocalizations.of(context);
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
      _showTransientMessage(l10n.playerEpisodeSwitchFailed('$error'));
    } finally {
      if (!reloadStarted) {
        _cancelPendingLoadingTransition();
      }
    }
  }
}
