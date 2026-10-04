# 悬浮小窗：画中画增强 + B 站式自绘悬浮窗（安卓）与置顶迷你窗（PC）

- 日期：2026-10-04
- 建议分支：`feature/floating-mini-player`
- 状态：方案（安卓阶段 1 可直接实施；安卓阶段 2 为主体；PC 为探索性规划，先规划不实施）
- 关联文档：`docs/plans/hyperos-cloud-fps-lock.md`（HyperOS 前台限帧钳制与本方案的帧率预算强相关）

## 0. 目标形态（对照 B 站）

**安卓**，分两阶段逼近 B 站客户端的悬浮小窗体验：

1. **阶段 1（系统画中画增强，独立可交付）**：维持系统 PiP，把画中画遥控条补齐为
   「上一集 / -15s / 播停 / +15s / 下一集」五键，API 33+ 画中画标题下方显示剧名·集名。
   覆盖 Home 手势离开、其他应用上层展示等所有系统级场景，零权限成本。
2. **阶段 2（主体，B 站式自绘悬浮窗）**：播放器内主动点「小窗」→ 收缩为跨应用置顶悬浮窗
   （`TYPE_APPLICATION_OVERLAY`），可拖动、边缘拖拽自由缩放（无档位）、边缘吸附；视频 + 弹幕在悬浮窗内继续
   播放；点内容区出迷你控制层（播停 / ±15s / 集名 / 展开 / 关闭）；底部「接下来播放」条
   以「下一集」图标进程内换片；点展开调回全屏播放器。系统 PiP 降级为悬浮窗能力缺失（未授权 / 交接失败）
   时的自动回退。

**PC（Windows）**：播放页一键收起为「置顶迷你窗」——主窗口缩为顶部居中的置顶小条
（视频缩略 + 播停 / 上一集 / 下一集 / 展开关闭），拖动用系统拖拽，展开逆序恢复全屏。
技术路径本文第 4 节给候选对比与推荐。

## 1. 现状与已落库改动

### 1.1 安卓：播放已全面原生壳化，悬浮窗基础设施为零

- 播放统一走纯原生壳：`lib/services/native_player_bridge.dart:20-26`
  `preferNativePlayerShell = true`，Flutter 只编排 + 喂参。
- 渲染三件套同在一个原生 `FrameLayout`（`mpv/NativePlayerSurface.kt:23-28`）：
  视频 = `SurfaceViewVideoOutputTarget` 固定硬编码（同文件 38-40，SurfaceFlinger 独立硬件层），
  弹幕 = `NativeDanmakuOverlayView` 普通 View（`mpv/NativeDanmakuOverlayView.kt:225-228`，
  无 Activity 依赖，Choreographer+Canvas+LruCache 文本位图），控制层 = Activity 原生 View。
  `NativePlayerSurface` 同时持有 `MpvPlaybackController` 与 mpv 实例
  （`mpv/NativePlayerSurface.kt:59-73`）——**渲染组迁移的移动单元就是整个 NativePlayerSurface**。
- PiP 是系统画中画：`supportsPictureInPicture`（`AndroidManifest.xml:137-147`）、
  RemoteAction 经 `PendingIntent.getService` 打到 `NativePlaybackMediaService`
  （`NativePlayerActivity.kt:10812-10823`）、`setAutoEnterEnabled`（10859-10875）。
  现有遥控为 3 键：±10s + 播停（10825-10857，`onMediaSeekBy(±SEEK_STEP_MS)`，
  `SEEK_STEP_MS = 10_000L` 见 `NativeMediaCommandCoordinator.kt:33`）。
- 前台服务只承载媒体会话 + 通知 + 命令路由（`NativePlaybackMediaService.kt:50-52`），
  无窗口能力；`stopWithTask=true`（`AndroidManifest.xml:209`）。
- **全仓库无任何悬浮窗基础设施**（两次检索确认）：
  `AndroidManifest.xml:3-18` 无 `SYSTEM_ALERT_WINDOW`；无 `canDrawOverlays` /
  `TYPE_APPLICATION_OVERLAY` / `WindowManager.addView` 代码。权限引导、窗口管理、
  MIUI「后台弹出界面」引导全部从零新增。
- Surface 交接的现成锚点：`VideoOutputController.detachSurfaceForHandoff()`
  （`mpv/output/VideoOutputController.kt:155-164`，"不暂停只解绑"）、
  `rebindSurface` 同 generation+identity 去重（594-631）、
  generation 门拒绝过期回调（106-109，generation 递增在
  `mpv/VideoOutputTarget.kt:387`/`592`）、**进程级单 surface owner**
  `SURFACE_BIND_LOCK + globalSurfaceOwnerId`（`VideoOutputController.kt:746-756`）。

### 1.2 桌面：迷你窗的三个关键积木全部在库

- 播放会话与 UI 解耦：`DesktopPlaybackHost` 静态槽保活 Player/VideoController/路由
  （`lib/desktop/playback/desktop_playback_host.dart:58-65`），退出播放页暂停并保留
  （`desktop_playback_screen.dart:386-400` 一带），`resume()` 复用会话重挂不重建
  （`desktop_playback_host.dart:104-167`）。
- 现成的「主窗口缩为置顶迷你条」完整参考实现：`ExternalPlaybackMiniHost`
  （`lib/desktop/playback/external_playback_mini_controller.dart`），三档尺寸
  360x64/360x196/360x492（31-33），进入流程保存全屏/最大化/置顶/Bounds →
  `setResizable(false)` → `setSize` → `setAlignment(topCenter)+下移 12px` → 置顶
  （56-96），退出逆序恢复并等 `endOfFrame` 再显示保留页面（108-127），主页面用
  `Offstage+ExcludeFocus+TickerMode` 保状态（214-218）；迷你条拖动
  `windowManager.startDragging` + Esc/空格快捷键
  （`external_playback_mini_player.dart:134,150,108-110`）。
