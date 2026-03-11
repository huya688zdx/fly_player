import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'item_list_request.dart';
import 'person_list_request.dart';
import '../models/authorized_dir_entry.dart';
import '../models/media_info.dart';
import '../models/media_library_item.dart';
import '../models/media_item.dart';
import '../models/person_credit.dart';
import '../models/person_detail_profile.dart';
import '../models/playback_stream.dart';
import '../models/play_info.dart';
import '../models/remote_subtitle.dart';
import '../models/server_play_session.dart';
import '../models/stream_list_option.dart';
import '../models/stream_track_data.dart';
import '../providers/nas_provider.dart';
import '../utils/app_exception.dart';
import '../utils/api_url_helper.dart';

/// Centralized Feiniu backend client.
///
/// Keeps request signing, common headers and response parsing in one place so
/// the rest of the app only deals with typed models and simple method calls.
class FeiniuApi {
  static const String _apiPrefix = '/v/api/v1';
  static const String _loginPath = '$_apiPrefix/login';
  static const String _userInfoPath = '$_apiPrefix/user/info';
  static const String _mediaListPath = '$_apiPrefix/mediadb/list';
  static const String _mediaSummaryPath = '$_apiPrefix/mediadb/sum';
  static const String _systemConfigPath = '$_apiPrefix/sys/config';
  static const String _systemVersionPath = '$_apiPrefix/sys/version';
  static const String _serverInfoPath = '$_apiPrefix/server/info';
  static const String _serverAuthorizedDirPath =
      '$_apiPrefix/server/getAppAuthorizedDir';
  static const String _searchListPath = '$_apiPrefix/search/list';
  static const String _itemListPath = '$_apiPrefix/item/list';
  static const String _favoriteListPath = '$_apiPrefix/favorite/list';
  static const String _runningTasksPath = '$_apiPrefix/task/running';
  static const String _userDataPath = '$_apiPrefix/user/getData';
  static const String _tagListPath = '$_apiPrefix/tag/list';
  static const String _tagGenresPath = '$_apiPrefix/tag/genres';
  static const String _tagIso3166Path = '$_apiPrefix/tag/iso3166';
    static const String _tagIso6392Path = '$_apiPrefix/tag/iso6392';
    static const String _playListPath = '$_apiPrefix/play/list';
    static const String _playInfoPath = '$_apiPrefix/play/info';
    static const String _playSetConfigByItemPath =
        '$_apiPrefix/play/setConfigByItem';
    static const String _playPlayPath = '$_apiPrefix/play/play';
  static const String _streamPath = '$_apiPrefix/stream';
  static const String _playRecordPath = '$_apiPrefix/play/record';
  static const String _favoritePath = '$_apiPrefix/item/favorite';
  static const String _watchedPath = '$_apiPrefix/item/watched';
  static const String _subtitleDownloadPathPrefix = '$_apiPrefix/subtitle/dl';
  static const String _subtitleSearchPath = '$_apiPrefix/subtitle/search';
  static const String _subtitleDownloadPath = '$_apiPrefix/subtitle/download';
  static const String _subtitleDeletePath = '$_apiPrefix/subtitle/del';
  static const String _itemPathPrefix = '$_apiPrefix/item';
  static const String _seasonListPathPrefix = '$_apiPrefix/season/list';
  static const String _episodeListPathPrefix = '$_apiPrefix/episode/list';
  static const String _streamListPathPrefix = '$_apiPrefix/stream/list';
  static const String _personListPathPrefix = '$_apiPrefix/person/list';
  static const String _personPathPrefix = '$_apiPrefix/person';
  static const String _personItemListPath = '$_apiPrefix/person/item/list';
  static const String _streamMetadataPath =
      '$_apiPrefix/mediadb/stream/metadata';
  static const String _mediaLocalePathPrefix = '/v/locales';

  final NasProvider nasProvider;
  final Dio _dio = Dio();
  final Random _random = Random();
  // Deduplicate identical paged-list requests during fast scrolling.
  final Map<String, Future<ItemListPage>> _itemListInflight = {};

