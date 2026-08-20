# 首页连续媒体架修正 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将飞牛、Emby、Jellyfin 首页统一为动态取色、自由横滑且图片比例合理的媒体架，并修正下一集、下载标签和大字长按菜单。

**Architecture:** 用一个无分页状态的 `HomeHorizontalShelf` 负责横向滚动与响应式卡宽；媒体库、继续观看和下一集分别负责自身卡片内容。`HomePresentationProfile` 只决定区块顺序，图片比例由内容类型决定，不再按后端制造不同媒体库形态。

**Tech Stack:** Flutter、Dart、Material 3、Provider、现有 `AppThemeColors`、`MediaImageRequest` 与 `flutter_test`。

---

## 文件结构

- Create: `lib/screens/home/widgets/home_horizontal_shelf.dart` — 自由横滑和响应式卡宽。
- Create: `lib/screens/home/widgets/home_landscape_media_section.dart` — 下一集横向剧集卡。
- Modify: `lib/screens/home/home_presentation_profile.dart` — 统一区块相对顺序，删除媒体库平台样式。
- Modify: `lib/screens/home/widgets/home_catalog_section.dart` — 自然比例海报架。
- Modify: `lib/screens/home/widgets/home_continue_watching_section.dart` — 自由横滑、动态色、文字下载标签。
- Modify: `lib/screens/home/widgets/home_section_header.dart` — 删除无用数量尾部。
- Modify: `lib/screens/media_list_screen_widgets.dart` — 组合区块、删除剩余时间、下一集使用横向请求。
- Modify: `lib/widgets/common/app_action_sheet.dart` — 大字长标签高度。
- Delete: `lib/screens/home/widgets/home_adaptive_pager.dart` — 首页不再分页。
- Modify/Create corresponding tests under `test/screens/home/` and `test/widgets/`.

## Task 1：无分页的响应式横向媒体架

**Files:**
- Create: `lib/screens/home/widgets/home_horizontal_shelf.dart`
- Create: `test/widgets/home_horizontal_shelf_test.dart`
- Delete after migration: `lib/screens/home/widgets/home_adaptive_pager.dart`
- Delete after migration: `test/widgets/home_adaptive_pager_test.dart`

- [ ] **Step 1: 写自由停留失败测试**

测试构建 8 个带稳定 key 的项目，宽度 360；断言存在横向 `ListView`、不存在 `PageView` 和分页语义。拖动 95 逻辑像素后读取横向 `ScrollableState.position.pixels`，断言偏移大于 0 且小于第一张卡片宽度，证明没有按整页吸附。

```dart
testWidgets('首页媒体架可停在任意横向偏移且不显示分页器', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 360,
        child: HomeHorizontalShelf<int>(
          storageKey: 'continue',
          items: List<int>.generate(8, (index) => index),
          idealItemWidth: 210,
          minItemWidth: 176,
          maxItemWidth: 210,
          itemAspectRatio: 16 / 10,
          textLinesHeight: 44,
          itemBuilder: (_, item, width) => SizedBox(
            key: ValueKey('item-$item'),
            width: width,
          ),
        ),
      ),
    ),
  ));
  expect(find.byType(PageView), findsNothing);
  expect(find.byType(ListView), findsOneWidget);
  final firstWidth = tester.getSize(find.byKey(const ValueKey('item-0'))).width;
  await tester.drag(find.byType(ListView), const Offset(-95, 0));
  await tester.pump();
  final position = tester.state<ScrollableState>(find.byType(Scrollable)).position;
  expect(position.pixels, greaterThan(0));
  expect(position.pixels, lessThan(firstWidth));
});
```

- [ ] **Step 2: 运行测试确认红灯**

Run: `flutter test test/widgets/home_horizontal_shelf_test.dart`

Expected: FAIL，因为 `HomeHorizontalShelf` 尚不存在。

- [ ] **Step 3: 实现最小自由媒体架**

组件使用 `LayoutBuilder`。手机宽度取可用宽度的 `0.56`，500–699 取 `0.40`，700 以上取 `0.28`，随后夹在调用方的 `minItemWidth..maxItemWidth`；高度延续原组件的图片比例和真实 `TextScaler` 文字预算。使用 `PageStorageKey(storageKey)` 的 `ListView.separated`、`ClampingScrollPhysics`、零 padding，不包 `Scrollbar`，不构建圆点。

