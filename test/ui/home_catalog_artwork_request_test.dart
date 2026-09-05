import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/ui/detail_artwork_resolver.dart';
import 'package:fly_player/ui/layout_adaptive.dart';
import 'package:fly_player/utils/api_url_helper.dart';

void main() {
  test('首页目录 fallback 与 fresh 图片候选使用相同稳定宽度', () {
    const baseUrl = 'http://nas.example';
    const path = '/library/poster.jpg';
    final fallbackUrls = ApiUrlHelper.imageCandidates(
      baseUrl,
      path,
      width: MediaLayoutProfile.homeCatalogRequestWidthValue,
    );
    final freshRequest =
        const DetailArtworkResolver(
          baseUrl: baseUrl,
          token: 'token',
          accessCode: 'access-code',
        ).resolveRef(
          const MediaImageRef(url: path),
          width: MediaLayoutProfile.homeCatalogRequestWidthValue,
        );

    expect(freshRequest.urls, fallbackUrls);
    expect(freshRequest.urls.first, contains('w=440'));
    expect(freshRequest.urls, everyElement(isNot(contains('w=900'))));
  });

  test('首页目录 preserved 服务器直链不被宽度重写', () {
    final request =
        const DetailArtworkResolver(
          baseUrl: 'https://nas.example',
          token: 'token',
          accessCode: 'access-code',
        ).resolveRef(
          const MediaImageRef(url: 'https://cdn.example/poster.jpg'),
          width: MediaLayoutProfile.homeCatalogRequestWidthValue,
        );

    expect(request.urls, <String>['https://cdn.example/poster.jpg']);
  });
}
