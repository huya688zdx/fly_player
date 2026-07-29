# 大屏海报浏览素材与布局修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让飞牛继续观看正确显示剧集级海报、背景和 Logo，以后端剧集媒体库替换不存在的“最近添加”，并稳定信息区与优化手机背景、清晰度和轮播间距。

**Architecture:** 在公共 `MediaDetail` 中携带稳定剧集关系，飞牛适配器从 `playInfo.grand_guid` 与原始 item 详情合并出展示详情；海报浏览补全器先解析条目详情再按真实剧集 ID 懒加载父级素材。栏目数据仍由 loader 编排，布局通过共享固定标题槽位和可测试的背景策略分流，大屏、手机竖屏、手机横屏只消费策略结果。

**Tech Stack:** Flutter、Dart、Provider、`flutter_test`、现有 `MediaBackend` 抽象、`DetailArtworkResolver`。

---

## 文件结构

- Modify: `lib/media_backend/detail/media_detail.dart` — 增加稳定 `seriesId` 展示关系。
- Modify: `lib/media_backend/feiniu/feiniu_detail_mappers.dart` — 从播放信息和原始详情映射剧集 ID 与剧集自身素材。
- Modify: `lib/media_backend/feiniu/feiniu_media_backend.dart` — 原始详情与播放信息容错编排。
- Modify: `lib/screens/poster_browse/poster_browse_artwork_enricher.dart` — 按条目详情解析出的真实剧集 ID 懒补全。
- Modify: `lib/screens/poster_browse/poster_browse_display_builder.dart` — 调整单集素材顺序并保留原始播放卡片。
- Modify: `lib/screens/poster_browse/poster_browse_rows.dart` — 支持携带后端标题的剧集媒体库行。
- Modify: `lib/screens/poster_browse/poster_browse_loader.dart` — 飞牛选择首个 Series 媒体库，其他后端保留最近添加。
- Modify: `lib/screens/poster_browse/poster_browse_media_info.dart` — 固定 Logo/标题槽位。
- Create: `lib/screens/poster_browse/poster_browse_background_policy.dart` — 统一选择背景素材、fit、alignment、请求/解码宽度和预取半径。
- Modify: `lib/screens/poster_browse/poster_browse_screen.dart` — 接入背景策略与设备自适应预取。
- Modify: `lib/screens/poster_browse/poster_browse_orientation_controller.dart` — 允许手机横屏进入已设计布局。
- Modify: `lib/screens/poster_browse/poster_browse_arc_carousel.dart` — 响应式紧凑间距。
- Modify: `lib/screens/poster_browse/poster_browse_large_layout.dart` — 动态行标题。
- Modify: `lib/screens/poster_browse/poster_browse_mobile_layout.dart` — 动态行标题和响应式轮播参数。
- Tests: `test/media_backend/feiniu_detail_mappers_test.dart`
- Tests: `test/media_backend/feiniu_detail_backend_test.dart`
- Tests: `test/poster_browse/poster_browse_artwork_enricher_test.dart`
- Tests: `test/poster_browse/poster_browse_display_builder_test.dart`
- Tests: `test/poster_browse/poster_browse_rows_test.dart`
- Tests: `test/poster_browse/poster_browse_large_layout_test.dart`
- Tests: `test/poster_browse/poster_browse_mobile_layout_test.dart`
- Tests: `test/poster_browse/poster_browse_orientation_controller_test.dart`
- Tests: `test/poster_browse/poster_browse_arc_carousel_test.dart`
- Create: `test/poster_browse/poster_browse_background_policy_test.dart`

### Task 1: 飞牛详情暴露真实剧集关系和剧集自身素材

**Files:**
- Modify: `lib/media_backend/detail/media_detail.dart`
- Modify: `lib/media_backend/feiniu/feiniu_detail_mappers.dart`
- Modify: `lib/media_backend/feiniu/feiniu_media_backend.dart`
- Test: `test/media_backend/feiniu_detail_mappers_test.dart`
- Test: `test/media_backend/feiniu_detail_backend_test.dart`

