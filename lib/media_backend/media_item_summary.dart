import 'media_image_ref.dart';

/// 卡片 / 列表 / 搜索结果需要的最小条目信息。
///
/// 只表达前端真正要展示的字段，不照搬飞牛或 Emby 的原始结构。
class MediaItemSummary {
  final String id;
  final String title;
  final String type;
  final MediaImageRef primaryImage;
  final MediaImageRef backdropImage;
  final int durationSeconds;
  final bool watched;

  const MediaItemSummary({
    required this.id,
    required this.title,
    required this.type,
    required this.primaryImage,
    required this.backdropImage,
    required this.durationSeconds,
    required this.watched,
  });

  String get displayTitle {
    final value = title.trim();
    return value.isEmpty ? 'Unknown' : value;
  }
}