- 窗口能力齐备且锁版：`window_manager 0.5.2`（`pubspec.yaml:53`），插件原生层已实现
  setAlwaysOnTop/setMinimumSize/setSkipTaskbar/startDragging/startResizing。
- 限制：极简模式当前仅覆盖外部播放器（PotPlayer 等，`supportsMiniPlayer` 门控）、
  仅 Windows 挂载（`lib/main.dart:439-443`）；内部 media_kit 播放页无任何迷你模式；
  置顶当前走 `PotPlayerBridge::SetMiniPinned` 原生 `HWND_TOPMOST` + WinEventHook
  （`windows/runner/potplayer_bridge.cpp:295-321`）——那是外部进程方案的钩子，内部
  播放器应直接用插件 `setAlwaysOnTop`；分屏副栏明确不承载播放
  （`lib/desktop/desktop_detail_pane_host.dart:165-173` `replacePlayerSource` 直接
  return false）。

### 1.3 先行入库改动（已提交 f0481772 / c387ed32，2026-10-05）

- `NativeSplitGate.displayModeEntry` 底栏入口三态判定（分屏/小窗 PiP/横竖屏兜底，
  `NativeSplitGate.kt:29-44`）+ JVM 测试（`NativeSplitGateTest.kt` 新增 3 用例）。
  **悬浮窗入口在此枚举上扩展**（见 3.6）。
- `HyperosRefreshRateGuard`（新文件，`HyperosRefreshRateGuard.kt`）：PowerKeeper
  前台写 60 的自动恢复守卫，未授权 WRITE_SECURE_SETTINGS 完全休眠（71-73）；
  挂载于 `NativePlayerActivity` onStart/onStop（11006/11024）。

## 2. 安卓阶段 1：系统画中画增强（独立可交付）

改动全部集中在 PiP 现有链路，不动窗口模型，先发布一个可感知的体验提升。

### 2.1 RemoteAction 五键

- 现状：`pipRemoteActions()`（`NativePlayerActivity.kt:10825-10857`）返回
  `[rewind, playPause, forward]`（±10s），直播只给播停（10849）。
- 改动：
  1. `NativeMediaCommandCoordinator` 新增 `ACTION_SEEK_BACK_15S` / `ACTION_SEEK_FWD_15S`
     （复用参数化的 `onMediaSeekBy(deltaMs)`，`NativeMediaCommandCoordinator.kt:21`，
     传 `±15_000`；**不动** `SEEK_STEP_MS=10_000`，通知线控保持 10s 语义）。
  2. 新增 `ACTION_PREVIOUS` + `Handler.onMediaPrevious()`（`ACTION_NEXT` 与
     `onMediaNext` 已存在，`NativeMediaCommandCoordinator.kt:30,62` →
     `NativePlayerActivity.kt:10764`）。上一集判定需新增 `hasPrevEpisode()`（对照
     `hasNextEpisode()`，`NativePlayerActivity.kt:7727`），沿用播放序列状态。
  3. `pipRemoteActions()` 扩为五键 `[prev, -15s, playPause, +15s, next]`，
     PendingIntent 打到 `NativePlaybackMediaService`（`pipCommandIntent` 10812-10823
     原样复用，requestCode 增量）。系统对 PiP action 上限即 5，窄窗下系统自行截取。
     直播仍只给播停；`canNext = hasNextEpisode()` 已随媒体会话下发（10794），
     `canPrev` 同法补齐。
- 播停图标刷新走现有 `updatePipParams()`（10872-10875，播停切换时重打 actions）。

### 2.2 API 33+ `setSubtitle` 显示剧名·集名

- `buildPipParams()`（10859-10869）补：
  `if (SDK_INT >= 33) builder.setSubtitle("剧名 · 第N集")`。数据源用 `loadArgsMap`
  现有 `"title"` 字段（该字段已存在并被集数解析消费，`NativePlayerActivity.kt:9405`
  `extractEpisodeNumber(loadArgsMap["title"])`）；剧名若不在 loadArgs 里，经
  `dispatchInPlaceLoad` 递参链路（1132-1148）补字段，实施时确认。
- 与 `currentPipRatio()`（10801-10810）无冲突：subtitle 是标题栏文案，不动比例。

### 2.3 阶段 1 验收标准

1. PiP 窗五键可用：上一集/下一集走与通知同一条命令总线换片且不重载整页
   （`applyIncomingPlaybackIntent`，`NativePlayerActivity.kt:3138`；同集去重
   `canKeepCurrentPlayback` 3190-3203）；±15s 精确生效。
2. API 33+ 真机 PiP 标题下显示剧名·集名；API 33 以下无回归。
3. 直播频道 PiP 只有播停，不出现换集键。
4. 现有单元测试全绿 + 新增 Coordinator action 路由用例。

## 3. 安卓阶段 2：B 站式自绘悬浮窗（主体）

### 3.1 前提事实与硬约束（决定架构的四条）

1. **mpv 进程级单 surface owner**（`VideoOutputController.kt:746-756`）：同一时刻
   只有一个 mpv surface 拥有者，悬浮窗与 Activity 双视图并存时必须走
   「detach 旧 → attach 新」，不存在双 surface 复制。
2. **Surface 归属窗口**：SurfaceView 的 Surface 随所在窗口创建/销毁
   （`mpv/VideoOutputTarget.kt:587-617` 回调驱动全部生命周期）。把视频 View 留在
   Activity 窗口、仅悬浮窗显示时画面必然断流——**渲染组必须物理迁移进悬浮窗层级**。
3. **释放顺序红线**：视频输出必须比 mpv detach/stop 活得久
   （`mpv/MpvPlayerView.kt:149-155` 注释明示先释放会撞下次播放崩溃；
   `mpv/NativePlayerSurface.kt:333-341` release 顺序 = controller.disposeBlocking 先行）。
