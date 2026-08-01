# 飞牛访问码适配实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为飞牛 NAS 直连和 FN Connect 最终 NAS 请求增加可选访问码，覆盖登录、API、图片、下载、字幕、播放和 Android 原生封面链路，同时保证旧后端与第三方 URL 不回归、不泄漏凭据。

**Architecture:** 新建纯 Dart 访问码传输策略，统一完成 UTF-8 Base64、同源判定和网关挑战识别；`NasProvider` 与登录历史通过安全凭据存储管理原始访问码，`FeiniuApi` 和图片请求只消费统一头构造函数。播放头沿 `MpvMediaSource.headers` 进入 Android，原生图片改为传完整头映射，原生代理通过可测试的白名单/阻断策略保留访问码头。

**Tech Stack:** Flutter/Dart、Provider、Dio、SharedPreferences、安全凭据 MethodChannel、Kotlin、OkHttp、Glide、JUnit 4、Flutter Test。

---

## 文件结构

- 新建 `lib/api/feiniu_access_code_transport.dart`：访问码编码、同源判定、Dio 拦截器及网关挑战哨兵。
- 修改 `lib/api/feiniu_api.dart`：所有飞牛 Dio、登录、FN Connect 和签名头入口接入访问码。
- 修改 `lib/providers/nas_provider.dart`：运行时访问码、安全存储、进程恢复与 bootstrap 快照。
- 修改 `lib/services/login_history_store.dart`：历史记录的访问码安全存储，不写 JSON。
- 修改 `lib/screens/connection_screen.dart`、`lib/screens/fn_connect_web_login_page.dart`：可选访问码输入、回填和登录参数传递。
- 修改 `lib/utils/login_error_resolver.dart` 及 `lib/l10n/`：访问码必需/错误提示。
- 修改 `lib/utils/nas_image_headers.dart`、`lib/ui/detail_artwork_resolver.dart` 及飞牛图片调用点：同源图片头。
- 修改 `lib/theme/dynamic_theme_seed_extractor.dart`：主题采样通道传完整图片头。
- 修改 `lib/services/download_task_service.dart`、`lib/controllers/item_playback_launcher.dart`、`lib/services/native_reentry_support.dart`：下载封面和原生选集图片头。
- 新建 `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativeImageRequestHeaders.kt`：Map 解析、Intent 扁平化和 Glide 头构造的公共策略。
- 修改 `ThemeColorSampler.kt`、`FlutterHostActivity.kt`、`NativePlayerActivity.kt`、`NativePlaybackMediaService.kt`：原生图片完整头透传。
- 新建 `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/mpv/NativeProxyHeaderPolicy.kt` 并修改 `NativeMpvProxyServer.kt`：可测试的代理转发头过滤。

### Task 1：访问码传输策略

**Files:**
- Create: `lib/api/feiniu_access_code_transport.dart`
- Create: `test/api/feiniu_access_code_transport_test.dart`

- [ ] **Step 1: 写编码、同源和挑战识别的失败测试**

```dart
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/api/feiniu_access_code_transport.dart';

void main() {
  test('访问码按 UTF-8 Base64 编码并标记 app 来源', () {
    expect(
      buildFeiniuAccessCodeHeaders('测试'),
      <String, String>{
        'x-access-code': base64Encode(utf8.encode('测试')),
        'x-access-source': 'app',
      },
    );
    expect(buildFeiniuAccessCodeHeaders('  '), isEmpty);
  });

  test('仅向同源 NAS URL 发送访问码', () {
    expect(
      buildFeiniuAccessCodeHeadersForUrl(
        accessCode: '123456',
        baseUrl: 'https://nas.example.test:5667',
        url: 'https://nas.example.test:5667/v/api/v1/user/info',
      ),
      contains('x-access-code'),
    );
    expect(
      buildFeiniuAccessCodeHeadersForUrl(
        accessCode: '123456',
        baseUrl: 'https://nas.example.test:5667',
        url: 'http://nas.example.test:5667/video.m3u8',
      ),
      isEmpty,
    );
    expect(
      buildFeiniuAccessCodeHeadersForUrl(
        accessCode: '123456',
        baseUrl: 'https://nas.example.test:5667',
        url: 'https://cdn.example.test/video.m3u8',
      ),
      isEmpty,
    );
  });

  test('识别飞牛访问码 HTML，不误判普通 JSON', () {
    expect(
      isFeiniuAccessCodeChallengeHtml(
        '<input id="access-code-input"><script>fetch("/access_code_verify")</script>',
      ),
      isTrue,
    );
    expect(isFeiniuAccessCodeChallengeHtml('{"code":-2}'), isFalse);
  });

  test('Dio 拦截器把缺失和错误访问码转换为稳定哨兵', () async {
    final requiredDio = Dio(BaseOptions(baseUrl: 'https://nas.example.test'))
      ..httpClientAdapter = _BodyAdapter(200, 'text/html',
          '<input id="access-code-input"><script>/access_code_verify</script>');
    installFeiniuAccessCodeInterceptor(
      requiredDio,
      baseUrl: 'https://nas.example.test',
      accessCodeProvider: () => '',
    );
    await expectLater(
      requiredDio.get<Object?>('/v/api/v1/login'),
      throwsA(
        isA<DioException>().having(
          (error) => error.message,
          'message',
          feiniuAccessCodeRequiredSentinel,
        ),
      ),
    );

    final invalidDio = Dio(BaseOptions(baseUrl: 'https://nas.example.test'))
      ..httpClientAdapter = _BodyAdapter(401, 'text/html', '');
    installFeiniuAccessCodeInterceptor(
      invalidDio,
      baseUrl: 'https://nas.example.test',
      accessCodeProvider: () => 'wrong',
    );
    await expectLater(
      invalidDio.get<Object?>('/v/api/v1/login'),
      throwsA(
        isA<DioException>().having(
          (error) => error.message,
          'message',
          feiniuAccessCodeInvalidSentinel,
        ),
      ),
    );
  });
}
```