- [ ] **Step 1: 写入失败测试，证明单集详情携带 `grand_guid`**

在 `feiniu_detail_mappers_test.dart` 的剧集映射测试中加入：

```dart
expect(detail.seriesId, 'series-guid');
```

并把测试输入的顶层字段设置为：

```dart
'grand_guid': 'series-guid',
```

- [ ] **Step 2: 写入失败测试，证明请求剧集 ID 时以原始 item 素材为准**

在 `_FakeFeiniuApi` 中让 `getPlayInfo('series-1')` 抛错，同时让 `getItemDetail('series-1')` 返回：

```dart
<String, dynamic>{
  'grand_guid': 'series-1',
  'item': <String, dynamic>{
    'guid': 'series-1',
    'type': 'TV',
    'title': '葬送的芙莉莲',
    'posters': '/series-poster.jpg',
    'backdrops': '/series-backdrop.jpg',
    'logos': '/series-logo.png',
  },
}
```

断言：

```dart
final detail = await backend.getItemDetail('series-1');
expect(detail.id, 'series-1');
expect(detail.primaryImage.url, '/series-poster.jpg');
expect(detail.backdropImage.url, '/series-backdrop.jpg');
expect(detail.logoImage.url, '/series-logo.png');
```

- [ ] **Step 3: 运行测试并确认因关系字段和 raw fallback 缺失而失败**

Run:

```bash
flutter test test/media_backend/feiniu_detail_mappers_test.dart test/media_backend/feiniu_detail_backend_test.dart
```

Expected: FAIL，`MediaDetail.seriesId` 尚不存在，且 series 的 `getPlayInfo` 异常会中断详情。

- [ ] **Step 4: 最小实现 `MediaDetail.seriesId` 与通用 PlayItem 映射**

在 `MediaDetail` 构造与 `copyWith` 中加入默认空值：

```dart
final String seriesId;

const MediaDetail({
  required this.id,
  required this.type,
  required this.title,
  required this.primaryImage,
  this.seriesId = '',
  // 其余参数保持原样
});
```

把飞牛 mapper 拆成由 `PlayItem` 驱动的内部函数，并让现有入口传入 `grandGuid`：

```dart
MediaDetail mapFeiniuItemDetail(
  PlayInfoData info, {
  required Map<int, String> genresMap,
  required Map<String, String> regionNames,
  List<PersonCredit> credits = const <PersonCredit>[],
  String imdbId = '',
}) {
  return mapFeiniuPlayItemDetail(
    info.item,
    seriesId: info.grandGuid,
    resumePositionSeconds: info.ts > 0 ? info.ts : info.item.watchedTs,
    genresMap: genresMap,
    regionNames: regionNames,
    credits: credits,
    imdbId: imdbId,
  );
}
```

新增原始详情提取函数：

```dart
PlayItem? extractFeiniuDetailPlayItem(Map<String, dynamic> detail) {
  final raw = detail['item'];
  final map = raw is Map<String, dynamic> ? raw : detail;
  final guid = (map['guid'] ?? '').toString().trim();
  if (guid.isEmpty) return null;
  return PlayItem.fromJson(map);
}
```

- [ ] **Step 5: 最小实现飞牛 backend 的原始详情 fallback**

先读取原始详情，再 best-effort 获取播放信息；展示条目按“请求 ID 对应的 raw item → playInfo.item”选择：

```dart
final rawDetail = await api.getItemDetail(itemId);
final rawItem = extractFeiniuDetailPlayItem(rawDetail);
PlayInfoData? playInfo;
try {
  playInfo = await api.getPlayInfo(itemId);
} catch (_) {
  if (rawItem == null) rethrow;
}
final item = rawItem?.guid.trim() == itemId.trim()
    ? rawItem!
    : playInfo?.item ?? rawItem!;
final seriesId = (rawDetail['grand_guid'] ?? '').toString().trim().isNotEmpty
    ? (rawDetail['grand_guid'] ?? '').toString().trim()
    : playInfo?.grandGuid.trim() ?? '';
```

