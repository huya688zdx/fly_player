# 大屏海报浏览页（Poster Browse）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增横屏电视风格的大屏海报浏览页（spec: `docs/superpowers/specs/2026-07-26-poster-browse-design.md`），三后端（飞牛/Emby/Jellyfin）全支持。

**Architecture:** 数据层给 `MediaBackend` 加 `getLatestItems`（默认空实现，行按能力降级隐藏）；UI 层新建 `lib/screens/poster_browse/` 四个文件（行模型/加载器/缩略图条/页面），背景复用 `ImmersiveDetailBackground` + `DynamicPageThemeScope`（pageKey=条目 id，与详情页共享取色缓存）；播放直接走现成的 `ItemPlaybackLauncher` / `TvSeasonPlaybackLauncher`（二者内部已绑定 NativePlaybackReentry 并启动原生壳）。

**Tech Stack:** Flutter/Dart，flutter_test 手写 Fake（项目无 mocktail/mockito），l10n 走 arb + `flutter gen-l10n`。

**红线（全程遵守）：**
- UI 文案一律 `AppLocalizations` getter，禁止硬编码中文、禁止 `_t()` 间接层。
- 禁止 BackdropFilter/玻璃效果；背景切换用纯 `FadeTransition`/`AnimatedSwitcher`。
- 禁止低清图铺底（垫底图与主图不同源会闪）；图未到显示纯 ambient 色底。
- 新代码禁止 `== MediaBackendKind.emby` / `isEmby` 判断（边界测试守卫）；服务器族用 `isServerFamily`，飞牛旁路允许 `== MediaBackendKind.feiniu`（数据层）。
- `lib/screens/media_list_screen*.dart` 内有 GBK 乱码注释，Edit 时用精确唯一锚点、别动无关行。

---

## 文件结构

| 文件 | 动作 | 职责 |
| --- | --- | --- |
| `lib/media_backend/media_item_card.dart` | 改 | 加 `overview` / `genres` 字段 |
| `lib/media_backend/emby/emby_media_mappers.dart` | 改 | `mapEmbyItemCard` 填 overview/genres |
| `lib/media_backend/feiniu/feiniu_media_mappers.dart` | 改 | `mapFeiniuItemCard` 填 overview |
| `lib/media_backend/media_backend.dart` | 改 | 加 `getLatestItems` 默认空实现 |
| `lib/media_backend/emby/emby_media_backend.dart` | 改 | override（`SortBy=DateCreated`）；`_cardFields` 加 `Genres` |
| `lib/media_backend/feiniu/feiniu_media_backend.dart` | 改 | override（`create_time DESC` 全局查询，失败返回空） |
| `lib/screens/poster_browse/poster_browse_rows.dart` | 建 | 行模型 + 行组装纯函数 |
| `lib/screens/poster_browse/poster_browse_loader.dart` | 建 | 数据加载（含飞牛继续观看旁路映射） |
| `lib/screens/poster_browse/poster_browse_focus_throttle.dart` | 建 | 焦点切换 300ms 节流 |
| `lib/screens/poster_browse/poster_browse_thumb_strip.dart` | 建 | 底部缩略图条组件 |
| `lib/screens/poster_browse/poster_browse_screen.dart` | 建 | 页面组装 |
| `lib/main.dart` | 改 | 路由 + `PosterBrowseRoute` |
| `lib/screens/media_list_screen_widgets.dart` | 改 | AppBar 入口图标 |
| `lib/l10n/app_zh.arb` + `lib/l10n/app_zh_CN.arb` | 改 | 新文案 key |
| `test/media_backend/latest_items_test.dart` | 建 | getLatestItems 三后端行为 |
| `test/poster_browse/poster_browse_rows_test.dart` | 建 | 行组装 + 旁路映射 |
| `test/poster_browse/poster_browse_focus_throttle_test.dart` | 建 | 节流 |
| `test/media_backend/multi_backend_abstraction_boundary_test.dart` | 改 | 新文件入守卫名单 |

Jellyfin：`JellyfinMediaBackend extends EmbyMediaBackend`，继承 `getLatestItems`，零代码。

---

### Task 1: MediaItemCard 加 overview / genres 字段

**Files:**
- Modify: `lib/media_backend/media_item_card.dart`
- Test: `test/media_backend/media_item_card_test.dart`（已存在，追加）

- [ ] **Step 1: 写失败测试**

在 `test/media_backend/media_item_card_test.dart` 的 `main()` 里追加：

```dart
  test('overview 与 genres 默认空且可构造', () {
    const card = MediaItemCard(
      id: '1',
      title: 't',
      type: 'Movie',
      primaryImage: MediaImageRef.empty,
    );
    expect(card.overview, '');
    expect(card.genres, isEmpty);

    final filled = card.copyWith(overview: 'plot', genres: const ['科幻']);
    expect(filled.overview, 'plot');
    expect(filled.genres, const ['科幻']);
    expect(filled.id, '1');
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/media_backend/media_item_card_test.dart`
Expected: 编译错误 `The getter 'overview' isn't defined`。

- [ ] **Step 3: 实现字段**

`lib/media_backend/media_item_card.dart`，在 `final String rating;` 之后加字段：

```dart
  /// 简介文本（首页大屏浏览页信息区用）。空表示后端未提供，UI 隐藏不占位。
  final String overview;

  /// 题材标签（如 `科幻` / `剧情`）。空表示后端未提供。
  final List<String> genres;
```

构造函数参数区（`this.rating = '',` 之后）加：

```dart
    this.overview = '',
    this.genres = const <String>[],
```

`copyWith` 参数区加 `String? overview, List<String>? genres,`，构造处加：

```dart
      overview: overview ?? this.overview,
      genres: genres ?? this.genres,
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/media_backend/media_item_card_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/media_backend/media_item_card.dart test/media_backend/media_item_card_test.dart
git commit -m "feat(backend): MediaItemCard 增加 overview/genres 展示字段"
```

---

### Task 2: Emby / 飞牛 mapper 填充 overview 与 genres

**Files:**
- Modify: `lib/media_backend/emby/emby_media_mappers.dart`（`mapEmbyItemCard`，约 :32-73）
- Modify: `lib/media_backend/emby/emby_media_backend.dart`（`_cardFields`，约 :44）
- Modify: `lib/media_backend/feiniu/feiniu_media_mappers.dart`（`mapFeiniuItemCard`）
- Test: `test/media_backend/emby_media_mappers_test.dart`、`test/media_backend/feiniu_media_mappers_test.dart`（均已存在，追加）

- [ ] **Step 1: 写失败测试（Emby）**

`test/media_backend/emby_media_mappers_test.dart` 追加：

