# 原生播放壳补强计划（交 Opus 4.8 执行）

> 背景：项目播放器正从「Flutter UI + mpv」迁到「原生 Android UI + mpv」（原生壳 =
> `NativePlayerActivity` + `mpv/NativePlayerSurface` 一族）。本计划由 Fable 5 调研产出，
> 列出已验证的缺口与分阶段改法。**执行前先读"现状盘点"，不要重复实现已有功能。**

## 0. 现状盘点（已逐项在代码中核实，勿重做）

原生壳**已具备**：
- 手势：亮度/音量/横拖 seek/双击播停/长按 2x/锁定（`NativePlayerActivity.GestureListener`）
- 选集、清晰度（网格+自定义）、音轨/字幕选择、外挂字幕（`applySubtitleByGuid`/`selectExternalSubtitle`）
- 弹幕：设置/搜索/本地导入/已存源管理（`buildDanmaku*Page`），动态遮罩（Plan B v2 流水线）
- AB 循环、书签、片头片尾跳过、纯听模式（`toggleAudioMode`）、截图+预览+分享
- PIP（`enterPip`）、分屏（ActivityEmbedding，`enterSplitMode`/`exitSplitMode`，**未真机验证**）
- mpv 高级设置：软硬解、画面比例、去隔行/去色带/锐化/降噪/缩放算法/HDR 模式/补帧/
  视频同步/缓存策略/兼容模式（`buildAdvancedMpvPage` → `MpvAdvancedSettingsController`）
- 音频：延迟、音量增益、动态范围压缩、限制器、低音/人声增强、声道、EQ 预设+自定义五段
- 字幕样式：延迟/垂直位置/字号缩放
- 章节缓存、续播提示、自动连播倒计时、弱网监测（`WeakNetworkBufferingController`）、
  持久播放缓存（`PersistentPlaybackCacheStore`，完整缓存可本地直放）
- 设置持久化：`NativePlayerSettingsStore`（SharedPreferences+JSON 白名单合并）
- 进度回写：`reportProgress` → `NativePlayerReverseBridge.dispatch("recordProgress")` →
  Flutter 详情页 State 写 NAS
- HDR 管线：`VideoOutputController` 已有 HDR_DIRECT / HDR_TONEMAP_SDR / hwdec
  mediacodec-copy 自动回退 / Activity colorMode 切换 / 显示器 HDR 能力探测
- 帧率提示：`NativePlayerSurface.kt:335` 已调 `Surface.setFrameRate`

**入口灰度开关**：`NativePlayerBridge.maybeLaunch`（`lib/services/native_player_bridge.dart:193`）
读 `DanmakuSettingsStore.useNativeRenderer`，所有播放入口（详情页/季页/下载页）都已接。

**未提交的在途改动**（执行本计划前先确认已提交）：Authx 公共签名修复
（`lib/api/feiniu_api.dart` + `NativeMpvProxyServer.kt`）与原生壳弹幕预取对齐
（`lib/services/native_danmaku_prefetch.dart`）。

---

## Phase 1：系统级媒体集成（最大缺口，优先）

**问题**：`NativePlayerActivity` 完全没有 MediaSession / 前台服务 / 音频焦点 / 拔耳机暂停；
PIP 窗口没有播放控制按钮。纯听模式切后台会被系统掐断。现有
`PlayerNotificationService` 只服务旧 Flutter 壳（`PlayerActivity`/`FlutterHostActivity`），
不要直接复用，但可参考其通知构建方式。

改动点（全部原生侧）：

1. **音频焦点**：在 `MpvPlaybackController`（或新建 `PlaybackAudioFocusController`）用
   `AudioFocusRequest`（API26+）请求/释放焦点：
   - 失去焦点 LOSS → 暂停；LOSS_TRANSIENT → 暂停并记录，恢复焦点续播；
   - LOSS_TRANSIENT_CAN_DUCK → mpv `volume` 临时降到 30% 左右，恢复时还原。
   - 播放开始时请求，暂停/销毁时释放。
