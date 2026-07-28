import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/detail/media_detail.dart';
import 'package:fly_player/media_backend/detail/media_season_summary.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/media_backend/media_item_card.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_display_builder.dart';

void main() {
  const builder = PosterBrowseDisplayBuilder();

  MediaImageRef image(String url, {Map<String, String> headers = const {}}) {
    return MediaImageRef(url: url, headers: headers);
  }

  MediaItemCard card({
    String id = 'item-1',
    String title = '卡片标题',
    String secondaryTitle = '',
    String type = 'Movie',
    String seriesId = '',
    MediaImageRef primaryImage = const MediaImageRef(url: 'card-primary'),
    MediaImageRef backdropImage = const MediaImageRef(url: 'card-backdrop'),
    String rating = '',
    String releaseDate = '',
    int seasonNumber = 0,
    int episodeNumber = 0,
    int numberOfSeasons = 0,
    int numberOfEpisodes = 0,
    int localNumberOfSeasons = 0,
    int localNumberOfEpisodes = 0,
    int durationSeconds = 0,
    int posterWidth = 0,
    int posterHeight = 0,
    List<String> genres = const <String>[],
    List<String> resolutions = const <String>[],
  }) {
    return MediaItemCard(
      id: id,
      title: title,
      secondaryTitle: secondaryTitle,
      type: type,
      seriesId: seriesId,
      primaryImage: primaryImage,
      backdropImage: backdropImage,
      rating: rating,
      releaseDate: releaseDate,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      numberOfSeasons: numberOfSeasons,
      numberOfEpisodes: numberOfEpisodes,
      localNumberOfSeasons: localNumberOfSeasons,
      localNumberOfEpisodes: localNumberOfEpisodes,
      durationSeconds: durationSeconds,
      posterWidth: posterWidth,
      posterHeight: posterHeight,
      resolutions: resolutions,
    );
  }

  MediaDetail detail({
    String id = 'detail-1',
    String title = '详情标题',
    String secondaryTitle = '',
    String type = 'Movie',
    MediaImageRef primaryImage = const MediaImageRef(url: 'detail-primary'),
    MediaImageRef backdropImage = const MediaImageRef(url: 'detail-backdrop'),
    MediaImageRef logoImage = const MediaImageRef(url: 'detail-logo'),
    String rating = '',
    String releaseDate = '',
    String airDate = '',
    String overview = '',
    int durationSeconds = 0,
    int numberOfSeasons = 0,
    int numberOfEpisodes = 0,
    List<String> genreLabels = const <String>[],
    List<String> resolutions = const <String>[],
  }) {
    return MediaDetail(
      id: id,
      title: title,
      secondaryTitle: secondaryTitle,
      type: type,
      primaryImage: primaryImage,
      backdropImage: backdropImage,
      logoImage: logoImage,
      rating: rating,
      releaseDate: releaseDate,
      airDate: airDate,
      overview: overview,
      durationSeconds: durationSeconds,
      numberOfSeasons: numberOfSeasons,
      numberOfEpisodes: numberOfEpisodes,
      genreLabels: genreLabels,
      resolutions: resolutions,
    );
  }

  MediaSeasonSummary season({
    String id = 'season-1',
    String title = '第 1 季',
    int seasonNumber = 1,
    MediaImageRef primaryImage = const MediaImageRef(url: 'season-primary'),
  }) {
    return MediaSeasonSummary(
      id: id,
      title: title,
      seasonNumber: seasonNumber,
      primaryImage: primaryImage,
    );
  }

  test('单集使用剧集标题并按规则组织标题、评分、目标和图片候选', () {
    final result = builder.build(
      card: card(
        id: 'episode-7',
        title: '第七集',
        secondaryTitle: '卡片剧名',
        type: 'Episode',
        seriesId: 'series-42',
        primaryImage: image('card-primary-landscape'),
        backdropImage: image('card-backdrop'),
        rating: '8.0',
        seasonNumber: 1,
        episodeNumber: 7,
        posterWidth: 1920,
        posterHeight: 1080,
      ),
      itemDetail: detail(
        type: 'Episode',
        rating: '9.123',
        backdropImage: image('item-backdrop'),
        logoImage: image('item-logo'),
      ),
      seriesDetail: detail(
        id: 'series-42',
        type: 'TV',
        title: '剧集详情标题',
        primaryImage: image('series-primary'),
        backdropImage: image('series-backdrop'),
        logoImage: image('series-logo'),
      ),
      season: season(primaryImage: image('season-primary')),
    );

    expect(result.isEpisode, isTrue);
    expect(result.type, 'Episode');
    expect(result.title, '剧集详情标题');
    expect(result.episodeTitle, '第七集');
    expect(result.seasonNumber, 1);
    expect(result.episodeNumber, 7);
    expect(result.ratingText, '9.1');
    expect(result.detailTargetId, 'series-42');
    expect(result.logoImages.map((image) => image.url), [
      'item-logo',
      'series-logo',
    ]);
    expect(result.posterImages.map((image) => image.url), [
      'season-primary',
      'series-primary',
      'card-primary-landscape',
    ]);
    expect(result.backgroundImages.map((image) => image.url), [
      'card-backdrop',
      'item-backdrop',
      'series-backdrop',
      'card-primary-landscape',
      'season-primary',
      'series-primary',
    ]);
  });

  test('formatRating 格式化合法数字并隐藏非法或非有限值', () {
    expect(builder.formatRating('9.0'), '9');
    expect(builder.formatRating('8'), '8');
    expect(builder.formatRating('bad'), '');
    expect(builder.formatRating(''), '');
    expect(builder.formatRating('NaN'), '');
    expect(builder.formatRating('Infinity'), '');
  });

  test('电影优先使用 itemDetail 展示字段且详情目标是自身', () {
    final result = builder.build(
      card: card(
        id: 'movie-card',
        title: '卡片电影',
        secondaryTitle: '卡片展示名',
        type: 'Movie',
        rating: '7.1',
        releaseDate: '2020-01-02',
        durationSeconds: 100,
        genres: const <String>['卡片题材'],
        resolutions: const <String>['720p'],
      ),
      itemDetail: detail(
        id: 'movie-detail',
        title: '详情电影标题',
        secondaryTitle: '详情展示名',
        type: 'Movie',
        rating: '8.25',
        releaseDate: ' 2024-03-04 ',
        overview: '详情简介',
        durationSeconds: 7200,
        genreLabels: const <String>['剧情', '科幻'],
        resolutions: const <String>['4K', 'HDR'],
      ),
    );

    expect(result.isEpisode, isFalse);
    expect(result.title, '详情展示名');
    expect(result.episodeTitle, isEmpty);
    expect(result.ratingText, '8.3');
    expect(result.releaseYear, '2024');
    expect(result.overview, '详情简介');
    expect(result.durationSeconds, 7200);
    expect(result.genres, ['剧情', '科幻']);
    expect(result.resolutions, ['4K', 'HDR']);
    expect(result.detailTargetId, 'movie-card');
  });

  test('计数按 detail、大于零的本地计数、服务端计数优先级补全', () {
    final detailCount = builder.build(
      card: card(numberOfSeasons: 1, numberOfEpisodes: 10),
      itemDetail: detail(numberOfSeasons: 3, numberOfEpisodes: 30),
    );
    final localCount = builder.build(
      card: card(
        numberOfSeasons: 1,
        numberOfEpisodes: 10,
        localNumberOfSeasons: 2,
        localNumberOfEpisodes: 20,
      ),
    );
    final serverCount = builder.build(
      card: card(numberOfSeasons: 1, numberOfEpisodes: 10),
    );

    expect(detailCount.numberOfSeasons, 3);
    expect(detailCount.numberOfEpisodes, 30);
    expect(localCount.numberOfSeasons, 2);
    expect(localCount.numberOfEpisodes, 20);
    expect(serverCount.numberOfSeasons, 1);
    expect(serverCount.numberOfEpisodes, 10);
  });

  test('图片去重保留首个相同鉴权候选并区分 headers 与自鉴权语义', () {
    final result = builder.build(
      card: card(
        primaryImage: image('same'),
        backdropImage: image(
          'same',
          headers: const {'Authorization': 'Bearer a'},
        ),
        posterWidth: 100,
        posterHeight: 150,
      ),
      itemDetail: detail(
        backdropImage: image(
          'same',
          headers: const {'Authorization': 'Bearer b'},
        ),
      ),
      seriesDetail: detail(
        primaryImage: image('same?api_key=token'),
        backdropImage: image(
          'same',
          headers: const {'Authorization': 'Bearer a'},
        ),
      ),
      season: season(primaryImage: image('same')),
    );

    expect(result.backgroundImages.map((image) => image.url), [
      'same',
      'same',
      'same',
      'same?api_key=token',
    ]);
    expect(result.backgroundImages[0].headers, {'Authorization': 'Bearer a'});
    expect(result.backgroundImages[1].headers, {'Authorization': 'Bearer b'});
    expect(result.backgroundImages[2].headers, isEmpty);
    expect(result.backgroundImages[3].headers, isEmpty);
  });
}
