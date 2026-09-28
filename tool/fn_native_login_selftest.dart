/// fn 原生登录协议核心的纯 Dart 自测（不依赖 flutter_test，避免 sqlite3 原生
/// 资产构建在受限网络下失败）。运行：
///   dart run tool/fn_native_login_selftest.dart
library;

// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:typed_data';

import 'package:fly_player/services/fn_native_system_login.dart';
import 'package:pointycastle/api.dart'
    show PrivateKeyParameter, PublicKeyParameter;
import 'package:pointycastle/asymmetric/api.dart'
    show RSAPrivateKey, RSAPublicKey;
import 'package:pointycastle/asymmetric/oaep.dart';
import 'package:pointycastle/asymmetric/rsa.dart';
import 'package:pointycastle/digests/sha1.dart';

const String _testPublicPem = '''-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAuRu/x1/TNEQyszXF1kJ5
HzFAEmb0oTdcE++sGYye8FtYWeaTzh24WWxJvd/d7ZcjU1QCmi9qyfh+MJ/pXogs
BD4WWX9oxCx1miWJMSN0GkiBwcO3Eits+g9/ZM0CYiqrX83dL0WooicvUh9QRpP2
7cE5P8LZDFR4kp3YBZ8aSg7Hybg5AwsBbD2u/fcnDfwissqxqq3xxsi6MQjgjPiC
eEB79dZhI7gv3c8rYuUPuAd0hC5Vf4+91HGJ7uyos1qek4CAxno9GAnT8UkLmIjb
AChxLVvNJzA6otWXvRDTCK6nxYaR6H12qFJiODxqjBN6yej4NS+6FW/sDimVqPa2
FQIDAQAB
-----END PUBLIC KEY-----''';

const String _testPrivatePem = '''-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC5G7/HX9M0RDKz
NcXWQnkfMUASZvShN1wT76wZjJ7wW1hZ5pPOHbhZbEm9393tlyNTVAKaL2rJ+H4w
n+leiCwEPhZZf2jELHWaJYkxI3QaSIHBw7cSK2z6D39kzQJiKqtfzd0vRaiiJy9S
H1BGk/btwTk/wtkMVHiSndgFnxpKDsfJuDkDCwFsPa799ycN/CKyyrGqrfHGyLox
COCM+IJ4QHv11mEjuC/dzyti5Q+4B3SELlV/j73UcYnu7KizWp6TgIDGej0YCdPx
SQuYiNsAKHEtW80nMDqi1Ze9ENMIrqfFhpHofXaoUmI4PGqME3rJ6Pg1L7oVb+wO
KZWo9rYVAgMBAAECggEAKCaZ9k21ctqREbip8SPJgGfPIT62NKrcnNFph8At8G4r
z5I5QKXHKRRZOWdvzJtyFN690sJSvDzbaEIjXTcVrxTlhaOibpzDJHycUa2CPzo3
dPc2BCmpsWK/q/Zg3Diro/P0FE8ceRGdTMeQgsKQ9rio6Yjiye8fmRPGOc/tJJ9J
XsoA/hZCefwiilwHD3iHs+0u7jY4E+er+IznU0esNf1fCa+t3uBkhqtou8DSaiMB
vTi7XoIqcq/fVDA9IlsQfL4hCgBpHEElYhvIU5TmMePZRte2AOAFesK1Hy0OErbm
e9sa6D8UyGo7+89AcQHzUaj5Iud1AVWuwBSdQa6VWQKBgQD3/zJrdER1bZfcGBcg
aBK/tY2mBThS+90bNO8lQJQt4LVBwxYd9g/CE60FFsUpLYjINIXFd1ijUkVndo1z
3Lege27zm1bFuyT9eHiUJNKl1Ps9nTtqEiSlA65e96khCJKM2VNjdYvsknr4hqsb
kdIBxgAQGgzzECnoxptTxkWOTQKBgQC/FQFEM+cqCSmztzxKiEtlh3w7ZzNC9FPD
ied/jQHz74dtTmd4B1ymQ59DX8szts1tjQBlATIX54QMiMtzn99tsr1i+LJcG6gk
G5/pVnho8FdH0clzwubrzWfQAugSPmceDA0rSDjnQjFAcZCC+AianP46cKh422ZK
x2Fa8/X66QKBgC3vU/x5RbDmgsleoPH8tPRTgZAtyVf9lN/UNzOUOZ4h0BEFPJSC
HjsZf+PAavaMm5hRujFwQLfHpllaqSq7yDtugYeXz0PCvUBBzzvJckcLIxovhHDK
OYVjICow/1/CAbsbCgoTHL7OBv7/mrP5l4eCkEJrQNjItqqKFv02bW3FAoGABVIv
a9fKKyiAKcoDesva1aP1OK5CBi5JmttfP/UMRd+4tLmHNhd2ZAbkC3tCbFk91Twk
86sZ2wKOcc7pY3njPenJTlVAmkIG56KBTH0k8z8mHxDffELELXLV3jwGfGOSeYq6
XycutnnoZzQCYzNHAg83ISd7+YmaiqCMvHyor+kCgYEA6L8OLf2OhibmO72whmNO
RLJYz8YDHOBX+KHZnjwuebZhlljbxiuetdzaOnaI5BFk5w3pWaRQQLpgg6AzlVbY
+1f+yNDPcMQZsrUdIpOI20b6V3GMDnSn73oNu2aWPKTpiZCB7o6Zr0CO0tWbUbC2
nf/FG13WeTHUvj0LGOt2Ve4=
-----END PRIVATE KEY-----''';