测试 adapter 使用以下完整实现，不访问网络：

```dart
class _BodyAdapter implements HttpClientAdapter {
  _BodyAdapter(this.status, this.contentType, this.body);

  final int status;
  final String contentType;
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
```

- [ ] **Step 2: 运行测试并确认按预期失败**

Run: `flutter test test/api/feiniu_access_code_transport_test.dart`

Expected: FAIL，提示 `feiniu_access_code_transport.dart` 或目标函数尚不存在。

- [ ] **Step 3: 实现最小传输策略**

```dart
import 'dart:convert';

import 'package:dio/dio.dart';

const String feiniuAccessCodeRequiredSentinel =
    'feiniu_access_code_required';
const String feiniuAccessCodeInvalidSentinel =
    'feiniu_access_code_invalid';

Map<String, String> buildFeiniuAccessCodeHeaders(String accessCode) {
  final normalized = accessCode.trim();
  if (normalized.isEmpty) return const <String, String>{};
  return <String, String>{
    'x-access-code': base64Encode(utf8.encode(normalized)),
    'x-access-source': 'app',
  };
}

Map<String, String> buildFeiniuAccessCodeHeadersForUrl({
  required String accessCode,
  required String baseUrl,
  required String url,
}) {
  if (!isSameHttpOrigin(baseUrl, url)) return const <String, String>{};
  return buildFeiniuAccessCodeHeaders(accessCode);
}

bool isSameHttpOrigin(String baseUrl, String url) {
  final base = Uri.tryParse(baseUrl.trim());
  final target = Uri.tryParse(url.trim());
  if (base == null || base.host.isEmpty || target == null) return false;
  if (!target.hasScheme && target.host.isEmpty) return true;
  if (target.scheme != 'http' && target.scheme != 'https') return false;
  int effectivePort(Uri uri) =>
      uri.hasPort ? uri.port : (uri.scheme.toLowerCase() == 'https' ? 443 : 80);
  return base.scheme.toLowerCase() == target.scheme.toLowerCase() &&
      base.host.toLowerCase() == target.host.toLowerCase() &&
      effectivePort(base) == effectivePort(target);
}

bool isFeiniuAccessCodeChallengeHtml(Object? body) {
  if (body is! String) return false;
  final lower = body.toLowerCase();
  return lower.contains('access-code-input') &&
      lower.contains('/access_code_verify');
}
```

同文件实现 `installFeiniuAccessCodeInterceptor`：请求阶段按 `options.uri` 合并同源头；响应阶段识别挑战 HTML 并以 `feiniuAccessCodeRequiredSentinel` 拒绝；错误阶段仅在 `401/403/429 + text/html` 时改写为 `feiniuAccessCodeInvalidSentinel`，JSON 账号错误保持原样。

- [ ] **Step 4: 运行测试并确认通过**

Run: `flutter test test/api/feiniu_access_code_transport_test.dart`

Expected: PASS，4 个访问码传输策略测试全部通过。

- [ ] **Step 5: 提交**

```bash
git add lib/api/feiniu_access_code_transport.dart test/api/feiniu_access_code_transport_test.dart
git commit -m "feat: 添加飞牛访问码传输策略"
```

### Task 2：会话和登录历史安全存储

**Files:**
- Modify: `lib/providers/nas_provider.dart`
- Modify: `lib/services/login_history_store.dart`
- Modify: `test/providers/nas_provider_session_stability_test.dart`
- Modify: `test/services/login_history_store_test.dart`

- [ ] **Step 1: 写 NasProvider 访问码生命周期失败测试**

在 `nas_provider_session_stability_test.dart` 增加：

```dart
test('访问码按记住开关安全保存且不写普通偏好', () async {
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  final backend = _SwitchableCredentialBackend();
  SecureCredentialStore.setBackendForTesting(backend);
  addTearDown(SecureCredentialStore.resetBackendForTesting);
  final provider = NasProvider();
  addTearDown(provider.dispose);
  await provider.reloadSettingsForTesting();

  await provider.updateSettings(
    baseUrl: 'https://nas.example.test:5667',
    userName: 'alice',
    password: 'password',
    accessCode: '654321',
    rememberPassword: true,
    token: 'token',
  );

  final prefs = await SharedPreferences.getInstance();
  expect(provider.accessCode, '654321');
  expect(backend.values['nas_session.access_code'], '654321');
  expect(prefs.getString('access_code'), isNull);
  expect(prefs.getBool('nas_access_code_enabled'), isTrue);
});

test('不记住访问码时当前进程保留但新进程清除旧 token', () async {
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  final backend = _SwitchableCredentialBackend();
  SecureCredentialStore.setBackendForTesting(backend);
  addTearDown(SecureCredentialStore.resetBackendForTesting);
  final provider = NasProvider();
  await provider.reloadSettingsForTesting();
  await provider.updateSettings(
    baseUrl: 'https://nas.example.test:5667',
    userName: 'alice',
    password: 'password',
    accessCode: '654321',
    rememberPassword: false,
    token: 'token',
  );
  await provider.reloadSettingsForTesting();
  expect(provider.accessCode, '654321');
  expect(provider.token, 'token');
  expect(backend.values.containsKey('nas_session.access_code'), isFalse);

  NasProvider.resetBootstrapForTesting();
  provider.dispose();
  final restarted = NasProvider();
  addTearDown(restarted.dispose);
  await restarted.reloadSettingsForTesting();
  expect(restarted.accessCode, isEmpty);
  expect(restarted.token, isEmpty);
  expect(restarted.isConfigured, isFalse);
});
```

调整测试 teardown，避免同一个 provider 重复 `dispose`。

- [ ] **Step 2: 写登录历史访问码失败测试**

