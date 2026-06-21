import 'package:dio/dio.dart';

class EmbyPublicSystemInfo {
  const EmbyPublicSystemInfo({required this.serverName});

  final String serverName;
}

class EmbyAuthenticateResult {
  const EmbyAuthenticateResult({
    required this.serverUrl,
    required this.serverName,
    required this.accessToken,
    required this.userId,
    required this.userName,
  });

  final String serverUrl;
  final String serverName;
  final String accessToken;
  final String userId;
  final String userName;
}

class EmbyApi {
  EmbyApi({
    Dio? dio,
    this.clientName = 'Fly Player',
    this.deviceName = 'Flutter',
    this.deviceId = 'fly-player',
    this.clientVersion = '1.0.0',
  }) : _dio = dio ?? Dio();

  final Dio _dio;
  final String clientName;
  final String deviceName;
  final String deviceId;
  final String clientVersion;

  static String normalizeServerUrl(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '';
    if (!value.startsWith(RegExp(r'https?://', caseSensitive: false))) {
      value = 'http://$value';
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  Future<EmbyPublicSystemInfo> getPublicSystemInfo(String serverUrl) async {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    final response = await _dio.get<Object?>(
      '$normalizedServerUrl/System/Info/Public',
      options: Options(headers: _jsonHeaders),
    );
    final data = _asMap(response.data);
    return EmbyPublicSystemInfo(
      serverName: (data['ServerName'] ?? '').toString(),
    );
  }

  Future<EmbyAuthenticateResult> authenticateByName({
    required String serverUrl,
    required String userName,
    required String password,
  }) async {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    final response = await _dio.post<Object?>(
      '$normalizedServerUrl/Users/AuthenticateByName',
      data: <String, Object?>{'Username': userName.trim(), 'Pw': password},
      options: Options(
        contentType: Headers.jsonContentType,
        headers: <String, Object?>{
          ..._jsonHeaders,
          'X-Emby-Authorization': _authorizationHeader,
        },
      ),
    );

    final data = _asMap(response.data);
    final user = _asMap(data['User']);
    return EmbyAuthenticateResult(
      serverUrl: normalizedServerUrl,
      serverName: (data['ServerName'] ?? '').toString(),
      accessToken: (data['AccessToken'] ?? '').toString(),
      userId: (user['Id'] ?? '').toString(),
      userName: (user['Name'] ?? userName.trim()).toString(),
    );
  }

  Map<String, Object?> get _jsonHeaders => const <String, Object?>{
    Headers.acceptHeader: Headers.jsonContentType,
  };

  String get _authorizationHeader =>
      'MediaBrowser Client=$clientName, Device=$deviceName, '
      'DeviceId=$deviceId, Version=$clientVersion';

  static Map<String, Object?> _asMap(Object? data) {
    if (data is Map) {
      return Map<String, Object?>.from(data);
    }
    return const <String, Object?>{};
  }
}
