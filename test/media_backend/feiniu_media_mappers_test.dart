import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/feiniu/feiniu_media_mappers.dart';
import 'package:fly_player/models/media_item.dart';
import 'package:fly_player/models/media_library_item.dart';

MediaLibraryItem _libraryItem({
  String guid = 'item',
  String title = 'title',
  String tvTitle = '',
  String type = 'Movie',
  String poster = '',
  int posterWidth = 0,
  int posterHeight = 0,
  List<String> posterList = const <String>[],
  String releaseDate = '',
  String firstAirDate = '',
  String lastAirDate = '',
  String voteAverage = '',
  int watched = 0,
  int duration = 0,
  int seasonNumber = 0,
  int episodeNumber = 0,
  int numberOfSeasons = 0,
  int numberOfEpisodes = 0,
  int localNumberOfSeasons = 0,
  int localNumberOfEpisodes = 0,
  int numberOfItem = 0,
  List<String> resolutions = const <String>[],
}) {
  return MediaLibraryItem(
    guid: guid,
    title: title,
    tvTitle: tvTitle,
    type: type,
    poster: poster,
    posterWidth: posterWidth,
    posterHeight: posterHeight,
    posterList: posterList,
    releaseDate: releaseDate,
    firstAirDate: firstAirDate,
    lastAirDate: lastAirDate,
    voteAverage: voteAverage,
    overview: '',
    watched: watched,
    watchedTs: 0,
    ts: 0,
    duration: duration,
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
    numberOfSeasons: numberOfSeasons,
    numberOfEpisodes: numberOfEpisodes,
    localNumberOfSeasons: localNumberOfSeasons,
    localNumberOfEpisodes: localNumberOfEpisodes,
    numberOfItem: numberOfItem,
    parentGuid: '',
    parentTitle: '',
    ancestorGuid: '',
    ancestorName: '',
    path: '',
    resolutions: resolutions,
  );
}

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

  test('mapFeiniuItemCard 无损搬运全部卡片展示字段', () {
    final card = mapFeiniuItemCard(
      _libraryItem(
        guid: 'card-1',
        title: '剧集 C',
        tvTitle: '第 5 集',
        type: 'Episode',
        poster: '/p.jpg',
        posterWidth: 1920,
        posterHeight: 1080,
        posterList: const ['/p.jpg', '/q.jpg'],
        releaseDate: '2020-01-01',
        firstAirDate: '2019-03-01',
        lastAirDate: '2022-06-01',
        voteAverage: '9.1',
        watched: 1,
        duration: 2400,
        seasonNumber: 2,
        episodeNumber: 5,
        numberOfSeasons: 4,
        numberOfEpisodes: 48,
        localNumberOfSeasons: 3,
        localNumberOfEpisodes: 30,
        numberOfItem: 7,
        resolutions: const ['2160p', '1080p'],
      ),
    );

    expect(card.id, 'card-1');
    expect(card.title, '剧集 C');
    expect(card.secondaryTitle, '第 5 集');
    expect(card.displayTitle, '第 5 集');
    expect(card.type, 'Episode');
    expect(card.primaryImage.url, '/p.jpg');
    expect(card.posters.map((e) => e.url).toList(), ['/p.jpg', '/q.jpg']);
    expect(card.durationSeconds, 2400);
    expect(card.watched, isTrue);
    expect(card.rating, '9.1');
    expect(card.releaseDate, '2020-01-01');
    expect(card.firstAirDate, '2019-03-01');
    expect(card.lastAirDate, '2022-06-01');
    expect(card.seasonNumber, 2);
    expect(card.episodeNumber, 5);
    expect(card.numberOfSeasons, 4);
    expect(card.numberOfEpisodes, 48);
    expect(card.localNumberOfSeasons, 3);
    expect(card.localNumberOfEpisodes, 30);
    expect(card.numberOfItem, 7);
    expect(card.posterWidth, 1920);
    expect(card.posterHeight, 1080);
    expect(card.isLandscapePoster, isTrue);
    expect(card.resolutions, ['2160p', '1080p']);
  });
}
