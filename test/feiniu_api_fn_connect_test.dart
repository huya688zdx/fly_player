import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/api/feiniu_access_code_transport.dart';
import 'package:fly_player/api/feiniu_api.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/utils/app_exception.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FeiniuApi FN Connect relay helpers', () {
    test('fnos.net relay host should use relay mode cookie', () {
      expect(
        FeiniuApi.shouldUseRelayModeCookieForBaseUrl(
          'https://geqian688.fnos.net',
        ),
        isTrue,
      );
      expect(
        FeiniuApi.shouldUseRelayModeCookieForBaseUrl('https://fnos.net'),
        isTrue,
      );
    });

    test('direct hosts should not use relay mode cookie', () {
      expect(
        FeiniuApi.shouldUseRelayModeCookieForBaseUrl(
          'https://192.168.1.2:5667',
        ),
        isFalse,
      );
      expect(
        FeiniuApi.shouldUseRelayModeCookieForBaseUrl('https://example.com'),
        isFalse,
      );
    });

    test(
      'playback headers include relay cookie for fnos.net media range',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final provider = NasProvider();
        addTearDown(provider.dispose);
        await provider.updateSettings(
          baseUrl: 'https://geqian688.fnos.net',
          userName: 'user',
          password: 'password',
          token: 'token',
        );
        final api = FeiniuApi(provider);

        final headers = api.buildPlaybackHeadersForUrl(
          'https://geqian688.fnos.net/v/api/v1/media/range/video-guid',
          includeInitialRangeHeader: false,
        );

        expect(headers, containsPair('Cookie', 'mode=relay'));
      },
    );

    test('playback headers merge relay cookie with existing cookies', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final provider = NasProvider();
      addTearDown(provider.dispose);
      await provider.updateSettings(
        baseUrl: 'https://geqian688.fnos.net',
        userName: 'user',
        password: 'password',
        token: 'token',
      );
      final api = FeiniuApi(provider);

      final headers = api.buildPlaybackHeadersForUrl(
        'https://geqian688.fnos.net/v/api/v1/media/range/video-guid',
        includeInitialRangeHeader: false,
        extraHeaders: const <String, String>{'Cookie': 'session=abc'},
      );

      expect(headers['Cookie'], contains('session=abc'));
      expect(headers['Cookie'], contains('mode=relay'));
    });

    test(
      'playback headers do not include relay cookie for direct NAS',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final provider = NasProvider();
        addTearDown(provider.dispose);
        await provider.updateSettings(
          baseUrl: 'https://192.168.6.120:5667',
          userName: 'user',
          password: 'password',
          token: 'token',
        );
        final api = FeiniuApi(provider);

        final headers = api.buildPlaybackHeadersForUrl(
          'https://192.168.6.120:5667/v/api/v1/media/range/video-guid',
          includeInitialRangeHeader: false,
        );

        expect(headers, isNot(contains('Cookie')));
      },
    );

    test('同源播放和签名请求头包含访问码，第三方请求不包含', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final provider = NasProvider();
      addTearDown(provider.dispose);
      await provider.updateSettings(
        baseUrl: 'https://nas.example.test:8443',
        userName: 'user',
        password: 'password',
        accessCode: '访问码',
        token: 'token',
      );
      final api = FeiniuApi(provider);

      final signedHeaders = api.buildSignedHeadersForUrl(
        'https://nas.example.test:8443/v/api/v1/items',
      );
      final playbackHeaders = api.buildPlaybackHeadersForUrl(
        '/v/api/v1/media/range/video-guid',
      );
      final thirdPartyHeaders = api.buildSignedHeadersForUrl(
        'https://cdn.example.test/resource',
      );

      for (final headers in <Map<String, String>>[
        signedHeaders,
        playbackHeaders,
      ]) {
        expect(headers['x-access-code'], base64Encode(utf8.encode('访问码')));
        expect(headers['x-access-source'], 'app');
      }
      expect(thirdPartyHeaders, isNot(contains('x-access-code')));
      expect(thirdPartyHeaders, isNot(contains('x-access-source')));
    });

    test('同 host 不同 scheme 或端口不携带 NAS 鉴权与访问码', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final provider = NasProvider();
      addTearDown(provider.dispose);
      await provider.updateSettings(
        baseUrl: 'https://nas.example.test:8443',
        userName: 'user',
        password: 'password',
        accessCode: 'code',
        token: 'token',
      );
      final api = FeiniuApi(provider);

      for (final url in <String>[
        'http://nas.example.test:8443/v/api/v1/items',
        'https://nas.example.test:9443/v/api/v1/items',
      ]) {
        final headers = api.buildSignedHeadersForUrl(url);
        expect(headers, isNot(contains('Authorization')));
        expect(headers, isNot(contains('Trim-MC-token')));
        expect(headers, isNot(contains('Authx')));
        expect(headers, isNot(contains('x-access-code')));
        expect(headers, isNot(contains('x-access-source')));
      }
    });

    test('官方发现请求无访问码，候选 NAS 登录请求携带访问码', () async {
      final requests = <RequestOptions>[];
      final adapter = _FakeDioAdapter((options) {
        requests.add(options);
        if (options.uri.host == 'fnos.net') {
          return _jsonResponse(<String, Object?>{
            'code': 0,
            'data': <String, Object?>{
              'publicIpv4': <String>['203.0.113.10'],
              'port': <String, Object?>{'httpPort': 5666, 'httpsPort': 5667},
            },
          });
        }
        return _jsonResponse(<String, Object?>{
          'code': 0,
          'data': <String, Object?>{'token': 'token'},
        });
      });

      final result = await FeiniuApi.loginWithBaseUrl(
        baseUrl: 'fnabc1',
        userName: 'user',
        password: 'password',
        accessCode: 'code',
        httpClientAdapter: adapter,
      );

      expect(result.usedFnConnect, isTrue);
      expect(requests, hasLength(2));
      expect(requests.first.uri, Uri.parse('https://fnos.net/api/v1/fn/con'));
      expect(requests.first.headers, isNot(contains('x-access-code')));
      expect(requests.first.headers, isNot(contains('x-access-source')));
      expect(
        requests.last.headers['x-access-code'],
        base64Encode(utf8.encode('code')),
      );
      expect(requests.last.headers['x-access-source'], 'app');
    });

    test('全部候选失败时保留 200 访问码挑战的 required 哨兵', () async {
      final adapter = _fnConnectLoginAdapter(<String, ResponseBody Function()>{
        '203.0.113.10': () => _htmlResponse(
          '<input id="access-code-input" action="/access_code_verify">',
          statusCode: 200,
        ),
      });

      await expectLater(
        _loginWithFnConnect(adapter),
        throwsA(
          isA<FnConnectLoginException>().having(
            (error) => error.error.message,
            'message',
            feiniuAccessCodeRequiredSentinel,
          ),
        ),
      );
    });

    test('全部候选失败时保留 429 HTML 的 invalid 哨兵', () async {
      final adapter = _fnConnectLoginAdapter(<String, ResponseBody Function()>{
        '203.0.113.10': () =>
            _htmlResponse('<html>denied</html>', statusCode: 429),
      });

      await expectLater(
        _loginWithFnConnect(adapter),
        throwsA(
          isA<FnConnectLoginException>().having(
            (error) => error.error.message,
            'message',
            feiniuAccessCodeInvalidSentinel,
          ),
        ),
      );
    });

    test('普通 401 之后的访问码 invalid 错误优先返回', () async {
      final adapter = _fnConnectLoginAdapter(<String, ResponseBody Function()>{
        '203.0.113.10': () => _jsonResponse(<String, Object?>{
          'message': 'password incorrect',
        }, statusCode: 401),
        '203.0.113.11': () =>
            _htmlResponse('<html>denied</html>', statusCode: 401),
      });

      await expectLater(
        _loginWithFnConnect(adapter),
        throwsA(
          isA<FnConnectLoginException>().having(
            (error) => error.error.message,
            'message',
            feiniuAccessCodeInvalidSentinel,
          ),
        ),
      );
    });

    test('访问码错误之后的候选登录成功仍返回成功结果', () async {
      final adapter = _fnConnectLoginAdapter(<String, ResponseBody Function()>{
        '203.0.113.10': () =>
            _htmlResponse('<html>denied</html>', statusCode: 429),
        '203.0.113.11': () => _jsonResponse(<String, Object?>{
          'code': 0,
          'data': <String, Object?>{'token': 'later-token'},
        }),
      });

      final result = await _loginWithFnConnect(adapter);

      expect(result.token, 'later-token');
      expect(result.resolvedBaseUrl, 'https://203.0.113.11:5667');
    });

    test('OAuth 配置与换码的 NAS 请求携带访问码', () async {
      final requests = <RequestOptions>[];
      final adapter = _FakeDioAdapter((options) {
        requests.add(options);
        if (options.path.endsWith('/sys/config')) {
          return _jsonResponse(<String, Object?>{
            'code': 0,
            'data': <String, Object?>{
              'nas_oauth': <String, Object?>{
                'app_id': 'app-id',
                'url': 'https://nas.example.test:5667',
              },
            },
          });
        }
        return _jsonResponse(<String, Object?>{
          'code': 0,
          'data': <String, Object?>{'token': 'token'},
        });
      });

      await FeiniuApi.fetchFnConnectOauthConfig(
        baseUrl: 'https://relay.fnos.net',
        cookie: 'session=abc',
        accessCode: 'code',
        httpClientAdapter: adapter,
      );
      await FeiniuApi.loginWithFnConnectOauthCode(
        baseUrl: 'https://nas.example.test:5667',
        code: 'oauth-code',
        accessCode: 'code',
        httpClientAdapter: adapter,
      );

      expect(requests, hasLength(2));
      for (final request in requests) {
        expect(
          request.headers['x-access-code'],
          base64Encode(utf8.encode('code')),
        );
        expect(request.headers['x-access-source'], 'app');
      }
    });
  });

  group('FeiniuApi 访问码传输', () {
    test('同一实例的普通 API 请求动态读取 provider 中的访问码', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final requests = <RequestOptions>[];
      final adapter = _FakeDioAdapter((options) {
        requests.add(options);
        return _jsonResponse(<String, Object?>{'code': 0});
      });
      final provider = NasProvider();
      addTearDown(provider.dispose);
      await provider.updateSettings(
        baseUrl: 'https://nas.example.test:5667',
        userName: 'user',
        password: 'password',
        accessCode: 'first',
        token: 'token',
      );
      final api = FeiniuApi(provider, httpClientAdapter: adapter);

      await _recordPlayback(api);
      await provider.updateSettings(
        baseUrl: 'https://nas.example.test:5667',
        userName: 'user',
        password: 'password',
        accessCode: 'second',
        token: 'token',
      );
      await _recordPlayback(api);

      expect(requests, hasLength(2));
      expect(
        requests[0].headers['x-access-code'],
        base64Encode(utf8.encode('first')),
      );
      expect(requests[0].headers['x-access-source'], 'app');
      expect(
        requests[1].headers['x-access-code'],
        base64Encode(utf8.encode('second')),
      );
      expect(requests[1].headers['x-access-source'], 'app');
    });

    test('直接登录请求携带访问码', () async {
      late RequestOptions request;
      final adapter = _FakeDioAdapter((options) {
        request = options;
        return _jsonResponse(<String, Object?>{
          'code': 0,
          'data': <String, Object?>{'token': 'token'},
        });
      });

      await FeiniuApi.loginWithBaseUrl(
        baseUrl: 'https://nas.example.test:5667',
        userName: 'user',
        password: 'password',
        accessCode: 'code',
        httpClientAdapter: adapter,
      );

      expect(
        request.headers['x-access-code'],
        base64Encode(utf8.encode('code')),
      );
      expect(request.headers['x-access-source'], 'app');
    });

    test('200 挑战 HTML 登录错误保留 required 哨兵', () async {
      final adapter = _FakeDioAdapter(
        (_) => ResponseBody.fromString(
          '<input id="access-code-input" action="/access_code_verify">',
          200,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['text/html'],
          },
        ),
      );

      await expectLater(
        FeiniuApi.loginWithBaseUrl(
          baseUrl: 'https://nas.example.test:5667',
          userName: 'user',
          password: 'password',
          httpClientAdapter: adapter,
        ),
        throwsA(
          isA<AppException>().having(
            (error) => error.message,
            'message',
            feiniuAccessCodeRequiredSentinel,
          ),
        ),
      );
    });

    test('401 HTML 登录错误保留 invalid 哨兵', () async {
      final adapter = _FakeDioAdapter(
        (_) => ResponseBody.fromString(
          '<html>denied</html>',
          401,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['text/html'],
          },
        ),
      );

      await expectLater(
        FeiniuApi.loginWithBaseUrl(
          baseUrl: 'https://nas.example.test:5667',
          userName: 'user',
          password: 'password',
          accessCode: 'code',
          httpClientAdapter: adapter,
        ),
        throwsA(
          isA<AppException>().having(
            (error) => error.message,
            'message',
            feiniuAccessCodeInvalidSentinel,
          ),
        ),
      );
    });

    test('401 JSON 登录错误保持账号凭据语义', () async {
      final adapter = _FakeDioAdapter(
        (_) => _jsonResponse(<String, Object?>{
          'code': -2,
          'message': 'password incorrect',
        }, statusCode: 401),
      );

      await expectLater(
        FeiniuApi.loginWithBaseUrl(
          baseUrl: 'https://nas.example.test:5667',
          userName: 'user',
          password: 'password',
          accessCode: 'code',
          httpClientAdapter: adapter,
        ),
        throwsA(
          isA<AppException>()
              .having((error) => error.message, 'message', 'password incorrect')
              .having((error) => error.httpStatus, 'httpStatus', 401),
        ),
      );
    });
  });

  group('FeiniuApi playback record', () {
    test('ordinary 401 does not clear the active session', () async {
      const initialBaseUrl = 'http://initial.invalid:5667';
      SharedPreferences.setMockInitialValues(<String, Object>{
        'base_url': initialBaseUrl,
      });
      final adapter = _FakeDioAdapter((options) {
        return ResponseBody.fromString(
          jsonEncode(<String, Object?>{'code': 401, 'message': 'unauthorized'}),
          401,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['application/json'],
          },
        );
      });

      final provider = NasProvider();
      addTearDown(provider.dispose);
      await _waitForSettingsLoad(provider, initialBaseUrl);
      await provider.updateSettings(
        baseUrl: 'http://127.0.0.1:5667',
        userName: 'user',
        password: 'password',
        token: 'active-token',
      );
      final api = FeiniuApi(provider, httpClientAdapter: adapter);

      await expectLater(
        api.recordPlayback(
          itemGuid: 'item-1',
          mediaGuid: 'media-1',
          videoGuid: 'video-1',
          ts: 10,
          duration: 100,
        ),
        throwsA(
          isA<AppException>()
              .having(
                (error) => error.kind,
                'kind',
                AppExceptionKind.unauthorized,
              )
              .having((error) => error.httpStatus, 'httpStatus', 401),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(provider.token, 'active-token');
      expect(provider.isConfigured, isTrue);
    });

    test('throws when backend payload reports failure', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      late RequestOptions captured;
      final adapter = _FakeDioAdapter((options) {
        captured = options;
        return ResponseBody.fromString(
          jsonEncode(<String, Object?>{
            'code': 500,
            'message': 'record failed',
          }),
          200,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['application/json'],
          },
        );
      });

      final provider = NasProvider();
      addTearDown(provider.dispose);
      await provider.updateSettings(
        baseUrl: 'http://127.0.0.1:5667',
        userName: 'user',
        password: 'password',
        token: 'token',
      );
      final api = FeiniuApi(provider, httpClientAdapter: adapter);

      await expectLater(
        api.recordPlayback(
          itemGuid: 'item-1',
          mediaGuid: 'media-1',
          videoGuid: 'video-1',
          ts: 10,
          duration: 100,
        ),
        throwsA(
          isA<AppException>()
              .having((error) => error.action, 'action', 'playback record')
              .having((error) => error.code, 'code', 500)
              .having((error) => error.message, 'message', 'record failed'),
        ),
      );
      expect(captured.method, 'POST');
      expect(captured.path, '/v/api/v1/play/record');
    });
  });
}

