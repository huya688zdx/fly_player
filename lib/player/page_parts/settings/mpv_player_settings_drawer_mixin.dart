part of mpv_player_page;

const String _playerSettingsMainPageId = 'player_settings_main';
const String _playerSettingsAdvancedPageId = 'player_settings_advanced';
const String _playerSettingsIntroOutroPageId = 'player_settings_intro_outro';
const String _playerSettingsVideoInfoPageId = 'player_settings_video_info';
const String _playerSettingsDecoderPageId = 'player_settings_decoder';
const String _playerSettingsMonitorPageId = 'player_settings_monitor';
const String _playerSettingsIntroChapterPageId =
    'player_settings_intro_chapter';
const String _playerSettingsOutroChapterPageId =
    'player_settings_outro_chapter';
const String _playerSettingsOfficialConfigPageId =
    'player_settings_intro_outro_official';
const String _playerSettingsOfficialOpeningPageId =
    'player_settings_intro_outro_official_opening';
const String _playerSettingsOfficialEndingPageId =
    'player_settings_intro_outro_official_ending';
const String _playerSettingsChapterConfigPageId =
    'player_settings_intro_outro_chapter';
const String _playerSettingsMpvPageId = 'player_settings_mpv';
const String _playerSettingsMpvQuickAdjustPageId =
    'player_settings_mpv_quick_adjust';
const String _playerSettingsMpvPresetPageId = 'player_settings_mpv_preset';
const String _playerSettingsMpvCustomPageId = 'player_settings_mpv_custom';
const String _playerSettingsMpvVideoFiltersPageId =
    'player_settings_mpv_video_filters';
const String _playerSettingsMpvPictureRenderingPageId =
    'player_settings_mpv_picture_rendering';
const String _playerSettingsMpvPlaybackSyncPageId =
    'player_settings_mpv_playback_sync';
const String _playerSettingsMpvAudioProcessingPageId =
    'player_settings_mpv_audio_processing';
const String _playerSettingsMpvCompatibilityPageId =
    'player_settings_mpv_compatibility';
const String _playerSettingsMpvDebandPageId = 'player_settings_mpv_deband';
const String _playerSettingsMpvSharpenPageId = 'player_settings_mpv_sharpen';
const String _playerSettingsMpvDenoisePageId = 'player_settings_mpv_denoise';
const String _playerSettingsMpvDeinterlacePageId =
    'player_settings_mpv_deinterlace';
const String _playerSettingsMpvScaleProfilePageId =
    'player_settings_mpv_scale_profile';
const String _playerSettingsMpvHdrPageId = 'player_settings_mpv_hdr';
const String _playerSettingsMpvFrameInterpolationPageId =
    'player_settings_mpv_frame_interpolation';
const String _playerSettingsMpvVideoSyncPageId =
    'player_settings_mpv_video_sync';
const String _playerSettingsMpvCachePageId = 'player_settings_mpv_cache';
const String _playerSettingsMpvCacheSizePageId =
    'player_settings_mpv_cache_size';
const String _playerSettingsMpvVolumeGainPageId =
    'player_settings_mpv_volume_gain';
const String _playerSettingsMpvAudioHighFidelityPageId =
    'player_settings_mpv_audio_high_fidelity';
const String _playerSettingsMpvDynamicRangePageId =
    'player_settings_mpv_dynamic_range';
const String _playerSettingsMpvAudioEqPageId = 'player_settings_mpv_audio_eq';
const String _playerSettingsMpvAudioEqAdvancedPageId =
    'player_settings_mpv_audio_eq_advanced';
const String _playerSettingsMpvAudioLimiterPageId =
    'player_settings_mpv_audio_limiter';
const String _playerSettingsMpvAudioBassBoostPageId =
    'player_settings_mpv_audio_bass_boost';
const String _playerSettingsMpvAudioVoiceEnhancePageId =
    'player_settings_mpv_audio_voice_enhance';
const String _playerSettingsMpvChannelMixPageId =
    'player_settings_mpv_channel_mix';
const String _playerSettingsMpvCompatibilityProfilePageId =
    'player_settings_mpv_compatibility_profile';

