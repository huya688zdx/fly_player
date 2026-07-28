# 海报浏览页响应式重设计 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将现有横屏海报浏览页改造成只含“继续观看 / 最近添加”的响应式沉浸页：大屏使用横屏竖版海报轨，手机使用背景主导的竖屏弧形循环轮盘，二者共享 Logo、季集信息、评分和素材补全语义。

**Architecture:** `PosterBrowseLoader` 只负责轻量双分组加载；页面专用 `PosterBrowseDisplayItem` / builder 集中承载横竖屏共享语义；`PosterBrowseArtworkEnricher` 基于稳定 ID 懒补全当前项和前后各两项。主页面只编排数据、焦点、方向和播放/详情动作，横屏轨道与手机轮盘分别封装为独立布局组件。

**Tech Stack:** Flutter/Dart、Provider、`flutter_test`、手写 Fake、`SystemChrome`、现有 `MediaBackend` / `DetailArtworkResolver` / `DetailHeroLogoTitle`。

**设计文档：** `docs/superpowers/specs/2026-07-28-poster-browse-responsive-redesign-design.md`

**红线：**

- 所有用户可见文案直接使用 `AppLocalizations` getter；禁止硬编码中文和 `_t()` 间接层。
- 页面和布局组件不得判断 Emby/Jellyfin；飞牛继续观看旁路只留在 loader 数据层。
- 不引入 `BackdropFilter`、实时模糊或低清垫图。
- 拖动过程中不请求网络、不动态取色；只在吸附完成后补全和切背景。
- 不扩展通用 `MediaItemCard`，页面缺失语义放进页面专用展示模型。
- 不修改播放器内部协议；继续复用 `ItemPlaybackLauncher`、`TvSeasonPlaybackLauncher` 和现有反向通道。

---

## 文件结构

| 文件 | 动作 | 单一职责 |
| --- | --- | --- |
| `lib/screens/poster_browse/poster_browse_rows.dart` | 修改 | 仅保留继续观看、最近添加两个分组 |
| `lib/screens/poster_browse/poster_browse_loader.dart` | 修改 | 并行加载两个轻量列表，不请求媒体库 |
| `lib/screens/poster_browse/poster_browse_display_item.dart` | 新建 | 横竖屏共享的不可变展示模型 |
| `lib/screens/poster_browse/poster_browse_display_builder.dart` | 新建 | 格式化标题、季集、评分及图片候选链 |
| `lib/screens/poster_browse/poster_browse_artwork_enricher.dart` | 新建 | 基于稳定 ID 补齐详情/所属剧/季，合并并发并做有界缓存 |
| `lib/screens/poster_browse/poster_browse_media_info.dart` | 新建 | 共享 Logo、文字回退、季集、元信息和按钮区 |
| `lib/screens/poster_browse/poster_browse_poster_card.dart` | 新建 | 共享竖版海报、标题、副信息、评分与进度条 |
| `lib/screens/poster_browse/poster_browse_poster_track.dart` | 新建 | 大屏普通横向竖版海报轨 |
| `lib/screens/poster_browse/poster_browse_arc_carousel.dart` | 新建 | 手机弧形循环轮盘及纯数学映射 |
| `lib/screens/poster_browse/poster_browse_orientation_controller.dart` | 新建 | 设备级手机判定与横竖屏锁定/恢复 |
| `lib/screens/poster_browse/poster_browse_large_layout.dart` | 新建 | 大屏横屏信息区与海报轨排版 |
| `lib/screens/poster_browse/poster_browse_mobile_layout.dart` | 新建 | 手机背景主导、分组控件和弧形轮盘排版 |
| `lib/screens/poster_browse/poster_browse_selection_state.dart` | 新建 | 两个分组各自记忆真实中心索引 |
| `lib/screens/poster_browse/poster_browse_screen.dart` | 修改 | 页面编排、焦点、补全窗口、背景、动作与响应式分流 |
| `test/poster_browse/poster_browse_rows_test.dart` | 修改 | 双分组加载与“不请求媒体库”守卫 |
| `test/poster_browse/poster_browse_display_builder_test.dart` | 新建 | 共享语义、评分、候选链 |
| `test/poster_browse/poster_browse_artwork_enricher_test.dart` | 新建 | 补全、并发、缓存、邻居窗口 |
| `test/poster_browse/poster_browse_poster_card_test.dart` | 新建 | 竖版卡文字、评分和进度 |
| `test/poster_browse/poster_browse_arc_carousel_test.dart` | 新建 | 循环映射、弧线、吸附和点击 |
| `test/poster_browse/poster_browse_responsive_layout_test.dart` | 新建 | 手机/大屏布局与共享 Logo 信息区 |

---

### Task 1: 收敛为“继续观看 / 最近添加”两个分组

**Files:**
- Modify: `lib/screens/poster_browse/poster_browse_rows.dart:1-52`
- Modify: `lib/screens/poster_browse/poster_browse_loader.dart:41-131`
- Modify: `test/poster_browse/poster_browse_rows_test.dart:1-324`

- [ ] **Step 1: 写失败测试，证明 loader 不再请求媒体库**

把 `_FakeMediaBackend` 增加计数器，并将 loader 测试改为：

```dart
int getCatalogsCallCount = 0;
int getCatalogPreviewCallCount = 0;

@override
Future<List<MediaCatalog>> getCatalogs() async {
  getCatalogsCallCount += 1;
  return catalogs;
}

@override
Future<List<MediaItemCard>> getCatalogPreviewItems(
  String catalogId, {
  int page = 1,
  int limit = 30,
}) async {
  getCatalogPreviewCallCount += 1;
  return catalogPreviewItems[catalogId] ?? const <MediaItemCard>[];
}
```

追加测试：

```dart
test('只返回继续观看与最近添加且不请求媒体库', () async {
  final backend = _FakeMediaBackend(
    catalogs: const <MediaCatalog>[
      MediaCatalog(
        id: 'unused',
        title: 'unused',
        type: 'movies',
        primaryImage: MediaImageRef.empty,
      ),
    ],
    continueWatching: <MediaItemCard>[card('c1')],
    latestItems: <MediaItemCard>[card('l1')],
  );

  final rows = await const PosterBrowseLoader().load(
    backend: backend,
    api: api,
  );

  expect(rows.map((row) => row.kind), <PosterBrowseRowKind>[
    PosterBrowseRowKind.continueWatching,
    PosterBrowseRowKind.latest,
  ]);
  expect(backend.getCatalogsCallCount, 0);
  expect(backend.getCatalogPreviewCallCount, 0);
});
```

