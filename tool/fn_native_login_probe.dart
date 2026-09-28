/// 真机端到端验证：官方 App 同款登录链路（纯 Dart，不依赖 Flutter）。
///
///   ① 加密 WS 系统登录（密码）→ token + longToken
///   ② sys/config → nas_oauth.app_id
///   ③ /oauthapi/authorize（静默）→ code
///   ④ /v/api/v1/auth {source:Trim-NAS} → 媒体 token
///   ⑤ longToken 免密续登 → 新会话 → 再次静默授权
///
/// 运行（凭据走环境变量，不落盘）：
///   FN_HOST=192.168.6.120:5666 FN_USER=... FN_PASS=... \
///   dart run tool/fn_native_login_probe.dart
library;

// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' show Hmac, md5, sha256;
import 'package:dio/dio.dart';

import 'package:fly_player/api/feiniu_access_code_transport.dart';
import 'package:fly_player/services/fn_native_system_login.dart';
import 'package:fly_player/utils/api_url_helper.dart';

Future<void> main() async {
  final host = Platform.environment['FN_HOST'] ?? '192.168.6.120:5666';
  final userName = Platform.environment['FN_USER'] ?? '';
  final password = Platform.environment['FN_PASS'] ?? '';
  final accessCode = Platform.environment['FN_ACCESS_CODE'] ?? '';
  if (userName.isEmpty || password.isEmpty) {
    stderr.writeln('need FN_USER / FN_PASS env');
    exitCode = 2;
    return;
  }
  FnNativeSystemLogin.debugSocketFrames =
      Platform.environment['FN_DEBUG'] == '1';
  final base = ApiUrlHelper.normalizeBaseUrl('http://$host');
  final dio = Dio()
    ..options.baseUrl = base
    ..options.connectTimeout = const Duration(seconds: 10)
    ..options.receiveTimeout = const Duration(seconds: 12);

  // ① 加密 WS 系统登录。
  final did = FnNativeSystemLogin.generateDeviceId();
  print('[1] system login via ${FnNativeSystemLogin.webSocketUrlOf(base)}');
  final session = await FnNativeSystemLogin.login(
    baseUrl: base,
    userName: userName,
    password: password,
    did: did,
  );
  print('    uid=${session.uid} admin=${session.isAdmin} '
      'token=${_mask(session.token)} longToken=${_mask(session.longToken)} '
      'did=${session.did}');

  // ② sys/config → nas_oauth.app_id。
  print('[2] sys/config → nas_oauth');
  final sysResp = await dio.get(
    '/v/api/v1/sys/config',
    options: Options(headers: _headers(base, accessCode)),
  );
  final sysData = _mapOf((sysResp.data as Map?)?['data']);
  final oauth = _mapOf(sysData['nas_oauth']);
  final clientId = (oauth['app_id'] ?? '').toString();
  print('    client_id=$clientId');

  // ③ 静默授权。
  print('[3] /oauthapi/authorize (native, silent)');
  final code = await FnNativeSystemLogin.requestAuthorizeCode(
    baseUrl: base,
    systemToken: session.token,
    clientId: clientId,
    accessCode: accessCode,
  );
  print('    code=${_mask(code)}');

  // ④ 换媒体 token。
  print('[4] /v/api/v1/auth {source:Trim-NAS}');
  const authPath = '/v/api/v1/auth';
  final authBody = {'source': 'Trim-NAS', 'code': code};
  final authResp = await dio.post(
    authPath,
    data: authBody,
    options: Options(headers: _headers(base, accessCode)),
  );
  final authPayload = _mapOf(_mapOf(authResp.data as Map?)['data']);
  final mediaToken = (authPayload['token'] ?? '').toString();
  print('    media token=${_mask(mediaToken)}');
  if (mediaToken.isEmpty) {
    stderr.writeln('media auth failed: ${authResp.data}');
    exitCode = 1;
    return;
  }

  // ⑤ longToken 免密续登 → 再次静默授权。
  print('[5] passwordless relogin via longToken');
  final secretBytes = base64Decode(session.secretBase64);
  final manualBody = jsonEncode({
    'req': 'user.tokenLogin',
    'token': session.longToken,
    'deviceType': 'pc',
    'deviceName': 'FlyPlayer',
    'did': session.did,
  });
  final manualHmac = Hmac(sha256, secretBytes);
  print('    manual signed: '
      '${base64Encode(manualHmac.convert(utf8.encode(manualBody)).bytes)}$manualBody');
  print('    secretBase64.len=${session.secretBase64.length}');
  final session2 = await FnNativeSystemLogin.loginWithLongToken(
    baseUrl: base,
    longToken: session.longToken,
    secretBytes: secretBytes,
    did: session.did,
  );
  print('    uid=${session2.uid} token=${_mask(session2.token)} '
      'longToken=${_mask(session2.longToken)}');
  final code2 = await FnNativeSystemLogin.requestAuthorizeCode(
    baseUrl: base,
    systemToken: session2.token,
    clientId: clientId,
    accessCode: accessCode,
  );
  print('    code2=${_mask(code2)}');

  final ok = mediaToken.isNotEmpty && code2.isNotEmpty;
  print('\nE2E ${ok ? 'SUCCESS' : 'FAILED'}');
  if (!ok) exitCode = 1;
}

Map<String, String> _headers(String base, String accessCode) {
  final headers = <String, String>{
    'Authx': _authx('/v/api/v1/sys/config'),
  };
  headers.addAll(buildFeiniuAccessCodeHeaders(accessCode));
  return headers;
}

String _mask(String value) {
  if (value.length <= 8) return value.isEmpty ? '(empty)' : '****';
  return '${value.substring(0, 4)}****${value.substring(value.length - 4)}';
}

Map<String, dynamic> _mapOf(Object? value) {
  return value is Map<String, dynamic> ? value : const <String, dynamic>{};
}

String _authx(String path, {Object? body}) {
  // 与 App 内 _buildPublicAuthxHeader / e2e 脚本一致。
  const key = 'NDzZTVxnRKP8Z0jXg1VAMonaG8akvh';
  const secret = '16CCEB3D-AB42-077D-36A1-F355324E4237';
  final nonce = (Random().nextInt(900000) + 100000).toString();
  final ts = DateTime.now().millisecondsSinceEpoch.toString();
  final payload = body == null ? '' : jsonEncode(body);
  final payloadMd5 = md5.convert(utf8.encode(payload)).toString();
  final signBase = [key, path, nonce, ts, payloadMd5, secret].join('_');
  final sign = md5.convert(utf8.encode(signBase)).toString();
  return 'nonce=$nonce&timestamp=$ts&sign=$sign';
}
