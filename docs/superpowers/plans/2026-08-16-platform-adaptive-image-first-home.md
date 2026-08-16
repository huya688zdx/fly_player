# 平台自适应、图片优先首页 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将飞牛、Emby、Jellyfin 首页改造成共享组件但按平台编排的图片优先界面，修复 Jellyfin 续看、响应式卡宽、长按菜单文字和底栏遮挡，同时保持现有详情与播放链路。

**Architecture:** 展示层用 `HomePresentationProfile` 集中描述平台区块顺序和卡片风格，用纯函数 `HomeResponsiveLayout` 按真实可用宽度计算列数与卡宽；首页渲染器只消费后端中立的 `HomeViewData`。Emby/Jellyfin 的请求差异留在 API 风味层，详情与播放继续使用现有 `MediaBackend`、`EmbeddedDetailLauncher` 和 `ItemPlaybackLauncher`。

**Tech Stack:** Flutter、Dart、Provider、Material 3、Dio、flutter_test、现有动态主题与 `MediaImageRequest` 图片管线。

---

## 文件结构

新增文件：

- `lib/screens/home/home_presentation_profile.dart`：平台区块顺序和媒体库卡片风格。
- `lib/screens/home/home_responsive_layout.dart`：纯响应式尺寸计算，不依赖 Widget。
- `lib/screens/home/home_view_data.dart`：首页一次渲染所需的中立快照。
- `lib/screens/home/widgets/home_adaptive_pager.dart`：按计算结果完整分页的通用横向容器。
- `lib/screens/home/widgets/home_catalog_section.dart`：图片优先的媒体库入口。
- `lib/screens/home/widgets/home_continue_watching_section.dart`：续看图片、进度、详情/播放/长按边界。
- `lib/screens/home/widgets/home_section_header.dart`：统一区块标题和数量。
- `lib/ui/main_navigation_metrics.dart`：悬浮底栏与内容安全区共用尺寸。
- 对应的 `test/screens/home/`、`test/widgets/` 和 `test/ui/` 测试文件。

修改文件：

- `lib/api/jellyfin_api.dart`：Jellyfin 续看改走 `IsResumable` 查询。
- `lib/api/emby_api.dart`：全局和指定剧集共用 NextUp 请求。
- `lib/media_backend/media_backend.dart`：新增默认空的首页下一集接口。
- `lib/media_backend/emby/emby_media_backend.dart`：实现首页下一集映射。
- `lib/screens/media_list_screen.dart`：加载并维护 `HomeViewData`，接线详情和直接播放。
- `lib/screens/media_list_screen_widgets.dart`：按 profile 构建区块并移除旧固定宽度组件。
- `lib/ui/layout_adaptive.dart`：删除首页续看/媒体库固定卡宽，只保留其它页面仍需的布局数据。
- `lib/widgets/common/app_action_sheet.dart`：修复二次缩放、颜色语义和响应式列数。
- `lib/main.dart`：底栏使用统一尺寸常量。
- 现有相关测试中的 API 方法签名和布局断言。

## Task 1：平台展示配置

**Files:**
- Create: `lib/screens/home/home_presentation_profile.dart`
- Create: `test/screens/home/home_presentation_profile_test.dart`

- [ ] **Step 1: 写失败测试，固定三平台区块顺序和媒体库样式**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_backend_kind.dart';
import 'package:fly_player/screens/home/home_presentation_profile.dart';

void main() {
  test('飞牛首页先媒体库，保留海报簇', () {
    final profile = HomePresentationProfile.forKind(MediaBackendKind.feiniu);
    expect(profile.catalogStyle, HomeCatalogStyle.posterMosaic);
    expect(profile.sectionOrder, <HomeSectionKind>[
      HomeSectionKind.catalogs,
      HomeSectionKind.continueWatching,
      HomeSectionKind.summary,
      HomeSectionKind.catalogPreviews,
    ]);
  });

  test('Emby 首页续看优先，媒体库使用横向图片', () {
    final profile = HomePresentationProfile.forKind(MediaBackendKind.emby);
    expect(profile.catalogStyle, HomeCatalogStyle.landscapeArtwork);
    expect(profile.sectionOrder, <HomeSectionKind>[
      HomeSectionKind.continueWatching,
      HomeSectionKind.catalogs,
      HomeSectionKind.nextUp,
      HomeSectionKind.latest,
      HomeSectionKind.catalogPreviews,
    ]);
  });

  test('Jellyfin 首页续看和下一集优先', () {
    final profile = HomePresentationProfile.forKind(MediaBackendKind.jellyfin);
    expect(profile.catalogStyle, HomeCatalogStyle.artworkGrid);
    expect(profile.sectionOrder, <HomeSectionKind>[
      HomeSectionKind.continueWatching,
      HomeSectionKind.nextUp,
      HomeSectionKind.latest,
      HomeSectionKind.catalogs,
      HomeSectionKind.catalogPreviews,
    ]);
  });
}
```

- [ ] **Step 2: 运行测试，确认因类型不存在而失败**

Run: `flutter test test/screens/home/home_presentation_profile_test.dart`

Expected: FAIL，提示找不到 `home_presentation_profile.dart` 或相关类型。

- [ ] **Step 3: 实现不可变展示配置**

```dart
import '../../media_backend/media_backend_kind.dart';

enum HomeSectionKind {
  catalogs,
  continueWatching,
  summary,
  nextUp,
  latest,
  catalogPreviews,
}

enum HomeCatalogStyle { posterMosaic, landscapeArtwork, artworkGrid }

class HomePresentationProfile {
  const HomePresentationProfile({
    required this.sectionOrder,
    required this.catalogStyle,
  });

  final List<HomeSectionKind> sectionOrder;
  final HomeCatalogStyle catalogStyle;

