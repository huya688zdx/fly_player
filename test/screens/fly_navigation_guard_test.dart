import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/desktop/desktop_environment.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/providers/app_locale_provider.dart';
import 'package:fly_player/providers/app_theme_provider.dart';
import 'package:fly_player/providers/media_backend_provider.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/providers/parallel_window_settings_provider.dart';
import 'package:fly_player/providers/startup_preferences_provider.dart';
import 'package:fly_player/screens/app_settings_screen.dart';
import 'package:fly_player/screens/settings_destination_routes.dart';
import 'package:fly_player/services/secure_credential_store.dart';
import 'package:fly_player/ui/adaptive_detail_navigator.dart';

void main() {
  const embedding = MethodChannel('fly_player/embedding');
  const mainHost = MethodChannel('fly_player/main_host');

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    SecureCredentialStore.setBackendForTesting(MemorySecureCredentialBackend());
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    DesktopEnvironment.debugOverridePlatform = null;
    SecureCredentialStore.resetBackendForTesting();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(embedding, null);
    messenger.setMockMethodCallHandler(mainHost, null);
  });

  testWidgets('Android 账号入口保留当前引擎的账号与媒体会话', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    DesktopEnvironment.debugOverridePlatform = false;
    var nativeSettingsCalls = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(embedding, (call) async {
      if (call.method == 'isParallelWindowSupported') return true;
      return null;
    });
    messenger.setMockMethodCallHandler(mainHost, (call) async {
      if (call.method == 'openPrimarySettings') {
        nativeSettingsCalls++;
        return true;
      }
      return null;
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppLocaleProvider()),
          ChangeNotifierProvider(create: (_) => AppThemeProvider()),
          ChangeNotifierProvider(
            create: (_) => ParallelWindowSettingsProvider(autoLoad: false),
          ),
          ChangeNotifierProvider(
            create: (_) => StartupPreferencesProvider(autoLoad: false),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => Scaffold(body: Text('本引擎:${settings.name}')),
          ),
          home: const AppSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final accountEntry = find.text('账号与媒体来源');
    await tester.ensureVisible(accountEntry);
    await tester.tap(accountEntry);
    await tester.pumpAndSettle();

    expect(nativeSettingsCalls, 0);
    expect(
      find.text('本引擎:${SettingsDestinationRoutes.flyAccount}'),
      findsOneWidget,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('详情预热期间来源失效后不再打开旧条目', (tester) async {
    final observer = _PushObserver();
    late BuildContext navigationContext;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppThemeProvider()),
          ChangeNotifierProvider(create: (_) => NasProvider()),
          ChangeNotifierProvider(
            create: (context) =>
                MediaBackendProvider(context.read<NasProvider>()),
          ),
        ],
        child: MaterialApp(
          navigatorObservers: [observer],
          home: Builder(
            builder: (context) {
              navigationContext = context;
              return const Scaffold(body: Text('原首页'));
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final initialPushes = observer.pushes;
    var current = true;
    var identityChecks = 0;
    var completed = false;
    final pending = AdaptiveDetailNavigator.open<void>(
      navigationContext,
      AdaptiveDetailRequest.item(itemGuid: 'prewarm-old-binding-item'),
      isCurrent: () {
        if (identityChecks++ == 0) {
          // Invalidate after the initial guard, while the real prewarmer yields.
          scheduleMicrotask(() => current = false);
        }
        return current;
      },
    ).then((_) => completed = true);
    await tester.pump();

    expect(current, isFalse);
    expect(identityChecks, greaterThanOrEqualTo(2));
    expect(observer.pushes, initialPushes);
    expect(completed, isTrue);
    expect(find.text('原首页'), findsOneWidget);
    await pending;
    await tester.pump(const Duration(milliseconds: 500));
  });
}

class _PushObserver extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }
}