4. **PiP 与保留会话互斥耦合**：`buildPipParams` 的 autoEnter = `!playbackParked &&
   pipAutoEnter && !paused`（`NativePlayerActivity.kt:10866`）、`parkPlayback` 在
   `inPipMode` 时拒绝（4419-4422）、park 即 pause+停上报+停媒体服务+moveTaskToBack
   （4423-4438）——**悬浮窗形态不能复用 parkPlayback（它先暂停）**，需要新的
   「缩小但继续播」状态（见 3.4）。

### 3.2 窗口与权限（从零新增的部分）

- 窗口：新 `FloatingPlayerService`（前台服务，`foregroundServiceType=mediaPlayback`，
  先例 `AndroidManifest.xml:204-209`）持有 `WindowManager.addView`，窗口类型
  `TYPE_APPLICATION_OVERLAY`。**功能下限 API 26**：本应用 minSdk=23
  （`android/app/build.gradle.kts:99` `maxOf(flutter.minSdkVersion, 23)`），API 23-25
  设备不存在该窗口类型，入口与执行路径统一加 `SDK_INT >= 26` 门控，低版本直接走
  PiP 回退（阶段 1 路径）；不做 `TYPE_PHONE` 版本分支（已废弃且与权限模型不符）。
  `FLAG_NOT_TOUCH_MODAL`（外部点击穿透）+ `FLAG_LAYOUT_NO_LIMITS`（拖出屏幕边）。
  内容为普通 View 层级：视频输出 View + 弹幕 View + 迷你控制条，全部硬件加速合成。
- 权限引导（一次性，设置页 + 首次点小窗时内联引导）：
  1. 通用：`Settings.canDrawOverlays()` 为 false → 跳
     `ACTION_MANAGE_OVERLAY_PERMISSION` + package Uri。
  2. MIUI/HyperOS 额外要求「后台弹出界面」权限，否则悬浮窗只在应用前台可见——
     跳转 MIUI 应用详情权限页（组件名各版本有差异，**需真机确认**，列入实施清单
     验证项而非拍脑袋写死）；检测用 `appops get <pkg> SYSTEM_ALERT_WINDOW` 观察
     授权前后输出差异。
- 服务只承载窗口句柄 + 触摸拖动（`LayoutParams.x/y` + `OnTouchListener`）+ 自由缩放
  （拖边缘 / 角等比缩放，宽 160dp–屏宽 72%，对齐系统画中画手感；**无档位**——用户
  2026-10-05 拍板，三档与 B 站双指缩放方案作废；松手重设 surface 尺寸并记忆上次尺寸）；
  命令按钮直接调 `NativeMediaCommandCoordinator.dispatch*`（进程内单例，
  `NativeMediaCommandCoordinator.kt:13,54-64`），与通知/PiP/线控同一条总线。

### 3.3 渲染交接：TextureView 后端 + 渲染组 reparent，失败回退 PiP

**决策：悬浮窗形态把视频后端切到 TextureView（阶段 2 唯一动渲染后端的地方），
迁移语义是「把 NativePlayerSurface 整体从 Activity 视图树 reparent 进悬浮窗
View 层级」，而不是 Activity/悬浮窗各持一份视频 View。**

- 为什么 TextureView 而非 SurfaceView：
  1. `TextureViewVideoOutputTarget` 已有完整实现
     （`mpv/VideoOutputTarget.kt:95-443`：generation 递增 387-392、stale frame
     用 `alpha=0` 压制 430、同步 getBitmap 146-210 + PixelCopy 212-270），基础件
     直接复用，**但 surface 生命周期语义需要 handoff 化改造（见迁移流程第 4-5 点
     的必要改造 A/B），不是零改动**；SurfaceView 侧（446-688）`supportsBitmapCapture=false`
     （473-474）拿不到定格图，交接防黑闪手段缺失。
  2. TextureView **具备**调用方保活 `SurfaceTexture` 的框架能力
     （`onSurfaceTextureDestroyed` 返回 false 自管释放），这是 SurfaceView
     （surface 随窗口生灭）做不到的零黑帧迁移基础。但**仓库现实现未利用该能力**：
     `mpv/VideoOutputTarget.kt:400-407` 的 `onSurfaceTextureDestroyed` 先回调
     `listener?.onSurfaceDestroyed(generation)` 再 `releaseCurrentSurface()` 并
     `return true`——SurfaceTexture 不被保活。零黑帧迁移必须改造该回调（必要改造 B），
     属本方案新增行为，需真机验证（见风险表）。
  3. TextureView 是 View 层合成，跟随窗口 transform/圆角/缩放，悬浮窗缩放动画顺滑。
  4. 代价可控：TextureView 放弃 SurfaceFlinger 独立硬件层、视频进 app GPU 合成——
     `lib/services/gpu_profile_bridge.dart:6-11` 注释警惕的整屏合成开销是 Flutter
     Impeller（Vulkan 双上下文）场景；原生壳无 Flutter 合成器参与，且悬浮窗为自由
     缩放（默认宽 248dp，160dp–屏宽 72%），合成面积随尺寸线性变化，默认档约为
     全屏的 1/6 量级。预算按默认档给出、最大档另测（5.2/5.3）。
