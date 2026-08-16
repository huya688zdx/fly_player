# 海报浏览横屏卡片溢出修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 消除海报浏览页在 `960 × 432` 横屏和最大文字缩放下的卡片底部溢出，同时保留双行标题与一行副标题。

**Architecture:** 保持现有大屏布局、卡片组件和文字规格不变，只把大屏海报轨的固定高度从 `264` 增加到 `280`。用真实窗口尺寸和应用最大文字缩放构造 Widget 回归测试，先证明现有布局产生 `RenderFlex` 溢出，再以单行生产代码修复。

**Tech Stack:** Flutter、Dart、`flutter_test`

---

## 文件结构

- 修改 `test/poster_browse/poster_browse_large_layout_test.dart`：覆盖截图对应的逻辑尺寸、最大文字缩放、双行标题和副标题组合。
- 修改 `lib/screens/poster_browse/poster_browse_large_layout.dart`：调整大屏海报轨的固定高度预算。
- 不新增生产文件，不修改手机轮播、海报卡文字规格或业务数据流。

### Task 1: 复现并修复大屏海报轨溢出

**Files:**
- Modify: `test/poster_browse/poster_browse_large_layout_test.dart:446-489`
- Modify: `lib/screens/poster_browse/poster_browse_large_layout.dart:93-96`

- [ ] **Step 1: 写入会失败的真实尺寸回归测试**

将现有“大屏海报轨为双行标题和副标题保留完整高度”用例替换为以下测试。测试必须在 `960 × 432` 的逻辑窗口中使用应用支持的最大 `1.35` 文字缩放，并继续展示长标题、续播进度和季集副标题：

```dart
testWidgets('大屏海报轨在 960×432 横屏最大文字缩放下保留双行标题和副标题', (
  tester,
) async {
  final card = _card(
    id: 'long-title',
    title: '吹响吧！上低音号特别篇',
    resumePositionSeconds: 30,
    durationSeconds: 120,
  );

  await tester.binding.setSurfaceSize(const Size(960, 432));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _localizedApp(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(960, 432),
          textScaler: TextScaler.linear(1.35),
        ),
        child: PosterBrowseLargeLayout(
          rows: <PosterBrowseRow>[
            PosterBrowseRow(
              kind: PosterBrowseRowKind.continueWatching,
              items: <MediaItemCard>[card],
            ),
          ],
          displayItemOf: _displayItem,
          selectedRow: 0,
          focusedIndex: 0,
          focusedItem: _displayItem(card),
          logoRequest: MediaImageRequest.empty,
          secondaryLabel: '第 1 季 第 1 集',
          metaWidgets: const <Widget>[],
          imageOf: _loadableImageOf,
          secondaryLabelOf: (_) => '第 1 季 第 1 集',
          onSelectRow: (_) {},
          onSelectItem: (_) {},
          onRetryCurrentRow: () {},
          onPlay: () {},
          onDetail: () {},
          onBack: () {},
        ),
      ),
    ),
  );

  expect(tester.takeException(), isNull);
  expect(
    tester.getSize(find.byType(PosterBrowsePosterTrack)).height,
    greaterThanOrEqualTo(280),
  );
});
```

- [ ] **Step 2: 运行回归测试并确认 RED**

Run:

```powershell
flutter test test/poster_browse/poster_browse_large_layout_test.dart --plain-name "大屏海报轨在 960×432 横屏最大文字缩放下保留双行标题和副标题"
```

Expected: FAIL；`tester.takeException()` 捕获 `RenderFlex overflowed`，或海报轨实际高度仍为 `264` 而不满足 `greaterThanOrEqualTo(280)`。失败必须来自现有高度预算，不得是测试语法、网络图片桩或本地化初始化错误。

- [ ] **Step 3: 写入最小生产代码修复**

在 `PosterBrowseLargeLayout` 中仅调整海报轨高度：

```dart
const SizedBox(height: 14),
SizedBox(
  height: 280,
  child: _buildTrackArea(context, currentRow, currentItems),
),
```

不得修改 `PosterBrowsePosterCard` 的 `width`、标题 `maxLines`、副标题 `maxLines` 或字体样式。

- [ ] **Step 4: 重新运行回归测试并确认 GREEN**

Run:

```powershell
flutter test test/poster_browse/poster_browse_large_layout_test.dart --plain-name "大屏海报轨在 960×432 横屏最大文字缩放下保留双行标题和副标题"
```

Expected: PASS；输出中无 `RenderFlex overflowed`、测试异常或失败。

- [ ] **Step 5: 运行海报浏览布局相关测试**

Run:

```powershell
flutter test test/poster_browse/poster_browse_large_layout_test.dart test/poster_browse/poster_browse_poster_card_test.dart test/poster_browse/poster_browse_orientation_controller_test.dart
```

Expected: 全部 PASS，0 个失败；大屏布局、海报卡内容和横竖屏策略没有回归。

- [ ] **Step 6: 运行完整静态分析与差异检查**

Run:

```powershell
flutter analyze
git diff --check -- lib/screens/poster_browse/poster_browse_large_layout.dart test/poster_browse/poster_browse_large_layout_test.dart
git diff -- lib/screens/poster_browse/poster_browse_large_layout.dart test/poster_browse/poster_browse_large_layout_test.dart
```

Expected: `flutter analyze` 以退出码 `0` 完成且无错误；`git diff --check` 无输出；最终差异只包含回归测试尺寸/文字缩放与海报轨高度调整。

- [ ] **Step 7: 提交修复**

```powershell
git add -- lib/screens/poster_browse/poster_browse_large_layout.dart test/poster_browse/poster_browse_large_layout_test.dart
git commit -m "fix(poster-browse): 修复横屏海报卡片溢出"
```
