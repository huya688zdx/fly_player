import 'dart:async';

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
  String _runtimeDynamicThemePage = '';
  DynamicThemeSeed? _runtimeDynamicThemeSeed;
  final Map<String, DynamicThemeSeed> _runtimeDynamicThemeCache =
      <String, DynamicThemeSeed>{};
  final List<String> _runtimeDynamicThemeOrder = <String>[];
  bool _isReady = false;
  SharedPreferences? _prefs;
  Timer? _syncTimer;
  int _themeRevision = 0;
  bool _syncInProgress = false;
  String _runtimeSessionId = '';

  AppThemeProvider() {
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
  bool get dynamicThemeEnabled =>
      _dynamicThemeMode == AppDynamicThemeMode.detailsAndPeople;
  String get runtimeDynamicThemePage => _runtimeDynamicThemePage;
  DynamicThemeSeed? get runtimeDynamicThemeSeed => _runtimeDynamicThemeSeed;

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

  String get effectiveThemeTitle => isPresetCustomized ? '自定义' : _preset.title;

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
    final baseColors = themeColors;
    final runtimeSeed = _runtimeDynamicThemeSeed;
    if (!dynamicThemeEnabled || runtimeSeed == null) {
      return baseColors;
    }
    return DynamicThemeMapper.map(
      baseColors: baseColors,
      seed: runtimeSeed,
      intensity: _dynamicThemeIntensity,
    );
  }

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

  Future<void> load() async {
    final prefs = await _obtainPrefs(refresh: true);
    await _ensureRuntimeThemeSession(prefs);
    _applyStoredValues(prefs);
    _themeRevision = prefs.getInt(_themeRevisionKey) ?? _themeRevision;
    _isReady = true;
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
    });
  }

  Future<void> setBackgroundTone(AppBackgroundTone value) async {
    _backgroundTone = value;
    _customBackgroundColor = null;
    await _persist((prefs) async {
      await prefs.setString(_backgroundToneKey, value.storageValue);
      await prefs.remove(_customBackgroundColorKey);
    });
  }

  Future<void> setAccentTone(AppAccentTone value) async {
    _accentTone = value;
    _customAccentColor = null;
    await _persist((prefs) async {
      await prefs.setString(_accentToneKey, value.storageValue);
      await prefs.remove(_customAccentColorKey);
    });
  }

  Future<void> setSelectionTone(AppAccentTone value) async {
    _selectionTone = value;
    _customSelectionColor = null;
    await _persist((prefs) async {
      await prefs.setString(_selectionToneKey, value.storageValue);
      await prefs.remove(_customSelectionColorKey);
    });
  }

  Future<void> setLinkTone(AppAccentTone value) async {
    _linkTone = value;
    _customLinkColor = null;
    await _persist((prefs) async {
      await prefs.setString(_linkToneKey, value.storageValue);
      await prefs.remove(_customLinkColorKey);
    });
  }

  Future<void> setCustomBackgroundColor(Color value) async {
    _customBackgroundColor = value;
    await _persist(
      (prefs) => prefs.setInt(_customBackgroundColorKey, value.toARGB32()),
    );
  }

  Future<void> setCustomAccentColor(Color value) async {
    _customAccentColor = value;
    await _persist(
      (prefs) => prefs.setInt(_customAccentColorKey, value.toARGB32()),
    );
  }

  Future<void> setCustomSelectionColor(Color value) async {
    _customSelectionColor = value;
    await _persist(
      (prefs) => prefs.setInt(_customSelectionColorKey, value.toARGB32()),
    );
  }

  Future<void> setCustomLinkColor(Color value) async {
    _customLinkColor = value;
    await _persist(
      (prefs) => prefs.setInt(_customLinkColorKey, value.toARGB32()),
    );
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
  }) async {
    final normalizedPageKey = pageKey.trim();
    if (normalizedPageKey.isEmpty) return;
    await _ensureRuntimeSessionLoaded();
    debugPrint(
      '[THEME][RUNTIME] set page=$normalizedPageKey broadcast=$broadcastToMain session=$_runtimeSessionId',
    );
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
    final visualChanged =
        previousVisualSignature != _effectiveThemeSignature();
    if (!visualChanged && !broadcastToMain) {
      return;
    }
    if (visualChanged) {
      _isReady = true;
      notifyListeners();
    }
    await _persist(_persistCurrentRuntimeDynamicTheme, false);
    if (broadcastToMain) {
      debugPrint('[THEME][RUNTIME] push_to_main page=$normalizedPageKey');
      await RuntimeThemeSyncBridge.instance.pushRuntimeThemeToMain(
        pageKey: normalizedPageKey,
        backgroundSeed: seed.backgroundSeed.toARGB32(),
        accentSeed: seed.accentSeed.toARGB32(),
        selectionSeed: seed.selectionSeed.toARGB32(),
        linkSeed: seed.linkSeed.toARGB32(),
        preferLightSurface: seed.preferLightSurface,
      );
    }
  }

  Future<void> clearRuntimeDynamicTheme(
    String pageKey, {
    bool broadcastToMain = true,
  }) async {
    final normalizedPageKey = pageKey.trim();
    if (normalizedPageKey.isEmpty) {
      return;
    }
    await _ensureRuntimeSessionLoaded();
    debugPrint(
      '[THEME][RUNTIME] clear page=$normalizedPageKey broadcast=$broadcastToMain session=$_runtimeSessionId',
    );
    final previousVisualSignature = _effectiveThemeSignature();
    final removedFromOrder = _runtimeDynamicThemeOrder.remove(
      normalizedPageKey,
    );
    final removedSeed = _runtimeDynamicThemeCache.remove(normalizedPageKey);
    if (!removedFromOrder && removedSeed == null) return;
    _syncRuntimeThemeFromCache();
    final visualChanged =
        previousVisualSignature != _effectiveThemeSignature();
    if (!visualChanged && !broadcastToMain) {
      return;
    }
    if (visualChanged) {
      _isReady = true;
      notifyListeners();
    }
    await _persist(_persistCurrentRuntimeDynamicTheme, false);
    if (broadcastToMain) {
      debugPrint('[THEME][RUNTIME] clear_on_main page=$normalizedPageKey');
      await RuntimeThemeSyncBridge.instance.clearRuntimeThemeOnMain(
        normalizedPageKey,
      );
    }
  }

  Future<void> _persist(
    Future<void> Function(SharedPreferences prefs) write, [
    bool notify = true,
  ]) async {
    _isReady = true;
    if (notify) {
      notifyListeners();
    }
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await write(prefs);
    final revision = DateTime.now().microsecondsSinceEpoch;
    await prefs.setInt(_themeRevisionKey, revision);
    _themeRevision = revision;
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
      _applyStoredValues(prefs);
      _isReady = true;
      if (previousVisualSignature != _effectiveThemeSignature()) {
        notifyListeners();
      }
    } finally {
      _syncInProgress = false;
    }
  }

  String _effectiveThemeSignature() {
    final parts = <Object?>[
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
    if ((storedSessionId.isEmpty && hasPersistedRuntimeTheme) ||
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

  Future<void> _persistCurrentRuntimeDynamicTheme(
    SharedPreferences prefs,
  ) async {
    final seed = _runtimeDynamicThemeSeed;
    if (_runtimeDynamicThemePage.isEmpty || seed == null) {
      await _clearPersistedRuntimeDynamicTheme(prefs);
      return;
    }
    await _ensureRuntimeSessionLoaded();
    if (_runtimeSessionId.isNotEmpty) {
      await prefs.setString(_runtimeDynamicSessionIdKey, _runtimeSessionId);
    }
    await prefs.setString(
      _runtimeDynamicThemePageKey,
      _runtimeDynamicThemePage,
    );
    await prefs.setInt(
      _runtimeDynamicBackgroundSeedKey,
      seed.backgroundSeed.toARGB32(),
    );
    await prefs.setInt(
      _runtimeDynamicAccentSeedKey,
      seed.accentSeed.toARGB32(),
    );
    await prefs.setInt(
      _runtimeDynamicSelectionSeedKey,
      seed.selectionSeed.toARGB32(),
    );
    await prefs.setInt(_runtimeDynamicLinkSeedKey, seed.linkSeed.toARGB32());
    await prefs.setBool(
      _runtimeDynamicPreferLightSurfaceKey,
      seed.preferLightSurface,
    );
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
          final backgroundSeed = args['backgroundSeed'];
          final accentSeed = args['accentSeed'];
          final selectionSeed = args['selectionSeed'];
          final linkSeed = args['linkSeed'];
          if (pageKey.isEmpty ||
              backgroundSeed is! int ||
              accentSeed is! int ||
              selectionSeed is! int ||
              linkSeed is! int) {
            return;
          }
          await setRuntimeDynamicTheme(
            pageKey: pageKey,
            seed: DynamicThemeSeed(
              backgroundSeed: Color(backgroundSeed),
              accentSeed: Color(accentSeed),
              selectionSeed: Color(selectionSeed),
              linkSeed: Color(linkSeed),
              preferLightSurface:
                  (args['preferLightSurface'] as bool?) ?? false,
            ),
            broadcastToMain: false,
          );
          debugPrint('[THEME][RUNTIME] applied_from_main page=$pageKey');
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
          debugPrint('[THEME][RUNTIME] cleared_from_main page=$pageKey');
          return;
      }
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    unawaited(RuntimeThemeSyncBridge.instance.unregisterHandler(this));
    super.dispose();
  }
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
