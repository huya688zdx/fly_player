import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_catalog.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/media_backend/media_item_summary.dart';

void main() {
  test('media item summary exposes display title and primary image', () {
    const image = MediaImageRef(url: 'https://server/poster.jpg');
    const item = MediaItemSummary(
      id: 'item-1',
      title: '正片标题',
      type: 'Movie',
      primaryImage: image,
      backdropImage: MediaImageRef.empty,
      durationSeconds: 3600,
      watched: false,
    );

    expect(item.displayTitle, '正片标题');
    expect(item.primaryImage.url, 'https://server/poster.jpg');
  });

  test('media catalog keeps stable id and title', () {
    const catalog = MediaCatalog(
      id: 'movies',
      title: '电影',
      type: 'Movie',
      primaryImage: MediaImageRef.empty,
    );

    expect(catalog.id, 'movies');
    expect(catalog.title, '电影');
  });
}
