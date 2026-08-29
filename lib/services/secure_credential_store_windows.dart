import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'secure_credential_store.dart';

/// Windows 桌面端安全凭据后端：DPAPI（CryptProtectData，当前用户作用域）加密
/// 后落 SharedPreferences。
///
/// Android 的凭据走 `fly_player/secret_store` 原生通道（Keystore）；Windows 上
/// 该通道不存在，`SecureCredentialStore.read` 会返回 unavailable，导致
/// NasProvider 加载时抛 SecureCredentialUnavailableException（桌面首启「加载
/// 失败」的根因）。此提供等价能力：密文仅当前 Windows 用户可解，满足 NAS
/// token/密码的存储安全档位；换用户/换机器拷贝出的密文解密失败按 missing 处
/// 理，让上层自然回登录态。
class WindowsSecureCredentialBackend implements SecureCredentialBackend {
  static const String _prefsPrefix = 'win_secret_dpapi_';

  @override
  Future<SecureCredentialReadResult> read(String key) async {
    final normalized = _normalizeKey(key);
    if (normalized.isEmpty) {
      return const SecureCredentialReadResult.missing();
    }
    final prefs = await SharedPreferences.getInstance();
    final blob = prefs.getString(_prefsPrefix + normalized);
    if (blob == null || blob.isEmpty) {
      return const SecureCredentialReadResult.missing();
    }
    // prefs 被人工改动/截断时 base64 解不开：按 missing 处理，回登录态而不是崩。
    final Uint8List cipher;
    try {
      cipher = base64Decode(blob);
    } on FormatException {
      return const SecureCredentialReadResult.missing();
    }
    final Uint8List? clear = _dpapiTransform(cipher, encrypt: false);
    if (clear == null) {
      return const SecureCredentialReadResult.missing();
    }
    return SecureCredentialReadResult.found(utf8.decode(clear));
  }

  @override
  Future<void> write(String key, String value) async {
    final normalized = _normalizeKey(key);
    if (normalized.isEmpty) return;
    if (value.isEmpty) {
      await delete(normalized);
      return;
    }
    final Uint8List? blob = _dpapiTransform(
      Uint8List.fromList(utf8.encode(value)),
      encrypt: true,
    );
    if (blob == null) {
      throw SecureCredentialOperationException('write', normalized);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsPrefix + normalized, base64Encode(blob));
  }

  @override
  Future<void> delete(String key) async {
    final normalized = _normalizeKey(key);
    if (normalized.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsPrefix + normalized);
  }
}

final DynamicLibrary _crypt32 = DynamicLibrary.open('crypt32.dll');
final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

final int Function(
  Pointer<Blob>,
  Pointer<Uint16>,
  Pointer<Blob>,
  int,
  Pointer<Blob>,
  int,
  Pointer<Blob>,
)
_cryptProtectData = _crypt32
    .lookupFunction<
      Int32 Function(
        Pointer<Blob>,
        Pointer<Uint16>,
        Pointer<Blob>,
        Uint32,
        Pointer<Blob>,
        Uint32,
        Pointer<Blob>,
      ),
      int Function(
        Pointer<Blob>,
        Pointer<Uint16>,
        Pointer<Blob>,
        int,
        Pointer<Blob>,
        int,
        Pointer<Blob>,
      )
    >('CryptProtectData');

final int Function(
  Pointer<Blob>,
  Pointer<Uint16>,
  Pointer<Blob>,
  int,
  Pointer<Blob>,
  int,
  Pointer<Blob>,
)
_cryptUnprotectData = _crypt32
    .lookupFunction<
      Int32 Function(
        Pointer<Blob>,
        Pointer<Uint16>,
        Pointer<Blob>,
        Uint32,
        Pointer<Blob>,
        Uint32,
        Pointer<Blob>,
      ),
      int Function(
        Pointer<Blob>,
        Pointer<Uint16>,
        Pointer<Blob>,
        int,
        Pointer<Blob>,
        int,
        Pointer<Blob>,
      )
    >('CryptUnprotectData');

final Pointer<Void> Function(Pointer<Void>) _localFree = _kernel32
    .lookupFunction<
      Pointer<Void> Function(Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>)
    >('LocalFree');

/// CRYPTPROTECT_UI_FORBIDDEN：服务/无头场景不弹任何保护 UI。
const int _uiForbidden = 0x1;

base class Blob extends Struct {
  @Uint32()
  external int cbData;

  external Pointer<Uint8> pbData;
}

/// 加密/解密一体：输入输出都是原始字节；失败（含密文损坏）返回 null。
Uint8List? _dpapiTransform(Uint8List input, {required bool encrypt}) {
  if (input.isEmpty) return null;
  final Pointer<Blob> inBlob = calloc<Blob>();
  final Pointer<Blob> outBlob = calloc<Blob>();
  final Pointer<Uint8> inBuffer = calloc<Uint8>(input.length);
  try {
    inBuffer.asTypedList(input.length).setAll(0, input);
    inBlob.ref
      ..cbData = input.length
      ..pbData = inBuffer;
    final int ok = encrypt
        ? _cryptProtectData(
            inBlob,
            nullptr,
            nullptr,
            0,
            nullptr,
            _uiForbidden,
            outBlob,
          )
        : _cryptUnprotectData(
            inBlob,
            nullptr,
            nullptr,
            0,
            nullptr,
            _uiForbidden,
            outBlob,
          );
    if (ok == 0) return null;
    final int length = outBlob.ref.cbData;
    if (length <= 0) return null;
    return Uint8List.fromList(outBlob.ref.pbData.asTypedList(length));
  } catch (_) {
    // FFI 层异常（理论上不应发生）：按失败处理，不向凭据调用方泄漏原生崩溃。
    return null;
  } finally {
    _localFree(outBlob.ref.pbData.cast<Void>());
    calloc
      ..free(inBuffer)
      ..free(inBlob)
      ..free(outBlob);
  }
}

String _normalizeKey(String key) => key.trim();
