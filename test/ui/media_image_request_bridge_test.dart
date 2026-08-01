import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/ui/detail_artwork_resolver.dart';

void main() {
  test('保存的服务器族请求不附加飞牛凭据', () {
    const preserved = MediaImageRequest(
      urls: <String>['https://emby.example/image?api_key=E'],
      selfAuthenticated: true,
    );

    final request = preferPreservedImageRequest(
      preserved: preserved,
      fallbackUrls: const <String>['https://emby.example/image?api_key=E'],
      fallbackToken: 'FN_TOKEN',
      fallbackAccessCode: 'FN_ACCESS_CODE',
      fallbackBaseUrl: 'https://nas.example',
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
      fallbackAccessCode: '',
      fallbackBaseUrl: '',
    );

    expect(request.headers, <String, String>{'Cookie': 'entry-token=ENTRY'});
  });

  test('旧字符串链路的自鉴权 URL 不附加飞牛凭据', () {
    final request = mediaImageRequestForUrls(
      const <String>['https://emby.example/image?api_key=E'],
      token: 'FN_TOKEN',
      accessCode: 'FN_ACCESS_CODE',
      baseUrl: 'https://nas.example',
    );

    expect(request.headers, isEmpty);
    expect(request.selfAuthenticated, isTrue);
  });

  test('无保存请求时保持飞牛旧数据回退', () {
    final request = preferPreservedImageRequest(
      preserved: null,
      fallbackUrls: const <String>['http://nas.local/image'],
      fallbackToken: 'FN_TOKEN',
      fallbackAccessCode: '',
      fallbackBaseUrl: 'http://nas.local',
    );

    expect(request.headers['Authorization'], 'FN_TOKEN');
    expect(request.headers['Trim-MC-token'], 'FN_TOKEN');
  });

  test('Emby 图片凭据不消费残留飞牛访问码', () {
    final credentials = mediaImageCredentialsForBackend(
      backendKind: MediaBackendKind.emby,
      token: 'FN_TOKEN',
      accessCode: 'FN_ACCESS_CODE',
      baseUrl: 'https://nas.example',
    );

    expect(credentials, (token: '', accessCode: '', baseUrl: ''));
  });

  test('Jellyfin 图片凭据不消费残留飞牛访问码', () {
    final credentials = mediaImageCredentialsForBackend(
      backendKind: MediaBackendKind.jellyfin,
      token: 'FN_TOKEN',
      accessCode: 'FN_ACCESS_CODE',
      baseUrl: 'https://nas.example',
    );

    expect(credentials, (token: '', accessCode: '', baseUrl: ''));
  });
}
