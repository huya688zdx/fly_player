import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/screens/login_history_screen.dart';
import 'package:fly_player/services/login_history_store.dart';
import 'package:fly_player/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  const feiniuEntry = LoginHistoryEntry(
    baseUrl: 'https://aliyun.bffss.cn',
    userName: 'geqian688',
    password: 'pw',
    rememberPassword: true,
    updatedAtMillis: 2,
  );
  const embyEntry = LoginHistoryEntry(
    kind: MediaBackendKind.emby,
    baseUrl: 'http://100.125.130.96:8096',
    userName: 'geqian688',
    password: 'pw',
    rememberPassword: true,
    updatedAtMillis: 1,
  );

  Widget host(List<LoginHistoryEntry> entries) {
    return MaterialApp(
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppThemeBuilder.buildFromColors(AppThemePalette.fallback),
      home: LoginHistoryScreen(entries: entries),
    );
  }

  testWidgets('统一列表同时渲染飞牛与 Emby 历史，各带后端 logo', (tester) async {
    await tester.pumpWidget(host(<LoginHistoryEntry>[feiniuEntry, embyEntry]));
    await tester.pumpAndSettle();

    expect(find.text('https://aliyun.bffss.cn'), findsOneWidget);
    expect(find.text('http://100.125.130.96:8096'), findsOneWidget);
    expect(find.byType(BackendLogo), findsNWidgets(2));
  });

  testWidgets('点击历史条目回传该条目', (tester) async {
    LoginHistoryEntry? popped;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppThemeBuilder.buildFromColors(AppThemePalette.fallback),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  popped = await Navigator.of(context).push<LoginHistoryEntry>(
                    MaterialPageRoute(
                      builder: (_) => const LoginHistoryScreen(
                        entries: <LoginHistoryEntry>[embyEntry],
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('http://100.125.130.96:8096'));
    await tester.pumpAndSettle();

    expect(popped, isNotNull);
    expect(popped!.kind, MediaBackendKind.emby);
    expect(popped!.baseUrl, 'http://100.125.130.96:8096');
  });
}
