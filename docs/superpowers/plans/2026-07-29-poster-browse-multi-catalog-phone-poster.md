# 海报浏览多媒体库与手机竖版背景修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让飞牛、Emby、Jellyfin 的海报浏览页展示全部后端媒体库，异步补全封面立即刷新，并让所有手机方向使用清晰的竖版封面背景。

**Architecture:** 初始加载只获取继续观看和媒体库元数据，媒体库内容由会话级加载器按需请求、去重并缓存。页面行模型保存目录 ID 与加载状态；焦点素材提交拆分为“当前会话可提交卡片”和“当前焦点可执行副作用”两个判断。横竖屏布局共享全部行并用固定高度横向选择器展示，手机背景策略统一选择竖版素材。

**Tech Stack:** Flutter、Dart、Provider、flutter_test、Flutter l10n

---

## 文件职责映射

- 修改 `lib/screens/poster_browse/poster_browse_rows.dart`：定义媒体库行的 ID、加载状态与不可变更新接口。
- 修改 `lib/screens/poster_browse/poster_browse_loader.dart`：统一加载继续观看和全部后端媒体库元数据。
- 新建 `lib/screens/poster_browse/poster_browse_catalog_session.dart`：负责单库内容的按需加载、并发合并、成功缓存与失败重试。
- 新建 `lib/screens/poster_browse/poster_browse_enrichment_commit_policy.dart`：纯函数描述素材结果的会话与焦点提交边界。
- 修改 `lib/screens/poster_browse/poster_browse_screen.dart`：集成媒体库会话、增量更新行、立即重建补全封面并隔离迟到结果。
- 修改 `lib/screens/poster_browse/poster_browse_large_layout.dart`：删除两行限制，提供固定高度横向分类与行状态占位。
- 修改 `lib/screens/poster_browse/poster_browse_mobile_layout.dart`：删除两行限制，提供固定高度横向分类与行状态占位。
- 修改 `lib/screens/poster_browse/poster_browse_background_policy.dart`：手机横竖屏均采用竖版封面策略。
- 修改 `lib/l10n/app_zh.arb`、`lib/l10n/app_zh_CN.arb` 及生成文件：增加空媒体库提示。
- 修改和新增 `test/poster_browse/` 下的针对性测试文件：锁定每个行为边界。

### Task 1: 行模型与全部后端媒体库元数据

**Files:**
- Modify: `lib/screens/poster_browse/poster_browse_rows.dart`
- Modify: `lib/screens/poster_browse/poster_browse_loader.dart`
- Test: `test/poster_browse/poster_browse_rows_test.dart`

- [ ] **Step 1: 写入失败测试，要求三个后端都保留全部媒体库**

在 `poster_browse_rows_test.dart` 中把旧的“非飞牛只取最近添加”和“飞牛只取第一个 TV”断言替换为以下行为：

```dart
test('按后端顺序返回继续观看与全部媒体库元数据', () async {
  final backend = _FakeMediaBackend(
    kind: MediaBackendKind.emby,
    catalogs: const <MediaCatalog>[
      MediaCatalog(id: 'movies', title: '电影', type: 'movies', primaryImage: MediaImageRef.empty),
      MediaCatalog(id: 'tv', title: '电视剧', type: 'tvshows', primaryImage: MediaImageRef.empty),
      MediaCatalog(id: 'anime', title: '动漫 TV', type: 'tvshows', primaryImage: MediaImageRef.empty),
    ],
    continueWatching: <MediaItemCard>[card('c1')],
  );

  final rows = await const PosterBrowseLoader().load(backend: backend, api: api);

  expect(rows.map((row) => row.title), <String>['', '电影', '电视剧', '动漫 TV']);
  expect(rows.skip(1).map((row) => row.catalogId), <String>['movies', 'tv', 'anime']);
  expect(rows.skip(1).every((row) => row.loadState == PosterBrowseRowLoadState.idle), isTrue);
  expect(backend.getCatalogsCallCount, 1);
  expect(backend.getLatestItemsCallCount, 0);
  expect(backend.getCatalogPreviewItemsCallCount, 0);
});

for (final kind in <MediaBackendKind>[
  MediaBackendKind.feiniu,
  MediaBackendKind.emby,
  MediaBackendKind.jellyfin,
]) {
  test('$kind 均通过公共目录接口返回所有媒体库', () async {
    final backend = _FakeMediaBackend(
      kind: kind,
      catalogs: const <MediaCatalog>[
        MediaCatalog(id: 'a', title: '电影', type: 'Movie', primaryImage: MediaImageRef.empty),
        MediaCatalog(id: 'b', title: '动漫 TV', type: 'Series', primaryImage: MediaImageRef.empty),
      ],
    );

    final rows = await const PosterBrowseLoader().load(backend: backend, api: api);
    expect(rows.map((row) => row.catalogId), <String>['a', 'b']);
  });
}
```

