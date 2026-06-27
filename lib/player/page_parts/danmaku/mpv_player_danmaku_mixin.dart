part of '../../mpv_player_page.dart';

const String _playerSettingsDanmakuPageId = 'player_settings_danmaku';
const String _playerSettingsDanmakuSavedPageId =
    'player_settings_danmaku_saved';
const String _playerSettingsDanmakuImportPageId =
    'player_settings_danmaku_import';
const String _playerSettingsDanmakuSearchPageId =
    'player_settings_danmaku_search';
const List<double> _danmakuAreaPresets = <double>[0.25, 0.50, 0.75, 1.0];
const List<double> _danmakuThicknessPresets = <double>[0.8, 1.0, 1.2, 1.4];
const List<double> _danmakuFrameRatePresets = <double>[
  24,
  30,
  45,
  60,
  72,
  90,
  120,
];
const List<double> _danmakuAiSampleIntervalPresets = <double>[
  200,
  250,
  300,
  400,
  500,
];
const List<double> _danmakuAiInputWidthPresets = <double>[
  160,
  192,
  224,
  256,
  288,
  320,
];

extension _MpvPlayerDanmakuMixin on _MpvPlayerPageState {
  static const String _danmakuAutoBlockNoResult = 'no_result';
  static const String _danmakuAutoBlockFailed = 'failed';

  bool get _danmakuEnabled => _danmakuController.settings.enabled;
  bool get _useNativeDanmakuRenderer => Platform.isAndroid;

  DanDanPlayResolver get _danDanPlayResolver => DanDanPlayResolver(
    DanDanPlayApi(
      appId: DanDanPlayConfig.appId,
      appSecrets: DanDanPlayConfig.appSecrets,
    ),
  );

  String get _danmakuToggleAsset => _danmakuEnabled
      ? 'assets/icons/player_danmaku_on.svg'
      : 'assets/icons/player_danmaku_off.svg';

  void _markInitialDanmakuPreferencesLoaded() {
    if (_initialDanmakuPreferencesLoaded) {
      return;
    }
    if (!mounted) {
      _initialDanmakuPreferencesLoaded = true;
      return;
    }
    _updatePlayerState(() {
      _initialDanmakuPreferencesLoaded = true;
    });
    _tryStartInitialSourceLoad();
  }

  void _handleDanmakuControllerChanged() {
    if (!_useNativeDanmakuRenderer) {
      return;
    }
    _queueNativeDanmakuRendererSync();
  }

  Future<void> _loadDanmakuPreferences() async {
    try {
      await DanDanPlayConfig.ensureLoaded();
      await _danmakuController.initialize();
      _syncDanmakuMediaContext();
      _markInitialDanmakuPreferencesLoaded();
      await _loadSavedLocalDanmakuSources();
      await _tryLoadPreferredDanmakuSource();
      await _syncDanmakuDynamicOcclusionConfig();
      await _controller.clearDanmaku();
      await _flushNativeDanmakuRendererSync();
      await _syncNativeDanmakuOcclusionState();
      if (!mounted) return;
      _updatePlayerState(() {});
    } catch (error, stackTrace) {
      debugPrint('[DANMAKU] Failed to load preferences: $error\n$stackTrace');
      _markInitialDanmakuPreferencesLoaded();
    }
  }

  void _queueNativeDanmakuRendererSync({bool immediate = false}) {
    if (!_useNativeDanmakuRenderer) {
      return;
    }
    final shouldLogQueue =
        !_nativeDanmakuSyncDirty &&
        !_nativeDanmakuSyncInFlight &&
        _nativeDanmakuSyncTimer == null;
    _nativeDanmakuSyncDirty = true;
    if (shouldLogQueue) {
      debugPrint(
        '[DANMAKU][NATIVE] queue_sync '
        'ready=${_danmakuController.ready} '
        'enabled=${_danmakuController.settings.enabled} '
        'comments=${_danmakuController.comments.length} '
        'platformAttached=$_platformViewAttached '
        'immediate=$immediate',
      );
    }
    _nativeDanmakuSyncTimer?.cancel();
    _nativeDanmakuSyncTimer = null;
    if (immediate) {
      unawaited(_flushNativeDanmakuRendererSync());
      return;
    }
    _nativeDanmakuSyncTimer = Timer(const Duration(milliseconds: 48), () {
      _nativeDanmakuSyncTimer = null;
      unawaited(_flushNativeDanmakuRendererSync());
    });
  }

