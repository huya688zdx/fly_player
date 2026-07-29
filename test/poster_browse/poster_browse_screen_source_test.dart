import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File(
      'lib/screens/poster_browse/poster_browse_screen.dart',
    ).readAsStringSync();
  });

  test('目录行通过共享 session Future 按需加载', () {
    expect(source, contains("import 'poster_browse_catalog_session.dart';"));
    expect(
      source,
      contains("import 'poster_browse_catalog_load_coordinator.dart';"),
    );
    expect(source, contains('Future<void> _ensureCatalogLoaded('));
    expect(source, contains('await ticket.future'));
    expect(source, contains('selectWhenReady: true'));
    expect(
      source,
      contains('_displayById.putIfAbsent('),
      reason: '目录初始展示不得覆盖已提交的 enrichment 展示',
    );
  });

  test('素材补全按世代策略通过 setState 即时提交', () {
    expect(
      source,
      contains("import 'poster_browse_enrichment_commit_policy.dart';"),
    );
    expect(source, contains('PosterBrowseEnrichmentCommitPolicy.resolve('));
    expect(source, contains('if (!decision.commitDisplay) return;'));
    expect(
      source,
      contains('setState(() => _displayById[card.id] = enrichedDisplay);'),
    );
  });

  test('只要分类行非空即构建页面壳且允许焦点项为空', () {
    expect(source, contains(': _rows.isEmpty'));
    expect(
      source,
      isNot(
        contains(': focusedItem == null\n                ? _buildError(l10n)'),
      ),
    );
    expect(source, contains('required PosterBrowseDisplayItem? focusedItem,'));
  });

  test('点击合法分类先提交选中行再处理空行加载状态', () {
    final start = source.indexOf('void _handleSelectRow(int rowIndex)');
    final end = source.indexOf('void _handleLargeSelectItem', start);
    final method = source.substring(start, end);

    expect(start, isNonNegative);
    expect(method, contains('setState(() {'));
    expect(method, contains('_selection.selectRow(rowIndex);'));
    expect(
      method.indexOf('_selection.selectRow(rowIndex);'),
      lessThan(method.indexOf('if (row.items.isEmpty)')),
    );
    expect(
      method,
      contains('row.loadState != PosterBrowseRowLoadState.loaded'),
      reason: 'loaded 空库保持选中空态，failed/idle/loading 才进入加载协调器',
    );
  });

  test('无继续观看时元数据完成即显示壳并异步加载首媒体库', () {
    final start = source.indexOf('Future<void> _load({');
    final end = source.indexOf('bool _isCurrentLoad', start);
    final method = source.substring(start, end);

    expect(method, isNot(contains('_loading = !hasContinueWatching')));
    expect(method, contains('_loading = false;'));
    expect(method, contains('_selection.selectRow(firstCatalogIndex);'));
    expect(
      method,
      contains(
        '_ensureCatalogLoaded(firstCatalogIndex, selectWhenReady: true)',
      ),
    );
    expect(
      method,
      isNot(contains('await _ensureCatalogLoaded(firstCatalogIndex')),
    );
  });
}
