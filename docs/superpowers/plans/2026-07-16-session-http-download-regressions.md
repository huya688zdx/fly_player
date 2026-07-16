# 登录会话、HTTP 登录与下载刷新回归修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复普通网络错误导致全局登出、飞牛登录页无法明确选择 HTTP，以及下载中记录不实时刷新的三个回归，同时保留批次 S 的安全存储和批次 P 的行级刷新目标。

**Architecture:** 网络层只返回认证错误，不再直接修改全局会话；安全凭据通道使用 `value/missing/unavailable` 三态结果，运行中读取失败时保留内存会话；登录地址把协议作为显式 UI 状态；下载行收到服务通知后按记录 ID 读取最新不可变记录。每个行为独立走 RED-GREEN-REFACTOR 并单独提交。

**Tech Stack:** Flutter/Dart、Provider、Dio、MethodChannel、Android Kotlin、JUnit 4、flutter_test、SharedPreferences。

---

## 文件结构

- `lib/api/feiniu_api.dart`：移除普通请求 401 的全局登出副作用。
- `test/feiniu_api_fn_connect_test.dart`：覆盖 401 只返回错误、会话保持不变。
- `lib/services/secure_credential_store.dart`：定义安全凭据三态读取契约并解析原生返回值。
- `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/SecureCredentialStore.kt`：返回结构化读取状态，读取失败不删除密文。
- `android/app/src/test/kotlin/com/geqian/flyplayer/fly_player/SecureCredentialStoreTest.kt`：覆盖读取失败时文件保留。
- `lib/providers/nas_provider.dart`：凭据不可用时保留当前会话，首次启动保持未就绪而不是误判未登录。
- `lib/providers/backend_session_provider.dart`：中立后端凭据暂不可用时保留已加载 snapshot。
- `lib/services/media_backend_connection_store.dart`：后端连接恢复使用三态读取，凭据不可用时向 provider 报告加载失败。
- `lib/services/login_history_store.dart`：登录历史区分凭据缺失与暂时不可用。
- `test/services/secure_credential_store_test.dart`：覆盖平台失败可重试、不会永久切换内存后备。
- `test/providers/nas_provider_session_stability_test.dart`：覆盖安全存储失败不清运行中 token。
- `test/providers/backend_session_provider_test.dart`：覆盖 Emby 等中立后端会话在读取失败时保持不变。
- `lib/screens/connection_screen.dart`：恢复可见的 HTTP/HTTPS 协议选择。
- `lib/l10n/app_zh.arb`、`lib/l10n/app_zh_CN.arb`：补充协议选择文案。
- `test/screens/connection_feiniu_compatibility_test.dart`：覆盖 HTTP/HTTPS 显式选择与地址恢复。
- `lib/services/download_task_service.dart`：提供按 ID 读取当前记录的只读方法。
- `lib/screens/download_list_screen.dart`：行级监听按 ID 读取最新记录。
- `test/screens/download_list_back_behavior_test.dart`：覆盖列表页和详情页下载进度实时刷新。
- `docs/codex-review/FIX-PLAN.md`：记录 A-006、B-011、G-007 与 HTTP 登录回归修复证据。

## Task 1：普通 401 不再触发全局登出

**Files:**
- Modify: `test/feiniu_api_fn_connect_test.dart`
- Modify: `lib/api/feiniu_api.dart:473-481`

- [ ] **Step 1: 写失败测试**

在 `test/feiniu_api_fn_connect_test.dart` 的 `FeiniuApi playback record` 组中新增：

```dart
test('普通接口返回 401 时保留当前登录会话', () async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final provider = NasProvider();
  addTearDown(provider.dispose);
  await provider.updateSettings(
    baseUrl: 'http://127.0.0.1:5667',
    userName: 'user',
    password: 'password',
    token: 'session-token',
  );
  final api = FeiniuApi(
    provider,
    httpClientAdapter: _FakeDioAdapter(
      (_) => ResponseBody.fromString(
        '{}',
        401,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        },
      ),
    ),
  );

  await expectLater(
    api.recordPlayback(
      itemGuid: 'item-1',
      mediaGuid: 'media-1',
      videoGuid: 'video-1',
      ts: 10,
      duration: 100,
    ),
    throwsA(isA<AppException>().having(
      (error) => error.httpStatus,
      'httpStatus',
      401,
    )),
  );
  await Future<void>.delayed(Duration.zero);

  expect(provider.token, 'session-token');
  expect(provider.isConfigured, isTrue);
});
```

