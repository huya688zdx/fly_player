/// fnOS 系统级加密 WebSocket 登录（官方客户端同款协议）与 OAuth 授权码获取。
///
/// 协议与 fnOS Web / 官方 App 实现一致（此前已在 fnconnect_e2e2.py 中端到端验证）：
/// 1. 连接 ws(s)://<host>/websocket，先 `util.getSI` 拿会话标识 si。
/// 2. `util.crypto.getRSAPub` 拿 SPKI 公钥；客户端生成 AES-256-CBC key(32B) 与
///    IV(16B)，用 RSA-OAEP（hash=SHA-256，MGF1=SHA-1）加密 AES key 放入信封
///    `rsa` 字段，信封带 `v:1`。
/// 3. 敏感请求整体放入信封：`{"req":"encrypted","iv","rsa","aes","si","v":1}`，
///    服务端响应同样用同一 key/IV 加密（只回 `aes` 字段）。
/// 4. `user.login` 的账号字段名是 `user`（不是 username）；`stay:2` 表示信任设备，
///    `did` 为客户端持久化的设备唯一标识。
/// 5. 登录成功返回 `token`（会话）与 `longToken`（30 天免密续登），后者可通过
///    `user.tokenLogin` 静默换新会话。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show Hmac, sha256;
import 'package:dio/dio.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/asymmetric/api.dart' show RSAPublicKey;
import 'package:pointycastle/asymmetric/oaep.dart';
import 'package:pointycastle/asymmetric/rsa.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/digests/sha1.dart';
import 'package:pointycastle/padded_block_cipher/padded_block_cipher_impl.dart';
import 'package:pointycastle/paddings/pkcs7.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../utils/api_url_helper.dart';
import '../utils/app_exception.dart';
import '../api/feiniu_access_code_transport.dart';

/// 系统登录成功后的会话信息。
class FnSystemSession {
  /// 本次系统会话 token，用于调用 /oauthapi/authorize。
  final String token;

  /// 30 天免密续登令牌；服务端未返回时为空。
  final String longToken;

  /// 与 longToken 配套的签名密钥（Base64，明文为 16 字节），用于
  /// `user.tokenLogin` 明文包签名；服务端未返回时为空。
  final String secretBase64;

  final int uid;

  final bool isAdmin;

  /// 本次登录使用的设备标识（调用方应持久化以便免密续登）。
  final String did;

  const FnSystemSession({
    required this.token,
    required this.longToken,
    required this.secretBase64,
    required this.uid,
    required this.isAdmin,
    required this.did,
  });
}

/// 账号开启两步验证时抛出；调用方应转原生验证码输入或回退 WebView 授权页。
class FnSystemTwoFactorRequired implements Exception {
  /// 服务端返回的 2FA 临时令牌（user.2fa.loginVerify 用）。
  final String? accessToken;

  /// 是否已绑定验证器（true=TOTP，false=邮箱验证码）。
  final bool bindTwofaSecret;

  final String? email;

  const FnSystemTwoFactorRequired({
    required this.accessToken,
    required this.bindTwofaSecret,
    required this.email,
  });

  @override
  String toString() =>
      'FnSystemTwoFactorRequired(accessToken=${accessToken == null ? 'missing' : 'present'}, bindTwofaSecret=$bindTwofaSecret)';
}

/// fnOS 系统加密 WebSocket 登录与 OAuth 授权的纯原生实现。
class FnNativeSystemLogin {
  static const String _defaultDeviceName = 'FlyPlayer';
  static const String _deviceType = 'pc';

  /// 排查握手/信封问题时打开帧级日志。
  static bool debugSocketFrames = false;

  /// 判断 [baseUrl] 是否为 fnOS 中继域（官方边缘代理，请求需带 relay cookie）。
  static bool isRelayHost(String baseUrl) {
    final uri = Uri.tryParse(ApiUrlHelper.normalizeBaseUrl(baseUrl));
    if (uri == null || uri.host.isEmpty) return false;
    final host = uri.host.toLowerCase();
    return host == 'fnos.net' ||
        host.endsWith('.fnos.net') ||
        host == '5ddd.com' ||
        host.endsWith('.5ddd.com');
  }

  /// 推导系统 WebSocket 地址（https→wss，http→ws，路径固定 /websocket）。
  static String webSocketUrlOf(String baseUrl) {
    final uri = Uri.parse(ApiUrlHelper.normalizeBaseUrl(baseUrl));
    final scheme = uri.scheme.toLowerCase() == 'https' ? 'wss' : 'ws';
    return uri.replace(scheme: scheme, path: '/websocket').toString();
  }

