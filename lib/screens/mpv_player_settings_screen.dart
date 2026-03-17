import 'dart:async';

import 'package:flutter/material.dart';

import '../player/stores/mpv_settings_store.dart';
import '../theme/app_theme.dart';
import '../ui/adaptive_text.dart';
import '../ui/app_transitions.dart';
import '../ui/mpv_audio_eq_advanced_panel.dart';

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
  bool _loading = true;
  bool _initialTargetHandled = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
  }

  Future<void> _loadSettings() async {
    final settings = await _store.load();
    if (!mounted) return;
    setState(() {
      _settings = settings;
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

  Future<void> _applyPreset(MpvSettingPreset preset) async {
    final next = await _store.applyPreset(preset);
    if (!mounted) return;
    setState(() => _settings = next);
  }

  Future<void> _resetSettings() async {
    final next = await _store.reset();
    if (!mounted) return;
    setState(() => _settings = next);
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

  Future<void> _openCategory(
    MpvSettingCategory category, {
    bool animated = true,
  }) async {
    await Navigator.of(context).push(
      _buildAutoRoute(
        _MpvSettingCategoryScreen(
          category: category,
          initialSettings: _settings,
        ),
        animated: animated,
      ),
    );
    await _loadSettings();
  }

  Future<void> _openDefinition(
    MpvSettingDefinition definition, {
    bool animated = true,
  }) async {
    if (definition.key == MpvSettingsCatalog.cacheSizeMbKey) {
      await Navigator.of(context).push(
        _buildAutoRoute(
          _MpvCacheSizeScreen(
            definition: definition,
            currentValue: MpvSettingsCatalog.settingValue(
              definition.key,
              _settings,
            ),
          ),
          animated: animated,
        ),
      );
    } else if (definition.key == MpvSettingsCatalog.audioEqKey) {
      await Navigator.of(context).push(
        _buildAutoRoute(
          _MpvAudioEqChoiceScreen(
            definition: definition,
            currentSettings: _settings,
          ),
          animated: animated,
        ),
      );
    } else {
      await Navigator.of(context).push(
        _buildAutoRoute(
          _MpvSettingChoiceScreen(
            definition: definition,
            currentValue: MpvSettingsCatalog.settingValue(
              definition.key,
              _settings,
            ),
          ),
          animated: animated,
        ),
      );
    }
    await _loadSettings();
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

  String _displayPresetLabel(MpvSettingPreset preset) {
    return switch (preset.id) {
      'off' => '关闭增强',
      'anime' => '动画清晰',
      'cinema' => '影院柔和',
      'smooth' => '流畅优先',
      _ => preset.label,
    };
  }

  String _displayPresetDescription(MpvSettingPreset preset) {
    return switch (preset.id) {
      'off' => '关闭大部分增强项，优先保证兼容性和稳定性。',
      'anime' => '提升线条和边缘观感，适合动画和较干净的片源。',
      'cinema' => '更柔和地压制噪点和高反差，适合老片和暗场。',
      'smooth' => '优先保证拖动响应和播放稳定性。',
      _ => preset.description,
    };
  }

  String _highFidelitySummaryLabel() {
    return _settings[MpvSettingsCatalog.audioHighFidelityKey] == 'on'
        ? '开启'
        : '关闭';
  }

  String _quickModeSummaryLabel() {
    final preset = MpvSettingsCatalog.activePreset(_settings);
    final presetLabel = preset == null ? '自定义' : _displayPresetLabel(preset);
    if (_settings[MpvSettingsCatalog.audioHighFidelityKey] == 'on') {
      return '$presetLabel / 高保真';
    }
    return presetLabel;
  }

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

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: AppBar(
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
                      status: _quickModeSummaryLabel(),
                      summary: MpvSettingsCatalog.summaryText(_settings),
                    ),
                    const SizedBox(height: 18),
                    _CardBlock(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const _SectionTitle(title: '快速模式'),
                          const SizedBox(height: 12),
                          _MenuTile(
                            icon: Icons.hearing_rounded,
                            title: '高保真模式',
                            subtitle: '优先保留干净解码输出，旁路大部分音频后处理。',
                            trailing: _highFidelitySummaryLabel(),
                            onTap: () async {
                              final definition =
                                  MpvSettingsCatalog.definitionByKey(
                                    MpvSettingsCatalog.audioHighFidelityKey,
                                  );
                              if (definition == null) return;
                              await _openDefinition(definition);
                            },
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: MpvSettingsCatalog.presets
                                .map((preset) {
                                  final selected =
                                      MpvSettingsCatalog.activePreset(
                                        _settings,
                                      )?.id ==
                                      preset.id;
                                  return _PresetChip(
                                    selected: selected,
                                    title: _displayPresetLabel(preset),
                                    subtitle: _displayPresetDescription(preset),
                                    onTap: () => _applyPreset(preset),
                                  );
                                })
                                .toList(growable: false),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _CardBlock(
                      child: Column(
                        children: <Widget>[
                          for (
                            var index = 0;
                            index < _displayCategories.length;
                            index++
                          ) ...[
                            _MenuTile(
                              icon: _iconForCategory(
                                _displayCategories[index].id,
                              ),
                              title: _displayCategories[index].title,
                              subtitle: _displayCategories[index].subtitle,
                              trailing: _displayCategorySummary(
                                _displayCategories[index],
                              ),
                              onTap: () =>
                                  _openCategory(_displayCategories[index]),
                            ),
                            if (index != _displayCategories.length - 1)
                              const _DividerLine(),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const _HintCard(
                      title: '三级结构',
                      content:
                          '这个页面只保留入口和预设，具体调节项都放在下一级分类页，再进入单项页选择，避免主页设置堆得太重。',
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  IconData _iconForCategory(String id) {
    return switch (id) {
      _displayPictureCategoryId => Icons.movie_filter_outlined,
      _displayAudioCategoryId => Icons.graphic_eq_rounded,
      _displayPlaybackCategoryId => Icons.sync_rounded,
      _displayCompatibilityCategoryId => Icons.shield_outlined,
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
      appBar: AppBar(
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

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: AppBar(
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
                    await _store.saveSetting(
                      widget.definition.key,
                      widget.definition.options[index].value,
                    );
                    if (!mounted) return;
                    setState(() {
                      _currentValue = widget.definition.options[index].value;
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
      appBar: AppBar(
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
      appBar: AppBar(
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
  late double _sliderValue = MpvSettingsCatalog.mbToCachePercent(
    int.tryParse(widget.currentValue) ??
        MpvSettingsCatalog.cacheSizeExtremeMinimumMb,
  ).toDouble();

  Future<void> _saveCurrentSliderValue() async {
    final normalized = _sliderValue.round().clamp(
      MpvSettingsCatalog.cachePercentSliderMin,
      MpvSettingsCatalog.cachePercentSliderMax,
    );
    final mapped = MpvSettingsCatalog.cachePercentToMb(normalized);
    await _store.saveSetting(
      MpvSettingsCatalog.cacheSizeMbKey,
      mapped.toString(),
    );
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
      appBar: AppBar(
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
                        } else {
                          await _saveCurrentSliderValue();
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

class _DividerLine extends StatelessWidget {
  const _DividerLine();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: context.appColors.borderSubtle);
  }
}