  FeiniuApi(this.nasProvider) {
    _dio.options.baseUrl = ApiUrlHelper.normalizeBaseUrl(nasProvider.baseUrl);
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 10);
    _configureHttpsTrust(_dio, nasProvider.baseUrl);

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          debugPrint(
            '[API][REQ] ${options.method} ${options.baseUrl}${options.path} '
            'query=${options.queryParameters}',
          );
          if (nasProvider.token.isNotEmpty) {
            options.headers['Authorization'] = nasProvider.token;
            options.headers['Trim-MC-token'] = nasProvider.token;
          }
          if (_shouldAttachAuthx(options.path)) {
            options.headers['Authx'] = _buildAuthxHeader(options);
          }
          return handler.next(options);
        },
        onResponse: (response, handler) {
          final data = response.data;
          final backendCode = data is Map<String, dynamic>
              ? data['code']
              : null;
          final backendMsg = data is Map<String, dynamic>
              ? _backendMessage(data)
              : null;
          debugPrint(
            '[API][RESP] ${response.requestOptions.path} '
            'http=${response.statusCode} code=$backendCode message=$backendMsg',
          );
          return handler.next(response);
        },
        onError: (e, handler) {
          debugPrint(
            '[API][ERR] ${e.requestOptions.path} '
            'http=${e.response?.statusCode} err=${e.message}',
          );
          if (e.response?.statusCode == 401) {
            nasProvider.logout();
          }
          return handler.next(e);
        },
      ),
    );
  }

  // Authentication
  Future<String> login(String userName, String password) {
    return _performLogin(
      _dio,
      userName,
      password,
      baseUrlLabel: nasProvider.baseUrl,
    );
  }

  static Future<String> loginWithBaseUrl({
    required String baseUrl,
    required String userName,
    required String password,
  }) {
    final dio = Dio()
      ..options.baseUrl = ApiUrlHelper.normalizeBaseUrl(baseUrl)
      ..options.connectTimeout = const Duration(seconds: 10)
      ..options.receiveTimeout = const Duration(seconds: 10);
    _configureHttpsTrust(dio, baseUrl);
    return _performLogin(dio, userName, password, baseUrlLabel: baseUrl);
  }

  static Future<String> _performLogin(
    Dio dio,
    String userName,
    String password, {
    required String baseUrlLabel,
  }) async {
    debugPrint('[LOGIN] start user=$userName baseUrl=$baseUrlLabel');
    try {
      final response = await dio.post(
        _loginPath,
        data: {'userName': userName, 'password': password},
      );
      final payload = response.data;
      if (payload is Map<String, dynamic> && payload['code'] == 0) {
        final data = payload['data'];
        if (data is Map<String, dynamic>) {
          final token = data['token']?.toString() ?? '';
          if (token.isNotEmpty) {
            debugPrint('[LOGIN] success');
            return token;
          }
        }
      }
      final message = _backendMessageOf(payload) ?? 'Login failed';
      debugPrint('[LOGIN] failed backend message=$message');
      throw AppException.api(
        action: 'login',
        message: message,
        code: payload is Map<String, dynamic>
            ? _toInt(payload['code'], fallback: 0)
            : null,
      );
    } on DioException catch (e) {
      final exception = AppException.fromDio(e, action: 'login');
      debugPrint('[LOGIN] dio exception ${exception.message}');
      throw exception;
    } catch (e) {
      debugPrint('[LOGIN] exception $e');
      throw AppException.from(
        e,
        action: 'login',
        fallbackKind: AppExceptionKind.unauthorized,
      );
    }
  }

  Future<Map<String, dynamic>> getUserInfo() async {
    try {
      final response = await _dio.get(_userInfoPath);
      return _extractDataMap(response.data, 'user info');
    } catch (e) {
      throw AppException.from(
        e,
        action: 'user info',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  // Media library
  Future<List<MediaItem>> getMediaList() async {
    try {
      final response = await _dio.get(_mediaListPath);
      final items = _extractDataList(
        response.data,
        'media list',
      ).map(MediaItem.fromJson).toList();
      debugPrint('[API][LIST] items=${items.length}');
      return items;
    } catch (e) {
      throw AppException.from(
        e,
        action: 'media list',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  Future<Map<String, dynamic>> getMediaSummary() async {
    try {
      final response = await _dio.get(_mediaSummaryPath);
      return _extractDataMap(response.data, 'media summary');
    } catch (e) {
      throw AppException.from(
        e,
        action: 'media summary',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  Future<Map<String, dynamic>> getMediaLocaleMap({
    String locale = 'zh-CN',
  }) async {
    try {
      final response = await _dio.get<List<int>>(
        '$_mediaLocalePathPrefix/$locale/media.json',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) return const <String, dynamic>{};

      final text = utf8.decode(bytes, allowMalformed: true);
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        return const <String, dynamic>{};
      }
      return _normalizeLocaleMap(decoded);
    } catch (e) {
      debugPrint('[API][LOCALE] load failed locale=$locale error=$e');
      return const <String, dynamic>{};
    }
  }

  static void _configureHttpsTrust(Dio dio, String urlOrBaseUrl) {
    if (kIsWeb) return;
    final normalized = ApiUrlHelper.normalizeBaseUrl(urlOrBaseUrl);
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty) {
      return;
    }
    if (!_isPrivateHost(uri.host)) return;

    final adapter = dio.httpClientAdapter;
    if (adapter is IOHttpClientAdapter) {
      adapter.createHttpClient = () {
        final client = HttpClient();
        client.badCertificateCallback = (cert, certHost, port) {
          return certHost == uri.host;
        };
        return client;
      };
    }
  }

  static bool _isPrivateHost(String host) {
    if (host == 'localhost' || host == '127.0.0.1') return true;
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final octets = parts.map(int.tryParse).toList();
    if (octets.any((value) => value == null)) return false;
    final first = octets[0]!;
    final second = octets[1]!;
    return first == 10 ||
        first == 127 ||
        (first == 192 && second == 168) ||
        (first == 172 && second >= 16 && second <= 31);
  }

  Map<String, dynamic> _normalizeLocaleMap(Map<String, dynamic> input) {
    final out = <String, dynamic>{};
    input.forEach((key, value) {
      out[key] = _normalizeLocaleValue(value);
    });
    return out;
  }

  dynamic _normalizeLocaleValue(dynamic value) {
    if (value is Map<String, dynamic>) {
      return _normalizeLocaleMap(value);
    }
    if (value is Map) {
      final converted = <String, dynamic>{};
      value.forEach((k, v) {
        converted['$k'] = _normalizeLocaleValue(v);
      });
      return converted;
    }
    if (value is List) {
      return value.map(_normalizeLocaleValue).toList();
    }
    if (value is String) {
      return _fixMojibake(value);
    }
    return value;
  }

  // Some locale/tag payloads are returned with mojibake. Repair them once here.
  String _fixMojibake(String input) {
    if (input.isEmpty) return input;
    if (!RegExp(r'[脙脗芒氓忙莽猫茅冒茂]').hasMatch(input)) {
      return input;
    }
    try {
      final repaired = utf8.decode(latin1.encode(input), allowMalformed: true);
      if (RegExp(r'[\u4e00-\u9fff]').hasMatch(repaired)) {
        return repaired;
      }
      return input;
    } catch (_) {
      return input;
    }
  }

  String _decodeTextBytes(List<int> bytes) {
    if (bytes.isEmpty) return '';
    try {
      if (bytes.length >= 3 &&
          bytes[0] == 0xEF &&
          bytes[1] == 0xBB &&
          bytes[2] == 0xBF) {
        return _fixMojibake(
          utf8.decode(bytes.sublist(3), allowMalformed: true),
        );
      }
      if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
        return _fixMojibake(
          _decodeUtf16Bytes(bytes.sublist(2), littleEndian: true),
        );
      }
      if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
        return _fixMojibake(
          _decodeUtf16Bytes(bytes.sublist(2), littleEndian: false),
        );
      }
      return _fixMojibake(utf8.decode(bytes, allowMalformed: true));
    } catch (_) {
      try {
        return _fixMojibake(latin1.decode(bytes, allowInvalid: true));
      } catch (_) {
        return utf8.decode(bytes, allowMalformed: true);
      }
    }
  }

  String _decodeUtf16Bytes(List<int> bytes, {required bool littleEndian}) {
    final buffer = Uint8List.fromList(bytes);
    final byteData = ByteData.sublistView(buffer);
    final codeUnits = <int>[];
    for (var offset = 0; offset + 1 < byteData.lengthInBytes; offset += 2) {
      codeUnits.add(
        byteData.getUint16(offset, littleEndian ? Endian.little : Endian.big),
      );
    }
    return String.fromCharCodes(codeUnits);
  }

  // System
  Future<Map<String, dynamic>> getSystemConfig() async {
    try {
      final response = await _dio.get(_systemConfigPath);
      return _extractDataMap(response.data, 'system config');
    } catch (e) {
      throw AppException.from(
        e,
        action: 'system config',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  Future<Map<String, dynamic>> getSystemVersion() async {
    try {
      final response = await _dio.get(_systemVersionPath);
      return _extractDataMap(response.data, 'system version');
    } catch (e) {
      throw AppException.from(
        e,
        action: 'system version',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  Future<Map<String, dynamic>> getServerInfo() async {
    try {
      final response = await _dio.get(_serverInfoPath);
      return _extractDataMap(response.data, 'server info');
    } catch (e) {
      throw AppException.from(
        e,
        action: 'server info',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  Future<List<AuthorizedDirEntry>> getAppAuthorizedDirs() async {
    try {
      final response = await _dio.get(_serverAuthorizedDirPath);
      final data = _extractDataMap(response.data, 'authorized dirs');
      final list = (data['authDirList'] as List?) ?? const <dynamic>[];
      return list
          .whereType<Map<String, dynamic>>()
          .map(AuthorizedDirEntry.fromJson)
          .toList();
    } catch (e) {
      throw AppException.from(
        e,
        action: 'authorized dirs',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  Future<List<MediaLibraryItem>> getItemsByCategoryGuid(
    String ancestorGuid, {
    int page = 1,
    int limit = 30,
  }) async {
    final result = await getItemsPageByCategoryGuid(
      ancestorGuid,
      page: page,
      pageSize: limit,
    );
    return result.items;
  }

  Future<List<MediaLibraryItem>> searchList(String query) async {
    try {
      final response = await _dio.get(
        _searchListPath,
        queryParameters: <String, dynamic>{'q': query},
      );
      return _extractDataList(
        response.data,
        'search list',
      ).map(MediaLibraryItem.fromJson).toList();
    } catch (e) {
      throw AppException.from(
        e,
        action: 'search',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  // Item list / favorite list
  Future<ItemListPage> getItemsPageByCategoryGuid(
    String ancestorGuid, {
    int page = 1,
    int pageSize = 30,
  }) async {
    final request = ItemListRequest.forAncestor(
      ancestorGuid,
      page: page,
      pageSize: pageSize,
    );
    return getItemsPageByRequest(request);
  }

  Future<ItemListPage> getItemsPageByRequest(ItemListRequest request) async {
    return getItemsPage(request.toJson());
  }

  Future<ItemListPage> getItemsPage(Map<String, dynamic> payload) async {
    final key = _stableJson(payload);
    final existing = _itemListInflight[key];
    if (existing != null) {
      debugPrint('[API][ITEM_LIST] dedup key=$key');
      return existing;
    }

    final future = _doGetItemsPage(payload, key);
    _itemListInflight[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_itemListInflight[key], future)) {
        _itemListInflight.remove(key);
      }
    }
  }

  Future<ItemListPage> getFavoritePage({
    Map<String, dynamic>? tags,
    String sortType = 'DESC',
    String sortColumn = 'create_time',
    int page = 1,
    int pageSize = 50,
  }) async {
    final payload = <String, dynamic>{
      'tags': tags ?? const <String, dynamic>{},
      'sort_type': sortType,
      'sort_column': sortColumn,
      'page': page,
      'page_size': pageSize,
    };
    final key = 'favorite:${_stableJson(payload)}';
    final existing = _itemListInflight[key];
    if (existing != null) {
      debugPrint('[API][FAVORITE_LIST] dedup key=$key');
      return existing;
    }
    final future = _doGetFavoritePage(payload, key);
    _itemListInflight[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_itemListInflight[key], future)) {
        _itemListInflight.remove(key);
      }
    }
  }

  Future<ItemListPage> _doGetItemsPage(
    Map<String, dynamic> payload,
    String key,
  ) async {
    try {
      debugPrint('[API][ITEM_LIST] request payload=$payload');
      final response = await _dio.post(_itemListPath, data: payload);
      final page = _extractItemListPage(response.data, 'item list');
      debugPrint(
        '[API][ITEM_LIST] key=$key items=${page.items.length} total=${page.total}',
      );
      return page;
    } catch (e) {
      throw AppException.from(
        e,
        action: 'item list',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  Future<ItemListPage> _doGetFavoritePage(
    Map<String, dynamic> payload,
    String key,
  ) async {
    try {
      debugPrint('[API][FAVORITE_LIST] request payload=$payload');
      final response = await _dio.post(_favoriteListPath, data: payload);
      final page = _extractItemListPage(response.data, 'favorite list');
      debugPrint(
        '[API][FAVORITE_LIST] key=$key items=${page.items.length} total=${page.total}',
      );
      return page;
    } catch (e) {
      throw AppException.from(
        e,
        action: 'favorite list',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  Future<Map<String, dynamic>> getRunningTasks() async {
    final response = await _dio.get(_runningTasksPath);
    return _extractDataMap(response.data, 'task running');
  }

  // User preferences / tags
  Future<UserListSetting?> getUserListSetting(String ancestorGuid) async {
    try {
      final response = await _dio.post(
        _userDataPath,
        data: {'key': 'mdb:list:setting', 'mdb_guid': ancestorGuid},
      );

      final payload = response.data;
      if (payload is! Map<String, dynamic> || payload['code'] != 0) {
        return null;
      }

      final data = payload['data'];
      if (data is! Map<String, dynamic>) {
        return null;
      }

      final rawValue = data['value'];
      if (rawValue is! String || rawValue.isEmpty) {
        return null;
      }
      final decoded = jsonDecode(rawValue);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return UserListSetting.fromJson(decoded);
    } catch (e) {
      debugPrint('[API][USER_SETTING] load failed: $e');
      return null;
    }
  }

  Future<Map<String, List<dynamic>>> getTagList({
    String ancestorGuid = '',
    int isFavorite = 0,
  }) async {
    final query = <String, dynamic>{'is_favorite': isFavorite};
    if (ancestorGuid.trim().isNotEmpty) {
      query['ancestor_guid'] = ancestorGuid;
    }
    final response = await _dio.get(_tagListPath, queryParameters: query);
    final data = _extractDataMap(response.data, 'tag list');
    final result = <String, List<dynamic>>{};
    data.forEach((key, value) {
      if (value is List) {
        result[key] = value;
      }
    });
    return result;
  }

  Future<Map<int, String>> getTagGenresMap({String lan = 'zh-CN'}) async {
    final response = await _dio.get(
      _tagGenresPath,
      queryParameters: {'lan': lan},
    );
    final data = _tryExtractDataList(response.data);
    if (data == null) return const {};
    final map = <int, String>{};
    for (final entry in data) {
      if (entry is Map<String, dynamic>) {
        final id = int.tryParse('${entry['id']}');
        final value = entry['value']?.toString();
        if (id != null && value != null && value.isNotEmpty) {
          map[id] = value;
        }
      }
    }
    return map;
  }

  Future<Map<String, String>> getTagIso3166Map({String lan = 'zh-CN'}) async {
    final response = await _dio.get(
      _tagIso3166Path,
      queryParameters: {'lan': lan},
    );
    final data = _tryExtractDataList(response.data);
    if (data == null) return const <String, String>{};
    final map = <String, String>{};
    for (final entry in data) {
      if (entry is Map<String, dynamic>) {
        final key = (entry['key'] ?? '').toString().trim().toUpperCase();
        final value = _fixMojibake((entry['value'] ?? '').toString().trim());
        if (key.isNotEmpty && value.isNotEmpty) {
          map[key] = value;
        }
      }
    }
    return map;
  }

  Future<Map<String, String>> getTagIso6392Map({String lan = 'zh-CN'}) async {
    final response = await _dio.get(
      _tagIso6392Path,
      queryParameters: {'lan': lan},
    );
    final data = _tryExtractDataList(response.data);
    if (data == null) return const <String, String>{};
    final map = <String, String>{};
    for (final entry in data) {
      if (entry is Map<String, dynamic>) {
        final key = (entry['key'] ?? '').toString().trim().toLowerCase();
        final value = _fixMojibake((entry['value'] ?? '').toString().trim());
        if (key.isNotEmpty && value.isNotEmpty) {
          map[key] = value;
        }
      }
    }
    return map;
  }

  // Playback / item actions
  Future<List<MediaLibraryItem>> getPlayList() async {
    try {
      final response = await _dio.get(_playListPath);
      final items = _extractDataList(
        response.data,
        'play list',
      ).map(MediaLibraryItem.fromJson).toList();
      debugPrint('[API][PLAY_LIST] items=${items.length}');
      return items;
    } catch (e) {
      throw AppException.from(
        e,
        action: 'play list',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  Future<PlayInfoData> getPlayInfo(String itemGuid) async {
    try {
      final response = await _dio.post(
        _playInfoPath,
        data: {'item_guid': itemGuid},
      );
      final data = _extractDataMap(response.data, 'play info');
      return PlayInfoData.fromJson(data);
    } catch (e) {
      throw AppException.from(
        e,
        action: 'play info',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  Future<void> setPlayConfigByItem({
    required String itemGuid,
    int? skipOpening,
    int? skipEnding,
  }) async {
    try {
      final response = await _dio.post(
        _playSetConfigByItemPath,
        data: <String, dynamic>{
          'guid': itemGuid,
          'skip_opening': skipOpening,
          'skip_ending': skipEnding,
        },
      );
      _requireSuccessPayload(response.data, 'play config');
    } catch (e) {
      throw AppException.from(
        e,
        action: 'play config',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  Future<PlaybackStreamData> getPlaybackStream(
    String mediaGuid, {
    int level = 1,
    String userAgent = _defaultPlaybackUserAgent,
  }) async {
    try {
      final response = await _dio.post(
        _streamPath,
        data: <String, dynamic>{
          'media_guid': mediaGuid,
          'ip': await _ensurePlaybackClientId(),
          'header': <String, dynamic>{
            'User-Agent': <String>[userAgent],
          },
          'level': level,
        },
      );
      final data = _extractDataMap(response.data, 'playback stream');
      return PlaybackStreamData.fromJson(data);
    } catch (e) {
      throw AppException.from(
        e,
        action: 'playback stream',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  Future<ServerPlaySessionData> createServerPlaySession({
    required String mediaGuid,
    required String videoGuid,
    required String audioGuid,
    String subtitleGuid = '',
    String videoEncoder = '',
    String resolution = '',
    int bitrate = 0,
    int? startTimestamp,
    String audioEncoder = '',
    int channels = 0,
  }) async {
    try {
      final response = await _dio.post(
        _playPlayPath,
        data: <String, dynamic>{
          'media_guid': mediaGuid.trim(),
          'video_guid': videoGuid.trim(),
          'video_encoder': videoEncoder.trim(),
          'resolution': resolution.trim(),
          'bitrate': bitrate,
          if (startTimestamp != null) 'startTimestamp': startTimestamp,
          'audio_encoder': audioEncoder.trim(),
          'audio_guid': audioGuid.trim(),
          'subtitle_guid': subtitleGuid.trim(),
          'channels': channels,
        },
      );
      final data = _extractDataMap(response.data, 'server play session');
      return ServerPlaySessionData.fromJson(data);
    } catch (e) {
      throw AppException.from(
        e,
        action: 'server play session',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  String getSubtitleDownloadUrl(String subtitleGuid) {
    final base = ApiUrlHelper.normalizeBaseUrl(nasProvider.baseUrl);
    return '$base$_subtitleDownloadPathPrefix/$subtitleGuid';
  }

  Future<String> downloadSubtitleText(String subtitleGuid) async {
    try {
      final response = await _dio.get<List<int>>(
        '$_subtitleDownloadPathPrefix/$subtitleGuid',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data ?? const <int>[];
      if (bytes.isEmpty) return '';
      return _decodeTextBytes(bytes);
    } catch (e) {
      throw AppException.from(
        e,
        action: 'subtitle download',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  Future<RemoteSubtitleSearchResult> searchRemoteSubtitles({
    required String mediaGuid,
    required String language,
  }) async {
    try {
      final response = await _dio.post(
        _subtitleSearchPath,
        data: <String, dynamic>{
          'lan': language.trim(),
          'media_guid': mediaGuid.trim(),
        },
      );
      final data = _extractDataMap(response.data, 'subtitle search');
      return RemoteSubtitleSearchResult.fromJson(data);
    } catch (e) {
      throw AppException.from(
        e,
        action: 'subtitle search',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  Future<RemoteSubtitleDownloadResult> downloadRemoteSubtitle({
    required String mediaGuid,
    required String trimId,
    int syncDownload = 1,
  }) async {
    try {
      final response = await _dio.post(
        _subtitleDownloadPath,
        data: <String, dynamic>{
          'media_guid': mediaGuid.trim(),
          'trim_id': trimId.trim(),
          'sync_download': syncDownload,
        },
      );
      final data = _extractDataMap(response.data, 'subtitle save');
      return RemoteSubtitleDownloadResult.fromJson(data);
    } catch (e) {
      throw AppException.from(
        e,
        action: 'subtitle save',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  Future<void> deleteSubtitle({
    required String subtitleGuid,
    String mediaGuid = '',
  }) async {
    try {
      final response = await _dio.delete(
        _subtitleDeletePath,
        data: <String, dynamic>{
          'guid': subtitleGuid.trim(),
          'subtitle_guid': subtitleGuid.trim(),
          if (mediaGuid.trim().isNotEmpty) 'media_guid': mediaGuid.trim(),
        },
      );
      _requireSuccessPayload(response.data, 'subtitle delete');
    } catch (e) {
      throw AppException.from(
        e,
        action: 'subtitle delete',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  Future<void> recordPlayback({
    required String itemGuid,
    required String mediaGuid,
    required String videoGuid,
    String? audioGuid,
    String? subtitleGuid,
    String? resolution,
    int? bitrate,
    required int ts,
    required int duration,
    String? playLink,
  }) async {
    try {
      await _dio.post(
        _playRecordPath,
        data: <String, dynamic>{
          'item_guid': itemGuid,
          'media_guid': mediaGuid,
          'video_guid': videoGuid,
          'audio_guid': (audioGuid ?? '').trim(),
          'subtitle_guid': (subtitleGuid ?? '').trim(),
          'resolution': (resolution ?? '').trim(),
          'bitrate': bitrate ?? 0,
          'ts': ts,
          'duration': duration,
          'play_link': (playLink ?? '').trim(),
        },
      );
    } catch (e) {
      throw AppException.from(
        e,
        action: 'playback record',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  Map<String, String> buildSignedHeadersForUrl(
    String url, {
    String method = 'GET',
    dynamic body,
    Map<String, String> extraHeaders = const <String, String>{},
  }) {
    final uri = Uri.tryParse(url);
    final headers = <String, String>{
      if (nasProvider.token.isNotEmpty) 'Authorization': nasProvider.token,
      if (nasProvider.token.isNotEmpty) 'Trim-MC-token': nasProvider.token,
      if ((uri?.path ?? '').startsWith('$_apiPrefix/media/range/'))
        'Range': 'bytes=0-',
      ...extraHeaders,
    };

    final path = uri?.path ?? '';
    if (_shouldAttachAuthx(path)) {
      headers['Authx'] = _buildAuthxHeaderFor(
        method: method,
        path: path,
        body: body,
      );
    }
    return headers;
  }

  Map<String, String> buildPlaybackHeadersForUrl(
    String url, {
    String method = 'GET',
    dynamic body,
    Map<String, String> extraHeaders = const <String, String>{},
  }) {
    return buildSignedHeadersForUrl(
      url,
      method: method,
      body: body,
      extraHeaders: <String, String>{
        'User-Agent': _defaultPlaybackUserAgent,
        ...extraHeaders,
      },
    );
  }

  Future<bool> setFavorite(String itemGuid, {required bool favorite}) async {
    try {
      dynamic payload;
      final body = {'item_guid': itemGuid};
      if (favorite) {
        final response = await _dio.put(_favoritePath, data: body);
        payload = response.data;
      } else {
        final response = await _dio.delete(_favoritePath, data: body);
        payload = response.data;
      }

      if (payload is! Map<String, dynamic> || payload['code'] != 0) {
        throw AppException.api(
          action: 'set favorite',
          message: _backendMessage(payload) ?? 'Failed to set favorite',
          code: payload is Map<String, dynamic>
              ? _toInt(payload['code'], fallback: 0)
              : null,
        );
      }

      return favorite;
    } catch (e) {
      throw AppException.from(
        e,
        action: 'set favorite',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  Future<bool> setWatched(String itemGuid, {required bool watched}) async {
    try {
      dynamic payload;
      final body = {'item_guid': itemGuid};
      if (watched) {
        final response = await _dio.post(_watchedPath, data: body);
        payload = response.data;
      } else {
        final response = await _dio.delete(_watchedPath, data: body);
        payload = response.data;
      }

      if (payload is! Map<String, dynamic> || payload['code'] != 0) {
        throw AppException.api(
          action: 'set watched',
          message: _backendMessage(payload) ?? 'Failed to set watched',
          code: payload is Map<String, dynamic>
              ? _toInt(payload['code'], fallback: 0)
              : null,
        );
      }

      return watched;
    } catch (e) {
      throw AppException.from(
        e,
        action: 'set watched',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  Future<Map<String, dynamic>> getItemDetail(String itemGuid) async {
    try {
      final response = await _dio.get('$_itemPathPrefix/$itemGuid');
      return _extractDataMap(response.data, 'item detail');
    } catch (e) {
      throw AppException.from(
        e,
        action: 'item detail',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  Future<List<MediaLibraryItem>> getSeasonList(String itemGuid) async {
    try {
      final response = await _dio.get('$_seasonListPathPrefix/$itemGuid');
      return _extractDataList(
        response.data,
        'season list',
      ).map(MediaLibraryItem.fromJson).toList();
    } catch (e) {
      throw AppException.from(
        e,
        action: 'season list',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  Future<List<MediaLibraryItem>> getEpisodeList(String seasonGuid) async {
    try {
      final response = await _dio.get('$_episodeListPathPrefix/$seasonGuid');
      return _extractDataList(
        response.data,
        'episode list',
      ).map(MediaLibraryItem.fromJson).toList();
    } catch (e) {
      throw AppException.from(
        e,
        action: 'episode list',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  Future<List<StreamListOption>> getStreamListOptions(String itemGuid) async {
    final data = await getStreamTrackData(itemGuid);
    return data.options;
  }

  Future<StreamTrackData> getStreamTrackData(String itemGuid) async {
    try {
      final response = await _dio.get('$_streamListPathPrefix/$itemGuid');
      final data = _extractDataMap(response.data, 'stream list');
      final trackData = StreamTrackData.fromApiData(data);
      debugPrint(
        '[API][STREAM_LIST] item=$itemGuid options=${trackData.options.length}',
      );
      return trackData;
    } catch (e) {
      throw AppException.from(
        e,
        action: 'stream list',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  // People
  Future<List<PersonCredit>> getPersonList(
    String itemGuid, {
    PersonListRequest request = const PersonListRequest(),
  }) async {
    try {
      final response = await _dio.post(
        '$_personListPathPrefix/$itemGuid',
        data: request.toJson(),
      );
      final data = _extractDataMap(response.data, 'person list');
      final list = (data['list'] as List?) ?? const <dynamic>[];
      final people =
          list
              .whereType<Map<String, dynamic>>()
              .map(PersonCredit.fromJson)
              .toList()
            ..sort((a, b) => a.order.compareTo(b.order));
      debugPrint('[API][PERSON_LIST] item=$itemGuid count=${people.length}');
      return people;
    } catch (e) {
      throw AppException.from(
        e,
        action: 'person list',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  Future<PersonDetailProfile> getPersonDetail(String personGuid) async {
    try {
      final response = await _dio.get('$_personPathPrefix/$personGuid');
      final data = _extractDataMap(response.data, 'person detail');
      return PersonDetailProfile.fromJson(data);
    } catch (e) {
      throw AppException.from(
        e,
        action: 'person detail',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  Future<ItemListPage> getPersonItemList({
    required String personGuid,
    required String job,
    int page = 1,
    int pageSize = 200,
    String sortColumn = 'update_time',
    String sortType = 'desc',
  }) async {
    try {
      final payload = <String, dynamic>{
        'person_guid': personGuid,
        'page': page,
        'page_size': pageSize,
        'job': job,
        'sort_column': sortColumn,
        'sort_type': sortType,
      };
      final response = await _dio.post(_personItemListPath, data: payload);
      return _extractItemListPage(response.data, 'person item list');
    } catch (e) {
      throw AppException.from(
        e,
        action: 'person related items',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  Future<MediaInfo> getStreamMetadata(String mediaGuid) async {
    try {
      final response = await _dio.get(
        _streamMetadataPath,
        queryParameters: {'media_guid': mediaGuid},
      );
      final data = _extractDataMap(response.data, 'media metadata');
      return MediaInfo.fromJson(data);
    } catch (e) {
      throw AppException.from(
        e,
        action: 'media metadata',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  // Helpers
  String getStreamUrl(String mediaGuid) {
    return ApiUrlHelper.streamUrl(nasProvider.baseUrl, mediaGuid);
  }

  Map<String, dynamic> _requireSuccessPayload(dynamic payload, String action) {
    if (payload is! Map<String, dynamic>) {
      throw AppException.api(
        action: action,
        message: 'Invalid response format for $action',
      );
    }
    if (payload['code'] != 0) {
      throw AppException.api(
        action: action,
        message: _backendMessage(payload) ?? 'Request failed for $action',
        code: _toInt(payload['code'], fallback: 0),
      );
    }
    return payload;
  }

  Map<String, dynamic> _extractDataMap(dynamic payload, String action) {
    final success = _requireSuccessPayload(payload, action);
    final data = success['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    return <String, dynamic>{'value': data};
  }

  List<Map<String, dynamic>> _extractDataList(dynamic payload, String action) {
    final success = _requireSuccessPayload(payload, action);
    final data = success['data'];
    if (data is! List) {
      throw AppException.api(
        action: action,
        message: 'Invalid $action payload',
      );
    }
    return data.whereType<Map<String, dynamic>>().toList();
  }

  List<dynamic>? _tryExtractDataList(dynamic payload) {
    if (payload is! Map<String, dynamic> || payload['code'] != 0) {
      return null;
    }
    final data = payload['data'];
    return data is List ? data : null;
  }

  ItemListPage _extractItemListPage(dynamic payload, String action) {
    final data = _extractDataMap(payload, action);
    final list = (data['list'] as List?) ?? const <dynamic>[];
    final items = list
        .whereType<Map<String, dynamic>>()
        .map(MediaLibraryItem.fromJson)
        .toList();
    final total = _toInt(data['total'], fallback: items.length);
    return ItemListPage(total: total, items: items);
  }

  static String? _backendMessageOf(dynamic payload) {
    if (payload is! Map<String, dynamic>) return null;
    final message = payload['message'] ?? payload['msg'];
    return message?.toString();
  }

  String? _backendMessage(dynamic payload) {
    return _backendMessageOf(payload);
  }

  bool _shouldAttachAuthx(String path) {
    if (path.startsWith('/v/media/')) return true;
    if (!path.startsWith(_apiPrefix)) return false;
    return path != _loginPath;
  }

  // Authx is required by most protected endpoints and signs method/path/body.
  String _buildAuthxHeader(RequestOptions options) {
    return _buildAuthxHeaderFor(
      method: options.method,
      path: options.path,
      body: options.data,
    );
  }

  String _buildAuthxHeaderFor({
    required String method,
    required String path,
    dynamic body,
  }) {
    final nonce = _generateNonce();
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final payload = _stableJson(body ?? <String, dynamic>{});
    final normalizedMethod = method.toUpperCase();
    final token = nasProvider.token;
    final signBase =
        '$normalizedMethod|$path|$payload|$nonce|$timestamp|$token';
    final sign = md5.convert(utf8.encode(signBase)).toString();
    debugPrint(
      '[API][AUTHX] method=$normalizedMethod path=$path nonce=$nonce timestamp=$timestamp sign=$sign',
    );
    return 'nonce=$nonce&timestamp=$timestamp&sign=$sign';
  }

  String _generateNonce() {
    final value = 100000 + _random.nextInt(900000);
    return value.toString();
  }

  String _stableJson(dynamic value) {
    return jsonEncode(_normalizeForStableJson(value));
  }

  static int _toInt(dynamic value, {required int fallback}) {
    if (value is int) return value;
    return int.tryParse('$value') ?? fallback;
  }

  dynamic _normalizeForStableJson(dynamic value) {
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      return <String, dynamic>{
        for (final e in entries)
          e.key.toString(): _normalizeForStableJson(e.value),
      };
    }
    if (value is List) {
      return value.map(_normalizeForStableJson).toList();
    }
    return value;
  }

  Future<String> _ensurePlaybackClientId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('playback_client_id') ?? '';
    if (existing.trim().isNotEmpty) return existing;

    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    final value = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    await prefs.setString('playback_client_id', value);
    return value;
  }
}

const String _defaultPlaybackUserAgent =
    'Mozilla/5.0 (Linux; Android 15; FlyPlayer) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Mobile Safari/537.36';

class ItemListPage {
  final int total;
  final List<MediaLibraryItem> items;

  const ItemListPage({required this.total, required this.items});

  bool get hasMore => items.length < total;
}

class UserListSetting {
  final String sortType;
  final String sortField;
  final String viewType;

  const UserListSetting({
    required this.sortType,
    required this.sortField,
    required this.viewType,
  });

  factory UserListSetting.fromJson(Map<String, dynamic> json) {
    return UserListSetting(
      sortType: (json['sort_type'] ?? 'DESC').toString().toUpperCase(),
      sortField: (json['sort_field'] ?? 'create_time').toString(),
      viewType: (json['view_type'] ?? '').toString(),
    );
  }
}