  /// 账号密码登录系统，返回会话与免密续登令牌。
  ///
  /// [did] 传调用方持久化的设备标识；缺省时按随机 UUID 生成（调用方应保存
  /// [FnSystemSession.did]，否则每次登录都会生成新设备记录）。
  static Future<FnSystemSession> login({
    required String baseUrl,
    required String userName,
    required String password,
    String? did,
    String deviceName = _defaultDeviceName,
    Duration timeout = const Duration(seconds: 20),
  }) {
    return _runSession(
      baseUrl: baseUrl,
      timeout: timeout,
      action: (channel, si) async {
        final data = await channel.sendEncrypted(<String, dynamic>{
          'req': 'user.login',
          'user': userName,
          'password': password,
          'stay': 2,
          'deviceType': _deviceType,
          'deviceName': deviceName,
          'did': did ?? generateDeviceId(),
          'si': si,
        });
        return _sessionFromLoginResponse(data, did: did);
      },
    );
  }

  /// 使用已保存的 longToken 免密续登（全程不接触密码）。
  ///
  /// 协议（与 fnOS Web 客户端一致）：`user.tokenLogin` 不能走加密信封，而是
  /// 发送明文包并用登录时保存的 16 字节 secret 做 HMAC-SHA256 签名：
  ///   payload = Base64(HMAC-SHA256(bodyJson, secretBytes)) + bodyJson
  /// body 必须包含当前连接的 `si`，否则服务端拒绝（errno 65534）。
  static Future<FnSystemSession> loginWithLongToken({
    required String baseUrl,
    required String longToken,
    required Uint8List secretBytes,
    String? did,
    String deviceName = _defaultDeviceName,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (secretBytes.isEmpty) {
      throw AppException.api(
        action: 'fn_system_login',
        message: 'Saved login requires the session secret',
      );
    }
    final channel = await _EncryptedWebSocket.connect(
      url: webSocketUrlOf(baseUrl),
      timeout: timeout,
    );
    try {
      final si = await channel.getSystemIdentifier();
      final body = jsonEncode(<String, dynamic>{
        'req': 'user.tokenLogin',
        'token': longToken,
        'deviceType': _deviceType,
        'deviceName': deviceName,
        'did': did ?? generateDeviceId(),
        'si': si,
      });
      final hmac = Hmac(sha256, secretBytes);
      final signed =
          base64Encode(hmac.convert(utf8.encode(body)).bytes) + body;
      final reply = await channel.sendPlain(signed);
      return _sessionFromLoginResponse(reply, did: did);
    } on FnSystemTwoFactorRequired {
      rethrow;
    } on AppException {
      rethrow;
    } on TimeoutException {
      throw AppException.api(
        action: 'fn_system_login',
        message: 'System login timed out',
      );
    } catch (error) {
      throw AppException.from(
        error,
        action: 'fn_system_login',
        fallbackKind: AppExceptionKind.transient,
      );
    } finally {
      unawaited(channel.close());
    }
  }

  /// 两步验证确认：TOTP 传 [totpCode]；邮箱方式传 [email] 与 [emailCode]。
  static Future<FnSystemSession> verifyTwoFactor({
    required String baseUrl,
    required String accessToken,
    String? totpCode,
    String? email,
    String? emailCode,
    required bool trustedDevice,
    String? did,
    String deviceName = _defaultDeviceName,
    Duration timeout = const Duration(seconds: 20),
  }) {
    return _runSession(
      baseUrl: baseUrl,
      timeout: timeout,
      action: (channel, si) async {
        final data = await channel.sendEncrypted(<String, dynamic>{
          'req': 'user.2fa.loginVerify',
          if (totpCode != null && totpCode.isNotEmpty) 'code': totpCode,
          if (email != null && email.isNotEmpty) 'email': email,
          if (emailCode != null && emailCode.isNotEmpty) 'emailCode': emailCode,
          'accessToken': accessToken,
          'isTrustedDevice': trustedDevice,
          'stay': trustedDevice ? 2 : 0,
          'deviceType': _deviceType,
          'deviceName': deviceName,
          'did': did ?? generateDeviceId(),
          'si': si,
        });
        return _sessionFromLoginResponse(data, did: did);
      },
    );
  }

  /// 用系统会话 token 调 /oauthapi/authorize 换取影视登录 code。
  ///
  /// 该接口只要持有有效系统 token 即直接返回 code（Web 上的授权确认卡片只是
  /// UI 层），与官方 App 的原生授权调用一致。
  static Future<String> requestAuthorizeCode({
    required String baseUrl,
    required String systemToken,
    required String clientId,
    String accessCode = '',
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final normalized = ApiUrlHelper.normalizeBaseUrl(baseUrl);
    final dio = Dio()
      ..options.baseUrl = normalized
      ..options.connectTimeout = timeout
      ..options.receiveTimeout = timeout;
    final uri = Uri.parse('$normalized/oauthapi/authorize');
    final body = <String, dynamic>{
      'token': systemToken,
      'client_id': clientId,
      'redirect_uri': '$normalized/v/oauth/result',
      'state': '',
      'response_type': 'code',
    };
    final headers = <String, String>{
      'Content-Type': 'application/json',
      ...buildFeiniuAccessCodeHeadersForUrl(
        accessCode: accessCode,
        baseUrl: normalized,
        url: uri.toString(),
      ),
    };
    if (isRelayHost(normalized)) {
      headers['Cookie'] = 'mode=relay';
    }
    final response = await dio.post(
      '/oauthapi/authorize',
      data: body,
      options: Options(headers: headers),
    );
    final payload = response.data;
    if (payload is! Map<String, dynamic>) {
      throw AppException.api(
        action: 'fn_connect_authorize',
        message: 'Invalid authorize response format',
      );
    }
    if (_intOf(payload['code']) != 0) {
      throw AppException.api(
        action: 'fn_connect_authorize',
        message: (payload['msg'] ?? payload['message'] ?? 'authorize failed')
            .toString(),
        code: _intOf(payload['code']),
      );
    }
    final data = payload['data'];
    final code =
        data is Map<String, dynamic> ? (data['code'] ?? '').toString() : '';
    if (code.trim().isEmpty) {
      throw AppException.api(
        action: 'fn_connect_authorize',
        message: 'Authorize response missing code',
      );
    }
    return code.trim();
  }

  /// 生成可持久化的设备标识（UUID v4）。
  static String generateDeviceId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static FnSystemSession _sessionFromLoginResponse(
    Map<String, dynamic> data, {
    String? did,
  }) {
    if (data['isTwofaEnforced'] == true) {
      throw FnSystemTwoFactorRequired(
        accessToken: (data['accessToken'] ?? '').toString(),
        bindTwofaSecret: data['isBindTwofaSecret'] == true,
        email: data['email']?.toString(),
      );
    }
    if (data['result'] != 'succ') {
      final message =
          (data['msg'] ??
              data['error'] ??
              data['result'] ??
              'login failed') +
          (data['errno'] == null ? '' : ' (errno=${data['errno']})');
      throw AppException.api(
        action: 'fn_system_login',
        message: message,
        code: _intOf(data['errno'] ?? _intOf(data['code'])),
      );
    }
    final token = (data['token'] ?? '').toString();
    if (token.isEmpty) {
      throw AppException.api(
        action: 'fn_system_login',
        message: 'System login response missing token',
      );
    }
    return FnSystemSession(
      token: token,
      longToken: (data['longToken'] ?? '').toString(),
      secretBase64: (data['secret'] ?? '').toString(),
      uid: _intOf(data['uid']),
      isAdmin: data['admin'] == true,
      did: (data['did'] ?? did ?? '').toString(),
    );
  }

  static int _intOf(Object? value) => value is num ? value.toInt() : 0;

  static Future<FnSystemSession> _runSession({
    required String baseUrl,
    required Duration timeout,
    required Future<FnSystemSession> Function(
            _EncryptedWebSocket channel, String si)
        action,
  }) async {
    final channel = await _EncryptedWebSocket.connect(
      url: webSocketUrlOf(baseUrl),
      timeout: timeout,
    );
    try {
      final si = await channel.getSystemIdentifier();
      await channel.establishEncryption(si);
      return await action(channel, si).timeout(timeout);
    } on FnSystemTwoFactorRequired {
      rethrow;
    } on AppException {
      rethrow;
    } on TimeoutException {
      throw AppException.api(
        action: 'fn_system_login',
        message: 'System login timed out',
      );
    } catch (error) {
      throw AppException.from(
        error,
        action: 'fn_system_login',
        fallbackKind: AppExceptionKind.transient,
      );
    } finally {
      // 等待连接真正断开：longToken 的续登请求要求原会话已结束。
      await channel.close();
    }
  }
}

/// 单次加密 WebSocket 会话：getSI → getRSAPub → 建立信封加密 → 业务请求。
class _EncryptedWebSocket {
  final WebSocketChannel _channel;
  final Duration _timeout;
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  final List<Map<String, dynamic>> _unsolicited = [];
  Uint8List? _key;
  Uint8List? _iv;
  int _reqId = 0;
  bool _closed = false;

  /// 排查握手/信封问题时打开（受调用方控制）。
  static bool get debugEnabled => FnNativeSystemLogin.debugSocketFrames;

  void _log(String message) {
    if (debugEnabled) {
      // ignore: avoid_print
      print('[FN_WS] $message');
    }
  }

  _EncryptedWebSocket._(this._channel, this._timeout) {
    _channel.stream.listen(_onData, onError: _failAll, onDone: _failClosed);
  }

  static Future<_EncryptedWebSocket> connect({
    required String url,
    required Duration timeout,
  }) async {
    final channel = WebSocketChannel.connect(Uri.parse(url));
    // TLS/握手失败会从 ready 抛出，避免等到第一条请求才报错。
    await channel.ready.timeout(timeout);
    return _EncryptedWebSocket._(channel, timeout);
  }

  /// 握手第一步：拿会话标识 si。
  Future<String> getSystemIdentifier() async {
    final reply = await _request(<String, dynamic>{'req': 'util.getSI'});
    final si = (reply['si'] ?? '').toString();
    if (si.isEmpty) {
      throw AppException.api(
        action: 'fn_system_login',
        message: 'System handshake missing si',
      );
    }
    return si;
  }

  /// 握手第二步：取服务端 RSA 公钥并生成会话 AES key/IV。
  Future<void> establishEncryption(String si) async {
    final reply = await _request(<String, dynamic>{
      'req': 'util.crypto.getRSAPub',
      'si': si,
    });
    final pubPem = (reply['pub'] ?? '').toString();
    if (!pubPem.contains('BEGIN PUBLIC KEY')) {
      throw AppException.api(
        action: 'fn_system_login',
        message: 'System handshake missing RSA public key',
      );
    }
    final random = Random.secure();
    _key = Uint8List.fromList(
        List<int>.generate(32, (_) => random.nextInt(256)));
    _iv = Uint8List.fromList(
        List<int>.generate(16, (_) => random.nextInt(256)));
    final pubKey = parseSpkiPem(pubPem);
    _rsaEnvelope = _encryptRsaOaep(pubKey, _key!);
  }

  Uint8List? _rsaEnvelope;

  /// 发送加密信封请求并解密响应。
  Future<Map<String, dynamic>> sendEncrypted(
    Map<String, dynamic> innerRequest,
  ) async {
    final key = _key;
    final iv = _iv;
    final rsaEnvelope = _rsaEnvelope;
    if (key == null || iv == null || rsaEnvelope == null) {
      throw StateError('encryption not established');
    }
    final request = <String, dynamic>{
      'req': 'encrypted',
      'iv': base64Encode(iv),
      'rsa': base64Encode(rsaEnvelope),
      'aes': base64Encode(encryptAesCbcPkcs7(
        key: key,
        iv: iv,
        input: utf8.encode(jsonEncode(innerRequest)),
      )),
      'si': innerRequest['si'] ?? '',
      'v': 1,
    };
    final reply = await _request(request);
    final aes = (reply['aes'] ?? '').toString();
    // 注意：实测 fnOS 对加密请求的响应可能是明文 JSON（无 aes 字段），
    // 也可能是同 key/IV 加密的包——两条路径都要做 secret 后处理。
    final decrypted = aes.isEmpty
        ? reply
        : decryptAesCbcPkcs7(
            key: key,
            iv: iv,
            input: base64Decode(aes),
          );
    // 登录响应中的 secret 是"再加密一层"的字符串（同一 key/IV），这里解出
    // 16 字节原始 secret 并转存为 Base64，供后续明文签名包使用。
    final secretField = (decrypted['secret'] ?? '').toString();
    if (secretField.isNotEmpty) {
      decrypted['secret'] = base64Encode(decryptAesCbcPkcs7Bytes(
        key: key,
        iv: iv,
        input: base64Decode(secretField),
      ));
      if (debugEnabled) {
        // ignore: avoid_print
        print('[FN_WS][SECRET] field=${secretField.length} '
            'out=${(decrypted['secret'] as String).length}');
      }
    }
    return decrypted;
  }

  void _onData(dynamic frame) {
    Map<String, dynamic>? message;
    try {
      final text = frame is String
          ? frame
          : frame is List<int>
              ? utf8.decode(frame)
              : null;
      if (text == null) return;
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) message = decoded;
    } catch (_) {
      return;
    }
    if (message == null) return;
    if (debugEnabled) {
      // ignore: avoid_print
      print('[FN_WS][RECV] keys=${message.keys.toList()} reqid=${message['reqid']} '
          'req=${message['req']} aes=${message['aes'] is String ? (message['aes'] as String).length : '-'}');
    }
    // 加密信封的响应可能不回显 reqid：优先精确匹配，否则按序交付给最早
    // 发出的请求（连接内请求是串行的）。
    final reqId = (message['reqid'] ?? '').toString();
    if (reqId.isNotEmpty) {
      final completer = _pending.remove(reqId);
      if (completer != null && !completer.isCompleted) {
        completer.complete(message);
        return;
      }
    }
    final pendingKey = _pending.keys.isEmpty ? null : _pending.keys.first;
    if (pendingKey != null) {
      final completer = _pending.remove(pendingKey);
      if (completer != null && !completer.isCompleted) {
        completer.complete(message);
        return;
      }
    }
    _unsolicited.add(message);
  }

  void _failAll(Object error) {
    if (_closed) return;
    _closed = true;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
  }

  void _failClosed() => _failAll(const SocketClosedBeforeReply());

  Future<Map<String, dynamic>> _request(Map<String, dynamic> request) {
    if (_closed) {
      return Future.error(const SocketClosedBeforeReply());
    }
    if (_unsolicited.isNotEmpty) {
      // 早于请求到达的响应按序消费。
      return Future.value(_unsolicited.removeAt(0));
    }
    _reqId += 1;
    final reqId = _reqId.toString();
    final completer = Completer<Map<String, dynamic>>();
    _pending[reqId] = completer;
    _log('SEND req=$reqId ${request['req']}');
    _channel.sink.add(jsonEncode(<String, dynamic>{...request, 'reqid': reqId}));
    return completer.future.timeout(_timeout, onTimeout: () {
      _pending.remove(reqId);
      throw TimeoutException('fn system websocket request timeout');
    });
  }

  /// 发送"签名前置 + JSON body"的明文包（user.tokenLogin 等免密续登请求）。
  /// 响应为明文 JSON，可能不回显 reqid，由无 reqid 回退队列按序交付。
  Future<Map<String, dynamic>> sendPlain(String payload) {
    if (_closed) {
      return Future.error(const SocketClosedBeforeReply());
    }
    if (_unsolicited.isNotEmpty) {
      return Future.value(_unsolicited.removeAt(0));
    }
    _reqId += 1;
    final tag = 'plain-$_reqId';
    final completer = Completer<Map<String, dynamic>>();
    _pending[tag] = completer;
    _log('SEND plain: $payload');
    _channel.sink.add(payload);
    return completer.future.timeout(_timeout, onTimeout: () {
      _pending.remove(tag);
      throw TimeoutException('fn system websocket request timeout');
    });
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _channel.sink.close(ws_status.normalClosure);
    } catch (_) {
      // 连接可能已被对端断开，忽略关闭异常。
    }
  }
}