- [ ] **Step 2: 运行测试并确认旧逻辑失败**

Run: `flutter test test/poster_browse/poster_browse_rows_test.dart`

Expected: FAIL，表现为只返回一个飞牛 TV 库，或非飞牛后端仍返回 `latest` 行。

- [ ] **Step 3: 扩展不可变行模型**

在 `poster_browse_rows.dart` 中实现完整状态模型：

```dart
enum PosterBrowseRowKind { continueWatching, latest, catalog }

enum PosterBrowseRowLoadState { idle, loading, loaded, failed }

class PosterBrowseRow {
  final PosterBrowseRowKind kind;
  final String title;
  final String catalogId;
  final PosterBrowseRowLoadState loadState;
  final List<MediaItemCard> items;

  const PosterBrowseRow({
    required this.kind,
    this.title = '',
    this.catalogId = '',
    this.loadState = PosterBrowseRowLoadState.loaded,
    required this.items,
  });

  PosterBrowseRow copyWith({
    List<MediaItemCard>? items,
    PosterBrowseRowLoadState? loadState,
  }) {
    return PosterBrowseRow(
      kind: kind,
      title: title,
      catalogId: catalogId,
      loadState: loadState ?? this.loadState,
      items: items ?? this.items,
    );
  }
}

List<PosterBrowseRow> buildPosterBrowseRows({
  required List<MediaItemCard> continueWatching,
  required List<MediaCatalog> catalogs,
}) {
  return <PosterBrowseRow>[
    if (continueWatching.isNotEmpty)
      PosterBrowseRow(
        kind: PosterBrowseRowKind.continueWatching,
        items: continueWatching,
      ),
    for (final catalog in catalogs)
      PosterBrowseRow(
        kind: PosterBrowseRowKind.catalog,
        title: catalog.title,
        catalogId: catalog.id,
        loadState: PosterBrowseRowLoadState.idle,
        items: const <MediaItemCard>[],
      ),
  ];
}
```

为使用 `MediaCatalog` 增加对应 import；暂时保留 `latest` 枚举值，避免无关本地化代码扩散，页面加载流程不再创建该类型。

- [ ] **Step 4: 统一加载全部媒体库元数据**

将 `PosterBrowseLoader.load` 的两个并行任务改为继续观看和 `getCatalogs()`：

```dart
var continueWatching = const <MediaItemCard>[];
var catalogs = const <MediaCatalog>[];
await Future.wait<void>(<Future<void>>[
  () async {
    try {
      continueWatching = await _loadContinueWatching(
        backend,
        api,
        isFeiniu: backend.capabilities.kind == MediaBackendKind.feiniu,
      );
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'poster browse load continue watching',
        error: error,
        stackTrace: stackTrace,
        source: 'poster_browse_loader',
      );
    }
  }(),
  () async {
    try {
      catalogs = await backend.getCatalogs();
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'poster browse load catalogs',
        error: error,
        stackTrace: stackTrace,
        source: 'poster_browse_loader',
      );
    }
  }(),
]);
return buildPosterBrowseRows(
  continueWatching: continueWatching.take(rowItemLimit).toList(growable: false),
  catalogs: catalogs,
);
```

