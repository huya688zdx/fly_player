import 'media_backend_kind.dart';

/// 描述某个媒体后端支持哪些前端能力。
///
/// 飞牛专属能力（下载任务、FN Connect、片头片尾配置）通过本类暴露，
/// 而不是塞进公共条目模型，避免公共模型泄漏后端私有概念。
class MediaBackendCapabilities {
  final MediaBackendKind kind;
  final bool supportsDownloadTasks;
  final bool supportsFnConnect;
  final bool supportsIntroOutroConfig;

  /// 是否支持「收藏 / 取消收藏」（详情页心形键）。决定该键是否可点。
  final bool supportsFavorite;

  /// 是否支持「标记已看 / 未看」（详情页已看键）。决定该键是否可点。
  final bool supportsWatched;

  /// 是否支持服务端转码会话重载（画质 / 音轨 / 字幕切换走服务端会话）。
  final bool supportsServerTranscodeSession;

  /// 是否在普通首页展示“最近添加”。
  ///
  /// 飞牛目前没有稳定的官方后端能力，先保留接口但关闭首页入口；服务器族开启。
  final bool supportsHomeLatestItems;

  const MediaBackendCapabilities({
    required this.kind,
    required this.supportsDownloadTasks,
    required this.supportsFnConnect,
    required this.supportsIntroOutroConfig,
    this.supportsFavorite = false,
    this.supportsWatched = false,
    this.supportsServerTranscodeSession = false,
    this.supportsHomeLatestItems = false,
  });

  /// 飞牛后端当前能力预设：NAS 专属功能全部开启。
  const MediaBackendCapabilities.feiniu()
    : kind = MediaBackendKind.feiniu,
      supportsDownloadTasks = true,
      supportsFnConnect = true,
      supportsIntroOutroConfig = true,
      supportsFavorite = true,
      supportsWatched = true,
      supportsServerTranscodeSession = false,
      supportsHomeLatestItems = false;

  /// 服务器族后端能力预设：关闭飞牛专属能力，保留公共收藏 / 已看能力。
  const MediaBackendCapabilities.server({
    required this.kind,
    this.supportsFavorite = true,
    this.supportsWatched = true,
    this.supportsServerTranscodeSession = false,
    this.supportsHomeLatestItems = true,
  }) : supportsDownloadTasks = false,
       supportsFnConnect = false,
       supportsIntroOutroConfig = false;

  /// 是否走飞牛遗留路径（下载 / FN Connect / PlayInfo / NAS 进度通道）。
  bool get usesLegacyFeiniuFlow => kind == MediaBackendKind.feiniu;
}
