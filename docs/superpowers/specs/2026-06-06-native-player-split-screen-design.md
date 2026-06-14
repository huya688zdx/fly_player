# 原生播放器平板分屏播放 + 全屏/分屏切换按钮 — 设计文档

- 日期：2026-06-06
- 范围：Android 原生壳 `NativePlayerActivity` 在平板分屏下"边播边浏览/换片"，并在进度条右侧新增全屏⇄分屏切换按钮；不支持分屏的设备退化为横竖屏切换。
- 技术路线：复用现有 AndroidX **ActivityEmbedding** 分屏机制（方案 A）。

## 1. 背景与现状

正在把播放从 Flutter 播放页迁到纯原生壳 `NativePlayerActivity`（视频 SurfaceView + 弹幕原生 Canvas + 控制原生 View，无 Hybrid Composition）。旧 Flutter 播放器（`PlayerActivity`）在平板上能"一边播放一边浏览信息流、并切换到其它视频"，靠的是 ActivityEmbedding 把播放栏与右侧 Flutter 浏览栏并排。

原生壳目前**只能全屏**，原因是被刻意隔离：

- Manifest：`taskAffinity=".nativeplayer"`（独立任务栈）、`launchMode="singleTask"`、`resizeableActivity="false"`、`screenOrientation="sensorLandscape"`。
- 启动：`FlutterHostActivity.registerNativePlayerChannel` 用 `FLAG_ACTIVITY_NEW_TASK` 拉起，注释明言"独立全屏 task：脱离平板分屏区、强制全屏"。

现有可复用基础设施：

- `ActivityEmbeddingInstaller`：已装 `MainActivity`+`DetailActivity` 的 `SplitPairRule`，以及 `PlayerActivity`/`FullscreenPlayerActivity`/`FullscreenScreenshotActivity` 的 `alwaysExpand` 全屏规则。
- `ParallelWindowCoordinator`：分屏偏好（主/次栏方向、比例预设、`defaultPlaybackFullscreen`、`isSplitPlayerVisible`）与详情定位缓存。
- `FlutterHostActivity.isParallelWindowSupported()` / `canOpenEmbeddedDetail()`：已用 `SplitController.getInstance(this).splitSupportStatus == SPLIT_AVAILABLE`（SDK≥32）判断设备是否真正支持分屏。
- `NativePlayerReverseBridge` + `native_player` MethodChannel：原生壳→Flutter 反向通道（`resolvePlayback` 解析新集、`recordProgress` 回写进度），及 `launch` 正向启动。
- 原生壳 `applyLoadArgs()` / `onNewIntent()`：可在同一 mpv 实例上原地换源，不重建 Activity/surface。

## 2. 目标与非目标

### 目标
1. 进度条行右侧新增一个切换按钮：
   - 设备**支持分屏** → 全屏 ⇄ 分屏切换。
   - 设备**不支持分屏** → 横屏 ⇄ 竖屏切换。
2. 分屏态：原生壳占播放栏，副栏是可导航的 Flutter（当前剧集详情 ⇄ 浏览首页），可在副栏切换到其它集/视频并驱动播放器原地换片。
3. 默认进入播放时的全屏/分屏状态**跟随设置 / 记住上次选择**。

### 非目标
- 不做系统级多窗口（自由窗口/系统分屏）触发——Android 不允许 app 用按钮主动拉起，否决。
- 不在 `NativePlayerActivity` 内部塞 FlutterView（会重新引入 Hybrid Composition，否决）。
- 不改动手机端 PIP（小窗）逻辑。

## 3. 设备能力门槛

抽一个判定 `splitSupported()`，语义对齐现有 `isParallelWindowSupported()`：

```
splitSupported() =
    Build.VERSION.SDK_INT >= 32 &&
    SplitController.getInstance(ctx).splitSupportStatus == SPLIT_AVAILABLE
```

