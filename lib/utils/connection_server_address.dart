import '../api/emby_api.dart';
import 'api_url_helper.dart';

/// 统一连接页的服务器地址输入规则。
///
/// 连接页之外的 API 工具仍保留各自历史默认协议；这里只将用户输入的裸地址
/// 默认补成 HTTPS，并按服务器族需要清理 Emby Web 客户端路径。
String normalizeConnectionServerAddress(
  String raw, {
  bool stripEmbyWebClientPath = false,
}) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';

  final hasExplicitScheme = RegExp(
    r'^https?://',
    caseSensitive: false,
  ).hasMatch(trimmed);
  final candidate = hasExplicitScheme ? trimmed : 'https://$trimmed';
  final normalized = stripEmbyWebClientPath
      ? EmbyApi.normalizeServerUrl(candidate)
      : ApiUrlHelper.normalizeBaseUrl(candidate);
  final uri = Uri.tryParse(normalized);

  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme.toLowerCase() != 'http' &&
          uri.scheme.toLowerCase() != 'https')) {
    return '';
  }
  return normalized;
}
