import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/api/feiniu_access_code_transport.dart';

void main() {
  group('访问码请求头', () {
    test('使用 UTF-8 Base64 编码中文访问码，并裁剪空白', () {
      expect(buildFeiniuAccessCodeHeaders('  中文访问码  '), <String, String>{
        'x-access-code': base64Encode(utf8.encode('中文访问码')),
        'x-access-source': 'app',
      });
    });

    test('空白访问码不产生请求头', () {
      expect(buildFeiniuAccessCodeHeaders(' \n\t '), isEmpty);
    });
  });

  group('同源判断', () {
    test('同一 scheme、host 和端口的 URL 同源', () {
      expect(
        isSameHttpOrigin(
          'https://NAS.example.test:8443/api',
          'https://nas.EXAMPLE.test:8443/items',
        ),
        isTrue,
      );
    });

    test('scheme、host 或端口不同时拒绝', () {
      expect(
        isSameHttpOrigin('https://nas.example.test', 'http://nas.example.test'),
        isFalse,
      );
      expect(
        isSameHttpOrigin(
          'https://nas.example.test',
          'https://other.example.test',
        ),
        isFalse,
      );
      expect(
        isSameHttpOrigin(
          'https://nas.example.test',
          'https://nas.example.test:8443',
        ),
        isFalse,
      );
    });

    test('HTTP(S) 默认端口等价，普通相对 URL 视为同源', () {
      expect(
        isSameHttpOrigin(
          'HTTPS://nas.example.test:443/api',
          'https://nas.example.test/items',
        ),
        isTrue,
      );
      expect(isSameHttpOrigin('http://nas.example.test', '/api/items'), isTrue);
    });

    test('无效、无 host 或非 HTTP(S) 目标不属于同源', () {
      expect(isSameHttpOrigin('not a url', '/items'), isFalse);
      expect(isSameHttpOrigin('https:///items', '/items'), isFalse);
      expect(
        isSameHttpOrigin('https://nas.example.test', 'file:///tmp/a'),
        isFalse,
      );
      expect(
        isSameHttpOrigin(
          'https://nas.example.test',
          'https://nas.example.test:70000/items',
        ),
        isFalse,
      );
      expect(
        isSameHttpOrigin('https://nas.example.test:70000', '/items'),
        isFalse,
      );
      expect(
        isSameHttpOrigin(
          'https://nas.example.test:70000',
          'https://nas.example.test:70000/items',
        ),
        isFalse,
      );
      expect(
        isSameHttpOrigin(
          'https://nas.example.test:0',
          'https://nas.example.test:0/items',
        ),
        isFalse,
      );
      expect(
        () => isSameHttpOrigin(
          'https://nas.example.test:999999999999999999999999999999',
          '/items',
        ),
        returnsNormally,
      );
    });
  });

  test('仅同源 URL 返回访问码请求头', () {
    expect(
      buildFeiniuAccessCodeHeadersForUrl(
        accessCode: 'code',
        baseUrl: 'https://nas.example.test',
        url: 'https://other.example.test/items',
      ),
      isEmpty,
    );
  });

  group('挑战页识别', () {
    test('同时含有两个标记的 HTML 是访问码挑战页', () {
      expect(
        isFeiniuAccessCodeChallengeHtml(
          '<input id="ACCESS-CODE-INPUT"><form action="/ACCESS_CODE_VERIFY">',
        ),
        isTrue,
      );
    });

    test('普通 JSON 不被误判为挑战页', () {
      expect(
        isFeiniuAccessCodeChallengeHtml(<String, String>{
          'access-code-input': '/access_code_verify',
        }),
        isFalse,
      );
    });
  });

  group('Dio 拦截器', () {
    test('每次请求动态读取访问码，且不会向第三方泄漏', () async {
      final captured = <RequestOptions>[];
      var code = 'first';
      final dio = _dioWith(captured);
      installFeiniuAccessCodeInterceptor(
        dio,
        baseUrl: 'https://nas.example.test',
        accessCodeProvider: () => code,
      );

      await dio.get<Object?>('https://nas.example.test/first');
      code = '中文';
      await dio.get<Object?>('https://nas.example.test/second');
      await dio.get<Object?>('https://third.example.test/items');

      expect(
        captured[0].headers['x-access-code'],
        base64Encode(utf8.encode('first')),
      );
      expect(
        captured[1].headers['x-access-code'],
        base64Encode(utf8.encode('中文')),
      );
      expect(captured[2].headers.containsKey('x-access-code'), isFalse);
      expect(captured[2].headers.containsKey('x-access-source'), isFalse);
    });

    test('第三方请求会剥离默认和请求级的大小写混合敏感头', () async {
      final captured = <RequestOptions>[];
      final dio = Dio(
        BaseOptions(
          headers: <String, Object?>{
            'X-Access-Code': '默认访问码',
            'x-ACCESS-source': '默认来源',
          },
        ),
      )..httpClientAdapter = _CapturingAdapter(captured);
      installFeiniuAccessCodeInterceptor(
        dio,
        baseUrl: 'https://nas.example.test',
        accessCodeProvider: () => 'current',
      );

      await dio.get<Object?>(
        'https://third.example.test/items',
        options: Options(
          headers: <String, Object?>{
            'x-Access-Code': '请求访问码',
            'X-ACCESS-SOURCE': '请求来源',
          },
        ),
      );

      expect(_hasAccessCodeHeader(captured.single.headers), isFalse);
      expect(_hasAccessSourceHeader(captured.single.headers), isFalse);
    });

    test('同源请求覆盖预置敏感头并注入当前访问码', () async {
      final captured = <RequestOptions>[];
      final dio = Dio(
        BaseOptions(
          headers: <String, Object?>{
            'X-Access-Code': '旧访问码',
            'X-ACCESS-SOURCE': '旧来源',
          },
        ),
      )..httpClientAdapter = _CapturingAdapter(captured);
      installFeiniuAccessCodeInterceptor(
        dio,
        baseUrl: 'https://nas.example.test',
        accessCodeProvider: () => 'current',
      );

      await dio.get<Object?>(
        'https://nas.example.test/items',
        options: Options(
          headers: <String, Object?>{
            'x-Access-Code': '请求旧访问码',
            'x-access-source': '请求旧来源',
          },
        ),
      );

      expect(
        captured.single.headers['x-access-code'],
        base64Encode(utf8.encode('current')),
      );
      expect(captured.single.headers['x-access-source'], 'app');
      expect(_accessCodeHeaderCount(captured.single.headers), 1);
      expect(_accessSourceHeaderCount(captured.single.headers), 1);
    });

    test('仅同源非空访问码请求关闭自动重定向', () async {
      final captured = <RequestOptions>[];
      var code = 'code';
      final dio = _dioWith(captured);
      installFeiniuAccessCodeInterceptor(
        dio,
        baseUrl: 'https://nas.example.test',
        accessCodeProvider: () => code,
      );

      await dio.get<Object?>('https://nas.example.test/items');
      code = '   ';
      await dio.get<Object?>('https://nas.example.test/empty');
      code = 'code';
      await dio.get<Object?>('https://third.example.test/items');

      expect(captured[0].followRedirects, isFalse);
      expect(captured[1].followRedirects, isTrue);
      expect(captured[2].followRedirects, isTrue);
      expect(_hasAccessCodeHeader(captured[2].headers), isFalse);
      expect(_hasAccessSourceHeader(captured[2].headers), isFalse);
    });

    test('200 挑战 HTML 映射为 required 哨兵', () async {
      final dio = _dioWithResponse(
        statusCode: 200,
        body: '<input id="access-code-input" action="/access_code_verify">',
        contentType: 'text/html; charset=utf-8',
      );
      installFeiniuAccessCodeInterceptor(
        dio,
        baseUrl: 'https://nas.example.test',
        accessCodeProvider: () => 'code',
      );

      await expectLater(
        dio.get<Object?>('https://nas.example.test/items'),
        throwsA(
          isA<DioException>().having(
            (error) => error.message,
            'message',
            feiniuAccessCodeRequiredSentinel,
          ),
        ),
      );
    });

    test('直接第三方 200 挑战 HTML 作为普通响应返回', () async {
      final dio = _dioWithResponse(
        statusCode: 200,
        body: '<input id="access-code-input" action="/access_code_verify">',
        contentType: 'text/html',
      );
      installFeiniuAccessCodeInterceptor(
        dio,
        baseUrl: 'https://nas.example.test',
        accessCodeProvider: () => 'code',
      );

      final response = await dio.get<String>('https://third.example.test/page');

      expect(response.data, contains('access-code-input'));
    });

    test('直接第三方相对重定向后的 200 挑战 HTML 作为普通响应返回', () async {
      final dio = _dioWithResponse(
        statusCode: 200,
        body: '<input id="access-code-input" action="/access_code_verify">',
        contentType: 'text/html',
        redirects: <RedirectRecord>[
          RedirectRecord(302, 'GET', Uri.parse('/login')),
        ],
      );
      installFeiniuAccessCodeInterceptor(
        dio,
        baseUrl: 'https://nas.example.test',
        accessCodeProvider: () => 'code',
      );

      final response = await dio.get<String>('https://third.example.test/page');

      expect(response.data, contains('access-code-input'));
    });

    test('NAS 跨源后再相对重定向的 200 挑战 HTML 作为普通响应返回', () async {
      final dio = _dioWithResponse(
        statusCode: 200,
        body: '<input id="access-code-input" action="/access_code_verify">',
        contentType: 'text/html',
        redirects: <RedirectRecord>[
          RedirectRecord(
            302,
            'GET',
            Uri.parse('https://third.example.test/page'),
          ),
          RedirectRecord(302, 'GET', Uri.parse('/login')),
        ],
      );
      installFeiniuAccessCodeInterceptor(
        dio,
        baseUrl: 'https://nas.example.test',
        accessCodeProvider: () => 'code',
      );

      final response = await dio.get<String>('https://nas.example.test/page');

      expect(response.data, contains('access-code-input'));
    });

    test('NAS 站内相对重定向后的 200 挑战 HTML 映射为 required 哨兵', () async {
      final dio = _dioWithResponse(
        statusCode: 200,
        body: '<input id="access-code-input" action="/access_code_verify">',
        contentType: 'text/html',
        redirects: <RedirectRecord>[
          RedirectRecord(302, 'GET', Uri.parse('/login')),
        ],
      );
      installFeiniuAccessCodeInterceptor(
        dio,
        baseUrl: 'https://nas.example.test',
        accessCodeProvider: () => 'code',
      );

      await expectLater(
        dio.get<String>('https://nas.example.test/page'),
        throwsA(
          isA<DioException>().having(
            (error) => error.message,
            'message',
            feiniuAccessCodeRequiredSentinel,
          ),
        ),
      );
    });

    test('最终 realUri 跨源的 200 挑战 HTML 作为普通响应返回', () async {
      final dio = _dioWithResponse(
        statusCode: 200,
        body: '<input id="access-code-input" action="/access_code_verify">',
        contentType: 'text/html',
        redirects: <RedirectRecord>[
          RedirectRecord(
            302,
            'GET',
            Uri.parse('https://third.example.test/page'),
          ),
        ],
      );
      installFeiniuAccessCodeInterceptor(
        dio,
        baseUrl: 'https://nas.example.test',
        accessCodeProvider: () => 'code',
      );

      final response = await dio.get<String>('https://nas.example.test/page');

      expect(response.realUri.host, 'third.example.test');
      expect(response.data, contains('access-code-input'));
    });

    for (final statusCode in <int>[401, 403, 429]) {
      test('$statusCode text/html 映射为 invalid 哨兵', () async {
        final dio = _dioWithResponse(
          statusCode: statusCode,
          body: '<html>拒绝</html>',
          contentType: 'TEXT/HTML; charset=UTF-8',
        );
        installFeiniuAccessCodeInterceptor(
          dio,
          baseUrl: 'https://nas.example.test',
          accessCodeProvider: () => 'code',
        );

        await expectLater(
          dio.get<Object?>('https://nas.example.test/items'),
          throwsA(
            isA<DioException>().having(
              (error) => error.message,
              'message',
              feiniuAccessCodeInvalidSentinel,
            ),
          ),
        );
      });
    }

    test('401 JSON 保持原始 Dio 错误', () async {
      final dio = _dioWithResponse(
        statusCode: 401,
        body: jsonEncode(<String, String>{'message': '密码错误'}),
        contentType: Headers.jsonContentType,
      );
      installFeiniuAccessCodeInterceptor(
        dio,
        baseUrl: 'https://nas.example.test',
        accessCodeProvider: () => 'code',
      );

      await expectLater(
        dio.get<Object?>('https://nas.example.test/items'),
        throwsA(
          isA<DioException>()
              .having(
                (error) => error.message,
                'message',
                isNot(
                  anyOf(
                    feiniuAccessCodeRequiredSentinel,
                    feiniuAccessCodeInvalidSentinel,
                  ),
                ),
              )
              .having((error) => error.response?.statusCode, 'statusCode', 401),
        ),
      );
    });

    for (final statusCode in <int>[401, 403, 429]) {
      test('直接第三方 $statusCode text/html 保持原始 Dio 错误', () async {
        final dio = _dioWithResponse(
          statusCode: statusCode,
          body: '<html>拒绝</html>',
          contentType: 'text/html',
        );
        installFeiniuAccessCodeInterceptor(
          dio,
          baseUrl: 'https://nas.example.test',
          accessCodeProvider: () => 'code',
        );

        await expectLater(
          dio.get<Object?>('https://third.example.test/page'),
          throwsA(
            isA<DioException>()
                .having(
                  (error) => error.message,
                  'message',
                  isNot(feiniuAccessCodeInvalidSentinel),
                )
                .having(
                  (error) => error.response?.realUri.host,
                  'realUri.host',
                  'third.example.test',
                ),
          ),
        );
      });
    }

    test('直接第三方相对重定向后的 403 text/html 保持原始 Dio 错误', () async {
      final dio = _dioWithResponse(
        statusCode: 403,
        body: '<html>拒绝</html>',
        contentType: 'text/html',
        redirects: <RedirectRecord>[
          RedirectRecord(302, 'GET', Uri.parse('/login')),
        ],
      );
      installFeiniuAccessCodeInterceptor(
        dio,
        baseUrl: 'https://nas.example.test',
        accessCodeProvider: () => 'code',
      );

      await expectLater(
        dio.get<Object?>('https://third.example.test/page'),
        throwsA(
          isA<DioException>().having(
            (error) => error.message,
            'message',
            isNot(feiniuAccessCodeInvalidSentinel),
          ),
        ),
      );
    });

    test('NAS 跨源后再相对重定向的 403 text/html 保持原始 Dio 错误', () async {
      final dio = _dioWithResponse(
        statusCode: 403,
        body: '<html>拒绝</html>',
        contentType: 'text/html',
        redirects: <RedirectRecord>[
          RedirectRecord(
            302,
            'GET',
            Uri.parse('https://third.example.test/page'),
          ),
          RedirectRecord(302, 'GET', Uri.parse('/login')),
        ],
      );
      installFeiniuAccessCodeInterceptor(
        dio,
        baseUrl: 'https://nas.example.test',
        accessCodeProvider: () => 'code',
      );

      await expectLater(
        dio.get<Object?>('https://nas.example.test/page'),
        throwsA(
          isA<DioException>().having(
            (error) => error.message,
            'message',
            isNot(feiniuAccessCodeInvalidSentinel),
          ),
        ),
      );
    });

    test('NAS 站内相对重定向后的 401 text/html 映射为 invalid 哨兵', () async {
      final dio = _dioWithResponse(
        statusCode: 401,
        body: '<html>拒绝</html>',
        contentType: 'text/html',
        redirects: <RedirectRecord>[
          RedirectRecord(302, 'GET', Uri.parse('/login')),
        ],
      );
      installFeiniuAccessCodeInterceptor(
        dio,
        baseUrl: 'https://nas.example.test',
        accessCodeProvider: () => 'code',
      );

      await expectLater(
        dio.get<Object?>('https://nas.example.test/page'),
        throwsA(
          isA<DioException>().having(
            (error) => error.message,
            'message',
            feiniuAccessCodeInvalidSentinel,
          ),
        ),
      );
    });

    test('最终 realUri 跨源的 403 text/html 保持原始 Dio 错误', () async {
      final dio = _dioWithResponse(
        statusCode: 403,
        body: '<html>拒绝</html>',
        contentType: 'text/html',
        redirects: <RedirectRecord>[
          RedirectRecord(
            302,
            'GET',
            Uri.parse('https://third.example.test/page'),
          ),
        ],
      );
      installFeiniuAccessCodeInterceptor(
        dio,
        baseUrl: 'https://nas.example.test',
        accessCodeProvider: () => 'code',
      );

      await expectLater(
        dio.get<Object?>('https://nas.example.test/page'),
        throwsA(
          isA<DioException>()
              .having(
                (error) => error.message,
                'message',
                isNot(feiniuAccessCodeInvalidSentinel),
              )
              .having(
                (error) => error.response?.realUri.host,
                'realUri.host',
                'third.example.test',
              ),
        ),
      );
    });
  });
}

