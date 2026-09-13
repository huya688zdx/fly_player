import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Fly credentials must not inherit the legacy media client's permissive TLS
/// override. Calling the base implementation creates a real, isolated client.
class _StrictHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..badCertificateCallback = (_, _, _) => false;
}

Dio createStrictFlyDio() => Dio()
  ..httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () =>
        _StrictHttpOverrides().createHttpClient(SecurityContext.defaultContext),
  );

class FlyDataApi {
  FlyDataApi(String serverUrl, {String? token, Dio? dio, this.maxResponseBytes})
    : _dio = dio ?? createStrictFlyDio() {
    _dio.options = BaseOptions(
      baseUrl: '${normalizeServerUrl(serverUrl)}/api/v1',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
      followRedirects: false,
      headers: {if (token != null) 'Authorization': 'Bearer $token'},
    );
  }
  final Dio _dio;

  /// Optional raw JSON limit for playback-side cache reads.
  final int? maxResponseBytes;

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final limit = maxResponseBytes;
    if (limit != null) {
      return _request(() async {
        final response = await _dio.get<ResponseBody>(
          path,
          queryParameters: query,
          options: Options(responseType: ResponseType.stream),
        );
        final type = response.headers.value(Headers.contentTypeHeader) ?? '';
        final body = response.data;
        if (body == null ||
            type.split(';').first.trim().toLowerCase() != 'application/json') {
          await body?.stream.listen(null).cancel();
          throw StateError('弹幕缓存格式不可用。');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in body.stream) {
          if (bytes.length + chunk.length > limit) {
            throw StateError('弹幕缓存超过本机读取上限。');
          }
          bytes.add(chunk);
        }
        return Response<dynamic>(
          requestOptions: response.requestOptions,
          data: jsonDecode(utf8.decode(bytes.takeBytes())),
        );
      });
    }
    return _request(() => _dio.get<dynamic>(path, queryParameters: query));
  }

  Future<Map<String, dynamic>> post(String path, Object data) async {
    return _request(
      () => _dio.post<dynamic>(
        path,
        data: data,
        options: Options(contentType: Headers.jsonContentType),
      ),
    );
  }

  Future<Map<String, dynamic>> patch(String path, Object data) =>
      _request(() => _dio.patch<dynamic>(path, data: data));

  Future<Uint8List> imageBytes(String mediaId) async {
    try {
      final response = await _dio.get<List<int>>(
        '/media/${Uri.encodeComponent(mediaId)}/image',
        queryParameters: {'kind': 'poster'},
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data ?? [];
      if (bytes.length > 8 * 1024 * 1024 ||
          !(response.headers.value('content-type') ?? '').startsWith(
            'image/',
          )) {
        throw StateError('图片格式不可用。');
      }
      return Uint8List.fromList(bytes);
    } on DioException {
      throw StateError('图片暂不可用。');
    }
  }

  Future<Map<String, dynamic>> _request(
    Future<Response<dynamic>> Function() send,
  ) async {
    try {
      final response = await send();
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (error) {
      final code = await _safeErrorCode(error.response?.data);
      // DioException.toString can contain request details; never surface/log it.
      throw StateError(
        code == null ? '数据服务连接失败，请检查地址和网络后手动重试。' : '数据服务拒绝请求：$code',
      );
    }
  }

  /// Playback reads use ResponseType.stream, including HTTP error bodies.
  /// Preserve only a short machine code, never the server's private message.
  Future<String?> _safeErrorCode(dynamic body) async {
    try {
      if (body is ResponseBody) {
        final type = body.headers[Headers.contentTypeHeader]?.firstOrNull ?? '';
        if (type.split(';').first.trim().toLowerCase() != 'application/json') {
          await body.stream.listen(null).cancel();
          return null;
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in body.stream) {
          if (bytes.length + chunk.length > 16 * 1024) return null;
          bytes.add(chunk);
        }
        body = jsonDecode(utf8.decode(bytes.takeBytes()));
      }
      final detail = body is Map ? body['error'] : null;
      final code = detail is Map ? detail['code'] : null;
      return code is String && RegExp(r'^[A-Z0-9_]{1,80}$').hasMatch(code)
          ? code
          : null;
    } catch (_) {
      return null;
    }
  }

  void close() => _dio.close(force: true);
}

String normalizeServerUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw const FormatException('请输入服务根地址，例如 http://nas:8787（不要含帐号、路径或查询参数）。');
  }
  return uri.replace(path: '').toString().replaceAll(RegExp(r'/$'), '');
}
