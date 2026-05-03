import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../../providers/app_theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/dynamic_theme_mapper.dart';
import '../../theme/dynamic_theme_runtime_controller.dart';
import '../../theme/dynamic_theme_seed_extractor.dart';

typedef DynamicPageThemeBuilder =
    Widget Function(BuildContext context, Color? ambientTint);

class _DynamicPageThemeBundle {
  final String signature;
  final Color ambientTint;
  final AppThemeColors effectiveColors;
  final ThemeData effectiveTheme;

  const _DynamicPageThemeBundle({
    required this.signature,
    required this.ambientTint,
    required this.effectiveColors,
    required this.effectiveTheme,
  });
}

class DynamicPageThemeScope extends StatefulWidget {
  static const Duration globalSyncLocalApplyDelay = Duration(milliseconds: 32);
  static const Duration globalRuntimeThemeSyncDebounce = Duration(
    milliseconds: 120,
  );

  final String pageKey;
  final String imageUrl;
  final String token;
  final bool enabled;
  final bool allowLiveResolve;
  final bool syncGlobalTheme;
  final bool deferLocalThemeApplyUntilGlobalSync;
  final AppDynamicThemeIntensity intensity;
  final DynamicPageThemeBuilder builder;

  const DynamicPageThemeScope({
    super.key,
    required this.pageKey,
    required this.imageUrl,
    required this.token,
    required this.enabled,
    this.allowLiveResolve = true,
    this.syncGlobalTheme = false,
    this.deferLocalThemeApplyUntilGlobalSync = false,
    required this.intensity,
    required this.builder,
  });

  @override
  State<DynamicPageThemeScope> createState() => _DynamicPageThemeScopeState();
}

class _DynamicPageThemeScopeState extends State<DynamicPageThemeScope> {
  static final Map<String, int> _globalThemeOwnerCounts = <String, int>{};
  static final Set<String> _pendingGlobalClearPageKeys = <String>{};
  static String? _pendingGlobalPageKey;
  static DynamicThemeSeed? _pendingGlobalSeed;
  static Duration? _pendingGlobalLocalNotifyDelay;
  static VoidCallback? _pendingGlobalLocalApply;
  static Timer? _pendingGlobalLocalApplyTimer;
  static Timer? _globalThemeSyncTimer;
  static bool _globalThemeSyncScheduled = false;
  static AppThemeProvider? _globalThemeSyncProvider;

  DynamicThemeSeed? _seed;
  DynamicThemeSeed? _resolvedSeed;
  String _seedPageKey = '';
  String _seedImageUrl = '';
  int _requestVersion = 0;
  Timer? _resolveTimer;
  AppThemeProvider? _themeProvider;
  String _lastSyncedPageKey = '';
  String _lastSyncedSeedSignature = '';
  bool _lastSyncedWasClear = false;
  _DynamicPageThemeBundle? _cachedThemeBundle;
  String? _registeredGlobalThemeKey;
  bool _holdingPreviousGlobalThemeWhileResolving = false;

  @override
  void initState() {
    super.initState();
    _updateGlobalThemeOwnerRegistration();
    _debugLogScopeConfig('init');
    final cachedSeed = DynamicThemeRuntimeController.instance.cachedSeedFor(
      widget.pageKey,
      imageUrl: widget.imageUrl,
    );
    if (cachedSeed != null) {
      _setResolvedSeedForCurrentTarget(cachedSeed);
      if (!widget.deferLocalThemeApplyUntilGlobalSync) {
        _seed = cachedSeed;
      }
    }
    unawaited(_restoreCachedSeedIfNeeded());
    _scheduleResolve();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _themeProvider = context.read<AppThemeProvider>();
    _syncGlobalRuntimeTheme(_resolvedSeed ?? _seed);
  }

