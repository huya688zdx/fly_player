import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/api/fn_entry_token_transport.dart';

/// 传输层横切单测：entry-token 拦截器的命中条件与 header 写法（fnos 中转是实机验证过的
/// 敏感鉴权链路，此处锁死行为，防止后续重构走样）。
void main() {
  test('fnos 中转域名注入 entry-token cookie', () async {
    final captured = <RequestOptions>[];
    final dio = _dioWith(captured);
    installFnEntryTokenInterceptor(dio, entryTokenProvider: () => 'entry-abc');

    await dio.get<Object?>('https://embyserver4-9.geqian688.fnos.net/Items');

    expect(captured.single.headers['Cookie'], 'entry-token=entry-abc');
  });

  test('已有 Cookie 合并：保留其它键、去重旧 entry-token', () async {
    final captured = <RequestOptions>[];
    final dio = _dioWith(captured);
    installFnEntryTokenInterceptor(dio, entryTokenProvider: () => 'new-token');

    await dio.get<Object?>(
      'https://relay.fnos.net/Items',
      options: Options(
        headers: <String, Object?>{
          'Cookie': 'session=abc; entry-token=stale; mode=relay',
        },
      ),
    );

    expect(
      captured.single.headers['Cookie'],
      'session=abc; mode=relay; entry-token=new-token',
    );
  });

  test('令牌两侧空白被裁剪后写入', () async {
    final captured = <RequestOptions>[];
    final dio = _dioWith(captured);
    installFnEntryTokenInterceptor(dio, entryTokenProvider: () => '  tok  ');

    await dio.get<Object?>('https://relay.fnos.net/Items');

    expect(captured.single.headers['Cookie'], 'entry-token=tok');
  });

  test('直连域名不写任何 cookie', () async {
    final captured = <RequestOptions>[];
    final dio = _dioWith(captured);
    installFnEntryTokenInterceptor(dio, entryTokenProvider: () => 'entry-abc');

    await dio.get<Object?>('https://emby.example.test/Items');

    expect(captured.single.headers.containsKey('Cookie'), isFalse);
  });

  test('取值器为空串或未提供时不写 cookie', () async {
    final captured = <RequestOptions>[];
    final dio = _dioWith(captured);
    installFnEntryTokenInterceptor(dio, entryTokenProvider: () => '   ');
    await dio.get<Object?>('https://relay.fnos.net/Items');

    final capturedNoProvider = <RequestOptions>[];
    final dioNoProvider = _dioWith(capturedNoProvider);
    installFnEntryTokenInterceptor(dioNoProvider);
    await dioNoProvider.get<Object?>('https://relay.fnos.net/Items');

    expect(captured.single.headers.containsKey('Cookie'), isFalse);
    expect(capturedNoProvider.single.headers.containsKey('Cookie'), isFalse);
  });

  test('每请求实时读取令牌，刷新后无需重建客户端', () async {
    final captured = <RequestOptions>[];
    final dio = _dioWith(captured);
    var token = 'first';
    installFnEntryTokenInterceptor(dio, entryTokenProvider: () => token);

    await dio.get<Object?>('https://relay.fnos.net/Items');
    token = 'second';
    await dio.get<Object?>('https://relay.fnos.net/Items');

    expect(captured[0].headers['Cookie'], 'entry-token=first');
    expect(captured[1].headers['Cookie'], 'entry-token=second');
  });
}

Dio _dioWith(List<RequestOptions> captured) =>
    Dio(BaseOptions())..httpClientAdapter = _CapturingAdapter(captured);

class _CapturingAdapter implements HttpClientAdapter {
  _CapturingAdapter(this.captured);

  final List<RequestOptions> captured;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    captured.add(options);
    return ResponseBody.fromString(
      jsonEncode(const <String, Object?>{'Items': <Object?>[]}),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
