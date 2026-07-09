import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

/// DanDanPlay 请求错误码。
enum DanDanPlayApiErrorCode {
  notConfigured,
  businessError,
  missingAuthenticationHeaders,
  invalidTimestamp,
  invalidAppId,
  invalidSignature,
  invalidAppSecret,
  unauthorized,
  forbidden,
  rateLimited,
  serverError,
  network,
  invalidResponse,
  temporarilyBlocked,
  unknown,
}

/// DanDanPlay 请求失败时抛出的统一异常。
class DanDanPlayApiException implements Exception {
  /// 归一化后的错误类别。
  final DanDanPlayApiErrorCode code;

  /// 面向调用方展示的错误说明。
  final String message;

  /// HTTP 状态码；如果请求未到达服务端则可能为空。
  final int? statusCode;

  /// 服务端返回的原始错误信息。
  final String? serverMessage;

  /// 建议的重试等待时间。
  final Duration? retryAfter;

  const DanDanPlayApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.serverMessage,
    this.retryAfter,
  });

  /// 为了避免继续触发限流，调用方应在短时间内暂停请求。
  bool get shouldTemporarilyBlockRequests => switch (code) {
    DanDanPlayApiErrorCode.rateLimited => true,
    DanDanPlayApiErrorCode.serverError => true,
    DanDanPlayApiErrorCode.temporarilyBlocked => true,
    _ => false,
  };

  @override
  String toString() => message;
}

/// DanDanPlay HTTP 客户端，负责鉴权头、错误映射和多密钥回退。
class DanDanPlayApi {
  static DateTime? _blockedUntil;
  static DanDanPlayApiException? _blockedException;

  final Dio _dio;
  final String appId;

  /// 当前请求可用的 AppSecret 列表。
  final List<String> appSecrets;

