import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/providers/app_theme_provider.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/theme/dynamic_theme_runtime_controller.dart';
import 'package:fly_player/theme/dynamic_theme_seed_extractor.dart';
import 'package:fly_player/ui/route_transition_gate.dart';
import 'package:fly_player/widgets/detail/dynamic_page_theme_scope.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('fly_player/theme_sampler');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await DynamicThemeSeedExtractor.clearCache();
    await DynamicThemeRuntimeController.instance.clearCachedSeeds();
  });

  tearDown(() async {
    RouteTransitionGate.debugResetTransitionOverride();
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    await DynamicThemeSeedExtractor.clearCache();
    await DynamicThemeRuntimeController.instance.clearCachedSeeds();
  });

  testWidgets('headers 更新后旧取色结果不能覆盖新作用域', (tester) async {
    final oldGate = Completer<Map<String, Object>>();
    var oldRequestStarted = false;
    messenger.setMockMethodCallHandler(channel, (call) {
      final args = call.arguments as Map<Object?, Object?>;
      final headers = args['headers'] as Map<Object?, Object?>;
      if (headers['Authorization'] == 'old-token') {
        oldRequestStarted = true;
        return oldGate.future;
      }
      return Future<Map<String, Object>>.value(_greenPixels);
    });
    final provider = AppThemeProvider();
    Color? lastTint;

    Widget buildScope(String token) => _scopeHarness(
      provider: provider,
      token: token,
      onTint: (tint) => lastTint = tint,
    );

    await tester.pumpWidget(buildScope('old-token'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(oldRequestStarted, isTrue);

    await tester.pumpWidget(buildScope('new-token'));
    oldGate.complete(_redPixels);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    expect(lastTint, isNull, reason: '旧 headers 的结果在新请求启动前也不得落地');

    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await _pumpUntil(tester, () => lastTint != null);
    expect(lastTint, isNotNull);

    await _cleanUpWidgetTest(tester, provider);
  });

  testWidgets('转场等待期间 headers 更新后旧 seed 不得落地', (tester) async {
    final transitionGate = Completer<void>();
    final newRequestGate = Completer<Map<String, Object>>();
    RouteTransitionGate.debugOverrideTransition(
      isTransitioning: true,
      wait: transitionGate.future,
    );
    messenger.setMockMethodCallHandler(channel, (call) {
      final args = call.arguments as Map<Object?, Object?>;
      final headers = args['headers'] as Map<Object?, Object?>;
      if (headers['Authorization'] == 'new-token') {
        return newRequestGate.future;
      }
      return Future<Map<String, Object>>.value(_redPixels);
    });
    final provider = AppThemeProvider();
    Color? lastTint;

    Widget buildScope(String token) => _scopeHarness(
      provider: provider,
      token: token,
      onTint: (tint) => lastTint = tint,
    );

    await tester.pumpWidget(buildScope('old-token'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    expect(lastTint, isNull);

    await tester.pumpWidget(buildScope('new-token'));
    RouteTransitionGate.debugOverrideTransition(
      isTransitioning: false,
      wait: transitionGate.future,
    );
    transitionGate.complete();
    await tester.pump();
    expect(lastTint, isNull, reason: '旧 seed 等待转场后不得绕过新 headers 作用域');

    await tester.pump(const Duration(milliseconds: 100));
    newRequestGate.complete(_greenPixels);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await _pumpUntil(tester, () => lastTint != null);
    expect(lastTint, isNotNull);

    await _cleanUpWidgetTest(tester, provider);
  });
}

Widget _scopeHarness({
  required AppThemeProvider provider,
  required String token,
  required ValueChanged<Color?> onTint,
}) {
  return ChangeNotifierProvider<AppThemeProvider>.value(
    value: provider,
    child: MaterialApp(
      theme: AppThemeBuilder.buildFromColors(AppThemePalette.fallback),
      home: DynamicPageThemeScope(
        pageKey: 'same-page',
        imageUrl: 'https://nas.example/same-image.jpg',
        imageHeaders: <String, String>{'Authorization': token},
        enabled: true,
        intensity: AppDynamicThemeIntensity.medium,
        builder: (context, ambientTint) {
          onTint(ambientTint);
          return const SizedBox();
        },
      ),
    ),
  );
}

Future<void> _cleanUpWidgetTest(
  WidgetTester tester,
  AppThemeProvider provider,
) async {
  RouteTransitionGate.debugResetTransitionOverride();
  await tester.pumpWidget(const SizedBox());
  provider.dispose();
  await DynamicThemeSeedExtractor.clearCache();
  await DynamicThemeRuntimeController.instance.clearCachedSeeds();
  debugDefaultTargetPlatformOverride = null;
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 40,
}) async {
  for (var index = 0; index < maxPumps && !condition(); index++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

final Map<String, Object> _redPixels = <String, Object>{
  'pixels': Int32List.fromList(<int>[
    0xFFFF0000,
    0xFFFF0000,
    0xFFFF0000,
    0xFF00FF00,
    0xFF0000FF,
    0xFFFFFFFF,
  ]),
};

final Map<String, Object> _greenPixels = <String, Object>{
  'pixels': Int32List.fromList(<int>[
    0xFF00FF00,
    0xFF00FF00,
    0xFF00FF00,
    0xFFFF0000,
    0xFF0000FF,
    0xFFFFFFFF,
  ]),
};
