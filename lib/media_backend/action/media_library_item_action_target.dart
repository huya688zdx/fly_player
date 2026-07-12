import '../../models/media_library_item.dart';
import 'media_item_action_target.dart';

/// 飞牛 `MediaLibraryItem` → 公共 [MediaItemActionTarget] 适配。
///
/// 转换逻辑集中在此适配层，使公共 target 模型不反依赖飞牛模型。仍持有飞牛列表模型的
/// 页面（收藏页 / 人物作品 / 剧详情季 / 季详情集 / 首页继续观看）调本扩展喂操作面板，
/// 待这些入口后续迁到公共卡片模型后即可移除。
extension MediaLibraryItemActionTargetX on MediaLibraryItem {
  MediaItemActionTarget toActionTarget() {
    final tv = tvTitle.trim();
    final base = tv.isNotEmpty ? tv : title.trim();
    return MediaItemActionTarget(
      id: guid,
      baseTitle: base,
      type: type,
      watched: watched == 1,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      seriesId: ancestorGuid,
      imageUrl: poster,
    );
  }
}
