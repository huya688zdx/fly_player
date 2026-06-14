# 原生播放器平板分屏播放 + 全屏/分屏切换按钮 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让原生壳 `NativePlayerActivity` 在平板上支持 ActivityEmbedding 分屏（播放栏 + 可导航 Flutter 浏览栏，可在副栏换片），并在进度条右侧加一个按钮——支持分屏的设备切全屏/分屏，不支持的设备切横竖屏。

**Architecture:** 复用现有 AndroidX ActivityEmbedding（`ActivityEmbeddingInstaller` + `SplitController` + `ParallelWindowCoordinator`）。把原生壳从"独立任务栈强制全屏"松绑为"可被嵌入、按需分屏"。副栏复用 Flutter `DetailActivity`；换片走现有 `native_player` `launch` 通道，分屏态改投同栈 `onNewIntent` 原地换源。反向桥（解析/进度回写）不变。

**Tech Stack:** Kotlin（Android Activity / Jetpack WindowManager embedding）、Android vector drawable、Flutter MethodChannel（仅条件路由，少量改动）。

**验证约定：** 本仓库 Android 侧无单测基础设施，每个任务的验证 = ①`gradlew compileFullDebugKotlin` 编译通过（PowerShell，关沙箱执行）②对应的手动验收步骤。编译命令统一为：
```
.\android\gradlew.bat -p android compileFullDebugKotlin
```
（若 `full` 变体名不符，先 `.\android\gradlew.bat -p android tasks --all | Select-String compile.*Kotlin` 确认实际变体名。）

**关键现状锚点（实现时核对，勿凭记忆）：**
- `AndroidManifest.xml` 中 `.NativePlayerActivity` 块（约 133–143 行）。
- `NativePlayerActivity.onCreate`（约 143 行）、`buildBottomBar()` 的 `progressRow` 在 `durationLabel` 之后 `bar.addView(progressRow)`（约 1431–1434 行）、`isTablet()`（约 1239 行）、`enableImmersiveMode()`（约 240 行）、`makeIconButton()`（约 1203 行）。
- `ActivityEmbeddingInstaller.install()`（整文件）。
- `ParallelWindowCoordinator`（prefs 常量在顶部，约 11–17 行；`restoreFromPreferences` 约 193 行；`persistSettings` 约 272 行）。
- `FlutterHostActivity.registerNativePlayerChannel` 的 `"launch"` 分支（约 239–258 行）。
- `DetailActivity.createIntent(context, itemGuid)` / `createRouteIntent`（约 141–163 行）。

---

## Task 1: Manifest 松绑 + 运行时恢复横屏锁

把原生壳改成"可被嵌入"，同时用运行时朝向保持现有"全屏横屏"行为不回归。

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`（`.NativePlayerActivity` 块）
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativePlayerActivity.kt`（`onCreate`）

- [ ] **Step 1: 改 Manifest 的 NativePlayerActivity 属性**

把原 `.NativePlayerActivity` 块：
```xml
<activity
    android:name=".NativePlayerActivity"
    android:exported="true"
    android:launchMode="singleTask"
    android:taskAffinity="com.geqian.flyplayer.fly_player.nativeplayer"
    android:theme="@style/PlayerLaunchTheme"
    android:supportsPictureInPicture="true"
    android:resizeableActivity="false"
    android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
    android:hardwareAccelerated="true"
    android:screenOrientation="sensorLandscape" />
```
改为：
```xml
<activity
    android:name=".NativePlayerActivity"
    android:exported="true"
    android:launchMode="singleTop"
    android:taskAffinity="com.geqian.flyplayer.fly_player"
    android:theme="@style/PlayerLaunchTheme"
    android:supportsPictureInPicture="true"
    android:resizeableActivity="true"
    android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
    android:hardwareAccelerated="true" />
```
要点：`launchMode singleTask→singleTop`、`taskAffinity` 改为默认 app 栈、`resizeableActivity false→true`、删除 `screenOrientation`。

