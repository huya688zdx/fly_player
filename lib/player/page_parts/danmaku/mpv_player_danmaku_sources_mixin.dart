part of mpv_player_page;

extension _MpvPlayerDanmakuSourcesMixin on _MpvPlayerPageState {
  Future<void> _searchDanmaku(PlayerNestedSheetController<void> drawer) async {
    if (!DanDanPlayConfig.configured) {
      _showTopTip('请先配置 DanDanPlay AppId / AppSecret', context.appColors.danger);
      return;
    }
    final keyword = _danmakuSearchController.text.trim();
    if (keyword.isEmpty) {
      _showTopTip('请先输入要搜索的番剧名称', context.appColors.danger);
      return;
    }
    _updatePlayerState(() {
      _danmakuSearchLoading = true;
      _danmakuSearchResults = const <DanDanPlayEpisodeSearchItem>[];
    });
    try {
      final results = await _danDanPlayResolver.searchEpisodeCandidates(
        keyword: keyword,
        episodeNumber: _currentEpisodeNumber,
        tmdbId: _currentTmdbId,
      );
      if (!mounted) return;
      _updatePlayerState(() {
        _danmakuSearchLoading = false;
        _danmakuSearchResults = results;
      });
      drawer.refresh();
      if (results.isEmpty) {
        _showTopTip('没有找到可用弹幕结果', context.appColors.danger);
      }
    } catch (error) {
      if (!mounted) return;
      _updatePlayerState(() {
        _danmakuSearchLoading = false;
      });
      drawer.refresh();
      _showTopTip('搜索弹幕失败: $error', context.appColors.danger);
    }
  }

  Future<void> _importDanmakuSearchResult(
    PlayerNestedSheetController<void> drawer,
    DanDanPlayEpisodeSearchItem item,
  ) async {
    if (!DanDanPlayConfig.configured) {
      _showTopTip('请先配置 DanDanPlay AppId / AppSecret', context.appColors.danger);
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
        seasonNumber: _currentSeasonNumber,
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
      _showTopTip('导入弹幕失败: $error', context.appColors.danger);
    }
  }

  Future<void> _importLocalDanmakuFile(
    PlayerNestedSheetController<void> drawer,
    String path,
  ) async {
    _updatePlayerState(() {
      _danmakuImportingLocalPath = path;
    });
    drawer.refresh();
    try {
      final result = await DanmakuImportParser.parseFile(path);
      _danmakuController.applyImportedComments(
        sourceLabel: result.sourceLabel,
        sourceType: DanmakuLoadedSourceType.local,
        comments: result.comments,
      );
      _activeDanmakuSourceKey = path;
      await _danmakuSavedSourceStore.saveSource(
        DanmakuSavedSource(
          type: DanmakuSavedSourceType.localFile,
          mediaKey: _currentDanmakuMediaKey(),
          sourceKey: path,
          label: result.sourceLabel,
          detail: path.split(Platform.pathSeparator).last,
          ancestorName: _currentAncestorName.trim(),
          seriesTitle: _currentSeriesTitle.trim(),
          itemTitle: _currentTitle.trim(),
          seasonNumber: _currentSeasonNumber,
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
      _showTopTip('导入弹幕失败: $error', context.appColors.danger);
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
          seasonNumber: source.seasonNumber,
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