```dart
  test('mapEmbyItemCard 填充 overview 与 genres', () {
    final card = mapEmbyItemCard(
      <String, Object?>{
        'Id': 'i1',
        'Name': 'Oppenheimer',
        'Type': 'Movie',
        'Overview': 'plot text',
        'Genres': <Object?>['Drama', ' History ', ''],
      },
      serverUrl: 'http://s',
      token: 'tk',
    );
    expect(card.overview, 'plot text');
    expect(card.genres, const <String>['Drama', 'History']);
  });
```

- [ ] **Step 2: 写失败测试（飞牛）**

`test/media_backend/feiniu_media_mappers_test.dart` 追加（构造 `MediaLibraryItem` 的必填参数照抄该文件里现有测试的构造写法，仅 `overview` 给 `'plot'`）：

```dart
  test('mapFeiniuItemCard 透传 overview', () {
    // 复用本文件现有测试的 MediaLibraryItem 构造样板，overview 填 'plot'
    final card = mapFeiniuItemCard(buildItem(overview: 'plot'));
    expect(card.overview, 'plot');
    expect(card.genres, isEmpty);
  });
```

（若该文件没有 `buildItem` 辅助函数，就地内联一个完整 `MediaLibraryItem(...)` 构造——字段列表见 `lib/models/media_library_item.dart:37-70`，全部必填字段给空串/0。）

- [ ] **Step 3: 跑测试确认失败**

Run: `flutter test test/media_backend/emby_media_mappers_test.dart test/media_backend/feiniu_media_mappers_test.dart`
Expected: FAIL（overview 为空串）。

- [ ] **Step 4: 实现**

`emby_media_mappers.dart` — `mapEmbyItemCard` 的 `MediaItemCard(...)` 构造里、`rating:` 行后加：

```dart
    overview: (item['Overview'] ?? '').toString(),
    genres: _genreNames(item['Genres']),
```

文件底部私有助手区（`_ratingText` 旁）加：

```dart
List<String> _genreNames(Object? genres) {
  if (genres is! List) return const <String>[];
  return genres
      .map((e) => (e ?? '').toString().trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
}
```

`emby_media_backend.dart` — `_cardFields` 常量追加 `Genres`：

```dart
  static const String _cardFields =
      'PrimaryImageAspectRatio,Overview,PremiereDate,CommunityRating,MediaStreams,Genres';
```

`feiniu_media_mappers.dart` — `mapFeiniuItemCard` 的 `MediaItemCard(...)` 构造里加：

```dart
    overview: item.overview,
```

- [ ] **Step 5: 跑测试确认通过 + 全量后端测试无回归**

Run: `flutter test test/media_backend/`
Expected: 全 PASS。

- [ ] **Step 6: Commit**

```bash
git add lib/media_backend/ test/media_backend/
git commit -m "feat(backend): Emby/飞牛卡片映射填充 overview 与 genres"
```

---

### Task 3: MediaBackend.getLatestItems + Emby override

**Files:**
- Modify: `lib/media_backend/media_backend.dart`（`getCatalogPreviewItems` 之后）
- Modify: `lib/media_backend/emby/emby_media_backend.dart`
- Test: Create `test/media_backend/latest_items_test.dart`

- [ ] **Step 1: 写失败测试**

新建 `test/media_backend/latest_items_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/api/emby_api.dart';
import 'package:fly_player/media_backend/emby/emby_media_backend.dart';
import 'package:fly_player/media_backend/media_backend_connection.dart';

/// 手写 Fake：模式与 emby_media_backend_test.dart 的 _FakeEmbyApi 一致——
/// extends 真类、只 override 用到的方法、公开字段记录最后一次调用参数。
class _LatestCaptureApi extends EmbyApi {
  String lastSortBy = '';
  String lastSortOrder = '';
  String lastIncludeItemTypes = '';
  bool lastRecursive = false;
  int? lastLimit;
  String lastFields = '';

  @override
  Future<List<Map<String, Object?>>> getItems({
    required String serverUrl,
    required String userId,
    required String accessToken,
    String parentId = '',
    int? limit,
    bool isResumable = false,
    bool recursive = false,
    String includeItemTypes = '',
    String fields = '',
    String sortBy = '',
    String sortOrder = '',
  }) async {
    lastSortBy = sortBy;
    lastSortOrder = sortOrder;
    lastIncludeItemTypes = includeItemTypes;
    lastRecursive = recursive;
    lastLimit = limit;
    lastFields = fields;
    return <Map<String, Object?>>[
      <String, Object?>{'Id': 'a', 'Name': 'A', 'Type': 'Movie'},
    ];
  }
}

void main() {
  // 连接对象构造参数以 media_backend_connection.dart 实际字段为准，
  // 照抄 emby_media_backend_test.dart 现有测试的构造写法。
  EmbyMediaBackend buildBackend(_LatestCaptureApi api) => EmbyMediaBackend(
        api: api,
        connection: buildTestConnection(),
      );

  test('Emby getLatestItems 走 DateCreated 倒序', () async {
    final api = _LatestCaptureApi();
    final cards = await buildBackend(api).getLatestItems(limit: 12);
    expect(api.lastSortBy, 'DateCreated');
    expect(api.lastSortOrder, 'Descending');
    expect(api.lastIncludeItemTypes, 'Movie,Series');
    expect(api.lastRecursive, isTrue);
    expect(api.lastLimit, 12);
    expect(api.lastFields, contains('Overview'));
    expect(cards, hasLength(1));
    expect(cards.first.id, 'a');
  });
}
```

注：`buildTestConnection()` 指代 `emby_media_backend_test.dart` 里现成的 `MediaBackendConnection` 测试构造——打开该文件把它的构造写法照抄成本文件的局部辅助函数（连接字段以真实类为准，不要臆造）。

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/media_backend/latest_items_test.dart`
Expected: 编译错误 `getLatestItems isn't defined`。

- [ ] **Step 3: 实现接口默认值 + Emby override**

`lib/media_backend/media_backend.dart`，`getCatalogPreviewItems`（:35-39）之后加：

```dart
  /// 最近添加条目（大屏海报浏览页"最近添加"行）。
  ///
  /// 默认返回空列表 = 该后端不提供，UI 隐藏整行不占位。Emby/Jellyfin override 为
  /// `/Users/{id}/Items` 按 `DateCreated` 倒序；飞牛 override 为 item/list 按
  /// `create_time DESC` 全局查询（排序不生效/失败时返回空，行自然降级）。
  Future<List<MediaItemCard>> getLatestItems({int limit = 20}) async =>
      const <MediaItemCard>[];
```

`lib/media_backend/emby/emby_media_backend.dart`，`getCatalogPreviewItems`（:165-189）之后加：