- [ ] **Step 2: 在 onCreate 里运行时恢复"全屏锁横屏"**

在 `NativePlayerActivity.onCreate` 内 `window.addFlags(...KEEP_SCREEN_ON)` 之后，加一行运行时朝向（保留删掉 manifest 属性前的行为）：
```kotlin
// Manifest 已去掉 screenOrientation（为分屏 resize 让路），全屏态用运行时锁横屏维持原观感。
applyFullscreenOrientation()
```
并在类内新增（放到 `isTablet()` 附近）：
```kotlin
/** 全屏态朝向：平板锁横屏（对齐原 sensorLandscape）；手机不强制，留给切换按钮控制。 */
private fun applyFullscreenOrientation() {
    requestedOrientation =
        if (isTablet()) android.content.pm.ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        else android.content.pm.ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
}
```

- [ ] **Step 3: 编译**

Run: `.\android\gradlew.bat -p android compileFullDebugKotlin`
Expected: BUILD SUCCESSFUL。

- [ ] **Step 4: 手动验收（回归现状）**

平板上从详情页正常进原生壳播放：仍全屏、横屏；选集/续播/手机端 PIP 行为不变（此步仅确认松绑没破坏既有全屏路径，分屏尚未接）。

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/AndroidManifest.xml android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativePlayerActivity.kt
git commit -m "feat(player): 原生壳 Manifest 松绑为可嵌入，运行时锁横屏保持全屏观感"
```

---

## Task 2: 设备分屏能力门槛 + 横竖屏切换

先把"不支持分屏"分支（横竖屏切换）做完，可独立验证。

**Files:**
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativePlayerActivity.kt`

- [ ] **Step 1: 加 splitSupported() 与 toggleOrientation()**

在 `NativePlayerActivity` 内（`isTablet()` 附近）新增。`splitSupported()` 语义对齐 `FlutterHostActivity.isParallelWindowSupported()`：
```kotlin
/** 设备是否真正支持 ActivityEmbedding 分屏（SDK≥32 且 SplitController 报 SPLIT_AVAILABLE）。 */
private fun splitSupported(): Boolean {
    if (Build.VERSION.SDK_INT < 32) return false
    return runCatching {
        androidx.window.embedding.SplitController.getInstance(this).splitSupportStatus ==
            androidx.window.embedding.SplitController.SplitSupportStatus.SPLIT_AVAILABLE
    }.getOrDefault(false)
}

/** 不支持分屏的设备：按钮退化为横/竖屏切换。 */
private fun toggleOrientation() {
    val current = resources.configuration.orientation
    requestedOrientation =
        if (current == Configuration.ORIENTATION_LANDSCAPE) {
            android.content.pm.ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        } else {
            android.content.pm.ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
        }
    setControlsVisible(true)
}
```
（`Configuration` 已 import；`Build` 已 import。）

- [ ] **Step 2: 编译**

Run: `.\android\gradlew.bat -p android compileFullDebugKotlin`
Expected: BUILD SUCCESSFUL。

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativePlayerActivity.kt
git commit -m "feat(player): 原生壳新增 splitSupported 门槛与横竖屏切换"
```

---

## Task 3: 进度条右侧切换按钮（先接横竖屏分支）

落地按钮 UI，分屏分支先占位（下个任务接）。

**Files:**
- Create: `android/app/src/main/res/drawable/ic_player_split.xml`
- Create: `android/app/src/main/res/drawable/ic_player_fullscreen.xml`
- Create: `android/app/src/main/res/drawable/ic_player_rotate.xml`
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativePlayerActivity.kt`（`buildBottomBar` 的 `progressRow`）

- [ ] **Step 1: 新建三个 vector drawable**