  static HomePresentationProfile forKind(MediaBackendKind kind) {
    return switch (kind) {
      MediaBackendKind.feiniu => const HomePresentationProfile(
        catalogStyle: HomeCatalogStyle.posterMosaic,
        sectionOrder: <HomeSectionKind>[
          HomeSectionKind.catalogs,
          HomeSectionKind.continueWatching,
          HomeSectionKind.summary,
          HomeSectionKind.catalogPreviews,
        ],
      ),
      MediaBackendKind.emby => const HomePresentationProfile(
        catalogStyle: HomeCatalogStyle.landscapeArtwork,
        sectionOrder: <HomeSectionKind>[
          HomeSectionKind.continueWatching,
          HomeSectionKind.catalogs,
          HomeSectionKind.nextUp,
          HomeSectionKind.latest,
          HomeSectionKind.catalogPreviews,
        ],
      ),
      MediaBackendKind.jellyfin => const HomePresentationProfile(
        catalogStyle: HomeCatalogStyle.artworkGrid,
        sectionOrder: <HomeSectionKind>[
          HomeSectionKind.continueWatching,
          HomeSectionKind.nextUp,
          HomeSectionKind.latest,
          HomeSectionKind.catalogs,
          HomeSectionKind.catalogPreviews,
        ],
      ),
    };
  }
}
```

- [ ] **Step 4: 运行测试并提交**

Run: `flutter test test/screens/home/home_presentation_profile_test.dart`

Expected: PASS。

```bash
git add lib/screens/home/home_presentation_profile.dart test/screens/home/home_presentation_profile_test.dart
git commit -m "feat: add backend-aware home presentation profiles"
```

## Task 2：响应式卡片尺寸计算

**Files:**
- Create: `lib/screens/home/home_responsive_layout.dart`
- Create: `test/screens/home/home_responsive_layout_test.dart`

- [ ] **Step 1: 写失败测试，覆盖宽度、文字缩放、分页和旋转恢复**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/screens/home/home_responsive_layout.dart';

void main() {
  test('续看列数由真实可用宽度计算', () {
    expect(HomeResponsiveLayout.resolve(availableWidth: 336, itemCount: 8).columns, 2);
    expect(HomeResponsiveLayout.resolve(availableWidth: 570, itemCount: 8).columns, 3);
    expect(HomeResponsiveLayout.resolve(availableWidth: 800, itemCount: 8).columns, 4);
  });

  test('卡片均分宽度且没有溢出', () {
    final layout = HomeResponsiveLayout.resolve(
      availableWidth: 570,
      itemCount: 8,
      gap: 10,
    );
    expect(layout.cardWidth * layout.columns + layout.gap * 2, closeTo(570, .001));
    expect(layout.pageCount, 3);
  });

  test('大号文字降低列数，空数据不产生非法尺寸', () {
    expect(
      HomeResponsiveLayout.resolve(
        availableWidth: 336,
        itemCount: 8,
        textScale: 2,
      ).columns,
      1,
    );
    final empty = HomeResponsiveLayout.resolve(availableWidth: 0, itemCount: 0);
    expect(empty.columns, 0);
    expect(empty.cardWidth, 0);
    expect(empty.pageCount, 0);
  });

  test('宽度变化后按第一个可见条目恢复页码', () {
    final layout = HomeResponsiveLayout.resolve(availableWidth: 800, itemCount: 8);
    expect(layout.pageForFirstItem(5), 1);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/screens/home/home_responsive_layout_test.dart`

Expected: FAIL，提示 `HomeResponsiveLayout` 不存在。

- [ ] **Step 3: 实现纯布局计算器**

```dart
import 'dart:math';

class HomeResponsiveLayout {
  const HomeResponsiveLayout({
    required this.columns,
    required this.cardWidth,
    required this.gap,
    required this.pageCount,
  });

  final int columns;
  final double cardWidth;
  final double gap;
  final int pageCount;

  static HomeResponsiveLayout resolve({
    required double availableWidth,
    required int itemCount,
    double idealCardWidth = 190,
    double gap = 10,
    double textScale = 1,
    int maxColumns = 5,
  }) {
    if (availableWidth <= 0 || itemCount <= 0) {
      return HomeResponsiveLayout(columns: 0, cardWidth: 0, gap: gap, pageCount: 0);
    }
    final adjustedIdeal = idealCardWidth * textScale.clamp(1, 1.25).toDouble();
    final candidate = ((availableWidth + gap) / (adjustedIdeal + gap)).round();
    final columns = min(itemCount, candidate.clamp(1, maxColumns).toInt());
    final cardWidth = (availableWidth - gap * (columns - 1)) / columns;
    return HomeResponsiveLayout(
      columns: columns,
      cardWidth: cardWidth,
      gap: gap,
      pageCount: (itemCount / columns).ceil(),
    );
  }

  int pageForFirstItem(int itemIndex) {
    if (columns == 0 || pageCount == 0) return 0;
    return (itemIndex.clamp(0, columns * pageCount - 1) ~/ columns)
        .clamp(0, pageCount - 1);
  }
}
```

- [ ] **Step 4: 运行测试并提交**

Run: `flutter test test/screens/home/home_responsive_layout_test.dart`

Expected: PASS。

```bash
git add lib/screens/home/home_responsive_layout.dart test/screens/home/home_responsive_layout_test.dart
git commit -m "feat: calculate responsive home card widths"
```

## Task 3：修复 Jellyfin 继续观看请求

**Files:**
- Modify: `lib/api/jellyfin_api.dart`
- Modify: `test/api/jellyfin_api_test.dart`

- [ ] **Step 1: 在 Jellyfin API 测试中加入可捕获请求的 Dio adapter**

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