class SocketClosedBeforeReply implements Exception {
  const SocketClosedBeforeReply();

  @override
  String toString() => 'fn system websocket closed before reply';
}

/// 以下加密助手暴露为 @visibleForTesting，供单元测试校验信封格式。
Uint8List encryptAesCbcPkcs7({
  required Uint8List key,
  required Uint8List iv,
  required List<int> input,
}) {
  final cipher = _paddedCipher(key, iv);
  return cipher.process(Uint8List.fromList(input));
}

Map<String, dynamic> decryptAesCbcPkcs7({
  required Uint8List key,
  required Uint8List iv,
  required List<int> input,
}) {
  final plain = decryptAesCbcPkcs7Bytes(key: key, iv: iv, input: input);
  final decoded = jsonDecode(utf8.decode(plain));
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('decrypted envelope payload is not an object');
  }
  return decoded;
}

/// 解密出原始字节（登录响应中的 secret 字段是再加密一层的字符串，非 JSON）。
Uint8List decryptAesCbcPkcs7Bytes({
  required Uint8List key,
  required Uint8List iv,
  required List<int> input,
}) {
  final cipher = _paddedCipher(key, iv, forEncryption: false);
  return cipher.process(Uint8List.fromList(input));
}

PaddedBlockCipher _paddedCipher(
  Uint8List key,
  Uint8List iv, {
  bool forEncryption = true,
}) {
  final cipher = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
    ..init(
      forEncryption,
      PaddedBlockCipherParameters(
        ParametersWithIV(KeyParameter(key), iv),
        null,
      ),
    );
  return cipher;
}

