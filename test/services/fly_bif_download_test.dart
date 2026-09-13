import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/services/fly_data/fly_data_api.dart';

class _NetworkBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _NetworkBinding();
  test(
    'BIF downloader uses only Fly bearer, rejects redirects and oversized streams',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final seen = <HttpRequest>[];
      server.listen((request) async {
        seen.add(request);
        final mode = request.uri.queryParameters['mode'];
        if (mode == 'redirect') {
          request.response.statusCode = 302;
          request.response.headers.set('Location', '/leaked');
        } else {
          request.response.add(List.filled(mode == 'oversized' ? 85 : 84, 1));
        }
        await request.response.close();
      });
      final api = FlyDataApi(
        'http://127.0.0.1:${server.port}',
        token: 'fly-only',
      );
      const path =
          '/api/v1/bif/assets/e0f07686-66e0-4331-abcd-675476aac219/content';
      try {
        expect(await api.bifBytes(path, expectedBytes: 84), hasLength(84));
        expect(seen.single.headers.value('authorization'), 'Bearer fly-only');
        expect(seen.single.headers.value('cookie'), isNull);
        await expectLater(
          api.bifBytes('$path?mode=redirect', expectedBytes: 84),
          throwsStateError,
        );
        await expectLater(
          api.bifBytes('$path?mode=oversized', expectedBytes: 84),
          throwsStateError,
        );
        await expectLater(
          api.bifBytes('https://evil.invalid$path', expectedBytes: 84),
          throwsStateError,
        );
        expect(seen, hasLength(3));
      } finally {
        api.close();
        await server.close(force: true);
      }
    },
  );
  test('BIF resolver caps streamed POST JSON before decoding', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"padding":"${'x' * 500}"}');
      await request.response.close();
    });
    final api = FlyDataApi(
      'http://127.0.0.1:${server.port}',
      maxResponseBytes: 100,
    );
    try {
      await expectLater(api.post('/bif/resolve', {}), throwsStateError);
    } finally {
      api.close();
      await server.close(force: true);
    }
  });
}
