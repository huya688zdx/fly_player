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

  test('页面实际接入纯状态策略与当前行重试回调', () {
    expect(source, contains("import 'poster_browse_screen_policy.dart';"));
    expect(source, contains('PosterBrowseScreenPolicy.bodyFor('));
    expect(source, contains('PosterBrowseScreenPolicy.selectionFor(row)'));
    expect(
      source,
      contains('onRetryCurrentRow: () => _handleSelectRow(selectedRow)'),
    );
  });

  test('目录索引重试只刷新目录元数据并用全部目录替换占位', () {
    expect(source, contains('Future<void> _reloadCatalogsRow('));
    expect(source, contains('loadCatalogs(backend)'));
    expect(source, contains('replacePosterBrowseCatalogIndexRow('));
    expect(source, contains('if (decision.reloadCatalogs)'));
    expect(
      source,
      contains('_ensureCatalogLoaded(rowIndex, selectWhenReady: shouldSelect)'),
    );
  });

  test('动态主题页键使用身份校验后的 settled item', () {
    expect(
      source,
      contains("pageKey: settledItem?.card.id ?? 'poster_browse_empty'"),
    );
  });
}