```dart
class HomeHorizontalShelf<T> extends StatelessWidget {
  const HomeHorizontalShelf({
    super.key,
    required this.storageKey,
    required this.items,
    required this.itemBuilder,
    required this.idealItemWidth,
    required this.minItemWidth,
    required this.maxItemWidth,
    required this.itemAspectRatio,
    this.textLinesHeight = 44,
    this.gap = 12,
  });

  final String storageKey;
  final List<T> items;
  final Widget Function(BuildContext, T, double) itemBuilder;
  final double idealItemWidth;
  final double minItemWidth;
  final double maxItemWidth;
  final double itemAspectRatio;
  final double textLinesHeight;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      final fraction = constraints.maxWidth >= 700
          ? .28
          : constraints.maxWidth >= 500
          ? .40
          : .56;
      final width = (constraints.maxWidth * fraction)
          .clamp(minItemWidth, maxItemWidth)
          .toDouble();
      final scaler = MediaQuery.textScalerOf(context);
      final textRatio = math.max(scaler.scale(14) / 14, scaler.scale(12) / 12);
      final height = width / itemAspectRatio +
          textLinesHeight * textRatio.clamp(1.0, double.infinity);
      return SizedBox(
        height: height,
        child: ListView.separated(
          key: PageStorageKey<String>('home-shelf-$storageKey'),
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: items.length,
          separatorBuilder: (_, __) => SizedBox(width: gap),
          itemBuilder: (context, index) => SizedBox(
            width: width,
            child: itemBuilder(context, items[index], width),
          ),
        ),
      );
    });
  }
}
```

- [ ] **Step 4: 运行测试并提交**

Run: `flutter test test/widgets/home_horizontal_shelf_test.dart`

Expected: PASS。

```bash
git add lib/screens/home/widgets/home_horizontal_shelf.dart test/widgets/home_horizontal_shelf_test.dart
git commit -m "feat: add continuous responsive home shelf"
```

## Task 2：统一平台顺序与媒体库海报架

**Files:**
- Modify: `lib/screens/home/home_presentation_profile.dart`
- Modify: `lib/screens/home/widgets/home_catalog_section.dart`
- Modify: `lib/screens/home/widgets/home_section_header.dart`
- Modify: `lib/screens/media_list_screen_widgets.dart`
- Modify: `test/screens/home/home_presentation_profile_test.dart`
- Modify: `test/widgets/home_catalog_section_test.dart`
- Modify: `test/screens/media_list_home_composition_test.dart`

- [ ] **Step 1: 写统一顺序和媒体库失败测试**

三个 profile 的 `catalogs` 必须排在 `continueWatching` 前；Emby/Jellyfin 的 `continueWatching` 必须排在 `nextUp/latest` 前。媒体库区块不得出现“个”、`PageView` 或分页语义；两张图片时找到两个竖版图片槽，并断言每个槽高宽比接近 `1.5`，标题 bounds 在图片舞台下方。

```dart
for (final kind in MediaBackendKind.values) {
  final order = HomePresentationProfile.forKind(kind).sectionOrder;
  expect(order.indexOf(HomeSectionKind.catalogs),
      lessThan(order.indexOf(HomeSectionKind.continueWatching)));
}
expect(find.textContaining('个'), findsNothing);
expect(find.byType(PageView), findsNothing);
final posterSize = tester.getSize(find.byKey(const ValueKey('catalog-poster-lib-1-0')));
expect(posterSize.height / posterSize.width, closeTo(1.5, .08));
```

- [ ] **Step 2: 运行测试确认红灯**

Run: `flutter test test/screens/home/home_presentation_profile_test.dart test/widgets/home_catalog_section_test.dart test/screens/media_list_home_composition_test.dart`

Expected: FAIL，旧 profile 顺序不同且媒体库仍使用分页铺满卡。

- [ ] **Step 3: 实现统一 profile 和海报架**

删除 `HomeCatalogStyle` 与 `HomePresentationProfile.catalogStyle`。三个 profile 的共同相对顺序为 `catalogs → continueWatching → nextUp → latest → summary → catalogPreviews`，每个平台可省略后端不提供的区块，但不得交换这些共同区块。

`HomeCatalogSection` 使用 `HomeHorizontalShelf`，`storageKey: 'catalogs'`、`minItemWidth: 156`、`maxItemWidth: 184`、`itemAspectRatio: 1.08`、`textLinesHeight: 0`。卡片主体为动态 `surfaceStrong`，边框为 `colors.accent.withValues(alpha: .18)`；图片舞台内最多两张竖版海报，图片用 `AspectRatio(aspectRatio: 2 / 3)` 和 `BoxFit.cover`，标题在舞台下独立显示。`_homeCatalogImageRequests` 固定最多取两张，不再接收平台 style。

`HomeSectionHeader` 删除 `trailingText` 参数和尾部渲染；所有调用点只传 title。

- [ ] **Step 4: 运行测试并提交**

Run: `flutter test test/screens/home/home_presentation_profile_test.dart test/widgets/home_catalog_section_test.dart test/screens/media_list_home_composition_test.dart`

Expected: PASS。