```dart
test('访问码只写安全存储且加载后回填', () async {
  final backend = MemorySecureCredentialBackend();
  SecureCredentialStore.setBackendForTesting(backend);
  addTearDown(SecureCredentialStore.resetBackendForTesting);

  await LoginHistoryStore.save(
    const LoginHistoryEntry(
      baseUrl: 'https://nas.example.test',
      userName: 'alice',
      password: 'password',
      accessCode: '654321',
      rememberPassword: true,
      updatedAtMillis: 1,
    ),
  );

  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getStringList('login_history_v1')!.single;
  expect(raw, isNot(contains('654321')));
  expect(raw, isNot(contains('accessCode')));
  expect((await LoginHistoryStore.load()).single.accessCode, '654321');
});
```

再增加删除、截断和清空测试：

```dart
test('删除截断和清空历史时同步删除访问码凭据', () async {
  final backend = _RecordingCredentialBackend();
  SecureCredentialStore.setBackendForTesting(backend);
  addTearDown(SecureCredentialStore.resetBackendForTesting);

  for (var index = 0; index < 11; index++) {
    await LoginHistoryStore.save(
      LoginHistoryEntry(
        baseUrl: 'https://nas-$index.example.test',
        userName: 'alice',
        password: 'password-$index',
        accessCode: 'code-$index',
        rememberPassword: true,
        updatedAtMillis: index,
      ),
    );
  }
  expect(backend.values.values, isNot(contains('code-0')));
  expect(backend.values.values, contains('code-10'));

  final newest = (await LoginHistoryStore.load()).first;
  await LoginHistoryStore.remove(newest);
  expect(backend.values.values, isNot(contains('code-10')));

  await LoginHistoryStore.clear();
  expect(backend.values, isEmpty);
});

class _RecordingCredentialBackend implements SecureCredentialBackend {
  final Map<String, String> values = <String, String>{};

  @override
  Future<SecureCredentialReadResult> read(String key) async {
    final value = values[key];
    return value == null
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

- [ ] **Step 3: 运行测试并确认失败**

Run: `flutter test test/providers/nas_provider_session_stability_test.dart test/services/login_history_store_test.dart`

Expected: FAIL，提示 `accessCode` getter/参数/字段不存在。

- [ ] **Step 4: 实现 NasProvider 会话状态**

在 `NasProvider` 增加：

```dart
static const String _accessCodeCredentialKey = 'nas_session.access_code';
String _accessCode = '';
String get accessCode => _accessCode;
```

`updateSettings` 增加 `String accessCode = ''`，始终把原值保留在 `_accessCode`；仅在 `rememberPassword` 为真时写 `_accessCodeCredentialKey`，否则删除。SharedPreferences 只写 `nas_access_code_enabled = accessCode.trim().isNotEmpty`。

加载规则必须同时满足：

```dart
final accessCodeEnabled =
    prefs.getBool('nas_access_code_enabled') ?? false;
final restoredAccessCode = rememberPassword
    ? await _restoreCredential(
        _accessCodeCredentialKey,
        legacyValue: '',
        currentValue: _accessCode,
        shouldKeep: true,
      )
    : (value: _accessCode, available: true);
```

如果访问码已启用、未记住且当前进程没有 `_accessCode`，清除恢复出的 token 与 resolvedBaseUrl，确保重启后回登录页。`_NasProviderBootstrapSnapshot` 增加 accessCode；登出时仅在未记住凭据时清空运行时 accessCode。

- [ ] **Step 5: 实现登录历史安全存储**

`LoginHistoryEntry` 增加：

```dart
final String accessCode;

const LoginHistoryEntry({
  this.kind = MediaBackendKind.feiniu,
  required this.baseUrl,
  required this.userName,
  required this.password,
  this.accessCode = '',
  required this.rememberPassword,
  required this.updatedAtMillis,
});
```

`toJson()` 不添加 accessCode。新增 `_accessCodeKey(entry)`，仅 `MediaBackendKind.feiniu` 读写该键；`save/remove/clear/截断` 与 password 对称处理。安全存储暂不可用时，将 password key 和 access-code key 分别加入保留集合，禁止误删。

- [ ] **Step 6: 运行测试并确认通过**

Run: `flutter test test/providers/nas_provider_session_stability_test.dart test/services/login_history_store_test.dart`

Expected: PASS，原有并发加载/凭据失败测试与新增访问码测试全部通过。

- [ ] **Step 7: 提交**

```bash
git add lib/providers/nas_provider.dart lib/services/login_history_store.dart test/providers/nas_provider_session_stability_test.dart test/services/login_history_store_test.dart
git commit -m "feat: 安全保存飞牛访问码会话"
```

### Task 3：FeiniuApi、FN Connect 与错误分类

**Files:**
- Modify: `lib/api/feiniu_api.dart`
- Modify: `lib/utils/login_error_resolver.dart`
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_zh_CN.arb`
- Modify: `lib/l10n/generated/app_localizations.dart`
- Modify: `lib/l10n/generated/app_localizations_zh.dart`
- Modify: `test/feiniu_api_fn_connect_test.dart`
- Modify: `test/login_error_resolver_test.dart`

- [ ] **Step 1: 写 API 头与第三方隔离失败测试**

在 `feiniu_api_fn_connect_test.dart` 增加捕获 RequestOptions 的测试：

```dart
test('普通 API 和播放同源 URL 携带访问码，第三方 URL 不携带', () async {
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  late RequestOptions captured;
  final adapter = _FakeDioAdapter((options) {
    captured = options;
    return ResponseBody.fromString(
      '{"code":0,"data":{}}',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  });
  final provider = NasProvider();
  addTearDown(provider.dispose);
  await provider.updateSettings(
    baseUrl: 'https://nas.example.test:5667',
    userName: 'alice',
    password: 'password',
    accessCode: '654321',
    token: 'token',
  );
  final api = FeiniuApi(provider, httpClientAdapter: adapter);

  await api.getUserInfo();
  expect(captured.headers['x-access-source'], 'app');
  expect(captured.headers['x-access-code'], isNotEmpty);
  expect(
    api.buildPlaybackHeadersForUrl(
      'https://nas.example.test:5667/v/api/v1/media/range/video',
    ),
    contains('x-access-code'),
  );
  expect(
    api.buildPlaybackHeadersForUrl('https://cdn.example.test/video.m3u8'),
    isNot(contains('x-access-code')),
  );
});
```

