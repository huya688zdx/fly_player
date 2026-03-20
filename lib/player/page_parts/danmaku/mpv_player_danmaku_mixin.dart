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
  bool get _danmakuEnabled => _danmakuController.settings.enabled;

  DanDanPlayResolver get _danDanPlayResolver => DanDanPlayResolver(
    DanDanPlayApi(
      appId: DanDanPlayConfig.appId,
      appSecret: DanDanPlayConfig.appSecret,
    ),
  );

  String get _danmakuToggleAsset => _danmakuEnabled
      ? 'assets/icons/player_danmaku_on.svg'
      : 'assets/icons/player_danmaku_off.svg';

  Future<void> _loadDanmakuPreferences() async {
    await _danmakuController.initialize();
    _syncDanmakuMediaContext();
    await _loadSavedLocalDanmakuSources();
    await _tryLoadPreferredDanmakuSource();
    if (!mounted) return;
    _updatePlayerState(() {});
  }

  void _syncDanmakuMediaContext() {
    _activeDanmakuSourceKey = null;
    _danmakuController.updateMediaContext(
      title: _currentSeriesTitle.trim().isNotEmpty
          ? _currentSeriesTitle
          : _currentTitle,
      seasonGuid: _currentSeasonGuid,
      seasonNumber: _currentSeasonNumber,
      episodeNumber: _currentEpisodeNumber,
    );
    unawaited(_loadSavedLocalDanmakuSources(refreshUi: mounted));
  }

  String _currentDanmakuMediaKey() {
    if (_currentItemGuid.trim().isNotEmpty) {
      return 'item:${_currentItemGuid.trim()}';
    }
    final title =
        (_currentSeriesTitle.trim().isNotEmpty
                ? _currentSeriesTitle
                : _currentTitle)
            .trim();
    return 'fallback:$title:$_currentSeasonNumber:$_currentEpisodeNumber';
  }

  Future<void> _loadSavedLocalDanmakuSources({bool refreshUi = false}) async {
    final mediaKey = _currentDanmakuMediaKey();
    final sources = await _danmakuSavedSourceStore.loadForMedia(mediaKey);
    if (!mounted) return;
    _savedLocalDanmakuSources = sources;
    if (refreshUi) {
      _updatePlayerState(() {});
    }
  }

  Future<bool> _restoreSavedLocalDanmakuIfNeeded() async {
    final settings = _danmakuController.settings;
    if (!settings.enabled) return false;
    final mediaKey = _currentDanmakuMediaKey();
    final activeSourceKey = await _danmakuSavedSourceStore.loadActiveSourceKey(
      mediaKey,
    );
    if (activeSourceKey != null && activeSourceKey.trim().isNotEmpty) {
      final activeSource = _savedLocalDanmakuSources
          .where((item) => item.sourceKey == activeSourceKey)
          .cast<DanmakuSavedSource?>()
          .firstWhere((item) => item != null, orElse: () => null);
      if (activeSource != null) {
        final restored = await _restoreSavedDanmakuSource(activeSource);
        if (restored) return true;
        await _loadSavedLocalDanmakuSources();
      }
    }
    final preferredType = settings.preferLocalSource
        ? DanmakuSavedSourceType.localFile
        : DanmakuSavedSourceType.danDanPlay;
    final preferredSource = _pickNewestSavedDanmakuSourceOfType(preferredType);
    if (preferredSource == null) return false;
    return _restoreSavedDanmakuSource(preferredSource);
  }

  Future<bool> _restoreSavedDanmakuSource(DanmakuSavedSource source) async {
    final mediaKey = _currentDanmakuMediaKey();
    try {
      final result = await _loadDanmakuResultForSource(source);
      if (result == null) return false;
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
    } catch (_) {
      await _danmakuSavedSourceStore.removeSource(
        mediaKey: mediaKey,
        sourceKey: source.sourceKey,
      );
      await _loadSavedLocalDanmakuSources(refreshUi: mounted);
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

  Future<bool> _tryLoadPreferredDanmakuSource() async {
    final settings = _danmakuController.settings;
    if (!settings.enabled) return false;
    await _loadSavedLocalDanmakuSources();
    if (await _restoreSavedLocalDanmakuIfNeeded()) {
      return true;
    }
    if (settings.preferLocalSource) {
      final networkSaved = _pickNewestSavedDanmakuSourceOfType(
        DanmakuSavedSourceType.danDanPlay,
      );
      if (networkSaved != null &&
          await _restoreSavedDanmakuSource(networkSaved)) {
        return true;
      }
      return _tryLoadDanDanPlayComments();
    }
    if (await _tryLoadDanDanPlayComments()) {
      return true;
    }
    final localSaved = _pickNewestSavedDanmakuSourceOfType(
      DanmakuSavedSourceType.localFile,
    );
    if (localSaved != null) {
      return _restoreSavedDanmakuSource(localSaved);
    }
    return false;
  }

  Future<bool> _tryLoadDanDanPlayComments() async {
    final settings = _danmakuController.settings;
    if (!DanDanPlayConfig.configured) return false;
    if (!settings.enabled) return false;

    try {
      final result = await _danDanPlayResolver.resolveForPlayback(
        seriesTitle: _currentSeriesTitle.trim().isNotEmpty
            ? _currentSeriesTitle
            : _currentTitle,
        seasonNumber: _currentSeasonNumber,
        episodeNumber: _currentEpisodeNumber,
        tmdbId: _currentTmdbId,
      );
      if (!mounted || result == null) return false;
      _danmakuController.applyImportedComments(
        sourceLabel: result.sourceLabel,
        sourceType: DanmakuLoadedSourceType.network,
        comments: result.comments,
      );
      _activeDanmakuSourceKey = null;
      await _danmakuSavedSourceStore.setActiveSourceKey(
        mediaKey: _currentDanmakuMediaKey(),
        sourceKey: null,
      );
      _updatePlayerState(() {});
      return true;
    } catch (_) {
      return false;
    }
  }

  void _primeDanmakuSearch() {
    final keyword = DanDanPlayResolver.normalizeSeriesTitle(
      _currentSeriesTitle.trim().isNotEmpty
          ? _currentSeriesTitle
          : _currentTitle,
    );
    if (_danmakuSearchController.text.trim().isEmpty && keyword.isNotEmpty) {
      _danmakuSearchController.text = keyword;
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
