import '../../media_backend/media_backend_kind.dart';

/// 海报浏览素材缓存的会话边界。
///
/// 凭据只取进程内 hash，避免把 token 原文写入缓存键、日志或诊断输出。
String buildPosterBrowseSessionKey({
  required Object backendKind,
  required String baseUrl,
  required String token,
}) {
  return '${backendKind.toString()}|${baseUrl.trim()}|${token.hashCode}';
}

String buildPosterBrowseBackendSessionKey({
  required MediaBackendKind backendKind,
  required String nasBaseUrl,
  required String nasToken,
  String serverBaseUrl = '',
  String serverToken = '',
}) {
  return buildPosterBrowseSessionKey(
    backendKind: backendKind,
    baseUrl: backendKind.isServerFamily ? serverBaseUrl : nasBaseUrl,
    token: backendKind.isServerFamily ? serverToken : nasToken,
  );
}