- [ ] **Step 5: 运行行测试并提交**

Run: `flutter test test/poster_browse/poster_browse_rows_test.dart`

Expected: PASS。

```powershell
git add lib/screens/poster_browse/poster_browse_rows.dart lib/screens/poster_browse/poster_browse_loader.dart test/poster_browse/poster_browse_rows_test.dart
git commit -m "feat(poster-browse): 展示全部后端媒体库"
```

### Task 2: 媒体库按需加载、去重、缓存与重试

**Files:**
- Create: `lib/screens/poster_browse/poster_browse_catalog_session.dart`
- Create: `test/poster_browse/poster_browse_catalog_session_test.dart`

- [ ] **Step 1: 写入会话加载器失败测试**

测试使用 `Completer` 验证并发合并，并验证成功缓存与失败后重试：

```dart
test('同一媒体库并发请求合并且成功结果缓存', () async {
  final backend = _FakeMediaBackend();
  final gate = Completer<List<MediaItemCard>>();
  backend.catalogResponses['anime'] = () => gate.future;
  final session = PosterBrowseCatalogSession(backend: backend, itemLimit: 20);

  final first = session.load('anime');
  final second = session.load('anime');
  expect(backend.requestedCatalogIds, <String>['anime']);

  gate.complete(<MediaItemCard>[card('a1')]);
  expect(await first, same(await second));
  expect((await session.load('anime')).single.id, 'a1');
  expect(backend.requestedCatalogIds, <String>['anime']);
});

test('失败不缓存且下一次调用重试', () async {
  final backend = _FakeMediaBackend();
  var attempt = 0;
  backend.catalogResponses['anime'] = () async {
    attempt += 1;
    if (attempt == 1) throw StateError('temporary');
    return <MediaItemCard>[card('a1')];
  };
  final session = PosterBrowseCatalogSession(backend: backend, itemLimit: 20);

  await expectLater(session.load('anime'), throwsStateError);
  expect((await session.load('anime')).single.id, 'a1');
  expect(attempt, 2);
});
```

- [ ] **Step 2: 运行新测试并确认类不存在**

Run: `flutter test test/poster_browse/poster_browse_catalog_session_test.dart`

Expected: FAIL，提示 `PosterBrowseCatalogSession` 未定义。

- [ ] **Step 3: 实现会话加载器**

新文件实现成功缓存、in-flight 合并与 clear 代次隔离：

```dart
import '../../media_backend/media_backend.dart';
import '../../media_backend/media_item_card.dart';

class PosterBrowseCatalogSession {
  PosterBrowseCatalogSession({required this.backend, required this.itemLimit});

  final MediaBackend backend;
  final int itemLimit;
  final Map<String, List<MediaItemCard>> _cache = <String, List<MediaItemCard>>{};
  final Map<String, Future<List<MediaItemCard>>> _inFlight =
      <String, Future<List<MediaItemCard>>>{};
  int _generation = 0;

  Future<List<MediaItemCard>> load(String rawCatalogId) {
    final catalogId = rawCatalogId.trim();
    final cached = _cache[catalogId];
    if (cached != null) return Future<List<MediaItemCard>>.value(cached);
    return _inFlight.putIfAbsent(catalogId, () => _load(catalogId, _generation));
  }

  Future<List<MediaItemCard>> _load(String catalogId, int generation) async {
    try {
      final items = await backend.getCatalogPreviewItems(
        catalogId,
        limit: itemLimit,
      );
      final result = items.take(itemLimit).toList(growable: false);
      if (generation == _generation) _cache[catalogId] = result;
      return result;
    } finally {
      if (generation == _generation) _inFlight.remove(catalogId);
    }
  }

  void clear() {
    _generation += 1;
    _cache.clear();
    _inFlight.clear();
  }
}
```

- [ ] **Step 4: 运行测试并提交**

Run: `flutter test test/poster_browse/poster_browse_catalog_session_test.dart`

