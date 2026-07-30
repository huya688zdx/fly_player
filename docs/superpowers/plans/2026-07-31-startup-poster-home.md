# 启动直达海报首页 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 增加默认关闭的“启动直达海报首页”设置，并在有效登录会话进入主入口时只自动打开一次海报浏览页。

**Architecture:** 使用独立 `StartupPreferencesProvider` 读写一个 SharedPreferences 布尔值；`StartupDestinationGate` 在偏好就绪后决定是否压入现有海报路由，并以一次性状态防止重建重复跳转。设置首页直接消费同一 Provider，重置设置删除同一存储键。

**Tech Stack:** Flutter、Provider、SharedPreferences、flutter_test、现有 URI 路由与本地化生成流程。

---

### Task 1: 启动偏好 Provider

**Files:**
- Create: `lib/providers/startup_preferences_provider.dart`
- Create: `test/providers/startup_preferences_provider_test.dart`

- [ ] **Step 1: 写失败测试**

覆盖默认关闭、异步加载已有值、保存成功、保存异常回滚四种行为。测试通过构造函数注入 `loadPreference` 与 `savePreference`，不模拟 SharedPreferences 平台通道。

```dart
final provider = StartupPreferencesProvider(
  autoLoad: false,
  loadPreference: () async => true,
  savePreference: (value) async => saved = value,
);
expect(provider.openPosterHomeOnStartup, isFalse);
await provider.load();
expect(provider.openPosterHomeOnStartup, isTrue);
await provider.setOpenPosterHomeOnStartup(false);
expect(saved, isFalse);
```

- [ ] **Step 2: 验证 RED**

Run: `flutter test test/providers/startup_preferences_provider_test.dart`

Expected: FAIL，提示 `StartupPreferencesProvider` 尚不存在。

- [ ] **Step 3: 最小实现**

实现 `isReady`、`openPosterHomeOnStartup`、`load()` 和乐观更新的 `setOpenPosterHomeOnStartup()`。公开常量：

```dart
static const String preferenceKey = 'startup_open_poster_home';
```

默认加载函数读取 SharedPreferences，读取失败安全回退为关闭并将 `isReady` 置为 true；保存失败恢复旧值并重新抛出。

- [ ] **Step 4: 验证 GREEN**

Run: `flutter test test/providers/startup_preferences_provider_test.dart`

Expected: PASS。

### Task 2: 一次性启动目的地门控

**Files:**
- Create: `lib/widgets/startup_destination_gate.dart`
- Create: `test/widgets/startup_destination_gate_test.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: 写失败测试**

用真实 Navigator 和 Provider 覆盖：偏好未就绪显示加载态；关闭时显示普通首页 child；开启时压入 `/screen/poster-browse`；海报页返回后显示 child 且 Provider 重建不重复跳转。

```dart
await tester.pumpWidget(
  ChangeNotifierProvider.value(
    value: provider,
    child: MaterialApp(
      home: const StartupDestinationGate(child: Text('普通首页')),
      routes: {'/screen/poster-browse': (_) => const Text('海报首页')},
    ),
  ),
);
```

- [ ] **Step 2: 验证 RED**

Run: `flutter test test/widgets/startup_destination_gate_test.dart`

Expected: FAIL，提示门控组件不存在。

- [ ] **Step 3: 最小实现并接入根入口**

门控在 Provider 首次就绪时固定本次启动决策。开启时首帧后执行一次：

```dart
await Navigator.of(context).pushNamed('/screen/poster-browse');
```

跳转完成前显示黑色轻量加载页，避免普通首页先构建；返回后显示传入 child。`FlyPlayerApp` 注册 Provider，`AppEntry` 在现有 `_ProviderGate` 内包裹 `MainNavigation`。非根路由不使用该门控。

- [ ] **Step 4: 验证 GREEN**

Run: `flutter test test/widgets/startup_destination_gate_test.dart test/provider_gate_retry_test.dart test/main_navigation_layout_test.dart`

Expected: PASS。

### Task 3: 设置项与本地化

**Files:**
- Modify: `lib/screens/app_settings_screen.dart`
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_zh_CN.arb`
- Modify/Generate: `lib/l10n/generated/*`
- Modify: `test/settings_search_screen_test.dart`
- Create: `test/screens/app_settings_startup_preference_test.dart`

