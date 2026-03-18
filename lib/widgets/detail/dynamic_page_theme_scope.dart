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

class DynamicPageThemeScope extends StatefulWidget {
  final String pageKey;
  final String imageUrl;
  final String token;
  final bool enabled;
  final bool syncGlobalTheme;
  final AppDynamicThemeIntensity intensity;
  final DynamicPageThemeBuilder builder;

  const DynamicPageThemeScope({
    super.key,
    required this.pageKey,
    required this.imageUrl,
    required this.token,
    required this.enabled,
    this.syncGlobalTheme = false,
    required this.intensity,
    required this.builder,
  });

  @override
  State<DynamicPageThemeScope> createState() => _DynamicPageThemeScopeState();
}

class _DynamicPageThemeScopeState extends State<DynamicPageThemeScope> {
  DynamicThemeSeed? _seed;
  int _requestVersion = 0;
  Timer? _resolveTimer;
  AppThemeProvider? _themeProvider;
  final Set<String> _pendingClearPageKeys = <String>{};
  String? _pendingGlobalPageKey;
  DynamicThemeSeed? _pendingGlobalSeed;
  bool _globalThemeSyncScheduled = false;
  String _lastSyncedPageKey = '';
  String _lastSyncedSeedSignature = '';
  bool _lastSyncedWasClear = false;

  @override
  void initState() {
    super.initState();
    _seed = DynamicThemeRuntimeController.instance.cachedSeedFor(
      widget.pageKey,
    );
    _scheduleResolve();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _themeProvider = context.read<AppThemeProvider>();
    _syncGlobalRuntimeTheme(_seed);
  }

  @override
  void didUpdateWidget(covariant DynamicPageThemeScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    final keyChanged = oldWidget.pageKey != widget.pageKey;
    final urlChanged = oldWidget.imageUrl != widget.imageUrl;
    final tokenChanged = oldWidget.token != widget.token;
    final enabledChanged = oldWidget.enabled != widget.enabled;
    if (keyChanged || urlChanged || tokenChanged || enabledChanged) {
      if (keyChanged) {
        _clearGlobalTheme(oldWidget.pageKey);
      }
      _seed = widget.enabled
          ? DynamicThemeRuntimeController.instance.cachedSeedFor(widget.pageKey)
          : null;
      _syncGlobalRuntimeTheme(_seed);
      _scheduleResolve();
    }
  }

  @override
  void dispose() {
    _resolveTimer?.cancel();
    _clearGlobalTheme(widget.pageKey);
    super.dispose();
  }

  void _scheduleResolve() {
    _resolveTimer?.cancel();
    _resolveTimer = Timer(const Duration(milliseconds: 90), _resolve);
  }

  void _resolve() {
    _requestVersion++;
    final currentVersion = _requestVersion;
    if (!widget.enabled ||
        widget.pageKey.trim().isEmpty ||
        widget.imageUrl.trim().isEmpty) {
      if (_seed != null && mounted) {
        setState(() => _seed = null);
      }
      _syncGlobalRuntimeTheme(null);
      return;
    }

    final cached = DynamicThemeRuntimeController.instance.cachedSeedFor(
      widget.pageKey,
    );
    if (cached != null) {
      if (_seed != cached && mounted) {
        setState(() => _seed = cached);
      }
      _syncGlobalRuntimeTheme(cached);
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
          if (_seed != seed) {
            setState(() => _seed = seed);
          }
          _syncGlobalRuntimeTheme(seed);
        });
  }

  void _syncGlobalRuntimeTheme(DynamicThemeSeed? seed) {
    if (!widget.syncGlobalTheme) {
      return;
    }
    final normalizedPageKey = widget.pageKey.trim();
    final seedSignature = _seedSignature(seed);
    final shouldClear = !widget.enabled || seed == null;
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
      '[THEME][SCOPE] sync page=$normalizedPageKey enabled=${widget.enabled} syncGlobal=${widget.syncGlobalTheme} hasSeed=${seed != null}',
    );
    if (!widget.enabled || seed == null) {
      _clearGlobalTheme(normalizedPageKey);
      return;
    }
    if (normalizedPageKey.isEmpty) {
      return;
    }
    _pendingClearPageKeys.remove(normalizedPageKey);
    _pendingGlobalPageKey = normalizedPageKey;
    _pendingGlobalSeed = seed;
    _lastSyncedPageKey = normalizedPageKey;
    _lastSyncedSeedSignature = seedSignature;
    _lastSyncedWasClear = false;
    _scheduleGlobalThemeSync();
  }

  void _clearGlobalTheme(String pageKey) {
    if (!widget.syncGlobalTheme) {
      return;
    }
    final normalizedPageKey = pageKey.trim();
    debugPrint('[THEME][SCOPE] clear page=$normalizedPageKey');
    if (normalizedPageKey.isEmpty) {
      return;
    }
    if (_lastSyncedWasClear && _lastSyncedPageKey == normalizedPageKey) {
      return;
    }
    _pendingClearPageKeys.add(normalizedPageKey);
    if (_pendingGlobalPageKey == normalizedPageKey) {
      _pendingGlobalPageKey = null;
      _pendingGlobalSeed = null;
    }
    _lastSyncedPageKey = normalizedPageKey;
    _lastSyncedSeedSignature = '';
    _lastSyncedWasClear = true;
    _scheduleGlobalThemeSync();
  }

  void _scheduleGlobalThemeSync() {
    if (_globalThemeSyncScheduled) {
      return;
    }
    _globalThemeSyncScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _globalThemeSyncScheduled = false;
      _flushGlobalThemeSync();
    });
  }

  void _flushGlobalThemeSync() {
    final provider = _themeProvider;
    if (provider == null) {
      _pendingClearPageKeys.clear();
      _pendingGlobalPageKey = null;
      _pendingGlobalSeed = null;
      return;
    }
    final pendingClearPageKeys = _pendingClearPageKeys.toList(growable: false);
    final pendingPageKey = _pendingGlobalPageKey;
    final pendingSeed = _pendingGlobalSeed;
    _pendingClearPageKeys.clear();
    _pendingGlobalPageKey = null;
    _pendingGlobalSeed = null;
    for (final pageKey in pendingClearPageKeys) {
      unawaited(provider.clearRuntimeDynamicTheme(pageKey));
    }
    if (pendingPageKey != null && pendingSeed != null) {
      unawaited(
        provider.setRuntimeDynamicTheme(
          pageKey: pendingPageKey,
          seed: pendingSeed,
        ),
      );
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

  @override
  Widget build(BuildContext context) {
    final parentTheme = Theme.of(context);
    final baseColors = context.appColors;
    final effectiveSeed = widget.enabled ? _seed : null;
    if (effectiveSeed == null) {
      return Builder(
        builder: (context) {
          return widget.builder(context, null);
        },
      );
    }
    final effectiveColors = DynamicThemeMapper.map(
      baseColors: baseColors,
      seed: effectiveSeed,
      intensity: widget.intensity,
    );
    final effectiveTheme = AppThemeBuilder.buildFromColors(
      effectiveColors,
      baseTheme: parentTheme,
    );
    final ambientTint = DynamicThemeMapper.ambientTint(
      baseColors: baseColors,
      seed: effectiveSeed,
      intensity: widget.intensity,
    );

    return AnimatedTheme(
      data: effectiveTheme,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: Builder(
        builder: (context) {
          return widget.builder(context, ambientTint);
        },
      ),
    );
  }
}
