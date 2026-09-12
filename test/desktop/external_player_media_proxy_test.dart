import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/playback/external_player_media_proxy.dart';

class _LoopbackFixtureHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..findProxy = (uri) => uri.host == '127.0.0.1' || uri.host == '::1'
            ? 'DIRECT'
            : HttpClient.findProxyFromEnvironment(uri);
}

void main() {
  setUp(() {
    // Also isolate the proxy's upstream client: its origin here is a fixture.
    final previous = HttpOverrides.current;
    HttpOverrides.global = _LoopbackFixtureHttpOverrides();
    addTearDown(() => HttpOverrides.global = previous);
  });
  test('HLS 清单、相对分片和密钥均经本机中转，并按各自地址签名', () async {
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => origin.close(force: true));
    final signedPaths = <String>[];
    origin.listen((request) async {
      expect(request.headers.value('Authx'), 'GET ${request.uri.path}');
      signedPaths.add(request.uri.path);
      if (request.uri.path.endsWith('.m3u8')) {
        request.response.headers.set(
          'Content-Type',
          'application/vnd.apple.mpegurl',
        );
        request.response.write(
          '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n#EXTINF:4,\nsegment.ts?sequence=1\n#EXT-X-ENDLIST\n',
        );
      } else {
        request.response.add([0x47, 1, 2, 3]);
      }
      await request.response.close();
    });
    final proxy = await ExternalPlayerMediaProxy.start(
      source: Uri.parse('http://127.0.0.1:${origin.port}/stream/main.m3u8'),
      headers: {'Authx': 'original-signature'},
      headersForUrl: (url) => {'Authx': 'GET ${url.path}'},
    );
    addTearDown(proxy.close);
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    addTearDown(() => client.close(force: true));
    final response = await (await client.getUrl(Uri.parse(proxy.url))).close();
    final body = String.fromCharCodes(
      await response.expand((chunk) => chunk).toList(),
    );
    final key = RegExp('URI="([^"]+)"').firstMatch(body)![1]!;
    final segment = body
        .split('\n')
        .firstWhere((line) => line.startsWith('http'));
    for (final url in [key, segment]) {
      expect(Uri.parse(url).port, Uri.parse(proxy.url).port);
      final part = await (await client.getUrl(Uri.parse(url))).close();
      expect(await part.expand((chunk) => chunk).toList(), [0x47, 1, 2, 3]);
    }
    expect(signedPaths, [
      '/stream/main.m3u8',
      '/stream/key.bin',
      '/stream/segment.ts',
    ]);
  });

  test('视频中转保留鉴权、Range 和 HEAD，关闭后停止取流', () async {
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => origin.close(force: true));
    final requests = <Map<String, String?>>[];
    origin.listen((request) async {
      requests.add({
        'host': request.headers.value('Host'),
        'method': request.method,
        'auth': request.headers.value('Authorization'),
        'authx': request.headers.value('Authx'),
        'cookie': request.headers.value('Cookie'),
        'range': request.headers.value('Range'),
      });
      final partial = request.headers.value('Range') == 'bytes=2-4';
      request.response.statusCode = partial ? 206 : 200;
      request.response.headers.set('Accept-Ranges', 'bytes');
      if (partial) request.response.headers.set('Content-Range', 'bytes 2-4/6');
      request.response.contentLength = partial ? 3 : 6;
      request.response.add(partial ? [2, 3, 4] : [0, 1, 2, 3, 4, 5]);
      await request.response.close();
    });
    final proxy = await ExternalPlayerMediaProxy.start(
      source: Uri.parse('http://127.0.0.1:${origin.port}/media'),
      headers: {
        'Authorization': 'nas-token',
        'Authx': 'get-signature',
        'Cookie': 'mode=relay',
        'Range': 'bytes=0-',
      },
    );
    addTearDown(proxy.close);
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    addTearDown(() => client.close(force: true));
    final get = await client.getUrl(Uri.parse(proxy.url));
    get.headers.set('Range', 'bytes=2-4');
    get.headers.set('Authorization', 'player-token');
    final part = await get.close();
    expect(part.statusCode, 206);
    expect(part.headers.value('Content-Range'), 'bytes 2-4/6');
    expect(part.contentLength, 3);
    expect(await part.expand((chunk) => chunk).toList(), [2, 3, 4]);
    final head = await (await client.headUrl(Uri.parse(proxy.url))).close();
    expect(head.contentLength, 6);
    expect(await head.expand((chunk) => chunk).toList(), isEmpty);
    expect(requests, [
      {
        'method': 'GET',
        'host': '127.0.0.1:${origin.port}',
        'auth': 'nas-token',
        'authx': 'get-signature',
        'cookie': 'mode=relay',
        'range': 'bytes=2-4',
      },
      {
        'method': 'GET',
        'host': '127.0.0.1:${origin.port}',
        'auth': 'nas-token',
        'authx': 'get-signature',
        'cookie': 'mode=relay',
        'range': null,
      },
    ]);
    final localDirectory = await Directory.systemTemp.createTemp(
      'fly_playlist_test_',
    );
    addTearDown(() => localDirectory.delete(recursive: true));
    final local = await File(
      '${localDirectory.path}/downloaded.bin',
    ).writeAsBytes([6, 7, 8, 9]);
    var resolutions = 0;
    final localUrl = proxy.addMedia(() async {
      resolutions++;
      return (source: local.uri, headers: <String, String>{});
    });
    expect(resolutions, 0);
    final localRequest = await client.getUrl(Uri.parse(localUrl));
    localRequest.headers.set('Range', 'bytes=1-2');
    final localResponse = await localRequest.close();
    expect(localResponse.statusCode, 206);
    expect(localResponse.headers.value('Content-Range'), 'bytes 1-2/4');
    expect(await localResponse.expand((chunk) => chunk).toList(), [7, 8]);
    expect(resolutions, 1);
    final missing = await (await client.getUrl(
      Uri.parse(proxy.url).replace(path: '/unknown/media'),
    )).close();
    expect(missing.statusCode, 404);
    await missing.drain<void>();
    expect(requests.length, 2);
    final playerUri = Uri.parse(proxy.url);
    await proxy.close();
    client.close(force: true);
    final freshClient = HttpClient()..findProxy = (_) => 'DIRECT';
    addTearDown(() => freshClient.close(force: true));
    await expectLater(() async {
      final request = await freshClient.getUrl(playerUri);
      final response = await request.close();
      await response.drain<void>();
    }(), throwsA(isA<SocketException>()));
    await expectLater(
      Socket.connect(
        playerUri.host,
        playerUri.port,
        timeout: const Duration(seconds: 2),
      ).then((socket) => socket.destroy()),
      throwsA(isA<SocketException>()),
    );
    expect(requests.length, 2);
    expect(resolutions, 1);
  });

  test('跨源重定向不携带 NAS 鉴权信息', () async {
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => origin.close(force: true));
    addTearDown(() => target.close(force: true));
    origin.listen((request) async {
      request.response.statusCode = 302;
      request.response.headers.set(
        'Location',
        'http://127.0.0.1:${target.port}/redirected',
      );
      await request.response.close();
    });
    final received = <String?>[];
    target.listen((request) async {
      for (final name in [
        'Authorization',
        'Authx',
        'Trim-MC-token',
        'Cookie',
      ]) {
        received.add(request.headers.value(name));
      }
      request.response.add([1, 2]);
      await request.response.close();
    });
    final proxy = await ExternalPlayerMediaProxy.start(
      source: Uri.parse('http://127.0.0.1:${origin.port}/media'),
      headers: {
        'Authorization': 'token',
        'Authx': 'signature',
        'Trim-MC-token': 'token',
        'Cookie': 'mode=relay',
      },
    );
    addTearDown(proxy.close);
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    addTearDown(() => client.close(force: true));
    final result = await (await client.getUrl(Uri.parse(proxy.url))).close();
    expect(result.statusCode, 200);
    expect(await result.expand((chunk) => chunk).toList(), [1, 2]);
    expect(received, [null, null, null, null]);
  });
}