- [ ] **Step 2: 运行测试确认 RED**

Run:

```powershell
flutter test test/feiniu_api_fn_connect_test.dart --plain-name "普通接口返回 401 时保留当前登录会话"
```

Expected: FAIL，`provider.token` 实际为空，证明现有拦截器触发了 `logout()`。

- [ ] **Step 3: 最小实现**

在 `lib/api/feiniu_api.dart` 的 `onError` 中删除全局状态副作用，仅保留诊断和错误传递：

```dart
onError: (e, handler) {
  debugPrint(
    '[API][ERR] ${e.requestOptions.path} '
    'http=${e.response?.statusCode} err=${e.message}',
  );
  return handler.next(e);
},
```

- [ ] **Step 4: 运行定向测试确认 GREEN**

Run:

```powershell
flutter test test/feiniu_api_fn_connect_test.dart
```

Expected: PASS，401 仍作为 `AppException` 返回且 token 保持不变。

- [ ] **Step 5: 格式化、检查差异并提交**

```powershell
dart format lib/api/feiniu_api.dart test/feiniu_api_fn_connect_test.dart
git diff --check
git add -- lib/api/feiniu_api.dart test/feiniu_api_fn_connect_test.dart
git commit -m "fix(auth): preserve sessions on request failures"
```

## Task 2：安全凭据读取失败不再被当成凭据缺失

**Files:**
- Create: `test/services/secure_credential_store_test.dart`
- Create: `test/providers/nas_provider_session_stability_test.dart`
- Create: `android/app/src/test/kotlin/com/geqian/flyplayer/fly_player/SecureCredentialStoreTest.kt`
- Modify: `lib/services/secure_credential_store.dart`
- Modify: `lib/providers/nas_provider.dart`
- Modify: `lib/providers/backend_session_provider.dart`
- Modify: `lib/services/media_backend_connection_store.dart`
- Modify: `lib/services/login_history_store.dart`
- Modify: `test/providers/backend_session_provider_test.dart`
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/SecureCredentialStore.kt`

- [ ] **Step 1: 写 Dart 三态读取失败测试**

创建 `test/services/secure_credential_store_test.dart`：

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/services/secure_credential_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('平台读取失败返回 unavailable 且下一次仍会重试平台通道', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('fly_player/secret_store'),
          (call) async {
            if (call.method != 'readCredential') return null;
            calls += 1;
            if (calls == 1) {
              throw PlatformException(code: 'temporary_failure');
            }
            return <String, Object?>{
              'status': 'value',
              'value': 'restored-token',
            };
          },
        );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('fly_player/secret_store'),
            null,
          );
      SecureCredentialStore.resetBackendForTesting();
    });
    SecureCredentialStore.setBackendForTesting(
      MethodChannelSecureCredentialBackend(forcePlatformChannel: true),
    );

    final first = await SecureCredentialStore.read('session.token');
    final second = await SecureCredentialStore.read('session.token');

    expect(first.status, SecureCredentialReadStatus.unavailable);
    expect(second.status, SecureCredentialReadStatus.value);
    expect(second.value, 'restored-token');
    expect(calls, 2);
  });
}
```

- [ ] **Step 2: 写 NasProvider 会话保持失败测试**

创建 `test/providers/nas_provider_session_stability_test.dart`，使用可切换 backend：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/services/secure_credential_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('回前台读取安全凭据失败时保留当前 token', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final backend = _SwitchableCredentialBackend();
    SecureCredentialStore.setBackendForTesting(backend);
    addTearDown(SecureCredentialStore.resetBackendForTesting);

    final provider = NasProvider();
    addTearDown(provider.dispose);
    await provider.updateSettings(
      baseUrl: 'http://192.168.1.8:5667',
      userName: 'alice',
      password: 'secret',
      token: 'active-token',
    );
    backend.unavailable = true;

    await provider.reloadSettingsForTesting();

    expect(provider.token, 'active-token');
    expect(provider.isConfigured, isTrue);
  });
}

