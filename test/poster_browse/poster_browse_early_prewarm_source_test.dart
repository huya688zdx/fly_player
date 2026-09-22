import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('首页数据就绪后按页面表现档位旁路预热继续观看素材', () {
    final source = File(
      'lib/screens/media_list_screen.dart',
    ).readAsStringSync();

    expect(source, contains('Future<void> _prewarmPosterBrowseArtwork('));
    expect(
      source,
      contains('PosterBrowseArtworkPrewarmCache.shared.warmFirst('),
    );
    expect(source, contains('posterBrowseHomePrewarmLimit(visibleCount)'));
    expect(source, contains('if (prewarmLimit == 0) return;'));
    expect(source, contains('limit: prewarmLimit'));
    expect(source, contains('maxConcurrent: 1'));
    expect(source, contains('onCardsLoaded:'));
    expect(source, contains('cards: cards'));
    expect(source, contains('centerIndex: centerIndex'));
    expect(
      source,
      contains('PosterBrowseInitialArtworkPolicy.visibleCountFor'),
    );
    expect(source, contains('unawaited('));
    expect(source, contains('_prewarmPosterBrowseArtwork('));
  });

  test('海报页首屏同步消费已完成结果并复用进行中的请求', () {
    final source = File(
      'lib/screens/poster_browse/poster_browse_screen.dart',
    ).readAsStringSync();

    expect(source, contains('PosterBrowseArtworkPrewarmCache.shared.peek('));
    expect(
      source,
      contains('PosterBrowseArtworkPrewarmCache.shared.futureFor('),
    );
    expect(source, contains('final prewarmed ='));
    expect(source, contains('await _hydrateInitialVisibleArtwork('));
    expect(source, contains('initialEnrichmentById'));
    expect(source, contains('while (isActive())'));
    expect(source, contains('if (latestProfile == profile)'));
  });
}
