import 'emby_api.dart';

/// Jellyfin API 客户端。
///
/// Jellyfin 是 Emby 3.5 的开源 fork，REST 形状与 MediaBrowser 家族内核 [EmbyApi] 同形：
/// 认证 `/Users/AuthenticateByName`、条目 `/Users/{id}/Items`、季集 `/Shows/{id}/Seasons`、
/// 直链 `/Videos/{id}/stream?Static=true`、HLS 转码 `/Videos/{id}/master.m3u8`、进度回写
/// `/Sessions/Playing/*`、收藏 / 已看、外挂字幕 `Stream.{ext}`、`api_key` 查询串自鉴权均
/// 一致，整体继承内核，只覆写风味差异：
///
/// - **鉴权头**：Jellyfin 10.8+ 的规范 `MediaBrowser` 授权头参数值带引号（兼容头名
///   `X-Emby-Authorization` 仍被接受，无需换头名）。
/// - **BIF 预览缩略图**（`/Videos/{id}/index.bif`）是 Emby 专有端点，Jellyfin 返回 404 →
///   原生壳自动回退章节图（章节图走通用 `/Items/{id}/Images/Chapter/{index}` 路由，
///   Jellyfin 侧开启「章节图提取」任务后同样可用），无需覆写。
class JellyfinApi extends EmbyApi {
  JellyfinApi({
    super.dio,
    super.clientName,
    super.deviceName,
    super.deviceId,
    super.clientVersion,
    super.entryTokenProvider,
  });

  /// Jellyfin 继续观看通过用户条目筛选获取，不使用 Emby 专用的 `/Items/Resume`。
  @override
  Future<List<Map<String, Object?>>> getResumeItems({
    required String serverUrl,
    required String userId,
    required String accessToken,
    int limit = 20,
    String fields = '',
  }) {
    return getItems(
      serverUrl: serverUrl,
      userId: userId,
      accessToken: accessToken,
      limit: limit,
      isResumable: true,
      recursive: true,
      includeItemTypes: 'Movie,Episode',
      fields: fields,
      sortBy: 'DatePlayed',
      sortOrder: 'Descending',
    );
  }

  @override
  String get authorizationHeaderValue =>
      'MediaBrowser Client="$clientName", Device="$deviceName", '
      'DeviceId="$deviceId", Version="$clientVersion"';
}