- 迁移流程（全程不断播的目标依赖下述两项必要改造，缺一会撞 destroy 分支暂停）：
  1. 进悬浮窗：`FloatingPlayerService` 建窗口 → 主线程把 `NativePlayerSurface`
     （即 controller+mpv+弹幕+视频 View 的整体，`mpv/NativePlayerSurface.kt:59-87`）
     从 Activity 内容视图摘下 → 先 `videoOutputController.detachSurfaceForHandoff()`
     （`VideoOutputController.kt:155-164`，**只解绑不暂停**）→ `addView` 进悬浮窗
     层级 → TextureView `onSurfaceTextureAvailable` 新 generation 递增
     （`VideoOutputTarget.kt:387-392`）→ `onSurfaceAvailable`（generation 门
     `VideoOutputController.kt:106-109`）→ `rebindSurface` 重挂
     （594-631）→ `onVideoOutputSurfaceSizeChanged` 把悬浮窗尺寸报给 mpv
     （`MpvPlaybackController.kt:1246-1261`，`android-surface-size` 是 resize 后
     不压缩画面的必需调用，1252-1253 注释明示）。
  2. 摘出瞬间到新 surface ready 之间的视觉空洞用定格图盖住：`captureFreezeFrame`
     （PixelCopy 异步，`mpv/NativePlayerSurface.kt:257`；分屏/全屏切换防黑闪的
     现成手段，调用方先例 `captureAndFreeze`，`NativePlayerActivity.kt:2469`）。
     **时序：定格图必须在 detach 之前捕获**（PixelCopy 需要有效 surface），
     `detachSurfaceForHandoff` 排在其后。
  3. 展开回全屏 = 逆序：freeze 图 → detach handoff → reparent 回 Activity 视图树
     → surface available 重挂 → 移除悬浮窗窗口 → `moveTaskToFront`（进程内
     `resumeRetained` 同款，`NativePlayerActivity.kt:1113-1119`）。
  4. **必要改造 A（硬性，否则违背不断播）**：reparent 出窗口必然触发
     `onSurfaceTextureDestroyed`（`mpv/VideoOutputTarget.kt:400-407`），其
     `listener?.onSurfaceDestroyed(generation)` 会沿
     `mpv/NativePlayerSurface.kt:112-115` 透传到
     `MpvPlaybackController.onVideoOutputSurfaceDestroyed`
     （`MpvPlaybackController.kt:1263-1307`）——按现有链路将 queueSeek + pause
     （除非听视频/keepAudioWhenScreenOff）+ detach + `vid=no` 挂起，播放中断。
     因此 handoff 态必须给这条链加旁路：进入迁移前置 handoff 标记，destroy 回调
     到达时**改走 detachSurfaceForHandoff 同义路径**（不 seek 回写、不 pause、
     不 `vid=no`、不 `sessionGate.onSurfaceLost`），退出迁移后清除标记；
     `detachSurfaceForHandoff` 先行解绑只解决 mpv 侧，**不能阻止** View 层的
     destroy 回调链，二者缺一不可。
  5. **必要改造 B（零黑帧目标，真机验证）**：handoff 分支同时让
     `onSurfaceTextureDestroyed` **返回 false** 且不执行 `releaseCurrentSurface()`
     （改造 `mpv/VideoOutputTarget.kt:400-407` 现逻辑），由 NativePlayerSurface
     自持 SurfaceTexture；新窗口 attach 后 `setSurfaceTexture()` 复用旧纹理，
     迁移期间帧缓冲不销毁。自持纹理的释放时机必须服从释放顺序红线——只在
     `NativePlayerSurface.release`（controller.disposeBlocking 之后，
     `mpv/NativePlayerSurface.kt:333-341`）里释放。**降级路径**：若框架在
     remove→add 场景下对返回 false 的复用行为真机验证不过（TextureView 重挂
     可能重建 SurfaceTexture），则只落地改造 A，交接黑帧由定格图覆盖，
     P3 <200ms 预算兜底；mpv 侧重挂恢复链路（`MpvPlaybackController.kt:1078-1244`：
     重挂→恢复视频轨→pending recovery→续播）在两种路径下都成立。
- 后端切换落点：`NativePlayerSurface` 构造参数增加后端选择（现状固定
  SurfaceViewVideoOutputTarget，`mpv/NativePlayerSurface.kt:40`；Activity 侧
  creationParams 硬编码 `"videoOutputBackend"="surface"`，`NativePlayerActivity.kt:3065`）。
  Flutter 侧编译期常量先例 `FLY_PLAYER_VIDEO_OUTPUT_BACKEND` 默认 texture
  （`lib/playback/playback_source.dart:9-22`）可对照，但**原生壳后端是 Kotlin
  构造期决定**，不走编译期常量。
- 失败回退：以下任一即自动降级系统 PiP（阶段 1 的五键遥控此时恰好是 PiP 的完整
  体验）：悬浮窗权限未授予 / TextureView surface attach 失败 /
  `escalatePerformanceFallback` 阶段 2 内连升两级（性能阶梯
  `MpvPlaybackController.kt:2835-2926`）。回退动作 = `enterPip()`
  （`NativePlayerActivity.kt:4393-4401`）并关闭悬浮窗。

### 3.4 生命周期链路改造（阶段 2 最大改动面）

悬浮窗态引入新状态 `floatingMinimized`（区别于 `playbackParked`）：

| 时机 | 现状 | 悬浮窗态目标 | 锚点 |
|---|---|---|---|
| 进小窗 | `finishOrEnterPip` → PiP（4403-4417） | 建 overlay 窗 + reparent + `moveTaskToBack`，**不 park 不 pause** | parkPlayback 会 pause+停上报（4423-4427），不可复用 |
| onStop | `pipExitAwaitingResume` 时暂停、守卫 stop（11011-11024） | `floatingMinimized` 时不停播、不停周期上报、守卫照常 | 依赖「不可见=onStop」的假设点逐个过 |
| onUserLeaveHint / autoEnter | S+ 手势离开自动进 PiP（10877-10892、10866） | 悬浮窗可用且未开时禁 autoEnter（悬浮窗优先），已开则保持 | — |
| back 键 | `finishOrEnterPip`（4403-4417） | 悬浮窗能力就绪 → 收小窗；否则维持 PiP 路径 | — |
| onPictureInPictureModeChanged | 进出 PiP 收/恢复控制层（3480 起） | 悬浮窗与 PiP 互斥：`inPipMode` 禁进悬浮窗，反之亦然 | — |
| 划掉播放器任务 | 服务 stopWithTask=true 即亡（`AndroidManifest.xml:209`） | 引擎在 Activity，任务划掉 = 停播，`onDestroy`（11092）关悬浮窗，**可接受限制** | 阶段 3 解决 |
| 展开回全屏 | `resumeRetained` moveToFront（1113-1122） | reparent 回 Activity + moveToFront，不停播不重载 | 3.3 流程 3 |