再增加同主机但 HTTP/HTTPS 不同的 URL 不携带 NAS token 与访问码的断言，锁定真正同源语义。

- [ ] **Step 2: 写访问码错误文案失败测试**

```dart
test('maps access-code sentinels before ordinary 401 credentials', () {
  expect(
    LoginErrorResolver.resolve(
      AppException.api(
        action: 'login',
        message: feiniuAccessCodeRequiredSentinel,
        httpStatus: 200,
      ),
    ),
    '该服务器需要访问码',
  );
  expect(
    LoginErrorResolver.resolve(
      AppException.api(
        action: 'login',
        message: feiniuAccessCodeInvalidSentinel,
        httpStatus: 401,
      ),
    ),
    '访问码错误或已失效',
  );
});
```

- [ ] **Step 3: 运行测试并确认失败**

Run: `flutter test test/feiniu_api_fn_connect_test.dart test/login_error_resolver_test.dart`

Expected: FAIL，普通 API 尚无访问码头，错误仍被归类为账号密码错误。

- [ ] **Step 4: 接入 FeiniuApi**

实现以下签名变化：

```dart
static Future<LoginWithBaseUrlResult> loginWithBaseUrl({
  required String baseUrl,
  required String userName,
  required String password,
  String accessCode = '',
})
```

`_loginWithFnConnect`、`_buildLoginDio`、`fetchFnConnectOauthConfig`、`loginWithFnConnectOauthCode` 同样接收 accessCode。FN Connect 官方发现请求 `/api/v1/fn/con` 不带访问码；只有候选 NAS baseUrl 和 OAuth NAS API 请求安装访问码拦截器。

实例 `_dio` 安装 Task 1 的拦截器，provider 为 `() => nasProvider.accessCode`。登录/公共 API Dio 使用传入值的闭包。`buildSignedHeadersForUrl` 在 token/Authx 之后合并同源访问码头；`_shouldAttachNasAuthToUrl` 增加 scheme 相等检查。

捕获挑战哨兵后保持 `AppException.message` 为稳定英文哨兵，不在 API 层硬编码中文。

- [ ] **Step 5: 在错误解析器中优先映射访问码哨兵**

在任何 `401/403` 账号判断之前加入：

```dart
if (message == feiniuAccessCodeRequiredSentinel) {
  return strings.loginErrorAccessCodeRequired;
}
if (message == feiniuAccessCodeInvalidSentinel) {
  return strings.loginErrorAccessCodeInvalid;
}
```

本步骤先引用 Task 4 将生成的 getter 名称；若编译器暂时报 getter 不存在，与 Task 4 同批完成后再运行整组测试。为保持每次提交可编译，可先在 ARB 中加入两个键并运行 `flutter gen-l10n`，Task 4 再加入表单键。

- [ ] **Step 6: 运行测试并确认通过**

Run: `flutter test test/feiniu_api_fn_connect_test.dart test/login_error_resolver_test.dart`

Expected: PASS，JSON `401` 仍映射用户名密码错误，HTML 网关错误映射访问码错误。

- [ ] **Step 7: 提交**

```bash
git add lib/api/feiniu_api.dart lib/utils/login_error_resolver.dart lib/l10n/app_zh.arb lib/l10n/app_zh_CN.arb lib/l10n/generated/app_localizations.dart lib/l10n/generated/app_localizations_zh.dart test/feiniu_api_fn_connect_test.dart test/login_error_resolver_test.dart
git commit -m "feat: 为飞牛 API 注入访问码"
```

### Task 4：登录 UI、历史回填和 FN Connect Web 交换

