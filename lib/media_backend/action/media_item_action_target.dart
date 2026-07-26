import '../media_item_card.dart';

/// 条目快捷操作菜单（长按 / 详情）的后端中立入参。
///
/// 只承载操作面板和标题真正需要的字段，不照搬飞牛 `MediaLibraryItem` 或 Emby 原始
/// 结构。列表 / 搜索 / 收藏 / 合集 / 人物等入口把各自模型转成本 target 再喂面板，使
/// `MediaItemActionSheetController` 与具体后端模型解耦——新后端只需产出 target，无需让
/// UI 控制器认识它的私有模型。
class MediaItemActionTarget {
  /// 条目唯一标识（飞牛 guid / Emby ItemId）。
  final String id;

  /// 已解析的基础标题（系列名优先），用于面板标题《...》。
  final String baseTitle;

  /// 条目类型（movie / series / season / episode / person ...）。
  final String type;

  /// 已看态，使用后端中立的布尔值。
  final bool watched;

  /// 收藏态。null 表示未知，由面板按需向后端预取。
  final bool? favorite;

  final int seasonNumber;
  final int episodeNumber;

  /// 单集所属系列 guid（用于后续导航；批次 1 收藏/已看不依赖）。
  final String seriesId;

  /// 主图 URL（完整直链或后端可解析路径）。
  final String imageUrl;

  const MediaItemActionTarget({
    required this.id,
    required this.baseTitle,
    required this.type,
    this.watched = false,
    this.favorite,
    this.seasonNumber = 0,
    this.episodeNumber = 0,
    this.seriesId = '',
    this.imageUrl = '',
  });

  bool get isWatched => watched;

  /// 由公共卡片模型构造，供搜索 / 分类 / 首页等已走 [MediaItemCard] 的入口直接使用。
  factory MediaItemActionTarget.fromCard(MediaItemCard card) {
    final secondary = card.secondaryTitle.trim();
    final base = secondary.isNotEmpty ? secondary : card.title;
    return MediaItemActionTarget(
      id: card.id,
      baseTitle: base,
      type: card.type,
      watched: card.watched,
      seasonNumber: card.seasonNumber,
      episodeNumber: card.episodeNumber,
      seriesId: card.seriesId,
      imageUrl: card.primaryImage.url,
    );
  }
}
