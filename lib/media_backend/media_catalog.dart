import 'media_image_ref.dart';

/// 首页媒体库入口（例如电影库、剧集库、目录库）的最小公共描述。
class MediaCatalog {
  final String id;
  final String title;
  final String type;
  final MediaImageRef primaryImage;

  const MediaCatalog({
    required this.id,
    required this.title,
    required this.type,
    required this.primaryImage,
  });
}