将原“单 catalog 失败只影响该行”测试删除，因为 catalog 已退出本页面范围；保留飞牛旁路映射测试，并给其 `MediaLibraryItem` 设置 `seasonNumber: 1`、`episodeNumber: 7`，增加：

```dart
expect(cardResult.seasonNumber, 1);
expect(cardResult.episodeNumber, 7);
```

`cardFromLibraryItem` 的 `MediaItemCard(...)` 构造补上：

```dart
seasonNumber: item.seasonNumber,
episodeNumber: item.episodeNumber,
numberOfSeasons: item.numberOfSeasons,
numberOfEpisodes: item.numberOfEpisodes,
localNumberOfSeasons: item.localNumberOfSeasons,
localNumberOfEpisodes: item.localNumberOfEpisodes,
```

这样飞牛继续观看单集可与服务器族共用季集信息构建规则。

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/poster_browse/poster_browse_rows_test.dart`

Expected: FAIL，`getCatalogsCallCount` 为 `1`，且当前行模型仍包含 catalog。

- [ ] **Step 3: 最小化行模型**

将 `poster_browse_rows.dart` 改为：

```dart
import '../../media_backend/media_item_card.dart';

enum PosterBrowseRowKind { continueWatching, latest }

class PosterBrowseRow {
  const PosterBrowseRow({required this.kind, required this.items});

  final PosterBrowseRowKind kind;
  final List<MediaItemCard> items;
}

List<PosterBrowseRow> buildPosterBrowseRows({
  required List<MediaItemCard> continueWatching,
  required List<MediaItemCard> latestItems,
}) {
  return <PosterBrowseRow>[
    if (continueWatching.isNotEmpty)
      PosterBrowseRow(
        kind: PosterBrowseRowKind.continueWatching,
        items: continueWatching,
      ),
    if (latestItems.isNotEmpty)
      PosterBrowseRow(
        kind: PosterBrowseRowKind.latest,
        items: latestItems,
      ),
  ];
}
```

- [ ] **Step 4: 删除 loader 的 catalog 请求**

`PosterBrowseLoader.load` 只保留两个并行请求：

```dart
Future<List<PosterBrowseRow>> load({
  required MediaBackend backend,
  required FeiniuApi api,
  int rowItemLimit = 20,
}) async {
  var continueWatching = const <MediaItemCard>[];
  var latest = const <MediaItemCard>[];

  await Future.wait<void>(<Future<void>>[
    () async {
      try {
        continueWatching = await _loadContinueWatching(backend, api);
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
        latest = await backend.getLatestItems(limit: rowItemLimit);
      } catch (error, stackTrace) {
        await logSwallowedError(
          action: 'poster browse load latest items',
          error: error,
          stackTrace: stackTrace,
          source: 'poster_browse_loader',
        );
      }
    }(),
  ]);

  return buildPosterBrowseRows(
    continueWatching: continueWatching.take(rowItemLimit).toList(growable: false),
    latestItems: latest.take(rowItemLimit).toList(growable: false),
  );
}
```

同时删除 loader 中不再使用的 `media_catalog.dart` import。

- [ ] **Step 5: 运行测试确认通过**

Run: `flutter test test/poster_browse/poster_browse_rows_test.dart`

Expected: PASS。

- [ ] **Step 6: Commit**

```bash
git add lib/screens/poster_browse/poster_browse_rows.dart lib/screens/poster_browse/poster_browse_loader.dart test/poster_browse/poster_browse_rows_test.dart
git commit -m "refactor(poster-browse): 仅保留续看与最近添加分组"
```

---

### Task 2: 建立横竖屏共享展示模型与格式化规则

**Files:**
- Create: `lib/screens/poster_browse/poster_browse_display_item.dart`
- Create: `lib/screens/poster_browse/poster_browse_display_builder.dart`
- Create: `test/poster_browse/poster_browse_display_builder_test.dart`

- [ ] **Step 1: 写失败测试覆盖单集语义和评分**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/detail/media_detail.dart';
import 'package:fly_player/media_backend/detail/media_season_summary.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/media_backend/media_item_card.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_display_builder.dart';

void main() {
  const builder = PosterBrowseDisplayBuilder();

  test('单集使用所属剧标题并组合季集与集名', () {
    const card = MediaItemCard(
      id: 'e7',
      title: '童话般的东西',
      secondaryTitle: '葬送的芙莉莲',
      type: 'Episode',
      seriesId: 'series',
      seasonNumber: 1,
      episodeNumber: 7,
      rating: '9.123',
      primaryImage: MediaImageRef(url: '/episode-wide.jpg'),
      posterWidth: 1920,
      posterHeight: 1080,
    );
    const series = MediaDetail(
      id: 'series',
      type: 'Series',
      title: '葬送的芙莉莲',
      primaryImage: MediaImageRef(url: '/series-poster.jpg'),
      backdropImage: MediaImageRef(url: '/series-bg.jpg'),
      logoImage: MediaImageRef(url: '/series-logo.png'),
    );
    const season = MediaSeasonSummary(
      id: 's1',
      title: '第 1 季',
      seasonNumber: 1,
      primaryImage: MediaImageRef(url: '/season.jpg'),
    );

    final item = builder.build(card: card, seriesDetail: series, season: season);

    expect(item.title, '葬送的芙莉莲');
    expect(item.episodeTitle, '童话般的东西');
    expect(item.seasonNumber, 1);
    expect(item.episodeNumber, 7);
    expect(item.ratingText, '9.1');
    expect(item.detailTargetId, 'series');
    expect(item.logoImages.map((image) => image.url), ['/series-logo.png']);
    expect(item.posterImages.map((image) => image.url), [
      '/season.jpg',
      '/series-poster.jpg',
      '/episode-wide.jpg',
    ]);
  });

  test('评分整数不补零，非法评分隐藏', () {
    expect(builder.formatRating('9.0'), '9');
    expect(builder.formatRating('8'), '8');
    expect(builder.formatRating('bad'), '');
    expect(builder.formatRating(''), '');
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/poster_browse/poster_browse_display_builder_test.dart`

Expected: FAIL，展示模型和 builder 文件不存在。

- [ ] **Step 3: 创建不可变展示模型**

