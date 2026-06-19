# Public Media Frontend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把现有飞牛专用前端逐步整理成公共媒体前端，第一阶段只迁移首页链路到公共 `MediaBackend`，不接入 Emby。

**Architecture:** 新增 `lib/media_backend/`，定义公共模型、接口和飞牛适配器。页面通过 provider 获取 `MediaBackend`，第一阶段保持底层仍为 `FeiniuApi`。

**Tech Stack:** Flutter、Provider、Dart model classes、flutter_test、现有 `FeiniuApi` / `NasProvider`。

---

## 文件结构

- Create: `lib/media_backend/media_backend_kind.dart`
  - 定义后端类型。
- Create: `lib/media_backend/media_backend_capabilities.dart`
  - 定义下载、收藏、远程访问、片头片尾等能力开关。
- Create: `lib/media_backend/media_image_ref.dart`
  - 统一图片 URL 与 headers。
- Create: `lib/media_backend/media_catalog.dart`
  - 首页媒体库入口模型。
- Create: `lib/media_backend/media_item_summary.dart`
  - 首页、分类页、搜索页卡片模型。
- Create: `lib/media_backend/media_backend.dart`
  - 公共后端接口。
- Create: `lib/media_backend/feiniu/feiniu_media_mappers.dart`
  - 飞牛模型到公共模型的转换。
- Create: `lib/media_backend/feiniu/feiniu_media_backend.dart`
  - 飞牛适配器，内部调用 `FeiniuApi`。
- Create: `lib/providers/media_backend_provider.dart`
  - 根据当前配置提供 `MediaBackend`。
- Modify: `lib/main.dart`
  - 注册 `MediaBackendProvider`。
- Modify: `lib/screens/media_list_screen.dart`
  - 首页从 `FeiniuApi` 改为 `MediaBackend`。
- Modify: `lib/services/home_data_cache.dart`
  - 如缓存模型仍使用飞牛模型，第一阶段只保留飞牛缓存；首页公共模型缓存单独落后处理。
- Test: `test/media_backend/feiniu_media_mappers_test.dart`
  - 验证飞牛字段映射。
- Test: `test/media_backend/feiniu_media_backend_test.dart`
  - 使用 fake API 或 mapper 层测试验证适配器输出。

## Task 1: 公共后端类型和能力模型

**Files:**
- Create: `lib/media_backend/media_backend_kind.dart`
- Create: `lib/media_backend/media_backend_capabilities.dart`
- Test: `test/media_backend/media_backend_capabilities_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_backend_capabilities.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';

void main() {
  test('Feiniu capabilities expose current NAS-only features', () {
    const capabilities = MediaBackendCapabilities.feiniu();

    expect(capabilities.kind, MediaBackendKind.feiniu);
    expect(capabilities.supportsDownloadTasks, isTrue);
    expect(capabilities.supportsFnConnect, isTrue);
    expect(capabilities.supportsIntroOutroConfig, isTrue);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test\media_backend\media_backend_capabilities_test.dart`

Expected: FAIL，提示 package 或 class 不存在。

- [ ] **Step 3: 实现最小代码**

`lib/media_backend/media_backend_kind.dart`

```dart
enum MediaBackendKind { feiniu, emby }
```

`lib/media_backend/media_backend_capabilities.dart`

```dart
import 'media_backend_kind.dart';

class MediaBackendCapabilities {
  final MediaBackendKind kind;
  final bool supportsDownloadTasks;
  final bool supportsFnConnect;
  final bool supportsIntroOutroConfig;

  const MediaBackendCapabilities({
    required this.kind,
    required this.supportsDownloadTasks,
    required this.supportsFnConnect,
    required this.supportsIntroOutroConfig,
  });

  const MediaBackendCapabilities.feiniu()
      : kind = MediaBackendKind.feiniu,
        supportsDownloadTasks = true,
        supportsFnConnect = true,
        supportsIntroOutroConfig = true;
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test\media_backend\media_backend_capabilities_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/media_backend/media_backend_kind.dart lib/media_backend/media_backend_capabilities.dart test/media_backend/media_backend_capabilities_test.dart
git commit -m "feat: add media backend capabilities"
```

## Task 2: 公共首页模型