  DanDanPlayApi({
    Dio? dio,
    required this.appId,
    String? appSecret,
    List<String> appSecrets = const <String>[],
  }) : appSecrets =
           <String>[
                 ...appSecrets,
                 if ((appSecret ?? '').trim().isNotEmpty) appSecret!.trim(),
               ]
               .map((item) => item.trim())
               .where((item) => item.isNotEmpty)
               .toSet()
               .toList(growable: false),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: 'https://api.dandanplay.net',
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 20),
               sendTimeout: const Duration(seconds: 10),
             ),
           );

  /// 当前是否已经具备可发起请求的 AppId / AppSecret。
  bool get ready => appId.trim().isNotEmpty && appSecrets.isNotEmpty;

  /// 搜索番剧/剧集候选。
  ///
  /// `anime` 是搜索关键字，`episode` 和 `tmdbId` 会作为额外约束缩小结果范围。
  Future<Response<Map<String, dynamic>>> searchEpisodes({
    String anime = '',
    int? episode,
    int? tmdbId,
  }) async {
    const path = '/api/v2/search/episodes';
    final response = await _runWithSecretFallback<Map<String, dynamic>>(
      path: path,
      request: (secret) => _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: <String, dynamic>{
          if (anime.trim().isNotEmpty) 'anime': anime.trim(),
          if (episode != null) 'episode': episode,
          if (tmdbId != null) 'tmdbId': tmdbId,
        },
        options: Options(headers: _buildHeaders(secret, path)),
      ),
    );
    _throwIfBusinessError(response.data);
    return response;
  }

  /// 按弹弹 Play 的剧集 id 拉取原始弹幕 XML/文本内容。
  Future<Response<String>> fetchComments(
    int episodeId, {
    bool withRelated = true,
  }) async {
    final path = '/api/v2/comment/$episodeId';
    final response = await _runWithSecretFallback<String>(
      path: path,
      request: (secret) => _dio.get<String>(
        path,
        queryParameters: <String, dynamic>{
          if (withRelated) 'withRelated': 'true',
        },
        options: Options(
          headers: _buildHeaders(secret, path),
          responseType: ResponseType.plain,
        ),
      ),
    );
    _throwIfCommentPayloadError(response.data);
    return response;
  }

  Future<Response<T>> _runWithSecretFallback<T>({
    required String path,
    required Future<Response<T>> Function(String secret) request,
  }) async {
    if (!ready) {
      throw const DanDanPlayApiException(
        code: DanDanPlayApiErrorCode.notConfigured,
        message: 'DanDanPlay AppId / AppSecret is not configured.',
      );
    }
    _throwIfTemporarilyBlocked();

    Object? lastError;
    for (var index = 0; index < appSecrets.length; index += 1) {
      final secret = appSecrets[index];
      try {
        return await request(secret);
      } on DioException catch (error) {
        final mapped = _mapDioException(error);
        lastError = mapped;
        if (mapped.shouldTemporarilyBlockRequests) {
          _blockRequests(
            mapped.retryAfter ?? const Duration(minutes: 10),
            mapped,
          );
        }
        final canRetry =
            index + 1 < appSecrets.length && _canRetryWithNextSecret(mapped);
        if (!canRetry) {
          throw mapped;
        }
      } on DanDanPlayApiException catch (error) {
        lastError = error;
        rethrow;
      } catch (error) {
        lastError = error;
        rethrow;
      }
    }
    throw lastError ??
        const DanDanPlayApiException(
          code: DanDanPlayApiErrorCode.unknown,
          message: 'DanDanPlay request failed without a specific error.',
        );
  }

  Map<String, String> _buildHeaders(String secret, String path) {
    final normalizedAppId = appId.trim();
    final normalizedSecret = secret.trim();
    if (normalizedAppId.isEmpty || normalizedSecret.isEmpty) {
      throw const DanDanPlayApiException(
        code: DanDanPlayApiErrorCode.notConfigured,
        message: 'DanDanPlay AppId / AppSecret is not configured.',
      );
    }
    // 弹弹 Play 开放平台鉴权：X-AppId + X-Timestamp + X-Signature。
    // 签名 = base64(sha256(appId + timestamp + apiPath + appSecret))，
    // timestamp 为当前 Unix 秒，apiPath 为不含 query 的请求路径（如 /api/v2/search/episodes）。
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000)
        .toString();
    final raw = '$normalizedAppId$timestamp$path$normalizedSecret';
    final signature = base64.encode(sha256.convert(utf8.encode(raw)).bytes);
    return <String, String>{
      'X-AppId': normalizedAppId,
      'X-Timestamp': timestamp,
      'X-Signature': signature,
    };
  }

  void _throwIfBusinessError(Map<String, dynamic>? payload) {
    if (payload == null || payload.isEmpty) return;
    final success = payload['success'];
    if (success is bool && success) return;
    if (success == null &&
        payload['errorCode'] == null &&
        payload['errorMessage'] == null) {
      return;
    }
    final serverMessage = _readServerMessage(payload);
    throw DanDanPlayApiException(
      code: DanDanPlayApiErrorCode.businessError,
      message: serverMessage.isEmpty
          ? 'DanDanPlay returned a business error.'
          : serverMessage,
      serverMessage: serverMessage.isEmpty ? null : serverMessage,
    );
  }

  void _throwIfCommentPayloadError(String? content) {
    final trimmed = content?.trim() ?? '';
    if (trimmed.isEmpty || !trimmed.startsWith('{')) {
      return;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return;
      final payload = Map<String, dynamic>.from(decoded);
      _throwIfBusinessError(payload);
    } on DanDanPlayApiException {
      rethrow;
    } catch (_) {
      return;
    }
  }

  bool _canRetryWithNextSecret(DanDanPlayApiException error) {
    return switch (error.code) {
      DanDanPlayApiErrorCode.invalidAppSecret => true,
      DanDanPlayApiErrorCode.unauthorized => true,
      DanDanPlayApiErrorCode.forbidden => true,
      _ => false,
    };
  }

  DanDanPlayApiException _mapDioException(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return const DanDanPlayApiException(
        code: DanDanPlayApiErrorCode.network,
        message: 'DanDanPlay request timed out. Please try again later.',
      );
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.unknown) {
      return const DanDanPlayApiException(
        code: DanDanPlayApiErrorCode.network,
        message:
            'DanDanPlay network connection failed. Check the network and retry.',
      );
    }

    final response = error.response;
    final statusCode = response?.statusCode;
    final serverMessage =
        response?.headers.value('X-Error-Message')?.trim().isNotEmpty == true
        ? response!.headers.value('X-Error-Message')!.trim()
        : _extractBodyMessage(response?.data);
    final retryAfter = _parseRetryAfter(response?.headers.value('Retry-After'));

    if (statusCode == 401) {
      return DanDanPlayApiException(
        code: DanDanPlayApiErrorCode.unauthorized,
        statusCode: statusCode,
        serverMessage: serverMessage,
        message: 'DanDanPlay authentication failed. Check AppId / AppSecret.',
      );
    }

    if (statusCode == 403) {
      return _mapForbidden(serverMessage, statusCode: statusCode ?? 403);
    }

    if (statusCode == 429) {
      return DanDanPlayApiException(
        code: DanDanPlayApiErrorCode.rateLimited,
        statusCode: statusCode,
        serverMessage: serverMessage,
        retryAfter: retryAfter ?? const Duration(minutes: 30),
        message:
            'DanDanPlay requests are too frequent and have been rate limited.',
      );
    }

    if (statusCode != null && statusCode >= 500) {
      return DanDanPlayApiException(
        code: DanDanPlayApiErrorCode.serverError,
        statusCode: statusCode,
        serverMessage: serverMessage,
        retryAfter: const Duration(minutes: 10),
        message: 'DanDanPlay server is temporarily unavailable.',
      );
    }

    if (statusCode != null) {
      return DanDanPlayApiException(
        code: DanDanPlayApiErrorCode.unknown,
        statusCode: statusCode,
        serverMessage: serverMessage,
        message: serverMessage?.isNotEmpty == true
            ? 'DanDanPlay request failed: $serverMessage'
            : 'DanDanPlay request failed with status code $statusCode.',
      );
    }

    return DanDanPlayApiException(
      code: DanDanPlayApiErrorCode.unknown,
      serverMessage: serverMessage,
      message: serverMessage?.isNotEmpty == true
          ? 'DanDanPlay request failed: $serverMessage'
          : 'DanDanPlay request failed. Please try again later.',
    );
  }

  DanDanPlayApiException _mapForbidden(
    String? serverMessage, {
    required int statusCode,
  }) {
    final normalized = (serverMessage ?? '').trim().toLowerCase();
    if (normalized.contains('missing authentication headers')) {
      return DanDanPlayApiException(
        code: DanDanPlayApiErrorCode.missingAuthenticationHeaders,
        statusCode: statusCode,
        serverMessage: serverMessage,
        message: 'DanDanPlay request is missing authentication headers.',
      );
    }
    if (normalized.contains('invalid timestamp')) {
      return DanDanPlayApiException(
        code: DanDanPlayApiErrorCode.invalidTimestamp,
        statusCode: statusCode,
        serverMessage: serverMessage,
        message: 'DanDanPlay request timestamp is invalid. Check device time.',
      );
    }
    if (normalized.contains('invalid appid')) {
      return DanDanPlayApiException(
        code: DanDanPlayApiErrorCode.invalidAppId,
        statusCode: statusCode,
        serverMessage: serverMessage,
        message: 'DanDanPlay AppId is invalid. Check the configuration.',
      );
    }
    if (normalized.contains('invalid signature')) {
      return DanDanPlayApiException(
        code: DanDanPlayApiErrorCode.invalidSignature,
        statusCode: statusCode,
        serverMessage: serverMessage,
        message: 'DanDanPlay request signature is invalid.',
      );
    }
    if (normalized.contains('invalid appsecret')) {
      return DanDanPlayApiException(
        code: DanDanPlayApiErrorCode.invalidAppSecret,
        statusCode: statusCode,
        serverMessage: serverMessage,
        message: 'DanDanPlay AppSecret is invalid. Check the configuration.',
      );
    }
    if (normalized.contains('too many') ||
        normalized.contains('frequent') ||
        normalized.contains('blocked') ||
        normalized.contains('forbidden')) {
      return DanDanPlayApiException(
        code: DanDanPlayApiErrorCode.temporarilyBlocked,
        statusCode: statusCode,
        serverMessage: serverMessage,
        retryAfter: const Duration(minutes: 30),
        message:
            'DanDanPlay rejected this request, possibly due to rate limits.',
      );
    }
    return DanDanPlayApiException(
      code: DanDanPlayApiErrorCode.forbidden,
      statusCode: statusCode,
      serverMessage: serverMessage,
      message: serverMessage?.isNotEmpty == true
          ? 'DanDanPlay rejected the request: $serverMessage'
          : 'DanDanPlay rejected the request. Check permissions and config.',
    );
  }

  String _readServerMessage(Map<String, dynamic> payload) {
    for (final key in const <String>[
      'errorMessage',
      'message',
      'error',
      'msg',
    ]) {
      final value = payload[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String? _extractBodyMessage(dynamic data) {
    if (data == null) return null;
    if (data is String) {
      final trimmed = data.trim();
      if (trimmed.isEmpty) return null;
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          final message = _readServerMessage(
            Map<String, dynamic>.from(decoded),
          );
          if (message.isNotEmpty) return message;
        }
      } catch (_) {
        return trimmed.length > 160 ? trimmed.substring(0, 160) : trimmed;
      }
      return trimmed.length > 160 ? trimmed.substring(0, 160) : trimmed;
    }
    if (data is Map) {
      final message = _readServerMessage(Map<String, dynamic>.from(data));
      return message.isEmpty ? null : message;
    }
    return data.toString().trim().isEmpty ? null : data.toString().trim();
  }

  Duration? _parseRetryAfter(String? rawValue) {
    final trimmed = rawValue?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final seconds = int.tryParse(trimmed);
    if (seconds == null || seconds <= 0) return null;
    return Duration(seconds: seconds);
  }

  void _throwIfTemporarilyBlocked() {
    final until = _blockedUntil;
    final error = _blockedException;
    if (until == null || error == null) return;
    final remaining = until.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _blockedUntil = null;
      _blockedException = null;
      return;
    }
    throw DanDanPlayApiException(
      code: DanDanPlayApiErrorCode.temporarilyBlocked,
      message:
          '${error.message} Requests are locally paused for ${remaining.inMinutes + 1} more minutes.',
      retryAfter: remaining,
      statusCode: error.statusCode,
      serverMessage: error.serverMessage,
    );
  }

  void _blockRequests(Duration duration, DanDanPlayApiException error) {
    _blockedUntil = DateTime.now().add(duration);
    _blockedException = error;
  }
}
