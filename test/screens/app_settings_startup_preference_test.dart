import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/providers/app_locale_provider.dart';
import 'package:fly_player/providers/app_theme_provider.dart';
import 'package:fly_player/providers/parallel_window_settings_provider.dart';
import 'package:fly_player/providers/startup_preferences_provider.dart';
import 'package:fly_player/screens/app_settings_screen.dart';

void main() {
  const embeddingChannel = MethodChannel('fly_player/embedding');

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(embeddingChannel, (call) async {
          if (call.method == 'isParallelWindowSupported') return false;
          if (call.method == 'getParallelWindowSettings') {
            return <String, Object>{
              'enabled': false,
              'preferredPrimaryPaneSide': 'left',
              'preferredPlaybackPrimaryPaneSide': 'right',
              'splitRatioPreset': 'balanced',
              'defaultPlaybackFullscreen': true,
              'immersiveStatusBar': true,
            };
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(embeddingChannel, null);
  });

  testWidgets('设置首页显示启动直达海报首页开关并可立即保存', (tester) async {
    var saved = false;
    final startupPreferences = StartupPreferencesProvider(
      autoLoad: false,
      loadPreference: () async => false,
      savePreference: (value) async {
        saved = value;
        return true;
      },
    );
    await startupPreferences.load();

    await tester.pumpWidget(_settingsApp(startupPreferences));
    await tester.pumpAndSettle();

    expect(find.text('启动直达海报首页'), findsOneWidget);
    expect(find.text('已有有效登录会话时，打开应用直接进入沉浸式海报浏览。'), findsOneWidget);
    final switchFinder = find.byKey(
      const ValueKey<String>('startup_poster_home_switch'),
    );
    expect(switchFinder, findsOneWidget);
    expect(tester.widget<Switch>(switchFinder).value, isFalse);

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(startupPreferences.openPosterHomeOnStartup, isTrue);
    expect(saved, isTrue);
  });
}

Widget _settingsApp(StartupPreferencesProvider startupPreferences) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AppLocaleProvider()),
      ChangeNotifierProvider(create: (_) => AppThemeProvider()),
      ChangeNotifierProvider(create: (_) => ParallelWindowSettingsProvider()),
      ChangeNotifierProvider<StartupPreferencesProvider>.value(
        value: startupPreferences,
      ),
    ],
    child: const MaterialApp(
      locale: Locale('zh', 'CN'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AppSettingsScreen(),
    ),
  );
}
