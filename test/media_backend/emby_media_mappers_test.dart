import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/emby/emby_media_mappers.dart';

void main() {
  const serverUrl = 'https://emby.example.test';
  const token = 'tok';

  group('mapEmbyView', () {
    test('媒体库 → MediaCatalog（type 取 CollectionType，图片带 api_key）', () {
      final catalog = mapEmbyView(
        <String, Object?>{
          'Id': 'lib-1',
          'Name': '电影',
          'CollectionType': 'movies',
          'ImageTags': <String, Object?>{'Primary': 'abc'},
        },
        serverUrl: serverUrl,
        token: token,
      );
      expect(catalog.id, 'lib-1');
      expect(catalog.title, '电影');
      expect(catalog.type, 'movies');
      expect(
        catalog.primaryImage.url,
        'https://emby.example.test/Items/lib-1/Images/Primary?tag=abc&api_key=tok',
      );
      expect(catalog.posters, hasLength(1));
    });

    test('无 Primary 图 → 图片空、posters 空', () {
      final catalog = mapEmbyView(
        <String, Object?>{
          'Id': 'lib-2',
          'Name': '剧集',
          'Type': 'CollectionFolder',
        },
        serverUrl: serverUrl,
        token: token,
      );
      expect(catalog.type, 'CollectionFolder');
      expect(catalog.primaryImage.isEmpty, isTrue);
      expect(catalog.posters, isEmpty);
    });
  });

  group('mapEmbyItemCard', () {
    test('影片 → MediaItemCard（ticks→秒、Played、评分、图片）', () {
      final card = mapEmbyItemCard(
        <String, Object?>{
          'Id': 'item-1',
          'Name': '影片甲',
          'Type': 'Movie',
          'RunTimeTicks': 72000000000, // 7200 秒
          'CommunityRating': 8.6,
          'PremiereDate': '2020-01-01T00:00:00.0000000Z',
          'ImageTags': <String, Object?>{'Primary': 'p1'},
          'BackdropImageTags': <Object?>['b1'],
          'UserData': <String, Object?>{'Played': true},
        },
        serverUrl: serverUrl,
        token: token,
      );
      expect(card.id, 'item-1');
      expect(card.title, '影片甲');
      expect(card.type, 'Movie');
      expect(card.durationSeconds, 7200);
      expect(card.watched, isTrue);
      expect(card.rating, '8.6');
      expect(card.releaseDate, '2020-01-01T00:00:00.0000000Z');
      expect(
        card.primaryImage.url,
        'https://emby.example.test/Items/item-1/Images/Primary?tag=p1&api_key=tok',
      );
      expect(
        card.backdropImage.url,
        'https://emby.example.test/Items/item-1/Images/Backdrop?tag=b1&api_key=tok',
      );
    });

    test('剧集单集：SeriesName→副标题，季/集编号', () {
      final card = mapEmbyItemCard(
        <String, Object?>{
          'Id': 'ep-1',
          'Name': '第三集',
          'Type': 'Episode',
          'SeriesName': '剧集名',
          'ParentIndexNumber': 1,
          'IndexNumber': 3,
        },
        serverUrl: serverUrl,
        token: token,
      );
      expect(card.secondaryTitle, '剧集名');
      expect(card.displayTitle, '剧集名');
      expect(card.seasonNumber, 1);
      expect(card.episodeNumber, 3);
      expect(card.watched, isFalse);
      expect(card.durationSeconds, 0);
      expect(card.primaryImage.isEmpty, isTrue);
    });
  });
}
