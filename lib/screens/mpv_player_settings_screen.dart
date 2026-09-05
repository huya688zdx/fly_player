import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../playback/settings/mpv_settings_l10n.dart';
import '../playback/settings/mpv_settings_store.dart';
import '../theme/app_theme.dart';
import '../ui/adaptive_text.dart';
import '../ui/app_transitions.dart';
import '../ui/mpv_audio_eq_advanced_panel.dart';
import '../ui/secondary_host_navigation.dart';
import '../utils/app_top_tip.dart';
import '../widgets/common/app_ambient_page.dart';
import '../widgets/common/bird_loader.dart';
import '../widgets/common/named_preset_save_dialog.dart';

part 'mpv_player_settings_choice_pages.dart';
part 'mpv_player_settings_pages.dart';
part 'mpv_player_settings_widgets.dart';

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

/// 四个显示分类（画面调节 / 音频调节 / 播放与缓存 / 兼容与诊断）的统一构建：
/// 主页面「深入调节」入口、搜索目标路由直跳与分类页共用同一份 key 列表，
/// 不再各自维护重复定义。
class _MpvDisplayCategories {
  static const String pictureId = 'display_picture_adjust';
  static const String audioId = 'display_audio_adjust';
  static const String playbackId = 'display_playback_cache';
  static const String compatibilityId = 'display_compatibility_diagnostics';