命令路由零改动：悬浮窗按钮与通知/PiP/线控汇同一总线
（`NativeMediaCommandCoordinator.kt:54-64` → `NativePlayerActivity` 的 onMediaXxx）。

### 3.5 内容形态与「接下来播放」

- 紧凑态：16:9 视频区 + 常显迷你条（播停 / ±15s / 集名跑马灯 / 展开关闭），
  尺寸由边缘拖拽自由缩放决定（无档位，见 3.2），记忆上次尺寸
  （`floating_mini_player_size`，同 3.6 设置键模式）。
- 点内容区出控制层：锁 / 选集入口 / 关闭。
- 选集面板：**可滚动列表**，上限约悬浮窗高度 64%，长剧集（几百集的综艺 / 长篇连载）
  不截断；打开时自动滚动定位当前集并高亮。集数多时条目用原生 View 复用
  （RecyclerView 语义）惰性构建，避免一次 inflate 全量条目；目录数据直接复用
  既有集目录源（`NativeEpisodeCatalog`，全屏页与分屏副栏同源），不在悬浮窗内
  另拉一份数据。
- 「接下来播放」条：右侧为「下一集」图标按钮（复用播放器既有 next 图标，与参考稿一致；
  **不做**文字「换片」按钮——用户 2026-10-05 拍板）。悬浮窗 UI 拿到下一集 `loadArgs` 后直接调
  `NativePlayerActivity.dispatchInPlaceLoad(loadArgs, danmakuFile)`
  （`NativePlayerActivity.kt:1143-1148`）——进程内就地换片，Activity 不可见也工作
  （`acceptInPlacePlayback` 3182-3188 → `applyIncomingPlaybackIntent` 3138-3170，
  与 onNewIntent 共用接线，同集不重载 3190-3203）。弹幕数据入口本就外置
  （`setDanmakuPayload`/`setDanmakuOcclusion`/`setDanmakuVisible`/`setDanmakuSettings`，
  `mpv/NativePlayerSurface.kt:281-314`），
  换片后新 payload 喂给悬浮窗里的同一个弹幕 View。
- 平行窗口/分屏互斥沿用现有让位规则扩展（见 3.6）。

### 3.6 入口与互斥：`displayModeEntry` 加第四态

`NativeSplitGate.displayModeEntry`（`NativeSplitGate.kt:29-44`）当前：
`currentlySplit → FULLSCREEN`；`parallelWindowEnabled && splitSupported → SPLIT`；
`pipSupported → PIP`；兜底 `ROTATE`。扩展：

```
DisplayModeEntry { SPLIT, FULLSCREEN, PIP, FLOAT, ROTATE }
```

判定优先序：`currentlySplit → FULLSCREEN`（保留退出出口，36）；悬浮窗能力 =
`overlayPermissionGranted && !inPipMode`，新设置键
`floating_mini_player_enabled` 落 `parallel_window_settings`
（SharedPreferences 先例 `ParallelWindowCoordinator.kt:11-18`，七个 key 同模式）。
用户明确的小窗与分屏二选一维持：`parallel_window_enabled=true` 时入口给分屏，
否则按 悬浮窗 → PiP → 横竖屏 让位；纯函数可测，测试扩 `NativeSplitGateTest`。

### 3.7 可接受限制与远期阶段 3

- **划掉播放器任务 = 小窗关闭、播放停止**（引擎与 Activity 同生命周期，见 3.4 表）。
- 引擎服务化（mpv/controller 迁入前台服务进程内承载，`stopWithTask` 改 false，
  UI 任挂）列为远期阶段 3：改动面 = NativePlayerSurface 与 Activity 解绑 +
  命令总线跨组件化，本方案不做前置设计，避免过早抽象。

## 4. PC 端：候选方案对比与推荐（探索性规划）

前提事实：播放页是根导航器独立全屏路由（`desktop_playback_host.dart:73-82`），
但会话静态保活可 resume（58-65, 104-167）；`window_manager 0.5.2` 窗口能力齐全
（`pubspec.yaml:53`）；已有外部播放器迷你条完整实现可对照
（`external_playback_mini_controller.dart`）；分屏副栏不承载播放
（`desktop_detail_pane_host.dart:165-173`）。

| | 候选 A：主窗口缩为置顶迷你窗 | 候选 B：第二个 Flutter 窗口 | 候选 C：原生 Win32 独立悬浮窗 |
|---|---|---|---|
| 思路 | 复用 ExternalPlaybackMiniHost 模式：保存窗口态 → 缩尺寸 → 置顶，页面 Offstage 保活 | desktop_multi_window 类插件开第二个 Flutter isolate 窗口装迷你播放器 | 自建 HWND + D3D 交换链，mpv 直接渲到原生窗口 |
| 播放连续性 | ✅ 同一 Player/VideoController，UI 切换不断播（会话保活先例 `desktop_playback_host.dart:104-167`） | ❌ media_kit Player 不可跨 isolate 移交，需双实例或状态同步 | ✅ 但等于第二套渲染栈 |
| 实现成本 | 低：进入/恢复/拖动/快捷键全有参考实现（`external_playback_mini_controller.dart:56-127`、`external_playback_mini_player.dart:134,150`） | 高：多窗口插件成熟度差，仓库零先例 | 极高：脱离 media_kit 纹理路径，显示同步补丁不适用 |
| 渲染风险 | 低：纹理路径不变，缩窗后 mpv 按小目标像素输出反而省（`desktop_mpv_runtime.dart:49` `videoOutputSize` 按显示像素算），`VideoController.setSize` 100ms 防抖已就绪（`desktop_playback_screen.dart:3839-3858`） | 中：新窗口要重建纹理注册 | 高：`media_kit_display_sync.cmake:4-11` 版本+SHA256 强绑定的纹理补丁只覆盖 media_kit_video 2.0.1 纹理入口 |
| 置顶 | 插件 `setAlwaysOnTop`（原生层已验证实现存在；不走 PotPlayerBridge——那是外部进程钩子，`potplayer_bridge.cpp:295-321`） | 同 A | 同 C 原生 |
| 主要缺点 | 缩窗瞬间全 UI relayout（有 Offstage 保状态 + 防抖兜底）；无独立圆角透明窗（迷你条 UI 自绘解决） | 跨 isolate 播放器共享无解 | 等于自研播放器壳 |

