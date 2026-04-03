import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/utils/app_exception.dart';
import 'package:fly_player/utils/login_error_resolver.dart';

void main() {
  group('LoginErrorResolver', () {
    test('maps invalid credentials to a unified message', () {
      final error = AppException.api(
        action: 'login',
        message: 'password incorrect',
      );

      expect(LoginErrorResolver.resolve(error), '用户名或密码错误');
    });

    test('maps backend code -15 to invalid credentials', () {
      final error = AppException.api(
        action: 'login',
        message: 'unexpected backend text',
        code: -15,
      );

      expect(LoginErrorResolver.resolve(error), '用户名或密码错误');
    });

    test('maps network failures to a unified message', () {
      expect(
        LoginErrorResolver.resolve(
          Exception('SocketException: Connection refused'),
        ),
        '无法连接到服务器，请检查地址、端口和网络',
      );
    });

    test('maps chinese handshake failures to https guidance', () {
      expect(
        LoginErrorResolver.resolve('基础连接已经关闭: 发送时发生错误。由于意外的数据包格式，握手失败。'),
        'HTTPS 连接失败，请检查证书配置或改用可访问地址',
      );
    });

    test('maps chinese connection refused failures to network guidance', () {
      expect(
        LoginErrorResolver.resolve('无法连接到远程服务器。由于目标计算机积极拒绝，无法连接。'),
        '无法连接到服务器，请检查地址、端口和网络',
      );
    });

    test('maps fn connect reachability failures to a unified message', () {
      expect(
        LoginErrorResolver.resolve(
          'FN Connect resolved only direct API addresses, '
          'but none of them were reachable from the current network.',
        ),
        'FN Connect 可用地址当前都无法连接，请检查网络环境或改用可直连地址',
      );
    });

    test('keeps readable chinese backend messages', () {
      expect(LoginErrorResolver.resolve('服务器正在维护，请稍后重试'), '服务器正在维护，请稍后重试');
    });

    test('drops mojibake messages back to a clean generic fallback', () {
      expect(LoginErrorResolver.resolve('鎿嶄綔澶辫触锛岃閲嶈瘯'), '登录失败，请重试');
    });
  });
}