- [ ] **Step 1: 写失败测试**

在 Provider 容器中渲染 `AppSettingsScreen`，断言标题“启动直达海报首页”、说明文本和默认关闭的开关；点击开关后断言 Provider 值变为 true。设置搜索测试断言关键词“海报首页”“启动”“沉浸式”可以命中该设置。

- [ ] **Step 2: 验证 RED**

Run: `flutter test test/screens/app_settings_startup_preference_test.dart test/settings_search_screen_test.dart`

Expected: FAIL，设置文案和开关尚不存在。

- [ ] **Step 3: 最小实现**

新增本地化键：

```json
"settingsStartupPosterHomeTitle": "启动直达海报首页",
"settingsStartupPosterHomeSubtitle": "已有有效登录会话时，打开应用直接进入沉浸式海报浏览。",
"settingsStartupPosterHomeKeywords": "启动|首页|海报|海报首页|沉浸式|默认进入"
```

设置首页基础组加入 `_SettingsSwitchTile`，值来自 `StartupPreferencesProvider`；未就绪时禁用。保存异常通过现有顶端提示体系报告，Provider 已负责回滚。设置搜索加入根设置位置条目，选择结果后停留在设置首页。

- [ ] **Step 4: 生成本地化并验证 GREEN**

Run: `flutter gen-l10n`

Run: `flutter test test/screens/app_settings_startup_preference_test.dart test/settings_search_screen_test.dart`

Expected: PASS。

### Task 4: 设置重置与完整验证

**Files:**
- Modify: `lib/services/storage_management_service.dart`
- Create: `test/services/storage_management_settings_reset_test.dart`

- [ ] **Step 1: 写失败测试**

先将 `StartupPreferencesProvider.preferenceKey` 写为 true，调用 `resetSettings`，断言该键被删除；同时断言登录配置未被删除。

- [ ] **Step 2: 验证 RED**

Run: `flutter test test/services/storage_management_settings_reset_test.dart`

Expected: FAIL，启动偏好仍存在。

- [ ] **Step 3: 最小实现**

将 `StartupPreferencesProvider.preferenceKey` 加入 `_settingsResetKeys`，避免复制字符串；保持现有主题、并行窗口与其他设置重载流程不变。

- [ ] **Step 4: 回归验证**

Run: `flutter test test/providers/startup_preferences_provider_test.dart test/widgets/startup_destination_gate_test.dart test/screens/app_settings_startup_preference_test.dart test/settings_search_screen_test.dart test/provider_gate_retry_test.dart test/main_navigation_layout_test.dart`

Run: `flutter analyze`

Run: `git diff --check`

Expected: 全部 PASS，静态检查无问题。

- [ ] **Step 5: 性能包与设备验证**

Run: `flutter build apk --profile --flavor full`

安装到当前 adb 设备，分别验证开关关闭和开启后的冷启动；开启时海报页返回应进入普通首页，日志中不得出现 FlutterError 或 AndroidRuntime 崩溃。

- [ ] **Step 6: 提交**

```bash
git add lib/providers/startup_preferences_provider.dart \
  lib/widgets/startup_destination_gate.dart lib/main.dart \
  lib/screens/app_settings_screen.dart lib/l10n lib/services/storage_management_service.dart \
  test/providers/startup_preferences_provider_test.dart \
  test/widgets/startup_destination_gate_test.dart \
  test/screens/app_settings_startup_preference_test.dart \
  test/settings_search_screen_test.dart test/services/storage_management_settings_reset_test.dart
git commit -m "feat(settings): 支持启动直达海报首页"
```