class _CaptureAdapter implements HttpClientAdapter {
  RequestOptions? request;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      jsonEncode(<String, Object?>{'Items': <Object?>[]}),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }
}
```

- [ ] **Step 2: 写失败测试，要求 Jellyfin 不再访问 `/Items/Resume`**

```dart
test('Jellyfin 续看使用 IsResumable 并按最近播放排序', () async {
  final adapter = _CaptureAdapter();
  final api = JellyfinApi(dio: Dio(BaseOptions())..httpClientAdapter = adapter);

  await api.getResumeItems(
    serverUrl: 'https://jellyfin.example.test',
    userId: 'user-1',
    accessToken: 'tok',
    limit: 20,
    fields: 'UserData,PrimaryImageAspectRatio',
  );

  final request = adapter.request!;
  expect(request.uri.path, '/Users/user-1/Items');
  expect(request.uri.queryParameters['Filters'], 'IsResumable');
  expect(request.uri.queryParameters['Recursive'], 'true');
  expect(request.uri.queryParameters['IncludeItemTypes'], 'Movie,Episode');
  expect(request.uri.queryParameters['SortBy'], 'DatePlayed');
  expect(request.uri.queryParameters['SortOrder'], 'Descending');
  expect(request.uri.queryParameters['Limit'], '20');
});
```

- [ ] **Step 3: 运行测试确认仍走 Resume 路径**

Run: `flutter test test/api/jellyfin_api_test.dart`

Expected: FAIL，实际路径是 `/Users/user-1/Items/Resume`。

- [ ] **Step 4: 在 `JellyfinApi` 覆写续看请求**

```dart
@override
Future<List<Map<String, Object?>>> getResumeItems({
  required String serverUrl,
  required String userId,
  required String accessToken,
  int limit = 20,
  String fields = '',
}) {
  return getItems(
    serverUrl: serverUrl,
    userId: userId,
    accessToken: accessToken,
    limit: limit,
    isResumable: true,
    recursive: true,
    includeItemTypes: 'Movie,Episode',
    fields: fields,
    sortBy: 'DatePlayed',
    sortOrder: 'Descending',
  );
}
```

- [ ] **Step 5: 运行 API 与后端续看测试并提交**

Run: `flutter test test/api/jellyfin_api_test.dart test/api/emby_api_test.dart test/media_backend/emby_media_backend_test.dart`

Expected: PASS，Emby 原有 Resume 测试仍通过。

```bash
git add lib/api/jellyfin_api.dart test/api/jellyfin_api_test.dart
git commit -m "fix: load Jellyfin resumable items from user items"
```

## Task 4：首页“下一集”公共接口

**Files:**
- Modify: `lib/media_backend/media_backend.dart`
- Modify: `lib/api/emby_api.dart`
- Modify: `lib/media_backend/emby/emby_media_backend.dart`
- Modify: `test/api/emby_api_test.dart`
- Modify: `test/media_backend/emby_media_backend_test.dart`

- [ ] **Step 1: 写 API 失败测试，允许 NextUp 不传 SeriesId**

```dart
test('getNextUpEpisodes 不传 seriesId 时加载首页全局下一集', () async {
  late RequestOptions captured;
  final adapter = _FakeDioAdapter((options) {
    captured = options;
    return const _JsonResponse(<String, Object?>{'Items': <Object?>[]});
  });
  final api = EmbyApi(dio: Dio(BaseOptions())..httpClientAdapter = adapter);

  await api.getNextUpEpisodes(
    serverUrl: 'https://emby.example.test',
    userId: 'user-1',
    accessToken: 'tok',
    limit: 8,
  );

  expect(captured.uri.path, '/Shows/NextUp');
  expect(captured.uri.queryParameters.containsKey('SeriesId'), isFalse);
  expect(captured.uri.queryParameters['Limit'], '8');
});
```

- [ ] **Step 2: 写后端失败测试，要求公共卡片映射保留季集和进度**

```dart
test('getNextUpItems：全局 NextUp 映射为公共卡片', () async {
  final api = _FakeEmbyApi(nextUpItems: <Map<String, Object?>>[
    <String, Object?>{
      'Id': 'ep-10',
      'Name': '下一集',
      'Type': 'Episode',
      'SeriesId': 'series-1',
      'SeriesName': '白箱',
      'ParentIndexNumber': 1,
      'IndexNumber': 10,
      'RunTimeTicks': 12000000000,
      'UserData': <String, Object?>{'PlaybackPositionTicks': 0},
    },
  ]);
  final backend = EmbyMediaBackend(api: api, connection: connection);

  final items = await backend.getNextUpItems(limit: 8);

  expect(api.lastNextUpSeriesId, isEmpty);
  expect(api.lastNextUpLimit, 8);
  expect(items.single.id, 'ep-10');
  expect(items.single.seriesId, 'series-1');
  expect(items.single.episodeNumber, 10);
});
```

- [ ] **Step 3: 运行测试确认接口和可选参数尚不存在**

Run: `flutter test test/api/emby_api_test.dart test/media_backend/emby_media_backend_test.dart`

Expected: FAIL，`seriesId` 仍必填且 `MediaBackend.getNextUpItems` 不存在。

- [ ] **Step 4: 增加默认空接口并放宽 API 参数**

在 `MediaBackend` 添加：

```dart
Future<List<MediaItemCard>> getNextUpItems({int limit = 20}) async =>
    const <MediaItemCard>[];
```

将 `EmbyApi.getNextUpEpisodes` 的参数和 query 改为：

```dart
Future<List<Map<String, Object?>>> getNextUpEpisodes({
  required String serverUrl,
  required String userId,
  required String accessToken,
  String seriesId = '',
  int limit = 1,
  String fields = 'Overview,UserData,MediaStreams',
}) async {
  final normalizedServerUrl = normalizeServerUrl(serverUrl);
  final query = <String, Object?>{
    'api_key': accessToken,
    'UserId': userId.trim(),
    if (seriesId.trim().isNotEmpty) 'SeriesId': seriesId.trim(),
    'Limit': limit,
    if (fields.trim().isNotEmpty) 'Fields': fields.trim(),
  };
  return _getItemList('$normalizedServerUrl/Shows/NextUp', query);
}
```

- [ ] **Step 5: 在 `EmbyMediaBackend` 实现全局下一集**

```dart
@override
Future<List<MediaItemCard>> getNextUpItems({int limit = 20}) async {
  final items = await api.getNextUpEpisodes(
    serverUrl: _serverUrl,
    userId: _userId,
    accessToken: _token,
    limit: limit,
    fields: _cardFields,
  );
  return items
      .map((item) => mapEmbyItemCard(
            item,
            serverUrl: _serverUrl,
            token: _token,
          ))
      .toList(growable: false);
}
```

同步所有测试 fake 的 override：`required String seriesId` 改为 `String seriesId = ''`。

- [ ] **Step 6: 运行相关测试并提交**

Run: `flutter test test/api/emby_api_test.dart test/media_backend/emby_media_backend_test.dart test/media_backend/media_backend_default_action_test.dart`

Expected: PASS。

```bash
git add lib/media_backend/media_backend.dart lib/api/emby_api.dart lib/media_backend/emby/emby_media_backend.dart test/api/emby_api_test.dart test/media_backend/emby_media_backend_test.dart test/media_backend/media_backend_default_action_test.dart
git commit -m "feat: expose global next-up items to home"
```

## Task 5：首页快照和可选区块独立加载

**Files:**
- Create: `lib/screens/home/home_view_data.dart`
- Create: `test/screens/home/home_view_data_test.dart`
- Modify: `lib/screens/media_list_screen.dart:83-775`

- [ ] **Step 1: 写失败测试，固定快照 copyWith 行为**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/screens/home/home_view_data.dart';

void main() {
  test('copyWith 只替换指定首页区块', () {
    const empty = HomeViewData.empty();
    final next = empty.copyWith(summary: <String, dynamic>{'total': 9});
    expect(next.summary['total'], 9);
    expect(next.catalogs, isEmpty);
    expect(next.continueWatching, isEmpty);
    expect(next.nextUp, isEmpty);
    expect(next.latest, isEmpty);
  });
}
```

