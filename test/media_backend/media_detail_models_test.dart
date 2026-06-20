import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/detail/media_detail.dart';
import 'package:fly_player/media_backend/detail/media_episode_summary.dart';
import 'package:fly_player/media_backend/detail/media_season_summary.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';

void main() {
  group('MediaDetail', () {
    const detail = MediaDetail(
      id: 'item-1',
      type: 'TV',
      title: '正片标题',
      secondaryTitle: '剧集副标题',
      primaryImage: MediaImageRef(url: 'https://server/poster.jpg'),
      backdropImage: MediaImageRef(url: 'https://server/backdrop.jpg'),
      overview: '简介',
      rating: '8.6',
      releaseDate: '2020-01-01',
      runtimeMinutes: 45,
      durationSeconds: 2700,
      seasonNumber: 1,
      episodeNumber: 3,
      genreLabels: <String>['动作', '冒险'],
      regionLabels: <String>['美国'],
      resolutions: <String>['4K'],
      watched: true,
      favorite: true,
      resumePositionSeconds: 600,
      externalIds: MediaExternalIds(tmdbId: 'tt-trim', imdbId: 'tt123'),
      cast: <MediaDetailPerson>[
        MediaDetailPerson(
          id: 'p-1',
          name: '演员甲',
          role: '主角',
          department: 'cast',
          avatar: MediaImageRef(url: 'https://server/p1.jpg'),
        ),
      ],
    );

    test('displayTitle 优先副标题，回退主标题', () {
      expect(detail.displayTitle, '剧集副标题');

      const noSecondary = MediaDetail(
        id: 'm',
        type: 'Movie',
        title: '电影标题',
        primaryImage: MediaImageRef.empty,
      );
      expect(noSecondary.displayTitle, '电影标题');

      const blank = MediaDetail(
        id: 'm',
        type: 'Movie',
        title: '',
        primaryImage: MediaImageRef.empty,
      );
      expect(blank.displayTitle, 'Unknown');
    });

    test('展示字段与外部 ID、演职员保留', () {
      expect(detail.primaryImage.url, 'https://server/poster.jpg');
      expect(detail.backdropImage.url, 'https://server/backdrop.jpg');
      expect(detail.rating, '8.6');
      expect(detail.genreLabels, <String>['动作', '冒险']);
      expect(detail.regionLabels, <String>['美国']);
      expect(detail.watched, isTrue);
      expect(detail.favorite, isTrue);
      expect(detail.resumePositionSeconds, 600);
      expect(detail.externalIds.tmdbId, 'tt-trim');
      expect(detail.externalIds.imdbId, 'tt123');
      expect(detail.cast.single.name, '演员甲');
      expect(detail.cast.single.department, 'cast');
    });

    test('可选字段缺省为空 / 0 / false', () {
      const minimal = MediaDetail(
        id: 'm',
        type: 'Movie',
        title: '电影',
        primaryImage: MediaImageRef.empty,
      );
      expect(minimal.secondaryTitle, '');
      expect(minimal.overview, '');
      expect(minimal.runtimeMinutes, 0);
      expect(minimal.seasonNumber, 0);
      expect(minimal.genreLabels, isEmpty);
      expect(minimal.regionLabels, isEmpty);
      expect(minimal.resolutions, isEmpty);
      expect(minimal.watched, isFalse);
      expect(minimal.favorite, isFalse);
      expect(minimal.resumePositionSeconds, 0);
      expect(minimal.externalIds.tmdbId, '');
      expect(minimal.externalIds.imdbId, '');
      expect(minimal.cast, isEmpty);
      expect(minimal.crew, isEmpty);
    });

    test('copyWith 仅改目标字段', () {
      final updated = detail.copyWith(watched: false, favorite: false);
      expect(updated.watched, isFalse);
      expect(updated.favorite, isFalse);
      // 其它字段保持。
      expect(updated.id, 'item-1');
      expect(updated.displayTitle, '剧集副标题');
      expect(updated.cast.single.name, '演员甲');
      expect(updated.externalIds.imdbId, 'tt123');
    });
  });

  test('MediaSeasonSummary 基础字段', () {
    const season = MediaSeasonSummary(
      id: 's-1',
      title: '第 1 季',
      seasonNumber: 1,
      numberOfEpisodes: 12,
      localNumberOfEpisodes: 8,
      primaryImage: MediaImageRef(url: 'https://server/s1.jpg'),
    );
    expect(season.id, 's-1');
    expect(season.seasonNumber, 1);
    expect(season.numberOfEpisodes, 12);
    expect(season.localNumberOfEpisodes, 8);
    expect(season.primaryImage.url, 'https://server/s1.jpg');
  });

  test('MediaEpisodeSummary 基础字段与缺省', () {
    const episode = MediaEpisodeSummary(
      id: 'e-1',
      title: '第 3 集',
      seasonNumber: 1,
      episodeNumber: 3,
      overview: '本集简介',
      airDate: '2020-01-15',
      durationSeconds: 2700,
      watched: true,
      resumePositionSeconds: 120,
      primaryImage: MediaImageRef(url: 'https://server/still.jpg'),
    );
    expect(episode.episodeNumber, 3);
    expect(episode.overview, '本集简介');
    expect(episode.watched, isTrue);
    expect(episode.resumePositionSeconds, 120);

    const minimal = MediaEpisodeSummary(
      id: 'e',
      title: '集',
      seasonNumber: 0,
      episodeNumber: 0,
      primaryImage: MediaImageRef.empty,
    );
    expect(minimal.overview, '');
    expect(minimal.airDate, '');
    expect(minimal.durationSeconds, 0);
    expect(minimal.watched, isFalse);
    expect(minimal.resumePositionSeconds, 0);
  });
}
