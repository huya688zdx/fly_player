import 'media_backend_kind.dart';

/// 首页媒体库入口可用的展示能力。
enum HomeCatalogPresentation {
  /// 飞牛官方式多海报入口。
  officialCollage,

  /// Emby 的横幅影院入口。
  cinematicBackdrop,

  /// Jellyfin 的清晰图库入口。
  clearGallery,
}

extension HomeCatalogPresentationForBackend on MediaBackendKind {
  HomeCatalogPresentation get homeCatalogPresentation => switch (this) {
    MediaBackendKind.feiniu => HomeCatalogPresentation.officialCollage,
    MediaBackendKind.emby => HomeCatalogPresentation.cinematicBackdrop,
    MediaBackendKind.jellyfin => HomeCatalogPresentation.clearGallery,
  };
}