**推荐：候选 A**，理由 = 播放会话保活机制（1.2 节）与迷你窗完整参考实现同时在场，
播放连续性与成本两项硬指标完胜。定位仍是「探索性规划」，实施前先做两个预研验证
（第 7 节 PC 清单）：

1. 360x64 迷你窗下 `VideoController.setSize` 极小目标 + `FlyMpvDisplaySync`
   （`windows/runner/mpv_display_sync.h`，DXGI WaitForVBlank，与窗口尺寸无关）
   的帧稳定性；
2. 全屏播放页 → 迷你态切换时 `windowManager.setFullScreen(false)`（
   `desktop_playback_screen.dart:3727-3731` 的逆操作）与 `setResizable(false)` 的
   时序冲突。

## 5. 性能专题

> 原则：每项预算必须落在仓库已有的可观测机制上，不做无测量点的优化。

### 5.1 指标与预算总表

| # | 指标 | 目标值 | 测量方法（对齐仓库既有机制） |
|---|---|---|---|
| P1 | 悬浮窗态 UI raster 帧时（TextureView 合成 + 弹幕） | p99 ≤ 16.7ms（60Hz 面板）/ ≤ 8.3ms（120Hz） | `adb shell dumpsys gfxinfo com.geqian.flyplayer.fly_player framestats`；对照弹幕侧自计帧预算（`NativeDanmakuOverlayView` recordFrameStats，`mpv/NativeDanmakuOverlayView.kt:357-360`） |
| P2 | mpv VO/解码丢帧（悬浮窗 30 分钟连续播放） | 悬浮窗态零 `perf fallback L*` 日志；drop 计数增量 ≈0 | logcat `perf fallback`（`MpvPlaybackController.kt:2856-2921`）；计数器采样机制本身在同文件 2788-2789（`frame-drop-count`/`decoder-frame-drop-count`，属性 miss 缓存跳过） |
| P3 | Surface 交接黑屏可感知时长（收小窗/展开各一次） | < 200ms | logcat 打点：detach handoff → onSurfaceAvailable generation 时间差；录屏逐帧复核（定格图覆盖，`mpv/NativePlayerSurface.kt:257`） |
| P4 | 悬浮窗弹幕单帧 onDraw | ≤ 4ms | 弹幕 View 自计帧统计 + `Choreographer` skip 计数（shouldThrottleFrame 路径，`NativeDanmakuOverlayView.kt:349-368`） |
| P5 | 悬浮窗显示刷新率（HyperOS 钳制设备） | 悬浮窗态仍按面板档播放，或明确记录钳制为系统限制 | logcat `HyperosRateGuard: clamped ... restored`（`HyperosRefreshRateGuard.kt:67`）与 `applyPreferredHostDisplayMode ... displayHz/requestedHz` 观测点（`docs/plans/hyperos-cloud-fps-lock.md:61-62`） |
| P6 | PC 迷你态 Flutter raster/build 帧时 | p99 ≤ 8.3ms（120Hz 显示） | `_FrameTimingLogger`（`lib/main.dart:126-127,84` install，slow>16.667/jank>33.333 分列 build/raster） |
| P7 | 后台功耗（悬浮窗 vs 系统 PiP 基线） | 增量 ≤ PiP 基线 +5% | `adb shell dumpsys batterystats` 30 分钟对照 + Battery Historian |

### 5.2 Surface 交接的帧预算（安卓）

- 交接路径上 mpv 侧只有两个同步点：`android-surface-size` 重设
  （`MpvPlaybackController.kt:1246-1261`）与 `rebindSurface` 的 detach-then-attach
  （`VideoOutputController.kt:594-631`）；两者都在单 playback HandlerThread 上收敛
  （mpv 属性写入集中该线程，主线程只做 Surface/UI/状态分发——线程模型即
  `MpvPlaybackController.kt:70-71,84-85` 的单 HandlerThread 设计），不存在主线程阻塞点。
- 视觉连续性预算：交接空洞由 freeze 图回填兜底（PixelCopy 异步，**先于 detach
  捕获**，见 3.3 流程 2），P3 <200ms 按这条最坏路径设计；SurfaceTexture 复用
  （3.3 改造 B）成立时空洞趋近零，但那是待真机验证的优化而非设计前提——
  P3 实测两条路径各记一个数，验收线以最坏路径为准。
- 交接后首帧起弹幕帧率票重打（`setRequestedFrameRate` 先例：
  `mpv/NativePlayerSurface.kt:356-357`，SDK35 View 票 + R+ Surface 票同款在
  `mpv/MpvPlayerView.kt:412-444`），避免迁移后掉回 60 默认档。

### 5.3 弹幕在缩放窗口的绘制策略

- 弹幕 View 直接随 `NativePlayerSurface` 迁入悬浮窗层级——它是无 Activity 依赖的
  普通 View（`mpv/NativeDanmakuOverlayView.kt:225-228`），时间线由外部喂的
  positionMs 驱动（数据入口 `mpv/NativePlayerSurface.kt:287-314`），零改造可挂。
- 缩放即省：悬浮窗物理像素小（默认 248dp 宽，自由缩放区间内仍远小于全屏），
  文本位图 LruCache 命中结构不变、
  drawBitmap 面积等比缩小，单帧成本天然下降；**不**为悬浮窗另做弹幕布局算法。
