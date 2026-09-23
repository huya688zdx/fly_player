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
import 'package:fly_player/desktop/desktop_scroll_behavior.dart';
import 'package:fly_player/desktop/desktop_floating_panel.dart';

import 'package:fly_player/l10n/generated/app_localizations.dart';

import 'package:fly_player/media_backend/session/media_backend_connection.dart';
import 'package:fly_player/providers/backend_session_provider.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/screens/fly_account_screen.dart';
import 'package:fly_player/services/fly_data/fly_account_controller.dart';
import 'package:fly_player/services/fly_data/fly_data_service.dart';
import 'package:fly_player/services/fly_data/fly_login_history_store.dart';
import 'package:fly_player/services/secure_credential_store.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/widgets/common/login_components.dart';
import 'package:fly_player/ui/app_info_popover.dart';
import 'package:fly_player/utils/app_top_tip.dart';
import 'package:fly_player/widgets/common/app_option_list.dart';
import 'package:fly_player/widgets/common/track_option_sheet.dart';

const _captureDirectory = String.fromEnvironment('FLY_UI_CAPTURE_DIR');
const _captureFont = String.fromEnvironment('FLY_UI_FONT');
const _captureKey = ValueKey('fly-account-widget-preview');

Future<void> _capture(
  WidgetTester tester,
  String name, {
  Finder? region,
}) async {
  if (_captureDirectory.isEmpty) return;
  final previousShadows = debugDisableShadows;
  void repaint(RenderObject object) {
    object.markNeedsPaint();
    object.visitChildren(repaint);
  }

  try {
    debugDisableShadows = false;
    repaint(tester.renderObject(find.byKey(_captureKey)));
    await tester.pump();
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(_captureKey),
      );
      final bounds = region == null
          ? null
          : tester.getRect(region).shift(-boundary.localToGlobal(Offset.zero));
      // Render the actual panel at the reference crop's width. This is a
      // comparison scale, not a claim about the Android device's pixel ratio.
      final image = bounds == null
          ? await boundary.toImage(pixelRatio: 2)
          : await (boundary.debugLayer! as OffsetLayer).toImage(
              bounds,
              pixelRatio: 691 / bounds.width,
            );
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = File('$_captureDirectory/$name-widget.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(data!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  } finally {
    debugDisableShadows = previousShadows;
    repaint(tester.renderObject(find.byKey(_captureKey)));
    await tester.pump();
  }
}

