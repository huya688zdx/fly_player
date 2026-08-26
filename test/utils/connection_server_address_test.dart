import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/utils/connection_server_address.dart';

void main() {
  group('normalizeConnectionServerAddress', () {
    test('空地址保持为空', () {
      expect(normalizeConnectionServerAddress('  '), isEmpty);
    });

    test('裸域名默认补 HTTPS', () {
      expect(
        normalizeConnectionServerAddress('nas.example.com'),
        'https://nas.example.com',
      );
    });

    test('裸 IP 和端口默认补 HTTPS', () {
      expect(
        normalizeConnectionServerAddress('100.125.130.96:8096'),
        'https://100.125.130.96:8096',
      );
    });

    test('显式 HTTP 不自动升级', () {
      expect(
        normalizeConnectionServerAddress('http://nas.example.com:5667'),
        'http://nas.example.com:5667',
      );
    });

    test('显式 HTTPS 保留路径', () {
      expect(
        normalizeConnectionServerAddress('https://nas.example.com/media'),
        'https://nas.example.com/media',
      );
    });

    test('服务器族清除 Web 客户端路径', () {
      expect(
        normalizeConnectionServerAddress(
          'emby.example.com/web/index.html',
          stripEmbyWebClientPath: true,
        ),
        'https://emby.example.com',
      );
    });
  });
}
