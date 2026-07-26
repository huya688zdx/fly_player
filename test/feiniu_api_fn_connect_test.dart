import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
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
