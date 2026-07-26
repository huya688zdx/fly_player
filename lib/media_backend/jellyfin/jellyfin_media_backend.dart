import '../../api/jellyfin_api.dart';
import '../emby/emby_media_backend.dart';
import '../media_backend_capabilities.dart';
import '../media_backend_kind.dart';

/// Jellyfin 媒体后端适配器。
///
/// Jellyfin 与 Emby 同属 MediaBrowser 家族（fork 同源），BaseItemDto 形状与端点一致，
/// 查询 / 映射 / 播放装配整体复用 [EmbyMediaBackend]（含 Emby mappers 与直链播放桥接器）；
/// 差异只有两处：能力声明的 kind、API 客户端风味（[JellyfinApi] 的引号鉴权头）。
///
/// 已知的行为性差异均由现有回退兜住，无需覆写：
/// - BIF 预览缩略图端点 Jellyfin 404 → 原生壳回退章节图；
/// - 章节图 / 图片 / 字幕 / 会话端点同形直用。
class JellyfinMediaBackend extends EmbyMediaBackend {
  JellyfinMediaBackend({
    required JellyfinApi super.api,
    required super.connection,
  });

  @override
  MediaBackendCapabilities get capabilities =>
      const MediaBackendCapabilities.server(kind: MediaBackendKind.jellyfin);
}