`ic_player_split.xml`（进入分屏 / 竖向分割图标）:
```xml
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp"
    android:viewportWidth="24" android:viewportHeight="24"
    android:tint="#FFFFFFFF">
    <path android:fillColor="#FFFFFFFF"
        android:pathData="M3,5v14h8V5L3,5zM9,17L5,17v-2h4v2zM9,13L5,13v-2h4v2zM9,9L5,9L5,7h4v2zM13,5v14h8L21,5h-8zM19,17h-4v-2h4v2zM19,13h-4v-2h4v2zM19,9h-4L15,7h4v2z" />
</vector>
```
`ic_player_fullscreen.xml`（退回全屏 / fullscreen_exit 图标）:
```xml
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp"
    android:viewportWidth="24" android:viewportHeight="24"
    android:tint="#FFFFFFFF">
    <path android:fillColor="#FFFFFFFF"
        android:pathData="M5,16h3v3h2v-5L5,14v2zM8,8L5,8v2h5L10,5L8,5v3zM14,19h2v-3h3v-2h-5v5zM16,8L16,5h-2v5h5L19,8h-3z" />
</vector>
```
`ic_player_rotate.xml`（screen_rotation 图标）:
```xml
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp"
    android:viewportWidth="24" android:viewportHeight="24"
    android:tint="#FFFFFFFF">
    <path android:fillColor="#FFFFFFFF"
        android:pathData="M16.48,2.52c3.27,1.55 5.61,4.72 5.97,8.48h1.5C23.44,4.84 18.29,0 12,0l-0.66,0.03 3.81,3.81 1.33,-1.32zM10.23,1.75c-0.59,-0.59 -1.54,-0.59 -2.12,0L1.75,8.11c-0.59,0.59 -0.59,1.54 0,2.12l12.02,12.02c0.59,0.59 1.54,0.59 2.12,0l6.36,-6.36c0.59,0.59 0.59,-1.54 0,-2.12L10.23,1.75zM14.83,21L2.83,9l6.36,-6.36 12,12 -6.36,6.36z" />
</vector>
```

- [ ] **Step 2: 在 progressRow 的 durationLabel 之后加按钮**

在 `buildBottomBar()` 内、`progressRow.addView(durationLabel)` 之后、`bar.addView(progressRow)` 之前插入：
```kotlin
// 全屏/分屏（或横竖屏）切换按钮：紧贴时长右侧。
displayModeButton = ImageButton(this).apply {
    background = null
    setColorFilter(Color.WHITE)
    scaleType = ImageView.ScaleType.CENTER_INSIDE
    setPadding(dp(6), dp(6), dp(6), dp(6))
    setOnClickListener { onDisplayModeButtonClick() }
}
progressRow.addView(
    displayModeButton,
    LinearLayout.LayoutParams(dp(40), dp(40)).apply { leftMargin = dp(4) },
)
refreshDisplayModeButton()
```
在类成员区（如 `qualityButton` 声明附近）加字段：
```kotlin
private lateinit var displayModeButton: ImageButton
```
并新增方法：
```kotlin
/** 按设备能力与当前分屏态刷新按钮图标。 */
private fun refreshDisplayModeButton() {
    if (!this::displayModeButton.isInitialized) return
    displayModeButton.setImageResource(
        when {
            !splitSupported() -> R.drawable.ic_player_rotate
            isCurrentlySplit() -> R.drawable.ic_player_fullscreen
            else -> R.drawable.ic_player_split
        },
    )
}

/** 是否处于分屏态。Task 4/7 接入真实判断，先以协调器标志为准。 */
private fun isCurrentlySplit(): Boolean =
    com.geqian.flyplayer.fly_player.ParallelWindowCoordinator.isSplitPlayerVisible()

private fun onDisplayModeButtonClick() {
    if (!splitSupported()) {
        toggleOrientation()
    } else {
        // Task 7 接入：toggleSplitMode()
        showTransientHint("分屏切换即将接入")
    }
    refreshDisplayModeButton()
    scheduleControlsAutoHide()
}
```

- [ ] **Step 3: 编译**

Run: `.\android\gradlew.bat -p android compileFullDebugKotlin`
Expected: BUILD SUCCESSFUL。

