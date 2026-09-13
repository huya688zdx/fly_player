import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Carries page-local themes across a route or overlay boundary.
/// Scopes already above the destination remain inherited and keep updating.
class AppPopupTheme {
  const AppPopupTheme._(this._themes, this._runtime, this._snapshot);

  final CapturedThemes _themes;
  final ({AppThemeColors? colors, bool enabled})? _runtime;
  final ({AppThemeColors colors, bool enabled})? _snapshot;

  factory AppPopupTheme.capture(
    BuildContext context, {
    BuildContext? to,
    bool useRootNavigator = false,
  }) {
    final target =
        to ?? Navigator.of(context, rootNavigator: useRootNavigator).context;
    final runtime = context
        .getElementForInheritedWidgetOfExactType<AppRuntimeColorScope>();
    final targetRuntime = target
        .getElementForInheritedWidgetOfExactType<AppRuntimeColorScope>();
    final snapshot = context
        .getElementForInheritedWidgetOfExactType<DynamicPageThemeSnapshot>();
    final targetSnapshot = target
        .getElementForInheritedWidgetOfExactType<DynamicPageThemeSnapshot>();
    final localRuntime = runtime != null && !identical(runtime, targetRuntime)
        ? runtime.widget as AppRuntimeColorScope
        : null;
    final localSnapshot =
        snapshot != null && !identical(snapshot, targetSnapshot)
        ? snapshot.widget as DynamicPageThemeSnapshot
        : null;
    return AppPopupTheme._(
      InheritedTheme.capture(from: context, to: target),
      localRuntime == null
          ? null
          : (
              colors: localRuntime.colors,
              enabled: localRuntime.hasRuntimeColors,
            ),
      localSnapshot == null
          ? null
          : (
              colors: localSnapshot.effectiveColors,
              enabled: localSnapshot.hasDynamicTheme,
            ),
    );
  }

  Widget wrap(Widget child) {
    final runtime = _runtime;
    final snapshot = _snapshot;
    if (runtime != null) {
      child = AppRuntimeColorScope(
        colors: runtime.colors,
        hasRuntimeColors: runtime.enabled,
        child: child,
      );
    }
    if (snapshot != null) {
      child = DynamicPageThemeSnapshot(
        hasDynamicTheme: snapshot.enabled,
        effectiveColors: snapshot.colors,
        child: child,
      );
    }
    return _themes.wrap(child);
  }
}