2. **拔耳机暂停**：注册 `AudioManager.ACTION_AUDIO_BECOMING_NOISY` receiver，收到即暂停。
3. **MediaSession + 前台服务**：新建 `NativePlaybackMediaService`（前台服务，
   `mediaPlayback` 类型，manifest 加 `FOREGROUND_SERVICE_MEDIA_PLAYBACK` 权限）：
   - `MediaSessionCompat`（或 media3 的 `MediaSession`，二选一，倾向 media3）；
     metadata 用 loadArgs 的 title/封面（封面取 Phase 3 的本地缓存）；
   - 通知动作：播放/暂停、±10s、下一集（有下一集时）；
   - 蓝牙/耳机线控经 MediaSession 回调接 `playerSurface` 的播停/seek；
   - 生命周期：进入 `NativePlayerActivity` 启动并绑定，退出播放器 stop；
     **纯听模式 + 切后台 = 继续播**（服务保活），非纯听模式切后台按现行为暂停。
4. **PIP 增强**：
   - `PictureInPictureParams` 加 `RemoteAction`：播放/暂停、±10s（监听
     `onPictureInPictureModeChanged` 刷新图标）；
   - API 31+ 设 `setAutoEnterEnabled(true)`（播放中划走自动进 PIP，做成开关，
     存 `NativePlayerSettingsStore` 的 `video_misc` 组）；API <31 在
     `onUserLeaveHint` 手动 `enterPip`。

验收：来电/其他 App 抢焦点会暂停并恢复；拔耳机暂停；纯听模式锁屏后继续出声且
通知可控制；蓝牙耳机双击播停有效；PIP 小窗里能播停。

## Phase 2：真·音频直通（杜比/DTS）

**问题**：现在音频页的「高保真直通」只是绕过 af 滤镜（`applyAudioProcessing`），不是位流
直通。mpv 支持 `--audio-spdif=ac3,eac3,dts,dts-hd,truehd` 经 AudioTrack passthrough 输出
给功放/回音壁/电视。Flutter 侧也从未实现（只有 `playerAudioPassthrough` 显示字符串）。

改动点：

1. `MpvAdvancedSettingsController` 增加 `audio_passthrough` 设置（三态：
   `auto` / `on` / `off`，默认 `off`）：
   - `on`/`auto` 时设 `mpv audio-spdif=ac3,eac3,dts,dts-hd,truehd`，并**清空 af 滤镜链、
     强制 audio-channels=auto**（直通与软件滤镜/EQ/混音互斥，UI 上联动置灰）；
   - `auto` 档先用 `AudioManager.getDevices` + `AudioFormat`/`AudioTrack.isDirectPlaybackSupported`
     探测当前输出设备是否支持对应编码（AC3/EAC3/DTS），不支持则不开；
   - `off` 时清 `audio-spdif`。
2. 直通失败兜底：监听 mpv log/audio init 失败（参考 `maybeTriggerHdrHwdecFallback` 的
   日志钩子模式），失败自动回退解码播放并 toast 提示。
3. 音频页 UI（`buildAudioPage`）：把「高保真直通」改名「直通输出(杜比/DTS)」接新设置；
   直通生效时 EQ/低音/人声/压缩/限制器整组置灰并显示"直通中由功放解码"。
4. 轨道信息页（`buildTrackInfoPage`）显示当前输出路径：直通(编码名)/PCM 解码，
   数据从 `PlaybackAudioOutputDiagnostics` 取（它已存在，确认其暴露 ao/格式信息）。

验收：连支持 eAC3 的设备（电视/回音壁）直通生效（功放显示 Dolby 标），蓝牙耳机上
auto 档自动回退解码；切直通不崩、失败有 toast 回退。

## Phase 3：断网/离线播放加固

