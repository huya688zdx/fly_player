import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/widgets/common/app_action_sheet.dart';

Widget _testApp({
  required double width,
  required double textScale,
  required WidgetBuilder builder,
  Color? customAccentColor,
}) {
  return MediaQuery(
    data: MediaQueryData(
      size: Size(width, 800),
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
  required double textScale,
  Color? customAccentColor,
}) async {
  await tester.pumpWidget(
    _testApp(
      width: width,
      textScale: textScale,
      customAccentColor: customAccentColor,
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showAppActionSheet<String>(
              context,
              title: '媒体操作',
              cancelText: '取消',
              options: const [
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

  testWidgets('320宽且大字使用单列且不溢出', (tester) async {
    await _openSheet(tester, width: 320, textScale: 2);

    expect(find.byKey(const ValueKey('action-sheet-grid-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('action-sheet-grid-2')), findsNothing);
    expect(tester.takeException(), isNull);
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