class _FakeDioAdapter implements HttpClientAdapter {
  _FakeDioAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;

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

ResponseBody _htmlResponse(String body, {required int statusCode}) {
  return ResponseBody.fromString(
    body,
    statusCode,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>['text/html'],
    },
  );
}

HttpClientAdapter _fnConnectLoginAdapter(
  Map<String, ResponseBody Function()> candidateResponses,
) {
  return _FakeDioAdapter((options) {
    if (options.uri.host == 'fnos.net') {
      return _jsonResponse(<String, Object?>{
        'code': 0,
        'data': <String, Object?>{
          'publicIpv4': candidateResponses.keys.toList(growable: false),
          'port': <String, Object?>{'httpPort': 5666, 'httpsPort': 5667},
        },
      });
    }
    return candidateResponses[options.uri.host]!();
  });
}

Future<LoginWithBaseUrlResult> _loginWithFnConnect(HttpClientAdapter adapter) {
  return FeiniuApi.loginWithBaseUrl(
    baseUrl: 'fnabc1',
    userName: 'user',
    password: 'password',
    accessCode: 'code',
    httpClientAdapter: adapter,
  );
}

Future<void> _recordPlayback(FeiniuApi api) {
  return api.recordPlayback(
    itemGuid: 'item-1',
    mediaGuid: 'media-1',
    videoGuid: 'video-1',
    ts: 10,
    duration: 100,
  );
}

Future<void> _waitForSettingsLoad(
  NasProvider provider,
  String expectedBaseUrl,
) async {
  if (provider.isReady && provider.sourceBaseUrl == expectedBaseUrl) return;

  final completer = Completer<void>();
  void listener() {
    if (!completer.isCompleted &&
        provider.isReady &&
        provider.sourceBaseUrl == expectedBaseUrl) {
      completer.complete();
    }
  }

  provider.addListener(listener);
  listener();
  try {
    await completer.future;
  } finally {
    provider.removeListener(listener);
  }
}
