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
    expect(find.byType(SegmentedButton<String>), findsNothing);
    expect(
      tester.getTopLeft(find.byType(ElevatedButton)).dy,
      closeTo(feiniuLoginButtonY, 0.5),
    );

    await tester.dragFrom(const Offset(400, 300), const Offset(360, 0));
    await tester.pumpAndSettle();

    expect(find.text('登录'), findsOneWidget);
    expect(find.text('重新登录 FN Connect'), findsOneWidget);
    expect(find.byType(SegmentedButton<String>), findsOneWidget);
  });

  testWidgets('高屏切换后端时登录按钮保持原位', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_connectionScreen());
    await tester.pumpAndSettle();
    final feiniuLoginButtonY = tester
        .getTopLeft(find.byType(ElevatedButton))
        .dy;

    await tester.tap(find.text('Emby'));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.byType(ElevatedButton)).dy,
      closeTo(feiniuLoginButtonY, 0.5),
    );
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