  static List<MpvSettingCategory> all(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return <MpvSettingCategory>[
      _build(
        context,
        id: pictureId,
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
      _build(
        context,
        id: audioId,
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
      _build(
        context,
        id: playbackId,
        title: l10n.settingsMpvPlaybackSection,
        subtitle: l10n.mpvPlaybackCategorySubtitle,
        description: l10n.mpvPlaybackCategoryDescription,
        keys: const <String>[
          MpvSettingsCatalog.videoSyncKey,
          MpvSettingsCatalog.cacheProfileKey,
          MpvSettingsCatalog.cacheSizeMbKey,
        ],
      ),
      _build(
        context,
        id: compatibilityId,
        title: l10n.settingsMpvCompatibilitySection,
        subtitle: l10n.mpvCompatibilityCategorySubtitle,
        description: l10n.mpvCompatibilityCategoryDescription,
        keys: const <String>[MpvSettingsCatalog.compatibilityKey],
      ),
    ];
  }

  static MpvSettingCategory? bySection(BuildContext context, String section) {
    final id = switch (section) {
      MpvPlayerSettingsScreen.sectionPicture => pictureId,
      MpvPlayerSettingsScreen.sectionAudio => audioId,
      MpvPlayerSettingsScreen.sectionPlayback => playbackId,
      MpvPlayerSettingsScreen.sectionCompatibility => compatibilityId,
      _ => null,
    };
    if (id == null) return null;
    for (final category in all(context)) {
      if (category.id == id) return category;
    }
    return null;
  }

  static MpvSettingCategory _build(
    BuildContext context, {
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
}

/// 「当前方案」名称 / 摘要 / 变化计数的统一计算。
/// 主页面状态条、分类页徽标、自定义管理 trailing、自定义编辑页共用，
/// 替代原先散落在三个 State 里的重复实现。
abstract final class _MpvSchemeSummary {
  static String pictureLabel(
    AppLocalizations l10n, {
    required Map<String, String> settings,
    required Map<String, double> videoAdjustments,
    required List<SavedMpvPreset> savedPresets,
  }) {
    final savedPreset = MpvSettingsCatalog.activeSavedPreset(
      SavedMpvPresetKind.picture,
      savedPresets,
      settings: settings,
      videoAdjustments: videoAdjustments,
    );
    if (savedPreset != null) return savedPreset.name;
    final builtIn = MpvSettingsCatalog.activeBuiltInPicturePreset(
      settings,
      videoAdjustments,
    );
    if (builtIn != null) {
      return MpvSettingsL10n.picturePresetLabel(
        l10n,
        builtIn.id,
        fallback: builtIn.label,
      );
    }
    final changed =
        MpvSettingsCatalog.changedCount(
          settings,
          MpvSettingsCatalog.picturePresetKeys,
        ) +
        MpvSettingsCatalog.videoAdjustmentChangedCount(videoAdjustments);
    return changed == 0
        ? MpvSettingsL10n.defaultLabel(l10n)
        : MpvSettingsL10n.currentCustomLabel(l10n);
  }

  static String audioLabel(
    AppLocalizations l10n, {
    required Map<String, String> settings,
    required List<SavedMpvPreset> savedPresets,
  }) {
    final savedPreset = MpvSettingsCatalog.activeSavedPreset(
      SavedMpvPresetKind.audio,
      savedPresets,
      settings: settings,
      videoAdjustments: MpvSettingsCatalog.videoAdjustmentDefaults,
    );
    if (savedPreset != null) return savedPreset.name;
    final builtIn = MpvSettingsCatalog.activeBuiltInAudioPreset(settings);
    if (builtIn != null) {
      return MpvSettingsL10n.audioPresetLabel(
        l10n,
        builtIn.id,
        fallback: builtIn.label,
      );
    }
    final changed = MpvSettingsCatalog.changedCount(
      settings,
      MpvSettingsCatalog.audioPresetKeys,
    );
    return changed == 0
        ? MpvSettingsL10n.defaultLabel(l10n)
        : MpvSettingsL10n.currentCustomLabel(l10n);
  }

  /// 画质 + 音频合成后的当前方案名。画质与音频同为“当前自定义”时只显示
  /// 一次（修复原先 “当前自定义 / 当前自定义” 的叠字）。
  static String schemeLabel(
    AppLocalizations l10n, {
    required Map<String, String> settings,
    required Map<String, double> videoAdjustments,
    required List<SavedMpvPreset> savedPicturePresets,
    required List<SavedMpvPreset> savedAudioPresets,
  }) {
    final savedPicture = MpvSettingsCatalog.activeSavedPreset(
      SavedMpvPresetKind.picture,
      savedPicturePresets,
      settings: settings,
      videoAdjustments: videoAdjustments,
    );
    final savedAudio = MpvSettingsCatalog.activeSavedPreset(
      SavedMpvPresetKind.audio,
      savedAudioPresets,
      settings: settings,
      videoAdjustments: MpvSettingsCatalog.videoAdjustmentDefaults,
    );
    if (savedPicture == null && savedAudio == null) {
      final scene = MpvSettingsCatalog.activeBuiltInScenePreset(
        settings,
        videoAdjustments,
      );
      if (scene != null) {
        return MpvSettingsL10n.scenePresetLabel(
          l10n,
          scene.id,
          fallback: scene.label,
        );
      }
    }
    final defaultLabel = MpvSettingsL10n.defaultLabel(l10n);
    final picture = pictureLabel(
      l10n,
      settings: settings,
      videoAdjustments: videoAdjustments,
      savedPresets: savedPicturePresets,
    );
    final audio = audioLabel(
      l10n,
      settings: settings,
      savedPresets: savedAudioPresets,
    );
    if (picture == defaultLabel && audio == defaultLabel) return defaultLabel;
    if (picture == defaultLabel) return audio;
    if (audio == defaultLabel) return picture;
    if (picture == audio) return picture;
    return '$picture / $audio';
  }

  /// 当前方案的一行变化摘要（与 [schemeLabel] 同源的判定次序）。
  static String summaryText(
    AppLocalizations l10n, {
    required Map<String, String> settings,
    required Map<String, double> videoAdjustments,
    required List<SavedMpvPreset> savedPicturePresets,
    required List<SavedMpvPreset> savedAudioPresets,
  }) {
    final savedPicture = MpvSettingsCatalog.activeSavedPreset(
      SavedMpvPresetKind.picture,
      savedPicturePresets,
      settings: settings,
      videoAdjustments: videoAdjustments,
    );
    final savedAudio = MpvSettingsCatalog.activeSavedPreset(
      SavedMpvPresetKind.audio,
      savedAudioPresets,
      settings: settings,
      videoAdjustments: MpvSettingsCatalog.videoAdjustmentDefaults,
    );
    if (savedPicture == null && savedAudio == null) {
      final scene = MpvSettingsCatalog.activeBuiltInScenePreset(
        settings,
        videoAdjustments,
      );
      if (scene != null) {
        return MpvSettingsL10n.scenePresetDescription(
          l10n,
          scene.id,
          fallback: scene.description,
        );
      }
    }
    final parts = <String>[];
    final builtInPicture = MpvSettingsCatalog.activeBuiltInPicturePreset(
      settings,
      videoAdjustments,
    );
    final builtInAudio = MpvSettingsCatalog.activeBuiltInAudioPreset(settings);
    if (savedPicture != null) {
      parts.add(
        '${MpvSettingsL10n.savedPresetKindLabel(l10n, SavedMpvPresetKind.picture)}: '
        '${savedPicture.description.isEmpty ? savedPicture.name : savedPicture.description}',
      );
    } else if (builtInPicture != null && builtInPicture.id != 'off') {
      parts.add(
        '${MpvSettingsL10n.savedPresetKindLabel(l10n, SavedMpvPresetKind.picture)}: '
        '${MpvSettingsL10n.picturePresetDescription(l10n, builtInPicture.id, fallback: builtInPicture.description)}',
      );
    }
    if (savedAudio != null) {
      parts.add(
        '${MpvSettingsL10n.savedPresetKindLabel(l10n, SavedMpvPresetKind.audio)}: '
        '${savedAudio.description.isEmpty ? savedAudio.name : savedAudio.description}',
      );
    } else if (builtInAudio != null && builtInAudio.id != 'off') {
      parts.add(
        '${MpvSettingsL10n.savedPresetKindLabel(l10n, SavedMpvPresetKind.audio)}: '
        '${MpvSettingsL10n.audioPresetDescription(l10n, builtInAudio.id, fallback: builtInAudio.description)}',
      );
    }
    if (parts.isNotEmpty) return parts.join('  ');
    final labels = <String>[];
    if (MpvSettingsCatalog.videoAdjustmentChangedCount(videoAdjustments) > 0) {
      for (final entry in MpvSettingsCatalog.videoAdjustmentDefaults.entries) {
        final current = videoAdjustments[entry.key] ?? entry.value;
        if (current == entry.value) continue;
        labels.add(
          '${MpvSettingsL10n.videoAdjustmentTitle(l10n, entry.key)} '
          '${MpvSettingsCatalog.formatVideoAdjustmentValue(current)}',
        );
        if (labels.length == 3) break;
      }
    }
    for (final definition in MpvSettingsL10n.definitions(l10n)) {
      final current = MpvSettingsCatalog.settingValue(definition.key, settings);
      final fallback = MpvSettingsCatalog.defaults[definition.key];
      if (current == fallback) continue;
      labels.add(
        '${definition.shortTitle} '
        '${MpvSettingsL10n.labelForSetting(l10n, definition.key, settings)}',
      );
      if (labels.length == 3) break;
    }
    final changed =
        MpvSettingsCatalog.changedCount(settings) +
        MpvSettingsCatalog.videoAdjustmentChangedCount(videoAdjustments);
    if (changed == 0) return l10n.mpvVideoAdjustAllDefaultSummary;
    return labels.isEmpty
        ? MpvSettingsL10n.changedCount(l10n, changed)
        : '${MpvSettingsL10n.changedCount(l10n, changed)}: ${labels.join(' / ')}';
  }

  /// 单一方向（画质或音频）的变化摘要，供自定义编辑页使用。
  static String kindSummaryText(
    AppLocalizations l10n,
    SavedMpvPresetKind kind, {
    required Map<String, String> settings,
    required Map<String, double> videoAdjustments,
    required List<SavedMpvPreset> savedPresets,
  }) {
    final savedPreset = MpvSettingsCatalog.activeSavedPreset(
      kind,
      savedPresets,
      settings: settings,
      videoAdjustments: videoAdjustments,
    );
    if (savedPreset != null && savedPreset.description.isNotEmpty) {
      return savedPreset.description;
    }
    final builtInPreset = kind == SavedMpvPresetKind.picture
        ? MpvSettingsCatalog.activeBuiltInPicturePreset(
            settings,
            videoAdjustments,
          )
        : MpvSettingsCatalog.activeBuiltInAudioPreset(settings);
    if (builtInPreset != null && builtInPreset.id != 'off') {
      return kind == SavedMpvPresetKind.picture
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
    return kind == SavedMpvPresetKind.picture
        ? l10n.mpvPictureCustomDescription
        : l10n.mpvAudioCustomDescription;
  }

  /// 单一方向的变化项数（画质方向含即时调节滑杆）。
  static int kindChangedCount(
    SavedMpvPresetKind kind, {
    required Map<String, String> settings,
    required Map<String, double> videoAdjustments,
  }) {
    return kind == SavedMpvPresetKind.picture
        ? MpvSettingsCatalog.changedCount(
                settings,
                MpvSettingsCatalog.picturePresetKeys,
              ) +
              MpvSettingsCatalog.videoAdjustmentChangedCount(videoAdjustments)
        : MpvSettingsCatalog.changedCount(
            settings,
            MpvSettingsCatalog.audioPresetKeys,
          );
  }

  /// 显示分类内的变化项数（画面方向含即时调节滑杆）。
  static int categoryChangedCount(
    MpvSettingCategory category, {
    required Map<String, String> settings,
    required Map<String, double> videoAdjustments,
  }) {
    var changed = 0;
    for (final entry in category.entries) {
      final current = MpvSettingsCatalog.settingValue(entry.key, settings);
      final fallback = MpvSettingsCatalog.defaults[entry.key];
      if (fallback != null && current != fallback) changed += 1;
    }
    if (category.id == _MpvDisplayCategories.pictureId) {
      changed += MpvSettingsCatalog.videoAdjustmentChangedCount(
        videoAdjustments,
      );
    }
    return changed;
  }
}

/// MPV 设置各页共用：设置/已保存预设快照的加载与刷新。
mixin _MpvSnapshotMixin<T extends StatefulWidget> on State<T> {
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

  Future<void> loadSnapshot() async {
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

  /// 把当前设置快照另存为独立预设（主页面 ghost 卡与自定义编辑页共用）。
  Future<void> saveCurrentPresetFlow(SavedMpvPresetKind kind) async {
    final l10n = AppLocalizations.of(context);
    final builtIn = kind == SavedMpvPresetKind.picture
        ? MpvSettingsCatalog.activeBuiltInPicturePreset(
            _settings,
            _videoAdjustments,
          )
        : MpvSettingsCatalog.activeBuiltInAudioPreset(_settings);
    final baseName = builtIn != null && builtIn.id != 'off'
        ? (kind == SavedMpvPresetKind.picture
              ? MpvSettingsL10n.picturePresetLabel(
                  l10n,
                  builtIn.id,
                  fallback: builtIn.label,
                )
              : MpvSettingsL10n.audioPresetLabel(
                  l10n,
                  builtIn.id,
                  fallback: builtIn.label,
                ))
        : MpvSettingsL10n.presetDefaultBaseName(l10n, kind);
    final suggestedName = await _store.nextSavedPresetNameFromBase(
      kind,
      baseName,
    );
    if (!mounted) return;
    final result = await showNamedPresetSaveDialog(
      context,
      title: kind == SavedMpvPresetKind.picture
          ? l10n.mpvSaveCurrentPictureTitle
          : l10n.mpvSaveCurrentAudioTitle,
      initialName: suggestedName,
      suggestedName: suggestedName,
      nameLabel: MpvSettingsL10n.presetNameLabel(l10n, kind),
      descriptionLabel: l10n.commonRemarkOptional,
      validateName: (name) {
        final presets = kind == SavedMpvPresetKind.picture
            ? _savedPicturePresets
            : _savedAudioPresets;
        for (final preset in presets) {
          if (preset.name.trim().toLowerCase() == name.trim().toLowerCase()) {
            return MpvSettingsL10n.presetDuplicateName(l10n, kind);
          }
        }
        return null;
      },
    );
    if (result == null) return;
    final savedPreset = await _store.savePresetSnapshot(
      kind: kind,
      name: result.name,
      description: result.description,
      settings: _settings,
      videoAdjustments: _videoAdjustments,
    );
    await loadSnapshot();
    if (!mounted) return;
    AppTopTip().show(
      context,
      message: MpvSettingsL10n.presetSavedMessage(l10n, kind, savedPreset.name),
      color: context.appColors.success,
    );
  }
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

class _MpvPlayerSettingsScreenState extends State<MpvPlayerSettingsScreen>
    with _MpvSnapshotMixin {
  @override
  void initState() {
    super.initState();
    // 深链目标（搜索直达某分类/某单项）在首帧快照就绪后一次性替换路由。
    unawaited(loadSnapshot().then((_) => _openInitialTarget()));
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
    await loadSnapshot();
  }

  Future<void> _deleteSavedPreset(
    SavedMpvPresetKind kind,
    SavedMpvPreset preset,
  ) async {
    await _store.deleteSavedPreset(kind, preset.id);
    await loadSnapshot();
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
    final category = _MpvDisplayCategories.bySection(
      context,
      widget.initialSection ?? '',
    );
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
    await Navigator.of(context).pushReplacement(
      _buildAutoRoute(page, animated: false, keepReverseAnimation: true),
    );
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
    await loadSnapshot();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final compact = MediaQuery.sizeOf(context).width < 720;
    final changedTotal =
        MpvSettingsCatalog.changedCount(_settings) +
        MpvSettingsCatalog.videoAdjustmentChangedCount(_videoAdjustments);
    return AppAmbientPage(
      child: Scaffold(
        backgroundColor: Colors.transparent,
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
        body: SafeArea(
          top: false,
          child: _loading
              ? const Center(child: BirdLoader(size: 120))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: <Widget>[
                    _SchemeStatusBar(
                      icon: Icons.tune_rounded,
                      label: l10n.mpvCurrentSchemeTitle,
                      scheme: _MpvSchemeSummary.schemeLabel(
                        l10n,
                        settings: _settings,
                        videoAdjustments: _videoAdjustments,
                        savedPicturePresets: _savedPicturePresets,
                        savedAudioPresets: _savedAudioPresets,
                      ),
                      summary: _MpvSchemeSummary.summaryText(
                        l10n,
                        settings: _settings,
                        videoAdjustments: _videoAdjustments,
                        savedPicturePresets: _savedPicturePresets,
                        savedAudioPresets: _savedAudioPresets,
                      ),
                      pillText: changedTotal == 0
                          ? l10n.mpvDefault
                          : MpvSettingsL10n.changedCount(l10n, changedTotal),
                      pillHot: changedTotal > 0,
                    ),
                    const SizedBox(height: 20),
                    _SectionTitle(title: l10n.mpvPictureQuickPresetTitle),
                    const SizedBox(height: 10),
                    _buildPresetRow(
                      compact: compact,
                      kind: SavedMpvPresetKind.picture,
                      builtInPresets: MpvSettingsL10n.builtInPicturePresets(
                        l10n,
                      ),
                      ghostLabel: l10n.mpvSavePictureGhostLabel,
                    ),
                    const SizedBox(height: 20),
                    _SectionTitle(title: l10n.mpvAudioQuickPresetTitle),
                    const SizedBox(height: 10),
                    _buildPresetRow(
                      compact: compact,
                      kind: SavedMpvPresetKind.audio,
                      builtInPresets: MpvSettingsL10n.builtInAudioPresets(l10n),
                      ghostLabel: l10n.mpvSaveAudioGhostLabel,
                    ),
                    const SizedBox(height: 20),
                    _SectionTitle(
                      title: l10n.mpvDeepTuneSectionTitle,
                      subtitle: l10n.mpvDeepTuneSectionSubtitle,
                    ),
                    const SizedBox(height: 10),
                    _buildTuneEntryGrid(l10n: l10n),
                    const SizedBox(height: 20),
                    _MgmtEntryRow(
                      icon: Icons.tune_rounded,
                      title: l10n.mpvCustomManagementTitle,
                      subtitle: l10n.mpvCustomManagementSubtitle,
                      onTap: () => unawaited(_openCustomManagementScreen()),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// 快速预设排：内置 + 已保存 + 「另存当前」虚线卡。
  /// 宽视口换行平铺，窄视口横向滑动（手机形态）。
  Widget _buildPresetRow({
    required bool compact,
    required SavedMpvPresetKind kind,
    required List<MpvSettingPreset> builtInPresets,
    required String ghostLabel,
  }) {
    final l10n = AppLocalizations.of(context);
    final savedPresets = kind == SavedMpvPresetKind.picture
        ? _savedPicturePresets
        : _savedAudioPresets;
    final activeSavedPreset = MpvSettingsCatalog.activeSavedPreset(
      kind,
      savedPresets,
      settings: _settings,
      videoAdjustments: _videoAdjustments,
    );

    Widget builtinChip(MpvSettingPreset preset) {
      final activeBuiltIn = kind == SavedMpvPresetKind.picture
          ? MpvSettingsCatalog.activeBuiltInPicturePreset(
              _settings,
              _videoAdjustments,
            )
          : MpvSettingsCatalog.activeBuiltInAudioPreset(_settings);
      return _PresetChipCard(
        title: preset.label,
        description: preset.description,
        selected: activeSavedPreset == null && activeBuiltIn?.id == preset.id,
        onTap: () => unawaited(_applyBuiltInPreset(kind, preset)),
      );
    }

    Widget savedChip(SavedMpvPreset preset) => _PresetChipCard(
      title: preset.name,
      description: preset.description.isEmpty
          ? l10n.mpvSavedPresetDefaultDescription
          : preset.description,
      selected: activeSavedPreset?.id == preset.id,
      onTap: () => unawaited(_applySavedPreset(preset)),
      menuBuilder: (_) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(value: 'rename', child: Text(l10n.commonRename)),
        PopupMenuItem<String>(value: 'delete', child: Text(l10n.commonDelete)),
      ],
      onMenuSelected: (value) {
        if (value == 'rename') {
          unawaited(_renameSavedPreset(kind, preset));
        } else if (value == 'delete') {
          unawaited(_deleteSavedPreset(kind, preset));
        }
      },
    );

    final chips = <Widget>[
      for (final preset in builtInPresets)
        SizedBox(width: compact ? 178.0 : 196.0, child: builtinChip(preset)),
      for (final preset in savedPresets)
        SizedBox(width: compact ? 178.0 : 196.0, child: savedChip(preset)),
      SizedBox(
        width: compact ? 150.0 : 172.0,
        child: _SavePresetGhostChip(
          label: ghostLabel,
          onTap: () => unawaited(saveCurrentPresetFlow(kind)),
        ),
      ),
    ];
    if (compact) {
      return SizedBox(
        height: 96,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: chips.length,
          separatorBuilder: (_, __) => const SizedBox(width: 9),
          itemBuilder: (_, index) => chips[index],
        ),
      );
    }
    return Wrap(spacing: 9, runSpacing: 9, children: chips);
  }

  /// 深入调节入口：两卡一行（4 个分类恰好两行），行内等高。
  Widget _buildTuneEntryGrid({required AppLocalizations l10n}) {
    Widget entryCard(MpvSettingCategory category) {
      final changed = _MpvSchemeSummary.categoryChangedCount(
        category,
        settings: _settings,
        videoAdjustments: _videoAdjustments,
      );
      return _TuneEntryCard(
        icon: switch (category.id) {
          _MpvDisplayCategories.pictureId => Icons.deblur_rounded,
          _MpvDisplayCategories.audioId => Icons.graphic_eq_rounded,
          _MpvDisplayCategories.playbackId => Icons.bolt_rounded,
          _ => Icons.shield_outlined,
        },
        title: category.title,
        description: category.subtitle,
        pillText: changed == 0
            ? l10n.mpvDefault
            : MpvSettingsL10n.changedCount(l10n, changed),
        pillHot: changed > 0,
        onTap: () => unawaited(
          Navigator.of(context).push(
            _buildAutoRoute(
              _MpvSettingCategoryScreen(
                category: category,
                initialSettings: _settings,
              ),
              animated: true,
            ),
          ),
        ),
      );
    }

    final categories = _MpvDisplayCategories.all(context);
    // IntrinsicHeight：ListView 纵向无界，Row 的 stretch 需要先取行内容高。
    Widget entryRow(
      List<MpvSettingCategory> rowCategories, {
      required bool first,
    }) {
      return Padding(
        padding: EdgeInsets.only(top: first ? 0 : 10),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: entryCard(rowCategories[0])),
              if (rowCategories.length > 1) ...<Widget>[
                const SizedBox(width: 10),
                Expanded(child: entryCard(rowCategories[1])),
              ] else ...<Widget>[const SizedBox(width: 10), const Spacer()],
            ],
          ),
        ),
      );
    }

    final rows = <List<MpvSettingCategory>>[
      for (var index = 0; index < categories.length; index += 2)
        categories.sublist(index, math.min(index + 2, categories.length)),
    ];
    return Column(
      children: <Widget>[
        for (var index = 0; index < rows.length; index++)
          entryRow(rows[index], first: index == 0),
      ],
    );
  }
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
      final category = _MpvDisplayCategories.bySection(context, section);
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
      return AppAmbientPage(
        child: const Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(child: BirdLoader(size: 120)),
        ),
      );
    }
    return _buildTarget(settings);
  }
}