  @override
  void didUpdateWidget(covariant DynamicPageThemeScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateGlobalThemeOwnerRegistration(oldWidget: oldWidget);
    final keyChanged = oldWidget.pageKey != widget.pageKey;
    final urlChanged = oldWidget.imageUrl != widget.imageUrl;
    final tokenChanged = oldWidget.token != widget.token;
    final enabledChanged = oldWidget.enabled != widget.enabled;
    final allowLiveResolveChanged =
        oldWidget.allowLiveResolve != widget.allowLiveResolve;
    final syncGlobalThemeChanged =
        oldWidget.syncGlobalTheme != widget.syncGlobalTheme;
    final intensityChanged = oldWidget.intensity != widget.intensity;
    if (keyChanged ||
        urlChanged ||
        tokenChanged ||
        enabledChanged ||
        allowLiveResolveChanged ||
        syncGlobalThemeChanged ||
        intensityChanged) {
      _debugLogScopeConfig('update');
      final cachedSeed = widget.enabled
          ? DynamicThemeRuntimeController.instance.cachedSeedFor(
              widget.pageKey,
              imageUrl: widget.imageUrl,
            )
          : null;
      final keepPreviousSeed =
          cachedSeed == null && _shouldKeepPreviousSeedWhileResolving();
      if (cachedSeed != null) {
        _setResolvedSeedForCurrentTarget(cachedSeed);
        if (!widget.deferLocalThemeApplyUntilGlobalSync) {
          _seed = cachedSeed;
        }
      } else if (!keepPreviousSeed) {
        _clearSeed();
      }
      _syncGlobalRuntimeTheme(_resolvedSeed ?? _seed);
      unawaited(_restoreCachedSeedIfNeeded());
      _scheduleResolve();
    }
  }

  @override
  void dispose() {
    _resolveTimer?.cancel();
    _setGlobalThemeResolveHold(false);
    final globalThemeKeyToClear =
        _registeredGlobalThemeKey ?? _lastSyncedPageKey;
    _releaseGlobalThemeOwnerRegistration();
    if (widget.syncGlobalTheme) {
      _queueGlobalThemeClear(globalThemeKeyToClear);
    }
    super.dispose();
  }

  String? _globalThemeOwnerKeyForWidget(DynamicPageThemeScope scope) {
    if (!scope.syncGlobalTheme) {
      return null;
    }
    final normalizedPageKey = scope.pageKey.trim();
    if (normalizedPageKey.isEmpty) {
      return null;
    }
    return normalizedPageKey;
  }

  void _updateGlobalThemeOwnerRegistration({DynamicPageThemeScope? oldWidget}) {
    final targetKey = _globalThemeOwnerKeyForWidget(widget);
    if (oldWidget == null) {
      if (targetKey == null) {
        return;
      }
      _registeredGlobalThemeKey = targetKey;
      _globalThemeOwnerCounts[targetKey] =
          (_globalThemeOwnerCounts[targetKey] ?? 0) + 1;
      return;
    }
    final previousKey = _registeredGlobalThemeKey;
    if (previousKey == targetKey) {
      return;
    }
    if (previousKey != null) {
      _releaseGlobalThemeOwnerKey(previousKey);
    }
    if (targetKey != null) {
      _registeredGlobalThemeKey = targetKey;
      _globalThemeOwnerCounts[targetKey] =
          (_globalThemeOwnerCounts[targetKey] ?? 0) + 1;
    } else {
      _registeredGlobalThemeKey = null;
    }
  }

  void _releaseGlobalThemeOwnerRegistration() {
    final registeredKey = _registeredGlobalThemeKey;
    if (registeredKey == null) {
      return;
    }
    _registeredGlobalThemeKey = null;
    _releaseGlobalThemeOwnerKey(registeredKey);
  }

  void _releaseGlobalThemeOwnerKey(String pageKey) {
    final currentCount = _globalThemeOwnerCounts[pageKey];
    if (currentCount == null) {
      return;
    }
    if (currentCount <= 1) {
      _globalThemeOwnerCounts.remove(pageKey);
      return;
    }
    _globalThemeOwnerCounts[pageKey] = currentCount - 1;
  }

