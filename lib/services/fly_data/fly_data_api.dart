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
  FlyDataApi(
    String serverUrl, {
    String? token,
    String fnEntryToken = '',
    Dio? dio,
    this.maxResponseBytes,
    Duration receiveTimeout = const Duration(seconds: 60),
  }) : _dio = dio ?? createStrictFlyDio() {
    _dio.options = BaseOptions(
      baseUrl: '${normalizeServerUrl(serverUrl)}/api/v1',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: receiveTimeout,
      sendTimeout: const Duration(seconds: 60),
      followRedirects: false,
      headers: {if (token != null) 'Authorization': 'Bearer $token'},
    );
    final base = Uri.parse(_dio.options.baseUrl);
    _isFnApplication = isFlyFnApplicationUrl(serverUrl);
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final target = options.uri;
          // 凭据只属于所选服务，禁止跨源、路径逃逸和重定向带出凭据。
          if (target.origin != base.origin ||
              !target.path.startsWith('${base.path}/') ||
              target.pathSegments.any(
                (part) =>
                    part == '..' ||
                    part == '.' ||
                    part.contains('/') ||
                    part.contains('\\'),
              )) {
            handler.reject(DioException(requestOptions: options));
            return;
          }
          options.followRedirects = false;
          if (_isFnApplication && fnEntryToken.isNotEmpty) {
            if (!RegExp(
              r'^[\x21\x23-\x2B\x2D-\x3A\x3C-\x5B\x5D-\x7E]+$',
            ).hasMatch(fnEntryToken)) {
              handler.reject(DioException(requestOptions: options));
              return;
            }
            options.headers['Cookie'] = 'entry-token=$fnEntryToken';
          }
          handler.next(options);
        },
      ),
    );
  }
  final Dio _dio;
  late final bool _isFnApplication;

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
    final limit = maxResponseBytes;
    if (limit != null) {
      return _request(() async {
        final response = await _dio.post<ResponseBody>(
          path,
          data: data,
          options: Options(
            contentType: Headers.jsonContentType,
            responseType: ResponseType.stream,
          ),
        );
        final body = response.data;
        if (body == null ||
            (response.headers.value('content-type') ?? '')
                    .split(';')
                    .first
                    .trim()
                    .toLowerCase() !=
                'application/json') {
          await body?.stream.listen(null).cancel();
          throw StateError('Invalid data response.');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in body.stream) {
          if (bytes.length + chunk.length > limit) {
            throw StateError('Data response exceeds limit.');
          }
          bytes.add(chunk);
        }
        return Response<dynamic>(
          requestOptions: response.requestOptions,
          data: jsonDecode(utf8.decode(bytes.takeBytes())),
        );
      });
    }
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

  /// Fixed same-service BIF endpoint; no redirects and no inherited media TLS
  /// override. Bound bytes while streaming, including chunked responses.
  Future<Uint8List> bifBytes(String path, {required int expectedBytes}) async {
    final uri = Uri.tryParse(path);
    if (uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasFragment ||
        !RegExp(
          r'^/api/v1/bif/assets/[0-9a-fA-F-]{36}/content$',
        ).hasMatch(uri.path) ||
        expectedBytes < 80 ||
        expectedBytes > 128 * 1024 * 1024) {
      throw StateError('Invalid BIF asset request.');
    }
    try {
      final response = await _dio.get<ResponseBody>(
        path.substring('/api/v1'.length),
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: false,
        ),
      );
      final body = response.data;
      if (response.statusCode != 200 || body == null) {
        throw StateError('BIF unavailable.');
      }
      final declared = int.tryParse(
        response.headers.value('content-length') ?? '',
      );
      if (declared != null && declared != expectedBytes) {
        await body.stream.listen(null).cancel();
        throw StateError('BIF length mismatch.');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in body.stream) {
        if (bytes.length + chunk.length > expectedBytes) {
          throw StateError('BIF exceeds declared limit.');
        }
        bytes.add(chunk);
      }
      if (bytes.length != expectedBytes) {
        throw StateError('BIF length mismatch.');
      }
      return bytes.takeBytes();
    } on DioException {
      throw StateError('BIF unavailable.');
    }
  }

  Future<Map<String, dynamic>> _request(
    Future<Response<dynamic>> Function() send,
  ) async {
    try {
      final response = await send();
      if (response.data is! Map) {
        throw StateError(
          _isFnApplication ? flyFnAccessMessage : '此地址没有返回飞翔服务数据，请核对服务地址。',
        );
      }
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (error) {
      final code = await _safeErrorCode(error.response?.data);
      // DioException.toString can contain request details; never surface/log it.
      throw StateError(
        code == null && _isFnApplication && error.response != null
            ? flyFnAccessMessage
            : code == null
            ? '数据服务连接失败，请检查地址和网络后手动重试。'
            : '数据服务拒绝请求：$code',
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
      ![
        '',
        '/',
        '/app/fly-data-service',
        '/app/fly-data-service/',
      ].contains(uri.path)) {
    throw const FormatException(
      '请输入服务根地址或 FN 应用链接（/app/fly-data-service），不要含账号或查询参数。',
    );
  }
  if (uri.host.endsWith('.fnos.net') &&
      uri.path.startsWith('/app/') &&
      uri.scheme != 'https') {
    throw const FormatException('FN 应用链接请使用 HTTPS。');
  }
  return uri.toString().replaceAll(RegExp(r'/$'), '');
}

const flyFnAccessMessage = 'FN 访问授权未完成或已失效，请重新授权后重试。';

bool isFlyFnApplicationUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.endsWith('.fnos.net') &&
      ['/app/fly-data-service', '/app/fly-data-service/'].contains(uri.path);
}
