import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/services/fly_data/fly_data_api.dart';
import 'package:fly_player/services/fly_data/fly_media_identity.dart';

class _NetworkBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

class _PermissiveMediaOverride extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..badCertificateCallback = (_, _, _) => true;
}

void main() {
  _NetworkBinding();
  test('飞翔服务的 Tailscale 地址直连，公网地址保留环境代理', () {
    expect(flyServiceProxy(Uri.parse('http://100.125.130.96:8787')), 'DIRECT');
    final public = Uri.parse('https://fly.example.com');
    expect(
      flyServiceProxy(public),
      HttpClient.findProxyFromEnvironment(public),
    );
  });
  test(
    'Fly authentication and public media probes reject real self-signed TLS despite global media override',
    () async {
      // Synthetic test certificate/private key only; no production secret.
      final context = SecurityContext()
        ..useCertificateChain('test/fixtures/fly_tls/synthetic-cert.pem')
        ..usePrivateKey('test/fixtures/fly_tls/synthetic-test-only-key.pem');
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      var received = 0;
      server.listen(
        (request) async {
          received++;
          await request.drain<void>();
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({'service_instance_id': 'forged', 'Id': 'forged'}),
          );
          await request.response.close();
        },
        onError: (Object _) {
          /* TLS rejection can surface at the listener. */
        },
      );
      final previous = HttpOverrides.current;
      HttpOverrides.global = _PermissiveMediaOverride();
      final url = 'https://127.0.0.1:${server.port}';
      final control = HttpClient()..findProxy = (_) => 'DIRECT';
      final api = FlyDataApi(url, token: 'must-not-arrive');
      try {
        final response = await (await control.getUrl(Uri.parse(url))).close();
        await response.drain<void>();
        expect(
          received,
          1,
          reason:
              'control proves the global override accepts this exact TLS endpoint',
        );
        await expectLater(api.get('/system/identity'), throwsStateError);
        await expectLater(
          api.bifBytes(
            '/api/v1/bif/assets/e0f07686-66e0-4331-abcd-675476aac219/content',
            expectedBytes: 84,
          ),
          throwsStateError,
        );
        await expectLater(
          api.post('/auth/login', {
            'username': 'alice',
            'password': 'must-not-arrive',
          }),
          throwsStateError,
        );
        await expectLater(
          verifyFlyMediaAddress(
            address: url,
            kind: 'emby',
            expectedId: 'forged',
          ),
          throwsStateError,
        );
        expect(
          received,
          1,
          reason:
              'No Fly bearer, password, or media probe HTTP request reached the untrusted TLS service',
        );
      } finally {
        api.close();
        control.close(force: true);
        HttpOverrides.global = previous;
        await server.close(force: true);
      }
    },
  );
}
