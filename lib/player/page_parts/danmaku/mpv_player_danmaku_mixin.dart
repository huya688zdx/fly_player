part of mpv_player_page;

const String _playerSettingsDanmakuPageId = 'player_settings_danmaku';
const String _playerSettingsDanmakuSavedPageId =
    'player_settings_danmaku_saved';
const String _playerSettingsDanmakuImportPageId =
    'player_settings_danmaku_import';
const String _playerSettingsDanmakuSearchPageId =
    'player_settings_danmaku_search';
const List<double> _danmakuAreaPresets = <double>[0.10, 0.25, 0.50, 0.75, 1.0];

extension _MpvPlayerDanmakuMixin on _MpvPlayerPageState {
  static const String _danmakuAutoBlockNoResult = 'no_result';
  static const String _danmakuAutoBlockFailed = 'failed';

  bool get _danmakuEnabled => _danmakuController.settings.enabled;

  DanDanPlayResolver get _danDanPlayResolver => DanDanPlayResolver(
    DanDanPlayApi(
      appId: DanDanPlayConfig.appId,
      appSecrets: DanDanPlayConfig.appSecrets,
    ),
  );

  String get _danmakuToggleAsset => _danmakuEnabled
      ? 'assets/icons/player_danmaku_on.svg'
      : 'assets/icons/player_danmaku_off.svg';

  Future<void> _loadDanmakuPreferences() async {
    await DanDanPlayConfig.ensureLoaded();
    await _danmakuController.initialize();
    _syncDanmakuMediaContext();
    await _loadSavedLocalDanmakuSources();
    await _tryLoadPreferredDanmakuSource();
    await _syncDanmakuDynamicOcclusionConfig();
    if (!mounted) return;
    _updatePlayerState(() {});
  }

  void _syncDanmakuMediaContext({bool triggerAutoLoad = false}) {
    final requestToken = ++_danmakuContextToken;
    _activeDanmakuSourceKey = null;
    _savedLocalDanmakuSources = const <DanmakuSavedSource>[];
    _danmakuSearchResults = const <DanDanPlayEpisodeSearchItem>[];
    _danmakuSearchLoading = false;
    _danmakuSearchPreparedContextKey = '';
    _danmakuSearchLastCompletedContextKey = '';
    _danmakuSearchController.clear();
    _danmakuController.updateMediaContext(
      title: _currentSeriesTitle.trim().isNotEmpty
          ? _currentSeriesTitle
          : _currentTitle,
      seasonGuid: _currentSeasonGuid,
      seasonNumber: _currentSeasonNumber,
      episodeNumber: _currentEpisodeNumber,
    );
    unawaited(
      _loadSavedLocalDanmakuSources(
        refreshUi: mounted,
        requestToken: requestToken,
      ),
    );
    if (triggerAutoLoad &&
        _danmakuController.ready &&
        _danmakuController.settings.enabled) {
      unawaited(_tryLoadPreferredDanmakuSource(requestToken: requestToken));
    }
  }

  bool _isActiveDanmakuContext(int requestToken, String mediaKey) {
    return mounted &&
        requestToken == _danmakuContextToken &&
        mediaKey == _currentDanmakuMediaKey();
  }

  String _currentDanmakuMediaKey() {
    final itemGuid = _currentItemGuid.trim();
    final mediaGuid = _currentMediaGuid.trim();
    final seasonGuid = _currentSeasonGuid.trim();
    final seriesTitle = _currentSeriesTitle.trim();
    final itemTitle = _currentTitle.trim();
    if (itemGuid.isNotEmpty ||
        mediaGuid.isNotEmpty ||
        seasonGuid.isNotEmpty ||
        _currentEpisodeNumber > 0) {
      return [
        'v2',
        'item=$itemGuid',
        'media=$mediaGuid',
        'season=$seasonGuid',
        's=$_currentSeasonNumber',
        'e=$_currentEpisodeNumber',
      ].join('|');
    }
    final title = (seriesTitle.isNotEmpty ? seriesTitle : itemTitle).trim();
    return 'fallback:v2:$title:$_currentSeasonNumber:$_currentEpisodeNumber';
  }