`poster_browse_display_item.dart`：

```dart
import '../../media_backend/media_image_ref.dart';
import '../../media_backend/media_item_card.dart';

class PosterBrowseDisplayItem {
  const PosterBrowseDisplayItem({
    required this.card,
    required this.title,
    required this.episodeTitle,
    required this.type,
    required this.seriesId,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.numberOfSeasons,
    required this.numberOfEpisodes,
    required this.ratingText,
    required this.releaseYear,
    required this.genres,
    required this.durationSeconds,
    required this.overview,
    required this.resolutions,
    required this.backgroundImages,
    required this.logoImages,
    required this.posterImages,
    required this.detailTargetId,
  });

  final MediaItemCard card;
  final String title;
  final String episodeTitle;
  final String type;
  final String seriesId;
  final int seasonNumber;
  final int episodeNumber;
  final int numberOfSeasons;
  final int numberOfEpisodes;
  final String ratingText;
  final String releaseYear;
  final List<String> genres;
  final int durationSeconds;
  final String overview;
  final List<String> resolutions;
  final List<MediaImageRef> backgroundImages;
  final List<MediaImageRef> logoImages;
  final List<MediaImageRef> posterImages;
  final String detailTargetId;

  bool get isEpisode => type.trim().toLowerCase() == 'episode';

  PosterBrowseDisplayItem copyWith({
    String? title,
    String? episodeTitle,
    String? ratingText,
    String? releaseYear,
    List<String>? genres,
    int? durationSeconds,
    String? overview,
    List<String>? resolutions,
    List<MediaImageRef>? backgroundImages,
    List<MediaImageRef>? logoImages,
    List<MediaImageRef>? posterImages,
    String? detailTargetId,
  }) {
    return PosterBrowseDisplayItem(
      card: card,
      title: title ?? this.title,
      episodeTitle: episodeTitle ?? this.episodeTitle,
      type: type,
      seriesId: seriesId,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      numberOfSeasons: numberOfSeasons,
      numberOfEpisodes: numberOfEpisodes,
      ratingText: ratingText ?? this.ratingText,
      releaseYear: releaseYear ?? this.releaseYear,
      genres: genres ?? this.genres,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      overview: overview ?? this.overview,
      resolutions: resolutions ?? this.resolutions,
      backgroundImages: backgroundImages ?? this.backgroundImages,
      logoImages: logoImages ?? this.logoImages,
      posterImages: posterImages ?? this.posterImages,
      detailTargetId: detailTargetId ?? this.detailTargetId,
    );
  }
}
```

- [ ] **Step 4: 实现 builder 与去重候选链**

`poster_browse_display_builder.dart` 提供以下公开接口：

```dart
class PosterBrowseDisplayBuilder {
  const PosterBrowseDisplayBuilder();

  PosterBrowseDisplayItem build({
    required MediaItemCard card,
    MediaDetail? itemDetail,
    MediaDetail? seriesDetail,
    MediaSeasonSummary? season,
  });

  String formatRating(String raw);
}
```

实现规则：

```dart
String formatRating(String raw) {
  final value = double.tryParse(raw.trim());
  if (value == null || !value.isFinite) return '';
  final fixed = value.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}

List<MediaImageRef> _uniqueImages(Iterable<MediaImageRef> images) {
  final seen = <String>{};
  return images.where((image) {
    final url = image.url.trim();
    return url.isNotEmpty && seen.add('${image.headers}|$url');
  }).toList(growable: false);
}
```

`build` 必须按以下顺序生成候选：

```dart
final type = card.type.trim().toLowerCase();
final isEpisode = type == 'episode';
final title = isEpisode
    ? (seriesDetail?.title.trim().isNotEmpty == true
          ? seriesDetail!.title.trim()
          : card.secondaryTitle.trim().isNotEmpty
          ? card.secondaryTitle.trim()
          : card.title.trim())
    : (itemDetail?.displayTitle.trim().isNotEmpty == true
          ? itemDetail!.displayTitle.trim()
          : card.displayTitle);
final episodeTitle = isEpisode && card.title.trim() != title
    ? card.title.trim()
    : '';

final backgroundImages = _uniqueImages(<MediaImageRef>[
  card.backdropImage,
  if (itemDetail != null) itemDetail.backdropImage,
  if (seriesDetail != null) seriesDetail.backdropImage,
  card.primaryImage,
  if (season != null) season.primaryImage,
  if (seriesDetail != null) seriesDetail.primaryImage,
]);
final logoImages = _uniqueImages(<MediaImageRef>[
  if (itemDetail != null) itemDetail.logoImage,
  if (seriesDetail != null) seriesDetail.logoImage,
]);
final currentPrimaryIsPortrait =
    card.hasPosterSize && !card.isLandscapePoster;
final posterImages = _uniqueImages(<MediaImageRef>[
  if (currentPrimaryIsPortrait) card.primaryImage,
  if (season != null) season.primaryImage,
  if (seriesDetail != null) seriesDetail.primaryImage,
  card.primaryImage,
]);
```

其余字段优先取 `itemDetail`，缺失时回退 card；`numberOfSeasons` / `numberOfEpisodes` 先取 detail 对应值，再取 card 的 local 计数，最后取 card 服务端计数；`detailTargetId` 对单集优先 `seriesId`，否则为 `card.id`。

- [ ] **Step 5: 运行测试确认通过**

Run: `flutter test test/poster_browse/poster_browse_display_builder_test.dart`

Expected: PASS。

- [ ] **Step 6: Commit**

```bash
git add lib/screens/poster_browse/poster_browse_display_item.dart lib/screens/poster_browse/poster_browse_display_builder.dart test/poster_browse/poster_browse_display_builder_test.dart
git commit -m "feat(poster-browse): 建立横竖屏共享展示模型"
```

---

### Task 3: 实现稳定 ID 素材补全与相邻窗口预取

**Files:**
- Create: `lib/screens/poster_browse/poster_browse_artwork_enricher.dart`
- Create: `test/poster_browse/poster_browse_artwork_enricher_test.dart`

- [ ] **Step 1: 写失败测试覆盖单集反查和并发合并**

创建 Fake `MediaBackend`，只实现 `getItemDetail`、`getItemSeasons` 并记录调用次数。核心测试：

