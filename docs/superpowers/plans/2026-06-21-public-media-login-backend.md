# 登录页后端选择 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不破坏现有飞牛登录/播放体验的前提下，为登录页和配置层加入后端类型选择，并为 Emby 只读连接验证留下干净入口。

**Architecture:** 新增中立 backend connection/session 模型与 store，保留 `NasProvider` 作为飞牛兼容壳。登录页按后端类型选择不同 handler，业务页面继续只依赖 `MediaBackendProvider` 与 `MediaBackend`，不写 UI 级 `if (isEmby)`。

**Tech Stack:** Flutter、Provider、SharedPreferences、Dart unit/widget tests、现有 `FeiniuApi` / `MediaBackend` 抽象。

---

## 文件结构

- Modify: `test/connection_login_persistence_test.dart`
  - 先补飞牛登录页保存语义和兼容性测试，作为后续改造护栏。
- Create: `test/screens/connection_feiniu_compatibility_test.dart`
  - 锁住飞牛登录页默认表单、历史入口、HTTPS 开关、FN Connect 重登入口。
- Create: `lib/media_backend/session/media_backend_connection.dart`
  - 后端中立连接快照模型，字段不带 Feiniu/Emby 私有命名。
- Create: `lib/services/media_backend_connection_store.dart`
  - 读写 `media_backend_active_kind_v1` 和 `media_backend_connections_v1`，兼容旧飞牛 prefs。
- Create: `lib/providers/backend_session_provider.dart`
  - 暴露当前后端类型、连接状态和切换能力；默认从旧飞牛配置恢复。
- Modify: `lib/providers/media_backend_provider.dart`
  - 后续从 `BackendSessionProvider` 选择 backend factory；第一阶段仍只创建 Feiniu backend。
- Modify: `lib/main.dart`
  - 注入 `BackendSessionProvider`；`_ProviderGate` 后续改读中立 gate，Feiniu 旧路径保持默认。
- Modify: `lib/screens/connection_screen.dart`
  - 抽出 Feiniu 登录 handler；加入后端类型选择；后续加入 Emby 只读验证入口。
- Modify: `lib/services/login_history_store.dart`
  - 增加 v2 历史结构，带 `backendKind`；v1 作为 Feiniu 历史兼容读入。
- Modify: `lib/services/storage_management_service.dart`
  - 把新连接 key / 历史 key 纳入存储清理视图。
- Test: `test/media_backend/media_backend_connection_test.dart`
- Test: `test/services/media_backend_connection_store_test.dart`
- Test: `test/services/login_history_store_test.dart`
- Test: `test/connection_login_persistence_test.dart`
- Test: `test/screens/connection_backend_selection_test.dart`

## Task 0: 飞牛登录页兼容护栏

**Files:**
- Modify: `test/connection_login_persistence_test.dart`
- Create: `test/screens/connection_feiniu_compatibility_test.dart`

- [ ] **Step 1: 扩展保存语义测试**

在 `test/connection_login_persistence_test.dart` 保留现有 `effectivePersistedBaseUrlForLogin` 用例，并新增“普通直连不受后端选择影响”的用例：

```dart
test('普通直连登录保存源地址，作为飞牛兼容基线', () {
  const result = LoginWithBaseUrlResult(
    token: 'fake-feiniu-token',
    resolvedBaseUrl: 'https://nas.example.test:5667',
  );

  expect(
    effectivePersistedBaseUrlForLogin(
      sourceBaseUrl: 'nas.example.test:5667',
      loginResult: result,
    ),
    'nas.example.test:5667',
  );
});
```

- [ ] **Step 2: 新增登录页兼容 widget test**

测试当前默认飞牛表单必须继续出现这些控件：

```dart
testWidgets('飞牛登录页默认保留历史、HTTPS、FN Connect 和下载入口', (tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'base_url': 'https://nas.example.test',
    'user_name': 'alice',
    'password': 'secret',
    'remember_password': true,
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NasProvider()),
      ],
      child: const MaterialApp(home: ConnectionScreen()),
    ),
  );
  await tester.pumpAndSettle();

  expect(find.text('重新登录 FN Connect'), findsOneWidget);
  expect(find.byIcon(Icons.history_rounded), findsOneWidget);
  expect(find.byType(Switch), findsOneWidget);
  expect(find.textContaining('下载'), findsOneWidget);
});
```