```dart
  @override
  Future<List<MediaItemCard>> getLatestItems({int limit = 20}) async {
    final items = await api.getItems(
      serverUrl: _serverUrl,
      userId: _userId,
      accessToken: _token,
      limit: limit,
      recursive: true,
      includeItemTypes: 'Movie,Series',
      fields: _cardFields,
      sortBy: 'DateCreated',
      sortOrder: 'Descending',
    );
    return items
        .map((e) => mapEmbyItemCard(e, serverUrl: _serverUrl, token: _token))
        .toList(growable: false);
  }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/media_backend/latest_items_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/media_backend/ test/media_backend/latest_items_test.dart
git commit -m "feat(backend): MediaBackend.getLatestItems + Emby DateCreated 倒序实现"
```

---

### Task 4: 飞牛 getLatestItems

**Files:**
- Modify: `lib/media_backend/feiniu/feiniu_media_backend.dart`
- Test: `test/media_backend/latest_items_test.dart`（追加）

- [ ] **Step 1: 写失败测试**

`latest_items_test.dart` 追加（Fake 构造照抄 `feiniu_media_backend_test.dart` 的 `_FakeFeiniuApi` 模式）：

```dart
class _LatestFeiniuApi extends FeiniuApi {
  // ctor 照抄 feiniu_media_backend_test.dart 现有 Fake 的写法
  Map<String, dynamic>? lastPayload;
  bool shouldThrow = false;

  @override
  Future<ItemListPage> getItemsPage(Map<String, dynamic> payload) async {
    lastPayload = payload;
    if (shouldThrow) throw Exception('boom');
    return ItemListPage(items: <MediaLibraryItem>[/* 一条最小构造 */], total: 1);
  }
}

  test('飞牛 getLatestItems 按 create_time DESC 全局查询', () async {
    final api = _LatestFeiniuApi(...);
    final backend = buildFeiniuBackend(api); // 照抄现有测试的构造
    await backend.getLatestItems(limit: 15);
    final payload = api.lastPayload!;
    expect(payload['sort_column'], 'create_time');
    expect(payload['sort_type'], 'DESC');
    expect(payload['page_size'], 15);
    expect(payload.containsKey('ancestor_guid'), isFalse); // 全局查询不带祖先
    expect((payload['tags'] as Map)['type'], const <String>['Movie', 'TV']);
  });

  test('飞牛 getLatestItems 请求失败返回空列表（行降级隐藏）', () async {
    final api = _LatestFeiniuApi(...)..shouldThrow = true;
    final cards = await buildFeiniuBackend(api).getLatestItems();
    expect(cards, isEmpty);
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/media_backend/latest_items_test.dart`
Expected: FAIL。

- [ ] **Step 3: 实现**

`lib/media_backend/feiniu/feiniu_media_backend.dart`，`getCatalogPreviewItems`（:62-74）之后加（`ItemListRequest` 已由该文件的 mapper 依赖链引入，若缺则 `import '../../api/item_list_request.dart';`）：

```dart
  @override
  Future<List<MediaItemCard>> getLatestItems({int limit = 20}) async {
    // 飞牛官方播放器无"最近添加"页，但 item/list 接口支持 create_time 倒序；
    // 不带 ancestor_guid 即全库查询。失败/排序不生效时返回空，行自然隐藏。
    try {
      final page = await api.getItemsPage(
        ItemListRequest(
          ancestorGuid: '',
          pageSize: limit,
          typeTags: const <String>['Movie', 'TV'],
        ).toJson(),
      );
      return page.items.map(mapFeiniuItemCard).toList(growable: false);
    } catch (_) {
      return const <MediaItemCard>[];
    }
  }
```

（`ItemListRequest` 默认 `sortColumn: 'create_time', sortType: 'DESC'`，`toJson()` 对空 `ancestorGuid` 自动省略该键——见 `lib/api/item_list_request.dart:30-73`。）

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/media_backend/latest_items_test.dart`
Expected: 全 PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/media_backend/feiniu/feiniu_media_backend.dart test/media_backend/latest_items_test.dart
git commit -m "feat(backend): 飞牛 getLatestItems 按 create_time 倒序拼最近添加"
```

---

### Task 5: l10n 文案

**Files:**
- Modify: `lib/l10n/app_zh_CN.arb`（模板）、`lib/l10n/app_zh.arb`

- [ ] **Step 1: 两个 arb 文件各追加同样的 key**（放到文件 JSON 对象内任意分组处，注意逗号）：

```json
  "posterBrowseEntryTooltip": "大屏浏览",
  "posterBrowseRowContinue": "继续观看",
  "posterBrowseRowLatest": "最近添加",
  "posterBrowseDetail": "详情",
  "posterBrowseLoadFailed": "加载失败，点按重试",
  "posterBrowseRowIndicator": "{current} / {total}",
  "@posterBrowseRowIndicator": {
    "placeholders": {
      "current": { "type": "int" },
      "total": { "type": "int" }
    }
  },
```

播放按钮复用现有 `detailPlay`；时长/年份等格式化优先复用现有 key（在 arb 里搜 `分钟`/`min`，有就用，没有则数字直拼不加单位文案）。

- [ ] **Step 2: 生成并验证**

Run: `flutter gen-l10n`
Expected: 无报错，`lib/l10n/generated/app_localizations.dart` 出现 `posterBrowseEntryTooltip` getter。

- [ ] **Step 3: Commit**

```bash
git add lib/l10n/
git commit -m "feat(i18n): 大屏海报浏览页文案 key"
```

---

### Task 6: 行模型 + 行组装纯函数

**Files:**
- Create: `lib/screens/poster_browse/poster_browse_rows.dart`
- Test: Create `test/poster_browse/poster_browse_rows_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_catalog.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/media_backend/media_item_card.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_rows.dart';

MediaItemCard card(String id) => MediaItemCard(
      id: id,
      title: id,
      type: 'Movie',
      primaryImage: MediaImageRef.empty,
    );

void main() {
  test('三类行按序组装，空行整行剔除', () {
    final rows = buildPosterBrowseRows(
      continueWatching: <MediaItemCard>[card('c1')],
      latestItems: const <MediaItemCard>[], // 空 → 隐藏
      catalogs: const <MediaCatalog>[
        MediaCatalog(id: 'lib1', title: '电影库', type: 'movies', primaryImage: MediaImageRef.empty),
        MediaCatalog(id: 'lib2', title: '空库', type: 'tvshows', primaryImage: MediaImageRef.empty),
      ],
      catalogItems: <String, List<MediaItemCard>>{
        'lib1': <MediaItemCard>[card('m1'), card('m2')],
        'lib2': const <MediaItemCard>[], // 空 → 隐藏
      },
    );
    expect(rows, hasLength(2));
    expect(rows[0].kind, PosterBrowseRowKind.continueWatching);
    expect(rows[1].kind, PosterBrowseRowKind.catalog);
    expect(rows[1].catalogId, 'lib1');
    expect(rows[1].catalogTitle, '电影库');
    expect(rows[1].items.map((e) => e.id), ['m1', 'm2']);
  });

  test('最近添加行在继续观看之后、媒体库之前', () {
    final rows = buildPosterBrowseRows(
      continueWatching: <MediaItemCard>[card('c1')],
      latestItems: <MediaItemCard>[card('l1')],
      catalogs: const <MediaCatalog>[],
      catalogItems: const <String, List<MediaItemCard>>{},
    );
    expect(rows.map((r) => r.kind), <PosterBrowseRowKind>[
      PosterBrowseRowKind.continueWatching,
      PosterBrowseRowKind.latest,
    ]);
  });

  test('全空返回空列表', () {
    final rows = buildPosterBrowseRows(
      continueWatching: const <MediaItemCard>[],
      latestItems: const <MediaItemCard>[],
      catalogs: const <MediaCatalog>[],
      catalogItems: const <String, List<MediaItemCard>>{},
    );
    expect(rows, isEmpty);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/poster_browse/poster_browse_rows_test.dart`
