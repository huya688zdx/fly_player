import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/ui/app_centered_modal.dart';
import 'package:fly_player/ui/app_popup_theme.dart';
import 'package:fly_player/ui/app_sheet_transitions.dart';
import 'package:fly_player/widgets/common/app_option_list.dart';
import 'package:fly_player/widgets/common/track_option_sheet.dart';

const _base = Color(0xff0055ff);
const _page = Color(0xffffaa00);
const _runtime = Color(0xff9900ff);
const _snapshot = Color(0xff00bb55);
const _updated = Color(0xffbb1144);

ThemeData _theme(Color accent) => AppThemeBuilder.build(
  AppThemePreset.midnight,
).copyWith(extensions: [AppThemePalette.fallback.copyWith(accent: accent)]);

Widget _scopes(
  Widget child, {
  Color theme = _page,
  Color? runtime = _runtime,
  bool runtimeEnabled = true,
  Color snapshot = _snapshot,
  bool snapshotEnabled = true,
}) => Theme(
  data: _theme(theme),
  child: AppRuntimeColorScope(
    colors: runtime == null
        ? null
        : AppThemePalette.fallback.copyWith(accent: runtime),
    hasRuntimeColors: runtimeEnabled,
    child: DynamicPageThemeSnapshot(
      hasDynamicTheme: snapshotEnabled,
      effectiveColors: AppThemePalette.fallback.copyWith(accent: snapshot),
      child: child,
    ),
  ),
);

Map<String, Object?> _inspect(BuildContext context) => {
  'theme': context.baseAppColors.accent,
  'runtime': AppRuntimeColorScope.maybeColorsOf(context)?.accent,
  'runtimeEnabled': context.hasRuntimeAppColors,
  'snapshot': DynamicPageThemeSnapshot.maybeOf(context)?.effectiveColors.accent,
  'snapshotEnabled': DynamicPageThemeSnapshot.maybeOf(context)?.hasDynamicTheme,
  'effective': context.appColors.accent,
};

Future<String?> _open(
  String mode,
  BuildContext context, {
  bool useRootNavigator = false,
}) {
  Widget body(BuildContext context) => const SizedBox(
    key: ValueKey('popup-theme-probe'),
    width: 120,
    height: 120,
  );
  return switch (mode) {
    'adaptive' => AppSheetTransitions.showAdaptiveSheet<String>(
      context,
      useRootNavigator: useRootNavigator,
      builder: body,
    ),
    'bottom' => AppSheetTransitions.showBottomSurface<String>(
      context,
      useRootNavigator: useRootNavigator,
      builder: body,
    ),
    'centered' => AppCenteredModal.show<String>(
      context,
      useRootNavigator: useRootNavigator,
      builder: body,
    ),
    _ => TrackOptionSheet.show(
      context,
      title: 'Popup theme',
      items: const [TrackOptionSheetItem(id: 'chosen', title: 'One')],
    ),
  };
}

Finder _probe(String mode) => mode.startsWith('track')
    ? find.byType(AppOptionSheetPanel)
    : find.byKey(const ValueKey('popup-theme-probe'));