```bash
git add lib/screens/home/home_presentation_profile.dart lib/screens/home/widgets/home_catalog_section.dart lib/screens/home/widgets/home_section_header.dart lib/screens/media_list_screen_widgets.dart test/screens/home/home_presentation_profile_test.dart test/widgets/home_catalog_section_test.dart test/screens/media_list_home_composition_test.dart
git commit -m "fix: align catalog shelves across backends"
```

## Task 3：继续观看和下一集使用正确横向卡片

**Files:**
- Modify: `lib/screens/home/widgets/home_continue_watching_section.dart`
- Create: `lib/screens/home/widgets/home_landscape_media_section.dart`
- Modify: `lib/screens/media_list_screen_widgets.dart`
- Modify: `test/widgets/home_continue_watching_section_test.dart`
- Create: `test/widgets/home_landscape_media_section_test.dart`
- Modify: `test/screens/media_list_home_composition_test.dart`

- [ ] **Step 1: 写继续观看共同修正失败测试**

测试使用 8 条数据，断言没有数量、`PageView`、分页圆点和“剩余”；存在可横滑 `ListView`。下载项显示文字“已下载”而不是 `Icons.download_done_rounded`。自定义动态 accent 后，播放圆形装饰和进度条都解析为该 accent，播放前景按亮度为黑或白。

```dart
expect(find.textContaining('条'), findsNothing);
expect(find.textContaining('剩余'), findsNothing);
expect(find.byType(PageView), findsNothing);
expect(find.text('已下载'), findsOneWidget);
expect(find.byIcon(Icons.download_done_rounded), findsNothing);
final progress = tester.widget<LinearProgressIndicator>(
  find.byKey(const ValueKey('continue-progress-item-1')),
);
expect(progress.color, dynamicAccent);
```

- [ ] **Step 2: 写下一集横图失败测试**

`HomeLandscapeMediaSection` 测试断言图片卡的宽高比在 `1.55..1.8`，`Image.fit == BoxFit.cover`，不存在 `MediaPosterCard`，卡片点击与长按分别触发传入回调。

```dart
expect(find.byType(MediaPosterCard), findsNothing);
final artwork = tester.getSize(find.byKey(const ValueKey('landscape-artwork-next-1')));
expect(artwork.width / artwork.height, inInclusiveRange(1.55, 1.8));
expect(tester.widget<Image>(find.byKey(const ValueKey('landscape-image-next-1'))).fit,
    BoxFit.cover);
```

- [ ] **Step 3: 运行测试确认红灯**

Run: `flutter test test/widgets/home_continue_watching_section_test.dart test/widgets/home_landscape_media_section_test.dart test/screens/media_list_home_composition_test.dart`

Expected: FAIL，继续观看仍分页且下一集仍复用竖版卡。

- [ ] **Step 4: 实现继续观看修正**

改用 `HomeHorizontalShelf<HomeContinueCardData>`，`storageKey: 'continue-watching'`、宽度范围 `176..210`、`itemAspectRatio: 16 / 10`。删除标题数量。播放按钮背景使用 `colors.accent`；前景为：

```dart
final playForeground = ThemeData.estimateBrightnessForColor(colors.accent) ==
        Brightness.dark
    ? Colors.white
    : const Color(0xFF1B1B1B);
```

`_DownloadedBadge` 的 child 改为白色 `Text('已下载', fontSize: 11, fontWeight: FontWeight.w600)`。`_continueContextText` 只返回电影类型或季集文本，不再调用 `PlayDetailFormatters.remainText`。

- [ ] **Step 5: 实现下一集横向媒体区块**

新增 `HomeLandscapeCardData`（id、title、contextText、imageRequest）和 `HomeLandscapeMediaSection`。使用 `HomeHorizontalShelf`、`16 / 10` 图片、标题/次要信息各一行、`BoxFit.cover`、动态缺图底板。卡片 tap 与 long press 由调用方提供。

`media_list_screen_widgets.dart` 将 `HomeSectionKind.nextUp` 改为 `_buildHomeNextUpShelf`：图片请求复用“backdrop 优先、poster 回退”的横向请求逻辑；`contextText` 使用季集信息；tap/long press 保留现有详情和操作入口。`latest` 与 catalog previews 继续调用 `_buildPosterRow`。

- [ ] **Step 6: 删除旧分页组件并运行测试**

确认无生产引用后删除 `home_adaptive_pager.dart` 和其旧测试。

Run: `rg -n "HomeAdaptivePager|home_adaptive_pager" lib test`

Expected: 无输出。

Run: `flutter test test/widgets/home_horizontal_shelf_test.dart test/widgets/home_continue_watching_section_test.dart test/widgets/home_landscape_media_section_test.dart test/widgets/home_catalog_section_test.dart test/screens/media_list_home_composition_test.dart test/home_scroll_physics_test.dart`

Expected: PASS。

