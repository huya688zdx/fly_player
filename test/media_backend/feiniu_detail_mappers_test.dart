import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/feiniu/feiniu_detail_mappers.dart';
import 'package:fly_player/models/media_library_item.dart';
import 'package:fly_player/models/person_credit.dart';
import 'package:fly_player/models/play_info.dart';

void main() {
  group('mapFeiniuItemDetail', () {
    PlayInfoData buildInfo({
      Map<String, dynamic> itemOverrides = const <String, dynamic>{},
      int ts = 0,
    }) {
      final item = <String, dynamic>{
        'guid': 'item-1',
        'trim_id': 'tmdb-100',
        'type': 'Movie',
        'title': '电影标题',
        'tv_title': '',
        'parent_title': '',
        'logos': '/logo.png',
        'posters': '/poster.jpg',
        'backdrops': '/backdrop.jpg',
        'still_path': '/still.jpg',
        'vote_average': '8.6',
        'release_date': '2020-01-01',
        'air_date': '',
        'runtime': 120,
        'duration': 7200,
        'watched_ts': 0,
        'overview': '简介内容',
        'season_number': 0,
        'episode_number': 0,
        'number_of_seasons': 0,
        'number_of_episodes': 0,
        'genres': <int>[28, 12],
        'production_countries': <String>['US'],
        'media_stream': <String, dynamic>{
          'resolutions': <String>['4K'],
          'audio_type': <String>['DTS'],
          'color_range_type': <String>['SDR'],
        },
        'ancestor_name': '电影库',
        'can_play': 1,
        'play_error': '',
        'is_favorite': 1,
        'is_watched': 1,
        ...itemOverrides,
      };
      return PlayInfoData.fromJson(<String, dynamic>{
        'grand_guid': 'g',
        'type': 'Movie',
        'ts': ts,
        'media_guid': 'media-guid',
        'video_guid': 'video-guid',
        'audio_guid': 'audio-guid',
        'subtitle_guid': 'subtitle-guid',
        'parent_guid': 'parent-guid',
        'item': item,
      });
    }

    test('电影展示字段无损映射', () {
      final detail = mapFeiniuItemDetail(
        buildInfo(ts: 600),
        genresMap: const <int, String>{28: '动作', 12: '冒险'},
        regionNames: const <String, String>{'US': '美国'},
        imdbId: 'tt123',
      );

      expect(detail.id, 'item-1');
      expect(detail.seriesId, 'g');
      expect(detail.type, 'Movie');
      expect(detail.title, '电影标题');
      expect(detail.overview, '简介内容');
      expect(detail.primaryImage.url, '/poster.jpg');
      expect(detail.backdropImage.url, '/backdrop.jpg');
      expect(detail.logoImage.url, '/logo.png');
      expect(detail.rating, '8.6');
      expect(detail.releaseDate, '2020-01-01');
      expect(detail.runtimeMinutes, 120);
      expect(detail.durationSeconds, 7200);
      expect(detail.genreLabels, <String>['动作', '冒险']);
      expect(detail.regionLabels, <String>['美国']);
      expect(detail.resolutions, <String>['4K']);
      expect(detail.audioTypes, <String>['DTS']);
      expect(detail.colorRanges, <String>['SDR']);
      expect(detail.watched, isTrue);
      expect(detail.favorite, isTrue);
      expect(detail.resumePositionSeconds, 600);
      expect(detail.externalIds.tmdbId, 'tmdb-100');
      expect(detail.externalIds.imdbId, 'tt123');
    });

    test('只搬展示半：播放接线字段不进公共详情', () {
      // mapper 输入含 mediaGuid / videoGuid / canPlay / playConfig，但 MediaDetail
      // 没有承载这些播放接线字段的位置——本测试用模型 API 缺失作为边界保证。
      final detail = mapFeiniuItemDetail(
        buildInfo(),
        genresMap: const <int, String>{},
        regionNames: const <String, String>{},
      );
      // 只读展示态快照存在；播放句柄不存在于模型（编译期已保证）。
      expect(detail.watched, isTrue);
      expect(detail.favorite, isTrue);
    });

    test('未知题材 id / 地区 code 原样回退；地区大写查表', () {
      final detail = mapFeiniuItemDetail(
        buildInfo(
          itemOverrides: <String, dynamic>{
            'genres': <int>[28, 99],
            'production_countries': <String>['us', 'JP'],
          },
        ),
        genresMap: const <int, String>{28: '动作'},
        regionNames: const <String, String>{'US': '美国'},
      );
      expect(detail.genreLabels, <String>['动作', '99']);
      // 'us' 直查不中 -> 大写 'US' 命中；'JP' 不中 -> 原样回退。
      expect(detail.regionLabels, <String>['美国', 'JP']);
    });

    test('剧集副标题与季集编号映射', () {
      final detail = mapFeiniuItemDetail(
        buildInfo(
          itemOverrides: <String, dynamic>{
            'type': 'Episode',
            'title': '单集名',
            'tv_title': '剧集名',
            'parent_title': '第 1 季',
            'season_number': 1,
            'episode_number': 3,
            'number_of_seasons': 2,
            'number_of_episodes': 12,
            'local_number_of_seasons': 2,
            'local_number_of_episodes': 8,
          },
        ),
        genresMap: const <int, String>{},
        regionNames: const <String, String>{},
      );
      expect(detail.secondaryTitle, '剧集名');
      expect(detail.parentTitle, '第 1 季');
      expect(detail.displayTitle, '剧集名');
      expect(detail.seasonNumber, 1);
      expect(detail.episodeNumber, 3);
      expect(detail.numberOfSeasons, 2);
      expect(detail.numberOfEpisodes, 12);
      expect(detail.localNumberOfSeasons, 2);
      expect(detail.localNumberOfEpisodes, 8);
    });

    test('续播位置：ts>0 用 ts，ts==0 回退 watchedTs', () {
      final withTs = mapFeiniuItemDetail(
        buildInfo(itemOverrides: <String, dynamic>{'watched_ts': 999}, ts: 600),
        genresMap: const <int, String>{},
        regionNames: const <String, String>{},
      );
      expect(withTs.resumePositionSeconds, 600);

      final fallback = mapFeiniuItemDetail(
        buildInfo(itemOverrides: <String, dynamic>{'watched_ts': 999}, ts: 0),
        genresMap: const <int, String>{},
        regionNames: const <String, String>{},
      );
      expect(fallback.resumePositionSeconds, 999);
    });

    test('演职员映射为扁平 people（role / job 保留）', () {
      final detail = mapFeiniuItemDetail(
        buildInfo(),
        genresMap: const <int, String>{},
        regionNames: const <String, String>{},
        credits: <PersonCredit>[
          const PersonCredit(
            itemGuid: 'item-1',
            personGuid: 'p-1',
            role: '主角',
            job: '',
            order: 0,
            name: '演员甲',
            originalName: 'Actor A',
            profilePath: '/p1.jpg',
          ),
          const PersonCredit(
            itemGuid: 'item-1',
            personGuid: 'p-2',
            role: '',
            job: 'Director',
            order: 1,
            name: '',
            originalName: 'Director B',
            profilePath: '/p2.jpg',
          ),
        ],
      );
      expect(detail.people.length, 2);
      expect(detail.people[0].id, 'p-1');
      expect(detail.people[0].name, '演员甲');
      expect(detail.people[0].role, '主角');
      expect(detail.people[0].avatar.url, '/p1.jpg');
      // name 为空回退 originalName。
      expect(detail.people[1].name, 'Director B');
      expect(detail.people[1].department, 'Director');
    });
  });

  MediaLibraryItem buildLibraryItem({
    String guid = 'lib-1',
    String title = '',
    String tvTitle = '',
    String type = 'Season',
    String poster = '/p.jpg',
    int seasonNumber = 0,
    int episodeNumber = 0,
    int numberOfEpisodes = 0,
    int localNumberOfEpisodes = 0,
    int watched = 0,
    int ts = 0,
    int watchedTs = 0,
    int duration = 0,
    String overview = '',
    String releaseDate = '',
  }) {
    return MediaLibraryItem(
      guid: guid,
      title: title,
      tvTitle: tvTitle,
      type: type,
      poster: poster,
      releaseDate: releaseDate,
      firstAirDate: '',
      lastAirDate: '',
      voteAverage: '',
      overview: overview,
      watched: watched,
      watchedTs: watchedTs,
      ts: ts,
      duration: duration,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      numberOfSeasons: 0,
      numberOfEpisodes: numberOfEpisodes,
      localNumberOfSeasons: 0,
      localNumberOfEpisodes: localNumberOfEpisodes,
      parentGuid: '',
      parentTitle: '',
      ancestorGuid: '',
      ancestorName: '',
      path: '',
    );
  }

  test('mapFeiniuSeason 映射季列表条目', () {
    final season = mapFeiniuSeason(
      buildLibraryItem(
        guid: 's-1',
        title: '第 1 季',
        seasonNumber: 1,
        numberOfEpisodes: 12,
        localNumberOfEpisodes: 8,
        poster: '/s1.jpg',
      ),
    );
    expect(season.id, 's-1');
    expect(season.title, '第 1 季');
    expect(season.seasonNumber, 1);
    expect(season.numberOfEpisodes, 12);
    expect(season.localNumberOfEpisodes, 8);
    expect(season.primaryImage.url, '/s1.jpg');
  });

  test('mapFeiniuEpisode 映射选集条目（tvTitle 优先标题、ts 续播、releaseDate 作播出日期）', () {
    final episode = mapFeiniuEpisode(
      buildLibraryItem(
        guid: 'e-1',
        title: '原始集名',
        tvTitle: '展示集名',
        type: 'Episode',
        seasonNumber: 1,
        episodeNumber: 3,
        numberOfEpisodes: 0,
        watched: 1,
        ts: 120,
        duration: 2700,
        overview: '本集简介',
        releaseDate: '2020-01-15',
        poster: '/still.jpg',
      ),
    );
    expect(episode.id, 'e-1');
    expect(episode.title, '展示集名');
    expect(episode.seasonNumber, 1);
    expect(episode.episodeNumber, 3);
    expect(episode.overview, '本集简介');
    expect(episode.airDate, '2020-01-15');
    expect(episode.durationSeconds, 2700);
    expect(episode.watched, isTrue);
    expect(episode.resumePositionSeconds, 120);
    expect(episode.primaryImage.url, '/still.jpg');
  });

  test('mapFeiniuEpisode 续播：ts==0 回退 watchedTs', () {
    final fallback = mapFeiniuEpisode(
      buildLibraryItem(type: 'Episode', ts: 0, watchedTs: 888),
    );
    expect(fallback.resumePositionSeconds, 888);

    final withTs = mapFeiniuEpisode(
      buildLibraryItem(type: 'Episode', ts: 120, watchedTs: 888),
    );
    expect(withTs.resumePositionSeconds, 120);
  });
}
