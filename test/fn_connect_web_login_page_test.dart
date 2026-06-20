import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/screens/fn_connect_web_login_page.dart';

void main() {
  group('FnConnectWebLoginEntry', () {
    test('有 relay host 时仍从官方页兜底，relay 只作为 OAuth 配置候选', () {
      final entry = FnConnectWebLoginEntry.resolve(
        fnConnectId: 'geqian688',
        relayHosts: const <String>[' relay.example.com ', 'backup.example.com'],
      );

      expect(entry.initialUrl, 'https://5ddd.com/geqian688');
      expect(entry.relayBaseUrls, const <String>[
        'https://relay.example.com',
        'https://backup.example.com',
      ]);
      expect(entry.cookieHosts, const <String>[
        'relay.example.com',
        'backup.example.com',
        '5ddd.com',
        'fnos.net',
      ]);
    });

    test('relay host 可包含协议和路径，最终只保留 origin', () {
      final entry = FnConnectWebLoginEntry.resolve(
        fnConnectId: 'geqian688',
        relayHosts: const <String>['https://relay.example.com/foo/bar'],
      );

      expect(entry.relayBaseUrls, const <String>['https://relay.example.com']);
      expect(entry.cookieHosts.first, 'relay.example.com');
    });

    test('没有 relay host 时回退到官方 FN Connect 入口', () {
      final entry = FnConnectWebLoginEntry.resolve(
        fnConnectId: 'geqian688',
        relayHosts: const <String>[],
      );

      expect(entry.initialUrl, 'https://5ddd.com/geqian688');
      expect(entry.relayBaseUrls, isEmpty);
      expect(entry.cookieHosts, const <String>['5ddd.com', 'fnos.net']);
    });
  });

  group('FnConnectWebLoginSessionPolicy', () {
    test('默认保留 WebView 登录态，避免每次重新输入 FN 账号密码', () {
      expect(FnConnectWebLoginSessionPolicy.preserveCookiesByDefault, isTrue);
    });
  });
}