```bash
git add lib/screens/home/widgets lib/screens/media_list_screen_widgets.dart test/widgets test/screens/media_list_home_composition_test.dart test/home_scroll_physics_test.dart
git commit -m "fix: use continuous landscape home shelves"
```

## Task 4：长按菜单真实长文案大字适配

**Files:**
- Modify: `lib/widgets/common/app_action_sheet.dart`
- Modify: `test/widgets/app_action_sheet_test.dart`

- [ ] **Step 1: 写最长生产文案失败测试**

在 320×800、`TextScaler.linear(2)` 下使用“从‘继续观看’中移除”，找到文字和所在 `FilledButton` 的 rect，断言文字上下边界都在按钮内部，且无异常。

```dart
final labelRect = tester.getRect(find.text('从“继续观看”中移除'));
final buttonRect = tester.getRect(find.ancestor(
  of: find.text('从“继续观看”中移除'),
  matching: find.byType(FilledButton),
));
expect(buttonRect.contains(labelRect.topLeft), isTrue);
expect(buttonRect.contains(labelRect.bottomRight), isTrue);
expect(tester.takeException(), isNull);
```

- [ ] **Step 2: 运行测试确认红灯**

Run: `flutter test test/widgets/app_action_sheet_test.dart`

Expected: FAIL，固定 50 高按钮无法容纳两行 2 倍字号。

- [ ] **Step 3: 使用真实 TextScaler 增长单列高度**

保持两列普通字号为 50；单列时计算 `max(50.0, media.textScaler.scale(16) * 2.6)`，并把结果传给 `SliverGridDelegateWithFixedCrossAxisCount.mainAxisExtent` 和所有业务按钮。取消按钮使用同一高度，外层 `SingleChildScrollView` 负责短屏滚动。普通/危险颜色规则不变。

```dart
final scaledButtonText = media.textScaler.scale(16);
final buttonHeight = columns == 1
    ? math.max(50.0, scaledButtonText * 2.6)
    : 50.0;
```

- [ ] **Step 4: 运行测试并提交**

Run: `flutter test test/widgets/app_action_sheet_test.dart`

Expected: PASS。

```bash
git add lib/widgets/common/app_action_sheet.dart test/widgets/app_action_sheet_test.dart
git commit -m "fix: fit long action labels at large text scales"
```

## Task 5：整体验证、真机推送与关机

**Files:**
- Modify only scoped files if verification reveals a regression.

- [ ] **Step 1: 格式化与定向验证**

Run:

```bash
dart format lib/screens/home lib/screens/media_list_screen.dart lib/screens/media_list_screen_widgets.dart lib/widgets/common/app_action_sheet.dart test/screens/home test/widgets test/screens/media_list_home_composition_test.dart
flutter test test/screens/home/home_presentation_profile_test.dart test/widgets/home_horizontal_shelf_test.dart test/widgets/home_catalog_section_test.dart test/widgets/home_continue_watching_section_test.dart test/widgets/home_landscape_media_section_test.dart test/widgets/app_action_sheet_test.dart test/screens/media_list_home_composition_test.dart test/home_scroll_physics_test.dart test/ui/main_navigation_metrics_test.dart test/main_navigation_layout_test.dart
flutter analyze
git diff --check
```

Expected: 全部 PASS / `No issues found` / diff check 无输出。

- [ ] **Step 2: 完整测试**

Run: `flutter test`

Expected: 除基线已记录的 `test/controllers/local_download_source_resolver_test.dart` 单项日志计数差异外，不得出现新增失败。若基线失败已自然通过，则完整套件全绿。

- [ ] **Step 3: 构建并安装真机包**

Run:

```powershell
flutter build apk --debug --flavor full
adb -s e92f5c16 install -r -d build\app\outputs\flutter-apk\app-full-debug.apk
adb -s e92f5c16 shell am force-stop com.geqian.flyplayer.fly_player
adb -s e92f5c16 shell monkey -p com.geqian.flyplayer.fly_player -c android.intent.category.LAUNCHER 1
```

Expected: APK build success、安装 success、应用启动。不要计算或核对 APK SHA-256。

- [ ] **Step 4: 日志复查**

启动后等待不超过 15 秒，获取当前进程 PID，只筛查 `RenderFlex|overflowed|FLUTTER_ERROR|ZONE_ERROR`。如有新错误，按 systematic-debugging 先复现和定位，再补回归测试修复。

- [ ] **Step 5: 最终提交与关机**

确认 `git status --short` 为空，记录最终 HEAD 和验证结果。向用户发送完成摘要后执行 Windows 定时关机：

```powershell
shutdown.exe /s /t 120 /c "Fly Player 首页修正与真机验证已完成"
```

Expected: 系统接受 120 秒关机计划，给最终消息留出发送时间。