class _SwitchableCredentialBackend implements SecureCredentialBackend {
  final Map<String, String> values = <String, String>{};
  bool unavailable = false;

  @override
  Future<SecureCredentialReadResult> read(String key) async {
    if (unavailable) return SecureCredentialReadResult.unavailable();
    final value = values[key] ?? '';
    return value.isEmpty
        ? const SecureCredentialReadResult.missing()
        : SecureCredentialReadResult.found(value);
  }

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
```

在 `test/providers/backend_session_provider_test.dart` 增加：

```dart
test('安全凭据暂不可用时保留已加载的后端会话', () async {
  final backend = _SwitchableCredentialBackend();
  SecureCredentialStore.setBackendForTesting(backend);
  addTearDown(SecureCredentialStore.resetBackendForTesting);
  await MediaBackendConnectionStore.saveActive(
    const MediaBackendConnection(
      kind: MediaBackendKind.emby,
      serverUrl: 'https://emby.example.test',
      userId: 'user-id',
      accessToken: 'access-token',
    ),
  );
  final provider = BackendSessionProvider(autoLoad: false);
  addTearDown(provider.dispose);
  await provider.load();
  backend.unavailable = true;

  await provider.load();

  expect(provider.currentKind, MediaBackendKind.emby);
  expect(provider.currentConnection?.accessToken, 'access-token');
  expect(provider.isConfigured, isTrue);
});
```

并在该测试文件底部加入：

```dart
class _SwitchableCredentialBackend implements SecureCredentialBackend {
  final Map<String, String> values = <String, String>{};
  bool unavailable = false;

  @override
  Future<SecureCredentialReadResult> read(String key) async {
    if (unavailable) return const SecureCredentialReadResult.unavailable();
    final value = values[key] ?? '';
    return value.isEmpty
        ? const SecureCredentialReadResult.missing()
        : SecureCredentialReadResult.found(value);
  }

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
```

`reloadSettingsForTesting()` 只用 `@visibleForTesting` 暴露现有 `_loadSettings()`，不新增测试专用状态修改逻辑：

```dart
@visibleForTesting
Future<void> reloadSettingsForTesting() => _loadSettings();
```

- [ ] **Step 3: 写 Kotlin 文件保留失败测试**

创建 `android/app/src/test/kotlin/com/geqian/flyplayer/fly_player/SecureCredentialStoreTest.kt`：

```kotlin
package com.geqian.flyplayer.fly_player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

class SecureCredentialStoreTest {
    @Test
    fun readFailureKeepsEncryptedFileForRetry() {
        val file = Files.createTempFile("credential", ".json").toFile()
        file.writeText("encrypted-payload")

        val result = readCredentialFile(file) {
            throw IllegalStateException("temporary keystore failure")
        }

        assertEquals(CredentialReadStatus.ERROR, result.status)
        assertTrue(file.exists())
        file.delete()
    }
}
```

- [ ] **Step 4: 运行三组测试确认 RED**

```powershell
flutter test test/services/secure_credential_store_test.dart
flutter test test/providers/nas_provider_session_stability_test.dart
Set-Location android
.\gradlew.bat :app:testLiteDebugUnitTest --tests "com.geqian.flyplayer.fly_player.SecureCredentialStoreTest"
Set-Location ..
```

Expected: Dart 测试因三态类型和测试入口不存在而失败；Kotlin 测试因 `readCredentialFile`/`CredentialReadStatus` 不存在而失败。

- [ ] **Step 5: 实现 Dart 三态契约**

在 `lib/services/secure_credential_store.dart` 定义：

```dart
enum SecureCredentialReadStatus { value, missing, unavailable }

class SecureCredentialReadResult {
  final SecureCredentialReadStatus status;
  final String value;

