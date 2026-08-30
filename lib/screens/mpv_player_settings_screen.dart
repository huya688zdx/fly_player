import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../playback/settings/mpv_settings_l10n.dart';
import '../playback/settings/mpv_settings_store.dart';
import '../desktop/desktop.dart';
import '../theme/app_theme.dart';
import '../ui/adaptive_text.dart';
import '../ui/layout_adaptive.dart';
import '../ui/app_transitions.dart';
import '../ui/mpv_audio_eq_advanced_panel.dart';
import '../ui/secondary_host_navigation.dart';
import '../utils/app_top_tip.dart';
import '../widgets/common/named_preset_save_dialog.dart';
import 'package:fly_player/widgets/common/bird_loader.dart';

const double _videoAdjustmentMin = -100;
const double _videoAdjustmentMax = 100;

Future<bool> _showMpvPerformanceWarningDialog(
  BuildContext context,
  MpvPerformanceImpactWarning warning,
) async {
  final colors = context.appColors;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: dialogContext.appModalBackgroundColor,
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
            child: Text(AppLocalizations.of(dialogContext).commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppLocalizations.of(dialogContext).mpvContinueEnable),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

MpvSettingCategoryEntry _mpvSettingCategoryEntry(
  BuildContext context,
  String key,
) {
  final l10n = AppLocalizations.of(context);
  final definition = MpvSettingsL10n.definitionByKey(l10n, key);
  return MpvSettingCategoryEntry(
    key: key,
    title: definition?.title ?? l10n.mpvGenericSettingTitle,
    subtitle: definition?.description ?? '',
  );
}

class MpvPlayerSettingsScreen extends StatefulWidget {
  static const String sectionQuickMode = 'quick_mode';
  static const String sectionPicture = 'picture';
  static const String sectionAudio = 'audio';
  static const String sectionPlayback = 'playback';
  static const String sectionCompatibility = 'compatibility';

  final String? initialSection;
  final String? initialSettingKey;

  const MpvPlayerSettingsScreen({
    super.key,
    this.initialSection,
    this.initialSettingKey,
  });

  @override
  State<MpvPlayerSettingsScreen> createState() =>
      _MpvPlayerSettingsScreenState();
}

class MpvPlayerSettingsDestinationScreen extends StatefulWidget {
  final String? section;
  final String? settingKey;

  const MpvPlayerSettingsDestinationScreen({
    super.key,
    this.section,
    this.settingKey,
  });

  @override
  State<MpvPlayerSettingsDestinationScreen> createState() =>
      _MpvPlayerSettingsDestinationScreenState();
}

class _MpvPlayerSettingsDestinationScreenState
    extends State<MpvPlayerSettingsDestinationScreen> {
  final MpvSettingsStore _store = const MpvSettingsStore();
  Map<String, String>? _settings;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final settings = await _store.load();
    if (!mounted) return;
    setState(() => _settings = settings);
  }

  MpvSettingCategory _buildCategory({
    required String id,
    required String title,
    required String subtitle,
    required String description,
    required List<String> keys,
  }) {
    return MpvSettingCategory(
      id: id,
      title: title,
      subtitle: subtitle,
      description: description,
      entries: keys
          .map((key) => _mpvSettingCategoryEntry(context, key))
          .toList(growable: false),
    );
  }

  MpvSettingCategory? _resolveCategory(String section) {
    final l10n = AppLocalizations.of(context);
    return switch (section) {
      MpvPlayerSettingsScreen.sectionPicture => _buildCategory(
        id: 'display_picture_adjust',
        title: l10n.settingsMpvPictureSection,
        subtitle: l10n.mpvPictureCategorySubtitle,
        description: l10n.mpvPictureCategoryDescription,
        keys: const <String>[
          MpvSettingsCatalog.debandKey,
          MpvSettingsCatalog.sharpenKey,
          MpvSettingsCatalog.denoiseKey,
          MpvSettingsCatalog.deinterlaceKey,
          MpvSettingsCatalog.scaleProfileKey,
          MpvSettingsCatalog.hdrModeKey,
          MpvSettingsCatalog.frameInterpolationKey,
        ],
      ),
      MpvPlayerSettingsScreen.sectionAudio => _buildCategory(
        id: 'display_audio_adjust',
        title: l10n.settingsMpvAudioSection,
        subtitle: l10n.mpvAudioCategorySubtitle,
        description: l10n.mpvAudioCategoryDescription,
        keys: const <String>[
          MpvSettingsCatalog.volumeGainKey,
          MpvSettingsCatalog.audioHighFidelityKey,
          MpvSettingsCatalog.dynamicRangeKey,
          MpvSettingsCatalog.audioEqKey,
          MpvSettingsCatalog.audioLimiterKey,
          MpvSettingsCatalog.audioBassBoostKey,
          MpvSettingsCatalog.audioVoiceEnhanceKey,
          MpvSettingsCatalog.channelMixKey,
        ],
      ),
      MpvPlayerSettingsScreen.sectionPlayback => _buildCategory(
        id: 'display_playback_cache',
        title: l10n.settingsMpvPlaybackSection,
        subtitle: l10n.mpvPlaybackCategorySubtitle,
        description: l10n.mpvPlaybackCategoryDescription,
        keys: const <String>[
          MpvSettingsCatalog.videoSyncKey,
          MpvSettingsCatalog.cacheProfileKey,
          MpvSettingsCatalog.cacheSizeMbKey,
        ],
      ),
      MpvPlayerSettingsScreen.sectionCompatibility => _buildCategory(
        id: 'display_compatibility_diagnostics',
        title: l10n.settingsMpvCompatibilitySection,
        subtitle: l10n.mpvCompatibilityCategorySubtitle,
        description: l10n.mpvCompatibilityCategoryDescription,
        keys: const <String>[MpvSettingsCatalog.compatibilityKey],
      ),
      _ => null,
    };
  }

  Widget _buildTarget(Map<String, String> settings) {
    final settingKey = widget.settingKey;
    if (settingKey != null && settingKey.trim().isNotEmpty) {
      final definition = MpvSettingsL10n.definitionByKey(
        AppLocalizations.of(context),
        settingKey,
      );
      if (definition != null) {
        if (definition.key == MpvSettingsCatalog.cacheSizeMbKey) {
          return _MpvCacheSizeScreen(
            definition: definition,
            currentValue: MpvSettingsCatalog.settingValue(
              definition.key,
              settings,
            ),
          );
        }
        if (definition.key == MpvSettingsCatalog.audioEqKey) {
          return _MpvAudioEqChoiceScreen(
            definition: definition,
            currentSettings: settings,
          );
        }
        return _MpvSettingChoiceScreen(
          definition: definition,
          currentValue: MpvSettingsCatalog.settingValue(
            definition.key,
            settings,
          ),
        );
      }
    }
    final section = widget.section;
    if (section != null && section.isNotEmpty) {
      final category = _resolveCategory(section);
      if (category != null && category.id.isNotEmpty) {
        return _MpvSettingCategoryScreen(
          category: category,
          initialSettings: settings,
        );
      }
    }
    return const MpvPlayerSettingsScreen();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null) {
      final colors = context.appColors;
      return Scaffold(
        backgroundColor: colors.backgroundBase,
        body: const Center(child: BirdLoader(size: 120)),
      );
    }
    return _buildTarget(settings);
  }
}

