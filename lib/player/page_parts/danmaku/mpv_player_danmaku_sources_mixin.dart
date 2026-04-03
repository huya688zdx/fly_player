part of mpv_player_page;

extension _MpvPlayerDanmakuSourcesMixin on _MpvPlayerPageState {
  Future<bool> _ensureDanDanPlayConfigured() async {
    final configured = await DanDanPlayConfig.ensureConfigured();
    if (configured) {
      return true;
    }
    if (!mounted) {
      return false;
    }
    _showTopTip(DanDanPlayConfig.unavailableMessage, context.appColors.danger);
    return false;
  }

  String _describeDanDanPlayError(Object error, {required String fallback}) {
    if (error is DanDanPlayApiException) {
      return error.message;
    }
    final raw = error.toString().trim();
    return raw.isEmpty ? fallback : '$fallback: $raw';
  }

  Future<bool> _ensureStorageAccessForDanmakuImport() async {
    var hasAccess = await StorageAccessService.hasFileAccess();
    if (hasAccess) {
      return true;
    }
    final granted = await StorageAccessService.requestFileAccess();
    if (granted) {
      return true;
    }
    hasAccess = await StorageAccessService.hasFileAccess();
    if (hasAccess) {
      return true;
    }
    final openedSettings = await StorageAccessService.openFileAccessSettings();
    if (!mounted) {
      return false;
    }
    _showTopTip(
      openedSettings ? '已跳转系统设置，请开启文件访问权限后返回重试' : '请先授予文件访问权限',
      context.appColors.danger,
    );
    return false;
  }

  Future<void> _openDanmakuImportPage(
    PlayerNestedSheetController<void> drawer,
  ) async {
    drawer.push(_playerSettingsDanmakuImportPageId);
  }

  Future<void> _searchDanmaku(
    PlayerNestedSheetController<void> drawer, {
    bool userInitiated = true,
  }) async {
    if (!await _ensureDanDanPlayConfigured()) {
      return;
    }
    final keyword = _danmakuSearchController.text.trim();
    final hasTmdbSearchContext =
        DanDanPlayResolver.normalizeTmdbId(_currentTmdbId) != null;
    if (keyword.isEmpty && !hasTmdbSearchContext) {
      _showTopTip('请先输入要搜索的番剧名称', context.appColors.danger);
      return;
    }
    final remaining = _danmakuSearchRateLimiter.remaining();
    if (remaining > Duration.zero) {
      if (userInitiated) {
        final seconds =
            remaining.inSeconds +
            (remaining.inMilliseconds % 1000 == 0 ? 0 : 1);
        _showTopTip('搜索过于频繁，请 $seconds 秒后再试。', context.appColors.warning);
      }
      return;
    }
    _danmakuSearchRateLimiter.shouldBlock();
    _updatePlayerState(() {
      _danmakuSearchLoading = true;
      _danmakuSearchResults = const <DanDanPlayEpisodeSearchItem>[];
    });
    final requestContextKey = _danmakuSearchContextKey(keyword);
    try {
      final results = await _danDanPlayResolver.searchEpisodeCandidates(
        keyword: keyword,
        episodeNumber: _currentEpisodeNumber,
        tmdbId: _currentTmdbId,
        allowLooseTitleFallback: true,
      );
      if (!mounted) return;
      _updatePlayerState(() {
        _danmakuSearchLoading = false;
        _danmakuSearchResults = results;
        _danmakuSearchLastCompletedContextKey = requestContextKey;
      });
      drawer.refresh();
      if (results.isEmpty) {
        _showTopTip('没有搜索到可用弹幕结果', context.appColors.danger);
      }
    } catch (error) {
      if (!mounted) return;
      _updatePlayerState(() {
        _danmakuSearchLoading = false;
      });
      drawer.refresh();
      _showTopTip(
        _describeDanDanPlayError(error, fallback: '搜索弹幕失败'),
        context.appColors.danger,
      );
    }
  }

