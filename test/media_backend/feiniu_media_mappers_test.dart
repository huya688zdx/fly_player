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
}
