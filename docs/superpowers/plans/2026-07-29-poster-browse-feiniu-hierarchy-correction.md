# 海报浏览飞牛层级纠错实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让飞牛海报浏览页用真实剧集标题、封面、背景和 Logo，同时把后端 TV/Series 目录仅显示为第二行选择器。

**Architecture:** 在页面入口先清洗飞牛续播卡片，彻底移除媒体库根目录对公共 `seriesId` 和 `secondaryTitle` 的污染；在飞牛后端详情适配器内按“播放信息候选 → 季父链”解析真实剧集 ID。现有 `PosterBrowseArtworkEnricher` 继续依据详情返回的 `seriesId` 懒加载剧集素材，现有 `PosterBrowseDisplayBuilder` 继续负责素材优先级与保持原单集卡片。

**Tech Stack:** Flutter、Dart、`flutter_test`、现有 `FeiniuApi` / `MediaBackend` / 海报浏览补全缓存。

---

## 文件结构与职责

- 修改 `lib/screens/poster_browse/poster_browse_loader.dart`：清洗续播标题与根目录关系；识别 `TV`、`Series` 两种飞牛目录类型。
- 修改 `lib/media_backend/feiniu/feiniu_media_backend.dart`：集中解析单集对应的真实剧集 ID，并对父链请求做 best-effort 回退。
- 修改 `test/poster_browse/poster_browse_rows_test.dart`：覆盖目录标题污染、根目录 ID 隔离、动态 TV 目录行。
- 修改 `test/media_backend/feiniu_detail_backend_test.dart`：覆盖有效 `grand_guid` 与“单集 → 季 → 剧集”父链。
- 修改 `test/poster_browse/poster_browse_display_builder_test.dart`：用纠正后的空 `card.seriesId` 输入锁住真实剧集素材与原单集播放卡片。
- 不修改 `poster_browse_artwork_enricher.dart` 和布局文件：现有补全器已经优先使用 `itemDetail.seriesId`，展示构建器已经优先使用剧集详情素材。

### Task 1：隔离媒体库目录并恢复第二行 TV 目录

**Files:**
- Modify: `test/poster_browse/poster_browse_rows_test.dart:63-250`
- Modify: `lib/screens/poster_browse/poster_browse_loader.dart:15-46,82-98`

- [ ] **Step 1：写入失败测试——目录名不能成为卡片标题或剧集 ID**

在 `poster_browse_rows_test.dart` 中把现有富字段测试对 `seriesId` 的期望改为空，并新增污染场景：

```dart
test('cardFromLibraryItem 隔离媒体库根目录与污染标题', () {
  final item = MediaLibraryItem(
    guid: 'episode-3',
    title: '不灭之焰',
    tvTitle: '动漫 TV',
    type: 'Episode',
    poster: '/episode-still.jpg',
    releaseDate: '',
    firstAirDate: '',
    lastAirDate: '',
    voteAverage: '8',
    overview: '',
    watched: 0,
    watchedTs: 0,
    ts: 120,
    duration: 1380,
    seasonNumber: 1,
    episodeNumber: 3,
    numberOfSeasons: 0,
    numberOfEpisodes: 0,
    localNumberOfSeasons: 0,
    localNumberOfEpisodes: 0,
    parentGuid: 'season-1',
    parentTitle: '第 1 季',
    ancestorGuid: 'library-root',
    ancestorName: '动漫 TV',
    path: '',
  );

  final result = cardFromLibraryItem(item);

  expect(result.id, 'episode-3');
  expect(result.seriesId, isEmpty);
  expect(result.secondaryTitle, isEmpty);
  expect(result.displayTitle, '不灭之焰');
});
```

- [ ] **Step 2：写入失败测试——飞牛 `TV` 目录成为动态第二行**

将现有“飞牛使用首个 Series 目录”用例的首个匹配目录改成：

```dart
const MediaCatalog(
  id: 'anime-tv',
  title: '动漫 TV',
  type: 'TV',
  primaryImage: MediaImageRef.empty,
),
```

并断言：

