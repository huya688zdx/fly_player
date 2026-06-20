/// 统一描述一张媒体图片：URL 加上访问所需的鉴权 header。
///
/// 飞牛与未来 Emby 的图片鉴权方式不同，前端只消费这个公共结构，
/// 不直接拼接后端私有的 token 或路径。
class MediaImageRef {
  final String url;
  final Map<String, String> headers;

  static const empty = MediaImageRef(url: '');

  const MediaImageRef({required this.url, this.headers = const {}});

  bool get isEmpty => url.trim().isEmpty;
  bool get isNotEmpty => !isEmpty;
}
