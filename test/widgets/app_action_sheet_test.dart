import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/widgets/common/app_action_sheet.dart';

Widget _testApp({
  required double width,
  double height = 800,
  required double textScale,
  required WidgetBuilder builder,
  Color? customAccentColor,
}) {
  return MediaQuery(
    data: MediaQueryData(
      size: Size(width, height),
      textScaler: TextScaler.linear(textScale),
    ),
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppThemeBuilder.build(
        AppThemePreset.midnight,
        customAccentColor: customAccentColor,
      ),
      home: Builder(builder: builder),
    ),
  );
}

Future<void> _openSheet(
  WidgetTester tester, {
  required double width,
  double height = 800,
  required double textScale,
  Color? customAccentColor,
  List<AppActionSheetOption<String>>? options,
}) async {
  await tester.pumpWidget(
    _testApp(
      width: width,
      height: height,
      textScale: textScale,
      customAccentColor: customAccentColor,
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showAppActionSheet<String>(
              context,
              title: '媒体操作',
              cancelText: '取消',
              options:
                  options ??
                  const [
                    AppActionSheetOption(value: 'detail', label: '查看详情'),
                    AppActionSheetOption(value: 'watched', label: '标为已观看'),
                    AppActionSheetOption(value: 'favorite', label: '收藏'),
                  ],
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
  // ignore: avoid_print
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
  });

  testWidgets('390宽且字号1使用两列并固定按钮字号', (tester) async {
    await _openSheet(tester, width: 390, textScale: 1);

    expect(find.byKey(const ValueKey('action-sheet-grid-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('action-sheet-grid-1')), findsNothing);
    expect(tester.widget<Text>(find.text('查看详情')).style?.fontSize, 16);
    expect(find.text('媒体操作'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });

  testWidgets('320宽且字号2的最长中文标签完整落在按钮内', (tester) async {
    const label = '从“继续观看”中移除';
    await _openSheet(
      tester,
      width: 320,
      textScale: 2,
      options: const [AppActionSheetOption(value: 'remove', label: label)],
    );
    expect(find.byKey(const ValueKey('action-sheet-grid-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('action-sheet-grid-2')), findsNothing);
    final textRect = tester.getRect(find.text(label));
    final buttonRect = tester.getRect(
      find
          .ancestor(of: find.text(label), matching: find.byType(FilledButton))
          .first,
    );
    expect(buttonRect.height, greaterThanOrEqualTo(83.2 - 1));
    expect(textRect.top, greaterThanOrEqualTo(buttonRect.top - 1));
    expect(textRect.bottom, lessThanOrEqualTo(buttonRect.bottom + 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('字号3且短屏时长菜单可滚动到最长按钮并点击', (tester) async {
    const label = '从“继续观看”中移除';
    final options = [
      for (var index = 0; index < 8; index++)
        AppActionSheetOption(value: 'option-$index', label: '操作$index'),
      const AppActionSheetOption(value: 'remove', label: label),
    ];
    await _openSheet(
      tester,
      width: 320,
      height: 500,
      textScale: 3,
      options: options,
    );

    final scrollable = find.byType(SingleChildScrollView);
    expect(scrollable, findsOneWidget);
    final buttonFinder = find
        .ancestor(of: find.text(label), matching: find.byType(FilledButton))
        .first;
    final before = tester.getRect(buttonFinder);
    expect(before.bottom, greaterThan(500));
    await tester.drag(scrollable, const Offset(0, -1000));
    await tester.pumpAndSettle();
    final buttonRect = tester.getRect(buttonFinder);
    expect(buttonRect.bottom, lessThan(before.bottom));
    expect(buttonRect.top, greaterThanOrEqualTo(0));
    expect(buttonRect.center.dy, lessThanOrEqualTo(500));
    expect(buttonRect.height, greaterThanOrEqualTo(124.8 - 1));
    final textRect = tester.getRect(find.text(label));
    expect(textRect.top, greaterThanOrEqualTo(buttonRect.top - 1));
    expect(textRect.bottom, lessThanOrEqualTo(buttonRect.bottom + 1));
    expect(tester.takeException(), isNull);
    await tester.tap(buttonFinder);
    await tester.pumpAndSettle();
  });

  testWidgets('泛型选项点击返回对应值且取消返回null', (tester) async {
    await tester.pumpWidget(
      _testApp(
        width: 390,
        textScale: 1,
        builder: (context) => const Scaffold(),
      ),
    );
    final context = tester.element(find.byType(Scaffold));
    final selected = showAppActionSheet<int>(
      context,
      title: '媒体操作',
      cancelText: '取消',
      options: const [AppActionSheetOption(value: 7, label: '选择七')],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择七'));
    await tester.pumpAndSettle();
    expect(await selected, 7);

    final cancelled = showAppActionSheet<int>(
      context,
      title: '媒体操作',
      cancelText: '取消',
      options: const [AppActionSheetOption(value: 7, label: '选择七')],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await cancelled, isNull);
  });

  testWidgets('字号1.3时切换为单列', (tester) async {
    await _openSheet(tester, width: 390, textScale: 1.3);

    expect(find.byKey(const ValueKey('action-sheet-grid-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('action-sheet-grid-2')), findsNothing);
  });

  testWidgets('普通按钮使用surfaceStrong背景和textPrimary前景色', (tester) async {
    await _openSheet(tester, width: 390, textScale: 1);

    final button = tester.widget<FilledButton>(
      find
          .ancestor(of: find.text('查看详情'), matching: find.byType(FilledButton))
          .first,
    );
    final colors = Theme.of(
      tester.element(find.text('查看详情')),
    ).extension<AppThemeColors>()!;
    expect(button.style?.backgroundColor?.resolve({}), colors.surfaceStrong);
    expect(button.style?.foregroundColor?.resolve({}), colors.textPrimary);
  });

  testWidgets('危险按钮使用混合背景和亮度语义前景色', (tester) async {
    await tester.pumpWidget(
      _testApp(
        width: 390,
        textScale: 1,
        builder: (context) => Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showAppActionSheet<String>(
                context,
                title: '危险操作',
                options: const [
                  AppActionSheetOption(
                    value: 'delete',
                    label: '删除',
                    destructive: true,
                  ),
                ],
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    final colors = Theme.of(
      tester.element(find.text('删除')),
    ).extension<AppThemeColors>()!;
    final expectedBackground = Color.alphaBlend(
      colors.danger.withValues(alpha: .14),
      colors.surfaceStrong,
    );
    final button = tester.widget<FilledButton>(
      find
          .ancestor(of: find.text('删除'), matching: find.byType(FilledButton))
          .first,
    );
    expect(button.style?.backgroundColor?.resolve({}), expectedBackground);
    expect(button.style?.foregroundColor?.resolve({}), Colors.white);
  });
}
