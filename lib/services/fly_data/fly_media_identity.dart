import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import '../../api/feiniu_api.dart';
import 'fly_data_api.dart';

/// 应用媒体凭据前只探测公开身份，不携带飞翔或媒体账号令牌、不跟随重定向。
/// 飞牛 FN 入口的 mode=relay 仅选择中继路由，不是登录凭据。
Future<void> verifyFlyMediaAddress({
  required String address,
  required String kind,
  required String expectedId,
  String fnEntryToken = '',
  Duration timeout = const Duration(seconds: 15),
}) async {
  if (expectedId.isEmpty) throw StateError('媒体服务器尚无可验证身份，请重新授权。');
  if (timeout <= Duration.zero) throw StateError('媒体地址验证已超时，请重试。');
  final dio = createStrictFlyDio();
  dio.options.connectTimeout = timeout;
  dio.options.sendTimeout = timeout;
  final feiniu = kind == 'feiniu';
  final path = feiniu ? '/v/api/v1/server/info' : '/System/Info/Public';
  final headers = <String, String>{};
  if (!feiniu && fnEntryToken.isNotEmpty) {
    final uri = Uri.parse(address);
    if (uri.scheme != 'https' ||
        !uri.host.endsWith('.fnos.net') ||
        !RegExp(
          r'^[\x21\x23-\x2B\x2D-\x3A\x3C-\x5B\x5D-\x7E]+$',
        ).hasMatch(fnEntryToken)) {
      dio.close(force: true);
      throw StateError('FN 媒体入口授权无效，请重新授权。');
    }
    // 此令牌由当前媒体入口的网页授权获得，不使用飞翔或其他来源的 Cookie。
    headers['Cookie'] = 'entry-token=$fnEntryToken';
  }
  if (feiniu) {
    final nonce = '${100000 + Random.secure().nextInt(900000)}';
    final timestamp = '${DateTime.now().millisecondsSinceEpoch}';
    final digest = md5.convert(utf8.encode(''));
    final sign = md5.convert(
      utf8.encode(
        'NDzZTVxnRKP8Z0jXg1VAMonaG8akvh_${path}_${nonce}_${timestamp}_${digest}_16CCEB3D-AB42-077D-36A1-F355324E4237',
      ),
    );
    headers.addAll({
      'Authx': 'nonce=$nonce&timestamp=$timestamp&sign=$sign',
      'X-Trim-Client': 'web',
      'X-Trim-Client-Version': '616',
      if (FeiniuApi.shouldUseRelayModeCookieForBaseUrl(address))
        'Cookie': 'mode=relay',
    });
  }
  final cancelToken = CancelToken();
  // Bound the complete probe, including a body that trickles bytes forever.
  // Cancel the request and close its isolated transport, not just its Future.
  final deadline = Timer(timeout, () {
    cancelToken.cancel('Media identity probe deadline exceeded');
    dio.close(force: true);
  });
  try {
    final response = await dio.get<dynamic>(
      '${address.replaceAll(RegExp(r'/+$'), '')}$path',
      cancelToken: cancelToken,
      options: Options(
        headers: headers,
        followRedirects: false,
        receiveTimeout: timeout,
      ),
    );
    final data = response.data;
    final actualId = data is Map
        ? feiniu
              ? data['code'] == 0 && data['data'] is Map
                    ? data['data']['guid']
                    : null
              : data['Id']
        : null;
    if (actualId != expectedId) throw StateError('媒体地址属于另一台服务器，未使用该地址的凭据。');
  } on DioException {
    throw StateError('无法验证媒体地址，请检查地址、网络和 HTTPS 证书。');
  } finally {
    deadline.cancel();
    dio.close(force: true);
  }
}
