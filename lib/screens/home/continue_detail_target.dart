import '../../media_backend/media_backend_kind.dart';
import '../../models/media_library_item.dart';

class ContinueSeasonDetailTarget {
  const ContinueSeasonDetailTarget({
    required this.parentGuid,
    required this.seriesTitle,
    required this.backdropPath,
    required this.seasonItem,
    required this.initialEpisodeGuid,
  });

  final String parentGuid;
  final String seriesTitle;
  final String backdropPath;
  final MediaLibraryItem seasonItem;
  final String initialEpisodeGuid;
}

ContinueSeasonDetailTarget? continueSeasonDetailTarget(MediaLibraryItem item) {
  if (item.type.trim().toLowerCase() != 'episode') return null;

  final seasonGuid = item.parentGuid.trim();
  final seriesGuid = item.ancestorGuid.trim();
  if (seasonGuid.isEmpty || seriesGuid.isEmpty || item.guid.trim().isEmpty) {
    return null;
  }

  final seriesTitle = item.ancestorName.trim().isNotEmpty
      ? item.ancestorName.trim()
      : item.tvTitle.trim().isNotEmpty
      ? item.tvTitle.trim()
      : item.title;
  final seasonTitle = item.parentTitle.trim().isNotEmpty
      ? item.parentTitle.trim()
      : seriesTitle;
  return ContinueSeasonDetailTarget(
    parentGuid: seriesGuid,
    seriesTitle: seriesTitle,
    backdropPath: item.backdropUrl,
    seasonItem: item.copyWith(
      guid: seasonGuid,
      title: seasonTitle,
      tvTitle: seriesTitle,
      type: 'season',
      episodeNumber: 0,
      parentGuid: seriesGuid,
      parentTitle: seriesTitle,
      ancestorGuid: seriesGuid,
      ancestorName: seriesTitle,
    ),
    initialEpisodeGuid: item.guid.trim(),
  );
}

/// 解析首页续看卡应打开的详情条目。
///
/// 服务器族的单集详情不含选集上下文，因此在有系列 ID 时改为
/// 打开系列详情；飞牛和无法解析系列的条目保持原行为。
MediaLibraryItem continueDetailTarget(
  MediaLibraryItem item,
  MediaBackendKind backendKind,
) {
  if (!backendKind.isServerFamily ||
      item.type.trim().toLowerCase() != 'episode') {
    return item;
  }

  final seriesGuid = item.ancestorGuid.trim();
  if (seriesGuid.isEmpty) return item;

  final seriesTitle = item.ancestorName.trim().isNotEmpty
      ? item.ancestorName.trim()
      : item.tvTitle.trim().isNotEmpty
      ? item.tvTitle.trim()
      : item.title;
  return item.copyWith(
    guid: seriesGuid,
    title: seriesTitle,
    tvTitle: seriesTitle,
    type: 'tv',
  );
}
