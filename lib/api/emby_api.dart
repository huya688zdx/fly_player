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

  /// 条目计数——首页计数行。`GET /Users/{userId}/Items`，`Limit=0` 只取 `TotalRecordCount`、
  /// 不拉条目体（最省流的计数方式）。Emby 无专用计数端点，按类型分别调本方法拼计数。
  Future<int> getItemCount({
    required String serverUrl,
    required String userId,
    required String accessToken,
    bool recursive = true,
    bool favoritesOnly = false,
    String includeItemTypes = '',
  }) async {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    final query = <String, Object?>{
      'api_key': accessToken,
      'Limit': 0,
      if (recursive) 'Recursive': true,
      if (favoritesOnly) 'Filters': 'IsFavorite',
      if (includeItemTypes.trim().isNotEmpty)
        'IncludeItemTypes': includeItemTypes.trim(),
    };
    final response = await _dio.get<Object?>(
      '$normalizedServerUrl/Users/${userId.trim()}/Items',
      queryParameters: query,
      options: Options(headers: _jsonHeaders),
    );
    final data = _asMap(response.data);
    final count = data['TotalRecordCount'];
    if (count is int) return count;
    if (count is num) return count.toInt();
    if (count is String) return int.tryParse(count) ?? 0;
    return 0;
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

  /// 剧集的季列表——系列页季栅格。`GET /Shows/{seriesId}/Seasons`，`api_key` 自鉴权。
  ///
  /// 返回 `Items` 数组（季 `BaseItemDto` 原样 `Map`，字段映射留 mapper）。`UserData` 为
  /// 季级已看快照;`ChildCount`/`RecursiveItemCount` 为该季集计数。
  Future<List<Map<String, Object?>>> getSeasons({
    required String serverUrl,
    required String userId,
    required String accessToken,
    required String seriesId,
    String fields = 'ItemCounts,UserData',
  }) async {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    final query = <String, Object?>{
      'api_key': accessToken,
      'UserId': userId.trim(),
      if (fields.trim().isNotEmpty) 'Fields': fields.trim(),
    };
    return _getItemList(
      '$normalizedServerUrl/Shows/${seriesId.trim()}/Seasons',
      query,
    );
  }

  /// 分页条目查询——分类 / 媒体库列表页（[CategoryItemsScreen]）。
  ///
  /// `GET /Users/{userId}/Items`，`api_key` 自鉴权。与 [getItems] 的差别：支持 `StartIndex`
  /// 偏移分页、`Genres` 题材筛选，并连同 `TotalRecordCount` 一起返回（列表页需要总数算
  /// 「还有更多」）。[genres] 为题材显示名（Emby `Genres` 取名字，多个用 `|` 分隔）。
  /// [searchTerm] 非空时按关键字搜索（Emby `SearchTerm`），供搜索页复用本分页查询。
  Future<EmbyItemPage> getItemPage({
    required String serverUrl,
    required String userId,
    required String accessToken,
    String parentId = '',
    int startIndex = 0,
    int? limit,
    bool recursive = true,
    String includeItemTypes = '',
    String genres = '',
    String fields = '',
    String sortBy = '',
    String sortOrder = '',
    String searchTerm = '',
  }) async {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    final query = <String, Object?>{
      'api_key': accessToken,
      if (parentId.trim().isNotEmpty) 'ParentId': parentId.trim(),
      if (startIndex > 0) 'StartIndex': startIndex,
      if (limit != null) 'Limit': limit,
      if (recursive) 'Recursive': true,
      if (includeItemTypes.trim().isNotEmpty)
        'IncludeItemTypes': includeItemTypes.trim(),
      if (genres.trim().isNotEmpty) 'Genres': genres.trim(),
      if (searchTerm.trim().isNotEmpty) 'SearchTerm': searchTerm.trim(),
      if (fields.trim().isNotEmpty) 'Fields': fields.trim(),
      if (sortBy.trim().isNotEmpty) 'SortBy': sortBy.trim(),
      if (sortOrder.trim().isNotEmpty) 'SortOrder': sortOrder.trim(),
    };
    final response = await _dio.get<Object?>(
      '$normalizedServerUrl/Users/${userId.trim()}/Items',
      queryParameters: query,
      options: Options(headers: _jsonHeaders),
    );
    final data = _asMap(response.data);
    final rawItems = data['Items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map((e) => Map<String, Object?>.from(e))
              .toList(growable: false)
        : const <Map<String, Object?>>[];
    return EmbyItemPage(
      items: items,
      totalRecordCount: _asCount(data['TotalRecordCount'], items.length),
    );
  }

  /// 题材列表——分类 / 媒体库列表页的题材筛选维度。`GET /Genres`，`api_key` 自鉴权。
  ///
  /// [parentId] 把题材限定在某库；[includeItemTypes] 限定统计的条目类型。返回 `Items`
  /// 数组（题材 `BaseItemDto`，取 `Name`；Emby 的 `Genres` 查询参数按名字筛选）。
  Future<List<Map<String, Object?>>> getGenres({
    required String serverUrl,
    required String userId,
    required String accessToken,
    String parentId = '',
    String includeItemTypes = '',
  }) async {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    final query = <String, Object?>{
      'api_key': accessToken,
      'UserId': userId.trim(),
      'Recursive': true,
      'SortBy': 'SortName',
      if (parentId.trim().isNotEmpty) 'ParentId': parentId.trim(),
      if (includeItemTypes.trim().isNotEmpty)
        'IncludeItemTypes': includeItemTypes.trim(),
    };
    return _getItemList('$normalizedServerUrl/Genres', query);
  }

  /// 继续观看——首页续播行。`GET /Users/{userId}/Items/Resume`，`api_key` 自鉴权。
  ///
  /// Emby 官方「继续观看」专用端点：返回该用户**有续播进度**的条目（任意 Emby 客户端播放
  /// 留下的进度），已按最近播放排序。比 `/Items?Filters=IsResumable` 更可靠。仅取视频
  /// （`MediaTypes=Video`）。返回 `Items` 数组（BaseItemDto 原样 `Map`，映射留 mapper）。
  Future<List<Map<String, Object?>>> getResumeItems({
    required String serverUrl,
    required String userId,
    required String accessToken,
    int limit = 20,
    String fields = '',
  }) async {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    final query = <String, Object?>{
      'api_key': accessToken,
      'Limit': limit,
      'Recursive': true,
      'MediaTypes': 'Video',
      if (fields.trim().isNotEmpty) 'Fields': fields.trim(),
    };
    return _getItemList(
      '$normalizedServerUrl/Users/${userId.trim()}/Items/Resume',
      query,
    );
  }

  static int _asCount(Object? value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
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

/// 分页条目查询结果（[EmbyApi.getItemPage]）：本页条目 + 库内匹配总数。
class EmbyItemPage {
  const EmbyItemPage({required this.items, required this.totalRecordCount});

  final List<Map<String, Object?>> items;
  final int totalRecordCount;
}
