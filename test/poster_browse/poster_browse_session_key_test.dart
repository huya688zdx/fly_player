import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_session_key.dart';

void main() {
  test('服务器族会话使用服务器地址和令牌隔离，忽略飞牛残留配置', () {
    final first = buildPosterBrowseBackendSessionKey(
      backendKind: MediaBackendKind.emby,
      nasBaseUrl: 'http://old-nas',
      nasToken: 'old-token',
      serverBaseUrl: 'http://emby-a',
      serverToken: 'token-a',
    );
    final second = buildPosterBrowseBackendSessionKey(
      backendKind: MediaBackendKind.emby,
      nasBaseUrl: 'http://old-nas',
      nasToken: 'old-token',
      serverBaseUrl: 'http://emby-a',
      serverToken: 'token-b',
    );

    expect(first, isNot(second));
    expect(first, isNot(contains('token-a')));
  });

  test('飞牛会话使用 NAS 地址和令牌，忽略服务器族残留配置', () {
    final first = buildPosterBrowseBackendSessionKey(
      backendKind: MediaBackendKind.feiniu,
      nasBaseUrl: 'http://nas',
      nasToken: 'token-a',
      serverBaseUrl: 'http://old-emby',
      serverToken: 'old-token',
    );
    final second = buildPosterBrowseBackendSessionKey(
      backendKind: MediaBackendKind.feiniu,
      nasBaseUrl: 'http://nas',
      nasToken: 'token-b',
      serverBaseUrl: 'http://old-emby',
      serverToken: 'old-token',
    );

    expect(first, isNot(second));
    expect(first, isNot(contains('token-a')));
  });
}