**Files:**
- Modify: `lib/screens/connection_screen.dart`
- Modify: `lib/screens/fn_connect_web_login_page.dart`
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_zh_CN.arb`
- Modify: `lib/l10n/generated/app_localizations.dart`
- Modify: `lib/l10n/generated/app_localizations_zh.dart`
- Modify: `test/screens/connection_feiniu_compatibility_test.dart`
- Modify: `test/connection_login_persistence_test.dart`

- [ ] **Step 1: 写表单与提交参数失败测试**

把 `connection_feiniu_compatibility_test.dart` 的 callback 类型增加 `required String accessCode`，并增加：

```dart
testWidgets('飞牛表单显示可选访问码并提交给登录回调', (tester) async {
  String? submittedAccessCode;
  await _pumpConnectionScreen(
    tester,
    baseUrl: 'https://nas.example.test:5667',
    feiniuLogin: ({
      required baseUrl,
      required userName,
      required password,
      required accessCode,
    }) async {
      submittedAccessCode = accessCode;
      return LoginWithBaseUrlResult(
        token: 'token',
        resolvedBaseUrl: baseUrl,
      );
    },
  );

  expect(find.text('访问码（可选）'), findsOneWidget);
  await tester.enterText(find.byKey(const Key('feiniuAccessCodeField')), '654321');
  await tester.tap(find.text('登录'));
  await tester.pumpAndSettle();
  expect(submittedAccessCode, '654321');
});
```

更新原“3 个 TextField”断言为飞牛 4 个；切换 Emby 后仍只有地址、用户名、密码 3 个可交互字段，并验证登录按钮 Y 坐标不抖动。

- [ ] **Step 2: 运行测试并确认失败**

Run: `flutter test test/screens/connection_feiniu_compatibility_test.dart test/connection_login_persistence_test.dart`

Expected: FAIL，找不到访问码字段或 callback 参数。

- [ ] **Step 3: 实现表单与持久化传递**

`FeiniuLoginCallback` 增加 `required String accessCode`。`_ConnectionScreenState` 增加 `_accessCodeController` 和 `_obscureAccessCode`，从 `NasProvider.accessCode` 初始化并在 dispose 释放。

为 `_GlassField` 构造器增加 `super.key`，使测试和无障碍定位能够稳定命中访问码字段。

飞牛表单在密码字段后渲染：

```dart
_GlassField(
  key: const Key('feiniuAccessCodeField'),
  controller: _accessCodeController,
  labelText: l10n.connectionAccessCodeOptional,
  hintText: '',
  leadingIcon: Icons.key_rounded,
  obscureText: _obscureAccessCode,
  textInputAction: TextInputAction.done,
  onSubmitted: (_) => _submit(),
  suffix: IconButton(
    onPressed: () => setState(
      () => _obscureAccessCode = !_obscureAccessCode,
    ),
    icon: Icon(
      _obscureAccessCode
          ? Icons.visibility_off_outlined
          : Icons.visibility_outlined,
    ),
  ),
)
```

服务器族表单在同一位置放等高 `SizedBox`，保持 AnimatedSwitcher 面板和登录按钮位置一致。提交时不要求非空；`_applyLoginResult` 同时传给 `NasProvider.updateSettings` 和 `LoginHistoryEntry`；选择飞牛历史时回填 accessCode，选择服务器族历史时清空飞牛访问码控制器。

- [ ] **Step 4: 传递 FN Connect Web 参数**

`FnConnectWebLoginPage` 增加默认值为空的 `accessCode` 字段；`_tryFnConnectWebFallback` 从控制器传入。页面调用 `fetchFnConnectOauthConfig` 和 `loginWithFnConnectOauthCode` 时都传 `widget.accessCode`。WebView 官方页面本身不注入访问码，避免把 NAS 凭据发给 `5ddd.com`/`fnos.net` 官方入口。

- [ ] **Step 5: 增加文案并生成本地化代码**

两个 ARB 同时加入：

```json
"connectionAccessCodeOptional": "访问码（可选）",
"loginErrorAccessCodeRequired": "该服务器需要访问码",
"loginErrorAccessCodeInvalid": "访问码错误或已失效"
```

Run: `flutter gen-l10n`

Expected: `app_localizations.dart` 与 `app_localizations_zh.dart` 更新且无生成错误。

- [ ] **Step 6: 运行测试并确认通过**

Run: `flutter test test/screens/connection_feiniu_compatibility_test.dart test/screens/connection_backend_selection_test.dart test/connection_login_persistence_test.dart test/login_error_resolver_test.dart`

Expected: PASS，飞牛有访问码字段，服务器族布局与行为不回归。

- [ ] **Step 7: 提交**

```bash
git add lib/screens/connection_screen.dart lib/screens/fn_connect_web_login_page.dart lib/l10n/app_zh.arb lib/l10n/app_zh_CN.arb lib/l10n/generated/app_localizations.dart lib/l10n/generated/app_localizations_zh.dart test/screens/connection_feiniu_compatibility_test.dart test/connection_login_persistence_test.dart
git commit -m "feat: 添加飞牛访问码登录字段"
```

### Task 5：Flutter 图片、主题取色和下载请求

**Files:**
- Modify: `lib/utils/nas_image_headers.dart`
- Modify: `lib/ui/detail_artwork_resolver.dart`
- Modify: `lib/theme/dynamic_theme_seed_extractor.dart`
- Modify: `lib/services/download_task_service.dart`
- Modify: `test/nas_image_headers_test.dart`
- Modify: `test/ui/detail_artwork_resolver_test.dart`
- Create: `test/theme/dynamic_theme_seed_extractor_headers_test.dart`
- Modify call sites: `lib/pages/media_collection_detail_page.dart`, `lib/pages/play_detail_page.dart`, `lib/pages/tv_detail_page.dart`, `lib/pages/tv_season_detail_page.dart`, `lib/screens/favorite_items_screen.dart`, `lib/screens/media_list_screen.dart`, `lib/screens/poster_browse/poster_browse_screen.dart`, `lib/screens/category_items_screen.dart`, `lib/screens/person_detail_screen.dart`, `lib/screens/search_screen.dart`, `lib/screens/download_list_screen.dart`, `lib/screens/media_list_screen_widgets.dart`, `lib/ui/adaptive_detail_navigator.dart`, `lib/widgets/library/media_collection_browser.dart`, `lib/widgets/detail/tv_season_download_sheet.dart`, `lib/widgets/detail/tv_season_detail_panel.dart`, `lib/widgets/detail/tv_episode_picker_sheet.dart`, `lib/widgets/detail/tv_episode_browser_section.dart`

- [ ] **Step 1: 写图片同源头失败测试**

```dart
test('NAS 图片头合并同源访问码且不发送给第三方', () {
  final sameOrigin = nasImageHeaders(
    'token',
    accessCode: '654321',
    baseUrl: 'https://nas.example.test:5667',
    url: 'https://nas.example.test:5667/v/api/v1/media/p/image',
  );
  expect(sameOrigin, contains('x-access-code'));
  expect(sameOrigin, containsPair('x-access-source', 'app'));

  final external = nasImageHeaders(
    'token',
    accessCode: '654321',
    baseUrl: 'https://nas.example.test:5667',
    url: 'https://cdn.example.test/image.jpg',
  );
  expect(external, isNot(contains('x-access-code')));
});
```

`detail_artwork_resolver_test.dart` 用 `DetailArtworkResolver(baseUrl, token, accessCode)` 断言相对路径图片带访问码，完整 Emby `api_key` URL 不带。

- [ ] **Step 2: 写 Android 主题通道完整头失败测试**

创建 widget test，设置 `debugDefaultTargetPlatformOverride = TargetPlatform.android`，为 `fly_player/theme_sampler` 注册 mock handler，调用：

```dart
await DynamicThemeSeedExtractor.extract(
  imageUrl: 'https://nas.example.test/poster.jpg',
  imageHeaders: const <String, String>{
    'Authorization': 'token',
    'x-access-code': 'encoded-code',
    'x-access-source': 'app',
  },
);
```

mock 返回至少 4 个不透明 ARGB 像素；断言 MethodCall arguments 的 `headers` 完整等于传入映射，且不再只有 `token`。

- [ ] **Step 3: 运行测试并确认失败**

Run: `flutter test test/nas_image_headers_test.dart test/ui/detail_artwork_resolver_test.dart test/theme/dynamic_theme_seed_extractor_headers_test.dart`

Expected: FAIL，图片工具和主题通道尚未接受 accessCode/headers。

- [ ] **Step 4: 实现图片头 API**

`nasImageHeaders` 改为：

```dart
Map<String, String> nasImageHeaders(
  String token, {
  String? url,
  String accessCode = '',
  String baseUrl = '',
}) {
  final headers = <String, String>{};
  final trimmedToken = token.trim();
  if (trimmedToken.isNotEmpty) {
    headers['Authorization'] = trimmedToken;
    headers['Trim-MC-token'] = trimmedToken;
  }
  headers.addAll(
    buildFeiniuAccessCodeHeadersForUrl(
      accessCode: accessCode,
      baseUrl: baseUrl,
      url: url ?? '',
    ),
  );
  if (usesFnConnectRelayCookie(url) && trimmedToken.isNotEmpty) {
    headers['Cookie'] = 'mode=relay';
  }
  return headers;
}
```

`mediaImageRequestForUrls`、`preferPreservedImageRequest` 和 `DetailArtworkResolver` 增加 accessCode/baseUrl 参数，并始终经上述函数构造飞牛图片头。

- [ ] **Step 5: 逐层传播图片凭据**

对本任务 Files 中列出的全部调用点执行统一变换：

```dart
mediaImageRequestForUrls(
  urls,
  token: nas.token,
  accessCode: nas.accessCode,
  baseUrl: nas.baseUrl,
)
```

已有 `DetailArtworkResolver` 的位置统一为：

```dart
DetailArtworkResolver(
  baseUrl: nas.baseUrl,
  token: nas.token,
  accessCode: nas.accessCode,
)
```

若中间 widget/controller 目前只接收 `token`，同时增加 `accessCode` 与 `baseUrl` 两个 required 参数并从其持有 `NasProvider` 的最近上游传入。Emby/Jellyfin 分支传空字符串，不读取 NasProvider 残留凭据。完成后运行 `rg -n "mediaImageRequestForUrls\(|DetailArtworkResolver\(" lib`，逐项确认飞牛分支均传 accessCode/baseUrl。

- [ ] **Step 6: 主题取色通道传完整头**

`DynamicThemeSeedExtractor._samplePixelsOnAndroid` 的 MethodChannel 参数改为：

```dart
<String, dynamic>{
  'imageUrl': imageUrl,
  'headers': imageHeaders,
}
```

不再从 Authorization 单独提 token。

- [ ] **Step 7: 下载恢复封面使用统一头**

`DownloadTaskService` 中手工创建 Dio 下载封面的代码改为：

```dart
final headers = FeiniuApi(provider).buildSignedHeadersForUrl(
  firstUrl,
  includeInitialRangeHeader: false,
);
final response = await Dio().get<List<int>>(
  firstUrl,
  options: Options(
    responseType: ResponseType.bytes,
    headers: headers,
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 15),
    validateStatus: (status) => status == 200,
  ),
);
```

其他两处已经调用 `buildPlaybackHeadersForUrl` 的下载路径只增加测试断言，不重复实现。

- [ ] **Step 8: 运行测试和静态分析**

Run: `flutter test test/nas_image_headers_test.dart test/ui/detail_artwork_resolver_test.dart test/theme/dynamic_theme_seed_extractor_headers_test.dart`

Run: `flutter analyze`

Expected: 测试 PASS；analyze 不出现遗漏参数、未使用字段或类型错误。

- [ ] **Step 9: 提交**

```bash
git add lib/utils/nas_image_headers.dart lib/ui/detail_artwork_resolver.dart lib/theme/dynamic_theme_seed_extractor.dart lib/services/download_task_service.dart lib/pages lib/screens lib/ui/adaptive_detail_navigator.dart lib/widgets test/nas_image_headers_test.dart test/ui/detail_artwork_resolver_test.dart test/theme/dynamic_theme_seed_extractor_headers_test.dart
git commit -m "feat: 为飞牛图片和下载透传访问码"
```

### Task 6：Flutter 到 Android 的原生图片头

**Files:**
- Modify: `lib/controllers/item_playback_launcher.dart`
- Modify: `lib/services/native_reentry_support.dart`
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/FlutterHostActivity.kt`
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/ThemeColorSampler.kt`
- Create: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativeImageRequestHeaders.kt`
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativePlayerActivity.kt`
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativePlaybackMediaService.kt`
- Create: `android/app/src/test/kotlin/com/geqian/flyplayer/fly_player/NativeImageRequestHeadersTest.kt`