完成字典与演职员加载后调用 `mapFeiniuPlayItemDetail`，续播位置使用 `playInfo?.ts`，不可用时回退 `item.watchedTs`。

- [ ] **Step 6: 运行测试确认通过**

Run:

```bash
flutter test test/media_backend/feiniu_detail_mappers_test.dart test/media_backend/feiniu_detail_backend_test.dart
```

Expected: PASS。

- [ ] **Step 7: 提交本任务**

```bash
git add lib/media_backend/detail/media_detail.dart lib/media_backend/feiniu/feiniu_detail_mappers.dart lib/media_backend/feiniu/feiniu_media_backend.dart test/media_backend/feiniu_detail_mappers_test.dart test/media_backend/feiniu_detail_backend_test.dart
git commit -m "fix(poster-browse): 暴露飞牛真实剧集关系"
```

### Task 2: 按真实剧集 ID 补全并纠正素材优先级

**Files:**
- Modify: `lib/screens/poster_browse/poster_browse_artwork_enricher.dart`
- Modify: `lib/screens/poster_browse/poster_browse_display_builder.dart`
- Test: `test/poster_browse/poster_browse_artwork_enricher_test.dart`
- Test: `test/poster_browse/poster_browse_display_builder_test.dart`

- [ ] **Step 1: 写入失败测试，证明 item detail 的 seriesId 覆盖错误卡片关系**

构造卡片原始类型为 `Movie` 且 `card.seriesId == 'library-root'`，但条目详情返回 `type == 'Episode'`、`seriesId == 'series-1'`；断言只请求 `series-1` 的详情和季列表：

```dart
expect(result.resolvedSeriesId, 'series-1');
expect(result.seriesDetail?.id, 'series-1');
expect(backend.detailCalls['library-root'], isNull);
expect(backend.seasonCalls['series-1'], 1);
```

- [ ] **Step 2: 写入失败测试，证明单集素材按剧集优先**

在 display builder 测试中断言：

```dart
expect(result.backgroundImages.map((image) => image.url), [
  'series-backdrop',
  'item-backdrop',
  'card-backdrop',
  'series-primary',
  'season-primary',
  'card-primary',
]);
expect(result.posterImages.map((image) => image.url), [
  'series-primary',
  'season-primary',
  'card-poster',
  'card-primary',
]);
expect(result.logoImages.map((image) => image.url), [
  'series-logo',
  'item-logo',
]);
expect(result.detailTargetId, 'series-1');
expect(result.card.id, 'episode-1');
```

另保留电影测试，断言自身 backdrop、poster、logo 仍在首位。

- [ ] **Step 3: 运行测试确认按旧优先级失败**

Run:

```bash
flutter test test/poster_browse/poster_browse_artwork_enricher_test.dart test/poster_browse/poster_browse_display_builder_test.dart
```

Expected: FAIL，补全器仍使用 `card.seriesId`，单集图片仍在首位。

- [ ] **Step 4: 最小实现真实关系解析**

在 `PosterBrowseEnrichment` 中加入：

```dart
final String resolvedSeriesId;
```

把 `_load` 改为先等待 item detail，再确定父级：

```dart
final itemDetailLookup = await _loadDetail(card.id);
final detailSeriesId = itemDetailLookup.value?.seriesId.trim() ?? '';
final cardSeriesId = card.seriesId.trim();
final resolvedSeriesId = detailSeriesId.isNotEmpty
    ? detailSeriesId
    : cardSeriesId;
final shouldLoadSeries =
    resolvedSeriesId.isNotEmpty && resolvedSeriesId != card.id.trim();
```

series detail 与 seasons 在 ID 确定后并行请求；缓存、失败 TTL 和 generation 逻辑保持原样。

- [ ] **Step 5: 最小实现单集素材顺序**

`PosterBrowseDisplayBuilder.build` 新增 `resolvedSeriesId` 参数，并对 episode 使用独立候选顺序：

