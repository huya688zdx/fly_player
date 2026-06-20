import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/api/feiniu_api.dart';
import 'package:fly_player/providers/nas_provider.dart';
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
}
