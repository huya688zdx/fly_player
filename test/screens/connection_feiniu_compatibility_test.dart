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

  testWidgets('飞牛登录页默认保留历史、FN Connect 和下载入口', (tester) async {
    await _pumpConnectionScreen(tester, baseUrl: 'https://nas.example.test');
    await tester.pump();

    expect(find.text('飞牛播放器'), findsOneWidget);
    expect(find.byIcon(Icons.history_rounded), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(find.text('查看已下载数据'), findsOneWidget);
    expect(find.text('重新登录 FN Connect'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3));
  });

  testWidgets('飞牛 HTTP 地址显示无协议服务器并选中 HTTP', (tester) async {
    await _pumpConnectionScreen(
      tester,
      baseUrl: 'http://nas.example.test:5667',
    );

    expect(find.text('HTTP'), findsOneWidget);
    expect(find.text('HTTPS'), findsOneWidget);
    final protocolSelector = tester.widget<SegmentedButton<String>>(
      find.byType(SegmentedButton<String>),
    );
    expect(protocolSelector.selected, <String>{'http'});
    expect(_serverField(tester).controller?.text, 'nas.example.test:5667');
  });

  testWidgets('飞牛 HTTPS 地址可明确切回 HTTP', (tester) async {
    await _pumpConnectionScreen(
      tester,
      baseUrl: 'https://nas.example.test:5667',
    );

    expect(
      tester
          .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>))
          .selected,
      <String>{'https'},
    );

    await tester.tap(find.text('HTTP'));
    await tester.pump();

    expect(
      tester
          .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>))
          .selected,
      <String>{'http'},
    );
  });

  testWidgets('粘贴完整 HTTPS 地址时同步协议选择', (tester) async {
    await _pumpConnectionScreen(
      tester,
      baseUrl: 'http://nas.example.test:5667',
    );

    await tester.enterText(
      find.byType(TextField).first,
      'https://other.example.test:7443/path',
    );
    await tester.pump();

    expect(
      tester
          .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>))
          .selected,
      <String>{'https'},
    );
  });
}

Future<void> _pumpConnectionScreen(
  WidgetTester tester, {
  required String baseUrl,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'base_url': baseUrl,
    'user_name': 'alice',
    'password': 'secret',
    'remember_password': true,
  });
  final provider = NasProvider();
  addTearDown(provider.dispose);
  await provider.reloadSettingsForTesting();
  await tester.pumpWidget(
    MultiProvider(
      providers: [ChangeNotifierProvider.value(value: provider)],
      child: MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppThemeBuilder.buildFromColors(AppThemePalette.fallback),
        home: const ConnectionScreen(),
      ),
    ),
  );
  await tester.pump();
}

TextField _serverField(WidgetTester tester) {
  return tester.widgetList<TextField>(find.byType(TextField)).first;
}