**Files:**
- Create: `lib/media_backend/media_image_ref.dart`
- Create: `lib/media_backend/media_catalog.dart`
- Create: `lib/media_backend/media_item_summary.dart`
- Test: `test/media_backend/media_frontend_models_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_catalog.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/media_backend/media_item_summary.dart';

void main() {
  test('media item summary exposes display title and primary image', () {
    const image = MediaImageRef(url: 'https://server/poster.jpg');
    const item = MediaItemSummary(
      id: 'item-1',
      title: '正片标题',
      type: 'Movie',
      primaryImage: image,
      backdropImage: MediaImageRef.empty,
      durationSeconds: 3600,
      watched: false,
    );

    expect(item.displayTitle, '正片标题');
    expect(item.primaryImage.url, 'https://server/poster.jpg');
  });

  test('media catalog keeps stable id and title', () {
    const catalog = MediaCatalog(
      id: 'movies',
      title: '电影',
      type: 'Movie',
      primaryImage: MediaImageRef.empty,
    );

    expect(catalog.id, 'movies');
    expect(catalog.title, '电影');
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test\media_backend\media_frontend_models_test.dart`

Expected: FAIL，提示模型不存在。

- [ ] **Step 3: 实现模型**

`lib/media_backend/media_image_ref.dart`

```dart
class MediaImageRef {
  final String url;
  final Map<String, String> headers;

  static const empty = MediaImageRef(url: '');

  const MediaImageRef({required this.url, this.headers = const {}});

  bool get isEmpty => url.trim().isEmpty;
  bool get isNotEmpty => !isEmpty;
}
```

`lib/media_backend/media_catalog.dart`

```dart
import 'media_image_ref.dart';

class MediaCatalog {
  final String id;
  final String title;
  final String type;
  final MediaImageRef primaryImage;

  const MediaCatalog({
    required this.id,
    required this.title,
    required this.type,
    required this.primaryImage,
  });
}
```

`lib/media_backend/media_item_summary.dart`

```dart
import 'media_image_ref.dart';

class MediaItemSummary {
  final String id;
  final String title;
  final String type;
  final MediaImageRef primaryImage;
  final MediaImageRef backdropImage;
  final int durationSeconds;
  final bool watched;

  const MediaItemSummary({
    required this.id,
    required this.title,
    required this.type,
    required this.primaryImage,
    required this.backdropImage,
    required this.durationSeconds,
    required this.watched,
  });

  String get displayTitle {
    final value = title.trim();
    return value.isEmpty ? 'Unknown' : value;
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test\media_backend\media_frontend_models_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/media_backend/media_image_ref.dart lib/media_backend/media_catalog.dart lib/media_backend/media_item_summary.dart test/media_backend/media_frontend_models_test.dart
git commit -m "feat: add public media frontend models"
```

## Task 3: Feiniu mapper

**Files:**
- Create: `lib/media_backend/feiniu/feiniu_media_mappers.dart`
- Test: `test/media_backend/feiniu_media_mappers_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/feiniu/feiniu_media_mappers.dart';
import 'package:fly_player/models/media_item.dart';
import 'package:fly_player/models/media_library_item.dart';

void main() {
  test('maps Feiniu MediaItem to MediaCatalog', () {
    final catalog = mapFeiniuCatalog(
      MediaItem(id: 'cat-1', name: '电影', type: 'Movie', path: '/p.jpg'),
    );

    expect(catalog.id, 'cat-1');
    expect(catalog.title, '电影');
    expect(catalog.type, 'Movie');
    expect(catalog.primaryImage.url, '/p.jpg');
  });

  test('maps Feiniu MediaLibraryItem to MediaItemSummary', () {
    final item = mapFeiniuItemSummary(
      MediaLibraryItem(
        guid: 'item-1',
        title: '电影 A',
        tvTitle: '',
        type: 'Movie',
        poster: '/poster.jpg',
        releaseDate: '',
        firstAirDate: '',
        lastAirDate: '',
        voteAverage: '',
        overview: '',
        watched: 1,
        watchedTs: 0,
        ts: 0,
        duration: 123,
        seasonNumber: 0,
        episodeNumber: 0,
        numberOfSeasons: 0,
        numberOfEpisodes: 0,
        localNumberOfSeasons: 0,
        localNumberOfEpisodes: 0,
        parentGuid: '',
        parentTitle: '',
        ancestorGuid: '',
        ancestorName: '',
        path: '',
      ),
    );

    expect(item.id, 'item-1');
    expect(item.displayTitle, '电影 A');
    expect(item.watched, isTrue);
    expect(item.durationSeconds, 123);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test\media_backend\feiniu_media_mappers_test.dart`

