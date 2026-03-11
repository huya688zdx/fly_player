import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../api/feiniu_api.dart';
import '../utils/api_url_helper.dart';

class MpvProxyRegistration {
  final String sessionId;
  final Uri localUri;

  const MpvProxyRegistration({required this.sessionId, required this.localUri});
}

class MpvProxyServer {
  MpvProxyServer._();

  static final MpvProxyServer instance = MpvProxyServer._();

  final Random _random = Random();
  final Map<String, _ProxySession> _sessions = <String, _ProxySession>{};
  HttpServer? _server;

  Future<MpvProxyRegistration> registerStream({
    required FeiniuApi api,
    required String remoteUrl,
  }) async {
    await _ensureStarted();
    final sessionId = _nextSessionId();
    final remoteUri = Uri.parse(remoteUrl);
    _sessions[sessionId] = _ProxySession(
      api: api,
      remoteUri: remoteUri,
      createdAt: DateTime.now(),
    );
    final localEntryName = _localEntryName(remoteUri);
    return MpvProxyRegistration(
      sessionId: sessionId,
      localUri: Uri.parse(
        'http://127.0.0.1:${_server!.port}/stream/$sessionId/$localEntryName',
      ),
    );
  }

  void unregister(String sessionId) {
    _sessions.remove(sessionId);
  }

  Future<void> _ensureStarted() async {
    if (_server != null) return;
    _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: true,
    );
    unawaited(
      _server!.forEach(_handleRequest).catchError((
        Object error,
        StackTrace st,
      ) {
        debugPrint('[MPV][PROXY] server stopped error=$error');
      }),
    );
    debugPrint('[MPV][PROXY] started port=${_server!.port}');
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    if (segments.length < 2 || segments.first != 'stream') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final session = _sessions[segments[1]];
    if (session == null) {
      request.response.statusCode = HttpStatus.gone;
      await request.response.close();
      return;
    }

    if (request.method != 'GET' && request.method != 'HEAD') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      request.response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      await request.response.close();
      return;
    }

    final remoteUri = session.resolveRemoteUri(request.uri);
    final client = HttpClient()..autoUncompress = false;
    _configurePrivateTls(client, remoteUri.toString());

    try {
      final upstreamRequest = await client.openUrl(request.method, remoteUri);
      upstreamRequest.followRedirects = true;
      upstreamRequest.bufferOutput = false;

      final extraHeaders = <String, String>{};
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null && range.trim().isNotEmpty) {
        extraHeaders[HttpHeaders.rangeHeader] = range.trim();
      }
      final userAgent = request.headers.value(HttpHeaders.userAgentHeader);
      if (userAgent != null && userAgent.trim().isNotEmpty) {
        extraHeaders[HttpHeaders.userAgentHeader] = userAgent.trim();
      }

      final headers = session.api.buildSignedHeadersForUrl(
        remoteUri.toString(),
        method: request.method,
        extraHeaders: extraHeaders,
      );
      headers.forEach(upstreamRequest.headers.set);

      debugPrint(
        '[MPV][PROXY] upstream request method=${request.method} '
        'range=${extraHeaders[HttpHeaders.rangeHeader] ?? '-'} '
        'url=$remoteUri',
      );
      final upstreamResponse = await upstreamRequest.close();
      request.response.statusCode = upstreamResponse.statusCode;
      request.response.reasonPhrase = upstreamResponse.reasonPhrase;
      request.response.bufferOutput = false;
      _copyResponseHeaders(upstreamResponse, request.response);
      debugPrint(
        '[MPV][PROXY] upstream response status=${upstreamResponse.statusCode} '
        'range=${upstreamResponse.headers.value(HttpHeaders.contentRangeHeader) ?? '-'} '
        'length=${upstreamResponse.headers.value(HttpHeaders.contentLengthHeader) ?? '-'} '
        'acceptRanges=${upstreamResponse.headers.value(HttpHeaders.acceptRangesHeader) ?? '-'} '
        'url=$remoteUri',
      );

      if (request.method == 'HEAD') {
        await request.response.close();
      } else {
        await upstreamResponse.pipe(request.response);
      }
    } catch (error) {
      debugPrint('[MPV][PROXY] request failed url=$remoteUri error=$error');
      request.response.statusCode = HttpStatus.badGateway;
      request.response.headers.contentType = ContentType.text;
      request.response.write('proxy error: $error');
      await request.response.close();
    } finally {
      client.close(force: true);
    }
  }

  void _copyResponseHeaders(
    HttpClientResponse upstream,
    HttpResponse downstream,
  ) {
    upstream.headers.forEach((name, values) {
      final lower = name.toLowerCase();
      if (lower == HttpHeaders.transferEncodingHeader ||
          lower == HttpHeaders.connectionHeader ||
          lower == 'keep-alive' ||
          lower == 'proxy-connection') {
        return;
      }
      for (final value in values) {
        downstream.headers.add(name, value);
      }
    });
  }

  void _configurePrivateTls(HttpClient client, String url) {
    final uri = Uri.tryParse(ApiUrlHelper.normalizeBaseUrl(url));
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        !_isPrivateHost(uri.host)) {
      return;
    }
    client.badCertificateCallback = (cert, host, port) => host == uri.host;
  }

  bool _isPrivateHost(String host) {
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

  String _nextSessionId() {
    final bytes = List<int>.generate(12, (_) => _random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  String _localEntryName(Uri remoteUri) {
    if (remoteUri.pathSegments.isEmpty) return 'stream';
    final candidate = remoteUri.pathSegments.last.trim();
    if (candidate.isEmpty) return 'stream';
    return candidate;
  }
}

class _ProxySession {
  final FeiniuApi api;
  final Uri remoteUri;
  final DateTime createdAt;

  const _ProxySession({
    required this.api,
    required this.remoteUri,
    required this.createdAt,
  });

  Uri resolveRemoteUri(Uri requestUri) {
    final segments = requestUri.pathSegments;
    if (segments.length <= 2) {
      return _withQuery(remoteUri, requestUri.query);
    }

    final relativeUri = Uri(
      pathSegments: segments.skip(2),
      query: requestUri.hasQuery ? requestUri.query : null,
    );
    return remoteUri.resolveUri(relativeUri);
  }

  Uri _withQuery(Uri uri, String query) {
    if (query.isEmpty) return uri;
    return uri.replace(query: query);
  }
}