- [ ] **Step 2: 运行测试确认类型不存在**

Run: `flutter test test/screens/home/home_view_data_test.dart`

Expected: FAIL。

- [ ] **Step 3: 创建首页展示快照**

```dart
import '../../models/media_item.dart';
import '../../models/media_library_item.dart';
import '../../ui/detail_artwork_resolver.dart';

class HomeViewData {
  const HomeViewData({
    this.catalogs = const <MediaItem>[],
    this.catalogPreviewItems = const <String, List<MediaLibraryItem>>{},
    this.continueWatching = const <MediaLibraryItem>[],
    this.nextUp = const <MediaLibraryItem>[],
    this.latest = const <MediaLibraryItem>[],
    this.summary = const <String, dynamic>{},
    this.catalogImageRequests = const <String, List<MediaImageRequest>>{},
    this.itemImageRequests = const <String, MediaImageRequest>{},
    this.backdropImageRequests = const <String, MediaImageRequest>{},
  });

  const HomeViewData.empty() : this();

  final List<MediaItem> catalogs;
  final Map<String, List<MediaLibraryItem>> catalogPreviewItems;
  final List<MediaLibraryItem> continueWatching;
  final List<MediaLibraryItem> nextUp;
  final List<MediaLibraryItem> latest;
  final Map<String, dynamic> summary;
  final Map<String, List<MediaImageRequest>> catalogImageRequests;
  final Map<String, MediaImageRequest> itemImageRequests;
  final Map<String, MediaImageRequest> backdropImageRequests;

  HomeViewData copyWith({
    List<MediaItem>? catalogs,
    Map<String, List<MediaLibraryItem>>? catalogPreviewItems,
    List<MediaLibraryItem>? continueWatching,
    List<MediaLibraryItem>? nextUp,
    List<MediaLibraryItem>? latest,
    Map<String, dynamic>? summary,
    Map<String, List<MediaImageRequest>>? catalogImageRequests,
    Map<String, MediaImageRequest>? itemImageRequests,
    Map<String, MediaImageRequest>? backdropImageRequests,
  }) => HomeViewData(
    catalogs: catalogs ?? this.catalogs,
    catalogPreviewItems: catalogPreviewItems ?? this.catalogPreviewItems,
    continueWatching: continueWatching ?? this.continueWatching,
    nextUp: nextUp ?? this.nextUp,
    latest: latest ?? this.latest,
    summary: summary ?? this.summary,
    catalogImageRequests: catalogImageRequests ?? this.catalogImageRequests,
    itemImageRequests: itemImageRequests ?? this.itemImageRequests,
    backdropImageRequests: backdropImageRequests ?? this.backdropImageRequests,
  );
}
```

- [ ] **Step 4: 将页面状态收敛到 `_homeData`**

在 `media_list_screen.dart` 导入 `home/home_view_data.dart`，用：

```dart
HomeViewData _homeData = const HomeViewData.empty();
```

删除原字段，增加兼容 getter/setter，让现有加载代码逐处迁移时始终写回同一份快照：

```dart
List<MediaItem> get _categories => _homeData.catalogs;
set _categories(List<MediaItem> value) =>
    _homeData = _homeData.copyWith(catalogs: value);

Map<String, List<MediaLibraryItem>> get _itemsByCategory =>
    _homeData.catalogPreviewItems;
set _itemsByCategory(Map<String, List<MediaLibraryItem>> value) =>
    _homeData = _homeData.copyWith(catalogPreviewItems: value);

List<MediaLibraryItem> get _continueWatching => _homeData.continueWatching;
set _continueWatching(List<MediaLibraryItem> value) =>
    _homeData = _homeData.copyWith(continueWatching: value);

List<MediaLibraryItem> get _nextUp => _homeData.nextUp;
set _nextUp(List<MediaLibraryItem> value) =>
    _homeData = _homeData.copyWith(nextUp: value);

List<MediaLibraryItem> get _latest => _homeData.latest;
set _latest(List<MediaLibraryItem> value) =>
    _homeData = _homeData.copyWith(latest: value);
```

对 `_mediaSummary`、`_catalogImageRequests`、`_itemImageRequests`、`_backdropImageRequests` 使用同样的明确 getter/setter 映射。飞牛 `HomeDataCache` 读写继续使用现有字段结构，在边界处转换。

- [ ] **Step 5: 为续看、下一集和最新入库建立独立失败边界**

在 `_MediaListScreenState` 添加：

