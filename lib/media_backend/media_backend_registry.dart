import '../api/emby_api.dart';
import '../api/feiniu_api.dart';
import '../api/jellyfin_api.dart';
import '../providers/nas_provider.dart';
import '../services/play_stats/play_stats_metadata_gateway.dart';
import 'feiniu/feiniu_media_backend.dart';
import 'feiniu/feiniu_play_stats_gateway.dart';
import 'emby/emby_media_backend.dart';
import 'jellyfin/jellyfin_media_backend.dart';
import 'media_backend.dart';
import 'media_backend_kind.dart';
import 'session/media_backend_connection.dart';

typedef MediaBackendFactory =
    MediaBackend Function(
      MediaBackendConnection connection, {
      String Function()? entryTokenProvider,
    });

/// MediaBrowser 家族 API 客户端工厂（[EmbyApi] 为家族内核，Jellyfin 为其风味子类）。
/// 登录页按当前选中的服务器族后端构造对应客户端做认证。
typedef MediaBrowserApiFactory =
    EmbyApi Function({String Function()? entryTokenProvider});

/// 后端类型的静态描述符。
///
/// 新增服务器族后端时，应在 [MediaBackendRegistry.serverDescriptors] 登记一条；
/// 页面和 provider 只消费描述符，不再散落具体后端判断。
class MediaBackendDescriptor {
  const MediaBackendDescriptor({
    required this.kind,
    required this.displayName,
    required this.badgeText,
    required this.logoAsset,
    required this.serverUrlExample,
    required this.createApiClient,
    required this.createBackend,
  });

  final MediaBackendKind kind;

  /// 品牌名（Emby / Jellyfin），不走 l10n。
  final String displayName;
  final String badgeText;

  /// 登录页后端选择条上的品牌 logo 资源。
  final String logoAsset;

  /// 登录页服务器地址输入框的示例地址（拼进 l10n 的「例如：{url}」文案）。
  final String serverUrlExample;

  final MediaBrowserApiFactory createApiClient;
  final MediaBackendFactory createBackend;
}

class MediaBackendRegistry {
  const MediaBackendRegistry._();

  static final MediaBackendDescriptor emby = MediaBackendDescriptor(
    kind: MediaBackendKind.emby,
    displayName: 'Emby',
    badgeText: 'E',
    logoAsset: 'lib/img/Emby_logo.png',
    serverUrlExample: 'https://emby.example.com',
    createApiClient: ({String Function()? entryTokenProvider}) =>
        EmbyApi(entryTokenProvider: entryTokenProvider),
    createBackend:
        (
          MediaBackendConnection connection, {
          String Function()? entryTokenProvider,
        }) => EmbyMediaBackend(
          api: EmbyApi(entryTokenProvider: entryTokenProvider),
          connection: connection,
        ),
  );

  static final MediaBackendDescriptor jellyfin = MediaBackendDescriptor(
    kind: MediaBackendKind.jellyfin,
    displayName: 'Jellyfin',
    badgeText: 'JF',
    logoAsset: 'lib/img/jellyfin_logo.png',
    serverUrlExample: 'https://jellyfin.example.com',
    createApiClient: ({String Function()? entryTokenProvider}) =>
        JellyfinApi(entryTokenProvider: entryTokenProvider),
    createBackend:
        (
          MediaBackendConnection connection, {
          String Function()? entryTokenProvider,
        }) => JellyfinMediaBackend(
          api: JellyfinApi(entryTokenProvider: entryTokenProvider),
          connection: connection,
        ),
  );

  static List<MediaBackendDescriptor> get serverDescriptors =>
      <MediaBackendDescriptor>[emby, jellyfin];

  /// 创建遗留飞牛后端。遗留族不进入服务器族描述符列表，但所有需要临时
  /// 解析飞牛原生回调的入口仍通过此处取得实例，避免调用方散落具体工厂。
  static MediaBackend createLegacyFeiniu(NasProvider nas) {
    return FeiniuMediaBackend(FeiniuApi(nas));
  }

  /// 创建播放统计所需的元数据网关；未连接后端时返回 null。
  ///
  /// 目前只有遗留飞牛后端在 Flutter 侧产出播放统计（服务器族走原生上报），
  /// 所以这里直接给飞牛实现；后续若有别的后端接入统计，在此按连接态分流即可，
  /// 统计页与回填服务不必改动。
  static PlayStatsMetadataGateway? createPlayStatsMetadataGateway(
    NasProvider nas,
  ) {
    if (!nas.isConfigured) {
      return null;
    }
    return FeiniuPlayStatsGateway(FeiniuApi(nas));
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