```dart
final normalizedType = (itemDetail?.type.trim().isNotEmpty == true
        ? itemDetail!.type
        : card.type)
    .trim()
    .toLowerCase();
final isEpisode = normalizedType == 'episode';
final effectiveSeriesId = resolvedSeriesId.trim().isNotEmpty
    ? resolvedSeriesId.trim()
    : card.seriesId.trim();
```

单集背景和海报按测试顺序组装；电影继续使用原顺序。展示类型使用补全后的条目详情类型，`PosterBrowseDisplayItem.card` 仍传原始 `card`，`detailTargetId` 和展示 `seriesId` 使用 `effectiveSeriesId`。

- [ ] **Step 6: 运行测试确认通过**

Run:

```bash
flutter test test/poster_browse/poster_browse_artwork_enricher_test.dart test/poster_browse/poster_browse_display_builder_test.dart
```

Expected: PASS。

- [ ] **Step 7: 提交本任务**

```bash
git add lib/screens/poster_browse/poster_browse_artwork_enricher.dart lib/screens/poster_browse/poster_browse_display_builder.dart test/poster_browse/poster_browse_artwork_enricher_test.dart test/poster_browse/poster_browse_display_builder_test.dart
git commit -m "fix(poster-browse): 使用剧集级素材补全续播卡"
```

### Task 3: 飞牛第二栏改为后端剧集媒体库

**Files:**
- Modify: `lib/screens/poster_browse/poster_browse_rows.dart`
- Modify: `lib/screens/poster_browse/poster_browse_loader.dart`
- Modify: `lib/screens/poster_browse/poster_browse_large_layout.dart`
- Modify: `lib/screens/poster_browse/poster_browse_mobile_layout.dart`
- Test: `test/poster_browse/poster_browse_rows_test.dart`
- Test: `test/poster_browse/poster_browse_large_layout_test.dart`
- Test: `test/poster_browse/poster_browse_mobile_layout_test.dart`

- [ ] **Step 1: 写入失败测试，证明飞牛选择首个 Series 库并透传标题**

扩展 fake backend 的调用记录，构造：

```dart
catalogs: const <MediaCatalog>[
  MediaCatalog(
    id: 'movie-lib',
    title: '动漫电影',
    type: 'Movie',
    primaryImage: MediaImageRef.empty,
  ),
  MediaCatalog(
    id: 'series-lib',
    title: '动漫 TV',
    type: 'Series',
    primaryImage: MediaImageRef.empty,
  ),
],
```

飞牛 fake API 返回继续观看条目，断言：

```dart
expect(rows[1].kind, PosterBrowseRowKind.catalog);
expect(rows[1].title, '动漫 TV');
expect(backend.requestedCatalogIds, ['series-lib']);
expect(backend.getLatestItemsCallCount, 0);
```

- [ ] **Step 2: 写入失败测试，证明非飞牛仍显示最近添加**

断言非飞牛行类型为 `latest`、标题为空，并且 UI 显示本地化“最近添加”。再新增布局测试，catalog 行显示传入的任意后端标题而不是固定字符串。

- [ ] **Step 3: 运行测试确认旧 loader 和固定标签失败**

Run:

```bash
flutter test test/poster_browse/poster_browse_rows_test.dart test/poster_browse/poster_browse_large_layout_test.dart test/poster_browse/poster_browse_mobile_layout_test.dart
```

Expected: FAIL，尚无 catalog 行和动态标题。

- [ ] **Step 4: 最小实现动态行模型**

```dart
enum PosterBrowseRowKind { continueWatching, latest, catalog }

class PosterBrowseRow {
  final PosterBrowseRowKind kind;
  final String title;
  final List<MediaItemCard> items;

  const PosterBrowseRow({
    required this.kind,
    required this.items,
    this.title = '',
  });
}
```

两个布局的 `_rowLabel` 先返回非空 `row.title`，否则按 kind 本地化。

- [ ] **Step 5: 最小实现后端分流**

在 loader 中只保留一个 `MediaBackendKind.feiniu` 判断，并复用该布尔值加载继续观看与第二栏：

```dart
final isFeiniu = backend.capabilities.kind == MediaBackendKind.feiniu;
```

