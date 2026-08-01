import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/ui/detail_artwork_resolver.dart';
import 'package:fly_player/utils/api_url_helper.dart';
import 'package:fly_player/utils/nas_image_headers.dart';

void main() {
  const baseUrl = 'http://nas.example:5666';
  const token = 'nas-token-xyz';
  const accessCode = '访问码';
  const resolver = DetailArtworkResolver(
    baseUrl: baseUrl,
    token: token,
    accessCode: accessCode,
  );

  group('resolvePath（飞牛相对路径）', () {
    test('与 imageCandidates + nasImageHeaders 逐字段等价', () {
      const path = '/media/poster/abc.jpg';
      final expectedUrls = ApiUrlHelper.imageCandidates(
        baseUrl,
        path,
        width: 1200,
      );
      final artwork = resolver.resolvePath(path, width: 1200);
      expect(artwork.urls, expectedUrls);
      expect(
        artwork.headers,
        nasImageHeaders(
          token,
          url: expectedUrls.first,
          accessCode: accessCode,
          baseUrl: baseUrl,
        ),
      );
      expect(artwork.headers, contains('x-access-code'));
    });

    test('空路径返回空', () {
      expect(resolver.resolvePath('').isEmpty, isTrue);
      expect(resolver.resolvePath('   ').isEmpty, isTrue);
    });
  });

  group('resolveRef（中立图引用）', () {
    test('完整 Emby api_key 直链沿用 ref 头且不附加访问码', () {
      const url = 'http://emby.example:8096/Items/1/Images/Primary?api_key=KEY';
      const ref = MediaImageRef(url: url, headers: {'X-Test': '1'});
      final artwork = resolver.resolveRef(ref);
      expect(artwork.urls, <String>[url]);
      expect(artwork.headers, {'X-Test': '1'});
      expect(artwork.headers, isNot(contains('x-access-code')));
    });

    test('第三方 https 直链不附加飞牛头', () {
      const url = 'https://cdn.example/a.jpg';
      const ref = MediaImageRef(url: url);
      final artwork = resolver.resolveRef(ref);
      expect(artwork.urls, <String>[url]);
      expect(artwork.headers, isEmpty);
    });

    test('相对路径 ref 走飞牛拼接', () {
      const path = '/media/backdrop/x.jpg';
      const ref = MediaImageRef(url: path);
      final artwork = resolver.resolveRef(ref, width: 360);
      expect(artwork.urls, resolver.resolvePath(path, width: 360).urls);
      expect(artwork.headers, resolver.resolvePath(path, width: 360).headers);
    });

    test('空 ref 返回空', () {
      expect(resolver.resolveRef(MediaImageRef.empty).isEmpty, isTrue);
    });
  });

  group('resolveRefs（背景 hero 合并）', () {
    test('按序合并候选：背景图优先、退海报', () {
      const backdrop = MediaImageRef(
        url: 'http://emby.example:8096/b?api_key=K',
      );
      const primary = MediaImageRef(
        url: 'http://emby.example:8096/p?api_key=K',
      );
      final artwork = resolver.resolveRefs(<MediaImageRef>[backdrop, primary]);
      expect(artwork.urls, <String>[
        'http://emby.example:8096/b?api_key=K',
        'http://emby.example:8096/p?api_key=K',
      ]);
    });

    test('跳过空引用', () {
      const primary = MediaImageRef(url: 'https://cdn.example/p.jpg');
      final artwork = resolver.resolveRefs(<MediaImageRef>[
        MediaImageRef.empty,
        primary,
      ]);
      expect(artwork.urls, <String>['https://cdn.example/p.jpg']);
    });
  });
}