- 用户口径"首先设备要支持安卓的多 Activity"即以此为准（不再叠加 `isParallelWindowEnabled` 总开关作为按钮是否分屏的硬门槛；总开关仅影响默认是否自动进分屏，按钮始终可用）。
- `splitSupported()==true` → 按钮做全屏/分屏切换。
- `splitSupported()==false` → 按钮做横竖屏切换。

## 4. UI：切换按钮

- 位置：`buildBottomBar()` 第一行 `progressRow` 内、`durationLabel` 之后追加一个 `ImageButton`（与现有 `lockButton`/图标按钮风格一致，玻璃底或纯图标）。
- 图标：
  - 分屏可用：全屏态显示"进入分屏"图标，分屏态显示"退出到全屏"图标（两枚 vector drawable，命名如 `ic_player_split_enter` / `ic_player_fullscreen_enter`）。
  - 分屏不可用：显示横/竖屏切换图标（`ic_player_rotate` 或横竖两态）。
- 点击行为：
  - 分屏可用：调用 `toggleSplitMode()`。
  - 分屏不可用：`toggleOrientation()`（在 `SCREEN_ORIENTATION_LANDSCAPE` ⇄ `SCREEN_ORIENTATION_PORTRAIT` 间切，经 `setRequestedOrientation`）。
- 状态刷新：进入分屏/全屏、窗口 resize（`onConfigurationChanged`）后更新图标与可见语义。

## 5. Manifest 松绑（敏感改动）

把"强制全屏隔离"改为"按需分屏、默认行为不变"：

| 属性 | 现状 | 改为 | 原因 |
|---|---|---|---|
| `taskAffinity` | `.nativeplayer` | 默认 app 栈（`com.geqian.flyplayer.fly_player`） | ActivityEmbedding 配对要求同任务栈 |
| `launchMode` | `singleTask` | `singleTop` | singleTask 独占任务栈根、无法做同栈分屏成员；singleTop 仍能投 `onNewIntent` |
| `resizeableActivity` | `false` | `true` | 嵌入/分屏 resize 必需 |
| `screenOrientation` | `sensorLandscape` | 移除（运行时控制） | 固定横屏属性会阻碍分屏 resize；改用 `setRequestedOrientation` |

- 启动 Intent（`FlutterHostActivity`）的 `FLAG_ACTIVITY_NEW_TASK` 改为**条件性**：全屏路径维持原行为；分屏路径走同栈（不加 NEW_TASK，或加 `REORDER_TO_FRONT|SINGLE_TOP`）。
- 运行时朝向：全屏 + 平板 → 锁 `SENSOR_LANDSCAPE`；分屏 → 不锁，交系统 resize；非分屏设备 → 由切换按钮在横竖屏间切。

## 6. 分屏规则（ActivityEmbedding）

在 `ActivityEmbeddingInstaller.install()` 增一条 `SplitPairRule`：

- 配对：`DetailActivity`（主/浏览栏）+ `NativePlayerActivity`（次/播放栏）。
- 比例与方向：复用 `ParallelWindowCoordinator.playerPrimaryRatio()` 与 `preferredPlaybackPrimaryPaneSide`（默认播放在右）。
- `setMinWidthDp` / `setMinSmallestWidthDp`：对齐现有浏览分屏阈值。
- `setFinishPrimaryWithSecondary` / `setFinishSecondaryWithPrimary`：按"关副栏回全屏、退播放栏一并收副栏"的期望设定（实现期验证具体 FinishBehavior 组合）。
- 现有 `fullscreenPlayerRule`(`PlayerActivity`) 等保留。原生壳**不**配 `alwaysExpand`；默认仍全屏靠"是否拉起副栏宿主"控制——未拉副栏时单 Activity 自然铺满。

## 7. 副栏内容与"换片"正向通道

