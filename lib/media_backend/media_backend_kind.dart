/// 公共媒体前端支持的后端类型。
enum MediaBackendKind { feiniu, emby, jellyfin }

extension MediaBackendKindX on MediaBackendKind {
  /// 是否服务器族后端（走 MediaBackend 公共路径；飞牛为遗留族）。
  bool get isServerFamily => this != MediaBackendKind.feiniu;
}
