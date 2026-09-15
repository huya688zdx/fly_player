import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/desktop/desktop_environment.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/main.dart';
import 'package:fly_player/providers/backend_session_provider.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/screens/connection_screen.dart';
import 'package:fly_player/screens/fly_account_screen.dart';
import 'package:fly_player/services/fly_data/fly_account_controller.dart';
import 'package:fly_player/services/fly_data/fly_data_service.dart';
import 'package:fly_player/services/play_stats/play_stats_service.dart';
import 'package:fly_player/services/login_history_store.dart';
import 'package:fly_player/services/secure_credential_store.dart';
import 'package:fly_player/theme/app_theme.dart';

const _captureDir = String.fromEnvironment('FLY_LOGIN_CAPTURE_DIR');
const _captureFont = String.fromEnvironment('FLY_UI_FONT');
const _captureKey = ValueKey('fly-login-preview');

void main() {
  setUpAll(() async {
    if (_captureDir.isEmpty) return;
    if (_captureFont.isEmpty) throw StateError('Captures need a real font');
    await (FontLoader(
          'FlyLoginPreview',
        )..addFont(File(_captureFont).readAsBytes().then(ByteData.sublistView)))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'app_locale_mode': 'zh-CN'});
    SecureCredentialStore.setBackendForTesting(MemorySecureCredentialBackend());
    DesktopEnvironment.debugOverridePlatform = false;
  });
  tearDown(() {
    DesktopEnvironment.debugOverridePlatform = null;
    SecureCredentialStore.resetBackendForTesting();
  });

  testWidgets('暂用本地媒体后可从真实入口切回飞翔登录且不带入媒体密码', (tester) async {
    await tester.pumpWidget(const FlyPlayerApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('媒体账号登录'));
    await tester.tap(find.text('媒体账号登录'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionScreen), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(2), 'local-only-fixture');
    final switcher = find.byKey(const Key('connectionSwitchToFlyAccount'));
    expect(switcher, findsOneWidget);
    await tester.ensureVisible(switcher);
    await tester.tap(switcher);
    await tester.pumpAndSettle();
    expect(find.byType(FlyLoginScreen), findsOneWidget);
    expect(find.byType(ConnectionScreen), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, '密码'))
          .controller!
          .text,
      isEmpty,
    );
    expect(
      Navigator.of(tester.element(find.byType(FlyLoginScreen))).canPop(),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('返回飞翔进行中禁用两类提交，失败保留本地页并显示说明', (tester) async {
    final account = _DelayedReturnAccount();
    addTearDown(() => _disposeAccount(account));
    await tester.pumpWidget(_host(account, home: const ConnectionScreen()));
    await tester.pumpAndSettle();
    final switcher = find.byKey(const Key('connectionSwitchToFlyAccount'));
    await tester.ensureVisible(switcher);
    await tester.tap(switcher);
    await tester.pump();
    expect(account.returnCalls, 1);
    expect(tester.widget<OutlinedButton>(switcher).onPressed, isNull);
    final localSubmit = find.descendant(
      of: find.byKey(const Key('connectionSubmitButton')),
      matching: find.byType(ElevatedButton),
    );
    expect(tester.widget<ElevatedButton>(localSubmit).onPressed, isNull);
    // The input method's Done callback uses the same submission guard.
    tester.widget<TextField>(find.byType(TextField).at(2)).onSubmitted!('');
    await tester.pump();
    expect(find.byKey(const Key('connectionInlineErrorText')), findsNothing);
    account.message = '切换未完成，请稍后重试。';
    account.returning.completeError(StateError('fixture failure'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionScreen), findsOneWidget);
    expect(find.text('切换未完成，请稍后重试。'), findsWidgets);
    expect(tester.widget<OutlinedButton>(switcher).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('手机本地登录首屏可见飞翔返回入口', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final account = _account()..legacyMode = true;
    addTearDown(() => _disposeAccount(account));
    await tester.pumpWidget(_host(account, home: const ConnectionScreen()));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('connectionSwitchToFlyAccount')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await _capture(tester, 'mobile-local-return');
  });

  testWidgets('二级本地页切回飞翔时阻止子页导航，完成后不会滞留旧登录页', (tester) async {
    final account = _DelayedReturnAccount();
    addTearDown(() => _disposeAccount(account));
    await tester.pumpWidget(
      _host(
        account,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ConnectionScreen(),
                ),
              ),
              child: const Text('打开本地连接'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开本地连接'));
    await tester.pumpAndSettle();
    final history = find.widgetWithIcon(IconButton, Icons.history_rounded);
    final downloads = find.widgetWithText(TextButton, '查看已下载数据');
    final fnReset = find.widgetWithText(TextButton, '重新登录 FN Connect');
    // Retain callbacks from before the state change to exercise handler guards.
    final oldHistory = tester.widget<IconButton>(history).onPressed!;
    final oldDownloads = tester.widget<TextButton>(downloads).onPressed!;
    final oldReset = tester.widget<TextButton>(fnReset).onPressed!;
    final switcher = find.byKey(const Key('connectionSwitchToFlyAccount'));
    await tester.ensureVisible(switcher);
    await tester.tap(switcher);
    await tester.pump();
    expect(tester.widget<IconButton>(history).onPressed, isNull);
    expect(tester.widget<TextButton>(downloads).onPressed, isNull);
    expect(tester.widget<TextButton>(fnReset).onPressed, isNull);
    oldHistory();
    oldDownloads();
    oldReset();
    await tester.pumpAndSettle();
    expect(
      ModalRoute.of(tester.element(find.byType(ConnectionScreen)))!.isCurrent,
      isTrue,
    );
    expect(find.byType(Dialog), findsNothing);
    account.returning.complete();
    await tester.pumpAndSettle();
    expect(account.legacyMode, isFalse);
    expect(find.byType(ConnectionScreen), findsNothing);
    expect(find.text('打开本地连接'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换前开始的历史读取不能在原路由退出动画中重新打开子页', (tester) async {
    final credentials = _DelayedHistoryCredentials();
    SecureCredentialStore.setBackendForTesting(credentials);
    await LoginHistoryStore.save(
      const LoginHistoryEntry(
        baseUrl: 'https://media.example.test',
        userName: 'viewer',
        password: 'history-fixture',
        rememberPassword: true,
        updatedAtMillis: 1,
      ),
    );
    final account = _DelayedReturnAccount();
    addTearDown(() => _disposeAccount(account));
    await tester.pumpWidget(
      _host(
        account,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ConnectionScreen(),
                ),
              ),
              child: const Text('打开本地连接'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开本地连接'));
    await tester.pumpAndSettle();
    credentials.pauseHistory = true;
    tester
        .widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.history_rounded),
        )
        .onPressed!();
    await tester.pump();
    expect(credentials.blockedReads, 1);
    final switcher = find.byKey(const Key('connectionSwitchToFlyAccount'));
    await tester.ensureVisible(switcher);
    await tester.tap(switcher);
    await tester.pump();
    account.returning.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    final departing = find.byType(ConnectionScreen, skipOffstage: false);
    expect(departing, findsOneWidget);
    expect(ModalRoute.of(tester.element(departing))!.isCurrent, isFalse);
    credentials.continueHistory.complete();
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(ConnectionScreen), findsNothing);
    expect(find.text('打开本地连接'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('首路由切换成功到gate下一帧之间不允许迟到历史页打开', (tester) async {
    final credentials = _DelayedHistoryCredentials();
    SecureCredentialStore.setBackendForTesting(credentials);
    await LoginHistoryStore.save(
      const LoginHistoryEntry(
        baseUrl: 'https://media.example.test',
        userName: 'viewer',
        password: 'history-fixture',
        rememberPassword: true,
        updatedAtMillis: 1,
      ),
    );
    await tester.pumpWidget(const FlyPlayerApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('媒体账号登录'));
    await tester.tap(find.text('媒体账号登录'));
    await tester.pumpAndSettle();
    credentials.pauseHistory = true;
    tester
        .widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.history_rounded),
        )
        .onPressed!();
    await tester.pump();
    expect(credentials.blockedReads, 1);
    final switcher = find.byKey(const Key('connectionSwitchToFlyAccount'));
    await tester.ensureVisible(switcher);
    await tester.tap(switcher);
    // Drain async work without rendering the provider gate's scheduled frame.
    await tester.idle();
    final connection = find.byType(ConnectionScreen);
    expect(connection, findsOneWidget);
    final context = tester.element(connection);
    expect(context.read<FlyAccountController>().legacyMode, isFalse);
    expect(ModalRoute.of(context)!.isCurrent, isTrue);
    credentials.continueHistory.complete();
    await tester.idle();
    await tester.pumpAndSettle();
    expect(find.byType(FlyLoginScreen), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final desktop in [true, false]) {
    testWidgets('飞翔登录宽屏布局遵守真实桌面开关 $desktop', (tester) async {
      DesktopEnvironment.debugOverridePlatform = desktop;
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final account = _account();
      addTearDown(() => _disposeAccount(account));
      await tester.pumpWidget(_host(account));
      await tester.pumpAndSettle();
      final brand = find.byKey(const Key('flyLoginDesktopBrand'));
      final form = find.byKey(const Key('flyLoginDesktopForm'));
      expect(brand, desktop ? findsOneWidget : findsNothing);
      expect(form, desktop ? findsOneWidget : findsNothing);
      if (desktop) {
        expect(
          tester.getRect(brand).right,
          lessThan(tester.getRect(form).left),
        );
        expect(tester.getSize(form).width, lessThanOrEqualTo(480));
        await _capture(tester, 'desktop-login');
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('手机登录入口清楚且大字键盘不挡提交', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    final account = _account();
    addTearDown(() => _disposeAccount(account));
    await tester.pumpWidget(_host(account));
    await tester.pumpAndSettle();
    expect(find.text('登录飞翔'), findsOneWidget);
    expect(find.text('媒体账号登录'), findsOneWidget);
    expect(find.byKey(const Key('flyLoginDesktopForm')), findsNothing);
    await _capture(tester, 'mobile-login');
    await tester.pumpWidget(_host(account, textScale: 1.6));
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    expect(
      MediaQuery.of(
        tester.element(find.byType(FlyLoginScreen)),
      ).viewInsets.bottom,
      280,
    );
    await tester.ensureVisible(find.text('登录飞翔'));
    expect(find.text('登录飞翔').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _capture(tester, 'mobile-login-large-text-keyboard');
  });
}

FlyAccountController _account() {
  final result = FlyAccountController(
    nas: NasProvider(),
    backendSession: BackendSessionProvider(autoLoad: false),
    autoLoad: false,
    service: FlyDataService(
      database: PlayStatsService.instance.database,
      drainWrites: () async {},
    ),
  );
  result.ready = true;
  return result;
}

void _disposeAccount(FlyAccountController account) {
  account.dispose();
  account.nas.dispose();
  account.backendSession.dispose();
}

Widget _host(
  FlyAccountController account, {
  double textScale = 1,
  Widget home = const FlyLoginScreen(),
}) {
  final baseTheme = AppThemeBuilder.build(AppThemePreset.midnight);
  return RepaintBoundary(
    key: _captureKey,
    child: MultiProvider(
      providers: [
        ChangeNotifierProvider<FlyAccountController>.value(value: account),
        ChangeNotifierProvider<NasProvider>.value(value: account.nas),
        ChangeNotifierProvider<BackendSessionProvider>.value(
          value: account.backendSession,
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _captureDir.isEmpty
            ? baseTheme
            : baseTheme.copyWith(
                textTheme: baseTheme.textTheme.apply(
                  fontFamily: 'FlyLoginPreview',
                ),
                primaryTextTheme: baseTheme.primaryTextTheme.apply(
                  fontFamily: 'FlyLoginPreview',
                ),
              ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (_captureDir.isEmpty) return;
  await tester.runAsync(
    () => precacheImage(
      const AssetImage('lib/img/app_logo.png'),
      tester.element(find.byType(Scaffold).first),
    ),
  );
  await tester.pumpAndSettle();
  final originalParagraphs = <(RenderParagraph, InlineSpan)>[];
  InlineSpan withPreviewFont(InlineSpan span) {
    if (span is! TextSpan) return span;
    final style = span.style ?? const TextStyle();
    return TextSpan(
      text: span.text,
      children: span.children?.map(withPreviewFont).toList(),
      style: style.copyWith(
        fontFamily: style.fontFamily == null || style.fontFamily == 'Ahem'
            ? 'FlyLoginPreview'
            : style.fontFamily,
      ),
      recognizer: span.recognizer,
      mouseCursor: span.mouseCursor,
      onEnter: span.onEnter,
      onExit: span.onExit,
      semanticsLabel: span.semanticsLabel,
      locale: span.locale,
      spellOut: span.spellOut,
    );
  }

  // AnimatedDefaultTextStyle can replace the theme's font family. Supply only
  // the test render's missing font, retaining product geometry and styling.
  void supplyPreviewFont(RenderObject object) {
    if (object is RenderParagraph) {
      originalParagraphs.add((object, object.text));
      object.text = withPreviewFont(object.text);
    }
    object.visitChildren(supplyPreviewFont);
  }

  supplyPreviewFont(tester.renderObject(find.byKey(_captureKey)));
  await tester.pump();
  try {
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(_captureKey),
      );
      final image = await boundary.toImage(pixelRatio: 1.5);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('$_captureDir/$name-widget.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(data!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  } finally {
    for (final (paragraph, span) in originalParagraphs) {
      if (paragraph.attached) paragraph.text = span;
    }
    await tester.pump();
  }
}

class _DelayedReturnAccount extends FlyAccountController {
  _DelayedReturnAccount()
    : super(
        nas: NasProvider(),
        backendSession: BackendSessionProvider(autoLoad: false),
        autoLoad: false,
      ) {
    ready = true;
    legacyMode = true;
  }
  final returning = Completer<void>();
  int returnCalls = 0;
  @override
  Future<void> returnToFlyMode() async {
    returnCalls++;
    await returning.future;
    await super.returnToFlyMode();
  }
}

class _DelayedHistoryCredentials extends MemorySecureCredentialBackend {
  bool pauseHistory = false;
  int blockedReads = 0;
  final continueHistory = Completer<void>();
  @override
  Future<SecureCredentialReadResult> read(String key) async {
    if (pauseHistory && key.startsWith('login_history.password.')) {
      blockedReads++;
      await continueHistory.future;
    }
    return super.read(key);
  }
}
