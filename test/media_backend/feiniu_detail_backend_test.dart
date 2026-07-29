import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/api/feiniu_api.dart';
import 'package:fly_player/api/person_list_request.dart';
import 'package:fly_player/media_backend/feiniu/feiniu_detail_mappers.dart';
import 'package:fly_player/media_backend/feiniu/feiniu_media_backend.dart';
import 'package:fly_player/models/media_library_item.dart';
import 'package:fly_player/models/person_credit.dart';
import 'package:fly_player/models/play_info.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 覆写详情编排所需的方法，使 [FeiniuMediaBackend] 的转发逻辑可在无网络下测试。
class _FakeFeiniuApi extends FeiniuApi {
  _FakeFeiniuApi(
    super.nas, {
    this.failDictionaries = false,
    this.failingPlayInfoIds = const <String>{},
    this.rawDetails = const <String, Map<String, dynamic>>{},
  });

  final bool failDictionaries;
  final Set<String> failingPlayInfoIds;
  final Map<String, Map<String, dynamic>> rawDetails;
  int personListCalls = 0;

  @override
  Future<PlayInfoData> getPlayInfo(String itemGuid) async {
    if (failingPlayInfoIds.contains(itemGuid)) {
      throw Exception('play info unavailable: $itemGuid');
    }
    return PlayInfoData.fromJson(<String, dynamic>{
      'grand_guid': 'g',
      'type': 'Movie',
      'ts': 0,
      'media_guid': 'm',
      'video_guid': 'v',
      'audio_guid': 'a',
      'subtitle_guid': 's',
      'parent_guid': 'p',
      'item': <String, dynamic>{
        'guid': itemGuid,
        'trim_id': 'tmdb-1',
        'type': 'Movie',
        'title': '电影',
        'genres': <int>[28],
        'production_countries': <String>['US'],
        'is_watched': 1,
        'is_favorite': 0,
      },
    });
  }

  @override
  Future<Map<String, dynamic>> getItemDetail(String itemGuid) async {
    return rawDetails[itemGuid] ?? <String, dynamic>{'imdb_id': 'tt999'};
  }

  @override
  Future<List<PersonCredit>> getPersonList(
    String itemGuid, {
    PersonListRequest request = const PersonListRequest(),
  }) async {
    personListCalls++;
    return <PersonCredit>[
      const PersonCredit(
        itemGuid: 'i',
        personGuid: 'p-1',
        role: '主角',
        job: '',
        order: 0,
        name: '演员甲',
        originalName: 'A',
        profilePath: '/a.jpg',
      ),
    ];
  }

  @override
  Future<Map<int, String>> getTagGenresMap({String lan = 'zh-CN'}) async {
    if (failDictionaries) throw Exception('genres boom');
    return const <int, String>{28: '动作'};
  }

  @override
  Future<Map<String, String>> getTagIso3166Map({String lan = 'zh-CN'}) async {
    if (failDictionaries) throw Exception('region boom');
    return const <String, String>{'US': '美国'};
  }

  @override
  Future<List<MediaLibraryItem>> getSeasonList(String itemGuid) async {
    return <MediaLibraryItem>[_libraryItem(guid: 's-1', seasonNumber: 1)];
  }

  @override
  Future<List<MediaLibraryItem>> getEpisodeList(String seasonGuid) async {
    return <MediaLibraryItem>[
      _libraryItem(guid: 'e-1', seasonNumber: 1, episodeNumber: 3),
    ];
  }
}

