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

  const MediaBackendCapabilities({
    required this.kind,
    required this.supportsDownloadTasks,
    required this.supportsFnConnect,
    required this.supportsIntroOutroConfig,
  });

  /// 飞牛后端当前能力预设：NAS 专属功能全部开启。
  const MediaBackendCapabilities.feiniu()
    : kind = MediaBackendKind.feiniu,
      supportsDownloadTasks = true,
      supportsFnConnect = true,
      supportsIntroOutroConfig = true;
}