- [ ] **Step 1: 写纯 Kotlin 图片头转换失败测试**

```kotlin
package com.geqian.flyplayer.fly_player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class NativeImageRequestHeadersTest {
    @Test
    fun `map and intent flat list preserve access-code headers`() {
        val headers = NativeImageRequestHeaders.fromAny(
            mapOf(
                "Authorization" to "token",
                "x-access-code" to "encoded-code",
                "x-access-source" to "app",
            ),
        )
        val restored = NativeImageRequestHeaders.fromFlatList(
            NativeImageRequestHeaders.toFlatList(headers),
        )
        assertEquals(headers, restored)
    }

    @Test
    fun `blank and unsafe header entries are discarded`() {
        val headers = NativeImageRequestHeaders.fromAny(
            mapOf("" to "x", "Connection" to "keep-alive", "X-Test" to "ok"),
        )
        assertFalse(headers.containsKey(""))
        assertFalse(headers.keys.any { it.equals("Connection", ignoreCase = true) })
        assertEquals("ok", headers["X-Test"])
    }
}
```

- [ ] **Step 2: 运行测试并确认失败**

Run from `android`: `.\gradlew.bat testFullDebugUnitTest --tests "com.geqian.flyplayer.fly_player.NativeImageRequestHeadersTest"`

Expected: FAIL，`NativeImageRequestHeaders` 尚不存在。

- [ ] **Step 3: 实现原生图片头工具**

