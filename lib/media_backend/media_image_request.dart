/// 后端中立的"一次图片加载请求"：URL 候选 + 鉴权 header + 自鉴权标志。
///
/// 组件层（海报卡/背景图/头像等）只消费本结构，不再感知任何后端私有的
/// 鉴权方式（飞牛 NAS token header、Emby URL 内 `api_key` 等）。产出规则收敛在
/// `lib/ui/detail_artwork_resolver.dart` 的单一入口，组件不得自行嗅探 URL。
class MediaImageRequest {
  /// 图片 URL 候选（主图失败按序回退次图）。
  final List<String> urls;

  /// 访问所有候选所需的鉴权 header（候选同源、同一份 header）。
  final Map<String, String> headers;

  /// URL 自带凭据（如 Emby 的 `?api_key=`）：不依赖 header 也可加载。
  final bool selfAuthenticated;

  const MediaImageRequest({
    required this.urls,
    this.headers = const {},
    this.selfAuthenticated = false,
  });

  static const empty = MediaImageRequest(urls: <String>[]);

  bool get isEmpty => urls.isEmpty;
  bool get isNotEmpty => urls.isNotEmpty;

  /// 能否发起加载：有候选且（带 header 鉴权 或 URL 自鉴权）。
  /// 与旧组件层判定等价：`urls 非空 && !(token 为空 && 非 api_key 直链)`
  /// —— token 非空 ⟺ headers 非空（nasImageHeaders 语义）。
  bool get canLoad =>
      urls.isNotEmpty && (headers.isNotEmpty || selfAuthenticated);
}