- 帧率策略：悬浮窗态弹幕目标帧率从默认 120 降为 60（clamp 24-120 的常量与 vote
  机制现成，`mpv/NativePlayerSurface.kt:31-34, 356-357`）——小窗上 120fps 无感知
  收益，直接减半 Choreographer 排帧；这与 L2 降级（压弹幕负载，
  `MpvPlaybackController.kt:2870-2883`）解耦，不冲突。
- AI 遮罩：悬浮窗态**默认关闭**遮罩管线。先例是分屏期间强制关（MNN resize 失配
  空跑烧 CPU，`effectiveOcclusionConfig` 收敛点 `NativePlayerActivity.kt:9100-9123`、
  L1 也经同一收敛点强关 10223）——悬浮窗复用该收敛点加一个条件，而不是新开开关。
- `shouldAnimate() == false`（禁弹幕/无评论/不可见）时完全不排帧
  （`mpv/NativeDanmakuOverlayView.kt:353-355`），悬浮窗关闭弹幕 = 零弹幕成本。

### 5.4 PC 端纹理/合成开销

- 迷你态 mpv 按 360 宽目标像素输出（`desktop_mpv_runtime.dart:49` `videoOutputSize`
  按显示像素算），缩放算法（bilinear/spline36/ewa_lanczossharp 三档，
  `desktop_playback_screen.dart:661-669`）在极小目标上的开销可忽略；
  resize 合并由 100ms Timer 防抖合并纹理重建（3839-3858 已验证存在）。
- 合成路径不变：media_kit_video 2.0.1 纹理提交 + Flutter 侧合成，显示同步补丁
  （`windows/media_kit_display_sync.cmake:4-11`）继续生效——这是候选 A 相对 C 的
  根本性优势。
- 置顶与 z 序：`HWND_TOPMOST`（插件 setAlwaysOnTop）无额外 GPU 成本，DWM 合成
  不变；`Offstage` 页面不参与绘制（`external_playback_mini_controller.dart:214-218`）。
- 观测：P6 的 `_FrameTimingLogger` + GPU 侧现有 debug 帧计时器；视觉分层
  `AppVisualPerformanceTier`（`lib/theme/visual_performance.dart:2-5`）的
  desktopBlurSigma 对迷你条玻璃效果按档降级（DesktopFloatingPanel 依 tier 决定
  是否实时 blur——迷你条 UI 若复用该组件自动继承）。

### 5.5 后台功耗

- 安卓悬浮窗本质 = 应用窗口可见渲染，不存在后台限制新问题；功耗增量来源只有
  TextureView 进 GPU 合成这一项（P1/P7 覆盖）。现状基线：**播放链路无 WakeLock、
  仅 `FLAG_KEEP_SCREEN_ON`**（`NativePlayerActivity.kt:3036`）；全仓唯一的
  WakeLock 持有方是后台下载服务——`DownloadTransferService.kt:46-50` 在服务启动时
  `newWakeLock(PARTIAL_WAKE_LOCK, "FlyPlayer:Downloads")` 并 `acquire(6h)`
  （manifest 的 WAKE_LOCK 权限即为其声明，`AndroidManifest.xml:8`），与播放/悬浮窗
  链路无关，悬浮窗态不新增持锁。熄屏丢 surface 时按听视频/keepAudioWhenScreenOff
  决定是否续声（`MpvPlaybackController.kt:1274-1285`）。悬浮窗态不动这些开关。
- 弹幕帧率降档（5.3）与 AI 遮罩默认关（5.3）同时是功耗措施：Choreographer 排帧
  减半 + MNN 不空跑。
- HyperOS 前台限帧是显示侧问题非功耗侧（PowerKeeper 每次进前台写 60，
  `HyperosRefreshRateGuard.kt:17-22` 实证注释），守卫已就位，悬浮窗态沿用
  onStart/onStop 挂载即可（11006/11024）。
- PC：迷你态无新增常驻线程；SMTC（`DesktopSystemMediaControls`）随播放页生命周期，
  迷你态保持其存活即可，不另起会话。

## 6. 风险与降级

| 风险 | 证据 | 缓解/降级 |
|---|---|---|
| TextureView 合成在中端 Mali 上不可接受（P1 超标） | Impeller 整屏合成 2x 开销的前车之鉴是 Flutter 双 Vulkan 场景（`lib/services/gpu_profile_bridge.dart:6-11`），原生壳无此问题，但需实测 | 性能阶梯 L1→L2 自动压弹幕（2835-2926）；连升两级 → 回退系统 PiP（3.3）；极端情况保留阶段 1 的 PiP 作为该档设备永久路径 |
| SurfaceTexture 复用真机不过（remove→add 场景框架可能重建纹理） | 现实现 `return true`+release（`mpv/VideoOutputTarget.kt:400-407`），自持复用（改造 B）是本方案新增行为 | 降级只落地改造 A（destroy 旁路），交接黑帧由定格图覆盖，P3 <200ms 兜底；mpv 重挂恢复链路（1078-1244）两条路径下都成立 |
| `android-surface-size` 未随悬浮窗尺寸重设 → 画面压缩 | 分屏 resize 已明示该调用必需（`MpvPlaybackController.kt:1252-1253`） | 迁移完成与每次自由缩放（拖拽松手）后强制走 `onVideoOutputSurfaceSizeChanged` |
| MIUI「后台弹出界面」未授权 → 悬浮窗前台外不可见 | MIUI 权限模型，真机才能确认引导组件名 | 权限检测 + 引导页 + 未授权时回退 PiP；写入实施清单验证项 |
| 生命周期改动碰坏 PiP/保留会话既有行为 | `buildPipParams` autoEnter 与 `playbackParked` 耦合（10866）、onStop 暂停依赖（11011-11024） | `floatingMinimized` 独立状态位，park/PiP 分支显式互斥；`NativePlayerActivityPanelModelsTest` 补状态矩阵用例 |
| 划掉任务小窗即亡（产品预期差） | `NativePlaybackMediaService` stopWithTask=true（`AndroidManifest.xml:209`）+ 引擎在 Activity | 产品侧接受（已确认）；阶段 3 引擎服务化才解 |
| PC：media_kit 升级破坏显示同步补丁 | CMake 版本+SHA256 双校验 FATAL_ERROR（`windows/media_kit_display_sync.cmake:4-11`） | 锁版本不动；预研项 1 失败则 PC 迷你窗整体缓行 |
| HyperOS 钳 60 使悬浮窗弹幕掉帧（用户观感归因错误） | 应用侧任何票顶不开 primary 钳制（`docs/plans/hyperos-cloud-fps-lock.md:44-46`） | P5 观测点区分「被钳」与「真掉帧」；守卫授权引导沿用现有文案 |