如果本测试因本地化文案不同失败，改用现有 `AppLocalizations` 包装或按实际 widget key/图标断言，不修改生产行为来迎合测试。

- [ ] **Step 3: 运行兼容测试确认通过**

Run: `flutter test test/connection_login_persistence_test.dart test/screens/connection_feiniu_compatibility_test.dart`

Expected: PASS。若 widget harness 缺少本地化或 theme provider，先补测试 wrapper，不改登录页行为。

- [ ] **Step 4: 提交**

```bash
git add test/connection_login_persistence_test.dart test/screens/connection_feiniu_compatibility_test.dart
git commit -m "test: lock feiniu connection screen compatibility"
```

## Task 1: 中立连接模型

**Files:**
- Create: `lib/media_backend/session/media_backend_connection.dart`
- Test: `test/media_backend/media_backend_connection_test.dart`

- [ ] **Step 1: 写模型单测**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/media_backend/session/media_backend_connection.dart';

void main() {
  test('connection serializes neutral fields', () {
    const connection = MediaBackendConnection(
      kind: MediaBackendKind.emby,
      serverUrl: 'https://media.example.test',
      displayName: 'Home Media',
      userName: 'alice',
      userId: 'user-1',
      accessToken: 'token',
      rememberSecret: false,
      updatedAtMillis: 123,
    );

    expect(connection.isAuthenticated, isTrue);
    expect(connection.toJson(), <String, Object?>{
      'kind': 'emby',
      'serverUrl': 'https://media.example.test',
      'displayName': 'Home Media',
      'userName': 'alice',
      'userId': 'user-1',
      'accessToken': 'token',
      'rememberSecret': false,
      'updatedAtMillis': 123,
    });
    expect(
      MediaBackendConnection.fromJson(connection.toJson()),
      connection,
    );
  });

  test('empty token is not authenticated', () {
    const connection = MediaBackendConnection(
      kind: MediaBackendKind.feiniu,
      serverUrl: 'https://nas.example.test',
    );

    expect(connection.isAuthenticated, isFalse);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/media_backend/media_backend_connection_test.dart`

Expected: FAIL，提示找不到 `MediaBackendConnection`。

- [ ] **Step 3: 实现模型**

```dart
import '../media_backend_kind.dart';

class MediaBackendConnection {
  const MediaBackendConnection({
    required this.kind,
    required this.serverUrl,
    this.displayName = '',
    this.userName = '',
    this.userId = '',
    this.accessToken = '',
    this.rememberSecret = true,
    this.updatedAtMillis = 0,
  });

  final MediaBackendKind kind;
  final String serverUrl;
  final String displayName;
  final String userName;
  final String userId;
  final String accessToken;
  final bool rememberSecret;
  final int updatedAtMillis;

  bool get isAuthenticated =>
      serverUrl.trim().isNotEmpty && accessToken.trim().isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'serverUrl': serverUrl,
    'displayName': displayName,
    'userName': userName,
    'userId': userId,
    'accessToken': accessToken,
    'rememberSecret': rememberSecret,
    'updatedAtMillis': updatedAtMillis,
  };

  factory MediaBackendConnection.fromJson(Map<String, Object?> json) {
    final kindName = (json['kind'] ?? '').toString();
    final kind = MediaBackendKind.values.firstWhere(
      (value) => value.name == kindName,
      orElse: () => MediaBackendKind.feiniu,
    );
    return MediaBackendConnection(
      kind: kind,
      serverUrl: (json['serverUrl'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      userName: (json['userName'] ?? '').toString(),
      userId: (json['userId'] ?? '').toString(),
      accessToken: (json['accessToken'] ?? '').toString(),
      rememberSecret: json['rememberSecret'] != false,
      updatedAtMillis: (json['updatedAtMillis'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaBackendConnection &&
          other.kind == kind &&
          other.serverUrl == serverUrl &&
          other.displayName == displayName &&
          other.userName == userName &&
          other.userId == userId &&
          other.accessToken == accessToken &&
          other.rememberSecret == rememberSecret &&
          other.updatedAtMillis == updatedAtMillis;

  @override
  int get hashCode => Object.hash(
    kind,
    serverUrl,
    displayName,
    userName,
    userId,
    accessToken,
    rememberSecret,
    updatedAtMillis,
  );
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/media_backend/media_backend_connection_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/media_backend/session/media_backend_connection.dart test/media_backend/media_backend_connection_test.dart
git commit -m "feat: add media backend connection model"
```

## Task 2: 连接 store 与旧飞牛配置兼容

**Files:**
- Create: `lib/services/media_backend_connection_store.dart`
- Test: `test/services/media_backend_connection_store_test.dart`

- [ ] **Step 1: 写 store 单测**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/services/media_backend_connection_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('defaults to Feiniu when legacy prefs exist', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://nas.example.test',
      'user_name': 'alice',
      'token': 'feiniu-token',
      'remember_password': true,
    });

    final snapshot = await MediaBackendConnectionStore.load();

    expect(snapshot.activeKind, MediaBackendKind.feiniu);
    expect(snapshot.activeConnection.serverUrl, 'https://nas.example.test');
    expect(snapshot.activeConnection.userName, 'alice');
    expect(snapshot.activeConnection.accessToken, 'feiniu-token');
  });

  test('saving Emby connection does not write legacy Feiniu keys', () async {
    await MediaBackendConnectionStore.saveActive(
      const MediaBackendConnection(
        kind: MediaBackendKind.emby,
        serverUrl: 'https://emby.example.test',
        userName: 'bob',
        userId: 'emby-user',
        accessToken: 'emby-token',
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('base_url'), isNull);
    expect(prefs.getString('token'), isNull);

    final snapshot = await MediaBackendConnectionStore.load();
    expect(snapshot.activeKind, MediaBackendKind.emby);
    expect(snapshot.activeConnection.userId, 'emby-user');
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/services/media_backend_connection_store_test.dart`

Expected: FAIL，提示找不到 store。

- [ ] **Step 3: 实现 store**

实现要点：
- `activeKindKey = 'media_backend_active_kind_v1'`
- `connectionsKey = 'media_backend_connections_v1'`
- JSON 列表存储 `MediaBackendConnection.toJson()`
- 新 key 不存在时读取旧飞牛 key 合成 Feiniu connection
- `saveActive()` 对 Feiniu 只写新 key；旧 key 仍由 `NasProvider.updateSettings()` 负责，避免 store 反向复制飞牛登录副作用

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/services/media_backend_connection_store_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/services/media_backend_connection_store.dart test/services/media_backend_connection_store_test.dart
git commit -m "feat: add backend connection store"
```

## Task 3: BackendSessionProvider 注入

**Files:**
- Create: `lib/providers/backend_session_provider.dart`
- Modify: `lib/main.dart:358-366`
- Test: `test/providers/backend_session_provider_test.dart`

- [ ] **Step 1: 写 provider 单测**

测试覆盖：
- 初始 `load()` 后旧飞牛 prefs 使 `activeKind == feiniu`
- `isConfigured == true`
- 切换到空 Emby connection 时 `isConfigured == false`

- [ ] **Step 2: 实现 provider**

Provider 只管理中立 session：

```dart
class BackendSessionProvider extends ChangeNotifier {
  MediaBackendKind _activeKind = MediaBackendKind.feiniu;
  MediaBackendConnection _activeConnection =
      const MediaBackendConnection(kind: MediaBackendKind.feiniu, serverUrl: '');
  bool _isReady = false;

  MediaBackendKind get activeKind => _activeKind;
  MediaBackendConnection get activeConnection => _activeConnection;
  bool get isReady => _isReady;
  bool get isConfigured => _activeConnection.isAuthenticated;

  Future<void> load() async {
    final snapshot = await MediaBackendConnectionStore.load();
    _activeKind = snapshot.activeKind;
    _activeConnection = snapshot.activeConnection;
    _isReady = true;
    notifyListeners();
  }

  Future<void> setActiveConnection(MediaBackendConnection connection) async {
    await MediaBackendConnectionStore.saveActive(connection);
    _activeKind = connection.kind;
    _activeConnection = connection;
    _isReady = true;
    notifyListeners();
  }
}
```

- [ ] **Step 3: 注入 main.dart**

在 `MultiProvider` 中新增：

```dart
ChangeNotifierProvider(create: (_) => BackendSessionProvider()..load()),
```

不要移除 `NasProvider`。

- [ ] **Step 4: 运行验证**

Run: `flutter test test/providers/backend_session_provider_test.dart`

Expected: PASS。

Run: `flutter analyze lib/providers/backend_session_provider.dart lib/main.dart test/providers/backend_session_provider_test.dart`

Expected: No issues。

- [ ] **Step 5: 提交**

```bash
git add lib/providers/backend_session_provider.dart lib/main.dart test/providers/backend_session_provider_test.dart
git commit -m "feat: provide active media backend session"
```

## Task 4: 登录历史 v2

**Files:**
- Modify: `lib/services/login_history_store.dart`
- Test: `test/services/login_history_store_test.dart`

- [ ] **Step 1: 写历史测试**

覆盖：
- v1 历史读作 Feiniu
- v2 保存带 `backendKind`
- `load(kind: MediaBackendKind.emby)` 不返回 Feiniu 历史
- `rememberPassword=false` 时密码为空

- [ ] **Step 2: 实现 v2**

新增 key：`login_history_v2`。保留 `login_history_v1` 只读兼容，不再写 v1。

- [ ] **Step 3: 更新调用方**

`ConnectionScreen` 当前读取历史的地方先传 `MediaBackendKind.feiniu`，保持 UI 行为不变。

- [ ] **Step 4: 运行验证**

Run: `flutter test test/services/login_history_store_test.dart test/connection_login_persistence_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/services/login_history_store.dart lib/screens/connection_screen.dart test/services/login_history_store_test.dart test/connection_login_persistence_test.dart
git commit -m "feat: version login history by backend"
```

## Task 5: 登录页后端选择 UI，Feiniu 行为不变

**Files:**
- Modify: `lib/screens/connection_screen.dart`
- Test: `test/screens/connection_backend_selection_test.dart`

- [ ] **Step 1: 写 widget test**

测试覆盖：
- 默认展示飞牛字段和登录按钮
- 默认选中 Feiniu，且 Task 0 的兼容测试继续通过
- 切到 Emby 后展示 Emby server/user/password 和“验证连接”
- 切回飞牛后原历史按钮、HTTPS 开关、FN Connect 重登入口仍存在

- [ ] **Step 2: 抽出 Feiniu 表单状态**

把当前 `_submitWithUnifiedErrors()` 保持为 Feiniu handler，例如 `_submitFeiniu()`，不改变内部登录顺序。

- [ ] **Step 3: 加后端 selector**

在登录页顶部新增 segmented control。选中 Feiniu 时渲染现有表单；选中 Emby 时先渲染独立表单与“验证连接”按钮。

- [ ] **Step 4: Emby 按钮先只显示受限提示**

在 verifier 未实现前，点击显示“Emby 连接验证将在下一阶段开放”，不写任何 prefs。

- [ ] **Step 5: 运行验证**

Run: `flutter test test/screens/connection_backend_selection_test.dart test/connection_login_persistence_test.dart`

Expected: PASS。

Run: `flutter test test/screens/connection_feiniu_compatibility_test.dart`

Expected: PASS。

Run: `flutter analyze lib/screens/connection_screen.dart test/screens/connection_backend_selection_test.dart`

Expected: No issues。

- [ ] **Step 6: 提交**

```bash
git add lib/screens/connection_screen.dart test/screens/connection_backend_selection_test.dart
git commit -m "feat: add backend selector to connection screen"
```

## Task 6: Emby 只读连接验证

**Files:**
- Create: `lib/media_backend/emby/emby_connection_verifier.dart`
- Test: `test/media_backend/emby_connection_verifier_test.dart`
- Modify: `lib/screens/connection_screen.dart`

- [ ] **Step 1: 写 verifier 单测**

用 fake HTTP client 或 injectable function，禁止使用真实服务器。测试覆盖：
- 认证成功返回中立 `MediaBackendConnection`
- serverUrl 标准化
- 认证失败返回可显示错误
- 返回内容不落盘真实 password

- [ ] **Step 2: 实现 verifier**

只实现认证和可选服务器信息读取。不要添加 items/detail/playback endpoint。

- [ ] **Step 3: 接入 Emby 表单**

Emby 验证成功后：
- 写 `MediaBackendConnectionStore.saveActive(connection)`
- 调 `BackendSessionProvider.setActiveConnection(connection)`
- 显示“连接已验证，媒体浏览将在后续阶段开放”

不要改业务首页、详情、播放。

- [ ] **Step 4: 运行验证**

Run: `flutter test test/media_backend/emby_connection_verifier_test.dart test/screens/connection_backend_selection_test.dart`

Expected: PASS。

Run: `flutter analyze lib/media_backend/emby lib/screens/connection_screen.dart test/media_backend/emby_connection_verifier_test.dart`

Expected: No issues。

- [ ] **Step 5: 提交**

```bash
git add lib/media_backend/emby/emby_connection_verifier.dart lib/screens/connection_screen.dart test/media_backend/emby_connection_verifier_test.dart test/screens/connection_backend_selection_test.dart
git commit -m "feat: verify emby backend connection"
```

## Task 7: 设置页连接管理入口

**Files:**
- Modify: `lib/screens/app_settings_screen.dart`
- Modify: `lib/services/storage_management_service.dart`
- Test: `test/services/storage_management_service_test.dart`

- [ ] **Step 1: 存储服务测试**

确认新 key 纳入存储统计/清理：
- `media_backend_active_kind_v1`
- `media_backend_connections_v1`
- `login_history_v2`

- [ ] **Step 2: 设置页新增中立入口**

新增“媒体服务器连接”入口，展示当前后端类型和连接状态。FN Connect 重登入口继续保留，但文案标注为飞牛专属。

- [ ] **Step 3: 运行验证**

Run: `flutter analyze lib/screens/app_settings_screen.dart lib/services/storage_management_service.dart`

Expected: No issues。

Run: `flutter test test/services/storage_management_service_test.dart`

Expected: PASS。

- [ ] **Step 4: 提交**

```bash
git add lib/screens/app_settings_screen.dart lib/services/storage_management_service.dart test/services/storage_management_service_test.dart
git commit -m "feat: expose media backend connection settings"
```

## Task 8: Provider factory 收口

**Files:**
- Modify: `lib/providers/media_backend_provider.dart`
- Modify: `lib/main.dart`
- Test: `test/providers/media_backend_provider_test.dart`

- [ ] **Step 1: 写 provider factory 测试**

覆盖：
- activeKind=feiniu 时仍创建 `FeiniuMediaBackend`
- baseUrl 未变时复用缓存
- activeKind 改变时清缓存
- activeKind=emby 且 Emby 媒体 backend 未实现时抛出受控异常或由 gate 拦截，不进入业务页面

- [ ] **Step 2: 修改 provider**

`MediaBackendProvider` 接收 `NasProvider` + `BackendSessionProvider`。Feiniu 分支保持现有构造；Emby 分支先不可用，等待后续 Emby 媒体 backend 设计。

- [ ] **Step 3: 修改 gate**

`_ProviderGate` 同时等待 `NasProvider.isReady` 和 `BackendSessionProvider.isReady`。Feiniu 旧配置仍允许进入主导航；Emby 在仅验证阶段显示受限连接页，不进入媒体页面。

- [ ] **Step 4: 运行验证**

Run: `flutter test test/providers/media_backend_provider_test.dart test/connection_login_persistence_test.dart`

Expected: PASS。

Run: `flutter analyze lib/main.dart lib/providers`

Expected: No issues。

- [ ] **Step 5: 提交**

```bash
git add lib/main.dart lib/providers/media_backend_provider.dart test/providers/media_backend_provider_test.dart
git commit -m "feat: route media backend provider by session"
```

## Final Verification

- [ ] Run: `flutter test test/media_backend/ test/services/ test/providers/ test/connection_login_persistence_test.dart --concurrency=1`
- [ ] Run: `flutter analyze lib/media_backend lib/services lib/providers lib/screens/connection_screen.dart lib/screens/app_settings_screen.dart test/media_backend test/services test/providers`
- [ ] Manual: `flutter run`，用飞牛账号验证登录、FN Connect、登出、重新登录、首页、单条目播放入口不回归。
- [ ] Confirm: `git status --short` 只包含本阶段文件或已清空；不得暂存 `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/mpv/MpvPlaybackController.kt` 和 `HANDOFF.md`。
