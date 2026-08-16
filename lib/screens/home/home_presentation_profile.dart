import '../../media_backend/media_backend_kind.dart';

/// 首页可展示的内容区块。
enum HomeSectionKind {
  catalogs,
  continueWatching,
  summary,
  nextUp,
  latest,
  catalogPreviews,
}

/// 媒体库入口采用的图片布局。
enum HomeCatalogStyle { posterMosaic, landscapeArtwork, artworkGrid }

/// 按后端能力确定的首页展示配置。
class HomePresentationProfile {
  HomePresentationProfile({
    required List<HomeSectionKind> sectionOrder,
    required this.catalogStyle,
  }) : sectionOrder = List<HomeSectionKind>.unmodifiable(sectionOrder);

  /// 首页区块从上到下的展示顺序。
  final List<HomeSectionKind> sectionOrder;

  /// 媒体库入口的图片布局。
  final HomeCatalogStyle catalogStyle;

  /// 返回指定后端对应的首页展示配置。
  static HomePresentationProfile forKind(MediaBackendKind kind) {
    return switch (kind) {
      MediaBackendKind.feiniu => HomePresentationProfile(
        sectionOrder: const <HomeSectionKind>[
          HomeSectionKind.catalogs,
          HomeSectionKind.continueWatching,
          HomeSectionKind.summary,
          HomeSectionKind.catalogPreviews,
        ],
        catalogStyle: HomeCatalogStyle.posterMosaic,
      ),
      MediaBackendKind.emby => HomePresentationProfile(
        sectionOrder: const <HomeSectionKind>[
          HomeSectionKind.continueWatching,
          HomeSectionKind.catalogs,
          HomeSectionKind.nextUp,
          HomeSectionKind.latest,
          HomeSectionKind.catalogPreviews,
        ],
        catalogStyle: HomeCatalogStyle.landscapeArtwork,
      ),
      MediaBackendKind.jellyfin => HomePresentationProfile(
        sectionOrder: const <HomeSectionKind>[
          HomeSectionKind.continueWatching,
          HomeSectionKind.nextUp,
          HomeSectionKind.latest,
          HomeSectionKind.catalogs,
          HomeSectionKind.catalogPreviews,
        ],
        catalogStyle: HomeCatalogStyle.artworkGrid,
      ),
    };
  }
}
