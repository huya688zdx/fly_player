part of '../../mpv_player_page.dart';

const String _subtitleMainPageId = 'subtitle_main';
const String _subtitleAdjustPageId = 'subtitle_adjust';
const String _subtitleAddPageId = 'subtitle_add';
const String _subtitleSearchPageId = 'subtitle_search';
const String _subtitleLanguagePageId = 'subtitle_language';

const double _subtitleScaleMin = 0.8;
const double _subtitleScaleMax = 2.0;

extension _MpvPlayerSubtitleDrawerMixin on _MpvPlayerPageState {
  Future<void> _showSubtitleDrawer() async {
    if (_playerUiLocked) return;
    _hideSpeedDialOverlay(restoreAutoHide: false);
    _deferredSubtitleSelectionTimer?.cancel();
    _overlayState.cancelAutoHide();
    final restoreControls = _controlsVisible;
    if (restoreControls) {
      _hideControlsImmediately();
    }
    final shouldWarmupLocalTracks = _isLocalRuntimeTrackSource();

    try {
      if (mounted && !_subtitleDrawerVisible) {
        _subtitleDrawerVisible = true;
        unawaited(_syncDanmakuDynamicOcclusionConfig());
      }
      unawaited(
        _warmupSubtitleDrawerData(
          refreshRuntimeTracks: shouldWarmupLocalTracks,
        ),
      );
      await PlayerNestedSheet.show<void>(
        context,
        initialPageId: _subtitleMainPageId,
        barrierLabel: 'subtitle drawer',
        pages: <PlayerNestedSheetPage<void>>[
          PlayerNestedSheetPage<void>(
            id: _subtitleMainPageId,
            builder: _buildSubtitleMainPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _subtitleAdjustPageId,
            builder: _buildSubtitleAdjustPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _subtitleAddPageId,
            builder: _buildSubtitleAddPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _subtitleSearchPageId,
            builder: _buildSubtitleSearchPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _subtitleLanguagePageId,
            builder: _buildSubtitleLanguagePage,
          ),
        ],
      );
    } finally {
      _activeSubtitleDrawerController = null;
      if (mounted && _subtitleDrawerVisible) {
        _subtitleDrawerVisible = false;
        unawaited(_syncDanmakuDynamicOcclusionConfig());
        unawaited(_startOrUpdateSystemPlaybackSession(force: true));
      }
      if (mounted && !restoreControls) {
        _scheduleControlsAutoHide();
      }
    }
  }

  Future<void> _warmupSubtitleDrawerData({
    required bool refreshRuntimeTracks,
  }) async {
    try {
      final nasProvider = context.read<NasProvider>();
      try {
        final languageMap = await FeiniuApi(
          nasProvider,
        ).getTagIso6392Map(lan: 'zh-CN');
        if (languageMap.isNotEmpty) {
          MediaLanguageMapper.mergeLanguageMap(languageMap);
        }
      } catch (error, trace) {
        unawaited(
          AppErrorReporter.report(
            error,
            action: 'load subtitle language map',
            source: 'mpv_player_subtitle',
            stackTrace: trace,
            fallbackKind: AppExceptionKind.noData,
            level: AppLogLevel.warning,
          ),
        );
      }
      if (refreshRuntimeTracks) {
        await _refreshRuntimeTracks(force: true);
      }
    } finally {
      _activeSubtitleDrawerController?.refresh();
    }
  }

