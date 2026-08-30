# 储存管理桌面等价宿主 实施计划

> **For agentic workers:** Execute these steps inline unless the user explicitly requests another workflow. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 桌面端（Windows/Linux/macOS）打开「储存管理」不再显示加载失败——统计、清理、设置重置全部可用，Android 行为完全不变。

**Architecture:** 引入 `StorageManagementHost` 平台宿主接口隔离 `fly_player/storage` 通道：Android 继续走通道（`MethodChannelStorageManagementHost`，透传既有协议）；桌面端用纯 Dart 的 `DesktopStorageManagementHost` 返回语义等价载荷（Android 专属统计归零、清理动作为安全空操作）。`StorageManagementService` 按平台选宿主，测试环境（TestDefaultBinaryMessenger）保持通道语义以兼容既有 mock。宿主为三桌面平台通用实现——Linux/macOS 接入时无需新增代码；桌面播放内核落地后，播放缓存统计在本宿主内补齐，业务层不改。

**Tech Stack:** Flutter (Dart)、MethodChannel、flutter_test。无新依赖。

**执行目录:** 全部命令在 worktree `F:/fly_wt/desktop-storage`（分支 `feat/desktop-storage`，基于 `feat/desktop-shell`）执行。

## 当前状态（2026-08-30 复核）

- 实现已落在 `feat/desktop-storage@738cf2b`，工作树干净；计划内的代码任务不再重复施工。
- 5 个储存管理相关测试文件以及桌面详情页/平台守卫测试共 23 项通过。
- 全仓 `flutter analyze` 未新增问题，仅保留 1 个既有的 poster browse 未使用 import 警告。
- 尚未留档的是 Windows 与 Android 的人工验收；因此本计划的代码状态为“完成”，发布验收状态仍为“待人工确认”。
- 下方历史复选框保留原执行记录格式，不再把未勾选误读为代码尚未实现。

---

### Task 1: 环境准备与基线

- [ ] **Step 1: 安装依赖并生成 l10n**

Run:
```bash
cd F:/fly_wt/desktop-storage && flutter pub get
```
Expected: 退出码 0。若 `lib/l10n/generated/app_localizations.dart` 不存在（生成文件不入库），追加：
```bash
cd F:/fly_wt/desktop-storage && flutter gen-l10n
```

- [ ] **Step 2: 记录 analyze 基线**

Run: `cd F:/fly_wt/desktop-storage && flutter analyze`
Expected: `No issues found!`（若有既有问题，记录条数作为基线，后续对比不得新增）。

### Task 2: DesktopStorageManagementHost（TDD）

**Files:**
- Test: `test/services/desktop_storage_management_host_test.dart`
- Create: `lib/services/storage_management_host.dart`

- [ ] **Step 1: 写失败测试**

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/services/storage_management_host.dart';

