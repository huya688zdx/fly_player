# 海报浏览横屏手势面板实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为横屏海报轨增加下滑收起、上滑展开、单步左右切换和匹配的跟手/结算动画。

**Architecture:** 新建一个只管理界面手势与动画的 `PosterBrowseLandscapeGesturePanel`，内部复用现有海报轨并通过 `onSelectItem` 上报结算索引。`PosterBrowseScreen` 继续独占业务焦点和背景状态；大屏布局只把有内容的轨道替换为新面板，空态和加载态保持原样。

**Tech Stack:** Flutter、Dart、`flutter_test`、AnimationController、ScrollController、GestureDetector

---

## 文件结构

- 新建 `lib/screens/poster_browse/poster_browse_landscape_gesture_panel.dart`：纵横拖动识别、收起进度、横向滚动和结算动画。
- 修改 `lib/screens/poster_browse/poster_browse_poster_track.dart`：允许注入滚动控制器和物理规则，默认行为保持兼容。
- 修改 `lib/screens/poster_browse/poster_browse_large_layout.dart`：仅在当前行有海报时接入手势面板。
- 修改 `lib/screens/poster_browse/poster_browse_poster_card.dart`：焦点缩放改用短时缓动动画。
- 新建 `test/poster_browse/poster_browse_landscape_gesture_panel_test.dart`：覆盖纵向、横向、首尾和点击行为。
- 修改 `test/poster_browse/poster_browse_large_layout_test.dart`：确认真机尺寸仍无溢出且已接入面板。

### Task 1：建立纵向收起与展开测试

**Files:**
- Create: `test/poster_browse/poster_browse_landscape_gesture_panel_test.dart`
- Create: `lib/screens/poster_browse/poster_browse_landscape_gesture_panel.dart`

- [ ] **Step 1：写默认展开、下滑收起和上滑展开测试**

测试使用三张真实 `PosterBrowseDisplayItem`，断言初始轨道透明度为 `1`；在 `poster_browse_landscape_gesture_panel` 上向下拖动 `180px` 并 `pumpAndSettle()` 后，轨道透明度为 `0` 且 `poster_browse_landscape_expand_handle` 可见；再向上拖动 `180px` 后恢复透明度 `1`。

- [ ] **Step 2：运行测试并确认 RED**

```powershell
flutter test test/poster_browse/poster_browse_landscape_gesture_panel_test.dart
```

预期：因 `PosterBrowseLandscapeGesturePanel` 尚不存在而编译失败。

- [ ] **Step 3：实现最小纵向手势面板**

组件使用 `AnimationController(duration: 280ms)`，`value=0` 表示展开、`value=1` 表示收起。纵向更新采用：

```dart
_collapseController.value = (_collapseController.value + delta / 160)
    .clamp(0.0, 1.0);
```

松手时速度绝对值超过 `500px/s` 按速度方向结算，否则以 `0.45` 为阈值；轨道使用 `Transform.translate`、`Opacity` 和 `ClipRect` 向下淡出，把手反向淡入。外层始终保留 `264px` 槽位，避免分类栏跳动。

- [ ] **Step 4：运行测试并确认 GREEN**

```powershell
flutter test test/poster_browse/poster_browse_landscape_gesture_panel_test.dart
```

预期：纵向用例通过，无未释放控制器或待处理动画。

### Task 2：建立横向单步切换测试

**Files:**
- Modify: `test/poster_browse/poster_browse_landscape_gesture_panel_test.dart`
- Modify: `lib/screens/poster_browse/poster_browse_landscape_gesture_panel.dart`
- Modify: `lib/screens/poster_browse/poster_browse_poster_track.dart`

- [ ] **Step 1：写左右切换、短拖回弹和首尾限制测试**

从索引 `1` 左滑 `100px` 只上报 `2`，右滑只上报 `0`；拖动 `25px` 不上报；索引 `0` 右滑和最后一项左滑均不上报越界索引。测试宿主在回调后同步更新 `focusedIndex`。

- [ ] **Step 2：运行新增用例并确认 RED**

预期：纵向最小实现尚未提供横向单步结算，新增断言失败。

- [ ] **Step 3：实现横向跟手和单步结算**

