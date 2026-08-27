import 'dart:io';

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
        contains('AppCatalogFilterSheet.show'),
        reason: '$path 仍未复用共享筛选弹层',
      );
      expect(
        source,
        contains('AppCatalogSortSheet.show'),
        reason: '$path 仍未复用共享排序弹层',
      );
    }
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