Expected: PASS。

```powershell
git add lib/screens/poster_browse/poster_browse_catalog_session.dart test/poster_browse/poster_browse_catalog_session_test.dart
git commit -m "feat(poster-browse): 按需缓存媒体库预览"
```

### Task 3: 页面增量加载与封面立即刷新

**Files:**
- Create: `lib/screens/poster_browse/poster_browse_enrichment_commit_policy.dart`
- Modify: `lib/screens/poster_browse/poster_browse_screen.dart`
- Create: `test/poster_browse/poster_browse_enrichment_commit_policy_test.dart`
- Test: `test/poster_browse/poster_browse_rows_test.dart`

- [ ] **Step 1: 写入素材提交边界失败测试**

```dart
test('同会话旧焦点结果提交卡片但不执行焦点副作用', () {
  final decision = PosterBrowseEnrichmentCommitPolicy.resolve(
    requestLoadGeneration: 3,
    currentLoadGeneration: 3,
    requestFocusGeneration: 7,
    currentFocusGeneration: 8,
  );
  expect(decision.commitDisplay, isTrue);
  expect(decision.applyFocusEffects, isFalse);
});

test('旧会话结果完全丢弃', () {
  final decision = PosterBrowseEnrichmentCommitPolicy.resolve(
    requestLoadGeneration: 2,
    currentLoadGeneration: 3,
    requestFocusGeneration: 7,
    currentFocusGeneration: 7,
  );
  expect(decision.commitDisplay, isFalse);
  expect(decision.applyFocusEffects, isFalse);
});
```

- [ ] **Step 2: 运行测试并确认策略不存在**

Run: `flutter test test/poster_browse/poster_browse_enrichment_commit_policy_test.dart`

Expected: FAIL，提示提交策略未定义。

- [ ] **Step 3: 实现纯提交策略**

```dart
class PosterBrowseEnrichmentCommitDecision {
  const PosterBrowseEnrichmentCommitDecision({
    required this.commitDisplay,
    required this.applyFocusEffects,
  });
  final bool commitDisplay;
  final bool applyFocusEffects;
}

abstract final class PosterBrowseEnrichmentCommitPolicy {
  static PosterBrowseEnrichmentCommitDecision resolve({
    required int requestLoadGeneration,
    required int currentLoadGeneration,
    required int requestFocusGeneration,
    required int currentFocusGeneration,
  }) {
    final sameSession = requestLoadGeneration == currentLoadGeneration;
    return PosterBrowseEnrichmentCommitDecision(
      commitDisplay: sameSession,
      applyFocusEffects:
          sameSession && requestFocusGeneration == currentFocusGeneration,
    );
  }
}
```

- [ ] **Step 4: 集成目录会话并增量替换行**

在 `PosterBrowseScreen` 中增加 `_catalogSession`，后端切换和 `dispose` 时调用 `clear()`。新增以下核心方法；所有迟到结果都同时校验 load generation 与 load key：

```dart
Future<void> _ensureCatalogLoaded(int rowIndex) async {
  if (rowIndex < 0 || rowIndex >= _rows.length) return;
  final row = _rows[rowIndex];
  if (row.kind != PosterBrowseRowKind.catalog ||
      row.loadState == PosterBrowseRowLoadState.loading ||
      row.loadState == PosterBrowseRowLoadState.loaded) {
    return;
  }
  final session = _catalogSession;
  final loadKey = _loadKey;
  final loadGeneration = _loadGeneration;
  if (session == null || loadKey == null) return;

  setState(() => _replaceRow(
        rowIndex,
        row.copyWith(loadState: PosterBrowseRowLoadState.loading),
      ));
  try {
    final items = await session.load(row.catalogId);
    if (!_isCurrentLoad(generation: loadGeneration, loadKey: loadKey)) return;
    final loaded = row.copyWith(
      items: items,
      loadState: PosterBrowseRowLoadState.loaded,
    );
    setState(() {
      _replaceRow(rowIndex, loaded);
      for (final card in items) {
        _displayById[card.id] = _displayBuilder.build(card: card);
      }
    });
    if (_selection.selectedRow == rowIndex && items.isNotEmpty) {
      await _settle(rowIndex: rowIndex, itemIndex: 0);
    }
  } catch (error, stackTrace) {
    if (!_isCurrentLoad(generation: loadGeneration, loadKey: loadKey)) return;
    setState(() => _replaceRow(
          rowIndex,
          row.copyWith(loadState: PosterBrowseRowLoadState.failed),
        ));
    await logSwallowedError(
      action: 'poster browse load catalog',
      error: error,
      stackTrace: stackTrace,
      source: 'poster_browse_screen',
      id: row.catalogId,
    );
  }
}

void _replaceRow(int index, PosterBrowseRow row) {
  _rows = List<PosterBrowseRow>.of(_rows)..[index] = row;
}
```