```dart
test('单集通过 seriesId 补齐所属剧与对应季', () async {
  final backend = _EnrichmentBackend();
  final enricher = PosterBrowseArtworkEnricher(
    backend: backend,
    sessionKey: 'emby|server|user',
  );
  final card = episodeCard(id: 'e7', seriesId: 'series', seasonNumber: 1);

  final result = await enricher.enrich(card);

  expect(result.seriesDetail?.id, 'series');
  expect(result.season?.seasonNumber, 1);
  expect(backend.detailCalls['e7'], 1);
  expect(backend.detailCalls['series'], 1);
  expect(backend.seasonCalls['series'], 1);
});

test('同一缓存键并发补全只发一组请求', () async {
  final backend = _EnrichmentBackend(delay: const Duration(milliseconds: 10));
  final enricher = PosterBrowseArtworkEnricher(
    backend: backend,
    sessionKey: 'emby|server|user',
  );
  final card = episodeCard(id: 'e7', seriesId: 'series', seasonNumber: 1);

  final results = await Future.wait(<Future<PosterBrowseEnrichment>>[
    enricher.enrich(card),
    enricher.enrich(card),
  ]);

  expect(identical(results[0], results[1]), isTrue);
  expect(backend.detailCalls['e7'], 1);
});

test('邻居窗口只覆盖中心前后各两项并按真实索引循环', () {
  expect(
    PosterBrowseArtworkEnricher.windowIndices(center: 0, length: 6),
    <int>[4, 5, 0, 1, 2],
  );
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/poster_browse/poster_browse_artwork_enricher_test.dart`

Expected: FAIL，补全器不存在。

- [ ] **Step 3: 实现补全结果与缓存**

公开类型：

```dart
class PosterBrowseEnrichment {
  const PosterBrowseEnrichment({
    this.itemDetail,
    this.seriesDetail,
    this.season,
  });

  final MediaDetail? itemDetail;
  final MediaDetail? seriesDetail;
  final MediaSeasonSummary? season;
}
```

补全器字段与构造：

```dart
class PosterBrowseArtworkEnricher {
  PosterBrowseArtworkEnricher({
    required this.backend,
    required this.sessionKey,
    this.maxEntries = 80,
  });

  final MediaBackend backend;
  final String sessionKey;
  final int maxEntries;
  final LinkedHashMap<String, PosterBrowseEnrichment> _cache = LinkedHashMap();
  final Map<String, Future<PosterBrowseEnrichment>> _inFlight = {};

  Future<PosterBrowseEnrichment> enrich(MediaItemCard card);
  Future<void> prefetchWindow(List<MediaItemCard> items, int center);
  static List<int> windowIndices({required int center, required int length});
  void clear();
}
```

`enrich` 使用 `$sessionKey|${card.id}` 为 key；缓存命中时删除再插入以刷新 LRU。未命中时把 `_load(card)` 的同一个 Future 放入 `_inFlight`，完成后写缓存并移除进行中项；失败不写长期缓存，只移除 `_inFlight` 后重新抛出，由页面静默降级。

`_load` 的实际请求：

```dart
Future<PosterBrowseEnrichment> _load(MediaItemCard card) async {
  final itemDetail = await _tryDetail(card.id);
  MediaDetail? seriesDetail;
  MediaSeasonSummary? season;

  final seriesId = card.seriesId.trim();
  if (seriesId.isNotEmpty && seriesId != card.id) {
    final seriesFuture = _tryDetail(seriesId);
    final seasonsFuture = _trySeasons(seriesId);
    seriesDetail = await seriesFuture;
    final seasons = await seasonsFuture;
    for (final candidate in seasons) {
      if (candidate.seasonNumber == card.seasonNumber) {
        season = candidate;
        break;
      }
    }
  }

  return PosterBrowseEnrichment(
    itemDetail: itemDetail,
    seriesDetail: seriesDetail,
    season: season,
  );
}
```

使用两个强类型 helper，不使用 `catchError` 的可空推断：

```dart
Future<MediaDetail?> _tryDetail(String itemId) async {
  try {
    return await backend.getItemDetail(itemId);
  } catch (_) {
    return null;
  }
}

Future<List<MediaSeasonSummary>> _trySeasons(String seriesId) async {
  try {
    return await backend.getItemSeasons(seriesId);
  } catch (_) {
    return const <MediaSeasonSummary>[];
  }
}
```

`_load` 调用 `_tryDetail` / `_trySeasons`，不使用 `dynamic` 或 `Future<Object?>`。

- [ ] **Step 4: 实现有界缓存和窗口预取**

```dart
static List<int> windowIndices({required int center, required int length}) {
  if (length <= 0) return const <int>[];
  final indices = <int>[];
  final seen = <int>{};
  for (var offset = -2; offset <= 2; offset++) {
    final index = (center + offset) % length;
    if (seen.add(index)) indices.add(index);
  }
  return indices;
}

Future<void> prefetchWindow(List<MediaItemCard> items, int center) async {
  await Future.wait<void>(
    windowIndices(center: center, length: items.length).map((index) async {
      try {
        await enrich(items[index]);
      } catch (_) {}
    }),
  );
}
```

每次写缓存后执行：

```dart
while (_cache.length > maxEntries) {
  _cache.remove(_cache.keys.first);
}
```

- [ ] **Step 5: 运行测试确认通过**

Run: `flutter test test/poster_browse/poster_browse_artwork_enricher_test.dart`

Expected: PASS。

- [ ] **Step 6: Commit**

```bash
git add lib/screens/poster_browse/poster_browse_artwork_enricher.dart test/poster_browse/poster_browse_artwork_enricher_test.dart
git commit -m "feat(poster-browse): 按稳定父级关系懒补全素材"
```

---

### Task 4: 创建横竖屏共享 Logo 信息区与竖版海报卡

**Files:**
- Create: `lib/screens/poster_browse/poster_browse_media_info.dart`
- Create: `lib/screens/poster_browse/poster_browse_poster_card.dart`
- Create: `test/poster_browse/poster_browse_poster_card_test.dart`

- [ ] **Step 1: 写失败 Widget 测试**

测试竖版卡文字在图片外、评分已格式化、继续观看进度显示：

