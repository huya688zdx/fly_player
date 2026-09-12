import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/providers/backend_session_provider.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/screens/fly_account_screen.dart';
import 'package:fly_player/services/fly_data/fly_account_controller.dart';
import 'package:fly_player/services/fly_data/fly_data_service.dart';
import 'package:fly_player/services/secure_credential_store.dart';
import 'package:fly_player/theme/app_theme.dart';

void main() {
  late _Account account;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SecureCredentialStore.setBackendForTesting(MemorySecureCredentialBackend());
    account = _Account();
  });
  tearDown(() {
    account.dispose();
    account.nas.dispose();
    account.backendSession.dispose();
  });

  Finder activateButton() => find.textContaining(RegExp('切换到此来源|选用 / 切换媒体地址'));

  testWidgets('单客户端地址直接选用，成功后返回原媒体首页', (tester) async {
    await tester.pumpWidget(_app(account, pushed: true));
    await tester.tap(find.text('管理来源'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(activateButton());
    await tester.tap(activateButton());
    await tester.pumpAndSettle();

    expect(find.byType(SimpleDialog), findsNothing);
    expect(account.activations, [('source', 'https://media.example')]);
    expect(find.text('原媒体首页'), findsOneWidget);
    expect(find.byType(FlyBindingsScreen), findsNothing);
  });

  testWidgets('首次入口选用成功不弹出根路由', (tester) async {
    final observer = _Pops();
    await tester.pumpWidget(_app(account, observer: observer));
    await tester.pumpAndSettle();
    await tester.ensureVisible(activateButton());
    await tester.tap(activateButton());
    await tester.pumpAndSettle();

    expect(account.activations, hasLength(1));
    expect(observer.count, 0);
    expect(find.byType(FlyBindingsScreen), findsOneWidget);
    expect(find.text('进入媒体库'), findsOneWidget);
  });

  testWidgets('多地址等用户选择，取消不申请媒体访问', (tester) async {
    account.bindings = [_binding(multiple: true)];
    await tester.pumpWidget(_app(account));
    await tester.pumpAndSettle();
    await tester.ensureVisible(activateButton());
    await tester.tap(activateButton());
    await tester.pumpAndSettle();

    expect(find.byType(SimpleDialog), findsOneWidget);
    expect(account.activations, isEmpty);
    expect(find.textContaining('局域网'), findsWidgets);
    expect(find.textContaining('VPN'), findsWidgets);
    expect(find.textContaining('client_lan'), findsNothing);
    expect(find.textContaining('nas_api'), findsNothing);
    Navigator.of(tester.element(find.byType(SimpleDialog))).pop();
    await tester.pumpAndSettle();
    expect(account.activations, isEmpty);

    await tester.tap(activateButton());
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('https://vpn.example'));
    await tester.pumpAndSettle();
    expect(account.activations, [('source', 'https://vpn.example')]);
  });

  testWidgets('选用失败保留来源页面并展示错误', (tester) async {
    account.rejectActivation = true;
    await tester.pumpWidget(_app(account, pushed: true));
    await tester.tap(find.text('管理来源'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(activateButton());
    await tester.tap(activateButton());
    await tester.pumpAndSettle();

    expect(find.byType(FlyBindingsScreen), findsOneWidget);
    expect(find.textContaining('媒体地址验证失败'), findsWidgets);
  });

  testWidgets('当前来源进入媒体库不重新授权或选地址', (tester) async {
    account.activeBindingId = 'source';
    account.bindings = [_binding(multiple: true)];
    await tester.pumpWidget(_app(account, pushed: true));
    await tester.tap(find.text('管理来源'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('进入媒体库'));
    await tester.tap(find.text('进入媒体库'));
    await tester.pumpAndSettle();

    expect(account.activations, isEmpty);
    expect(find.text('原媒体首页'), findsOneWidget);
    expect(find.byType(SimpleDialog), findsNothing);
  });

  testWidgets('登录表单只在提交时登录并清除密码', (tester) async {
    account.signedIn = false;
    await tester.pumpWidget(_app(account));
    await tester.pumpAndSettle();
    expect(account.logins, isEmpty);
    await tester.enterText(
      find.widgetWithText(TextFormField, '飞翔服务地址'),
      'https://fly.example',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '飞翔账号'),
      'viewer',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '密码'),
      'example-password',
    );
    await tester.ensureVisible(find.text('登录飞翔'));
    await tester.tap(find.text('登录飞翔'));
    await tester.pumpAndSettle();

    expect(account.logins, [
      ('https://fly.example', 'viewer', 'example-password', 'Fly Player'),
    ]);
    expect(
      tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, '密码'))
          .controller!
          .text,
      isEmpty,
    );
  });
}

Widget _app(
  _Account account, {
  bool pushed = false,
  NavigatorObserver? observer,
}) => ChangeNotifierProvider<FlyAccountController>.value(
  value: account,
  child: MaterialApp(
    theme: AppThemeBuilder.build(AppThemePreset.midnight),
    locale: const Locale('zh', 'CN'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    navigatorObservers: [if (observer != null) observer],
    home: pushed
        ? Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  const Text('原媒体首页'),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const FlyBindingsScreen(),
                      ),
                    ),
                    child: const Text('管理来源'),
                  ),
                ],
              ),
            ),
          )
        : const FlyBindingsScreen(),
  ),
);

Map<String, dynamic> _binding({bool multiple = false}) => {
  'id': 'source',
  'label': '家中媒体',
  'status': 'active',
  'revision': 1,
  'remote_username': 'media-viewer',
  'server_id': 'server',
  'server': {
    'kind': 'feiniu',
    'addresses': [
      {'purpose': 'nas_api', 'base_url': 'https://nas-only.example'},
      {'purpose': 'client_lan', 'base_url': 'https://media.example'},
      if (multiple) {'purpose': 'vpn', 'base_url': 'https://vpn.example'},
    ],
  },
};

class _Account extends FlyAccountController {
  _Account()
    : super(
        nas: NasProvider(),
        backendSession: BackendSessionProvider(autoLoad: false),
        autoLoad: false,
      ) {
    ready = true;
    bindings = [_binding()];
  }
  bool signedIn = true, rejectActivation = false;
  final activations = <(String, String?)>[];
  final logins = <(String, String, String, String)>[];
  @override
  FlyDataSession? get session => signedIn
      ? FlyDataSession(
          serverUrl: 'https://fly.example',
          userId: 'viewer',
          username: 'viewer',
          deviceId: 'device',
          deviceName: 'Fly Player',
          token: 'test',
          installationId: 'installation',
          serviceInstanceId: 'instance',
        )
      : null;
  @override
  Future<void> activate(Map<String, dynamic> binding, {String? address}) async {
    activations.add((binding['id'] as String, address));
    if (rejectActivation) {
      message = '媒体地址验证失败';
      notifyListeners();
      throw StateError(message!);
    }
    activeBindingId = binding['id'] as String;
    notifyListeners();
  }

  @override
  Future<void> login({
    required String url,
    required String username,
    required String password,
    required String deviceName,
  }) async {
    logins.add((url, username, password, deviceName));
  }
}

class _Pops extends NavigatorObserver {
  int count = 0;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    count++;
  }
}
