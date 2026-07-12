# 平板多窗口分屏修正计划（原生播放器 displayModeButton）

> 执行对象：Opus 4.8。本文档自包含，按顺序执行即可；行号以写作时为准，可能有轻微漂移，以代码锚点（函数名/注释）为准。

## 一、用户报告的两个症状

1. **平板横屏全屏播放**：进度条右侧按钮是"分屏"，点击后**整个画面变成集详情页**（不是左右并排），播放器被盖住。
2. **平板任务台（小米小窗/自由窗口）播放**：按钮仍是"分屏"，点击后**出现两个独立可控的 App 窗口**（"双开"观感），一个是主应用首页，一个是播放器窗口被详情页盖满后退化成的完整浏览界面。

## 二、根因分析（已排查确认）

分屏入口链路：

- `NativePlayerActivity.splitSupported()`（约 :1802）决定按钮语义：**只检查** `SDK≥32 + resources.configuration.smallestScreenWidthDp≥600 + SplitController 报 SPLIT_AVAILABLE`。
- `enterSplitMode()`（约 :1910）直接 `startActivity(DetailActivity.createSplitIntent(...))`，**完全信任** ActivityEmbedding 的 `SplitPairRule` 会并排嵌入，**事后不校验是否真的嵌入**。
- 而 AE 真正并排的条件在 `ActivityEmbeddingInstaller.kt`：`MIN_WIDTH_DP=840`、`MIN_SMALLEST_WIDTH_DP=600`（针对**真实窗口容器**）。该文件 22–25 行注释明确要求 `splitSupported()` 与这组阈值**两处同源**——现状已漂移：`splitSupported()` 没查 840dp 宽度、没查真实窗口尺寸、没查多窗口状态。

两个症状的成因：

- **症状 1**：点击后 AE 没有形成并排（窗口条件不满足或 OEM 行为差异），`DetailActivity` 以普通 Activity 方式压满整屏 → "画面进入集详情页"。无任何回滚兜底。
- **症状 2**：原生播放器是**独立 task**（`FlutterHostActivity` launch 分支加 `FLAG_ACTIVITY_NEW_TASK`，Manifest `taskAffinity=".nativeplayer"`），任务台下天然是第二个自由窗口。小米小窗的 `resources.configuration` 仍按整屏上报（sw≥600 照样通过）→ 按钮仍显示分屏；点击后小窗真实宽度远不足 840dp，AE 拒绝并排 → 副栏 `DetailActivity` 盖满播放器所在小窗；副栏跑的是**独立第二 Flutter 引擎**、可自行导航回首页 → 两个"完整 App 窗口"。

## 三、修复方案（三层）

### 修-1：`splitSupported()` 与 AE 阈值同源化 + 多窗口态判定

把入口判定逻辑抽成**可 JVM 单测的纯函数**（新文件，如 `NativeSplitGate.kt`）：

```kotlin
/** 分屏入口纯判定：与 ActivityEmbeddingInstaller 的阈值同源。全部入参由 Activity 侧采集。 */
object NativeSplitGate {
    fun splitEntryAllowed(
        sdkInt: Int,
        alreadyEmbedded: Boolean,     // isActivityEmbedded(this)
        inMultiWindow: Boolean,       // isInMultiWindowMode（系统分屏/任务台小窗）
        windowWidthDp: Float,         // 真实窗口宽（WindowMetricsCalculator，勿用 configuration）
        windowHeightDp: Float,
        windowIsFullDisplay: Boolean, // currentWindowMetrics.bounds == maximumWindowMetrics.bounds
        splitAvailable: Boolean,      // SplitController.splitSupportStatus == SPLIT_AVAILABLE
    ): Boolean {
        if (sdkInt < 32) return false
        // ⚠️ 关键陷阱：已并排时本 pane 宽度必然低于入口阈值，且 AE 嵌入态下
        // isInMultiWindowMode 也会返回 true——绝不能用入口阈值否决已成立的分屏，
        // 否则按钮会在分屏中变成"旋转"、点击无法退出分屏。已嵌入=事实支持，直接放行。
        if (alreadyEmbedded) return true
        // 任务台小窗/系统分屏里发起 AE 分屏不可靠（症状2 的"双开"来源），一律禁止，按钮退化为横竖屏切换。
        if (inMultiWindow) return false
        if (!windowIsFullDisplay) return false // 兜住 OEM 不上报 multi-window 的自由窗口
        if (windowWidthDp < ActivityEmbeddingInstaller.MIN_WIDTH_DP) return false
        if (minOf(windowWidthDp, windowHeightDp) < ActivityEmbeddingInstaller.MIN_SMALLEST_WIDTH_DP) return false
        return splitAvailable
    }
}
```

