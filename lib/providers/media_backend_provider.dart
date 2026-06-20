import 'package:flutter/foundation.dart';

import '../api/feiniu_api.dart';
import '../media_backend/feiniu/feiniu_media_backend.dart';
import '../media_backend/media_backend.dart';
import 'nas_provider.dart';

/// 向页面提供当前 [MediaBackend] 实例。
///
/// 第一阶段固定返回飞牛适配器；未来根据配置切换后端时，只改这里，
/// 页面无需感知后端类型。
class MediaBackendProvider extends ChangeNotifier {
  final NasProvider nasProvider;

  MediaBackendProvider(this.nasProvider);

  MediaBackend get backend => FeiniuMediaBackend(FeiniuApi(nasProvider));
}
