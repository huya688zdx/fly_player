// 临时验证脚本：用与 _buildAuthxHeaderFor 相同的算法实测新版飞牛后端签名。
// 用法: dart run tool/verify_authx_sign.dart <baseUrl> <user> <password>
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

const _key = 'NDzZTVxnRKP8Z0jXg1VAMonaG8akvh';
const _secret = '16CCEB3D-AB42-077D-36A1-F355324E4237';

String buildAuthx({
  required String method,
  required String path,
  Map<String, String> queryParameters = const <String, String>{},
  dynamic body,
}) {
  final nonce = (100000 + Random().nextInt(900000)).toString();
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
      payload = jsonEncode(body);
    }
    payloadMd5 = md5.convert(utf8.encode(payload)).toString();
  }
  final signBase = [
    _key,
    path,
    nonce,
    timestamp,
    payloadMd5,
    _secret,
  ].join('_');
  final sign = md5.convert(utf8.encode(signBase)).toString();
  return 'nonce=$nonce&timestamp=$timestamp&sign=$sign';
}

Future<Map<String, dynamic>> request(
  HttpClient client,
  String baseUrl,
  String method,
  String path, {
  Map<String, String> query = const <String, String>{},
  Map<String, dynamic>? body,
  String token = '',
}) async {
  final uri = Uri.parse(
    '$baseUrl$path',
  ).replace(queryParameters: query.isEmpty ? null : query);
  final req = await client.openUrl(method, uri);
  req.headers.set('Content-Type', 'application/json');
  if (token.isNotEmpty) {
    req.headers.set('Authorization', token);
    req.headers.set(
      'Authx',
      buildAuthx(
        method: method,
        path: uri.path,
        queryParameters: uri.queryParameters,
        body: body,
      ),
    );
  }
  if (body != null) {
    req.write(jsonEncode(body));
  }
  final resp = await req.close();
  final text = await resp.transform(utf8.decoder).join();
  return jsonDecode(text) as Map<String, dynamic>;
}

Future<void> main(List<String> args) async {
  final baseUrl = args[0];
  final client = HttpClient();
  final login = await request(
    client,
    baseUrl,
    'POST',
    '/v/api/v1/login',
    body: {'userName': args[1], 'password': args[2]},
  );
  final token = (login['data'] as Map?)?['token']?.toString() ?? '';
  stdout.writeln('login code=${login['code']} token=${token.isNotEmpty}');

  final cases = <String, Future<Map<String, dynamic>>>{
    'GET mediadb/list (无query)': request(
      client,
      baseUrl,
      'GET',
      '/v/api/v1/mediadb/list',
      token: token,
    ),
    'GET user/info (无query)': request(
      client,
      baseUrl,
      'GET',
      '/v/api/v1/user/info',
      token: token,
    ),
    'GET search/list (中文query)': request(
      client,
      baseUrl,
      'GET',
      '/v/api/v1/search/list',
      query: {'q': '动漫'},
      token: token,
    ),
    'GET tag/genres (多query乱序)': request(
      client,
      baseUrl,
      'GET',
      '/v/api/v1/tag/genres',
      query: {'lan': 'zh-CN', 'category': 'Movie'},
      token: token,
    ),
    'POST item/list (带body)': request(
      client,
      baseUrl,
      'POST',
      '/v/api/v1/item/list',
      body: {'page': 1, 'page_size': 1},
      token: token,
    ),
  };
  for (final entry in cases.entries) {
    final result = await entry.value;
    stdout.writeln('${entry.key}: code=${result['code']} msg=${result['msg']}');
  }
  client.close();
}