  Future<void> _flushNativeDanmakuRendererSync() async {
    if (!_useNativeDanmakuRenderer) {
      return;
    }
    _nativeDanmakuSyncTimer?.cancel();
    _nativeDanmakuSyncTimer = null;
    if (_nativeDanmakuSyncInFlight) {
      return;
    }
    _nativeDanmakuSyncInFlight = true;
    try {
      while (_nativeDanmakuSyncDirty) {
        _nativeDanmakuSyncDirty = false;
        await _syncNativeDanmakuRenderer();
      }
    } finally {
      _nativeDanmakuSyncInFlight = false;
    }
  }

  Future<void> _syncNativeDanmakuRenderer() async {
    if (!_useNativeDanmakuRenderer) {
      return;
    }
    if (!_platformViewAttached) {
      return;
    }
    if (!_danmakuController.ready) {
      _lastNativeDanmakuCommentsSignature = '';
      _lastNativeDanmakuSettingsSignature = '';
      debugPrint('[DANMAKU][NATIVE] clear reason=controller_not_ready');
      await _controller.clearDanmaku();
      return;
    }
    final settings = _danmakuController.settings;
    final comments = _danmakuController.comments;
    if (!settings.enabled || comments.isEmpty) {
      _lastNativeDanmakuCommentsSignature = '';
      _lastNativeDanmakuSettingsSignature = '';
      debugPrint(
        '[DANMAKU][NATIVE] clear reason=empty '
        'enabled=${settings.enabled} comments=${comments.length}',
      );
      await _controller.clearDanmaku();
      return;
    }
    final commentsSignature = _buildNativeDanmakuCommentsSignature(
      comments: comments,
    );
    final settingsSignature = _buildNativeDanmakuSettingsSignature(
      settings: settings,
    );
    final commentsChanged =
        commentsSignature != _lastNativeDanmakuCommentsSignature;
    final settingsChanged =
        settingsSignature != _lastNativeDanmakuSettingsSignature;
    if (!commentsChanged && !settingsChanged) {
      debugPrint(
        '[DANMAKU][NATIVE] skip_sync '
        'source=${_currentDanmakuMediaKey()} '
        'comments=${comments.length}',
      );
      return;
    }
    final payload = <String, Object?>{
      'enabled': settings.enabled,
      'opacity': settings.opacity,
      'density': settings.density,
      'fontScale': settings.fontScale,
      'fontThickness': settings.fontThickness,
      'speed': settings.speed,
      'displayAreaRatio': settings.displayAreaRatio,
      'targetFrameRateHz': settings.targetFrameRateHz,
      'scrollEnabled': settings.scrollEnabled,
      'topEnabled': settings.topEnabled,
      'bottomEnabled': settings.bottomEnabled,
      'colorEnabled': settings.colorEnabled,
      'hideDuplicate': settings.hideDuplicate,
      'avoidSubtitleArea': settings.avoidSubtitleArea,
      'playbackSpeed': _speedBoostActive ? 2.0 : _playbackSpeed,
      'initialPositionMs': _controller.value.value.position.inMilliseconds,
      'sourceKey': _currentDanmakuMediaKey(),
      if (commentsChanged)
        'comments': comments
            .map(
              (comment) => <String, Object?>{
                'id': comment.id,
                'timeMs': comment.timeMs,
                'text': comment.text,
                'type': comment.type.name,
                'color': comment.color.toARGB32(),
              },
            )
            .toList(growable: false),
    };
    _lastNativeDanmakuCommentsSignature = commentsSignature;
    _lastNativeDanmakuSettingsSignature = settingsSignature;
    debugPrint(
      '[DANMAKU][NATIVE] sync '
      'source=${_currentDanmakuMediaKey()} '
      'comments=${comments.length} '
      'settingsOnly=${!commentsChanged} '
      'initialPositionMs=${payload['initialPositionMs']} '
      'speed=${payload['playbackSpeed']}',
    );
    await _controller.setDanmakuPayload(payload);
  }