```dart
Future<List<MediaItemCard>> _loadOptionalCards(
  String label,
  Future<List<MediaItemCard>> Function() loader,
) async {
  try {
    return await loader();
  } catch (error) {
    debugPrint('[UI][HOME] optional section failed $label: $error');
    return const <MediaItemCard>[];
  }
}

Future<_MediaItemsWithImages> _loadContinueWatchingSafely(
  MediaBackend backend,
  FeiniuApi api,
  DetailArtworkResolver resolver, {
  bool forceRefresh = false,
}) async {
  try {
    return await _loadContinueWatching(
      backend,
      api,
      resolver,
      forceRefresh: forceRefresh,
    );
  } catch (error) {
    debugPrint('[UI][HOME] optional section failed continueWatching: $error');
    return (
      items: <MediaLibraryItem>[],
      imageRequests: <String, MediaImageRequest>{},
      backdropImageRequests: <String, MediaImageRequest>{},
    );
  }
}
```

`_fetchHomeData()` 和 `_backgroundRefresh()` 的首批并行请求包含：

```dart
final profile = HomePresentationProfile.forKind(backend.capabilities.kind);
final loadNextUp = profile.sectionOrder.contains(HomeSectionKind.nextUp)
    ? _loadOptionalCards('nextUp', () => backend.getNextUpItems(limit: 8))
    : Future<List<MediaItemCard>>.value(const <MediaItemCard>[]);
final loadLatest = profile.sectionOrder.contains(HomeSectionKind.latest)
    ? _loadOptionalCards('latest', () => backend.getLatestItems(limit: 12))
    : Future<List<MediaItemCard>>.value(const <MediaItemCard>[]);
final primaryResults = await Future.wait<Object?>(<Future<Object?>>[
  backend.getCatalogs(),
  backend.getHomeSummary(),
  _loadContinueWatchingSafely(backend, api, resolver),
  loadNextUp,
  loadLatest,
]);
```

把公共卡片经现有 `_cardsToMediaItems()` 转换并合并图片请求；续看最多保留 8 条。删除服务器族空续看时用分类内容伪造数据的任何路径，飞牛现有进度回退保持。

- [ ] **Step 6: 运行快照、后端和首页源测试并提交**

Run: `flutter test test/screens/home/home_view_data_test.dart test/media_backend/emby_media_backend_test.dart test/home_scroll_physics_test.dart`

Expected: PASS。

```bash
git add lib/screens/home/home_view_data.dart lib/screens/media_list_screen.dart test/screens/home/home_view_data_test.dart
git commit -m "refactor: model home data as independent sections"
```

## Task 6：响应式分页器和图片优先首页组件

**Files:**
- Create: `lib/screens/home/widgets/home_adaptive_pager.dart`
- Create: `lib/screens/home/widgets/home_section_header.dart`
- Create: `lib/screens/home/widgets/home_continue_watching_section.dart`
- Create: `lib/screens/home/widgets/home_catalog_section.dart`
- Create: `test/widgets/home_adaptive_pager_test.dart`
- Create: `test/widgets/home_continue_watching_section_test.dart`
- Create: `test/widgets/home_catalog_section_test.dart`

- [ ] **Step 1: 写分页器失败测试，验证不同宽度完整显示不同数量**

```dart
testWidgets('分页器按约束宽度改变列数且不裁半张卡', (tester) async {
  Future<void> pump(double width) async {
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: HomeAdaptivePager<int>(
            items: List<int>.generate(8, (index) => index),
            itemId: (item) => '$item',
            idealItemWidth: 190,
            itemAspectRatio: 16 / 10,
            itemBuilder: (context, item, width) => SizedBox(
              key: ValueKey<int>(item),
              width: width,
            ),
          ),
        ),
      ),
    ));
  }

  await pump(336);
  expect(tester.getSize(find.byKey(const ValueKey<int>(0))).width, closeTo(163, .01));
  expect(tester.getSize(find.byKey(const ValueKey<int>(1))).width, closeTo(163, .01));
  expect(tester.takeException(), isNull);

  await pump(570);
  expect(tester.getSize(find.byKey(const ValueKey<int>(0))).width, closeTo(183.33, .02));
  expect(tester.takeException(), isNull);
});
```

- [ ] **Step 2: 实现 `HomeAdaptivePager` 的公开 API**

组件必须：

```dart
class HomeAdaptivePager<T> extends StatefulWidget {
  const HomeAdaptivePager({
    super.key,
    required this.items,
    required this.itemId,
    required this.itemBuilder,
    required this.idealItemWidth,
    required this.itemAspectRatio,
    this.gap = 10,
    this.maxColumns = 5,
    this.textLinesHeight = 44,
    this.onFirstVisibleItemIdChanged,
  });

  final List<T> items;
  final String Function(T item) itemId;
  final Widget Function(BuildContext context, T item, double width) itemBuilder;
  final double idealItemWidth;
  final double itemAspectRatio;
  final double gap;
  final int maxColumns;
  final double textLinesHeight;
  final ValueChanged<String>? onFirstVisibleItemIdChanged;
}
```

内部用 `LayoutBuilder` + `HomeResponsiveLayout.resolve()`；`PageView.builder` 每页构建一个 `Row`，最后一页缺少的槽位用 `SizedBox(width: cardWidth)` 保持列宽。只有 `pageCount > 1` 时显示语义标签为“第 X 页，共 Y 页”的指示器。组件记录当前页第一项的 `itemId`；宽度或数据变化时先在新列表中查回该 id 的 index，再调用 `pageForFirstItem()` 重建 `PageController(initialPage: ...)`。若该 id 已被移除，则回退到距离原 index 最近的有效项目。

- [ ] **Step 3: 运行分页器测试确认通过**

Run: `flutter test test/widgets/home_adaptive_pager_test.dart`

Expected: PASS，无 overflow 异常。

- [ ] **Step 4: 写续看组件失败测试，固定三个点击区域和无二级页入口**