**现状**：下载播放已走本地文件（`download_list_screen._resolveLocalSource` →
`PlaybackSourceResolver` 支持 file 路径与完整持久缓存直放），但断网体验有洞。

改动点：

1. **进度离线排队**：`reportProgress` 经反向桥到 Flutter 写 NAS，断网即丢。
   在 Flutter 侧 `NativeReentrySupport.recordProgress` 失败时把 payload 落盘
   （SharedPreferences/sqflite 队列，键含 itemGuid+ts），网络恢复或下次启动时重放；
   同一 item 只保留最新一条。本地播放统计（`play_stats`，SQLite）确认不依赖网络。
2. **封面离线可用**：原生壳 `resolveImageUrl`/`refreshListenArtwork` 走网络 URL。
   启动原生壳时 Flutter 侧（`native_player_bridge.launch` 前）把封面经图片缓存解析为
   本地文件路径塞进 loadArgs（已有图片缓存体系，复用即可），原生侧优先取本地路径，
   网络路径仅作回退。MediaSession 通知封面（Phase 1）直接受益。
3. **已存弹幕源离线加载**：`reapplyDanmakuSource` 里 episodeId 型源会经反向桥重新联网
   拉取。保存源时把弹幕内容落临时文件改为落**持久目录**（带媒体键命名），重放时优先读
   本地文件，失败才联网。本地 XML 导入型源确认已是本地文件（copyUriToCache —— 注意
   cache 目录可能被清，迁到 files 目录）。
4. **离线状态感知**：原生壳加一个轻量网络监听（`ConnectivityManager.NetworkCallback`）：
   - 断网时：选集面板里"未下载的集"置灰（下载组场景反向桥本就解析本地，确认其
     失败路径有 toast）、弹幕搜索入口置灰、清晰度切换（需 NAS 重解析的档位）置灰；
   - 弱网横幅（`updateOverlays` 已有弱网提示）补"已断网，正在播放本地内容"一档。
5. **持久缓存离线续看入口**（可选，工作量大可放最后）：断网启动 App 时，详情页/
   下载页能列出 `PersistentPlaybackCacheStore` 中完整缓存的条目并直接起原生壳本地播。

验收：飞行模式下播下载内容全程无报错弹窗，退出后进度在恢复网络后回传 NAS；
断网时封面/弹幕（已存源）正常显示；选集面板正确置灰。

## Phase 4：分屏强化——厂商平行窗口接入 + Google 合规补缺 + 真机验证

当前分支 `feat/native-player-split-screen` 已实现（ActivityEmbedding：
`ActivityEmbeddingInstaller` 的 nativePlayerSplitRule + 定格帧防黑闪 + 副栏独立引擎），
**已编译未真机**。本阶段三件事：厂商接入补缺、Google 官方方案对齐、真机验证。

### 4.0 合规现状（已核实，作为基线，勿重复改）

Manifest 已具备：`PROPERTY_ACTIVITY_EMBEDDING_SPLITS_ENABLED=true`、全 Activity
`resizeableActivity=true`、`android.supports_size_changes`、分屏阈值 840/600dp、
FinishBehavior 联动、全屏页 alwaysExpand、SDK<32 退化。
`PROPERTY_ACTIVITY_EMBEDDING_ALLOW_SYSTEM_OVERRIDE=false` 是**刻意为之**：应用自管
AE 规则，必须拒绝厂商系统规则叠加（否则主次容器错乱）。**不要改成 true。**

厂商平行窗口结论：
- Android 12L+ 的小米/OPPO/vivo 新系统已统一走 Google AE，应用自声明规则即等于
  接入，无需也无法再单独"上厂商列表"；
- Android ≤11 的旧式平行窗口是厂商白名单制，应用侧无官方接入通道，**放弃**
  （这些设备本就退化为横竖屏切换按钮，行为正确）；
- 华为/荣耀"平行视界"是唯一应用侧可接入的厂商方案 → 见 4.1。

### 4.1 华为/荣耀平行视界接入（easygo.json）

