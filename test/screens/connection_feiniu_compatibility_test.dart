import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/api/feiniu_api.dart';
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
    expect(find.text('访问码（可选）'), findsOneWidget);
    expect(find.byKey(const Key('feiniuAccessCodeField')), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(4));
  });

  testWidgets('飞牛登录会将访问码原值传给回调', (tester) async {
    String? submittedAccessCode;
    await _pumpConnectionScreen(
      tester,
      baseUrl: 'https://nas.example.test',
      feiniuLogin:
          ({
            required baseUrl,
            required userName,
            required password,
            required accessCode,
          }) async {
            submittedAccessCode = accessCode;
            return LoginWithBaseUrlResult(
              token: 'token',
              resolvedBaseUrl: baseUrl,
            );
          },
    );

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(2), 'secret');
    await tester.enterText(
      find.byKey(const Key('feiniuAccessCodeField')),
      '  2468 ',
    );
    await tester.ensureVisible(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(submittedAccessCode, '  2468 ');
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

  testWidgets('粘贴 HTTPS 地址后选择 HTTP 会以 HTTP 提交', (tester) async {
    final submittedBaseUrl = await _submitPastedAddress(
      tester,
      pastedAddress: 'https://other.example.test:7443/path',
      selectedProtocol: 'HTTP',
    );

    expect(submittedBaseUrl, 'http://other.example.test:7443/path');
  });

  testWidgets('粘贴 HTTP 地址后选择 HTTPS 会以 HTTPS 提交', (tester) async {
    final submittedBaseUrl = await _submitPastedAddress(
      tester,
      pastedAddress: 'http://other.example.test:7443/path',
      selectedProtocol: 'HTTPS',
    );

    expect(submittedBaseUrl, 'https://other.example.test:7443/path');
  });

  testWidgets('320dp 大字体下协议选择不溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpConnectionScreen(
      tester,
      baseUrl: 'http://nas.example.test:5667',
      textScaler: const TextScaler.linear(1.6),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpConnectionScreen(
  WidgetTester tester, {
  required String baseUrl,
  Future<LoginWithBaseUrlResult> Function({
    required String baseUrl,
    required String userName,
    required String password,
    required String accessCode,
  })?
  feiniuLogin,
  TextScaler textScaler = TextScaler.noScaling,
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
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          );
        },
        home: ConnectionScreen(feiniuLogin: feiniuLogin),
      ),
    ),
  );
  await tester.pump();
}

TextField _serverField(WidgetTester tester) {
  return tester.widgetList<TextField>(find.byType(TextField)).first;
}

Future<String?> _submitPastedAddress(
  WidgetTester tester, {
  required String pastedAddress,
  required String selectedProtocol,
}) async {
  String? submittedBaseUrl;
  await _pumpConnectionScreen(
    tester,
    baseUrl: 'https://nas.example.test:5667',
    feiniuLogin:
        ({
          required baseUrl,
          required userName,
          required password,
          required accessCode,
        }) async {
          submittedBaseUrl = baseUrl;
          return LoginWithBaseUrlResult(
            token: 'token',
            resolvedBaseUrl: baseUrl,
          );
        },
  );

  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), pastedAddress);
  await tester.enterText(fields.at(1), 'alice');
  await tester.enterText(fields.at(2), 'secret');
  await tester.tap(find.text(selectedProtocol));
  await tester.pump();
  await tester.ensureVisible(find.byType(ElevatedButton));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(ElevatedButton));
  await tester.pumpAndSettle();
  return submittedBaseUrl;
}
