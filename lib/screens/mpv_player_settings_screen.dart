import 'dart:async';

import 'package:flutter/material.dart';

import '../player/stores/mpv_settings_store.dart';
import '../theme/app_theme.dart';
import '../ui/adaptive_text.dart';
import '../ui/app_transitions.dart';
import '../ui/mpv_audio_eq_advanced_panel.dart';
import '../ui/secondary_host_navigation.dart';
import '../utils/app_top_tip.dart';
import '../widgets/common/named_preset_save_dialog.dart';

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
          .map(
            (key) => MpvSettingCategoryEntry(
              key: key,
              title: _settingTitle(key),
              subtitle: _settingSubtitle(key),
            ),
          )
          .toList(growable: false),
    );
  }

  String _settingTitle(String key) {
    return switch (key) {
      MpvSettingsCatalog.debandKey => '去色带',
      MpvSettingsCatalog.sharpenKey => '锐化',
      MpvSettingsCatalog.denoiseKey => '降噪',
      MpvSettingsCatalog.deinterlaceKey => '反交错',
      MpvSettingsCatalog.scaleProfileKey => '缩放算法',
      MpvSettingsCatalog.hdrModeKey => 'HDR 处理',
      MpvSettingsCatalog.frameInterpolationKey => '插帧',
      MpvSettingsCatalog.videoSyncKey => '同步模式',
      MpvSettingsCatalog.cacheProfileKey => '缓存策略',
      MpvSettingsCatalog.cacheSizeMbKey => '缓存大小',
      MpvSettingsCatalog.volumeGainKey => '音量放大',
      MpvSettingsCatalog.audioHighFidelityKey => '高保真模式',
      MpvSettingsCatalog.dynamicRangeKey => '动态范围压缩',
      MpvSettingsCatalog.audioEqKey => 'EQ 均衡器',
      MpvSettingsCatalog.audioLimiterKey => '峰值限幅',
      MpvSettingsCatalog.audioBassBoostKey => '低音增强',
      MpvSettingsCatalog.audioVoiceEnhanceKey => '人声增强',
      MpvSettingsCatalog.channelMixKey => '声道混合',
      MpvSettingsCatalog.compatibilityKey => '兼容模式',
      _ => '调节项',
    };
  }

  String _settingSubtitle(String key) {
    return switch (key) {
      MpvSettingsCatalog.debandKey => '处理渐变断层和暗部条带。',
      MpvSettingsCatalog.sharpenKey => '提升线条和边缘清晰度。',
      MpvSettingsCatalog.denoiseKey => '压制噪点和颗粒感。',
      MpvSettingsCatalog.deinterlaceKey => '适配隔行扫描片源。',
      MpvSettingsCatalog.scaleProfileKey => '控制放大和缩小时的取向。',
      MpvSettingsCatalog.hdrModeKey => '调整 HDR 映射和整体色彩倾向。',
      MpvSettingsCatalog.frameInterpolationKey => '提升运动流畅度，性能开销更高。',
      MpvSettingsCatalog.videoSyncKey => '控制音画同步与刷新率优先级。',
      MpvSettingsCatalog.cacheProfileKey => '按片源和网络环境切换缓存风格。',
      MpvSettingsCatalog.cacheSizeMbKey => '单独调整最大预读缓存上限。',
      MpvSettingsCatalog.volumeGainKey => '提高偏小声音源的输出上限。',
      MpvSettingsCatalog.audioHighFidelityKey => '优先保持干净解码输出，旁路大部分后处理。',
      MpvSettingsCatalog.dynamicRangeKey => '让对白更靠前，夜间播放更稳。',
      MpvSettingsCatalog.audioEqKey => '调整低频、中频和高频的听感平衡。',
      MpvSettingsCatalog.audioLimiterKey => '抑制突发峰值，避免爆音。',
      MpvSettingsCatalog.audioBassBoostKey => '增强低频氛围和下潜感。',
      MpvSettingsCatalog.audioVoiceEnhanceKey => '提升对白和人声清晰度。',
      MpvSettingsCatalog.channelMixKey => '控制多声道输出的下混方式。',
      MpvSettingsCatalog.compatibilityKey => '遇到异常时优先回退到更稳方案。',
      _ => '',
    };
  }

  MpvSettingCategory? _resolveCategory(String section) {
    return switch (section) {
      MpvPlayerSettingsScreen.sectionPicture => _buildCategory(
        id: 'display_picture_adjust',
        title: '画面调节',
        subtitle: '滤镜、渲染、HDR 与插帧',
        description: '围绕画面观感的细项调节，适合按片源逐步细调。',
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
        title: '音频调节',
        subtitle: '音量、EQ、增强与声道混合',
        description: '统一管理音频后处理和高保真模式，避免入口散开。',
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
        title: '播放与缓存',
        subtitle: '同步模式、缓存策略与缓存大小',
        description: '主要影响拖动响应、缓存强度和播放稳定性。',
        keys: const <String>[
          MpvSettingsCatalog.videoSyncKey,
          MpvSettingsCatalog.cacheProfileKey,
          MpvSettingsCatalog.cacheSizeMbKey,
        ],
      ),
      MpvPlayerSettingsScreen.sectionCompatibility => _buildCategory(
        id: 'display_compatibility_diagnostics',
        title: '兼容与诊断',
        subtitle: '兼容模式与排障入口',
        description: '遇到兼容性问题时优先从这里回退和排查。',
        keys: const <String>[MpvSettingsCatalog.compatibilityKey],
      ),
      _ => null,
    };
  }

  Widget _buildTarget(Map<String, String> settings) {
    final settingKey = widget.settingKey;
    if (settingKey != null && settingKey.trim().isNotEmpty) {
      final definition = MpvSettingsCatalog.definitionByKey(settingKey);
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
        body: Center(child: CircularProgressIndicator(color: colors.accent)),
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

  Future<void> _applyScenePreset(MpvScenePreset preset) async {
    final next = await _store.applyScenePreset(
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
    final result = await showNamedPresetSaveDialog(
      context,
      title: '重命名${kind.label}预设',
      initialName: preset.name,
      initialDescription: preset.description,
      nameLabel: '${kind.label}预设名称',
      descriptionLabel: '说明（可选）',
      validateName: (name) {
        final presets = kind == SavedMpvPresetKind.picture
            ? _savedPicturePresets
            : _savedAudioPresets;
        for (final item in presets) {
          if (item.id == preset.id) continue;
          if (item.name.trim().toLowerCase() == name.trim().toLowerCase()) {
            return '${kind.label}预设名称不能重复';
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
      final definition = MpvSettingsCatalog.definitionByKey(initialSettingKey);
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

  List<MpvSettingCategory> get _displayCategories => <MpvSettingCategory>[
    _buildDisplayCategory(
      id: _displayPictureCategoryId,
      title: '画面调节',
      subtitle: '滤镜、渲染、HDR 与插帧',
      description: '围绕画面观感的细项调节，适合按片源逐步细调。',
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
      title: '音频调节',
      subtitle: '音量、EQ、增强与声道混合',
      description: '统一管理音频后处理和高保真模式，避免入口散开。',
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
      title: '播放与缓存',
      subtitle: '同步模式、缓存策略与缓存大小',
      description: '主要影响拖动响应、缓存强度和播放稳定性。',
      keys: const <String>[
        MpvSettingsCatalog.videoSyncKey,
        MpvSettingsCatalog.cacheProfileKey,
        MpvSettingsCatalog.cacheSizeMbKey,
      ],
    ),
    _buildDisplayCategory(
      id: _displayCompatibilityCategoryId,
      title: '兼容与诊断',
      subtitle: '兼容模式与排障入口',
      description: '遇到兼容性问题时优先从这里回退和排查。',
      keys: const <String>[MpvSettingsCatalog.compatibilityKey],
    ),
  ];

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
          .map(
            (key) => MpvSettingCategoryEntry(
              key: key,
              title: _displaySettingTitle(key),
              subtitle: _displaySettingSubtitle(key),
            ),
          )
          .toList(growable: false),
    );
  }

  String _displaySettingTitle(String key) {
    return switch (key) {
      MpvSettingsCatalog.debandKey => '去色带',
      MpvSettingsCatalog.sharpenKey => '锐化',
      MpvSettingsCatalog.denoiseKey => '降噪',
      MpvSettingsCatalog.deinterlaceKey => '反交错',
      MpvSettingsCatalog.scaleProfileKey => '缩放算法',
      MpvSettingsCatalog.hdrModeKey => 'HDR 处理',
      MpvSettingsCatalog.frameInterpolationKey => '插帧',
      MpvSettingsCatalog.videoSyncKey => '同步模式',
      MpvSettingsCatalog.cacheProfileKey => '缓存策略',
      MpvSettingsCatalog.cacheSizeMbKey => '缓存大小',
      MpvSettingsCatalog.volumeGainKey => '音量放大',
      MpvSettingsCatalog.audioHighFidelityKey => '高保真模式',
      MpvSettingsCatalog.dynamicRangeKey => '动态范围压缩',
      MpvSettingsCatalog.audioEqKey => 'EQ 均衡器',
      MpvSettingsCatalog.audioLimiterKey => '峰值限幅',
      MpvSettingsCatalog.audioBassBoostKey => '低音增强',
      MpvSettingsCatalog.audioVoiceEnhanceKey => '人声增强',
      MpvSettingsCatalog.channelMixKey => '声道混合',
      MpvSettingsCatalog.compatibilityKey => '兼容模式',
      _ => '调节项',
    };
  }

  String _displaySettingSubtitle(String key) {
    return switch (key) {
      MpvSettingsCatalog.debandKey => '处理渐变断层和暗部条带。',
      MpvSettingsCatalog.sharpenKey => '提升线条和边缘清晰度。',
      MpvSettingsCatalog.denoiseKey => '压制噪点和颗粒感。',
      MpvSettingsCatalog.deinterlaceKey => '适配隔行扫描片源。',
      MpvSettingsCatalog.scaleProfileKey => '控制放大和缩小时的取向。',
      MpvSettingsCatalog.hdrModeKey => '调整 HDR 映射和整体亮度取向。',
      MpvSettingsCatalog.frameInterpolationKey => '提升运动流畅度，性能开销更高。',
      MpvSettingsCatalog.videoSyncKey => '控制音画同步与刷新率优先级。',
      MpvSettingsCatalog.cacheProfileKey => '按片源和网络环境切换缓存风格。',
      MpvSettingsCatalog.cacheSizeMbKey => '单独调整最大预读缓存上限。',
      MpvSettingsCatalog.volumeGainKey => '提高偏小声音源的输出上限。',
      MpvSettingsCatalog.audioHighFidelityKey => '优先保持干净解码输出，旁路大部分后处理。',
      MpvSettingsCatalog.dynamicRangeKey => '让对白更靠前，夜间播放更稳。',
      MpvSettingsCatalog.audioEqKey => '调整低频、中频和高频的听感平衡。',
      MpvSettingsCatalog.audioLimiterKey => '抑制突发峰值，避免爆音。',
      MpvSettingsCatalog.audioBassBoostKey => '增强低频氛围和下潜感。',
      MpvSettingsCatalog.audioVoiceEnhanceKey => '提升对白和人声清晰度。',
      MpvSettingsCatalog.channelMixKey => '控制多声道输出的下混方式。',
      MpvSettingsCatalog.compatibilityKey => '遇到异常时优先回退到更稳妥方案。',
      _ => '',
    };
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

  String _scenePresetSummaryLabel() {
    final preset = _activeScenePreset();
    if (preset != null) return preset.label;
    if (_settingsStatusLabel() == '默认') return '未使用';
    return '当前组合';
  }

  String _picturePresetSummaryLabel() {
    final savedPreset = _activeSavedPreset(SavedMpvPresetKind.picture);
    if (savedPreset != null) return savedPreset.name;
    final preset = _activeBuiltInPicturePreset();
    if (preset != null) return preset.label;
    final changed =
        MpvSettingsCatalog.changedCount(
          _settings,
          MpvSettingsCatalog.picturePresetKeys,
        ) +
        MpvSettingsCatalog.videoAdjustmentChangedCount(_videoAdjustments);
    return changed == 0 ? '默认' : '当前自定义';
  }

  String _audioPresetSummaryLabel() {
    final savedPreset = _activeSavedPreset(SavedMpvPresetKind.audio);
    if (savedPreset != null) return savedPreset.name;
    final preset = _activeBuiltInAudioPreset();
    if (preset != null) return preset.label;
    final changed = MpvSettingsCatalog.changedCount(
      _settings,
      MpvSettingsCatalog.audioPresetKeys,
    );
    return changed == 0 ? '默认' : '当前自定义';
  }

  String _settingsStatusLabel() {
    final scenePreset = _activeScenePreset();
    if (scenePreset != null) return scenePreset.label;
    final picture = _picturePresetSummaryLabel();
    final audio = _audioPresetSummaryLabel();
    if (picture == '默认' && audio == '默认') return '默认';
    if (picture == '默认') return audio;
    if (audio == '默认') return picture;
    return '$picture / $audio';
  }

  String _settingsSummaryText() {
    final scenePreset = _activeScenePreset();
    if (scenePreset != null) return scenePreset.description;
    final parts = <String>[];
    final savedPicture = _activeSavedPreset(SavedMpvPresetKind.picture);
    final builtInPicture = _activeBuiltInPicturePreset();
    final savedAudio = _activeSavedPreset(SavedMpvPresetKind.audio);
    final builtInAudio = _activeBuiltInAudioPreset();
    if (savedPicture != null) {
      parts.add(
        '画质：${savedPicture.description.isEmpty ? savedPicture.name : savedPicture.description}',
      );
    } else if (builtInPicture != null && builtInPicture.id != 'off') {
      parts.add('画质：${builtInPicture.description}');
    }
    if (savedAudio != null) {
      parts.add(
        '音频：${savedAudio.description.isEmpty ? savedAudio.name : savedAudio.description}',
      );
    } else if (builtInAudio != null && builtInAudio.id != 'off') {
      parts.add('音频：${builtInAudio.description}');
    }
    if (parts.isNotEmpty) return parts.join('  ');
    final labels = <String>[];
    if (MpvSettingsCatalog.videoAdjustmentChangedCount(_videoAdjustments) > 0) {
      for (final entry in MpvSettingsCatalog.videoAdjustmentDefaults.entries) {
        final current = _videoAdjustments[entry.key] ?? entry.value;
        if (current == entry.value) continue;
        labels.add(
          '${MpvSettingsCatalog.videoAdjustmentTitle(entry.key)} ${MpvSettingsCatalog.formatVideoAdjustmentValue(current)}',
        );
        if (labels.length == 3) break;
      }
    }
    for (final definition in MpvSettingsCatalog.definitions) {
      final current = MpvSettingsCatalog.settingValue(
        definition.key,
        _settings,
      );
      final fallback = MpvSettingsCatalog.defaults[definition.key];
      if (current == fallback) continue;
      labels.add(
        '${definition.shortTitle} ${MpvSettingsCatalog.labelForSetting(definition.key, _settings)}',
      );
      if (labels.length == 3) break;
    }
    final changed =
        MpvSettingsCatalog.changedCount(_settings) +
        MpvSettingsCatalog.videoAdjustmentChangedCount(_videoAdjustments);
    if (changed == 0) return '当前使用默认 MPV 参数。';
    return labels.isEmpty
        ? '已调整 $changed 项。'
        : '已调整 $changed 项：${labels.join(' / ')}';
  }

  // ignore: unused_element
  String _displayCategorySummary(MpvSettingCategory category) {
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
      return changed == 0 ? '高保真' : '高保真 / $changed 项';
    }
    if (changed == 0) return '默认';
    return '$changed 项';
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
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: buildSecondaryHostAppBar(
        context,
        title: Text(
          'MPV播放器设置',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: AdaptiveText.roleSize(20, role: AdaptiveFontRole.title),
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: _loading ? null : _resetSettings,
            child: const Text('恢复默认'),
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
              ? Center(child: CircularProgressIndicator(color: colors.accent))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: <Widget>[
                    _HeroCard(
                      title: '当前方案',
                      status: _settingsStatusLabel(),
                      summary: _settingsSummaryText(),
                    ),
                    const SizedBox(height: 18),
                    _CardBlock(
                      child: _MenuTile(
                        icon: Icons.tune_rounded,
                        title: '自定义管理',
                        subtitle: '把画质自定义和音频自定义统一收进三级页面管理，首页只保留快速预设和已保存预设。',
                        trailing: _settingsStatusLabel(),
                        onTap: () => unawaited(_openCustomManagementScreen()),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const _SectionTitle(title: '画质快速预设'),
                    const SizedBox(height: 12),
                    _CardBlock(
                      child: SizedBox(
                        height: 152,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount:
                              MpvSettingsCatalog.builtInPicturePresets.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final preset =
                                MpvSettingsCatalog.builtInPicturePresets[index];
                            final selected =
                                _activeSavedPreset(
                                      SavedMpvPresetKind.picture,
                                    ) ==
                                    null &&
                                _activeBuiltInPicturePreset()?.id == preset.id;
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
                    const SizedBox(height: 14),
                    if (_savedPicturePresets.isNotEmpty)
                      SizedBox(
                        height: 166,
                        child: ListView.separated(
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
                      )
                    else
                      const _HintCard(
                        title: '还没有已保存画质预设',
                        content: '去“画质自定义”里微调即时调节和画质项后，再把喜欢的结果另存下来。',
                      ),
                    const SizedBox(height: 18),
                    const _SectionTitle(title: '音频快速预设'),
                    const SizedBox(height: 12),
                    _CardBlock(
                      child: SizedBox(
                        height: 152,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount:
                              MpvSettingsCatalog.builtInAudioPresets.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final preset =
                                MpvSettingsCatalog.builtInAudioPresets[index];
                            final selected =
                                _activeSavedPreset(SavedMpvPresetKind.audio) ==
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
                    const SizedBox(height: 14),
                    if (_savedAudioPresets.isNotEmpty)
                      SizedBox(
                        height: 166,
                        child: ListView.separated(
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
                      )
                    else
                      const _HintCard(
                        title: '还没有已保存音频预设',
                        content: '去“音频自定义”里把高保真、EQ 和增强调好后，再把常用听感保存成独立预设。',
                      ),
                    const SizedBox(height: 18),
                    const _HintCard(
                      title: '当前自定义',
                      content: '当前自定义会持续保留，已保存预设是独立快照，可应用、重命名和删除。',
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
    if (builtInPreset != null) return builtInPreset.label;
    final changed =
        MpvSettingsCatalog.changedCount(
          _settings,
          MpvSettingsCatalog.picturePresetKeys,
        ) +
        MpvSettingsCatalog.videoAdjustmentChangedCount(_videoAdjustments);
    return changed == 0 ? '默认' : '当前自定义';
  }

  String _audioLabel() {
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
    if (builtInPreset != null) return builtInPreset.label;
    final changed = MpvSettingsCatalog.changedCount(
      _settings,
      MpvSettingsCatalog.audioPresetKeys,
    );
    return changed == 0 ? '默认' : '当前自定义';
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
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: buildSecondaryHostAppBar(
        context,
        title: Text(
          '自定义管理',
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
              ? Center(child: CircularProgressIndicator(color: colors.accent))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: <Widget>[
                    const _HeroCard(
                      title: '自定义管理',
                      status: '三级页面',
                      summary: '首页只保留快速预设和已保存预设，当前画质自定义与音频自定义统一收进这里继续细调、保存和管理。',
                      icon: Icons.tune_rounded,
                    ),
                    const SizedBox(height: 18),
                    _CardBlock(
                      child: Column(
                        children: <Widget>[
                          _MenuTile(
                            icon: Icons.movie_filter_outlined,
                            title: '画质自定义',
                            subtitle: '即时调节、滤镜、HDR、插帧、同步、缓存和兼容项都在这里继续管理。',
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
                            title: '音频自定义',
                            subtitle: '高保真、音量增强、EQ、限幅、低音增强、人声增强和声道混合都在这里继续管理。',
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
    return MpvSettingsCatalog.categories
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
    final savedPreset = _activeSavedPreset();
    if (savedPreset != null) return savedPreset.name;
    final builtInPreset = _activeBuiltInPreset();
    if (builtInPreset != null) return builtInPreset.label;
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
    return changed == 0 ? '默认' : '当前自定义';
  }

  String _summaryText() {
    final savedPreset = _activeSavedPreset();
    if (savedPreset != null && savedPreset.description.isNotEmpty) {
      return savedPreset.description;
    }
    final builtInPreset = _activeBuiltInPreset();
    if (builtInPreset != null && builtInPreset.id != 'off') {
      return builtInPreset.description;
    }
    if (widget.kind == SavedMpvPresetKind.picture) {
      return '即时调节、滤镜、HDR、插帧、同步和缓存都会纳入当前画质自定义，保存后可在播放器抽屉和设置页直接复用。';
    }
    return '高保真、音量增强、EQ、限幅、低音增强、人声增强和声道混合都会纳入当前音频自定义，保存后可快速切换。';
  }

  String _videoAdjustmentTrailingLabel() {
    final changed = MpvSettingsCatalog.videoAdjustmentChangedCount(
      _videoAdjustments,
    );
    if (changed == 0) return '默认';
    if (changed == 1) {
      for (final key in MpvSettingsCatalog.videoAdjustmentDefaults.keys) {
        final current =
            _videoAdjustments[key] ??
            MpvSettingsCatalog.videoAdjustmentDefaults[key]!;
        if (current == 0) continue;
        return '${MpvSettingsCatalog.videoAdjustmentTitle(key)} ${MpvSettingsCatalog.formatVideoAdjustmentValue(current)}';
      }
    }
    return '$changed 项';
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
    final builtInPreset = _activeBuiltInPreset();
    final baseName = builtInPreset != null && builtInPreset.id != 'off'
        ? builtInPreset.label
        : '${widget.kind.label}预设';
    return _store.nextSavedPresetNameFromBase(widget.kind, baseName);
  }

  Future<void> _saveCurrentPreset() async {
    final suggestedName = await _suggestedPresetName();
    if (!mounted) return;
    final result = await showNamedPresetSaveDialog(
      context,
      title: widget.kind == SavedMpvPresetKind.picture ? '保存当前画质' : '保存当前音频',
      initialName: suggestedName,
      suggestedName: suggestedName,
      nameLabel: '${widget.kind.label}预设名称',
      descriptionLabel: '说明（可选）',
      validateName: (name) {
        for (final preset in _savedPresets) {
          if (preset.name.trim().toLowerCase() == name.trim().toLowerCase()) {
            return '${widget.kind.label}预设名称不能重复';
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
      message: '已保存${widget.kind.label}预设：${savedPreset.name}',
      color: context.appColors.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final title = widget.kind == SavedMpvPresetKind.picture ? '画质自定义' : '音频自定义';
    final saveTitle = widget.kind == SavedMpvPresetKind.picture
        ? '保存当前画质'
        : '保存当前音频';
    final saveSubtitle = widget.kind == SavedMpvPresetKind.picture
        ? '将即时调节和画质增强项保存为独立预设，后续可以在播放器抽屉和设置页快速应用。'
        : '将高保真、EQ 和增强项保存为独立预设，后续可以在播放器抽屉和设置页快速应用。';
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
              ? Center(child: CircularProgressIndicator(color: colors.accent))
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
                              title: '即时调节',
                              subtitle: '亮度、对比度、饱和度、Gamma 和色相会一起保存到画质预设中。',
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
                              trailing: MpvSettingsCatalog.categorySummaryLabel(
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
                        trailing: '保存',
                        onTap: () => unawaited(_saveCurrentPreset()),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const _HintCard(
                      title: '当前自定义',
                      content:
                          '当前自定义会持续保留；你保存出来的是独立快照。后续继续微调当前自定义，不会反向覆盖已经保存的预设。',
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
                status: MpvSettingsCatalog.categorySummaryLabel(
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
                        trailing: MpvSettingsCatalog.labelForSetting(
                          widget.category.entries[index].key,
                          _settings,
                        ),
                        onTap: () {
                          final definition = MpvSettingsCatalog.definitionByKey(
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
    final warning = MpvSettingsCatalog.performanceWarningForSelection(
      widget.definition.key,
      value,
    );
    if (warning == null) return true;
    return _showMpvPerformanceWarningDialog(context, warning);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
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
                status: MpvSettingsCatalog.labelForSetting(
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
      'stable' => '中等偏重缓冲，优先减少抖动导致的卡顿。拖动响应会比极速慢一点，但更适合大多数 NAS、网盘和普通 STRM 观看。',
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
              child: const Text('知道了'),
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
                status: MpvSettingsCatalog.labelForSetting(
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
                  title: '高级频段调整',
                  subtitle: '进入上下滑动频谱页，自定义每个频段并保存多套预设。',
                  trailing:
                      currentValue == MpvSettingsCatalog.audioEqCustomValue
                      ? '当前使用'
                      : '进入',
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
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: buildSecondaryHostAppBar(
        context,
        title: Text(
          '高级均衡',
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
    final warning = MpvSettingsCatalog.performanceWarningForSelection(
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
                    ? '自动'
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
                        '自动缓冲',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: AdaptiveText.roleSize(16),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        _auto ? '当前由缓存策略自动分配缓冲上限。' : '关闭后可手动指定缓冲百分比。',
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
                                    '滑动调节缓冲强度',
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
                                  'MIN ${MpvSettingsCatalog.formatCachePercentLabel(MpvSettingsCatalog.cachePercentSliderMin)}',
                                  style: TextStyle(
                                    color: colors.textSecondary,
                                    fontSize: AdaptiveText.roleSize(12),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  'MAX ${MpvSettingsCatalog.formatCachePercentLabel(MpvSettingsCatalog.cachePercentSliderMax)}',
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
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: buildSecondaryHostAppBar(
        context,
        title: Text(
          '即时调节',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: AdaptiveText.roleSize(18, role: AdaptiveFontRole.title),
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => unawaited(_resetAll()),
            child: const Text('恢复默认'),
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
                title: '即时调节',
                status:
                    '${MpvSettingsCatalog.videoAdjustmentChangedCount(_values)} 项已调整',
                summary: '这些值会直接写入 mpv 的亮度、对比度、饱和度、Gamma 和色相参数，并会一起保存到画质预设中。',
                icon: Icons.tune_rounded,
              ),
              const SizedBox(height: 18),
              for (final key
                  in MpvSettingsCatalog.videoAdjustmentDefaults.keys) ...[
                _VideoAdjustmentSliderCard(
                  title: MpvSettingsCatalog.videoAdjustmentTitle(key),
                  subtitle: MpvSettingsCatalog.videoAdjustmentSubtitle(key),
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
                  itemBuilder: (_) => const <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(value: 'rename', child: Text('重命名')),
                    PopupMenuItem<String>(value: 'delete', child: Text('删除')),
                  ],
                  icon: Icon(Icons.more_horiz_rounded, color: colors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              preset.description.isEmpty
                  ? '已保存的独立预设，可随时再次应用。'
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
                selected ? '当前已应用' : '点按应用',
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