飞牛路径加载 catalogs，使用大小写不敏感的 `series` 类型匹配，找到首项后调用 `getCatalogPreviewItems(catalog.id, limit: rowItemLimit)`；其他后端调用 `getLatestItems`。空行继续整行剔除。

- [ ] **Step 6: 运行测试与抽象边界测试确认通过**

Run:

```bash
flutter test test/poster_browse/poster_browse_rows_test.dart test/poster_browse/poster_browse_large_layout_test.dart test/poster_browse/poster_browse_mobile_layout_test.dart test/media_backend/multi_backend_abstraction_boundary_test.dart
```

Expected: PASS，且 `MediaBackendKind.feiniu` 白名单计数仍为 1。

- [ ] **Step 7: 提交本任务**

```bash
git add lib/screens/poster_browse/poster_browse_rows.dart lib/screens/poster_browse/poster_browse_loader.dart lib/screens/poster_browse/poster_browse_large_layout.dart lib/screens/poster_browse/poster_browse_mobile_layout.dart test/poster_browse/poster_browse_rows_test.dart test/poster_browse/poster_browse_large_layout_test.dart test/poster_browse/poster_browse_mobile_layout_test.dart
git commit -m "fix(poster-browse): 飞牛展示后端剧集媒体库"
```

### Task 4: 固定 Logo/标题槽位

**Files:**
- Modify: `lib/screens/poster_browse/poster_browse_media_info.dart`
- Test: `test/poster_browse/poster_browse_large_layout_test.dart`
- Test: `test/poster_browse/poster_browse_mobile_layout_test.dart`

- [ ] **Step 1: 写入失败 widget 测试，记录下方组件固定坐标**

分别用空 Logo 和可加载 Logo 构建相同 `PosterBrowseMediaInfo`，以副标题 key 测量纵坐标：

```dart
final withoutLogoY = tester.getTopLeft(
  find.byKey(const ValueKey('poster_browse_secondary')),
).dy;
// 重新 pump 有 Logo 的组件
final withLogoY = tester.getTopLeft(
  find.byKey(const ValueKey('poster_browse_secondary')),
).dy;
expect(withLogoY, withoutLogoY);
```

同时加入超长标题用例，断言无 overflow 异常。

- [ ] **Step 2: 运行测试确认自然高度布局会失败**

Run:

```bash
flutter test test/poster_browse/poster_browse_large_layout_test.dart test/poster_browse/poster_browse_mobile_layout_test.dart
```

Expected: FAIL，下方位置随 Logo/文字高度变化或查找不到稳定 key。

- [ ] **Step 3: 最小实现固定槽位**

```dart
final titleSlotHeight = compact ? 74.0 : 112.0;

SizedBox(
  key: const ValueKey('poster_browse_title_slot'),
  height: titleSlotHeight,
  child: Align(
    alignment: Alignment.bottomLeft,
    child: ClipRect(
      child: DetailHeroLogoTitle(
        images: logoRequest,
        fallbackTitle: item.title,
        maxHeight: titleSlotHeight,
        maxWidth: compact ? 240 : 420,
        fallbackFontSize: compact ? 28 : 38,
      ),
    ),
  ),
),
```

给副标题 Text 添加 `ValueKey('poster_browse_secondary')`。固定槽位之外的间距保持不变。

- [ ] **Step 4: 运行测试确认通过**

Run:

```bash
flutter test test/poster_browse/poster_browse_large_layout_test.dart test/poster_browse/poster_browse_mobile_layout_test.dart
```

Expected: PASS。

- [ ] **Step 5: 提交本任务**

```bash
git add lib/screens/poster_browse/poster_browse_media_info.dart test/poster_browse/poster_browse_large_layout_test.dart test/poster_browse/poster_browse_mobile_layout_test.dart
git commit -m "fix(poster-browse): 固定标题与 Logo 信息槽位"
```

### Task 5: 手机横屏竖版背景与自适应图片成本