```dart
testWidgets('海报下显示作品名和季集信息，评分使用展示模型值', (tester) async {
  final item = displayItem(
    title: '葬送的芙莉莲',
    episodeTitle: '童话般的东西',
    ratingText: '9.1',
    seasonNumber: 1,
    episodeNumber: 7,
    resumePositionSeconds: 300,
    durationSeconds: 600,
  );

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: PosterBrowsePosterCard(
        item: item,
        focused: true,
        showProgress: true,
        imageUrl: '',
        imageHeaders: const <String, String>{},
        episodeLabel: '第 1 季 · 第 7 集 · 童话般的东西',
        onTap: () {},
      ),
    ),
  ));

  expect(find.text('葬送的芙莉莲'), findsOneWidget);
  expect(find.text('第 1 季 · 第 7 集 · 童话般的东西'), findsOneWidget);
  expect(find.text('★ 9.1'), findsOneWidget);
  expect(find.byType(LinearProgressIndicator), findsOneWidget);
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/poster_browse/poster_browse_poster_card_test.dart`

Expected: FAIL，组件不存在。

- [ ] **Step 3: 实现共享海报卡**

`PosterBrowsePosterCard` 必须使用固定的 `AspectRatio(aspectRatio: 2 / 3)` 图片区域，标题和 `episodeLabel` 位于图片 `Stack` 外的下方 `Column`。构造签名：

```dart
const PosterBrowsePosterCard({
  super.key,
  required this.item,
  required this.focused,
  required this.showProgress,
  required this.imageUrl,
  required this.imageHeaders,
  required this.episodeLabel,
  required this.onTap,
  this.width = 116,
});
```

评分角标只读取 `item.ratingText`；进度值为：

```dart
final progress = item.card.durationSeconds > 0
    ? (item.card.resumePositionSeconds / item.card.durationSeconds)
          .clamp(0.0, 1.0)
    : 0.0;
```

禁止在组件内重新解析 rating 或拼后端图片 URL。

- [ ] **Step 4: 实现共享 Logo 信息区**

`PosterBrowseMediaInfo` 构造签名：

```dart
const PosterBrowseMediaInfo({
  super.key,
  required this.item,
  required this.logoRequest,
  required this.episodeLabel,
  required this.metaWidgets,
  required this.compact,
  required this.onPlay,
  required this.onDetail,
});
```

Logo 有候选时直接复用：

```dart
DetailHeroLogoTitle(
  images: logoRequest,
  fallbackTitle: item.title,
  maxHeight: compact ? 74 : 112,
  maxWidth: compact ? 240 : 420,
  fallbackFontSize: compact ? 28 : 38,
)
```

Logo 下依次放 `episodeLabel`、元信息 Wrap、简介和按钮。`compact == true` 时简介最多一行且按钮缩小；大屏最多两行。播放与详情文字分别复用 `l10n.detailPlay` 和 `l10n.posterBrowseDetail`，由组件内部获取 `AppLocalizations.of(context)`。

- [ ] **Step 5: 运行测试确认通过**

Run: `flutter test test/poster_browse/poster_browse_poster_card_test.dart`

Expected: PASS。

- [ ] **Step 6: Commit**

```bash
git add lib/screens/poster_browse/poster_browse_media_info.dart lib/screens/poster_browse/poster_browse_poster_card.dart test/poster_browse/poster_browse_poster_card_test.dart
git commit -m "feat(poster-browse): 共享 Logo 信息区与竖版海报卡"
```

---

### Task 5: 实现大屏普通竖版海报轨

**Files:**
- Create: `lib/screens/poster_browse/poster_browse_poster_track.dart`
- Create: `lib/screens/poster_browse/poster_browse_large_layout.dart`
- Test: `test/poster_browse/poster_browse_responsive_layout_test.dart`

- [ ] **Step 1: 写失败测试验证大屏使用普通轨道和 Logo 信息区**

```dart
testWidgets('大屏布局包含 Logo 信息区和普通竖版海报轨', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(size: Size(1280, 800)),
      child: PosterBrowseLargeLayout(
        rows: rows,
        selectedRow: 0,
        focusedIndex: 0,
        focusedItem: focused,
        logoRequest: MediaImageRequest.empty,
        episodeLabel: '第 1 季 · 第 7 集',
        metaWidgets: const <Widget>[],
        imageOf: (_) => MediaImageRequest.empty,
        onSelectRow: (_) {},
        onSelectItem: (_, __) {},
        onPlay: () {},
        onDetail: () {},
      ),
    ),
  ));

  expect(find.byType(PosterBrowseMediaInfo), findsOneWidget);
  expect(find.byType(PosterBrowsePosterTrack), findsOneWidget);
  expect(find.byType(PosterBrowseArcCarousel), findsNothing);
});
```

所有布局与测试统一使用现有 `MediaImageRequest`（`lib/media_backend/media_image_request.dart`），由 `DetailArtworkResolver.resolveRefs(...)` 产出；不要新建第二套图片解析类型。

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/poster_browse/poster_browse_responsive_layout_test.dart`

Expected: FAIL，布局和轨道组件不存在。

- [ ] **Step 3: 实现普通海报轨**

`PosterBrowsePosterTrack` 使用横向 `ListView.separated`，构造签名：

```dart
const PosterBrowsePosterTrack({
  super.key,
  required this.items,
  required this.focusedIndex,
  required this.showProgress,
  required this.imageOf,
  required this.episodeLabelOf,
  required this.onItemTap,
});
```

每项使用 `PosterBrowsePosterCard`；聚焦项通过 `AnimatedScale(scale: 1.06)` 和白色描边表现。点击回调只传 index，是否进入详情由 screen 按“已居中/未居中”统一判断。

- [ ] **Step 4: 实现大屏布局**

`PosterBrowseLargeLayout` 的 Stack 只负责前景：左侧 `PosterBrowseMediaInfo`、底部弱化分组切换和 `PosterBrowsePosterTrack`。背景由 screen 外层统一渲染，避免横竖屏各自实现候选切换。

分组控件使用现有 `posterBrowseRowContinue` / `posterBrowseRowLatest`，选中项白色，未选中项 `white54`；放在海报轨上沿。不要显示旧的 `posterBrowseRowIndicator`。

- [ ] **Step 5: 运行测试确认通过**

Run: `flutter test test/poster_browse/poster_browse_responsive_layout_test.dart`

Expected: PASS 大屏测试。

- [ ] **Step 6: Commit**

```bash
git add lib/screens/poster_browse/poster_browse_poster_track.dart lib/screens/poster_browse/poster_browse_large_layout.dart test/poster_browse/poster_browse_responsive_layout_test.dart
git commit -m "feat(poster-browse): 大屏使用竖版海报轨与共享 Logo 信息"
```

---

### Task 6: 实现手机弧形循环轮盘

**Files:**
- Create: `lib/screens/poster_browse/poster_browse_arc_carousel.dart`
- Create: `test/poster_browse/poster_browse_arc_carousel_test.dart`

- [ ] **Step 1: 先测纯数学映射和中心层级**

```dart
void main() {
  test('虚拟索引首尾循环映射真实索引', () {
    expect(PosterBrowseArcMath.realIndex(-1, 5), 4);
    expect(PosterBrowseArcMath.realIndex(0, 5), 0);
    expect(PosterBrowseArcMath.realIndex(5, 5), 0);
  });

  test('中心卡最高、两侧沿上拱弧线下沉', () {
    final center = PosterBrowseArcMath.transformFor(delta: 0);
    final near = PosterBrowseArcMath.transformFor(delta: 1);
    final far = PosterBrowseArcMath.transformFor(delta: 2);

    expect(center.verticalOffset, lessThan(near.verticalOffset));
    expect(near.verticalOffset, lessThan(far.verticalOffset));
    expect(center.scale, greaterThan(near.scale));
    expect(center.zIndex, greaterThan(near.zIndex));
    expect(near.rotation, greaterThan(0));
  });
}
```

Widget 测试：拖动后 `onSettled` 必须返回吸附到中心的真实 index；点击侧边先 `onSettled`，再次点击中心才触发 `onCenteredTap`。

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/poster_browse/poster_browse_arc_carousel_test.dart`

