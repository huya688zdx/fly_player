part of mpv_player_page;

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
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: 'MPV 播放器设置',
        onBack: drawer.popPage,
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsStatusCard(
            title: '当前方案',
            value: _mpvSettingsStatusLabel(),
            description: _mpvSettingsSummaryText(),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: '智能推荐',
            subtitle: '根据当前片源的分辨率、码率、HDR 和音轨信息推荐更合适的场景预设',
            trailingLabel: _mpvRecommendedSceneLabel(),
            onTap: () => drawer.push(_playerSettingsMpvScenePresetPageId),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: '画质快速预设',
            subtitle: '快速套用动画、影院、流畅等画质方案',
            trailingLabel: _mpvVideoQuickPresetSummaryLabel(),
            onTap: () => drawer.push(_playerSettingsMpvPresetPageId),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: '音频快速预设',
            subtitle: '高保真、EQ、低音增强、人声增强一键切换',
            trailingLabel: _mpvAudioQuickPresetSummaryLabel(),
            onTap: () => drawer.push(_playerSettingsMpvAudioPresetPageId),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: '自定义管理',
            subtitle: '把画质自定义、音频自定义和即时调节统一收进三级页面管理',
            trailingLabel:
                _mpvChangedSettingCount() > 0 ||
                    _videoAdjustmentChangedCount() > 0
                ? '当前自定义'
                : '默认',
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
    final scenePresets = MpvSettingsCatalog.builtInScenePresets;
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(title: '智能推荐', onBack: drawer.popPage),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsStatusCard(
            title: recommendation?.title ?? '当前没有推荐',
            value: recommendation?.preset.label ?? _mpvRecommendedSceneLabel(),
            description: recommendation?.reason ?? '当前片源信息还不完整，先保留手动选择。',
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
    final builtInPresets = MpvSettingsCatalog.builtInPicturePresets;
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(title: '画质快速预设', onBack: drawer.popPage),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsStatusCard(
            title: '画质快速预设',
            value: _mpvVideoQuickPresetSummaryLabel(),
            description: '这里只放画面相关方案，音频增强已经拆到独立的音频快速预设。',
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
                    ? '已保存画质预设'
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
    final builtInPresets = MpvSettingsCatalog.builtInAudioPresets;
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(title: '音频快速预设', onBack: drawer.popPage),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsStatusCard(
            title: '音频快速预设',
            value: _mpvAudioQuickPresetSummaryLabel(),
            description: '一键切换高保真、对白增强、低频氛围和夜间压缩，不再和画质预设混在一起。',
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
                    ? '已保存音频预设'
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
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(title: '自定义管理', onBack: drawer.popPage),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsStatusCard(
            title: '自定义管理',
            value:
                _mpvChangedSettingCount() > 0 ||
                    _videoAdjustmentChangedCount() > 0
                ? '当前自定义'
                : '全部默认',
            description: '首页只保留快速预设；即时调节、分类细调和保存当前预设都统一收进这里。',
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: '画质自定义',
            subtitle: '即时调节、滤镜、渲染、HDR、插帧、同步、缓存和兼容项',
            trailingLabel: _mpvPictureCustomSummaryLabel(),
            onTap: () => drawer.push(_playerSettingsMpvPictureCustomPageId),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: '音频自定义',
            subtitle: '高保真、音量增强、EQ、限幅、低音增强、人声增强和声道混合',
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
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(title: '画质自定义', onBack: drawer.popPage),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsStatusCard(
            title: '画质自定义',
            value: _mpvPictureCustomSummaryLabel(),
            description: '即时调节和所有画质相关细项都统一放在这里管理，保存后会生成独立画质预设。',
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: '保存当前画质',
            subtitle: '把当前即时调节和画质增强另存为独立预设',
            trailingLabel: '保存',
            onTap: () => unawaited(
              _saveCurrentMpvPresetFromDrawer(
                drawer,
                kind: SavedMpvPresetKind.picture,
              ),
            ),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: '即时调节',
            subtitle: '亮度、对比度、饱和度、Gamma、色相',
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
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(title: '音频自定义', onBack: drawer.popPage),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsStatusCard(
            title: '音频自定义',
            value: _mpvAudioCustomSummaryLabel(),
            description: '把高保真、EQ、音量增强和所有音频后处理统一放在这里管理，保存后会生成独立音频预设。',
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: '保存当前音频',
            subtitle: '把当前音频增强和 EQ 另存为独立预设',
            trailingLabel: '保存',
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
    final title = switch (value) {
      'default' => '智能分配',
      'low_latency' => '极速响应',
      'stable' => '稳定缓冲',
      'network' => '网盘 / STRM / NAS',
      _ => '缓存策略',
    };
    final content = switch (value) {
      'default' => '自动档。播放器会根据片源类型决定更合适的缓冲强度，本地文件更偏常规，较重的网络片源会自动偏向更稳的缓冲。',
      'low_latency' => '预读最轻，拖动、切换和回填最快，但抗抖动最弱。更适合本地视频，或者局域网很稳时追求跟手感。',
      'stable' => '中等偏重缓冲，优先减少抖动导致的卡顿。拖动响应会比极速慢一点，但更适合大多数 NAS、网盘和 STRM 观看。',
      'network' => '最重的一档，给高码率网盘、STRM 和 NAS 片源更多预读空间。起播和拖动后的回填更重，但最抗波动。',
      _ => '当前选项用于控制预读力度和缓冲风格。',
    };
    final extra = switch (value) {
      'default' => '适合：不想自己判断时直接用。',
      'low_latency' => '适合：本地硬盘视频、局域网很稳时的 NAS。',
      'stable' => '适合：大多数 NAS、网盘和普通 STRM。',
      'network' => '适合：高码率、大体积、跨网络访问的片源。',
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
              child: const Text('知道了'),
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
    final warning = MpvSettingsCatalog.performanceWarningForSelection(
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
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('继续开启'),
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
            title: '高级频段调整',
            subtitle: '进入上下滑动频谱页，自定义每个频段并保存多套预设。',
            trailingLabel:
                _mpvSettingValue(definition.key) ==
                    MpvSettingsCatalog.audioEqCustomValue
                ? '当前使用'
                : '进入',
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
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(title: '高级均衡', onBack: drawer.popPage),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          MpvAudioEqAdvancedPanel(
            settings: _mpvSettings,
            onApplyPatch: (patch) async {
              await _setMpvAdvancedSettingsPatch(patch);
              if (mounted) {
                drawer.refresh();
              }
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
            title: _mpvCacheSizeDefinition.title,
            onBack: drawer.popPage,
          ),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              PlaybackSettingsStatusCard(
                title: '缓存设定',
                value: auto
                    ? '自动'
                    : _formatMpvCachePercentLabel(selectedPercent),
                description: auto
                    ? '当前由缓存策略自动分配上限。关闭自动后，可直接拖动滑杆控制缓存百分比。'
                    : '缓存百分比越高，越有利于高码率和不稳定网络，但也会占用更多内存和存储。',
              ),
              const SizedBox(height: 12),
              PlaybackSettingsSwitchTile(
                title: '自动缓存',
                subtitle: auto ? '当前由缓存策略自动分配缓冲上限' : '关闭后可手动指定缓存百分比',
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
                          const Expanded(
                            child: _SettingsTextBlock(
                              title: '滑动设定',
                              subtitle: '拖动滑杆调整缓存百分比，修改后会立即应用到当前播放器。',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '缓存设定：${_formatMpvCachePercentLabel(selectedPercent)}',
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
    final range = _mpvCacheSizeSliderMaxMb - _mpvCacheSizeSliderMinMb;
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
    final range = _mpvCacheSizeSliderMaxMb - _mpvCacheSizeSliderMinMb;
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
    if (value == 'auto') return '自动';
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
    final scenePreset = _activeMpvScenePreset();
    if (scenePreset != null) return scenePreset.label;
    final videoPreset = _activeMpvVideoPreset();
    final audioPreset = _activeMpvAudioPreset();
    if (videoPreset != null && audioPreset != null) {
      final videoOff = videoPreset.id == 'off';
      final audioOff = audioPreset.id == 'off';
      if (videoOff && audioOff) return '默认';
      if (videoOff) return audioPreset.label;
      if (audioOff) return videoPreset.label;
      return '${videoPreset.label} / ${audioPreset.label}';
    }
    if (_mpvChangedSettingCount() == 0 && _videoAdjustmentChangedCount() == 0) {
      return '默认';
    }
    return '已自定义';
  }

  String _mpvSettingsSummaryText() {
    final scenePreset = _activeMpvScenePreset();
    if (scenePreset != null) return scenePreset.description;
    final videoPreset = _activeMpvVideoPreset();
    final audioPreset = _activeMpvAudioPreset();
    if (videoPreset != null || audioPreset != null) {
      final parts = <String>[];
      if (videoPreset != null && videoPreset.id != 'off') {
        parts.add('画质：${videoPreset.description}');
      }
      if (audioPreset != null && audioPreset.id != 'off') {
        parts.add('音频：${audioPreset.description}');
      }
      if (parts.isNotEmpty) return parts.join('  ');
    }
    if (_videoAdjustmentChangedCount() > 0 && _mpvChangedSettingCount() == 0) {
      return _videoAdjustmentSummaryText();
    }
    final changed = _mpvChangedSettingCount();
    if (changed == 0 && _videoAdjustmentChangedCount() == 0) {
      return '当前使用默认 MPV 参数。';
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
        ? '已调整 $totalChanged 项。'
        : '已调整 $totalChanged 项：${labels.join(' / ')}';
  }

  String _mpvCategorySummaryLabel(_MpvSettingCategory category) {
    final changedCount = _mpvChangedSettingCount(
      category.entries
          .map((entry) => entry.settingKey)
          .whereType<String>()
          .toList(growable: false),
    );
    if (changedCount == 0) return '默认';
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
    return '$changedCount 项';
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
    final recommendation = _recommendedMpvScenePreset();
    if (recommendation != null) return recommendation.preset.label;
    return _activeMpvScenePreset()?.label ?? '未使用';
  }

  String _mpvVideoQuickPresetSummaryLabel() {
    final preset = _activeMpvVideoPreset();
    if (preset != null) return preset.label;
    final changed = _mpvChangedSettingCount(
      _mpvVideoQuickPresetKeys.toList(growable: false),
    );
    if (changed == 0 && _videoAdjustmentChangedCount() == 0) return '默认';
    return '当前自定义';
  }

  String _mpvAudioQuickPresetSummaryLabel() {
    final preset = _activeMpvAudioPreset();
    if (preset != null) return preset.label;
    final changed = _mpvChangedSettingCount(
      _mpvAudioQuickPresetKeys.toList(growable: false),
    );
    return changed == 0 ? '默认' : '当前自定义';
  }

  String _mpvPictureCustomSummaryLabel() {
    final preset = _activeMpvVideoPreset();
    if (preset != null) return preset.label;
    final changed =
        _mpvChangedSettingCount(
          _mpvVideoQuickPresetKeys.toList(growable: false),
        ) +
        _videoAdjustmentChangedCount();
    return changed == 0 ? '默认' : '当前自定义';
  }

  String _mpvAudioCustomSummaryLabel() {
    final preset = _activeMpvAudioPreset();
    if (preset != null) return preset.label;
    final changed = _mpvChangedSettingCount(
      _mpvAudioQuickPresetKeys.toList(growable: false),
    );
    return changed == 0 ? '默认' : '当前自定义';
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
    return MpvSettingPreset(
      id: preset.id,
      label: preset.name,
      description: preset.description.isEmpty ? '已保存画质预设' : preset.description,
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
    return MpvSettingPreset(
      id: preset.id,
      label: preset.name,
      description: preset.description.isEmpty ? '已保存音频预设' : preset.description,
      settings: preset.settingsSnapshot,
    );
  }

  Future<void> _saveCurrentMpvPresetFromDrawer(
    PlayerNestedSheetController<void> drawer, {
    required SavedMpvPresetKind kind,
  }) async {
    final suggestedName = await _suggestedMpvPresetName(kind);
    if (!mounted) return;
    final result = await showNamedPresetSaveDialog(
      context,
      title: kind == SavedMpvPresetKind.picture ? '保存当前画质' : '保存当前音频',
      initialName: suggestedName,
      suggestedName: suggestedName,
      nameLabel: '${kind.label}预设名称',
      descriptionLabel: '说明（可选）',
      validateName: (name) {
        final presets = kind == SavedMpvPresetKind.picture
            ? _savedMpvPicturePresets
            : _savedMpvAudioPresets;
        for (final preset in presets) {
          if (preset.name.trim().toLowerCase() == name.trim().toLowerCase()) {
            return '${kind.label}预设名称不能重复';
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
      message: '已保存${kind.label}预设：${savedPreset.name}',
      color: context.appColors.success,
    );
  }

  Future<String> _suggestedMpvPresetName(SavedMpvPresetKind kind) async {
    final basePreset = kind == SavedMpvPresetKind.picture
        ? MpvSettingsCatalog.activeBuiltInPicturePreset(
            _mpvSettings,
            _videoAdjustments,
          )
        : MpvSettingsCatalog.activeBuiltInAudioPreset(_mpvSettings);
    final baseName = basePreset != null && basePreset.id != 'off'
        ? basePreset.label
        : '${kind.label}预设';
    return _mpvSettingsStore.nextSavedPresetNameFromBase(kind, baseName);
  }

  _MpvSettingDefinition? _mpvDefinitionByKey(String key) {
    for (final definition in _mpvChoiceDefinitions) {
      if (definition.key == key) return definition;
    }
    return null;
  }

  List<_MpvSettingPreset> get _mpvPresets => <_MpvSettingPreset>[
    const _MpvSettingPreset(
      id: 'off',
      label: '默认',
      description: '关闭额外画质增强，优先保证兼容性和稳定性。',
      settings: <String, String>{},
    ),
    const _MpvSettingPreset(
      id: 'anime',
      label: '动画清晰',
      description: '轻量去色带加标准缩放，适合动画和较干净的片源。',
      settings: <String, String>{
        _MpvPlayerPageState._mpvSettingDeband: 'low',
        _MpvPlayerPageState._mpvSettingScaleProfile: 'balanced',
      },
    ),
    const _MpvSettingPreset(
      id: 'cinema',
      label: '影院柔和',
      description: '保守去色带，适合老片和暗场，避免过重后处理。',
      settings: <String, String>{_MpvPlayerPageState._mpvSettingDeband: 'low'},
    ),
    const _MpvSettingPreset(
      id: 'smooth',
      label: '流畅优先',
      description: '偏性能与稳定的流畅方案，自动判断是否启用插帧。',
      settings: <String, String>{
        _MpvPlayerPageState._mpvSettingScaleProfile: 'fast',
        _MpvPlayerPageState._mpvSettingFrameInterpolation: 'auto',
        _MpvPlayerPageState._mpvSettingVideoSync: 'auto',
        _MpvPlayerPageState._mpvSettingCacheProfile: 'stable',
        _MpvPlayerPageState._mpvSettingCompatibility: 'conservative',
      },
    ),
  ];

  List<_MpvSettingPreset> get _mpvAudioPresets => <_MpvSettingPreset>[
    const _MpvSettingPreset(
      id: 'off',
      label: '默认',
      description: '关闭额外音频增强，保留基础播放参数。',
      settings: <String, String>{},
    ),
    const _MpvSettingPreset(
      id: 'hi_fi',
      label: '原声保真',
      description: '打开高保真，旁路 EQ 和增强，适合耳机和高质量片源。',
      settings: <String, String>{
        _MpvPlayerPageState._mpvSettingAudioHighFidelity: 'on',
        _MpvPlayerPageState._mpvSettingVolumeGain: '100',
      },
    ),
    const _MpvSettingPreset(
      id: 'balanced',
      label: '通用增强',
      description: '轻度提亮人声和低频，适合大多数普通剧集、综艺和日常看片。',
      settings: <String, String>{
        _MpvPlayerPageState._mpvSettingVolumeGain: '125',
        _MpvPlayerPageState._mpvSettingAudioEq: 'soft',
        _MpvPlayerPageState._mpvSettingAudioLimiter: 'light',
        _MpvPlayerPageState._mpvSettingAudioBassBoost: 'low',
        _MpvPlayerPageState._mpvSettingAudioVoiceEnhance: 'low',
        _MpvPlayerPageState._mpvSettingChannelMix: 'stereo',
      },
    ),
    const _MpvSettingPreset(
      id: 'dialogue',
      label: '人声清晰',
      description: '抬前对白和中高频细节，适合台词偏轻的片源。',
      settings: <String, String>{
        _MpvPlayerPageState._mpvSettingVolumeGain: '140',
        _MpvPlayerPageState._mpvSettingDynamicRange: 'low',
        _MpvPlayerPageState._mpvSettingAudioEq: 'clarity',
        _MpvPlayerPageState._mpvSettingAudioLimiter: 'light',
        _MpvPlayerPageState._mpvSettingAudioVoiceEnhance: 'medium',
        _MpvPlayerPageState._mpvSettingChannelMix: 'stereo',
      },
    ),
    const _MpvSettingPreset(
      id: 'speaker_clear',
      label: '外放清晰',
      description: '针对手机和平板外放，压住爆点、把对白往前推，减少糊成一团。',
      settings: <String, String>{
        _MpvPlayerPageState._mpvSettingVolumeGain: '160',
        _MpvPlayerPageState._mpvSettingDynamicRange: 'medium',
        _MpvPlayerPageState._mpvSettingAudioEq: 'clarity',
        _MpvPlayerPageState._mpvSettingAudioLimiter: 'strong',
        _MpvPlayerPageState._mpvSettingAudioVoiceEnhance: 'medium',
        _MpvPlayerPageState._mpvSettingChannelMix: 'stereo',
      },
    ),
    const _MpvSettingPreset(
      id: 'cinema_bass',
      label: '影院低频',
      description: '增强低频氛围和厚度，适合动作片、配乐片和外放。',
      settings: <String, String>{
        _MpvPlayerPageState._mpvSettingVolumeGain: '135',
        _MpvPlayerPageState._mpvSettingAudioEq: 'cinema',
        _MpvPlayerPageState._mpvSettingAudioLimiter: 'light',
        _MpvPlayerPageState._mpvSettingAudioBassBoost: 'medium',
        _MpvPlayerPageState._mpvSettingChannelMix: 'auto',
      },
    ),
    const _MpvSettingPreset(
      id: 'headphone_immersive',
      label: '耳机沉浸',
      description: '保留动态感，补一点氛围和厚度，适合耳机听电影和演唱会现场。',
      settings: <String, String>{
        _MpvPlayerPageState._mpvSettingVolumeGain: '120',
        _MpvPlayerPageState._mpvSettingAudioEq: 'cinema',
        _MpvPlayerPageState._mpvSettingAudioLimiter: 'light',
        _MpvPlayerPageState._mpvSettingAudioBassBoost: 'low',
        _MpvPlayerPageState._mpvSettingChannelMix: 'stereo',
      },
    ),
    const _MpvSettingPreset(
      id: 'night',
      label: '夜间均衡',
      description: '压低爆点、抬前对白，适合深夜外放和追剧。',
      settings: <String, String>{
        _MpvPlayerPageState._mpvSettingVolumeGain: '140',
        _MpvPlayerPageState._mpvSettingDynamicRange: 'medium',
        _MpvPlayerPageState._mpvSettingAudioEq: 'soft',
        _MpvPlayerPageState._mpvSettingAudioLimiter: 'strong',
        _MpvPlayerPageState._mpvSettingAudioVoiceEnhance: 'low',
        _MpvPlayerPageState._mpvSettingChannelMix: 'stereo',
      },
    ),
  ];

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

  List<_MpvSettingDefinition> get _mpvChoiceDefinitions =>
      <_MpvSettingDefinition>[
        _mpvDebandDefinition,
        _mpvSharpenDefinition,
        _mpvDenoiseDefinition,
        _mpvDeinterlaceDefinition,
        _mpvScaleProfileDefinition,
        _mpvHdrDefinition,
        _mpvFrameInterpolationDefinition,
        _mpvVideoSyncDefinition,
        _mpvCacheDefinition,
        _mpvCacheSizeDefinition,
        _mpvVolumeGainDefinition,
        _mpvAudioHighFidelityDefinition,
        _mpvDynamicRangeDefinition,
        _mpvAudioEqDefinitionFixed,
        _mpvAudioLimiterDefinition,
        _mpvAudioBassBoostDefinition,
        _mpvAudioVoiceEnhanceDefinition,
        _mpvChannelMixDefinition,
        _mpvCompatibilityDefinition,
      ];

  _MpvSettingDefinition get _mpvDebandDefinition => const _MpvSettingDefinition(
    key: _MpvPlayerPageState._mpvSettingDeband,
    pageId: _playerSettingsMpvDebandPageId,
    title: '去色带',
    shortTitle: '去色带',
    description: '处理渐变断层和暗部条带，适合高压缩或低码率片源。',
    helperLabel: '去色带强度',
    options: <_MpvSettingOption>[
      _MpvSettingOption(value: 'off', label: '关闭', description: '不额外处理色带。'),
      _MpvSettingOption(value: 'low', label: '轻度', description: '轻微去除色带，兼顾细节。'),
      _MpvSettingOption(value: 'medium', label: '标准', description: '更明显地平滑色带。'),
    ],
  );

  _MpvSettingDefinition
  get _mpvSharpenDefinition => const _MpvSettingDefinition(
    key: _MpvPlayerPageState._mpvSettingSharpen,
    pageId: _playerSettingsMpvSharpenPageId,
    title: '锐化',
    shortTitle: '锐化',
    description: '提升边缘清晰度，但过强可能带来噪点和轮廓感。',
    helperLabel: '锐化强度',
    options: <_MpvSettingOption>[
      _MpvSettingOption(value: 'off', label: '关闭', description: '保持原始画面细节。'),
      _MpvSettingOption(value: 'low', label: '轻度', description: '轻微提升边缘锐利度。'),
      _MpvSettingOption(value: 'medium', label: '标准', description: '更明显的锐化效果。'),
    ],
  );

  _MpvSettingDefinition get _mpvDenoiseDefinition =>
      const _MpvSettingDefinition(
        key: _MpvPlayerPageState._mpvSettingDenoise,
        pageId: _playerSettingsMpvDenoisePageId,
        title: '降噪',
        shortTitle: '降噪',
        description: '压制噪点和颗粒感，适合老片源或码率偏低的视频。',
        helperLabel: '降噪强度',
        options: <_MpvSettingOption>[
          _MpvSettingOption(value: 'off', label: '关闭', description: '不做额外降噪。'),
          _MpvSettingOption(
            value: 'low',
            label: '轻度',
            description: '轻微压制噪点，保留较多细节。',
          ),
          _MpvSettingOption(
            value: 'medium',
            label: '标准',
            description: '更强调干净画面。',
          ),
        ],
      );

  _MpvSettingDefinition get _mpvDeinterlaceDefinition =>
      const _MpvSettingDefinition(
        key: _MpvPlayerPageState._mpvSettingDeinterlace,
        pageId: _playerSettingsMpvDeinterlacePageId,
        title: '反交错',
        shortTitle: '反交错',
        description: '针对隔行扫描片源，普通网络视频建议保持自动。',
        helperLabel: '处理方式',
        options: <_MpvSettingOption>[
          _MpvSettingOption(
            value: 'auto',
            label: '自动',
            description: '检测到隔行源时才启用。',
          ),
          _MpvSettingOption(value: 'off', label: '关闭', description: '始终关闭反交错。'),
          _MpvSettingOption(
            value: 'force',
            label: '强制开启',
            description: '无论片源类型都执行反交错。',
          ),
        ],
      );

  _MpvSettingDefinition get _mpvScaleProfileDefinition =>
      const _MpvSettingDefinition(
        key: _MpvPlayerPageState._mpvSettingScaleProfile,
        pageId: _playerSettingsMpvScaleProfilePageId,
        title: '缩放算法',
        shortTitle: '缩放',
        description: '控制放大和缩小时的画面取向，在画质和性能之间取舍。',
        helperLabel: '缩放策略',
        options: <_MpvSettingOption>[
          _MpvSettingOption(
            value: 'fast',
            label: '快速',
            description: '优先性能，适合低端设备。',
          ),
          _MpvSettingOption(
            value: 'balanced',
            label: '标准',
            description: '画质和功耗更均衡。',
          ),
          _MpvSettingOption(
            value: 'quality',
            label: '高质量',
            description: '追求更细腻的缩放效果。',
          ),
        ],
      );

  _MpvSettingDefinition get _mpvHdrDefinition => const _MpvSettingDefinition(
    key: _MpvPlayerPageState._mpvSettingHdrMode,
    pageId: _playerSettingsMpvHdrPageId,
    title: 'HDR 处理',
    shortTitle: 'HDR',
    description: '控制 HDR 到 SDR 的映射和整体色彩倾向。',
    helperLabel: 'HDR 模式',
    options: <_MpvSettingOption>[
      _MpvSettingOption(
        value: 'auto',
        label: '自动',
        description: '按片源和设备能力自动选择。',
      ),
      _MpvSettingOption(
        value: 'sdr_map',
        label: 'SDR 映射',
        description: '更偏兼容和稳定。',
      ),
      _MpvSettingOption(
        value: 'conservative',
        label: '保守映射',
        description: '更稳地压制高光。',
      ),
      _MpvSettingOption(
        value: 'enhanced',
        label: '增强映射',
        description: '更强调对比和高光层次。',
      ),
    ],
  );

  _MpvSettingDefinition get _mpvFrameInterpolationDefinition =>
      const _MpvSettingDefinition(
        key: _MpvPlayerPageState._mpvSettingFrameInterpolation,
        pageId: _playerSettingsMpvFrameInterpolationPageId,
        title: '插帧',
        shortTitle: '插帧',
        description: '通过补帧提升运动流畅度，但会增加功耗，也可能改变观感。',
        helperLabel: '插帧策略',
        options: <_MpvSettingOption>[
          _MpvSettingOption(
            value: 'off',
            label: '关闭',
            description: '保持原始帧率输出。',
          ),
          _MpvSettingOption(
            value: 'auto',
            label: '自动',
            description: '按场景决定是否启用。',
          ),
          _MpvSettingOption(
            value: 'on',
            label: '始终开启',
            description: '最大化流畅度，性能开销最高。',
          ),
        ],
      );

  _MpvSettingDefinition get _mpvVideoSyncDefinition =>
      const _MpvSettingDefinition(
        key: _MpvPlayerPageState._mpvSettingVideoSync,
        pageId: _playerSettingsMpvVideoSyncPageId,
        title: '同步模式',
        shortTitle: '同步',
        description: '只控制音画与刷新率的同步取向，不负责缓冲大小和缓存风格。',
        helperLabel: '同步取向',
        options: <_MpvSettingOption>[
          _MpvSettingOption(
            value: 'auto',
            label: '智能平衡',
            description: '按当前设备能力自动平衡音画稳定与刷新率匹配。',
          ),
          _MpvSettingOption(
            value: 'audio',
            label: '音频优先',
            description: '优先保证音频连续稳定。',
          ),
          _MpvSettingOption(
            value: 'display',
            label: '显示优先',
            description: '更重视刷新率匹配。',
          ),
          _MpvSettingOption(
            value: 'smooth',
            label: '平滑同步',
            description: '更积极地贴合显示刷新率，适合更在意观感流畅的场景。',
          ),
        ],
      );

  _MpvSettingDefinition get _mpvCacheDefinition => const _MpvSettingDefinition(
    key: _MpvPlayerPageState._mpvSettingCacheProfile,
    pageId: _playerSettingsMpvCachePageId,
    title: '缓存策略',
    shortTitle: '缓存',
    description: '只决定缓冲风格和预读力度，不会改动同步模式。',
    helperLabel: '缓冲取向',
    options: <_MpvSettingOption>[
      _MpvSettingOption(
        value: 'default',
        label: '智能分配',
        description: '按片源类型自动选择更合适的缓冲强度。',
      ),
      _MpvSettingOption(
        value: 'low_latency',
        label: '极速响应',
        description: '尽量减轻预读，优先拖动和切换响应。',
      ),
      _MpvSettingOption(
        value: 'stable',
        label: '稳定缓冲',
        description: '适当增加预读，优先减轻网络抖动。',
      ),
      _MpvSettingOption(
        value: 'network',
        label: '网盘 / STRM / NAS',
        description: '适合网盘、STRM 和 NAS 里的高码率片源。',
      ),
    ],
  );

  _MpvSettingDefinition get _mpvCacheSizeDefinition =>
      const _MpvSettingDefinition(
        key: _MpvPlayerPageState._mpvSettingCacheSizeMb,
        pageId: _playerSettingsMpvCacheSizePageId,
        title: '缓冲大小',
        shortTitle: '缓冲大小',
        description: '直接控制播放器最多预读多少数据，数值越大越稳，但起播和拖动后的回填会更重。',
        helperLabel: '缓冲上限',
        options: <_MpvSettingOption>[
          _MpvSettingOption(
            value: 'auto',
            label: '自动',
            description: '跟随当前缓存策略自动分配。',
          ),
          _MpvSettingOption(
            value: '64',
            label: '64 MB',
            description: '较省内存，适合普通码率。',
          ),
          _MpvSettingOption(
            value: '128',
            label: '128 MB',
            description: '更适合远程直链和高码率文件。',
          ),
          _MpvSettingOption(
            value: '256',
            label: '256 MB',
            description: '优先减少网络抖动带来的卡顿。',
          ),
          _MpvSettingOption(
            value: '512',
            label: '512 MB',
            description: '适合超高码率和不稳定网络，但占用更高。',
          ),
        ],
      );

  _MpvSettingDefinition get _mpvVolumeGainDefinition =>
      const _MpvSettingDefinition(
        key: _MpvPlayerPageState._mpvSettingVolumeGain,
        pageId: _playerSettingsMpvVolumeGainPageId,
        title: '音量放大',
        shortTitle: '音量',
        description: '为偏小声片源提供更高的音量上限。',
        helperLabel: '音量上限',
        options: <_MpvSettingOption>[
          _MpvSettingOption(
            value: '100',
            label: '100%',
            description: '标准音量上限。',
          ),
          _MpvSettingOption(
            value: '150',
            label: '150%',
            description: '适合对白偏轻的片源。',
          ),
          _MpvSettingOption(
            value: '200',
            label: '200%',
            description: '最大放大，可能带来失真。',
          ),
        ],
      );

  _MpvSettingDefinition
  get _mpvDynamicRangeDefinition => const _MpvSettingDefinition(
    key: _MpvPlayerPageState._mpvSettingDynamicRange,
    pageId: _playerSettingsMpvDynamicRangePageId,
    title: '动态范围压缩',
    shortTitle: '动态范围',
    description: '压低爆点和高动态差异，让对白更靠前。',
    helperLabel: '压缩强度',
    options: <_MpvSettingOption>[
      _MpvSettingOption(value: 'off', label: '关闭', description: '保持原始动态范围。'),
      _MpvSettingOption(value: 'low', label: '轻度', description: '轻微提升对白可听性。'),
      _MpvSettingOption(value: 'medium', label: '标准', description: '夜间播放更友好。'),
    ],
  );

  _MpvSettingDefinition get _mpvAudioHighFidelityDefinition =>
      const _MpvSettingDefinition(
        key: _MpvPlayerPageState._mpvSettingAudioHighFidelity,
        pageId: _playerSettingsMpvAudioHighFidelityPageId,
        title: '高保真模式',
        shortTitle: '高保真',
        description: '关闭 EQ、限幅、低音增强、人声增强和动态压缩，尽量保持更干净的解码输出。',
        helperLabel: '输出取向',
        options: <_MpvSettingOption>[
          _MpvSettingOption(
            value: 'off',
            label: '关闭',
            description: '继续按当前音频处理设置应用增强和滤镜链。',
          ),
          _MpvSettingOption(
            value: 'on',
            label: '开启',
            description: '优先保留原始音色，旁路大部分音频后处理。',
          ),
        ],
      );
  // ignore: unused_element
  _MpvSettingDefinition get _mpvAudioEqDefinition =>
      const _MpvSettingDefinition(
        key: _MpvPlayerPageState._mpvSettingAudioEq,
        pageId: _playerSettingsMpvAudioEqPageId,
        title: 'EQ 均衡器',
        shortTitle: 'EQ',
        description: '用不同的均衡预设调整低频、中频和高频的听感平衡。',
        helperLabel: '均衡预设',
        options: <_MpvSettingOption>[
          _MpvSettingOption(value: 'off', label: '关闭', description: '保持原始音色。'),
          _MpvSettingOption(
            value: 'soft',
            label: '柔和',
            description: '轻微修整低频和人声，适合普通观看。',
          ),
          _MpvSettingOption(
            value: 'clarity',
            label: '清晰',
            description: '更强调人声和高频细节，适合对白偏轻的片源。',
          ),
          _MpvSettingOption(
            value: 'cinema',
            label: '影院',
            description: '更均衡地兼顾低频氛围和台词清晰度。',
          ),
        ],
      );

  _MpvSettingDefinition get _mpvAudioEqDefinitionFixed =>
      const _MpvSettingDefinition(
        key: _MpvPlayerPageState._mpvSettingAudioEq,
        pageId: _playerSettingsMpvAudioEqPageId,
        title: 'EQ 均衡器',
        shortTitle: 'EQ',
        description: '用不同的均衡预设调整低频、中频和高频的听感平衡。',
        helperLabel: '均衡预设',
        options: <_MpvSettingOption>[
          _MpvSettingOption(value: 'off', label: '关闭', description: '保持原始音色。'),
          _MpvSettingOption(
            value: 'soft',
            label: '柔和',
            description: '轻微修整低频和人声，适合普通观看。',
          ),
          _MpvSettingOption(
            value: 'clarity',
            label: '清晰',
            description: '更强调人声和高频细节，适合对白偏轻的片源。',
          ),
          _MpvSettingOption(
            value: 'cinema',
            label: '影院',
            description: '更均衡地兼顾低频氛围和台词清晰度。',
          ),
          _MpvSettingOption(
            value: MpvSettingsCatalog.audioEqCustomValue,
            label: '高级自定义',
            description: '进入多频段页，自己上下拖动每个频带。',
          ),
        ],
      );

  _MpvSettingDefinition get _mpvAudioLimiterDefinition =>
      const _MpvSettingDefinition(
        key: _MpvPlayerPageState._mpvSettingAudioLimiter,
        pageId: _playerSettingsMpvAudioLimiterPageId,
        title: '峰值限幅',
        shortTitle: '限幅',
        description: '在不改变整体听感的情况下压住瞬时过高的声音，防止破音。',
        helperLabel: '限幅强度',
        options: <_MpvSettingOption>[
          _MpvSettingOption(
            value: 'off',
            label: '关闭',
            description: '不额外做峰值压制。',
          ),
          _MpvSettingOption(
            value: 'light',
            label: '轻度',
            description: '轻微压低突然的大音量，尽量保留动态。',
          ),
          _MpvSettingOption(
            value: 'strong',
            label: '标准',
            description: '更积极地防止破音，适合增强较多时使用。',
          ),
        ],
      );

  _MpvSettingDefinition get _mpvAudioBassBoostDefinition =>
      const _MpvSettingDefinition(
        key: _MpvPlayerPageState._mpvSettingAudioBassBoost,
        pageId: _playerSettingsMpvAudioBassBoostPageId,
        title: '低音增强',
        shortTitle: '低音',
        description: '为影院氛围感、地鸣和配乐的低频部分提供更强烈的存在感。',
        helperLabel: '低音强度',
        options: <_MpvSettingOption>[
          _MpvSettingOption(
            value: 'off',
            label: '关闭',
            description: '保持当前低频表现。',
          ),
          _MpvSettingOption(
            value: 'low',
            label: '轻度',
            description: '轻微提升低频厚度。',
          ),
          _MpvSettingOption(
            value: 'medium',
            label: '标准',
            description: '更明显的低音增强效果。',
          ),
        ],
      );

  _MpvSettingDefinition get _mpvAudioVoiceEnhanceDefinition =>
      const _MpvSettingDefinition(
        key: _MpvPlayerPageState._mpvSettingAudioVoiceEnhance,
        pageId: _playerSettingsMpvAudioVoiceEnhancePageId,
        title: '人声增强',
        shortTitle: '人声',
        description: '通过人声去除低频混浊，提升台词和对白的清晰度。',
        helperLabel: '人声强度',
        options: <_MpvSettingOption>[
          _MpvSettingOption(
            value: 'off',
            label: '关闭',
            description: '保持原始人声表现。',
          ),
          _MpvSettingOption(
            value: 'low',
            label: '轻度',
            description: '轻微提升台词，不太改变整体音色。',
          ),
          _MpvSettingOption(
            value: 'medium',
            label: '标准',
            description: '更适合对白偏轻或后景音偏响的片源。',
          ),
        ],
      );

  _MpvSettingDefinition get _mpvChannelMixDefinition =>
      const _MpvSettingDefinition(
        key: _MpvPlayerPageState._mpvSettingChannelMix,
        pageId: _playerSettingsMpvChannelMixPageId,
        title: '声道混合',
        shortTitle: '声道',
        description: '控制多声道到当前输出设备的混合策略。',
        helperLabel: '输出方式',
        options: <_MpvSettingOption>[
          _MpvSettingOption(
            value: 'auto',
            label: '自动',
            description: '按设备和片源自动选择。',
          ),
          _MpvSettingOption(
            value: 'stereo',
            label: '立体声优先',
            description: '更适合耳机和普通外放。',
          ),
          _MpvSettingOption(
            value: 'surround',
            label: '环绕优先',
            description: '尽量保留更多多声道信息。',
          ),
        ],
      );

  _MpvSettingDefinition get _mpvCompatibilityDefinition =>
      const _MpvSettingDefinition(
        key: _MpvPlayerPageState._mpvSettingCompatibility,
        pageId: _playerSettingsMpvCompatibilityProfilePageId,
        title: '兼容模式',
        shortTitle: '兼容',
        description: '遇到黑屏、花屏或特殊机型问题时，用来快速回退策略。',
        helperLabel: '兼容策略',
        options: <_MpvSettingOption>[
          _MpvSettingOption(
            value: 'default',
            label: '默认',
            description: '保持当前常规配置。',
          ),
          _MpvSettingOption(
            value: 'conservative',
            label: '保守兼容',
            description: '减少激进渲染和滤镜行为。',
          ),
          _MpvSettingOption(
            value: 'software_fallback',
            label: '软件优先',
            description: '更强调稳定性，必要时回退到软解策略。',
          ),
        ],
      );

  _MpvSettingCategory get _mpvVideoFiltersCategory => _MpvSettingCategory(
    pageId: _playerSettingsMpvVideoFiltersPageId,
    title: '视频滤镜',
    subtitle: '去色带、锐化、降噪、反交错、缩放算法',
    description: '主要针对画面净化、边缘锐度和缩放观感。',
    entries: const <_MpvSettingCategoryEntry>[
      _MpvSettingCategoryEntry(
        title: '去色带',
        subtitle: '处理渐变断层和暗部条带',
        pageId: _playerSettingsMpvDebandPageId,
        settingKey: _MpvPlayerPageState._mpvSettingDeband,
      ),
      _MpvSettingCategoryEntry(
        title: '锐化',
        subtitle: '提升边缘清晰度',
        pageId: _playerSettingsMpvSharpenPageId,
        settingKey: _MpvPlayerPageState._mpvSettingSharpen,
      ),
      _MpvSettingCategoryEntry(
        title: '降噪',
        subtitle: '压制噪点和颗粒感',
        pageId: _playerSettingsMpvDenoisePageId,
        settingKey: _MpvPlayerPageState._mpvSettingDenoise,
      ),
      _MpvSettingCategoryEntry(
        title: '反交错',
        subtitle: '处理隔行扫描片源',
        pageId: _playerSettingsMpvDeinterlacePageId,
        settingKey: _MpvPlayerPageState._mpvSettingDeinterlace,
      ),
      _MpvSettingCategoryEntry(
        title: '缩放算法',
        subtitle: '控制放大和缩小时的取向',
        pageId: _playerSettingsMpvScaleProfilePageId,
        settingKey: _MpvPlayerPageState._mpvSettingScaleProfile,
      ),
    ],
  );

  _MpvSettingCategory get _mpvPictureRenderingCategory => _MpvSettingCategory(
    pageId: _playerSettingsMpvPictureRenderingPageId,
    title: '画面调节',
    subtitle: '即时调节、滤镜、渲染、HDR 与插帧',
    description: '围绕画面观感的细项统一收在这里，避免和其他链路混杂。',
    entries: const <_MpvSettingCategoryEntry>[
      _MpvSettingCategoryEntry(
        title: '即时调节',
        subtitle: '亮度、对比度、饱和度、Gamma、色相',
        pageId: _playerSettingsMpvQuickAdjustPageId,
        trailingLabel: '进入',
      ),
      _MpvSettingCategoryEntry(
        title: '去色带',
        subtitle: '处理渐变断层和暗部条带',
        pageId: _playerSettingsMpvDebandPageId,
        settingKey: _MpvPlayerPageState._mpvSettingDeband,
      ),
      _MpvSettingCategoryEntry(
        title: '锐化',
        subtitle: '提升线条和边缘清晰度',
        pageId: _playerSettingsMpvSharpenPageId,
        settingKey: _MpvPlayerPageState._mpvSettingSharpen,
      ),
      _MpvSettingCategoryEntry(
        title: '降噪',
        subtitle: '压制噪点和颗粒感',
        pageId: _playerSettingsMpvDenoisePageId,
        settingKey: _MpvPlayerPageState._mpvSettingDenoise,
      ),
      _MpvSettingCategoryEntry(
        title: '反交错',
        subtitle: '处理隔行扫描片源',
        pageId: _playerSettingsMpvDeinterlacePageId,
        settingKey: _MpvPlayerPageState._mpvSettingDeinterlace,
      ),
      _MpvSettingCategoryEntry(
        title: '缩放算法',
        subtitle: '控制放大和缩小时的取向',
        pageId: _playerSettingsMpvScaleProfilePageId,
        settingKey: _MpvPlayerPageState._mpvSettingScaleProfile,
      ),
      _MpvSettingCategoryEntry(
        title: 'HDR 处理',
        subtitle: '调整 HDR 映射和整体色调',
        pageId: _playerSettingsMpvHdrPageId,
        settingKey: _MpvPlayerPageState._mpvSettingHdrMode,
      ),
      _MpvSettingCategoryEntry(
        title: '插帧',
        subtitle: '改善运动流畅度，性能开销更高',
        pageId: _playerSettingsMpvFrameInterpolationPageId,
        settingKey: _MpvPlayerPageState._mpvSettingFrameInterpolation,
      ),
    ],
  );

  _MpvSettingCategory get _mpvPlaybackSyncCategory => _MpvSettingCategory(
    pageId: _playerSettingsMpvPlaybackSyncPageId,
    title: '播放与缓存',
    subtitle: '同步模式、缓存策略与缓冲大小',
    description: '主要影响拖动响应、缓冲强度和播放稳定性。',
    entries: const <_MpvSettingCategoryEntry>[
      _MpvSettingCategoryEntry(
        title: '同步模式',
        subtitle: '只调整音画与刷新率的同步取向',
        pageId: _playerSettingsMpvVideoSyncPageId,
        settingKey: _MpvPlayerPageState._mpvSettingVideoSync,
      ),
      _MpvSettingCategoryEntry(
        title: '缓存策略',
        subtitle: '只调整预读力度和缓冲风格',
        pageId: _playerSettingsMpvCachePageId,
        settingKey: _MpvPlayerPageState._mpvSettingCacheProfile,
      ),
      _MpvSettingCategoryEntry(
        title: '缓冲大小',
        subtitle: '手动覆盖自动缓存上限',
        pageId: _playerSettingsMpvCacheSizePageId,
        settingKey: _MpvPlayerPageState._mpvSettingCacheSizeMb,
      ),
    ],
  );

  _MpvSettingCategory get _mpvAudioProcessingCategory => _MpvSettingCategory(
    pageId: _playerSettingsMpvAudioProcessingPageId,
    title: '音频调节',
    subtitle: '音量、EQ、增强与声道混合',
    description: '统一管理音频后处理和高保真模式，避免入口散开。',
    entries: const <_MpvSettingCategoryEntry>[
      _MpvSettingCategoryEntry(
        title: '音量放大',
        subtitle: '提高偏小声音源的音量上限',
        pageId: _playerSettingsMpvVolumeGainPageId,
        settingKey: _MpvPlayerPageState._mpvSettingVolumeGain,
      ),
      _MpvSettingCategoryEntry(
        title: '高保真模式',
        subtitle: '优先保留干净解码输出，统一旁路大部分后处理',
        pageId: _playerSettingsMpvAudioHighFidelityPageId,
        settingKey: _MpvPlayerPageState._mpvSettingAudioHighFidelity,
      ),
      _MpvSettingCategoryEntry(
        title: '动态范围压缩',
        subtitle: '让对白更靠前，夜间播放更稳',
        pageId: _playerSettingsMpvDynamicRangePageId,
        settingKey: _MpvPlayerPageState._mpvSettingDynamicRange,
      ),
      _MpvSettingCategoryEntry(
        title: 'EQ 均衡器',
        subtitle: '调整低频、中频和高频的听感平衡',
        pageId: _playerSettingsMpvAudioEqPageId,
        settingKey: _MpvPlayerPageState._mpvSettingAudioEq,
      ),
      _MpvSettingCategoryEntry(
        title: '峰值限幅',
        subtitle: '防止音量突然过高带来破音',
        pageId: _playerSettingsMpvAudioLimiterPageId,
        settingKey: _MpvPlayerPageState._mpvSettingAudioLimiter,
      ),
      _MpvSettingCategoryEntry(
        title: '低音增强',
        subtitle: '为影院氛围和低频空间感提供支撑',
        pageId: _playerSettingsMpvAudioBassBoostPageId,
        settingKey: _MpvPlayerPageState._mpvSettingAudioBassBoost,
      ),
      _MpvSettingCategoryEntry(
        title: '人声增强',
        subtitle: '让台词和对白更清晰更靠前',
        pageId: _playerSettingsMpvAudioVoiceEnhancePageId,
        settingKey: _MpvPlayerPageState._mpvSettingAudioVoiceEnhance,
      ),
      _MpvSettingCategoryEntry(
        title: '声道混合',
        subtitle: '控制多声道输出取向',
        pageId: _playerSettingsMpvChannelMixPageId,
        settingKey: _MpvPlayerPageState._mpvSettingChannelMix,
      ),
    ],
  );

  _MpvSettingCategory get _mpvCompatibilityCategory => _MpvSettingCategory(
    pageId: _playerSettingsMpvCompatibilityPageId,
    title: '兼容与诊断',
    subtitle: '兼容模式、播放器诊断信息',
    description: '遇到机型兼容或播放异常时，优先从这里排查。',
    entries: const <_MpvSettingCategoryEntry>[
      _MpvSettingCategoryEntry(
        title: '兼容模式',
        subtitle: '遇到黑屏、花屏或异常时切换',
        pageId: _playerSettingsMpvCompatibilityProfilePageId,
        settingKey: _MpvPlayerPageState._mpvSettingCompatibility,
      ),
      _MpvSettingCategoryEntry(
        title: '播放器诊断信息',
        subtitle: '查看当前 codec、输出、色彩和源信息',
        pageId: _playerSettingsVideoInfoPageId,
        trailingLabel: '查看',
      ),
    ],
  );
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

class _MpvSettingPreset {
  final String id;
  final String label;
  final String description;
  final Map<String, String> settings;

  const _MpvSettingPreset({
    required this.id,
    required this.label,
    required this.description,
    required this.settings,
  });
}
