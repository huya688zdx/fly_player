import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/desktop/desktop_environment.dart';
import 'package:fly_player/desktop/desktop_floating_panel.dart';
import 'package:fly_player/desktop/desktop_hover_dropdown.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/media_backend/session/media_backend_connection.dart';
import 'package:fly_player/providers/backend_session_provider.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/screens/fly_account_screen.dart';
import 'package:fly_player/services/fly_data/fly_account_controller.dart';
import 'package:fly_player/services/fly_data/fly_data_service.dart';
import 'package:fly_player/services/secure_credential_store.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/ui/app_info_popover.dart';
import 'package:fly_player/utils/app_top_tip.dart';
import 'package:fly_player/widgets/common/app_modal_surface.dart';
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

  Finder activateButton() => find.textContaining(RegExp('切换到此来源|选用 / 切换媒体地址'));

  for (final size in [const Size(1280, 800), const Size(640, 900)]) {
    testWidgets('PC 来源操作和连接设置复用桌面浮窗 $size', (tester) async {
      DesktopEnvironment.debugOverridePlatform = true;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      account.bindings = [_binding(multiple: true)];
      await tester.pumpWidget(
        RepaintBoundary(key: _captureKey, child: _app(account)),
      );
      await tester.pumpAndSettle();
      if (_captureDirectory.isNotEmpty) {
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('lib/img/feiniu_Logo.png'),
            tester.element(find.byType(FlyBindingsScreen)),
          ),
        );
        await tester.pumpAndSettle();
      }
      final anchor = tester.getRect(find.byTooltip('来源设置'));
      await tester.tap(find.byTooltip('来源设置'));
      await tester.pumpAndSettle();
      expect(find.byType(DesktopFloatingPanel), findsOneWidget);
      expect(find.byType(AppOptionSheetPanel), findsNothing);
      final menu = tester.getRect(find.byType(DesktopFloatingPanel));
      expect(menu.width, lessThanOrEqualTo(292));
      // IconButton has a 4 px outer hit-target inset around its Tooltip.
      expect(menu.top, inInclusiveRange(anchor.bottom, anchor.bottom + 8));
      expect(menu.right, lessThanOrEqualTo(size.width));
      await _capture(tester, 'pc-source-menu-${size.width.toInt()}');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(DesktopFloatingPanel), findsNothing);
      await tester.tap(find.byTooltip('来源设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('连接设置'));
      await tester.pumpAndSettle();
      expect(find.byType(DesktopFloatingPanel), findsOneWidget);
      expect(find.byType(AppOptionSheetPanel), findsNothing);
      expect(
        tester.getSize(find.byType(DesktopFloatingPanel)).width,
        lessThanOrEqualTo(470),
      );
      await _capture(tester, 'pc-connections-${size.width.toInt()}');
      await tester.tap(find.textContaining('https://vpn.example'));
      await tester.pumpAndSettle();
      expect(account.activations, [('source', 'https://vpn.example')]);
      expect(find.byType(DesktopFloatingPanel), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('PC 重新授权表单单层桌面外壳并可关闭 $size', (tester) async {
      DesktopEnvironment.debugOverridePlatform = true;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(key: _captureKey, child: _app(account)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('来源设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重新授权'));
      await tester.pumpAndSettle();
      expect(find.byType(DesktopFloatingPanel), findsOneWidget);
      expect(find.byType(AppOptionSheetPanel), findsNothing);
      final panel = tester.getRect(find.byType(DesktopFloatingPanel));
      expect(panel.width, lessThanOrEqualTo(470));
      expect(panel.center.dx, closeTo(size.width / 2, 1));
      await _capture(tester, 'pc-authorization-${size.width.toInt()}');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.text('请填写媒体账号'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, '媒体账号'),
        'viewer',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '媒体密码'),
        'test-password',
      );
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(account.reauthorizations, 1);
      expect(find.byType(DesktopFloatingPanel), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

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
    expect(find.text('进入媒体库'), findsOneWidget);
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

  testWidgets('连接设置复用选项面板，取消不连接且手动选址保持精准', (tester) async {
    account.bindings = [_binding(multiple: true)];
    await tester.pumpWidget(_app(account));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('来源设置'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('app-modal-surface-action-sheet')),
      findsOneWidget,
    );
    await tester.tap(find.text('连接设置'));
    await tester.pumpAndSettle();

    expect(find.byType(AppOptionSheetPanel), findsOneWidget);
    expect(find.byType(SimpleDialog), findsNothing);
    expect(account.activations, isEmpty);
    expect(find.textContaining('局域网'), findsWidgets);
    expect(find.textContaining('VPN'), findsWidgets);
    expect(find.textContaining('client_lan'), findsNothing);
    expect(find.textContaining('nas_api'), findsNothing);
    Navigator.of(tester.element(find.byType(AppOptionSheetPanel))).pop();
    await tester.pumpAndSettle();
    expect(account.activations, isEmpty);

    await tester.tap(find.byTooltip('来源设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('连接设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('https://vpn.example'));
    await tester.pumpAndSettle();
    expect(account.activations, [('source', 'https://vpn.example')]);
  });

  testWidgets('没有客户端地址时手动设置不退回 NAS 管理地址', (tester) async {
    account.bindings = [_binding()];
    (account.bindings.single['server'] as Map)['addresses'] = [
      {'purpose': 'nas_api', 'base_url': 'https://nas-only.example'},
    ];
    await tester.pumpWidget(_app(account));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('来源设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('连接设置'));
    await tester.pumpAndSettle();
    expect(account.activations, isEmpty);
    expect(find.textContaining('暂无可手动选择的播放地址'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    await tester.pump(const Duration(seconds: 2));
  });

  for (final scope in ['current', 'other-account', 'other-binding']) {
    testWidgets('PC 连接设置只勾选本账号本来源 $scope', (tester) async {
      DesktopEnvironment.debugOverridePlatform = true;
      account.bindings = [_binding(multiple: true)];
      (account.backendSession as _Backend).connection = MediaBackendConnection(
        kind: MediaBackendKind.feiniu,
        serverUrl: 'https://vpn.example/',
        accountKey: scope == 'other-account' ? 'other' : account.accountKey,
        bindingId: scope == 'other-binding' ? 'other' : 'source',
        bindingRevision: 1,
      );
      await tester.pumpWidget(_app(account));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('来源设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('连接设置'));
      await tester.pumpAndSettle();
      final selected = tester
          .widgetList<DesktopDropdownOptionRow>(
            find.byType(DesktopDropdownOptionRow),
          )
          .where((row) => row.selected)
          .toList();
      expect(selected, hasLength(scope == 'current' ? 1 : 0));
      if (selected.isNotEmpty) {
        expect(selected.single.item.id, 'https://vpn.example');
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(account.activations, isEmpty);
      expect(find.byType(DesktopFloatingPanel), findsNothing);
    });

    testWidgets('连接设置仅标记当前账号与来源的地址 $scope', (tester) async {
      account.bindings = [_binding(multiple: true)];
      (account.backendSession as _Backend).connection = MediaBackendConnection(
        kind: MediaBackendKind.feiniu,
        serverUrl: 'https://vpn.example/',
        accountKey: scope == 'other-account' ? 'other' : account.accountKey,
        bindingId: scope == 'other-binding' ? 'other' : 'source',
        bindingRevision: 1,
      );
      await tester.pumpWidget(_app(account));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('来源设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('连接设置'));
      await tester.pumpAndSettle();
      final selected = tester
          .widgetList<AppOptionListTile>(find.byType(AppOptionListTile))
          .where((tile) => tile.selected)
          .toList();
      expect(selected, hasLength(scope == 'current' ? 1 : 0));
      if (selected.isNotEmpty) {
        expect(selected.single.subtitle, 'https://vpn.example');
      }
    });
  }

  testWidgets('连接设置打开后绑定版本改变，旧选择不能激活', (tester) async {
    account.bindings = [_binding(multiple: true)];
    await tester.pumpWidget(_app(account));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('来源设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('连接设置'));
    await tester.pumpAndSettle();
    account.bindings = [
      {..._binding(multiple: true), 'revision': 2},
    ];
    account.notifyListeners();
    await tester.pump();
    await tester.tap(find.text('https://vpn.example'));
    await tester.pumpAndSettle();
    expect(account.activations, isEmpty);
    expect(find.textContaining('账号或媒体来源已改变'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('来源菜单打开后账号退出，旧回调不能打开授权表单', (tester) async {
    await tester.pumpWidget(_app(account));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('来源设置'));
    await tester.pumpAndSettle();
    account.signedIn = false;
    account.notifyListeners();
    await tester.pump();
    await tester.tap(find.text('重新授权'));
    await tester.pumpAndSettle();
    expect(find.text('绑定媒体账号'), findsNothing);
    expect(find.text('媒体密码'), findsNothing);
    expect(account.activations, isEmpty);
  });

  testWidgets('授权表单打开后绑定更新，提交不作用于新版本', (tester) async {
    await tester.pumpWidget(_app(account));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('来源设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新授权'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, '媒体账号'),
      'viewer',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '媒体密码'),
      'example-password',
    );
    account.bindings = [
      {..._binding(), 'revision': 2},
    ];
    account.notifyListeners();
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(account.reauthorizations, 0);
    expect(find.textContaining('账号或媒体来源已改变'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('移除来源使用原项目确认弹窗，取消保留来源', (tester) async {
    await tester.pumpWidget(_app(account));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('来源设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移除媒体来源'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('已有播放历史保留'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(account.bindings, hasLength(1));
  });

  testWidgets('已绑定来源说明复用原说明浮层', (tester) async {
    await tester.pumpWidget(_app(account));
    await tester.pumpAndSettle();
    expect(find.byType(AppInfoPopoverAnchor), findsWidgets);
    expect(find.text('已同步绑定，选择来源即可连接。'), findsOneWidget);
    await tester.tap(find.byTooltip('媒体来源说明'));
    await tester.pumpAndSettle();
    expect(find.textContaining('连接设置'), findsWidgets);
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

  testWidgets('绑定表单复用原浮层并显示必填提示，选填字段可留空', (tester) async {
    Map<String, String>? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                submitted = await flyForm(
                  context,
                  '绑定媒体账号',
                  {'username': '媒体账号', 'password': '媒体密码', 'label': '备注'},
                  secretKeys: {'password'},
                  optionalKeys: {'label'},
                );
              },
              child: const Text('打开表单'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开表单'));
    await tester.pumpAndSettle();
    expect(find.byType(AppModalSurface), findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('请填写媒体账号'), findsOneWidget);
    expect(find.text('请填写媒体密码'), findsOneWidget);
    expect(find.text('请填写备注'), findsNothing);
    expect(submitted, isNull);
    await tester.enterText(
      find.widgetWithText(TextFormField, '媒体账号'),
      'viewer',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '媒体密码'),
      'example-password',
    );
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(submitted, {
      'username': 'viewer',
      'password': 'example-password',
      'label': '',
    });
    expect(tester.takeException(), isNull);
  });

  for (final preset in [AppThemePreset.midnight, AppThemePreset.latte]) {
    testWidgets('手机窄屏原组件布局与连接设置 ${preset.name}', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      account.bindings = [_binding(multiple: true)];
      await tester.pumpWidget(
        RepaintBoundary(
          key: _captureKey,
          child: _app(account, preset: preset),
        ),
      );
      await tester.pumpAndSettle();
      if (_captureDirectory.isNotEmpty) {
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('lib/img/feiniu_Logo.png'),
            tester.element(find.byType(FlyBindingsScreen)),
          ),
        );
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await _capture(tester, 'account-${preset.name}');
      await tester.tap(find.byTooltip('来源设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('连接设置'));
      await tester.pumpAndSettle();
      expect(find.byType(AppOptionSheetPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'connection-${preset.name}');
    });
  }

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

  testWidgets('窄屏大字与键盘下表单可滚动且确认可见', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 740);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      RepaintBoundary(key: _captureKey, child: _app(account, textScale: 1.6)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byTooltip('来源设置'));
    await tester.tap(find.byTooltip('来源设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新授权'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('确定').hitTestable(), findsOneWidget);
    await _capture(tester, 'form-large-text-keyboard');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Widget _app(
  _Account account, {
  bool pushed = false,
  NavigatorObserver? observer,
  AppThemePreset preset = AppThemePreset.midnight,
  double textScale = 1,
  Widget? home,
}) => ChangeNotifierProvider<FlyAccountController>.value(
  value: account,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
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
    locale: const Locale('zh', 'CN'),
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
  bool signedIn = true, rejectActivation = false;
  final activations = <(String, String?)>[];
  final logins = <(String, String, String, String)>[];
  int reauthorizations = 0;
  @override
  Future<void> reauthorize(
    Map<String, dynamic> binding, {
    required String username,
    required String password,
  }) async {
    reauthorizations++;
  }

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

class _Backend extends BackendSessionProvider {
  _Backend() : super(autoLoad: false);
  MediaBackendConnection? connection;
  @override
  MediaBackendConnection? get currentConnection => connection;
}
