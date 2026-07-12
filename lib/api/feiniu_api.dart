import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
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
import '../utils/private_network_http_overrides.dart';
import '../utils/swallowed_error_logger.dart';

const bool _verboseApiLogsEnabled = false;

void _apiVerboseLog(String message) {
  if (_verboseApiLogsEnabled) {
    debugPrint(message);
  }
}

Future<T> _parseOffMainIsolate<S, T>(S payload, T Function(S payload) parser) {
  if (kIsWeb) {
    return Future<T>.value(parser(payload));
  }
  return Isolate.run<T>(() => parser(payload));
}

List<MediaLibraryItem> _parseMediaLibraryItems(List<dynamic> data) {
  return data
      .whereType<Map>()
      .map(
        (entry) => MediaLibraryItem.fromJson(Map<String, dynamic>.from(entry)),
      )
      .toList(growable: false);
}

PlayInfoData _parsePlayInfoData(Map<String, dynamic> data) {
  return PlayInfoData.fromJson(Map<String, dynamic>.from(data));
}

StreamTrackData _parseStreamTrackData(Map<String, dynamic> data) {
  return StreamTrackData.fromApiData(Map<String, dynamic>.from(data));
}

List<PersonCredit> _parsePersonCredits(Map<String, dynamic> data) {
  final list = (data['list'] as List?) ?? const <dynamic>[];
  final people =
      list
          .whereType<Map>()
          .map(
            (entry) => PersonCredit.fromJson(Map<String, dynamic>.from(entry)),
          )
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
  return List<PersonCredit>.unmodifiable(people);
}

/// 登录流程的最终结果。
///
/// `resolvedBaseUrl` 是实际登录成功的服务器地址，可能和输入值不同，
/// 例如用户输入 FN Connect 标识时，会先解析为可直连地址。
class LoginWithBaseUrlResult {
  /// 登录成功后返回的令牌。
  final String token;

  /// 实际可用于后续请求的标准化 baseUrl。
  final String resolvedBaseUrl;

  /// 本次登录是否经过 FN Connect 地址解析。
  final bool usedFnConnect;

  /// FN Connect 相关诊断信息；普通直连登录时通常为空。
  final FnConnectLoginDiagnostic? diagnostic;

  const LoginWithBaseUrlResult({
    required this.token,
    required this.resolvedBaseUrl,
    this.usedFnConnect = false,
    this.diagnostic,
  });
}

/// FN Connect OAuth 所需的配置。
class FnConnectOauthConfig {
  /// FN Connect OAuth 回调后应连接的目标地址。
  final String baseUrl;

  /// FN Connect OAuth 对应的应用标识。
  final String appId;

  const FnConnectOauthConfig({required this.baseUrl, required this.appId});
}

/// FN Connect 地址发现结果的可展示诊断信息。
class FnConnectDiscoveryDiagnostic {
  /// 发现到的 DDNS 地址。
  final List<String> ddns;

  /// 发现到的局域网 IPv4 地址。
  final List<String> ipv4;

  /// 发现到的局域网 IPv6 地址。
  final List<String> ipv6;

  /// 发现到的公网 IPv4 地址。
  final List<String> publicIpv4;

  /// 发现到的公网 IPv6 地址。
  final List<String> publicIpv6;

  /// 发现到的 relay 主机列表。
  final List<String> relayHosts;

  /// HTTP 服务端口。
  final int httpPort;

  /// HTTPS 服务端口。
  final int httpsPort;

  const FnConnectDiscoveryDiagnostic({
    required this.ddns,
    required this.ipv4,
    required this.ipv6,
    required this.publicIpv4,
    required this.publicIpv6,
    required this.relayHosts,
    required this.httpPort,
    required this.httpsPort,
  });
}

/// 单个 FN Connect 登录尝试的诊断记录。
class FnConnectAttemptDiagnostic {
  /// 本次尝试的地址标签。
  final String label;

  /// 本次尝试使用的 baseUrl。
  final String baseUrl;

  /// 归一化后的尝试状态。
  final String status;

  /// 本次尝试的结果说明。
  final String message;

  const FnConnectAttemptDiagnostic({
    required this.label,
    required this.baseUrl,
    required this.status,
    required this.message,
  });
}

/// FN Connect 登录过程中累计的诊断信息。
class FnConnectLoginDiagnostic {
  /// 用户输入或解析得到的 FN Connect 标识。
  final String fnConnectId;

  /// 地址发现阶段的诊断数据。
  final FnConnectDiscoveryDiagnostic? discovery;

  /// 登录尝试记录。
  final List<FnConnectAttemptDiagnostic> attempts;

  const FnConnectLoginDiagnostic({
    required this.fnConnectId,
    required this.discovery,
    required this.attempts,
  });

  /// 返回一个追加了尝试记录的新诊断对象。
  FnConnectLoginDiagnostic withAttempt(FnConnectAttemptDiagnostic attempt) {
    return FnConnectLoginDiagnostic(
      fnConnectId: fnConnectId,
      discovery: discovery,
      attempts: List<FnConnectAttemptDiagnostic>.unmodifiable([
        ...attempts,
        attempt,
      ]),
    );
  }
}

/// FN Connect 登录失败时抛出的异常，包含可上报/展示的诊断信息。
class FnConnectLoginException implements Exception {
  /// 归一化后的登录错误。
  final AppException error;

  /// 失败时的完整诊断信息。
  final FnConnectLoginDiagnostic diagnostic;

  const FnConnectLoginException({
    required this.error,
    required this.diagnostic,
  });

  @override
  String toString() => error.toString();
}

class _FnConnectDiscoveryData {
  final List<String> ddns;
  final List<String> ipv4;
  final List<String> ipv6;
  final List<String> publicIpv4;
  final List<String> publicIpv6;
  final List<String> relayHosts;
  final int httpPort;
  final int httpsPort;

  const _FnConnectDiscoveryData({
    required this.ddns,
    required this.ipv4,
    required this.ipv6,
    required this.publicIpv4,
    required this.publicIpv6,
    required this.relayHosts,
    required this.httpPort,
    required this.httpsPort,
  });

  bool get hasAnyAddress =>
      ddns.isNotEmpty ||
      ipv4.isNotEmpty ||
      ipv6.isNotEmpty ||
      publicIpv4.isNotEmpty ||
      publicIpv6.isNotEmpty ||
      relayHosts.isNotEmpty;

  factory _FnConnectDiscoveryData.fromJson(Map<String, dynamic> json) {
    final port = json['port'];
    final portMap = port is Map<String, dynamic>
        ? port
        : const <String, dynamic>{};
    return _FnConnectDiscoveryData(
      ddns: _stringListOf(json['ddns']),
      ipv4: _stringListOf(json['ipv4']),
      ipv6: _stringListOf(json['ipv6']),
      publicIpv4: _stringListOf(json['publicIpv4']),
      publicIpv6: _stringListOf(json['publicIpv6']),
      relayHosts: _stringListOf(json['fn']),
      httpPort: _jsonInt(portMap['httpPort'], fallback: 5666),
      httpsPort: _jsonInt(portMap['httpsPort'], fallback: 5667),
    );
  }
}

class _FnConnectLoginCandidate {
  final String baseUrl;
  final String label;

  const _FnConnectLoginCandidate({required this.baseUrl, required this.label});
}

List<String> _stringListOf(dynamic value) {
  if (value is! List) return const <String>[];
  return value
      .map((entry) => entry.toString().trim())
      .where((entry) => entry.isNotEmpty)
      .toList();
}