int _failures = 0;

void _check(String name, bool condition) {
  if (condition) {
    print('PASS  $name');
  } else {
    _failures++;
    print('FAIL  $name');
  }
}

void main() {
  // 1. SPKI 解析。
  final publicKey = parseSpkiPem(_testPublicPem);
  final modulusHex = publicKey.modulus!.toRadixString(16).toUpperCase();
  _check('parseSpkiPem 模数前缀', modulusHex.startsWith('B91BBFC75FD3344432B335C5D642791F3'));
  _check('parseSpkiPem 模数长度 512 hex', modulusHex.length == 512);
  _check('parseSpkiPem 指数 65537', publicKey.exponent == BigInt.from(65537));

  var threw = false;
  try {
    parseSpkiPem('not a pem');
  } on FormatException {
    threw = true;
  }
  _check('parseSpkiPem 拒绝非 PEM', threw);

  // 2. AES-CBC/PKCS7 信封往返。
  final key =
      Uint8List.fromList(List<int>.generate(32, (i) => (i * 7 + 3) & 0xff));
  final iv = Uint8List.fromList(List<int>.generate(16, (i) => (i * 11) & 0xff));
  final inner = <String, dynamic>{
    'req': 'user.login',
    'user': 'geqian688',
    'password': 'p@ss word with spaces 中文',
    'stay': 2,
  };
  final cipherText = encryptAesCbcPkcs7(
    key: key,
    iv: iv,
    input: utf8.encode(jsonEncode(inner)),
  );
  _check('AES 密文按块对齐', cipherText.length % 16 == 0);
  final decrypted = decryptAesCbcPkcs7(key: key, iv: iv, input: cipherText);
  _check('AES 信封解密还原', jsonEncode(decrypted) == jsonEncode(inner));

  var tamperThrew = false;
  try {
    final tampered = Uint8List.fromList(cipherText);
    tampered[tampered.length - 1] ^= 0xff;
    decryptAesCbcPkcs7(key: key, iv: iv, input: tampered);
  } on ArgumentError {
    tamperThrew = true;
  }
  _check('AES 篡改密文触发填充错误', tamperThrew);

  // 3. RSA-OAEP（hash=SHA-256，MGF1=SHA-1）：加密 32B key 后用私钥解回。
  final rsaCipher = OAEPEncoding.withSHA256(RSAEngine())
    ..mgf1Hash = SHA1Digest()
    ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
  final encryptedKey = rsaCipher.process(key);
  _check('RSA 密文长度 = 2048bit', encryptedKey.length == 256);

  final privateKey = _parsePkcs1PrivateKey(_testPrivatePem);
  final rsaDecrypt = OAEPEncoding.withSHA256(RSAEngine())
    ..mgf1Hash = SHA1Digest()
    ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
  final decryptedKey = rsaDecrypt.process(encryptedKey);
  _check('RSA-OAEP 私钥解回原始 AES key', () {
    if (decryptedKey.length != key.length) return false;
    for (var i = 0; i < key.length; i++) {
      if (decryptedKey[i] != key[i]) return false;
    }
    return true;
  }());

  // 4. WS 地址推导与中继域判断。
  _check(
    'ws url 直连',
    FnNativeSystemLogin.webSocketUrlOf('http://192.168.6.120:5666') ==
        'ws://192.168.6.120:5666/websocket',
  );
  _check(
    'wss url 中继',
    FnNativeSystemLogin.webSocketUrlOf('https://demo.fnos.net/') ==
        'wss://demo.fnos.net/websocket',
  );
  _check('isRelayHost fnos.net', FnNativeSystemLogin.isRelayHost('https://demo.fnos.net'));
  _check('isRelayHost 直连 IP', !FnNativeSystemLogin.isRelayHost('http://192.168.6.120:5666'));

  // 5. 设备 ID。
  final id = FnNativeSystemLogin.generateDeviceId();
  _check(
    'deviceId UUID v4 格式',
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
        .hasMatch(id),
  );

  if (_failures > 0) {
    print('\nSELFTEST FAILED: $_failures failure(s)');
    throw StateError('selftest failed');
  }
  print('\nSELFTEST OK');
}