void main() {
  setUpAll(() async {
    if (_captureDirectory.isNotEmpty) {
      if (_captureFont.isEmpty) {
        throw StateError('Widget captures require a real font');
      }
      final loader = FontLoader('FlyUiPreview')
        ..addFont(File(_captureFont).readAsBytes().then(ByteData.sublistView));
      await loader.load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  late _Account account;
  setUp(() {
    DesktopEnvironment.debugOverridePlatform = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    SharedPreferences.setMockInitialValues({});
    SecureCredentialStore.setBackendForTesting(MemorySecureCredentialBackend());
    FlyLoginHistoryStore.resetPendingForTesting();
    account = _Account();
  });
  tearDown(() {
    DesktopEnvironment.debugOverridePlatform = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    AppTopTip().dispose();
    account.dispose();
    account.nas.dispose();
    account.backendSession.dispose();
  });

  testWidgets('English account localization preserves validation and sources', (
    tester,
  ) async {
    account.signedIn = false;
    await tester.pumpWidget(_app(account, locale: const Locale('en')));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to your Fly account'), findsOneWidget);
    await tester.ensureVisible(find.text('Sign in to Fly'));
    await tester.tap(find.text('Sign in to Fly'));
    await tester.pumpAndSettle();
    expect(find.text('Please fill in Fly service address'), findsOneWidget);
    expect(account.logins, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    account.signedIn = true;
    account.bindings = [_binding(multiple: true)];
    await tester.pumpWidget(_app(account, locale: const Locale('en')));
    await tester.pumpAndSettle();
    expect(find.text('Account and media sources'), findsOneWidget);
    expect(find.textContaining('Available to connect'), findsOneWidget);
    expect(find.text('家中媒体'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'FN 登录授权页使用带尾斜杠的应用入口',
    (tester) async {
      const root = MethodChannel('io.jns.webview.win');
      const view = MethodChannel('io.jns.webview.win/1');
      const events = MethodChannel('io.jns.webview.win/1/events');
      final loads = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        root,
        (call) async => call.method == 'initialize' ? {'textureId': 1} : null,
      );
      messenger.setMockMethodCallHandler(view, (call) async {
        if (call.method == 'loadUrl') loads.add(call.arguments as String);
        return null;
      });
      messenger.setMockMethodCallHandler(events, (_) async => null);
      addTearDown(() {
        for (final channel in [root, view, events]) {
          messenger.setMockMethodCallHandler(channel, null);
        }
      });
      account.signedIn = false;
      await tester.pumpWidget(_app(account));
      await tester.enterText(
        find.widgetWithText(TextFormField, '飞翔服务地址'),
        'https://geqian688.fnos.net/app/fly-data-service',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '飞翔账号'),
        'viewer',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '密码'),
        'password',
      );
      await tester.tap(find.text('登录飞翔'));
      await tester.pump();

      expect(loads, <String>[
        'https://geqian688.fnos.net/app/fly-data-service/',
      ]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    '来源页复用选项行和贴边滚动条，无绑定时指引后端处理',
    (tester) async {
      DesktopEnvironment.debugOverridePlatform = true;
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      account.bindings = List.generate(
        8,
        (index) => {
          ..._binding(),
          'id': 'source-$index',
          'label': '媒体来源 ${index + 1}',
        },
      );
      await tester.pumpWidget(
        RepaintBoundary(key: _captureKey, child: _app(account)),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(DesktopScrollbar).first).right, 1280);
      expect(find.byType(AppOptionListTile), findsWidgets);
      await _capture(tester, 'account-desktop-sources');
      account.bindings = account.bindings.take(2).toList();
      account.activeBindingId = 'source-0';
      account.notifyListeners();
      await tester.pumpAndSettle();
      await _capture(tester, 'account-desktop-compact');
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _capture(tester, 'account-mobile-sources');
      account.bindings = [];
      account.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('暂无已绑定的媒体来源'), findsOneWidget);
      expect(find.textContaining('后端网页的“连接”'), findsOneWidget);
      expect(find.text('切换账号'), findsOneWidget);
      expect(find.text('添加服务器'), findsNothing);
      expect(find.text('添加媒体来源'), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'account-empty');
      account.message = '读取媒体来源失败，请重试。';
      account.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('暂无已绑定的媒体来源'), findsNothing);
      expect(find.text('读取媒体来源失败，请重试。'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  Finder activateButton() => find.byKey(const ValueKey('fly-source-source'));

  testWidgets('单客户端地址直接选用，成功后返回原媒体首页', (tester) async {
    await tester.pumpWidget(_app(account, pushed: true));
    await tester.tap(find.text('管理来源'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(activateButton());
    await tester.tap(activateButton());
    await tester.pumpAndSettle();

    expect(find.byType(SimpleDialog), findsNothing);
    expect(account.activations, [('source', null)]);
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
    expect(find.textContaining('当前来源'), findsOneWidget);
  });

  testWidgets('多地址默认自动连接，不要求再次选择地址或登录', (tester) async {
    account.bindings = [_binding(multiple: true)];
    await tester.pumpWidget(_app(account));
    await tester.pumpAndSettle();
    await tester.ensureVisible(activateButton());
    await tester.tap(activateButton());
    await tester.pumpAndSettle();

    expect(account.activations, [('source', null)]);
    expect(find.byType(AppOptionSheetPanel), findsNothing);
    expect(find.byType(SimpleDialog), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('已绑定来源说明复用原说明浮层', (tester) async {
    await tester.pumpWidget(_app(account));
    await tester.pumpAndSettle();
    expect(find.byType(AppInfoPopoverAnchor), findsWidgets);
    expect(find.text('1 个来源'), findsOneWidget);
    await tester.tap(find.byTooltip('媒体来源说明'));
    await tester.pumpAndSettle();
    expect(find.textContaining('后端网页的“连接”'), findsWidgets);
    expect(find.byType(TextFormField), findsNothing);
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
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('当前来源进入媒体库不重新授权或选地址', (tester) async {
    account.activeBindingId = 'source';
    account.bindings = [_binding(multiple: true)];
    await tester.pumpWidget(_app(account, pushed: true));
    await tester.tap(find.text('管理来源'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(activateButton());
    await tester.tap(activateButton());
    await tester.pumpAndSettle();

    expect(account.activations, isEmpty);
    expect(find.text('原媒体首页'), findsOneWidget);
    expect(find.byType(SimpleDialog), findsNothing);
  });

  testWidgets('飞翔登录提供登录记录与记住密码入口', (tester) async {
    account.signedIn = false;
    await tester.pumpWidget(_app(account));
    await tester.pumpAndSettle();
    expect(find.text('登录记录'), findsOneWidget);
    expect(find.text('记住密码'), findsOneWidget);
  });

  TextEditingController loginField(WidgetTester tester, String label) => tester
      .widget<TextFormField>(find.widgetWithText(TextFormField, label))
      .controller!;

  Future<void> settleHistory(WidgetTester tester) async {
    await tester.pumpAndSettle();
    // Drain real plugin/storage futures as well as Flutter's fake clock.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  const savedLogin = FlyLoginHistoryEntry(
    serverUrl: 'https://fly.example',
    username: 'saved-viewer',
    deviceName: '我的电脑',
    serviceInstanceId: 'saved-instance',
    rememberPassword: true,
    password: 'saved-password-fixture',
    updatedAtMillis: 2,
  );

  testWidgets('设备名称从标题设置入口修改并用于本次登录', (tester) async {
    await tester.runAsync(() => FlyLoginHistoryStore.save(savedLogin));
    account.signedIn = false;
    await tester.pumpWidget(
      RepaintBoundary(key: _captureKey, child: _app(account)),
    );
    await settleHistory(tester);
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.widgetWithText(TextFormField, '当前设备名称'), findsNothing);
    await tester.tap(find.byTooltip('当前设备名称'));
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextFormField, '当前设备名称');
    expect(
      tester.widget<TextFormField>(field).initialValue,
      savedLogin.deviceName,
    );
    await tester.enterText(field, '');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(field, findsOneWidget);
    await tester.enterText(field, '客厅电脑');
    await _capture(tester, 'login-device-settings');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(field, findsNothing);
    await tester.ensureVisible(find.text('登录飞翔'));
    await tester.tap(find.text('登录飞翔'));
    await settleHistory(tester);
    expect(account.logins.single.$4, '客厅电脑');
    expect(tester.takeException(), isNull);
  });

  testWidgets('登录页重新创建后回填最近账号，提交才登录并核对服务身份', (tester) async {
    await tester.runAsync(() => FlyLoginHistoryStore.save(savedLogin));
    account.signedIn = false;
    await tester.pumpWidget(_app(account));
    await settleHistory(tester);
    await settleHistory(tester);
    expect(loginField(tester, '飞翔服务地址').text, savedLogin.serverUrl);
    expect(loginField(tester, '飞翔账号').text, savedLogin.username);
    expect(loginField(tester, '密码').text, savedLogin.password);
    expect(account.logins, isEmpty);
    await tester.ensureVisible(find.text('登录飞翔'));
    await tester.tap(find.text('登录飞翔'));
    await settleHistory(tester);
    expect(account.logins.single, (
      savedLogin.serverUrl,
      savedLogin.username,
      savedLogin.password,
      savedLogin.deviceName,
    ));
    expect(account.loginInstanceIds, [savedLogin.serviceInstanceId]);
    expect(account.loginRememberFlags, [true]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_app(account));
    await settleHistory(tester);
    expect(loginField(tester, '密码').text, savedLogin.password);
    expect(account.logins, hasLength(1));
  });

  for (final desktop in [true, false]) {
    testWidgets('登录记录使用原平台弹窗，可切账号和清除保存凭据 $desktop', (tester) async {
      DesktopEnvironment.debugOverridePlatform = desktop;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = desktop
          ? const Size(1280, 900)
          : const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      const other = FlyLoginHistoryEntry(
        serverUrl: 'https://other.example',
        username: 'other-viewer',
        deviceName: '另一账号',
        serviceInstanceId: 'other-instance',
        rememberPassword: true,
        password: 'other-password-fixture',
        updatedAtMillis: 1,
      );
      await tester.runAsync(() => FlyLoginHistoryStore.save(other));
      await tester.runAsync(() => FlyLoginHistoryStore.save(savedLogin));
      account.signedIn = false;
      await tester.pumpWidget(
        RepaintBoundary(key: _captureKey, child: _app(account)),
      );
      await settleHistory(tester);
      await _capture(
        tester,
        desktop ? 'login-history-desktop-form' : 'login-history-mobile-form',
      );
      await tester.ensureVisible(find.text('登录记录'));
      await tester.tap(find.text('登录记录'));
      await settleHistory(tester);
      expect(
        find.byType(DesktopFloatingPanel),
        desktop ? findsOneWidget : findsNothing,
      );
      expect(
        find.byType(AppOptionSheetPanel),
        desktop ? findsNothing : findsOneWidget,
      );
      await _capture(
        tester,
        desktop
            ? 'login-history-desktop-picker'
            : 'login-history-mobile-picker',
      );
      await tester.tap(find.text(other.username));
      await settleHistory(tester);
      expect(loginField(tester, '飞翔账号').text, other.username);
      expect(loginField(tester, '密码').text, other.password);
      expect(account.logins, isEmpty);
      await tester.tap(find.text('登录记录'));
      await settleHistory(tester);
      await tester.tap(find.text('清除登录记录'));
      await settleHistory(tester);
      await tester.tap(find.text('清除'));
      await settleHistory(tester);
      expect(await tester.runAsync(FlyLoginHistoryStore.load), isEmpty);
      expect(loginField(tester, '飞翔账号').text, isEmpty);
      expect(loginField(tester, '密码').text, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final identity in ['飞翔服务地址', '飞翔账号']) {
    testWidgets('只移动密码光标后修改$identity仍清除回填密码', (tester) async {
      await tester.runAsync(() => FlyLoginHistoryStore.save(savedLogin));
      account.signedIn = false;
      await tester.pumpWidget(_app(account));
      await settleHistory(tester);
      final secret = loginField(tester, '密码');
      secret.selection = const TextSelection.collapsed(offset: 1);
      await tester.enterText(
        find.widgetWithText(TextFormField, identity),
        identity == '飞翔服务地址' ? 'https://different.example' : 'different-viewer',
      );
      expect(secret.text, isEmpty);
      await tester.enterText(
        find.widgetWithText(TextFormField, '密码'),
        'new-manual-fixture',
      );
      await tester.ensureVisible(find.text('登录飞翔'));
      await tester.tap(find.text('登录飞翔'));
      await settleHistory(tester);
      expect(account.logins.single.$3, 'new-manual-fixture');
      expect(account.loginInstanceIds, [null]);
    });
  }

  testWidgets('取消记住立即删除已存密码，重开仍保留账号地址', (tester) async {
    await tester.runAsync(() => FlyLoginHistoryStore.save(savedLogin));
    account.signedIn = false;
    await tester.pumpWidget(_app(account));
    await settleHistory(tester);
    await tester.ensureVisible(find.text('记住密码'));
    await tester.tap(find.text('记住密码'));
    await settleHistory(tester);
    expect(
      (await tester.runAsync(FlyLoginHistoryStore.load))!.single.password,
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_app(account));
    await settleHistory(tester);
    expect(loginField(tester, '飞翔账号').text, savedLogin.username);
    expect(loginField(tester, '密码').text, isEmpty);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
  });

  for (final changeMode in [false, true]) {
    testWidgets('迟到的登录记录不能覆盖输入或登录方式 $changeMode', (tester) async {
      final secure = _DelayedHistoryBackend();
      SecureCredentialStore.setBackendForTesting(secure);
      await tester.runAsync(() => FlyLoginHistoryStore.save(savedLogin));
      secure.pending = Completer<void>();
      account.signedIn = false;
      await tester.pumpWidget(_app(account));
      await settleHistory(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, '飞翔账号'),
        'typing-viewer',
      );
      if (changeMode) {
        account.legacyMode = true;
        account.notifyListeners();
      }
      secure.pending!.complete();
      await settleHistory(tester);
      expect(loginField(tester, '飞翔账号').text, 'typing-viewer');
      expect(loginField(tester, '密码').text, isEmpty);
      expect(account.logins, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('登录表单提交时锁定，失败后显示反馈并恢复输入', (tester) async {
    account.signedIn = false;
    account.pendingLogin = Completer<void>();
    await tester.pumpWidget(
      RepaintBoundary(key: _captureKey, child: _app(account)),
    );
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
    await tester.tap(find.byTooltip('显示密码'));
    await tester.pump();
    expect(find.byTooltip('隐藏密码'), findsOneWidget);
    await tester.tap(find.byTooltip('隐藏密码'));
    await tester.pump();
    await tester.ensureVisible(find.text('登录飞翔'));
    await tester.tap(find.text('登录飞翔'));
    await tester.pump();
    expect(
      tester
          .widget<LoginSubmitButton>(find.byType(LoginSubmitButton))
          .isSubmitting,
      isTrue,
    );
    expect(
      tester
          .widget<LoginSubmitButton>(find.byType(LoginSubmitButton))
          .onPressed,
      isNull,
    );
    await _capture(tester, 'login-loading');
    account.pendingLogin!.completeError(StateError('连接失败'));
    await tester.pumpAndSettle();
    expect(find.text('测试连接失败，请重试。'), findsOneWidget);
    expect(
      tester
          .widget<LoginSubmitButton>(find.byType(LoginSubmitButton))
          .onPressed,
      isNotNull,
    );
    await _capture(tester, 'login-failure');

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

  for (final preset in [AppThemePreset.midnight, AppThemePreset.forest]) {
    testWidgets('安卓字幕参考同内容正常字号 ${preset.name}', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(
          key: _captureKey,
          child: _app(
            account,
            preset: preset,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => TrackOptionSheet.show(
                    context,
                    title: '选择字幕',
                    selectedId: 'default',
                    items: const [
                      TrackOptionSheetItem(id: 'off', title: '字幕关'),
                      TrackOptionSheetItem(
                        id: 'default',
                        title: '未知语言-默认',
                        subtitle: 'SUP',
                      ),
                      TrackOptionSheetItem(
                        id: 'alternate',
                        title: '未知语言',
                        subtitle: 'SUP 1',
                      ),
                    ],
                  ),
                  child: const Text('打开字幕参考'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开字幕参考'));
      await tester.pumpAndSettle();
      final tiles = tester
          .widgetList<AppOptionListTile>(find.byType(AppOptionListTile))
          .toList();
      expect(tiles.map((tile) => tile.selected), [false, true, false]);
      expect(tiles.map((tile) => tile.title), ['字幕关', '未知语言-默认', '未知语言']);
      expect(tester.takeException(), isNull);
      await _capture(
        tester,
        'subtitle-reference-${preset.name}',
        region: find.byKey(const ValueKey('app-modal-surface-track-options')),
      );
      await tester.tap(find.text('字幕关'));
      await tester.pumpAndSettle();
      expect(find.byType(AppOptionSheetPanel), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

Widget _app(
  _Account account, {
  bool pushed = false,
  NavigatorObserver? observer,
  AppThemePreset preset = AppThemePreset.midnight,
  double textScale = 1,
  Widget? home,
  Locale locale = const Locale('zh', 'CN'),
}) => ChangeNotifierProvider<FlyAccountController>.value(
  value: account,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    scrollBehavior: const DesktopScrollBehavior(),
    theme: _captureDirectory.isEmpty
        ? AppThemeBuilder.build(preset)
        : AppThemeBuilder.build(preset).copyWith(
            textTheme: AppThemeBuilder.build(
              preset,
            ).textTheme.apply(fontFamily: 'FlyUiPreview'),
            primaryTextTheme: AppThemeBuilder.build(
              preset,
            ).primaryTextTheme.apply(fontFamily: 'FlyUiPreview'),
            appBarTheme: AppThemeBuilder.build(preset).appBarTheme.copyWith(
              titleTextStyle: AppThemeBuilder.build(preset)
                  .appBarTheme
                  .titleTextStyle!
                  .copyWith(fontFamily: 'FlyUiPreview'),
            ),
          ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    navigatorObservers: [if (observer != null) observer],
    home:
        home ??
        (pushed
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
            : const FlyBindingsScreen()),
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
    : super(nas: NasProvider(), backendSession: _Backend(), autoLoad: false) {
    ready = true;
    bindings = [_binding()];
  }
  bool signedIn = true, rejectActivation = false, admin = false;
  String serverUrl = 'https://fly.example';
  final addressSwitches = <String>[];
  final activations = <(String, String?)>[];
  Completer<void>? pendingLogin;
  final logins = <(String, String, String, String)>[];
  final loginInstanceIds = <String?>[];
  final loginRememberFlags = <bool>[];
  @override
  FlyDataSession? get session => signedIn
      ? FlyDataSession(
          serverUrl: serverUrl,
          addresses: ['https://fly.example', 'https://fly-vpn.example'],
          role: admin ? 'admin' : 'user',
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
  Future<void> switchAddress(String address) async {
    addressSwitches.add(address);
    serverUrl = address;
    notifyListeners();
  }

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
    bool rememberPassword = true,
    String? expectedInstanceId,
    String fnEntryToken = '',
  }) async {
    logins.add((url, username, password, deviceName));
    loginInstanceIds.add(expectedInstanceId);
    loginRememberFlags.add(rememberPassword);
    try {
      await pendingLogin?.future;
    } catch (_) {
      message = '测试连接失败，请重试。';
      notifyListeners();
      rethrow;
    }
  }
}

class _DelayedHistoryBackend extends MemorySecureCredentialBackend {
  Completer<void>? pending;
  @override
  Future<SecureCredentialReadResult> read(String key) async {
    await pending?.future;
    return super.read(key);
  }
}

class _Pops extends NavigatorObserver {
  int count = 0;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    count++;
  }
}

class _Backend extends BackendSessionProvider {
  _Backend() : super(autoLoad: false);
  MediaBackendConnection? connection;
  @override
  MediaBackendConnection? get currentConnection => connection;
}
