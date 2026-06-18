part of '../../mpv_player_page.dart';

const int _mpvCacheSizeSliderMinMb = 64;
const int _mpvCacheSizeSliderMaxMb = 1984;
const int _mpvCacheSizeSliderStepMb = 64;
const int _mpvCacheSizeExtremeMinimumMb = 512;
const int _mpvCachePercentSliderMin = 0;
const int _mpvCachePercentSliderMax = 100;

extension _MpvPlayerSettingsMpvMixin on _MpvPlayerPageState {
  // ignore: unused_element
  Widget _buildPlaybackSettingsMpvHubPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    final l10n = AppLocalizations.of(context);
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: l10n.settingsMpvTitle,
        onBack: drawer.popPage,
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsStatusCard(
            title: l10n.mpvCurrentSchemeTitle,
            value: _mpvSettingsStatusLabel(),
            description: _mpvSettingsSummaryText(),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: l10n.mpvSmartRecommendationTitle,
            subtitle: l10n.mpvSmartRecommendationSubtitle,
            trailingLabel: _mpvRecommendedSceneLabel(),
            onTap: () => drawer.push(_playerSettingsMpvScenePresetPageId),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: l10n.mpvPictureQuickPresetTitle,
            subtitle: l10n.mpvPictureQuickPresetSubtitle,
            trailingLabel: _mpvVideoQuickPresetSummaryLabel(),
            onTap: () => drawer.push(_playerSettingsMpvPresetPageId),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: l10n.mpvAudioQuickPresetTitle,
            subtitle: l10n.mpvAudioQuickPresetSubtitle,
            trailingLabel: _mpvAudioQuickPresetSummaryLabel(),
            onTap: () => drawer.push(_playerSettingsMpvAudioPresetPageId),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: l10n.mpvCustomManagementTitle,
            subtitle: l10n.mpvCustomManagementSubtitle,
            trailingLabel:
                _mpvChangedSettingCount() > 0 ||
                    _videoAdjustmentChangedCount() > 0
                ? l10n.mpvCurrentCustom
                : l10n.mpvDefault,
            onTap: () => drawer.push(_playerSettingsMpvCustomPageId),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackSettingsMpvScenePresetPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    final recommendation = _recommendedMpvScenePreset();
    final activeScenePreset = _activeMpvScenePreset();
    final l10n = AppLocalizations.of(context);
    final scenePresets = MpvSettingsL10n.builtInScenePresets(l10n);
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: l10n.mpvSmartRecommendationTitle,
        onBack: drawer.popPage,
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsStatusCard(
            title: recommendation == null
                ? l10n.mpvNoRecommendationTitle
                : MpvSettingsL10n.sceneRecommendationTitle(
                    l10n,
                    recommendation.preset.id,
                  ),
            value: recommendation == null
                ? _mpvRecommendedSceneLabel()
                : MpvSettingsL10n.scenePresetLabel(
                    l10n,
                    recommendation.preset.id,
                    fallback: recommendation.preset.label,
                  ),
            description: recommendation == null
                ? l10n.mpvNoRecommendationDescription
                : MpvSettingsL10n.sceneRecommendationReason(
                    l10n,
                    recommendation.preset.id,
                  ),
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < scenePresets.length; index++) ...[
            PlaybackSettingsChoiceTile(
              title: scenePresets[index].label,
              subtitle: scenePresets[index].description,
              selected: activeScenePreset?.id == scenePresets[index].id,
              onTap: () async {
                final bundle = await _mpvSettingsStore.applyScenePreset(
                  scenePresets[index],
                  currentSettings: _mpvSettings,
                  currentVideoAdjustments: _videoAdjustments,
                );
                await _applyStoredMpvBundle(bundle);
                if (mounted) {
                  drawer.refresh();
                }
              },
            ),
            if (index != scenePresets.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildPlaybackSettingsMpvPresetPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    final activeBuiltInPreset = _activeMpvVideoPreset();
    final activeSavedPreset = _activeSavedMpvPicturePreset();
    final l10n = AppLocalizations.of(context);
    final builtInPresets = MpvSettingsL10n.builtInPicturePresets(l10n);
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: l10n.mpvPictureQuickPresetTitle,
        onBack: drawer.popPage,
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsStatusCard(
            title: l10n.mpvPictureQuickPresetTitle,
            value: _mpvVideoQuickPresetSummaryLabel(),
            description: l10n.mpvPictureQuickPresetDescription,
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < builtInPresets.length; index++) ...[
            PlaybackSettingsChoiceTile(
              title: builtInPresets[index].label,
              subtitle: builtInPresets[index].description,
              selected:
                  activeSavedPreset == null &&
                  activeBuiltInPreset?.id == builtInPresets[index].id,
              onTap: () async {
                final bundle = await _mpvSettingsStore.applyBuiltInPreset(
                  SavedMpvPresetKind.picture,
                  builtInPresets[index],
                  currentSettings: _mpvSettings,
                  currentVideoAdjustments: _videoAdjustments,
                );
                await _applyStoredMpvBundle(bundle);
                if (mounted) {
                  drawer.refresh();
                }
              },
            ),
            if (index != builtInPresets.length - 1) const SizedBox(height: 12),
          ],
          if (_savedMpvPicturePresets.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (
              var index = 0;
              index < _savedMpvPicturePresets.length;
              index++
            ) ...[
              PlaybackSettingsChoiceTile(
                title: _savedMpvPicturePresets[index].name,
                subtitle: _savedMpvPicturePresets[index].description.isEmpty
                    ? l10n.mpvSavedPicturePreset
                    : _savedMpvPicturePresets[index].description,
                selected:
                    activeSavedPreset?.id == _savedMpvPicturePresets[index].id,
                onTap: () async {
                  final bundle = await _mpvSettingsStore.applySavedPreset(
                    _savedMpvPicturePresets[index],
                    currentSettings: _mpvSettings,
                    currentVideoAdjustments: _videoAdjustments,
                  );
                  await _applyStoredMpvBundle(bundle);
                  if (mounted) {
                    drawer.refresh();
                  }
                },
              ),
              if (index != _savedMpvPicturePresets.length - 1)
                const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildPlaybackSettingsMpvAudioPresetPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    final activeBuiltInPreset = _activeMpvAudioPreset();
    final activeSavedPreset = _activeSavedMpvAudioPreset();
    final l10n = AppLocalizations.of(context);
    final builtInPresets = MpvSettingsL10n.builtInAudioPresets(l10n);
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: l10n.mpvAudioQuickPresetTitle,
        onBack: drawer.popPage,
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsStatusCard(
            title: l10n.mpvAudioQuickPresetTitle,
            value: _mpvAudioQuickPresetSummaryLabel(),
            description: l10n.mpvAudioQuickPresetDescription,
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < builtInPresets.length; index++) ...[
            PlaybackSettingsChoiceTile(
              title: builtInPresets[index].label,
              subtitle: builtInPresets[index].description,
              selected:
                  activeSavedPreset == null &&
                  activeBuiltInPreset?.id == builtInPresets[index].id,
              onTap: () async {
                final bundle = await _mpvSettingsStore.applyBuiltInPreset(
                  SavedMpvPresetKind.audio,
                  builtInPresets[index],
                  currentSettings: _mpvSettings,
                  currentVideoAdjustments: _videoAdjustments,
                );
                await _applyStoredMpvBundle(bundle);
                if (mounted) {
                  drawer.refresh();
                }
              },
            ),
            if (index != builtInPresets.length - 1) const SizedBox(height: 12),
          ],
          if (_savedMpvAudioPresets.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (
              var index = 0;
              index < _savedMpvAudioPresets.length;
              index++
            ) ...[
              PlaybackSettingsChoiceTile(
                title: _savedMpvAudioPresets[index].name,
                subtitle: _savedMpvAudioPresets[index].description.isEmpty
                    ? l10n.mpvSavedAudioPreset
                    : _savedMpvAudioPresets[index].description,
                selected:
                    activeSavedPreset?.id == _savedMpvAudioPresets[index].id,
                onTap: () async {
                  final bundle = await _mpvSettingsStore.applySavedPreset(
                    _savedMpvAudioPresets[index],
                    currentSettings: _mpvSettings,
                    currentVideoAdjustments: _videoAdjustments,
                  );
                  await _applyStoredMpvBundle(bundle);
                  if (mounted) {
                    drawer.refresh();
                  }
                },
              ),
              if (index != _savedMpvAudioPresets.length - 1)
                const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildPlaybackSettingsMpvCustomPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    final l10n = AppLocalizations.of(context);
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: l10n.mpvCustomManagementTitle,
        onBack: drawer.popPage,
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsStatusCard(
            title: l10n.mpvCustomManagementTitle,
            value:
                _mpvChangedSettingCount() > 0 ||
                    _videoAdjustmentChangedCount() > 0
                ? l10n.mpvCurrentCustom
                : l10n.mpvAllDefault,
            description: l10n.mpvCustomManagementDescription,
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: l10n.mpvPictureCustomTitle,
            subtitle: l10n.mpvPictureCustomSubtitle,
            trailingLabel: _mpvPictureCustomSummaryLabel(),
            onTap: () => drawer.push(_playerSettingsMpvPictureCustomPageId),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: l10n.mpvAudioCustomTitle,
            subtitle: l10n.mpvAudioCustomSubtitle,
            trailingLabel: _mpvAudioCustomSummaryLabel(),
            onTap: () => drawer.push(_playerSettingsMpvAudioCustomPageId),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackSettingsMpvPictureCustomPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    final categories = <_MpvSettingCategory>[
      _mpvVideoFiltersCategory,
      _mpvPictureRenderingCategory,
      _mpvPlaybackSyncCategory,
      _mpvCompatibilityCategory,
    ];
    final l10n = AppLocalizations.of(context);
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: l10n.mpvPictureCustomTitle,
        onBack: drawer.popPage,
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsStatusCard(
            title: l10n.mpvPictureCustomTitle,
            value: _mpvPictureCustomSummaryLabel(),
            description: l10n.mpvPictureCustomDescription,
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: l10n.mpvSaveCurrentPictureTitle,
            subtitle: l10n.mpvSaveCurrentPictureSubtitle,
            trailingLabel: l10n.commonSave,
            onTap: () => unawaited(
              _saveCurrentMpvPresetFromDrawer(
                drawer,
                kind: SavedMpvPresetKind.picture,
              ),
            ),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: l10n.mpvInstantAdjustTitle,
            subtitle: l10n.mpvInstantAdjustSubtitle,
            trailingLabel: _videoAdjustmentSummaryLabel(),
            onTap: () => drawer.push(_playerSettingsMpvQuickAdjustPageId),
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < categories.length; index++) ...[
            PlaybackSettingsMenuTile(
              title: categories[index].title,
              subtitle: categories[index].subtitle,
              trailingLabel: _mpvCategorySummaryLabel(categories[index]),
              onTap: () => drawer.push(categories[index].pageId),
            ),
            if (index != categories.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildPlaybackSettingsMpvAudioCustomPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    final l10n = AppLocalizations.of(context);
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: l10n.mpvAudioCustomTitle,
        onBack: drawer.popPage,
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsStatusCard(
            title: l10n.mpvAudioCustomTitle,
            value: _mpvAudioCustomSummaryLabel(),
            description: l10n.mpvAudioCustomDescription,
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: l10n.mpvSaveCurrentAudioTitle,
            subtitle: l10n.mpvSaveCurrentAudioSubtitle,
            trailingLabel: l10n.commonSave,
            onTap: () => unawaited(
              _saveCurrentMpvPresetFromDrawer(
                drawer,
                kind: SavedMpvPresetKind.audio,
              ),
            ),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: _mpvAudioProcessingCategory.title,
            subtitle: _mpvAudioProcessingCategory.subtitle,
            trailingLabel: _mpvCategorySummaryLabel(
              _mpvAudioProcessingCategory,
            ),
            onTap: () => drawer.push(_mpvAudioProcessingCategory.pageId),
          ),
        ],
      ),
    );
  }

  Widget _buildMpvCategoryPage(
    PlayerNestedSheetController<void> drawer, {
    required _MpvSettingCategory category,
  }) {
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: category.title,
        onBack: drawer.popPage,
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsStatusCard(
            title: category.title,
            value: _mpvCategorySummaryLabel(category),
            description: category.description,
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < category.entries.length; index++) ...[
            PlaybackSettingsMenuTile(
              title: category.entries[index].title,
              subtitle: category.entries[index].subtitle,
              trailingLabel: category.entries[index].settingKey == null
                  ? category.entries[index].trailingLabel
                  : _mpvSettingLabel(category.entries[index].settingKey!),
              onTap: () => drawer.push(category.entries[index].pageId),
            ),
            if (index != category.entries.length - 1)
              const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildMpvChoicePage(
    PlayerNestedSheetController<void> drawer,
    _MpvSettingDefinition definition,
  ) {
    if (definition.key == _MpvPlayerPageState._mpvSettingAudioEq) {
      return _buildMpvAudioEqChoicePage(drawer, definition);
    }
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: definition.title,
        onBack: drawer.popPage,
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsStatusCard(
            title: definition.helperLabel,
            value: _mpvSettingLabel(definition.key),
            description: definition.description,
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < definition.options.length; index++) ...[
            PlaybackSettingsChoiceTile(
              title: definition.options[index].label,
              subtitle: definition.options[index].description,
              onInfoTap:
                  definition.key == _MpvPlayerPageState._mpvSettingCacheProfile
                  ? () => _showMpvCacheProfileHelp(
                      context,
                      definition.options[index].value,
                    )
                  : null,
              selected:
                  _mpvSettingValue(definition.key) ==
                  definition.options[index].value,
              onTap: () async {
                final nextValue = definition.options[index].value;
                if (_mpvSettingValue(definition.key) == nextValue) return;
                final confirmed = await _confirmMpvPerformanceSelection(
                  context,
                  definition.key,
                  nextValue,
                );
                if (!confirmed) return;
                await _setMpvAdvancedSetting(definition.key, nextValue);
                if (mounted) {
                  drawer.refresh();
                }
              },
            ),
            if (index != definition.options.length - 1)
              const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  void _showMpvCacheProfileHelp(BuildContext context, String value) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final title = switch (value) {
      'default' => l10n.mpvOptionDefault,
      'low_latency' => l10n.mpvOptionLowLatency,
      'stable' => l10n.mpvOptionStable,
      'network' => l10n.mpvOptionNetwork,
      _ => l10n.mpvSettingCacheProfileTitle,
    };
    final content = switch (value) {
      'default' => l10n.mpvCacheHelpDefaultContent,
      'low_latency' => l10n.mpvCacheHelpLowLatencyContent,
      'stable' => l10n.mpvCacheHelpStableContent,
      'network' => l10n.mpvCacheHelpNetworkContent,
      _ => l10n.mpvCacheHelpGenericContent,
    };
    final extra = switch (value) {
      'default' => l10n.mpvCacheHelpDefaultExtra,
      'low_latency' => l10n.mpvCacheHelpLowLatencyExtra,
      'stable' => l10n.mpvCacheHelpStableExtra,
      'network' => l10n.mpvCacheHelpNetworkExtra,
      _ => '',
    };
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: colors.borderSubtle),
          ),
          title: Text(
            title,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                content,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              if (extra.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  extra,
                  style: TextStyle(
                    color: colors.selectionStrong,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.commonOk),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _confirmMpvPerformanceSelection(
    BuildContext context,
    String key,
    String value,
  ) async {
    final l10n = AppLocalizations.of(context);
    final warning = MpvSettingsL10n.performanceWarningForSelection(
      l10n,
      key,
      value,
    );
    if (warning == null) return true;
    final colors = context.appColors;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: colors.borderSubtle),
          ),
          title: Text(
            warning.title,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            warning.message,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.mpvContinueEnable),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Widget _buildMpvAudioEqChoicePage(
    PlayerNestedSheetController<void> drawer,
    _MpvSettingDefinition definition,
  ) {
    final l10n = AppLocalizations.of(context);
    final presetOptions = definition.options
        .where(
          (option) => option.value != MpvSettingsCatalog.audioEqCustomValue,
        )
        .toList(growable: false);
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: definition.title,
        onBack: drawer.popPage,
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsStatusCard(
            title: definition.helperLabel,
            value: _mpvSettingLabel(definition.key),
            description: definition.description,
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: l10n.mpvAudioEqAdvancedTitle,
            subtitle: l10n.mpvAudioEqAdvancedSubtitle,
            trailingLabel:
                _mpvSettingValue(definition.key) ==
                    MpvSettingsCatalog.audioEqCustomValue
                ? l10n.mpvCurrentlyUsed
                : l10n.commonEnter,
            onTap: () => drawer.push(_playerSettingsMpvAudioEqAdvancedPageId),
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < presetOptions.length; index++) ...[
            PlaybackSettingsChoiceTile(
              title: presetOptions[index].label,
              subtitle: presetOptions[index].description,
              selected:
                  _mpvSettingValue(definition.key) ==
                  presetOptions[index].value,
              onTap: () async {
                await _setMpvAdvancedSetting(
                  definition.key,
                  presetOptions[index].value,
                );
                if (mounted) {
                  drawer.refresh();
                }
              },
            ),
            if (index != presetOptions.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildMpvAudioEqAdvancedPage(
    PlayerNestedSheetController<void> drawer,
  ) {
    final l10n = AppLocalizations.of(context);
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: l10n.mpvAudioEqAdvancedHeader,
        onBack: drawer.popPage,
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          MpvAudioEqAdvancedPanel(
            settings: _mpvSettings,
            onApplyPatch: (patch) async {
              await _setMpvAdvancedSettingsPatch(patch);
            },
            onMessage: (message) => _showTopTip(
              message,
              context.appColors.success,
              revealControls: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMpvCacheSizePage(PlayerNestedSheetController<void> drawer) {
    var persistedValue = _mpvSettingValue(
      _MpvPlayerPageState._mpvSettingCacheSizeMb,
    );
    var auto = persistedValue == 'auto';
    var sliderValue = _mbToCachePercent(
      _currentMpvCacheSizeMb() ?? _mpvCacheSizeExtremeMinimumMb,
    ).toDouble();

    return StatefulBuilder(
      builder: (context, setLocalState) {
        final l10n = AppLocalizations.of(context);
        final cacheDefinition = _mpvDefinitionForKey(
          _MpvPlayerPageState._mpvSettingCacheSizeMb,
        )!;
        final selectedPercent = sliderValue.round().clamp(
          _mpvCachePercentSliderMin,
          _mpvCachePercentSliderMax,
        );
        final selectedMb = _cachePercentToMb(selectedPercent);
        final sliderDivisions =
            (_mpvCachePercentSliderMax - _mpvCachePercentSliderMin).clamp(
              1,
              1000,
            );
        return PlayerNestedSheetScaffold(
          header: PlayerNestedSheetHeader(
            title: cacheDefinition.title,
            onBack: drawer.popPage,
          ),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              PlaybackSettingsStatusCard(
                title: l10n.mpvCacheSettingStatusTitle,
                value: auto
                    ? l10n.mpvOptionAuto
                    : _formatMpvCachePercentLabel(selectedPercent),
                description: auto
                    ? l10n.mpvCacheSettingAutoDescription
                    : l10n.mpvCacheSettingManualDescription,
              ),
              const SizedBox(height: 12),
              PlaybackSettingsSwitchTile(
                title: l10n.mpvCacheAutoSwitchTitle,
                subtitle: auto
                    ? l10n.mpvCacheAutoSwitchAutoSubtitle
                    : l10n.mpvCacheAutoSwitchManualSubtitle,
                value: auto,
                onChanged: (value) async {
                  final nextValue = value ? 'auto' : selectedMb.toString();
                  if (persistedValue == nextValue) {
                    setLocalState(() {
                      auto = value;
                    });
                    return;
                  }
                  if (!value) {
                    final warning =
                        MpvSettingsCatalog.performanceWarningForSelection(
                          _MpvPlayerPageState._mpvSettingCacheSizeMb,
                          selectedMb.toString(),
                        );
                    if (warning != null) {
                      final confirmed = await _confirmMpvPerformanceSelection(
                        context,
                        _MpvPlayerPageState._mpvSettingCacheSizeMb,
                        selectedMb.toString(),
                      );
                      if (!confirmed) {
                        setLocalState(() {
                          auto = true;
                          if (persistedValue != 'auto') {
                            sliderValue = _mbToCachePercent(
                              int.tryParse(persistedValue) ??
                                  _mpvCacheSizeExtremeMinimumMb,
                            ).toDouble();
                          }
                        });
                        return;
                      }
                    }
                  }
                  setLocalState(() {
                    auto = value;
                  });
                  await _setMpvAdvancedSetting(
                    _MpvPlayerPageState._mpvSettingCacheSizeMb,
                    nextValue,
                  );
                  persistedValue = nextValue;
                  if (mounted) {
                    drawer.refresh();
                  }
                },
              ),
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: _settingsCardDecoration(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _SettingsTextBlock(
                              title: l10n.mpvCacheSliderTitle,
                              subtitle: l10n.mpvCacheSliderSubtitle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            l10n.mpvCachePercentSettingLabel(
                              _formatMpvCachePercentLabel(selectedPercent),
                            ),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Opacity(
                        opacity: auto ? 0.45 : 1,
                        child: IgnorePointer(
                          ignoring: auto,
                          child: Column(
                            children: [
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: context.appColors.accent,
                                  inactiveTrackColor:
                                      context.appColors.borderStrong,
                                  thumbColor: context.appColors.textPrimary,
                                  overlayColor: context.appColors.accentSoft,
                                  trackHeight: 4,
                                ),
                                child: Slider(
                                  min: _mpvCachePercentSliderMin.toDouble(),
                                  max: _mpvCachePercentSliderMax.toDouble(),
                                  divisions: sliderDivisions,
                                  value: sliderValue.clamp(
                                    _mpvCachePercentSliderMin.toDouble(),
                                    _mpvCachePercentSliderMax.toDouble(),
                                  ),
                                  onChanged: (value) {
                                    setLocalState(() {
                                      sliderValue = value;
                                    });
                                  },
                                  onChangeEnd: (value) async {
                                    final normalized = value.round().clamp(
                                      _mpvCachePercentSliderMin,
                                      _mpvCachePercentSliderMax,
                                    );
                                    final normalizedMb = _cachePercentToMb(
                                      normalized,
                                    );
                                    if (persistedValue ==
                                        normalizedMb.toString()) {
                                      setLocalState(() {
                                        sliderValue = normalized.toDouble();
                                      });
                                      return;
                                    }
                                    final confirmed =
                                        await _confirmMpvPerformanceSelection(
                                          context,
                                          _MpvPlayerPageState
                                              ._mpvSettingCacheSizeMb,
                                          normalizedMb.toString(),
                                        );
                                    if (!confirmed) {
                                      setLocalState(() {
                                        if (persistedValue != 'auto') {
                                          sliderValue = _mbToCachePercent(
                                            int.tryParse(persistedValue) ??
                                                _mpvCacheSizeExtremeMinimumMb,
                                          ).toDouble();
                                        }
                                      });
                                      return;
                                    }
                                    setLocalState(() {
                                      sliderValue = normalized.toDouble();
                                    });
                                    await _setMpvAdvancedSetting(
                                      _MpvPlayerPageState
                                          ._mpvSettingCacheSizeMb,
                                      normalizedMb.toString(),
                                    );
                                    persistedValue = normalizedMb.toString();
                                    if (mounted) {
                                      drawer.refresh();
                                    }
                                  },
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    'MIN ${_formatMpvCachePercentLabel(_mpvCachePercentSliderMin)}',
                                    style: TextStyle(
                                      color: context.appColors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    'MAX ${_formatMpvCachePercentLabel(_mpvCachePercentSliderMax)}',
                                    style: TextStyle(
                                      color: context.appColors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _mpvSettingValue(String key) {
    return _mpvSettings[key] ??
        _MpvPlayerPageState._defaultMpvSettings[key] ??
        '';
  }

  String _mpvSettingLabel(String key) {
    if (key == _MpvPlayerPageState._mpvSettingCacheSizeMb) {
      return _formatMpvCacheSizeLabel(_mpvSettingValue(key));
    }
    final definition = _mpvDefinitionByKey(key);
    if (definition == null) return _mpvSettingValue(key);
    final value = _mpvSettingValue(key);
    for (final option in definition.options) {
      if (option.value == value) {
        return option.label;
      }
    }
    return value;
  }

  bool _shouldCompareMpvKey(String key) {
    if (!MpvSettingsCatalog.isAudioEqBandKey(key)) return true;
    return _mpvSettingValue(_MpvPlayerPageState._mpvSettingAudioEq) ==
        MpvSettingsCatalog.audioEqCustomValue;
  }

  int? _currentMpvCacheSizeMb() {
    final parsed = int.tryParse(
      _mpvSettingValue(_MpvPlayerPageState._mpvSettingCacheSizeMb),
    );
    if (parsed == null) return null;
    return _normalizeMpvCacheSizeMb(parsed);
  }

  int _mbToCachePercent(int value) {
    final normalized = _normalizeMpvCacheSizeMb(value);
    const range = _mpvCacheSizeSliderMaxMb - _mpvCacheSizeSliderMinMb;
    if (range <= 0) return _mpvCachePercentSliderMax;
    final percent = ((normalized - _mpvCacheSizeSliderMinMb) * 100 / range)
        .round();
    return percent.clamp(_mpvCachePercentSliderMin, _mpvCachePercentSliderMax);
  }

  int _cachePercentToMb(int percent) {
    final normalizedPercent = percent.clamp(
      _mpvCachePercentSliderMin,
      _mpvCachePercentSliderMax,
    );
    const range = _mpvCacheSizeSliderMaxMb - _mpvCacheSizeSliderMinMb;
    final mapped =
        _mpvCacheSizeSliderMinMb + (range * normalizedPercent / 100).round();
    return _normalizeMpvCacheSizeMb(mapped);
  }

  int _normalizeMpvCacheSizeMb(int value) {
    final clamped = value.clamp(
      _mpvCacheSizeSliderMinMb,
      _mpvCacheSizeSliderMaxMb,
    );
    final steps =
        ((clamped - _mpvCacheSizeSliderMinMb) / _mpvCacheSizeSliderStepMb)
            .round();
    return _mpvCacheSizeSliderMinMb + (steps * _mpvCacheSizeSliderStepMb);
  }

  String _formatMpvCacheSizeLabel(String value) {
    if (value == 'auto') return AppLocalizations.of(context).mpvOptionAuto;
    final parsed = int.tryParse(value);
    if (parsed == null) return value;
    return _formatMpvCachePercentLabel(_mbToCachePercent(parsed));
  }

  String _formatMpvCachePercentLabel(int percent) {
    final normalized = percent.clamp(
      _mpvCachePercentSliderMin,
      _mpvCachePercentSliderMax,
    );
    return '$normalized%';
  }

  String _mpvSettingsStatusLabel() {
    final l10n = AppLocalizations.of(context);
    final scenePreset = _activeMpvScenePreset();
    if (scenePreset != null) {
      return MpvSettingsL10n.scenePresetLabel(
        l10n,
        scenePreset.id,
        fallback: scenePreset.label,
      );
    }
    final videoPreset = _activeMpvVideoPreset();
    final audioPreset = _activeMpvAudioPreset();
    if (videoPreset != null && audioPreset != null) {
      final videoOff = videoPreset.id == 'off';
      final audioOff = audioPreset.id == 'off';
      final defaultLabel = MpvSettingsL10n.defaultLabel(l10n);
      final videoLabel = MpvSettingsL10n.picturePresetLabel(
        l10n,
        videoPreset.id,
        fallback: videoPreset.label,
      );
      final audioLabel = MpvSettingsL10n.audioPresetLabel(
        l10n,
        audioPreset.id,
        fallback: audioPreset.label,
      );
      if (videoOff && audioOff) return defaultLabel;
      if (videoOff) return audioLabel;
      if (audioOff) return videoLabel;
      return '$videoLabel / $audioLabel';
    }
    if (_mpvChangedSettingCount() == 0 && _videoAdjustmentChangedCount() == 0) {
      return MpvSettingsL10n.defaultLabel(l10n);
    }
    return MpvSettingsL10n.currentCustomLabel(l10n);
  }

  String _mpvSettingsSummaryText() {
    final l10n = AppLocalizations.of(context);
    final scenePreset = _activeMpvScenePreset();
    if (scenePreset != null) {
      return MpvSettingsL10n.scenePresetDescription(
        l10n,
        scenePreset.id,
        fallback: scenePreset.description,
      );
    }
    final videoPreset = _activeMpvVideoPreset();
    final audioPreset = _activeMpvAudioPreset();
    if (videoPreset != null || audioPreset != null) {
      final parts = <String>[];
      if (videoPreset != null && videoPreset.id != 'off') {
        parts.add(
          '${MpvSettingsL10n.savedPresetKindLabel(l10n, SavedMpvPresetKind.picture)}: ${MpvSettingsL10n.picturePresetDescription(l10n, videoPreset.id, fallback: videoPreset.description)}',
        );
      }
      if (audioPreset != null && audioPreset.id != 'off') {
        parts.add(
          '${MpvSettingsL10n.savedPresetKindLabel(l10n, SavedMpvPresetKind.audio)}: ${MpvSettingsL10n.audioPresetDescription(l10n, audioPreset.id, fallback: audioPreset.description)}',
        );
      }
      if (parts.isNotEmpty) return parts.join('  ');
    }
    if (_videoAdjustmentChangedCount() > 0 && _mpvChangedSettingCount() == 0) {
      return _videoAdjustmentSummaryText();
    }
    final changed = _mpvChangedSettingCount();
    if (changed == 0 && _videoAdjustmentChangedCount() == 0) {
      return l10n.mpvVideoAdjustAllDefaultSummary;
    }
    final labels = <String>[];
    for (final definition in _videoAdjustmentDefinitions) {
      final current =
          _videoAdjustments[definition.key] ??
          _MpvPlayerPageState._defaultVideoAdjustments[definition.key]!;
      if (_normalizeVideoAdjustmentValue(current) == 0) continue;
      labels.add('${definition.title} ${_videoAdjustmentValueLabel(current)}');
      if (labels.length == 3) break;
    }
    for (final definition in _mpvChoiceDefinitions) {
      if (!_shouldCompareMpvKey(definition.key)) continue;
      final current = _mpvSettingValue(definition.key);
      final fallback = _MpvPlayerPageState._defaultMpvSettings[definition.key];
      if (current == fallback) continue;
      labels.add(
        '${definition.shortTitle} ${_mpvSettingLabel(definition.key)}',
      );
      if (labels.length == 3) break;
    }
    final totalChanged = changed + _videoAdjustmentChangedCount();
    return labels.isEmpty
        ? MpvSettingsL10n.changedCount(l10n, totalChanged)
        : '${MpvSettingsL10n.changedCount(l10n, totalChanged)}: ${labels.join(' / ')}';
  }

  String _mpvCategorySummaryLabel(_MpvSettingCategory category) {
    final changedCount = _mpvChangedSettingCount(
      category.entries
          .map((entry) => entry.settingKey)
          .whereType<String>()
          .toList(growable: false),
    );
    if (changedCount == 0) return AppLocalizations.of(context).mpvDefault;
    if (changedCount == 1) {
      for (final entry in category.entries) {
        final key = entry.settingKey;
        if (key == null) continue;
        if (!_shouldCompareMpvKey(key)) continue;
        if (_mpvSettingValue(key) !=
            _MpvPlayerPageState._defaultMpvSettings[key]) {
          return _mpvSettingLabel(key);
        }
      }
    }
    return MpvSettingsL10n.changedCount(
      AppLocalizations.of(context),
      changedCount,
    );
  }

  int _mpvChangedSettingCount([List<String>? keys]) {
    final targetKeys =
        keys ??
        _MpvPlayerPageState._defaultMpvSettings.keys.toList(growable: false);
    var count = 0;
    for (final key in targetKeys) {
      if (!_shouldCompareMpvKey(key)) continue;
      final current = _mpvSettingValue(key);
      final fallback = _MpvPlayerPageState._defaultMpvSettings[key];
      if (fallback != null && current != fallback) {
        count += 1;
      }
    }
    return count;
  }

  MpvScenePreset? _activeMpvScenePreset() {
    if (_activeSavedMpvPicturePreset() != null ||
        _activeSavedMpvAudioPreset() != null) {
      return null;
    }
    return MpvSettingsCatalog.activeBuiltInScenePreset(
      _mpvSettings,
      _videoAdjustments,
    );
  }

  MpvScenePresetRecommendation? _recommendedMpvScenePreset() {
    final audioTrack = _currentAudioTrack();
    return MpvSettingsCatalog.recommendScenePreset(
      videoWidth: _currentVideoWidth > 0
          ? _currentVideoWidth
          : widget.source.videoWidth,
      videoHeight: _currentVideoHeight > 0
          ? _currentVideoHeight
          : widget.source.videoHeight,
      resolution: _currentResolution.trim().isNotEmpty
          ? _currentResolution
          : widget.source.resolution,
      bitrate: _currentBitrate > 0 ? _currentBitrate : widget.source.bitrate,
      videoCodecName: _currentVideoCodecName.trim().isNotEmpty
          ? _currentVideoCodecName
          : widget.source.videoCodecName,
      videoProfile: _currentVideoProfile.trim().isNotEmpty
          ? _currentVideoProfile
          : widget.source.videoProfile,
      colorSpace: _currentColorSpace.trim().isNotEmpty
          ? _currentColorSpace
          : widget.source.colorSpace,
      colorTransfer: _currentColorTransfer.trim().isNotEmpty
          ? _currentColorTransfer
          : widget.source.colorTransfer,
      colorPrimaries: _currentColorPrimaries.trim().isNotEmpty
          ? _currentColorPrimaries
          : widget.source.colorPrimaries,
      bitDepth: _currentBitDepth > 0
          ? _currentBitDepth
          : widget.source.bitDepth,
      isRemoteSource: _currentSourceLooksRemoteHttp(),
      audioChannels: audioTrack?.channels ?? 0,
      audioBitrate: audioTrack?.bps ?? 0,
      audioSampleRate: audioTrack?.sampleRate ?? 0,
    );
  }

  bool _currentSourceLooksRemoteHttp() {
    final raw = widget.source.url.trim().isNotEmpty
        ? widget.source.url.trim()
        : (widget.source.playLink ?? '').trim();
    if (raw.isEmpty) return false;
    final uri = Uri.tryParse(raw);
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;
    final host = uri.host.trim().toLowerCase();
    if (host.isEmpty || host == 'localhost' || host == '127.0.0.1') {
      return false;
    }
    if (host.endsWith('.local')) return false;
    final parts = host.split('.');
    if (parts.length == 4 &&
        parts.every((part) => int.tryParse(part) != null)) {
      final octets = parts.map(int.parse).toList(growable: false);
      final first = octets[0];
      final second = octets[1];
      if (first == 10 ||
          first == 127 ||
          (first == 192 && second == 168) ||
          (first == 172 && second >= 16 && second <= 31)) {
        return false;
      }
    }
    return true;
  }

  String _mpvRecommendedSceneLabel() {
    final l10n = AppLocalizations.of(context);
    final recommendation = _recommendedMpvScenePreset();
    if (recommendation != null) {
      return MpvSettingsL10n.scenePresetLabel(
        l10n,
        recommendation.preset.id,
        fallback: recommendation.preset.label,
      );
    }
    final active = _activeMpvScenePreset();
    if (active != null) {
      return MpvSettingsL10n.scenePresetLabel(
        l10n,
        active.id,
        fallback: active.label,
      );
    }
    return MpvSettingsL10n.notUsedLabel(l10n);
  }

  String _mpvVideoQuickPresetSummaryLabel() {
    final l10n = AppLocalizations.of(context);
    final preset = _activeMpvVideoPreset();
    if (preset != null) {
      return MpvSettingsL10n.picturePresetLabel(
        l10n,
        preset.id,
        fallback: preset.label,
      );
    }
    final changed = _mpvChangedSettingCount(
      _mpvVideoQuickPresetKeys.toList(growable: false),
    );
    if (changed == 0 && _videoAdjustmentChangedCount() == 0) {
      return MpvSettingsL10n.defaultLabel(l10n);
    }
    return MpvSettingsL10n.currentCustomLabel(l10n);
  }

  String _mpvAudioQuickPresetSummaryLabel() {
    final l10n = AppLocalizations.of(context);
    final preset = _activeMpvAudioPreset();
    if (preset != null) {
      return MpvSettingsL10n.audioPresetLabel(
        l10n,
        preset.id,
        fallback: preset.label,
      );
    }
    final changed = _mpvChangedSettingCount(
      _mpvAudioQuickPresetKeys.toList(growable: false),
    );
    return changed == 0
        ? MpvSettingsL10n.defaultLabel(l10n)
        : MpvSettingsL10n.currentCustomLabel(l10n);
  }

  String _mpvPictureCustomSummaryLabel() {
    final l10n = AppLocalizations.of(context);
    final preset = _activeMpvVideoPreset();
    if (preset != null) {
      return MpvSettingsL10n.picturePresetLabel(
        l10n,
        preset.id,
        fallback: preset.label,
      );
    }
    final changed =
        _mpvChangedSettingCount(
          _mpvVideoQuickPresetKeys.toList(growable: false),
        ) +
        _videoAdjustmentChangedCount();
    return changed == 0
        ? MpvSettingsL10n.defaultLabel(l10n)
        : MpvSettingsL10n.currentCustomLabel(l10n);
  }

  String _mpvAudioCustomSummaryLabel() {
    final l10n = AppLocalizations.of(context);
    final preset = _activeMpvAudioPreset();
    if (preset != null) {
      return MpvSettingsL10n.audioPresetLabel(
        l10n,
        preset.id,
        fallback: preset.label,
      );
    }
    final changed = _mpvChangedSettingCount(
      _mpvAudioQuickPresetKeys.toList(growable: false),
    );
    return changed == 0
        ? MpvSettingsL10n.defaultLabel(l10n)
        : MpvSettingsL10n.currentCustomLabel(l10n);
  }

  MpvSettingPreset? _activeMpvVideoPreset() {
    return _activeSavedMpvPicturePreset() ??
        MpvSettingsCatalog.activeBuiltInPicturePreset(
          _mpvSettings,
          _videoAdjustments,
        );
  }

  MpvSettingPreset? _activeMpvAudioPreset() {
    return _activeSavedMpvAudioPreset() ??
        MpvSettingsCatalog.activeBuiltInAudioPreset(_mpvSettings);
  }

  MpvSettingPreset? _activeSavedMpvPicturePreset() {
    final preset = MpvSettingsCatalog.activeSavedPreset(
      SavedMpvPresetKind.picture,
      _savedMpvPicturePresets,
      settings: _mpvSettings,
      videoAdjustments: _videoAdjustments,
    );
    if (preset == null) return null;
    final l10n = AppLocalizations.of(context);
    return MpvSettingPreset(
      id: preset.id,
      label: preset.name,
      description: preset.description.isEmpty
          ? l10n.mpvSavedPicturePreset
          : preset.description,
      settings: preset.settingsSnapshot,
      videoAdjustments: preset.videoAdjustmentsSnapshot,
    );
  }

  MpvSettingPreset? _activeSavedMpvAudioPreset() {
    final preset = MpvSettingsCatalog.activeSavedPreset(
      SavedMpvPresetKind.audio,
      _savedMpvAudioPresets,
      settings: _mpvSettings,
      videoAdjustments: _videoAdjustments,
    );
    if (preset == null) return null;
    final l10n = AppLocalizations.of(context);
    return MpvSettingPreset(
      id: preset.id,
      label: preset.name,
      description: preset.description.isEmpty
          ? l10n.mpvSavedAudioPreset
          : preset.description,
      settings: preset.settingsSnapshot,
    );
  }

  Future<void> _saveCurrentMpvPresetFromDrawer(
    PlayerNestedSheetController<void> drawer, {
    required SavedMpvPresetKind kind,
  }) async {
    final suggestedName = await _suggestedMpvPresetName(kind);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final result = await showNamedPresetSaveDialog(
      context,
      title: kind == SavedMpvPresetKind.picture
          ? l10n.mpvSaveCurrentPictureTitle
          : l10n.mpvSaveCurrentAudioTitle,
      initialName: suggestedName,
      suggestedName: suggestedName,
      nameLabel: MpvSettingsL10n.presetNameLabel(l10n, kind),
      descriptionLabel: l10n.commonDescriptionOptional,
      validateName: (name) {
        final presets = kind == SavedMpvPresetKind.picture
            ? _savedMpvPicturePresets
            : _savedMpvAudioPresets;
        for (final preset in presets) {
          if (preset.name.trim().toLowerCase() == name.trim().toLowerCase()) {
            return MpvSettingsL10n.presetDuplicateName(l10n, kind);
          }
        }
        return null;
      },
    );
    if (result == null) return;
    final savedPreset = await _mpvSettingsStore.savePresetSnapshot(
      kind: kind,
      name: result.name,
      description: result.description,
      settings: _mpvSettings,
      videoAdjustments: _videoAdjustments,
    );
    await _refreshSavedMpvPresets();
    if (!mounted) return;
    drawer.refresh();
    AppTopTip().show(
      context,
      message: MpvSettingsL10n.presetSavedMessage(l10n, kind, savedPreset.name),
      color: context.appColors.success,
    );
  }

  Future<String> _suggestedMpvPresetName(SavedMpvPresetKind kind) async {
    final l10n = AppLocalizations.of(context);
    final basePreset = kind == SavedMpvPresetKind.picture
        ? MpvSettingsCatalog.activeBuiltInPicturePreset(
            _mpvSettings,
            _videoAdjustments,
          )
        : MpvSettingsCatalog.activeBuiltInAudioPreset(_mpvSettings);
    final baseName = basePreset != null && basePreset.id != 'off'
        ? (kind == SavedMpvPresetKind.picture
              ? MpvSettingsL10n.picturePresetLabel(
                  l10n,
                  basePreset.id,
                  fallback: basePreset.label,
                )
              : MpvSettingsL10n.audioPresetLabel(
                  l10n,
                  basePreset.id,
                  fallback: basePreset.label,
                ))
        : MpvSettingsL10n.presetDefaultBaseName(l10n, kind);
    return _mpvSettingsStore.nextSavedPresetNameFromBase(kind, baseName);
  }

  _MpvSettingDefinition? _mpvDefinitionByKey(String key) {
    for (final definition in _mpvChoiceDefinitions) {
      if (definition.key == key) return definition;
    }
    return null;
  }

  Set<String> get _mpvVideoQuickPresetKeys => <String>{
    _MpvPlayerPageState._mpvSettingDeband,
    _MpvPlayerPageState._mpvSettingSharpen,
    _MpvPlayerPageState._mpvSettingDenoise,
    _MpvPlayerPageState._mpvSettingDeinterlace,
    _MpvPlayerPageState._mpvSettingScaleProfile,
    _MpvPlayerPageState._mpvSettingHdrMode,
    _MpvPlayerPageState._mpvSettingFrameInterpolation,
    _MpvPlayerPageState._mpvSettingVideoSync,
    _MpvPlayerPageState._mpvSettingCacheProfile,
    _MpvPlayerPageState._mpvSettingCacheSizeMb,
    _MpvPlayerPageState._mpvSettingCompatibility,
  };

  Set<String> get _mpvAudioQuickPresetKeys => <String>{
    _MpvPlayerPageState._mpvSettingVolumeGain,
    _MpvPlayerPageState._mpvSettingAudioHighFidelity,
    _MpvPlayerPageState._mpvSettingDynamicRange,
    _MpvPlayerPageState._mpvSettingAudioEq,
    _MpvPlayerPageState._mpvSettingAudioLimiter,
    _MpvPlayerPageState._mpvSettingAudioBassBoost,
    _MpvPlayerPageState._mpvSettingAudioVoiceEnhance,
    _MpvPlayerPageState._mpvSettingAudioEqBand60,
    _MpvPlayerPageState._mpvSettingAudioEqBand170,
    _MpvPlayerPageState._mpvSettingAudioEqBand310,
    _MpvPlayerPageState._mpvSettingAudioEqBand1000,
    _MpvPlayerPageState._mpvSettingAudioEqBand6000,
    _MpvPlayerPageState._mpvSettingChannelMix,
  };

  List<_MpvSettingDefinition> get _mpvChoiceDefinitions {
    return <String>[
          _MpvPlayerPageState._mpvSettingDeband,
          _MpvPlayerPageState._mpvSettingSharpen,
          _MpvPlayerPageState._mpvSettingDenoise,
          _MpvPlayerPageState._mpvSettingDeinterlace,
          _MpvPlayerPageState._mpvSettingScaleProfile,
          _MpvPlayerPageState._mpvSettingHdrMode,
          _MpvPlayerPageState._mpvSettingFrameInterpolation,
          _MpvPlayerPageState._mpvSettingVideoSync,
          _MpvPlayerPageState._mpvSettingCacheProfile,
          _MpvPlayerPageState._mpvSettingCacheSizeMb,
          _MpvPlayerPageState._mpvSettingVolumeGain,
          _MpvPlayerPageState._mpvSettingAudioHighFidelity,
          _MpvPlayerPageState._mpvSettingDynamicRange,
          _MpvPlayerPageState._mpvSettingAudioEq,
          _MpvPlayerPageState._mpvSettingAudioLimiter,
          _MpvPlayerPageState._mpvSettingAudioBassBoost,
          _MpvPlayerPageState._mpvSettingAudioVoiceEnhance,
          _MpvPlayerPageState._mpvSettingChannelMix,
          _MpvPlayerPageState._mpvSettingCompatibility,
        ]
        .map(_mpvDefinitionForKey)
        .whereType<_MpvSettingDefinition>()
        .toList(growable: false);
  }

  _MpvSettingDefinition? _mpvDefinitionForKey(String key) {
    final l10n = AppLocalizations.of(context);
    final definition = MpvSettingsL10n.definitionByKey(l10n, key);
    if (definition == null) return null;
    final pageId = _mpvPageIdForSettingKey(key);
    if (pageId == null) return null;
    return _MpvSettingDefinition(
      key: definition.key,
      pageId: pageId,
      title: definition.title,
      shortTitle: definition.shortTitle,
      description: definition.description,
      helperLabel: definition.helperLabel,
      options: definition.options
          .map(
            (option) => _MpvSettingOption(
              value: option.value,
              label: option.label,
              description: option.description,
            ),
          )
          .toList(growable: false),
    );
  }

  String? _mpvPageIdForSettingKey(String key) {
    return switch (key) {
      _MpvPlayerPageState._mpvSettingDeband => _playerSettingsMpvDebandPageId,
      _MpvPlayerPageState._mpvSettingSharpen => _playerSettingsMpvSharpenPageId,
      _MpvPlayerPageState._mpvSettingDenoise => _playerSettingsMpvDenoisePageId,
      _MpvPlayerPageState._mpvSettingDeinterlace =>
        _playerSettingsMpvDeinterlacePageId,
      _MpvPlayerPageState._mpvSettingScaleProfile =>
        _playerSettingsMpvScaleProfilePageId,
      _MpvPlayerPageState._mpvSettingHdrMode => _playerSettingsMpvHdrPageId,
      _MpvPlayerPageState._mpvSettingFrameInterpolation =>
        _playerSettingsMpvFrameInterpolationPageId,
      _MpvPlayerPageState._mpvSettingVideoSync =>
        _playerSettingsMpvVideoSyncPageId,
      _MpvPlayerPageState._mpvSettingCacheProfile =>
        _playerSettingsMpvCachePageId,
      _MpvPlayerPageState._mpvSettingCacheSizeMb =>
        _playerSettingsMpvCacheSizePageId,
      _MpvPlayerPageState._mpvSettingVolumeGain =>
        _playerSettingsMpvVolumeGainPageId,
      _MpvPlayerPageState._mpvSettingAudioHighFidelity =>
        _playerSettingsMpvAudioHighFidelityPageId,
      _MpvPlayerPageState._mpvSettingDynamicRange =>
        _playerSettingsMpvDynamicRangePageId,
      _MpvPlayerPageState._mpvSettingAudioEq => _playerSettingsMpvAudioEqPageId,
      _MpvPlayerPageState._mpvSettingAudioLimiter =>
        _playerSettingsMpvAudioLimiterPageId,
      _MpvPlayerPageState._mpvSettingAudioBassBoost =>
        _playerSettingsMpvAudioBassBoostPageId,
      _MpvPlayerPageState._mpvSettingAudioVoiceEnhance =>
        _playerSettingsMpvAudioVoiceEnhancePageId,
      _MpvPlayerPageState._mpvSettingChannelMix =>
        _playerSettingsMpvChannelMixPageId,
      _MpvPlayerPageState._mpvSettingCompatibility =>
        _playerSettingsMpvCompatibilityProfilePageId,
      _ => null,
    };
  }

  _MpvSettingCategoryEntry _mpvEntry(String key) {
    final definition = _mpvDefinitionForKey(key)!;
    return _MpvSettingCategoryEntry(
      title: definition.title,
      subtitle: definition.description,
      pageId: definition.pageId,
      settingKey: key,
    );
  }

  _MpvSettingCategoryEntry _mpvStaticEntry({
    required String title,
    required String subtitle,
    required String pageId,
    String trailingLabel = '',
  }) {
    return _MpvSettingCategoryEntry(
      title: title,
      subtitle: subtitle,
      pageId: pageId,
      trailingLabel: trailingLabel,
    );
  }

  _MpvSettingCategory get _mpvVideoFiltersCategory {
    final l10n = AppLocalizations.of(context);
    return _MpvSettingCategory(
      pageId: _playerSettingsMpvVideoFiltersPageId,
      title: l10n.mpvVideoFiltersCategoryTitle,
      subtitle: l10n.mpvVideoFiltersCategorySubtitle,
      description: l10n.mpvVideoFiltersCategoryDescription,
      entries: <_MpvSettingCategoryEntry>[
        _mpvEntry(_MpvPlayerPageState._mpvSettingDeband),
        _mpvEntry(_MpvPlayerPageState._mpvSettingSharpen),
        _mpvEntry(_MpvPlayerPageState._mpvSettingDenoise),
        _mpvEntry(_MpvPlayerPageState._mpvSettingDeinterlace),
        _mpvEntry(_MpvPlayerPageState._mpvSettingScaleProfile),
      ],
    );
  }

  _MpvSettingCategory get _mpvPictureRenderingCategory {
    final l10n = AppLocalizations.of(context);
    return _MpvSettingCategory(
      pageId: _playerSettingsMpvPictureRenderingPageId,
      title: l10n.settingsMpvPictureSection,
      subtitle: l10n.mpvPictureCategorySubtitle,
      description: l10n.mpvPictureCategoryDescription,
      entries: <_MpvSettingCategoryEntry>[
        _mpvStaticEntry(
          title: l10n.mpvInstantAdjustTitle,
          subtitle: l10n.mpvInstantAdjustSubtitle,
          pageId: _playerSettingsMpvQuickAdjustPageId,
          trailingLabel: l10n.commonEnter,
        ),
        _mpvEntry(_MpvPlayerPageState._mpvSettingDeband),
        _mpvEntry(_MpvPlayerPageState._mpvSettingSharpen),
        _mpvEntry(_MpvPlayerPageState._mpvSettingDenoise),
        _mpvEntry(_MpvPlayerPageState._mpvSettingDeinterlace),
        _mpvEntry(_MpvPlayerPageState._mpvSettingScaleProfile),
        _mpvEntry(_MpvPlayerPageState._mpvSettingHdrMode),
        _mpvEntry(_MpvPlayerPageState._mpvSettingFrameInterpolation),
      ],
    );
  }

  _MpvSettingCategory get _mpvPlaybackSyncCategory {
    final l10n = AppLocalizations.of(context);
    return _MpvSettingCategory(
      pageId: _playerSettingsMpvPlaybackSyncPageId,
      title: l10n.settingsMpvPlaybackSection,
      subtitle: l10n.mpvPlaybackCategorySubtitle,
      description: l10n.mpvPlaybackCategoryDescription,
      entries: <_MpvSettingCategoryEntry>[
        _mpvEntry(_MpvPlayerPageState._mpvSettingVideoSync),
        _mpvEntry(_MpvPlayerPageState._mpvSettingCacheProfile),
        _mpvEntry(_MpvPlayerPageState._mpvSettingCacheSizeMb),
      ],
    );
  }

  _MpvSettingCategory get _mpvAudioProcessingCategory {
    final l10n = AppLocalizations.of(context);
    return _MpvSettingCategory(
      pageId: _playerSettingsMpvAudioProcessingPageId,
      title: l10n.settingsMpvAudioSection,
      subtitle: l10n.mpvAudioCategorySubtitle,
      description: l10n.mpvAudioCategoryDescription,
      entries: <_MpvSettingCategoryEntry>[
        _mpvEntry(_MpvPlayerPageState._mpvSettingVolumeGain),
        _mpvEntry(_MpvPlayerPageState._mpvSettingAudioHighFidelity),
        _mpvEntry(_MpvPlayerPageState._mpvSettingDynamicRange),
        _mpvEntry(_MpvPlayerPageState._mpvSettingAudioEq),
        _mpvEntry(_MpvPlayerPageState._mpvSettingAudioLimiter),
        _mpvEntry(_MpvPlayerPageState._mpvSettingAudioBassBoost),
        _mpvEntry(_MpvPlayerPageState._mpvSettingAudioVoiceEnhance),
        _mpvEntry(_MpvPlayerPageState._mpvSettingChannelMix),
      ],
    );
  }

  _MpvSettingCategory get _mpvCompatibilityCategory {
    final l10n = AppLocalizations.of(context);
    return _MpvSettingCategory(
      pageId: _playerSettingsMpvCompatibilityPageId,
      title: l10n.settingsMpvCompatibilitySection,
      subtitle: l10n.mpvCompatibilityCategorySubtitle,
      description: l10n.mpvCompatibilityCategoryDescription,
      entries: <_MpvSettingCategoryEntry>[
        _mpvEntry(_MpvPlayerPageState._mpvSettingCompatibility),
        _mpvStaticEntry(
          title: l10n.mpvPlayerDiagnosticsTitle,
          subtitle: l10n.mpvPlayerDiagnosticsSubtitle,
          pageId: _playerSettingsVideoInfoPageId,
          trailingLabel: l10n.commonView,
        ),
      ],
    );
  }
}

class _MpvSettingCategory {
  final String pageId;
  final String title;
  final String subtitle;
  final String description;
  final List<_MpvSettingCategoryEntry> entries;

  const _MpvSettingCategory({
    required this.pageId,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.entries,
  });
}

class _MpvSettingCategoryEntry {
  final String title;
  final String subtitle;
  final String pageId;
  final String? settingKey;
  final String trailingLabel;

  const _MpvSettingCategoryEntry({
    required this.title,
    required this.subtitle,
    required this.pageId,
    this.settingKey,
    this.trailingLabel = '',
  });
}

class _MpvSettingDefinition {
  final String key;
  final String pageId;
  final String title;
  final String shortTitle;
  final String description;
  final String helperLabel;
  final List<_MpvSettingOption> options;

  const _MpvSettingDefinition({
    required this.key,
    required this.pageId,
    required this.title,
    required this.shortTitle,
    required this.description,
    required this.helperLabel,
    required this.options,
  });
}

class _MpvSettingOption {
  final String value;
  final String label;
  final String description;

  const _MpvSettingOption({
    required this.value,
    required this.label,
    required this.description,
  });
}