Expected: FAIL，提示 mapper 不存在。

- [ ] **Step 3: 实现 mapper**

```dart
import '../../models/media_item.dart';
import '../../models/media_library_item.dart';
import '../media_catalog.dart';
import '../media_image_ref.dart';
import '../media_item_summary.dart';

MediaCatalog mapFeiniuCatalog(MediaItem item) {
  return MediaCatalog(
    id: item.id,
    title: item.name,
    type: item.type ?? '',
    primaryImage: MediaImageRef(url: item.path ?? ''),
  );
}

MediaItemSummary mapFeiniuItemSummary(MediaLibraryItem item) {
  return MediaItemSummary(
    id: item.guid,
    title: item.displayTitle,
    type: item.type,
    primaryImage: MediaImageRef(url: item.poster),
    backdropImage: MediaImageRef.empty,
    durationSeconds: item.duration,
    watched: item.watched != 0,
  );
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test\media_backend\feiniu_media_mappers_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/media_backend/feiniu/feiniu_media_mappers.dart test/media_backend/feiniu_media_mappers_test.dart
git commit -m "feat: map Feiniu media models to public frontend models"
```

## Task 4: MediaBackend 接口和飞牛适配器

**Files:**
- Create: `lib/media_backend/media_backend.dart`
- Create: `lib/media_backend/feiniu/feiniu_media_backend.dart`
- Test: `test/media_backend/feiniu_media_backend_test.dart`

- [ ] **Step 1: 写接口**

```dart
import 'media_backend_capabilities.dart';
import 'media_catalog.dart';
import 'media_item_summary.dart';

abstract class MediaBackend {
  MediaBackendCapabilities get capabilities;

  Future<List<MediaCatalog>> getCatalogs();

  Future<Map<String, dynamic>> getHomeSummary();

  Future<List<MediaItemSummary>> getContinueWatching({bool forceRefresh = false});

  Future<List<MediaItemSummary>> getCatalogPreviewItems(
    String catalogId, {
    int page = 1,
    int limit = 30,
  });
}
```

- [ ] **Step 2: 实现飞牛适配器**

```dart
import '../../api/feiniu_api.dart';
import '../media_backend.dart';
import '../media_backend_capabilities.dart';
import '../media_catalog.dart';
import '../media_item_summary.dart';
import 'feiniu_media_mappers.dart';

class FeiniuMediaBackend implements MediaBackend {
  final FeiniuApi api;

  const FeiniuMediaBackend(this.api);

  @override
  MediaBackendCapabilities get capabilities =>
      const MediaBackendCapabilities.feiniu();

  @override
  Future<List<MediaCatalog>> getCatalogs() async {
    final items = await api.getMediaList();
    return items.map(mapFeiniuCatalog).toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>> getHomeSummary() => api.getMediaSummary();

  @override
  Future<List<MediaItemSummary>> getContinueWatching({
    bool forceRefresh = false,
  }) async {
    final items = await api.getPlayList(forceRefresh: forceRefresh);
    return items.map(mapFeiniuItemSummary).toList(growable: false);
  }

  @override
  Future<List<MediaItemSummary>> getCatalogPreviewItems(
    String catalogId, {
    int page = 1,
    int limit = 30,
  }) async {
    final items = await api.getItemsByCategoryGuid(
      catalogId,
      page: page,
      limit: limit,
    );
    return items.map(mapFeiniuItemSummary).toList(growable: false);
  }
}
```

- [ ] **Step 3: 写适配器测试**

测试用 fake API 不方便直接替换 `FeiniuApi` 时，先把 Task 3 mapper 覆盖作为核心回归；适配器测试只验证 capabilities。

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/media_backend/media_backend_capabilities.dart';

void main() {
  test('Feiniu capability preset stays NAS-specific', () {
    const capabilities = MediaBackendCapabilities.feiniu();

    expect(capabilities.kind, MediaBackendKind.feiniu);
    expect(capabilities.supportsDownloadTasks, isTrue);
    expect(capabilities.supportsFnConnect, isTrue);
  });
}
```

- [ ] **Step 4: 运行测试**

Run:

```bash
flutter test test\media_backend\media_backend_capabilities_test.dart
flutter test test\media_backend\media_frontend_models_test.dart
flutter test test\media_backend\feiniu_media_mappers_test.dart
```

Expected: 全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/media_backend/media_backend.dart lib/media_backend/feiniu/feiniu_media_backend.dart test/media_backend
git commit -m "feat: add Feiniu media backend adapter"
```

