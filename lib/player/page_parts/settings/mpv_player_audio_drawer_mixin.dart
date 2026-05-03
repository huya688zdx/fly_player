part of '../../mpv_player_page.dart';

const String _audioMainPageId = 'audio_main';
const String _audioAdjustPageId = 'audio_adjust';

extension _MpvPlayerAudioDrawerMixin on _MpvPlayerPageState {
  Future<void> _showAudioDrawer() async {
    if (_playerUiLocked) return;
    _hideSpeedDialOverlay(restoreAutoHide: false);
    final audioProcessingKeys = <String>{
      _MpvPlayerPageState._mpvSettingVolumeGain,
      _MpvPlayerPageState._mpvSettingAudioHighFidelity,
      _MpvPlayerPageState._mpvSettingDynamicRange,
      _MpvPlayerPageState._mpvSettingAudioEq,
      _MpvPlayerPageState._mpvSettingAudioLimiter,
      _MpvPlayerPageState._mpvSettingAudioBassBoost,
      _MpvPlayerPageState._mpvSettingAudioVoiceEnhance,
      _MpvPlayerPageState._mpvSettingChannelMix,
    };
    final shouldWarmupLocalTracks = _isLocalRuntimeTrackSource();
    if (!shouldWarmupLocalTracks && _audioTracks.isEmpty) {
      _showTransientMessage('\u5f53\u524d\u6ca1\u6709\u53ef\u7528\u97f3\u8f68');
      return;
    }
    _overlayState.cancelAutoHide();
    final restoreControls = _controlsVisible;
    if (restoreControls) {
      _hideControlsImmediately();
    }
    try {
      if (mounted && !_audioDrawerVisible) {
        _audioDrawerVisible = true;
        unawaited(_syncDanmakuDynamicOcclusionConfig());
      }
      if (shouldWarmupLocalTracks) {
        _audioDrawerSyncInFlight = true;
        unawaited(_warmupAudioDrawerTracks());
      }
      await PlayerNestedSheet.show<void>(
        context,
        initialPageId: _audioMainPageId,
        barrierLabel: 'audio drawer',
        pages: <PlayerNestedSheetPage<void>>[
          PlayerNestedSheetPage<void>(
            id: _audioMainPageId,
            builder: _buildAudioMainPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _audioAdjustPageId,
            builder: _buildAudioAdjustPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsMpvAudioProcessingPageId,
            builder: (context, drawer) => _buildMpvCategoryPage(
              drawer,
              category: _mpvAudioProcessingCategory,
            ),
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsMpvAudioEqAdvancedPageId,
            builder: (context, drawer) => _buildMpvAudioEqAdvancedPage(drawer),
          ),
          ..._mpvChoiceDefinitions
              .where(
                (definition) => audioProcessingKeys.contains(definition.key),
              )
              .map(
                (definition) => PlayerNestedSheetPage<void>(
                  id: definition.pageId,
                  builder: (context, drawer) =>
                      _buildMpvChoicePage(drawer, definition),
                ),
              ),
        ],
      );
    } finally {
      _activeAudioDrawerController = null;
      _audioDrawerSyncInFlight = false;
      if (mounted && _audioDrawerVisible) {
        _audioDrawerVisible = false;
        unawaited(_syncDanmakuDynamicOcclusionConfig());
        unawaited(_startOrUpdateSystemPlaybackSession(force: true));
      }
      if (mounted && !restoreControls) {
        _scheduleControlsAutoHide();
      }
    }
  }

  Future<void> _warmupAudioDrawerTracks() async {
    try {
      await _refreshRuntimeTracks(force: true);
    } finally {
      _audioDrawerSyncInFlight = false;
      _activeAudioDrawerController?.refresh();
    }
  }

