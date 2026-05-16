import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/runtime_theme_session_bridge.dart';
import '../services/runtime_theme_sync_bridge.dart';
import '../theme/app_theme.dart';
import '../theme/dynamic_theme_mapper.dart';
import '../theme/dynamic_theme_seed_extractor.dart';

class AppThemeProvider extends ChangeNotifier {
  static const String _presetKey = 'app_theme_preset';
  static const String _backgroundToneKey = 'app_theme_background_tone';
  static const String _accentToneKey = 'app_theme_accent_tone';
  static const String _selectionToneKey = 'app_theme_selection_tone';
  static const String _linkToneKey = 'app_theme_link_tone';
  static const String _customBackgroundColorKey = 'app_theme_custom_background';
  static const String _customAccentColorKey = 'app_theme_custom_accent';
  static const String _customSelectionColorKey = 'app_theme_custom_selection';
  static const String _customLinkColorKey = 'app_theme_custom_link';
  static const String _dynamicThemeModeKey = 'app_theme_dynamic_mode';
  static const String _dynamicThemeIntensityKey = 'app_theme_dynamic_intensity';
  static const String _themeSourceTypeKey = 'app_theme_source_type';
  static const String _activeSavedThemeIdKey =
      'app_theme_active_saved_theme_id';
  static const String _savedThemesKey = 'app_theme_saved_themes_v1';
  static const String _runtimeDynamicThemePageKey =
      'app_theme_runtime_dynamic_page_key';
  static const String _runtimeDynamicBackgroundSeedKey =
      'app_theme_runtime_dynamic_background_seed';
  static const String _runtimeDynamicAccentSeedKey =
      'app_theme_runtime_dynamic_accent_seed';
  static const String _runtimeDynamicSelectionSeedKey =
      'app_theme_runtime_dynamic_selection_seed';
  static const String _runtimeDynamicLinkSeedKey =
      'app_theme_runtime_dynamic_link_seed';
  static const String _runtimeDynamicPreferLightSurfaceKey =
      'app_theme_runtime_dynamic_prefer_light_surface';
  static const String _runtimeDynamicSessionIdKey =
      'app_theme_runtime_dynamic_session_id';
  static const String _themeRevisionKey = 'app_theme_revision';
  static const Duration _syncInterval = Duration(milliseconds: 700);
  static const Duration _runtimeMainClearGrace = Duration(milliseconds: 600);
  static _AppThemeBootstrapSnapshot? _bootstrapSnapshot;

  AppThemePreset _preset = AppThemePreset.midnight;
  AppBackgroundTone _backgroundTone = AppBackgroundTone.night;
  AppAccentTone _accentTone = AppAccentTone.blue;
  AppAccentTone _selectionTone = AppAccentTone.blue;
  AppAccentTone _linkTone = AppAccentTone.blue;
  Color? _customBackgroundColor;
  Color? _customAccentColor;
  Color? _customSelectionColor;
  Color? _customLinkColor;
  AppDynamicThemeMode _dynamicThemeMode = AppDynamicThemeMode.off;
  AppDynamicThemeIntensity _dynamicThemeIntensity =
      AppDynamicThemeIntensity.medium;
  AppThemeSourceType _themeSourceType = AppThemeSourceType.preset;
  String _activeSavedThemeId = '';
  List<SavedCustomTheme> _savedThemes = const <SavedCustomTheme>[];
  String _runtimeDynamicThemePage = '';
  DynamicThemeSeed? _runtimeDynamicThemeSeed;
  final Map<String, DynamicThemeSeed> _runtimeDynamicThemeCache =
      <String, DynamicThemeSeed>{};
  final List<String> _runtimeDynamicThemeOrder = <String>[];
  bool _isReady = false;
  SharedPreferences? _prefs;
  Timer? _syncTimer;
  Timer? _runtimeMainClearTimer;
  Timer? _runtimeTopThemeRemovalTimer;
  int _themeRevision = 0;
  bool _syncInProgress = false;
  String _runtimeSessionId = '';
  String _cachedEffectiveThemeSignature = '';
  AppThemeColors? _cachedEffectiveThemeColors;
  String _pendingRuntimeMainClearPageKey = '';
  String _pendingRuntimeTopRemovalPageKey = '';
  int _runtimeMainClearHoldCount = 0;
  int _runtimeThemeApplyToken = 0;
  bool _disposed = false;

  AppThemeProvider() {
    final bootstrap = _bootstrapSnapshot;
    if (bootstrap != null) {
      _applyBootstrapSnapshot(bootstrap);
      _isReady = true;
    }
    unawaited(_registerRuntimeThemeSyncHandler());
    load();
    _startSyncLoop();
  }

  bool get isReady => _isReady;
  AppThemePreset get preset => _preset;
  AppBackgroundTone get backgroundTone => _backgroundTone;
  AppAccentTone get accentTone => _accentTone;
  AppAccentTone get selectionTone => _selectionTone;
  AppAccentTone get linkTone => _linkTone;
  Color? get customBackgroundColor => _customBackgroundColor;
  Color? get customAccentColor => _customAccentColor;
  Color? get customSelectionColor => _customSelectionColor;
  Color? get customLinkColor => _customLinkColor;
  AppDynamicThemeMode get dynamicThemeMode => _dynamicThemeMode;
  AppDynamicThemeIntensity get dynamicThemeIntensity => _dynamicThemeIntensity;
  AppThemeSourceType get themeSourceType => _themeSourceType;
  String get activeSavedThemeId => _activeSavedThemeId;
  List<SavedCustomTheme> get savedThemes =>
      List<SavedCustomTheme>.unmodifiable(_savedThemes);
  bool get dynamicThemeEnabled =>
      _dynamicThemeMode == AppDynamicThemeMode.detailsAndPeople;
  String get runtimeDynamicThemePage => _runtimeDynamicThemePage;
  DynamicThemeSeed? get runtimeDynamicThemeSeed => _runtimeDynamicThemeSeed;
  SavedCustomTheme? get activeSavedTheme => savedThemeById(_activeSavedThemeId);
  bool get isSavedThemeActive =>
      _themeSourceType == AppThemeSourceType.savedCustomTheme;
  bool get isCurrentCustomActive =>
      _themeSourceType == AppThemeSourceType.currentCustom;
  bool get isPresetActive => _themeSourceType == AppThemeSourceType.preset;
  AppThemeColors get selectedThemeBaseColors {
    if (_themeSourceType == AppThemeSourceType.savedCustomTheme) {
      final savedTheme = activeSavedTheme;
      if (savedTheme != null) {
        return savedTheme.colorsSnapshot;
      }
    }
    return themeColors;
  }

  String get materialThemeSignature => _baseThemeSignature();

