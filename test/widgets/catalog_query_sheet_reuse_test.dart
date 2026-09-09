import 'dart:io';

import 'package:fly_player/desktop/desktop_environment.dart';
import 'package:fly_player/desktop/desktop_floating_panel.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/widgets/common/app_catalog_query_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(WidgetBuilder builder) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: AppThemeBuilder.build(AppThemePreset.midnight),
  home: Builder(builder: builder),
);

void main() {
  setUp(() => DesktopEnvironment.debugOverridePlatform = false);
  tearDown(() => DesktopEnvironment.debugOverridePlatform = null);

  test('分类、收藏和媒体库页面复用同一套筛选与排序弹层', () {
    final shared = File('lib/widgets/common/app_catalog_query_sheets.dart');
    expect(shared.existsSync(), isTrue, reason: '缺少共享筛选与排序弹层组件');

    for (final path in <String>[
      'lib/screens/category_items_screen.dart',
      'lib/screens/favorite_items_screen_sheets.dart',
      'lib/pages/media_collection_detail_page.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains(
          path.contains('category_items_screen')
              ? 'AppCatalogFilterInlinePanel('
              : 'AppCatalogFilterSheet.show',
        ),
        reason: '$path 仍未复用共享筛选弹层',
      );
      expect(
        source,
        contains('AppCatalogSortSheet.show'),
        reason: '$path 仍未复用共享排序弹层',
      );
    }
  });

  testWidgets('桌面筛选复用横排面板，重置后确认返回最终选择', (tester) async {
    DesktopEnvironment.debugOverridePlatform = true;
    Map<String, Set<Object>>? result;
    await tester.pumpWidget(
      _app(
        (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await AppCatalogFilterSheet.show(
                context,
                sections: const [
                  AppCatalogFilterSection(
                    key: 'type',
                    title: '影视分类',
                    options: [
                      AppCatalogFilterOption(value: 'Movie', label: '电影'),
                      AppCatalogFilterOption(value: 'TV', label: '电视剧'),
                    ],
                  ),
                ],
              );
            },
            child: const Text('打开筛选'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开筛选'));
    await tester.pumpAndSettle();
    expect(find.byType(AppCatalogFilterInlinePanel), findsOneWidget);
    final nextOptionRect = tester.getRect(find.text('电视剧'));
    final initialWeight = tester
        .widget<Text>(find.text('电影'))
        .style!
        .fontWeight;
    final allFill = tester
        .widget<Material>(
          find
              .ancestor(of: find.text('全部'), matching: find.byType(Material))
              .first,
        )
        .color;
    expect(
      allFill,
      tester
          .element(find.text('全部'))
          .appColors
          .selection
          .withValues(alpha: 0.12),
    );
    await tester.tap(find.text('电影'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('电视剧')), nextOptionRect);
    expect(
      tester.widget<Text>(find.text('电影')).style!.fontWeight,
      initialWeight,
    );
    expect(
      tester
          .widget<AppCatalogFilterInlinePanel>(
            find.byType(AppCatalogFilterInlinePanel),
          )
          .sections
          .single
          .selectedValues,
      {'Movie'},
    );
    await tester.tap(find.text('重置'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AppCatalogFilterInlinePanel>(
            find.byType(AppCatalogFilterInlinePanel),
          )
          .sections
          .single
          .selectedValues,
      isEmpty,
    );
    expect(result, isNull);
    await tester.tap(find.text('电影'));
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(result, <String, Set<Object>>{
      'type': {'Movie'},
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('筛选打开后随窗口宽度切换位置并保留选择', (tester) async {
    DesktopEnvironment.debugOverridePlatform = true;
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var expanded = false;
    var selected = <Object>{};
    await tester.pumpWidget(
      _app(
        (context) => Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => AppCatalogFilterRegion(
              expanded: expanded,
              onDismiss: () => update(() => expanded = false),
              toolbar: SizedBox(
                width: double.infinity,
                height: 48,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => update(() => expanded = !expanded),
                    child: const Text('筛选'),
                  ),
                ),
              ),
              panelBuilder: (floating) => AppCatalogFilterInlinePanel(
                framed: !floating,
                sections: [
                  AppCatalogFilterSection(
                    key: 'type',
                    title: '影视分类',
                    selectedValues: selected,
                    options: const [
                      AppCatalogFilterOption(value: 'Movie', label: '电影'),
                    ],
                  ),
                ],
                onOptionSelected: (_, value) =>
                    update(() => selected = {if (value != null) value}),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('筛选'));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopFloatingPanel), findsOneWidget);
    await tester.tap(find.text('电影'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1400, 700);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopFloatingPanel), findsNothing);
    final panel = find.byType(AppCatalogFilterInlinePanel);
    expect(panel, findsOneWidget);
    expect(
      tester
          .widget<AppCatalogFilterInlinePanel>(panel)
          .sections
          .single
          .selectedValues,
      {'Movie'},
    );
    tester.view.physicalSize = const Size(800, 700);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopFloatingPanel), findsOneWidget);
    expect(panel, findsOneWidget);
    expect(
      tester
          .widget<AppCatalogFilterInlinePanel>(panel)
          .sections
          .single
          .selectedValues,
      {'Movie'},
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('共享筛选弹层使用统一表面并返回确认后的选择', (tester) async {
    Map<String, Set<Object>>? result;
    await tester.pumpWidget(
      _app(
        (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              result = await AppCatalogFilterSheet.show(
                context,
                sections: const <AppCatalogFilterSection>[
                  AppCatalogFilterSection(
                    key: 'type',
                    title: '影视分类',
                    options: <AppCatalogFilterOption>[
                      AppCatalogFilterOption(value: 'Movie', label: '电影'),
                      AppCatalogFilterOption(value: 'TV', label: '电视剧'),
                    ],
                  ),
                ],
              );
            },
            child: const Text('打开筛选'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开筛选'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('app-modal-surface-catalog-filter')),
      findsOneWidget,
    );
    expect(find.text('影视分类'), findsOneWidget);

    await tester.tap(find.text('电影'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(result, <String, Set<Object>>{
      'type': <Object>{'Movie'},
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('共享排序弹层使用字幕选择同款状态行并在第二行展示方向', (tester) async {
    AppCatalogSortResult? result;
    await tester.pumpWidget(
      _app(
        (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              result = await AppCatalogSortSheet.show(
                context,
                options: const <AppCatalogSortOption>[
                  AppCatalogSortOption(field: 'create_time', label: '按添加日期'),
                  AppCatalogSortOption(field: 'release_date', label: '按发行年份'),
                ],
                selectedField: 'create_time',
                sortType: 'DESC',
              );
            },
            child: const Text('打开排序'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开排序'));
    await tester.pumpAndSettle();
    final selected = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey<String>('catalog-sort-option-create_time')),
    );
    final decoration = selected.decoration! as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(14));
    expect(decoration.border, isNotNull);
    expect(
      tester.getSize(
        find.byKey(
          const ValueKey<String>('catalog-sort-selection-create_time'),
        ),
      ),
      const Size.square(22),
    );
    expect(find.text('降序'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('catalog-sort-drag-handle')),
      findsNothing,
    );
    final titleRect = tester.getRect(find.text('排序'));
    expect(titleRect.center.dx, lessThan(195));

    await tester.tap(find.text('按添加日期'));
    await tester.pumpAndSettle();

    expect(result?.field, 'create_time');
    expect(result?.sortType, 'ASC');
    expect(tester.takeException(), isNull);
  });

  testWidgets('筛选列表向上滚动不会被下拉关闭手势抢占', (tester) async {
    await tester.pumpWidget(
      _app(
        (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => AppCatalogFilterSheet.show(
              context,
              sections: <AppCatalogFilterSection>[
                for (int i = 0; i < 9; i++)
                  AppCatalogFilterSection(
                    key: 'section-$i',
                    title: '分组 $i',
                    options: <AppCatalogFilterOption>[
                      AppCatalogFilterOption(value: i, label: '选项 $i'),
                    ],
                  ),
              ],
            ),
            child: const Text('打开长筛选'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开长筛选'));
    await tester.pumpAndSettle();
    expect(find.text('分组 8'), findsNothing);

    await tester.drag(
      find.byKey(const ValueKey<String>('catalog-filter-sections')),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();

    expect(find.text('分组 8'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('app-modal-surface-catalog-filter')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
