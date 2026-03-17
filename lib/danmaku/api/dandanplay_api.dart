import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

class DanDanPlayApi {
  final Dio _dio;
  final String appId;
  final String appSecret;

  DanDanPlayApi({
    Dio? dio,
    required this.appId,
    required this.appSecret,
  }) : _dio = dio ?? Dio(BaseOptions(baseUrl: 'https://api.dandanplay.net'));

  bool get ready => appId.trim().isNotEmpty && appSecret.trim().isNotEmpty;

  Future<Response<Map<String, dynamic>>> searchEpisodes({
    String anime = '',
    int? episode,
    int? tmdbId,
  }) {
    const path = '/api/v2/search/episodes';
    return _dio.get<Map<String, dynamic>>(
      path,
      queryParameters: <String, dynamic>{
        if (anime.trim().isNotEmpty) 'anime': anime.trim(),
        if (episode != null) 'episode': episode,
        if (tmdbId != null) 'tmdbId': tmdbId,
      },
      options: Options(headers: _buildHeaders(path)),
    );
  }

  Future<Response<String>> fetchComments(
    int episodeId, {
    bool withRelated = true,
  }) {
    final path = '/api/v2/comment/$episodeId';
    return _dio.get<String>(
      path,
      queryParameters: <String, dynamic>{
        if (withRelated) 'withRelated': 'true',
      },
      options: Options(
        headers: _buildHeaders(path),
        responseType: ResponseType.plain,
      ),
    );
  }

  Map<String, String> _buildHeaders(String path) {
    final normalizedAppId = appId.trim();
    final normalizedSecret = appSecret.trim();
    if (normalizedAppId.isEmpty || normalizedSecret.isEmpty) {
      throw StateError('DanDanPlay AppId / AppSecret 未配置');
    }
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final raw = '$normalizedAppId$timestamp$path$normalizedSecret';
    final signature = base64Encode(sha256.convert(utf8.encode(raw)).bytes);
    return <String, String>{
      'X-AppId': normalizedAppId,
      'X-Timestamp': '$timestamp',
      'X-Signature': signature,
    };
  }
}