```dart
const continueFixture = HomeContinueCardData(
  id: 'item-1',
  title: '吹响吧！上低音号',
  contextText: '第 1 季 · 第 9 集 · 剩 18 分钟',
  progress: .5,
  imageRequest: MediaImageRequest.empty,
  downloaded: false,
);

Widget testApp(Widget child) => MaterialApp(
  theme: AppThemeBuilder.build(AppThemePreset.midnight),
  home: Scaffold(body: child),
);

testWidgets('续看卡主体、播放键、长按分别调用独立回调', (tester) async {
  var detail = 0;
  var play = 0;
  var longPress = 0;
  await tester.pumpWidget(testApp(
    HomeContinueWatchingSection(
      items: <HomeContinueCardData>[continueFixture],
      onOpenDetail: (_) => detail++,
      onPlay: (_) => play++,
      onLongPress: (_) => longPress++,
    ),
  ));

  expect(find.text('查看全部'), findsNothing);
  await tester.tap(find.byKey(const ValueKey<String>('continue-card-item-1')));
  expect(detail, 1);
  await tester.tap(find.byKey(const ValueKey<String>('continue-play-item-1')));
  expect(play, 1);
  await tester.longPress(find.byKey(const ValueKey<String>('continue-card-item-1')));
  expect(longPress, 1);
});
```

组件局部展示模型不携带后端 DTO：

```dart
class HomeContinueCardData {
  const HomeContinueCardData({
    required this.id,
    required this.title,
    required this.contextText,
    required this.progress,
    required this.imageRequest,
    required this.downloaded,
  });

  final String id;
  final String title;
  final String contextText;
  final double progress;
  final MediaImageRequest imageRequest;
  final bool downloaded;
}
```

- [ ] **Step 5: 实现续看组件**

使用 `HomeAdaptivePager`，参数为 `idealItemWidth: 190`、`itemAspectRatio: 16 / 10`、`maxColumns: 5`。图片 `BoxFit.cover`，底部固定渐变遮罩；标题 `w500`，元信息 `w400`；进度使用 `context.appColors.accent`；播放按钮背景使用 `Theme.of(context).colorScheme.primary`，前景使用 `onPrimary`。标题右侧只显示 `${items.length} 条`，没有点击回调。

- [ ] **Step 6: 写媒体库组件失败测试并实现三种图片形态**

测试要求：

```dart
expect(
  tester.widget<Image>(find.byKey(const ValueKey<String>('catalog-image-lib-1'))).fit,
  BoxFit.cover,
);
expect(find.byKey(const ValueKey<String>('catalog-mini-poster-lib-1')), findsNothing);
```

实现要求：

- `posterMosaic`：2–3 张图片并排或轻叠并铺满卡片主体，标题位于底部渐变之上。
- `landscapeArtwork`：单张图片铺满 `3:2` 横向卡片。
- `artworkGrid`：单张图片铺满接近方形的卡片。
- 缺图时使用 `surfaceStrong` + 媒体类型图标。
- 卡片标题 `w500`，不设置 `TextScaler.linear(1)`。

Run: `flutter test test/widgets/home_continue_watching_section_test.dart test/widgets/home_catalog_section_test.dart`

Expected: PASS。

- [ ] **Step 7: 提交共享首页组件**

```bash
git add lib/screens/home/widgets test/widgets/home_adaptive_pager_test.dart test/widgets/home_continue_watching_section_test.dart test/widgets/home_catalog_section_test.dart
git commit -m "feat: add responsive image-first home sections"
```

## Task 7：将平台编排、下一集和直接播放接入首页

**Files:**
- Modify: `lib/screens/media_list_screen.dart:83-1280`
- Modify: `lib/screens/media_list_screen_widgets.dart:1-820`
- Modify: `lib/ui/layout_adaptive.dart:4-147`
- Create: `test/screens/media_list_home_composition_test.dart`

- [ ] **Step 1: 写首页组合失败测试**

直接测试可见区块过滤函数：

```dart
test('空区块被隐藏，Jellyfin 剩余区块保持配置顺序', () {
  final kinds = visibleHomeSections(
    profile: HomePresentationProfile.forKind(MediaBackendKind.jellyfin),
    hasCatalogs: true,
    hasContinueWatching: true,
    hasSummary: false,
    hasNextUp: false,
    hasLatest: true,
  );
  expect(kinds, <HomeSectionKind>[
    HomeSectionKind.continueWatching,
    HomeSectionKind.latest,
    HomeSectionKind.catalogs,
    HomeSectionKind.catalogPreviews,
  ]);
});
```

- [ ] **Step 2: 运行测试确认组合函数不存在**

Run: `flutter test test/screens/media_list_home_composition_test.dart`

Expected: FAIL。

- [ ] **Step 3: 实现空区块过滤和 profile 顺序渲染**

在 `home_presentation_profile.dart` 添加：

```dart
List<HomeSectionKind> visibleHomeSections({
  required HomePresentationProfile profile,
  required bool hasCatalogs,
  required bool hasContinueWatching,
  required bool hasSummary,
  required bool hasNextUp,
  required bool hasLatest,
}) {
  return profile.sectionOrder.where((kind) => switch (kind) {
    HomeSectionKind.catalogs => hasCatalogs,
    HomeSectionKind.continueWatching => hasContinueWatching,
    HomeSectionKind.summary => hasSummary,
    HomeSectionKind.nextUp => hasNextUp,
    HomeSectionKind.latest => hasLatest,
    HomeSectionKind.catalogPreviews => hasCatalogs,
  }).toList(growable: false);
}
```

`media_list_screen_widgets.dart` 用该结果构建一个 `SliverList`，每种 `HomeSectionKind` 只映射到共享组件；不得在卡片 Widget 内判断 Emby/Jellyfin。

- [ ] **Step 4: 接入续看详情、播放和长按**

详情沿用：

```dart
onOpenDetail: (item) => _openItemDetail(
  item,
  heroTag: 'home_continue_${item.guid}',
),
```

新增直接续播方法：

```dart
Future<void> _playContinueItem(MediaLibraryItem item) async {
  _pendingContinueWatchingRefresh = true;
  await const ItemPlaybackLauncher().open(
    context,
    itemGuid: item.guid,
    fallbackTitle: item.displayTitle,
  );
  if (!mounted) return;
  unawaited(_refreshContinueWatching());
}
```

播放按钮调用 `_playContinueItem`；长按继续调用 `_showContinueWatchingActionsV2`。删除续看标题上的“查看全部”入口和任何新路由。

- [ ] **Step 5: 接入下一集、最新入库和媒体库图片**