## Task 5: Provider 注入，不迁移页面

**Files:**
- Create: `lib/providers/media_backend_provider.dart`
- Modify: `lib/main.dart`
- Test: `test/media_backend/media_backend_provider_test.dart`

- [ ] **Step 1: 新增 provider**

```dart
import 'package:flutter/foundation.dart';

import '../api/feiniu_api.dart';
import '../media_backend/feiniu/feiniu_media_backend.dart';
import '../media_backend/media_backend.dart';
import 'nas_provider.dart';

class MediaBackendProvider extends ChangeNotifier {
  final NasProvider nasProvider;

  MediaBackendProvider(this.nasProvider);

  MediaBackend get backend => FeiniuMediaBackend(FeiniuApi(nasProvider));
}
```

- [ ] **Step 2: 在 main.dart 注册**

在 `MultiProvider` 中 `NasProvider` 后面添加：

```dart
ChangeNotifierProxyProvider<NasProvider, MediaBackendProvider>(
  create: (context) => MediaBackendProvider(context.read<NasProvider>()),
  update: (context, nas, previous) =>
      previous ?? MediaBackendProvider(nas),
),
```

- [ ] **Step 3: 运行分析**

Run: `flutter analyze`

Expected: 不新增和本任务相关的 analyzer 问题。仓库已有 lint 保持记录即可。

- [ ] **Step 4: 提交**

```bash
git add lib/providers/media_backend_provider.dart lib/main.dart
git commit -m "feat: provide media backend abstraction"
```

## Task 6: 首页迁移样板

**Files:**
- Modify: `lib/screens/media_list_screen.dart`
- Optional Modify: `lib/services/home_data_cache.dart`

- [ ] **Step 1: 替换首页数据入口**

将 `_fetchHomeData()` 和 `_backgroundRefresh()` 中的：

```dart
final api = FeiniuApi(provider);
```

替换为：

```dart
final backend = context.read<MediaBackendProvider>().backend;
```

首页仍需要旧 UI 模型时，先用临时本地转换函数把 `MediaCatalog` / `MediaItemSummary` 转回现有 `MediaItem` / `MediaLibraryItem`。这一步是过渡，不允许扩散到其它文件。

- [ ] **Step 2: 保留旧缓存策略**

如果 `HomeDataCache` 仍要求飞牛模型，第一阶段不改缓存文件。首页从 backend 拉到公共模型后，立即转换回旧模型并继续存旧缓存。

- [ ] **Step 3: 跑首页相关测试**

Run:

```bash
flutter test test\home_scroll_physics_test.dart
flutter test test\main_navigation_layout_test.dart
flutter analyze
```

Expected: 测试 PASS；analyze 不新增本任务相关问题。

- [ ] **Step 4: 手动验证**

Run: `flutter run`

Expected:

- 登录飞牛后首页分类正常显示。
- 继续观看正常显示。
- 分类预览正常显示。
- 点击卡片进入详情正常。

- [ ] **Step 5: 提交**

```bash
git add lib/screens/media_list_screen.dart lib/services/home_data_cache.dart
git commit -m "refactor: load home media through media backend"
```

## Task 7: 更新共享状态看板

**Files:**
- Modify: `docs/superpowers/public-media-frontend-status.md`

- [ ] **Step 1: 每完成一个 Task 更新状态**

把对应任务从 `未开始` 改为 `完成`，并写上提交 hash。

- [ ] **Step 2: 标记下一步负责人**

如果下一步交给 Claude，把负责人写为 `Claude`；如果交给 Codex，写为 `Codex`。

- [ ] **Step 3: 提交状态文档**

```bash
git add docs/superpowers/public-media-frontend-status.md
git commit -m "docs: update public media frontend status"
```

## 自查清单

- [ ] 没有引入 Emby API 调用。
- [ ] 没有把飞牛专属字段放进公共模型名称。
- [ ] 首页视觉表现没有变化。
- [ ] 飞牛登录、FN Connect、下载入口保持原状。
- [ ] 每个完成任务都有提交 hash 写入状态看板。