Expected: 编译错误（文件不存在）。

- [ ] **Step 3: 实现**

`lib/screens/poster_browse/poster_browse_rows.dart`：

```dart
import '../../media_backend/media_catalog.dart';
import '../../media_backend/media_item_card.dart';

/// 大屏海报浏览页的一"行"。行标题由 UI 按 [kind] 取 l10n（catalog 行用 [catalogTitle]）。
enum PosterBrowseRowKind { continueWatching, latest, catalog }

class PosterBrowseRow {
  final PosterBrowseRowKind kind;
  final String catalogId;
  final String catalogTitle;
  final List<MediaItemCard> items;

  const PosterBrowseRow({
    required this.kind,
    required this.items,
    this.catalogId = '',
    this.catalogTitle = '',
  });
}

/// 行组装纯函数：继续观看 → 最近添加 → 各媒体库；空行整行剔除，不留占位。
List<PosterBrowseRow> buildPosterBrowseRows({
  required List<MediaItemCard> continueWatching,
  required List<MediaItemCard> latestItems,
  required List<MediaCatalog> catalogs,
  required Map<String, List<MediaItemCard>> catalogItems,
}) {
  final rows = <PosterBrowseRow>[
    if (continueWatching.isNotEmpty)
      PosterBrowseRow(
        kind: PosterBrowseRowKind.continueWatching,
        items: continueWatching,
      ),
    if (latestItems.isNotEmpty)
      PosterBrowseRow(kind: PosterBrowseRowKind.latest, items: latestItems),
  ];
  for (final catalog in catalogs) {
    final items = catalogItems[catalog.id] ?? const <MediaItemCard>[];
    if (items.isEmpty) continue;
    rows.add(
      PosterBrowseRow(
        kind: PosterBrowseRowKind.catalog,
        catalogId: catalog.id,
        catalogTitle: catalog.title,
        items: items,
      ),
    );
  }
  return rows;
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/poster_browse/poster_browse_rows_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/screens/poster_browse/poster_browse_rows.dart test/poster_browse/poster_browse_rows_test.dart
git commit -m "feat(poster-browse): 行模型与行组装纯函数"
```

---

### Task 7: 数据加载器（含飞牛旁路映射）

**Files:**
- Create: `lib/screens/poster_browse/poster_browse_loader.dart`
- Test: `test/poster_browse/poster_browse_rows_test.dart`（追加映射测试）

- [ ] **Step 1: 写失败测试**（追加到 rows 测试文件）

```dart
  test('cardFromLibraryItem 保留续播富字段', () {
    final item = MediaLibraryItem(
      guid: 'g1', title: '沙丘', tvTitle: '', type: 'Movie', poster: '/p.jpg',
      releaseDate: '2024-03-01', firstAirDate: '', lastAirDate: '',
      voteAverage: '8.3', overview: 'plot', watched: 0, watchedTs: 0,
      ts: 1200, duration: 6000, seasonNumber: 0, episodeNumber: 0,
      numberOfSeasons: 0, numberOfEpisodes: 0, localNumberOfSeasons: 0,
      localNumberOfEpisodes: 0, parentGuid: '', parentTitle: '',
      ancestorGuid: 'series1', ancestorName: '', path: '',
    );
    final cardResult = cardFromLibraryItem(item);
    expect(cardResult.id, 'g1');
    expect(cardResult.rating, '8.3');
    expect(cardResult.overview, 'plot');
    expect(cardResult.resumePositionSeconds, 1200);
    expect(cardResult.durationSeconds, 6000);
    expect(cardResult.seriesId, 'series1');
    expect(cardResult.primaryImage.url, '/p.jpg');
  });
```

（import 补 `package:fly_player/models/media_library_item.dart` 与 `package:fly_player/screens/poster_browse/poster_browse_loader.dart`。）

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/poster_browse/poster_browse_rows_test.dart`
Expected: 编译错误。

- [ ] **Step 3: 实现**

`lib/screens/poster_browse/poster_browse_loader.dart`：

```dart
import '../../api/feiniu_api.dart';
import '../../media_backend/media_backend.dart';
import '../../media_backend/media_backend_kind.dart';
import '../../media_backend/media_catalog.dart';
import '../../media_backend/media_image_ref.dart';
import '../../media_backend/media_item_card.dart';
import '../../models/media_library_item.dart';
import 'poster_browse_rows.dart';

/// 飞牛继续观看旁路（getPlayList 保留 ts/duration 富字段）→ 公共卡片。
MediaItemCard cardFromLibraryItem(MediaLibraryItem item) {
  return MediaItemCard(
    id: item.guid,
    title: item.title,
    secondaryTitle: item.tvTitle,
    type: item.type,
    seriesId: item.ancestorGuid,
    primaryImage: MediaImageRef(url: item.poster),
    posters: item.posterList
        .map((p) => MediaImageRef(url: p))
        .toList(growable: false),
    backdropImage: item.backdropUrl.trim().isNotEmpty
        ? MediaImageRef(url: item.backdropUrl)
        : MediaImageRef.empty,
    durationSeconds: item.duration,
    watched: item.watched > 0,
    resumePositionSeconds: item.ts > 0 ? item.ts : item.watchedTs,
    rating: item.voteAverage,
    releaseDate: item.releaseDate,
    overview: item.overview,
    resolutions: item.resolutions,
  );
}

/// 页面数据加载：三源并行，单源失败该行隐藏；全部行为空视为整页失败（由页面判定）。
class PosterBrowseLoader {
  const PosterBrowseLoader();