```dart
expect(rows.single.kind, PosterBrowseRowKind.catalog);
expect(rows.single.title, '动漫 TV');
expect(backend.requestedCatalogIds, <String>['anime-tv']);
expect(backend.getLatestItemsCallCount, 0);
```

- [ ] **Step 3：运行测试并确认按旧实现失败**

Run: `flutter test test/poster_browse/poster_browse_rows_test.dart`

Expected: FAIL；旧实现仍返回 `seriesId == 'library-root'`、`secondaryTitle == '动漫 TV'`，且不会选择类型为 `TV` 的目录。

- [ ] **Step 4：最小实现卡片字段清洗**

在 `cardFromLibraryItem` 开头计算干净剧集名，并按下面的精确替换停止把 `ancestorGuid` 写入 `seriesId`：

```dart
final tvTitle = item.tvTitle.trim();
final ancestorName = item.ancestorName.trim();
final cleanSeriesTitle =
    tvTitle.isNotEmpty && tvTitle != ancestorName ? tvTitle : '';
```

```diff
-    secondaryTitle: item.tvTitle,
+    secondaryTitle: cleanSeriesTitle,
     type: item.type,
-    seriesId: item.ancestorGuid,
+    seriesId: '',
```

这里不保存 `ancestorGuid` 作为任何备用剧集关系；真实关系由详情适配器懒解析。

- [ ] **Step 5：最小实现 TV/Series 类型识别**

把目录筛选条件改为显式的两个后端类型：

```dart
final type = catalog.type.trim().toLowerCase();
if (type == 'tv' || type == 'series') {
  seriesCatalog = catalog;
  break;
}
```

目录标题继续使用 `seriesCatalog.title`，不添加本地固定文案。

- [ ] **Step 6：运行测试并确认通过**

Run: `flutter test test/poster_browse/poster_browse_rows_test.dart`

Expected: PASS；飞牛不调用最近添加，第二行标题和 ID 跟随后端，续播卡片不再携带目录标题/ID。

- [ ] **Step 7：提交第一阶段**

```bash
git add lib/screens/poster_browse/poster_browse_loader.dart test/poster_browse/poster_browse_rows_test.dart
git commit -m "fix(poster-browse): 隔离飞牛媒体库目录"
```

### Task 2：按真实父链解析飞牛剧集 ID

**Files:**
- Modify: `test/media_backend/feiniu_detail_backend_test.dart:12-252`
- Modify: `lib/media_backend/feiniu/feiniu_media_backend.dart:169-254`

- [ ] **Step 1：增强测试 Fake，使播放信息和详情调用可观察**

给 `_FakeFeiniuApi` 增加可配置播放信息和详情调用记录：

```dart
_FakeFeiniuApi(
  super.nas, {
  this.failDictionaries = false,
  this.failingPlayInfoIds = const <String>{},
  this.playInfos = const <String, PlayInfoData>{},
  this.rawDetails = const <String, Map<String, dynamic>>{},
});

final Map<String, PlayInfoData> playInfos;
final List<String> itemDetailRequests = <String>[];

@override
Future<PlayInfoData> getPlayInfo(String itemGuid) async {
  if (failingPlayInfoIds.contains(itemGuid)) {
    throw Exception('play info unavailable: $itemGuid');
  }
  return playInfos[itemGuid] ?? _playInfo(itemGuid: itemGuid);
}

@override
Future<Map<String, dynamic>> getItemDetail(String itemGuid) async {
  itemDetailRequests.add(itemGuid);
  return rawDetails[itemGuid] ?? <String, dynamic>{'imdb_id': 'tt999'};
}
```

新增完整的 `_playInfo` 测试工厂：