class _MpvPlayerSettingsScreenState extends State<MpvPlayerSettingsScreen> {
  final MpvSettingsStore _store = const MpvSettingsStore();
  Map<String, String> _settings = Map<String, String>.from(
    MpvSettingsCatalog.defaults,
  );
  Map<String, double> _videoAdjustments = Map<String, double>.from(
    MpvSettingsCatalog.videoAdjustmentDefaults,
  );
  List<SavedMpvPreset> _savedPicturePresets = const <SavedMpvPreset>[];
  List<SavedMpvPreset> _savedAudioPresets = const <SavedMpvPreset>[];
  bool _loading = true;
  bool _initialTargetHandled = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
  }

  Future<void> _loadSettings() async {
    final bundle = await _store.loadBundle();
    final savedPicturePresets = await _store.loadSavedPresets(
      SavedMpvPresetKind.picture,
    );
    final savedAudioPresets = await _store.loadSavedPresets(
      SavedMpvPresetKind.audio,
    );
    if (!mounted) return;
    setState(() {
      _settings = bundle.settings;
      _videoAdjustments = bundle.videoAdjustments;
      _savedPicturePresets = savedPicturePresets;
      _savedAudioPresets = savedAudioPresets;
      _loading = false;
    });
    if (!_initialTargetHandled &&
        (widget.initialSection != null || widget.initialSettingKey != null)) {
      _initialTargetHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_openInitialTarget());
      });
    }
  }

  Future<void> _applyBuiltInPreset(
    SavedMpvPresetKind kind,
    MpvSettingPreset preset,
  ) async {
    final next = await _store.applyBuiltInPreset(
      kind,
      preset,
      currentSettings: _settings,
      currentVideoAdjustments: _videoAdjustments,
    );
    if (!mounted) return;
    setState(() {
      _settings = next.settings;
      _videoAdjustments = next.videoAdjustments;
    });
  }

  Future<void> _resetSettings() async {
    final next = await _store.resetAll();
    if (!mounted) return;
    setState(() {
      _settings = next.settings;
      _videoAdjustments = next.videoAdjustments;
    });
  }

  Future<void> _applySavedPreset(SavedMpvPreset preset) async {
    final next = await _store.applySavedPreset(
      preset,
      currentSettings: _settings,
      currentVideoAdjustments: _videoAdjustments,
    );
    if (!mounted) return;
    setState(() {
      _settings = next.settings;
      _videoAdjustments = next.videoAdjustments;
    });
  }

  Future<void> _renameSavedPreset(
    SavedMpvPresetKind kind,
    SavedMpvPreset preset,
  ) async {
    final l10n = AppLocalizations.of(context);
    final result = await showNamedPresetSaveDialog(
      context,
      title: MpvSettingsL10n.presetRenameTitle(l10n, kind),
      initialName: preset.name,
      initialDescription: preset.description,
      nameLabel: MpvSettingsL10n.presetNameLabel(l10n, kind),
      descriptionLabel: l10n.commonRemarkOptional,
      validateName: (name) {
        final presets = kind == SavedMpvPresetKind.picture
            ? _savedPicturePresets
            : _savedAudioPresets;
        for (final item in presets) {
          if (item.id == preset.id) continue;
          if (item.name.trim().toLowerCase() == name.trim().toLowerCase()) {
            return MpvSettingsL10n.presetDuplicateName(l10n, kind);
          }
        }
        return null;
      },
    );
    if (result == null) return;
    await _store.renameSavedPreset(
      kind,
      preset.id,
      name: result.name,
      description: result.description,
    );
    await _loadSettings();
  }

  Future<void> _deleteSavedPreset(
    SavedMpvPresetKind kind,
    SavedMpvPreset preset,
  ) async {
    await _store.deleteSavedPreset(kind, preset.id);
    await _loadSettings();
  }

  Route<void> _buildAutoRoute(
    Widget page, {
    required bool animated,
    bool keepReverseAnimation = false,
  }) {
    if (animated) {
      return AppTransitions.leftToRightPageTurnRoute<void>(page);
    }
    return PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: keepReverseAnimation
          ? const Duration(milliseconds: 220)
          : Duration.zero,
      transitionsBuilder: (_, animation, __, child) {
        if (!keepReverseAnimation) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.linear,
          reverseCurve: Curves.easeInOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.04, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  Future<void> _openInitialTarget() async {
    if (!mounted) return;
    final initialSettingKey = widget.initialSettingKey;
    if (initialSettingKey != null && initialSettingKey.trim().isNotEmpty) {
      final definition = MpvSettingsL10n.definitionByKey(
        AppLocalizations.of(context),
        initialSettingKey,
      );
      if (definition != null) {
        await _replaceWithDefinition(definition);
      }
      return;
    }
    final category = _categoryForInitialSection(widget.initialSection);
    if (category != null) {
      await _replaceWithCategory(category);
    }
  }

  Future<void> _replaceWithCategory(MpvSettingCategory category) async {
    await Navigator.of(context).pushReplacement(
      _buildAutoRoute(
        _MpvSettingCategoryScreen(
          category: category,
          initialSettings: _settings,
        ),
        animated: false,
        keepReverseAnimation: true,
      ),
    );
  }

  Future<void> _replaceWithDefinition(MpvSettingDefinition definition) async {
    late final Widget page;
    if (definition.key == MpvSettingsCatalog.cacheSizeMbKey) {
      page = _MpvCacheSizeScreen(
        definition: definition,
        currentValue: MpvSettingsCatalog.settingValue(
          definition.key,
          _settings,
        ),
      );
    } else if (definition.key == MpvSettingsCatalog.audioEqKey) {
      page = _MpvAudioEqChoiceScreen(
        definition: definition,
        currentSettings: _settings,
      );
    } else {
      page = _MpvSettingChoiceScreen(
        definition: definition,
        currentValue: MpvSettingsCatalog.settingValue(
          definition.key,
          _settings,
        ),
      );
    }
    await Navigator.of(context).pushReplacement(
      _buildAutoRoute(page, animated: false, keepReverseAnimation: true),
    );
  }

  MpvSettingCategory? _categoryForInitialSection(String? section) {
    if (section == null || section.isEmpty) return null;
    for (final category in _displayCategories) {
      if (category.id == _displayCategoryIdForSection(section)) {
        return category;
      }
    }
    return null;
  }

  String? _displayCategoryIdForSection(String section) {
    return switch (section) {
      MpvPlayerSettingsScreen.sectionPicture => _displayPictureCategoryId,
      MpvPlayerSettingsScreen.sectionAudio => _displayAudioCategoryId,
      MpvPlayerSettingsScreen.sectionPlayback => _displayPlaybackCategoryId,
      MpvPlayerSettingsScreen.sectionCompatibility =>
        _displayCompatibilityCategoryId,
      _ => null,
    };
  }

  static const String _displayPictureCategoryId = 'display_picture_adjust';
  static const String _displayAudioCategoryId = 'display_audio_adjust';
  static const String _displayPlaybackCategoryId = 'display_playback_cache';
  static const String _displayCompatibilityCategoryId =
      'display_compatibility_diagnostics';

  List<MpvSettingCategory> get _displayCategories {
    final l10n = AppLocalizations.of(context);
    return <MpvSettingCategory>[
      _buildDisplayCategory(
        id: _displayPictureCategoryId,
        title: l10n.settingsMpvPictureSection,
        subtitle: l10n.mpvPictureCategorySubtitle,
        description: l10n.mpvPictureCategoryDescription,
        keys: const <String>[
          MpvSettingsCatalog.debandKey,
          MpvSettingsCatalog.sharpenKey,
          MpvSettingsCatalog.denoiseKey,
          MpvSettingsCatalog.deinterlaceKey,
          MpvSettingsCatalog.scaleProfileKey,
          MpvSettingsCatalog.hdrModeKey,
          MpvSettingsCatalog.frameInterpolationKey,
        ],
      ),
      _buildDisplayCategory(
        id: _displayAudioCategoryId,
        title: l10n.settingsMpvAudioSection,
        subtitle: l10n.mpvAudioCategorySubtitle,
        description: l10n.mpvAudioCategoryDescription,
        keys: const <String>[
          MpvSettingsCatalog.volumeGainKey,
          MpvSettingsCatalog.audioHighFidelityKey,
          MpvSettingsCatalog.dynamicRangeKey,
          MpvSettingsCatalog.audioEqKey,
          MpvSettingsCatalog.audioLimiterKey,
          MpvSettingsCatalog.audioBassBoostKey,
          MpvSettingsCatalog.audioVoiceEnhanceKey,
          MpvSettingsCatalog.channelMixKey,
        ],
      ),
      _buildDisplayCategory(
        id: _displayPlaybackCategoryId,
        title: l10n.settingsMpvPlaybackSection,
        subtitle: l10n.mpvPlaybackCategorySubtitle,
        description: l10n.mpvPlaybackCategoryDescription,
        keys: const <String>[
          MpvSettingsCatalog.videoSyncKey,
          MpvSettingsCatalog.cacheProfileKey,
          MpvSettingsCatalog.cacheSizeMbKey,
        ],
      ),
      _buildDisplayCategory(
        id: _displayCompatibilityCategoryId,
        title: l10n.settingsMpvCompatibilitySection,
        subtitle: l10n.mpvCompatibilityCategorySubtitle,
        description: l10n.mpvCompatibilityCategoryDescription,
        keys: const <String>[MpvSettingsCatalog.compatibilityKey],
      ),
    ];
  }

  MpvSettingCategory _buildDisplayCategory({
    required String id,
    required String title,
    required String subtitle,
    required String description,
    required List<String> keys,
  }) {
    return MpvSettingCategory(
      id: id,
      title: title,
      subtitle: subtitle,
      description: description,
      entries: keys
          .map((key) => _mpvSettingCategoryEntry(context, key))
          .toList(growable: false),
    );
  }

  SavedMpvPreset? _activeSavedPreset(SavedMpvPresetKind kind) {
    return MpvSettingsCatalog.activeSavedPreset(
      kind,
      kind == SavedMpvPresetKind.picture
          ? _savedPicturePresets
          : _savedAudioPresets,
      settings: _settings,
      videoAdjustments: _videoAdjustments,
    );
  }

  MpvSettingPreset? _activeBuiltInPicturePreset() {
    return MpvSettingsCatalog.activeBuiltInPicturePreset(
      _settings,
      _videoAdjustments,
    );
  }

  MpvSettingPreset? _activeBuiltInAudioPreset() {
    return MpvSettingsCatalog.activeBuiltInAudioPreset(_settings);
  }

  MpvScenePreset? _activeScenePreset() {
    if (_activeSavedPreset(SavedMpvPresetKind.picture) != null ||
        _activeSavedPreset(SavedMpvPresetKind.audio) != null) {
      return null;
    }
    return MpvSettingsCatalog.activeBuiltInScenePreset(
      _settings,
      _videoAdjustments,
    );
  }

  String _picturePresetSummaryLabel() {
    final l10n = AppLocalizations.of(context);
    final savedPreset = _activeSavedPreset(SavedMpvPresetKind.picture);
    if (savedPreset != null) return savedPreset.name;
    final preset = _activeBuiltInPicturePreset();
    if (preset != null) {
      return MpvSettingsL10n.picturePresetLabel(
        l10n,
        preset.id,
        fallback: preset.label,
      );
    }
    final changed =
        MpvSettingsCatalog.changedCount(
          _settings,
          MpvSettingsCatalog.picturePresetKeys,
        ) +
        MpvSettingsCatalog.videoAdjustmentChangedCount(_videoAdjustments);
    return changed == 0
        ? MpvSettingsL10n.defaultLabel(l10n)
        : MpvSettingsL10n.currentCustomLabel(l10n);
  }

  String _audioPresetSummaryLabel() {
    final l10n = AppLocalizations.of(context);
    final savedPreset = _activeSavedPreset(SavedMpvPresetKind.audio);
    if (savedPreset != null) return savedPreset.name;
    final preset = _activeBuiltInAudioPreset();
    if (preset != null) {
      return MpvSettingsL10n.audioPresetLabel(
        l10n,
        preset.id,
        fallback: preset.label,
      );
    }
    final changed = MpvSettingsCatalog.changedCount(
      _settings,
      MpvSettingsCatalog.audioPresetKeys,
    );
    return changed == 0
        ? MpvSettingsL10n.defaultLabel(l10n)
        : MpvSettingsL10n.currentCustomLabel(l10n);
  }

  String _settingsStatusLabel() {
    final l10n = AppLocalizations.of(context);
    final scenePreset = _activeScenePreset();
    if (scenePreset != null) {
      return MpvSettingsL10n.scenePresetLabel(
        l10n,
        scenePreset.id,
        fallback: scenePreset.label,
      );
    }
    final picture = _picturePresetSummaryLabel();
    final audio = _audioPresetSummaryLabel();
    final defaultLabel = MpvSettingsL10n.defaultLabel(l10n);
    if (picture == defaultLabel && audio == defaultLabel) return defaultLabel;
    if (picture == defaultLabel) return audio;
    if (audio == defaultLabel) return picture;
    return '$picture / $audio';
  }

  String _settingsSummaryText() {
    final l10n = AppLocalizations.of(context);
    final scenePreset = _activeScenePreset();
    if (scenePreset != null) {
      return MpvSettingsL10n.scenePresetDescription(
        l10n,
        scenePreset.id,
        fallback: scenePreset.description,
      );
    }
    final parts = <String>[];
    final savedPicture = _activeSavedPreset(SavedMpvPresetKind.picture);
    final builtInPicture = _activeBuiltInPicturePreset();
    final savedAudio = _activeSavedPreset(SavedMpvPresetKind.audio);
    final builtInAudio = _activeBuiltInAudioPreset();
    if (savedPicture != null) {
      parts.add(
        '${MpvSettingsL10n.savedPresetKindLabel(l10n, SavedMpvPresetKind.picture)}: ${savedPicture.description.isEmpty ? savedPicture.name : savedPicture.description}',
      );
    } else if (builtInPicture != null && builtInPicture.id != 'off') {
      parts.add(
        '${MpvSettingsL10n.savedPresetKindLabel(l10n, SavedMpvPresetKind.picture)}: ${MpvSettingsL10n.picturePresetDescription(l10n, builtInPicture.id, fallback: builtInPicture.description)}',
      );
    }
    if (savedAudio != null) {
      parts.add(
        '${MpvSettingsL10n.savedPresetKindLabel(l10n, SavedMpvPresetKind.audio)}: ${savedAudio.description.isEmpty ? savedAudio.name : savedAudio.description}',
      );
    } else if (builtInAudio != null && builtInAudio.id != 'off') {
      parts.add(
        '${MpvSettingsL10n.savedPresetKindLabel(l10n, SavedMpvPresetKind.audio)}: ${MpvSettingsL10n.audioPresetDescription(l10n, builtInAudio.id, fallback: builtInAudio.description)}',
      );
    }
    if (parts.isNotEmpty) return parts.join('  ');
    final labels = <String>[];
    if (MpvSettingsCatalog.videoAdjustmentChangedCount(_videoAdjustments) > 0) {
      for (final entry in MpvSettingsCatalog.videoAdjustmentDefaults.entries) {
        final current = _videoAdjustments[entry.key] ?? entry.value;
        if (current == entry.value) continue;
        labels.add(
          '${MpvSettingsL10n.videoAdjustmentTitle(l10n, entry.key)} ${MpvSettingsCatalog.formatVideoAdjustmentValue(current)}',
        );
        if (labels.length == 3) break;
      }
    }
    for (final definition in MpvSettingsL10n.definitions(l10n)) {
      final current = MpvSettingsCatalog.settingValue(
        definition.key,
        _settings,
      );
      final fallback = MpvSettingsCatalog.defaults[definition.key];
      if (current == fallback) continue;
      labels.add(
        '${definition.shortTitle} ${MpvSettingsL10n.labelForSetting(l10n, definition.key, _settings)}',
      );
      if (labels.length == 3) break;
    }
    final changed =
        MpvSettingsCatalog.changedCount(_settings) +
        MpvSettingsCatalog.videoAdjustmentChangedCount(_videoAdjustments);
    if (changed == 0) return l10n.mpvVideoAdjustAllDefaultSummary;
    return labels.isEmpty
        ? MpvSettingsL10n.changedCount(l10n, changed)
        : '${MpvSettingsL10n.changedCount(l10n, changed)}: ${labels.join(' / ')}';
  }

  // ignore: unused_element
  String _displayCategorySummary(MpvSettingCategory category) {
    final l10n = AppLocalizations.of(context);
    var changed = 0;
    for (final entry in category.entries) {
      final current = MpvSettingsCatalog.settingValue(entry.key, _settings);
      final fallback = MpvSettingsCatalog.defaults[entry.key];
      if (fallback != null && current != fallback) {
        changed += 1;
      }
    }
    if (category.id == _displayAudioCategoryId &&
        _settings[MpvSettingsCatalog.audioHighFidelityKey] == 'on') {
      return changed == 0
          ? l10n.mpvSettingAudioHighFidelityTitle
          : '${l10n.mpvSettingAudioHighFidelityTitle} / ${MpvSettingsL10n.changedCount(l10n, changed)}';
    }
    if (changed == 0) return l10n.mpvDefault;
    return MpvSettingsL10n.changedCount(l10n, changed);
  }

  Future<void> _openCustomManagementScreen() async {
    await Navigator.of(context).push(
      _buildAutoRoute(
        _MpvCustomManagementScreen(
          initialSettings: _settings,
          initialVideoAdjustments: _videoAdjustments,
        ),
        animated: true,
      ),
    );
    await _loadSettings();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final picturePresets = MpvSettingsL10n.builtInPicturePresets(l10n);
    final audioPresets = MpvSettingsL10n.builtInAudioPresets(l10n);
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: buildSecondaryHostAppBar(
        context,
        title: Text(
          l10n.settingsMpvTitle,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: AdaptiveText.roleSize(20, role: AdaptiveFontRole.title),
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: _loading ? null : _resetSettings,
            child: Text(l10n.commonRestoreDefault),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[colors.backgroundElevated, colors.backgroundBase],
          ),
        ),
        child: SafeArea(
          top: false,
          child: _loading
              ? const Center(child: BirdLoader(size: 120))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: <Widget>[
                    _HeroCard(
                      title: l10n.mpvCurrentSchemeTitle,
                      status: _settingsStatusLabel(),
                      summary: _settingsSummaryText(),
                    ),
                    const SizedBox(height: 18),
                    _CardBlock(
                      child: _MenuTile(
                        icon: Icons.tune_rounded,
                        title: l10n.mpvCustomManagementTitle,
                        subtitle: l10n.mpvCustomManagementSubtitle,
                        trailing: _settingsStatusLabel(),
                        onTap: () => unawaited(_openCustomManagementScreen()),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _SectionTitle(title: l10n.mpvPictureQuickPresetTitle),
                    const SizedBox(height: 12),
                    _CardBlock(
                      child: SizedBox(
                        height: 152,
                        child: HoverScrollRow(
                          enabled: MediaLayoutProfile.of(context).isDesktopTier,
                          builder: (controller) => ListView.separated(
                            controller: controller,
                            scrollDirection: Axis.horizontal,
                            itemCount: picturePresets.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, index) {
                              final preset = picturePresets[index];
                              final selected =
                                  _activeSavedPreset(
                                        SavedMpvPresetKind.picture,
                                      ) ==
                                      null &&
                                  _activeBuiltInPicturePreset()?.id ==
                                      preset.id;
                              return _PresetChip(
                                selected: selected,
                                title: preset.label,
                                subtitle: preset.description,
                                onTap: () => _applyBuiltInPreset(
                                  SavedMpvPresetKind.picture,
                                  preset,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_savedPicturePresets.isNotEmpty)
                      SizedBox(
                        height: 166,
                        child: HoverScrollRow(
                          enabled: MediaLayoutProfile.of(context).isDesktopTier,
                          builder: (controller) => ListView.separated(
                            controller: controller,
                            scrollDirection: Axis.horizontal,
                            itemCount: _savedPicturePresets.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, index) {
                              final preset = _savedPicturePresets[index];
                              return _SavedMpvPresetCard(
                                preset: preset,
                                selected:
                                    _activeSavedPreset(
                                      SavedMpvPresetKind.picture,
                                    )?.id ==
                                    preset.id,
                                onApply: () => _applySavedPreset(preset),
                                onRename: () => _renameSavedPreset(
                                  SavedMpvPresetKind.picture,
                                  preset,
                                ),
                                onDelete: () => _deleteSavedPreset(
                                  SavedMpvPresetKind.picture,
                                  preset,
                                ),
                              );
                            },
                          ),
                        ),
                      )
                    else
                      _HintCard(
                        title: l10n.mpvNoSavedPicturePresetTitle,
                        content: l10n.mpvNoSavedPicturePresetContent,
                      ),
                    const SizedBox(height: 18),
                    _SectionTitle(title: l10n.mpvAudioQuickPresetTitle),
                    const SizedBox(height: 12),
                    _CardBlock(
                      child: SizedBox(
                        height: 152,
                        child: HoverScrollRow(
                          enabled: MediaLayoutProfile.of(context).isDesktopTier,
                          builder: (controller) => ListView.separated(
                            controller: controller,
                            scrollDirection: Axis.horizontal,
                            itemCount: audioPresets.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, index) {
                              final preset = audioPresets[index];
                              final selected =
                                  _activeSavedPreset(
                                        SavedMpvPresetKind.audio,
                                      ) ==
                                      null &&
                                  _activeBuiltInAudioPreset()?.id == preset.id;
                              return _PresetChip(
                                selected: selected,
                                title: preset.label,
                                subtitle: preset.description,
                                onTap: () => _applyBuiltInPreset(
                                  SavedMpvPresetKind.audio,
                                  preset,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_savedAudioPresets.isNotEmpty)
                      SizedBox(
                        height: 166,
                        child: HoverScrollRow(
                          enabled: MediaLayoutProfile.of(context).isDesktopTier,
                          builder: (controller) => ListView.separated(
                            controller: controller,
                            scrollDirection: Axis.horizontal,
                            itemCount: _savedAudioPresets.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, index) {
                              final preset = _savedAudioPresets[index];
                              return _SavedMpvPresetCard(
                                preset: preset,
                                selected:
                                    _activeSavedPreset(
                                      SavedMpvPresetKind.audio,
                                    )?.id ==
                                    preset.id,
                                onApply: () => _applySavedPreset(preset),
                                onRename: () => _renameSavedPreset(
                                  SavedMpvPresetKind.audio,
                                  preset,
                                ),
                                onDelete: () => _deleteSavedPreset(
                                  SavedMpvPresetKind.audio,
                                  preset,
                                ),
                              );
                            },
                          ),
                        ),
                      )
                    else
                      _HintCard(
                        title: l10n.mpvNoSavedAudioPresetTitle,
                        content: l10n.mpvNoSavedAudioPresetContent,
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

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

class _MpvCustomManagementScreenState
    extends State<_MpvCustomManagementScreen> {
  final MpvSettingsStore _store = const MpvSettingsStore();

  late Map<String, String> _settings = Map<String, String>.from(
    widget.initialSettings,
  );
  late Map<String, double> _videoAdjustments = Map<String, double>.from(
    widget.initialVideoAdjustments,
  );
  List<SavedMpvPreset> _savedPicturePresets = const <SavedMpvPreset>[];
  List<SavedMpvPreset> _savedAudioPresets = const <SavedMpvPreset>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final bundle = await _store.loadBundle();
    final savedPicturePresets = await _store.loadSavedPresets(
      SavedMpvPresetKind.picture,
    );
    final savedAudioPresets = await _store.loadSavedPresets(
      SavedMpvPresetKind.audio,
    );
    if (!mounted) return;
    setState(() {
      _settings = bundle.settings;
      _videoAdjustments = bundle.videoAdjustments;
      _savedPicturePresets = savedPicturePresets;
      _savedAudioPresets = savedAudioPresets;
      _loading = false;
    });
  }

  String _pictureLabel() {
    final l10n = AppLocalizations.of(context);
    final savedPreset = MpvSettingsCatalog.activeSavedPreset(
      SavedMpvPresetKind.picture,
      _savedPicturePresets,
      settings: _settings,
      videoAdjustments: _videoAdjustments,
    );
    if (savedPreset != null) return savedPreset.name;
    final builtInPreset = MpvSettingsCatalog.activeBuiltInPicturePreset(
      _settings,
      _videoAdjustments,
    );
    if (builtInPreset != null) {
      return MpvSettingsL10n.picturePreset(l10n, builtInPreset).label;
    }
    final changed =
        MpvSettingsCatalog.changedCount(
          _settings,
          MpvSettingsCatalog.picturePresetKeys,
        ) +
        MpvSettingsCatalog.videoAdjustmentChangedCount(_videoAdjustments);
    return changed == 0 ? l10n.mpvDefault : l10n.mpvCurrentCustom;
  }

  String _audioLabel() {
    final l10n = AppLocalizations.of(context);
    final savedPreset = MpvSettingsCatalog.activeSavedPreset(
      SavedMpvPresetKind.audio,
      _savedAudioPresets,
      settings: _settings,
      videoAdjustments: _videoAdjustments,
    );
    if (savedPreset != null) return savedPreset.name;
    final builtInPreset = MpvSettingsCatalog.activeBuiltInAudioPreset(
      _settings,
    );
    if (builtInPreset != null) {
      return MpvSettingsL10n.audioPreset(l10n, builtInPreset).label;
    }
    final changed = MpvSettingsCatalog.changedCount(
      _settings,
      MpvSettingsCatalog.audioPresetKeys,
    );
    return changed == 0 ? l10n.mpvDefault : l10n.mpvCurrentCustom;
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
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: colors.backgroundBase,
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
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[colors.backgroundElevated, colors.backgroundBase],
          ),
        ),
        child: SafeArea(
          top: false,
          child: _loading
              ? const Center(child: BirdLoader(size: 120))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: <Widget>[
                    _HeroCard(
                      title: l10n.mpvCustomManagementTitle,
                      status: l10n.mpvPresetManagementStatus,
                      summary: l10n.mpvPresetManagementSummary,
                      icon: Icons.tune_rounded,
                    ),
                    const SizedBox(height: 18),
                    _CardBlock(
                      child: Column(
                        children: <Widget>[
                          _MenuTile(
                            icon: Icons.movie_filter_outlined,
                            title: l10n.mpvPictureCustomTitle,
                            subtitle: l10n.mpvPictureCustomSubtitle,
                            trailing: _pictureLabel(),
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
                            trailing: _audioLabel(),
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

class _MpvCustomPresetScreenState extends State<_MpvCustomPresetScreen> {
  final MpvSettingsStore _store = const MpvSettingsStore();

  late Map<String, String> _settings = Map<String, String>.from(
    widget.initialSettings,
  );
  late Map<String, double> _videoAdjustments = Map<String, double>.from(
    widget.initialVideoAdjustments,
  );
  List<SavedMpvPreset> _savedPresets = const <SavedMpvPreset>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final bundle = await _store.loadBundle();
    final savedPresets = await _store.loadSavedPresets(widget.kind);
    if (!mounted) return;
    setState(() {
      _settings = bundle.settings;
      _videoAdjustments = bundle.videoAdjustments;
      _savedPresets = savedPresets;
      _loading = false;
    });
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

  SavedMpvPreset? _activeSavedPreset() {
    return MpvSettingsCatalog.activeSavedPreset(
      widget.kind,
      _savedPresets,
      settings: _settings,
      videoAdjustments: _videoAdjustments,
    );
  }

  MpvSettingPreset? _activeBuiltInPreset() {
    return widget.kind == SavedMpvPresetKind.picture
        ? MpvSettingsCatalog.activeBuiltInPicturePreset(
            _settings,
            _videoAdjustments,
          )
        : MpvSettingsCatalog.activeBuiltInAudioPreset(_settings);
  }

  String _statusLabel() {
    final l10n = AppLocalizations.of(context);
    final savedPreset = _activeSavedPreset();
    if (savedPreset != null) return savedPreset.name;
    final builtInPreset = _activeBuiltInPreset();
    if (builtInPreset != null) {
      return widget.kind == SavedMpvPresetKind.picture
          ? MpvSettingsL10n.picturePresetLabel(
              l10n,
              builtInPreset.id,
              fallback: builtInPreset.label,
            )
          : MpvSettingsL10n.audioPresetLabel(
              l10n,
              builtInPreset.id,
              fallback: builtInPreset.label,
            );
    }
    final changed = widget.kind == SavedMpvPresetKind.picture
        ? MpvSettingsCatalog.changedCount(
                _settings,
                MpvSettingsCatalog.picturePresetKeys,
              ) +
              MpvSettingsCatalog.videoAdjustmentChangedCount(_videoAdjustments)
        : MpvSettingsCatalog.changedCount(
            _settings,
            MpvSettingsCatalog.audioPresetKeys,
          );
    return changed == 0
        ? MpvSettingsL10n.defaultLabel(l10n)
        : MpvSettingsL10n.currentCustomLabel(l10n);
  }

  String _summaryText() {
    final l10n = AppLocalizations.of(context);
    final savedPreset = _activeSavedPreset();
    if (savedPreset != null && savedPreset.description.isNotEmpty) {
      return savedPreset.description;
    }
    final builtInPreset = _activeBuiltInPreset();
    if (builtInPreset != null && builtInPreset.id != 'off') {
      return widget.kind == SavedMpvPresetKind.picture
          ? MpvSettingsL10n.picturePresetDescription(
              l10n,
              builtInPreset.id,
              fallback: builtInPreset.description,
            )
          : MpvSettingsL10n.audioPresetDescription(
              l10n,
              builtInPreset.id,
              fallback: builtInPreset.description,
            );
    }
    if (widget.kind == SavedMpvPresetKind.picture) {
      return l10n.mpvPictureCustomDescription;
    }
    return l10n.mpvAudioCustomDescription;
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
        return '${MpvSettingsL10n.videoAdjustmentTitle(l10n, key)} ${MpvSettingsCatalog.formatVideoAdjustmentValue(current)}';
      }
    }
    return MpvSettingsL10n.changedCount(l10n, changed);
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
    await _refresh();
  }

  Future<void> _openVideoAdjustments() async {
    await Navigator.of(context).push(
      AppTransitions.leftToRightPageTurnRoute<void>(
        _MpvVideoAdjustmentsScreen(initialValues: _videoAdjustments),
      ),
    );
    await _refresh();
  }

  Future<String> _suggestedPresetName() async {
    final l10n = AppLocalizations.of(context);
    final builtInPreset = _activeBuiltInPreset();
    final baseName = builtInPreset != null && builtInPreset.id != 'off'
        ? (widget.kind == SavedMpvPresetKind.picture
              ? MpvSettingsL10n.picturePresetLabel(
                  l10n,
                  builtInPreset.id,
                  fallback: builtInPreset.label,
                )
              : MpvSettingsL10n.audioPresetLabel(
                  l10n,
                  builtInPreset.id,
                  fallback: builtInPreset.label,
                ))
        : MpvSettingsL10n.presetDefaultBaseName(l10n, widget.kind);
    return _store.nextSavedPresetNameFromBase(widget.kind, baseName);
  }

  Future<void> _saveCurrentPreset() async {
    final suggestedName = await _suggestedPresetName();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final result = await showNamedPresetSaveDialog(
      context,
      title: widget.kind == SavedMpvPresetKind.picture
          ? l10n.mpvSaveCurrentPictureTitle
          : l10n.mpvSaveCurrentAudioTitle,
      initialName: suggestedName,
      suggestedName: suggestedName,
      nameLabel: MpvSettingsL10n.presetNameLabel(l10n, widget.kind),
      descriptionLabel: l10n.commonRemarkOptional,
      validateName: (name) {
        for (final preset in _savedPresets) {
          if (preset.name.trim().toLowerCase() == name.trim().toLowerCase()) {
            return MpvSettingsL10n.presetDuplicateName(l10n, widget.kind);
          }
        }
        return null;
      },
    );
    if (result == null) return;
    final savedPreset = await _store.savePresetSnapshot(
      kind: widget.kind,
      name: result.name,
      description: result.description,
      settings: _settings,
      videoAdjustments: _videoAdjustments,
    );
    await _refresh();
    if (!mounted) return;
    AppTopTip().show(
      context,
      message: MpvSettingsL10n.presetSavedMessage(
        l10n,
        widget.kind,
        savedPreset.name,
      ),
      color: context.appColors.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final title = widget.kind == SavedMpvPresetKind.picture
        ? l10n.mpvPictureCustomTitle
        : l10n.mpvAudioCustomTitle;
    final saveTitle = widget.kind == SavedMpvPresetKind.picture
        ? l10n.mpvSaveCurrentPictureTitle
        : l10n.mpvSaveCurrentAudioTitle;
    final saveSubtitle = widget.kind == SavedMpvPresetKind.picture
        ? l10n.mpvSaveCurrentPictureSubtitle
        : l10n.mpvSaveCurrentAudioSubtitle;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
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
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[colors.backgroundElevated, colors.backgroundBase],
          ),
        ),
        child: SafeArea(
          top: false,
          child: _loading
              ? const Center(child: BirdLoader(size: 120))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: <Widget>[
                    _HeroCard(
                      title: title,
                      status: _statusLabel(),
                      summary: _summaryText(),
                      icon: widget.kind == SavedMpvPresetKind.picture
                          ? Icons.movie_filter_outlined
                          : Icons.graphic_eq_rounded,
                    ),
                    const SizedBox(height: 18),
                    _CardBlock(
                      child: Column(
                        children: <Widget>[
                          if (widget.kind == SavedMpvPresetKind.picture) ...[
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
                              onTap: () => _openCategory(_categories[index]),
                            ),
                            if (index != _categories.length - 1)
                              const _DividerLine(),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _CardBlock(
                      child: _MenuTile(
                        icon: Icons.bookmark_add_outlined,
                        title: saveTitle,
                        subtitle: saveSubtitle,
                        trailing: l10n.commonSave,
                        onTap: () => unawaited(_saveCurrentPreset()),
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
    if (definition.key == MpvSettingsCatalog.cacheSizeMbKey) {
      await Navigator.of(context).push(
        AppTransitions.leftToRightPageTurnRoute<void>(
          _MpvCacheSizeScreen(
            definition: definition,
            currentValue: MpvSettingsCatalog.settingValue(
              definition.key,
              _settings,
            ),
          ),
        ),
      );
    } else if (definition.key == MpvSettingsCatalog.audioEqKey) {
      await Navigator.of(context).push(
        AppTransitions.leftToRightPageTurnRoute<void>(
          _MpvAudioEqChoiceScreen(
            definition: definition,
            currentSettings: _settings,
          ),
        ),
      );
    } else {
      await Navigator.of(context).push(
        AppTransitions.leftToRightPageTurnRoute<void>(
          _MpvSettingChoiceScreen(
            definition: definition,
            currentValue: MpvSettingsCatalog.settingValue(
              definition.key,
              _settings,
            ),
          ),
        ),
      );
    }
    final next = await _store.load();
    if (!mounted) return;
    setState(() => _settings = next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: colors.backgroundBase,
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
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[colors.backgroundElevated, colors.backgroundBase],
          ),
        ),
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: <Widget>[
              _HeroCard(
                title: widget.category.title,
                status: MpvSettingsL10n.categorySummaryLabel(
                  l10n,
                  widget.category,
                  _settings,
                ),
                summary: widget.category.description,
                icon: Icons.tune_rounded,
              ),
              const SizedBox(height: 18),
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
                          _openDefinition(definition);
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
    return Scaffold(
      backgroundColor: colors.backgroundBase,
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
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[colors.backgroundElevated, colors.backgroundBase],
          ),
        ),
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: <Widget>[
              _HeroCard(
                title: widget.definition.helperLabel,
                status: MpvSettingsL10n.labelForSetting(
                  l10n,
                  widget.definition.key,
                  <String, String>{widget.definition.key: _currentValue},
                ),
                summary: widget.definition.description,
                icon: Icons.tune_rounded,
              ),
              const SizedBox(height: 18),
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
    return Scaffold(
      backgroundColor: colors.backgroundBase,
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
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[colors.backgroundElevated, colors.backgroundBase],
          ),
        ),
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: <Widget>[
              _HeroCard(
                title: widget.definition.helperLabel,
                status: MpvSettingsL10n.labelForSetting(
                  l10n,
                  widget.definition.key,
                  _currentSettings,
                ),
                summary: widget.definition.description,
                icon: Icons.graphic_eq_rounded,
              ),
              const SizedBox(height: 18),
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
              const SizedBox(height: 18),
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
    return Scaffold(
      backgroundColor: colors.backgroundBase,
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
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[colors.backgroundElevated, colors.backgroundBase],
          ),
        ),
        child: SafeArea(
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
    return Scaffold(
      backgroundColor: colors.backgroundBase,
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
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[colors.backgroundElevated, colors.backgroundBase],
          ),
        ),
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: <Widget>[
              _HeroCard(
                title: widget.definition.helperLabel,
                status: _auto
                    ? l10n.mpvOptionAuto
                    : MpvSettingsCatalog.formatCachePercentLabel(
                        selectedPercent,
                      ),
                summary: widget.definition.description,
                icon: Icons.storage_rounded,
              ),
              const SizedBox(height: 18),
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
    return Scaffold(
      backgroundColor: colors.backgroundBase,
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
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[colors.backgroundElevated, colors.backgroundBase],
          ),
        ),
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: <Widget>[
              _HeroCard(
                title: l10n.mpvInstantAdjustTitle,
                status: MpvSettingsL10n.changedCount(
                  l10n,
                  MpvSettingsCatalog.videoAdjustmentChangedCount(_values),
                ),
                summary: l10n.mpvVideoAdjustDescription,
                icon: Icons.tune_rounded,
              ),
              const SizedBox(height: 18),
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

class _HeroCard extends StatelessWidget {
  final String title;
  final String status;
  final String summary;
  final IconData icon;

  const _HeroCard({
    required this.title,
    required this.status,
    required this.summary,
    this.icon = Icons.tune_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[colors.surfaceSubtle, colors.backgroundElevated],
        ),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: colors.surfaceStrong,
              borderRadius: BorderRadius.circular(18),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: colors.textPrimary, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: AdaptiveText.roleSize(
                            18,
                            role: AdaptiveFontRole.title,
                          ),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _StatusBadge(label: status),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  summary,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: AdaptiveText.roleSize(13.8),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;

  const _StatusBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.accentSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.accentStrong,
          fontSize: AdaptiveText.roleSize(12.5),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CardBlock extends StatelessWidget {
  final Widget child;

  const _CardBlock({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: TextStyle(
          color: context.appColors.textPrimary,
          fontSize: AdaptiveText.roleSize(15.5),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PresetChip({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 260,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? colors.accentSoft : colors.backgroundElevated,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? colors.accent : colors.borderSubtle,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: selected ? colors.accentStrong : colors.textMuted,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: AdaptiveText.roleSize(15),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: AdaptiveText.roleSize(13.2),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedMpvPresetCard extends StatelessWidget {
  final SavedMpvPreset preset;
  final bool selected;
  final VoidCallback onApply;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _SavedMpvPresetCard({
    required this.preset,
    required this.selected,
    required this.onApply,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onApply,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 260,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? colors.accentSoft : colors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? colors.accent : colors.borderSubtle,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    preset.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: AdaptiveText.roleSize(15),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'rename') {
                      onRename();
                      return;
                    }
                    if (value == 'delete') {
                      onDelete();
                    }
                  },
                  itemBuilder: (_) => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'rename',
                      child: Text(l10n.commonRename),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text(l10n.commonDelete),
                    ),
                  ],
                  icon: Icon(Icons.more_horiz_rounded, color: colors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              preset.description.isEmpty
                  ? l10n.mpvSavedPresetDefaultDescription
                  : preset.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: AdaptiveText.roleSize(13.1),
                height: 1.4,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? colors.accent : colors.backgroundElevated,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                selected ? l10n.mpvPresetApplied : l10n.mpvTapToApply,
                style: TextStyle(
                  color: selected ? colors.textPrimary : colors.textSecondary,
                  fontSize: AdaptiveText.roleSize(12.4),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colors.backgroundElevated,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: colors.textPrimary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: AdaptiveText.roleSize(15.5),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: AdaptiveText.roleSize(13.2),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 88),
              child: Text(
                trailing,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: AdaptiveText.roleSize(12.8),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              color: colors.textMuted,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onInfoTap;

  const _ChoiceTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.onInfoTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? colors.accent : colors.borderSubtle,
            ),
            color: selected ? colors.accentSoft : colors.surface,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? colors.accentStrong : colors.textMuted,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: AdaptiveText.roleSize(15.5),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (onInfoTap != null) ...[
                          const SizedBox(width: 10),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onInfoTap,
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: colors.accent),
                                color: colors.accentSoft,
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.help_outline_rounded,
                                color: colors.accentStrong,
                                size: 16,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: AdaptiveText.roleSize(12.8),
                        height: 1.35,
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

class _HintCard extends StatelessWidget {
  final String title;
  final String content;

  const _HintCard({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: AdaptiveText.roleSize(15.5),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: AdaptiveText.roleSize(13.4),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoAdjustmentSliderCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _VideoAdjustmentSliderCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final safeValue = value.clamp(_videoAdjustmentMin, _videoAdjustmentMax);
    return _CardBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: AdaptiveText.roleSize(15.5),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                MpvSettingsCatalog.formatVideoAdjustmentValue(safeValue),
                style: TextStyle(
                  color: colors.accentStrong,
                  fontSize: AdaptiveText.roleSize(13.4),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: AdaptiveText.roleSize(13.1),
              height: 1.4,
            ),
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
              min: _videoAdjustmentMin,
              max: _videoAdjustmentMax,
              divisions: (_videoAdjustmentMax - _videoAdjustmentMin).round(),
              value: safeValue,
              label: MpvSettingsCatalog.formatVideoAdjustmentValue(safeValue),
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
          Row(
            children: <Widget>[
              Text(
                '-100',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: AdaptiveText.roleSize(12),
                ),
              ),
              const Spacer(),
              Text(
                '+100',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: AdaptiveText.roleSize(12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DividerLine extends StatelessWidget {
  const _DividerLine();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: context.appColors.borderSubtle);
  }
}