  Future<List<PosterBrowseRow>> load({
    required MediaBackend backend,
    required FeiniuApi api,
    int rowItemLimit = 20,
  }) async {
    var continueWatching = const <MediaItemCard>[];
    var latest = const <MediaItemCard>[];
    var catalogs = const <MediaCatalog>[];
    await Future.wait<void>(<Future<void>>[
      () async {
        try {
          continueWatching = await _loadContinueWatching(backend, api);
        } catch (_) {}
      }(),
      () async {
        try {
          latest = await backend.getLatestItems(limit: rowItemLimit);
        } catch (_) {}
      }(),
      () async {
        try {
          catalogs = await backend.getCatalogs();
        } catch (_) {}
      }(),
    ]);

    final catalogItems = <String, List<MediaItemCard>>{};
    await Future.wait<void>(
      catalogs.map((catalog) async {
        try {
          catalogItems[catalog.id] = await backend.getCatalogPreviewItems(
            catalog.id,
            limit: rowItemLimit,
          );
        } catch (_) {
          catalogItems[catalog.id] = const <MediaItemCard>[];
        }
      }),
    );

    return buildPosterBrowseRows(
      continueWatching: continueWatching.take(rowItemLimit).toList(),
      latestItems: latest,
      catalogs: catalogs,
      catalogItems: catalogItems,
    );
  }

