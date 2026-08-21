import 'media_image_ref.dart';

/// 首页媒体库入口（例如电影库、剧集库、目录库）的最小公共描述。
class MediaCatalog {
  final String id;
  final String title;
  final String type;
  final MediaImageRef primaryImage;

  /// 入口封面图集合。飞牛首页连续展示前 3 张；其它后端按各自布局选择主图，
  /// 为空时回退 [primaryImage]。属于前端展示概念，各后端在适配层填充。
  final List<MediaImageRef> posters;

  const MediaCatalog({
    required this.id,
    required this.title,
    required this.type,
    required this.primaryImage,
    this.posters = const <MediaImageRef>[],
  });
}