`NativePlayerActivity.splitSupported()` 改为采集入参后调用该函数：

```kotlin
private fun splitSupported(): Boolean {
    val calculator = androidx.window.layout.WindowMetricsCalculator.getOrCreate()
    val current = calculator.computeCurrentWindowMetrics(this).bounds
    val maximum = calculator.computeMaximumWindowMetrics(this).bounds
    val density = resources.displayMetrics.density
    return NativeSplitGate.splitEntryAllowed(
        sdkInt = Build.VERSION.SDK_INT,
        alreadyEmbedded = isCurrentlySplit(),
        inMultiWindow = isInMultiWindowMode,
        windowWidthDp = current.width() / density,
        windowHeightDp = current.height() / density,
        windowIsFullDisplay = current.width() >= maximum.width() && current.height() >= maximum.height(),
        splitAvailable = runCatching {
            androidx.window.embedding.SplitController.getInstance(this).splitSupportStatus ==
                androidx.window.embedding.SplitController.SplitSupportStatus.SPLIT_AVAILABLE
        }.getOrDefault(false),
    )
}
```

注意：

- `androidx.window:window:1.5.0` 已在 `android/app/build.gradle.kts` 依赖中，`WindowMetricsCalculator` 无需新增依赖。
- 原 `isTablet()` 保留（PIP 按钮等处还在用），但 `splitSupported()` 不再依赖它。
- 现有注释"手机上按钮退化为横竖屏切换"的语义扩展为"手机 + 任务台小窗 + 窄窗口都退化为横竖屏切换"，同步更新 `ActivityEmbeddingInstaller.kt:22-25` 与 `splitSupported()` 处的互引注释。
- 在 `onDisplayModeButtonClick()` 里加一行诊断日志（tag 沿用 `NativePlayerSplit`）：输出 `current/maximum bounds、density、isInMultiWindowMode、splitSupportStatus、isActivityEmbedded`，便于用户实机复现症状 1 时抓 logcat 定位（若他的平板真全屏横屏仍进不了并排，说明另有 OEM 回归，靠修-2 兜底 + 此日志诊断）。

### 修-2：进分屏后校验"是否真的并排"，失败自动回滚（终极兜底）

`enterSplitMode()` 成功 `startActivity` 后，安排**两次延迟校验**（600ms、1600ms，字段持有 Runnable 以便取消）：