  String _buildNativeDanmakuCommentsSignature({
    required List<DanmakuComment> comments,
  }) {
    final head = comments.isEmpty ? null : comments.first;
    final tail = comments.isEmpty ? null : comments.last;
    return <Object?>[
      _currentDanmakuMediaKey(),
      identityHashCode(comments),
      comments.length,
      head?.id ?? '',
      head?.timeMs ?? 0,
      tail?.id ?? '',
      tail?.timeMs ?? 0,
    ].join('|');
  }

  String _buildNativeDanmakuSettingsSignature({
    required DanmakuSettings settings,
  }) {
    return <Object?>[
      settings.enabled,
      settings.opacity.toStringAsFixed(3),
      settings.density.toStringAsFixed(3),
      settings.fontScale.toStringAsFixed(3),
      settings.fontThickness.toStringAsFixed(3),
      settings.speed.toStringAsFixed(3),
      settings.displayAreaRatio.toStringAsFixed(3),
      settings.targetFrameRateHz,
      settings.scrollEnabled,
      settings.topEnabled,
      settings.bottomEnabled,
      settings.colorEnabled,
      settings.hideDuplicate,
      settings.avoidSubtitleArea,
      (_speedBoostActive ? 2.0 : _playbackSpeed).toStringAsFixed(3),
    ].join('|');
  }

  void _handleDanmakuOcclusionStateChanged() {
    if (_useNativeDanmakuRenderer) {
      unawaited(_syncNativeDanmakuOcclusionState());
      final settingsDrawer = _activePlaybackSettingsDrawerController;
      if (settingsDrawer?.currentPageId == _playerSettingsDanmakuPageId) {
        settingsDrawer?.refresh();
      }
      return;
    }
    if (!mounted) return;
    _updatePlayerState(() {});
  }

  Future<void> _syncNativeDanmakuOcclusionState() async {
    if (!_useNativeDanmakuRenderer || !_platformViewAttached) {
      return;
    }
    final state = _controller.danmakuOcclusionState.value;
    await _controller.setNativeDanmakuOcclusion(<String, Object?>{
      'enabled': state.enabled,
      'available': state.available,
      'backend': state.backend,
      'occlusionMode': state.occlusionMode,
      'updatedAtMs': state.updatedAtMs,
      'maskPath': state.maskPath,
      'maskSignature': state.maskSignature,
      'maskWidth': state.maskWidth,
      'maskHeight': state.maskHeight,
      'captureAreaRatio': state.captureAreaRatio,
      'captureBackend': state.captureBackend,
      'degradationLevel': state.degradationLevel,
      'effectiveSampleIntervalMs': state.effectiveSampleIntervalMs,
      'effectiveInputWidth': state.effectiveInputWidth,
      'normalizedRect': state.normalizedRect == null
          ? null
          : <String, Object?>{
              'x': state.normalizedRect!.x,
              'y': state.normalizedRect!.y,
              'width': state.normalizedRect!.width,
              'height': state.normalizedRect!.height,
            },
      'unavailableReason': state.unavailableReason,
    });
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
    if (requestToken != null &&
        !_isActiveDanmakuContext(requestToken, mediaKey)) {
      return;
    }
    if (!mounted) return;
    _savedLocalDanmakuSources = sources;
    if (refreshUi) {
      if (!mounted) return;
      _updatePlayerState(() {});
    }
  }