`NativeImageRequestHeaders` 使用以下纯 Kotlin 实现：

```kotlin
object NativeImageRequestHeaders {
    private val blocked = setOf(
        "connection",
        "host",
        "keep-alive",
        "proxy-authenticate",
        "proxy-authorization",
        "te",
        "trailer",
        "transfer-encoding",
        "upgrade",
    )

    fun fromAny(raw: Any?): Map<String, String> {
        val source = raw as? Map<*, *> ?: return emptyMap()
        return buildMap {
            source.forEach { (rawKey, rawValue) ->
                val key = rawKey?.toString()?.trim().orEmpty()
                val value = rawValue?.toString()?.trim().orEmpty()
                if (key.isNotEmpty() && value.isNotEmpty() && key.lowercase() !in blocked) {
                    put(key, value)
                }
            }
        }
    }

    fun toFlatList(headers: Map<String, String>): ArrayList<String> =
        ArrayList<String>(headers.size * 2).apply {
            fromAny(headers).forEach { (key, value) ->
                add(key)
                add(value)
            }
        }

    fun fromFlatList(values: ArrayList<String>?): Map<String, String> {
        if (values.isNullOrEmpty()) return emptyMap()
        val pairs = linkedMapOf<String, String>()
        var index = 0
        while (index + 1 < values.size) {
            pairs[values[index]] = values[index + 1]
            index += 2
        }
        return fromAny(pairs)
    }

    fun legacyAuth(token: String): Map<String, String> {
        val normalized = token.trim()
        if (normalized.isEmpty()) return emptyMap()
        return mapOf(
            "Authorization" to normalized,
            "Trim-MC-token" to normalized,
        )
    }
}
```

扁平列表按 key/value 交替存储，避免 JSON 和 Android JVM stub；过滤空 key/value 以及 `Connection`、`Host`、`Transfer-Encoding` 等 hop-by-hop 头。`legacyAuth` 仅为旧 loadArgs 兼容生成 Authorization/Trim-MC-token。

- [ ] **Step 4: Flutter 原生选集数据增加 imageHeaders**

`ItemPlaybackLauncher.loadSeasonEpisodes` 与 `NativeReentrySupport._nativeEpisodeMap` 对 NAS 海报 URL 调用：

```dart
final imageHeaders = usingLocal
    ? const <String, String>{}
    : nasImageHeaders(
        nas.token,
        url: poster,
        accessCode: nas.accessCode,
        baseUrl: nas.baseUrl,
      );
```

每集同时输出 `'imageHeaders': imageHeaders` 和旧 `'imageAuth'`，后者暂留一版兼容；本地封面两者均为空。

- [ ] **Step 5: 主题采样接收完整头**

`FlutterHostActivity` 从 call arguments 读取 `headers` Map，经 `NativeImageRequestHeaders.fromAny` 后传给：

```kotlin
ThemeColorSampler.samplePixels(imageUrl, headers) { sampled ->
    result.success(sampled)
}
```

`ThemeColorSampler.samplePixels/sampleInternal` 的 token 参数改为 `Map<String, String>`，OkHttp Request.Builder 遍历安全头添加，不再自行拼两个 token 头。

- [ ] **Step 6: 播放 Activity 和媒体服务使用完整图片头**

`currentArtwork()` 返回 `Pair<String, Map<String, String>>`；优先解析当前 episode 的 `imageHeaders`，为空时回退旧 `imageAuth`。选集面板、听视频、播放完成页共用一个 `artworkGlideModel(url, headers)`，用 `LazyHeaders.Builder` 遍历添加。

`NativePlaybackMediaService.update` 把 `artworkAuth` 参数替换为 `artworkHeaders`。Intent 用 `putStringArrayListExtra` 保存 `toFlatList(headers)`，`SessionState.fromIntent` 用 `fromFlatList` 恢复。封面缓存键使用 `"${artworkUrl}|${artworkHeaders.hashCode()}"`，不得拼接头原文。

- [ ] **Step 7: 运行 Kotlin 与 Flutter 相关测试**

Run from `android`: `.\gradlew.bat testFullDebugUnitTest --tests "com.geqian.flyplayer.fly_player.NativeImageRequestHeadersTest"`

Run from repository root: `flutter test test/services/native_reentry_support_test.dart test/services/server_native_picker_support_test.dart test/theme/dynamic_theme_seed_extractor_headers_test.dart`

Expected: 全部 PASS，Kotlin 编译确认 Activity/Service 签名一致。

- [ ] **Step 8: 提交**

```bash
git add lib/controllers/item_playback_launcher.dart lib/services/native_reentry_support.dart android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/FlutterHostActivity.kt android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/ThemeColorSampler.kt android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativeImageRequestHeaders.kt android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativePlayerActivity.kt android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativePlaybackMediaService.kt android/app/src/test/kotlin/com/geqian/flyplayer/fly_player/NativeImageRequestHeadersTest.kt
git commit -m "feat: 为原生飞牛图片透传访问码"
```

### Task 7：原生 mpv 代理转发策略

**Files:**
- Create: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/mpv/NativeProxyHeaderPolicy.kt`
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/mpv/NativeMpvProxyServer.kt`
- Create: `android/app/src/test/kotlin/com/geqian/flyplayer/fly_player/mpv/NativeProxyHeaderPolicyTest.kt`

- [ ] **Step 1: 写访问码保留与危险头阻断失败测试**

```kotlin
package com.geqian.flyplayer.fly_player.mpv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class NativeProxyHeaderPolicyTest {
    @Test
    fun `proxy preserves access-code headers`() {
        val forwarded = NativeProxyHeaderPolicy.copyForwardable(
            mapOf(
                "x-access-code" to "encoded-code",
                "x-access-source" to "app",
                "Connection" to "keep-alive",
                "Authorization" to "old-token",
                "Authx" to "stale-sign",
            ),
        )
        assertEquals("encoded-code", forwarded["x-access-code"])
        assertEquals("app", forwarded["x-access-source"])
        assertFalse(forwarded.keys.any { it.equals("Connection", true) })
        assertFalse(forwarded.keys.any { it.equals("Authorization", true) })
        assertFalse(forwarded.keys.any { it.equals("Authx", true) })
    }
}
```