```dart
PlayInfoData _playInfo({
  required String itemGuid,
  String type = 'Movie',
  String grandGuid = '',
  String parentGuid = '',
}) {
  return PlayInfoData.fromJson(<String, dynamic>{
    'grand_guid': grandGuid,
    'type': type,
    'ts': 0,
    'media_guid': 'media-$itemGuid',
    'video_guid': 'video-$itemGuid',
    'audio_guid': '',
    'subtitle_guid': '',
    'parent_guid': parentGuid,
    'item': <String, dynamic>{
      'guid': itemGuid,
      'trim_id': '',
      'type': type,
      'title': type == 'Episode' ? '不灭之焰' : '电影',
      'genres': <int>[],
      'production_countries': <String>[],
      'is_watched': 0,
      'is_favorite': 0,
    },
  });
}
```

- [ ] **Step 2：写入失败测试——有效播放信息剧集 ID 优先且不查季**

```dart
test('单集优先使用有效 grandGuid，忽略原始详情中的根目录 grand_guid', () async {
  final nas = NasProvider();
  addTearDown(nas.dispose);
  final api = _FakeFeiniuApi(
    nas,
    playInfos: <String, PlayInfoData>{
      'episode-3': _playInfo(
        itemGuid: 'episode-3',
        type: 'Episode',
        grandGuid: 'series-real',
        parentGuid: 'season-1',
      ),
    },
    rawDetails: const <String, Map<String, dynamic>>{
      'episode-3': <String, dynamic>{
        'grand_guid': 'library-root',
        'item': <String, dynamic>{
          'guid': 'episode-3',
          'type': 'Episode',
          'title': '不灭之焰',
          'parent_guid': 'season-1',
          'ancestor_guid': 'library-root',
        },
      },
    },
  );

  final detail = await FeiniuMediaBackend(api).getItemDetail('episode-3');

  expect(detail.seriesId, 'series-real');
  expect(api.itemDetailRequests, <String>['episode-3']);
});
```

- [ ] **Step 3：写入失败测试——根目录候选通过季详情修正为剧集**

```dart
test('grandGuid 指向根目录时按单集到季到剧集父链解析', () async {
  final nas = NasProvider();
  addTearDown(nas.dispose);
  final api = _FakeFeiniuApi(
    nas,
    playInfos: <String, PlayInfoData>{
      'episode-3': _playInfo(
        itemGuid: 'episode-3',
        type: 'Episode',
        grandGuid: 'library-root',
        parentGuid: 'season-1',
      ),
    },
    rawDetails: const <String, Map<String, dynamic>>{
      'episode-3': <String, dynamic>{
        'item': <String, dynamic>{
          'guid': 'episode-3',
          'type': 'Episode',
          'title': '不灭之焰',
          'parent_guid': 'season-1',
          'ancestor_guid': 'library-root',
        },
      },
      'season-1': <String, dynamic>{
        'item': <String, dynamic>{
          'guid': 'season-1',
          'type': 'Season',
          'parent_guid': 'series-real',
          'ancestor_guid': 'library-root',
        },
      },
    },
  );

  final detail = await FeiniuMediaBackend(api).getItemDetail('episode-3');

  expect(detail.seriesId, 'series-real');
  expect(api.itemDetailRequests, <String>['episode-3', 'season-1']);
});
```

- [ ] **Step 4：运行测试并确认按旧实现失败**

Run: `flutter test test/media_backend/feiniu_detail_backend_test.dart`

Expected: FAIL；旧实现优先采用原始响应顶层 `grand_guid`，且不会请求季详情修正父链。

- [ ] **Step 5：实现原始层级字段读取与候选校验**

在 `FeiniuMediaBackend` 内新增私有帮助方法：

```dart
String _detailText(Map<String, dynamic> detail, String key) {
  final direct = (detail[key] ?? '').toString().trim();
  if (direct.isNotEmpty) return direct;
  final nested = detail['item'];
  return nested is Map<String, dynamic>
      ? (nested[key] ?? '').toString().trim()
      : '';
}

bool _isValidSeriesId(
  String candidate, {
  required String itemId,
  required String seasonId,
  required String ancestorId,
}) {
  final value = candidate.trim();
  return value.isNotEmpty &&
      value != itemId &&
      value != seasonId &&
      value != ancestorId;
}
```

- [ ] **Step 6：实现按类型和父链解析的最小逻辑**

