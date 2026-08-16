import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/ui/adaptive_detail_navigator.dart';

void main() {
  test('飞牛同源绝对图使用当前 NAS token 与访问码', () {
    final request = resolveAdaptiveDetailHeroRequest(
      backendKind: MediaBackendKind.feiniu,
      directRef: const MediaImageRef(
        url: 'https://nas.example/poster.jpg',
        headers: <String, String>{'Authorization': 'stale'},
      ),
      feiniuCredentialsProvider: () => (
        token: 'current-token',
        accessCode: 'current-access',
        baseUrl: 'https://nas.example',
      ),
    );

    expect(request.headers['Authorization'], 'current-token');
    expect(request.headers['Trim-MC-token'], 'current-token');
    expect(request.headers, contains('x-access-code'));
  });

  test('飞牛第三方绝对图不附加 NAS 管理头', () {
    final request = resolveAdaptiveDetailHeroRequest(
      backendKind: MediaBackendKind.feiniu,
      directRef: const MediaImageRef(
        url: 'https://cdn.example/poster.jpg',
        headers: <String, String>{'X-Test': 'keep'},
      ),
      feiniuCredentialsProvider: () => (
        token: 'current-token',
        accessCode: 'current-access',
        baseUrl: 'https://nas.example',
      ),
    );

    expect(request.headers, <String, String>{'X-Test': 'keep'});
  });

  test('server-family 保留自身鉴权且不读取残留 NAS', () {
    var nasReads = 0;
    final request = resolveAdaptiveDetailHeroRequest(
      backendKind: MediaBackendKind.emby,
      directRef: const MediaImageRef(
        url: 'https://emby.example/poster.jpg',
        headers: <String, String>{'X-Emby-Token': 'emby-token'},
        selfAuthenticated: true,
      ),
      feiniuCredentialsProvider: () {
        nasReads++;
        return (
          token: 'stale-token',
          accessCode: 'stale-access',
          baseUrl: 'https://stale-nas.example',
        );
      },
    );

    expect(request.headers, <String, String>{'X-Emby-Token': 'emby-token'});
    expect(request.selfAuthenticated, isTrue);
    expect(nasReads, 0);
  });
}