Dio _dioWith(List<RequestOptions> captured) =>
    Dio()..httpClientAdapter = _CapturingAdapter(captured);

Dio _dioWithResponse({
  required int statusCode,
  required String body,
  required String contentType,
  List<RedirectRecord>? redirects,
}) => Dio()
  ..httpClientAdapter = _ResponseAdapter(
    statusCode: statusCode,
    body: body,
    contentType: contentType,
    redirects: redirects,
  );

class _CapturingAdapter extends _ResponseAdapter {
  _CapturingAdapter(this.captured)
    : super(
        statusCode: 200,
        body: jsonEncode(<String, Object?>{'items': <Object?>[]}),
        contentType: Headers.jsonContentType,
      );

  final List<RequestOptions> captured;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    captured.add(options);
    return super.fetch(options, requestStream, cancelFuture);
  }
}

class _ResponseAdapter implements HttpClientAdapter {
  _ResponseAdapter({
    required this.statusCode,
    required this.body,
    required this.contentType,
    this.redirects,
  });

  final int statusCode;
  final String body;
  final String contentType;
  final List<RedirectRecord>? redirects;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody(
    Stream<Uint8List>.value(Uint8List.fromList(utf8.encode(body))),
    statusCode,
    redirects: redirects,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[contentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

bool _hasAccessCodeHeader(Map<String, dynamic> headers) =>
    _accessCodeHeaderCount(headers) > 0;

bool _hasAccessSourceHeader(Map<String, dynamic> headers) =>
    _accessSourceHeaderCount(headers) > 0;

int _accessCodeHeaderCount(Map<String, dynamic> headers) =>
    headers.keys.where((name) => name.toLowerCase() == 'x-access-code').length;

int _accessSourceHeaderCount(Map<String, dynamic> headers) => headers.keys
    .where((name) => name.toLowerCase() == 'x-access-source')
    .length;