  Widget _buildSubtitleMainPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    _activeSubtitleDrawerController = drawer;
    final selectedSubtitleGuid = _normalizedSubtitleGuid() ?? '';
    final items = <_SubtitleDrawerTileData>[
      _SubtitleDrawerTileData(
        title: '\u5173\u95ed',
        selected: selectedSubtitleGuid.isEmpty,
        onTap: () => unawaited(_selectSubtitleFromDrawer('', drawer)),
      ),
      ..._subtitleTracks.map(
        (track) => _SubtitleDrawerTileData(
          title: _subtitleTitle(track),
          subtitle: _subtitleSubtitle(track),
          trailingDetail: _subtitleStreamTitle(track),
          deleting: track.guid == _subtitleDeletingGuid,
          onDelete: _subtitleCanDelete(track)
              ? () => unawaited(_deleteSubtitleFromDrawer(track, drawer))
              : null,
          selected: track.guid == selectedSubtitleGuid,
          onTap: () => unawaited(_selectSubtitleFromDrawer(track.guid, drawer)),
        ),
      ),
    ];

    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: '\u5b57\u5e55',
        actions: <Widget>[
          _SubtitleHeaderActionButton(
            icon: Icons.settings_rounded,
            label: '\u8c03\u6574',
            onTap: () => drawer.push(_subtitleAdjustPageId),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '\u5b57\u5e55\u5217\u8868',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              _SubtitlePrimaryButton(
                icon: Icons.add_rounded,
                label: '\u6dfb\u52a0',
                onTap: () => drawer.push(_subtitleAddPageId),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 2),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                return _SubtitleOptionTile(
                  title: item.title,
                  subtitle: item.subtitle,
                  trailingDetail: item.trailingDetail,
                  deleting: item.deleting,
                  onDelete: item.onDelete,
                  selected: item.selected,
                  onTap: item.onTap,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubtitleAddPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    final canSearchRemoteSubtitle = _canSearchRemoteSubtitlesForCurrentSource();
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: '\u9009\u62e9\u5b57\u5e55\u6dfb\u52a0\u65b9\u5f0f',
        onBack: drawer.popPage,
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (canSearchRemoteSubtitle)
            _SubtitleMenuTile(
              title: '\u641c\u7d22\u4e0b\u8f7d\u5b57\u5e55',
              onTap: () {
                drawer.push(_subtitleSearchPageId);
                unawaited(_loadRemoteSubtitleSearch(drawer));
              },
            ),
          if (canSearchRemoteSubtitle) const SizedBox(height: 12),
          _SubtitleMenuTile(
            title: '\u6dfb\u52a0\u672c\u5730\u5b57\u5e55',
            onTap: () =>
                unawaited(_pickAndAttachLocalSubtitleFromBrowser(drawer)),
          ),
        ],
      ),
    );
  }

  bool _canSearchRemoteSubtitlesForCurrentSource() {
    if (_externalLocalSource) return false;
    final mediaGuid = _subtitleSourceMediaGuid.trim().isNotEmpty
        ? _subtitleSourceMediaGuid.trim()
        : _currentMediaGuid.trim();
    return mediaGuid.isNotEmpty;
  }

  Widget _buildSubtitleSearchPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    final loading = _subtitleSearchLoadingLanguage != null;
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: '\u641c\u7d22\u4e0b\u8f7d\u5b57\u5e55',
        onBack: drawer.popPage,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _currentTitle.trim().isEmpty
                      ? '\u5f53\u524d\u89c6\u9891'
                      : _currentTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _SubtitlePillButton(
                label: _subtitleSearchLanguageLabel(_subtitleSearchLanguage),
                onTap: () => drawer.push(_subtitleLanguagePageId),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            '\u6309\u76f8\u5173\u5ea6\u6392\u5e8f',
            style: TextStyle(
              color: Color(0xB3FFFFFF),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: loading
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    ),
                  )
                : _subtitleSearchResults.isEmpty
                ? const Center(
                    child: Text(
                      '\u672a\u627e\u5230\u53ef\u4e0b\u8f7d\u5b57\u5e55',
                      style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 15),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: _subtitleSearchResults.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = _subtitleSearchResults[index];
                      return _SubtitleSearchResultTile(
                        title: item.filename,
                        meta:
                            '${item.source.toUpperCase()}  ${item.format.toUpperCase()}',
                        downloads: item.download,
                        loading: item.trimId == _subtitleDownloadTrimId,
                        onTap: () => unawaited(
                          _downloadRemoteSubtitle(item: item, drawer: drawer),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubtitleLanguagePage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    final items = <Map<String, String>>[
      <String, String>{'label': '\u7b80\u4f53\u4e2d\u6587', 'value': 'zh-CN'},
      <String, String>{'label': '\u82f1\u6587', 'value': 'en'},
    ];
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: '\u9009\u62e9\u8bed\u8a00',
        onBack: drawer.popPage,
      ),
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = items[index];
          final value = item['value']!;
          return _SubtitleOptionTile(
            title: item['label']!,
            selected: value == _subtitleSearchLanguage,
            onTap: () =>
                unawaited(_changeSubtitleSearchLanguage(value, drawer)),
          );
        },
      ),
    );
  }

  Widget _buildSubtitleAdjustPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: '\u5b57\u5e55\u8c03\u6574',
        onBack: drawer.popPage,
        actions: [
          TextButton.icon(
            onPressed: () => unawaited(_resetSubtitleStyle(drawer)),
            icon: const Icon(Icons.restart_alt_rounded, color: Colors.white),
            label: const Text(
              '\u91cd\u7f6e',
              style: TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ],
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _SubtitleAdjustRow(
            label: '\u5ef6\u8fdf',
            child: Row(
              children: [
                Expanded(
                  child: _SubtitleActionCapsule(
                    label: '\u5ef6\u540e',
                    onTap: () => unawaited(
                      _setSubtitleDelaySeconds(
                        _subtitleDelaySeconds + 0.1,
                        drawer: drawer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SubtitleValueCapsule(
                    label: _subtitleDelayDisplayLabel(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SubtitleActionCapsule(
                    label: '\u63d0\u524d',
                    onTap: () => unawaited(
                      _setSubtitleDelaySeconds(
                        _subtitleDelaySeconds - 0.1,
                        drawer: drawer,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _SubtitleAdjustRow(
            label: '\u4f4d\u7f6e ${_subtitlePositionDisplayLabel()}',
            child: Row(
              children: [
                const Text(
                  '\u5e95\u90e8',
                  style: TextStyle(color: Color(0x8FFFFFFF), fontSize: 14),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: context.appColors.selectionStrong,
                      inactiveTrackColor: context.appColors.borderStrong,
                      thumbColor: context.appColors.textPrimary,
                      overlayColor: context.appColors.selectionSoft,
                      trackHeight: 3,
                    ),
                    child: Slider(
                      min: 0,
                      max: 1,
                      value: _subtitlePositionFactor.clamp(0.0, 1.0).toDouble(),
                      onChanged: (value) => unawaited(
                        _setSubtitlePositionFactor(value, drawer: drawer),
                      ),
                    ),
                  ),
                ),
                const Text(
                  '\u9876\u90e8',
                  style: TextStyle(color: Color(0x8FFFFFFF), fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _SubtitleAdjustRow(
            label: '\u5927\u5c0f ${_subtitleScaleDisplayLabel()}',
            child: Row(
              children: [
                const Text(
                  '\u5c0f',
                  style: TextStyle(color: Color(0x8FFFFFFF), fontSize: 14),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: context.appColors.accent,
                      inactiveTrackColor: context.appColors.borderStrong,
                      thumbColor: context.appColors.textPrimary,
                      overlayColor: context.appColors.accentSoft,
                      trackHeight: 3,
                    ),
                    child: Slider(
                      min: 0,
                      max: 1,
                      value: _subtitleScaleFactor.clamp(0.0, 1.0).toDouble(),
                      onChanged: (value) => unawaited(
                        _setSubtitleScaleFactor(value, drawer: drawer),
                      ),
                    ),
                  ),
                ),
                const Text(
                  '\u5927',
                  style: TextStyle(color: Color(0x8FFFFFFF), fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectSubtitleFromDrawer(
    String guid,
    PlayerNestedSheetController<void> drawer,
  ) async {
    final selected = _findSubtitleTrack(guid.trim());
    final plan = _subtitleController.planSelectionChange(
      guid: guid,
      currentGuid: _currentSubtitleGuid,
      serverManagedPlayback: _playbackMode.isServerManaged,
      requiresExternalFile: _subtitleShouldUseExternalFile(selected),
      hasDirectFile: _subtitleHasDirectFile(selected),
    );
    switch (plan.action) {
      case PlayerSubtitleSelectionAction.closeDrawer:
        drawer.close();
        return;
      case PlayerSubtitleSelectionAction.blockedByDirectFile:
        _showTransientMessage(
          '\u5f53\u524d\u5b57\u5e55\u6682\u4e0d\u652f\u6301\u5207\u6362',
        );
        return;
      case PlayerSubtitleSelectionAction.apply:
        break;
    }
    _invalidateNextEpisodePreload();
    _updatePlayerState(() {
      _uiController.qualitySwitchLoading = true;
      _uiController.subtitleSwitchMessage =
          _subtitleDrawerSwitchMessageForTrack(selected);
      _currentSubtitleGuid = plan.normalizedGuid;
      _subtitleExplicitlyDisabled = plan.subtitleExplicitlyDisabled;
    });
    try {
      _subtitleStatusTipSuppressedUntil = plan.subtitleStatusTipSuppressedUntil;
      await _applySubtitleSelection();
      _showControls();
      if (mounted) {
        drawer.close();
      }
    } finally {
      final transitionStillActive =
          _uiController.pendingLoadingTransition ||
          _uiController.awaitingVisualPlaybackStart;
      if (!transitionStillActive) {
        if (mounted) {
          _updatePlayerState(() => _uiController.qualitySwitchLoading = false);
        }
        _hideSubtitleSwitchMessage(delay: const Duration(milliseconds: 900));
      }
    }
  }

  Future<void> _loadRemoteSubtitleSearch(
    PlayerNestedSheetController<void> drawer,
  ) async {
    if (!_canSearchRemoteSubtitlesForCurrentSource()) return;
    final mediaGuid = _subtitleSourceMediaGuid.trim().isNotEmpty
        ? _subtitleSourceMediaGuid.trim()
        : _currentMediaGuid;
    if (mediaGuid.isEmpty) {
      _showTransientMessage(
        '\u5f53\u524d\u89c6\u9891\u7f3a\u5c11\u5a92\u4f53\u6807\u8bc6',
      );
      return;
    }
    if (!_subtitleController.beginRemoteSearch(_subtitleSearchLanguage)) {
      return;
    }
    drawer.refresh();
    try {
      final api = FeiniuApi(context.read<NasProvider>());
      final results = await _subtitleService.searchRemoteSubtitles(
        api: api,
        mediaGuid: mediaGuid,
        language: _subtitleSearchLanguage,
      );
      _subtitleController.completeRemoteSearch(results);
      if (!mounted) return;
    } catch (error, trace) {
      unawaited(
        AppErrorReporter.report(
          error,
          action: 'search remote subtitles',
          source: 'mpv_player_subtitle',
          stackTrace: trace,
          fallbackKind: AppExceptionKind.transient,
          details: 'mediaGuid=$mediaGuid language=$_subtitleSearchLanguage',
        ),
      );
      _subtitleController.failRemoteSearch();
      if (mounted) {
        _showTransientMessage('\u641c\u7d22\u5b57\u5e55\u5931\u8d25: $error');
      }
    } finally {
      if (mounted) {
        drawer.refresh();
      }
    }
  }

  Future<void> _changeSubtitleSearchLanguage(
    String language,
    PlayerNestedSheetController<void> drawer,
  ) async {
    if (!_canSearchRemoteSubtitlesForCurrentSource()) {
      drawer.popPage();
      return;
    }
    if (!_subtitleController.updateSearchLanguage(language)) {
      drawer.popPage();
      return;
    }
    drawer.popPage();
    drawer.refresh();
    await _loadRemoteSubtitleSearch(drawer);
  }

  Future<void> _downloadRemoteSubtitle({
    required RemoteSubtitleSearchItem item,
    required PlayerNestedSheetController<void> drawer,
  }) async {
    if (!_canSearchRemoteSubtitlesForCurrentSource()) return;
    final mediaGuid = _subtitleSourceMediaGuid.trim().isNotEmpty
        ? _subtitleSourceMediaGuid.trim()
        : _currentMediaGuid;
    if (mediaGuid.isEmpty) {
      _showTransientMessage(
        '\u5f53\u524d\u89c6\u9891\u7f3a\u5c11\u5a92\u4f53\u6807\u8bc6',
      );
      return;
    }
    _subtitleController.beginRemoteDownload(item.trimId);
    drawer.refresh();
    try {
      final api = FeiniuApi(context.read<NasProvider>());
      final track = await _subtitleService.downloadRemoteSubtitleTrack(
        api: api,
        mediaGuid: mediaGuid,
        trimId: item.trimId,
      );
      if (!mounted) return;
      _upsertSubtitleTrack(track, insertAtFront: true);
      await _selectSubtitleFromDrawer(track.guid, drawer);
    } catch (error, trace) {
      unawaited(
        AppErrorReporter.report(
          error,
          action: 'download remote subtitle',
          source: 'mpv_player_subtitle',
          stackTrace: trace,
          fallbackKind: AppExceptionKind.transient,
          details: 'mediaGuid=$mediaGuid trimId=${item.trimId}',
        ),
      );
      if (mounted) {
        _showTransientMessage('\u4e0b\u8f7d\u5b57\u5e55\u5931\u8d25: $error');
      }
    } finally {
      _subtitleController.finishRemoteDownload();
      if (mounted) {
        drawer.refresh();
      }
    }
  }

  Future<void> _pickAndAttachLocalSubtitleFromBrowser(
    PlayerNestedSheetController<void> drawer,
  ) async {
    try {
      final selection = await LocalFileBrowserSheet.pickFile(
        context,
        title: '\u9009\u62e9\u5b57\u5e55\u6587\u4ef6',
        allowedExtensions: const <String>[
          'ass',
          'ssa',
          'srt',
          'vtt',
          'sub',
          'txt',
        ],
      );
      if (!mounted || selection == null) return;
      final guid = 'local:${DateTime.now().microsecondsSinceEpoch}';
      final title = selection.displayName.trim();
      if (title.isEmpty) return;
      final format = _subtitleFormatFromFileName(title, selection.identifier);
      final path = StorageAccessService.isScopedIdentifier(selection.identifier)
          ? await (() async {
              final bytes = await StorageAccessService.readScopedFileBytes(
                selection.identifier,
              );
              if (bytes == null || bytes.isEmpty) {
                throw const FileSystemException(
                  '\u65e0\u6cd5\u8bfb\u53d6\u5df2\u9009\u62e9\u7684\u5b57\u5e55\u6587\u4ef6',
                );
              }
              final tempPath =
                  '${Directory.systemTemp.path}${Platform.pathSeparator}'
                  'fly_player_local_sub_${DateTime.now().microsecondsSinceEpoch}.$format';
              return _writeSubtitleBytesToTempFile(
                path: tempPath,
                bytes: bytes,
              );
            })()
          : selection.identifier;
      if (!mounted || path.trim().isEmpty) return;
      _subtitleController.cacheLocalSubtitleFile(guid: guid, path: path);
      _upsertSubtitleTrack(
        _subtitleController.buildLocalSubtitleTrack(
          mediaGuid: _subtitleSourceMediaGuid.trim().isNotEmpty
              ? _subtitleSourceMediaGuid.trim()
              : _currentMediaGuid,
          guid: guid,
          title: title,
          format: format,
        ),
        insertAtFront: true,
      );
      await _selectSubtitleFromDrawer(guid, drawer);
    } catch (error) {
      if (mounted) {
        _showTopTip(
          '\u6dfb\u52a0\u672c\u5730\u5b57\u5e55\u5931\u8d25: $error',
          context.appColors.danger,
        );
      }
    }
  }

  void _upsertSubtitleTrack(
    SubtitleTrackOption track, {
    bool insertAtFront = false,
  }) {
    _updatePlayerState(() {
      _subtitleTracks = _subtitleController.upsertSubtitleTrack(
        _subtitleTracks,
        track,
        insertAtFront: insertAtFront,
      );
    });
  }

  Future<void> _deleteSubtitleFromDrawer(
    SubtitleTrackOption track,
    PlayerNestedSheetController<void> drawer,
  ) async {
    if (!_subtitleController.beginDeletingTrack(track.guid)) return;
    drawer.refresh();
    try {
      if (!track.guid.startsWith('local:')) {
        final api = FeiniuApi(context.read<NasProvider>());
        await api.deleteSubtitle(
          subtitleGuid: track.guid,
          mediaGuid: track.mediaGuid,
        );
      }

      final result = _subtitleController.completeTrackDeletion(
        track: track,
        currentTracks: _subtitleTracks,
        currentGuid: _currentSubtitleGuid,
      );
      if ((result.removedCachedPath ?? '').isNotEmpty) {
        unawaited(_deleteTempFile(result.removedCachedPath!));
      }
      _updatePlayerState(() {
        _subtitleTracks = result.remainingTracks;
        _currentSubtitleGuid = result.nextCurrentGuid;
        _subtitleExplicitlyDisabled = result.nextSubtitleExplicitlyDisabled;
      });
      if (result.shouldApplySelection) {
        _subtitleStatusTipSuppressedUntil =
            result.subtitleStatusTipSuppressedUntil;
        await _applySubtitleSelection();
      }
    } catch (error) {
      if (mounted) {
        _showTransientMessage('\u5220\u9664\u5b57\u5e55\u5931\u8d25: $error');
      }
    } finally {
      _subtitleController.finishDeletingTrack();
      if (mounted) {
        drawer.refresh();
      }
    }
  }

  bool _subtitleCanDelete(SubtitleTrackOption track) {
    return _subtitleController.subtitleCanDelete(track);
  }

  Future<void> _setSubtitleDelaySeconds(
    double value, {
    required PlayerNestedSheetController<void> drawer,
  }) async {
    _subtitleDelaySeconds = _subtitleController.updateSubtitleDelaySeconds(
      value,
    );
    drawer.refresh();
    await _persistSubtitleAdjustmentRecord();
    await _syncEffectiveSubtitleDelay(force: true);
  }

  Future<void> _setSubtitlePositionFactor(
    double value, {
    required PlayerNestedSheetController<void> drawer,
  }) async {
    _subtitleController.updateSubtitlePositionFactor(value);
    _subtitlePositionFactor = _subtitleController.subtitlePositionFactor;
    drawer.refresh();
    await _persistSubtitleAdjustmentRecord();
    await _syncEffectiveSubtitlePosition(force: true);
  }

  Future<void> _setSubtitleScaleFactor(
    double value, {
    required PlayerNestedSheetController<void> drawer,
  }) async {
    _subtitleController.updateSubtitleScaleFactor(
      value,
      minScale: _subtitleScaleMin,
      maxScale: _subtitleScaleMax,
    );
    _subtitleScaleFactor = _subtitleController.subtitleScaleFactor;
    drawer.refresh();
    await _persistSubtitleAdjustmentRecord();
    await _syncEffectiveSubtitleScale(force: true);
  }

  Future<void> _resetSubtitleStyle(
    PlayerNestedSheetController<void> drawer,
  ) async {
    _subtitleController.resetSubtitleStyle(
      minScale: _subtitleScaleMin,
      maxScale: _subtitleScaleMax,
    );
    _subtitleDelaySeconds = _subtitleController.subtitleDelaySeconds;
    _subtitlePositionFactor = _subtitleController.subtitlePositionFactor;
    _subtitleScaleFactor = _subtitleController.subtitleScaleFactor;
    drawer.refresh();
    await _persistSubtitleAdjustmentRecord();
    await _controller.resetSubtitleStyle();
    _invalidateAppliedSubtitleStyle();
    await _syncEffectiveSubtitleStyle(force: true);
  }

  Future<void> _persistSubtitleAdjustmentRecord() {
    return _runtimePreferencesStore.saveSubtitleAdjustmentRecord(
      key: _currentSubtitleAdjustmentRecordKey(),
      title: _currentTitle,
      subtitleDelaySeconds: _subtitleDelaySeconds,
      subtitlePositionFactor: _subtitlePositionFactor,
      subtitleScaleFactor: _subtitleScaleFactor,
    );
  }

  String _subtitleDelayDisplayLabel() {
    final value = _subtitleDelaySeconds;
    final sign = value > 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(1)} \u79d2';
  }

  String _subtitlePositionDisplayLabel() {
    final percent = (_subtitlePositionFactor.clamp(0.0, 1.0) * 100).round();
    return '$percent%';
  }

  String _subtitleScaleDisplayLabel() {
    final factor = _subtitleScaleFactor.clamp(0.0, 1.0).toDouble();
    final scale =
        _subtitleScaleMin + ((_subtitleScaleMax - _subtitleScaleMin) * factor);
    return '${scale.toStringAsFixed(2)}x';
  }

  String _subtitleSearchLanguageLabel(String language) {
    final l10n = AppLocalizations.of(context);
    switch (language) {
      case 'en':
        return l10n.playerSubtitleLanguageEnglish;
      case 'zh-CN':
      default:
        return l10n.playerSubtitleLanguageChinese;
    }
  }

  String _subtitleFormatFromFileName(String fileName, String fallbackPath) {
    return _subtitleController.subtitleFormatFromFileName(
      fileName,
      fallbackPath,
    );
  }

  String _subtitleStreamTitle(SubtitleTrackOption track) {
    return _subtitleController.subtitleStreamTitle(
      track,
      subtitleLabel: _subtitleSubtitle(track),
    );
  }

  String _subtitleDrawerSwitchMessageForTrack(SubtitleTrackOption? track) {
    final l10n = AppLocalizations.of(context);
    if (track == null) {
      return l10n.playerSubtitleClosing;
    }
    final title = _subtitleTitle(track);
    final format = (track.format.isNotEmpty ? track.format : track.codecName)
        .trim()
        .toLowerCase();
    final suffix = format.isEmpty ? '' : ' ($format)';
    return l10n.playerSubtitleSwitching(title, suffix);
  }
}

class _SubtitleDrawerTileData {
  final String title;
  final String subtitle;
  final String trailingDetail;
  final bool deleting;
  final VoidCallback? onDelete;
  final bool selected;
  final VoidCallback onTap;

  const _SubtitleDrawerTileData({
    required this.title,
    this.subtitle = '',
    this.trailingDetail = '',
    this.deleting = false,
    this.onDelete,
    required this.selected,
    required this.onTap,
  });
}

class _SubtitleHeaderActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SubtitleHeaderActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: Colors.white, size: 19),
      label: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
    );
  }
}

class _SubtitlePrimaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SubtitlePrimaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.accentSoft,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: colors.textPrimary, size: 20),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubtitlePillButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SubtitlePillButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.surfaceStrong,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: colors.textPrimary,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubtitleMenuTile extends StatelessWidget {
  final String title;
  final VoidCallback onTap;

  const _SubtitleMenuTile({required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.borderStrong),
            color: colors.surface.withValues(alpha: 0.58),
          ),
          child: Text(
            title,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _SubtitleOptionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String trailingDetail;
  final bool deleting;
  final VoidCallback? onDelete;
  final bool selected;
  final VoidCallback onTap;

  const _SubtitleOptionTile({
    required this.title,
    this.subtitle = '',
    this.trailingDetail = '',
    this.deleting = false,
    this.onDelete,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: selected
                ? colors.selectionSoft
                : colors.surface.withValues(alpha: 0.58),
            border: Border.all(
              color: selected ? colors.selection : colors.borderSubtle,
              width: selected ? 1.2 : 0.9,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? colors.selection : colors.chipBorder,
                    width: 2,
                  ),
                  color: selected ? colors.selection : Colors.transparent,
                ),
                child: selected
                    ? Icon(Icons.check, color: colors.textPrimary, size: 14)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? colors.selectionStrong
                            : colors.textPrimary,
                        fontSize: title.length > 12 ? 13.5 : 14.5,
                        fontWeight: FontWeight.w500,
                        height: 1.15,
                      ),
                    ),
                    if (subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: Color(0xB3FFFFFF),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (trailingDetail.trim().isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                trailingDetail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0x85FFFFFF),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (onDelete != null) ...[
                const SizedBox(width: 10),
                _SubtitleDeleteButton(
                  deleting: deleting,
                  onTap: deleting ? null : onDelete,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SubtitleSearchResultTile extends StatelessWidget {
  final String title;
  final String meta;
  final int downloads;
  final bool loading;
  final VoidCallback onTap;

  const _SubtitleSearchResultTile({
    required this.title,
    required this.meta,
    required this.downloads,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.borderStrong),
            color: colors.surface.withValues(alpha: 0.58),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: title.length > 26 ? 13.5 : 14.5,
                        fontWeight: FontWeight.w500,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(
                          Icons.download_rounded,
                          color: colors.textSecondary,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$downloads',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              loading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.accent,
                      ),
                    )
                  : Icon(
                      Icons.download_for_offline_outlined,
                      color: colors.textPrimary,
                      size: 22,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubtitleDeleteButton extends StatelessWidget {
  final bool deleting;
  final VoidCallback? onTap;

  const _SubtitleDeleteButton({required this.deleting, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkResponse(
      onTap: onTap,
      radius: 18,
      child: SizedBox(
        width: 24,
        height: 24,
        child: Center(
          child: deleting
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: colors.accent,
                  ),
                )
              : Icon(
                  Icons.delete_outline_rounded,
                  color: colors.textSecondary,
                  size: 20,
                ),
        ),
      ),
    );
  }
}

class _SubtitleAdjustRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _SubtitleAdjustRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _SubtitleActionCapsule extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SubtitleActionCapsule({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.surfaceStrong,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 56,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SubtitleValueCapsule extends StatelessWidget {
  final String label;

  const _SubtitleValueCapsule({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.borderStrong),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
