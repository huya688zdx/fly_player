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
    expect(source, contains('Future<void> _ensureCatalogLoaded('));
    expect(source, contains('await session.load(row.catalogId)'));
    expect(source, contains('selectWhenReady: true'));
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
}