extension _MpvPlayerSettingsDrawerMixin on _MpvPlayerPageState {
  Future<void> _showPlaybackSettingsDrawer({
    String initialPageId = _playerSettingsMainPageId,
  }) async {
    _overlayState.cancelAutoHide();
    final restoreControls = _controlsVisible;
    if (restoreControls) {
      _hideControlsImmediately();
    }

    if (!mounted) return;
    try {
      setState(() => _playbackSettingsDrawerVisible = true);
      await PlayerNestedSheet.show<void>(
        context,
        initialPageId: initialPageId,
        barrierLabel: 'player settings drawer',
        pages: <PlayerNestedSheetPage<void>>[
          PlayerNestedSheetPage<void>(
            id: _playerSettingsMainPageId,
            builder: _buildPlaybackSettingsMainPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsAdvancedPageId,
            builder: _buildPlaybackSettingsAdvancedPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsDecoderPageId,
            builder: _buildPlaybackSettingsDecoderPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsMonitorPageId,
            builder: _buildPlaybackSettingsMonitorPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsIntroOutroPageId,
            builder: _buildPlaybackSettingsIntroOutroPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsOfficialConfigPageId,
            builder: _buildPlaybackSettingsOfficialConfigPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsOfficialOpeningPageId,
            builder: (context, drawer) =>
                _buildPlaybackSettingsOfficialTimePage(drawer, intro: true),
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsOfficialEndingPageId,
            builder: (context, drawer) =>
                _buildPlaybackSettingsOfficialTimePage(drawer, intro: false),
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsChapterConfigPageId,
            builder: _buildPlaybackSettingsChapterConfigPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsIntroChapterPageId,
            builder: (context, drawer) => _buildPlaybackSettingsChapterPage(
              drawer,
              title: '选择片头章节',
              selectedIndex: _introChapterIndex,
              onSelected: (index) {
                _setIntroOutroChapter(intro: true, chapterIndex: index);
                drawer.popPage();
              },
            ),
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsOutroChapterPageId,
            builder: (context, drawer) => _buildPlaybackSettingsChapterPage(
              drawer,
              title: '选择片尾章节',
              selectedIndex: _outroChapterIndex,
              onSelected: (index) {
                _setIntroOutroChapter(intro: false, chapterIndex: index);
                drawer.popPage();
              },
            ),
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsVideoInfoPageId,
            builder: _buildPlaybackSettingsVideoInfoPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsMpvPageId,
            builder: _buildPlaybackSettingsMpvOverviewPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsMpvQuickAdjustPageId,
            builder: _buildMpvQuickAdjustPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsBookmarkPageId,
            builder: _buildPlaybackSettingsBookmarkPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsDanmakuPageId,
            builder: _buildPlaybackSettingsDanmakuPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsDanmakuSavedPageId,
            builder: _buildPlaybackSettingsDanmakuSavedPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsDanmakuImportPageId,
            builder: _buildPlaybackSettingsDanmakuImportPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsDanmakuSearchPageId,
            builder: _buildPlaybackSettingsDanmakuSearchPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsMpvPresetPageId,
            builder: _buildPlaybackSettingsMpvPresetPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsMpvCustomPageId,
            builder: _buildPlaybackSettingsMpvCustomPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsMpvVideoFiltersPageId,
            builder: (context, drawer) => _buildMpvCategoryPage(
              drawer,
              category: _mpvVideoFiltersCategory,
            ),
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsMpvPictureRenderingPageId,
            builder: (context, drawer) => _buildMpvCategoryPage(
              drawer,
              category: _mpvPictureRenderingCategory,
            ),
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsMpvPlaybackSyncPageId,
            builder: (context, drawer) => _buildMpvCategoryPage(
              drawer,
              category: _mpvPlaybackSyncCategory,
            ),
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsMpvAudioProcessingPageId,
            builder: (context, drawer) => _buildMpvCategoryPage(
              drawer,
              category: _mpvAudioProcessingCategory,
            ),
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsMpvCompatibilityPageId,
            builder: (context, drawer) => _buildMpvCategoryPage(
              drawer,
              category: _mpvCompatibilityCategory,
            ),
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsMpvAudioEqAdvancedPageId,
            builder: (context, drawer) => _buildMpvAudioEqAdvancedPage(drawer),
          ),
          ..._mpvChoiceDefinitions.map(
            (definition) => PlayerNestedSheetPage<void>(
              id: definition.pageId,
              builder: (context, drawer) {
                if (definition.key ==
                    _MpvPlayerPageState._mpvSettingCacheSizeMb) {
                  return _buildMpvCacheSizePage(drawer);
                }
                return _buildMpvChoicePage(drawer, definition);
              },
            ),
          ),
        ],
      );
    } finally {
      if (mounted) {
        setState(() => _playbackSettingsDrawerVisible = false);
        if (restoreControls) {
          _showControls();
        }
      }
    }
  }

  Widget _buildPlaybackSettingsMainPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: '设置',
        actions: <Widget>[
          PlaybackSettingsHeaderAction(
            icon: Icons.settings_rounded,
            label: '高级设置',
            onTap: () => drawer.push(_playerSettingsAdvancedPageId),
          ),
        ],
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsSwitchTile(
            title: '自动旋转',
            subtitle: _autoRotateEnabled ? '跟随系统方向自动切换' : '锁定当前播放方向',
            value: _autoRotateEnabled,
            onChanged: (value) {
              unawaited(_setAutoRotateEnabled(value));
              drawer.refresh();
            },
          ),
          const SizedBox(height: 12),
          PlaybackSettingsAspectRatioTile(
            value: _displayAspectRatioMode,
            subtitle: '当前：${_displayAspectRatioLabel()}',
            onChanged: (value) {
              unawaited(_setDisplayAspectRatioMode(value));
              drawer.refresh();
            },
          ),
          const SizedBox(height: 12),
          if (_supportsIntroOutroUi)
            PlaybackSettingsMenuTile(
              title: '片头片尾设置',
              subtitle: _introOutroDisplaySummaryTextV3(),
              trailingLabel: _introOutroDisplayStatusLabelV3(),
              onTap: () => drawer.push(_playerSettingsIntroOutroPageId),
            ),
          if (_supportsIntroOutroUi) const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: '书签',
            subtitle: '记录当前片段关键时间点并快速跳转',
            trailingLabel: _bookmarkSummaryLabel(),
            onTap: () => drawer.push(_playerSettingsBookmarkPageId),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: 'MPV 播放器设置',
            subtitle: _mpvSettingsSummaryText(),
            trailingLabel: _mpvSettingsStatusLabel(),
            onTap: () => drawer.push(_playerSettingsMpvPageId),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackSettingsAdvancedPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(title: '高级设置', onBack: drawer.popPage),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsMenuTile(
            title: '解码方式',
            subtitle: '切换当前播放器使用的解码方式',
            trailingLabel: _decoderModeLabel(),
            onTap: () => drawer.push(_playerSettingsDecoderPageId),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: '缓存设置',
            subtitle: '直接按百分比调节播放器缓存策略强度。',
            trailingLabel: _mpvSettingLabel(
              _MpvPlayerPageState._mpvSettingCacheSizeMb,
            ),
            onTap: () => drawer.push(_playerSettingsMpvCacheSizePageId),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: '播放监测',
            subtitle: '设置左上角悬浮信息显示的性能占用和实时帧率',
            trailingLabel: _playbackMonitorStatusLabel(),
            onTap: () => drawer.push(_playerSettingsMonitorPageId),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsSwitchTile(
            title: '极限播放',
            subtitle: _extremePlaybackEnabled
                ? '边下边播已开启，退出播放器后会清理本次播放缓存。切换时会重新加载当前播放源。'
                : '边下边播开启后，退出播放器会自动删除已下载缓存，但会增加内存和存储空间消耗。',
            value: _extremePlaybackEnabled,
            onChanged: (value) async {
              await _setExtremePlaybackEnabled(
                value,
                reloadCurrentPlayback: true,
              );
              if (!mounted) return;
              _hideControlsImmediately();
              drawer.refresh();
            },
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: '视频信息',
            subtitle: '查看当前播放链路、渲染输出和片源信息',
            onTap: () => drawer.push(_playerSettingsVideoInfoPageId),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackSettingsMonitorPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(title: '播放监测', onBack: drawer.popPage),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsStatusCard(
            title: '播放监控',
            value: _playbackMonitorStatusLabel(),
            description: '显示在左上角，可拖动并记住位置。GPU 占用取决于设备是否开放系统节点。',
          ),
          const SizedBox(height: 12),
          PlaybackSettingsSwitchTile(
            title: '性能监控',
            subtitle: '显示 CPU / GPU 占用百分比',
            value: _performanceOverlayEnabled,
            onChanged: (value) {
              unawaited(_setPerformanceOverlayEnabled(value));
              drawer.refresh();
            },
          ),
          const SizedBox(height: 12),
          PlaybackSettingsSwitchTile(
            title: '实时帧率',
            subtitle: '显示当前视频输出 FPS，默认关闭',
            value: _fpsOverlayEnabled,
            onChanged: (value) {
              unawaited(_setFpsOverlayEnabled(value));
              drawer.refresh();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackSettingsDecoderPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(title: '解码方式', onBack: drawer.popPage),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsChoiceTile(
            title: '硬解码',
            subtitle: '性能高，优先选择',
            selected: _decoderMode == _MpvPlayerPageState._decoderModeHardware,
            onTap: () => unawaited(
              _switchDecoderModeFromDrawer(
                _MpvPlayerPageState._decoderModeHardware,
                drawer,
              ),
            ),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsChoiceTile(
            title: '软解码',
            subtitle: '兼容性更高，适合硬解异常时切换',
            selected: _decoderMode == _MpvPlayerPageState._decoderModeSoftware,
            onTap: () => unawaited(
              _switchDecoderModeFromDrawer(
                _MpvPlayerPageState._decoderModeSoftware,
                drawer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _switchDecoderModeFromDrawer(
    String mode,
    PlayerNestedSheetController<void> drawer,
  ) async {
    if (mode == _decoderMode) {
      drawer.close();
      return;
    }
    final currentPosition = _displayPosition(_controller.value.value);
    _updatePlayerState(() {
      _uiController.qualitySwitchLoading = true;
      _uiController.subtitleSwitchMessage = _settingsController
          .decoderSwitchMessage(_decoderModeLabel(mode));
    });
    _uiController.pendingLoadingTransition = true;
    _markAwaitingVisualPlaybackStart(
      currentPosition,
      targetPaused: _controller.value.value.paused,
    );
    drawer.close();
    var switchStarted = false;
    try {
      await _setDecoderModePreference(mode);
      switchStarted = true;
      if (!mounted) return;
      _showControls();
    } finally {
      if (!switchStarted) {
        _cancelPendingLoadingTransition();
      }
    }
  }

  String _playbackMonitorStatusLabel() {
    return _settingsController.playbackMonitorStatusLabel();
  }
}
