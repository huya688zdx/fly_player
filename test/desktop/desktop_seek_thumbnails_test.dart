import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/playback/desktop_seek_thumbnails.dart';
import 'package:fly_player/models/stream_track_data.dart';

void main() {
  late HttpServer server;
  late DesktopSeekThumbnails thumbnails;
  late String baseUrl;
  final requests = <HttpRequest>[];
  var invalidBif = false;
  const headers = {'Cookie': 'entry-token=test-token'};

  setUp(() async {
    requests.clear();
    invalidBif = false;
    thumbnails = DesktopSeekThumbnails();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      requests.add(request);
      if (request.uri.path == '/missing.bif') {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        request.response.add(invalidBif ? [1, 2, 3] : _bif());
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    thumbnails.dispose();
    await server.close(force: true);
  });

  test('BIF 带播放鉴权下载，按目标时间取帧且换源清空旧帧', () async {
    final chapters = [MpvSeekThumbnail(positionMs: 0, url: '$baseUrl/chapter')];
    final loaded = thumbnails.prepare(
      bifUrl: '$baseUrl/index.bif?api_key=test',
      chapters: chapters,
      headers: headers,
    );
    expect((thumbnails.imageAt(15000) as NetworkImage).headers, headers);
    await loaded;
    expect(requests.single.headers.value('Cookie'), headers['Cookie']);
    expect(requests.single.uri.queryParameters['api_key'], 'test');
    expect((thumbnails.imageAt(9999) as MemoryImage).bytes, [10, 11]);
    final secondFrame = thumbnails.imageAt(10000) as MemoryImage;
    expect(secondFrame.bytes, [20, 21, 22]);
    expect(identical(thumbnails.imageAt(60000), secondFrame), isTrue);
    await thumbnails.prepare(
      bifUrl: '$baseUrl/index.bif?api_key=test',
      chapters: chapters,
      headers: headers,
    );
    expect(requests, hasLength(1));
    await thumbnails.prepare(bifUrl: '', chapters: [], headers: {});
    expect(thumbnails.imageAt(15000), isNull);
  });

  test('BIF 缺失或损坏时退回对应章节，重复刷新不重试失败请求', () async {
    final chapters = [
      MpvSeekThumbnail(positionMs: 0, url: '$baseUrl/chapter/0'),
      MpvSeekThumbnail(positionMs: 10000, url: '$baseUrl/chapter/1'),
    ];
    await thumbnails.prepare(
      bifUrl: '$baseUrl/missing.bif',
      chapters: chapters,
      headers: headers,
    );
    final image = thumbnails.imageAt(15000) as NetworkImage;
    expect(image.url, '$baseUrl/chapter/1');
    expect(image.headers, headers);
    await thumbnails.prepare(
      bifUrl: '$baseUrl/missing.bif',
      chapters: chapters,
      headers: headers,
    );
    expect(requests, hasLength(1));
    invalidBif = true;
    await thumbnails.prepare(
      bifUrl: '$baseUrl/broken.bif',
      chapters: chapters,
      headers: headers,
    );
    expect(
      (thumbnails.imageAt(9999) as NetworkImage).url,
      '$baseUrl/chapter/0',
    );
  });
}

// 两帧、10 秒间隔；只验证 BIF 索引与切片，图片解码由 Flutter 负责。
Uint8List _bif() {
  final bytes = Uint8List(93);
  bytes.setRange(0, 8, [0x89, 0x42, 0x49, 0x46, 0x0d, 0x0a, 0x1a, 0x0a]);
  final data = ByteData.sublistView(bytes);
  void put(int at, int value) => data.setUint32(at, value, Endian.little);
  put(12, 2);
  put(16, 1000);
  put(64, 0);
  put(68, 88);
  put(72, 10);
  put(76, 90);
  put(80, 0xffffffff);
  put(84, 93);
  bytes.setRange(88, 93, [10, 11, 20, 21, 22]);
  return bytes;
}