Expected: FAIL，轮盘不存在。

- [ ] **Step 3: 实现纯数学类型**

```dart
class PosterBrowseArcTransform {
  const PosterBrowseArcTransform({
    required this.horizontalOffset,
    required this.verticalOffset,
    required this.scale,
    required this.rotation,
    required this.opacity,
    required this.zIndex,
  });

  final double horizontalOffset;
  final double verticalOffset;
  final double scale;
  final double rotation;
  final double opacity;
  final int zIndex;
}

abstract final class PosterBrowseArcMath {
  static int realIndex(int virtualIndex, int length) =>
      length == 0 ? 0 : virtualIndex % length;

  static PosterBrowseArcTransform transformFor({required double delta}) {
    final distance = delta.abs();
    return PosterBrowseArcTransform(
      horizontalOffset: delta * 68,
      verticalOffset: 7 * distance * distance,
      scale: (1 - distance * 0.11).clamp(0.72, 1.0),
      rotation: delta * 0.11,
      opacity: (1 - distance * 0.17).clamp(0.35, 1.0),
      zIndex: 1000 - (distance * 100).round(),
    );
  }
}
```

- [ ] **Step 4: 实现跟手拖动与吸附**

`PosterBrowseArcCarousel` 持有一个不受边界限制的 `double _page` 和 `AnimationController`。水平拖动时：

```dart
void _onDragUpdate(DragUpdateDetails details) {
  setState(() => _page -= details.delta.dx / 68);
}

void _onDragEnd(DragEndDetails details) {
  final velocity = details.primaryVelocity ?? 0;
  final target = velocity.abs() >= 420
      ? (_page - velocity.sign).roundToDouble()
      : _page.roundToDouble();
  _animateTo(target);
}
```

绘制 `floor(_page) - 3` 到 `ceil(_page) + 3` 的虚拟项，先按 `zIndex` 从低到高排序再放入 Stack，确保中心最后绘制。真实 item 使用 `realIndex(virtualIndex, items.length)` 取模。动画完成后调用：

```dart
widget.onSettled(PosterBrowseArcMath.realIndex(_page.round(), items.length));
```

单项列表禁用拖动，只渲染一张；双项限制可见虚拟项去重，避免同一真实条目在同侧重复出现。

- [ ] **Step 5: 实现点击行为**

每个视觉卡片的 `onTap`：

```dart
final isCentered = (virtualIndex - _page).abs() < 0.35;
if (isCentered) {
  widget.onCenteredTap(realIndex);
} else {
  _animateTo(virtualIndex.toDouble());
}
```

- [ ] **Step 6: 运行测试确认通过**

Run: `flutter test test/poster_browse/poster_browse_arc_carousel_test.dart`

Expected: PASS。

- [ ] **Step 7: Commit**

```bash
git add lib/screens/poster_browse/poster_browse_arc_carousel.dart test/poster_browse/poster_browse_arc_carousel_test.dart
git commit -m "feat(poster-browse): 手机弧形轮盘支持循环与中心吸附"
```

---

### Task 7: 实现设备级方向策略与手机背景主导布局

**Files:**
- Create: `lib/screens/poster_browse/poster_browse_orientation_controller.dart`
- Create: `lib/screens/poster_browse/poster_browse_mobile_layout.dart`
- Modify: `test/poster_browse/poster_browse_responsive_layout_test.dart`

- [ ] **Step 1: 写失败测试验证横拿手机仍判手机**

```dart
test('设备最短边小于 600dp 时横拿仍判为手机', () {
  expect(PosterBrowseDeviceProfile.isPhone(const Size(844, 390)), isTrue);
  expect(PosterBrowseDeviceProfile.isPhone(const Size(390, 844)), isTrue);
  expect(PosterBrowseDeviceProfile.isPhone(const Size(1280, 800)), isFalse);
});
```

Widget 测试在 `MediaQueryData(size: Size(390, 844))` 下 pump `PosterBrowseMobileLayout`，断言：

```dart
expect(find.byType(PosterBrowseArcCarousel), findsOneWidget);
expect(find.byType(PosterBrowsePosterTrack), findsNothing);
expect(find.byType(PosterBrowseMediaInfo), findsOneWidget);
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/poster_browse/poster_browse_responsive_layout_test.dart`

Expected: FAIL。

- [ ] **Step 3: 实现可测试的设备判定和系统方向控制**

```dart
abstract final class PosterBrowseDeviceProfile {
  static bool isPhone(Size logicalSize) => logicalSize.shortestSide < 600;
}

class PosterBrowseOrientationController {
  const PosterBrowseOrientationController();

  Future<void> enter({required bool isPhone}) async {
    await SystemChrome.setPreferredOrientations(
      isPhone
          ? const <DeviceOrientation>[DeviceOrientation.portraitUp]
          : const <DeviceOrientation>[
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ],
    );
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> restore() async {
    await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}
```

