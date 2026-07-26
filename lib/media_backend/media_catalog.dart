import 'media_image_ref.dart';

/// 首页媒体库入口（例如电影库、剧集库、目录库）的最小公共描述。
class MediaCatalog {
  final String id;
  final String title;
  final String type;
  final MediaImageRef primaryImage;

  /// 入口封面图集合。首页分类条会叠展示前若干张（飞牛主机上最多 2 张），
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