```kotlin
private var splitVerifyRunnable: Runnable? = null

private fun scheduleSplitEntryVerification() {
    cancelSplitEntryVerification()
    val secondCheck = Runnable { verifySplitEntry(final = true) }
    val firstCheck = Runnable {
        if (!verifySplitEntry(final = false)) {
            splitVerifyRunnable = secondCheck
            playerSurface.postDelayed(secondCheck, 1000L)
        }
    }
    splitVerifyRunnable = firstCheck
    playerSurface.postDelayed(firstCheck, 600L)
}

/** @return true=已确认并排（或无需再管）。final=true 时未并排则执行回滚。 */
private fun verifySplitEntry(final: Boolean): Boolean {
    splitVerifyRunnable = null
    if (isFinishing || inPipMode) return true
    if (!ParallelWindowCoordinator.isNativeSplitPlayerVisible()) return true // 用户已手动退出
    val embedded = runCatching {
        androidx.window.embedding.ActivityEmbeddingController.getInstance(this)
            .isActivityEmbedded(this)
    }.getOrDefault(false)
    if (embedded) return true
    if (!final) return false
    // 回滚：AE 没并排，副栏正盖在播放器上（或盖满小窗）——收掉并恢复全屏。
    Log.w("NativePlayerSplit", "split entry NOT embedded after grace period, rolling back")
    ParallelWindowCoordinator.currentSplitDetailHost()?.let { runCatching { it.finish() } }
    ParallelWindowCoordinator.setNativeSplitPlayerVisible(false)
    ParallelWindowCoordinator.setLastNativePlaybackSplit(this, false)
    applyFullscreenOrientation()
    syncOcclusionWithSplitState()
    refreshDisplayModeButton()
    showTransientHint(getString(R.string.player_split_unavailable_window))
    return true
}

private fun cancelSplitEntryVerification() {
    splitVerifyRunnable?.let { playerSurface.removeCallbacks(it) }
    splitVerifyRunnable = null
}
```

接线点：

- `enterSplitMode()`：`startActivity` 的 `runCatching` 成功分支后调用 `scheduleSplitEntryVerification()`。
- `exitSplitMode()`、`collapseSplitForPip()`、`onDestroy()`：先调 `cancelSplitEntryVerification()`，避免回滚打到已不存在的状态。
- 新增字符串资源 `android/app/src/main/res/values/strings.xml`（项目当前仅此一份 locale 文件）：
  `<string name="player_split_unavailable_window">当前窗口不支持分屏，已恢复全屏</string>`
  ——遵循项目 i18n 规则：原生 UI 文案一律外置 strings.xml，禁止硬编码。

### 修-3：窗口模式变化时收口 + 刷新按钮

场景：已并排分屏中，用户把整个窗口拖进任务台/系统分屏，窗口收窄后 AE 会解除并排、把副栏**叠盖**在播放器上——等价于症状 2。处理：

1. `NativePlayerActivity` 增加 override：

```kotlin
override fun onMultiWindowModeChanged(isInMultiWindowMode: Boolean, newConfig: Configuration) {
    super.onMultiWindowModeChanged(isInMultiWindowMode, newConfig)
    refreshDisplayModeButton()
    if (isInMultiWindowMode) collapseStrandedSplitDetail()
}
```

2. 新增 `collapseStrandedSplitDetail()`：检测"副栏还在但已不处于嵌入态"的搁浅状态并收掉：

```kotlin
/** 副栏 Activity 仍存活但 AE 已不再并排（窗口收窄/模式切换）→ 收副栏、恢复全屏播放。 */
private fun collapseStrandedSplitDetail() {
    if (inPipMode) return
    if (splitVerifyRunnable != null) return // 进分屏校验期内，交给修-2 处理，避免误杀成形中的分屏
    val host = ParallelWindowCoordinator.currentSplitDetailHost() ?: return
    val embedded = runCatching {
        androidx.window.embedding.ActivityEmbeddingController.getInstance(this)
            .isActivityEmbedded(this)
    }.getOrDefault(false)
    if (embedded) return
    Log.w("NativePlayerSplit", "stranded split detail (not embedded) -> collapse")
    runCatching { host.finish() }
    ParallelWindowCoordinator.setNativeSplitPlayerVisible(false)
    ParallelWindowCoordinator.setLastNativePlaybackSplit(this, false)
    syncOcclusionWithSplitState()
    refreshDisplayModeButton()
}
```

3. 现有 `onConfigurationChanged()`（约 :2493，已有 `syncSplitFlagFromWindow()+refreshDisplayModeButton()`）里，在 `syncSplitFlagFromWindow()` **之前**调用 `collapseStrandedSplitDetail()`——sync 只校准标志位、不会收掉盖在上面的副栏，必须先收口再校准。

