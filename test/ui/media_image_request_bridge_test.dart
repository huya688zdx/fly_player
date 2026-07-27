import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/ui/detail_artwork_resolver.dart';

void main() {
  test('保存的服务器族请求不会附加飞牛 token', () {
    const preserved = MediaImageRequest(
      urls: <String>['https://emby.example/image?api_key=E'],
      selfAuthenticated: true,
    );

    final request = preferPreservedImageRequest(
      preserved: preserved,
      fallbackUrls: const <String>['https://emby.example/image?api_key=E'],
      fallbackToken: 'FN_TOKEN',
    );

    expect(request.headers, isEmpty);
    expect(request.selfAuthenticated, isTrue);
  });

  test('保存的 FNOS headers 原样保留', () {
    const preserved = MediaImageRequest(
      urls: <String>['https://host.fnos.net/image'],
      headers: <String, String>{'Cookie': 'entry-token=ENTRY'},
    );

    final request = preferPreservedImageRequest(
      preserved: preserved,
      fallbackUrls: const <String>[],
      fallbackToken: 'FN_TOKEN',
    );

    expect(request.headers, <String, String>{'Cookie': 'entry-token=ENTRY'});
  });

  test('旧字符串链路的自鉴权 URL 不附加飞牛 token', () {
    final request = mediaImageRequestForUrls(const <String>[
      'https://emby.example/image?api_key=E',
    ], token: 'FN_TOKEN');

    expect(request.headers, isEmpty);
    expect(request.selfAuthenticated, isTrue);
  });

  test('无保存请求时保持飞牛旧数据回退', () {
    final request = preferPreservedImageRequest(
      preserved: null,
      fallbackUrls: const <String>['http://nas.local/image'],
      fallbackToken: 'FN_TOKEN',
    );

    expect(request.headers['Authorization'], 'FN_TOKEN');
    expect(request.headers['Trim-MC-token'], 'FN_TOKEN');
  });
}