  void _setGlobalThemeResolveHold(bool shouldHold) {
    final provider = _themeProvider;
    if (shouldHold == _holdingPreviousGlobalThemeWhileResolving) {
      return;
    }
    _holdingPreviousGlobalThemeWhileResolving = shouldHold;
    if (provider == null) {
      return;
    }
    if (shouldHold) {
      provider.acquireRuntimeMainClearHold();
    } else {
      provider.releaseRuntimeMainClearHold();
    }
  }

  void _scheduleResolve() {
    _resolveTimer?.cancel();
    if (!widget.allowLiveResolve) {
      return;
    }
    _resolveTimer = Timer(const Duration(milliseconds: 90), _resolve);
  }

  Future<void> _restoreCachedSeedIfNeeded() async {
    if (!widget.enabled || widget.pageKey.trim().isEmpty) {
      return;
    }
    final targetPageKey = widget.pageKey.trim();
    final targetImageUrl = widget.imageUrl.trim();
    final restored = await DynamicThemeRuntimeController.instance
        .restoreCachedSeed(key: widget.pageKey, imageUrl: widget.imageUrl);
    if (!mounted ||
        !widget.enabled ||
        widget.pageKey.trim() != targetPageKey ||
        widget.imageUrl.trim() != targetImageUrl ||
        restored == null) {
      return;
    }
    _setResolvedSeedForCurrentTarget(restored);
    if (_shouldDeferLocalThemeApply() && widget.syncGlobalTheme) {
      _syncGlobalRuntimeTheme(restored, allowResolveHold: false);
      return;
    }
    if (_seed != restored) {
      setState(() {
        _seed = restored;
      });
    }
    _syncGlobalRuntimeTheme(restored, allowResolveHold: false);
  }

  void _resolve() {
    _requestVersion++;
    final currentVersion = _requestVersion;
    if (!widget.enabled ||
        widget.pageKey.trim().isEmpty ||
        widget.imageUrl.trim().isEmpty) {
      if (_seed != null && mounted) {
        setState(_clearSeed);
      }
      _syncGlobalRuntimeTheme(null, allowResolveHold: false);
      return;
    }

    final cached = DynamicThemeRuntimeController.instance.cachedSeedFor(
      widget.pageKey,
      imageUrl: widget.imageUrl,
    );
    if (cached != null) {
      _setResolvedSeedForCurrentTarget(cached);
      if (_shouldDeferLocalThemeApply() && widget.syncGlobalTheme) {
        _syncGlobalRuntimeTheme(cached, allowResolveHold: false);
        return;
      }
      if (_seed != cached && mounted) {
        setState(() {
          _seed = cached;
        });
      }
      _syncGlobalRuntimeTheme(cached, allowResolveHold: false);
      return;
    }
    if (!widget.allowLiveResolve) {
      _syncGlobalRuntimeTheme(null);
      return;
    }

    DynamicThemeRuntimeController.instance
        .getOrResolve(
          key: widget.pageKey,
          imageUrl: widget.imageUrl,
          token: widget.token,
        )
        .then((seed) {
          if (!mounted ||
              currentVersion != _requestVersion ||
              !widget.enabled) {
            return;
          }
          if (seed != null) {
            _setResolvedSeedForCurrentTarget(seed);
          } else {
            _clearResolvedSeed();
          }
          if (_shouldDeferLocalThemeApply() && widget.syncGlobalTheme) {
            _syncGlobalRuntimeTheme(seed, allowResolveHold: false);
            return;
          }
          if (_seed != seed) {
            setState(() {
              _seed = seed;
              if (seed == null) {
                _clearSeed();
              }
            });
          }
          _syncGlobalRuntimeTheme(seed, allowResolveHold: false);
        });
  }

  bool _shouldKeepPreviousSeedWhileResolving() {
    return widget.enabled &&
        !widget.intensity.usesAmbientOnly &&
        widget.pageKey.trim().isNotEmpty &&
        widget.imageUrl.trim().isNotEmpty &&
        _seed != null;
  }

  bool _seedMatchesCurrentTarget(DynamicThemeSeed? seed) {
    return seed != null &&
        _seedPageKey == widget.pageKey.trim() &&
        _seedImageUrl == widget.imageUrl.trim();
  }