- [ ] **Step 4: 手动验收**

- 手机（不支持分屏）：进度条右侧出现旋转图标，点击在横竖屏间切换。
- 平板（支持分屏）：出现"进入分屏"图标，点击弹"分屏切换即将接入"提示（占位）。

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/res/drawable/ic_player_split.xml android/app/src/main/res/drawable/ic_player_fullscreen.xml android/app/src/main/res/drawable/ic_player_rotate.xml android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativePlayerActivity.kt
git commit -m "feat(player): 进度条右侧加显示模式切换按钮（先接横竖屏）"
```

---

## Task 4: ParallelWindowCoordinator 记忆"上次原生分屏态"

**Files:**
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/ParallelWindowCoordinator.kt`

- [ ] **Step 1: 新增持久位常量与字段**

在 prefs key 常量区（约 11–17 行）加：
```kotlin
private const val KEY_LAST_NATIVE_PLAYBACK_SPLIT = "parallel_window_last_native_playback_split"
```
在 `@Volatile` 字段区加：
```kotlin
@Volatile
private var lastNativePlaybackSplit: Boolean = false
```

- [ ] **Step 2: 读写接口 + restore 接入**

新增方法：
```kotlin
fun lastNativePlaybackSplit(): Boolean = lastNativePlaybackSplit

fun setLastNativePlaybackSplit(context: Context, split: Boolean) {
    lastNativePlaybackSplit = split
    context
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .edit()
        .putBoolean(KEY_LAST_NATIVE_PLAYBACK_SPLIT, split)
        .apply()
}
```
在 `restoreFromPreferences` 末尾加：
```kotlin
lastNativePlaybackSplit = prefs.getBoolean(KEY_LAST_NATIVE_PLAYBACK_SPLIT, false)
```

- [ ] **Step 3: 编译**

Run: `.\android\gradlew.bat -p android compileFullDebugKotlin`
Expected: BUILD SUCCESSFUL。

- [ ] **Step 4: Commit**

```bash
git add android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/ParallelWindowCoordinator.kt
git commit -m "feat(player): 协调器记忆上次原生分屏/全屏态"
```

---

## Task 5: ActivityEmbeddingInstaller 新增原生壳分屏规则

把 `NativePlayerActivity`(primary) 与 `DetailActivity`(secondary) 配成分屏对。

**Files:**
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/ActivityEmbeddingInstaller.kt`

- [ ] **Step 1: 构建原生壳分屏规则并加入 setRules**

在 `install()` 内、构建 `splitPairRule` 之后，新增。player 为 primary，占播放主侧（默认右），比例用 `playerPrimaryRatio()`：
```kotlin
val playbackPrimaryOnRight =
    ParallelWindowCoordinator.preferredPlaybackPrimaryPaneSide() == ParallelPaneSide.RIGHT
val playbackLayoutDirection =
    if (playbackPrimaryOnRight) {
        SplitAttributes.LayoutDirection.RIGHT_TO_LEFT
    } else {
        SplitAttributes.LayoutDirection.LOCALE
    }
val nativePlayerSplitAttributes =
    SplitAttributes
        .Builder()
        .setSplitType(SplitAttributes.SplitType.ratio(ParallelWindowCoordinator.playerPrimaryRatio()))
        .setLayoutDirection(playbackLayoutDirection)
        .build()
val nativePlayerSplitRule =
    SplitPairRule
        .Builder(
            setOf(
                SplitPairFilter(
                    ComponentName(context, NativePlayerActivity::class.java),
                    ComponentName(context, DetailActivity::class.java),
                    null,
                ),
            ),
        ).setDefaultSplitAttributes(nativePlayerSplitAttributes)
        .setMinWidthDp(840)
        .setMinSmallestWidthDp(600)
        .setMaxAspectRatioInPortrait(EmbeddingAspectRatio.ratio(1.5f))
        // 关副栏(secondary)不收播放栏 → 回退全屏；退播放栏(primary)一并收副栏。
        .setFinishPrimaryWithSecondary(SplitRule.FinishBehavior.NEVER)
        .setFinishSecondaryWithPrimary(SplitRule.FinishBehavior.ALWAYS)
        .setClearTop(false)
        .build()
