part of mpv_player_page;

const String _audioMainPageId = 'audio_main';
const String _audioAdjustPageId = 'audio_adjust';

extension _MpvPlayerAudioDrawerMixin on _MpvPlayerPageState {
  Future<void> _showAudioDrawer() async {
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
    if (_isLocalRuntimeTrackSource()) {
      await _refreshRuntimeTracks(force: true);
      if (!mounted) return;
    }
    if (_audioTracks.isEmpty) {
      _showTransientMessage('当前没有可用音轨');
      return;
    }
    _overlayState.cancelAutoHide();
    final restoreControls = _controlsVisible;
    if (restoreControls) {
      _hideControlsImmediately();
    }
    try {
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
      if (mounted && restoreControls) {
        _showControls();
      }
    }
  }

  Widget _buildAudioMainPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    final tracks = _audioTracks;
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: '音频',
        actions: <Widget>[
          _SubtitleHeaderActionButton(
            icon: Icons.tune_rounded,
            label: '调节',
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
                  '音轨列表',
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
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 2),
              itemCount: tracks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final track = tracks[index];
                return _SubtitleOptionTile(
                  title: _audioTitle(track),
                  subtitle: _audioSubtitle(track),
                  selected: track.guid == _currentAudioGuid,
                  onTap: () =>
                      unawaited(_selectAudioTrackFromDrawer(track, drawer)),
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
        title: '音频调整',
        onBack: drawer.popPage,
        actions: [
          TextButton.icon(
            onPressed: () => unawaited(_resetAudioDelay(drawer)),
            icon: const Icon(Icons.restart_alt_rounded, color: Colors.white),
            label: const Text(
              '重置',
              style: TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ],
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _SubtitleAdjustRow(
            label: '音频延迟',
            child: Row(
              children: [
                Expanded(
                  child: _SubtitleActionCapsule(
                    label: '延后',
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
                    label: '提前',
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
            '正值会让声音更晚，负值会让声音更早。',
            style: TextStyle(
              color: context.appColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          PlaybackSettingsMenuTile(
            title: '均衡器与滤镜',
            subtitle: 'EQ、限幅、低音增强、人声增强',
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
    if (_playbackMode.isServerManaged) {
      final currentPosition = _displayPosition(_controller.value.value);
      var reloadStarted = false;
      _updatePlayerState(() {
        _uiController.qualitySwitchLoading = true;
        _currentAudioGuid = selected.guid;
      });
      _uiController.pendingLoadingTransition = true;
      _markAwaitingVisualPlaybackStart(
        currentPosition,
        targetPaused: _controller.value.value.paused,
      );
      _showSubtitleSwitchMessage('正在切换音频，请稍等...');
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
    return '$prefix${seconds.toStringAsFixed(1)} 秒';
  }

  String _audioDelayErrorMessage(Object error) {
    if (error is MissingPluginException) {
      return '音频延迟原生模块未加载，请重启应用后重试';
    }
    return '音频延迟设置失败';
  }
}
