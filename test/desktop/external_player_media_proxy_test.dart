import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/playback/external_player_media_proxy.dart';

void main() {
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
    final client = HttpClient();
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
    final freshClient = HttpClient();
    addTearDown(() => freshClient.close(force: true));
    await expectLater(
      freshClient.getUrl(playerUri),
      throwsA(isA<SocketException>()),
    );
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
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final result = await (await client.getUrl(Uri.parse(proxy.url))).close();
    expect(result.statusCode, 200);
    expect(await result.expand((chunk) => chunk).toList(), [1, 2]);
    expect(received, [null, null, null, null]);
  });
}
