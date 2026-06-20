import 'package:flutter/foundation.dart';

import '../api/feiniu_api.dart';
import '../media_backend/feiniu/feiniu_media_backend.dart';
import '../media_backend/media_backend.dart';
import 'nas_provider.dart';

/// 向页面提供当前 [MediaBackend] 实例。
///
/// 第一阶段固定返回飞牛适配器；未来根据配置切换后端时，只改这里，
/// 页面无需感知后端类型。
///
/// 按 NAS 会话缓存 backend 实例：[FeiniuApi] 在构造时把 `nasProvider.baseUrl`
/// 烤进内部 Dio（token 在拦截器里每次请求动态读取，无需重建），所以缓存键取
/// `baseUrl`——同一会话内多页面频繁读取 `backend` 复用同一实例（连带复用
/// FeiniuApi 内的标签 / 题材等共享缓存），baseUrl 变更（重登 / FN Connect 切换 /
/// 登出清除 resolvedBaseUrl）时才重建，避免重复创建 Dio。
class MediaBackendProvider extends ChangeNotifier {
  final NasProvider nasProvider;

  MediaBackendProvider(this.nasProvider);

  MediaBackend? _cachedBackend;
  String? _cachedBaseUrl;

  MediaBackend get backend {
    final baseUrl = nasProvider.baseUrl;
    final cached = _cachedBackend;
    if (cached != null && _cachedBaseUrl == baseUrl) {
      return cached;
    }
    final created = FeiniuMediaBackend(FeiniuApi(nasProvider));
    _cachedBackend = created;
    _cachedBaseUrl = baseUrl;
    return created;
  }
}
