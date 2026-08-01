import '../media_backend/media_image_ref.dart';
import '../media_backend/media_image_request.dart';
import '../media_backend/media_backend_kind.dart';
import '../utils/api_url_helper.dart';
import '../utils/nas_image_headers.dart';

export '../media_backend/media_image_request.dart';

typedef MediaImageCredentials = ({
  String token,
  String accessCode,
  String baseUrl,
});

/// 根据当前媒体后端隔离图片凭据；服务器族不得读取残留飞牛会话。
MediaImageCredentials mediaImageCredentialsForBackend({
  required MediaBackendKind backendKind,
  required String token,
  required String accessCode,
  required String baseUrl,
}) {
  if (backendKind.isServerFamily) {
    return (token: '', accessCode: '', baseUrl: '');
  }
  return (token: token, accessCode: accessCode, baseUrl: baseUrl);
}

/// 历史命名兼容别名：详情页早期把"URL 候选 + header"叫 DetailArtwork，
/// 现统一为后端中立的 [MediaImageRequest]（多了 selfAuthenticated 标志）。
typedef DetailArtwork = MediaImageRequest;

/// URL 是否自带凭据（Emby `?api_key=` 直链）。**全库唯一**允许做该子串
/// 判定的位置：组件层一律消费 [MediaImageRequest.selfAuthenticated]，
/// 后端 mapper 走 [MediaImageRef.selfAuthenticated] 显式标注；这里仅为
/// 旧 URL 字符串管线（MediaLibraryItem 等未携带标志的链路）兜底。
bool _embedsSelfAuthCredential(String url) => url.contains('api_key=');

/// 把“已拼好的完整 URL 候选 + NAS 凭据”包装成 [MediaImageRequest]。
///
/// 旧组件层 URL 候选入口：
/// - URL 自带 `api_key` 时视为自鉴权直链，不得附加 NAS 凭据；
/// - 其它候选统一使用 [nasImageHeaders]；访问码仅在候选与飞牛基址严格同源时附加。
///   候选由同一后端
///   产出，取首个候选计算 headers 与自鉴权状态。
MediaImageRequest mediaImageRequestForUrls(
  List<String> urls, {
  required String token,
  required String accessCode,
  required String baseUrl,
}) {
  if (urls.isEmpty) return MediaImageRequest.empty;
  final selfAuthenticated = _embedsSelfAuthCredential(urls.first);
  return MediaImageRequest(
    urls: urls,
    headers: selfAuthenticated
        ? const <String, String>{}
        : nasImageHeaders(
            token,
            url: urls.first,
            accessCode: accessCode,
            baseUrl: baseUrl,
          ),
    selfAuthenticated: selfAuthenticated,
  );
}

/// 优先使用后端已产出的中立图片请求；仅旧字符串链路缺少请求时，
/// 才用当前后端对应的 NAS 凭据包装候选 URL。
MediaImageRequest preferPreservedImageRequest({
  required MediaImageRequest? preserved,
  required List<String> fallbackUrls,
  required String fallbackToken,
  required String fallbackAccessCode,
  required String fallbackBaseUrl,
}) {
  if (preserved != null && preserved.isNotEmpty) return preserved;
  return mediaImageRequestForUrls(
    fallbackUrls,
    token: fallbackToken,
    accessCode: fallbackAccessCode,
    baseUrl: fallbackBaseUrl,
  );
}

/// 后端中立的详情页图源解析器(纯 UI helper:不碰 BuildContext / 导航 / 播放句柄)。
///
/// 把"一张 [MediaImageRef] 或飞牛相对路径 → 可直接喂 `Image.network` 的 URL 候选 + header"
/// 的判定收成单一入口,让飞牛 / Emby 成功分支最终共用同一套渲染:
/// - **完整 http(s) 直链**(Emby 自带 `api_key` 的图):直接用,header 取 ref 自带(通常为空),
///   自鉴权标志优先取 ref 显式标注、旧字符串链路回退子串兜底。
/// - **飞牛相对路径**:走 [ApiUrlHelper.imageCandidates] 拼候选 + [nasImageHeaders] 加同源 NAS 凭据。
///
/// 行为与旧页内联逻辑逐字段等价:`resolvePath(rawPath)` ≡ 旧 `imageCandidates(baseUrl, rawPath)`
/// + `nasImageHeaders(token)`;`resolveRef(embyRef)` ≡ 旧 `_neutralHeroUrls` 的完整直链。
class DetailArtworkResolver {
  /// 飞牛 NAS 基址,用于把相对路径拼成绝对 URL。Emby 直链不依赖它。
  final String baseUrl;

  /// 飞牛 NAS token,用于相对路径图的鉴权 header。Emby 直链不依赖它。
  final String token;

  /// 飞牛 NAS 访问码，仅用于与 [baseUrl] 严格同源的图片请求。
  final String accessCode;

  const DetailArtworkResolver({
    required this.baseUrl,
    required this.token,
    required this.accessCode,
  });

  /// 解析一张中立图引用。完整直链直接用,否则按飞牛相对路径拼接。
  MediaImageRequest resolveRef(
    MediaImageRef ref, {
    int width = 900,
    bool preferDirectPath = false,
  }) {
    final url = ref.url.trim();
    if (url.isEmpty) return MediaImageRequest.empty;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return MediaImageRequest(
        urls: <String>[url],
        headers: ref.headers,
        selfAuthenticated:
            ref.selfAuthenticated || _embedsSelfAuthCredential(url),
      );
    }
    return resolvePath(url, width: width, preferDirectPath: preferDirectPath);
  }

  /// 解析飞牛相对路径(等价旧 `imageCandidates` + `nasImageHeaders` 调用)。
  MediaImageRequest resolvePath(
    String path, {
    int width = 900,
    bool preferDirectPath = false,
  }) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return MediaImageRequest.empty;
    final urls = ApiUrlHelper.imageCandidates(
      baseUrl,
      trimmed,
      width: width,
      preferDirectPath: preferDirectPath,
    );
    if (urls.isEmpty) return MediaImageRequest.empty;
    return MediaImageRequest(
      urls: urls,
      headers: nasImageHeaders(
        token,
        url: urls.first,
        accessCode: accessCode,
        baseUrl: baseUrl,
      ),
    );
  }

  /// 把"已拼好的完整 URL 候选"包装成请求（用本 resolver 的 NAS 凭据生成 header）。
  /// 语义同顶层 [mediaImageRequestForUrls]，供已持有 resolver 的调用方少传参。
  MediaImageRequest resolveUrls(List<String> urls) {
    return mediaImageRequestForUrls(
      urls,
      token: token,
      accessCode: accessCode,
      baseUrl: baseUrl,
    );
  }

  /// 顺序解析多张图引用并合并候选(背景 hero:背景图优先、退海报)。
  /// header 取第一张非空的(同后端 header 一致);自鉴权标志按候选取或。
  MediaImageRequest resolveRefs(List<MediaImageRef> refs, {int width = 900}) {
    final urls = <String>[];
    var headers = const <String, String>{};
    var selfAuthenticated = false;
    for (final ref in refs) {
      final artwork = resolveRef(ref, width: width);
      if (artwork.isEmpty) continue;
      urls.addAll(artwork.urls);
      if (headers.isEmpty && artwork.headers.isNotEmpty) {
        headers = artwork.headers;
      }
      selfAuthenticated = selfAuthenticated || artwork.selfAuthenticated;
    }
    return MediaImageRequest(
      urls: urls,
      headers: headers,
      selfAuthenticated: selfAuthenticated,
    );
  }
}