新增异步私有方法并在 `getItemDetail` 映射前调用：

```dart
Future<String> _resolveSeriesId({
  required String itemId,
  required PlayItem item,
  required PlayInfoData? info,
  required Map<String, dynamic> rawDetail,
}) async {
  final normalizedItemId = itemId.trim();
  final itemType = item.type.trim();
  final type = (itemType.isNotEmpty ? itemType : info?.type ?? '')
      .trim()
      .toLowerCase();
  if (type == 'tv' || type == 'series') {
    final ownId = item.guid.trim();
    return ownId.isNotEmpty ? ownId : normalizedItemId;
  }
  if (type != 'episode') return '';

  final ancestorId = _detailText(rawDetail, 'ancestor_guid');
  final infoParentId = info?.parentGuid.trim() ?? '';
  final rawParentId = _detailText(rawDetail, 'parent_guid');
  final seasonId = infoParentId.isNotEmpty ? infoParentId : rawParentId;
  final directCandidate = info?.grandGuid.trim() ?? '';
  if (_isValidSeriesId(
    directCandidate,
    itemId: normalizedItemId,
    seasonId: seasonId,
    ancestorId: ancestorId,
  )) {
    return directCandidate;
  }
  if (seasonId.isEmpty ||
      seasonId == normalizedItemId ||
      seasonId == ancestorId) {
    return '';
  }

  try {
    final seasonDetail = await api.getItemDetail(seasonId);
    final parentCandidate = _detailText(seasonDetail, 'parent_guid');
    final seasonAncestorId = _detailText(seasonDetail, 'ancestor_guid');
    final effectiveAncestorId = ancestorId.isNotEmpty
        ? ancestorId
        : seasonAncestorId;
    return _isValidSeriesId(
      parentCandidate,
      itemId: normalizedItemId,
      seasonId: seasonId,
      ancestorId: effectiveAncestorId,
    )
        ? parentCandidate
        : '';
  } catch (error, stackTrace) {
    await logSwallowedError(
      action: 'resolve feiniu episode series parent',
      id: itemId,
      error: error,
      stackTrace: stackTrace,
      source: 'feiniu_media_backend',
    );
    return '';
  }
}
```

把旧的 `rawDetail['grand_guid']` 优先逻辑替换为：

```dart
final seriesId = await _resolveSeriesId(
  itemId: normalizedItemId,
  item: item,
  info: info,
  rawDetail: rawDetail,
);
```

- [ ] **Step 7：保留剧集自身详情的既有行为**

现有“剧集播放信息不可用时仍从原始 item 详情映射自身素材”测试必须继续断言：

```dart
expect(detail.id, 'series-1');
expect(detail.seriesId, 'series-1');
expect(detail.primaryImage.url, '/series-poster.jpg');
expect(detail.backdropImage.url, '/series-backdrop.jpg');
expect(detail.logoImage.url, '/series-logo.png');
```

- [ ] **Step 8：运行测试并确认通过**

Run: `flutter test test/media_backend/feiniu_detail_backend_test.dart`

Expected: PASS；有效候选零额外父链请求，根目录候选只增加一次季详情请求，剧集自身详情不回归。

- [ ] **Step 9：提交第二阶段**

```bash
git add lib/media_backend/feiniu/feiniu_media_backend.dart test/media_backend/feiniu_detail_backend_test.dart
git commit -m "fix(poster-browse): 解析飞牛真实剧集父链"
```

### Task 3：锁住展示链路与播放目标

**Files:**
- Modify: `test/poster_browse/poster_browse_display_builder_test.dart:129-198`
- Verify: `lib/screens/poster_browse/poster_browse_artwork_enricher.dart:162-199`
- Verify: `lib/screens/poster_browse/poster_browse_display_builder.dart:17-98`

- [ ] **Step 1：新增纠正后输入形态的展示回归测试**

在现有单集素材优先级测试之后新增一个聚焦回归测试；卡片不携带目录标题和目录 ID，真实关系只来自详情补全：

