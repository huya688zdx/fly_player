import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/api/feiniu_api.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/screens/connection_screen.dart';
import 'package:fly_player/services/login_history_store.dart';
import 'package:fly_player/services/secure_credential_store.dart';
import 'package:fly_player/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('飞牛登录页默认保留历史、FN Connect 和下载入口', (tester) async {
    await _pumpConnectionScreen(tester, baseUrl: 'https://nas.example.test');
    await tester.pump();

    expect(find.text('飞翔播放器'), findsOneWidget);
    expect(find.byIcon(Icons.history_rounded), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(find.text('查看已下载数据'), findsOneWidget);
    expect(find.text('重新登录 FN Connect'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('访问码（可选）'), findsNothing);
    expect(find.byKey(const Key('feiniuAccessCodeField')), findsNothing);
    expect(find.byType(TextField), findsNWidgets(3));

    await _expandFeiniuOptions(tester);
    expect(find.text('访问码（可选）'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('feiniuAccessCodeField')))
          .obscureText,
      isTrue,
    );
    expect(find.byType(TextField), findsNWidgets(4));
  });

  testWidgets('访问码默认遮挡且眼睛按钮可切换明文状态', (tester) async {
    await _pumpConnectionScreen(tester, baseUrl: 'https://nas.example.test');
    await _expandFeiniuOptions(tester);
    final accessCodeFinder = find.byKey(const Key('feiniuAccessCodeField'));
    await tester.ensureVisible(accessCodeFinder);
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(accessCodeFinder).obscureText, isTrue);
    await tester.tap(find.byIcon(Icons.visibility_off_outlined).last);
    await tester.pump();
    expect(tester.widget<TextField>(accessCodeFinder).obscureText, isFalse);
  });

  testWidgets('访问码字段Done动作会提交原值', (tester) async {
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
    await _expandFeiniuOptions(tester);
    final accessCodeFinder = find.byKey(const Key('feiniuAccessCodeField'));
    await tester.ensureVisible(accessCodeFinder);
    await tester.enterText(accessCodeFinder, 'done-access-code');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(submittedAccessCode, 'done-access-code');
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
    await _expandFeiniuOptions(tester);

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

  testWidgets('切换服务器族后返回飞牛会保留尚未提交的访问码', (tester) async {
    await _pumpConnectionScreen(tester, baseUrl: 'https://nas.example.test');
    await _expandFeiniuOptions(tester);
    await tester.enterText(
      find.byKey(const Key('feiniuAccessCodeField')),
      'temporary-access-code',
    );

    await tester.tap(find.text('Emby'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(3));

    await tester.tap(find.text('飞牛影视'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('feiniuAccessCodeField')), findsNothing);
    await _expandFeiniuOptions(tester);
    final accessCodeField = tester.widget<TextField>(
      find.byKey(const Key('feiniuAccessCodeField')),
    );
    expect(accessCodeField.controller!.text, 'temporary-access-code');
  });

  testWidgets('选择历史会回填飞牛访问码并在服务器族条目时清空', (tester) async {
    const feiniuHistory = LoginHistoryEntry(
      baseUrl: 'https://history-feiniu.example.test',
      userName: 'history-user',
      password: 'history-password',
      accessCode: 'history-access-code',
      rememberPassword: true,
      updatedAtMillis: 2,
    );
    const embyHistory = LoginHistoryEntry(
      kind: MediaBackendKind.emby,
      baseUrl: 'https://history-emby.example.test',
      userName: 'emby-user',
      password: 'emby-password',
      rememberPassword: true,
      updatedAtMillis: 1,
    );
    await _pumpConnectionScreen(
      tester,
      baseUrl: 'https://nas.example.test',
      historyEntries: const <LoginHistoryEntry>[feiniuHistory, embyHistory],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.history_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text(feiniuHistory.baseUrl));
    await tester.pumpAndSettle();
    await _expandFeiniuOptions(tester);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('feiniuAccessCodeField')))
          .controller!
          .text,
      feiniuHistory.accessCode,
    );

    await tester.tap(find.byIcon(Icons.history_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text(embyHistory.baseUrl));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(3));

    await tester.tap(find.text('飞牛影视'));
    await tester.pumpAndSettle();
    await _expandFeiniuOptions(tester);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('feiniuAccessCodeField')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('飞牛裸地址登录默认提交 HTTPS', (tester) async {
    String? submittedBaseUrl;
    await _pumpConnectionScreen(
      tester,
      baseUrl: '',
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
    await tester.enterText(
      find.byKey(const Key('connectionServerAddressField')),
      'nas.example.test:5667',
    );
    await tester.enterText(
      find.byKey(const Key('connectionUserNameField')),
      'alice',
    );
    await tester.enterText(
      find.byKey(const Key('connectionPasswordField')),
      'secret',
    );
    await tester.tap(find.byKey(const Key('connectionSubmitButton')));
    await tester.pumpAndSettle();
    expect(submittedBaseUrl, 'https://nas.example.test:5667');
  });

  testWidgets('飞牛显式 HTTP 地址保持 HTTP', (tester) async {
    String? submittedBaseUrl;
    await _pumpConnectionScreen(
      tester,
      baseUrl: '',
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
    await tester.enterText(
      find.byKey(const Key('connectionServerAddressField')),
      'http://nas.example.test:5667',
    );
    await tester.enterText(
      find.byKey(const Key('connectionUserNameField')),
      'alice',
    );
    await tester.enterText(
      find.byKey(const Key('connectionPasswordField')),
      'secret',
    );
    await tester.tap(find.byKey(const Key('connectionSubmitButton')));
    await tester.pumpAndSettle();
    expect(submittedBaseUrl, 'http://nas.example.test:5667');
  });

  testWidgets('320dp 大字体下地址输入不溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpConnectionScreen(
      tester,
      baseUrl: '',
      textScaler: const TextScaler.linear(1.6),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('首次进入不预填真实服务器地址', (tester) async {
    await _pumpConnectionScreen(tester, baseUrl: '');

    final field = tester.widget<TextField>(
      find.byKey(const Key('connectionServerAddressField')),
    );
    expect(field.controller!.text, isEmpty);
    expect(field.decoration!.hintText, isNot(contains('geqian688')));
    expect(field.decoration!.hintText, isNot(contains('feiniu.geqian.sbs')));
  });

  testWidgets('飞牛更多选项展开并在切换服务后收起', (tester) async {
    await _pumpConnectionScreen(tester, baseUrl: '');

    expect(find.byKey(const Key('feiniuAccessCodeField')), findsNothing);

    await tester.tap(find.byKey(const Key('feiniuAdvancedOptionsButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('feiniuAccessCodeField')), findsOneWidget);

    await tester.tap(find.text('Emby'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('feiniuAccessCodeField')), findsNothing);

    await tester.tap(find.text('飞牛影视'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('feiniuAccessCodeField')), findsNothing);
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
  List<LoginHistoryEntry> historyEntries = const <LoginHistoryEntry>[],
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  NasProvider.resetBootstrapForTesting();
  SecureCredentialStore.setBackendForTesting(MemorySecureCredentialBackend());
  addTearDown(() {
    SecureCredentialStore.resetBackendForTesting();
    NasProvider.resetBootstrapForTesting();
  });
  SharedPreferences.setMockInitialValues(<String, Object>{
    'base_url': baseUrl,
    'user_name': 'alice',
    'password': 'secret',
    'remember_password': true,
  });
  final provider = NasProvider();
  addTearDown(provider.dispose);
  await provider.reloadSettingsForTesting();
  await LoginHistoryStore.clear();
  for (final entry in historyEntries) {
    await LoginHistoryStore.save(entry);
  }
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

Future<void> _expandFeiniuOptions(WidgetTester tester) async {
  final button = find.byKey(const Key('feiniuAdvancedOptionsButton'));
  if (find.byKey(const Key('feiniuAccessCodeField')).evaluate().isEmpty) {
    await tester.tap(button);
    await tester.pumpAndSettle();
  }
}