  /// 数据层按后端能力选源（与首页 _loadContinueWatching 同款分流），UI 不判后端。
  Future<List<MediaItemCard>> _loadContinueWatching(
    MediaBackend backend,
    FeiniuApi api,
  ) async {
    if (backend.capabilities.kind == MediaBackendKind.feiniu) {
      final items = await api.getPlayList();
      return items.map(cardFromLibraryItem).toList(growable: false);
    }
    return backend.getContinueWatching();
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/poster_browse/`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/screens/poster_browse/poster_browse_loader.dart test/poster_browse/
git commit -m "feat(poster-browse): 数据加载器与飞牛续播旁路映射"
```

---

### Task 8: 焦点切换节流

**Files:**
- Create: `lib/screens/poster_browse/poster_browse_focus_throttle.dart`
- Test: Create `test/poster_browse/poster_browse_focus_throttle_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_focus_throttle.dart';

void main() {
  test('连续调度只触发最后一次，且在 300ms 后', () {
    fakeAsync((async) {
      final settled = <String>[];
      final throttle = PosterBrowseFocusThrottle(onSettle: settled.add);
      throttle.schedule('a');
      async.elapse(const Duration(milliseconds: 100));
      throttle.schedule('b');
      async.elapse(const Duration(milliseconds: 100));
      throttle.schedule('c');
      expect(settled, isEmpty);
      async.elapse(const Duration(milliseconds: 300));
      expect(settled, ['c']);
      throttle.dispose();
    });
  });

  test('dispose 后不再触发', () {
    fakeAsync((async) {
      final settled = <String>[];
      PosterBrowseFocusThrottle(onSettle: settled.add)
        ..schedule('a')
        ..dispose();
      async.elapse(const Duration(seconds: 1));
      expect(settled, isEmpty);
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/poster_browse/poster_browse_focus_throttle_test.dart`
Expected: 编译错误。

- [ ] **Step 3: 实现**

```dart
import 'dart:async';

/// 焦点切换节流：快速连点/滑动时，背景大图与取色只在停留 [delay] 后触发一次。
class PosterBrowseFocusThrottle {
  PosterBrowseFocusThrottle({
    required this.onSettle,
    this.delay = const Duration(milliseconds: 300),
  });

  final void Function(String itemId) onSettle;
  final Duration delay;
  Timer? _timer;

  void schedule(String itemId) {
    _timer?.cancel();
    _timer = Timer(delay, () => onSettle(itemId));
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/poster_browse/poster_browse_focus_throttle_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/screens/poster_browse/poster_browse_focus_throttle.dart test/poster_browse/poster_browse_focus_throttle_test.dart
git commit -m "feat(poster-browse): 焦点切换 300ms 节流"
```

---

### Task 9: 底部缩略图条组件

**Files:**
- Create: `lib/screens/poster_browse/poster_browse_thumb_strip.dart`
- Test: Create `test/poster_browse/poster_browse_thumb_strip_test.dart`

- [ ] **Step 1: 写失败测试（widget test）**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/media_backend/media_item_card.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_thumb_strip.dart';

void main() {
  final cards = <MediaItemCard>[
    const MediaItemCard(
      id: 'a', title: 'A', type: 'Movie',
      primaryImage: MediaImageRef.empty, rating: '8.9',
      resumePositionSeconds: 300, durationSeconds: 600,
    ),
    const MediaItemCard(
      id: 'b', title: 'B', type: 'Movie',
      primaryImage: MediaImageRef.empty,
    ),
  ];

  testWidgets('评分角标只在有评分时出现，点击回调携带 index', (tester) async {
    int? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PosterBrowseThumbStrip(
          items: cards,
          focusedIndex: 0,
          imageUrlOf: (_) => '',
          showProgress: true,
          onItemTap: (index) => tapped = index,
        ),
      ),
    ));
    expect(find.text('★ 8.9'), findsOneWidget); // a 有评分
    expect(find.textContaining('★'), findsOneWidget); // b 无评分不占位
    await tester.tap(find.byKey(const ValueKey('poster_browse_thumb_b')));
    expect(tapped, 1);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/poster_browse/poster_browse_thumb_strip_test.dart`
Expected: 编译错误。

- [ ] **Step 3: 实现**

```dart
import 'package:flutter/material.dart';

import '../../media_backend/media_item_card.dart';

/// 底部横向缩略图条：16:9 小图、聚焦放大 + 白描边、评分角标、可选进度条。
/// 图片 URL 由调用方经 DetailArtworkResolver 解析后注入（本组件不接触后端概念）。
class PosterBrowseThumbStrip extends StatelessWidget {
  const PosterBrowseThumbStrip({
    super.key,
    required this.items,
    required this.focusedIndex,
    required this.imageUrlOf,
    required this.onItemTap,
    this.imageHeaders = const <String, String>{},
    this.showProgress = false,
    this.thumbHeight = 72,
  });

  final List<MediaItemCard> items;
  final int focusedIndex;
  final String Function(MediaItemCard item) imageUrlOf;
  final Map<String, String> imageHeaders;
  final void Function(int index) onItemTap;
  final bool showProgress;
  final double thumbHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: thumbHeight + 16,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = items[index];
          final focused = index == focusedIndex;
          final url = imageUrlOf(item);
          final progress = _progress(item);
          return Center(
            child: GestureDetector(
              key: ValueKey('poster_browse_thumb_${item.id}'),
              onTap: () => onItemTap(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                height: focused ? thumbHeight + 12 : thumbHeight,
                width: (focused ? thumbHeight + 12 : thumbHeight) * 16 / 9,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: focused
                      ? Border.all(color: Colors.white, width: 2.5)
                      : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (url.trim().isNotEmpty)
                      Image.network(
                        url,
                        headers: imageHeaders.isEmpty ? null : imageHeaders,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    if (item.rating.trim().isNotEmpty)
                      Positioned(
                        top: 4,
                        right: 5,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            child: Text(
                              '★ ${item.rating.trim()}',
                              style: const TextStyle(
                                color: Color(0xFFFFD166),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (showProgress && progress > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          backgroundColor: Colors.white.withValues(alpha: 0.25),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  double _progress(MediaItemCard item) {
    if (item.durationSeconds <= 0 || item.resumePositionSeconds <= 0) return 0;
    return (item.resumePositionSeconds / item.durationSeconds)
        .clamp(0, 1)
        .toDouble();
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/poster_browse/poster_browse_thumb_strip_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/screens/poster_browse/poster_browse_thumb_strip.dart test/poster_browse/poster_browse_thumb_strip_test.dart
git commit -m "feat(poster-browse): 缩略图条组件（聚焦放大/评分角标/进度条）"
```

---

### Task 10: 页面组装 PosterBrowseScreen

**Files:**
- Create: `lib/screens/poster_browse/poster_browse_screen.dart`

无单测（依赖 Provider 树与原生通道，由 Task 12 静态分析 + 实机验收覆盖）。

- [ ] **Step 1: 实现页面**

要点先行（代码随后）：
- 进入即横屏 + `SystemUiMode.immersiveSticky`；`dispose` 恢复 `setPreferredOrientations(const [])` + `edgeToEdge`（模式对照 `lib/screens/screenshot_preview_screen.dart:1791-1795` 与其 `dispose`）。
- 推详情/返回前先恢复竖屏，pop 回来重新横屏（避免详情页横屏渲染）。
- `DynamicPageThemeScope`：`pageKey` = 节流后聚焦条目 id（与详情页同键共享 seed），enabled/intensity 取法对照 `lib/pages/tv_season_detail_page.dart:2910-2913` 与 `AppThemeProvider.dynamicThemeEnabled`。
- 背景 `AnimatedSwitcher`（keyed by 聚焦 id）交叉淡入 `ImmersiveDetailBackground`；无图时纯 ambient 色底。
- 播放：`Movie`/单集 → `const ItemPlaybackLauncher().open(context, itemGuid: ...)`（内部已绑 reentry + 起原生壳，见 `lib/controllers/item_playback_launcher.dart:39-145`）；`Series`/`TV` → `backend.resolveSeriesPlaybackTarget` 后 `const TvSeasonPlaybackLauncher().open(context, itemGuid: target, seriesTitle: ..., seriesGuid: ...)`（对照 `lib/pages/tv_detail_page.dart:1297-1375`）。
- 详情：`DetailThemePrewarmer.warmUp` 后 push `PlayDetailScreen(itemGuid: ...)`（判型交给它，对照 `lib/screens/media_list_screen.dart:708-845`）。

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../controllers/item_playback_launcher.dart';
import '../../controllers/tv_season_playback_launcher.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../media_backend/media_backend.dart';
import '../../media_backend/media_item_card.dart';
import '../../api/feiniu_api.dart';
import '../../providers/app_theme_provider.dart';
import '../../providers/media_backend_provider.dart';
import '../../providers/nas_provider.dart';
import '../../theme/app_theme.dart';
import '../../ui/detail_artwork_resolver.dart';
import '../../ui/detail_theme_prewarmer.dart';
import '../../widgets/detail/dynamic_page_theme_scope.dart';
import '../../widgets/detail/immersive_detail_background.dart';
import '../play_detail_screen.dart';
import 'poster_browse_focus_throttle.dart';
import 'poster_browse_loader.dart';
import 'poster_browse_rows.dart';
import 'poster_browse_thumb_strip.dart';

/// 大屏海报浏览页：横屏全屏，聚焦条目 backdrop 铺底，底部多行类别缩略图条。
class PosterBrowseScreen extends StatefulWidget {
  const PosterBrowseScreen({super.key});

  @override
  State<PosterBrowseScreen> createState() => _PosterBrowseScreenState();
}

class _PosterBrowseScreenState extends State<PosterBrowseScreen> {
  static const int _rowItemLimit = 20;

  List<PosterBrowseRow> _rows = const <PosterBrowseRow>[];
  bool _loading = true;
  int _rowIndex = 0;
  final Map<int, int> _focusByRow = <int, int>{};
  MediaItemCard? _settled; // 节流后的聚焦条目：驱动背景与取色
  late final PageController _rowController;
  late final PosterBrowseFocusThrottle _throttle;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _rowController = PageController(viewportFraction: 0.62);
    _throttle = PosterBrowseFocusThrottle(onSettle: _onFocusSettled);
    _clockTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => mounted ? setState(() {}) : null,
    );
    unawaited(_enterImmersiveLandscape());
    unawaited(_load());
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _throttle.dispose();
    _rowController.dispose();
    unawaited(_exitImmersiveLandscape());
    super.dispose();
  }

  Future<void> _enterImmersiveLandscape() async {
    await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _exitImmersiveLandscape() async {
    await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final backend = context.read<MediaBackendProvider>().backend;
    final api = FeiniuApi(context.read<NasProvider>());
    final rows = await const PosterBrowseLoader().load(
      backend: backend,
      api: api,
      rowItemLimit: _rowItemLimit,
    );
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
      _rowIndex = 0;
      _focusByRow.clear();
      _settled = rows.isEmpty ? null : rows.first.items.first;
    });
  }

  MediaItemCard? get _focusedItem {
    if (_rows.isEmpty || _rowIndex >= _rows.length) return null;
    final row = _rows[_rowIndex];
    final index = (_focusByRow[_rowIndex] ?? 0).clamp(0, row.items.length - 1);
    return row.items[index];
  }

  void _onFocusSettled(String itemId) {
    if (!mounted) return;
    final item = _focusedItem;
    if (item == null || item.id != itemId) return;
    setState(() => _settled = item);
    _precacheNeighbors();
  }

  /// 相邻 ±2 张 backdrop 预取，滑动到位时背景即刻可用。
  void _precacheNeighbors() {
    final row = _rows.isEmpty ? null : _rows[_rowIndex];
    if (row == null) return;
    final resolver = _resolver();
    final center = _focusByRow[_rowIndex] ?? 0;
    for (var i = center - 2; i <= center + 2; i++) {
      if (i < 0 || i >= row.items.length || i == center) continue;
      final artwork = resolver.resolveRefs(<dynamic>[
        row.items[i].backdropImage,
        row.items[i].primaryImage,
      ].whereType<dynamic>().cast(), width: 1280);
      if (artwork.isNotEmpty) {
        unawaited(
          precacheImage(
            NetworkImage(artwork.urls.first, headers: artwork.headers),
            context,
            onError: (_, _) {},
          ),
        );
      }
    }
  }

  DetailArtworkResolver _resolver() {
    final nas = context.read<NasProvider>();
    return DetailArtworkResolver(baseUrl: nas.baseUrl, token: nas.token);
  }

  void _onThumbTap(int rowIndex, int itemIndex) {
    final row = _rows[rowIndex];
    final item = row.items[itemIndex];
    final alreadyFocused =
        rowIndex == _rowIndex && (_focusByRow[rowIndex] ?? 0) == itemIndex;
    if (alreadyFocused) {
      unawaited(_openDetail(item));
      return;
    }
    setState(() => _focusByRow[rowIndex] = itemIndex);
    _throttle.schedule(item.id);
  }

  Future<void> _openDetail(MediaItemCard item) async {
    final resolver = _resolver();
    final artwork = resolver.resolveRefs(<dynamic>[
      item.backdropImage,
      item.primaryImage,
    ].cast(), width: 1280);
    await DetailThemePrewarmer.warmUp(
      context,
      pageKey: item.id,
      imageUrl: artwork.isNotEmpty ? artwork.urls.first : '',
    );
    if (!mounted) return;
    // 详情页按竖屏设计：进入前恢复竖屏，返回后重回横屏沉浸。
    await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayDetailScreen(itemGuid: item.id),
      ),
    );
    if (!mounted) return;
    await _enterImmersiveLandscape();
  }

  Future<void> _play(MediaItemCard item) async {
    final type = item.type.trim().toLowerCase();
    if (type == 'series' || type == 'tv') {
      final backend = context.read<MediaBackendProvider>().backend;
      final target = await backend.resolveSeriesPlaybackTarget(item.id);
      if (!mounted || target.trim().isEmpty) return;
      await const TvSeasonPlaybackLauncher().open(
        context,
        itemGuid: target,
        seriesTitle: item.displayTitle,
        seriesGuid: item.id,
      );
      return;
    }
    await const ItemPlaybackLauncher().open(
      context,
      itemGuid: item.id,
      fallbackTitle: item.displayTitle,
    );
  }

  String _rowLabel(AppLocalizations l10n, PosterBrowseRow row) {
    switch (row.kind) {
      case PosterBrowseRowKind.continueWatching:
        return l10n.posterBrowseRowContinue;
      case PosterBrowseRowKind.latest:
        return l10n.posterBrowseRowLatest;
      case PosterBrowseRowKind.catalog:
        return row.catalogTitle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nas = context.read<NasProvider>();
    final dynamicThemeEnabled = context.select<AppThemeProvider, bool>(
      (p) => p.dynamicThemeEnabled,
    );
    final intensity = context
        .select<AppThemeProvider, AppDynamicThemeIntensity>(
          (p) => p.dynamicThemeIntensity,
        );
    final settled = _settled;
    final resolver = _resolver();
    final backdrop = settled == null
        ? DetailArtwork.empty
        : resolver.resolveRefs(<dynamic>[
            settled.backdropImage,
            settled.primaryImage,
          ].cast(), width: 1280);

    return DynamicPageThemeScope(
      pageKey: settled?.id ?? 'poster_browse_empty',
      imageUrl: backdrop.isNotEmpty ? backdrop.urls.first : '',
      token: nas.token,
      enabled: dynamicThemeEnabled && settled != null,
      intensity: intensity,
      builder: (context, ambientTint) {
        final size = MediaQuery.of(context).size;
        return Scaffold(
          backgroundColor: ambientTint ?? Colors.black,
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
                  ? _buildError(l10n)
                  : Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 350),
                          child: KeyedSubtree(
                            key: ValueKey<String>(settled?.id ?? ''),
                            child: backdrop.isNotEmpty
                                ? ImmersiveDetailBackground(
                                    urls: backdrop.urls,
                                    token: nas.token,
                                    scrollOffset: 0,
                                    posterHeight: size.height,
                                    imageAlignment: Alignment.center,
                                    fillGapsWithImage: true,
                                    parallaxFactor: 0,
                                    overlayOpacity: 0.62,
                                    ambientTintOverride: ambientTint,
                                  )
                                : ColoredBox(
                                    color: ambientTint ?? Colors.black,
                                  ),
                          ),
                        ),
                        // 左侧渐变压暗，保证信息区可读
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              stops: <double>[0, 0.38, 0.68, 1],
                              colors: <Color>[
                                Color(0xEE06080E),
                                Color(0x8C06080E),
                                Color(0x1406080E),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                        // 底部渐变压暗
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              stops: <double>[0, 0.35, 0.6],
                              colors: <Color>[
                                Color(0xF706080E),
                                Color(0xB806080E),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                        SafeArea(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              _buildTopBar(context),
                              Expanded(child: _buildInfoArea(l10n, settled)),
                              SizedBox(
                                height: size.height * 0.36,
                                child: _buildRowPager(l10n, resolver),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
        );
      },
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Text(
            TimeOfDay.now().format(context),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoArea(AppLocalizations l10n, MediaItemCard? item) {
    if (item == null) return const SizedBox.shrink();
    final year = item.releaseDate.trim().length >= 4
        ? item.releaseDate.trim().substring(0, 4)
        : '';
    final minutes = item.durationSeconds > 0
        ? '${item.durationSeconds ~/ 60} min'
        : '';
    final metaParts = <Widget>[
      if (item.rating.trim().isNotEmpty)
        Text(
          '★ ${item.rating.trim()}',
          style: const TextStyle(
            color: Color(0xFFFFD166),
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      if (year.isNotEmpty) _metaText(year),
      if (item.genres.isNotEmpty) _metaText(item.genres.take(3).join(' / ')),
      if (minutes.isNotEmpty) _metaText(minutes),
      for (final res in item.resolutions.take(2)) _metaChip(res),
    ];
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 36, right: 36, bottom: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _rowLabel(l10n, _rows[_rowIndex]).toUpperCase(),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: metaParts,
            ),
            if (item.overview.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Text(
                  item.overview.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                  ),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l10n.detailPlay),
                  onPressed: () => unawaited(_play(item)),
                ),
                const SizedBox(width: 10),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.16),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(l10n.posterBrowseDetail),
                  onPressed: () => unawaited(_openDetail(item)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaText(String text) => Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.72),
          fontSize: 13,
        ),
      );

  Widget _metaChip(String text) => DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 10.5,
              letterSpacing: 0.5,
            ),
          ),
        ),
      );

  Widget _buildRowPager(AppLocalizations l10n, DetailArtworkResolver resolver) {
    return PageView.builder(
      controller: _rowController,
      scrollDirection: Axis.vertical,
      itemCount: _rows.length,
      onPageChanged: (index) {
        setState(() => _rowIndex = index);
        final item = _focusedItem;
        if (item != null) _throttle.schedule(item.id);
      },
      itemBuilder: (context, rowIndex) {
        final row = _rows[rowIndex];
        final active = rowIndex == _rowIndex;
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: active ? 1 : 0.45,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(left: 36, bottom: 8),
                child: Row(
                  children: <Widget>[
                    Text(
                      _rowLabel(l10n, row),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      l10n.posterBrowseRowIndicator(
                        rowIndex + 1,
                        _rows.length,
                      ),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: PosterBrowseThumbStrip(
                  items: row.items,
                  focusedIndex: _focusByRow[rowIndex] ?? 0,
                  showProgress:
                      row.kind == PosterBrowseRowKind.continueWatching,
                  imageUrlOf: (item) {
                    final artwork = resolver.resolveRefs(<dynamic>[
                      item.backdropImage,
                      item.primaryImage,
                    ].cast(), width: 440);
                    return artwork.isNotEmpty ? artwork.urls.first : '';
                  },
                  onItemTap: (itemIndex) => _onThumbTap(rowIndex, itemIndex),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildError(AppLocalizations l10n) {
    return Center(
      child: TextButton(
        onPressed: () => unawaited(_load()),
        child: Text(
          l10n.posterBrowseLoadFailed,
          style: const TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}
```

实现落地时的两处对齐（写代码前先读原文件核对，不要照抄本计划里的猜测签名）：
1. `resolveRefs` 的形参是 `List<MediaImageRef>`（`lib/ui/detail_artwork_resolver.dart:30-88`）——把上面 `<dynamic>[...].cast()` 写成正规 `<MediaImageRef>[item.backdropImage, item.primaryImage]`。
2. `AppDynamicThemeIntensity` 的 import 来源以 `tv_season_detail_page.dart` 顶部 import 为准。

- [ ] **Step 2: 静态分析**

Run: `flutter analyze lib/screens/poster_browse/`
Expected: No issues found。

- [ ] **Step 3: Commit**

```bash
git add lib/screens/poster_browse/poster_browse_screen.dart
git commit -m "feat(poster-browse): 大屏海报浏览页页面组装"
```

---

### Task 11: 路由 + 首页入口 + 边界守卫

**Files:**
- Modify: `lib/main.dart`（`/screen/search` case 附近 :504-509；Route 类区 :796-829）
- Modify: `lib/screens/media_list_screen_widgets.dart`（AppBar actions :43-50）
- Modify: `test/media_backend/multi_backend_abstraction_boundary_test.dart`（:76-90）

- [ ] **Step 1: 更新边界守卫测试（先写失败测试）**

`multi_backend_abstraction_boundary_test.dart` 的 `服务器族公共层不再写死 Emby 判断` 测试里，`publicBoundaryFiles` 列表追加：

```dart
        'lib/screens/poster_browse/poster_browse_screen.dart',
        'lib/screens/poster_browse/poster_browse_loader.dart',
```

Run: `flutter test test/media_backend/multi_backend_abstraction_boundary_test.dart`
Expected: PASS（新文件本来就没写 emby 判断；此步是守卫住未来）。

- [ ] **Step 2: 注册路由**

`lib/main.dart`，`/screen/search` case 之后加：

```dart
  if (uri != null && uri.path == '/screen/poster-browse') {
    return AppTransitions.leftToRightPageTurnRoute<void>(
      const PosterBrowseRoute(),
      settings: settings,
    );
  }
```

Route 类区（`SearchRoute` 旁）加：

```dart
class PosterBrowseRoute extends StatelessWidget {
  const PosterBrowseRoute({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ProviderGate(child: PosterBrowseScreen());
  }
}
```

import 区加 `import 'screens/poster_browse/poster_browse_screen.dart';`。

- [ ] **Step 3: 首页入口图标**

`lib/screens/media_list_screen_widgets.dart` AppBar `actions` 里、搜索按钮**之前**加（该文件含 GBK 乱码注释，Edit 锚点用 `actions: <Widget>[` 精确匹配）：

```dart
          if (!widget.secondaryHost)
            IconButton(
              icon: const Icon(Icons.connected_tv_outlined),
              tooltip: AppLocalizations.of(context).posterBrowseEntryTooltip,
              onPressed: () {
                Navigator.of(context).pushNamed('/screen/poster-browse');
              },
            ),
```

- [ ] **Step 4: 静态分析 + 全量测试**

Run: `flutter analyze && flutter test`
Expected: analyze 无新增告警；测试全 PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart lib/screens/media_list_screen_widgets.dart test/media_backend/multi_backend_abstraction_boundary_test.dart
git commit -m "feat(poster-browse): 路由注册与首页入口，边界守卫入册"
```

---

### Task 12: 收尾验证

- [ ] **Step 1: 全量校验**

Run: `flutter analyze && flutter test`
Expected: 全绿。

- [ ] **Step 2: 打包**

Run: `flutter build apk --debug`
Expected: BUILD SUCCESSFUL。

- [ ] **Step 3: 实机验收清单**（三后端各过一遍：飞牛 / Emby / Jellyfin）

1. 首页 AppBar 出现入口图标（分屏副宿主不出现）；点入强制横屏 + 沉浸。
2. 行构成正确：继续观看/最近添加/媒体库行，空行不出现；飞牛"最近添加"若服务器不认排序则该行消失、其余正常。
3. 点缩略图聚焦 → 背景/标题/评分 300ms 内只切一次；快速连点不闪。
4. 评分：信息区 ★ 与角标一致；无评分条目两处都不显示。
5. 再点聚焦项/点"详情" → 竖屏详情页，返回后回到横屏浏览页且焦点保持；配色与详情页一致（同 seed 无闪变）。
6. 点"播放"：电影直接起播；剧集起播续看集；播放返回后页面状态正常。
7. 返回退出页面 → 恢复竖屏、状态栏可见；异常路径（播放器内直接杀回首页）不卡横屏。
8. 弱网：背景图未到时为纯色底，无低清糊图；无 backdrop 条目背景用海报 cover + 压暗。

- [ ] **Step 4: 按验收结果修缺陷后，最终提交**

```bash
git add -A
git commit -m "fix(poster-browse): 实机验收问题修正"
```

---

## Self-Review 结论（已执行）

- **Spec 覆盖**：入口/路由(T11)、getLatestItems 三后端(T3/T4)、行组装与降级(T6/T7)、评分(T2/T9/T10)、取色与背景复用(T10)、节流与预取(T8/T10)、l10n(T5)、横屏恢复双保险(T10 dispose+详情往返)、边界测试(T11)、实机验收(T12) —— 均有任务落点。
- **已知偏差**：spec 提到"重试按钮"与"整页错误态"，T10 以 `_rows.isEmpty` 统一呈现（加载失败与空库同态，点按重试）；"下一行半露"用垂直 PageView `viewportFraction: 0.62` 实现。
- **签名风险点已标注**：T10 末尾两条"对齐"注记 + T3/T4 测试中 connection/api Fake 构造照抄现有测试，不臆造。