MediaLibraryItem _libraryItem({
  required String guid,
  int seasonNumber = 0,
  int episodeNumber = 0,
}) {
  return MediaLibraryItem(
    guid: guid,
    title: '条目',
    tvTitle: '',
    type: 'Season',
    poster: '/p.jpg',
    releaseDate: '',
    firstAirDate: '',
    lastAirDate: '',
    voteAverage: '',
    overview: '',
    watched: 0,
    watchedTs: 0,
    ts: 0,
    duration: 0,
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
    numberOfSeasons: 0,
    numberOfEpisodes: 0,
    localNumberOfSeasons: 0,
    localNumberOfEpisodes: 0,
    parentGuid: '',
    parentTitle: '',
    ancestorGuid: '',
    ancestorName: '',
    path: '',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  group('extractFeiniuImdbId', () {
    test('顶层 imdb_id 优先', () {
      expect(
        extractFeiniuImdbId(<String, dynamic>{'imdb_id': 'tt100'}),
        'tt100',
      );
    });

    test('顶层缺失时回退 item.imdb_id', () {
      expect(
        extractFeiniuImdbId(<String, dynamic>{
          'imdb_id': '',
          'item': <String, dynamic>{'imdb_id': 'tt200'},
        }),
        'tt200',
      );
    });

    test('两处皆空返回空串', () {
      expect(extractFeiniuImdbId(<String, dynamic>{}), '');
      expect(
        extractFeiniuImdbId(<String, dynamic>{
          'item': <String, dynamic>{'imdb_id': '  '},
        }),
        '',
      );
    });
  });

  group('FeiniuMediaBackend 详情编排', () {
    test('getItemDetail 装配 playInfo + imdb + credits + 字典', () async {
      final nas = NasProvider();
      addTearDown(nas.dispose);
      final api = _FakeFeiniuApi(nas);
      final backend = FeiniuMediaBackend(api);

      final detail = await backend.getItemDetail('item-1');

      expect(detail.id, 'item-1');
      expect(detail.externalIds.tmdbId, 'tmdb-1');
      expect(detail.externalIds.imdbId, 'tt999');
      expect(detail.genreLabels, <String>['动作']);
      expect(detail.regionLabels, <String>['美国']);
      expect(detail.watched, isTrue);
      expect(detail.people.single.name, '演员甲');
      expect(api.personListCalls, 1);
    });

    test('字典失败时 best-effort：详情仍可读，题材/地区回退原值', () async {
      final nas = NasProvider();
      addTearDown(nas.dispose);
      final api = _FakeFeiniuApi(nas, failDictionaries: true);
      final backend = FeiniuMediaBackend(api);

      final detail = await backend.getItemDetail('item-1');

      // 没有抛异常；题材/地区字典缺失，回退原始 id / code。
      expect(detail.id, 'item-1');
      expect(detail.genreLabels, <String>['28']);
      expect(detail.regionLabels, <String>['US']);
    });

    test('剧集播放信息不可用时仍从原始 item 详情映射自身素材', () async {
      final nas = NasProvider();
      addTearDown(nas.dispose);
      final api = _FakeFeiniuApi(
        nas,
        failingPlayInfoIds: <String>{'series-1'},
        rawDetails: <String, Map<String, dynamic>>{
          'series-1': <String, dynamic>{
            'grand_guid': 'series-1',
            'item': <String, dynamic>{
              'guid': 'series-1',
              'type': 'TV',
              'title': '葬送的芙莉莲',
              'posters': '/series-poster.jpg',
              'backdrops': '/series-backdrop.jpg',
              'logos': '/series-logo.png',
              'genres': <int>[],
              'production_countries': <String>[],
            },
          },
        },
      );
      final backend = FeiniuMediaBackend(api);

      final detail = await backend.getItemDetail('series-1');

      expect(detail.id, 'series-1');
      expect(detail.seriesId, 'series-1');
      expect(detail.primaryImage.url, '/series-poster.jpg');
      expect(detail.backdropImage.url, '/series-backdrop.jpg');
      expect(detail.logoImage.url, '/series-logo.png');
    });

    test('getItemSeasons / getSeasonEpisodes 转发并映射', () async {
      final nas = NasProvider();
      addTearDown(nas.dispose);
      final backend = FeiniuMediaBackend(_FakeFeiniuApi(nas));

      final seasons = await backend.getItemSeasons('series-1');
      expect(seasons.single.id, 's-1');
      expect(seasons.single.seasonNumber, 1);

      final episodes = await backend.getSeasonEpisodes('season-1');
      expect(episodes.single.id, 'e-1');
      expect(episodes.single.episodeNumber, 3);
    });
  });
}
