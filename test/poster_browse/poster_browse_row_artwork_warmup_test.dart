import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/media_backend/media_item_card.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_artwork_enricher.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_row_artwork_warmup.dart';

void main() {
  test('继续观看整行按上限并发补全，并把每一项结果提交给页面', () async {
    final completers = <String, Completer<PosterBrowseEnrichment>>{};
    final submitted = <String>[];
    var active = 0;
    var maxActive = 0;

    final future = const PosterBrowseRowArtworkWarmup(maxConcurrent: 2).run(
      items: <MediaItemCard>[_card('a'), _card('b'), _card('c'), _card('d')],
      load: (card) {
        active += 1;
        if (active > maxActive) maxActive = active;
        final completer = Completer<PosterBrowseEnrichment>();
        completers[card.id] = completer;
        return completer.future.whenComplete(() => active -= 1);
      },
      onLoaded: (card, enrichment) => submitted.add(card.id),
      isActive: () => true,
    );

    await Future<void>.delayed(Duration.zero);
    expect(completers.keys, unorderedEquals(<String>['a', 'b']));
    expect(maxActive, 2);

    completers['a']!.complete(const PosterBrowseEnrichment());
    await Future<void>.delayed(Duration.zero);
    expect(completers.containsKey('c'), isTrue);
    expect(submitted, contains('a'));

    completers['b']!.complete(const PosterBrowseEnrichment());
    completers['c']!.complete(const PosterBrowseEnrichment());
    await Future<void>.delayed(Duration.zero);
    expect(completers.containsKey('d'), isTrue);
    completers['d']!.complete(const PosterBrowseEnrichment());

    await future;
    expect(submitted, unorderedEquals(<String>['a', 'b', 'c', 'd']));
    expect(maxActive, 2);
  });

  test('会话失效后不再领取队列中的新条目', () async {
    final first = Completer<PosterBrowseEnrichment>();
    final loaded = <String>[];
    var active = true;

    final future = const PosterBrowseRowArtworkWarmup(maxConcurrent: 1).run(
      items: <MediaItemCard>[_card('a'), _card('b')],
      load: (card) {
        loaded.add(card.id);
        return first.future;
      },
      onLoaded: (_, __) {},
      isActive: () => active,
    );

    await Future<void>.delayed(Duration.zero);
    active = false;
    first.complete(const PosterBrowseEnrichment());
    await future;

    expect(loaded, <String>['a']);
  });
}

MediaItemCard _card(String id) {
  return MediaItemCard(
    id: id,
    title: id,
    type: 'Episode',
    primaryImage: const MediaImageRef(url: 'poster.jpg'),
  );
}
