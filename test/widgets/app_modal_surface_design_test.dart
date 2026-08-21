import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/pages/long_text_overlay_page.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/widgets/common/app_modal_surface.dart';
import 'package:fly_player/widgets/common/track_option_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app({required WidgetBuilder builder}) => MediaQuery(
  data: const MediaQueryData(size: Size(390, 800)),
  child: MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: AppThemeBuilder.build(AppThemePreset.midnight),
    home: Builder(builder: builder),
  ),
);

Widget _runtimeApp({required AppThemeColors colors, required Widget child}) =>
    MaterialApp(
      theme: AppThemeBuilder.build(AppThemePreset.midnight),
      home: AppRuntimeColorScope(
        colors: colors,
        hasRuntimeColors: true,
        child: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('轨道选择使用单一分组列表和紧凑协调的选中态', (tester) async {
    await tester.pumpWidget(
      _app(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => TrackOptionSheet.show(
              context,
              title: '选择字幕',
              selectedId: 'default',
              items: const <TrackOptionSheetItem>[
                TrackOptionSheetItem(id: 'off', title: '字幕关'),
                TrackOptionSheetItem(
                  id: 'default',
                  title: '未知语言-默认',
                  subtitle: 'SUP',
                ),
                TrackOptionSheetItem(
                  id: 'one',
                  title: '未知语言',
                  subtitle: 'SUP 1',
                ),
              ],
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('app-modal-surface-track-options')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('track-option-group')),
      findsOneWidget,
    );
    expect(find.byType(Divider), findsNWidgets(2));
    expect(
      tester.getSize(
        find.byKey(const ValueKey<String>('track-selection-default')),
      ),
      const Size.square(22),
    );
    final selectedTile = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey<String>('track-option-tile-default')),
    );
    final decoration = selectedTile.decoration as BoxDecoration;
    final colors = Theme.of(
      tester.element(find.text('未知语言-默认')),
    ).extension<AppThemeColors>()!;
    expect(decoration.color, isNot(colors.surfaceSubtle));
    expect(decoration.border, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('长文本弹层显示所属条目并使用适合阅读的正文排版', (tester) async {
    await tester.pumpWidget(
      _app(
        builder: (_) => const Scaffold(
          body: LongTextOverlayPage(
            title: '莉兹与青鸟',
            sectionTitle: '简介',
            content: '第一段简介。\n\n第二段简介。',
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('app-modal-surface-long-text')),
      findsOneWidget,
    );
    expect(find.text('莉兹与青鸟'), findsOneWidget);
    final sectionTitle = tester.widget<Text>(find.text('简介'));
    expect(sectionTitle.style?.fontSize, 18);
    expect(sectionTitle.style?.fontWeight, FontWeight.w700);
    final body = tester.widget<Text>(
      find.byKey(const ValueKey<String>('long-text-content')),
    );
    expect(body.style?.fontSize, 16);
    expect(body.style?.fontWeight, FontWeight.w400);
    expect(body.style?.height, 1.65);
    expect(tester.takeException(), isNull);
  });

  testWidgets('弹层表面使用页面运行时取色生成多层低饱和渐变', (tester) async {
    final baseColors = AppThemeBuilder.build(
      AppThemePreset.midnight,
    ).extension<AppThemeColors>()!;
    const runtimeAccent = Color(0xFFE06755);
    final runtimeColors = baseColors.copyWith(accent: runtimeAccent);

    await tester.pumpWidget(
      _runtimeApp(
        colors: runtimeColors,
        child: const AppModalSurface(
          key: ValueKey<String>('runtime-modal'),
          floating: true,
          child: SizedBox(width: 240, height: 180),
        ),
      ),
    );

    final decorated = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('runtime-modal')),
        matching: find.byType(DecoratedBox),
      ),
    );
    final decoration = decorated.decoration as BoxDecoration;
    final gradient = decoration.gradient! as LinearGradient;
    expect(gradient.colors, hasLength(3));
    expect(gradient.colors.first, isNot(runtimeColors.backgroundElevated));
    expect(gradient.colors.toSet(), hasLength(3));
    expect(decoration.border, isNotNull);
  });
}
