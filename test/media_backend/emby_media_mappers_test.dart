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

  group('mapEmbyItemDetail', () {
    test('影片详情：标题/简介/题材/时长/评分/外部 ID/图片/演职员', () {
      final detail = mapEmbyItemDetail(
        <String, Object?>{
          'Id': 'm-1',
          'Name': '银翼杀手 2049',
          'Type': 'Movie',
          'Overview': '简介文本',
          'RunTimeTicks': 9840000000000, // 984000 秒 = 16400 分
          'CommunityRating': 8.0,
          'PremiereDate': '2017-10-06T00:00:00.0000000Z',
          'Genres': <Object?>['科幻', '剧情'],
          'ProductionLocations': <Object?>['美国'],
          'ImageTags': <String, Object?>{'Primary': 'p1', 'Logo': 'lg1'},
          'BackdropImageTags': <Object?>['b1'],
          'ProviderIds': <String, Object?>{
            'Tmdb': '335984',
            'Imdb': 'tt1856101',
          },
          'UserData': <String, Object?>{
            'Played': true,
            'IsFavorite': true,
            'PlaybackPositionTicks': 6000000000, // 600 秒
          },
          'People': <Object?>[
            <String, Object?>{
              'Id': 'pp-1',
              'Name': 'Ryan Gosling',
              'Role': 'K',
              'Type': 'Actor',
              'PrimaryImageTag': 'av1',
            },
            <String, Object?>{
              'Id': 'pp-2',
              'Name': 'Denis Villeneuve',
              'Type': 'Director',
            },
            <String, Object?>{'Id': 'pp-3', 'Name': '', 'Type': 'Actor'},
          ],
        },
        serverUrl: serverUrl,
        token: token,
      );

      expect(detail.id, 'm-1');
      expect(detail.type, 'Movie');
      expect(detail.title, '银翼杀手 2049');
      expect(detail.overview, '简介文本');
      expect(detail.genreLabels, <String>['科幻', '剧情']);
      expect(detail.regionLabels, <String>['美国']);
      expect(detail.durationSeconds, 984000);
      expect(detail.runtimeMinutes, 16400);
      expect(detail.rating, '8.0');
      expect(detail.releaseDate, '2017-10-06T00:00:00.0000000Z');
      expect(detail.externalIds.tmdbId, '335984');
      expect(detail.externalIds.imdbId, 'tt1856101');
      expect(detail.watched, isTrue);
      expect(detail.favorite, isTrue);
      expect(detail.resumePositionSeconds, 600);
      expect(
        detail.primaryImage.url,
        'https://emby.example.test/Items/m-1/Images/Primary?tag=p1&api_key=tok',
      );
      expect(
        detail.logoImage.url,
        'https://emby.example.test/Items/m-1/Images/Logo?tag=lg1&api_key=tok',
      );
      expect(
        detail.backdropImage.url,
        'https://emby.example.test/Items/m-1/Images/Backdrop?tag=b1&api_key=tok',
      );
      // 无名演职员被剔除；其余保留顺序、department=Type。
      expect(detail.people, hasLength(2));
      expect(detail.people[0].name, 'Ryan Gosling');
      expect(detail.people[0].role, 'K');
      expect(detail.people[0].department, 'Actor');
      expect(
        detail.people[0].avatar.url,
        'https://emby.example.test/Items/pp-1/Images/Primary?tag=av1&api_key=tok',
      );
      expect(detail.people[1].name, 'Denis Villeneuve');
      expect(detail.people[1].department, 'Director');
      expect(detail.people[1].avatar.isEmpty, isTrue);
    });

    test('缺图缺人缺外部 ID：空态降级不报错，年份回退 ProductionYear', () {
      final detail = mapEmbyItemDetail(
        <String, Object?>{
          'Id': 'm-2',
          'Name': '某电影',
          'Type': 'Movie',
          'ProductionYear': 1999,
        },
        serverUrl: serverUrl,
        token: token,
      );
      expect(detail.releaseDate, '1999');
      expect(detail.primaryImage.isEmpty, isTrue);
      expect(detail.logoImage.isEmpty, isTrue);
      expect(detail.genreLabels, isEmpty);
      expect(detail.people, isEmpty);
      expect(detail.externalIds.tmdbId, isEmpty);
      expect(detail.externalIds.imdbId, isEmpty);
      expect(detail.watched, isFalse);
    });
  });
}