覆盖 EMUI 10.1+/HarmonyOS（Android 侧）华为平板存量设备（它们多数没有标准 AE）：
1. 新建 `android/app/src/main/assets/easygo.json`：按华为官方《平行视界接入指南》
   声明逻辑实体——`MainActivity` 为主页面(head)，`DetailActivity` 为从页面(body)，
   `NativePlayerActivity`/`PlayerActivity`/`FullscreenPlayerActivity`/
   `FullscreenScreenshotActivity` 声明为**全屏页**（不参与分屏，对齐现有
   alwaysExpand 语义）；默认分屏比例对齐 `ParallelWindowCoordinator.browsePrimaryRatio()`。
2. Manifest `<application>` 加华为要求的 meta-data（键名以华为当前文档为准，
   执行时先查官方文档核对，勿凭记忆写）。
3. 验收：华为平板（鸿蒙 2/3，无标准 AE）上 Main→Detail 左右分栏；进播放器全屏；
   退出回分栏。无华为真机则此项标注"待验证"后跳过，**不得影响其他设备行为**
   （easygo.json 在非华为设备上是死文件，零风险）。

### 4.2 Google 官方方案补缺（折叠屏为主）

1. **`SplitAttributesCalculator`**（androidx.window 1.5.0 已具备，缺口最大）：
   在 `ActivityEmbeddingInstaller` 注册 `setSplitAttributesCalculator`：
   - 折叠屏半开/桌面态（`FoldingFeature.state == HALF_OPENED` 或存在分割铰链）时
     返回 `SplitType.SPLIT_TYPE_HINGE`，让分割线落在铰链上；
   - 普通宽屏按窗口宽度档位返回比例：≥840dp 用现有 ratio，600–840dp 收窄副栏
     （或返回 expand 不分屏，与现有 minWidthDp 行为保持一致即可）；
   - 播放分屏对（nativePlayerSplitRule）与浏览分屏对（splitPairRule）按 tag 区分，
     各用各的 ratio 来源（`playerPrimaryRatio()` / `browsePrimaryRatio()`）。
   - 注意：calculator 一旦注册对所有 rule 生效，必须保留 JUMP_CUT 动画参数语义。
2. **`SplitPlaceholderRule` 评估**（二选一，倾向保留现状）：
   现状用自管 `PlaceholderActivity` + `ParallelWindowCoordinator` 编排占位，
   功能等价但旋转/折叠时机自己兜。若 4.2.1 落地后真机出现"展开瞬间副栏空白"，
   再迁 `SplitPlaceholderRule`；否则在 `ActivityEmbeddingInstaller` 顶部注释写明
   "不用官方 placeholder 规则的原因"（双引擎注册时机需自管），避免后人误改。
3. **`SplitPinRule` 评估**（window 1.5 新能力，可选）：分屏态把播放器栈
   pin 住（`SplitController.pinTopActivityStack`），保证副栏内一切跳转都留在副栏，
   不会把播放器顶走。现状靠副栏独立引擎+路由约束，若真机出现跳转把播放器
   挤掉的 case 再上 pin，不预防性引入。

### 4.3 真机验证清单

真机检查清单（平板 sw≥600dp + API≥32 设备；4.2.1 落地后折叠屏项必测）：
1. 全屏→分屏：定格帧无黑闪，副栏 DetailActivity 起的是新实例（日志
   `NativePlayerSplit`），播放不重载；
2. 分屏→全屏：副栏被 finish，播放器铺满重锁横屏；
3. 副栏内点其他集/其他媒体 → 经反向桥原地换源（确认 `applyLoadArgs` 走通）；
4. 分屏态弹幕遮罩暂挂生效（`syncOcclusionWithSplitState`），回全屏恢复；
5. 折叠屏/多窗口模式下 `splitSupported()` 返回 false 时按钮退化为旋转，无崩溃；
6. 进 PIP、回来、再分屏的状态机不乱（`isNativeSplitPlayerVisible` 标志复位）；
7. 手机（sw<600dp）：按钮 = 横竖屏切换；竖屏播放时控制栏布局不溢出（重点看
   底栏按钮挤压与面板宽度 `panelWidthPx` 在窄屏的表现）；
