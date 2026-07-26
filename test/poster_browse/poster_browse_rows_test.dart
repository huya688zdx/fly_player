import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_catalog.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/media_backend/media_item_card.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_rows.dart';

MediaItemCard card(String id) => MediaItemCard(
  id: id,
  title: id,
  type: 'Movie',
  primaryImage: MediaImageRef.empty,
);

void main() {
  test('三类行按序组装，空行整行剔除', () {
    final rows = buildPosterBrowseRows(
      continueWatching: <MediaItemCard>[card('c1')],
      latestItems: const <MediaItemCard>[], // 空 → 隐藏
      catalogs: const <MediaCatalog>[
        MediaCatalog(
          id: 'lib1',
          title: '电影库',
          type: 'movies',
          primaryImage: MediaImageRef.empty,
        ),
        MediaCatalog(
          id: 'lib2',
          title: '空库',
          type: 'tvshows',
          primaryImage: MediaImageRef.empty,
        ),
      ],
      catalogItems: <String, List<MediaItemCard>>{
        'lib1': <MediaItemCard>[card('m1'), card('m2')],
        'lib2': const <MediaItemCard>[], // 空 → 隐藏
      },
    );
    expect(rows, hasLength(2));
    expect(rows[0].kind, PosterBrowseRowKind.continueWatching);
    expect(rows[1].kind, PosterBrowseRowKind.catalog);
    expect(rows[1].catalogId, 'lib1');
    expect(rows[1].catalogTitle, '电影库');
    expect(rows[1].items.map((e) => e.id), ['m1', 'm2']);
  });

  test('最近添加行在继续观看之后、媒体库之前', () {
    final rows = buildPosterBrowseRows(
      continueWatching: <MediaItemCard>[card('c1')],
      latestItems: <MediaItemCard>[card('l1')],
      catalogs: const <MediaCatalog>[],
      catalogItems: const <String, List<MediaItemCard>>{},
    );
    expect(rows.map((r) => r.kind), <PosterBrowseRowKind>[
      PosterBrowseRowKind.continueWatching,
      PosterBrowseRowKind.latest,
    ]);
  });

  test('全空返回空列表', () {
    final rows = buildPosterBrowseRows(
      continueWatching: const <MediaItemCard>[],
      latestItems: const <MediaItemCard>[],
      catalogs: const <MediaCatalog>[],
      catalogItems: const <String, List<MediaItemCard>>{},
    );
    expect(rows, isEmpty);
  });
}