void main() {
  for (final mode in [
    'adaptive',
    'bottom',
    'centered',
    'track_portrait',
    'track_landscape',
  ]) {
    for (final global in [true, false]) {
      testWidgets('$mode preserves ${global ? 'global' : 'page'} themes', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = mode == 'track_landscape'
            ? const Size(900, 500)
            : const Size(390, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        late Map<String, Object?> caller;
        late Future<String?> result;
        final page = Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                caller = _inspect(context);
                result = _open(mode, context);
              },
              child: const Text('Open'),
            ),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: _theme(_base),
            builder: global ? (_, child) => _scopes(child!) : null,
            home: global ? page : _scopes(page),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final sheet = tester.element(_probe(mode));
        final observed = _inspect(sheet);
        Navigator.of(sheet).pop('chosen');
        await tester.pumpAndSettle();
        expect(await result, 'chosen');
        expect(observed, caller);
        expect(AppSheetTransitions.activeSheetCount.value, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('local false and null scopes keep shadowing outer colors', (
    tester,
  ) async {
    late BuildContext caller;
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => _scopes(child!),
        home: _scopes(
          Builder(
            builder: (context) {
              caller = context;
              return const Scaffold();
            },
          ),
          theme: _base,
          runtime: null,
          runtimeEnabled: false,
          snapshotEnabled: false,
        ),
      ),
    );
    final expected = _inspect(caller);
    expect(expected['effective'], _base);
    final result = _open('adaptive', caller);
    await tester.pumpAndSettle();
    final sheet = tester.element(_probe('adaptive'));
    final observed = _inspect(sheet);
    Navigator.of(sheet).pop();
    await tester.pumpAndSettle();
    expect(await result, isNull);
    expect(observed, expected);
  });

  testWidgets('global scopes continue updating while the sheet stays open', (
    tester,
  ) async {
    final color = ValueNotifier(_runtime);
    addTearDown(color.dispose);
    late BuildContext caller;
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => ValueListenableBuilder<Color>(
          valueListenable: color,
          child: child,
          builder: (_, value, child) =>
              _scopes(child!, theme: value, runtime: value, snapshot: value),
        ),
        home: Builder(
          builder: (context) {
            caller = context;
            return const Scaffold();
          },
        ),
      ),
    );
    final result = _open('centered', caller);
    await tester.pumpAndSettle();
    color.value = _updated;
    await tester.pumpAndSettle();
    final sheet = tester.element(_probe('centered'));
    final observed = _inspect(sheet);
    Navigator.of(sheet).pop();
    await tester.pumpAndSettle();
    await result;
    expect(observed, _inspect(caller));
    expect(observed['effective'], _updated);
  });

  for (final root in [false, true]) {
    testWidgets('capture targets the ${root ? 'root' : 'nested'} navigator', (
      tester,
    ) async {
      final color = ValueNotifier(_snapshot);
      addTearDown(color.dispose);
      final rootNavigator = GlobalKey<NavigatorState>();
      final nestedNavigator = GlobalKey<NavigatorState>();
      late BuildContext caller;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigator,
          theme: _theme(_base),
          home: ValueListenableBuilder<Color>(
            valueListenable: color,
            builder: (_, value, child) =>
                _scopes(child!, theme: value, runtime: value, snapshot: value),
            child: Navigator(
              key: nestedNavigator,
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (context) {
                  caller = context;
                  return const Scaffold();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final result = _open('adaptive', caller, useRootNavigator: root);
      await tester.pumpAndSettle();
      expect(rootNavigator.currentState!.canPop(), root);
      expect(nestedNavigator.currentState!.canPop(), !root);
      color.value = _updated;
      await tester.pumpAndSettle();
      final sheet = tester.element(_probe('adaptive'));
      final observed = _inspect(sheet);
      Navigator.of(sheet).pop('chosen');
      await tester.pumpAndSettle();
      expect(await result, 'chosen');
      expect(observed['effective'], root ? _snapshot : _updated);
      expect(observed['runtimeEnabled'], isTrue);
      expect(observed['snapshotEnabled'], isTrue);
    });
  }

  testWidgets('an explicit overlay target needs no Navigator', (tester) async {
    final overlayKey = GlobalKey<OverlayState>();
    late BuildContext caller;
    final entry = OverlayEntry(
      builder: (_) => _scopes(
        Builder(
          builder: (context) {
            caller = context;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Theme(
          data: _theme(_base),
          child: Overlay(key: overlayKey, initialEntries: [entry]),
        ),
      ),
    );
    expect(Navigator.maybeOf(caller), isNull);
    final expected = _inspect(caller);
    final captured = AppPopupTheme.capture(
      caller,
      to: overlayKey.currentContext,
    );
    final popup = OverlayEntry(
      builder: (_) =>
          captured.wrap(const SizedBox(key: ValueKey('overlay-theme-probe'))),
    );
    overlayKey.currentState!.insert(popup);
    await tester.pump();
    final observed = _inspect(
      tester.element(find.byKey(const ValueKey('overlay-theme-probe'))),
    );
    popup.remove();
    popup.dispose();
    entry.remove();
    entry.dispose();
    await tester.pumpWidget(const SizedBox());
    expect(observed, expected);
    expect(tester.takeException(), isNull);
  });
}
