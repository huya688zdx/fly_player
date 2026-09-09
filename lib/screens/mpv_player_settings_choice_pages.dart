part of 'mpv_player_settings_screen.dart';

/// 单项设置选择页。
class _MpvSettingChoiceScreen extends StatefulWidget {
  final MpvSettingDefinition definition;
  final String currentValue;

  const _MpvSettingChoiceScreen({
    required this.definition,
    required this.currentValue,
  });

  @override
  State<_MpvSettingChoiceScreen> createState() =>
      _MpvSettingChoiceScreenState();
}

class _MpvSettingChoiceScreenState extends State<_MpvSettingChoiceScreen> {
  final MpvSettingsStore _store = const MpvSettingsStore();
  late String _currentValue = widget.currentValue;

  Future<bool> _confirmSelection(String value) async {
    if (_currentValue == value) return true;
    final warning = MpvSettingsL10n.performanceWarningForSelection(
      AppLocalizations.of(context),
      widget.definition.key,
      value,
    );
    if (warning == null) return true;
    return _showMpvPerformanceWarningDialog(context, warning);
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
            widget.definition.title,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: AdaptiveText.roleSize(18, role: AdaptiveFontRole.title),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: <Widget>[
              _SchemeStatusBar(
                icon: Icons.tune_rounded,
                summary: widget.definition.description,
                pillText: MpvSettingsL10n.labelForSetting(
                  l10n,
                  widget.definition.key,
                  <String, String>{widget.definition.key: _currentValue},
                ),
                pillHot: true,
              ),
              const SizedBox(height: 16),
              for (
                var index = 0;
                index < widget.definition.options.length;
                index++
              ) ...[
                _ChoiceTile(
                  title: widget.definition.options[index].label,
                  subtitle: widget.definition.options[index].description,
                  onInfoTap:
                      widget.definition.key ==
                          MpvSettingsCatalog.cacheProfileKey
                      ? () => _showCacheProfileHelp(
                          context,
                          widget.definition.options[index].value,
                        )
                      : null,
                  selected:
                      _currentValue == widget.definition.options[index].value,
                  onTap: () async {
                    final nextValue = widget.definition.options[index].value;
                    final confirmed = await _confirmSelection(nextValue);
                    if (!confirmed) return;
                    await _store.saveSetting(widget.definition.key, nextValue);
                    if (!mounted) return;
                    setState(() {
                      _currentValue = nextValue;
                    });
                  },
                ),
                if (index != widget.definition.options.length - 1)
                  const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showCacheProfileHelp(BuildContext context, String value) {
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
          backgroundColor: dialogContext.appModalBackgroundColor,
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
                    color: colors.accentStrong,
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
}

/// 音频 EQ 选择页：预设项直选，「高级自定义」进入多段 EQ 编辑。
class _MpvAudioEqChoiceScreen extends StatefulWidget {
  final MpvSettingDefinition definition;
  final Map<String, String> currentSettings;

  const _MpvAudioEqChoiceScreen({
    required this.definition,
    required this.currentSettings,
  });

  @override
  State<_MpvAudioEqChoiceScreen> createState() =>
      _MpvAudioEqChoiceScreenState();
}

class _MpvAudioEqChoiceScreenState extends State<_MpvAudioEqChoiceScreen> {
  final MpvSettingsStore _store = const MpvSettingsStore();
  late Map<String, String> _currentSettings = Map<String, String>.from(
    widget.currentSettings,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final currentValue = MpvSettingsCatalog.settingValue(
      widget.definition.key,
      _currentSettings,
    );
    final presetOptions = widget.definition.options
        .where(
          (option) => option.value != MpvSettingsCatalog.audioEqCustomValue,
        )
        .toList(growable: false);
    return AppAmbientPage(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: buildSecondaryHostAppBar(
          context,
          title: Text(
            widget.definition.title,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: AdaptiveText.roleSize(18, role: AdaptiveFontRole.title),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: <Widget>[
              _SchemeStatusBar(
                icon: Icons.graphic_eq_rounded,
                summary: widget.definition.description,
                pillText: MpvSettingsL10n.labelForSetting(
                  l10n,
                  widget.definition.key,
                  _currentSettings,
                ),
                pillHot: true,
              ),
              const SizedBox(height: 16),
              _CardBlock(
                child: _MenuTile(
                  icon: Icons.tune_rounded,
                  title: l10n.mpvAudioEqAdvancedTitle,
                  subtitle: l10n.mpvAudioEqAdvancedSubtitle,
                  trailing:
                      currentValue == MpvSettingsCatalog.audioEqCustomValue
                      ? l10n.mpvCurrentlyUsed
                      : l10n.commonEnter,
                  onTap: () async {
                    await Navigator.of(context).push(
                      AppTransitions.leftToRightPageTurnRoute<void>(
                        _MpvAudioEqAdvancedScreen(settings: _currentSettings),
                      ),
                    );
                    final next = await _store.load();
                    if (!mounted) return;
                    setState(() {
                      _currentSettings = next;
                    });
                  },
                ),
              ),
              const SizedBox(height: 16),
              for (var index = 0; index < presetOptions.length; index++) ...[
                _ChoiceTile(
                  title: presetOptions[index].label,
                  subtitle: presetOptions[index].description,
                  selected: currentValue == presetOptions[index].value,
                  onTap: () async {
                    await _store.saveSetting(
                      widget.definition.key,
                      presetOptions[index].value,
                    );
                    if (!mounted) return;
                    setState(() {
                      _currentSettings[widget.definition.key] =
                          presetOptions[index].value;
                    });
                  },
                ),
                if (index != presetOptions.length - 1)
                  const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 多段 EQ 高级编辑页（内容为共享面板 MpvAudioEqAdvancedPanel）。
class _MpvAudioEqAdvancedScreen extends StatefulWidget {
  final Map<String, String> settings;

  const _MpvAudioEqAdvancedScreen({required this.settings});

  @override
  State<_MpvAudioEqAdvancedScreen> createState() =>
      _MpvAudioEqAdvancedScreenState();
}

class _MpvAudioEqAdvancedScreenState extends State<_MpvAudioEqAdvancedScreen> {
  final MpvSettingsStore _store = const MpvSettingsStore();
  late Map<String, String> _settings = Map<String, String>.from(
    widget.settings,
  );

  Future<void> _applyPatch(Map<String, String> patch) async {
    final next = await _store.savePatch(patch);
    if (!mounted) return;
    setState(() => _settings = next);
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
            l10n.mpvAudioEqAdvancedHeader,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: AdaptiveText.roleSize(18, role: AdaptiveFontRole.title),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: <Widget>[
              MpvAudioEqAdvancedPanel(
                settings: _settings,
                onApplyPatch: _applyPatch,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 缓存大小页：自动开关 + 百分比滑杆（含性能确认）。
class _MpvCacheSizeScreen extends StatefulWidget {
  final MpvSettingDefinition definition;
  final String currentValue;

  const _MpvCacheSizeScreen({
    required this.definition,
    required this.currentValue,
  });

  @override
  State<_MpvCacheSizeScreen> createState() => _MpvCacheSizeScreenState();
}

class _MpvCacheSizeScreenState extends State<_MpvCacheSizeScreen> {
  final MpvSettingsStore _store = const MpvSettingsStore();

  late bool _auto = widget.currentValue == 'auto';
  late String _persistedValue = widget.currentValue;
  late double _sliderValue = MpvSettingsCatalog.mbToCachePercent(
    int.tryParse(widget.currentValue) ??
        MpvSettingsCatalog.cacheSizeExtremeMinimumMb,
  ).toDouble();

  void _restorePersistedSliderValue() {
    if (_persistedValue == 'auto') return;
    _sliderValue = MpvSettingsCatalog.mbToCachePercent(
      int.tryParse(_persistedValue) ??
          MpvSettingsCatalog.cacheSizeExtremeMinimumMb,
    ).toDouble();
  }

  Future<bool> _saveCurrentSliderValue() async {
    final normalized = _sliderValue.round().clamp(
      MpvSettingsCatalog.cachePercentSliderMin,
      MpvSettingsCatalog.cachePercentSliderMax,
    );
    final mapped = MpvSettingsCatalog.cachePercentToMb(normalized);
    if (_persistedValue == mapped.toString()) return true;
    final warning = MpvSettingsL10n.performanceWarningForSelection(
      AppLocalizations.of(context),
      MpvSettingsCatalog.cacheSizeMbKey,
      mapped.toString(),
    );
    if (warning != null) {
      final confirmed = await _showMpvPerformanceWarningDialog(
        context,
        warning,
      );
      if (!confirmed) {
        if (mounted) {
          setState(_restorePersistedSliderValue);
        }
        return false;
      }
    }
    await _store.saveSetting(
      MpvSettingsCatalog.cacheSizeMbKey,
      mapped.toString(),
    );
    _persistedValue = mapped.toString();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final selectedPercent = _sliderValue.round().clamp(
      MpvSettingsCatalog.cachePercentSliderMin,
      MpvSettingsCatalog.cachePercentSliderMax,
    );
    return AppAmbientPage(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: buildSecondaryHostAppBar(
          context,
          title: Text(
            widget.definition.title,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: AdaptiveText.roleSize(18, role: AdaptiveFontRole.title),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: <Widget>[
              _SchemeStatusBar(
                icon: Icons.storage_rounded,
                summary: widget.definition.description,
                pillText: _auto
                    ? l10n.mpvOptionAuto
                    : MpvSettingsCatalog.formatCachePercentLabel(
                        selectedPercent,
                      ),
                pillHot: !_auto,
              ),
              const SizedBox(height: 16),
              _CardBlock(
                child: Column(
                  children: <Widget>[
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _auto,
                      onChanged: (value) async {
                        setState(() => _auto = value);
                        if (value) {
                          await _store.saveSetting(
                            MpvSettingsCatalog.cacheSizeMbKey,
                            'auto',
                          );
                          _persistedValue = 'auto';
                        } else {
                          final saved = await _saveCurrentSliderValue();
                          if (!saved && mounted) {
                            setState(() => _auto = true);
                          }
                        }
                      },
                      title: Text(
                        l10n.mpvCacheAutoSwitchTitle,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: AdaptiveText.roleSize(16),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        _auto
                            ? l10n.mpvCacheAutoSwitchAutoSubtitle
                            : l10n.mpvCacheAutoSwitchManualSubtitle,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: AdaptiveText.roleSize(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Opacity(
                      opacity: _auto ? 0.45 : 1,
                      child: IgnorePointer(
                        ignoring: _auto,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    l10n.mpvCacheSliderTitle,
                                    style: TextStyle(
                                      color: colors.textPrimary,
                                      fontSize: AdaptiveText.roleSize(15),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(
                                  MpvSettingsCatalog.formatCachePercentLabel(
                                    selectedPercent,
                                  ),
                                  style: TextStyle(
                                    color: colors.accentStrong,
                                    fontSize: AdaptiveText.roleSize(14),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: colors.accent,
                                inactiveTrackColor: colors.borderStrong,
                                thumbColor: colors.textPrimary,
                                overlayColor: colors.accentSoft,
                                trackHeight: 4,
                              ),
                              child: Slider(
                                min: MpvSettingsCatalog.cachePercentSliderMin
                                    .toDouble(),
                                max: MpvSettingsCatalog.cachePercentSliderMax
                                    .toDouble(),
                                divisions:
                                    MpvSettingsCatalog.cachePercentSliderMax -
                                    MpvSettingsCatalog.cachePercentSliderMin,
                                value: _sliderValue.clamp(
                                  MpvSettingsCatalog.cachePercentSliderMin
                                      .toDouble(),
                                  MpvSettingsCatalog.cachePercentSliderMax
                                      .toDouble(),
                                ),
                                onChanged: (value) {
                                  setState(() => _sliderValue = value);
                                },
                                onChangeEnd: (_) => _saveCurrentSliderValue(),
                              ),
                            ),
                            Row(
                              children: <Widget>[
                                Text(
                                  l10n.mpvCacheSliderMinimum(
                                    MpvSettingsCatalog.formatCachePercentLabel(
                                      MpvSettingsCatalog.cachePercentSliderMin,
                                    ),
                                  ),
                                  style: TextStyle(
                                    color: colors.textSecondary,
                                    fontSize: AdaptiveText.roleSize(12),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  l10n.mpvCacheSliderMaximum(
                                    MpvSettingsCatalog.formatCachePercentLabel(
                                      MpvSettingsCatalog.cachePercentSliderMax,
                                    ),
                                  ),
                                  style: TextStyle(
                                    color: colors.textSecondary,
                                    fontSize: AdaptiveText.roleSize(12),
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
            ],
          ),
        ),
      ),
    );
  }
}

/// 即时调节页：亮度 / 对比度 / 饱和度 / 色相 / Gamma 滑杆。
class _MpvVideoAdjustmentsScreen extends StatefulWidget {
  final Map<String, double> initialValues;

  const _MpvVideoAdjustmentsScreen({required this.initialValues});

  @override
  State<_MpvVideoAdjustmentsScreen> createState() =>
      _MpvVideoAdjustmentsScreenState();
}

class _MpvVideoAdjustmentsScreenState
    extends State<_MpvVideoAdjustmentsScreen> {
  final MpvSettingsStore _store = const MpvSettingsStore();
  late Map<String, double> _values =
      MpvSettingsCatalog.normalizeVideoAdjustments(widget.initialValues);

  Future<void> _saveValues() async {
    final normalized = await _store.saveVideoAdjustments(_values);
    if (!mounted) return;
    setState(() => _values = normalized);
  }

  Future<void> _resetAll() async {
    final normalized = await _store.saveVideoAdjustments(
      MpvSettingsCatalog.videoAdjustmentDefaults,
    );
    if (!mounted) return;
    setState(() => _values = normalized);
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
            l10n.mpvInstantAdjustTitle,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: AdaptiveText.roleSize(18, role: AdaptiveFontRole.title),
              fontWeight: FontWeight.w700,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => unawaited(_resetAll()),
              child: Text(l10n.commonRestoreDefault),
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
                summary: l10n.mpvVideoAdjustDescription,
                pillText: MpvSettingsL10n.changedCount(
                  l10n,
                  MpvSettingsCatalog.videoAdjustmentChangedCount(_values),
                ),
                pillHot:
                    MpvSettingsCatalog.videoAdjustmentChangedCount(_values) > 0,
              ),
              const SizedBox(height: 16),
              for (final key
                  in MpvSettingsCatalog.videoAdjustmentDefaults.keys) ...[
                _VideoAdjustmentSliderCard(
                  title: MpvSettingsL10n.videoAdjustmentTitle(l10n, key),
                  subtitle: MpvSettingsL10n.videoAdjustmentSubtitle(l10n, key),
                  value: _values[key] ?? 0,
                  onChanged: (value) {
                    setState(() {
                      _values[key] = value.clamp(
                        _videoAdjustmentMin,
                        _videoAdjustmentMax,
                      );
                    });
                  },
                  onChangeEnd: (_) => _saveValues(),
                ),
                if (key != MpvSettingsCatalog.videoAdjustmentDefaults.keys.last)
                  const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
