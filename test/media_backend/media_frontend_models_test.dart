import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_catalog.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';

void main() {
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