## 四、明确不做 / 别碰

- **不改** `ActivityEmbeddingInstaller` 的 SplitPairRule 阈值（840/600 保持不变），只做同源引用。
- **不碰** `PlayerActivity`/`MainActivity` 浏览侧分屏那套状态机（`splitPlayerVisible`、`canOpenEmbeddedDetail`、右栏 host 机器）——本次只修原生壳（`nativeSplitPlayerVisible` 这条线）。见 `ParallelWindowCoordinator.kt:66-69` 注释：两套状态互不复用。
- **不动**原生播放器独立 task 的启动方式（`FLAG_ACTIVITY_NEW_TASK` + 独立 affinity 是全屏行为的既有设计）。
- **不加**任何硬编码中文到 Kotlin 代码，新文案进 strings.xml。
- `maybeAutoEnterSplit()`（约 :2274）已调用 `splitSupported()`，修-1 生效后自动被新判定约束，无需单独改；但确认"默认分屏进入"路径也要接 `scheduleSplitEntryVerification()`——即把校验调度放在 `enterSplitMode()` 内部而非按钮点击处。

## 五、单元测试（JVM）

新增 `android/app/src/test/kotlin/.../NativeSplitGateTest.kt`（参考现有 `NativePlayerActivityPanelModelsTest.kt` 的风格），覆盖：

| 用例 | 期望 |
|---|---|
| sdk 31 | false |
| 已嵌入（alreadyEmbedded=true），即使 inMultiWindow=true、宽度不足 | **true**（分屏中不得自我否决） |
| inMultiWindow=true（任务台/系统分屏） | false |
| windowIsFullDisplay=false（自由窗口未上报 multi-window） | false |
| 全屏横屏 1440x900dp、splitAvailable | true |
| 全屏 800x1280dp（宽 <840） | false |
| 1000x560dp（最小边 <600） | false |
| 条件全满足但 splitAvailable=false | false |

运行：`cd android && ./gradlew :app:testDebugUnitTest --tests "*NativeSplitGateTest*"`。

## 六、实机验证清单（交付前必过）

平板（HyperOS）：

1. 全屏横屏播放 → 按钮为"分屏"图标 → 点击 → **左右并排**出现（播放不中断）；再点 → 恢复全屏。若并排失败：≤2 秒内自动回到全屏播放 + toast"当前窗口不支持分屏"，**绝不出现详情页盖满**。抓 `NativePlayerSplit` 日志回传诊断行。
2. 任务台小窗播放 → 按钮为**旋转**图标（不再是分屏）→ 点击只做横竖屏切换，**不出现第二个窗口**。
3. 全屏并排分屏中 → 把窗口拖进任务台/缩小 → 副栏自动收掉、恢复纯播放器窗口，按钮变旋转。
4. 分屏中按钮图标必须是"全屏"（退出分屏）语义，点击能正常退出——回归"分屏中自我否决"陷阱。
5. 分屏 → 进 PIP → 回来：`collapseSplitForPip` 原有行为不回归。

手机：按钮仍为旋转、行为不变（回归验证 62d6b38 的手机修复）。

## 七、涉及文件汇总

| 文件 | 改动 |
|---|---|
| `android/.../NativePlayerActivity.kt` | `splitSupported()` 重写、`enterSplitMode()` 接校验、新增 verify/rollback/collapse 函数、`onMultiWindowModeChanged` override、`onConfigurationChanged` 插一行、诊断日志 |
| `android/.../NativeSplitGate.kt`（新增） | 纯判定函数 |
| `android/.../ActivityEmbeddingInstaller.kt` | 仅更新 22–25 行注释（同源说明指向 NativeSplitGate） |
| `android/app/src/main/res/values/strings.xml` | 新增 `player_split_unavailable_window` |
| `android/app/src/test/kotlin/.../NativeSplitGateTest.kt`（新增） | JVM 单测 |