```dart
test('纠正后的飞牛单集使用真实剧集素材且保留原播放卡片', () {
  final result = builder.build(
    card: card(
      id: 'episode-7',
      title: '第七集',
      secondaryTitle: '',
      type: 'Episode',
      seriesId: '',
      primaryImage: image('episode-still'),
      backdropImage: image('episode-backdrop'),
      seasonNumber: 1,
      episodeNumber: 7,
    ),
    itemDetail: detail(
      id: 'episode-7',
      type: 'Episode',
      seriesId: 'series-42',
      backdropImage: image('item-backdrop'),
    ),
    seriesDetail: detail(
      id: 'series-42',
      type: 'TV',
      title: '真实剧集标题',
      primaryImage: image('series-primary'),
      backdropImage: image('series-backdrop'),
      logoImage: image('series-logo'),
    ),
    resolvedSeriesId: 'series-42',
  );

  expect(result.title, '真实剧集标题');
  expect(result.posterImages.first.url, 'series-primary');
  expect(result.backgroundImages.first.url, 'series-backdrop');
  expect(result.logoImages.first.url, 'series-logo');
  expect(result.card.id, 'episode-7');
  expect(result.detailTargetId, 'series-42');
});
```

`result.card.id` 是播放入口使用的原单集 ID；`detailTargetId` 仅用于进入剧集详情，两者不得混用。

- [ ] **Step 2：运行展示与补全测试**

Run: `flutter test test/poster_browse/poster_browse_display_builder_test.dart test/poster_browse/poster_browse_artwork_enricher_test.dart`

Expected: PASS；现有补全器从 `itemDetail.seriesId` 请求 `series-42`，展示构建器把剧集素材排在单集截图之前，原单集卡片保持不变。

- [ ] **Step 3：提交回归测试**

```bash
git add test/poster_browse/poster_browse_display_builder_test.dart
git commit -m "test(poster-browse): 锁住飞牛真实剧集展示链"
```

### Task 4：针对性与静态验证

**Files:**
- Verify: `lib/screens/poster_browse/`
- Verify: `lib/media_backend/feiniu/`
- Verify: `test/poster_browse/`
- Verify: `test/media_backend/feiniu_detail_backend_test.dart`

- [ ] **Step 1：格式化所有本次修改的 Dart 文件**

Run:

```bash
dart format lib/screens/poster_browse/poster_browse_loader.dart lib/media_backend/feiniu/feiniu_media_backend.dart test/poster_browse/poster_browse_rows_test.dart test/media_backend/feiniu_detail_backend_test.dart test/poster_browse/poster_browse_display_builder_test.dart
```

Expected: 命令成功；只格式化列出的本次修改文件。

- [ ] **Step 2：运行全部相关回归测试**

Run:

```bash
flutter test test/poster_browse test/media_backend/feiniu_detail_backend_test.dart test/media_backend/feiniu_detail_mappers_test.dart test/media_backend/feiniu_media_mappers_test.dart
```

Expected: PASS；海报浏览与飞牛详情/映射相关测试全部通过。

- [ ] **Step 3：运行静态分析**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 4：确认没有误改无关文件或残留目录语义**

Run:

```bash
git diff --check
git status --short
rg -n "seriesId: item\.ancestorGuid|catalog\.type\.trim\(\)\.toLowerCase\(\) == 'series'" lib/screens/poster_browse lib/media_backend/feiniu
```

Expected: `git diff --check` 无输出；`rg` 无匹配；状态中仅包含本计划涉及的变更和用户原有未跟踪文件。

- [ ] **Step 5：若格式化产生未提交变更则提交**

```bash
git add lib/screens/poster_browse/poster_browse_loader.dart lib/media_backend/feiniu/feiniu_media_backend.dart test/poster_browse/poster_browse_rows_test.dart test/media_backend/feiniu_detail_backend_test.dart test/poster_browse/poster_browse_display_builder_test.dart
git commit -m "style(poster-browse): 格式化飞牛层级修复"
```

仅在 `git status --short` 显示上述文件仍有格式化变更时执行；没有变更则跳过该提交。
