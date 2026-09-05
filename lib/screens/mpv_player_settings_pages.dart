part of 'mpv_player_settings_screen.dart';

/// 自定义管理：画质 / 音频两个自定义编辑入口。
/// 主页面已提供深入调节直达与快速预设，这里只保留编辑器入口与当前状态。
class _MpvCustomManagementScreen extends StatefulWidget {
  final Map<String, String> initialSettings;
  final Map<String, double> initialVideoAdjustments;

  const _MpvCustomManagementScreen({
    required this.initialSettings,
    required this.initialVideoAdjustments,
  });

  @override
  State<_MpvCustomManagementScreen> createState() =>
      _MpvCustomManagementScreenState();
}

class _MpvCustomManagementScreenState extends State<_MpvCustomManagementScreen>
    with _MpvSnapshotMixin {
  @override
  void initState() {
    super.initState();
    _settings = Map<String, String>.from(widget.initialSettings);
    _videoAdjustments = Map<String, double>.from(
      widget.initialVideoAdjustments,
    );
    unawaited(loadSnapshot());
  }

  Future<void> _openCustomPresetScreen(SavedMpvPresetKind kind) async {
    await Navigator.of(context).push(
      AppTransitions.leftToRightPageTurnRoute<void>(
        _MpvCustomPresetScreen(
          kind: kind,
          initialSettings: _settings,
          initialVideoAdjustments: _videoAdjustments,
        ),
      ),
    );
    await loadSnapshot();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return AppAmbientPage(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: buildSecondaryHostAppBar(
          context,
          title: Text(
            l10n.mpvCustomManagementTitle,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: AdaptiveText.roleSize(18, role: AdaptiveFontRole.title),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: _loading
              ? const Center(child: BirdLoader(size: 120))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: <Widget>[
                    _CardBlock(
                      child: Column(
                        children: <Widget>[
                          _MenuTile(
                            icon: Icons.movie_filter_outlined,
                            title: l10n.mpvPictureCustomTitle,
                            subtitle: l10n.mpvPictureCustomSubtitle,
                            trailing: _MpvSchemeSummary.pictureLabel(
                              l10n,
                              settings: _settings,
                              videoAdjustments: _videoAdjustments,
                              savedPresets: _savedPicturePresets,
                            ),
                            onTap: () => unawaited(
                              _openCustomPresetScreen(
                                SavedMpvPresetKind.picture,
                              ),
                            ),
                          ),
                          const _DividerLine(),
                          _MenuTile(
                            icon: Icons.graphic_eq_rounded,
                            title: l10n.mpvAudioCustomTitle,
                            subtitle: l10n.mpvAudioCustomSubtitle,
                            trailing: _MpvSchemeSummary.audioLabel(
                              l10n,
                              settings: _settings,
                              savedPresets: _savedAudioPresets,
                            ),
                            onTap: () => unawaited(
                              _openCustomPresetScreen(SavedMpvPresetKind.audio),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// 自定义编辑页（画质 / 音频）：即时调节（仅画质）+ 分类调整 + 另存当前。
class _MpvCustomPresetScreen extends StatefulWidget {
  final SavedMpvPresetKind kind;
  final Map<String, String> initialSettings;
  final Map<String, double> initialVideoAdjustments;

  const _MpvCustomPresetScreen({
    required this.kind,
    required this.initialSettings,
    required this.initialVideoAdjustments,
  });

  @override
  State<_MpvCustomPresetScreen> createState() => _MpvCustomPresetScreenState();
}

class _MpvCustomPresetScreenState extends State<_MpvCustomPresetScreen>
    with _MpvSnapshotMixin {
  @override
  void initState() {
    super.initState();
    _settings = Map<String, String>.from(widget.initialSettings);
    _videoAdjustments = Map<String, double>.from(
      widget.initialVideoAdjustments,
    );
    unawaited(loadSnapshot());
  }

  List<MpvSettingCategory> get _categories {
    const pictureCategoryIds = <String>{
      MpvSettingsCatalog.videoFiltersCategoryId,
      MpvSettingsCatalog.pictureRenderingCategoryId,
      MpvSettingsCatalog.playbackSyncCategoryId,
      MpvSettingsCatalog.compatibilityCategoryId,
    };
    const audioCategoryIds = <String>{
      MpvSettingsCatalog.audioProcessingCategoryId,
    };
    final allowedIds = widget.kind == SavedMpvPresetKind.picture
        ? pictureCategoryIds
        : audioCategoryIds;
    final l10n = AppLocalizations.of(context);
    return MpvSettingsL10n.categories(l10n)
        .where((category) => allowedIds.contains(category.id))
        .toList(growable: false);
  }

  Future<void> _openCategory(MpvSettingCategory category) async {
    await Navigator.of(context).push(
      AppTransitions.leftToRightPageTurnRoute<void>(
        _MpvSettingCategoryScreen(
          category: category,
          initialSettings: _settings,
        ),
      ),
    );
    await loadSnapshot();
  }

  Future<void> _openVideoAdjustments() async {
    await Navigator.of(context).push(
      AppTransitions.leftToRightPageTurnRoute<void>(
        _MpvVideoAdjustmentsScreen(initialValues: _videoAdjustments),
      ),
    );
    await loadSnapshot();
  }

  String _videoAdjustmentTrailingLabel() {
    final l10n = AppLocalizations.of(context);
    final changed = MpvSettingsCatalog.videoAdjustmentChangedCount(
      _videoAdjustments,
    );
    if (changed == 0) return MpvSettingsL10n.defaultLabel(l10n);
    if (changed == 1) {
      for (final key in MpvSettingsCatalog.videoAdjustmentDefaults.keys) {
        final current =
            _videoAdjustments[key] ??
            MpvSettingsCatalog.videoAdjustmentDefaults[key]!;
        if (current == 0) continue;
        return '${MpvSettingsL10n.videoAdjustmentTitle(l10n, key)} '
            '${MpvSettingsCatalog.formatVideoAdjustmentValue(current)}';
      }
    }
    return MpvSettingsL10n.changedCount(l10n, changed);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final isPicture = widget.kind == SavedMpvPresetKind.picture;
    final title = isPicture
        ? l10n.mpvPictureCustomTitle
        : l10n.mpvAudioCustomTitle;
    final changed = _MpvSchemeSummary.kindChangedCount(
      widget.kind,
      settings: _settings,
      videoAdjustments: _videoAdjustments,
    );
    return AppAmbientPage(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: buildSecondaryHostAppBar(
          context,
          title: Text(
            title,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: AdaptiveText.roleSize(18, role: AdaptiveFontRole.title),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: _loading
              ? const Center(child: BirdLoader(size: 120))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: <Widget>[
                    _SchemeStatusBar(
                      icon: isPicture
                          ? Icons.movie_filter_outlined
                          : Icons.graphic_eq_rounded,
                      scheme: isPicture
                          ? _MpvSchemeSummary.pictureLabel(
                              l10n,
                              settings: _settings,
                              videoAdjustments: _videoAdjustments,
                              savedPresets: _savedPicturePresets,
                            )
                          : _MpvSchemeSummary.audioLabel(
                              l10n,
                              settings: _settings,
                              savedPresets: _savedAudioPresets,
                            ),
                      summary: _MpvSchemeSummary.kindSummaryText(
                        l10n,
                        widget.kind,
                        settings: _settings,
                        videoAdjustments: _videoAdjustments,
                        savedPresets: isPicture
                            ? _savedPicturePresets
                            : _savedAudioPresets,
                      ),
                      pillText: changed == 0
                          ? l10n.mpvDefault
                          : MpvSettingsL10n.changedCount(l10n, changed),
                      pillHot: changed > 0,
                    ),
                    const SizedBox(height: 16),
                    _CardBlock(
                      child: Column(
                        children: <Widget>[
                          if (isPicture) ...<Widget>[
                            _MenuTile(
                              icon: Icons.tune_rounded,
                              title: l10n.mpvInstantAdjustTitle,
                              subtitle: l10n.mpvInstantAdjustSubtitle,
                              trailing: _videoAdjustmentTrailingLabel(),
                              onTap: () => unawaited(_openVideoAdjustments()),
                            ),
                            const _DividerLine(),
                          ],
                          for (
                            var index = 0;
                            index < _categories.length;
                            index++
                          ) ...[
                            _MenuTile(
                              icon: _iconForCustomCategory(
                                _categories[index].id,
                              ),
                              title: _categories[index].title,
                              subtitle: _categories[index].subtitle,
                              trailing: MpvSettingsL10n.categorySummaryLabel(
                                l10n,
                                _categories[index],
                                _settings,
                              ),
                              onTap: () =>
                                  unawaited(_openCategory(_categories[index])),
                            ),
                            if (index != _categories.length - 1)
                              const _DividerLine(),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _CardBlock(
                      child: _MenuTile(
                        icon: Icons.bookmark_add_outlined,
                        title: isPicture
                            ? l10n.mpvSaveCurrentPictureTitle
                            : l10n.mpvSaveCurrentAudioTitle,
                        subtitle: isPicture
                            ? l10n.mpvSaveCurrentPictureSubtitle
                            : l10n.mpvSaveCurrentAudioSubtitle,
                        trailing: l10n.commonSave,
                        onTap: () =>
                            unawaited(saveCurrentPresetFlow(widget.kind)),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  IconData _iconForCustomCategory(String id) {
    return switch (id) {
      MpvSettingsCatalog.videoFiltersCategoryId => Icons.auto_fix_high_rounded,
      MpvSettingsCatalog.pictureRenderingCategoryId =>
        Icons.high_quality_rounded,
      MpvSettingsCatalog.playbackSyncCategoryId => Icons.sync_rounded,
      MpvSettingsCatalog.audioProcessingCategoryId => Icons.graphic_eq_rounded,
      MpvSettingsCatalog.compatibilityCategoryId => Icons.shield_outlined,
      _ => Icons.tune_rounded,
    };
  }
}

/// 设置分类页：单项设置逐行进入对应选择页，头部徽标显示本类变化数。
class _MpvSettingCategoryScreen extends StatefulWidget {
  final MpvSettingCategory category;
  final Map<String, String> initialSettings;

  const _MpvSettingCategoryScreen({
    required this.category,
    required this.initialSettings,
  });

  @override
  State<_MpvSettingCategoryScreen> createState() =>
      _MpvSettingCategoryScreenState();
}

class _MpvSettingCategoryScreenState extends State<_MpvSettingCategoryScreen> {
  final MpvSettingsStore _store = const MpvSettingsStore();
  late Map<String, String> _settings = Map<String, String>.from(
    widget.initialSettings,
  );

  Future<void> _openDefinition(MpvSettingDefinition definition) async {
    final page = switch (definition.key) {
      MpvSettingsCatalog.cacheSizeMbKey => _MpvCacheSizeScreen(
        definition: definition,
        currentValue: MpvSettingsCatalog.settingValue(
          definition.key,
          _settings,
        ),
      ),
      MpvSettingsCatalog.audioEqKey => _MpvAudioEqChoiceScreen(
        definition: definition,
        currentSettings: _settings,
      ),
      _ => _MpvSettingChoiceScreen(
        definition: definition,
        currentValue: MpvSettingsCatalog.settingValue(
          definition.key,
          _settings,
        ),
      ),
    };
    await Navigator.of(
      context,
    ).push(AppTransitions.leftToRightPageTurnRoute<void>(page));
    final next = await _store.load();
    if (!mounted) return;
    setState(() => _settings = next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final changed = _MpvSchemeSummary.categoryChangedCount(
      widget.category,
      settings: _settings,
      videoAdjustments: MpvSettingsCatalog.videoAdjustmentDefaults,
    );
    return AppAmbientPage(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: buildSecondaryHostAppBar(
          context,
          title: Text(
            widget.category.title,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: AdaptiveText.roleSize(19, role: AdaptiveFontRole.title),
              fontWeight: FontWeight.w700,
            ),
          ),
          actions: <Widget>[
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: _MiniPill(
                  text: changed == 0
                      ? l10n.mpvDefault
                      : MpvSettingsL10n.changedCount(l10n, changed),
                  hot: changed > 0,
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: <Widget>[
              _SchemeStatusBar(
                icon: Icons.tune_rounded,
                summary: widget.category.description,
              ),
              const SizedBox(height: 16),
              _CardBlock(
                child: Column(
                  children: <Widget>[
                    for (
                      var index = 0;
                      index < widget.category.entries.length;
                      index++
                    ) ...[
                      _MenuTile(
                        icon: Icons.adjust_rounded,
                        title: widget.category.entries[index].title,
                        subtitle: widget.category.entries[index].subtitle,
                        trailing: MpvSettingsL10n.labelForSetting(
                          l10n,
                          widget.category.entries[index].key,
                          _settings,
                        ),
                        onTap: () {
                          final definition = MpvSettingsL10n.definitionByKey(
                            l10n,
                            widget.category.entries[index].key,
                          );
                          if (definition == null) return;
                          unawaited(_openDefinition(definition));
                        },
                      ),
                      if (index != widget.category.entries.length - 1)
                        const _DividerLine(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
