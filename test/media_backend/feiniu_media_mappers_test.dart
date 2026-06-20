import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/feiniu/feiniu_media_mappers.dart';
import 'package:fly_player/models/media_item.dart';
import 'package:fly_player/models/media_library_item.dart';

void main() {
  test('maps Feiniu MediaItem to MediaCatalog', () {
    final catalog = mapFeiniuCatalog(
      MediaItem(id: 'cat-1', name: '电影', type: 'Movie', path: '/p.jpg'),
    );

    expect(catalog.id, 'cat-1');
    expect(catalog.title, '电影');
    expect(catalog.type, 'Movie');
    expect(catalog.primaryImage.url, '/p.jpg');
  });

  test('maps Feiniu MediaItem poster list to MediaCatalog posters', () {
    final catalog = mapFeiniuCatalog(
      MediaItem(
        id: 'cat-2',
        name: '剧集',
        type: 'Series',
        path: '/a.jpg',
        posters: const ['/a.jpg', '/b.jpg'],
      ),
    );

    // 分类条最多叠展示 2 张封面，列表顺序需原样保留以保证视觉一致。
    expect(catalog.posters.map((e) => e.url).toList(), ['/a.jpg', '/b.jpg']);
  });

  test('maps Feiniu MediaLibraryItem to MediaItemSummary', () {
    final item = mapFeiniuItemSummary(
      MediaLibraryItem(
        guid: 'item-1',
        title: '电影 A',
        tvTitle: '',
        type: 'Movie',
        poster: '/poster.jpg',
        releaseDate: '',
        firstAirDate: '',
        lastAirDate: '',
        voteAverage: '',
        overview: '',
        watched: 1,
        watchedTs: 0,
        ts: 0,
        duration: 123,
        seasonNumber: 0,
        episodeNumber: 0,
        numberOfSeasons: 0,
        numberOfEpisodes: 0,
        localNumberOfSeasons: 0,
        localNumberOfEpisodes: 0,
        parentGuid: '',
        parentTitle: '',
        ancestorGuid: '',
        ancestorName: '',
        path: '',
      ),
    );

    expect(item.id, 'item-1');
    expect(item.displayTitle, '电影 A');
    expect(item.watched, isTrue);
    expect(item.durationSeconds, 123);
  });

  test('preserves episode display fields for lossless round-trip', () {
    final item = mapFeiniuItemSummary(
      MediaLibraryItem(
        guid: 'ep-1',
        title: '剧集 B',
        tvTitle: '第 3 集',
        type: 'Episode',
        poster: '/ep.jpg',
        posterWidth: 1000,
        posterHeight: 1500,
        releaseDate: '2024-01-02',
        firstAirDate: '',
        lastAirDate: '',
        voteAverage: '8.5',
        overview: '',
        watched: 0,
        watchedTs: 0,
        ts: 0,
        duration: 2400,
        seasonNumber: 2,
        episodeNumber: 3,
        numberOfSeasons: 4,
        numberOfEpisodes: 12,
        localNumberOfSeasons: 0,
        localNumberOfEpisodes: 0,
        parentGuid: '',
        parentTitle: '',
        ancestorGuid: '',
        ancestorName: '',
        path: '',
      ),
    );

    // 副标题优先（复刻飞牛 displayTitle 回退语义），原始 title 仍保留。
    expect(item.title, '剧集 B');
    expect(item.secondaryTitle, '第 3 集');
    expect(item.displayTitle, '第 3 集');
    // 首页卡片所需展示字段不丢失。
    expect(item.rating, '8.5');
    expect(item.releaseDate, '2024-01-02');
    expect(item.seasonNumber, 2);
    expect(item.episodeNumber, 3);
    expect(item.numberOfSeasons, 4);
    expect(item.numberOfEpisodes, 12);
    expect(item.posterWidth, 1000);
    expect(item.posterHeight, 1500);
    expect(item.isLandscapePoster, isFalse);
    expect(item.watched, isFalse);
  });
}
