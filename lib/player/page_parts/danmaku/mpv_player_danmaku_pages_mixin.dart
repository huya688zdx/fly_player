part of '../../mpv_player_page.dart';

extension _MpvPlayerDanmakuPagesMixin on _MpvPlayerPageState {
  Widget _buildPlaybackSettingsDanmakuPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    final media = MediaQuery.of(context);
    final landscape = media.size.width > media.size.height;
    final safeTop = media.padding.top > 10 ? media.padding.top : 10.0;
    final safeBottom = media.padding.bottom > 10 ? media.padding.bottom : 10.0;
    final settings = _danmakuController.settings;
    final supportsAutoMatch = _danmakuController.supportsAutoMatch;
    final l10n = AppLocalizations.of(context);

    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: l10n.danmakuSettingsTitle,
        onBack: drawer.popPage,
      ),
      padding: EdgeInsets.fromLTRB(
        landscape ? 18 : 14,
        landscape ? safeTop : 12,
        14,
        landscape ? safeBottom : 10,
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsSectionLabel(label: l10n.danmakuDisplaySection),
          const SizedBox(height: 10),
          _DanmakuPanelCard(
            child: Column(
              children: [
                _DanmakuSliderRow(
                  label: l10n.danmakuDisplayArea,
                  trailing: _danmakuAreaLabel(),
                  slider: _DanmakuDiscreteDotsSlider(
                    values: _danmakuAreaPresets,
                    value: _nearestDanmakuAreaPreset(settings.displayAreaRatio),
                    onChanged: (value) {
                      unawaited(_setDanmakuAreaPreset(value));
                      drawer.refresh();
                    },
                  ),
                ),
                const SizedBox(height: 18),
                _DanmakuSliderRow(
                  label: l10n.danmakuOpacity,
                  trailing: _danmakuOpacityLabel(),
                  slider: _DanmakuLineSlider(
                    value: settings.opacity,
                    min: 0.2,
                    max: 1.0,
                    activeColor: context.appColors.accent,
                    onChanged: (value) {
                      unawaited(_setDanmakuOpacity(value));
                      drawer.refresh();
                    },
                  ),
                ),
                const SizedBox(height: 18),
                _DanmakuSliderRow(
                  label: l10n.danmakuDensity,
                  trailing: _danmakuDensityLabel(),
                  slider: _DanmakuLineSlider(
                    value: settings.density,
                    min: 0.2,
                    max: 1.0,
                    activeColor: context.appColors.accent,
                    onChanged: (value) {
                      unawaited(_setDanmakuDensity(value));
                      drawer.refresh();
                    },
                  ),
                ),
                const SizedBox(height: 18),
                _DanmakuSliderRow(
                  label: l10n.danmakuFontSize,
                  trailing: _danmakuFontScaleLabel(),
                  slider: _DanmakuLineSlider(
                    value: settings.fontScale,
                    min: 0.6,
                    max: 1.4,
                    activeColor: context.appColors.accent,
                    onChanged: (value) {
                      unawaited(_setDanmakuFontScale(value));
                      drawer.refresh();
                    },
                  ),
                ),
                const SizedBox(height: 18),
                _DanmakuSliderRow(
                  label: l10n.danmakuFontWeight,
                  trailing: _danmakuThicknessLabel(),
                  slider: _DanmakuDiscreteDotsSlider(
                    values: _danmakuThicknessPresets,
                    value: _nearestDanmakuThicknessPreset(
                      settings.fontThickness,
                    ),
                    onChanged: (value) {
                      unawaited(_setDanmakuFontThickness(value));
                      drawer.refresh();
                    },
                  ),
                ),
                const SizedBox(height: 18),
                _DanmakuSliderRow(
                  label: l10n.danmakuSpeed,
                  trailing: _danmakuSpeedLabel(),
                  slider: _DanmakuLineSlider(
                    value: clampDanmakuSpeed(settings.speed),
                    min: danmakuSpeedMin,
                    max: danmakuSpeedMax,
                    activeColor: context.appColors.accent,
                    onChanged: (value) {
                      unawaited(_setDanmakuSpeed(value));
                      drawer.refresh();
                    },
                  ),
                ),
                if (_useNativeDanmakuRenderer) ...[
                  const SizedBox(height: 18),
                  _DanmakuSliderRow(
                    label: l10n.danmakuFrameRate,
                    trailing: _danmakuFrameRateLabel(),
                    slider: _DanmakuDiscreteDotsSlider(
                      values: _danmakuFrameRatePresets,
                      value: _nearestDanmakuFrameRatePreset(
                        settings.targetFrameRateHz,
                      ).toDouble(),
                      onChanged: (value) {
                        unawaited(_setDanmakuFrameRate(value.round()));
                        drawer.refresh();
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          PlaybackSettingsSectionLabel(label: l10n.danmakuTypeFilterSection),
          const SizedBox(height: 10),
          _DanmakuPanelCard(
            child: Wrap(
              spacing: 12,
              runSpacing: 14,
              children: [
                _DanmakuTypeChip(
                  label: l10n.danmakuTypeFixed,
                  icon: Icons.vertical_align_top_rounded,
                  selected: settings.topEnabled,
                  onTap: () {
                    unawaited(
                      _updateDanmakuSettings(
                        (current) =>
                            current.copyWith(topEnabled: !current.topEnabled),
                      ),
                    );
                    drawer.refresh();
                  },
                ),
                _DanmakuTypeChip(
                  label: l10n.danmakuTypeScroll,
                  icon: Icons.swap_horiz_rounded,
                  selected: settings.scrollEnabled,
                  onTap: () {
                    unawaited(
                      _updateDanmakuSettings(
                        (current) => current.copyWith(
                          scrollEnabled: !current.scrollEnabled,
                        ),
                      ),
                    );
                    drawer.refresh();
                  },
                ),
                _DanmakuTypeChip(
                  label: l10n.danmakuTypeColor,
                  icon: Icons.palette_outlined,
                  selected: settings.colorEnabled,
                  onTap: () {
                    unawaited(
                      _updateDanmakuSettings(
                        (current) => current.copyWith(
                          colorEnabled: !current.colorEnabled,
                        ),
                      ),
                    );
                    drawer.refresh();
                  },
                ),
                _DanmakuTypeChip(
                  label: l10n.danmakuTypeBottom,
                  icon: Icons.vertical_align_bottom_rounded,
                  selected: settings.bottomEnabled,
                  onTap: () {
                    unawaited(
                      _updateDanmakuSettings(
                        (current) => current.copyWith(
                          bottomEnabled: !current.bottomEnabled,
                        ),
                      ),
                    );
                    drawer.refresh();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          PlaybackSettingsSectionLabel(label: l10n.danmakuOcclusionSection),
          const SizedBox(height: 10),
          _DanmakuPanelCard(
            child: Column(
              children: [
                _DanmakuSwitchRow(
                  title: l10n.danmakuHideDuplicateTitle,
                  subtitle: l10n.danmakuHideDuplicateSubtitle,
                  value: settings.hideDuplicate,
                  onChanged: (value) {
                    unawaited(
                      _updateDanmakuSettings(
                        (current) => current.copyWith(hideDuplicate: value),
                      ),
                    );
                    drawer.refresh();
                  },
                ),
                const SizedBox(height: 18),
                _DanmakuSwitchRow(
                  title: l10n.danmakuAvoidSubtitleTitle,
                  subtitle: l10n.danmakuAvoidSubtitleSubtitle,
                  value: settings.avoidSubtitleArea,
                  onChanged: (value) {
                    unawaited(
                      _updateDanmakuSettings(
                        (current) => current.copyWith(avoidSubtitleArea: value),
                      ),
                    );
                    drawer.refresh();
                  },
                ),
                const SizedBox(height: 18),
                _DanmakuSwitchRow(
                  title: l10n.danmakuAvoidCenterTitle,
                  subtitle: l10n.danmakuAvoidCenterSubtitle,
                  value: settings.avoidCenterArea,
                  onChanged: (value) {
                    unawaited(
                      _updateDanmakuSettings(
                        (current) => current.copyWith(avoidCenterArea: value),
                      ),
                    );
                    drawer.refresh();
                  },
                ),
                const SizedBox(height: 18),
                _DanmakuSwitchRow(
                  title: l10n.danmakuNativeRendererTitle,
                  subtitle: l10n.danmakuNativeRendererSubtitle,
                  value: settings.useNativeRenderer,
                  onChanged: (value) {
                    unawaited(_setDanmakuUseNativeRenderer(value));
                    drawer.refresh();
                  },
                ),
                const SizedBox(height: 18),
                _DanmakuSliderRow(
                  label: l10n.danmakuAiSampleInterval,
                  trailing: _danmakuAiSampleIntervalLabel(),
                  slider: _DanmakuDiscreteDotsSlider(
                    values: _danmakuAiSampleIntervalPresets,
                    value: _nearestDanmakuAiSampleIntervalPreset(
                      settings.aiSampleIntervalMs,
                    ),
                    onChanged: (value) {
                      unawaited(_setDanmakuAiSampleInterval(value.round()));
                      drawer.refresh();
                    },
                  ),
                ),
                const SizedBox(height: 18),
                _DanmakuSliderRow(
                  label: l10n.danmakuAiSampleSize,
                  trailing: _danmakuAiInputSizeLabel(),
                  slider: _DanmakuDiscreteDotsSlider(
                    values: _danmakuAiInputWidthPresets,
                    value: _nearestDanmakuAiInputWidthPreset(
                      settings.aiInputWidth,
                    ),
                    onChanged: (value) {
                      unawaited(_setDanmakuAiInputWidth(value.round()));
                      drawer.refresh();
                    },
                  ),
                ),
                const SizedBox(height: 18),
                _SettingsTextBlock(
                  title: _danmakuOcclusionStatusTitle(),
                  subtitle: _danmakuOcclusionStatusSubtitle(),
                ),
              ],
            ),
          ),
          PlaybackSettingsSectionLabel(label: l10n.danmakuSourceSection),
          const SizedBox(height: 10),
          _DanmakuPanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DanmakuSwitchRow(
                  title: l10n.danmakuLayerEnabledTitle,
                  subtitle: l10n.danmakuLayerEnabledSubtitle,
                  value: settings.enabled,
                  onChanged: (value) {
                    unawaited(_toggleDanmakuEnabled());
                    drawer.refresh();
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.danmakuCurrentStatus(
                    _danmakuStatusLabel(),
                    _danmakuSummaryText(),
                  ),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _DanmakuPanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.danmakuSourcePriority,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.danmakuSourcePriorityDescription(
                    _danmakuSourcePriorityLabel(),
                  ),
                  style: TextStyle(
                    color: context.appColors.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _DanmakuPriorityButton(
                        label: l10n.danmakuLocalFirst,
                        selected: settings.preferLocalSource,
                        onTap: () {
                          if (!settings.preferLocalSource) {
                            unawaited(
                              _setDanmakuSourcePriority(
                                preferLocalSource: true,
                              ),
                            );
                          }
                          drawer.refresh();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DanmakuPriorityButton(
                        label: l10n.danmakuNetworkFirst,
                        selected: !settings.preferLocalSource,
                        onTap: () {
                          if (settings.preferLocalSource) {
                            unawaited(
                              _setDanmakuSourcePriority(
                                preferLocalSource: false,
                              ),
                            );
                          }
                          drawer.refresh();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: l10n.danmakuSavedTitle,
            subtitle: _savedLocalDanmakuSources.isEmpty
                ? l10n.danmakuSavedEmptySubtitle
                : l10n.danmakuSavedCountSubtitle(
                    _savedLocalDanmakuSources.length,
                  ),
            trailingLabel: _savedLocalDanmakuSources.isEmpty
                ? ''
                : '${_savedLocalDanmakuSources.length}',
            onTap: () => drawer.push(_playerSettingsDanmakuSavedPageId),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: l10n.danmakuSearchTitle,
            subtitle: supportsAutoMatch
                ? l10n.danmakuSearchAnimeSubtitle
                : l10n.danmakuSearchSourceSubtitle,
            trailingLabel: l10n.danmakuDanDanPlay,
            onTap: () {
              _primeDanmakuSearch();
              drawer.push(_playerSettingsDanmakuSearchPageId);
              final currentContextKey = _danmakuSearchContextKey();
              if (_danmakuAutoSearchAllowed &&
                  !_danmakuSearchLoading &&
                  _danmakuSearchLastCompletedContextKey != currentContextKey) {
                unawaited(_searchDanmaku(drawer, userInitiated: false));
              }
            },
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: l10n.danmakuManualImportTitle,
            subtitle: l10n.danmakuManualImportSubtitle,
            trailingLabel: l10n.danmakuLocalFile,
            onTap: () => drawer.push(_playerSettingsDanmakuImportPageId),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildPlaybackSettingsDanmakuImportPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: AppLocalizations.of(context).danmakuManualImportTitle,
        onBack: drawer.popPage,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PlaybackSettingsSectionLabel(
            label: AppLocalizations.of(context).danmakuLocalImport,
          ),
          const SizedBox(height: 10),
          Expanded(
            child: LocalFileBrowserBody(
              allowedExtensions: const <String>['xml', 'json'],
              onFileSelected: (path) => _importLocalDanmakuFile(drawer, path),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackSettingsDanmakuSavedPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    final savedSources = _savedLocalDanmakuSources;
    final localSources = savedSources
        .where((item) => !item.isDanDanPlay)
        .toList(growable: false);
    final networkSources = savedSources
        .where((item) => item.isDanDanPlay)
        .toList(growable: false);
    final l10n = AppLocalizations.of(context);
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: l10n.danmakuSavedTitle,
        onBack: drawer.popPage,
      ),
      child: savedSources.isEmpty
          ? Center(
              child: Text(
                l10n.danmakuNoSavedSources,
                style: TextStyle(
                  color: context.appColors.textSecondary,
                  fontSize: 14,
                ),
              ),
            )
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                if (localSources.isNotEmpty) ...[
                  PlaybackSettingsSectionLabel(label: l10n.danmakuLocalSource),
                  const SizedBox(height: 10),
                  _buildSavedDanmakuSourceGroup(drawer, localSources),
                  const SizedBox(height: 16),
                ],
                if (networkSources.isNotEmpty) ...[
                  PlaybackSettingsSectionLabel(label: l10n.danmakuDanDanPlay),
                  const SizedBox(height: 10),
                  _buildSavedDanmakuSourceGroup(drawer, networkSources),
                ],
              ],
            ),
    );
  }

  Widget _buildSavedDanmakuSourceGroup(
    PlayerNestedSheetController<void> drawer,
    List<DanmakuSavedSource> sources,
  ) {
    return DecoratedBox(
      decoration: _settingsCardDecoration(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          children: [
            for (var i = 0; i < sources.length; i++) ...[
              _SavedDanmakuSourceTile(
                source: sources[i],
                loading: _danmakuImportingLocalPath == sources[i].sourceKey,
                deleting: _danmakuDeletingLocalPath == sources[i].sourceKey,
                active: _activeDanmakuSourceKey == sources[i].sourceKey,
                onTap: () =>
                    unawaited(_activateSavedLocalDanmaku(drawer, sources[i])),
                onDelete: () =>
                    unawaited(_deleteSavedLocalDanmaku(drawer, sources[i])),
              ),
              if (i != sources.length - 1)
                Divider(height: 14, color: context.appColors.borderSubtle),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPlaybackSettingsDanmakuSearchPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    final results = _danmakuSearchResults;
    final loading = _danmakuSearchLoading;
    final l10n = AppLocalizations.of(context);
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: l10n.danmakuSearchTitle,
        onBack: drawer.popPage,
      ),
      child: Column(
        children: [
          DecoratedBox(
            decoration: _settingsCardDecoration(context),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _danmakuSearchController,
                          builder: (context, value, _) {
                            final hasText = value.text.trim().isNotEmpty;
                            return TextField(
                              controller: _danmakuSearchController,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                hintText: l10n.danmakuSearchHint,
                                hintStyle: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.35),
                                  fontSize: 14,
                                ),
                                isDense: true,
                                border: InputBorder.none,
                                suffixIcon: hasText
                                    ? IconButton(
                                        tooltip: l10n.commonClear,
                                        splashRadius: 18,
                                        onPressed: () {
                                          _danmakuSearchController.clear();
                                          _updatePlayerState(() {
                                            _danmakuSearchResults =
                                                const <
                                                  DanDanPlayEpisodeSearchItem
                                                >[];
                                            _danmakuSearchLastCompletedContextKey =
                                                '';
                                          });
                                          drawer.refresh();
                                        },
                                        icon: Icon(
                                          Icons.close_rounded,
                                          color: Colors.white.withValues(
                                            alpha: 0.6,
                                          ),
                                          size: 18,
                                        ),
                                      )
                                    : null,
                              ),
                              onSubmitted: (_) =>
                                  unawaited(_searchDanmaku(drawer)),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      _DanmakuSearchButton(
                        loading: loading,
                        onTap: () => unawaited(_searchDanmaku(drawer)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.danmakuCurrentMatch(_danmakuSearchContextText()),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.appColors.textSecondary,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: loading
                ? Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: context.appColors.accent,
                      ),
                    ),
                  )
                : results.isEmpty
                ? Center(
                    child: Text(
                      DanDanPlayConfig.configured
                          ? l10n.danmakuNoSearchResults
                          : l10n.danmakuConfigRequired,
                      style: TextStyle(
                        color: context.appColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = results[index];
                      return _DanmakuSearchResultTile(
                        item: item,
                        loading: _danmakuImportingEpisodeId == item.episodeId,
                        onTap: () =>
                            unawaited(_importDanmakuSearchResult(drawer, item)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