```
把它加进 `setRules(setOf(...))`：在原 `splitPairRule, fullscreenPlayerRule, ...` 集合里追加 `nativePlayerSplitRule`。

- [ ] **Step 2: 编译**

Run: `.\android\gradlew.bat -p android compileFullDebugKotlin`
Expected: BUILD SUCCESSFUL。

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/ActivityEmbeddingInstaller.kt
git commit -m "feat(player): 装载原生壳+详情页的 ActivityEmbedding 分屏规则"
```

---

## Task 6: launch 通道条件化 task flag（分屏同栈 + 副栏换片）

让 `native_player` `launch` 在分屏态投同栈 `onNewIntent`（既用于副栏换片，也用于分屏内重启）；全屏态维持原 `NEW_TASK`。

**Files:**
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/FlutterHostActivity.kt`（`registerNativePlayerChannel` 的 `"launch"` 分支）

- [ ] **Step 1: 改 launch 分支的 Intent flag**

把 `"launch"` 分支里构建 intent 的 flag 部分：
```kotlin
val intent =
    Intent(this, NativePlayerActivity::class.java).apply {
        // 独立全屏 task：脱离平板分屏区，强制全屏（配合
        // Manifest 的独立 taskAffinity + singleTask）。
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        putExtra(NativePlayerActivity.EXTRA_LOAD_ARGS, loadArgs)
        ...
    }
```
改为按分屏态选 flag：
```kotlin
val intent =
    Intent(this, NativePlayerActivity::class.java).apply {
        if (ParallelWindowCoordinator.isSplitPlayerVisible()) {
            // 分屏态：同栈复用前台原生壳 → onNewIntent 原地换片（副栏选片即走此路）。
            addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        } else {
            // 全屏态：独立 task 强制全屏（维持原行为）。
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        putExtra(NativePlayerActivity.EXTRA_LOAD_ARGS, loadArgs)
        call.argument<String>("danmakuFile")
            ?.takeIf { it.isNotBlank() }
            ?.let {
                putExtra(NativePlayerActivity.EXTRA_DANMAKU_FILE, it)
            }
    }
```
（`ParallelWindowCoordinator` 同包，无需 import。）

- [ ] **Step 2: 编译**

Run: `.\android\gradlew.bat -p android compileFullDebugKotlin`
Expected: BUILD SUCCESSFUL。

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/FlutterHostActivity.kt
git commit -m "feat(player): 分屏态下 launch 走同栈 onNewIntent 原地换片"
```

---

## Task 7: toggleSplitMode() 接入按钮（全屏 ⇄ 分屏）

**Files:**
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativePlayerActivity.kt`

- [ ] **Step 1: 实现 enterSplitMode / exitSplitMode / toggleSplitMode**

在 `NativePlayerActivity` 内新增（`toggleOrientation()` 附近）。副栏用当前剧集 itemGuid 拉起 `DetailActivity`：
```kotlin
private fun toggleSplitMode() {
    if (!splitSupported()) {
        toggleOrientation()
        return
    }
    if (isCurrentlySplit()) exitSplitMode() else enterSplitMode()
}

/** 全屏 → 分屏：装规则 + 解锁朝向 + 拉副栏详情 + 记忆。 */
private fun enterSplitMode() {
    ParallelWindowCoordinator.setSplitPlayerVisible(true)
    ActivityEmbeddingInstaller.install(this, force = true)
    requestedOrientation = android.content.pm.ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
    val itemGuid = loadArgsMap["itemGuid"]?.toString().orEmpty()
    val detailIntent =
        if (itemGuid.isNotEmpty()) {
            DetailActivity.createIntent(this, itemGuid)
        } else {
            // 无 itemGuid（如本地视频）回退浏览首页路由。
            DetailActivity.createRouteIntent(this, "/")
        }.apply {
            addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
    runCatching { startActivity(detailIntent) }
        .onFailure {
            ParallelWindowCoordinator.setSplitPlayerVisible(false)
            showTransientHint("分屏启动失败")
        }
    ParallelWindowCoordinator.setLastNativePlaybackSplit(this, true)
    refreshDisplayModeButton()
}

/** 分屏 → 全屏：收副栏 + 重锁横屏 + 记忆。 */
private fun exitSplitMode() {
    ParallelWindowCoordinator.setSplitPlayerVisible(false)
    ParallelWindowCoordinator.currentBrowseHost()?.let { host ->
        runCatching { host.finish() }
    }
    applyFullscreenOrientation()
    ParallelWindowCoordinator.setLastNativePlaybackSplit(this, false)
    refreshDisplayModeButton()
}
```

- [ ] **Step 2: 按钮点击接 toggleSplitMode**

把 Task 3 中 `onDisplayModeButtonClick()` 里的占位：
```kotlin
    } else {
        // Task 7 接入：toggleSplitMode()
        showTransientHint("分屏切换即将接入")
    }
```
改为：
```kotlin
    } else {
        toggleSplitMode()
    }