  Future<void> _loadSavedLocalDanmakuSources({
    bool refreshUi = false,
    int? requestToken,
  }) async {
    final mediaKey = _currentDanmakuMediaKey();
    final sources = await _danmakuSavedSourceStore.loadForMedia(mediaKey);
    if (requestToken != null && !_isActiveDanmakuContext(requestToken, mediaKey)) {
      return;
    }
    if (!mounted) return;
    _savedLocalDanmakuSources = sources;
    if (refreshUi) {
      _updatePlayerState(() {});
    }
  }

  Future<bool> _restoreSavedLocalDanmakuIfNeeded({int? requestToken}) async {
    final settings = _danmakuController.settings;
    if (!settings.enabled) return false;
    final mediaKey = _currentDanmakuMediaKey();
    final activeSourceKey = await _danmakuSavedSourceStore.loadActiveSourceKey(
      mediaKey,
    );
    if (requestToken != null && !_isActiveDanmakuContext(requestToken, mediaKey)) {
      return false;
    }
    if (activeSourceKey != null && activeSourceKey.trim().isNotEmpty) {
      final activeSource = _savedLocalDanmakuSources
          .where((item) => item.sourceKey == activeSourceKey)
          .cast<DanmakuSavedSource?>()
          .firstWhere((item) => item != null, orElse: () => null);
      if (activeSource != null) {
        final restored = await _restoreSavedDanmakuSource(
          activeSource,
          requestToken: requestToken,
        );
        if (restored) return true;
        await _loadSavedLocalDanmakuSources(requestToken: requestToken);
      }
    }
    final preferredType = settings.preferLocalSource
        ? DanmakuSavedSourceType.localFile
        : DanmakuSavedSourceType.danDanPlay;
    final preferredSource = _pickNewestSavedDanmakuSourceOfType(preferredType);
    if (preferredSource == null) return false;
    return _restoreSavedDanmakuSource(
      preferredSource,
      requestToken: requestToken,
    );
  }

  Future<bool> _restoreSavedDanmakuSource(
    DanmakuSavedSource source, {
    int? requestToken,
  }) async {
    final mediaKey = _currentDanmakuMediaKey();
    try {
      final result = await _loadDanmakuResultForSource(source);
      if (result == null) return false;
      if (requestToken != null && !_isActiveDanmakuContext(requestToken, mediaKey)) {
        return false;
      }
      if (!mounted) return false;
      _danmakuController.applyImportedComments(
        sourceLabel: result.sourceLabel,
        sourceType: source.isDanDanPlay
            ? DanmakuLoadedSourceType.network
            : DanmakuLoadedSourceType.local,
        comments: result.comments,
      );
      _activeDanmakuSourceKey = source.sourceKey;
      await _danmakuSavedSourceStore.setActiveSourceKey(
        mediaKey: mediaKey,
        sourceKey: source.sourceKey,
      );
      return true;
    } catch (error, stackTrace) {
      debugPrint(
        '[DANMAKU][RESTORE] failed sourceKey=${source.sourceKey} '
        'type=${source.type.name} error=$error',
      );
      unawaited(
        AppLogService.instance.recordWarning(
          error: error,
          stackTrace: stackTrace,
          source: 'danmaku.restore_saved',
          details:
              'mediaKey=$mediaKey sourceKey=${source.sourceKey} '
              'type=${source.type.name}',
        ),
      );
      await _danmakuSavedSourceStore.removeSource(
        mediaKey: mediaKey,
        sourceKey: source.sourceKey,
      );
      await _loadSavedLocalDanmakuSources(
        refreshUi: mounted,
        requestToken: requestToken,
      );
      return false;
    }
  }

  DanmakuSavedSource? _pickNewestSavedDanmakuSourceOfType(
    DanmakuSavedSourceType type,
  ) {
    return _savedLocalDanmakuSources
        .where((item) => item.type == type)
        .cast<DanmakuSavedSource?>()
        .firstWhere((item) => item != null, orElse: () => null);
  }

