import '../../media_backend/media_backend_kind.dart';
import '../../models/media_library_item.dart';

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