FnConnectDiscoveryDiagnostic _diagnosticFromDiscovery(
  _FnConnectDiscoveryData discovery,
) {
  return FnConnectDiscoveryDiagnostic(
    ddns: List<String>.unmodifiable(discovery.ddns),
    ipv4: List<String>.unmodifiable(discovery.ipv4),
    ipv6: List<String>.unmodifiable(discovery.ipv6),
    publicIpv4: List<String>.unmodifiable(discovery.publicIpv4),
    publicIpv6: List<String>.unmodifiable(discovery.publicIpv6),
    relayHosts: List<String>.unmodifiable(discovery.relayHosts),
    httpPort: discovery.httpPort,
    httpsPort: discovery.httpsPort,
  );
}

int _jsonInt(dynamic value, {required int fallback}) {
  if (value is int) return value;
  return int.tryParse('$value') ?? fallback;
}

Future<bool?> _hasGlobalIpv6Connectivity() async {
  if (kIsWeb) return null;
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv6,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    return interfaces.any((interface) => interface.addresses.isNotEmpty);
  } catch (_) {
    return null;
  }
}

bool _isIpv6Host(String host) {
  final address = InternetAddress.tryParse(host);
  return address?.type == InternetAddressType.IPv6;
}

/// 下载任务的简化进度信息。
class DownloadTaskProgressInfo {
  /// 下载任务状态码。
  final int status;

  /// 当前进度百分比。
  final int percents;

  const DownloadTaskProgressInfo({
    required this.status,
    required this.percents,
  });

  /// 根据后端返回的 JSON 构造进度对象。
  factory DownloadTaskProgressInfo.fromJson(Map<String, dynamic> json) {
    return DownloadTaskProgressInfo(
      status: json['status'] is num ? (json['status'] as num).toInt() : 0,
      percents: json['percents'] is num ? (json['percents'] as num).toInt() : 0,
    );
  }
}

/// 飞牛后端 API 客户端。
///
/// 统一封装登录、鉴权头、缓存、错误转换和响应解析，调用方应优先通过
/// 类型化方法与模型访问后端能力，而不是重复拼接路径或处理公共异常。
class FeiniuApi {
  static const String _apiPrefix = '/v/api/v1';
  static const String _loginPath = '$_apiPrefix/login';
  static const String _authPath = '$_apiPrefix/auth';
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
  static const String _userSetDataPath = '$_apiPrefix/user/setData';
  static const String _folderListSettingKey = 'mdb:list:setting:folder';
  static const String _tagListPath = '$_apiPrefix/tag/list';
  static const String _tagGenresPath = '$_apiPrefix/tag/genres';
  static const String _tagIso3166Path = '$_apiPrefix/tag/iso3166';
  static const String _tagIso6392Path = '$_apiPrefix/tag/iso6392';
  static const String _playListPath = '$_apiPrefix/play/list';
  static const String _playInfoPath = '$_apiPrefix/play/info';
  static const String _playSetConfigByItemPath =
      '$_apiPrefix/play/setConfigByItem';
  static const String _playPlayPath = '$_apiPrefix/play/play';
  static const String _playMediaBridgePath = '$_apiPrefix/media/p';
  static const String _streamPath = '$_apiPrefix/stream';
  static const String _playRecordPath = '$_apiPrefix/play/record';
  static const String _favoritePath = '$_apiPrefix/item/favorite';
  static const String _watchedPath = '$_apiPrefix/item/watched';
  static const String _downloadResolutionPathPrefix =
      '$_apiPrefix/download/resolution';
  static const String _downloadTaskPath = '$_apiPrefix/download/task';
  static const String _downloadTaskProgressPath =
      '$_apiPrefix/download/taskProgress';
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
  static const String _fnConnectServiceBaseUrl = 'https://fnos.net';
  static const String _fnConnectServicePath = '/api/v1/fn/con';
  static const String _publicAuthxKey = 'NDzZTVxnRKP8Z0jXg1VAMonaG8akvh';
  static const String _publicAuthxSecret =
      '16CCEB3D-AB42-077D-36A1-F355324E4237';
  static const String _fnConnectApiKey = 'zIGtkc3dqZnJpd29qZXJqa2w7c';
  static const String _fnConnectAuthxPrefix = _publicAuthxKey;
  static final RegExp _fnConnectIdPattern = RegExp(r'^[a-z][a-z0-9-]{5,31}$');
  static final Map<String, Object?> _sharedResourceCache = <String, Object?>{};
  static final Map<String, Future<Object?>> _sharedResourceInflight =
      <String, Future<Object?>>{};
  static final Map<String, DateTime> _sharedResourceCacheTimes =
      <String, DateTime>{};
  static const Duration _homeReadCacheTtl = Duration(seconds: 8);
  static const Duration _playListCacheTtl = Duration(seconds: 2);
  static const Duration _detailReadCacheTtl = Duration(seconds: 4);

  /// 清理当前 Dart isolate 中的飞牛共享读取缓存，登出时避免旧 token 数据继续驻留。
  static void clearSharedResourceCache() {
    _sharedResourceCache.clear();
    _sharedResourceInflight.clear();
    _sharedResourceCacheTimes.clear();
  }

  final NasProvider nasProvider;
  final Dio _dio = Dio();
  final Random _random = Random();
  // Deduplicate identical paged-list requests during fast scrolling.
  final Map<String, Future<ItemListPage>> _itemListInflight = {};

