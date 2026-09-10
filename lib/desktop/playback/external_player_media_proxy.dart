import 'dart:async';
import 'dart:io';
import 'dart:math';

typedef ExternalPlayerMedia = ({Uri source, Map<String, String> headers});

/// 飞牛视频交由 Fly 处理证书和鉴权，播放器只读取本次会话的本机地址。
final class ExternalPlayerMediaProxy {
  ExternalPlayerMediaProxy._(
    this._server,
    this._client,
    Uri source,
    Map<String, String> headers,
  ) {
    final random = Random.secure();
    _path =
        '/${List.generate(24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}/media';
    _loaders[_path] = () async => (source: source, headers: headers);
  }

  final HttpServer _server;
  final HttpClient _client;
  final _loaders = <String, Future<ExternalPlayerMedia> Function()>{};
  late final String _path;
  bool _closed = false;

  String get url => 'http://127.0.0.1:${_server.port}$_path';

  /// 列表先登记稳定地址，用户选中时才解析该集的视频与鉴权。
  String addMedia(Future<ExternalPlayerMedia> Function() load) {
    final path = '$_path/${_loaders.length}';
    _loaders[path] = load;
    return 'http://127.0.0.1:${_server.port}$path';
  }

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
      final load = _loaders[request.uri.path];
      if (_closed || load == null) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final entry = await load();
      if (_closed) return;
      if (entry.source.scheme == 'file') {
        await _serveFile(File.fromUri(entry.source), request);
        return;
      }
      var target = entry.source;
      for (var redirects = 0; redirects <= 5; redirects++) {
        // 飞牛 Authx 对 GET 签名；探测 HEAD 也向上游发 GET，仅返回响应头。
        upstream = await _client.getUrl(target);
        upstream.followRedirects = false;
        if (target.origin == entry.source.origin) {
          entry.headers.forEach((name, value) {
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

  Future<void> _serveFile(File file, HttpRequest request) async {
    final size = await file.length();
    var start = 0;
    var end = size - 1;
    final response = request.response;
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (range != null) {
      final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range);
      if (match == null || (match[1]!.isEmpty && match[2]!.isEmpty)) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
        return;
      }
      if (match[1]!.isEmpty) {
        start = max(0, size - (int.tryParse(match[2]!) ?? 0));
      } else {
        start = int.tryParse(match[1]!) ?? size;
        end = min(end, int.tryParse(match[2]!) ?? end);
      }
      if (start >= size || start > end) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
        return;
      }
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$size',
      );
    }
    response.contentLength = max(0, end - start + 1);
    if (request.method != 'HEAD') {
      await response.addStream(file.openRead(start, end + 1));
    }
  }
}