  /// 最高优先级层：用户**手动选择过**的源（持久化的 activeSourceKey）。其次在离线播放下载
  /// 文件、且没有手动源时，优先本地导入源（在线源此时拉不到）。其余优先级在
  /// [_tryLoadPreferredDanmakuSource] 中按 本地导入 > 网络 > 本地下载 处理。
  Future<bool> _restoreSavedLocalDanmakuIfNeeded({int? requestToken}) async {
    final settings = _danmakuController.settings;
    if (!settings.enabled) return false;
    final mediaKey = _currentDanmakuMediaKey();
    final activeSourceKey = await _danmakuSavedSourceStore.loadActiveSourceKey(
      mediaKey,
    );
    if (requestToken != null &&
        !_isActiveDanmakuContext(requestToken, mediaKey)) {
      return false;
    }
    DanmakuSavedSource? activeSource;
    if (activeSourceKey != null && activeSourceKey.trim().isNotEmpty) {
      activeSource = _savedLocalDanmakuSources
          .where((item) => item.sourceKey == activeSourceKey)
          .cast<DanmakuSavedSource?>()
          .firstWhere((item) => item != null, orElse: () => null);
    }
    // 手动选择过的源最高优先（重新确认其激活态）。随片下载缓存不算手动选择，即便历史数据
    // 把它误设成 active 也跳过，让它落到网络之后的兜底（修复旧版强制激活下载源的遗留数据）。
    if (activeSource != null && !activeSource.isDownloadedFile) {
      final restored = await _restoreSavedDanmakuSource(
        activeSource,
        requestToken: requestToken,
        markActive: true,
      );
      if (restored) return true;
      await _loadSavedLocalDanmakuSources(requestToken: requestToken);
    }
    // 离线播放下载文件、无手动源：先本地导入（手动），再随片下载缓存兜底（在线源拉不到）。
    if (_currentSourceIsDownloadedFile) {
      final localSource =
          _pickNewestReadableSavedLocalDanmakuSource() ??
          _pickReadableDownloadedDanmakuSource();
      if (localSource != null) {
        final restored = await _restoreSavedDanmakuSource(
          localSource,
          requestToken: requestToken,
        );
        if (restored) return true;
        await _loadSavedLocalDanmakuSources(requestToken: requestToken);
      }
    }
    return false;
  }