  Widget _buildAudioMainPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    _activeAudioDrawerController = drawer;
    final tracks = _audioTracks;
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: '\u97f3\u9891',
        actions: <Widget>[
          _SubtitleHeaderActionButton(
            icon: Icons.tune_rounded,
            label: '\u8c03\u8282',
            onTap: () => drawer.push(_audioAdjustPageId),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '\u97f3\u8f68\u5217\u8868',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              _SubtitlePillButton(
                label: _audioDelayDisplayLabel(_audioDelaySeconds),
                onTap: () => drawer.push(_audioAdjustPageId),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _audioDrawerSyncInFlight && tracks.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : tracks.isEmpty
                ? Center(
                    child: Text(
                      '\u5f53\u524d\u6ca1\u6709\u53ef\u7528\u97f3\u8f68',
                      style: TextStyle(
                        color: context.appColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 2),
                    itemCount: tracks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final track = tracks[index];
                      return _SubtitleOptionTile(
                        title: _audioTitle(track),
                        subtitle: _audioSubtitle(track),
                        selected: track.guid == _currentAudioGuid,
                        onTap: () => unawaited(
                          _selectAudioTrackFromDrawer(track, drawer),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioAdjustPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: '\u97f3\u9891\u8c03\u6574',
        onBack: drawer.popPage,
        actions: [
          TextButton.icon(
            onPressed: () => unawaited(_resetAudioDelay(drawer)),
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
            label: '\u97f3\u9891\u5ef6\u8fdf',
            child: Row(
              children: [
                Expanded(
                  child: _SubtitleActionCapsule(
                    label: '\u5ef6\u540e',
                    onTap: () => unawaited(
                      _setAudioDelaySeconds(
                        _audioDelaySeconds + 0.1,
                        drawer: drawer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SubtitleValueCapsule(
                    label: _audioDelayDisplayLabel(_audioDelaySeconds),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SubtitleActionCapsule(
                    label: '\u63d0\u524d',
                    onTap: () => unawaited(
                      _setAudioDelaySeconds(
                        _audioDelaySeconds - 0.1,
                        drawer: drawer,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '\u6b63\u503c\u4f1a\u8ba9\u58f0\u97f3\u66f4\u665a\uff0c\u8d1f\u503c\u4f1a\u8ba9\u58f0\u97f3\u66f4\u65e9\u3002',
            style: TextStyle(
              color: context.appColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          PlaybackSettingsMenuTile(
            title: '\u5747\u8861\u5668\u4e0e\u6ee4\u955c',
            subtitle:
                '\u5305\u542b EQ\u3001\u9650\u5e45\u3001\u4f4e\u97f3\u589e\u5f3a\u3001\u4eba\u58f0\u589e\u5f3a',
            trailingLabel: _mpvCategorySummaryLabel(
              _mpvAudioProcessingCategory,
            ),
            onTap: () => drawer.push(_playerSettingsMpvAudioProcessingPageId),
          ),
        ],
      ),
    );
  }

  Future<void> _selectAudioTrackFromDrawer(
    AudioTrackOption selected,
    PlayerNestedSheetController<void> drawer,
  ) async {
    if (selected.guid == _currentAudioGuid) {
      drawer.close();
      return;
    }
    _invalidateNextEpisodePreload();
    if (_playbackMode.isServerManaged) {
      final currentPosition = _displayPosition(_controller.value.value);
      var reloadStarted = false;
      _updatePlayerState(() {
        _uiController.qualitySwitchLoading = true;
        _uiController.subtitleSwitchMessage =
            '\u6b63\u5728\u5207\u6362\u97f3\u9891\uff0c\u8bf7\u7a0d\u7b49...';
        _currentAudioGuid = selected.guid;
      });
      _uiController.pendingLoadingTransition = true;
      _markAwaitingVisualPlaybackStart(
        currentPosition,
        targetPaused: _controller.value.value.paused,
      );
      _showSubtitleSwitchMessage(
        '\u6b63\u5728\u5207\u6362\u97f3\u9891\uff0c\u8bf7\u7a0d\u7b49...',
      );
      try {
        await _reloadServerPlaySession(audioGuid: selected.guid);
        reloadStarted = true;
        _showControls();
        if (mounted) {
          drawer.close();
        }
      } finally {
        if (!reloadStarted) {
          _cancelPendingLoadingTransition();
        }
      }
      return;
    }
    _updatePlayerState(() => _currentAudioGuid = selected.guid);
    await _controller.setAudioTrack(
      trackIndex: _mpvAudioTrackId(selected),
      trackGuid: selected.guid,
    );
    _showControls();
    if (mounted) {
      drawer.close();
    }
  }

  Future<void> _setAudioDelaySeconds(
    double value, {
    required PlayerNestedSheetController<void> drawer,
  }) async {
    final warningColor = context.appColors.warning;
    final previous = _audioDelaySeconds;
    final normalized = value.clamp(-10.0, 10.0).toDouble();
    _audioDelaySeconds = double.parse(normalized.toStringAsFixed(1));
    drawer.refresh();
    try {
      await _controller.setAudioDelay(_audioDelaySeconds);
    } catch (error) {
      _audioDelaySeconds = previous;
      drawer.refresh();
      _showTopTip(_audioDelayErrorMessage(error), warningColor);
    }
  }

  Future<void> _resetAudioDelay(
    PlayerNestedSheetController<void> drawer,
  ) async {
    final warningColor = context.appColors.warning;
    final previous = _audioDelaySeconds;
    _audioDelaySeconds = 0;
    drawer.refresh();
    try {
      await _controller.setAudioDelay(_audioDelaySeconds);
    } catch (error) {
      _audioDelaySeconds = previous;
      drawer.refresh();
      _showTopTip(_audioDelayErrorMessage(error), warningColor);
    }
  }

  String _audioDelayDisplayLabel(double seconds) {
    final prefix = seconds > 0 ? '+' : '';
    return '$prefix${seconds.toStringAsFixed(1)} \u79d2';
  }

  String _audioDelayErrorMessage(Object error) {
    if (error is MissingPluginException) {
      return '\u97f3\u9891\u5ef6\u8fdf\u539f\u751f\u6a21\u5757\u672a\u52a0\u8f7d\uff0c\u8bf7\u91cd\u542f\u5e94\u7528\u540e\u91cd\u8bd5';
    }
    return '\u97f3\u9891\u5ef6\u8fdf\u8bbe\u7f6e\u5931\u8d25';
  }
}
