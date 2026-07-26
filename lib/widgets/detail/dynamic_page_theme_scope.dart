import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../../providers/app_theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/dynamic_theme_mapper.dart';
import '../../theme/dynamic_theme_runtime_controller.dart';
import '../../theme/dynamic_theme_seed_extractor.dart';
import '../../ui/route_transition_gate.dart';

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

class _GlobalSyncEntry {
  final DynamicThemeSeed seed;
  final Duration? localNotifyDelay;
  final VoidCallback? localApply;

  _GlobalSyncEntry({
    required this.seed,
    this.localNotifyDelay,
    this.localApply,
  });
}

class _DynamicPageThemeScopeState extends State<DynamicPageThemeScope> {
  static final Map<String, int> _globalThemeOwnerCounts = <String, int>{};
  static final Set<String> _pendingGlobalClearPageKeys = <String>{};
  static final Map<String, _GlobalSyncEntry> _pendingGlobalSyncs =
      <String, _GlobalSyncEntry>{};
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
          // 数据到达触发的 props 变化常落在 380ms 进场转场内（详情接口
          // 100-400ms 返回），此处直接翻 _seed 会绕过 _applyResolvedSeedSetState
          // 的转场闸门，在转场中段引发整页 Theme 切换；转场中改为推迟应用。
          if (_seed != cachedSeed &&
              RouteTransitionGate.isTransitioning(context)) {
            unawaited(_applyResolvedSeedAfterTransition(cachedSeed));
          } else {
            _seed = cachedSeed;
          }
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
    _releaseGlobalThemeOwnerRegistration();
    // Sticky runtime theme: do NOT clear the global theme on tear-down. Once a
    // page has sampled a color it persists until another page samples a new one
    // (or the app restarts). This means popping back to a page that does not
    // sample (e.g. a season page) keeps the host on the last sampled color
    // instead of resetting to the base theme. It also removes the synchronous
    // post-frame flush + full theme-tree rebuild that previously ran during the
    // pop animation, which was a source of dropped frames on page transitions.
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
    _applyResolvedSeedSetState(restored);
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
      _applyResolvedSeedSetState(cached);
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
          _applyResolvedSeedSetState(seed);
          _syncGlobalRuntimeTheme(seed, allowResolveHold: false);
        });
  }

  // 异步解析得到的 seed 应用到本地（setState 触发 AnimatedTheme + tint 动画，P2）。
  // 若本页正处于进入转场中，推迟到转场结束再 setState，避免与 enter 动画叠加。
  // 注意：initState 命中缓存的同步路径不经此处——它直接赋值 _seed，使第一帧即终态。
  void _applyResolvedSeedSetState(DynamicThemeSeed? seed) {
    if (!mounted || _seed == seed) {
      return;
    }
    if (RouteTransitionGate.isTransitioning(context)) {
      unawaited(_applyResolvedSeedAfterTransition(seed));
      return;
    }
    setState(() {
      _seed = seed;
      if (seed == null) {
        _clearSeed();
      }
    });
  }

  Future<void> _applyResolvedSeedAfterTransition(DynamicThemeSeed? seed) async {
    await RouteTransitionGate.of(context);
    if (!mounted || _seed == seed) {
      return;
    }
    setState(() {
      _seed = seed;
      if (seed == null) {
        _clearSeed();
      }
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
    _warmUpSeedScheme(seed);
  }

  // Warm the HCT-derived color schemes for this seed on an idle microtask so
  // the build that applies the theme doesn't run the solver inside the frame.
  void _warmUpSeedScheme(DynamicThemeSeed seed) {
    scheduleMicrotask(() {
      if (!mounted) {
        return;
      }
      DynamicThemeMapper.warmUp(
        baseColors: context.baseAppColors,
        seed: seed,
        intensity: widget.intensity,
      );
    });
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
    if (!kDebugMode) return;
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
      if (kDebugMode) {
        debugPrint(
          '[THEME][SCOPE] hold page=$normalizedPageKey awaiting_seed=true',
        );
      }
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
    if (kDebugMode) {
      debugPrint(
        '[THEME][SCOPE] queue page=$normalizedPageKey enabled=${widget.enabled} syncGlobal=${widget.syncGlobalTheme} hasSeed=${seedForGlobal != null}',
      );
    }
    if (!widget.enabled || seedForGlobal == null) {
      _clearGlobalTheme(normalizedPageKey);
      return;
    }
    if (normalizedPageKey.isEmpty) {
      return;
    }
    _pendingGlobalClearPageKeys.remove(normalizedPageKey);
    _pendingGlobalSyncs[normalizedPageKey] = _GlobalSyncEntry(
      seed: seedForGlobal,
      localNotifyDelay: widget.deferLocalThemeApplyUntilGlobalSync
          ? DynamicPageThemeScope.globalSyncLocalApplyDelay
          : null,
      localApply: widget.deferLocalThemeApplyUntilGlobalSync
          ? _buildDeferredLocalThemeApply(
              pageKey: normalizedPageKey,
              imageUrl: normalizedImageUrl,
              seed: seedForGlobal,
            )
          : null,
    );
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

  void _queueGlobalThemeClear(String pageKey, {bool flushImmediate = false}) {
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
    if (kDebugMode) {
      debugPrint('[THEME][SCOPE] clear page=$normalizedPageKey');
    }
    _pendingGlobalSyncs.remove(normalizedPageKey);
    _lastSyncedPageKey = normalizedPageKey;
    _lastSyncedSeedSignature = '';
    _lastSyncedWasClear = true;
    if (flushImmediate) {
      _scheduleGlobalThemeSyncImmediate();
    } else {
      _scheduleGlobalThemeSync();
    }
  }

  void _scheduleGlobalThemeSyncImmediate() {
    _globalThemeSyncProvider = _themeProvider ?? _globalThemeSyncProvider;
    _globalThemeSyncScheduled = true;
    _globalThemeSyncTimer?.cancel();
    _globalThemeSyncTimer = null;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _flushGlobalThemeSyncWhenStable();
    });
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
          _flushGlobalThemeSyncWhenStable();
        });
      },
    );
  }

  // 全局运行时主题同步会重建 MaterialApp.builder 之下整棵 App 树（P3）。若此刻有
  // 路由正在转场（enter/exit），把 flush 推迟到下一帧重查，直到没有转场再执行，
  // 避免整树重建落在 380ms 转场窗口内。进入与退出两条路径都经此收口。
  static void _flushGlobalThemeSyncWhenStable() {
    if (!_globalThemeSyncScheduled) {
      return;
    }
    if (RouteTransitionGate.anyRouteTransitioning) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _flushGlobalThemeSyncWhenStable();
      });
      return;
    }
    _globalThemeSyncScheduled = false;
    _flushGlobalThemeSyncStatic();
  }

  static void _flushGlobalThemeSyncStatic() {
    final provider = _globalThemeSyncProvider;
    if (provider == null) {
      _pendingGlobalClearPageKeys.clear();
      _pendingGlobalSyncs.clear();
      return;
    }
    final pendingClearPageKeys = _pendingGlobalClearPageKeys.toList(
      growable: false,
    );
    final pendingSyncs = Map<String, _GlobalSyncEntry>.from(
      _pendingGlobalSyncs,
    );
    if (kDebugMode) {
      debugPrint(
        '[THEME][SCOPE] flush clear=${pendingClearPageKeys.length} apply=${pendingSyncs.length}',
      );
    }
    _pendingGlobalClearPageKeys.clear();
    _pendingGlobalSyncs.clear();
    // Process clears — skip pageKeys that also have a pending set.
    for (final pageKey in pendingClearPageKeys) {
      if (pendingSyncs.containsKey(pageKey)) continue;
      unawaited(
        provider.clearRuntimeDynamicTheme(
          pageKey,
          restoreFallbackOnMain: true,
          localNotifyDelayAfterBroadcast:
              DynamicPageThemeScope.globalSyncLocalApplyDelay,
        ),
      );
    }
    // Store all seeds in the provider so fallback works after a top clear.
    final batchedLocalApplies = <VoidCallback>[];
    for (final MapEntry<String, _GlobalSyncEntry> mapEntry
        in pendingSyncs.entries) {
      final pageKey = mapEntry.key;
      final syncEntry = mapEntry.value;
      unawaited(
        provider.setRuntimeDynamicTheme(
          pageKey: pageKey,
          seed: syncEntry.seed,
          localNotifyDelayAfterBroadcast: syncEntry.localNotifyDelay,
        ),
      );
      if (syncEntry.localApply != null) {
        batchedLocalApplies.add(syncEntry.localApply!);
      }
    }
    // Fire all deferred-local-apply callbacks in a single post-frame callback
    // so every scope updates its _seed in the same frame.
    if (batchedLocalApplies.isNotEmpty) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        for (final apply in batchedLocalApplies) {
          apply();
        }
      });
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
    final Color? ambientTint;
    final AppThemeColors effectiveColors;
    final ThemeData? effectiveTheme;
    if (effectiveSeed == null) {
      ambientTint = null;
      effectiveColors = baseColors;
      effectiveTheme = null;
    } else {
      final bundle = _themeBundleFor(
        parentTheme: parentTheme,
        baseColors: baseColors,
        seed: effectiveSeed,
      );
      ambientTint = bundle.ambientTint;
      effectiveColors = bundle.effectiveColors;
      effectiveTheme = bundle.effectiveTheme;
    }
    final hasTheme = effectiveSeed != null;
    // seed 已在转场结束后单次应用（Phase 1），ambientTint 随之一次性给定，不再做 140ms
    // 过渡动画——旧的每 tick setState 重建整页（含全部 sliver）是进详情页掉帧的最大单点。
    Widget child = DynamicPageThemeSnapshot(
      hasDynamicTheme: hasTheme,
      effectiveColors: effectiveColors,
      child: Builder(
        builder: (context) => widget.builder(context, ambientTint),
      ),
    );
    // 始终包一层 Theme（无 seed 时透传 parentTheme）：让 seed null→非 null
    // 只是 Theme.data 变化而非元素树结构变化，否则整棵页面子树会被 re-inflate
    // （State 全部重建），恰在主题落地那一帧放大构建成本。
    // 直接切 ThemeData，不做 AnimatedTheme 每帧 lerp（旧 140ms 动画 = P2）。
    child = Theme(data: effectiveTheme ?? parentTheme, child: child);
    return child;
  }
}