  const SecureCredentialReadResult._(this.status, this.value);
  const SecureCredentialReadResult.missing()
    : this._(SecureCredentialReadStatus.missing, '');
  const SecureCredentialReadResult.unavailable()
    : this._(SecureCredentialReadStatus.unavailable, '');
  factory SecureCredentialReadResult.found(String value) =>
      SecureCredentialReadResult._(SecureCredentialReadStatus.value, value);

  bool get isUnavailable => status == SecureCredentialReadStatus.unavailable;
}

abstract class SecureCredentialBackend {
  Future<SecureCredentialReadResult> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}
```

`MethodChannelSecureCredentialBackend` 不再在异常后设置永久 `_useMemoryFallback`；测试 messenger 仍可使用内存 backend，显式 `forcePlatformChannel` 用于验证重试：

```dart
class MethodChannelSecureCredentialBackend implements SecureCredentialBackend {
  MethodChannelSecureCredentialBackend({this.forcePlatformChannel = false});

  final bool forcePlatformChannel;

  @override
  Future<SecureCredentialReadResult> read(String key) async {
    final normalized = _normalizeKey(key);
    if (normalized.isEmpty) return const SecureCredentialReadResult.missing();
    if (!forcePlatformChannel && _usesTestMessenger()) {
      return const SecureCredentialReadResult.missing();
    }
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'readCredential',
        <String, String>{'key': normalized},
      );
      return switch (raw?['status']) {
        'value' => SecureCredentialReadResult.found(
            (raw?['value'] ?? '').toString(),
          ),
        'missing' => const SecureCredentialReadResult.missing(),
        _ => const SecureCredentialReadResult.unavailable(),
      };
    } on PlatformException {
      return const SecureCredentialReadResult.unavailable();
    } on MissingPluginException {
      return const SecureCredentialReadResult.unavailable();
    }
  }

  bool _usesTestMessenger() {
    try {
      return ServicesBinding.instance.defaultBinaryMessenger.runtimeType
          .toString()
          .contains('Test');
    } catch (_) {
      return true;
    }
  }
}
```

`MemorySecureCredentialBackend.read()` 返回 `value` 或 `missing`。`write/delete` 的现有签名保持不变；生产平台写入异常继续抛出，使登录保存明确失败而不是假成功。

- [ ] **Step 6: 实现 Kotlin 三态读取并保留文件**

在 `SecureCredentialStore.kt` 增加纯文件边界：

```kotlin
internal enum class CredentialReadStatus { VALUE, MISSING, ERROR }

internal data class CredentialReadResult(
    val status: CredentialReadStatus,
    val value: String = "",
) {
    fun toChannelValue(): Map<String, Any> = when (status) {
        CredentialReadStatus.VALUE -> mapOf("status" to "value", "value" to value)
        CredentialReadStatus.MISSING -> mapOf("status" to "missing")
        CredentialReadStatus.ERROR -> mapOf("status" to "unavailable")
    }
}

internal fun readCredentialFile(
    file: File,
    reader: (File) -> String,
): CredentialReadResult {
    if (!file.exists()) return CredentialReadResult(CredentialReadStatus.MISSING)
    return try {
        CredentialReadResult(CredentialReadStatus.VALUE, reader(file))
    } catch (_: Exception) {
        CredentialReadResult(CredentialReadStatus.ERROR)
    }
}
```

`SecureCredentialStore.read()` 改为返回 channel map，并删除异常路径中的 `file.delete()`：

```kotlin
fun read(key: String): Map<String, Any> {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
        return CredentialReadResult(CredentialReadStatus.ERROR).toChannelValue()
    }
    return readCredentialFile(credentialFile(key)) { file ->
        val payload = JSONObject(file.readText(StandardCharsets.UTF_8))
        decrypt(
            cipherText = payload.optString("encryptedValue"),
            iv = payload.optString("iv"),
        )
    }.toChannelValue()
}
```

`FlutterHostActivity.kt` 现有 `result.success(secureCredentialStore.read(key))` 可以直接透传 map，不需要修改。

- [ ] **Step 7: 让会话恢复消费三态结果**

在 `NasProvider._restoreCredential()` 增加 `currentValue`，不可用时保留当前值：

```dart
Future<({String value, bool available})> _restoreCredential(
  String key, {
  required String legacyValue,
  required String currentValue,
  required bool shouldKeep,
}) async {
  if (!shouldKeep) {
    await SecureCredentialStore.delete(key);
    return (value: '', available: true);
  }
  final stored = await SecureCredentialStore.read(key);
  if (stored.isUnavailable) {
    return (value: currentValue, available: false);
  }
  if (stored.value.isNotEmpty) {
    return (value: stored.value, available: true);
  }
  if (legacyValue.isNotEmpty) {
    await SecureCredentialStore.write(key, legacyValue);
    return (value: legacyValue, available: true);
  }
  return (value: '', available: true);
}
```

`_loadSettings()` 在 token 不可用且没有当前 token 时提前返回、不设置 `_isReady`；已有内存 token 时继续使用并保持已登录。只有 `available == true` 时才清理对应旧明文 key。

在 `secure_credential_store.dart` 定义不携带敏感内容的异常：

```dart
class SecureCredentialUnavailableException implements Exception {
  final String key;

