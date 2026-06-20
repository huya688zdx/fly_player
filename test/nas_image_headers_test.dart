import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/utils/nas_image_headers.dart';

void main() {
  group('nasImageHeaders', () {
    test('为 FN Connect 图片请求补 relay cookie', () {
      expect(
        nasImageHeaders(
          'Bearer token',
          url: 'https://geqian688.fnos.net/a.png',
        ),
        containsPair('Cookie', 'mode=relay'),
      );
    });

    test('普通 NAS 图片请求不补 relay cookie', () {
      expect(
        nasImageHeaders('Bearer token', url: 'https://192.168.6.120/a.png'),
        isNot(contains('Cookie')),
      );
    });

    test('空 token 不返回鉴权头', () {
      expect(nasImageHeaders(' ', url: 'https://fnos.net/a.png'), isEmpty);
    });
  });
}
