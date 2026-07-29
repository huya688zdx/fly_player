import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/detail/media_detail.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/media_backend/media_item_card.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_artwork_enricher.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_artwork_prewarmer.dart';

void main() {
  test('只按单并发预热前四项，失败不阻断后续条目', () async {
    final completers = <String, Completer<PosterBrowseEnrichment>>{};
    final started = <String>[];
    var active = 0;
    var maxActive = 0;

    final cache = PosterBrowseArtworkPrewarmCache(maxEntries: 8);
    final future = cache.warmFirst(
      sessionKey: 'session-a',
      items: <MediaItemCard>[
        _card('a'),
        _card('b'),
        _card('c'),
        _card('d'),
        _card('e'),
      ],
      limit: 4,
      maxConcurrent: 1,
      load: (card) {
        started.add(card.id);
        active += 1;
        maxActive = active > maxActive ? active : maxActive;
        final completer = Completer<PosterBrowseEnrichment>();
        completers[card.id] = completer;
        return completer.future.whenComplete(() => active -= 1);
      },
      isActive: () => true,
    );

    await Future<void>.delayed(Duration.zero);
    expect(started, <String>['a']);
    expect(cache.futureFor(sessionKey: 'session-a', itemId: 'a'), isNotNull);

    final enrichmentA = _success('a');
    completers['a']!.complete(enrichmentA);
    await Future<void>.delayed(Duration.zero);
    expect(started, <String>['a', 'b']);
    expect(cache.peek(sessionKey: 'session-a', itemId: 'a'), same(enrichmentA));

    completers['b']!.completeError(StateError('暂时失败'));
    await Future<void>.delayed(Duration.zero);
    expect(started, <String>['a', 'b', 'c']);
    expect(cache.futureFor(sessionKey: 'session-a', itemId: 'b'), isNull);

    completers['c']!.complete(_success('c'));
    await Future<void>.delayed(Duration.zero);
    completers['d']!.complete(_success('d'));
    await future;

    expect(started, <String>['a', 'b', 'c', 'd']);
    expect(started, isNot(contains('e')));
    expect(maxActive, 1);
  });

  test('会话之间不共享结果，且失效后停止领取新任务', () async {
    final cache = PosterBrowseArtworkPrewarmCache(maxEntries: 8);
    final first = Completer<PosterBrowseEnrichment>();
    final started = <String>[];
    var active = true;

    final future = cache.warmFirst(
      sessionKey: 'session-a',
      items: <MediaItemCard>[_card('a'), _card('b')],
      limit: 4,
      maxConcurrent: 1,
      load: (card) {
        started.add(card.id);
        return first.future;
      },
      isActive: () => active,
    );

    await Future<void>.delayed(Duration.zero);
    active = false;
    first.complete(_success('a'));
    await future;

    expect(started, <String>['a']);
    expect(cache.peek(sessionKey: 'session-a', itemId: 'a'), isNotNull);
    expect(cache.peek(sessionKey: 'session-b', itemId: 'a'), isNull);
  });

  test('补全结果为失败时不进入长期预热缓存', () async {
    final cache = PosterBrowseArtworkPrewarmCache(maxEntries: 8);

    await cache.warmFirst(
      sessionKey: 'session-a',
      items: <MediaItemCard>[_card('a')],
      load: (_) async => const PosterBrowseEnrichment(hasLookupFailure: true),
      isActive: () => true,
    );

    expect(cache.futureFor(sessionKey: 'session-a', itemId: 'a'), isNull);
    expect(cache.peek(sessionKey: 'session-a', itemId: 'a'), isNull);
  });
}

MediaItemCard _card(String id) {
  return MediaItemCard(
    id: id,
    title: id,
    type: 'Episode',
    primaryImage: const MediaImageRef(url: 'landscape.jpg'),
  );
}

PosterBrowseEnrichment _success(String id) {
  return PosterBrowseEnrichment(
    itemDetail: MediaDetail(
      id: id,
      type: 'Movie',
      title: id,
      primaryImage: const MediaImageRef(url: 'portrait.jpg'),
    ),
  );
}