  String get currentThemeTitle => switch (_themeSourceType) {
    AppThemeSourceType.preset => _preset.title,
    AppThemeSourceType.currentCustom => 'Current custom',
    AppThemeSourceType.savedCustomTheme =>
      activeSavedTheme?.name ?? 'Current custom',
  };
  String get currentThemeSubtitle => switch (_themeSourceType) {
    AppThemeSourceType.preset => 'Preset theme',
    AppThemeSourceType.currentCustom => 'Manual recipe',
    AppThemeSourceType.savedCustomTheme =>
      activeSavedTheme?.description.trim().isNotEmpty == true
          ? activeSavedTheme!.description
          : 'Saved theme',
  };

  bool get usesCustomBackgroundColor => _customBackgroundColor != null;
  bool get usesCustomAccentColor => _customAccentColor != null;
  bool get usesCustomSelectionColor => _customSelectionColor != null;
  bool get usesCustomLinkColor => _customLinkColor != null;
  bool get isPresetCustomized {
    final defaults = _defaultsForPreset(_preset);
    return usesCustomBackgroundColor ||
        usesCustomAccentColor ||
        usesCustomSelectionColor ||
        usesCustomLinkColor ||
        _backgroundTone != defaults.backgroundTone ||
        _accentTone != defaults.accentTone ||
        _selectionTone != defaults.selectionTone ||
        _linkTone != defaults.linkTone;
  }

  String get effectiveThemeTitle =>
      isPresetCustomized ? 'Custom' : _preset.title;

  AppThemeColors get themeColors => AppThemePalette.colorsFor(
    _preset,
    backgroundTone: _backgroundTone,
    accentTone: _accentTone,
    selectionTone: _selectionTone,
    linkTone: _linkTone,
    customBackgroundColor: _customBackgroundColor,
    customAccentColor: _customAccentColor,
    customSelectionColor: _customSelectionColor,
    customLinkColor: _customLinkColor,
  );

  AppThemeColors get effectiveThemeColors {
    final signature = _effectiveThemeSignature();
    final cachedColors = _cachedEffectiveThemeColors;
    if (cachedColors != null && _cachedEffectiveThemeSignature == signature) {
      return cachedColors;
    }
    final baseColors = selectedThemeBaseColors;
    final runtimeSeed = _runtimeDynamicThemeSeed;
    if (!dynamicThemeEnabled || runtimeSeed == null) {
      _cachedEffectiveThemeSignature = signature;
      _cachedEffectiveThemeColors = baseColors;
      return baseColors;
    }
    final mappedColors = DynamicThemeMapper.map(
      baseColors: baseColors,
      seed: runtimeSeed,
      intensity: _dynamicThemeIntensity,
    );
    _cachedEffectiveThemeSignature = signature;
    _cachedEffectiveThemeColors = mappedColors;
    return mappedColors;
  }

  String get effectiveThemeSignature => _effectiveThemeSignature();

  Color get backgroundPreviewColor =>
      _customBackgroundColor ?? _backgroundTone.tint;
  Color get accentPreviewColor =>
      _customAccentColor ??
      _accentTone.colorFor(
        light: themeColors.backgroundBase.computeLuminance() >= 0.58,
      );
  Color get selectionPreviewColor =>
      _customSelectionColor ??
      _selectionTone.colorFor(
        light: themeColors.backgroundBase.computeLuminance() >= 0.58,
      );
  Color get linkPreviewColor =>
      _customLinkColor ??
      _linkTone.strongColorFor(
        light: themeColors.backgroundBase.computeLuminance() >= 0.58,
      );

  AppThemeColors previewColorsForPreset(AppThemePreset preset) {
    final defaults = _defaultsForPreset(preset);
    return AppThemePalette.colorsFor(
      preset,
      backgroundTone: defaults.backgroundTone,
      accentTone: defaults.accentTone,
      selectionTone: defaults.selectionTone,
      linkTone: defaults.linkTone,
    );
  }

