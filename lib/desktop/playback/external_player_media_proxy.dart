import 'dart:async';
import 'dart:io';
import 'dart:math';

/// 飞牛视频交由 Fly 处理证书和鉴权，播放器只读取本次会话的本机地址。
final class ExternalPlayerMediaProxy {
  ExternalPlayerMediaProxy._(
    this._server,
    this._client,
    this._source,
    this._headers,
  ) {
    final random = Random.secure();
    _path =
        '/${List.generate(24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}/media';
  }

  final HttpServer _server;
  final HttpClient _client;
  final Uri _source;
  final Map<String, String> _headers;
  late final String _path;
  bool _closed = false;

  String get url => 'http://127.0.0.1:${_server.port}$_path';

  static Future<ExternalPlayerMediaProxy> start({
    required Uri source,
    required Map<String, String> headers,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    // 沿用应用的 PrivateNetworkHttpOverrides，不扩大 NAS 证书信任范围。
    final client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = const Duration(seconds: 12);
    final proxy = ExternalPlayerMediaProxy._(
      server,
      client,
      source,
      Map.of(headers),
    );
    server.listen((request) => unawaited(proxy._serve(request)));
    return proxy;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _client.close(force: true);
    await _server.close(force: true);
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    HttpClientRequest? upstream;
    var finished = false;
    unawaited(
      response.done.then<void>(
        (_) {
          if (!finished) upstream?.abort();
        },
        onError: (Object _) {
          upstream?.abort();
        },
      ),
    );
    try {
      if (_closed || request.uri.path != _path) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      var target = _source;
      for (var redirects = 0; redirects <= 5; redirects++) {
        // 飞牛 Authx 对 GET 签名；探测 HEAD 也向上游发 GET，仅返回响应头。
        upstream = await _client.getUrl(target);
        upstream.followRedirects = false;
        if (target.origin == _source.origin) {
          _headers.forEach((name, value) {
            if (!{
              HttpHeaders.hostHeader,
              HttpHeaders.connectionHeader,
              HttpHeaders.rangeHeader,
            }.contains(name.toLowerCase())) {
              upstream!.headers.set(name, value);
            }
          });
        }
        upstream.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        for (final name in [
          HttpHeaders.rangeHeader,
          HttpHeaders.ifRangeHeader,
        ]) {
          final value = request.headers.value(name);
          if (value != null) upstream.headers.set(name, value);
        }
        final media = await upstream.close().timeout(
          const Duration(seconds: 15),
        );
        if (media.isRedirect) {
          final location = media.headers.value(HttpHeaders.locationHeader);
          await media.listen(null).cancel();
          if (location == null || redirects == 5) {
            throw const HttpException('媒体重定向无效');
          }
          target = target.resolve(location);
          if (target.scheme != 'http' && target.scheme != 'https') {
            throw const HttpException('媒体重定向协议无效');
          }
          continue;
        }
        response.statusCode = media.statusCode;
        for (final name in [
          HttpHeaders.contentTypeHeader,
          HttpHeaders.contentLengthHeader,
          HttpHeaders.contentRangeHeader,
          HttpHeaders.contentEncodingHeader,
          HttpHeaders.acceptRangesHeader,
          HttpHeaders.etagHeader,
          HttpHeaders.lastModifiedHeader,
        ]) {
          final value = media.headers.value(name);
          if (value != null) response.headers.set(name, value);
        }
        if (request.method == 'HEAD') {
          await media.listen(null).cancel();
        } else {
          await response.addStream(media.timeout(const Duration(seconds: 30)));
        }
        break;
      }
    } catch (_) {
      upstream?.abort();
      // 不把包含 NAS 地址、签名或令牌的网络异常返回给播放器。
      try {
        response.statusCode = HttpStatus.badGateway;
        response.headers.removeAll(HttpHeaders.contentLengthHeader);
      } catch (_) {
        // 已开始传输时由连接关闭结束本次请求。
      }
    } finally {
      finished = true;
      try {
        await response.close();
      } catch (_) {
        // 拖动或退出时播放器会主动取消旧的取流请求。
      }
    }
  }
}
