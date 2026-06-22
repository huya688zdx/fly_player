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

  /// 当前用户的媒体库（Views）——首页分类条的来源。
  ///
  /// `GET /Users/{userId}/Views`，`api_key` 自鉴权。返回 `Items` 数组（BaseItemDto 原样
  /// `Map`，字段映射留 mapper）。
  Future<List<Map<String, Object?>>> getUserViews({
    required String serverUrl,
    required String userId,
    required String accessToken,
  }) async {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    return _getItemList(
      '$normalizedServerUrl/Users/${userId.trim()}/Views',
      <String, Object?>{'api_key': accessToken},
    );
  }

  /// 条目列表——首页某库预览（[parentId]）或继续观看（[isResumable]）。
  ///
  /// `GET /Users/{userId}/Items`，`api_key` 自鉴权。返回 `Items` 数组。
  Future<List<Map<String, Object?>>> getItems({
    required String serverUrl,
    required String userId,
    required String accessToken,
    String parentId = '',
    int? limit,
    bool isResumable = false,
    bool recursive = false,
    String includeItemTypes = '',
    String fields = '',
    String sortBy = '',
    String sortOrder = '',
  }) async {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    final query = <String, Object?>{
      'api_key': accessToken,
      if (parentId.trim().isNotEmpty) 'ParentId': parentId.trim(),
      if (limit != null) 'Limit': limit,
      if (isResumable) 'Filters': 'IsResumable',
      if (recursive) 'Recursive': true,
      if (includeItemTypes.trim().isNotEmpty)
        'IncludeItemTypes': includeItemTypes.trim(),
      if (fields.trim().isNotEmpty) 'Fields': fields.trim(),
      if (sortBy.trim().isNotEmpty) 'SortBy': sortBy.trim(),
      if (sortOrder.trim().isNotEmpty) 'SortOrder': sortOrder.trim(),
    };
    return _getItemList(
      '$normalizedServerUrl/Users/${userId.trim()}/Items',
      query,
    );
  }

  /// 单个条目详情——详情页（[itemId]）。
  ///
  /// `GET /Users/{userId}/Items/{itemId}`，`api_key` 自鉴权，`Fields` 拉详情所需字段
  /// （简介 / 题材 / 演职员 / 外部 ID / 拍摄地）。返回单个 `BaseItemDto` 原样 `Map`
  /// （字段映射留 mapper），与列表接口的 `Items` 数组不同。
  Future<Map<String, Object?>> getItem({
    required String serverUrl,
    required String userId,
    required String accessToken,
    required String itemId,
    String fields =
        'Overview,Genres,People,ProviderIds,ProductionLocations,'
        'PremiereDate,CommunityRating',
  }) async {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    final query = <String, Object?>{
      'api_key': accessToken,
      if (fields.trim().isNotEmpty) 'Fields': fields.trim(),
    };
    final response = await _dio.get<Object?>(
      '$normalizedServerUrl/Users/${userId.trim()}/Items/${itemId.trim()}',
      queryParameters: query,
      options: Options(headers: _jsonHeaders),
    );
    return _asMap(response.data);
  }

  Future<List<Map<String, Object?>>> _getItemList(
    String url,
    Map<String, Object?> query,
  ) async {
    final response = await _dio.get<Object?>(
      url,
      queryParameters: query,
      options: Options(headers: _jsonHeaders),
    );
    final data = _asMap(response.data);
    final items = data['Items'];
    if (items is! List) return const <Map<String, Object?>>[];
    return items
        .whereType<Map>()
        .map((e) => Map<String, Object?>.from(e))
        .toList(growable: false);
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