  SavedCustomTheme? savedThemeById(String id) {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) {
      return null;
    }
    for (final theme in _savedThemes) {
      if (theme.id == normalizedId) {
        return theme;
      }
    }
    return null;
  }

  bool isSavedThemeNameAvailable(String name, {String? excludingId}) {
    return _isThemeNameAvailable(name, excludingId: excludingId);
  }

  String nextSavedThemeName() {
    var index = 1;
    while (true) {
      final candidate = 'Custom theme $index';
      if (_isThemeNameAvailable(candidate)) {
        return candidate;
      }
      index++;
    }
  }

  Future<void> activateCurrentCustomTheme() async {
    _themeSourceType = AppThemeSourceType.currentCustom;
    _activeSavedThemeId = '';
    await _persist(_persistThemeSelection);
  }

  String nextSavedThemeNameFromBase(String baseName) {
    final normalizedBase = baseName.trim();
    if (normalizedBase.isEmpty) {
      return nextSavedThemeName();
    }
    var index = 1;
    while (true) {
      final candidate = '$normalizedBase$index';
      if (_isThemeNameAvailable(candidate)) {
        return candidate;
      }
      index++;
    }
  }

  Future<void> applySavedTheme(String id) async {
    final theme = savedThemeById(id);
    if (theme == null) {
      return;
    }
    _themeSourceType = AppThemeSourceType.savedCustomTheme;
    _activeSavedThemeId = theme.id;
    await _persist(_persistThemeSelection);
  }

  Future<void> saveThemeSnapshot({
    required AppThemeColors colors,
    required String name,
    String description = '',
    String? pageKey,
    bool clearRuntimeBroadcastToMain = true,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError('Theme name must not be empty.');
    }
    if (!_isThemeNameAvailable(normalizedName)) {
      throw StateError('Theme name already exists.');
    }
    final savedTheme = SavedCustomTheme(
      id: 'saved_theme_${DateTime.now().microsecondsSinceEpoch}',
      name: normalizedName,
      description: description.trim(),
      createdAt: DateTime.now(),
      colorsSnapshot: colors,
    );
    _savedThemes = <SavedCustomTheme>[..._savedThemes, savedTheme];
    _themeSourceType = AppThemeSourceType.savedCustomTheme;
    _activeSavedThemeId = savedTheme.id;
    await _persist((prefs) async {
      await _persistSavedThemes(prefs);
      await _persistThemeSelection(prefs);
    });
    final normalizedPageKey = pageKey?.trim() ?? '';
    if (normalizedPageKey.isNotEmpty) {
      await clearRuntimeDynamicTheme(
        normalizedPageKey,
        broadcastToMain: clearRuntimeBroadcastToMain,
      );
    }
  }

  Future<void> renameSavedTheme(
    String id, {
    required String name,
    String description = '',
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError('Theme name must not be empty.');
    }
    if (!_isThemeNameAvailable(normalizedName, excludingId: id)) {
      throw StateError('Theme name already exists.');
    }
    final nextThemes = <SavedCustomTheme>[];
    var updated = false;
    for (final theme in _savedThemes) {
      if (theme.id == id) {
        nextThemes.add(
          theme.copyWith(name: normalizedName, description: description.trim()),
        );
        updated = true;
      } else {
        nextThemes.add(theme);
      }
    }
    if (!updated) {
      return;
    }
    _savedThemes = nextThemes;
    await _persist(_persistSavedThemes);
  }

  Future<void> deleteSavedTheme(String id) async {
    final nextThemes = _savedThemes
        .where((theme) => theme.id != id)
        .toList(growable: false);
    if (nextThemes.length == _savedThemes.length) {
      return;
    }
    _savedThemes = nextThemes;
    if (_activeSavedThemeId == id) {
      _themeSourceType = AppThemeSourceType.currentCustom;
      _activeSavedThemeId = '';
    }
    await _persist((prefs) async {
      await _persistSavedThemes(prefs);
      await _persistThemeSelection(prefs);
    });
  }

  Future<void> load() async {
    final prefs = await _obtainPrefs(refresh: true);
    await _ensureRuntimeThemeSession(prefs);
    _applyStoredValues(prefs);
    _themeRevision = prefs.getInt(_themeRevisionKey) ?? _themeRevision;
    _isReady = true;
    _cacheBootstrapSnapshot();
    _publishRuntimeDynamicThemeToScope();
    notifyListeners();
  }

  Future<void> setPreset(AppThemePreset value) async {
    await applyPreset(value);
  }

  Future<void> applyPreset(AppThemePreset value) async {
    final defaults = _defaultsForPreset(value);
    _preset = value;
    _backgroundTone = defaults.backgroundTone;
    _accentTone = defaults.accentTone;
    _selectionTone = defaults.selectionTone;
    _linkTone = defaults.linkTone;
    _customBackgroundColor = null;
    _customAccentColor = null;
    _customSelectionColor = null;
    _customLinkColor = null;
    _themeSourceType = AppThemeSourceType.preset;
    _activeSavedThemeId = '';
    await _persist((prefs) async {
      await prefs.setString(_presetKey, value.storageValue);
      await prefs.setString(
        _backgroundToneKey,
        defaults.backgroundTone.storageValue,
      );
      await prefs.setString(_accentToneKey, defaults.accentTone.storageValue);
      await prefs.setString(
        _selectionToneKey,
        defaults.selectionTone.storageValue,
      );
      await prefs.setString(_linkToneKey, defaults.linkTone.storageValue);
      await prefs.remove(_customBackgroundColorKey);
      await prefs.remove(_customAccentColorKey);
      await prefs.remove(_customSelectionColorKey);
      await prefs.remove(_customLinkColorKey);
      await _persistThemeSelection(prefs);
    });
  }

  Future<void> setBackgroundTone(AppBackgroundTone value) async {
    _backgroundTone = value;
    _customBackgroundColor = null;
    _themeSourceType = AppThemeSourceType.currentCustom;
    _activeSavedThemeId = '';
    await _persist((prefs) async {
      await prefs.setString(_backgroundToneKey, value.storageValue);
      await prefs.remove(_customBackgroundColorKey);
      await _persistThemeSelection(prefs);
    });
  }

  Future<void> setAccentTone(AppAccentTone value) async {
    _accentTone = value;
    _customAccentColor = null;
    _themeSourceType = AppThemeSourceType.currentCustom;
    _activeSavedThemeId = '';
    await _persist((prefs) async {
      await prefs.setString(_accentToneKey, value.storageValue);
      await prefs.remove(_customAccentColorKey);
      await _persistThemeSelection(prefs);
    });
  }

  Future<void> setSelectionTone(AppAccentTone value) async {
    _selectionTone = value;
    _customSelectionColor = null;
    _themeSourceType = AppThemeSourceType.currentCustom;
    _activeSavedThemeId = '';
    await _persist((prefs) async {
      await prefs.setString(_selectionToneKey, value.storageValue);
      await prefs.remove(_customSelectionColorKey);
      await _persistThemeSelection(prefs);
    });
  }

  Future<void> setLinkTone(AppAccentTone value) async {
    _linkTone = value;
    _customLinkColor = null;
    _themeSourceType = AppThemeSourceType.currentCustom;
    _activeSavedThemeId = '';
    await _persist((prefs) async {
      await prefs.setString(_linkToneKey, value.storageValue);
      await prefs.remove(_customLinkColorKey);
      await _persistThemeSelection(prefs);
    });
  }

  Future<void> setCustomBackgroundColor(Color value) async {
    _customBackgroundColor = value;
    _themeSourceType = AppThemeSourceType.currentCustom;
    _activeSavedThemeId = '';
    await _persist((prefs) async {
      await prefs.setInt(_customBackgroundColorKey, value.toARGB32());
      await _persistThemeSelection(prefs);
    });
  }

  Future<void> setCustomAccentColor(Color value) async {
    _customAccentColor = value;
    _themeSourceType = AppThemeSourceType.currentCustom;
    _activeSavedThemeId = '';
    await _persist((prefs) async {
      await prefs.setInt(_customAccentColorKey, value.toARGB32());
      await _persistThemeSelection(prefs);
    });
  }

  Future<void> setCustomSelectionColor(Color value) async {
    _customSelectionColor = value;
    _themeSourceType = AppThemeSourceType.currentCustom;
    _activeSavedThemeId = '';
    await _persist((prefs) async {
      await prefs.setInt(_customSelectionColorKey, value.toARGB32());
      await _persistThemeSelection(prefs);
    });
  }

  Future<void> setCustomLinkColor(Color value) async {
    _customLinkColor = value;
    _themeSourceType = AppThemeSourceType.currentCustom;
    _activeSavedThemeId = '';
    await _persist((prefs) async {
      await prefs.setInt(_customLinkColorKey, value.toARGB32());
      await _persistThemeSelection(prefs);
    });
  }

  Future<void> setDynamicThemeMode(AppDynamicThemeMode value) async {
    if (_dynamicThemeMode == value && _isReady) return;
    _dynamicThemeMode = value;
    await _persist(
      (prefs) => prefs.setString(_dynamicThemeModeKey, value.storageValue),
    );
  }

  Future<void> setDynamicThemeIntensity(AppDynamicThemeIntensity value) async {
    if (_dynamicThemeIntensity == value && _isReady) return;
    _dynamicThemeIntensity = value;
    await _persist(
      (prefs) => prefs.setString(_dynamicThemeIntensityKey, value.storageValue),
    );
  }

  Future<void> setRuntimeDynamicTheme({
    required String pageKey,
    required DynamicThemeSeed seed,
    bool broadcastToMain = true,
    Duration? localNotifyDelayAfterBroadcast,
  }) async {
    final normalizedPageKey = pageKey.trim();
    if (normalizedPageKey.isEmpty) return;
    await _ensureRuntimeSessionLoaded();
    _cancelPendingRuntimeMainClear();
    final deferredRemovalPageKey = _pendingRuntimeTopRemovalPageKey;
    _cancelPendingRuntimeTopRemoval();
    final applyToken = ++_runtimeThemeApplyToken;
    if (kDebugMode) {
      debugPrint(
        '[THEME][RUNTIME] set page=$normalizedPageKey broadcast=$broadcastToMain session=$_runtimeSessionId',
      );
    }
    final previousVisualSignature = _effectiveThemeSignature();
    final cachedSeed = _runtimeDynamicThemeCache[normalizedPageKey];
    final seedUnchanged = _sameRuntimeSeed(cachedSeed, seed);
    final alreadyTop =
        _runtimeDynamicThemeOrder.isNotEmpty &&
        _runtimeDynamicThemeOrder.last == normalizedPageKey;
    if (seedUnchanged && alreadyTop && _isReady) {
      return;
    }
    _runtimeDynamicThemeCache[normalizedPageKey] = seed;
    _runtimeDynamicThemeOrder.remove(normalizedPageKey);
    _runtimeDynamicThemeOrder.add(normalizedPageKey);
    _syncRuntimeThemeFromCache();
    final visualChanged = previousVisualSignature != _effectiveThemeSignature();
    final shouldDeferLocalNotify =
        visualChanged &&
        broadcastToMain &&
        localNotifyDelayAfterBroadcast != null &&
        localNotifyDelayAfterBroadcast > Duration.zero;
    if (!visualChanged && !broadcastToMain) {
      return;
    }
    if (visualChanged && !shouldDeferLocalNotify) {
      _isReady = true;
      _publishRuntimeDynamicThemeToScope();
    }
    if (broadcastToMain) {
      if (kDebugMode) {
        debugPrint('[THEME][RUNTIME] push_to_main page=$normalizedPageKey');
      }
      await RuntimeThemeSyncBridge.instance.pushRuntimeThemeToMain(
        pageKey: normalizedPageKey,
        backgroundSeed: seed.backgroundSeed.toARGB32(),
        accentSeed: seed.accentSeed.toARGB32(),
        selectionSeed: seed.selectionSeed.toARGB32(),
        linkSeed: seed.linkSeed.toARGB32(),
        preferLightSurface: seed.preferLightSurface,
      );
    }
    if (deferredRemovalPageKey.isNotEmpty &&
        deferredRemovalPageKey != normalizedPageKey) {
      unawaited(
        _performRuntimeDynamicThemeClear(
          deferredRemovalPageKey,
          broadcastToMain: broadcastToMain,
          allowTopDeferral: false,
          restoreFallbackOnMain: false,
        ),
      );
    }
    if (!shouldDeferLocalNotify || _disposed) {
      return;
    }
    if (applyToken != _runtimeThemeApplyToken) {
      return;
    }
    await Future<void>.delayed(localNotifyDelayAfterBroadcast);
    if (_disposed || applyToken != _runtimeThemeApplyToken) {
      return;
    }
    _isReady = true;
    _publishRuntimeDynamicThemeToScope();
  }

  Future<void> clearRuntimeDynamicTheme(
    String pageKey, {
    bool broadcastToMain = true,
    bool restoreFallbackOnMain = true,
    Duration? localNotifyDelayAfterBroadcast,
  }) async {
    final normalizedPageKey = pageKey.trim();
    if (normalizedPageKey.isEmpty) {
      return;
    }
    await _ensureRuntimeSessionLoaded();
    await _performRuntimeDynamicThemeClear(
      normalizedPageKey,
      broadcastToMain: broadcastToMain,
      allowTopDeferral: true,
      restoreFallbackOnMain: restoreFallbackOnMain,
      localNotifyDelayAfterBroadcast: localNotifyDelayAfterBroadcast,
    );
  }

  Future<void> _performRuntimeDynamicThemeClear(
    String pageKey, {
    required bool broadcastToMain,
    required bool allowTopDeferral,
    bool restoreFallbackOnMain = true,
    Duration? localNotifyDelayAfterBroadcast,
  }) async {
    final normalizedPageKey = pageKey.trim();
    if (normalizedPageKey.isEmpty) {
      return;
    }
    final applyToken = ++_runtimeThemeApplyToken;
    if (kDebugMode) {
      debugPrint(
        '[THEME][RUNTIME] clear page=$normalizedPageKey broadcast=$broadcastToMain session=$_runtimeSessionId',
      );
    }
    final isCurrentTop =
        _runtimeDynamicThemeOrder.isNotEmpty &&
        _runtimeDynamicThemeOrder.last == normalizedPageKey;
    final hasFallbackTheme = _runtimeDynamicThemeOrder.length > 1;
    if (allowTopDeferral &&
        broadcastToMain &&
        isCurrentTop &&
        !hasFallbackTheme) {
      if (kDebugMode) {
        debugPrint('[THEME][RUNTIME] defer_top_clear page=$normalizedPageKey');
      }
      _scheduleRuntimeTopRemoval(normalizedPageKey);
      return;
    }
    final previousVisualSignature = _effectiveThemeSignature();
    final removedWasTop = isCurrentTop;
    final removedFromOrder = _runtimeDynamicThemeOrder.remove(
      normalizedPageKey,
    );
    final removedSeed = _runtimeDynamicThemeCache.remove(normalizedPageKey);
    if (!removedFromOrder && removedSeed == null) return;
    _syncRuntimeThemeFromCache();
    final visualChanged = previousVisualSignature != _effectiveThemeSignature();
    final willRestoreFallback =
        broadcastToMain &&
        removedWasTop &&
        _runtimeDynamicThemeSeed != null &&
        restoreFallbackOnMain;
    final shouldDeferLocalNotify =
        visualChanged &&
        willRestoreFallback &&
        localNotifyDelayAfterBroadcast != null &&
        localNotifyDelayAfterBroadcast > Duration.zero;
    if (!visualChanged && !broadcastToMain) {
      return;
    }
    if (visualChanged && !shouldDeferLocalNotify) {
      _isReady = true;
      _publishRuntimeDynamicThemeToScope();
    }
    if (broadcastToMain) {
      if (willRestoreFallback) {
        final fallbackPageKey = _runtimeDynamicThemePage;
        final fallbackSeed = _runtimeDynamicThemeSeed!;
        if (kDebugMode) {
          debugPrint(
            '[THEME][RUNTIME] restore_on_main page=$fallbackPageKey after_clear=$normalizedPageKey',
          );
        }
        await RuntimeThemeSyncBridge.instance.pushRuntimeThemeToMain(
          pageKey: fallbackPageKey,
          backgroundSeed: fallbackSeed.backgroundSeed.toARGB32(),
          accentSeed: fallbackSeed.accentSeed.toARGB32(),
          selectionSeed: fallbackSeed.selectionSeed.toARGB32(),
          linkSeed: fallbackSeed.linkSeed.toARGB32(),
          preferLightSurface: fallbackSeed.preferLightSurface,
        );
        await RuntimeThemeSyncBridge.instance.clearRuntimeThemeOnMain(
          normalizedPageKey,
        );
      } else {
        if (kDebugMode) {
          debugPrint(
            '[THEME][RUNTIME] schedule_clear_on_main page=$normalizedPageKey',
          );
        }
        _scheduleRuntimeMainClear(normalizedPageKey);
      }
    }
    if (!shouldDeferLocalNotify || _disposed) {
      return;
    }
    if (applyToken != _runtimeThemeApplyToken) {
      return;
    }
    await Future<void>.delayed(localNotifyDelayAfterBroadcast);
    if (_disposed || applyToken != _runtimeThemeApplyToken) {
      return;
    }
    _isReady = true;
    _publishRuntimeDynamicThemeToScope();
  }

  void _scheduleRuntimeTopRemoval(String pageKey) {
    _pendingRuntimeTopRemovalPageKey = pageKey.trim();
    _runtimeTopThemeRemovalTimer?.cancel();
    _runtimeTopThemeRemovalTimer = Timer(_runtimeMainClearGrace, () {
      final pendingPageKey = _pendingRuntimeTopRemovalPageKey;
      _pendingRuntimeTopRemovalPageKey = '';
      _runtimeTopThemeRemovalTimer = null;
      if (pendingPageKey.isEmpty) {
        return;
      }
      if (_runtimeMainClearHoldCount > 0) {
        _scheduleRuntimeTopRemoval(pendingPageKey);
        return;
      }
      unawaited(
        _performRuntimeDynamicThemeClear(
          pendingPageKey,
          broadcastToMain: true,
          allowTopDeferral: false,
          restoreFallbackOnMain: true,
        ),
      );
    });
  }

  void _cancelPendingRuntimeTopRemoval() {
    _runtimeTopThemeRemovalTimer?.cancel();
    _runtimeTopThemeRemovalTimer = null;
    _pendingRuntimeTopRemovalPageKey = '';
  }

  Future<void> _persist(
    Future<void> Function(SharedPreferences prefs) write, [
    bool notify = true,
  ]) async {
    _isReady = true;
    _cacheBootstrapSnapshot();
    _publishRuntimeDynamicThemeToScope();
    if (notify) {
      notifyListeners();
    }
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await write(prefs);
    final revision = DateTime.now().microsecondsSinceEpoch;
    await prefs.setInt(_themeRevisionKey, revision);
    _themeRevision = revision;
    _cacheBootstrapSnapshot();
  }

  void acquireRuntimeMainClearHold() {
    _runtimeMainClearHoldCount++;
    if (kDebugMode) {
      debugPrint(
        '[THEME][RUNTIME] hold_acquire count=$_runtimeMainClearHoldCount pending=$_pendingRuntimeMainClearPageKey',
      );
    }
  }

  void releaseRuntimeMainClearHold() {
    if (_runtimeMainClearHoldCount <= 0) {
      return;
    }
    _runtimeMainClearHoldCount--;
    if (kDebugMode) {
      debugPrint(
        '[THEME][RUNTIME] hold_release count=$_runtimeMainClearHoldCount pending=$_pendingRuntimeMainClearPageKey',
      );
    }
    if (_runtimeMainClearHoldCount == 0 &&
        _pendingRuntimeMainClearPageKey.isNotEmpty &&
        _runtimeMainClearTimer == null) {
      _scheduleRuntimeMainClear(
        _pendingRuntimeMainClearPageKey,
        delay: Duration.zero,
      );
    }
  }

  void _scheduleRuntimeMainClear(String pageKey, {Duration? delay}) {
    final normalizedPageKey = pageKey.trim();
    if (normalizedPageKey.isEmpty) {
      return;
    }
    _pendingRuntimeMainClearPageKey = normalizedPageKey;
    _runtimeMainClearTimer?.cancel();
    _runtimeMainClearTimer = Timer(delay ?? _runtimeMainClearGrace, () {
      final pendingPageKey = _pendingRuntimeMainClearPageKey;
      _pendingRuntimeMainClearPageKey = '';
      _runtimeMainClearTimer = null;
      if (_runtimeMainClearHoldCount > 0) {
        if (pendingPageKey.isNotEmpty) {
          if (kDebugMode) {
            debugPrint(
              '[THEME][RUNTIME] defer_clear_on_main page=$pendingPageKey hold=$_runtimeMainClearHoldCount',
            );
          }
          _scheduleRuntimeMainClear(pendingPageKey);
        }
        return;
      }
      if (pendingPageKey.isEmpty ||
          _runtimeDynamicThemePage == pendingPageKey ||
          _runtimeDynamicThemeCache.containsKey(pendingPageKey)) {
        return;
      }
      unawaited(
        RuntimeThemeSyncBridge.instance.clearRuntimeThemeOnMain(pendingPageKey),
      );
    });
  }

  void _cancelPendingRuntimeMainClear() {
    _runtimeMainClearTimer?.cancel();
    _runtimeMainClearTimer = null;
    _pendingRuntimeMainClearPageKey = '';
  }

  static Color? _readColor(SharedPreferences prefs, String key) {
    final value = prefs.getInt(key);
    return value == null ? null : Color(value);
  }

  _PresetDefaults _defaultsForPreset(AppThemePreset preset) {
    return switch (preset) {
      AppThemePreset.midnight => const _PresetDefaults(
        backgroundTone: AppBackgroundTone.night,
        accentTone: AppAccentTone.blue,
        selectionTone: AppAccentTone.blue,
        linkTone: AppAccentTone.blue,
      ),
      AppThemePreset.ocean => const _PresetDefaults(
        backgroundTone: AppBackgroundTone.ocean,
        accentTone: AppAccentTone.cyan,
        selectionTone: AppAccentTone.blue,
        linkTone: AppAccentTone.cyan,
      ),
      AppThemePreset.forest => const _PresetDefaults(
        backgroundTone: AppBackgroundTone.moss,
        accentTone: AppAccentTone.green,
        selectionTone: AppAccentTone.green,
        linkTone: AppAccentTone.green,
      ),
      AppThemePreset.graphite => const _PresetDefaults(
        backgroundTone: AppBackgroundTone.slate,
        accentTone: AppAccentTone.indigo,
        selectionTone: AppAccentTone.indigo,
        linkTone: AppAccentTone.indigo,
      ),
      AppThemePreset.sunset => const _PresetDefaults(
        backgroundTone: AppBackgroundTone.ember,
        accentTone: AppAccentTone.coral,
        selectionTone: AppAccentTone.coral,
        linkTone: AppAccentTone.amber,
      ),
      AppThemePreset.aurora => const _PresetDefaults(
        backgroundTone: AppBackgroundTone.ocean,
        accentTone: AppAccentTone.mint,
        selectionTone: AppAccentTone.blue,
        linkTone: AppAccentTone.mint,
      ),
      AppThemePreset.latte => const _PresetDefaults(
        backgroundTone: AppBackgroundTone.ivory,
        accentTone: AppAccentTone.indigo,
        selectionTone: AppAccentTone.blue,
        linkTone: AppAccentTone.indigo,
      ),
    };
  }

  bool _isThemeNameAvailable(String name, {String? excludingId}) {
    final normalizedName = _normalizeThemeName(name);
    if (normalizedName.isEmpty) {
      return false;
    }
    for (final theme in _savedThemes) {
      if (excludingId != null && theme.id == excludingId) {
        continue;
      }
      if (_normalizeThemeName(theme.name) == normalizedName) {
        return false;
      }
    }
    return true;
  }

  String _normalizeThemeName(String value) {
    return value.trim().toLowerCase();
  }

  List<SavedCustomTheme> _decodeSavedThemes(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const <SavedCustomTheme>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <SavedCustomTheme>[];
      }
      final result = <SavedCustomTheme>[];
      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }
        final theme = SavedCustomTheme.fromMap(item.cast<String, dynamic>());
        if (theme != null) {
          result.add(theme);
        }
      }
      return result;
    } catch (_) {
      return const <SavedCustomTheme>[];
    }
  }

  Future<void> _persistThemeSelection(SharedPreferences prefs) async {
    await prefs.setString(_themeSourceTypeKey, _themeSourceType.storageValue);
    await prefs.setString(_activeSavedThemeIdKey, _activeSavedThemeId);
  }

  Future<void> _persistSavedThemes(SharedPreferences prefs) async {
    final payload = _savedThemes
        .map((theme) => theme.toMap())
        .toList(growable: false);
    await prefs.setString(_savedThemesKey, jsonEncode(payload));
  }

  void _startSyncLoop() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(_syncInterval, (_) {
      unawaited(_pollExternalChanges());
    });
  }

  Future<void> _pollExternalChanges() async {
    if (_syncInProgress) return;
    _syncInProgress = true;
    try {
      final prefs = await _obtainPrefs(refresh: true);
      await _ensureRuntimeThemeSession(prefs);
      final nextRevision = prefs.getInt(_themeRevisionKey) ?? 0;
      if (nextRevision == _themeRevision) return;
      final previousVisualSignature = _effectiveThemeSignature();
      _themeRevision = nextRevision;
      final runtimePage = _runtimeDynamicThemePage;
      final runtimeSeed = _runtimeDynamicThemeSeed;
      final runtimeCache = Map<String, DynamicThemeSeed>.from(
        _runtimeDynamicThemeCache,
      );
      final runtimeOrder = List<String>.from(_runtimeDynamicThemeOrder);
      _applyStoredValues(prefs);
      if (runtimeSeed != null && runtimePage.isNotEmpty) {
        _runtimeDynamicThemePage = runtimePage;
        _runtimeDynamicThemeSeed = runtimeSeed;
        _runtimeDynamicThemeCache
          ..clear()
          ..addAll(runtimeCache);
        _runtimeDynamicThemeOrder
          ..clear()
          ..addAll(runtimeOrder);
      }
      _isReady = true;
      _cacheBootstrapSnapshot();
      _publishRuntimeDynamicThemeToScope();
      if (previousVisualSignature != _effectiveThemeSignature()) {
        notifyListeners();
      }
    } finally {
      _syncInProgress = false;
    }
  }

  String _effectiveThemeSignature() {
    final parts = <Object?>[
      _themeSourceType.storageValue,
      _activeSavedThemeId,
      _preset.storageValue,
      _backgroundTone.storageValue,
      _accentTone.storageValue,
      _selectionTone.storageValue,
      _linkTone.storageValue,
      _customBackgroundColor?.toARGB32(),
      _customAccentColor?.toARGB32(),
      _customSelectionColor?.toARGB32(),
      _customLinkColor?.toARGB32(),
      _dynamicThemeMode.storageValue,
      _dynamicThemeIntensity.storageValue,
      ...selectedThemeBaseColors.toMap().values,
    ];
    if (dynamicThemeEnabled && _runtimeDynamicThemeSeed != null) {
      final seed = _runtimeDynamicThemeSeed!;
      parts.addAll(<Object?>[
        seed.backgroundSeed.toARGB32(),
        seed.accentSeed.toARGB32(),
        seed.selectionSeed.toARGB32(),
        seed.linkSeed.toARGB32(),
        seed.preferLightSurface,
      ]);
    }
    return parts.join('|');
  }

  String _baseThemeSignature() {
    return selectedThemeBaseColors.toMap().values.join('|');
  }

  AppThemeColors? _runtimeDynamicThemeColors() {
    final runtimeSeed = _runtimeDynamicThemeSeed;
    if (!dynamicThemeEnabled ||
        runtimeSeed == null ||
        _runtimeDynamicThemePage.trim().isEmpty) {
      return null;
    }
    return DynamicThemeMapper.map(
      baseColors: selectedThemeBaseColors,
      seed: runtimeSeed,
      intensity: _dynamicThemeIntensity,
    );
  }

  void _publishRuntimeDynamicThemeToScope() {
    final colors = _runtimeDynamicThemeColors();
    if (colors == null) {
      AppRuntimeColorController.instance.clearRuntimeColors();
      return;
    }
    AppRuntimeColorController.instance.setRuntimeColors(
      pageKey: _runtimeDynamicThemePage,
      colors: colors,
    );
  }

  Future<SharedPreferences> _obtainPrefs({bool refresh = false}) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    if (refresh) {
      await prefs.reload();
    }
    return prefs;
  }

  Future<void> _ensureRuntimeSessionLoaded() async {
    if (_runtimeSessionId.isNotEmpty) {
      return;
    }
    _runtimeSessionId = await RuntimeThemeSessionBridge.instance.getSessionId();
  }

  Future<void> _ensureRuntimeThemeSession(SharedPreferences prefs) async {
    await _ensureRuntimeSessionLoaded();
    if (_runtimeSessionId.isEmpty) {
      return;
    }
    final storedSessionId =
        prefs.getString(_runtimeDynamicSessionIdKey)?.trim() ?? '';
    final hasPersistedRuntimeTheme =
        (prefs.getString(_runtimeDynamicThemePageKey)?.trim().isNotEmpty ??
            false) &&
        prefs.getInt(_runtimeDynamicBackgroundSeedKey) != null;
    if (hasPersistedRuntimeTheme ||
        (storedSessionId.isNotEmpty && storedSessionId != _runtimeSessionId)) {
      await _clearPersistedRuntimeDynamicTheme(prefs);
    }
  }

  void _applyStoredValues(SharedPreferences prefs) {
    _preset = AppThemePresetX.fromStorageValue(prefs.getString(_presetKey));
    _backgroundTone = AppBackgroundToneX.fromStorageValue(
      prefs.getString(_backgroundToneKey),
    );
    _accentTone = AppAccentToneX.fromStorageValue(
      prefs.getString(_accentToneKey),
    );
    _selectionTone = AppAccentToneX.fromStorageValue(
      prefs.getString(_selectionToneKey),
    );
    _linkTone = AppAccentToneX.fromStorageValue(prefs.getString(_linkToneKey));
    _customBackgroundColor = _readColor(prefs, _customBackgroundColorKey);
    _customAccentColor = _readColor(prefs, _customAccentColorKey);
    _customSelectionColor = _readColor(prefs, _customSelectionColorKey);
    _customLinkColor = _readColor(prefs, _customLinkColorKey);
    _dynamicThemeMode = AppDynamicThemeModeX.fromStorageValue(
      prefs.getString(_dynamicThemeModeKey),
    );
    _dynamicThemeIntensity = AppDynamicThemeIntensityX.fromStorageValue(
      prefs.getString(_dynamicThemeIntensityKey),
    );
    _themeSourceType = AppThemeSourceTypeX.fromStorageValue(
      prefs.getString(_themeSourceTypeKey),
    );
    _activeSavedThemeId = prefs.getString(_activeSavedThemeIdKey)?.trim() ?? '';
    _savedThemes = _decodeSavedThemes(prefs.getString(_savedThemesKey));
    if (savedThemeById(_activeSavedThemeId) == null) {
      _activeSavedThemeId = '';
      if (_themeSourceType == AppThemeSourceType.savedCustomTheme) {
        _themeSourceType = AppThemeSourceType.currentCustom;
      }
    }
    final runtimePage =
        prefs.getString(_runtimeDynamicThemePageKey)?.trim() ?? '';
    final backgroundSeed = prefs.getInt(_runtimeDynamicBackgroundSeedKey);
    final accentSeed = prefs.getInt(_runtimeDynamicAccentSeedKey);
    final selectionSeed = prefs.getInt(_runtimeDynamicSelectionSeedKey);
    final linkSeed = prefs.getInt(_runtimeDynamicLinkSeedKey);
    if (runtimePage.isNotEmpty &&
        backgroundSeed != null &&
        accentSeed != null &&
        selectionSeed != null &&
        linkSeed != null) {
      _runtimeDynamicThemePage = runtimePage;
      _runtimeDynamicThemeSeed = DynamicThemeSeed(
        backgroundSeed: Color(backgroundSeed),
        accentSeed: Color(accentSeed),
        selectionSeed: Color(selectionSeed),
        linkSeed: Color(linkSeed),
        preferLightSurface:
            prefs.getBool(_runtimeDynamicPreferLightSurfaceKey) ?? false,
      );
      _runtimeDynamicThemeCache
        ..clear()
        ..[runtimePage] = _runtimeDynamicThemeSeed!;
      _runtimeDynamicThemeOrder
        ..clear()
        ..add(runtimePage);
    } else {
      _runtimeDynamicThemePage = '';
      _runtimeDynamicThemeSeed = null;
      _runtimeDynamicThemeCache.clear();
      _runtimeDynamicThemeOrder.clear();
    }
  }

  void _applyBootstrapSnapshot(_AppThemeBootstrapSnapshot snapshot) {
    _preset = snapshot.preset;
    _backgroundTone = snapshot.backgroundTone;
    _accentTone = snapshot.accentTone;
    _selectionTone = snapshot.selectionTone;
    _linkTone = snapshot.linkTone;
    _customBackgroundColor = snapshot.customBackgroundColor;
    _customAccentColor = snapshot.customAccentColor;
    _customSelectionColor = snapshot.customSelectionColor;
    _customLinkColor = snapshot.customLinkColor;
    _dynamicThemeMode = snapshot.dynamicThemeMode;
    _dynamicThemeIntensity = snapshot.dynamicThemeIntensity;
    _themeSourceType = snapshot.themeSourceType;
    _activeSavedThemeId = snapshot.activeSavedThemeId;
    _savedThemes = snapshot.savedThemes;
    _runtimeDynamicThemePage = snapshot.runtimeDynamicThemePage;
    _runtimeDynamicThemeSeed = snapshot.runtimeDynamicThemeSeed;
    _runtimeDynamicThemeCache
      ..clear()
      ..addAll(snapshot.runtimeDynamicThemeCache);
    _runtimeDynamicThemeOrder
      ..clear()
      ..addAll(snapshot.runtimeDynamicThemeOrder);
    _themeRevision = snapshot.themeRevision;
    _runtimeSessionId = snapshot.runtimeSessionId;
  }

  void _cacheBootstrapSnapshot() {
    _bootstrapSnapshot = _AppThemeBootstrapSnapshot(
      preset: _preset,
      backgroundTone: _backgroundTone,
      accentTone: _accentTone,
      selectionTone: _selectionTone,
      linkTone: _linkTone,
      customBackgroundColor: _customBackgroundColor,
      customAccentColor: _customAccentColor,
      customSelectionColor: _customSelectionColor,
      customLinkColor: _customLinkColor,
      dynamicThemeMode: _dynamicThemeMode,
      dynamicThemeIntensity: _dynamicThemeIntensity,
      themeSourceType: _themeSourceType,
      activeSavedThemeId: _activeSavedThemeId,
      savedThemes: List<SavedCustomTheme>.from(_savedThemes),
      runtimeDynamicThemePage: _runtimeDynamicThemePage,
      runtimeDynamicThemeSeed: _runtimeDynamicThemeSeed,
      runtimeDynamicThemeCache: Map<String, DynamicThemeSeed>.from(
        _runtimeDynamicThemeCache,
      ),
      runtimeDynamicThemeOrder: List<String>.from(_runtimeDynamicThemeOrder),
      themeRevision: _themeRevision,
      runtimeSessionId: _runtimeSessionId,
    );
  }

  void _syncRuntimeThemeFromCache() {
    while (_runtimeDynamicThemeOrder.isNotEmpty &&
        !_runtimeDynamicThemeCache.containsKey(
          _runtimeDynamicThemeOrder.last,
        )) {
      _runtimeDynamicThemeOrder.removeLast();
    }
    if (_runtimeDynamicThemeOrder.isEmpty) {
      _runtimeDynamicThemePage = '';
      _runtimeDynamicThemeSeed = null;
      return;
    }
    final currentPage = _runtimeDynamicThemeOrder.last;
    _runtimeDynamicThemePage = currentPage;
    _runtimeDynamicThemeSeed = _runtimeDynamicThemeCache[currentPage];
  }

  Future<void> _clearPersistedRuntimeDynamicTheme(
    SharedPreferences prefs,
  ) async {
    await prefs.remove(_runtimeDynamicSessionIdKey);
    await prefs.remove(_runtimeDynamicThemePageKey);
    await prefs.remove(_runtimeDynamicBackgroundSeedKey);
    await prefs.remove(_runtimeDynamicAccentSeedKey);
    await prefs.remove(_runtimeDynamicSelectionSeedKey);
    await prefs.remove(_runtimeDynamicLinkSeedKey);
    await prefs.remove(_runtimeDynamicPreferLightSurfaceKey);
  }

  bool _sameRuntimeSeed(DynamicThemeSeed? a, DynamicThemeSeed b) {
    if (a == null) return false;
    return a.backgroundSeed.toARGB32() == b.backgroundSeed.toARGB32() &&
        a.accentSeed.toARGB32() == b.accentSeed.toARGB32() &&
        a.selectionSeed.toARGB32() == b.selectionSeed.toARGB32() &&
        a.linkSeed.toARGB32() == b.linkSeed.toARGB32() &&
        a.preferLightSurface == b.preferLightSurface;
  }

  Future<void> _registerRuntimeThemeSyncHandler() async {
    await RuntimeThemeSyncBridge.instance.registerHandler(this, (call) async {
      switch (call.method) {
        case 'applyRuntimeDynamicTheme':
          final args =
              (call.arguments as Map?)?.cast<dynamic, dynamic>() ??
              const <dynamic, dynamic>{};
          final pageKey = (args['pageKey'] ?? '').toString().trim();
          final seed = _runtimeSeedFromArgs(args);
          if (pageKey.isEmpty || seed == null) {
            return;
          }
          await setRuntimeDynamicTheme(
            pageKey: pageKey,
            seed: seed,
            broadcastToMain: false,
          );
          if (kDebugMode) {
            debugPrint('[THEME][RUNTIME] applied_from_main page=$pageKey');
          }
          return;
        case 'clearRuntimeDynamicTheme':
          final args =
              (call.arguments as Map?)?.cast<dynamic, dynamic>() ??
              const <dynamic, dynamic>{};
          final pageKey = (args['pageKey'] ?? '').toString().trim();
          if (pageKey.isEmpty) {
            return;
          }
          await clearRuntimeDynamicTheme(pageKey, broadcastToMain: false);
          if (kDebugMode) {
            debugPrint('[THEME][RUNTIME] cleared_from_main page=$pageKey');
          }
          return;
      }
    });
    final active = await RuntimeThemeSyncBridge.instance
        .activeRuntimeThemeSnapshot();
    if (active != null) {
      final pageKey = (active['pageKey'] ?? '').toString().trim();
      final seed = _runtimeSeedFromArgs(active);
      if (pageKey.isNotEmpty && seed != null) {
        await setRuntimeDynamicTheme(
          pageKey: pageKey,
          seed: seed,
          broadcastToMain: false,
        );
      }
    }
  }

  DynamicThemeSeed? _runtimeSeedFromArgs(Map<dynamic, dynamic> args) {
    final backgroundSeed = args['backgroundSeed'];
    final accentSeed = args['accentSeed'];
    final selectionSeed = args['selectionSeed'];
    final linkSeed = args['linkSeed'];
    if (backgroundSeed is! int ||
        accentSeed is! int ||
        selectionSeed is! int ||
        linkSeed is! int) {
      return null;
    }
    return DynamicThemeSeed(
      backgroundSeed: Color(backgroundSeed),
      accentSeed: Color(accentSeed),
      selectionSeed: Color(selectionSeed),
      linkSeed: Color(linkSeed),
      preferLightSurface: (args['preferLightSurface'] as bool?) ?? false,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _runtimeThemeApplyToken++;
    _syncTimer?.cancel();
    _runtimeMainClearTimer?.cancel();
    _runtimeTopThemeRemovalTimer?.cancel();
    AppRuntimeColorController.instance.clearRuntimeColors();
    unawaited(RuntimeThemeSyncBridge.instance.unregisterHandler(this));
    super.dispose();
  }
}

