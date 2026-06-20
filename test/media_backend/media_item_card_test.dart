import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/media_backend/media_item_card.dart';

void main() {
  test('displayTitle 优先副标题，其次主标题，皆空回退占位', () {
    const withSecondary = MediaItemCard(
      id: 'a',
      title: '剧集 B',
      type: 'Episode',
      primaryImage: MediaImageRef.empty,
      secondaryTitle: '第 3 集',
    );
    expect(withSecondary.displayTitle, '第 3 集');

    const titleOnly = MediaItemCard(
      id: 'b',
      title: '电影 A',
      type: 'Movie',
      primaryImage: MediaImageRef.empty,
    );
    expect(titleOnly.displayTitle, '电影 A');

    const empty = MediaItemCard(
      id: 'c',
      title: '   ',
      type: 'Movie',
      primaryImage: MediaImageRef.empty,
    );
    expect(empty.displayTitle, 'Unknown');
  });

  test('hasPosterSize / isLandscapePoster 由海报尺寸推导', () {
    const portrait = MediaItemCard(
      id: 'a',
      title: 't',
      type: 'Movie',
      primaryImage: MediaImageRef.empty,
      posterWidth: 1000,
      posterHeight: 1500,
    );
    expect(portrait.hasPosterSize, isTrue);
    expect(portrait.isLandscapePoster, isFalse);

    const landscape = MediaItemCard(
      id: 'b',
      title: 't',
      type: 'Episode',
      primaryImage: MediaImageRef.empty,
      posterWidth: 1920,
      posterHeight: 1080,
    );
    expect(landscape.isLandscapePoster, isTrue);

    const noSize = MediaItemCard(
      id: 'c',
      title: 't',
      type: 'Movie',
      primaryImage: MediaImageRef.empty,
    );
    expect(noSize.hasPosterSize, isFalse);
    expect(noSize.isLandscapePoster, isFalse);
  });

  test('默认值保持后端中立的空 / 0', () {
    const card = MediaItemCard(
      id: 'a',
      title: 't',
      type: 'Movie',
      primaryImage: MediaImageRef.empty,
    );
    expect(card.posters, isEmpty);
    expect(card.resolutions, isEmpty);
    expect(card.watched, isFalse);
    expect(card.rating, '');
    expect(card.numberOfItem, 0);
    expect(card.localNumberOfSeasons, 0);
    expect(card.firstAirDate, '');
  });

  test('copyWith 只替换指定字段（搜索页本地 watched 变更场景）', () {
    const card = MediaItemCard(
      id: 'a',
      title: '电影 A',
      type: 'Movie',
      primaryImage: MediaImageRef.empty,
      rating: '8.5',
      seasonNumber: 2,
      watched: false,
    );

    final toggled = card.copyWith(watched: true);
    expect(toggled.watched, isTrue);
    // 其余字段原样保留。
    expect(toggled.id, 'a');
    expect(toggled.title, '电影 A');
    expect(toggled.rating, '8.5');
    expect(toggled.seasonNumber, 2);
  });
}