Uint8List _encryptRsaOaep(RSAPublicKey publicKey, Uint8List input) {
  // 与 fnconnect_e2e2.py（PyCryptodome PKCS1_OAEP(hashAlgo=SHA256)）一致：
  // OAEP hash=SHA-256，MGF1=SHA-1。
  final cipher = OAEPEncoding.withSHA256(RSAEngine())
    ..mgf1Hash = SHA1Digest()
    ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
  return cipher.process(input);
}

/// DER TLV 结构：tag + content 视图 + 下一个元素的位置。
class _DerTlv {
  final int tag;
  final Uint8List content;
  final int next;

  const _DerTlv({
    required this.tag,
    required this.content,
    required this.next,
  });
}

_DerTlv _readTlv(Uint8List bytes, int pos) {
  if (pos + 2 > bytes.length) {
    throw const FormatException('truncated DER structure');
  }
  final tag = bytes[pos];
  var length = bytes[pos + 1] & 0x7f;
  var headerSize = 2;
  if ((bytes[pos + 1] & 0x80) != 0) {
    final byteCount = length;
    if (byteCount == 0 || pos + 2 + byteCount > bytes.length) {
      throw const FormatException('invalid DER length header');
    }
    length = 0;
    for (var i = 0; i < byteCount; i++) {
      length = (length << 8) | bytes[pos + 2 + i];
    }
    headerSize = 2 + byteCount;
  }
  if (pos + headerSize + length > bytes.length) {
    throw const FormatException('DER content exceeds buffer');
  }
  return _DerTlv(
    tag: tag,
    content: Uint8List.sublistView(
        bytes, pos + headerSize, pos + headerSize + length),
    next: pos + headerSize + length,
  );
}

