import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/api/emby_api.dart';
import 'package:fly_player/api/jellyfin_api.dart';
import 'package:fly_player/media_backend/jellyfin/jellyfin_media_backend.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/media_backend/media_backend_registry.dart';
import 'package:fly_player/media_backend/session/media_backend_connection.dart';

/// 子类探针：@protected 的鉴权头缝隙只允许子类访问，测试经由子类读取。
class _EmbyHeaderProbe extends EmbyApi {
  _EmbyHeaderProbe();

  String get header => authorizationHeaderValue;
  String sessionHeader(String token) => sessionAuthorizationHeaderValue(token);
}

class _JellyfinHeaderProbe extends JellyfinApi {
  _JellyfinHeaderProbe();

  String get header => authorizationHeaderValue;
  String sessionHeader(String token) => sessionAuthorizationHeaderValue(token);
}

void main() {
  test('Emby 鉴权头维持历史行为：参数值不带引号', () {
    final api = _EmbyHeaderProbe();
    expect(
      api.header,
      'MediaBrowser Client=Fly Player, Device=Flutter, '
      'DeviceId=fly-player, Version=1.0.0',
    );
  });

  test('Jellyfin 鉴权头为带引号的规范 MediaBrowser 形状', () {
    final api = _JellyfinHeaderProbe();
    expect(
      api.header,
      'MediaBrowser Client="Fly Player", Device="Flutter", '
      'DeviceId="fly-player", Version="1.0.0"',
    );
  });

  test('会话端点授权头（带 Token）两家同形：值带引号', () {
    expect(
      _JellyfinHeaderProbe().sessionHeader('tok-1'),
      _EmbyHeaderProbe().sessionHeader('tok-1'),
    );
    expect(_JellyfinHeaderProbe().sessionHeader('tok-1'), contains('"tok-1"'));
  });

  test('Jellyfin 描述符已登记且工厂产出 Jellyfin 后端', () {
    final descriptor = MediaBackendRegistry.requireDescriptor(
      MediaBackendKind.jellyfin,
    );
    expect(descriptor.displayName, 'Jellyfin');
    expect(descriptor.badgeText, 'JF');
    expect(descriptor.createApiClient(), isA<JellyfinApi>());

    final backend = descriptor.createBackend(
      const MediaBackendConnection(
        kind: MediaBackendKind.jellyfin,
        serverUrl: 'https://jellyfin.example.test',
        userId: 'user-1',
        accessToken: 'token',
      ),
    );
    expect(backend, isA<JellyfinMediaBackend>());
    expect(backend.capabilities.kind, MediaBackendKind.jellyfin);
    expect(backend.capabilities.usesLegacyFeiniuFlow, isFalse);
    expect(MediaBackendKind.jellyfin.isServerFamily, isTrue);
  });
}