```

- [ ] **Step 3: 编译**

Run: `.\android\gradlew.bat -p android compileFullDebugKotlin`
Expected: BUILD SUCCESSFUL。

- [ ] **Step 4: 手动验收**

平板：进原生壳全屏 → 点按钮 → 右侧播放、左侧弹出 Flutter 详情（剧集信息/选集），可在副栏滚动浏览；按钮图标变"退回全屏"。再点 → 副栏关闭、播放栏铺满回横屏。

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativePlayerActivity.kt
git commit -m "feat(player): 按钮接入全屏⇄分屏切换，副栏拉起 Flutter 详情"
```

---

## Task 8: 副栏换片驱动播放器（验证正向通道）

副栏 Flutter 选别的集/视频 → 现有详情页 launcher 调 `native_player` `launch` → 分屏态同栈 `onNewIntent` → `applyLoadArgs` 原地换源。本任务核对该链路在分屏下贯通，必要时补副栏侧入口。

**Files:**
- Verify/Modify: `lib/services/native_player_bridge.dart`、详情页 launcher（调用 `NativePlayerBridge.launch/maybeLaunch` 处）

- [ ] **Step 1: 核对副栏选片是否调用 launch**

确认副栏 `DetailActivity` 内 Flutter 详情页点选集/相关视频时，走的是 `NativePlayerBridge.maybeLaunch(...)`（或 `launch`）。若是 → 分屏态会被 Task 6 路由为同栈 `onNewIntent`，无需 Dart 改动。若副栏走的是另一条"push Flutter 播放器"路径 → 需让它在 `isSplitPlayerVisible` 时改调 `NativePlayerBridge.launch`。用：
```
grep -rn "NativePlayerBridge" lib/
```
定位所有播放入口，逐一确认分屏态下都收敛到 `launch`。

- [ ] **Step 2: 手动验收**

分屏态下，在副栏点另一集 → 右侧播放器原地换片（标题/进度刷新、mpv 不重建、不闪退）、弹幕随之刷新；副栏停留可继续浏览。

- [ ] **Step 3: Commit（若有 Dart 改动）**

```bash
git add lib/
git commit -m "feat(player): 分屏副栏选片收敛到原生壳同栈换片"
```
（若 Step 1 确认无需改动，跳过提交，在执行记录里注明。）

---

## Task 9: 默认进入态（跟随设置 / 记住上次）

