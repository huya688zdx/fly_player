import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/utils/private_network_http_overrides.dart';

void main() {
  test('只对私网、回环、链路本地和已注册 NAS host 跳过证书校验', () {
    bool allowed(String host) =>
        PrivateNetworkHttpOverrides.allowsBadCertificateForHost(host);

    expect(allowed('192.168.1.9'), isTrue);
    expect(allowed('10.0.0.8'), isTrue);
    expect(allowed('172.16.0.2'), isTrue);
    expect(allowed('172.31.255.254'), isTrue);
    expect(allowed('127.0.0.1'), isTrue);
    expect(allowed('localhost'), isTrue);
    expect(allowed('169.254.10.20'), isTrue);
    expect(allowed('::1'), isTrue);
    expect(allowed('fc00::1'), isTrue);
    expect(allowed('fe80::1'), isTrue);

    expect(allowed('8.8.8.8'), isFalse);
    expect(allowed('1.1.1.1'), isFalse);
    expect(allowed('172.32.0.1'), isFalse);
    expect(allowed('example.com'), isFalse);

    PrivateNetworkHttpOverrides.registerNasHost('Nas.Example.Test');
    expect(allowed('nas.example.test'), isTrue);
  });
}