初始行写入后后台加载第一个 catalog；若继续观看存在则先 settle 继续观看，否则先选择第一个 catalog。`_handleSelectRow` 对空 catalog 先更新选择状态再调用 `_ensureCatalogLoaded`，对失败行再次调用即重试。

- [ ] **Step 5: 让所有当前会话素材结果触发重建**

在 `_settle` 发起 enrich 前记录 `requestLoadGeneration`，完成后按策略提交：

```dart
final decision = PosterBrowseEnrichmentCommitPolicy.resolve(
  requestLoadGeneration: requestLoadGeneration,
  currentLoadGeneration: _loadGeneration,
  requestFocusGeneration: generation,
  currentFocusGeneration: _focusGeneration,
);
if (!mounted || !decision.commitDisplay) return;
setState(() => _displayById[card.id] = enrichedDisplay);
if (!decision.applyFocusEffects) return;
_precacheNeighbors(
  rowIndex: normalized.rowIndex,
  itemIndex: normalized.itemIndex,
);
```

关键约束是旧焦点分支不能再直接写 `_displayById` 后 `return`；同会话结果必须走 `setState`。

- [ ] **Step 6: 运行策略和数据测试并提交**

Run: `flutter test test/poster_browse/poster_browse_enrichment_commit_policy_test.dart test/poster_browse/poster_browse_rows_test.dart test/poster_browse/poster_browse_catalog_session_test.dart`

Expected: PASS。

```powershell
git add lib/screens/poster_browse/poster_browse_screen.dart lib/screens/poster_browse/poster_browse_enrichment_commit_policy.dart test/poster_browse/poster_browse_enrichment_commit_policy_test.dart
git commit -m "fix(poster-browse): 即时提交封面并按需加载分类"
```

### Task 4: 全部分类的固定高度横向选择器与状态占位

**Files:**
- Modify: `lib/screens/poster_browse/poster_browse_large_layout.dart`
- Modify: `lib/screens/poster_browse/poster_browse_mobile_layout.dart`
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_zh_CN.arb`
- Modify: `lib/l10n/generated/app_localizations.dart`
- Modify: `lib/l10n/generated/app_localizations_zh.dart`
- Test: `test/poster_browse/poster_browse_large_layout_test.dart`
- Test: `test/poster_browse/poster_browse_mobile_layout_test.dart`

- [ ] **Step 1: 写入超过两个分类不截断且不换行的失败测试**

在两个布局测试中分别传入四行并断言末尾分类存在、选择器为横向滚动：

```dart
final rows = <PosterBrowseRow>[
  PosterBrowseRow(kind: PosterBrowseRowKind.continueWatching, items: <MediaItemCard>[continueCard]),
  PosterBrowseRow(kind: PosterBrowseRowKind.catalog, title: '电影', catalogId: 'movies', items: <MediaItemCard>[movieCard]),
  PosterBrowseRow(kind: PosterBrowseRowKind.catalog, title: '电视剧', catalogId: 'tv', items: <MediaItemCard>[tvCard]),
  PosterBrowseRow(kind: PosterBrowseRowKind.catalog, title: '动漫 TV', catalogId: 'anime', items: <MediaItemCard>[animeCard]),
];