RSAPrivateKey _parsePkcs1PrivateKey(String pem) {
  final base64Body = pem
      .split(RegExp(r'-----[A-Z ]+-----'))
      .map((part) => part.replaceAll(RegExp(r'\s'), ''))
      .where((part) => part.isNotEmpty)
      .join();
  final bytes = Uint8List.fromList(base64Decode(base64Body));

  _Tlv readTlv(Uint8List b, int pos) {
    final tag = b[pos];
    var length = b[pos + 1] & 0x7f;
    var headerSize = 2;
    if ((b[pos + 1] & 0x80) != 0) {
      final count = length;
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | b[pos + 2 + i];
      }
      headerSize = 2 + count;
    }
    return _Tlv(
      tag: tag,
      content: Uint8List.sublistView(
          b, pos + headerSize, pos + headerSize + length),
      next: pos + headerSize + length,
    );
  }

  BigInt toBigInt(_Tlv tlv) => BigInt.parse(
      tlv.content.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
      radix: 16);

  final outer = readTlv(bytes, 0);
  // PKCS#8: SEQUENCE { INTEGER version, SEQUENCE alg, OCTET STRING pkcs1 }
  final version = readTlv(outer.content, 0);
  final algorithm = readTlv(outer.content, version.next);
  final octet = readTlv(outer.content, algorithm.next);
  final pkcs1 = readTlv(octet.content, 0);
  // PKCS#1 RSAPrivateKey ::= SEQUENCE { version, n, e, d, p, q, ... }
  final version2 = readTlv(pkcs1.content, 0);
  final n = readTlv(pkcs1.content, version2.next);
  final e = readTlv(pkcs1.content, n.next);
  final d = readTlv(pkcs1.content, e.next);
  final p = readTlv(pkcs1.content, d.next);
  final q = readTlv(pkcs1.content, p.next);
  return RSAPrivateKey(toBigInt(n), toBigInt(d), toBigInt(p), toBigInt(q));
}

class _Tlv {
  final int tag;
  final Uint8List content;
  final int next;

  const _Tlv({required this.tag, required this.content, required this.next});
}