void main() {
  const host = DesktopStorageManagementHost();

  test('概览：桌面端原生侧统计归零且截图不受限', () async {
    final overview = await host.getStorageOverview();

    final playback = overview['playbackCache']! as Map<Object?, Object?>;
    expect(playback['bytes'], 0);
    expect(playback['fileCount'], 0);
    expect(playback['completeCount'], 0);
    expect(playback['active'], isFalse);

    expect(
      overview['danmakuAiCache'],
      <String, Object?>{'bytes': 0, 'fileCount': 0},
    );
    expect(
      overview['otherCache'],
      <String, Object?>{'bytes': 0, 'fileCount': 0},
    );

    final screenshots = overview['screenshots']! as Map<Object?, Object?>;
    expect(screenshots['bytes'], 0);
    expect(screenshots['fileCount'], 0);
    expect(screenshots['restricted'], isFalse);

    expect(overview['nativeSettingsBytes'], 0);
  });

  test('清理动作：Android 专属项按成功空操作返回，未知动作返回 unknown_action', () async {
    for (final action in const <String>[
      'clearPlaybackCache',
      'clearDanmakuAiCache',
      'clearOtherCache',
      'clearParallelWindowSettings',
      'clearScopedTreeAccess',
    ]) {
      expect(
        (await host.clearStorageAction(action))['success'],
        isTrue,
        reason: '$action 应按成功空操作返回',
      );
    }

    final screenshots = await host.clearStorageAction('clearScreenshots');
    expect(screenshots['success'], isTrue);
    expect(screenshots['restricted'], isFalse);
    expect(screenshots['deletedCount'], 0);

    expect(
      (await host.clearStorageAction('unknown_action'))['code'],
      'unknown_action',
    );
  });

  test('缓存与权限：桌面端无播放缓存、文件访问视为已授权', () async {
    expect(await host.listPlaybackCacheEntries(), isEmpty);
    expect(
      (await host.clearPlaybackCacheEntries(
        const <String>['resource-1'],
      ))['success'],
      isTrue,
    );

    final downloadable = await host.queryCachedDownloadable(
      const <String, Object?>{
        'itemGuid': 'item-1',
        'mediaGuid': 'media-1',
        'videoGuid': 'video-1',
        'resourceKey': 'resource-1',
      },
    );
    expect(downloadable['found'], isFalse);
    expect(downloadable['downloadable'], isFalse);
    expect(downloadable['code'], 'not_found');

    expect(
      (await host.promoteCachedMedia(const <String, Object?>{
        'itemGuid': 'item-1',
        'targetMode': 'appExternalMovies',
      }))['success'],
      isFalse,
    );

    expect(await host.hasFileAccess(), isTrue);
    expect(await host.requestFileAccess(), isTrue);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd F:/fly_wt/desktop-storage && flutter test test/services/desktop_storage_management_host_test.dart`
Expected: FAIL——`storage_management_host.dart` 不存在导致的编译错误。

- [ ] **Step 3: 写接口与桌面宿主实现**

`lib/services/storage_management_host.dart`：

```dart
import 'package:flutter/services.dart';

/// 储存管理平台宿主接口：屏蔽 Android 原生通道与桌面端等价实现的差异。
///
/// Android 由 `FlutterHostActivity` 注册的 `fly_player/storage` 通道承载；
/// 桌面端（Windows/Linux/macOS）无该通道，任何调用都会抛 MissingPluginException，
/// 由 [DesktopStorageManagementHost] 提供语义等价的 Dart 实现。新增平台只需追加
/// `StorageManagementHost` 实现，业务层禁止直连通道。方法返回的映射结构与
/// Android 端 `StorageManagementController` 的载荷字段保持一致。
abstract interface class StorageManagementHost {
  /// 原生侧统计：playbackCache{bytes,fileCount,completeCount,active}、
  /// danmakuAiCache{bytes,fileCount}、otherCache{bytes,fileCount}、
  /// screenshots{bytes,fileCount,restricted}、nativeSettingsBytes。
  Future<Map<Object?, Object?>?> getStorageOverview();

  /// 执行原生清理动作，action 取值与 Android 端 StorageManagementController
  /// 常量一致（clearPlaybackCache/clearDanmakuAiCache/clearOtherCache/
  /// clearScreenshots/clearParallelWindowSettings/clearScopedTreeAccess）。
  Future<Map<Object?, Object?>?> clearStorageAction(String action);

  /// 列出播放缓存记录（桌面端恒为空）。
  Future<List<Object?>?> listPlaybackCacheEntries();

  /// 按资源键批量清理播放缓存记录。
  Future<Map<Object?, Object?>?> clearPlaybackCacheEntries(
    List<String> resourceKeys,
  );

  /// 查询缓存媒体可否提升为下载文件。
  Future<Map<Object?, Object?>?> queryCachedDownloadable(
    Map<String, Object?> identity,
  );

  /// 将缓存媒体提升到目标存储位置。
  Future<Map<Object?, Object?>?> promoteCachedMedia(
    Map<String, Object?> arguments,
  );

  /// 是否具备常规文件访问权限（桌面端恒为 true）。
  Future<bool?> hasFileAccess();

  /// 请求常规文件访问权限（桌面端恒为 true）。
  Future<bool?> requestFileAccess();
}

/// 桌面端（Windows/Linux/macOS）储存宿主等价实现，纯 Dart，三平台通用。
///
/// 归零口径与桌面壳当前能力一一对应：
/// - 播放缓存：桌面播放内核未接入（`*playback_launcher` 有桌面守卫），无缓存会话；
/// - 弹幕 AI 缓存：Paddle Lite 遮挡分割是 Android 原生能力；
/// - 其他缓存：Android 对应 cacheDir/codeCacheDir/tmpdir，桌面端应用自有数据
///   全部位于 SharedPreferences/数据库/下载目录（已由 Dart 侧统计），共享系统
///   临时目录禁止批量清理，故恒为 0；
/// - 截图：截图库依赖 Android MediaStore/SAF，桌面无截图管线；
/// - 原生设置：parallel_window_settings / fly_player_scoped_tree 为 Android
///   原生 SharedPreferences，桌面端无对应存储。
/// 播放内核接入后，播放缓存统计在本类内补齐，`StorageManagementService` 不再改动。
class DesktopStorageManagementHost implements StorageManagementHost {
  const DesktopStorageManagementHost();

  @override
  Future<Map<Object?, Object?>> getStorageOverview() async {
    return const <String, Object?>{
      'playbackCache': <String, Object?>{
        'bytes': 0,
        'fileCount': 0,
        'completeCount': 0,
        'active': false,
      },
      'danmakuAiCache': <String, Object?>{'bytes': 0, 'fileCount': 0},
      'otherCache': <String, Object?>{'bytes': 0, 'fileCount': 0},
      'screenshots': <String, Object?>{
        'bytes': 0,
        'fileCount': 0,
        'restricted': false,
      },
      'nativeSettingsBytes': 0,
    };
  }

  @override
  Future<Map<Object?, Object?>> clearStorageAction(String action) async {
    switch (action) {
      case 'clearPlaybackCache':
      case 'clearDanmakuAiCache':
      case 'clearOtherCache':
      case 'clearParallelWindowSettings':
      case 'clearScopedTreeAccess':
        return const <String, Object?>{'success': true};
      case 'clearScreenshots':
        return const <String, Object?>{
          'success': true,
          'restricted': false,
          'deletedCount': 0,
        };
      default:
        return const <String, Object?>{
          'success': false,
          'code': 'unknown_action',
        };
    }
  }

  @override
  Future<List<Object?>> listPlaybackCacheEntries() async {
    return const <Object?>[];
  }

  @override
  Future<Map<Object?, Object?>> clearPlaybackCacheEntries(
    List<String> resourceKeys,
  ) async {
    return const <String, Object?>{'success': true, 'clearedCount': 0};
  }

  @override
  Future<Map<Object?, Object?>> queryCachedDownloadable(
    Map<String, Object?> identity,
  ) async {
    return const <String, Object?>{
      'found': false,
      'downloadable': false,
      'code': 'not_found',
      'resourceKey': '',
      'bytes': 0,
      'totalBytes': 0,
      'mimeType': '',
      'suggestedFileName': '',
      'title': '',
    };
  }

  @override
  Future<Map<Object?, Object?>> promoteCachedMedia(
    Map<String, Object?> arguments,
  ) async {
    return const <String, Object?>{'success': false, 'code': 'not_found'};
  }

  @override
  Future<bool> hasFileAccess() async {
    return true;
  }

  @override
  Future<bool> requestFileAccess() async {
    return true;
  }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `cd F:/fly_wt/desktop-storage && flutter test test/services/desktop_storage_management_host_test.dart`
Expected: PASS（3 个测试）。

### Task 3: 通道宿主 + 服务按平台选宿主

**Files:**
- Modify: `lib/services/storage_management_host.dart`（追加通道宿主）
- Modify: `lib/services/storage_management_service.dart`
- Test: `test/services/storage_management_host_selection_test.dart`
- Modify: `AGENTS.md`

- [ ] **Step 1: 追加通道宿主**

在 `lib/services/storage_management_host.dart` 文件末尾追加：

```dart
/// Android 通道宿主：透传 `fly_player/storage`，行为与原先
/// `StorageManagementService` 直连通道完全一致。
class MethodChannelStorageManagementHost implements StorageManagementHost {
  const MethodChannelStorageManagementHost();

  static const MethodChannel _channel = MethodChannel('fly_player/storage');

  @override
  Future<Map<Object?, Object?>?> getStorageOverview() =>
      _channel.invokeMapMethod<Object?, Object?>('getStorageOverview');

  @override
  Future<Map<Object?, Object?>?> clearStorageAction(String action) =>
      _channel.invokeMapMethod<Object?, Object?>(
        'clearStorageAction',
        <String, Object?>{'action': action},
      );

  @override
  Future<List<Object?>?> listPlaybackCacheEntries() =>
      _channel.invokeListMethod<Object?>('listPlaybackCacheEntries');

  @override
  Future<Map<Object?, Object?>?> clearPlaybackCacheEntries(
    List<String> resourceKeys,
  ) =>
      _channel.invokeMapMethod<Object?, Object?>(
        'clearPlaybackCacheEntries',
        <String, Object?>{'resourceKeys': resourceKeys},
      );

  @override
  Future<Map<Object?, Object?>?> queryCachedDownloadable(
    Map<String, Object?> identity,
  ) =>
      _channel.invokeMapMethod<Object?, Object?>(
        'queryCachedDownloadable',
        identity,
      );

  @override
  Future<Map<Object?, Object?>?> promoteCachedMedia(
    Map<String, Object?> arguments,
  ) =>
      _channel.invokeMapMethod<Object?, Object?>(
        'promoteCachedMedia',
        arguments,
      );

  @override
  Future<bool?> hasFileAccess() => _channel.invokeMethod<bool>('hasFileAccess');

  @override
  Future<bool?> requestFileAccess() =>
      _channel.invokeMethod<bool>('requestFileAccess');
}
```

- [ ] **Step 2: 修改 StorageManagementService**

`lib/services/storage_management_service.dart` 共 7 处修改：

(a) imports 新增两条（按现有相对导入顺序插入）：

```dart
import '../desktop/desktop_environment.dart';
import 'storage_management_host.dart';
```

(b) 删除 `static const MethodChannel _channel = MethodChannel('fly_player/storage');`，原位替换为宿主选择：

```dart
  /// 平台储存宿主：Android 走 `fly_player/storage` 原生通道；桌面端无该通道实现，
  /// 改用 Dart 等价宿主（此前 loadOverview 首个调用即抛 MissingPluginException，
  /// 储存管理页显示「加载失败」）。测试环境保持通道语义，兼容既有 mock。
  static StorageManagementHost? _debugHostOverride;

  static StorageManagementHost get _host {
    final override = _debugHostOverride;
    if (override != null) return override;
    if (_isTestMessenger()) return const MethodChannelStorageManagementHost();
    if (DesktopEnvironment.isDesktopPlatform) {
      return const DesktopStorageManagementHost();
    }
    return const MethodChannelStorageManagementHost();
  }

  static bool _isTestMessenger() {
    try {
      return ServicesBinding
          .instance.defaultBinaryMessenger.runtimeType
          .toString()
          .contains('Test');
    } catch (_) {
      return true;
    }
  }

  @visibleForTesting
  static StorageManagementHost get debugHost => _host;

  @visibleForTesting
  static void setHostForTesting(StorageManagementHost? host) {
    _debugHostOverride = host;
  }
```

(c) `loadOverview` 开头（原 `_channel.invokeMapMethod('getStorageOverview') ?? {}`）替换为：

```dart
    final native = _normalizeMap(await _host.getStorageOverview());
```

(d) `clearSystemAction` 中截图权限检查与动作执行替换为：

```dart
    if (action == StorageClearAction.clearScreenshots) {
      final hasAccess = await _host.hasFileAccess() ?? false;
      if (!hasAccess) {
        await _host.requestFileAccess();
      }
    }
    final result = _normalizeMap(await _host.clearStorageAction(actionName));
```

(e) `resetSettings` 中两处通道调用替换为：

```dart
    await _host.clearStorageAction('clearParallelWindowSettings');
    await _host.clearStorageAction('clearScopedTreeAccess');
```

(f) `loadPlaybackCacheEntries` / `clearPlaybackCacheEntries` / `canPromoteCachedMedia` / `promoteCachedMedia` 中通道调用分别替换为：

```dart
    final raw = await _host.listPlaybackCacheEntries() ?? const <Object?>[];
```

```dart
    final result =
        _normalizeMap(await _host.clearPlaybackCacheEntries(normalized));
```

```dart
    final result = _normalizeMap(
      await _host.queryCachedDownloadable(identity.toMap()) ??
          const <Object?, Object?>{},
    );
```

```dart
    if (targetMode == 'publicDownloads') {
      final hasAccess = await _host.hasFileAccess() ?? false;
      if (!hasAccess) {
        await _host.requestFileAccess();
      }
    }
    final result = _normalizeMap(
      await _host.promoteCachedMedia(<String, Object?>{
        ...identity.toMap(),
        'targetMode': targetMode,
      }),
    );
```

注意：`import 'package:flutter/services.dart'` 保留（`ServicesBinding` 仍在使用）。

- [ ] **Step 3: 写宿主选择与端到端测试**

`test/services/storage_management_host_selection_test.dart`：

```dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/services/storage_management_host.dart';
import 'package:fly_player/services/storage_management_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('默认宿主：测试环境选择通道宿主，兼容既有 mock', () {
    expect(
      StorageManagementService.debugHost,
      isA<MethodChannelStorageManagementHost>(),
    );
  });

  test('桌面宿主下 loadOverview 不依赖原生通道且播放缓存项归零', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    StorageManagementService.setHostForTesting(
      const DesktopStorageManagementHost(),
    );
    addTearDown(() => StorageManagementService.setHostForTesting(null));

    final overview = await StorageManagementService.instance.loadOverview(
      lookupAppLocalizations(const Locale('zh')),
    );

    final playback = overview.items
        .firstWhere((item) => item.kind == StorageItemKind.playbackCache);
    expect(playback.bytes, 0);
    expect(playback.clearDisabled, isFalse);
    expect(playback.note, isNull);
  });
}
```

- [ ] **Step 4: 运行相关测试**

Run:
```bash
cd F:/fly_wt/desktop-storage && flutter test test/services/storage_management_host_selection_test.dart test/services/desktop_storage_management_host_test.dart test/services/storage_management_settings_reset_test.dart test/services/storage_play_stats_bytes_test.dart test/screens/storage_management_screen_test.dart
```
Expected: 全部 PASS（含既有 3 个储存相关测试文件）。

- [ ] **Step 5: 全量静态检查**

Run: `cd F:/fly_wt/desktop-storage && flutter analyze`
Expected: `No issues found!`（不得比 Task 1 基线新增）。

- [ ] **Step 6: AGENTS.md 登记平台后端约定**

在 AGENTS.md 桌面端小节「凭据存储」段落之后追加一行：

```markdown
储存管理：Android 走 `fly_player/storage` 原生通道；桌面端由 `lib/services/storage_management_host.dart` 的 Dart 等价宿主承担（`StorageManagementService` 按平台选默认宿主，三桌面平台通用，Android 专属统计按 0/未受限返回）。播放内核接入后桌面播放缓存统计在该宿主内补齐；业务层禁止直连通道。
```

- [ ] **Step 7: 提交**

```bash
cd F:/fly_wt/desktop-storage && git add lib/services/storage_management_host.dart lib/services/storage_management_service.dart test/services/desktop_storage_management_host_test.dart test/services/storage_management_host_selection_test.dart AGENTS.md docs/superpowers/plans/2026-08-30-desktop-storage-equivalence.md docs/superpowers/plans/2026-08-30-desktop-playback-poc.md && git commit -m "fix(desktop): 储存管理桌面等价宿主——修复打开显示加载失败"
```

### Task 4: Windows 实机验收（人工）

- [ ] **Step 1: 运行桌面壳**

Run: `cd F:/fly_wt/desktop-storage && flutter run -d windows`
Expected: 应用正常启动登录页。

- [ ] **Step 2: 验收储存管理**

操作：设置 → 储存管理。
Expected: 不再显示「加载失败」；下载/日志/应用数据等 Dart 侧统计正常；播放缓存/截图/弹幕 AI 缓存/其他缓存显示 0 且清理动作可执行（成功提示）；「重置设置」不报错。

- [ ] **Step 3: Android 回归（可选，有设备时）**

Run: `cd F:/fly_wt/desktop-storage && flutter run`
Expected: 储存管理行为与改动前一致（走通道宿主）。

---

## 已知边界（不在本计划内）

- `StorageAccessService`（SAF 目录浏览、截图库、日志导出等，同通道）仍为 Android 专属，桌面端对应页面/入口需另行适配——储存管理页不依赖它。
- 桌面播放内核接入后：`DesktopStorageManagementHost.getStorageOverview` 的 playbackCache 统计、以及截图（若桌面支持）需在宿主内补齐真实数据。
