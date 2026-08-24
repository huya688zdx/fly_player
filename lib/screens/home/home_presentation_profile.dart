import '../../media_backend/media_backend_capabilities.dart';

/// 首页可展示的内容区块。
enum HomeSectionKind {
  catalogs,
  continueWatching,
  summary,
  nextUp,
  latest,
  catalogPreviews,
}

/// 按后端能力确定的首页展示配置。
class HomePresentationProfile {
  HomePresentationProfile({required List<HomeSectionKind> sectionOrder})
    : sectionOrder = List<HomeSectionKind>.unmodifiable(sectionOrder);

  /// 首页区块从上到下的展示顺序。
  final List<HomeSectionKind> sectionOrder;

  /// 返回指定后端能力对应的首页展示配置。
  static HomePresentationProfile forCapabilities(
    MediaBackendCapabilities capabilities,
  ) {
    return HomePresentationProfile(
      sectionOrder: <HomeSectionKind>[
        HomeSectionKind.catalogs,
        HomeSectionKind.continueWatching,
        HomeSectionKind.nextUp,
        if (capabilities.supportsHomeLatestItems) HomeSectionKind.latest,
        HomeSectionKind.summary,
        HomeSectionKind.catalogPreviews,
      ],
    );
  }
}

/// 按平台配置顺序筛出当前真正有内容的首页区块。
List<HomeSectionKind> visibleHomeSections({
  required HomePresentationProfile profile,
  required bool hasCatalogs,
  required bool hasContinueWatching,
  required bool hasSummary,
  required bool hasNextUp,
  required bool hasLatest,
}) {
  bool hasContent(HomeSectionKind section) => switch (section) {
    HomeSectionKind.catalogs || HomeSectionKind.catalogPreviews => hasCatalogs,
    HomeSectionKind.continueWatching => hasContinueWatching,
    HomeSectionKind.summary => hasSummary,
    HomeSectionKind.nextUp => hasNextUp,
    HomeSectionKind.latest => hasLatest,
  };

  return profile.sectionOrder.where(hasContent).toList(growable: false);
}