**Files:**
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativePlayerActivity.kt`（`onCreate`）

- [ ] **Step 1: onCreate 末尾按偏好自动进分屏**

在 `onCreate` 的 `scheduleControlsAutoHide()` 之后追加：
```kotlin
maybeAutoEnterSplit()
```
新增方法：
```kotlin
/** 进入播放时按"跟随设置/记住上次"决定是否自动进分屏。仅平板/支持分屏时生效。 */
private fun maybeAutoEnterSplit() {
    if (!splitSupported()) return
    if (ParallelWindowCoordinator.isSplitPlayerVisible()) return
    val wantSplit =
        ParallelWindowCoordinator.lastNativePlaybackSplit() ||
            !ParallelWindowCoordinator.defaultPlaybackFullscreen()
    if (wantSplit) {
        // 等首帧/布局稳定后再进分屏，避免 onCreate 期 startActivity 与 surface 初始化交叠。
        rootContainer.post { enterSplitMode() }
    }
}
```

- [ ] **Step 2: 编译**

Run: `.\android\gradlew.bat -p android compileFullDebugKotlin`
Expected: BUILD SUCCESSFUL。

- [ ] **Step 3: 手动验收**

上次以分屏退出后，下次进原生壳自动进分屏；上次全屏退出则全屏进入。`defaultPlaybackFullscreen=false` 时默认分屏。

- [ ] **Step 4: Commit**

```bash
git add android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativePlayerActivity.kt
git commit -m "feat(player): 原生壳按设置/上次态自动进分屏"
```

---

## Task 10: 分屏 resize 自适应 + 返回键 + inset

收尾边界：窗口宽度变化时刷新按钮/沉浸式，返回键在分屏下只收副栏。

**Files:**
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativePlayerActivity.kt`

- [ ] **Step 1: onConfigurationChanged 刷新**

新增（或在已有 `onConfigurationChanged` 内追加）：
```kotlin
override fun onConfigurationChanged(newConfig: Configuration) {
    super.onConfigurationChanged(newConfig)
    refreshDisplayModeButton()
    enableImmersiveMode()
}
```
（若类中已有该重写，仅把 `refreshDisplayModeButton()` 加进去，勿重复声明。）

- [ ] **Step 2: 返回键在分屏下先收副栏回全屏**

新增：
```kotlin
override fun onBackPressed() {
    if (splitSupported() && isCurrentlySplit()) {
        exitSplitMode()
        return
    }
    super.onBackPressed()
}
```

- [ ] **Step 3: 编译**

Run: `.\android\gradlew.bat -p android compileFullDebugKotlin`
Expected: BUILD SUCCESSFUL。

- [ ] **Step 4: 手动验收**

- 分屏下系统返回键：先收副栏回全屏，再按才退出播放。
- 分屏 ⇄ 全屏切换、设备旋转：按钮图标即时刷新，画面无明显黑屏/错位，沉浸式系统栏保持隐藏。

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativePlayerActivity.kt
git commit -m "feat(player): 分屏 resize 刷新与返回键先收副栏"
```

---

## 自查：spec 覆盖

- §3 设备门槛 → Task 2（`splitSupported`）。
- §4 切换按钮 → Task 3（UI）+ Task 7（分屏分支）+ Task 2（横竖屏分支）。
- §5 Manifest 松绑 → Task 1。
- §6 分屏规则 → Task 5。
- §7 副栏内容 + 正向换片通道 → Task 7（拉副栏）+ Task 6（同栈路由）+ Task 8（链路核对）。
- §8 切换流程 + 默认进入态 → Task 7 + Task 9 + Task 4（持久位）。
- §9 错误/边界（resize/返回键/inset/singleTop 连带） → Task 10 + 各任务手动验收。
- §10 验证 → 各任务编译 + 手动验收。

执行期注意（非新任务，落实现细节时核对）：mpv vo 不在 surface 交叠时重建（换片走 `applyLoadArgs` 原地，已满足）；`singleTask→singleTop` 对 PIP（仅手机、分屏不触发）与选集 `onNewIntent` 复用的回归在 Task 1/7 手动验收覆盖。
