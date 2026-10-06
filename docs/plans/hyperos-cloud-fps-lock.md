# HyperOS 云控游戏误判锁 60fps：诊断与处置

- 日期：2026-09-30 晨
- 设备：2410CRP4CC（Redmi，HyperOS，面板 30-144Hz，用户设置 `user_refresh_rate=120`）
- 现象：应用 UI 掉到 60fps（此前也发生过，"又回来了"）

## 机制（本机实证）

1. 云控/SAGT 把应用误判为游戏后写 **`secure miui_refresh_rate=60`**（注意此时
   `system peak_refresh_rate=120`、`secure user_refresh_rate=120` 都还是 120——
   云控绕过用户选择直接改 `miui_refresh_rate`）。
2. display 策略层随之钳制：`mDisplayModeSpecs` 的 `primary render (0.0,60.0)` 与
   `appRequest render (0.0,60.0)` 同时被压到 60，`mActiveModeId=4`（60Hz）。
   应用侧 `preferredDisplayModeId`（FlutterHostActivity 请求最高档）**在此钳制下不生效**，
   desired 虽出现 120 但 active 不动。
3. SAGT 自适应跟测（logcat `ANDR-PERF-LM`/`SAGT_ACTION`）：量到应用实际 fps 就把
   `sched_penalty fps` 限到该值（实测 19.5→20、32→35），应用被钉在 60 → 永远锁 60，
   恶性循环。`cloud_periodic_game_enable=true`（云端周期性游戏判定开启）。
4. 设备 FrameRateCategory 配置：`normal=60, high=90`——未显式投票的应用按类别落 60。

## 现场恢复（10 秒）

```bash
adb shell settings put secure miui_refresh_rate 120
# 立即生效：mActiveModeId=1（120Hz），primary/appRequest 两层同时解锁
```
或设备上：设置 → 显示 → 刷新率切一次（会重写 `miui_refresh_rate`）。

## 应用侧加固（本次实施）

`FlutterHostActivity.applyPreferredHostDisplayMode` 在原有
`preferredRefreshRate + preferredDisplayModeId`（最高档）之外补一层显式票（View 层），
与播放器弹幕面先例（MpvPlayerView host_frame_rate_vote）同款——
仅移植先例的 View 层，未加 Surface 层票：
- SDK 35+：`window.decorView.setRequestedFrameRate(hz)`（显式帧率票，传显式 Hz 值
  `preferredRefreshRateHz` 而非 FrameRateCategory 类别）；
- 未实施：R+ `Surface/SurfaceControl.setFrameRate` 票仅存在于弹幕面先例
  （mpv/MpvPlayerView.kt:427-435），宿主窗口未加；如未来需要参照该处。
create/resume/focus/configuration 四时机都会重打票。原生日志
`applyPreferredHostDisplayMode ... displayHz=... requestedHz=...` 即"是否被钳"的观测点
（displayHz=60 且 requestedHz=120 → 正被钳）。

## A/B 结论（2026-09-30 实测）

- 基线（无新票，旧 APK）：miui_refresh_rate=60 → active=60（modeId 4）。已实证。
- 新票后（SDK 35 View.setRequestedFrameRate，冷启动四时机全打票）：
  miui_refresh_rate=60 → **active 仍为 60**。应用侧任何票
  （preferredDisplayModeId / preferredRefreshRate / 显式帧率票）都顶不开
  primary 策略层的钳制。
- miui_refresh_rate=120 → active=120，立即可用（已实证，两次）。
- **重写行为**：解锁后应用正常使用约 2 分钟即被静默改回 60（日志无写入者痕迹，
  推断为 PowerKeeper/云控策略服务直写 SettingsProvider）。恢复操作是临时性的，
  会随使用反复失效——这正是"又回来了"的原因。

## 处置结论

1. 应用侧无解（primary 层钳制高于一切应用投票）；SDK 35 显式帧率票已合入作为
   最佳努力（仅 View 层，与播放器先例的 View 层一致），成本为零。