8. 折叠屏（若有设备）：半开态分割线落铰链（4.2.1）；展开↔折叠切换时播放不重载、
   分屏标志位不悬挂；折叠成外屏（宽度跌破阈值）时自动回全屏播放；
9. 小米/OPPO 平板（12L+）：系统侧不强行嵌入（ALLOW_SYSTEM_OVERRIDE=false 生效），
   应用自家分屏按钮工作正常；
10. 华为平板（若做了 4.1）：平行视界分栏生效、播放页全屏。

修缺原则：发现的问题逐个最小修复，每修一个真机复测，不做架构调整。

## Phase 5：解码 / HDR / 显示细节增强

在 `VideoOutputController` 现有管线上做增量，**不要推翻现有 HDR 自动回退逻辑**：

1. **tone-mapping 算法可选**：HDR 映射 SDR 时当前用 mpv 默认。`hdr_mode` 旁新增
   `tone_mapping` 设置（`auto`/`bt2390`/`mobius`/`hable`/`reinhard`），映射到 mpv
   `tone-mapping` 属性；只在色彩管线为 HDR_TONEMAP_SDR 时生效。
2. **Dolby Vision Profile 5 特判**：`MpvPlaybackModels.isHdrLikely` 已识别 DV，但
   P5（无 HDR10 兼容层）在多数设备 mediacodec 直出会绿紫屏。从轨道 profile 字符串
   判断疑似 DV 时，若设备无 DV 解码器（`MediaCodecList` 查 `dolby-vision` 类型），
   强制走 mediacodec-copy + tone-map 管线（复用现有 `forcedColorPipeline` 机制）。
3. **真刷新率切换**：原生壳目前只有 `Surface.setFrameRate`（软提示）。参考
   `PlayerActivity.kt:173` 的 `preferredDisplayModeId` 实现，在 `NativePlayerActivity`
   按视频 fps 选最接近的 display mode（24/25/30/50/60Hz 整数倍匹配），做成
   `video_misc` 开关（默认关，避免切换闪屏争议）；离开播放器恢复。
4. **解码诊断透出**：轨道信息页（`buildTrackInfoPage`）补充：实际 hwdec 状态
   （`hwdec-current` 属性）、色彩管线（直出 HDR/映射 SDR）、是否触发过自动回退
   （`VideoOutputController` 已记 fallbackReason，透出来）、丢帧数
   （`frame-drop-count`）。排查用户反馈全靠它。

## 执行顺序与公共约束

顺序：**Phase 4（真机验证，当前分支收尾）→ 1 → 3 → 2 → 5**。
Phase 4 先做是因为当前分支就是分屏分支，验完才能合主干；1/3 是体验硬缺口；
2/5 依赖真机外设（功放/HDR 屏），放后。

公共约束：
- 每个 Phase 独立分支独立提交，提交信息沿用现有风格（`feat(player): ...` 中文说明）；
- 新设置一律走 `NativePlayerSettingsStore` 白名单模式（defaults 里先声明 key）；
- 原生壳 UI 沿用现有 `panelSegment`/`panelSlider`/`panelCardGroup` 组件，不引新 UI 框架；
- 编译验证：PowerShell 关沙箱跑 `gradlew compileFullDebugKotlin`（见既往经验），
  Flutter 侧改动跑 `flutter analyze`；
- 涉及 mpv 属性的改动，在 `MpvAdvancedSettingsController` 集中收口，别散在 Activity 里；
- 所有"自动回退"逻辑参考现有指纹+日志钩子模式（`buildApplyFingerprint`、
  `maybeTriggerHdrHwdecFallback`），保持风格一致。
