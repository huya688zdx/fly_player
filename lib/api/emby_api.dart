import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'fn_entry_token_transport.dart';

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

/// Emby API 客户端，兼作 MediaBrowser 家族（Emby / Jellyfin）共享内核。
///
/// Jellyfin 是 Emby 3.5 的 fork，REST 端点与本类同形（认证 / 条目 / 播放直链 / 进度回写 /
/// 收藏已看 / 外挂字幕 / `api_key` 查询串自鉴权），[JellyfinApi] 直接继承本类、只覆写
/// 鉴权头风味（见 [authorizationHeaderValue]）。新增端点时若两家同形，直接写在本类。
class EmbyApi {
  EmbyApi({
    Dio? dio,
    this.clientName = 'Fly Player',
    this.deviceName = 'Flutter',
    this.deviceId = 'fly-player',
    this.clientVersion = '1.0.0',
    String Function()? entryTokenProvider,
  }) : _dio = dio ?? Dio(_defaultBaseOptions()),
       _entryTokenProvider = entryTokenProvider {
    installFnEntryTokenInterceptor(
      _dio,
      entryTokenProvider: _entryTokenProvider,
    );
  }

  /// 默认 Dio 的超时配置——只作用于本类自建的 Dio，外部注入（测试 / 定制）的实例不改动。
  ///
  /// 连接 10s 与 FeiniuApi 基线一致；接收放宽到 20s（Dio 的 receiveTimeout 计的是两次数据
  /// 事件的间隔而非总时长），照顾 fnos 中转闸首字节偏慢的情况。本类所有请求都是短 JSON 或
  /// 字幕文本，无长轮询 / 大流式下载（视频直链与 BIF 只产 URL 交给原生壳），该档位安全。
  static BaseOptions _defaultBaseOptions() => BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
    sendTimeout: const Duration(seconds: 10),
  );

  final Dio _dio;
  final String clientName;
  final String deviceName;
  final String deviceId;
  final String clientVersion;

  /// FN Connect 入口令牌（cookie `entry-token` 的值）的动态取值器。
  ///
  /// 当 Emby 服务器是 `*.fnos.net` 中转域名（藏在飞牛反向代理后面）时，请求必须携带
  /// `Cookie: entry-token=<值>` 才能过云端 FN Connect 边缘闸——实测这是唯一被认的凭据
  /// （NAS token / mode=relay 都不行）。每请求动态读取，令牌刷新后无需重建 EmbyApi。
  /// 直连地址（非 fnos）该取值器返回空、不带任何 cookie。
  ///
  /// 实际的 cookie 注入与诊断日志由传输层的 [installFnEntryTokenInterceptor] 承担。
  final String Function()? _entryTokenProvider;

  /// 传输层配置的只读视图——供测试断言自建 Dio 的超时档位；注入 Dio 时反映注入实例的配置。
  @visibleForTesting
  BaseOptions get transportOptions => _dio.options;

  static String normalizeServerUrl(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '';
    if (!value.startsWith(RegExp(r'https?://', caseSensitive: false))) {
      value = 'http://$value';
    }
    // 去掉 fragment / query：Emby 网页客户端是 /web/index.html#!/home 这种 hash
    // 路由，从浏览器复制地址会带上 `#!/...`（及可能的 `?...`），这些不属于 API 根。
    final hashIndex = value.indexOf('#');
    if (hashIndex >= 0) value = value.substring(0, hashIndex);
    final queryIndex = value.indexOf('?');
    if (queryIndex >= 0) value = value.substring(0, queryIndex);
    // 去掉粘贴网页地址时带上的 /web/index.html 或 /web 客户端路径，还原成 API 根
    // 地址（fnos 中转域名同样适用）。仅剥这段众所周知的网页路径，子路径反代部署
    // （如 https://host/emby）保持不动。
    value = value.replaceFirst(
      RegExp(r'/web/index\.html/?$', caseSensitive: false),
      '',
    );
    value = value.replaceFirst(RegExp(r'/web/?$', caseSensitive: false), '');
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
          'X-Emby-Authorization': authorizationHeaderValue,
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
  /// [personIds] 非空时只取该人物参与的条目（Emby `PersonIds`），供人物详情页作品区。
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
    String years = '',
    String filters = '',
    String seriesStatus = '',
    String fields = '',
    String sortBy = '',
    String sortOrder = '',
    String searchTerm = '',
    String personIds = '',
    bool favoritesOnly = false,
  }) async {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    // Emby `Filters`（IsFavorite / IsPlayed / IsUnplayed …）合并 favoritesOnly 与显式 filters。
    final filterTokens = <String>{
      if (favoritesOnly) 'IsFavorite',
      for (final t in filters.split(','))
        if (t.trim().isNotEmpty) t.trim(),
    };
    final query = <String, Object?>{
      'api_key': accessToken,
      if (parentId.trim().isNotEmpty) 'ParentId': parentId.trim(),
      if (startIndex > 0) 'StartIndex': startIndex,
      if (limit != null) 'Limit': limit,
      if (recursive) 'Recursive': true,
      if (filterTokens.isNotEmpty) 'Filters': filterTokens.join(','),
      if (seriesStatus.trim().isNotEmpty) 'SeriesStatus': seriesStatus.trim(),
      if (includeItemTypes.trim().isNotEmpty)
        'IncludeItemTypes': includeItemTypes.trim(),
      if (genres.trim().isNotEmpty) 'Genres': genres.trim(),
      if (years.trim().isNotEmpty) 'Years': years.trim(),
      if (searchTerm.trim().isNotEmpty) 'SearchTerm': searchTerm.trim(),
      if (personIds.trim().isNotEmpty) 'PersonIds': personIds.trim(),
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

  /// 剧集「下一集」——系列起播的目标集直取。`GET /Shows/NextUp`，`api_key` 自鉴权。
  ///
  /// MediaBrowser 家族通用端点（Emby / Jellyfin 同形，故留在内核、无风味缝隙）：服务端按
  /// 该用户在本剧的观看进度算出「接下来该看哪一集」，一次请求即定位，省掉客户端逐季拉集的
  /// N 次往返。[seriesId] 把范围限定到本剧；[limit] 通常取 1（只要首条）。
  ///
  /// 空结果是正常语义（全剧看完 / 服务端不给推荐），调用方须自备回退——本端点只是快路径。
  /// `UserData` 显式请求：列表端点默认不回 `PlaybackPositionTicks`/`Played`；`MediaStreams`
  /// 供选集卡清晰度角标，与 `getItems` 取集时的 `Fields` 对齐。
  Future<List<Map<String, Object?>>> getNextUpEpisodes({
    required String serverUrl,
    required String userId,
    required String accessToken,
    required String seriesId,
    int limit = 1,
    String fields = 'Overview,UserData,MediaStreams',
  }) async {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    final query = <String, Object?>{
      'api_key': accessToken,
      'UserId': userId.trim(),
      'SeriesId': seriesId.trim(),
      'Limit': limit,
      if (fields.trim().isNotEmpty) 'Fields': fields.trim(),
    };
    return _getItemList('$normalizedServerUrl/Shows/NextUp', query);
  }

  /// 直链直播 URL——Emby 原文件 static 直链，供播放层装配 `MpvMediaSource.url`。
  ///
  /// `GET /Videos/{itemId}/stream`，`Static=true` 表示不转码、原样投递整文件（mpv 直接吃
  /// 原始容器，所有内嵌音轨/字幕在 mpv 侧按轨道号切换，无服务端转码会话/PlaySessionId
  /// 生命周期）。[mediaSourceId] 指定多版本中的某一版（多 `MediaSources` 时必带）；
  /// [container] 非空时拼进路径（如 `stream.mkv`），帮 mpv 识别容器。`api_key` 自鉴权；
  /// `*.fnos.net` 中转域名的 entry-token cookie 由播放 headers 携带（不进 URL）。
  ///
  /// 纯字符串构造，不发请求（故无 entry-token 拦截器介入；过闸靠 headers）。
  String buildStreamUrl({
    required String serverUrl,
    required String itemId,
    required String mediaSourceId,
    required String accessToken,
    String container = '',
  }) {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    final path = container.trim().isNotEmpty
        ? 'stream.${container.trim()}'
        : 'stream';
    final query = <String, String>{
      'Static': 'true',
      if (mediaSourceId.trim().isNotEmpty)
        'MediaSourceId': mediaSourceId.trim(),
      'api_key': accessToken,
    };
    final qs = query.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$normalizedServerUrl/Videos/${itemId.trim()}/$path?$qs';
  }

  /// 服务端转码 HLS 直链——`GET /Videos/{itemId}/master.m3u8`，`api_key` 自鉴权。
  ///
  /// 画质切换的转码档投递：服务端按 [videoBitrate]（bps 上限）+ [maxHeight]（竖直分辨率上限）
  /// 出 h264/aac 的 HLS 流，mpv 直接吃 m3u8。Emby 会先产出完整时长的 playlist、分片按需转码，
  /// 故 seek 可靠（服务端从目标位重启 ffmpeg）。[playSessionId] 为客户端生成的会话标识，
  /// 服务端据此跟踪/回收转码任务（切档时配合 [stopActiveEncodings] 停旧任务）。
  /// [audioStreamIndex] 为选中音轨的容器 Index——转码流只带这一条音轨（切音轨须重载会话）。
  /// 码率上限内服务端允许视频流拷贝（不强制重编码），带宽语义不变、省服务器 CPU。
  /// 纯字符串构造，不发请求（过 fnos 中转闸的 entry-token cookie 由播放 headers 携带）。
  String buildHlsStreamUrl({
    required String serverUrl,
    required String itemId,
    required String mediaSourceId,
    required String accessToken,
    required String playSessionId,
    required int videoBitrate,
    required int maxHeight,
    int? audioStreamIndex,
  }) {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    final query = <String, String>{
      'DeviceId': deviceId,
      if (mediaSourceId.trim().isNotEmpty)
        'MediaSourceId': mediaSourceId.trim(),
      if (playSessionId.trim().isNotEmpty)
        'PlaySessionId': playSessionId.trim(),
      'VideoCodec': 'h264',
      'AudioCodec': 'aac',
      if (videoBitrate > 0) 'VideoBitrate': '$videoBitrate',
      'AudioBitrate': '192000',
      if (maxHeight > 0) 'MaxHeight': '$maxHeight',
      if (audioStreamIndex != null && audioStreamIndex >= 0)
        'AudioStreamIndex': '$audioStreamIndex',
      // ts 分片 + 首片即播：mpv/ffmpeg 的 hls demuxer 对 ts 兼容性最好。
      'SegmentContainer': 'ts',
      'MinSegments': '1',
      'api_key': accessToken,
    };
    final qs = query.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$normalizedServerUrl/Videos/${itemId.trim()}/master.m3u8?$qs';
  }

  /// 停止本设备的进行中转码任务——`DELETE /Videos/ActiveEncodings`，`api_key` 自鉴权。
  ///
  /// 切画质/切回原画/换集时回收旧转码 ffmpeg（不停会导致服务端旧任务空转到超时）。
  /// 按 DeviceId（+ 可选 [playSessionId] 精确到会话）定位任务。best-effort：失败由调用方吞。
  Future<void> stopActiveEncodings({
    required String serverUrl,
    required String accessToken,
    String playSessionId = '',
  }) async {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    await _dio.delete<Object?>(
      '$normalizedServerUrl/Videos/ActiveEncodings',
      queryParameters: <String, Object?>{
        'DeviceId': deviceId,
        if (playSessionId.trim().isNotEmpty)
          'PlaySessionId': playSessionId.trim(),
        'api_key': accessToken,
      },
      options: Options(headers: _jsonHeaders),
    );
  }

  /// 章节缩略图直链——`GET /Items/{itemId}/Images/Chapter/{index}`，`api_key` 自鉴权。
  ///
  /// 拖动 seek 预览用：Emby 的「章节图 / 视频预览缩略图提取」任务会在条目 `Chapters` 上
  /// 按位置生成图（带 `ImageTag`），网页客户端拖动时即取此端点。[chapterIndex] 为章节在
  /// `Chapters` 数组的下标，[tag] 为该章节 `ImageTag`（带上确保命中正确缓存版本）。
  /// [maxWidth] 限制服务端缩放后的宽度（省流，缩略图 320 足够）。纯字符串构造、不发请求
  /// （过 fnos 中转闸的 entry-token cookie 由播放 headers 复用）。
  String buildChapterImageUrl({
    required String serverUrl,
    required String itemId,
    required int chapterIndex,
    required String accessToken,
    String tag = '',
    int maxWidth = 320,
  }) {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    final query = <String, String>{
      if (tag.trim().isNotEmpty) 'tag': tag.trim(),
      if (maxWidth > 0) 'MaxWidth': '$maxWidth',
      'api_key': accessToken,
    };
    final qs = query.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$normalizedServerUrl/Items/${itemId.trim()}'
        '/Images/Chapter/$chapterIndex?$qs';
  }

  /// BIF 预览缩略图直链——`GET /Videos/{itemId}/index.bif`，`api_key` 自鉴权。
  ///
  /// Emby 的「视频预览缩略图提取」任务会按 MediaSource 生成 BIF 文件（Roku BIF 格式：
  /// 单文件打包整片按固定间隔抽帧的 JPEG + 时间索引，密度远高于章节图）。[width] 为
  /// 服务端预生成的档位宽度（Emby 默认 320）。未生成时该端点 404，由原生壳退回章节图。
  /// 纯字符串构造、不发请求（过 fnos 中转闸的 entry-token cookie 由播放 headers 复用）。
  String buildThumbnailBifUrl({
    required String serverUrl,
    required String itemId,
    required String mediaSourceId,
    required String accessToken,
    int width = 320,
  }) {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    final query = <String, String>{
      if (mediaSourceId.trim().isNotEmpty)
        'MediaSourceId': mediaSourceId.trim(),
      if (width > 0) 'Width': '$width',
      'api_key': accessToken,
    };
    final qs = query.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$normalizedServerUrl/Videos/${itemId.trim()}/index.bif?$qs';
  }

  /// 播放开始——`POST /Sessions/Playing`，`api_key` 自鉴权。
  ///
  /// 实测 Emby **必须先收到 PlaybackStart 建立播放会话**，之后的 `/Progress` 才会被持久化进
  /// `UserData.PlaybackPositionTicks`（否则只发 Progress 续播位不更新、继续观看不出条目）。
  /// 故原生壳直链直播首次回传进度前先调本方法开会话。[PlayMethod]=DirectStream（直链原文件）。
  Future<void> reportPlaybackStart({
    required String serverUrl,
    required String userId,
    required String accessToken,
    required String itemId,
    required String mediaSourceId,
    int positionTicks = 0,
  }) async {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    await _dio.post<Object?>(
      '$normalizedServerUrl/Sessions/Playing',
      queryParameters: <String, Object?>{'api_key': accessToken},
      data: _playStateBody(
        itemId,
        mediaSourceId,
        positionTicks,
        _playSessionIdFor(itemId),
      ),
      options: Options(
        contentType: Headers.jsonContentType,
        // 会话端点（/Sessions/Playing 系列）须带含 Token 的完整 X-Emby-Authorization，让 Emby
        // 定位/建立设备会话；缺 Token 时 Emby 以 null 作会话字典键 → 400。
        headers: <String, Object?>{
          ..._jsonHeaders,
          'X-Emby-Authorization': sessionAuthorizationHeaderValue(accessToken),
        },
      ),
    );
  }

  /// 回写播放进度——`POST /Sessions/Playing/Progress`，`api_key` 自鉴权。
  ///
  /// 让 Emby 更新该条目 `UserData.PlaybackPositionTicks`（续播位），使跨会话 / 跨客户端续播
  /// 一致。[positionTicks] 为 100ns 单位（秒 ×1e7）。须在 [reportPlaybackStart] 开会话后调用
  /// 才会被持久化。best-effort：失败由调用方静默吞。
  Future<void> reportPlaybackProgress({
    required String serverUrl,
    required String userId,
    required String accessToken,
    required String itemId,
    required String mediaSourceId,
    required int positionTicks,
    bool isPaused = false,
  }) async {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    await _dio.post<Object?>(
      '$normalizedServerUrl/Sessions/Playing/Progress',
      queryParameters: <String, Object?>{'api_key': accessToken},
      data: _playStateBody(
        itemId,
        mediaSourceId,
        positionTicks,
        _playSessionIdFor(itemId),
        isPaused,
        true,
      ),
      options: Options(
        contentType: Headers.jsonContentType,
        // 会话端点（/Sessions/Playing 系列）须带含 Token 的完整 X-Emby-Authorization，让 Emby
        // 定位/建立设备会话；缺 Token 时 Emby 以 null 作会话字典键 → 400。
        headers: <String, Object?>{
          ..._jsonHeaders,
          'X-Emby-Authorization': sessionAuthorizationHeaderValue(accessToken),
        },
      ),
    );
  }

  /// 播放停止——`POST /Sessions/Playing/Stopped`，`api_key` 自鉴权。关闭播放会话并落定最终
  /// 续播位（Emby 据此判断是否标记已看 / 移出继续观看）。best-effort：失败由调用方静默吞。
  Future<void> reportPlaybackStopped({
    required String serverUrl,
    required String userId,
    required String accessToken,
    required String itemId,
    required String mediaSourceId,
    required int positionTicks,
  }) async {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    await _dio.post<Object?>(
      '$normalizedServerUrl/Sessions/Playing/Stopped',
      queryParameters: <String, Object?>{'api_key': accessToken},
      data: _playStateBody(
        itemId,
        mediaSourceId,
        positionTicks,
        _playSessionIdFor(itemId),
      ),
      options: Options(
        contentType: Headers.jsonContentType,
        // 会话端点（/Sessions/Playing 系列）须带含 Token 的完整 X-Emby-Authorization，让 Emby
        // 定位/建立设备会话；缺 Token 时 Emby 以 null 作会话字典键 → 400。
        headers: <String, Object?>{
          ..._jsonHeaders,
          'X-Emby-Authorization': sessionAuthorizationHeaderValue(accessToken),
        },
      ),
    );
  }

  /// 设置 / 取消「收藏」——`POST`(收藏) / `DELETE`(取消) `/Users/{userId}/FavoriteItems/{itemId}`，
  /// `api_key` 自鉴权（与 getItems 等用户域端点同口径）。返回服务端回写的最终收藏态
  /// （响应体 `UserItemDataDto.IsFavorite`），缺则回退入参。
  Future<bool> setFavorite({
    required String serverUrl,
    required String userId,
    required String accessToken,
    required String itemId,
    required bool favorite,
  }) async {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    final path =
        '$normalizedServerUrl/Users/${userId.trim()}/FavoriteItems/${itemId.trim()}';
    final query = <String, Object?>{'api_key': accessToken};
    final response = favorite
        ? await _dio.post<Object?>(path, queryParameters: query)
        : await _dio.delete<Object?>(path, queryParameters: query);
    final data = response.data;
    if (data is Map && data['IsFavorite'] is bool) {
      return data['IsFavorite'] as bool;
    }
    return favorite;
  }

  /// 标记「已看 / 未看」——`POST`(已看) / `DELETE`(未看) `/Users/{userId}/PlayedItems/{itemId}`，
  /// `api_key` 自鉴权。返回服务端回写的最终已看态（响应体 `UserItemDataDto.Played`），缺则回退入参。
  Future<bool> setWatched({
    required String serverUrl,
    required String userId,
    required String accessToken,
    required String itemId,
    required bool watched,
  }) async {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    final path =
        '$normalizedServerUrl/Users/${userId.trim()}/PlayedItems/${itemId.trim()}';
    final query = <String, Object?>{'api_key': accessToken};
    final response = watched
        ? await _dio.post<Object?>(path, queryParameters: query)
        : await _dio.delete<Object?>(path, queryParameters: query);
    final data = response.data;
    if (data is Map && data['Played'] is bool) {
      return data['Played'] as bool;
    }
    return watched;
  }

  /// 同一条目（itemId）一次播放期间复用的 PlaySessionId。Emby 对 `PlayMethod` 非 DirectPlay
  /// 的播放会按 PlaySessionId 建流跟踪字典；body 不带 PlaySessionId 时服务端以 null 作字典键
  /// 抛 `Value cannot be null. (Parameter 'key')` → 400。Start/Progress/Stopped 须用同一个 id，
  /// 故按 itemId 缓存（切集 = 新 itemId = 新会话）。
  final Map<String, String> _playSessionIds = <String, String>{};

  String _playSessionIdFor(String itemId) =>
      _playSessionIds.putIfAbsent(itemId.trim(), () {
        final rnd = Random();
        final buf = StringBuffer();
        for (var i = 0; i < 32; i++) {
          buf.write(rnd.nextInt(16).toRadixString(16));
        }
        return buf.toString();
      });

  /// 三个播放会话端点共用的 PlaybackProgressInfo 体。[withProgressFields] 时附带
  /// IsPaused/EventName（仅 /Progress 需要）。PlayMethod/CanSeek 让 Emby 把它当成一次真实
  /// 直链播放会话登记（缺这些字段部分 Emby 版本会忽略上报、续播位不持久化）。[playSessionId]
  /// 让服务端流跟踪字典有非 null 键。
  static Map<String, Object?> _playStateBody(
    String itemId,
    String mediaSourceId,
    int positionTicks,
    String playSessionId, [
    bool isPaused = false,
    bool withProgressFields = false,
  ]) {
    return <String, Object?>{
      'ItemId': itemId.trim(),
      if (mediaSourceId.trim().isNotEmpty)
        'MediaSourceId': mediaSourceId.trim(),
      'PlaySessionId': playSessionId,
      'PositionTicks': positionTicks < 0 ? 0 : positionTicks,
      'PlayMethod': 'DirectStream',
      'CanSeek': true,
      if (withProgressFields) ...<String, Object?>{
        'IsPaused': isPaused,
        'EventName': 'TimeUpdate',
      },
    };
  }

  /// 外挂字幕直链——`GET /Videos/{itemId}/{mediaSourceId}/Subtitles/{index}/Stream.{ext}`，
  /// `api_key` 自鉴权。[streamIndex] 为字幕在 MediaStreams 的容器 Index，[format] 为字幕格式
  /// （srt / ass / vtt …，决定 URL 扩展名与服务端转码目标）。
  String buildSubtitleUrl({
    required String serverUrl,
    required String itemId,
    required String mediaSourceId,
    required int streamIndex,
    required String accessToken,
    String format = 'srt',
  }) {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    final ext = format.trim().isNotEmpty ? format.trim() : 'srt';
    return '$normalizedServerUrl/Videos/${itemId.trim()}/${mediaSourceId.trim()}'
        '/Subtitles/$streamIndex/Stream.$ext'
        '?api_key=${Uri.encodeQueryComponent(accessToken)}';
  }

  /// 下载外挂字幕文本——直链 [buildSubtitleUrl] 取字幕全文，供原生壳落临时文件后 `sub-add`。
  ///
  /// 经 [_dio] 取流（同 EmbyApi 其它请求，过 fnos 中转闸的 entry-token cookie 由拦截器注入），
  /// 故不像视频直链需在 headers 手动塞 cookie。`ResponseType.plain` 拿原始文本而非 JSON 解析。
  /// 空响应返回空串，由调用方判空。
  Future<String> downloadSubtitleText({
    required String serverUrl,
    required String itemId,
    required String mediaSourceId,
    required int streamIndex,
    required String accessToken,
    String format = 'srt',
  }) async {
    final url = buildSubtitleUrl(
      serverUrl: serverUrl,
      itemId: itemId,
      mediaSourceId: mediaSourceId,
      streamIndex: streamIndex,
      accessToken: accessToken,
      format: format,
    );
    final response = await _dio.get<Object?>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    return (response.data ?? '').toString();
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

  /// 认证请求（AuthenticateByName）的 `X-Emby-Authorization` 头值。
  ///
  /// MediaBrowser 家族的风味缝隙：Emby 维持历史行为（参数值不带引号）；Jellyfin 子类
  /// 覆写为带引号的规范格式（Jellyfin 10.8+ 文档形状）。头名固定 `X-Emby-Authorization`
  /// （Jellyfin 同样接受该兼容头名，无需换名缝隙）。
  @protected
  String get authorizationHeaderValue =>
      'MediaBrowser Client=$clientName, Device=$deviceName, '
      'DeviceId=$deviceId, Version=$clientVersion';

  /// 会话端点（/Sessions/Playing 系列）用的完整授权头：值加引号 + 带 `Token`（accessToken）。
  /// Emby 的 SessionManager 据此定位/建立设备会话——仅靠 `api_key` query、头里不带 Token 时，
  /// 部分版本以 null token 作字典键抛 `Value cannot be null. (Parameter 'key')` → 400、续播不落库。
  @protected
  String sessionAuthorizationHeaderValue(String token) =>
      'MediaBrowser Client="$clientName", Device="$deviceName", '
      'DeviceId="$deviceId", Version="$clientVersion", Token="${token.trim()}"';

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
