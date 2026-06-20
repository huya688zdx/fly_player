import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/api/feiniu_api.dart';
import 'package:fly_player/screens/connection_screen.dart';

void main() {
  group('effectivePersistedBaseUrlForLogin', () {
    test('FN Connect 登录成功后运行时地址保存 resolvedBaseUrl', () {
      const result = LoginWithBaseUrlResult(
        token: 'token',
        resolvedBaseUrl: 'https://geqian688.fnos.net',
        usedFnConnect: true,
      );

      expect(
        effectivePersistedBaseUrlForLogin(
          sourceBaseUrl: 'geqian688',
          loginResult: result,
        ),
        'https://geqian688.fnos.net',
      );
    });

    test('普通直连登录继续保存用户输入地址', () {
      const result = LoginWithBaseUrlResult(
        token: 'token',
        resolvedBaseUrl: 'https://nas.example.com:5667',
      );

      expect(
        effectivePersistedBaseUrlForLogin(
          sourceBaseUrl: 'nas.example.com:5667',
          loginResult: result,
        ),
        'nas.example.com:5667',
      );
    });
  });
}