页面应以 `MediaQuery.sizeOf(context).shortestSide` 判定；最短边与当前横竖方向无关，因此横拿手机仍为手机。不要额外要求 `width < height`。

- [ ] **Step 4: 实现手机布局**

`PosterBrowseMobileLayout` 前景结构固定为：

1. 顶部返回按钮；
2. 背景安全区内的 `PosterBrowseMediaInfo(compact: true)`；
3. 轮盘上沿的弱化分组控件；
4. 底部 `PosterBrowseArcCarousel`。

不渲染中心大竖海报。分组切换使用 `onSelectRow`；每组中心真实索引由 screen 保存并传入 `initialIndex`。背景仍由 screen 外层统一渲染。

- [ ] **Step 5: 运行测试确认通过**

Run: `flutter test test/poster_browse/poster_browse_responsive_layout_test.dart`

Expected: PASS 手机与大屏测试。

- [ ] **Step 6: Commit**

```bash
git add lib/screens/poster_browse/poster_browse_orientation_controller.dart lib/screens/poster_browse/poster_browse_mobile_layout.dart test/poster_browse/poster_browse_responsive_layout_test.dart
git commit -m "feat(poster-browse): 手机使用竖屏背景主导布局"
```

---

### Task 8: 将主页面改为编排层并接入补全窗口

**Files:**
- Create: `lib/screens/poster_browse/poster_browse_selection_state.dart`
- Modify: `lib/screens/poster_browse/poster_browse_screen.dart:1-896`
- Delete after migration: `lib/screens/poster_browse/poster_browse_thumb_strip.dart`
- Modify/Delete: `test/poster_browse/poster_browse_thumb_strip_test.dart`

- [ ] **Step 1: 先测试两个分组分别记忆中心索引**

在 `poster_browse_responsive_layout_test.dart` 追加纯状态测试：

```dart
test('两个分组分别记忆中心索引', () {
  final state = PosterBrowseSelectionState();
  state.select(rowIndex: 0, itemIndex: 4);
  state.select(rowIndex: 1, itemIndex: 2);

  expect(state.selectedRow, 1);
  expect(state.indexForRow(0), 4);
  expect(state.indexForRow(1), 2);

  state.selectRow(0);
  expect(state.selectedRow, 0);
  expect(state.currentIndex, 4);
});
```

生产类型固定为：

```dart
class PosterBrowseSelectionState {
  int selectedRow = 0;
  final Map<int, int> _indices = <int, int>{};

  int indexForRow(int rowIndex) => _indices[rowIndex] ?? 0;
  int get currentIndex => indexForRow(selectedRow);

  void select({required int rowIndex, required int itemIndex}) {
    selectedRow = rowIndex;
    _indices[rowIndex] = itemIndex;
  }

  void selectRow(int rowIndex) {
    selectedRow = rowIndex;
  }
}
```

页面继续从 Provider 获取真实 backend，不为测试引入生产环境后端注入或全局单例。

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/poster_browse/poster_browse_responsive_layout_test.dart`

Expected: FAIL，页面尚未接入新布局/状态。

- [ ] **Step 3: 重构页面状态**

主页面保留以下状态：

```dart
List<PosterBrowseRow> _rows = const <PosterBrowseRow>[];
final PosterBrowseSelectionState _selection = PosterBrowseSelectionState();
final Map<String, PosterBrowseDisplayItem> _displayById = {};
String _settledItemId = '';
int _focusGeneration = 0;
bool _loading = true;
bool? _isPhone;
PosterBrowseArtworkEnricher? _enricher;
```

`didChangeDependencies` 首次执行时用最短边判定手机并调用 orientation controller；不要在 `initState` 读取 MediaQuery。

加载完成后先用 builder 仅从 card 构建基础展示模型，立即显示；随后对中心项调用 `_settleFocus`。

- [ ] **Step 4: 接入防过期补全**

```dart
Future<void> _settleFocus(int rowIndex, int itemIndex) async {
  if (rowIndex < 0 || rowIndex >= _rows.length) return;
  final items = _rows[rowIndex].items;
  if (items.isEmpty) return;
  final normalized = itemIndex % items.length;
  final card = items[normalized];
  final generation = ++_focusGeneration;

  setState(() {
    _selection.select(rowIndex: rowIndex, itemIndex: normalized);
    _settledItemId = card.id;
  });

  final enricher = _enricher;
  if (enricher == null) return;
  unawaited(enricher.prefetchWindow(items, normalized));

  try {
    final enrichment = await enricher.enrich(card);
    final display = const PosterBrowseDisplayBuilder().build(
      card: card,
      itemDetail: enrichment.itemDetail,
      seriesDetail: enrichment.seriesDetail,
      season: enrichment.season,
    );
    if (!mounted) return;
    setState(() => _displayById[card.id] = display);
    if (generation != _focusGeneration || _settledItemId != card.id) return;
    _precacheNeighbors();
  } catch (_) {}
}
```

补全旧项允许写入它自己的 `_displayById` 缓存，但只有 generation 和 item ID 都匹配时才能触发当前背景预取/动态取色。

- [ ] **Step 5: 统一 episode label、图片解析与背景切换**

共享副信息只在 screen 的 helper 中调用已有 l10n，覆盖四类媒体：

```dart
String _secondaryLabel(AppLocalizations l10n, PosterBrowseDisplayItem item) {
  final type = item.type.trim().toLowerCase();
  final parts = <String>[];
  if (type == 'episode') {
    if (item.seasonNumber > 0 && item.episodeNumber > 0) {
      parts.add(l10n.detailSeasonEpisodeNumber(
        item.seasonNumber,
        item.episodeNumber,
      ));
    } else if (item.seasonNumber > 0) {
      parts.add(l10n.detailSeasonNumber(item.seasonNumber));
    } else if (item.episodeNumber > 0) {
      parts.add(l10n.detailEpisodeNumber(item.episodeNumber));
    }
    if (item.episodeTitle.trim().isNotEmpty) {
      parts.add(item.episodeTitle.trim());
    }
  } else if (type == 'season') {
    if (item.seasonNumber > 0) {
      parts.add(l10n.detailSeasonNumber(item.seasonNumber));
    }
    if (item.numberOfEpisodes > 0) {
      parts.add(l10n.detailEpisodeTotal(item.numberOfEpisodes));
    }
  } else if (type == 'series' || type == 'tv') {
    if (item.numberOfSeasons > 0) {
      parts.add(l10n.detailTvSeasonCount(item.numberOfSeasons));
    }
    if (item.numberOfEpisodes > 0) {
      parts.add(l10n.detailEpisodeTotal(item.numberOfEpisodes));
    }
  }
  return parts.join(' · ');
}
```

电影返回空副信息。所有 getter 均为现有 `detailSeasonNumber`、`detailEpisodeNumber`、`detailSeasonEpisodeNumber`、`detailTvSeasonCount`、`detailEpisodeTotal`，不新增硬编码文案。

背景 `AnimatedSwitcher` 继续使用现有 `_PosterBrowseBackdrop`，但输入改为展示模型 `backgroundImages` 经 `DetailArtworkResolver.resolveRefs` 的结果。Logo 同理解析 `logoImages` 后传 `DetailHeroLogoTitle`。

- [ ] **Step 6: 响应式分流并保留动作闸门**

```dart
final foreground = _isPhone == true
    ? PosterBrowseMobileLayout(/* shared display data and callbacks */)
    : PosterBrowseLargeLayout(/* same shared display data and callbacks */);