  bool _shouldDeferLocalThemeApply() {
    return widget.deferLocalThemeApplyUntilGlobalSync;
  }

  void _setResolvedSeedForCurrentTarget(DynamicThemeSeed seed) {
    _resolvedSeed = seed;
    _markSeedForCurrentTarget();
  }

  void _clearResolvedSeed() {
    _resolvedSeed = null;
    _seedPageKey = '';
    _seedImageUrl = '';
  }

  void _markSeedForCurrentTarget() {
    _seedPageKey = widget.pageKey.trim();
    _seedImageUrl = widget.imageUrl.trim();
  }

  void _clearSeed() {
    _seed = null;
    _clearResolvedSeed();
  }

  void _debugLogScopeConfig(String phase) {
    debugPrint(
      '[THEME][SCOPE] $phase page=${widget.pageKey.trim()} enabled=${widget.enabled} syncGlobal=${widget.syncGlobalTheme} live=${widget.allowLiveResolve} hasImage=${widget.imageUrl.trim().isNotEmpty} intensity=${widget.intensity.storageValue}',
    );
  }

  void _syncGlobalRuntimeTheme(
    DynamicThemeSeed? seed, {
    bool allowResolveHold = true,
  }) {
    if (!widget.syncGlobalTheme) {
      _setGlobalThemeResolveHold(false);
      return;
    }
    final normalizedPageKey = widget.pageKey.trim();
    final normalizedImageUrl = widget.imageUrl.trim();
    final seedForGlobal = _seedMatchesCurrentTarget(seed) ? seed : null;
    final shouldHoldPreviousTheme =
        allowResolveHold &&
        widget.enabled &&
        normalizedPageKey.isNotEmpty &&
        normalizedImageUrl.isNotEmpty &&
        seedForGlobal == null;
    if (shouldHoldPreviousTheme) {
      debugPrint(
        '[THEME][SCOPE] hold page=$normalizedPageKey awaiting_seed=true',
      );
      _setGlobalThemeResolveHold(true);
      return;
    }
    final holdUntilGlobalApply =
        widget.deferLocalThemeApplyUntilGlobalSync && seedForGlobal != null;
    if (!holdUntilGlobalApply) {
      _setGlobalThemeResolveHold(false);
    }
    final seedSignature = _seedSignature(seedForGlobal);
    if (widget.enabled && seedForGlobal == null && normalizedImageUrl.isEmpty) {
      return;
    }
    final shouldClear = !widget.enabled || seedForGlobal == null;
    if (shouldClear) {
      if (_lastSyncedWasClear && _lastSyncedPageKey == normalizedPageKey) {
        return;
      }
    } else if (_lastSyncedPageKey == normalizedPageKey &&
        _lastSyncedSeedSignature == seedSignature &&
        !_lastSyncedWasClear) {
      return;
    }
    debugPrint(
      '[THEME][SCOPE] queue page=$normalizedPageKey enabled=${widget.enabled} syncGlobal=${widget.syncGlobalTheme} hasSeed=${seedForGlobal != null}',
    );
    if (!widget.enabled || seedForGlobal == null) {
      _clearGlobalTheme(normalizedPageKey);
      return;
    }
    if (normalizedPageKey.isEmpty) {
      return;
    }
    _pendingGlobalClearPageKeys.remove(normalizedPageKey);
    _pendingGlobalPageKey = normalizedPageKey;
    _pendingGlobalSeed = seedForGlobal;
    _pendingGlobalLocalNotifyDelay = widget.deferLocalThemeApplyUntilGlobalSync
        ? DynamicPageThemeScope.globalSyncLocalApplyDelay
        : null;
    _pendingGlobalLocalApply = widget.deferLocalThemeApplyUntilGlobalSync
        ? _buildDeferredLocalThemeApply(
            pageKey: normalizedPageKey,
            imageUrl: normalizedImageUrl,
            seed: seedForGlobal,
          )
        : null;
    _lastSyncedPageKey = normalizedPageKey;
    _lastSyncedSeedSignature = seedSignature;
    _lastSyncedWasClear = false;
    _scheduleGlobalThemeSync();
  }

