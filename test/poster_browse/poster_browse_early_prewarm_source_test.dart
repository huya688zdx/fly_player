import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('首页先展示基础区块，再逐项加载分类且不预热其他页面素材', () {
    final source = File(
      'lib/screens/media_list_screen.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('_prewarmPosterBrowseArtwork')));
    expect(source, isNot(contains('PosterBrowseArtworkEnricher')));
    expect(source, isNot(contains('Future.wait(categoryFutures)')));
    final fetch = source.substring(
      source.indexOf('Future<void> _fetchHomeData()'),
      source.indexOf('Future<void> _backgroundRefresh()'),
    );
    expect(
      fetch.indexOf('_isLoading = false'),
      lessThan(fetch.indexOf('_refreshCategoryPreviews(')),
    );
    expect(source, contains('await WidgetsBinding.instance.endOfFrame'));
    expect(source, contains('await _loadCategoryItems('));
  });

  test('海报页首屏只消费缓存，素材补全不阻塞页面显示', () {
    final source = File(
      'lib/screens/poster_browse/poster_browse_screen.dart',
    ).readAsStringSync();

    expect(source, contains('PosterBrowseArtworkPrewarmCache.shared.peek('));
    expect(
      source,
      contains('PosterBrowseArtworkPrewarmCache.shared.futureFor('),
    );
    expect(source, contains('final prewarmed ='));
    expect(source, isNot(contains('_hydrateInitialVisibleArtwork(')));
    final load = source.substring(
      source.indexOf('Future<void> _load({'),
      source.indexOf('bool _isCurrentLoad('),
    );
    expect(
      load.indexOf('_loading = false'),
      lessThan(load.indexOf('_settle(')),
    );
  });
}
