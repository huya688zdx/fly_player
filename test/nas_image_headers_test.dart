import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/utils/nas_image_headers.dart';

void main() {
  group('nasImageHeaders', () {
    test('为 FN Connect 图片请求补 relay cookie', () {
      expect(
        nasImageHeaders(
          'Bearer token',
          url: 'https://geqian688.fnos.net/a.png',
          baseUrl: 'https://geqian688.fnos.net',
        ),
        containsPair('Cookie', 'mode=relay'),
      );
    });

    test('普通 NAS 图片请求不补 relay cookie', () {
      expect(
        nasImageHeaders(
          'Bearer token',
          url: 'https://192.168.6.120/a.png',
          baseUrl: 'https://192.168.6.120',
        ),
        isNot(contains('Cookie')),
      );
    });

    test('空 token 不返回鉴权头', () {
      expect(nasImageHeaders(' ', url: 'https://fnos.net/a.png'), isEmpty);
    });

    test('同源图片携带 UTF-8 Base64 访问码及来源', () {
      final headers = nasImageHeaders(
        'Bearer token',
        url: 'https://nas.example:5667/image.jpg',
        accessCode: ' 访问码-123 ',
        baseUrl: 'https://nas.example:5667',
      );

      expect(headers['x-access-code'], base64Encode(utf8.encode('访问码-123')));
      expect(headers['x-access-source'], 'app');
      expect(headers['Authorization'], 'Bearer token');
      expect(headers['Trim-MC-token'], 'Bearer token');
    });

    test('第三方、跨协议及跨端口图片均不携带访问码', () {
      for (final url in <String>[
        'https://cdn.example/image.jpg',
        'http://nas.example:5667/image.jpg',
        'https://nas.example:5668/image.jpg',
      ]) {
        final headers = nasImageHeaders(
          'Bearer token',
          url: url,
          accessCode: 'secret',
          baseUrl: 'https://nas.example:5667',
        );
        expect(headers, isNot(contains('Authorization')), reason: url);
        expect(headers, isNot(contains('Trim-MC-token')), reason: url);
        expect(headers, isNot(contains('Cookie')), reason: url);
        expect(headers, isNot(contains('x-access-code')), reason: url);
        expect(headers, isNot(contains('x-access-source')), reason: url);
      }
    });

    test('空访问码不携带访问码头', () {
      final headers = nasImageHeaders(
        'Bearer token',
        url: 'https://nas.example/image.jpg',
        accessCode: ' ',
        baseUrl: 'https://nas.example',
      );

      expect(headers, isNot(contains('x-access-code')));
      expect(headers, isNot(contains('x-access-source')));
    });

    test('相对 URL 配合合法基址视为同源', () {
      final headers = nasImageHeaders(
        '',
        url: '/media/poster.jpg',
        accessCode: 'code',
        baseUrl: 'https://nas.example',
      );

      expect(headers['x-access-code'], base64Encode(utf8.encode('code')));
      expect(headers['x-access-source'], 'app');
    });

    test('FN Connect 相对 URL 携带同源 NAS 头和 relay cookie', () {
      final headers = nasImageHeaders(
        'Bearer token',
        url: '/media/poster.jpg',
        accessCode: 'code',
        baseUrl: 'https://device.fnos.net',
      );

      expect(headers['Authorization'], 'Bearer token');
      expect(headers['Trim-MC-token'], 'Bearer token');
      expect(headers['Cookie'], 'mode=relay');
      expect(headers, contains('x-access-code'));
    });
  });
}
