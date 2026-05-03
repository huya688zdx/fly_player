part of '../../mpv_player_page.dart';

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
const String _playerSettingsMpvScenePresetPageId =
    'player_settings_mpv_scene_preset';
const String _playerSettingsMpvPresetPageId = 'player_settings_mpv_preset';
const String _playerSettingsMpvAudioPresetPageId =
    'player_settings_mpv_audio_preset';
const String _playerSettingsMpvCustomPageId = 'player_settings_mpv_custom';
const String _playerSettingsMpvPictureCustomPageId =
    'player_settings_mpv_picture_custom';
const String _playerSettingsMpvAudioCustomPageId =
    'player_settings_mpv_audio_custom';
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
    if (_playerUiLocked) return;
    _overlayState.cancelAutoHide();
    final restoreControls = _controlsVisible;
    if (restoreControls) {
      _hideControlsImmediately();
    }

    if (!mounted) return;
    try {
      _playbackSettingsDrawerVisible = true;
      unawaited(_syncDanmakuDynamicOcclusionConfig());
      unawaited(_warmupPlaybackSettingsDrawerState());
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
              title: AppLocalizations.of(context).playerSelectIntroChapterTitle,
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
              title: AppLocalizations.of(context).playerSelectOutroChapterTitle,
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
            id: _playerSettingsMpvScenePresetPageId,
            builder: _buildPlaybackSettingsMpvScenePresetPage,
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
            id: _playerSettingsMpvAudioPresetPageId,
            builder: _buildPlaybackSettingsMpvAudioPresetPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsMpvCustomPageId,
            builder: _buildPlaybackSettingsMpvCustomPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsMpvPictureCustomPageId,
            builder: _buildPlaybackSettingsMpvPictureCustomPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsMpvAudioCustomPageId,
            builder: _buildPlaybackSettingsMpvAudioCustomPage,
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
        _activePlaybackSettingsDrawerController = null;
        _playbackSettingsDrawerVisible = false;
        unawaited(_syncDanmakuDynamicOcclusionConfig());
        unawaited(_startOrUpdateSystemPlaybackSession(force: true));
        if (!restoreControls) {
          _scheduleControlsAutoHide();
        }
      }
    }
  }

  Future<void> _warmupPlaybackSettingsDrawerState() async {
    await _syncMpvPresetStateFromStore();
  }

  Widget _buildPlaybackSettingsMainPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    _activePlaybackSettingsDrawerController = drawer;
    final l10n = AppLocalizations.of(context);
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: l10n.playerSettingsTitle,
        actions: <Widget>[
          PlaybackSettingsHeaderAction(
            icon: Icons.settings_rounded,
            label: l10n.playerAdvancedSettingsTitle,
            onTap: () => drawer.push(_playerSettingsAdvancedPageId),
          ),
        ],
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsSwitchTile(
            title: l10n.playerAutoRotateTitle,
            subtitle: _autoRotateEnabled
                ? l10n.playerAutoRotateSystemSubtitle
                : l10n.playerAutoRotateLockedSubtitle,
            value: _autoRotateEnabled,
            onChanged: (value) {
              unawaited(_setAutoRotateEnabled(value));
              drawer.refresh();
            },
          ),
          const SizedBox(height: 12),
          PlaybackSettingsSwitchTile(
            title: l10n.playerAutoPlayTitle,
            subtitle: _autoPlayEnabled
                ? l10n.playerAutoPlayEnabledSubtitle
                : l10n.playerAutoPlayDisabledSubtitle,
            value: _autoPlayEnabled,
            onChanged: (value) {
              unawaited(_setAutoPlayEnabled(value));
              drawer.refresh();
            },
          ),
          const SizedBox(height: 12),
          PlaybackSettingsSwitchTile(
            title: l10n.playerNextEpisodePreloadTitle,
            subtitle: _autoPlayEnabled
                ? (_nextEpisodePreloadEnabled
                      ? l10n.playerNextEpisodePreloadEnabledSubtitle
                      : l10n.playerNextEpisodePreloadDisabledSubtitle)
                : l10n.playerNextEpisodePreloadRequiresAutoPlay,
            value: _nextEpisodePreloadEnabled,
            enabled: _autoPlayEnabled,
            onChanged: (value) {
              unawaited(_setNextEpisodePreloadEnabled(value));
              drawer.refresh();
            },
          ),
          const SizedBox(height: 12),
          PlaybackSettingsAspectRatioTile(
            value: _displayAspectRatioMode,
            subtitle: l10n.playerCurrentValue(_displayAspectRatioLabel()),
            onChanged: (value) {
              unawaited(_setDisplayAspectRatioMode(value));
              drawer.refresh();
            },
          ),
          const SizedBox(height: 12),
          if (_supportsIntroOutroUi)
            PlaybackSettingsMenuTile(
              title: l10n.playerIntroOutroSettingsTitle,
              subtitle: _introOutroDisplaySummaryTextV3(),
              trailingLabel: _introOutroDisplayStatusLabelV3(),
              onTap: () => drawer.push(_playerSettingsIntroOutroPageId),
            ),
          if (_supportsIntroOutroUi) const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: l10n.playerBookmarkTitle,
            subtitle: l10n.playerBookmarkSettingsSubtitle,
            trailingLabel: _bookmarkSummaryLabel(),
            onTap: () => drawer.push(_playerSettingsBookmarkPageId),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: l10n.settingsMpvTitle,
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
    final l10n = AppLocalizations.of(context);
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: l10n.playerAdvancedSettingsTitle,
        onBack: drawer.popPage,
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsMenuTile(
            title: l10n.playerDecoderTitle,
            subtitle: l10n.playerDecoderSubtitle,
            trailingLabel: _decoderModeLabel(),
            onTap: () => drawer.push(_playerSettingsDecoderPageId),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: l10n.playerCacheSettingsTitle,
            subtitle: l10n.playerCacheSettingsSubtitle,
            trailingLabel: _mpvSettingLabel(
              _MpvPlayerPageState._mpvSettingCacheSizeMb,
            ),
            onTap: () => drawer.push(_playerSettingsMpvCacheSizePageId),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: l10n.playerMonitorTitle,
            subtitle: l10n.playerMonitorSubtitle,
            trailingLabel: _playbackMonitorStatusLabel(),
            onTap: () => drawer.push(_playerSettingsMonitorPageId),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsSwitchTile(
            title: l10n.playerExtremePlaybackTitle,
            subtitle: _extremePlaybackEnabled
                ? l10n.playerExtremePlaybackEnabledSubtitle
                : l10n.playerExtremePlaybackDisabledSubtitle,
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
            title: l10n.playerVideoInfoTitle,
            subtitle: l10n.playerVideoInfoSubtitle,
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
    final l10n = AppLocalizations.of(context);
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: l10n.playerMonitorTitle,
        onBack: drawer.popPage,
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsStatusCard(
            title: l10n.playerMonitorStatusTitle,
            value: _playbackMonitorStatusLabel(),
            description: l10n.playerMonitorStatusDescription,
          ),
          const SizedBox(height: 12),
          PlaybackSettingsSwitchTile(
            title: l10n.playerPerformanceMonitorTitle,
            subtitle: l10n.playerPerformanceMonitorSubtitle,
            value: _performanceOverlayEnabled,
            onChanged: (value) {
              unawaited(_setPerformanceOverlayEnabled(value));
              drawer.refresh();
            },
          ),
          const SizedBox(height: 12),
          PlaybackSettingsSwitchTile(
            title: l10n.playerFpsMonitorTitle,
            subtitle: l10n.playerFpsMonitorSubtitle,
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
    final l10n = AppLocalizations.of(context);
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: l10n.playerDecoderTitle,
        onBack: drawer.popPage,
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsChoiceTile(
            title: l10n.playerHardwareDecoderTitle,
            subtitle: l10n.playerHardwareDecoderSubtitle,
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
            title: l10n.playerSoftwareDecoderTitle,
            subtitle: l10n.playerSoftwareDecoderSubtitle,
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
      _uiController.subtitleSwitchMessage = AppLocalizations.of(
        context,
      ).playerDecoderSwitching(_decoderModeLabel(mode));
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
    final l10n = AppLocalizations.of(context);
    return _performanceOverlayEnabled
        ? l10n.playerMonitorPartiallyEnabled
        : l10n.playerMonitorOff;
  }
}
