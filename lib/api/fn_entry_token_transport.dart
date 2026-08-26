/// FN Connect 入口令牌（cookie `entry-token`）的 Dio 传输层横切。
///
/// 当媒体服务器地址是 `*.fnos.net` 中转域名（藏在飞牛发布服务的反向代理后面）时，请求必须
/// 携带 `Cookie: entry-token=<值>` 才能过云端 FN Connect 边缘闸——实测这是唯一被认的凭据
/// （NAS token / `mode=relay` 都不行）。这套逻辑与 Emby / Jellyfin 协议本身无关，属于纯粹的
/// 传输层鉴权横切，故独立于 API 客户端存放。
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../utils/nas_image_headers.dart';

/// 给 [dio] 安装 FN Connect entry-token 拦截器。
///
/// - [entryTokenProvider]：入口令牌的动态取值器，每请求实时读取，令牌刷新后无需重建客户端；
///   为 null 或返回空串时不写任何 cookie。
/// - [logTag]：诊断日志前缀，默认沿用历史的 `EmbyApi`（fnos 中转链路是实机验证过的敏感路径，
///   日志形状保持不变以便比对既有排障记录）。
///
/// 仅在 [usesFnConnectRelayCookie] 判定为 fnos 中转域名时生效：直连地址既不写 cookie 也不打
/// 日志，行为与未安装拦截器一致。
void installFnEntryTokenInterceptor(
  Dio dio, {
  String Function()? entryTokenProvider,
  String logTag = 'EmbyApi',
}) {
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        if (usesFnConnectRelayCookie(options.uri.toString())) {
          final token = entryTokenProvider?.call().trim() ?? '';
          if (token.isNotEmpty) {
            options.headers['Cookie'] = mergeEntryTokenCookie(
              options.headers['Cookie']?.toString() ?? '',
              token,
            );
          }
          debugPrint(
            '[$logTag][REQ] ${options.method} ${options.uri} '
            'entryTokenLen=${token.length}',
          );
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        final uri = response.requestOptions.uri;
        if (usesFnConnectRelayCookie(uri.toString())) {
          final ct = response.headers.value(Headers.contentTypeHeader) ?? '';
          final raw = response.data;
          final snippet = raw is String
              ? raw.replaceAll('\n', ' ')
              : raw.runtimeType.toString();
          debugPrint(
            '[$logTag][RESP] http=${response.statusCode} ct=$ct '
            'path=${uri.path} body=${snippet.length > 160 ? snippet.substring(0, 160) : snippet}',
          );
        }
        handler.next(response);
      },
      onError: (error, handler) {
        final uri = error.requestOptions.uri;
        if (usesFnConnectRelayCookie(uri.toString())) {
          final body = error.response?.data;
          final snippet = body is String
              ? body.replaceAll('\n', ' ')
              : body?.runtimeType.toString() ?? '';
          debugPrint(
            '[$logTag][ERR] http=${error.response?.statusCode} '
            'type=${error.type} path=${uri.path} '
            'body=${snippet.length > 160 ? snippet.substring(0, 160) : snippet}',
          );
        }
        handler.next(error);
      },
    ),
  );
}