  const SecureCredentialUnavailableException(this.key);

  @override
  String toString() => 'Secure credential is temporarily unavailable: $key';
}
```

`MediaBackendConnectionStore._restoreCredential()` 在 `unavailable` 时执行：

```dart
final stored = await SecureCredentialStore.read(key);
if (stored.isUnavailable) {
  throw SecureCredentialUnavailableException(key);
}
```

`BackendSessionProvider.load()` 先把新 snapshot 读到局部变量，成功后才替换；读取失败时记录 warning 并保留旧值：

```dart
Future<void> load() async {
  try {
    final nextSnapshot = await MediaBackendConnectionStore.load();
    _snapshot = nextSnapshot;
    _isReady = true;
    notifyListeners();
  } on SecureCredentialUnavailableException catch (error, stackTrace) {
    await logSwallowedError(
      action: 'load backend session credentials',
      error: error,
      stackTrace: stackTrace,
      source: 'backend_session_provider',
    );
  }
}
```

首次启动失败时 `_isReady` 保持 `false`，AppGate 继续显示加载态；回前台会再次 `load()`。运行中失败时旧 `_snapshot` 和已认证状态保持不变。

`LoginHistoryStore._restorePassword()` 对三态的处理固定为：

```dart
final stored = await SecureCredentialStore.read(_passwordKey(entry));
if (stored.isUnavailable) {
  return '';
}
if (stored.value.isNotEmpty) {
  return stored.value;
}
```

然后沿用现有 legacy password 迁移逻辑；`unavailable` 分支不删除安全凭据，也不改变 `rememberPassword`。

- [ ] **Step 8: 运行定向测试确认 GREEN**

```powershell
flutter test test/services/secure_credential_store_test.dart test/providers/nas_provider_session_stability_test.dart test/providers/backend_session_provider_test.dart test/services/media_backend_connection_store_test.dart test/services/login_history_store_test.dart
Set-Location android
.\gradlew.bat :app:testLiteDebugUnitTest --tests "com.geqian.flyplayer.fly_player.SecureCredentialStoreTest"
Set-Location ..
```

Expected: 全部 PASS；Kotlin 测试确认异常后临时文件仍存在。

- [ ] **Step 9: 格式化、静态检查并提交**

```powershell
dart format lib/services/secure_credential_store.dart lib/providers/nas_provider.dart lib/providers/backend_session_provider.dart lib/services/media_backend_connection_store.dart lib/services/login_history_store.dart test/services/secure_credential_store_test.dart test/providers/nas_provider_session_stability_test.dart test/providers/backend_session_provider_test.dart
flutter analyze lib/services/secure_credential_store.dart lib/providers/nas_provider.dart lib/providers/backend_session_provider.dart lib/services/media_backend_connection_store.dart lib/services/login_history_store.dart
git diff --check
git add -- lib/services/secure_credential_store.dart lib/providers/nas_provider.dart lib/providers/backend_session_provider.dart lib/services/media_backend_connection_store.dart lib/services/login_history_store.dart android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/SecureCredentialStore.kt android/app/src/test/kotlin/com/geqian/flyplayer/fly_player/SecureCredentialStoreTest.kt test/services/secure_credential_store_test.dart test/providers/nas_provider_session_stability_test.dart test/providers/backend_session_provider_test.dart
git commit -m "fix(auth): keep sessions on credential read failures"
```

## Task 3：恢复明确的 HTTP/HTTPS 登录选择

**Files:**
- Modify: `lib/screens/connection_screen.dart`
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_zh_CN.arb`
- Modify: `lib/l10n/generated/app_localizations.dart`
- Modify: `lib/l10n/generated/app_localizations_zh.dart`
- Modify: `test/screens/connection_feiniu_compatibility_test.dart`

