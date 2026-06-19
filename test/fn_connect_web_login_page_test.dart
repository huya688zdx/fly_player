import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/screens/fn_connect_web_login_page.dart';

void main() {
  group('FnConnectWebLoginEntry', () {
    test('有 relay host 时优先直接打开 relay 入口', () {
      final entry = FnConnectWebLoginEntry.resolve(
        fnConnectId: 'geqian688',
        relayHosts: const <String>[' relay.example.com ', 'backup.example.com'],
      );

      expect(entry.initialUrl, 'https://relay.example.com');
      expect(entry.cookieHosts, const <String>[
        'relay.example.com',
        '5ddd.com',
        'fnos.net',
      ]);
    });

    test('relay host 可包含协议和路径，最终只保留 origin', () {
      final entry = FnConnectWebLoginEntry.resolve(
        fnConnectId: 'geqian688',
        relayHosts: const <String>['https://relay.example.com/foo/bar'],
      );

      expect(entry.initialUrl, 'https://relay.example.com');
      expect(entry.cookieHosts.first, 'relay.example.com');
    });

    test('没有 relay host 时回退到官方 FN Connect 入口', () {
      final entry = FnConnectWebLoginEntry.resolve(
        fnConnectId: 'geqian688',
        relayHosts: const <String>[],
      );

      expect(entry.initialUrl, 'https://5ddd.com/geqian688');
      expect(entry.cookieHosts, const <String>['5ddd.com', 'fnos.net']);
    });
  });
}