**Files:**
- Create: `lib/screens/poster_browse/poster_browse_background_policy.dart`
- Modify: `lib/screens/poster_browse/poster_browse_screen.dart`
- Modify: `lib/screens/poster_browse/poster_browse_orientation_controller.dart`
- Create: `test/poster_browse/poster_browse_background_policy_test.dart`
- Modify: `test/poster_browse/poster_browse_orientation_controller_test.dart`

- [ ] **Step 1: 写入失败纯函数测试**

测试策略在 `Size(844, 390)` 的 phone landscape 返回：

```dart
expect(spec.images, same(item.posterImages));
expect(spec.fit, BoxFit.contain);
expect(spec.alignment, Alignment.centerRight);
expect(spec.prefetchRadius, 1);
expect(spec.requestWidth, inInclusiveRange(360, 720));
```

在大屏 `Size(1920, 1080)` 返回 `backgroundImages`、`BoxFit.cover`、预取半径 2、请求宽度不超过 1440。

- [ ] **Step 2: 写入失败方向测试**

把手机进入方向的期望改为：

```dart
expect(systemUi.orientations, <DeviceOrientation>[
  DeviceOrientation.portraitUp,
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
]);
```

- [ ] **Step 3: 运行测试确认策略不存在且手机仍锁竖屏**

Run:

```bash
flutter test test/poster_browse/poster_browse_background_policy_test.dart test/poster_browse/poster_browse_orientation_controller_test.dart
```

Expected: FAIL，新策略文件不存在，旧方向列表只有 portraitUp。

- [ ] **Step 4: 最小实现背景策略**

创建不可变 spec 与纯策略：

```dart
class PosterBrowseBackgroundSpec {
  final List<MediaImageRef> images;
  final BoxFit fit;
  final Alignment alignment;
  final int requestWidth;
  final int cacheWidth;
  final int prefetchRadius;
  // const constructor
}
```

`resolve` 使用 `shortestSide < 600` 判断 phone，使用 `width > height` 判断 landscape；phone landscape 选择 poster、contain、centerRight，并按 `height / 1.5 * dpr` 计算宽度，限制在 360..720。其余形态选择 background、cover，并按实际屏宽与 DPR 限制在 560..1440。

- [ ] **Step 5: 接入 screen**

在 `build` 中先构造 spec，再用 `resolver.resolveRefs(spec.images, width: spec.requestWidth)`。把 `_PosterBrowseBackdrop` 扩展为接收 `fit` 与 `alignment`：

```dart
Image.network(
  widget.urls[_index],
  fit: widget.fit,
  alignment: widget.alignment,
  cacheWidth: widget.cacheWidth,
  // 其余参数保持原样
)
```

预取循环使用 `spec.prefetchRadius`，ResizeImage 使用 `spec.cacheWidth`；动态主题和详情预热使用同一候选首图。手机横屏底层先绘制黑色背景，现有左右与底部渐变保持。

- [ ] **Step 6: 允许手机横屏并运行测试**

修改 controller 的 phone orientations 为 portraitUp、landscapeLeft、landscapeRight，然后运行：

```bash
flutter test test/poster_browse/poster_browse_background_policy_test.dart test/poster_browse/poster_browse_orientation_controller_test.dart test/poster_browse/poster_browse_mobile_layout_test.dart
```

Expected: PASS。

- [ ] **Step 7: 提交本任务**

```bash
git add lib/screens/poster_browse/poster_browse_background_policy.dart lib/screens/poster_browse/poster_browse_screen.dart lib/screens/poster_browse/poster_browse_orientation_controller.dart test/poster_browse/poster_browse_background_policy_test.dart test/poster_browse/poster_browse_orientation_controller_test.dart test/poster_browse/poster_browse_mobile_layout_test.dart
git commit -m "fix(poster-browse): 优化手机横屏背景与图片成本"
```

### Task 6: 收紧手机弧形轮播间距

**Files:**
- Modify: `lib/screens/poster_browse/poster_browse_arc_carousel.dart`
- Modify: `lib/screens/poster_browse/poster_browse_mobile_layout.dart`
- Test: `test/poster_browse/poster_browse_arc_carousel_test.dart`
- Test: `test/poster_browse/poster_browse_mobile_layout_test.dart`