- [ ] **Step 1: 写失败 Widget 测试**

把 `connection_feiniu_compatibility_test.dart` 的初始偏好改为 HTTP，并扩展断言：

```dart
setUp(() {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'base_url': 'http://nas.example.test:5667',
    'user_name': 'alice',
    'password': 'secret',
    'remember_password': true,
  });
});

testWidgets('飞牛登录页显示并保留 HTTP 协议选择', (tester) async {
  await tester.pumpWidget(_connectionScreen());
  await tester.pumpAndSettle();

  expect(find.text('HTTP'), findsOneWidget);
  expect(find.text('HTTPS'), findsOneWidget);
  final selector = tester.widget<SegmentedButton<String>>(
    find.byType(SegmentedButton<String>),
  );
  expect(selector.selected, <String>{'http'});
  final serverField = tester.widget<TextField>(find.byType(TextField).first);
  expect(serverField.controller?.text, 'nas.example.test:5667');
});
```

再增加切换验证：

```dart
testWidgets('用户可以从 HTTPS 明确切回 HTTP', (tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'base_url': 'https://nas.example.test:5667',
  });
  await tester.pumpWidget(_connectionScreen());
  await tester.pumpAndSettle();

  await tester.tap(find.text('HTTP'));
  await tester.pump();

  final selector = tester.widget<SegmentedButton<String>>(
    find.byType(SegmentedButton<String>),
  );
  expect(selector.selected, <String>{'http'});
});
```

再增加“粘贴完整 HTTPS 地址会同步协议选择”的测试：向首个地址字段输入 `https://other.example.test:7443/path`，`pump()` 后断言 `SegmentedButton<String>.selected == {'https'}`。

- [ ] **Step 2: 运行测试确认 RED**

```powershell
flutter test test/screens/connection_feiniu_compatibility_test.dart
```

Expected: FAIL，页面没有 `SegmentedButton<String>` 和可见协议选项。

- [ ] **Step 3: 添加国际化资源并生成代码**

在两个 ARB 文件的连接文案区增加：

```json
"connectionProtocolLabel": "访问协议",
"connectionProtocolHttp": "HTTP",
"connectionProtocolHttps": "HTTPS"
```

Run:

```powershell
flutter gen-l10n
```

- [ ] **Step 4: 实现协议选择控件**

在飞牛地址字段下、账号字段前加入只对飞牛显示的分段选择：

```dart
if (!isEmby) ...<Widget>[
  const SizedBox(height: 10),
  Row(
    children: <Widget>[
      Expanded(
        child: Text(
          l10n.connectionProtocolLabel,
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
      SegmentedButton<String>(
        segments: <ButtonSegment<String>>[
          ButtonSegment<String>(
            value: 'http',
            label: Text(l10n.connectionProtocolHttp),
          ),
          ButtonSegment<String>(
            value: 'https',
            label: Text(l10n.connectionProtocolHttps),
          ),
        ],
        selected: <String>{_baseUrlScheme},
        onSelectionChanged: (selected) {
          if (selected.isEmpty) return;
          setState(() => _baseUrlScheme = selected.first);
        },
      ),
    ],
  ),
],
```

为 `_GlassField` 增加可选 `ValueChanged<String>? onChanged` 并透传给内部 `TextField`。飞牛地址字段传入以下 handler，使粘贴显式协议时立即同步选择：

