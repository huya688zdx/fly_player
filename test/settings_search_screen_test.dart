import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/l10n/generated/app_localizations_zh.dart';
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
          switch (call.method) {
            case 'isParallelWindowSupported':
              return false;
            case 'getParallelWindowSettings':
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

  testWidgets('设置搜索里的 MPV 详细项使用本地化标题', (tester) async {
    final l10n = AppLocalizationsZh();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppLocaleProvider()),
          ChangeNotifierProvider(create: (_) => AppThemeProvider()),
          ChangeNotifierProvider(
            create: (_) => ParallelWindowSettingsProvider(),
          ),
          ChangeNotifierProvider(create: (_) => StartupPreferencesProvider()),
        ],
        child: const MaterialApp(
          locale: Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AppSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('settings_open_full_search')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'deband');
    await tester.pumpAndSettle();

    expect(find.text(l10n.mpvSettingDebandTitle), findsOneWidget);
    expect(find.text('Deband'), findsNothing);
  });

  testWidgets('设置搜索可通过启动和海报关键词命中启动目的地设置', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppLocaleProvider()),
          ChangeNotifierProvider(create: (_) => AppThemeProvider()),
          ChangeNotifierProvider(
            create: (_) => ParallelWindowSettingsProvider(),
          ),
          ChangeNotifierProvider(create: (_) => StartupPreferencesProvider()),
        ],
        child: const MaterialApp(
          locale: Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AppSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('settings_open_full_search')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '海报首页');
    await tester.pumpAndSettle();

    expect(find.text('启动直达海报首页'), findsOneWidget);
  });
}