- [ ] **Step 2: 运行测试并确认失败**

Run from `android`: `.\gradlew.bat testFullDebugUnitTest --tests "com.geqian.flyplayer.fly_player.mpv.NativeProxyHeaderPolicyTest"`

Expected: FAIL，策略对象尚不存在。

- [ ] **Step 3: 提取并接入策略**

`NativeProxyHeaderPolicy` 使用以下实现，返回保留原始大小写的 LinkedHashMap：

```kotlin
package com.geqian.flyplayer.fly_player.mpv

import java.util.Locale

object NativeProxyHeaderPolicy {
    private val rebuiltOrBlocked = setOf(
        "authorization",
        "trim-mc-token",
        "user-agent",
        "range",
        "authx",
        "host",
        "connection",
        "keep-alive",
        "transfer-encoding",
        "te",
        "trailer",
        "upgrade",
        "proxy-authenticate",
        "proxy-authorization",
        "proxy-connection",
    )

    fun copyForwardable(headers: Map<String, String>): Map<String, String> =
        buildMap {
            headers.forEach { (key, value) ->
                if (key.isBlank() || value.isBlank()) return@forEach
                if (key.lowercase(Locale.US) in rebuiltOrBlocked) return@forEach
                put(key, value)
            }
        }
}
```

`buildSignedHeaders` 改为先遍历策略结果，再重建 Authorization、Trim-MC-token、User-Agent、Range 和 Authx。访问码头不是 hop-by-hop 头，必须原样保留。

- [ ] **Step 4: 运行测试并确认通过**

Run from `android`: `.\gradlew.bat testFullDebugUnitTest --tests "com.geqian.flyplayer.fly_player.mpv.NativeProxyHeaderPolicyTest"`

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/mpv/NativeProxyHeaderPolicy.kt android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/mpv/NativeMpvProxyServer.kt android/app/src/test/kotlin/com/geqian/flyplayer/fly_player/mpv/NativeProxyHeaderPolicyTest.kt
git commit -m "refactor: 固化原生代理请求头策略"
```

### Task 8：全量回归、构建与真实服务验收

**Files:**
- Modify only if verification exposes a defect in files already listed above.

- [ ] **Step 1: 运行访问码定向 Flutter 测试**

Run:

```bash
flutter test test/api/feiniu_access_code_transport_test.dart test/feiniu_api_fn_connect_test.dart test/providers/nas_provider_session_stability_test.dart test/services/login_history_store_test.dart test/screens/connection_feiniu_compatibility_test.dart test/login_error_resolver_test.dart test/nas_image_headers_test.dart test/ui/detail_artwork_resolver_test.dart test/theme/dynamic_theme_seed_extractor_headers_test.dart
```

Expected: PASS，0 failures。

- [ ] **Step 2: 运行 Android 单元测试**

Run from `android`: `.\gradlew.bat testFullDebugUnitTest`

Expected: BUILD SUCCESSFUL，0 failed tests。

- [ ] **Step 3: 运行全部 Flutter 测试与静态分析**

Run: `flutter test`

Run: `flutter analyze`

Expected: 全部测试通过；analyze 无 error/warning。

- [ ] **Step 4: 构建 Debug APK**

Run: `flutter build apk --debug`

Expected: exit code 0，生成 Debug APK。

- [ ] **Step 5: 使用临时环境变量执行真实服务协议验收**

在当前 PowerShell 进程设置 `FLY_NAS_URL`、`FLY_NAS_USER`、`FLY_NAS_PASSWORD`、`FLY_NAS_ACCESS_CODE`，不得写入文件或 shell 历史脚本。验证脚本只输出：访问码头是否生成、登录 HTTP 状态、业务码、token 是否非空、受保护 API Content-Type 和业务码；不得输出任一变量或 token。

验收顺序：

```text
1. 不带访问码请求登录路径，确认命中 HTML 挑战页。
2. 带错误访问码请求，确认 HTTP 401/403/429 被识别为访问码错误。
3. 带正确访问码和 NAS 凭据登录，确认业务码 0、token 非空。
4. 带访问码、token 和正确 Authx 请求 /v/api/v1/user/info，确认 JSON 业务码 0。
5. 从用户信息或媒体列表取得一个同源图片 URL，只发起小范围读取，确认不是访问码 HTML。
```

Expected: 五项均满足，控制台无敏感值。

- [ ] **Step 6: 检查凭据泄漏与变更范围**

Run:

```powershell
git diff --check
$sensitiveValues = @(
  $env:FLY_NAS_URL,
  $env:FLY_NAS_USER,
  $env:FLY_NAS_PASSWORD,
  $env:FLY_NAS_ACCESS_CODE
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
$featureDiff = git diff 'cfbc9ad^' -- . | Out-String
foreach ($value in $sensitiveValues) {
  if ($featureDiff.Contains($value, [System.StringComparison]::Ordinal)) {
    throw '检测到真实验收凭据进入本功能变更'
  }
}
git status --short
```

Expected: `git diff --check` 无输出；敏感值扫描无匹配；status 只包含本功能预期文件和用户原有未跟踪文件。若验证暴露缺陷，回到对应 Task 按 RED → GREEN 修正、重跑该 Task 验证，并使用该 Task 已列出的精确 `git add` 文件清单提交；没有修正时不创建空提交。

## 完成条件

- 每个新增行为都经历 RED → GREEN；
- 访问码不进入普通偏好、日志、缓存键、测试夹具或 Git 历史；
- 同源飞牛 API、图片、下载、字幕、播放、选集和原生封面均带访问码头；
- 第三方 URL、Emby/Jellyfin 和 FN Connect 官方发现接口不带访问码；
- Flutter 全测、Android 全测、analyze 和 Debug APK 构建均通过；
- 真实服务登录和受保护读取验证通过且输出已脱敏。