```dart
void _handleFeiniuAddressChanged(String raw) {
  final scheme = Uri.tryParse(raw.trim())?.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return;
  if (_baseUrlScheme == scheme) return;
  setState(() => _baseUrlScheme = scheme!);
}
```

保持 `_normalizeBaseUrlInput()` 的“显式协议优先”规则；`initState` 和 `_applyHistorySelection()` 继续通过 `_schemeForLogin()` 恢复协议。不要修改 Android cleartext 配置。

- [ ] **Step 5: 运行 Widget 测试确认 GREEN**

```powershell
flutter test test/screens/connection_feiniu_compatibility_test.dart test/screens/connection_backend_selection_test.dart
```

Expected: PASS；HTTP 地址恢复为 HTTP，切换后状态可见且 Emby 表单不出现飞牛协议控件。

- [ ] **Step 6: 格式化、分析并提交**

```powershell
dart format lib/screens/connection_screen.dart test/screens/connection_feiniu_compatibility_test.dart lib/l10n/generated
flutter analyze lib/screens/connection_screen.dart test/screens/connection_feiniu_compatibility_test.dart
git diff --check
git add -- lib/screens/connection_screen.dart lib/l10n/app_zh.arb lib/l10n/app_zh_CN.arb lib/l10n/generated/app_localizations.dart lib/l10n/generated/app_localizations_zh.dart test/screens/connection_feiniu_compatibility_test.dart
git commit -m "fix(login): restore explicit http protocol selection"
```

## Task 4：下载行从服务读取最新不可变记录

**Files:**
- Modify: `lib/services/download_task_service.dart:192-269`
- Modify: `lib/screens/download_list_screen.dart:528-548,1105-1130`
- Modify: `test/screens/download_list_back_behavior_test.dart`

- [ ] **Step 1: 写列表页和详情页失败测试**

在 `download_list_back_behavior_test.dart` 添加一个 `_downloadingRecord()` helper，`totalBytes: 1024`、初始 `downloadedBytes: 128`、状态为 `downloading`。

列表页测试：

```dart
testWidgets('下载列表在记录对象被替换后刷新已下载字节', (tester) async {
  final initial = _downloadingRecord(videoFile.path);
  DownloadTaskService.instance.debugReplaceRecordsForTesting(<DownloadTaskRecord>[
    initial,
  ]);
  await tester.pumpWidget(
    _testApp(
      observer: _PopCountingObserver(),
      routePage: const DownloadListScreen(initialTab: DownloadListTab.downloading),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('128 B / 1.00 KB'), findsOneWidget);

  DownloadTaskService.instance.debugReplaceRecordsForTesting(<DownloadTaskRecord>[
    initial.copyWith(downloadedBytes: 512, updatedAtMs: 3),
  ]);
  await tester.pump();

  expect(find.text('512 B / 1.00 KB'), findsOneWidget);
});
```

详情页测试使用：

```dart
const DownloadGroupDetailScreen(
  groupId: '白箱 第 1 季',
  initialTab: DownloadListTab.downloading,
)
```

执行同样的 `128 → 512` 替换并断言详情页刷新。

- [ ] **Step 2: 运行测试确认 RED**

```powershell
flutter test test/screens/download_list_back_behavior_test.dart --plain-name "下载列表在记录对象被替换后刷新已下载字节"
flutter test test/screens/download_list_back_behavior_test.dart --plain-name "下载详情在记录对象被替换后刷新已下载字节"
```

Expected: 两个测试都 FAIL，界面仍显示 `128 B / 1.00 KB`。

- [ ] **Step 3: 暴露按 ID 只读查询**

在 `DownloadTaskService` 的公开 getters 附近添加：

```dart
DownloadTaskRecord? recordById(String recordId) {
  final normalized = recordId.trim();
  if (normalized.isEmpty) return null;
  return _recordById(normalized);
}
```

- [ ] **Step 4: 行级 builder 获取最新记录**

列表页下载中行 builder 改为：

```dart
builder: (context, _) {
  final currentRecord = _service.recordById(record.id) ?? record;
  return _DownloadRecordRow(
    record: currentRecord,
    token: token,
    downloadSpeedBytesPerSecond:
        _service.downloadSpeedBytesPerSecondFor(currentRecord.id),
  );
},
```

