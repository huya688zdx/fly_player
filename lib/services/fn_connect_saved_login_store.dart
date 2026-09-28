/// FN Connect 免密续登凭据的持久化（按 FN Connect 标识隔离）。
///
/// 基于 [SecureCredentialStore]：Windows 走 DPAPI、Linux 走桌面密钥环、
/// 移动端走原生安全通道；读取失败一律按无凭据处理，避免安全存储不可用
/// 时阻断正常登录。
library;

import 'secure_credential_store.dart';

/// 已保存的免密续登凭据（按 FN Connect 标识隔离）。
class FnConnectSavedLogin {
  final String longToken;

  /// tokenLogin 明文包签名用的 16 字节 secret（Base64 编码存储）。
  final String secretBase64;

  final String did;

  const FnConnectSavedLogin({
    required this.longToken,
    required this.secretBase64,
    required this.did,
  });
}

/// 基于 [SecureCredentialStore] 的免密续登凭据存取。
class FnConnectSavedLoginStore {
  static String _tokenKey(String fnConnectId) =>
      'fn_connect.long_token/${fnConnectId.trim().toLowerCase()}';

  static String _secretKey(String fnConnectId) =>
      'fn_connect.secret/${fnConnectId.trim().toLowerCase()}';

  static String _didKey(String fnConnectId) =>
      'fn_connect.did/${fnConnectId.trim().toLowerCase()}';

  static Future<FnConnectSavedLogin?> read(String fnConnectId) async {
    if (fnConnectId.trim().isEmpty) return null;
    final tokenResult = await SecureCredentialStore.read(_tokenKey(fnConnectId));
    if (tokenResult.status != SecureCredentialReadStatus.value) return null;
    final token = tokenResult.value;
    if (token.isEmpty) return null;
    final secretResult =
        await SecureCredentialStore.read(_secretKey(fnConnectId));
    final secret = secretResult.status == SecureCredentialReadStatus.value
        ? secretResult.value
        : '';
    final didResult = await SecureCredentialStore.read(_didKey(fnConnectId));
    final did = didResult.status == SecureCredentialReadStatus.value
        ? didResult.value
        : '';
    return FnConnectSavedLogin(
      longToken: token,
      secretBase64: secret,
      did: did,
    );
  }

  static Future<void> save(
    String fnConnectId, {
    required String longToken,
    required String secretBase64,
    required String did,
  }) async {
    if (fnConnectId.trim().isEmpty || longToken.isEmpty) return;
    await SecureCredentialStore.write(_tokenKey(fnConnectId), longToken);
    if (secretBase64.isNotEmpty) {
      await SecureCredentialStore.write(_secretKey(fnConnectId), secretBase64);
    }
    if (did.isNotEmpty) {
      await SecureCredentialStore.write(_didKey(fnConnectId), did);
    }
  }

  static Future<void> clear(String fnConnectId) async {
    if (fnConnectId.trim().isEmpty) return;
    await SecureCredentialStore.delete(_tokenKey(fnConnectId));
    await SecureCredentialStore.delete(_secretKey(fnConnectId));
    await SecureCredentialStore.delete(_didKey(fnConnectId));
  }
}
