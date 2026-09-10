import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/widgets/common/app_action_sheet.dart';

Widget _testApp({
  required double width,
  double height = 800,
  double textScale = 1,
  double viewInsetsBottom = 0,
  required WidgetBuilder builder,
}) {
  return MediaQuery(
    data: MediaQueryData(
      size: Size(width, height),
      textScaler: TextScaler.linear(textScale),
      viewInsets: EdgeInsets.only(bottom: viewInsetsBottom),
    ),
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppThemeBuilder.build(AppThemePreset.midnight),
      home: Builder(builder: builder),
    ),
  );
}

Future<void> _openSheet(
  WidgetTester tester, {
  double width = 390,
  double height = 800,
  double textScale = 1,
  List<AppActionSheetOption<String>>? options,
}) async {
  await tester.pumpWidget(
    _testApp(
      width: width,
      height: height,
      textScale: textScale,
      builder: (context) => Scaffold(
        body: ElevatedButton(
          onPressed: () => showAppActionSheet<String>(
            context,
            title: '媒体操作',
            cancelText: '取消',
            options:
                options ??
                const <AppActionSheetOption<String>>[
                  AppActionSheetOption(value: 'detail', label: '查看详情'),
                  AppActionSheetOption(value: 'watched', label: '标为已观看'),
                  AppActionSheetOption(value: 'favorite', label: '收藏'),
                ],
          ),
          child: const Text('打开'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  testWidgets('操作菜单使用无圆点的独立描边项且不再显示网格和取消条', (tester) async {
    await _openSheet(tester);

    expect(
      find.byKey(const ValueKey<String>('app-modal-surface-action-sheet')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('action-sheet-options')),
      findsOneWidget,
    );
    expect(find.byType(GridView), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('取消'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('action-sheet-option-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('action-sheet-selection-0')),
      findsNothing,
    );
    final firstRow = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey<String>('action-sheet-option-0')),
    );
    final secondRow = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey<String>('action-sheet-option-1')),
    );
    final firstDecoration = firstRow.decoration! as BoxDecoration;
    final secondDecoration = secondRow.decoration! as BoxDecoration;
    expect(
      (firstDecoration.border! as Border).top.color,
      isNot(Colors.transparent),
    );
    expect(
      (secondDecoration.border! as Border).top.color,
      isNot(Colors.transparent),
    );
    expect(firstDecoration.color, isNot(Colors.transparent));
    expect(secondDecoration.color, isNot(Colors.transparent));
    final firstRect = tester.getRect(
      find.byKey(const ValueKey<String>('action-sheet-option-0')),
    );
    final secondRect = tester.getRect(
      find.byKey(const ValueKey<String>('action-sheet-option-1')),
    );
    expect(secondRect.top - firstRect.bottom, 8);
    expect(tester.takeException(), isNull);
  });

  testWidgets('大字号短屏操作列表保持自适应行高并可滚动到最后一项', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(320, 500));
    const label = '从“继续观看”中移除';
    await _openSheet(
      tester,
      width: 320,
      height: 500,
      textScale: 2,
      options: <AppActionSheetOption<String>>[
        for (var index = 0; index < 8; index++)
          AppActionSheetOption(value: 'option-$index', label: '操作 $index'),
        const AppActionSheetOption(
          value: 'remove',
          label: label,
          destructive: true,
        ),
      ],
    );

    final list = find.byKey(const ValueKey<String>('action-sheet-options'));
    final scrollable = find.descendant(
      of: list,
      matching: find.byType(Scrollable),
    );
    final lastRow = find.byKey(const ValueKey<String>('action-sheet-option-8'));
    await tester.scrollUntilVisible(lastRow, 260, scrollable: scrollable);
    await tester.pumpAndSettle();

    expect(tester.getRect(lastRow).center.dy, lessThanOrEqualTo(500));
    expect(tester.getRect(find.text(label)).height, greaterThan(20));
    expect(tester.takeException(), isNull);
  });

  testWidgets('操作菜单点击状态行返回泛型值且点击遮罩返回空', (tester) async {
    await tester.pumpWidget(
      _testApp(width: 390, builder: (context) => const Scaffold()),
    );
    final context = tester.element(find.byType(Scaffold));

    final selected = showAppActionSheet<int>(
      context,
      title: '媒体操作',
      options: const <AppActionSheetOption<int>>[
        AppActionSheetOption(value: 7, label: '选择七'),
      ],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择七'));
    await tester.pumpAndSettle();
    expect(await selected, 7);

    final cancelled = showAppActionSheet<int>(
      context,
      title: '媒体操作',
      options: const <AppActionSheetOption<int>>[
        AppActionSheetOption(value: 7, label: '选择七'),
      ],
    );
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(await cancelled, isNull);
  });

  testWidgets('危险操作保留红色语义但仍使用同一列表行结构', (tester) async {
    await _openSheet(
      tester,
      options: const <AppActionSheetOption<String>>[
        AppActionSheetOption(value: 'delete', label: '删除', destructive: true),
      ],
    );

    final row = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey<String>('action-sheet-option-0')),
    );
    final decoration = row.decoration! as BoxDecoration;
    final colors = Theme.of(
      tester.element(find.text('删除')),
    ).extension<AppThemeColors>()!;
    final label = tester.widget<Text>(find.text('删除'));

    expect(decoration.color, isNot(Colors.transparent));
    expect(decoration.border, isNotNull);
    expect(label.style?.color, colors.danger);
    expect(tester.takeException(), isNull);
  });

  testWidgets('键盘占用空间时操作面板保持在键盘上方', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 700));
    await tester.pumpWidget(
      _testApp(
        width: 390,
        height: 700,
        viewInsetsBottom: 240,
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showAppActionSheet<String>(
              context,
              title: '媒体操作',
              options: const <AppActionSheetOption<String>>[
                AppActionSheetOption(value: 'detail', label: '查看详情'),
              ],
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    final surface = tester.getRect(
      find.byKey(const ValueKey<String>('app-modal-surface-action-sheet')),
    );
    expect(surface.bottom, lessThanOrEqualTo(461));
    expect(tester.takeException(), isNull);
  });
}