```

两种布局必须传同一个 `PosterBrowseDisplayItem focusedItem`、同一个 `_episodeLabel`、同一组元信息 Widget 和同一对 `_play` / `_openDetail` 回调。

`_openDetailInner` 使用 `item.detailTargetId`；单集有 seriesId 时进入所属剧详情。`_playInner` 仍使用 `item.card` 的真实当前条目，不把详情目标误用为播放目标。

进入详情前临时恢复方向；详情返回后按 `_isPhone` 重新调用 `enter(isPhone: ...)`。`dispose` 无条件 `restore()`。

- [ ] **Step 7: 删除旧缩略图组件**

确认主页面无引用后删除：

- `lib/screens/poster_browse/poster_browse_thumb_strip.dart`
- `test/poster_browse/poster_browse_thumb_strip_test.dart`

它已被 `PosterBrowsePosterCard` + `PosterBrowsePosterTrack` + `PosterBrowseArcCarousel` 完整替代。

- [ ] **Step 8: 运行海报浏览模块测试**

Run: `flutter test test/poster_browse`

Expected: 全 PASS。

- [ ] **Step 9: Commit**

```bash
git add lib/screens/poster_browse test/poster_browse
git commit -m "feat(poster-browse): 接入响应式布局与懒补全编排"
```

---

### Task 9: 静态分析、全量回归与实机验收准备

**Files:**
- Modify only if required by failures: files changed in Tasks 1-8
- Update: `docs/superpowers/plans/2026-07-28-poster-browse-responsive-redesign.md` checkboxes during execution

- [ ] **Step 1: 格式化变更文件**

Run:

```bash
dart format lib/screens/poster_browse test/poster_browse
```

Expected: 命令成功；仅格式化本功能文件。

- [ ] **Step 2: 运行定向测试**

Run: `flutter test test/poster_browse`

Expected: 全 PASS。

- [ ] **Step 3: 运行后端抽象边界与详情相关回归**

Run:

```bash
flutter test test/media_backend/multi_backend_abstraction_boundary_test.dart
flutter test test/media_backend/media_item_card_test.dart
```

Expected: 全 PASS；新页面文件没有 Emby/Jellyfin UI 分支，通用卡片行为未变。

- [ ] **Step 4: 运行静态分析**

Run: `flutter analyze`

Expected: `No issues found!`。如果仓库基线已有问题，保存完整输出并确认没有新增指向 `poster_browse` 的诊断，不能笼统宣称通过。

- [ ] **Step 5: 运行全量测试**

Run: `flutter test`

Expected: 全 PASS。任何失败都先判断是否由本次变更引入；未解决前不得标记完成。

- [ ] **Step 6: 构建 Debug APK**

Run: `flutter build apk --debug`

Expected: `Built build/app/outputs/flutter-apk/app-debug.apk`。

- [ ] **Step 7: 实机验收清单**

逐项记录飞牛、Emby、Jellyfin结果：

1. 横拿手机进入仍自动切竖屏；退出后其他页面方向恢复。
2. 平板/大屏进入横屏；横屏信息区显示作品 Logo，无 Logo 时文字回退。
3. 页面只出现继续观看和最近添加；单组为空时切组控件隐藏。
4. 单集 Logo、背景和季海报能通过父级关系补齐，不串到其他作品。
5. 手机无中心大竖海报，背景占主体；分组标签位于弧形轮盘上沿。
6. 轮盘可无限左右滚动，松手必吸附中心；点侧边先居中，点中心进详情。
7. 快速甩动与快速切组不串背景/Logo，每组保留自己的中心项。
8. 大屏海报为竖版，文字在海报下方；继续观看保留进度条。
9. 评分最长一位小数，非法评分隐藏。
10. 弱网下先显示列表已有素材，补全失败不阻塞播放和详情。

- [ ] **Step 8: 最终提交验证修复**

若 Steps 1-7 产生修复：

```bash
git add lib/screens/poster_browse test/poster_browse docs/superpowers/plans/2026-07-28-poster-browse-responsive-redesign.md
git commit -m "test(poster-browse): 完成响应式海报页回归验证"
```

若没有文件变化，不创建空提交。

---

## 执行依赖与检查点

- Tasks 1-3 是数据基础，必须按顺序完成。
- Task 4 提供横竖屏共享组件；Tasks 5 和 6 可在 Task 4 后分别实施，但按用户要求执行期最多同时使用一个子进程，默认串行。
- Task 7 依赖 Tasks 4-6。
- Task 8 是唯一的大页面整合点；整合前各组件测试必须已经通过。
- Task 9 只有在所有功能任务完成后执行。

## 规格覆盖自查

- 双分组与空组降级：Task 1、Task 8。
- 横竖屏共享 Logo/文字/评分语义：Tasks 2、4、8。
- 单集反查所属剧与季海报：Task 3。
- 大屏横屏竖版海报轨：Task 5。
- 手机背景主导、无中心大海报：Task 7、Task 8。
- 弧形、循环、吸附、点击语义：Task 6。
- 设备级手机判定与方向恢复：Task 7、Task 8。
- 防过期结果、邻居 ±2、缓存有界：Task 3、Task 8。
- 播放/详情正确目标：Task 8。
- 性能与三后端实机验收：Task 9。
