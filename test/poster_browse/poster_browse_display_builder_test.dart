import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/detail/media_detail.dart';
import 'package:fly_player/media_backend/detail/media_season_summary.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/media_backend/media_item_card.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_display_builder.dart';

void main() {
  const builder = PosterBrowseDisplayBuilder();

  MediaImageRef image(
    String url, {
    Map<String, String> headers = const {},
    bool selfAuthenticated = false,
  }) {
    return MediaImageRef(
      url: url,
      headers: headers,
      selfAuthenticated: selfAuthenticated,
    );
  }

  MediaItemCard card({
    String id = 'item-1',
    String title = '卡片标题',
    String secondaryTitle = '',
    String type = 'Movie',
    String seriesId = '',
    MediaImageRef primaryImage = const MediaImageRef(url: 'card-primary'),
    List<MediaImageRef> posters = const <MediaImageRef>[],
    MediaImageRef backdropImage = const MediaImageRef(url: 'card-backdrop'),
    String rating = '',
    String overview = '',
    String releaseDate = '',
    String firstAirDate = '',
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
      posters: posters,
      backdropImage: backdropImage,
      rating: rating,
      overview: overview,
      genres: genres,
      releaseDate: releaseDate,
      firstAirDate: firstAirDate,
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
    String seriesId = '',
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
      seriesId: seriesId,
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
        type: 'Movie',
        seriesId: 'library-root',
        primaryImage: image('card-primary-landscape'),
        posters: <MediaImageRef>[
          image('card-poster-a'),
          image('card-poster-b'),
        ],
        backdropImage: image('card-backdrop'),
        rating: '8.0',
        seasonNumber: 1,
        episodeNumber: 7,
        posterWidth: 1920,
        posterHeight: 1080,
      ),
      itemDetail: detail(
        type: 'Episode',
        seriesId: 'series-42',
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
      resolvedSeriesId: 'series-42',
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
      'series-logo',
      'item-logo',
    ]);
    expect(result.posterImages.map((image) => image.url), [
      'series-primary',
      'season-primary',
      'card-poster-a',
      'card-poster-b',
      'card-primary-landscape',
    ]);
    expect(result.backgroundImages.map((image) => image.url), [
      'series-backdrop',
      'item-backdrop',
      'card-backdrop',
      'series-primary',
      'season-primary',
      'card-primary-landscape',
    ]);
    expect(result.card.id, 'episode-7');
  });

  test('季条目使用作品标题且优先系列 logo', () {
    final result = builder.build(
      card: card(
        id: 'season-1-card',
        title: '卡片季标题',
        type: ' Season ',
        seriesId: 'series-42',
      ),
      itemDetail: detail(
        id: 'season-1-detail',
        title: '详情季标题',
        secondaryTitle: '详情季展示名',
        type: 'Season',
        logoImage: image('season-logo'),
      ),
      seriesDetail: detail(
        id: 'series-42',
        title: '作品标题',
        type: 'TV',
        logoImage: image('series-logo'),
      ),
    );

    expect(result.isEpisode, isFalse);
    expect(result.title, '作品标题');
    expect(result.episodeTitle, isEmpty);
    expect(result.logoImages.map((image) => image.url), [
      'series-logo',
      'season-logo',
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
        id: ' movie-card ',
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

  test('无详情时使用 card genres、overview 和 firstAirDate 回退', () {
    final result = builder.build(
      card: card(
        overview: '卡片简介',
        firstAirDate: '2019-05-06',
        genres: const <String>['卡片题材', '悬疑'],
      ),
    );

    expect(result.overview, '卡片简介');
    expect(result.releaseYear, '2019');
    expect(result.genres, ['卡片题材', '悬疑']);
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

  test('飞牛多 poster 候选在竖版 primary 后按顺序参与去重', () {
    final result = builder.build(
      card: card(
        primaryImage: image('card-primary-portrait'),
        posters: <MediaImageRef>[
          image('card-poster-a'),
          image('card-poster-b'),
          image('card-poster-a'),
        ],
        posterWidth: 100,
        posterHeight: 150,
      ),
      seriesDetail: detail(primaryImage: image('series-primary')),
      season: season(primaryImage: image('season-primary')),
    );

    expect(result.posterImages.map((image) => image.url), [
      'card-primary-portrait',
      'card-poster-a',
      'card-poster-b',
      'season-primary',
      'series-primary',
    ]);
  });

  test('图片去重保留首个相同鉴权候选并区分 headers 与显式自鉴权语义', () {
    final result = builder.build(
      card: card(
        primaryImage: image('same', selfAuthenticated: true),
        backdropImage: image(
          'same',
          headers: const {'Authorization': 'Bearer a', 'X-Trace': '1'},
        ),
        posterWidth: 100,
        posterHeight: 150,
      ),
      itemDetail: detail(
        backdropImage: image(
          'same',
          headers: const {'X-Trace': '1', 'Authorization': 'Bearer a'},
        ),
      ),
      seriesDetail: detail(
        primaryImage: image('same', selfAuthenticated: false),
        backdropImage: image('same?api_key=token', selfAuthenticated: false),
      ),
      season: season(primaryImage: image('same', selfAuthenticated: true)),
    );

    expect(result.backgroundImages.map((image) => image.url), [
      'same',
      'same?api_key=token',
      'same',
      'same',
    ]);
    expect(result.backgroundImages[0].headers, {
      'Authorization': 'Bearer a',
      'X-Trace': '1',
    });
    expect(result.backgroundImages[1].headers, isEmpty);
    expect(result.backgroundImages[1].selfAuthenticated, isFalse);
    expect(result.backgroundImages[2].selfAuthenticated, isTrue);
    expect(result.backgroundImages[3].selfAuthenticated, isFalse);
  });

  test('copyWith 覆盖所有可补全字段且保持原对象不变', () {
    final original = builder.build(
      card: card(
        id: 'original-card',
        type: 'Episode',
        seriesId: 'original-series',
        seasonNumber: 1,
        episodeNumber: 2,
        numberOfSeasons: 3,
        numberOfEpisodes: 4,
      ),
    );
    final replacementCard = card(id: 'replacement-card');
    final replacementBackground = <MediaImageRef>[image('background-new')];
    final replacementLogos = <MediaImageRef>[image('logo-new')];
    final replacementPosters = <MediaImageRef>[image('poster-new')];

    final updated = original.copyWith(
      card: replacementCard,
      title: '新标题',
      episodeTitle: '新单集标题',
      type: 'Movie',
      seriesId: 'new-series',
      ratingText: '9.8',
      releaseYear: '2026',
      overview: '新简介',
      detailTargetId: 'new-target',
      seasonNumber: 5,
      episodeNumber: 6,
      numberOfSeasons: 7,
      numberOfEpisodes: 8,
      durationSeconds: 900,
      genres: const <String>['新题材'],
      resolutions: const <String>['8K'],
      backgroundImages: replacementBackground,
      logoImages: replacementLogos,
      posterImages: replacementPosters,
    );

    replacementBackground.add(image('background-late'));
    replacementLogos.add(image('logo-late'));
    replacementPosters.add(image('poster-late'));

    expect(updated.card.id, 'replacement-card');
    expect(updated.title, '新标题');
    expect(updated.episodeTitle, '新单集标题');
    expect(updated.type, 'Movie');
    expect(updated.seriesId, 'new-series');
    expect(updated.ratingText, '9.8');
    expect(updated.releaseYear, '2026');
    expect(updated.overview, '新简介');
    expect(updated.detailTargetId, 'new-target');
    expect(updated.seasonNumber, 5);
    expect(updated.episodeNumber, 6);
    expect(updated.numberOfSeasons, 7);
    expect(updated.numberOfEpisodes, 8);
    expect(updated.durationSeconds, 900);
    expect(updated.genres, ['新题材']);
    expect(updated.resolutions, ['8K']);
    expect(updated.backgroundImages.map((image) => image.url), [
      'background-new',
    ]);
    expect(updated.logoImages.map((image) => image.url), ['logo-new']);
    expect(updated.posterImages.map((image) => image.url), ['poster-new']);
    expect(
      () => updated.backgroundImages.add(image('background-unsupported')),
      throwsUnsupportedError,
    );

    expect(original.card.id, 'original-card');
    expect(original.type, 'Episode');
    expect(original.seriesId, 'original-series');
    expect(original.seasonNumber, 1);
    expect(original.episodeNumber, 2);
    expect(original.numberOfSeasons, 3);
    expect(original.numberOfEpisodes, 4);
  });
}
