part of mpv_player_page;

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

    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(title: '弹幕设置', onBack: drawer.popPage),
      padding: EdgeInsets.fromLTRB(
        landscape ? 18 : 14,
        landscape ? safeTop : 12,
        14,
        landscape ? safeBottom : 10,
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const PlaybackSettingsSectionLabel(label: '显示调节'),
          const SizedBox(height: 10),
          _DanmakuPanelCard(
            child: Column(
              children: [
                _DanmakuSliderRow(
                  label: '显示区域',
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
                  label: '不透明度',
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
                  label: '弹幕密度',
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
                  label: '字体大小',
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
                  label: '弹幕速度',
                  trailing: _danmakuSpeedLabel(),
                  slider: _DanmakuDiscreteDotsSlider(
                    values: const <double>[0.7, 0.85, 1.0, 1.25, 1.55],
                    value: const <double>[0.7, 0.85, 1.0, 1.25, 1.55].reduce(
                      (best, candidate) =>
                          (candidate - settings.speed).abs() <
                              (best - settings.speed).abs()
                          ? candidate
                          : best,
                    ),
                    onChanged: (value) {
                      unawaited(_setDanmakuSpeed(value));
                      drawer.refresh();
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const PlaybackSettingsSectionLabel(label: '按弹幕类型屏蔽'),
          const SizedBox(height: 10),
          _DanmakuPanelCard(
            child: Wrap(
              spacing: 12,
              runSpacing: 14,
              children: [
                _DanmakuTypeChip(
                  label: '固定',
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
                  label: '滚动',
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
                  label: '彩色',
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
                  label: '底部',
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
          const PlaybackSettingsSectionLabel(label: '画面防遮挡'),
          const SizedBox(height: 10),
          _DanmakuPanelCard(
            child: Column(
              children: [
                _DanmakuSwitchRow(
                  title: '重复弹幕隐藏',
                  subtitle: '合并高频重复内容，减少同屏密集刷屏。',
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
                  title: '底部字幕区域防遮挡',
                  subtitle: '优先避开字幕所在区域，减少弹幕压住字幕。',
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
                  title: '人像防遮挡',
                  subtitle: '当前先按主体安全区避让，后续再接更细的人像检测。',
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
              ],
            ),
          ),
          const PlaybackSettingsSectionLabel(label: '弹幕来源'),
          const SizedBox(height: 10),
          _DanmakuPanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DanmakuSwitchRow(
                  title: '启用弹幕层',
                  subtitle: '关闭后右上角设置入口会隐藏，仅保留左下角开关。',
                  value: settings.enabled,
                  onChanged: (value) {
                    unawaited(_toggleDanmakuEnabled());
                    drawer.refresh();
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  '当前状态：${_danmakuStatusLabel()}  ·  ${_danmakuSummaryText()}',
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
                const Text(
                  '来源优先级',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '当本地弹幕和网络弹幕都可用时，优先自动载入 ${_danmakuSourcePriorityLabel()}。',
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
                        label: '本地优先',
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
                        label: '网络优先',
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
            title: '已保存弹幕',
            subtitle: _savedLocalDanmakuSources.isEmpty
                ? '统一管理本地弹幕和弹弹play缓存。'
                : '当前已保存 ${_savedLocalDanmakuSources.length} 个弹幕来源。',
            trailingLabel: _savedLocalDanmakuSources.isEmpty
                ? ''
                : '${_savedLocalDanmakuSources.length}',
            onTap: () => drawer.push(_playerSettingsDanmakuSavedPageId),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: '搜索弹幕',
            subtitle: supportsAutoMatch
                ? '通过弹弹play搜索当前番剧和剧集，直接导入网络弹幕。'
                : '通过弹弹play搜索当前片源相关结果，直接导入网络弹幕。',
            trailingLabel: '弹弹play',
            onTap: () {
              _primeDanmakuSearch();
              drawer.push(_playerSettingsDanmakuSearchPageId);
              if (_danmakuSearchResults.isEmpty && !_danmakuSearchLoading) {
                unawaited(_searchDanmaku(drawer));
              }
            },
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: '手动导入弹幕',
            subtitle: '支持本地 XML / JSON 弹幕文件，导入后会替换当前已载入弹幕。',
            trailingLabel: '本地文件',
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
      header: PlayerNestedSheetHeader(title: '手动导入弹幕', onBack: drawer.popPage),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PlaybackSettingsSectionLabel(label: '本地导入'),
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
        .where((item) => item.isLocalFile)
        .toList(growable: false);
    final networkSources = savedSources
        .where((item) => item.isDanDanPlay)
        .toList(growable: false);
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(title: '已保存弹幕', onBack: drawer.popPage),
      child: savedSources.isEmpty
          ? Center(
              child: Text(
                '还没有保存的弹幕来源',
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
                  const PlaybackSettingsSectionLabel(label: '本地弹幕'),
                  const SizedBox(height: 10),
                  _buildSavedDanmakuSourceGroup(drawer, localSources),
                  const SizedBox(height: 16),
                ],
                if (networkSources.isNotEmpty) ...[
                  const PlaybackSettingsSectionLabel(label: '弹弹play'),
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
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(title: '搜索弹幕', onBack: drawer.popPage),
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
                        child: TextField(
                          controller: _danmakuSearchController,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: '输入番剧名称',
                            hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.35),
                              fontSize: 14,
                            ),
                            isDense: true,
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => unawaited(_searchDanmaku(drawer)),
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
                    '当前匹配：${_danmakuSearchContextText()}',
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
                          ? '没有搜索到可用结果'
                          : '请先在配置中填入弹弹play AppId / AppSecret',
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