- [ ] **Step 1: 写入失败的间距数学测试**

```dart
expect(
  PosterBrowseArcMath.spacingFor(viewportWidth: 390, cardWidth: 116),
  inInclusiveRange(145, 158),
);
expect(
  PosterBrowseArcMath.spacingFor(viewportWidth: 844, cardWidth: 116),
  inInclusiveRange(170, 190),
);
```

widget 测试测量中心卡与相邻卡中心横坐标差，断言竖屏小于 170 且大于卡片宽度，横屏小于 200；同时断言无 overflow。

- [ ] **Step 2: 运行测试确认固定 220 间距失败**

Run:

```bash
flutter test test/poster_browse/poster_browse_arc_carousel_test.dart test/poster_browse/poster_browse_mobile_layout_test.dart
```

Expected: FAIL，尚无 `spacingFor`，旧间距为 220。

- [ ] **Step 3: 最小实现响应式间距**

```dart
static double spacingFor({
  required double viewportWidth,
  required double cardWidth,
}) {
  final ratio = viewportWidth >= 600 ? 1.55 : 1.30;
  return (cardWidth * ratio).clamp(cardWidth + 24, 190).toDouble();
}
```

把 widget 的显式 spacing 改为可选 override；默认在 `LayoutBuilder` 内调用 `spacingFor`。平移、拖动除数和吸附计算共用同一个 effective spacing，防止视觉与手势速度不一致。

- [ ] **Step 4: 运行测试确认通过**

Run:

```bash
flutter test test/poster_browse/poster_browse_arc_carousel_test.dart test/poster_browse/poster_browse_mobile_layout_test.dart
```

Expected: PASS。

- [ ] **Step 5: 提交本任务**

```bash
git add lib/screens/poster_browse/poster_browse_arc_carousel.dart lib/screens/poster_browse/poster_browse_mobile_layout.dart test/poster_browse/poster_browse_arc_carousel_test.dart test/poster_browse/poster_browse_mobile_layout_test.dart
git commit -m "fix(poster-browse): 收紧手机轮播卡片间距"
```

### Task 7: 集成验证与回归检查

**Files:**
- Verify: `lib/screens/poster_browse/`
- Verify: `lib/media_backend/`
- Verify: `test/poster_browse/`
- Verify: `test/media_backend/`

- [ ] **Step 1: 运行海报浏览全部测试**

Run:

```bash
flutter test test/poster_browse
```

Expected: PASS，0 failures。

- [ ] **Step 2: 运行相关后端测试与抽象边界测试**

Run:

```bash
flutter test test/media_backend/feiniu_detail_mappers_test.dart test/media_backend/feiniu_detail_backend_test.dart test/media_backend/multi_backend_abstraction_boundary_test.dart
```

Expected: PASS，0 failures。

- [ ] **Step 3: 运行完整测试**

Run:

```bash
flutter test
```

Expected: PASS，0 failures。

- [ ] **Step 4: 运行静态分析**

Run:

```bash
flutter analyze
```

Expected: `No issues found!`。

- [ ] **Step 5: 检查差异、格式和工作区边界**

Run:

```bash
dart format --output=none --set-exit-if-changed lib test
git diff --check
git status --short
```

Expected: Dart 格式无差异，`git diff --check` 无输出；用户原有 `.codex-remote-attachments/` 和既有未跟踪计划文件仍保持未修改。

- [ ] **Step 6: 若格式命令报告差异，格式化本次文件后重跑全部验证**

Run:

```bash
dart format lib/media_backend/detail/media_detail.dart lib/media_backend/feiniu/feiniu_detail_mappers.dart lib/media_backend/feiniu/feiniu_media_backend.dart lib/screens/poster_browse test/media_backend/feiniu_detail_mappers_test.dart test/media_backend/feiniu_detail_backend_test.dart test/poster_browse
flutter test
flutter analyze
```

Expected: 全部命令 exit 0。