2. 用户侧恢复：`adb shell settings put secure miui_refresh_rate 120`，或
   设置 → 显示 → 刷新率重切一次。**会反复失效，需要时重跑。**
3. 用户侧排查方向：手机管家 → 游戏加速 的应用列表里若出现本应用，关闭其加速
   （云控把应用注入游戏分类的落点通常在这里）；同时可向 MIUI 反馈该包名被
   云控误分类。
4. 观测点：原生日志 `applyPreferredHostDisplayMode ... displayHz=... requestedHz=...`
   ——displayHz=60 且 requestedHz=120 即正处于钳制态。
5. 对昨晚弹窗验收的影响：无。整页重建的消除是 build 侧成本（17.1ms→0），
   与显示刷新率无关；昨晚复测的 2 帧边缘越线是在 60Hz 钳制态下量的（最坏情况），
   120Hz 下只会更宽裕。

## 触发诱因（推测，供观察）

夜里复测让右栏引擎连续以 ~60fps 渲染约 30 分钟（分屏详情页本身 raster 重，
本就到不了 120），SAGT 周期判定窗口内量到 60 → 判定游戏 → 写 60。
复现规避：避免让分屏详情页长时间静止停留在前台？不可控，等云控策略变化即可，
恢复命令见上。

## 2026-10-04 复发实测：写入者与触发规律已实锤

设备 2410CRP4CC，应用使用中被再次钳到 60。本次抓到完整证据链：

1. **写入者 = `com.miui.powerkeeper`（不是云控直写、也不是 SAGT）**。
   SettingsProvider 日志逐条记录调用方：
   `SettingsProvider: refresh rate settings changed, name:miui_refresh_rate,value:60,pkg:com.miui.powerkeeper`。
2. **触发规律：本应用每次进前台后 60~230ms 内写 60；切回桌面（com.miui.home 进前台）
   写回 120。** 18:53~18:56 共 6 次事件全部吻合，无一例外。此前「约 2 分钟被静默
   改回」实为前台切换相关，不是定时器。PowerKeeper 自身日志佐证：
   `PerfEngineController: ForegroundInfo{mForegroundPackageName='com.geqian.flyplayer.fly_player'}`
   紧跟写 60 动作；其 DisplayFrameSetting 模块同时跟踪本包（`onVideoFpsChange`）。
3. **排除项（均有实证）**：SAGT 调度限帧当时写 0（未参与）；按应用省电策略改为
   「无限制」（`PowerSaveConfigureManager ... configure=no_restrict`）后照写不误；
   应用窗口已投出 144Hz Exact 帧率票（SurfaceFlinger requestedFrameRate 可见），
   primary 钳制下 active 仍为 60（modeId 4）——再次验证「应用侧票顶不开钳制」。
4. **PowerKeeper 无法用 adb 停用**：`pm disable-user` 报
   `SecurityException: Cannot disable system packages`，`pm suspend` 返回
   `new suspended state: false`（需 root）。
5. **应用侧自救（本次实施）**：`HyperosRefreshRateGuard` 监听
   `secure miui_refresh_rate`（ContentObserver）。当该键被写低（低于用户
   `user_refresh_rate`，其次系统 `peak_refresh_rate`）且应用持有
   WRITE_SECURE_SETTINGS（`adb shell pm grant com.geqian.flyplayer.fly_player
   android.permission.WRITE_SECURE_SETTINGS` 一次性授予）时，自动写回用户值。
   未授权时休眠（`Settings.Secure.canWrite` 即 false）；用户主动选 60 时目标值
   同为 60，不对抗用户。挂载点：FlutterHostActivity 与 NativePlayerActivity 的
   onStart/onStop（分屏下 onStop 不触发，观察器保持活跃）。
   验证方法：应用前台时 `adb shell settings put secure miui_refresh_rate 60`，
   应在 1s 内被自动写回，logcat `HyperosRateGuard: clamped ... restored`。
