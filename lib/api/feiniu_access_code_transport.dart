import 'dart:convert';

import 'package:dio/dio.dart';

/// 飞牛要求输入访问码时使用的错误标识。
const feiniuAccessCodeRequiredSentinel = 'feiniu_access_code_required';

/// 飞牛拒绝当前访问码时使用的错误标识。
const feiniuAccessCodeInvalidSentinel = 'feiniu_access_code_invalid';

/// 根据访问码构造飞牛服务所需的请求头。
Map<String, String> buildFeiniuAccessCodeHeaders(String accessCode) {
  final normalized = accessCode.trim();
  if (normalized.isEmpty) {
    return const <String, String>{};
  }
  return <String, String>{
    'x-access-code': base64Encode(utf8.encode(normalized)),
    'x-access-source': 'app',
  };
}

/// 判断 [url] 是否与 [baseUrl] 属于同一个 HTTP(S) 源。
bool isSameHttpOrigin(String baseUrl, String url) {
  final base = Uri.tryParse(baseUrl);
  final target = Uri.tryParse(url);
  if (base == null || target == null || !_isHttpUriWithHost(base)) {
    return false;
  }

  if (!target.hasScheme && !target.hasAuthority) {
    return true;
  }
  if (!_isHttpUriWithHost(target)) {
    return false;
  }

  return base.scheme.toLowerCase() == target.scheme.toLowerCase() &&
      base.host.toLowerCase() == target.host.toLowerCase() &&
      _effectivePort(base) == _effectivePort(target);
}

/// 仅为与飞牛服务同源的地址构造访问码请求头。
Map<String, String> buildFeiniuAccessCodeHeadersForUrl({
  required String accessCode,
  required String baseUrl,
  required String url,
}) {
  if (!isSameHttpOrigin(baseUrl, url)) {
    return const <String, String>{};
  }
  return buildFeiniuAccessCodeHeaders(accessCode);
}

/// 判断响应正文是否为飞牛的访问码挑战页。
bool isFeiniuAccessCodeChallengeHtml(Object? body) {
  if (body is! String) {
    return false;
  }
  final normalized = body.toLowerCase();
  return normalized.contains('access-code-input') &&
      normalized.contains('/access_code_verify');
}

/// 为 [dio] 安装飞牛访问码的请求与响应处理逻辑。
void installFeiniuAccessCodeInterceptor(
  Dio dio, {
  required String baseUrl,
  required String Function() accessCodeProvider,
}) {
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        _removeFeiniuAccessCodeHeaders(options.headers);
        final accessCodeHeaders = buildFeiniuAccessCodeHeadersForUrl(
          accessCode: accessCodeProvider(),
          baseUrl: baseUrl,
          url: options.uri.toString(),
        );
        options.headers.addAll(accessCodeHeaders);
        if (accessCodeHeaders.isNotEmpty) {
          options.followRedirects = false;
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        if (isSameHttpOrigin(
              baseUrl,
              _resolveFinalResponseUri(response).toString(),
            ) &&
            isFeiniuAccessCodeChallengeHtml(response.data)) {
          handler.reject(
            DioException(
              requestOptions: response.requestOptions,
              response: response,
              type: DioExceptionType.badResponse,
              message: feiniuAccessCodeRequiredSentinel,
            ),
          );
          return;
        }
        handler.next(response);
      },
      onError: (error, handler) {
        final response = error.response;
        if (response != null &&
            isSameHttpOrigin(
              baseUrl,
              _resolveFinalResponseUri(response).toString(),
            ) &&
            _isAccessCodeInvalidResponse(response)) {
          handler.next(
            DioException(
              requestOptions: error.requestOptions,
              response: error.response,
              type: error.type,
              error: error.error,
              stackTrace: error.stackTrace,
              message: feiniuAccessCodeInvalidSentinel,
            ),
          );
          return;
        }
        handler.next(error);
      },
    ),
  );
}

bool _isHttpUriWithHost(Uri? uri) {
  if (uri == null || uri.host.isEmpty) {
    return false;
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    return false;
  }
  try {
    if (!uri.hasPort) {
      return true;
    }
    final port = uri.port;
    return port >= 1 && port <= 65535;
  } on FormatException {
    return false;
  }
}

int _effectivePort(Uri uri) {
  if (uri.hasPort) {
    return uri.port;
  }
  return uri.scheme.toLowerCase() == 'https' ? 443 : 80;
}

bool _isAccessCodeInvalidResponse(Response<dynamic>? response) {
  final statusCode = response?.statusCode;
  if (statusCode != 401 && statusCode != 403 && statusCode != 429) {
    return false;
  }
  final contentType = response?.headers.value(Headers.contentTypeHeader) ?? '';
  return contentType.toLowerCase().split(';').first.trim() == 'text/html';
}

void _removeFeiniuAccessCodeHeaders(Map<String, dynamic> headers) {
  for (final name in headers.keys.toList()) {
    final normalized = name.toLowerCase();
    if (normalized == 'x-access-code' || normalized == 'x-access-source') {
      headers.remove(name);
    }
  }
}

Uri _resolveFinalResponseUri(Response<dynamic> response) {
  var current = response.requestOptions.uri;
  for (final redirect in response.redirects) {
    current = current.resolveUri(redirect.location);
  }
  return current;
}