  Future<DanmakuImportResult?> _loadDanmakuResultForSource(
    DanmakuSavedSource source,
  ) {
    if (source.isDanDanPlay) {
      return _danDanPlayResolver.importEpisodeById(
        DanDanPlayEpisodeSearchItem(
          episodeId: int.tryParse(source.sourceKey) ?? 0,
          animeTitle: source.detail,
          episodeTitle: source.label,
          episodeNumber: _currentEpisodeNumber,
        ),
      );
    }
    if (!StorageAccessService.isScopedIdentifier(source.sourceKey)) {
      return DanmakuImportParser.parseFile(source.sourceKey);
    }
    return (() async {
      final bytes = await StorageAccessService.readScopedFileBytes(
        source.sourceKey,
      );
      if (bytes == null || bytes.isEmpty) {
        throw const FileSystemException('无法读取已保存的弹幕文件');
      }
      return DanmakuImportParser.parseBytes(
        bytes,
        fileName: source.detail.trim().isNotEmpty
            ? source.detail.trim()
            : source.label,
      );
    })();
  }

  Future<bool> _tryLoadPreferredDanmakuSource({int? requestToken}) async {
    final settings = _danmakuController.settings;
    if (!settings.enabled) return false;
    final mediaKey = _currentDanmakuMediaKey();
    await _loadSavedLocalDanmakuSources(requestToken: requestToken);
    if (requestToken != null && !_isActiveDanmakuContext(requestToken, mediaKey)) {
      return false;
    }
    if (await _restoreSavedLocalDanmakuIfNeeded(requestToken: requestToken)) {
      return true;
    }
    if (settings.preferLocalSource) {
      final networkSaved = _pickNewestSavedDanmakuSourceOfType(
        DanmakuSavedSourceType.danDanPlay,
      );
      if (networkSaved != null &&
          await _restoreSavedDanmakuSource(
            networkSaved,
            requestToken: requestToken,
          )) {
        return true;
      }
      return _tryLoadDanDanPlayComments(requestToken: requestToken);
    }
    if (await _tryLoadDanDanPlayComments(requestToken: requestToken)) {
      return true;
    }
    final localSaved = _pickNewestSavedDanmakuSourceOfType(
      DanmakuSavedSourceType.localFile,
    );
    if (localSaved != null) {
      return _restoreSavedDanmakuSource(
        localSaved,
        requestToken: requestToken,
      );
    }
    return false;
  }

