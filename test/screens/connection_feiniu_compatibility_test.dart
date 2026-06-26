import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/screens/connection_screen.dart';
import 'package:fly_player/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://nas.example.test',
      'user_name': 'alice',
      'password': 'secret',
      'remember_password': true,
    });
  });

  testWidgets('飞牛登录页默认保留历史、FN Connect 和下载入口', (tester) async {
    await tester.pumpWidget(_connectionScreen());
    await tester.pump();

    expect(find.text('飞牛播放器'), findsOneWidget);
    expect(find.byIcon(Icons.history_rounded), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(find.text('查看已下载数据'), findsOneWidget);
    expect(find.text('重新登录 FN Connect'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3));
  });
}

Widget _connectionScreen() {
  return MultiProvider(
    providers: [ChangeNotifierProvider(create: (_) => NasProvider())],
    child: MaterialApp(
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppThemeBuilder.buildFromColors(AppThemePalette.fallback),
      home: const ConnectionScreen(),
    ),
  );
}