给 `PosterBrowsePosterTrack` 增加可选 `ScrollController? controller` 和 `ScrollPhysics? physics`。面板注入控制器与 `NeverScrollableScrollPhysics`，在水平拖动时按手指位移更新滚动偏移；松手时使用 `64px` 距离或 `420px/s` 速度阈值确定 `focusedIndex ± 1`，并把目标限制在 `0..items.length-1`。目标滚动位置按固定项跨度 `116 + 18 = 134px` 计算，使用 `240ms easeOutCubic` 对齐后调用 `onSelectItem`。

- [ ] **Step 4：同步外部焦点**

在 `didUpdateWidget` 中检测焦点或列表变化，通过下一帧回调把滚动控制器移动到新的安全索引；使用递增结算编号忽略已经过期的动画完成回调。

- [ ] **Step 5：运行测试并确认 GREEN**

```powershell
flutter test test/poster_browse/poster_browse_landscape_gesture_panel_test.dart
```

预期：所有纵横手势用例通过。

### Task 3：接入大屏布局并保留点击/空态行为

**Files:**
- Modify: `lib/screens/poster_browse/poster_browse_large_layout.dart`
- Modify: `lib/screens/poster_browse/poster_browse_poster_card.dart`
- Modify: `test/poster_browse/poster_browse_large_layout_test.dart`
- Modify: `test/poster_browse/poster_browse_landscape_gesture_panel_test.dart`

- [ ] **Step 1：写大屏接入和点击兼容测试**

真机 `853 × 384` 用例断言存在 `PosterBrowseLandscapeGesturePanel` 且没有异常；面板用例断言点非焦点卡仍上报该索引。现有大屏测试继续验证空库和失败状态不创建海报轨。

- [ ] **Step 2：运行测试并确认 RED**

预期：大屏仍直接创建 `PosterBrowsePosterTrack`，面板类型断言失败。

- [ ] **Step 3：接入面板并增加焦点缓动**

在 `_buildTrackArea` 的非空分支返回 `PosterBrowseLandscapeGesturePanel`，透传现有全部海报参数和 `onSelectItem`。把海报卡的静态 `Transform.scale` 替换为 `AnimatedScale(duration: 180ms, curve: Curves.easeOutCubic)`，不改变尺寸、文本或点击逻辑。

- [ ] **Step 4：运行大屏和面板测试并确认 GREEN**

```powershell
flutter test test/poster_browse/poster_browse_landscape_gesture_panel_test.dart test/poster_browse/poster_browse_large_layout_test.dart
```

预期：全部通过，`853 × 384` 无 `RenderFlex`。

### Task 4：回归、构建和真机验证

**Files:**
- Verify only

- [ ] **Step 1：运行海报浏览相关测试**

```powershell
flutter test test/poster_browse
```

预期：全部通过。

- [ ] **Step 2：运行静态分析和差异检查**

```powershell
flutter analyze
git diff --check
```

预期：无分析问题，无空白错误。

- [ ] **Step 3：构建并覆盖安装真机包**

```powershell
cd android
.\gradlew.bat app:assembleFullDebug
adb -s e92f5c16 install -r ..\build\app\outputs\apk\full\debug\app-full-debug.apk
```

预期：`BUILD SUCCESSFUL`，安装输出 `Success`。

- [ ] **Step 4：真机验证**

在 `853 × 384` 横屏中依次执行下滑收起、上滑展开、左滑下一部和右滑上一部；抓取截图与安装后日志。日志不得出现 `RenderFlex`、`overflowed`、控制器异常或 `FLUTTER_ERROR`。

- [ ] **Step 5：提交实现**

```powershell
git add -- lib/screens/poster_browse/poster_browse_landscape_gesture_panel.dart lib/screens/poster_browse/poster_browse_poster_track.dart lib/screens/poster_browse/poster_browse_large_layout.dart lib/screens/poster_browse/poster_browse_poster_card.dart test/poster_browse/poster_browse_landscape_gesture_panel_test.dart test/poster_browse/poster_browse_large_layout_test.dart
git commit -m "feat(poster-browse): 增加横屏海报手势面板"
```