- 副栏宿主：复用 `DetailActivity`（Flutter，可在详情⇄浏览首页导航）。用现有 `DetailActivity.createRouteIntent` + `ParallelFlutterEngineRegistry.prepareDetailRoute` 拉起到当前剧集详情（route/itemGuid 取自原生壳 `loadArgsMap`）。
- **新增正向"换片"通道**（当前缺口）：副栏 Flutter 选了别的集/视频 → 解析好 loadArgs → 复用 `native_player` channel 的 `launch`（分屏态走同栈 `SINGLE_TOP|REORDER_TO_FRONT`，不带 NEW_TASK）→ 投到已在前台的 `NativePlayerActivity.onNewIntent` → `applyLoadArgs` 原地换源（不重建 mpv）。
- 反向通道（`resolvePlayback`/`recordProgress`）保持不变；原生壳自身选集面板继续可用。

## 8. 切换流程

### toggleSplitMode()：全屏 → 分屏
1. 校验 `splitSupported()`。
2. `ParallelWindowCoordinator.setSplitPlayerVisible(true)` 并装/刷新分屏规则。
3. 解除原生壳横屏锁（`setRequestedOrientation(UNSPECIFIED)`）。
4. 拉起副栏 `DetailActivity`（带当前 itemGuid 路由，同栈）。
5. 持久化"上次为分屏"。

### toggleSplitMode()：分屏 → 全屏
1. finish/收起副栏 `DetailActivity`（`setSplitPlayerVisible(false)`）。
2. 原生壳重铺满（平板重锁横屏）。
3. 持久化"上次为全屏"。

### 默认进入态（跟随设置/记住上次）
- 新增持久位 `KEY_LAST_NATIVE_PLAYBACK_SPLIT`（落 `parallel_window_settings` prefs，由 `ParallelWindowCoordinator` 管理）。
- 进入播放时：`splitSupported()` 为真且（`!defaultPlaybackFullscreen()` 或 上次为分屏）→ 自动进分屏；否则全屏。

## 9. 错误与边界

- **SurfaceView resize/分屏切换**：避免 mpv vo 在 surface 交叠时重建；resize 走 `onConfigurationChanged` 重布局，必要时短暂占位避免黑屏闪烁。
- **生命周期联动**：副栏 `DetailActivity` 与原生壳的 finish 关系、返回键（分屏下返回应只收副栏回全屏，而非直接退播放）、`setFinishSecondaryWithPrimary` 行为。
- **沉浸式/inset**：分屏窗口变窄时 controls 自动隐藏与系统栏 inset 自适应（按窗口宽度，而非全屏假设）。
- **singleTask→singleTop 连带**：核对"选集 onNewIntent 复用""返回栈""PIP（手机）"不回归。
- **降级**：`splitSupported()==false` 时按钮只做横竖屏切换；正向换片通道在副栏不存在时安全 no-op。

## 10. 验证

- 编译：`gradlew compileFullDebugKotlin`（PowerShell，关沙箱）先过 Kotlin 编译。
- 平板（支持分屏）：进入播放→点按钮进分屏→副栏浏览/选集→播放器原地换片；再点退回全屏；横屏锁定与 resize 无黑屏。
- 手机（不支持分屏）：按钮做横竖屏切换；无分屏副栏。
- 回归：现有 `MainActivity`+`DetailActivity` 浏览分屏、`PlayerActivity` 全屏规则、原生壳选集/续播/PIP 不受影响。

## 11. 受影响文件（预估）

- `android/app/src/main/AndroidManifest.xml`：`NativePlayerActivity` 属性松绑。
- `ActivityEmbeddingInstaller.kt`：新增原生壳分屏 `SplitPairRule`。
- `ParallelWindowCoordinator.kt`：新增"上次原生分屏态"持久位 + 读写。
- `NativePlayerActivity.kt`：切换按钮、`toggleSplitMode()`/`toggleOrientation()`、`splitSupported()`、运行时朝向、resize 自适应、副栏拉起。
- `FlutterHostActivity.kt`：`native_player` `launch` 的条件性 task flag（全屏 vs 分屏同栈）。
- 可能：副栏 Flutter 选片→正向换片所需的 Dart 侧入口（`native_player_bridge.dart` / 详情页 launcher）。
- 新增 vector drawable：分屏/全屏/横竖屏切换图标。