- `nextUp`、`latest` 使用现有 `MediaPosterCard` 图片请求和详情回调。
- 服务器族媒体库卡使用 `catalogImageRequests` 的第一张真实图片。
- 飞牛媒体库卡使用最多三张 `catalogImageRequests`。
- 所有图片请求继续走 `preferPreservedImageRequest`/`MediaImageRequest`，不拼新的裸 URL 缓存键。

- [ ] **Step 6: 删除旧固定首页尺寸**

从 `MediaLayoutProfile` 删除仅被旧首页消费的：

```dart
categoryStripHeight
categoryCardWidth
categoryMiniPosterWidth
categoryMiniPosterHeight
continueCardWidth
continueImageHeight
continueRowHeight
```

保留固定的图片请求/解码宽度 getter，避免旋转和分屏改变图片缓存键。删除旧 `_CategoryPosterCard`、`_PosterCluster` 和 `_buildContinueItem`，避免两套首页组件并存。

- [ ] **Step 7: 调整首页文字层级**

- AppBar 和区块标题：`w600`。
- 卡片标题：`w500`。
- 元信息：`w400`。
- 统计数字从 `FontWeight.bold` 改为 `w600`。
- 删除首页标题中的 `w700` 和强制 `TextScaler.linear(1)`。

- [ ] **Step 8: 运行首页组合和既有布局测试并提交**

Run: `flutter test test/screens/media_list_home_composition_test.dart test/home_scroll_physics_test.dart test/widget_test.dart`

Expected: PASS。

```bash
git add lib/screens/media_list_screen.dart lib/screens/media_list_screen_widgets.dart lib/ui/layout_adaptive.dart test/screens/media_list_home_composition_test.dart
git commit -m "feat: compose image-first home by backend profile"
```

## Task 8：长按菜单的文字、颜色和密度

**Files:**
- Modify: `lib/widgets/common/app_action_sheet.dart`
- Create: `test/widgets/app_action_sheet_test.dart`

- [ ] **Step 1: 写失败 Widget 测试，覆盖二次缩放和响应式列数**

```dart
testWidgets('动作菜单不手工二次缩放，普通宽度两列，大字单列', (tester) async {
  await pumpSheet(tester, width: 390, textScale: 1);
  final normalButton = tester.widget<Text>(find.text('查看详情'));
  expect(normalButton.style?.fontSize, 16);
  expect(find.byKey(const ValueKey<String>('action-sheet-grid-2')), findsOneWidget);

  await tester.binding.setSurfaceSize(const Size(320, 700));
  await pumpSheet(tester, width: 320, textScale: 2);
  final largeButton = tester.widget<Text>(find.text('查看详情'));
  expect(largeButton.style?.fontSize, 16);
  expect(find.byKey(const ValueKey<String>('action-sheet-grid-1')), findsOneWidget);
  expect(tester.takeException(), isNull);
});
```

`pumpSheet` 使用 `AppLocalizations.localizationsDelegates`、`supportedLocales` 和现有 `AppThemeBuilder` 包裹测试；调用 `showAppActionSheet` 时显式传 `cancelText: '取消'`。

测试 helper 写成：

```dart
Future<void> pumpSheet(
  WidgetTester tester, {
  required double width,
  required double textScale,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemeBuilder.build(AppThemePreset.midnight),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 700),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAppActionSheet<int>(
                context,
                title: '测试标题',
                cancelText: '取消',
                options: const <AppActionSheetOption<int>>[
                  AppActionSheetOption<int>(value: 1, label: '查看详情'),
                  AppActionSheetOption<int>(value: 2, label: '标为已观看'),
                  AppActionSheetOption<int>(value: 3, label: '收藏'),
                ],
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}
```

- [ ] **Step 2: 运行测试确认当前单列大按钮或字号不符**

Run: `flutter test test/widgets/app_action_sheet_test.dart`

Expected: FAIL。

- [ ] **Step 3: 删除手工 textScale 乘法并实现自适应网格**

```dart
final inheritedScale = media.textScaler.scale(1);
final columns = screenWidth >= 360 && inheritedScale < 1.3 ? 2 : 1;
const buttonFontSize = 16.0;
const buttonHeight = 50.0;
```

使用 `GridView.builder(shrinkWrap: true, physics: NeverScrollableScrollPhysics())` 渲染业务操作；`crossAxisCount: columns`，`mainAxisExtent: buttonHeight`。取消按钮单独放在网格下方。

- [ ] **Step 4: 使用 Material 语义前景色**

常规按钮：`backgroundColor: colors.surfaceStrong`、`foregroundColor: colors.textPrimary`。危险按钮使用下面的确定规则：

```dart
final destructiveBackground = Color.alphaBlend(
  colors.danger.withValues(alpha: .14),
  colors.surfaceStrong,
);
final destructiveForeground =
    ThemeData.estimateBrightnessForColor(destructiveBackground) ==
        Brightness.dark
    ? Colors.white
    : const Color(0xFF1B1B1B);
```

若按钮使用 `colors.accent`，前景必须取 `Theme.of(context).colorScheme.onPrimary`，禁止复用 `textPrimary`。

- [ ] **Step 5: 运行测试并提交**

Run: `flutter test test/widgets/app_action_sheet_test.dart`

Expected: PASS，1.0、1.3、2.0 缩放均无 overflow。

```bash
git add lib/widgets/common/app_action_sheet.dart test/widgets/app_action_sheet_test.dart
git commit -m "fix: make action sheet typography compact and readable"
```

## Task 9：悬浮底栏安全区

**Files:**
- Create: `lib/ui/main_navigation_metrics.dart`
- Create: `test/ui/main_navigation_metrics_test.dart`
- Modify: `lib/main.dart:1045-1110`
- Modify: `lib/screens/media_list_screen_widgets.dart:140-210`
- Modify: `test/main_navigation_layout_test.dart`

- [ ] **Step 1: 写失败测试，固定底栏和内容 inset 使用同一来源**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/ui/main_navigation_metrics.dart';