  FeiniuApi(this.nasProvider, {HttpClientAdapter? httpClientAdapter}) {
    if (httpClientAdapter != null) {
      _dio.httpClientAdapter = httpClientAdapter;
    }
    _dio.options.baseUrl = ApiUrlHelper.normalizeBaseUrl(nasProvider.baseUrl);
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 10);
    _configureHttpsTrust(_dio, nasProvider.baseUrl);

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          _apiVerboseLog(
            '[API][REQ] ${options.method} ${options.baseUrl}${options.path} '
            'query=${options.queryParameters}',
          );
          if (nasProvider.token.isNotEmpty) {
            options.headers['Authorization'] = nasProvider.token;
            options.headers['Trim-MC-token'] = nasProvider.token;
          }
          if (shouldUseRelayModeCookieForBaseUrl(options.baseUrl)) {
            options.headers['Cookie'] = _mergeRelayCookie(
              options.headers['Cookie']?.toString() ?? '',
            );
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
          _apiVerboseLog(
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

  /// 使用当前 `NasProvider` 中配置的 baseUrl 发起用户名密码登录。
  Future<String> login(String userName, String password) {
    return _performLogin(
      _dio,
      userName,
      password,
      baseUrlLabel: nasProvider.baseUrl,
    );
  }

  /// 从用户输入中提取 FN Connect id。
  ///
  /// 支持纯 id、`*.fnos.net` 子域名和官网页面地址三种输入形式。
  static String? extractFnConnectIdFromInput(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) return null;
    final direct = trimmed.toLowerCase();
    if (_fnConnectIdPattern.hasMatch(direct)) {
      return direct;
    }

    final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(candidate);
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (host.endsWith('.fnos.net')) {
      final subdomain = host.substring(0, host.length - '.fnos.net'.length);
      if (_fnConnectIdPattern.hasMatch(subdomain)) {
        return subdomain;
      }
    }
    if (host == 'fnos.net' || host == 'www.fnos.net') {
      for (final segment in uri.pathSegments) {
        final normalized = segment.trim().toLowerCase();
        if (_fnConnectIdPattern.hasMatch(normalized)) {
          return normalized;
        }
      }
    }
    return null;
  }

  /// 根据用户输入的地址或 FN Connect 标识完成登录。
  ///
  /// 返回值里会带上最终可直连的 baseUrl，后续应保存这个地址而不是原始输入。
  static bool shouldUseRelayModeCookieForBaseUrl(String rawBaseUrl) {
    final normalizedBaseUrl = ApiUrlHelper.normalizeBaseUrl(rawBaseUrl);
    final uri = Uri.tryParse(normalizedBaseUrl);
    if (uri == null || uri.host.isEmpty) return false;
    final host = uri.host.toLowerCase();
    return host == 'fnos.net' || host.endsWith('.fnos.net');
  }

  static Future<LoginWithBaseUrlResult> loginWithBaseUrl({
    required String baseUrl,
    required String userName,
    required String password,
  }) async {
    final fnConnectId = extractFnConnectIdFromInput(baseUrl);
    if (fnConnectId != null) {
      return _loginWithFnConnect(
        fnConnectId: fnConnectId,
        userName: userName,
        password: password,
      );
    }

    final normalizedBaseUrl = ApiUrlHelper.normalizeBaseUrl(baseUrl);
    final uri = Uri.tryParse(normalizedBaseUrl);
    if (uri != null && _isIpv6Host(uri.host)) {
      final hasIpv6 = await _hasGlobalIpv6Connectivity();
      if (hasIpv6 == false) {
        throw AppException.api(
          action: 'login',
          message:
              'This device has no usable global IPv6 network and cannot connect to an IPv6 NAS directly. Android emulators usually only have link-local IPv6; use a real device or an available IPv6 network.',
        );
      }
    }
    final dio = _buildLoginDio(normalizedBaseUrl);
    final token = await _performLogin(
      dio,
      userName,
      password,
      baseUrlLabel: normalizedBaseUrl,
    );
    return LoginWithBaseUrlResult(
      token: token,
      resolvedBaseUrl: normalizedBaseUrl,
      usedFnConnect: false,
    );
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

  static Dio _buildLoginDio(String baseUrl) {
    final normalizedBaseUrl = ApiUrlHelper.normalizeBaseUrl(baseUrl);
    final dio = Dio()
      ..options.baseUrl = normalizedBaseUrl
      ..options.connectTimeout = const Duration(seconds: 10)
      ..options.receiveTimeout = const Duration(seconds: 12);
    _configureHttpsTrust(dio, normalizedBaseUrl);
    return dio;
  }

  /// 拉取 FN Connect OAuth 所需的 baseUrl 和 appId。
  static Future<FnConnectOauthConfig> fetchFnConnectOauthConfig({
    required String baseUrl,
    required String cookie,
  }) async {
    final normalizedBaseUrl = ApiUrlHelper.normalizeBaseUrl(baseUrl);
    final dio = _buildPublicApiDio(normalizedBaseUrl);
    try {
      final response = await dio.get(
        _systemConfigPath,
        options: Options(
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Cookie': _mergeRelayCookie(cookie),
            'Authx': _buildPublicAuthxHeader(path: _systemConfigPath),
          },
        ),
      );
      final payload = response.data;
      if (payload is! Map<String, dynamic>) {
        throw AppException.api(
          action: 'fn connect oauth config',
          message: 'Invalid FN Connect system config response',
        );
      }
      if (_jsonInt(payload['code'], fallback: -1) != 0) {
        throw AppException.api(
          action: 'fn connect oauth config',
          message:
              (payload['msg'] ??
                      payload['message'] ??
                      'Failed to load system config')
                  .toString(),
          code: _jsonInt(payload['code'], fallback: -1),
        );
      }
      final data = payload['data'];
      if (data is! Map<String, dynamic>) {
        throw AppException.api(
          action: 'fn connect oauth config',
          message: 'Missing FN Connect OAuth payload',
        );
      }
      final oauth = data['nas_oauth'];
      if (oauth is! Map<String, dynamic>) {
        throw AppException.api(
          action: 'fn connect oauth config',
          message: 'Missing FN Connect OAuth configuration',
        );
      }
      final appId = oauth['app_id']?.toString().trim() ?? '';
      if (appId.isEmpty) {
        throw AppException.api(
          action: 'fn connect oauth config',
          message: 'Missing FN Connect OAuth app id',
        );
      }
      final oauthUrl = oauth['url']?.toString().trim() ?? '';
      final targetBaseUrl = oauthUrl.isNotEmpty && oauthUrl != '://'
          ? ApiUrlHelper.normalizeBaseUrl(oauthUrl)
          : ApiUrlHelper.originFromBaseUrl(normalizedBaseUrl);
      return FnConnectOauthConfig(baseUrl: targetBaseUrl, appId: appId);
    } on DioException catch (e) {
      throw AppException.fromDio(e, action: 'fn connect oauth config');
    } catch (e) {
      throw AppException.from(
        e,
        action: 'fn connect oauth config',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  /// 使用 FN Connect OAuth 回调 code 换取 NAS 登录结果。
  static Future<LoginWithBaseUrlResult> loginWithFnConnectOauthCode({
    required String baseUrl,
    required String code,
  }) async {
    final normalizedBaseUrl = ApiUrlHelper.normalizeBaseUrl(baseUrl);
    final body = <String, dynamic>{'source': 'Trim-NAS', 'code': code};
    final dio = _buildPublicApiDio(normalizedBaseUrl);
    try {
      final response = await dio.post(
        _authPath,
        data: body,
        options: Options(
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Cookie': 'mode=relay',
            'Authx': _buildPublicAuthxHeader(path: _authPath, body: body),
          },
        ),
      );
      final payload = response.data;
      if (payload is Map<String, dynamic> && payload['code'] == 0) {
        final data = payload['data'];
        if (data is Map<String, dynamic>) {
          final token = data['token']?.toString() ?? '';
          if (token.isNotEmpty) {
            return LoginWithBaseUrlResult(
              token: token,
              resolvedBaseUrl: normalizedBaseUrl,
              usedFnConnect: true,
            );
          }
        }
      }
      throw AppException.api(
        action: 'fn connect oauth auth',
        message:
            _backendMessageOf(payload) ?? 'Failed to exchange FN Connect token',
        code: payload is Map<String, dynamic>
            ? _toInt(payload['code'], fallback: 0)
            : null,
      );
    } on DioException catch (e) {
      throw AppException.fromDio(e, action: 'fn connect oauth auth');
    } catch (e) {
      throw AppException.from(
        e,
        action: 'fn connect oauth auth',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  static Future<LoginWithBaseUrlResult> _loginWithFnConnect({
    required String fnConnectId,
    required String userName,
    required String password,
  }) async {
    late final _FnConnectDiscoveryData discovery;
    try {
      discovery = await _fetchFnConnectDiscovery(fnConnectId);
    } catch (error) {
      final exception = AppException.from(
        error,
        action: 'login',
        fallbackKind: AppExceptionKind.transient,
      );
      throw FnConnectLoginException(
        error: exception,
        diagnostic: FnConnectLoginDiagnostic(
          fnConnectId: fnConnectId,
          discovery: null,
          attempts: const <FnConnectAttemptDiagnostic>[],
        ),
      );
    }
    var diagnostic = FnConnectLoginDiagnostic(
      fnConnectId: fnConnectId,
      discovery: _diagnosticFromDiscovery(discovery),
      attempts: const <FnConnectAttemptDiagnostic>[],
    );
    if (!discovery.hasAnyAddress) {
      throw FnConnectLoginException(
        error: AppException.api(
          action: 'login',
          message: 'FN Connect did not return any available address',
        ),
        diagnostic: diagnostic,
      );
    }

    final hasIpv6 = await _hasGlobalIpv6Connectivity();
    final candidates = _buildFnConnectLoginCandidates(
      discovery: discovery,
      allowIpv6: hasIpv6 != false,
    );
    if (candidates.isEmpty) {
      throw FnConnectLoginException(
        error: AppException.api(
          action: 'login',
          message:
              'FN Connect did not provide a direct API address. Relay-only access is not supported by this app yet.',
        ),
        diagnostic: diagnostic,
      );
    }

    AppException? unauthorizedError;
    AppException? firstTransientError;
    AppException? firstFatalError;

    for (final candidate in candidates) {
      debugPrint(
        '[LOGIN][FN_CONNECT] try fnId=$fnConnectId '
        'label=${candidate.label} baseUrl=${candidate.baseUrl}',
      );
      try {
        final dio = _buildLoginDio(candidate.baseUrl);
        final token = await _performLogin(
          dio,
          userName,
          password,
          baseUrlLabel: candidate.baseUrl,
        );
        return LoginWithBaseUrlResult(
          token: token,
          resolvedBaseUrl: ApiUrlHelper.normalizeBaseUrl(candidate.baseUrl),
          usedFnConnect: true,
          diagnostic: diagnostic.withAttempt(
            FnConnectAttemptDiagnostic(
              label: candidate.label,
              baseUrl: candidate.baseUrl,
              status: 'success',
              message: 'Login succeeded',
            ),
          ),
        );
      } catch (error) {
        final exception = AppException.from(
          error,
          action: 'login',
          fallbackKind: AppExceptionKind.transient,
        );
        diagnostic = diagnostic.withAttempt(
          FnConnectAttemptDiagnostic(
            label: candidate.label,
            baseUrl: candidate.baseUrl,
            status: _fnConnectAttemptStatus(exception),
            message: exception.message,
          ),
        );
        debugPrint(
          '[LOGIN][FN_CONNECT] failed fnId=$fnConnectId '
          'label=${candidate.label} baseUrl=${candidate.baseUrl} '
          'message=${exception.message}',
        );
        if (exception.isUnauthorized) {
          unauthorizedError ??= exception;
        } else if (exception.isTransient) {
          firstTransientError ??= exception;
        } else {
          firstFatalError ??= exception;
        }
      }
    }

    final finalError =
        unauthorizedError ??
        (firstTransientError != null
            ? AppException.api(
                action: 'login',
                message:
                    'FN Connect resolved only direct API addresses, but none of them were reachable from the current network. Official relay access is web-only and is not supported by this app yet.',
                cause: firstTransientError,
              )
            : null) ??
        firstFatalError ??
        AppException.api(
          action: 'login',
          message: 'FN Connect login failed for all resolved addresses',
        );
    throw FnConnectLoginException(error: finalError, diagnostic: diagnostic);
  }

  static Future<_FnConnectDiscoveryData> _fetchFnConnectDiscovery(
    String fnConnectId,
  ) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final body = <String, dynamic>{'fnId': fnConnectId};
    final bodyText = jsonEncode(body);
    final nonce = (Random().nextInt(900000) + 100000).toString();
    final fnSign = sha256
        .convert(utf8.encode('trim_connect`$fnConnectId`$timestamp`anna'))
        .toString();
    final md5Body = md5.convert(utf8.encode(bodyText)).toString();
    final authRaw = [
      _fnConnectAuthxPrefix,
      _fnConnectServicePath,
      nonce,
      '$timestamp',
      md5Body,
      _fnConnectApiKey,
    ].join('_');
    final authx =
        'nonce=$nonce&timestamp=$timestamp&sign=${md5.convert(utf8.encode(authRaw))}';

    final dio = Dio()
      ..options.baseUrl = _fnConnectServiceBaseUrl
      ..options.connectTimeout = const Duration(seconds: 6)
      ..options.receiveTimeout = const Duration(seconds: 8);
    try {
      final response = await dio.post(
        _fnConnectServicePath,
        data: body,
        options: Options(
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Authx': authx,
            'fn-sign': fnSign,
          },
        ),
      );
      final payload = response.data;
      if (payload is! Map<String, dynamic>) {
        throw AppException.api(
          action: 'fn connect discovery',
          message: 'Invalid FN Connect response format',
        );
      }
      if (_jsonInt(payload['code'], fallback: -1) != 0) {
        throw AppException.api(
          action: 'fn connect discovery',
          message: (payload['msg'] ?? payload['message'] ?? 'FN Connect failed')
              .toString(),
          code: _jsonInt(payload['code'], fallback: -1),
        );
      }
      final data = payload['data'];
      if (data is! Map<String, dynamic>) {
        throw AppException.api(
          action: 'fn connect discovery',
          message: 'Missing FN Connect discovery payload',
        );
      }
      debugPrint('[LOGIN][FN_CONNECT] discovery fnId=$fnConnectId data=$data');
      return _FnConnectDiscoveryData.fromJson(data);
    } on DioException catch (e) {
      throw AppException.fromDio(e, action: 'fn connect discovery');
    } catch (e) {
      throw AppException.from(
        e,
        action: 'fn connect discovery',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  static List<_FnConnectLoginCandidate> _buildFnConnectLoginCandidates({
    required _FnConnectDiscoveryData discovery,
    required bool allowIpv6,
  }) {
    final candidates = <_FnConnectLoginCandidate>[];
    final seen = <String>{};

    void addCandidate(String baseUrl, String label) {
      final normalized = ApiUrlHelper.normalizeBaseUrl(baseUrl);
      if (normalized.isEmpty) return;
      if (!seen.add(normalized)) return;
      candidates.add(
        _FnConnectLoginCandidate(baseUrl: normalized, label: label),
      );
    }

    for (final address in discovery.publicIpv4) {
      addCandidate('https://$address:${discovery.httpsPort}', 'public-ipv4');
    }
    for (final address in discovery.ddns) {
      addCandidate('https://$address:${discovery.httpsPort}', 'ddns');
    }
    if (allowIpv6) {
      for (final address in discovery.publicIpv6) {
        addCandidate(
          'https://[$address]:${discovery.httpsPort}',
          'public-ipv6',
        );
      }
    }
    for (final address in discovery.ipv4) {
      addCandidate('https://$address:${discovery.httpsPort}', 'lan-ipv4');
    }
    if (allowIpv6) {
      for (final address in discovery.ipv6) {
        addCandidate('https://[$address]:${discovery.httpsPort}', 'lan-ipv6');
      }
    }
    return candidates;
  }

  static String _fnConnectAttemptStatus(AppException exception) {
    if (exception.isUnauthorized) {
      return 'unauthorized';
    }
    final status = exception.httpStatus;
    if (status == 302 || exception.message.contains('status code of 302')) {
      return 'redirect';
    }
    if (status != null) {
      return 'http-$status';
    }
    final message = exception.message.toLowerCase();
    if (message.contains('timed out') || message.contains('timeout')) {
      return 'timeout';
    }
    if (message.contains('connection failed') ||
        message.contains('connection refused') ||
        message.contains('network is unreachable') ||
        message.contains('socketexception') ||
        message.contains('failed host lookup')) {
      return 'connection';
    }
    if (exception.isTransient) {
      return 'transient';
    }
    return 'failed';
  }

  static Dio _buildPublicApiDio(String baseUrl) {
    final normalizedBaseUrl = ApiUrlHelper.normalizeBaseUrl(baseUrl);
    final dio = Dio()
      ..options.baseUrl = normalizedBaseUrl
      ..options.connectTimeout = const Duration(seconds: 10)
      ..options.receiveTimeout = const Duration(seconds: 15);
    _configureHttpsTrust(dio, normalizedBaseUrl);
    return dio;
  }

  static String _buildPublicAuthxHeader({required String path, dynamic body}) {
    final nonce = (Random().nextInt(900000) + 100000).toString();
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final payload = body == null ? '' : jsonEncode(body);
    final payloadMd5 = md5.convert(utf8.encode(payload)).toString();
    final signBase = [
      _publicAuthxKey,
      path,
      nonce,
      timestamp,
      payloadMd5,
      _publicAuthxSecret,
    ].join('_');
    final sign = md5.convert(utf8.encode(signBase)).toString();
    return 'nonce=$nonce&timestamp=$timestamp&sign=$sign';
  }

  static String _mergeRelayCookie(String cookie) {
    final entries = cookie
        .split(';')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
    final hasRelayCookie = entries.any(
      (entry) => entry.toLowerCase().startsWith('mode='),
    );
    if (!hasRelayCookie) {
      entries.add('mode=relay');
    }
    return entries.join('; ');
  }

  /// 获取当前登录用户信息。
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

  /// 获取首页媒体库分类列表。
  Future<List<MediaItem>> getMediaList() async {
    return _getOrLoadSharedResource<List<MediaItem>>(
      cacheKey: _sharedResourceKey('home_media_list'),
      maxAge: _homeReadCacheTtl,
      loader: () async {
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
      },
    );
  }

  /// 获取首页媒体库概览统计。
  Future<Map<String, dynamic>> getMediaSummary() async {
    return _getOrLoadSharedResource<Map<String, dynamic>>(
      cacheKey: _sharedResourceKey('home_media_summary'),
      maxAge: _homeReadCacheTtl,
      loader: () async {
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
      },
    );
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

    PrivateNetworkHttpOverrides.registerNasHost(uri.host);

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

  // Some tag/subtitle payloads are returned with mojibake. Repair them once here.
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
  /// 获取系统配置。
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

  /// 获取系统版本信息。
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

  /// 获取服务器基础信息。
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

  /// 获取应用已授权访问的目录列表。
  Future<List<AuthorizedDirEntry>> getAppAuthorizedDirs() async {
    return _getOrLoadSharedResource<List<AuthorizedDirEntry>>(
      cacheKey: _sharedResourceKey('authorized_dirs'),
      loader: () async {
        try {
          final response = await _dio.get(_serverAuthorizedDirPath);
          final data = _extractDataMap(response.data, 'authorized dirs');
          final list = (data['authDirList'] as List?) ?? const <dynamic>[];
          return list
              .whereType<Map<String, dynamic>>()
              .map(AuthorizedDirEntry.fromJson)
              .toList(growable: false);
        } catch (e) {
          throw AppException.from(
            e,
            action: 'authorized dirs',
            fallbackKind: AppExceptionKind.transient,
          );
        }
      },
    );
  }

  /// 获取某个分类目录下的条目列表。
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

  /// 关键词搜索媒体条目。
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
  /// 按祖先目录构造并查询分页结果。
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

  /// 使用结构化请求对象查询条目分页。
  Future<ItemListPage> getItemsPageByRequest(ItemListRequest request) async {
    return getItemsPage(request.toJson());
  }

  /// 直接使用原始 payload 查询条目分页。
  ///
  /// 适合调用方已经自行构造复杂筛选条件的场景。
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

  /// 获取收藏列表分页。
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

  /// 获取后端正在运行的任务列表。
  Future<Map<String, dynamic>> getRunningTasks() async {
    final response = await _dio.get(_runningTasksPath);
    return _extractDataMap(response.data, 'task running');
  }

  // User preferences / tags
  /// 读取某个列表页的用户展示设置。
  Future<UserListSetting?> getUserListSetting(
    String ancestorGuid, {
    String key = _folderListSettingKey,
  }) async {
    try {
      final decoded = await getUserDataJsonValue(key, mdbGuid: ancestorGuid);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return UserListSetting.fromJson(decoded);
    } catch (e) {
      debugPrint('[API][USER_SETTING] load failed: $e');
      return null;
    }
  }

  /// 保存某个列表页的用户展示设置。
  Future<bool> setUserListSetting(
    String ancestorGuid, {
    String? sortType,
    String? sortField,
    String? viewType,
    String key = _folderListSettingKey,
  }) async {
    final current =
        await getUserDataJsonValue(key, mdbGuid: ancestorGuid) ??
        <String, dynamic>{};
    final next = <String, dynamic>{...current};
    if (sortType != null) {
      next['sort_type'] = sortType.toUpperCase();
    }
    if (sortField != null) {
      next['sort_field'] = sortField;
    }
    if (viewType != null) {
      next['view_type'] = viewType;
    }
    return setUserDataJsonValue(key, next, mdbGuid: ancestorGuid);
  }

  /// 读取用户数据表中的原始条目。
  Future<Map<String, dynamic>?> getUserDataEntry(
    String key, {
    String mdbGuid = '',
  }) async {
    try {
      final payload = <String, dynamic>{'key': key};
      if (mdbGuid.trim().isNotEmpty) {
        payload['mdb_guid'] = mdbGuid;
      }
      final response = await _dio.post(_userDataPath, data: payload);
      return _extractDataMap(response.data, 'user data');
    } catch (e) {
      debugPrint('[API][USER_DATA] load failed key=$key error=$e');
      return null;
    }
  }

  /// 读取用户数据条目里的 JSON 值。
  Future<Map<String, dynamic>?> getUserDataJsonValue(
    String key, {
    String mdbGuid = '',
  }) async {
    final data = await getUserDataEntry(key, mdbGuid: mdbGuid);
    if (data == null) return null;
    final rawValue = data['value'];
    if (rawValue is! String || rawValue.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(rawValue);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      debugPrint('[API][USER_DATA] decode failed key=$key error=$e');
      return null;
    }
  }

  /// 写入用户数据的普通字符串值。
  Future<bool> setUserDataValue(
    String key,
    String value, {
    String mdbGuid = '',
  }) async {
    try {
      final payload = <String, dynamic>{'key': key, 'value': value};
      if (mdbGuid.trim().isNotEmpty) {
        payload['mdb_guid'] = mdbGuid;
      }
      final response = await _dio.post(_userSetDataPath, data: payload);
      _extractDataMap(response.data, 'set user data');
      return true;
    } catch (e) {
      debugPrint('[API][USER_DATA] save failed key=$key error=$e');
      return false;
    }
  }

  /// 写入用户数据的 JSON 值。
  Future<bool> setUserDataJsonValue(
    String key,
    Map<String, dynamic> value, {
    String mdbGuid = '',
  }) {
    return setUserDataValue(key, jsonEncode(value), mdbGuid: mdbGuid);
  }

  /// 与原生壳共享的本地视图偏好键。shared_preferences 落盘为 `flutter.playlist_view_type`，
  /// 原生壳 NativePlayerActivity 直接读同一文件同一键——三端共用一份、不漂移。
  static const String _playlistViewTypePrefKey = 'playlist_view_type';

  /// 读取播放列表视图类型偏好（本地优先）。
  ///
  /// 命中本地缓存即刻返回（开播/打开选集面板秒级正确，不等网络），同时后台异步刷新服务端
  /// 偏好回写本地，使下次取到最新；无本地缓存时退回服务端并写入本地。
  Future<String?> getPlaylistViewType() async {
    final cached = await _readLocalPlaylistViewType();
    if (cached != null) {
      // 后台对齐服务端，不阻塞本次返回。
      unawaited(
        _fetchServerPlaylistViewType().then((server) {
          if (server != null) _writeLocalPlaylistViewType(server);
        }),
      );
      return cached;
    }
    final server = await _fetchServerPlaylistViewType();
    if (server != null) await _writeLocalPlaylistViewType(server);
    return server;
  }

  /// 保存播放列表视图类型偏好：本地即时写入（供秒级恢复）+ 写穿服务端。
  Future<bool> setPlaylistViewType(String viewType) async {
    if (viewType != 'button' && viewType != 'card') {
      debugPrint('[API][USER_DATA] unsupported playlist view type=$viewType');
      return false;
    }
    await _writeLocalPlaylistViewType(viewType);
    return setUserDataJsonValue('playlist:setting', <String, dynamic>{
      'view_type': viewType,
    });
  }

  Future<String?> _fetchServerPlaylistViewType() async {
    final setting = await getUserDataJsonValue('playlist:setting');
    final viewType = setting?['view_type']?.toString().trim();
    if (viewType == 'button' || viewType == 'card') {
      return viewType;
    }
    return null;
  }

  Future<String?> _readLocalPlaylistViewType() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_playlistViewTypePrefKey)?.trim();
      return (v == 'button' || v == 'card') ? v : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeLocalPlaylistViewType(String viewType) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_playlistViewTypePrefKey, viewType);
    } catch (_) {
      // 本地缓存写失败不影响服务端真值。
    }
  }

  /// 获取标签接口的原始数据。
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

  /// 获取题材标签 id 到名称的映射。
  Future<Map<int, String>> getTagGenresMap({String lan = 'zh-CN'}) async {
    final normalizedLan = lan.trim();
    return _getOrLoadSharedResource<Map<int, String>>(
      cacheKey: _sharedResourceKey('tag_genres|$normalizedLan'),
      loader: () async {
        final response = await _dio.get(
          _tagGenresPath,
          queryParameters: {'lan': normalizedLan},
        );
        final data = _tryExtractDataList(response.data);
        if (data == null) return const <int, String>{};
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
        return Map<int, String>.unmodifiable(map);
      },
    );
  }

  /// 获取地区代码到名称的映射。
  Future<Map<String, String>> getTagIso3166Map({String lan = 'zh-CN'}) async {
    final normalizedLan = lan.trim();
    return _getOrLoadSharedResource<Map<String, String>>(
      cacheKey: _sharedResourceKey('tag_iso3166|$normalizedLan'),
      loader: () async {
        final response = await _dio.get(
          _tagIso3166Path,
          queryParameters: {'lan': normalizedLan},
        );
        final data = _tryExtractDataList(response.data);
        if (data == null) return const <String, String>{};
        final map = <String, String>{};
        for (final entry in data) {
          if (entry is Map<String, dynamic>) {
            final key = (entry['key'] ?? '').toString().trim().toUpperCase();
            final value = _fixMojibake(
              (entry['value'] ?? '').toString().trim(),
            );
            if (key.isNotEmpty && value.isNotEmpty) {
              map[key] = value;
            }
          }
        }
        return Map<String, String>.unmodifiable(map);
      },
    );
  }

  /// 获取语言代码到名称的映射。
  Future<Map<String, String>> getTagIso6392Map({String lan = 'zh-CN'}) async {
    final normalizedLan = lan.trim();
    return _getOrLoadSharedResource<Map<String, String>>(
      cacheKey: _sharedResourceKey('tag_iso6392|$normalizedLan'),
      loader: () async {
        final response = await _dio.get(
          _tagIso6392Path,
          queryParameters: {'lan': normalizedLan},
        );
        final data = _tryExtractDataList(response.data);
        if (data == null) return const <String, String>{};
        final map = <String, String>{};
        for (final entry in data) {
          if (entry is Map<String, dynamic>) {
            final key = (entry['key'] ?? '').toString().trim().toLowerCase();
            final value = _fixMojibake(
              (entry['value'] ?? '').toString().trim(),
            );
            if (key.isNotEmpty && value.isNotEmpty) {
              map[key] = value;
            }
          }
        }
        return Map<String, String>.unmodifiable(map);
      },
    );
  }

  // Playback / item actions
  /// 获取某个条目的可播放列表。
  ///
  /// 既可用于电影，也可用于剧集/目录展开后的播放集合。
  Future<List<MediaLibraryItem>> getPlayList({
    bool forceRefresh = false,
  }) async {
    Future<List<MediaLibraryItem>> load() async {
      try {
        final response = await _dio.get(_playListPath);
        final data = _extractDataList(response.data, 'play list');
        final items = await _parseOffMainIsolate(data, _parseMediaLibraryItems);
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

    if (forceRefresh) {
      _sharedResourceCache.remove(_sharedResourceKey('home_play_list'));
      _sharedResourceCacheTimes.remove(_sharedResourceKey('home_play_list'));
      return load();
    }

    return _getOrLoadSharedResource<List<MediaLibraryItem>>(
      cacheKey: _sharedResourceKey('home_play_list'),
      maxAge: _playListCacheTtl,
      loader: load,
    );
  }

  /// 获取播放页初始化所需的播放信息。
  Future<PlayInfoData> getPlayInfo(String itemGuid) async {
    try {
      final response = await _dio.post(
        _playInfoPath,
        data: {'item_guid': itemGuid},
      );
      final data = _extractDataMap(response.data, 'play info');
      return await _parseOffMainIsolate(data, _parsePlayInfoData);
    } catch (e) {
      throw AppException.from(
        e,
        action: 'play info',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  /// 更新条目的播放配置。
  ///
  /// 当前主要用于同步官方片头片尾跳过时长。
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

  /// 获取媒体实际播放流信息。
  ///
  /// `recordProgress` 为 true 时会顺带触发服务端进度记录。
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
      return PlaybackStreamData.fromJson(data, requestUserAgent: userAgent);
    } catch (e) {
      throw AppException.from(
        e,
        action: 'playback stream',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  /// 创建服务端托管播放会话。
  ///
  /// 用于需要服务端保活、鉴权续期或统一回收的播放链路。
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

  /// 获取字幕下载地址。
  ///
  /// 返回值是可直接用于 HTTP 请求的完整 URL。
  String getSubtitleDownloadUrl(String subtitleGuid) {
    final base = ApiUrlHelper.normalizeBaseUrl(nasProvider.baseUrl);
    return '$base$_subtitleDownloadPathPrefix/$subtitleGuid';
  }

  /// 下载字幕正文文本。
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

  /// 下载封面图原始字节（带鉴权），供离线缓存。
  ///
  /// [posterPath] 是 NAS 相对图片路径（loadArgs.posterPath）。按 [ApiUrlHelper] 候选
  /// 逐个尝试，首个成功即返回字节；全失败返回 null（断网时即如此，调用方静默回退网络 URL）。
  Future<List<int>?> downloadImageBytes(
    String posterPath, {
    int width = 480,
  }) async {
    final raw = posterPath.trim();
    if (raw.isEmpty) return null;
    final candidates = ApiUrlHelper.imageCandidates(
      nasProvider.baseUrl,
      raw,
      width: width,
    );
    for (final url in candidates) {
      try {
        final response = await _dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
        final bytes = response.data ?? const <int>[];
        if (bytes.isNotEmpty) return bytes;
      } catch (_) {
        // 该候选失败，试下一个。
      }
    }
    return null;
  }

  /// 搜索远程字幕候选。
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

  /// 下载远程字幕并让服务端挂接到当前媒体。
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

  /// 删除已挂接的字幕记录。
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

  /// 上报播放进度。
  ///
  /// 一般在播放器退出、切源或定时心跳时调用。
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
      final response = await _dio.post(
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
      _requireSuccessPayload(response.data, 'playback record');
    } catch (e) {
      throw AppException.from(
        e,
        action: 'playback record',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  /// 判断播放链接是否已经过期。
  ///
  /// 返回 `null` 表示当前无法可靠判断。
  Future<bool?> checkPlayLinkExpired(String? playLink) async {
    final normalizedPlayLink = (playLink ?? '').trim();
    if (normalizedPlayLink.isEmpty) {
      return null;
    }
    try {
      final clientId = await _ensurePlaybackClientId();
      final response = await _dio.post(
        _playMediaBridgePath,
        data: <String, dynamic>{
          'playLink': normalizedPlayLink,
          'req': 'media.checkPlayLink',
          'reqid': clientId
              .substring(0, min(16, clientId.length))
              .toUpperCase(),
        },
      );
      final errno = _extractMediaBridgeErrno(response.data);
      if (errno == null) {
        return false;
      }
      return errno == 4100;
    } catch (e) {
      throw AppException.from(
        e,
        action: 'check play link',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  /// 重置某条播放记录到指定位置。
  Future<void> resetPlaybackRecord({
    required String itemGuid,
    required String mediaGuid,
  }) async {
    try {
      final response = await _dio.post(
        _playRecordPath,
        data: <String, dynamic>{
          'item_guid': itemGuid.trim(),
          'media_guid': mediaGuid.trim(),
          'ts': 0,
        },
      );
      _requireSuccessPayload(response.data, 'playback reset');
    } catch (e) {
      throw AppException.from(
        e,
        action: 'playback reset',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  /// 删除指定条目的播放记录。
  Future<void> deletePlaybackRecord({required String itemGuid}) async {
    try {
      final response = await _dio.delete(
        _playRecordPath,
        data: <String, dynamic>{'item_guid': itemGuid.trim()},
      );
      _requireSuccessPayload(response.data, 'playback delete');
    } catch (e) {
      throw AppException.from(
        e,
        action: 'playback delete',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  /// 为任意飞牛资源 URL 构造鉴权请求头。
  ///
  /// 主要用于播放器、下载器等不直接复用 `_dio` 的场景。
  Map<String, String> buildSignedHeadersForUrl(
    String url, {
    String method = 'GET',
    dynamic body,
    bool includeInitialRangeHeader = true,
    Map<String, String> extraHeaders = const <String, String>{},
  }) {
    final uri = Uri.tryParse(url);
    final shouldAttachNasAuth = _shouldAttachNasAuthToUrl(uri);
    final headers = <String, String>{
      if (shouldAttachNasAuth && nasProvider.token.isNotEmpty)
        'Authorization': nasProvider.token,
      if (shouldAttachNasAuth && nasProvider.token.isNotEmpty)
        'Trim-MC-token': nasProvider.token,
      if (includeInitialRangeHeader &&
          (uri?.path ?? '').startsWith('$_apiPrefix/media/range/'))
        'Range': 'bytes=0-',
      ...extraHeaders,
    };
    if (shouldAttachNasAuth && shouldUseRelayModeCookieForBaseUrl(url)) {
      headers['Cookie'] = _mergeRelayCookie(
        headers['Cookie']?.toString() ?? '',
      );
    }

    final path = uri?.path ?? '';
    if (shouldAttachNasAuth && _shouldAttachAuthx(path)) {
      headers['Authx'] = _buildAuthxHeaderFor(
        method: method,
        path: path,
        queryParameters: uri?.queryParameters ?? const <String, String>{},
        body: body,
      );
    }
    return headers;
  }

  /// 为播放链路构造请求头。
  ///
  /// 在通用签名头基础上补充播放链路使用的 User-Agent。
  Map<String, String> buildPlaybackHeadersForUrl(
    String url, {
    String method = 'GET',
    dynamic body,
    bool includeInitialRangeHeader = true,
    Map<String, String> extraHeaders = const <String, String>{},
  }) {
    return buildSignedHeadersForUrl(
      url,
      method: method,
      body: body,
      includeInitialRangeHeader: includeInitialRangeHeader,
      extraHeaders: <String, String>{
        'User-Agent': _defaultPlaybackUserAgent,
        ...extraHeaders,
      },
    );
  }

  String _sharedResourceKey(String suffix) {
    final baseUrl = ApiUrlHelper.normalizeBaseUrl(nasProvider.baseUrl);
    return '$baseUrl|${nasProvider.token}|$suffix';
  }

  Future<T> _getOrLoadSharedResource<T>({
    required String cacheKey,
    Duration? maxAge,
    required Future<T> Function() loader,
  }) async {
    final cached = _sharedResourceCache[cacheKey];
    final cachedAt = _sharedResourceCacheTimes[cacheKey];
    final cacheValid =
        maxAge == null ||
        (cachedAt != null && DateTime.now().difference(cachedAt) <= maxAge);
    if (cached is T && cacheValid) {
      return cached;
    }
    if (cached != null && !cacheValid) {
      _sharedResourceCache.remove(cacheKey);
      _sharedResourceCacheTimes.remove(cacheKey);
    }

    final pending = _sharedResourceInflight[cacheKey];
    if (pending != null) {
      return (await pending) as T;
    }

    final future = loader().then<Object?>(
      (value) {
        _sharedResourceCache[cacheKey] = value;
        _sharedResourceCacheTimes[cacheKey] = DateTime.now();
        _sharedResourceInflight.remove(cacheKey);
        return value;
      },
      onError: (Object error, StackTrace stackTrace) {
        _sharedResourceInflight.remove(cacheKey);
        throw error;
      },
    );

    _sharedResourceInflight[cacheKey] = future;
    return (await future) as T;
  }

  /// 设置收藏状态。
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

  /// 设置看过状态。
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

  /// 获取条目的完整详情。
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

  /// 获取可用于创建下载任务的清晰度选项。
  Future<List<String>> getDownloadResolutionOptions(
    String playItemGuid, {
    String lan = 'zh-CN',
  }) async {
    final guid = playItemGuid.trim();
    if (guid.isEmpty) return const <String>[];
    try {
      final response = await _dio.get(
        '$_downloadResolutionPathPrefix/$guid',
        queryParameters: <String, dynamic>{'guid': guid, 'lan': lan.trim()},
      );
      final success = _requireSuccessPayload(
        response.data,
        'download resolution',
      );
      final data = success['data'];
      if (data is! List) {
        throw AppException.api(
          action: 'download resolution',
          message: 'Invalid download resolution payload',
        );
      }
      return data
          .map((entry) => entry.toString().trim())
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      throw AppException.from(
        e,
        action: 'download resolution',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  /// 创建下载任务并返回任务 id。
  Future<String> createDownloadTask({
    required String mediaGuid,
    required String itemGuid,
    required String resolution,
    int type = 0,
    String lan = 'zh-CN',
  }) async {
    final normalizedMediaGuid = mediaGuid.trim();
    final normalizedItemGuid = itemGuid.trim();
    final normalizedResolution = resolution.trim();
    if (normalizedMediaGuid.isEmpty ||
        normalizedItemGuid.isEmpty ||
        normalizedResolution.isEmpty) {
      throw AppException.api(
        action: 'download task',
        message: 'Missing download task parameters',
      );
    }
    final body = <String, dynamic>{
      'media_guid': normalizedMediaGuid,
      'item_guid': normalizedItemGuid,
      'resolution': normalizedResolution,
      'type': type,
      'lan': lan.trim(),
    };
    try {
      final response = await _dio.put(_downloadTaskPath, data: body);
      final payload = _requireSuccessPayload(response.data, 'download task');
      final taskId = (payload['data'] ?? '').toString().trim();
      if (taskId.isEmpty) {
        throw AppException.api(
          action: 'download task',
          message: 'Empty download task id',
        );
      }
      return taskId;
    } catch (e) {
      throw AppException.from(
        e,
        action: 'download task',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  /// 查询下载任务进度。
  Future<DownloadTaskProgressInfo?> getDownloadTaskProgress(
    String taskId, {
    String lan = 'zh-CN',
  }) async {
    final normalizedTaskId = taskId.trim();
    if (normalizedTaskId.isEmpty) return null;
    try {
      final response = await _dio.get(
        _downloadTaskProgressPath,
        queryParameters: <String, dynamic>{
          'guid': normalizedTaskId,
          'lan': lan.trim(),
        },
      );
      final payload = _requireSuccessPayload(
        response.data,
        'download task progress',
      );
      final data = payload['data'];
      if (data is! Map<String, dynamic>) return null;
      return DownloadTaskProgressInfo.fromJson(data);
    } catch (e) {
      throw AppException.from(
        e,
        action: 'download task progress',
        fallbackKind: AppExceptionKind.transient,
      );
    }
  }

  /// 取消服务端下载任务（暂停/取消下载时调用）。
  Future<void> deleteDownloadTask(String taskId, {String lan = 'zh-CN'}) async {
    final normalizedTaskId = taskId.trim();
    if (normalizedTaskId.isEmpty) return;
    try {
      await _dio.delete(
        '$_downloadTaskPath/$normalizedTaskId',
        data: <String, dynamic>{'lan': lan.trim()},
      );
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'delete download task',
        id: normalizedTaskId,
        error: error,
        stackTrace: stackTrace,
        source: 'feiniu_api',
      );
      // Best-effort: server-side cleanup should not block the local UX.
    }
  }

  /// 构造下载任务详情接口的完整 URL。
  String buildDownloadTaskUrl(String taskId) {
    final normalizedTaskId = taskId.trim();
    if (normalizedTaskId.isEmpty) return '';
    final base = ApiUrlHelper.normalizeBaseUrl(nasProvider.baseUrl);
    return '$base$_downloadTaskPath/$normalizedTaskId';
  }

  /// 获取剧集对应的季列表。
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

  /// 获取某一季下的剧集列表。
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

  /// 获取条目的转码/流清单选项。
  Future<List<StreamListOption>> getStreamListOptions(String itemGuid) async {
    final data = await getStreamTrackData(itemGuid);
    return data.options;
  }

  /// 获取条目的音轨、字幕轨等流轨道信息。
  Future<StreamTrackData> getStreamTrackData(String itemGuid) async {
    final normalizedItemGuid = itemGuid.trim();
    return _getOrLoadSharedResource<StreamTrackData>(
      cacheKey: _sharedResourceKey('stream_track|$normalizedItemGuid'),
      maxAge: _detailReadCacheTtl,
      loader: () async {
        try {
          final response = await _dio.get(
            '$_streamListPathPrefix/$normalizedItemGuid',
          );
          final data = _extractDataMap(response.data, 'stream list');
          final trackData = await _parseOffMainIsolate(
            data,
            _parseStreamTrackData,
          );
          debugPrint(
            '[API][STREAM_LIST] item=$normalizedItemGuid options=${trackData.options.length}',
          );
          return trackData;
        } catch (e) {
          throw AppException.from(
            e,
            action: 'stream list',
            fallbackKind: AppExceptionKind.transient,
          );
        }
      },
    );
  }

  // People
  /// 获取人物相关的作品/职务列表。
  Future<List<PersonCredit>> getPersonList(
    String itemGuid, {
    PersonListRequest request = const PersonListRequest(),
  }) async {
    final normalizedItemGuid = itemGuid.trim();
    final requestPayload = request.toJson();
    final requestKey = jsonEncode(requestPayload);
    return _getOrLoadSharedResource<List<PersonCredit>>(
      cacheKey: _sharedResourceKey(
        'person_list|$normalizedItemGuid|$requestKey',
      ),
      maxAge: _detailReadCacheTtl,
      loader: () async {
        try {
          final response = await _dio.post(
            '$_personListPathPrefix/$normalizedItemGuid',
            data: requestPayload,
          );
          final data = _extractDataMap(response.data, 'person list');
          final people = await _parseOffMainIsolate(data, _parsePersonCredits);
          debugPrint(
            '[API][PERSON_LIST] item=$normalizedItemGuid count=${people.length}',
          );
          return people;
        } catch (e) {
          throw AppException.from(
            e,
            action: 'person list',
            fallbackKind: AppExceptionKind.transient,
          );
        }
      },
    );
  }

  /// 获取人物详情资料。
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

  /// 获取某个人物名下的条目分页。
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

  /// 获取媒体流的探测元数据。
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
  /// 构造媒体流 URL。
  ///
  /// `directLinkQualityIndex` 不为空时表示请求指定直链清晰度。
  String getStreamUrl(String mediaGuid, {int? directLinkQualityIndex}) {
    return ApiUrlHelper.streamUrl(
      nasProvider.baseUrl,
      mediaGuid,
      directLinkQualityIndex: directLinkQualityIndex,
    );
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

  bool _shouldAttachNasAuthToUrl(Uri? uri) {
    if (uri == null) return true;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return true;
    }
    final targetHost = uri.host.trim().toLowerCase();
    if (targetHost.isEmpty) {
      return true;
    }
    final baseUri = Uri.tryParse(
      ApiUrlHelper.normalizeBaseUrl(nasProvider.baseUrl),
    );
    final baseHost = baseUri?.host.trim().toLowerCase() ?? '';
    if (baseHost.isEmpty) {
      return true;
    }
    if (targetHost != baseHost) {
      return false;
    }
    final targetPort = uri.hasPort ? uri.port : (scheme == 'https' ? 443 : 80);
    final baseScheme = (baseUri?.scheme ?? '').toLowerCase();
    final basePort = baseUri == null
        ? targetPort
        : (baseUri.hasPort ? baseUri.port : (baseScheme == 'https' ? 443 : 80));
    return targetPort == basePort;
  }

  // Authx is required by most protected endpoints. 新版后端严格校验签名：
  // md5("KEY_path_nonce_timestamp_payloadMd5_SECRET")。
  // GET 的 payload 是按 key 排序、值取解码原文的 query 串（k=v&k2=v2）；
  // 非 GET 的 payload 必须与实际发送的请求体字节完全一致（null 时为空串）。
  String _buildAuthxHeader(RequestOptions options) {
    final uri = options.uri;
    return _buildAuthxHeaderFor(
      method: options.method,
      path: uri.path,
      queryParameters: uri.queryParameters,
      body: options.data,
    );
  }

  String _buildAuthxHeaderFor({
    required String method,
    required String path,
    Map<String, String> queryParameters = const <String, String>{},
    dynamic body,
  }) {
    final nonce = _generateNonce();
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final normalizedMethod = method.toUpperCase();
    final String payloadMd5;
    if (normalizedMethod == 'GET') {
      final keys = queryParameters.keys.toList()..sort();
      final canonicalQuery = keys
          .map((key) => '$key=${queryParameters[key]}')
          .join('&');
      payloadMd5 = md5.convert(utf8.encode(canonicalQuery)).toString();
    } else {
      final String payload;
      if (body == null) {
        payload = '';
      } else if (body is String) {
        payload = body;
      } else {
        // 与 Dio 默认 transformer 的 json.encode 输出保持一致（保留插入序）。
        payload = jsonEncode(body);
      }
      payloadMd5 = md5.convert(utf8.encode(payload)).toString();
    }
    final signBase = [
      _publicAuthxKey,
      path,
      nonce,
      timestamp,
      payloadMd5,
      _publicAuthxSecret,
    ].join('_');
    final sign = md5.convert(utf8.encode(signBase)).toString();
    _apiVerboseLog(
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

  int? _extractMediaBridgeErrno(dynamic payload) {
    if (payload is Map<String, dynamic>) {
      final directErrno = payload['errno'];
      if (directErrno is num) {
        return directErrno.toInt();
      }
      final data = payload['data'];
      if (data is Map<String, dynamic>) {
        final nestedErrno = data['errno'];
        if (nestedErrno is num) {
          return nestedErrno.toInt();
        }
      }
    }
    return null;
  }
}

const String _defaultPlaybackUserAgent =
    'Mozilla/5.0 (Linux; Android 15; FlyPlayer) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Mobile Safari/537.36';

/// 条目分页查询结果。
class ItemListPage {
  /// 服务端返回的总条目数。
  final int total;

  /// 当前页条目集合。
  final List<MediaLibraryItem> items;

  const ItemListPage({required this.total, required this.items});

  /// 当前页是否还没有覆盖到总条目数。
  bool get hasMore => items.length < total;
}

/// 列表页在服务端保存的用户展示设置。
class UserListSetting {
  /// 排序方向。
  final String sortType;

  /// 排序字段。
  final String sortField;

  /// 列表视图类型。
  final String viewType;

  const UserListSetting({
    required this.sortType,
    required this.sortField,
    required this.viewType,
  });

  /// 从后端 JSON 构造设置对象。
  factory UserListSetting.fromJson(Map<String, dynamic> json) {
    return UserListSetting(
      sortType: (json['sort_type'] ?? 'DESC').toString().toUpperCase(),
      sortField: (json['sort_field'] ?? 'create_time').toString(),
      viewType: (json['view_type'] ?? '').toString(),
    );
  }
}