  Future<bool> _tryLoadDanDanPlayComments({int? requestToken}) async {
    final settings = _danmakuController.settings;
    if (!await DanDanPlayConfig.ensureConfigured()) return false;
    if (!settings.enabled) return false;
    final mediaKey = _currentDanmakuMediaKey();
    final blockedReason = await _danmakuSavedSourceStore
        .loadAutoMatchBlockedReason(mediaKey);
    if (blockedReason != null && blockedReason.isNotEmpty) {
      debugPrint(
        '[DANMAKU][AUTO_LOAD] skipped mediaKey=$mediaKey blocked=$blockedReason',
      );
      return false;
    }

    try {
      final resolved = await _danDanPlayResolver.resolveForPlayback(
        seriesTitle: _currentSeriesTitle.trim().isNotEmpty
            ? _currentSeriesTitle
            : _currentTitle,
        seasonNumber: _currentSeasonNumber,
        episodeNumber: _currentEpisodeNumber,
        tmdbId: _currentTmdbId,
      );
      if (resolved == null) {
        await _danmakuSavedSourceStore.saveAutoMatchBlockedReason(
          mediaKey: mediaKey,
          reason: _danmakuAutoBlockNoResult,
        );
        if (mounted) {
          _showTopTip(
            '当前片源自动匹配弹幕无结果，后续不再自动请求，可手动搜索。',
            context.appColors.warning,
          );
        }
        return false;
      }
      if (requestToken != null && !_isActiveDanmakuContext(requestToken, mediaKey)) {
        return false;
      }
      if (!mounted) return false;
      final result = resolved.result;
      final matchedItem = resolved.item;
      _danmakuController.applyImportedComments(
        sourceLabel: result.sourceLabel,
        sourceType: DanmakuLoadedSourceType.network,
        comments: result.comments,
      );
      final savedSource = DanmakuSavedSource(
        type: DanmakuSavedSourceType.danDanPlay,
        mediaKey: mediaKey,
        sourceKey: matchedItem.episodeId.toString(),
        label: matchedItem.displayTitle,
        detail: matchedItem.displaySubtitle,
        ancestorName: _currentAncestorName.trim(),
        seriesTitle: _currentSeriesTitle.trim(),
        itemTitle: _currentTitle.trim(),
        itemGuid: _currentItemGuid.trim(),
        seasonGuid: _currentSeasonGuid.trim(),
        mediaGuid: _currentMediaGuid.trim(),
        seasonNumber: _currentSeasonNumber,
        episodeNumber: _currentEpisodeNumber,
        mediaType: _currentMediaType.trim(),
        commentCount: result.comments.length,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      await _danmakuSavedSourceStore.saveSource(savedSource);
      await _loadSavedLocalDanmakuSources(requestToken: requestToken);
      _activeDanmakuSourceKey = savedSource.sourceKey;
      await _danmakuSavedSourceStore.setActiveSourceKey(
        mediaKey: mediaKey,
        sourceKey: savedSource.sourceKey,
      );
      _updatePlayerState(() {});
      _showTopTip(
        '已加载 ${result.comments.length} 条弹幕',
        context.appColors.success,
      );
      return true;
    } catch (error, stackTrace) {
      await _danmakuSavedSourceStore.saveAutoMatchBlockedReason(
        mediaKey: mediaKey,
        reason: _danmakuAutoBlockFailed,
      );
      final seriesTitle = _currentSeriesTitle.trim().isNotEmpty
          ? _currentSeriesTitle
          : _currentTitle;
      debugPrint(
        '[DANMAKU][AUTO_LOAD] failed title=$seriesTitle '
        'season=$_currentSeasonNumber episode=$_currentEpisodeNumber '
        'tmdb=$_currentTmdbId error=$error',
      );
      unawaited(
        AppLogService.instance.recordWarning(
          error: error,
          stackTrace: stackTrace,
          source: 'danmaku.auto_load',
          details:
              'title=$seriesTitle season=$_currentSeasonNumber '
              'episode=$_currentEpisodeNumber tmdb=$_currentTmdbId',
        ),
      );
      if (mounted) {
        final reason = error is DanDanPlayApiException
            ? error.message
            : '当前片源自动匹配弹幕失败';
        _showTopTip('$reason，后续不再自动请求，可手动搜索。', context.appColors.warning);
      }
      return false;
    }
  }

  String _defaultDanmakuSearchKeyword() {
    return DanDanPlayResolver.normalizeSeriesTitle(
      _currentSeriesTitle.trim().isNotEmpty
          ? _currentSeriesTitle
          : _currentTitle,
    );
  }

  String _danmakuSearchContextKey([String? keyword]) {
    final normalizedKeyword = DanDanPlayResolver.normalizeSeriesTitle(
      keyword ?? _danmakuSearchController.text,
    );
    final normalizedTmdbId = DanDanPlayResolver.normalizeTmdbId(_currentTmdbId);
    return [
      _currentDanmakuMediaKey(),
      'q=$normalizedKeyword',
      'tmdb=${normalizedTmdbId ?? ''}',
    ].join('|');
  }

  void _primeDanmakuSearch() {
    final keyword = _defaultDanmakuSearchKeyword();
    final contextKey = _danmakuSearchContextKey(keyword);
    if (_danmakuSearchPreparedContextKey == contextKey) {
      return;
    }
    _danmakuSearchPreparedContextKey = contextKey;
    _danmakuSearchLastCompletedContextKey = '';
    _danmakuSearchResults = const <DanDanPlayEpisodeSearchItem>[];
    if (_danmakuSearchController.text.trim() == keyword.trim()) {
      return;
    }
    if (keyword.isNotEmpty) {
      _danmakuSearchController.value = TextEditingValue(
        text: keyword,
        selection: TextSelection.collapsed(offset: keyword.length),
      );
    } else {
      _danmakuSearchController.clear();
    }
  }

  String _danmakuSearchContextText() {
    final title = _currentSeriesTitle.trim().isNotEmpty
        ? _currentSeriesTitle.trim()
        : _currentTitle.trim();
    final parts = <String>[
      if (title.isNotEmpty) title,
      if (_currentSeasonNumber > 0) '?$_currentSeasonNumber?',
      if (_currentEpisodeNumber > 0) '?$_currentEpisodeNumber?',
    ];
    return parts.join(' ');
  }
}