void main() {
  test('悬浮底栏内容 inset 包含底栏、外边距和系统安全区', () {
    expect(MainNavigationMetrics.contentBottomInset(0), 96);
    expect(MainNavigationMetrics.contentBottomInset(24), 112);
  });
}
```

- [ ] **Step 2: 实现统一尺寸常量**

```dart
abstract final class MainNavigationMetrics {
  static const double barHeight = 72;
  static const double fallbackBottomMargin = 8;
  static const double contentGap = 16;

  static double outerBottomPadding(double safeBottom) =>
      safeBottom > 0 ? safeBottom : fallbackBottomMargin;

  static double contentBottomInset(double safeBottom) =>
      barHeight + outerBottomPadding(safeBottom) + contentGap;
}
```

- [ ] **Step 3: 让底栏和首页共同消费常量**

`main.dart` 中 `_LiquidGlassBottomNavigation` 的 `height: 72` 和底部 fallback 改为 `MainNavigationMetrics`。首页最终 `SliverPadding`：

```dart
final bottomContentInset = widget.secondaryHost
    ? 20.0
    : MainNavigationMetrics.contentBottomInset(
        MediaQuery.viewPaddingOf(context).bottom,
      );
```

最后一个 sliver 的 bottom padding 使用 `bottomContentInset`，不再写死 `20`。

- [ ] **Step 4: 更新源结构测试并运行**

`test/main_navigation_layout_test.dart` 保留 `extendBody: true` 断言，并增加：

```dart
expect(buildSource, contains('MainNavigationMetrics.barHeight'));
expect(buildSource, contains('MainNavigationMetrics.outerBottomPadding'));
```

Run: `flutter test test/ui/main_navigation_metrics_test.dart test/main_navigation_layout_test.dart test/home_scroll_physics_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交安全区修复**

```bash
git add lib/ui/main_navigation_metrics.dart lib/main.dart lib/screens/media_list_screen_widgets.dart test/ui/main_navigation_metrics_test.dart test/main_navigation_layout_test.dart
git commit -m "fix: reserve space for floating bottom navigation"
```

## Task 10：整体验证与清理

**Files:**
- Modify only files already touched when verification finds a scoped defect
- Test: all tests listed above, then the full suite

- [ ] **Step 1: 格式化本功能文件**

Run:

```bash
dart format lib/screens/home lib/screens/media_list_screen.dart lib/screens/media_list_screen_widgets.dart lib/api/jellyfin_api.dart lib/api/emby_api.dart lib/media_backend/media_backend.dart lib/media_backend/emby/emby_media_backend.dart lib/widgets/common/app_action_sheet.dart lib/ui/main_navigation_metrics.dart lib/main.dart test/screens/home test/screens/media_list_home_composition_test.dart test/widgets/home_adaptive_pager_test.dart test/widgets/home_continue_watching_section_test.dart test/widgets/home_catalog_section_test.dart test/widgets/app_action_sheet_test.dart test/ui/main_navigation_metrics_test.dart test/api/jellyfin_api_test.dart test/api/emby_api_test.dart test/media_backend/emby_media_backend_test.dart test/main_navigation_layout_test.dart
```

Expected: 命令成功，无无法解析文件。

- [ ] **Step 2: 运行聚焦测试**

Run:

```bash
flutter test test/screens/home test/screens/media_list_home_composition_test.dart test/widgets/home_adaptive_pager_test.dart test/widgets/home_continue_watching_section_test.dart test/widgets/home_catalog_section_test.dart test/widgets/app_action_sheet_test.dart test/ui/main_navigation_metrics_test.dart test/api/jellyfin_api_test.dart test/api/emby_api_test.dart test/media_backend/emby_media_backend_test.dart test/main_navigation_layout_test.dart test/home_scroll_physics_test.dart
```

Expected: 全部 PASS。

- [ ] **Step 3: 静态分析**

Run: `flutter analyze`

Expected: `No issues found!`；若仓库存在与本任务无关的既有告警，记录完整输出并确认本次改动没有新增告警。

- [ ] **Step 4: 运行完整测试套件**

Run: `flutter test`

Expected: 全部 PASS。

- [ ] **Step 5: 在 Android 设备进行人工验收**

Run: `flutter run`

依次连接飞牛、Emby、Jellyfin，验证：

1. 飞牛媒体库图片簇不再压缩，Emby/Jellyfin 单图铺满入口。
2. 窄屏、横屏、分屏和展开态下续看列数变化且没有裁半张卡。
3. Jellyfin 真实续看出现；空续看时整区隐藏。
4. 卡片进入详情、播放键直接续播、长按菜单动作互不误触。
5. 播放退出后续看进度更新，首页滚动位置和分页位置保留。
6. 动态深浅配色下文字、播放键、进度和危险操作清晰。
7. 首页最后一排可完整滚动到底栏上方。

- [ ] **Step 6: 检查 diff 只包含本功能文件并提交最终清理**

Run: `git status --short` 和 `git diff --check`

Expected: 不包含用户原有的 mpv、下载记录或二进制改动；`git diff --check` 无输出。

如果验证阶段产生了修复，只暂存本计划列出的具体文件后提交。先运行：

```bash
git diff --quiet -- lib/screens/home lib/screens/media_list_screen.dart lib/screens/media_list_screen_widgets.dart lib/api/jellyfin_api.dart lib/api/emby_api.dart lib/media_backend/media_backend.dart lib/media_backend/emby/emby_media_backend.dart lib/widgets/common/app_action_sheet.dart lib/ui/layout_adaptive.dart lib/ui/main_navigation_metrics.dart lib/main.dart test/screens/home test/screens/media_list_home_composition_test.dart test/widgets/home_adaptive_pager_test.dart test/widgets/home_continue_watching_section_test.dart test/widgets/home_catalog_section_test.dart test/widgets/app_action_sheet_test.dart test/ui/main_navigation_metrics_test.dart test/api/jellyfin_api_test.dart test/api/emby_api_test.dart test/media_backend/emby_media_backend_test.dart test/main_navigation_layout_test.dart
```

返回 0 时不创建空提交；返回 1 时只 `git add` 上述路径中实际属于本功能的文件，然后提交：

```bash
git commit -m "test: verify adaptive image-first home"
```
