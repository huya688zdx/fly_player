import 'package:flutter/foundation.dart';

import '../api/emby_api.dart';
import '../api/feiniu_api.dart';
import '../media_backend/emby/emby_media_backend.dart';
import '../media_backend/feiniu/feiniu_media_backend.dart';
import '../media_backend/media_backend.dart';
import '../media_backend/media_backend_kind.dart';
import 'backend_session_provider.dart';
import 'nas_provider.dart';

/// 向页面提供当前 [MediaBackend] 实例。
///
/// 按当前后端会话路由：[BackendSessionProvider.currentKind] 为服务器族且连接已认证时
/// 返回当前服务器族后端；否则（飞牛 / 无会话层）返回 [FeiniuMediaBackend]。页面只读
/// `backend`，无需感知后端类型，也不写 `if (isEmby)`。
///
/// 按会话身份缓存 backend 实例（缓存键 = kind + 身份）：飞牛取 `nasProvider.baseUrl`
/// （FeiniuApi 把 baseUrl 烤进 Dio、token 拦截器每请求动态读取，故 baseUrl 变更才重建）；
/// 服务器族取 kind + serverUrl + accessToken。同一会话内多页面复用同一实例，会话切换时才重建。
class MediaBackendProvider extends ChangeNotifier {
  final NasProvider nasProvider;

  /// 后端会话来源；为 `null`（无会话层，如单元测试）时固定走飞牛，保持历史行为。
  final BackendSessionProvider? sessionProvider;

  MediaBackendProvider(this.nasProvider, [this.sessionProvider]);

  MediaBackend? _cachedBackend;
  String? _cachedKey;

  MediaBackend get backend {
    final session = sessionProvider;
    final connection = session?.currentConnection;
    if (session != null &&
        session.currentKind.isServerFamily &&
        connection != null &&
        connection.isAuthenticated) {
      final key =
          '${session.currentKind.name}:${connection.serverUrl}:${connection.accessToken}';
      final cached = _cachedBackend;
      if (cached != null && _cachedKey == key) return cached;
      // .fnos.net 中转域名的 Emby 需携带 FN Connect 入口令牌（entry-token cookie）过云端
      // 边缘闸；从已保存连接动态读取，令牌刷新后无需重建。直连地址 entryToken 为空、不带头。
      final created = EmbyMediaBackend(
        api: EmbyApi(
          entryTokenProvider: () => session.currentConnection?.entryToken ?? '',
        ),
        connection: connection,
      );
      _cachedBackend = created;
      _cachedKey = key;
      return created;
    }

    final key = 'feiniu:${nasProvider.baseUrl}';
    final cached = _cachedBackend;
    if (cached != null && _cachedKey == key) return cached;
    final created = FeiniuMediaBackend(FeiniuApi(nasProvider));
    _cachedBackend = created;
    _cachedKey = key;
    return created;
  }
}
