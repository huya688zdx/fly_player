import '../api/emby_api.dart';
import '../api/feiniu_api.dart';
import '../providers/nas_provider.dart';
import 'feiniu/feiniu_media_backend.dart';
import 'emby/emby_media_backend.dart';
import 'media_backend.dart';
import 'media_backend_kind.dart';
import 'session/media_backend_connection.dart';

typedef MediaBackendFactory =
    MediaBackend Function(
      MediaBackendConnection connection, {
      String Function()? entryTokenProvider,
    });

/// 后端类型的静态描述符。
///
/// 新增服务器族后端时，应在 [MediaBackendRegistry.serverDescriptors] 登记一条；
/// 页面和 provider 只消费描述符，不再散落具体后端判断。
class MediaBackendDescriptor {
  const MediaBackendDescriptor({
    required this.kind,
    required this.displayName,
    required this.badgeText,
    required this.createBackend,
  });

  final MediaBackendKind kind;
  final String displayName;
  final String badgeText;
  final MediaBackendFactory createBackend;
}

class MediaBackendRegistry {
  const MediaBackendRegistry._();

  static final MediaBackendDescriptor emby = MediaBackendDescriptor(
    kind: MediaBackendKind.emby,
    displayName: 'Emby',
    badgeText: 'E',
    createBackend:
        (
          MediaBackendConnection connection, {
          String Function()? entryTokenProvider,
        }) => EmbyMediaBackend(
          api: EmbyApi(entryTokenProvider: entryTokenProvider),
          connection: connection,
        ),
  );

  static List<MediaBackendDescriptor> get serverDescriptors =>
      <MediaBackendDescriptor>[emby];

  /// 创建遗留飞牛后端。遗留族不进入服务器族描述符列表，但所有需要临时
  /// 解析飞牛原生回调的入口仍通过此处取得实例，避免调用方散落具体工厂。
  static MediaBackend createLegacyFeiniu(NasProvider nas) {
    return FeiniuMediaBackend(FeiniuApi(nas));
  }

  static MediaBackendDescriptor? descriptorFor(MediaBackendKind kind) {
    for (final descriptor in serverDescriptors) {
      if (descriptor.kind == kind) return descriptor;
    }
    return null;
  }

  static MediaBackendDescriptor requireDescriptor(MediaBackendKind kind) {
    final descriptor = descriptorFor(kind);
    if (descriptor == null) {
      throw UnsupportedError('Unsupported server backend: ${kind.name}');
    }
    return descriptor;
  }
}