BigInt _derIntegerToBigInt(Uint8List content) {
  if (content.isEmpty) return BigInt.zero;
  final hex = content
      .map((b) => '${(b >> 4).toRadixString(16)}${(b & 0x0f).toRadixString(16)}')
      .join();
  return BigInt.parse(hex, radix: 16);
}

/// 解析 `-----BEGIN PUBLIC KEY-----`（SPKI DER）中的 RSA 公钥。
RSAPublicKey parseSpkiPem(String pem) {
  final base64Body = pem
      .split(RegExp(r'-----[A-Z ]+-----'))
      .map((part) => part.replaceAll(RegExp(r'\s'), ''))
      .where((part) => part.isNotEmpty)
      .join();
  final bytes = Uint8List.fromList(base64Decode(base64Body));

  // SPKI ::= SEQUENCE { AlgorithmIdentifier, BIT STRING }
  final spki = _readTlv(bytes, 0);
  if (spki.tag != 0x30) {
    throw const FormatException('expected SPKI SEQUENCE');
  }
  // AlgorithmIdentifier —— 跳过。
  final algorithm = _readTlv(spki.content, 0);
  final bitStringTlv = _readTlv(spki.content, algorithm.next);
  if (bitStringTlv.tag != 0x03) {
    throw const FormatException('expected BIT STRING for subjectPublicKey');
  }
  final bitString = bitStringTlv.content;
  if (bitString.isEmpty || bitString[0] != 0) {
    throw const FormatException('unsupported BIT STRING padding');
  }
  // subjectPublicKey 内容是内层 SEQUENCE：{ INTEGER n, INTEGER e }。
  final keySeqBytes = Uint8List.sublistView(bitString, 1);
  final keySeq = _readTlv(keySeqBytes, 0);
  if (keySeq.tag != 0x30) {
    throw const FormatException('expected RSA key SEQUENCE');
  }
  final modulusTlv = _readTlv(keySeq.content, 0);
  final exponentTlv = _readTlv(keySeq.content, modulusTlv.next);
  return RSAPublicKey(
    _derIntegerToBigInt(modulusTlv.content),
    _derIntegerToBigInt(exponentTlv.content),
  );
}
