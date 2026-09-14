import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/api/feiniu_api.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/services/native_reentry_support.dart';
import 'package:fly_player/services/playback_progress_offline_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final scenario in [
    'account',
    'owner',
    'unchanged',
    'default',
    'alreadyStale',
    'capturedAccount',
  ]) {
    test('release guard at Dio request queue: $scenario', () async {
      SharedPreferences.setMockInitialValues({
        'playback_client_id': 'synthetic-client',
      });
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final nas = _Nas('http://127.0.0.1:${server.port}');
        final requests = <Map>[];
        final requestHeaders = <HttpHeaders>[];
        var owner = 1;
        var intercepted = false;
        server.listen((request) async {
          requestHeaders.add(request.headers);
          requests.add(
            jsonDecode(await utf8.decoder.bind(request).join()) as Map,
          );
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'code': 0,
              'data': {'result': 'succ'},
            }),
          );
          await request.response.close();
        });
        try {
          if (scenario == 'alreadyStale') {
            await PlaybackProgressOfflineQueue.enqueue({
              'itemGuid': 'synthetic-item',
              'mediaGuid': 'synthetic-media',
              'ts': 10,
              'duration': 100,
            });
            owner = 2;
          }
          // The existing access-code interceptor runs after Dio.post is queued
          // and before the API's auth interceptor. Invalidate via a microtask at
          // that real boundary, without adding a production test hook.
          nas.onAccessCode = () {
            intercepted = true;
            scheduleMicrotask(() {
              if (scenario == 'account' || scenario == 'capturedAccount') {
                nas.sessionUser = 'account-B';
              }
              if (scenario == 'owner') owner = 2;
            });
          };
          if (scenario == 'capturedAccount') {
            final release = FeiniuApi(nas).captureServerSessionRelease();
            await release('synthetic-link');
          } else {
            await NativeReentrySupport.releaseServerSession(
              nas,
              'synthetic-link',
              isCurrent: scenario == 'default'
                  ? null
                  : () => nas.userName == 'account-A' && owner == 1,
            );
          }
          expect(intercepted, scenario != 'alreadyStale');
          if (scenario == 'unchanged' ||
              scenario == 'default' ||
              scenario == 'capturedAccount') {
            expect(requests, hasLength(1));
            expect(requests.single['req'], 'media.quit');
            expect(requests.single['playLink'], 'synthetic-link');
            if (scenario == 'capturedAccount') {
              expect(nas.sessionUser, 'account-B');
              expect(
                requestHeaders.single.value('authorization'),
                'token-account-A',
              );
              expect(
                requestHeaders.single.value('x-access-code'),
                base64Encode(utf8.encode('code-account-A')),
              );
            }
          } else {
            expect(requests, isEmpty);
          }
        } finally {
          nas.dispose();
          await server.close(force: true);
        }
      }, _DirectHttpOverrides());
    });
  }
}

class _Nas extends NasProvider {
  _Nas(this.server);
  final String server;
  String sessionUser = 'account-A';
  void Function()? onAccessCode;
  @override
  String get baseUrl => server;
  @override
  String get token => 'token-$sessionUser';
  @override
  bool get isConfigured => true;
  @override
  String get userName => sessionUser;
  @override
  String get accessCode {
    onAccessCode?.call();
    return 'code-$sessionUser';
  }
}

class _DirectHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}