  VoidCallback _buildDeferredLocalThemeApply({
    required String pageKey,
    required String imageUrl,
    required DynamicThemeSeed seed,
  }) {
    return () {
      if (!mounted ||
          !widget.enabled ||
          widget.pageKey.trim() != pageKey ||
          widget.imageUrl.trim() != imageUrl) {
        return;
      }
      if (_seed == seed) {
        return;
      }
      setState(() {
        _seed = seed;
        _setResolvedSeedForCurrentTarget(seed);
      });
      _setGlobalThemeResolveHold(false);
    };
  }

  void _clearGlobalTheme(String pageKey) {
    _queueGlobalThemeClear(pageKey);
  }

  void _queueGlobalThemeClear(String pageKey) {
    final normalizedPageKey = pageKey.trim();
    if (normalizedPageKey.isEmpty) {
      return;
    }
    if ((_globalThemeOwnerCounts[normalizedPageKey] ?? 0) > 0) {
      return;
    }
    if (_lastSyncedWasClear && _lastSyncedPageKey == normalizedPageKey) {
      return;
    }
    _pendingGlobalClearPageKeys.add(normalizedPageKey);
    debugPrint('[THEME][SCOPE] clear page=$normalizedPageKey');
    if (_pendingGlobalPageKey == normalizedPageKey) {
      _pendingGlobalPageKey = null;
      _pendingGlobalSeed = null;
      _pendingGlobalLocalNotifyDelay = null;
      _pendingGlobalLocalApply = null;
    }
    _lastSyncedPageKey = normalizedPageKey;
    _lastSyncedSeedSignature = '';
    _lastSyncedWasClear = true;
    _scheduleGlobalThemeSync();
  }