## 7. 实施清单（分支 `feature/floating-mini-player`）

### 阶段 0：分支与地基（0.5d）
- [ ] 从当前工作区切出分支；未提交的 `displayModeEntry` + `HyperosRefreshRateGuard`
      先行入库（与本方案无冲突但属前置）。
- 验收：`gradlew test` 全绿（`NativeSplitGateTest`、`HyperosRefreshRateGuardTest` 在列）。

### 阶段 1：PiP 五键 + setSubtitle（1-1.5d）
- [ ] `NativeMediaCommandCoordinator`：`ACTION_SEEK_BACK_15S/FWD_15S/PREVIOUS` +
      `onMediaPrevious()`（`Handler` 接口扩展，`NativeMediaCommandCoordinator.kt:21-22`）。
- [ ] `NativePlayerActivity`：`hasPrevEpisode()`（对照 7727）、`pipRemoteActions`
      五键化（10825-10857）、`buildPipParams` API33+ `setSubtitle`（10859-10869）。
- [ ] 单测：Coordinator 路由 + 五键编排 + 直播只播停。
- 验收：2.3 节 4 条全部真机通过。

### 阶段 2：自绘悬浮窗（5-8d，按 3.2→3.6 顺序）
- [ ] `FloatingPlayerService` + manifest（`SYSTEM_ALERT_WINDOW` 权限、前台服务声明）。
- [ ] **API 26+ 门控**：`SDK_INT >= 26` 才启用悬浮窗入口与执行路径
      （minSdk=23，`android/app/build.gradle.kts:99`），低版本直接 PiP 回退。
- [ ] 权限引导页/内联引导（含 MIUI 后台弹出界面真机确认）。
- [ ] `NativePlayerSurface` 后端构造参数（40 行处）+ TextureView 迁移路径（3.3 流程），
      其中两项必要改造单列：
      - 改造 A：handoff 标记 + destroy 回调旁路——`onSurfaceTextureDestroyed`
        触发链（`mpv/VideoOutputTarget.kt:400-407` → `mpv/NativePlayerSurface.kt:112-115`
        → `MpvPlaybackController.kt:1263-1307`）在 handoff 态跳过 queueSeek/pause/
        `vid=no`/`sessionGate.onSurfaceLost`，改走 detach 语义；
      - 改造 B：`onSurfaceTextureDestroyed` 返回 false 自持 SurfaceTexture +
        重挂 `setSurfaceTexture` 复用，真机验证 remove→add 框架行为，
        不过则降级只做 A。
- [ ] `floatingMinimized` 生命周期矩阵（3.4 表逐格落地）。
- [ ] 悬浮窗 UI：紧凑条/控制层/接下来播放（`dispatchInPlaceLoad` 1143-1148）/
      拖动/边缘自由缩放/边缘吸附。
- [ ] `displayModeEntry` FLOAT 态 + `floating_mini_player_enabled` 设置键
      （`ParallelWindowCoordinator.kt:11-18` 同模式）+ 测试。
- [ ] 性能打点：P1-P5 观测点落位（5.1 表）。
- 验收（真机 + P1/P2/P3 预算达标）：
  1. 播放中点小窗 → 悬浮窗出现、回桌面/其他应用置顶可拖可缩，播放与弹幕连续，
     交接黑屏 <200ms；
  2. 「接下来播放」在悬浮窗内换片成功且全屏展开后进度/轨道正确；
  3. 展开回全屏画面连续；关闭悬浮窗回 PiP 兜底路径；
  4. 未授权设备/失败注入 → 自动回退系统 PiP（阶段 1 体验）；
  5. 划掉任务 = 小窗关闭且无泄漏（`onDestroy` 释放顺序红线不破，
     `mpv/NativePlayerSurface.kt:333-341`）；
  6. 30 分钟悬浮窗播放 P2 零降级日志、P7 功耗对照达标。

### PC 预研（探索性，2-3d，不进本分支主线）
- [ ] 预研项 1/2（第 4 节）；产出候选 A 的迷你条复用改造清单
      （ExternalPlaybackMiniHost 与播放器类型解耦）后另行立项。

## 8. 开放问题

1. ±15s 粒度是否也应用到通知/线控（现 `SEEK_STEP_MS=10_000`，
   `NativeMediaCommandCoordinator.kt:33`）？本方案默认只改 PiP/悬浮窗，通知保持 10s。
2. MIUI「后台弹出界面」权限的跳转组件名与检测方式需真机确认（无真机证据不写死，
   见 3.2 与 7 阶段 2）。
3. ~~悬浮窗档位缩放的默认档与记忆策略~~ 已拍板（2026-10-05）：**无档位**，拖边缘/角
   自由等比缩放（宽 160dp–屏宽 72%）；记忆上次尺寸（落 `floating_mini_player_size`，
   同 3.6 设置键模式）。「接下来播放」条换片按钮改为「下一集」图标，同日拍板。
4. PiP 与悬浮窗并存的系统场景（用户先进 PiP 又在别处开小窗）：本方案用互斥
   （3.4 表），是否需要在 PiP 内给「转悬浮窗」按钮？建议阶段 2 后按反馈决定。
5. PC 迷你窗是否需要「接下来播放」条（外部播放器迷你条无此形态）？候选 A 复用
   会话换片链路可行，但建议 PC 首版只做播停/切集，控制密度对标 B 站桌面端。
