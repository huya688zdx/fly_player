import '../media_backend/media_image_ref.dart';
import '../utils/api_url_helper.dart';
import '../utils/nas_image_headers.dart';

/// 一组解析完成的图片候选 + 访问 header。
///
/// 详情页的 `Image.network` 既要 URL 候选(主图失败回退次图),也要鉴权 header。
/// 飞牛走 NAS token header,Emby 走 URL 内的 `api_key`(header 为空),这里统一表达。
class DetailArtwork {
  final List<String> urls;
  final Map<String, String> headers;

  const DetailArtwork({required this.urls, this.headers = const {}});

  static const empty = DetailArtwork(urls: <String>[]);

  bool get isEmpty => urls.isEmpty;
  bool get isNotEmpty => urls.isNotEmpty;
}

/// 后端中立的详情页图源解析器(纯 UI helper:不碰 BuildContext / 导航 / 播放句柄)。
///
/// 把"一张 [MediaImageRef] 或飞牛相对路径 → 可直接喂 `Image.network` 的 URL 候选 + header"
/// 的判定收成单一入口,让飞牛 / Emby 成功分支最终共用同一套渲染:
/// - **完整 http(s) 直链**(Emby 自带 `api_key` 的图):直接用,header 取 ref 自带(通常为空)。
/// - **飞牛相对路径**:走 [ApiUrlHelper.imageCandidates] 拼候选 + [nasImageHeaders] 加 NAS token。
///
/// 行为与旧页内联逻辑逐字段等价:`resolvePath(rawPath)` ≡ 旧 `imageCandidates(baseUrl, rawPath)`
/// + `nasImageHeaders(token)`;`resolveRef(embyRef)` ≡ 旧 `_neutralHeroUrls` 的完整直链。
class DetailArtworkResolver {
  /// 飞牛 NAS 基址,用于把相对路径拼成绝对 URL。Emby 直链不依赖它。
  final String baseUrl;

  /// 飞牛 NAS token,用于相对路径图的鉴权 header。Emby 直链不依赖它。
  final String token;

  const DetailArtworkResolver({required this.baseUrl, required this.token});

  /// 解析一张中立图引用。完整直链直接用,否则按飞牛相对路径拼接。
  DetailArtwork resolveRef(
    MediaImageRef ref, {
    int width = 900,
    bool preferDirectPath = false,
  }) {
    final url = ref.url.trim();
    if (url.isEmpty) return DetailArtwork.empty;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return DetailArtwork(urls: <String>[url], headers: ref.headers);
    }
    return resolvePath(url, width: width, preferDirectPath: preferDirectPath);
  }

  /// 解析飞牛相对路径(等价旧 `imageCandidates` + `nasImageHeaders` 调用)。
  DetailArtwork resolvePath(
    String path, {
    int width = 900,
    bool preferDirectPath = false,
  }) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return DetailArtwork.empty;
    final urls = ApiUrlHelper.imageCandidates(
      baseUrl,
      trimmed,
      width: width,
      preferDirectPath: preferDirectPath,
    );
    if (urls.isEmpty) return DetailArtwork.empty;
    return DetailArtwork(
      urls: urls,
      headers: nasImageHeaders(token, url: urls.first),
    );
  }

  /// 顺序解析多张图引用并合并候选(背景 hero:背景图优先、退海报)。
  /// header 取第一张非空的(同后端 header 一致)。
  DetailArtwork resolveRefs(List<MediaImageRef> refs, {int width = 900}) {
    final urls = <String>[];
    var headers = const <String, String>{};
    for (final ref in refs) {
      final artwork = resolveRef(ref, width: width);
      if (artwork.isEmpty) continue;
      urls.addAll(artwork.urls);
      if (headers.isEmpty && artwork.headers.isNotEmpty) {
        headers = artwork.headers;
      }
    }
    return DetailArtwork(urls: urls, headers: headers);
  }
}