class _AppThemeBootstrapSnapshot {
  final AppThemePreset preset;
  final AppBackgroundTone backgroundTone;
  final AppAccentTone accentTone;
  final AppAccentTone selectionTone;
  final AppAccentTone linkTone;
  final Color? customBackgroundColor;
  final Color? customAccentColor;
  final Color? customSelectionColor;
  final Color? customLinkColor;
  final AppDynamicThemeMode dynamicThemeMode;
  final AppDynamicThemeIntensity dynamicThemeIntensity;
  final AppThemeSourceType themeSourceType;
  final String activeSavedThemeId;
  final List<SavedCustomTheme> savedThemes;
  final String runtimeDynamicThemePage;
  final DynamicThemeSeed? runtimeDynamicThemeSeed;
  final Map<String, DynamicThemeSeed> runtimeDynamicThemeCache;
  final List<String> runtimeDynamicThemeOrder;
  final int themeRevision;
  final String runtimeSessionId;

  const _AppThemeBootstrapSnapshot({
    required this.preset,
    required this.backgroundTone,
    required this.accentTone,
    required this.selectionTone,
    required this.linkTone,
    required this.customBackgroundColor,
    required this.customAccentColor,
    required this.customSelectionColor,
    required this.customLinkColor,
    required this.dynamicThemeMode,
    required this.dynamicThemeIntensity,
    required this.themeSourceType,
    required this.activeSavedThemeId,
    required this.savedThemes,
    required this.runtimeDynamicThemePage,
    required this.runtimeDynamicThemeSeed,
    required this.runtimeDynamicThemeCache,
    required this.runtimeDynamicThemeOrder,
    required this.themeRevision,
    required this.runtimeSessionId,
  });
}

class _PresetDefaults {
  final AppBackgroundTone backgroundTone;
  final AppAccentTone accentTone;
  final AppAccentTone selectionTone;
  final AppAccentTone linkTone;

  const _PresetDefaults({
    required this.backgroundTone,
    required this.accentTone,
    required this.selectionTone,
    required this.linkTone,
  });
}