详情页下载中行 builder 同样用 `currentRecord`，并让 `busy`、`dimmed`、选择回调和播放回调统一引用 `currentRecord.id`/`currentRecord`，避免 UI 数据与操作目标不一致。

- [ ] **Step 5: 运行测试确认 GREEN**

```powershell
flutter test test/screens/download_list_back_behavior_test.dart
flutter test test/download_task_record_test.dart
```

Expected: PASS；列表页、详情页都显示 `512 B / 1.00 KB`，原有返回键行为仍通过。

- [ ] **Step 6: 格式化、分析并提交**

```powershell
dart format lib/services/download_task_service.dart lib/screens/download_list_screen.dart test/screens/download_list_back_behavior_test.dart
flutter analyze lib/services/download_task_service.dart lib/screens/download_list_screen.dart test/screens/download_list_back_behavior_test.dart
git diff --check
git add -- lib/services/download_task_service.dart lib/screens/download_list_screen.dart test/screens/download_list_back_behavior_test.dart
git commit -m "fix(download): refresh rows from current task records"
```

## Task 5：更新评审计划并做全量验证

**Files:**
- Modify: `docs/codex-review/FIX-PLAN.md`

- [ ] **Step 1: 更新登记表**

在已修复登记表中：

- 更新 `B-011` 行，补充三态安全存储、瞬时读取失败保留会话、Android 密文不删除及 Task 2 提交号。
- 新增 `A-006` 行，说明普通 401 不再由网络层直接调用 `logout()`，证据为 Task 1 测试与提交。
- 更新 `G-007` 行，说明行级监听按记录 ID 读取当前记录，证据为 Task 4 Widget 测试与提交。
- 新增 `S/P 回归` 行，说明飞牛登录恢复显式 HTTP/HTTPS 选择，证据为 Task 3 Widget 测试与提交。
- 将第 5.2 节的 A-006 标记为已修复；将批次 P 的 G-007 说明补充为“已修复回归”。

不要覆盖用户已有内容；提交前确认 `git diff -- docs/codex-review/FIX-PLAN.md` 只包含上述登记变化。

- [ ] **Step 2: 运行相关测试集合**

```powershell
flutter test test/feiniu_api_fn_connect_test.dart test/services/secure_credential_store_test.dart test/providers/nas_provider_session_stability_test.dart test/providers/backend_session_provider_test.dart test/services/media_backend_connection_store_test.dart test/services/login_history_store_test.dart test/screens/connection_feiniu_compatibility_test.dart test/screens/connection_backend_selection_test.dart test/screens/download_list_back_behavior_test.dart test/download_task_record_test.dart
```

Expected: 全部 PASS，0 failed。

- [ ] **Step 3: 运行 Android 单测**

```powershell
Set-Location android
.\gradlew.bat :app:testLiteDebugUnitTest --tests "com.geqian.flyplayer.fly_player.SecureCredentialStoreTest"
Set-Location ..
```

Expected: `BUILD SUCCESSFUL`。

- [ ] **Step 4: 运行全项目静态分析**

```powershell
flutter analyze
```

Expected: exit code 0；若存在与本次无关的历史 warning，记录完整数量与文件，不得声称分析通过。

- [ ] **Step 5: 构建 debug APK**

```powershell
flutter build apk --debug --flavor lite
```

Expected: exit code 0，并生成 lite debug APK。若本机依赖或签名配置阻塞，如实记录命令和错误。

- [ ] **Step 6: 检查差异并提交文档**

```powershell
git diff --check
git status --short
git diff -- docs/codex-review/FIX-PLAN.md
git add -- docs/codex-review/FIX-PLAN.md
git commit -m "docs: record session and download regression fixes"
```

- [ ] **Step 7: 最终核对提交与工作区**

```powershell
git log --oneline -6
git status --short --branch
```

Expected: 能看到设计提交、四个修复/文档提交；工作区只保留任务开始前已有的 `.codex-remote-attachments/`、旧计划文件或其他用户变更，不出现本任务未提交代码。