  /// 恢复一个已保存的弹幕源。[markActive]=true 才把它持久化为"手动选择的激活源"
  /// （loadActiveSourceKey 的最高优先来源）；自动加载链一律 false，仅更新内存态用于 UI
  /// 高亮，避免自动命中的网络源把用户手动选择/本地导入源挤掉。
  Future<bool> _restoreSavedDanmakuSource(
    DanmakuSavedSource source, {
    int? requestToken,
    bool markActive = false,
  }) async {
    final mediaKey = _currentDanmakuMediaKey();
    try {
      final result = await _loadDanmakuResultForSource(source);
      if (result == null) return false;
      if (requestToken != null &&
          !_isActiveDanmakuContext(requestToken, mediaKey)) {
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
      if (_useNativeDanmakuRenderer) {
        await _flushNativeDanmakuRendererSync();
      }
      _activeDanmakuSourceKey = source.sourceKey;
      if (markActive) {
        await _danmakuSavedSourceStore.setActiveSourceKey(
          mediaKey: mediaKey,
          sourceKey: source.sourceKey,
        );
      }
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

  DanmakuSavedSource? _pickNewestReadableSavedLocalDanmakuSource() {
    return _savedLocalDanmakuSources
        .where(
          (item) =>
              item.isLocalFile && _savedLocalDanmakuSourceLooksReadable(item),
        )
        .cast<DanmakuSavedSource?>()
        .firstWhere((item) => item != null, orElse: () => null);
  }

  /// 随片下载缓存（一键下载，非手动导入）：优先级最低，仅离线兜底。
  DanmakuSavedSource? _pickReadableDownloadedDanmakuSource() {
    return _savedLocalDanmakuSources
        .where(
          (item) =>
              item.isDownloadedFile &&
              _savedLocalDanmakuSourceLooksReadable(item),
        )
        .cast<DanmakuSavedSource?>()
        .firstWhere((item) => item != null, orElse: () => null);
  }

  bool _savedLocalDanmakuSourceLooksReadable(DanmakuSavedSource source) {
    final sourceKey = source.sourceKey.trim();
    if (sourceKey.isEmpty) return false;
    if (StorageAccessService.isScopedIdentifier(sourceKey)) return true;
    try {
      return File(sourceKey).existsSync();
    } catch (_) {
      return false;
    }
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
    if (requestToken != null &&
        !_isActiveDanmakuContext(requestToken, mediaKey)) {
      return false;
    }
    // 手动选择过的源最高优先（含离线下载文件的本地兜底）。
    if (await _restoreSavedLocalDanmakuIfNeeded(requestToken: requestToken)) {
      return true;
    }

    // 本地导入源（用户主动导入/随片下载的本地弹幕文件）。
    Future<bool> tryLocalImport() async {
      final localImport =
          _pickNewestReadableSavedLocalDanmakuSource() ??
          _pickNewestSavedDanmakuSourceOfType(DanmakuSavedSourceType.localFile);
      if (localImport == null) return false;
      return _restoreSavedDanmakuSource(
        localImport,
        requestToken: requestToken,
      );
    }

    // 网络源：在线自动匹配，拉到最新并覆盖旧的已保存（下载）缓存。
    Future<bool> tryNetwork() async {
      if (!_danmakuAutoSearchAllowed) return false;
      return _tryLoadDanDanPlayComments(requestToken: requestToken);
    }

    // 用户期望顺序：本地导入 > 网络 > 本地下载。preferLocalSource=false 时把网络提到本地导入前。
    if (settings.preferLocalSource) {
      if (await tryLocalImport()) return true;
      if (await tryNetwork()) return true;
    } else {
      if (await tryNetwork()) return true;
      if (await tryLocalImport()) return true;
    }

    // 网络源兜底：之前保存的网络源（在线实时匹配失败/受限时回退到已保存条目）。
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

    // 最低优先：随片下载缓存（一键下载）。网络全拿不到时离线兜底。
    final downloadedBundle = _pickReadableDownloadedDanmakuSource();
    if (downloadedBundle != null &&
        await _restoreSavedDanmakuSource(
          downloadedBundle,
          requestToken: requestToken,
        )) {
      return true;
    }
    return false;
  }

  Future<bool> _tryLoadDanDanPlayComments({int? requestToken}) async {
    final settings = _danmakuController.settings;
    if (!settings.enabled) return false;
    if (!_danmakuAutoSearchAllowed) return false;
    if (!await DanDanPlayConfig.ensureConfigured()) return false;
    final mediaKey = _currentDanmakuMediaKey();
    final blockedReason = await _danmakuSavedSourceStore
        .loadAutoMatchBlockedReason(mediaKey);
    if (blockedReason != null &&
        blockedReason.isNotEmpty &&
        blockedReason != _danmakuAutoBlockNoResult) {
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
        itemTitle: _currentTitle,
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
            AppLocalizations.of(context).danmakuAutoMatchNoResultBlocked,
            context.appColors.warning,
          );
        }
        return false;
      }
      if (requestToken != null &&
          !_isActiveDanmakuContext(requestToken, mediaKey)) {
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
      // 自动匹配命中：覆盖旧的已保存（下载）缓存即"网络拉到最新覆盖旧下载"，但**不**持久化
      // 为激活源——自动命中不是手动选择，不应挤掉用户手动选择/本地导入源的最高优先。仅更新
      // 内存态供 UI 高亮。
      await _danmakuSavedSourceStore.saveSource(savedSource);
      await _loadSavedLocalDanmakuSources(requestToken: requestToken);
      _activeDanmakuSourceKey = savedSource.sourceKey;
      if (!mounted) return true;
      final successColor = context.appColors.success;
      _updatePlayerState(() {});
      _showTopTip(
        AppLocalizations.of(context).danmakuLoadedCount(result.comments.length),
        successColor,
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
        final l10n = AppLocalizations.of(context);
        final reason = error is DanDanPlayApiException
            ? error.message
            : l10n.danmakuAutoMatchFailed;
        _showTopTip(
          l10n.danmakuAutoMatchBlockedWithReason(reason),
          context.appColors.warning,
        );
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