  Future<void> _importDanmakuSearchResult(
    PlayerNestedSheetController<void> drawer,
    DanDanPlayEpisodeSearchItem item,
  ) async {
    if (!await _ensureDanDanPlayConfigured()) {
      return;
    }
    _updatePlayerState(() {
      _danmakuImportingEpisodeId = item.episodeId;
    });
    drawer.refresh();
    try {
      final result = await _danDanPlayResolver.importEpisodeById(item);
      if (!mounted) return;
      if (result == null) {
        _updatePlayerState(() {
          _danmakuImportingEpisodeId = null;
        });
        drawer.refresh();
        _showTopTip('没有获取到可用弹幕数据', context.appColors.danger);
        return;
      }
      _danmakuController.applyImportedComments(
        sourceLabel: result.sourceLabel,
        sourceType: DanmakuLoadedSourceType.network,
        comments: result.comments,
      );
      final savedSource = DanmakuSavedSource(
        type: DanmakuSavedSourceType.danDanPlay,
        mediaKey: _currentDanmakuMediaKey(),
        sourceKey: item.episodeId.toString(),
        label: item.displayTitle,
        detail: item.displaySubtitle,
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
      await _loadSavedLocalDanmakuSources();
      _activeDanmakuSourceKey = savedSource.sourceKey;
      await _danmakuSavedSourceStore.setActiveSourceKey(
        mediaKey: _currentDanmakuMediaKey(),
        sourceKey: savedSource.sourceKey,
      );
      await _updateDanmakuSettings(
        (current) => current.copyWith(enabled: true),
      );
      if (!mounted) return;
      _updatePlayerState(() {
        _danmakuImportingEpisodeId = null;
      });
      drawer.popPage();
      drawer.refresh();
      _showTopTip(
        '已导入 ${result.comments.length} 条弹幕',
        context.appColors.success,
      );
    } catch (error) {
      if (!mounted) return;
      _updatePlayerState(() {
        _danmakuImportingEpisodeId = null;
      });
      drawer.refresh();
      _showTopTip(
        _describeDanDanPlayError(error, fallback: '导入弹幕失败'),
        context.appColors.danger,
      );
    }
  }

  Future<void> _importLocalDanmakuFile(
    PlayerNestedSheetController<void> drawer,
    LocalBrowserFileSelection selection,
  ) async {
    final sourceKey = selection.identifier.trim();
    if (sourceKey.isEmpty) {
      return;
    }
    _updatePlayerState(() {
      _danmakuImportingLocalPath = sourceKey;
    });
    drawer.refresh();
    try {
      final result = StorageAccessService.isScopedIdentifier(sourceKey)
          ? await (() async {
              final bytes = await StorageAccessService.readScopedFileBytes(
                sourceKey,
              );
              if (bytes == null || bytes.isEmpty) {
                throw const FileSystemException('无法读取已选择的弹幕文件');
              }
              return DanmakuImportParser.parseBytes(
                bytes,
                fileName: selection.displayName,
              );
            })()
          : await DanmakuImportParser.parseFile(sourceKey);
      _danmakuController.applyImportedComments(
        sourceLabel: result.sourceLabel,
        sourceType: DanmakuLoadedSourceType.local,
        comments: result.comments,
      );
      _activeDanmakuSourceKey = sourceKey;
      await _danmakuSavedSourceStore.saveSource(
        DanmakuSavedSource(
          type: DanmakuSavedSourceType.localFile,
          mediaKey: _currentDanmakuMediaKey(),
          sourceKey: sourceKey,
          label: result.sourceLabel,
          detail: selection.displayName.trim().isNotEmpty
              ? selection.displayName.trim()
              : result.sourceLabel,
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
        ),
      );
      await _loadSavedLocalDanmakuSources();
      await _updateDanmakuSettings(
        (current) => current.copyWith(enabled: true),
      );
      if (!mounted) return;
      drawer.popPage();
      _updatePlayerState(() {
        _danmakuImportingLocalPath = null;
      });
      drawer.refresh();
      _showTopTip(
        '已导入 ${result.comments.length} 条弹幕',
        context.appColors.success,
      );
    } catch (error) {
      if (!mounted) return;
      _updatePlayerState(() {
        _danmakuImportingLocalPath = null;
      });
      drawer.refresh();
      _showTopTip('导入弹幕失败: ', context.appColors.danger);
    }
  }

  Future<void> _activateSavedLocalDanmaku(
    PlayerNestedSheetController<void> drawer,
    DanmakuSavedSource source,
  ) async {
    _updatePlayerState(() {
      _danmakuImportingLocalPath = source.sourceKey;
    });
    drawer.refresh();
    try {
      final result = await _loadDanmakuResultForSource(source);
      if (result == null) {
        throw StateError('没有获取到可用弹幕数据');
      }
      await _danmakuSavedSourceStore.saveSource(
        DanmakuSavedSource(
          type: source.type,
          mediaKey: source.mediaKey,
          sourceKey: source.sourceKey,
          label: result.sourceLabel,
          detail: source.detail,
          ancestorName: source.ancestorName,
          seriesTitle: source.seriesTitle,
          itemTitle: source.itemTitle,
          itemGuid: source.itemGuid,
          seasonGuid: source.seasonGuid,
          mediaGuid: source.mediaGuid,
          seasonNumber: source.seasonNumber,
          episodeNumber: source.episodeNumber,
          mediaType: source.mediaType,
          commentCount: result.comments.length,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await _loadSavedLocalDanmakuSources();
      _danmakuController.applyImportedComments(
        sourceLabel: result.sourceLabel,
        sourceType: source.isDanDanPlay
            ? DanmakuLoadedSourceType.network
            : DanmakuLoadedSourceType.local,
        comments: result.comments,
      );
      _activeDanmakuSourceKey = source.sourceKey;
      await _updateDanmakuSettings(
        (current) => current.copyWith(enabled: true),
      );
      if (!mounted) return;
      _updatePlayerState(() {
        _danmakuImportingLocalPath = null;
      });
      drawer.refresh();
      _showTopTip(
        '已载入 ${result.comments.length} 条弹幕',
        context.appColors.success,
      );
    } catch (error) {
      await _danmakuSavedSourceStore.removeSource(
        mediaKey: source.mediaKey,
        sourceKey: source.sourceKey,
      );
      await _loadSavedLocalDanmakuSources();
      if (!mounted) return;
      _updatePlayerState(() {
        _danmakuImportingLocalPath = null;
      });
      drawer.refresh();
      _showTopTip('弹幕文件已失效，已从列表移除', context.appColors.danger);
    }
  }

  Future<void> _deleteSavedLocalDanmaku(
    PlayerNestedSheetController<void> drawer,
    DanmakuSavedSource source,
  ) async {
    _updatePlayerState(() {
      _danmakuDeletingLocalPath = source.sourceKey;
    });
    drawer.refresh();
    await _danmakuSavedSourceStore.removeSource(
      mediaKey: source.mediaKey,
      sourceKey: source.sourceKey,
    );
    await _loadSavedLocalDanmakuSources();
    if (!mounted) return;
    if (_activeDanmakuSourceKey == source.sourceKey) {
      _activeDanmakuSourceKey = null;
      _syncDanmakuMediaContext();
      unawaited(_tryLoadPreferredDanmakuSource());
    }
    _updatePlayerState(() {
      _danmakuDeletingLocalPath = null;
    });
    drawer.refresh();
    _showTopTip('已删除保存的弹幕来源', context.appColors.success);
  }
}