expect(find.text('动漫 TV'), findsOneWidget);
expect(
  find.byKey(const ValueKey('poster_browse_row_selector_scroll')),
  findsOneWidget,
);
final scroll = tester.widget<SingleChildScrollView>(
  find.byKey(const ValueKey('poster_browse_row_selector_scroll')),
);
expect(scroll.scrollDirection, Axis.horizontal);
```

再增加加载态与空态测试：

```dart
expect(find.byKey(const ValueKey('poster_browse_row_loading')), findsOneWidget);
expect(find.text('此媒体库暂无内容'), findsOneWidget);
```

- [ ] **Step 2: 运行布局测试并确认失败**

Run: `flutter test test/poster_browse/poster_browse_large_layout_test.dart test/poster_browse/poster_browse_mobile_layout_test.dart`

Expected: FAIL，因为 `rows.take(2)` 丢弃第三、第四行，选择器仍为 `Wrap`。

- [ ] **Step 3: 增加空媒体库本地化文本并重新生成**

在两个 ARB 文件加入：

```json
"posterBrowseCatalogEmpty": "此媒体库暂无内容"
```

Run: `flutter gen-l10n`

Expected: `app_localizations.dart` 和 `app_localizations_zh.dart` 生成 `posterBrowseCatalogEmpty`。

- [ ] **Step 4: 两个布局都使用全部行与单行滚动选择器**

删除 `rows.take(2)`，直接使用 `rows`。将两个 `_RowSelector` 的 `Wrap` 替换为相同结构：

```dart
SizedBox(
  height: 44,
  child: SingleChildScrollView(
    key: const ValueKey('poster_browse_row_selector_scroll'),
    scrollDirection: Axis.horizontal,
    child: Row(
      children: <Widget>[
        for (var index = 0; index < rows.length; index++) ...<Widget>[
          if (index > 0) const SizedBox(width: 10),
          _RowChip(
            label: _rowLabel(AppLocalizations.of(context), rows[index]),
            selected: index == selectedRow,
            onTap: () => onSelectRow(index),
          ),
        ],
      ],
    ),
  ),
)
```

手机版本保留现有 `_RowButton` 视觉，只复用相同滚动容器。当前行内容区域按状态渲染：

```dart
Widget _rowBody(BuildContext context, PosterBrowseRow? row, Widget content) {
  if (row?.loadState == PosterBrowseRowLoadState.loading) {
    return const Center(
      key: ValueKey('poster_browse_row_loading'),
      child: CircularProgressIndicator(),
    );
  }
  if (row?.loadState == PosterBrowseRowLoadState.failed) {
    return Center(child: Text(AppLocalizations.of(context).posterBrowseLoadFailed));
  }
  if (row != null &&
      row.loadState == PosterBrowseRowLoadState.loaded &&
      row.items.isEmpty) {
    return Center(child: Text(AppLocalizations.of(context).posterBrowseCatalogEmpty));
  }
  return content;
}
```

让 `focusedItem` 可空；为空时隐藏 `PosterBrowseMediaInfo`，但保留原有信息区槽位、分类选择器和海报轨道位置。页面首库尚未返回时因此不会误显示整页加载失败。

- [ ] **Step 5: 运行布局测试并提交**

Run: `flutter test test/poster_browse/poster_browse_large_layout_test.dart test/poster_browse/poster_browse_mobile_layout_test.dart`

Expected: PASS，且 `tester.takeException()` 为 null。

```powershell
git add lib/screens/poster_browse/poster_browse_large_layout.dart lib/screens/poster_browse/poster_browse_mobile_layout.dart lib/l10n test/poster_browse/poster_browse_large_layout_test.dart test/poster_browse/poster_browse_mobile_layout_test.dart
git commit -m "fix(poster-browse): 展示全部分类并固定选择器位置"
```

### Task 5: 手机横竖屏统一竖版背景

**Files:**
- Modify: `lib/screens/poster_browse/poster_browse_background_policy.dart`
- Test: `test/poster_browse/poster_browse_background_policy_test.dart`

- [ ] **Step 1: 把手机竖屏旧断言改成竖版封面策略**

```dart
test('手机竖屏使用顶部居中的完整竖版封面', () {
  final spec = PosterBrowseBackgroundPolicy.resolve(
    logicalSize: const Size(390, 844),
    devicePixelRatio: 3,
  );

  expect(spec.usePosterImages, isTrue);
  expect(spec.fit, BoxFit.contain);
  expect(spec.alignment, Alignment.topCenter);
  expect(spec.requestWidth, inInclusiveRange(720, 960));
  expect(spec.cacheWidth, spec.requestWidth);
  expect(spec.prefetchRadius, 1);
});
```

保留手机横屏和 1920×1080 大屏测试，分别锁定右侧完整竖版封面与横版 `cover`。

- [ ] **Step 2: 运行策略测试并确认竖屏断言失败**

Run: `flutter test test/poster_browse/poster_browse_background_policy_test.dart`

Expected: FAIL，旧策略的手机竖屏 `usePosterImages` 为 false。

- [ ] **Step 3: 实现横竖屏手机分支**

```dart
final isPhone = PosterBrowseDeviceProfile.isPhone(logicalSize);
if (isPhone) {
  final isLandscape = logicalSize.width > logicalSize.height;
  final renderedWidth = isLandscape ? logicalSize.height / 1.5 : logicalSize.width;
  final width = (renderedWidth * dpr).round().clamp(360, 960);
  return PosterBrowseBackgroundSpec(
    usePosterImages: true,
    fit: BoxFit.contain,
    alignment: isLandscape ? Alignment.centerRight : Alignment.topCenter,
    requestWidth: width,
    cacheWidth: width,
    prefetchRadius: 1,
  );
}
```

非手机分支保持 `backgroundImages + BoxFit.cover`、1440 解码宽度上限和预取半径 2。

- [ ] **Step 4: 运行策略测试并提交**

Run: `flutter test test/poster_browse/poster_browse_background_policy_test.dart`

Expected: PASS。

```powershell
git add lib/screens/poster_browse/poster_browse_background_policy.dart test/poster_browse/poster_browse_background_policy_test.dart
git commit -m "fix(poster-browse): 手机横竖屏统一使用竖版背景"
```

### Task 6: 集成验证与回归检查

**Files:**
- Verify: `lib/screens/poster_browse/`
- Verify: `test/poster_browse/`

- [ ] **Step 1: 格式化本次 Dart 文件**

Run: `dart format lib/screens/poster_browse test/poster_browse`

Expected: 命令退出码为 0，仅格式化本次涉及文件。

- [ ] **Step 2: 运行全部海报浏览测试**

Run: `flutter test test/poster_browse`

Expected: PASS。

- [ ] **Step 3: 运行与后端抽象相关的回归测试**

Run: `flutter test test/media_backend test/poster_browse`

Expected: 本次相关测试 PASS；若仓库没有 `test/media_backend` 目录，则使用 `rg --files test | rg "media_backend|backend_abstraction"` 找到实际测试文件并逐个运行。

- [ ] **Step 4: 运行静态分析**

Run: `flutter analyze`

Expected: `No issues found!`。

- [ ] **Step 5: 检查差异与工作区边界**

Run: `git diff --check`

Expected: 无输出、退出码为 0。随后运行 `git status --short`，确认未提交的既有 `.codex-remote-attachments/` 与两份 2026-07-27 文档未被纳入本次提交。

- [ ] **Step 6: 提交验证阶段需要的机械修正**

仅当格式化或生成文件在前述任务提交后仍有改动时执行：

```powershell
git add lib/screens/poster_browse lib/l10n test/poster_browse
git commit -m "test(poster-browse): 完成多媒体库回归验证"
```

若没有改动，不创建空提交。
