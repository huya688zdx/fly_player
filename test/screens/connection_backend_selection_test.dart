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
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  testWidgets('默认选中飞牛，切到 Emby 后显示独立连接表单', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_connectionScreen());
    await tester.pump();

    expect(find.text('飞牛影视'), findsOneWidget);
    expect(find.text('Emby'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    final feiniuLoginButtonY = tester
        .getTopLeft(find.byType(ElevatedButton))
        .dy;

    await tester.dragFrom(const Offset(400, 300), const Offset(-360, 0));
    await tester.pumpAndSettle();

    // Emby 表单已完善为正式登录：登录按钮、记住登录勾选，下载/FN Connect 仍是飞牛专属。
    expect(find.text('Emby 服务器地址'), findsOneWidget);
    expect(find.text('用户名'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('保持登录'), findsOneWidget);
    expect(find.text('重新登录 FN Connect').hitTestable(), findsNothing);
    final semanticsTree = tester
        .binding
        .rootPipelineOwner
        .semanticsOwner
        ?.rootSemanticsNode
        ?.toStringDeep();
    expect(semanticsTree, isNot(contains('重新登录 FN Connect')));
    semantics.dispose();
    expect(find.byType(TextField), findsNWidgets(3));
    expect(find.byKey(const Key('feiniuAccessCodeField')), findsNothing);
    expect(find.byType(SegmentedButton<String>), findsNothing);
    expect(
      tester.getTopLeft(find.byType(ElevatedButton)).dy,
      closeTo(feiniuLoginButtonY, 3),
    );

    await tester.dragFrom(const Offset(400, 300), const Offset(360, 0));
    await tester.pumpAndSettle();

    expect(find.text('登录'), findsOneWidget);
    expect(find.text('重新登录 FN Connect'), findsOneWidget);
    expect(find.byType(SegmentedButton<String>), findsNothing);
  });

  testWidgets('高屏切换后端时登录按钮保持原位', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_connectionScreen());
    await tester.pumpAndSettle();
    final feiniuLoginButtonY = tester
        .getTopLeft(find.byType(ElevatedButton))
        .dy;

    await tester.tap(find.text('Emby').first);
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.byType(ElevatedButton)).dy,
      closeTo(feiniuLoginButtonY, 3),
    );
  });

  testWidgets('三种服务完整显示且主按钮位置稳定', (tester) async {
    await tester.pumpWidget(_connectionScreen());
    await tester.pumpAndSettle();

    expect(find.text('飞牛影视'), findsOneWidget);
    expect(find.text('Emby'), findsOneWidget);
    expect(find.text('Jellyfin'), findsOneWidget);

    final button = find.byKey(const Key('connectionSubmitButton'));
    final feiniuRect = tester.getRect(button);

    await tester.tap(find.text('Emby').first);
    await tester.pumpAndSettle();
    final embyRect = tester.getRect(button);

    await tester.tap(find.text('Jellyfin').first);
    await tester.pumpAndSettle();
    final jellyfinRect = tester.getRect(button);

    expect(embyRect.top, closeTo(feiniuRect.top, 1));
    expect(jellyfinRect.top, closeTo(feiniuRect.top, 1));
    expect(embyRect.left, closeTo(feiniuRect.left, 1));
    expect(jellyfinRect.left, closeTo(feiniuRect.left, 1));
    expect(embyRect.width, closeTo(feiniuRect.width, 1));
    expect(jellyfinRect.width, closeTo(feiniuRect.width, 1));
  });

  testWidgets('窄屏连接内容在可用高度内保持上下空间接近平衡', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_connectionScreen());
    await tester.pumpAndSettle();

    final viewport = tester.getSize(find.byType(Scaffold));
    final contentTop = tester
        .getTopLeft(find.byKey(const Key('connectionBrandTitle')))
        .dy;
    final contentBottom = tester.getBottomRight(find.text('查看已下载数据')).dy;
    final topSpace = contentTop;
    final bottomSpace = viewport.height - contentBottom;

    expect((topSpace - bottomSpace).abs(), lessThan(48));
  });

  testWidgets('无连接错误时错误区不占固定空槽，错误出现后平滑展开', (tester) async {
    await tester.pumpWidget(_connectionScreen());
    await tester.pumpAndSettle();

    final panel = find.byKey(const Key('connectionLoginFormPanel'));
    final heightWithoutError = tester.getRect(panel).height;
    expect(find.byKey(const Key('connectionInlineErrorText')), findsNothing);

    await tester.tap(find.byKey(const Key('connectionSubmitButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('connectionInlineErrorText')), findsOneWidget);
    expect(tester.getRect(panel).height, greaterThan(heightWithoutError + 1));
  });

  testWidgets('选择器到连接标题仅保留紧凑间距', (tester) async {
    await tester.pumpWidget(_connectionScreen());
    await tester.pumpAndSettle();

    final selector = tester.getRect(
      find.byKey(const Key('connectionBackendSelector')),
    );
    final title = tester.getRect(find.text('登录 飞牛影视'));
    expect(title.top - selector.bottom, lessThanOrEqualTo(11));
  });

  testWidgets('服务切换动画中同时保留旧表单和新表单', (tester) async {
    await tester.pumpWidget(_connectionScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Emby').first);
    await tester.pump(const Duration(milliseconds: 80));

    expect(
      find.byKey(const Key('connectionServerAddressField')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('serverAddress_emby')), findsOneWidget);
    expect(find.byType(FadeTransition), findsWidgets);
    expect(find.byType(SlideTransition), findsWidgets);
  });

  testWidgets('各服务输入状态独立保留', (tester) async {
    await tester.pumpWidget(_connectionScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Emby').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('serverAddress_emby')),
      'https://emby.example.test',
    );
    await tester.enterText(find.byKey(const Key('userName_emby')), 'emby-user');
    await tester.enterText(
      find.byKey(const Key('password_emby')),
      'emby-password',
    );

    await tester.tap(find.text('Jellyfin').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('serverAddress_jellyfin')),
      'https://jellyfin.example.test',
    );
    await tester.enterText(
      find.byKey(const Key('userName_jellyfin')),
      'jellyfin-user',
    );
    await tester.enterText(
      find.byKey(const Key('password_jellyfin')),
      'jellyfin-password',
    );

    await tester.tap(find.text('Emby').first);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('serverAddress_emby')))
          .controller!
          .text,
      'https://emby.example.test',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('userName_emby')))
          .controller!
          .text,
      'emby-user',
    );

    await tester.tap(find.text('Jellyfin').first);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('serverAddress_jellyfin')))
          .controller!
          .text,
      'https://jellyfin.example.test',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('password_jellyfin')))
          .controller!
          .text,
      'jellyfin-password',
    );
  });

  testWidgets('手机与平板尺寸均无溢出', (tester) async {
    for (final size in const <Size>[
      Size(360, 800),
      Size(390, 844),
      Size(600, 900),
      Size(839, 1000),
      Size(840, 600),
      Size(1200, 800),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(_connectionScreen());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '尺寸 $size 溢出');
      expect(find.byKey(const Key('connectionSubmitButton')), findsOneWidget);
      if (size.width >= 840) {
        expect(
          find.byKey(const Key('connectionWideBrandPane')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('connectionWideFormPane')), findsOneWidget);
      } else {
        expect(find.byKey(const Key('connectionWideBrandPane')), findsNothing);
        expect(find.byKey(const Key('connectionWideFormPane')), findsNothing);
      }
    }
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('窄屏大字体保持可滚动且无溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _connectionScreen(textScaler: const TextScaler.linear(1.6)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const Key('connectionBrandTitle'))).height,
      greaterThan(24),
    );
  });

  testWidgets('连接页使用统一产品名', (tester) async {
    await tester.pumpWidget(_connectionScreen());
    await tester.pumpAndSettle();

    expect(find.text('飞翔播放器'), findsOneWidget);
    expect(find.text('飞牛播放器'), findsNothing);
  });

  testWidgets('服务选择器与登录按钮属于同一张连接卡', (tester) async {
    await tester.pumpWidget(_connectionScreen());
    await tester.pumpAndSettle();

    final panel = find.byKey(const Key('connectionLoginFormPanel'));
    expect(
      find.ancestor(
        of: find.byKey(const Key('connectionBackendSelector')),
        matching: panel,
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byKey(const Key('connectionSubmitButton')),
        matching: panel,
      ),
      findsOneWidget,
    );
  });

  testWidgets('自定义绿色主题下连接主按钮仍使用雾蓝色', (tester) async {
    final colors = AppThemePalette.colorsFor(
      AppThemePreset.forest,
      customAccentColor: Colors.green,
    );
    await tester.pumpWidget(
      _connectionScreen(theme: AppThemeBuilder.buildFromColors(colors)),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<ElevatedButton>(
      find.descendant(
        of: find.byKey(const Key('connectionSubmitButton')),
        matching: find.byType(ElevatedButton),
      ),
    );
    final buttonColor = button.style!.backgroundColor!.resolve(<WidgetState>{});
    expect(buttonColor, const Color(0xFF567A98));
    expect(buttonColor, isNot(equals(Colors.green)));
  });

  testWidgets('切换服务时清除连接错误提示', (tester) async {
    await tester.pumpWidget(_connectionScreen());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('connectionSubmitButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('connectionInlineErrorText')), findsOneWidget);
    await tester.tap(find.text('Emby'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('connectionInlineErrorText')), findsNothing);
  });
}

Widget _connectionScreen({ThemeData? theme, TextScaler? textScaler}) {
  return MultiProvider(
    providers: [ChangeNotifierProvider(create: (_) => NasProvider())],
    child: MaterialApp(
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: theme ?? AppThemeBuilder.buildFromColors(AppThemePalette.fallback),
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: textScaler ?? mediaQuery.textScaler,
          ),
          child: child!,
        );
      },
      home: const ConnectionScreen(),
    ),
  );
}
