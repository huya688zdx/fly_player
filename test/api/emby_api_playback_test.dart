import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/api/emby_api.dart';

void main() {
  // buildStreamUrl 是纯字符串构造（不发请求），用任意 Dio 即可。
  final api = EmbyApi(dio: Dio(BaseOptions()));

  test('buildStreamUrl 拼 Static=true + MediaSourceId + api_key', () {
    final url = api.buildStreamUrl(
      serverUrl: 'https://emby.example.test/',
      itemId: 'item-9',
      mediaSourceId: 'src-3',
      accessToken: 'tok',
    );
    final uri = Uri.parse(url);
    expect(uri.host, 'emby.example.test');
    expect(uri.path, '/Videos/item-9/stream');
    expect(uri.queryParameters['Static'], 'true');
    expect(uri.queryParameters['MediaSourceId'], 'src-3');
    expect(uri.queryParameters['api_key'], 'tok');
  });

  test('buildStreamUrl 带 container 时路径拼成 stream.<container>', () {
    final url = api.buildStreamUrl(
      serverUrl: 'https://emby.example.test',
      itemId: 'item-9',
      mediaSourceId: 'src-3',
      accessToken: 'tok',
      container: 'mkv',
    );
    expect(Uri.parse(url).path, '/Videos/item-9/stream.mkv');
  });

  test('buildStreamUrl 空 mediaSourceId 时省略该参数', () {
    final url = api.buildStreamUrl(
      serverUrl: 'https://emby.example.test',
      itemId: 'item-9',
      mediaSourceId: '',
      accessToken: 'tok',
    );
    final uri = Uri.parse(url);
    expect(uri.queryParameters.containsKey('MediaSourceId'), isFalse);
    expect(uri.queryParameters['Static'], 'true');
    expect(uri.queryParameters['api_key'], 'tok');
  });
}
