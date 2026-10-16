import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/api/feiniu_api.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 列表读（`item/list` / `favorite/list`）的超时与重试策略。
///
/// 背景：dio 5.9.2 的 `receiveTimeout` 在 io_adapter 里只包 `request.close()`，即只覆盖
/// 「等到响应头」，不约束响应体传输。飞牛大库要现算 total，TTFB 会顶到默认的 10s——
/// 用户反馈的「媒体库加载不出来」即此形态。所以对列表读单独放宽 TTFB 预算，并对
/// 「快速失败」的瞬时错误（连接类 + 5xx）重试一次；超时不重试。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<FeiniuApi> buildApi(
    FutureOr<ResponseBody> Function(RequestOptions options) handler,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final provider = NasProvider();
    addTearDown(provider.dispose);
    await provider.updateSettings(
      baseUrl: 'http://127.0.0.1:5667',
      userName: 'user',
      password: '',
      token: 'token',
    );
    return FeiniuApi(provider, httpClientAdapter: _FakeDioAdapter(handler));
  }

  ResponseBody okPage() => _jsonResponse(<String, Object?>{
    'code': 0,
    'data': <String, Object?>{'list': <Object?>[], 'total': 0},
  });

  ResponseBody serverError() =>
      _jsonResponse(<String, Object?>{'message': 'boom'}, statusCode: 500);

  ResponseBody notImplemented() => _jsonResponse(<String, Object?>{
    'message': 'Not Implemented, please update.',
  }, statusCode: 501);

  test('5xx 首次失败会重试一次并成功', () async {
    var calls = 0;
    final api = await buildApi((options) {
      if (!options.path.endsWith('/item/list')) return okPage();
      calls++;
      return calls == 1 ? serverError() : okPage();
    });

    final page = await api.getItemsPage(<String, dynamic>{'page': 1});
    expect(page.items, isEmpty);
    expect(calls, 2, reason: '应重试一次');
  });

  test('5xx 连续失败只重试一次，不会无限重试', () async {
    var calls = 0;
    final api = await buildApi((options) {
      if (!options.path.endsWith('/item/list')) return okPage();
      calls++;
      return serverError();
    });

    await expectLater(
      api.getItemsPage(<String, dynamic>{'page': 1}),
      throwsA(isA<Object>()),
    );
    expect(calls, 2, reason: '首次 + 一次重试，共 2 次');
  });

  test('501 Not Implemented 不重试——重试必然同样失败', () async {
    var calls = 0;
    final api = await buildApi((options) {
      if (!options.path.endsWith('/item/list')) return okPage();
      calls++;
      return notImplemented();
    });

    await expectLater(
      api.getItemsPage(<String, dynamic>{'page': 1}),
      throwsA(isA<Object>()),
    );
    expect(calls, 1, reason: '501 属永久失败，不应重试');
  });

  test('收藏列表沿用同一策略', () async {
    var calls = 0;
    final api = await buildApi((options) {
      if (!options.path.endsWith('/favorite/list')) return okPage();
      calls++;
      return calls == 1 ? serverError() : okPage();
    });

    await api.getFavoritePage();
    expect(calls, 2);
  });

  test('列表读单独放宽 TTFB 预算到 20s，全局默认仍是 10s', () async {
    final byPath = <String, Duration?>{};
    final api = await buildApi((options) {
      byPath[options.path] = options.receiveTimeout;
      return okPage();
    });

    await api.getItemsPage(<String, dynamic>{'page': 1});
    expect(byPath['/v/api/v1/item/list'], const Duration(seconds: 20));

    // 对照：普通请求（非列表读）仍走全局默认。不该一起拉长，否则服务端真挂时
    // 用户要多等一倍。
    try {
      await api.getUserInfo();
    } catch (_) {
      // 假响应形状不完整，这里只为观察该请求的超时设置。
    }
    expect(byPath['/v/api/v1/user/info'], const Duration(seconds: 10));
  });
}

class _FakeDioAdapter implements HttpClientAdapter {
  _FakeDioAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonResponse(
  Map<String, Object?> payload, {
  int statusCode = 200,
}) {
  return ResponseBody.fromString(
    jsonEncode(payload),
    statusCode,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );
}