  void _scheduleGlobalThemeSync() {
    _globalThemeSyncProvider = _themeProvider ?? _globalThemeSyncProvider;
    _globalThemeSyncScheduled = true;
    _globalThemeSyncTimer?.cancel();
    _globalThemeSyncTimer = Timer(
      DynamicPageThemeScope.globalRuntimeThemeSyncDebounce,
      () {
        _globalThemeSyncTimer = null;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (!_globalThemeSyncScheduled) {
            return;
          }
          _globalThemeSyncScheduled = false;
          _flushGlobalThemeSync();
        });
      },
    );
  }

  void _flushGlobalThemeSync() {
    final provider = _globalThemeSyncProvider ?? _themeProvider;
    if (provider == null) {
      _pendingGlobalClearPageKeys.clear();
      _pendingGlobalPageKey = null;
      _pendingGlobalSeed = null;
      _pendingGlobalLocalNotifyDelay = null;
      _pendingGlobalLocalApply = null;
      return;
    }
    final pendingClearPageKeys = _pendingGlobalClearPageKeys.toList(
      growable: false,
    );
    final pendingPageKey = _pendingGlobalPageKey;
    final pendingSeed = _pendingGlobalSeed;
    final pendingLocalNotifyDelay = _pendingGlobalLocalNotifyDelay;
    final pendingLocalApply = _pendingGlobalLocalApply;
    debugPrint(
      '[THEME][SCOPE] flush clear=${pendingClearPageKeys.length} apply=${pendingPageKey ?? ''}',
    );
    _pendingGlobalClearPageKeys.clear();
    _pendingGlobalPageKey = null;
    _pendingGlobalSeed = null;
    _pendingGlobalLocalNotifyDelay = null;
    _pendingGlobalLocalApply = null;
    _pendingGlobalLocalApplyTimer?.cancel();
    _pendingGlobalLocalApplyTimer = null;
    for (final pageKey in pendingClearPageKeys) {
      unawaited(
        provider.clearRuntimeDynamicTheme(
          pageKey,
          restoreFallbackOnMain: false,
        ),
      );
    }
    if (pendingPageKey != null && pendingSeed != null) {
      unawaited(
        provider.setRuntimeDynamicTheme(
          pageKey: pendingPageKey,
          seed: pendingSeed,
          localNotifyDelayAfterBroadcast: pendingLocalNotifyDelay,
        ),
      );
      if (pendingLocalApply != null) {
        _pendingGlobalLocalApplyTimer = Timer(
          pendingLocalNotifyDelay ?? Duration.zero,
          pendingLocalApply,
        );
      }
    }
  }

  String _seedSignature(DynamicThemeSeed? seed) {
    if (seed == null) {
      return '';
    }
    return <Object>[
      seed.backgroundSeed.toARGB32(),
      seed.accentSeed.toARGB32(),
      seed.selectionSeed.toARGB32(),
      seed.linkSeed.toARGB32(),
      seed.preferLightSurface,
    ].join('|');
  }

  String _themeBundleSignature({
    required ThemeData parentTheme,
    required AppThemeColors baseColors,
    required DynamicThemeSeed seed,
  }) {
    return <Object>[
      widget.intensity.storageValue,
      identityHashCode(parentTheme),
      identityHashCode(baseColors),
      _seedSignature(seed),
    ].join('|');
  }

  _DynamicPageThemeBundle _themeBundleFor({
    required ThemeData parentTheme,
    required AppThemeColors baseColors,
    required DynamicThemeSeed seed,
  }) {
    final signature = _themeBundleSignature(
      parentTheme: parentTheme,
      baseColors: baseColors,
      seed: seed,
    );
    final cached = _cachedThemeBundle;
    if (cached != null && cached.signature == signature) {
      return cached;
    }

    final ambientTint = DynamicThemeMapper.ambientTint(
      baseColors: baseColors,
      seed: seed,
      intensity: widget.intensity,
    );
    final effectiveColors = widget.intensity.usesAmbientOnly
        ? DynamicThemeMapper.mapSubtle(baseColors: baseColors, seed: seed)
        : DynamicThemeMapper.map(
            baseColors: baseColors,
            seed: seed,
            intensity: widget.intensity,
          );
    final effectiveTheme = AppThemeBuilder.buildFromColors(
      effectiveColors,
      baseTheme: parentTheme,
    );
    final bundle = _DynamicPageThemeBundle(
      signature: signature,
      ambientTint: ambientTint,
      effectiveColors: effectiveColors,
      effectiveTheme: effectiveTheme,
    );
    _cachedThemeBundle = bundle;
    return bundle;
  }

  @override
  Widget build(BuildContext context) {
    final parentTheme = Theme.of(context);
    final baseColors = context.baseAppColors;
    final effectiveSeed = widget.enabled ? _seed : null;
    if (effectiveSeed == null) {
      return DynamicPageThemeSnapshot(
        hasDynamicTheme: false,
        effectiveColors: baseColors,
        child: Builder(
          builder: (context) {
            return widget.builder(context, null);
          },
        ),
      );
    }
    final bundle = _themeBundleFor(
      parentTheme: parentTheme,
      baseColors: baseColors,
      seed: effectiveSeed,
    );
    if (widget.intensity.usesAmbientOnly) {
      return Theme(
        data: bundle.effectiveTheme,
        child: DynamicPageThemeSnapshot(
          hasDynamicTheme: true,
          effectiveColors: bundle.effectiveColors,
          child: Builder(
            builder: (context) {
              return widget.builder(context, bundle.ambientTint);
            },
          ),
        ),
      );
    }

    final themedChild = DynamicPageThemeSnapshot(
      hasDynamicTheme: true,
      effectiveColors: bundle.effectiveColors,
      child: Builder(
        builder: (context) {
          return widget.builder(context, bundle.ambientTint);
        },
      ),
    );
    if (widget.deferLocalThemeApplyUntilGlobalSync) {
      return Theme(data: bundle.effectiveTheme, child: themedChild);
    }
    return AnimatedTheme(
      data: bundle.effectiveTheme,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: themedChild,
    );
  }
}
