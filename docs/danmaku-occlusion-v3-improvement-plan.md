# 弹幕 AI 遮罩与时间轴改进计划（v3）

> 交接对象：执行模型（Opus 4.8）。本文档自包含：先读 §1-§2 理解根因，再按 §3 的 Phase 顺序执行。
> 前置阅读（历史脉络，不必先改）：`docs/danmaku-occlusion-rework-plan.md`、
> `docs/danmaku-occlusion-planb-v2-plan.md`（其 Phase A/B/E 已落地，本计划接续其 Phase C/D 未完成部分）。
> 所有行号基于当前 `feat/media-item-action-abstraction` 分支，执行前先重新定位。

## 0. 用户反馈（原始症状）

1. **遮罩效果一般（本地 + 云端都一般）**：人物明明在画面里，弹幕一会儿压在人物上、一会儿又被遮罩
   擦掉，来回振荡。模型能力本身没问题（分割结果是准的），是链路把好结果用坏了。
2. **运动跟踪完全是负面加成**：开了"蒙版跟随运动"反而更差。
3. **弹幕时间轴与视频进度有出入**：弹幕呈现的时刻和视频画面对不上，**拖动进度条后尤其明显**。

三个症状不独立：**遮罩按 PTS 选帧用的就是弹幕时间轴**
（`NativeDanmakuOverlayView.drawOcclusionMask()` ~:3110 用 `currentTimelineMs()` 选 mask），
时间轴超前多少，mask 选取就偏多少。所以时间轴修复（Phase T）同时是遮罩修复的前置。

## 1. 现状架构速览

### 1.1 遮罩两条链路

| | 本地（Plan B v2） | 云端/NAS（live-capture） |
|---|---|---|
| 入口判定 | `planBActive()`（DanmakuDynamicOcclusion.kt ~:2830）：**只认 `file://` 或 `/` 开头** | 其余全部 |
| 生产 | `DanmakuMaskPrecomputePipeline`：独立线程 MediaCodec 提前解码，步长 140–960ms 自适应，mask 带视频 PTS | 采样器 500–1200ms（默认 800ms）PixelCopy 抓屏 → 推理，mask 描述**已播过去的帧** |
| 渲染 | PTS 缓冲 + floor/next 包夹双 mask 联合绘制（overlay ~:3127） | 单张最新 mask + wall-clock 全局速度外推（cap 600ms / 屏幕 8%，overlay ~:3160） |
| 后处理 | 生产端门控（前景比例 + 滞回）+ 防闪烁 carry | 8000+ 行启发式：tracker 生命周期 / small-multi 多目标 / mask 复用 / scale rescue / 歧义前景拒绝 / 降级 |

### 1.2 弹幕时间轴（NativeDanmakuOverlayView.kt）

弹幕有自己的自由轮转时钟：`timelineAnchorPositionMs + (now - timelineAnchorTimeNs) × speed`。
mpv `time-pos`（事件驱动，MpvPlaybackController.kt ~:2279）经播放线程→主线程送到
`updatePlaybackState()`（~:656），依次过：投影（~:1056）→ 延迟可靠性滤波（~:1076）→
稳定化（~:1003）→ 三选一（rebuild / reanchor / softSync，~:727-763）。
并存 **7 套守卫机制**：seek guard、playback floor guard、paused anchor guard、
continuity rebuild guard、soft-sync suppress、回退钳制（rollback clamp）、latency filter。

## 2. 根因诊断

### 2.1 时间轴：单向棘轮，只会超前、永不回拉（P0）

**这是"弹幕与进度有出入"的直接原因**，机制上是一个只进不退的棘轮：

1. **回退钳制吃掉一切负漂移**（`stabilizeIncomingPosition` ~:1011）：
   播放中只要 mpv 上报位置落后弹幕预测 >48ms（`POSITION_ROLLBACK_TOLERANCE_MS`），
   上报值直接被替换成预测值 → 稳定化后的 drift 恒 ≥ -48ms。
2. 于是 **负向 rebuild 阈值永远够不着**：`negativeDriftRequiresRebuild` 要求 drift < -160ms
   （~:745），但 drift 被钳到 -48ms 以内，播放状态下永不触发。
3. **软同步只往前修**（`softSyncTimeline` ~:1168）：`driftMs < 0f → return false`，注释明说
   "避免回拉"。
4. **暂停/恢复 reanchor 用的是漂移后的预测值**（~:730-732 `reanchorTimeline(predictedMs)`），
   不是 mpv 真实位置 → 暂停也洗不掉已积累的超前量。

超前从哪来：mpv 微卡顿（掉帧、缓存微停顿，不足以触发 buffering 事件）时弹幕时钟照走；
恢复后钳制阻止回拉 → 每次微卡顿都往棘轮里塞一点超前量，**整集只增不减**，直到下一次 seek。

**Seek 后更糟的原因**：`hintSeek()`（~:785）立刻按 UI 目标位置 rebuild；此后 seek guard
（容差 `SEEK_SETTLE_TOLERANCE_MS = 3000ms`，极宽）、floor guard（恢复播放时把地板设成
`max(lastKnown, predicted)` ~:702-707，即**弹幕自己的钟**）、continuity guard 三者叠加，
1.4–4.2 秒窗口内一律拒绝向下修正。期间任何一个乱序/迟到的 time-pos 样本（播放线程异步投递，
相位可能已翻回 PLAYING）都可能把时间轴顶到错误位置，然后被棘轮锁死。
（seek 本身是 `absolute+exact`，MpvPlaybackController.kt ~:2194，落点精度不是问题。）

另外 `applyPositionSampleLatencyFilter`（~:1076）在样本延迟 ≥42ms 时把样本可靠性打到 0、
完全信预测值——跨两个线程投递的样本延迟经常超 42ms，等于**常态性地偏袒那只会漂的自由时钟**。

### 2.2 本地 Plan B：闪烁 = 空步丢弃 + 硬门控 + 步长拉长（P1）

1. **空步不推送**（`emitPipelineStep` DanmakuDynamicOcclusion.kt ~:2884-2890）：
   生产端产出 `mask == null` 的步（无人/漏检/超上限）直接 return，不给渲染端。
   这是 planb-v2 计划里 Phase B/C 的"空步清除"**从未落地**。后果双向都坏：
   - 模型连续 2+ 步漏检（防抖 `EMPTY_DEBOUNCE_STEPS = 1` 只兜 1 步）→ 渲染端 floor mask
     悬空老化，到 `maskStaleMaxMs`（1.5×步长，overlay ~:518）后突然消失 → 弹幕压脸 →
     下一张成功 mask 到达 → 又被擦掉。**这就是"一会在人物上一会被遮罩"的主振荡源**。
   - 人物真离场时，旧 mask 还多挂 ~1.5×步长（残留）。
2. **前景比例门是硬开关**（`buildMask` DanmakuMaskPrecomputePipeline.kt ~:487-490）：
   ratio < 0.012 或 > 0.80(+0.06 滞回) → 整张 mask 直接 null。人物占比在门口徘徊时
   （走近/远离镜头、蹲下起身），滞回带（0.006 / 0.06）扛不住模型输出的逐步抖动 → mask 整张
   开/关翻转，和 1 叠加成可见闪烁。
3. **步长可拉到 960ms**（`STEP_MS_MAX`，慢机 512 宽推理 ~450ms → budget 退避），
   此时包夹"扫过带"很宽（过度擦除 = 弹幕大片消失）、stale 窗 1.44s，对齐质量塌方。
   降精度（输入宽度）这个更好的自由度没有参与预算调节——预算紧时只会拉步长。

### 2.3 运动跟踪为何负收益（P1，与 2.2 联动）

- **live 路径**：速度来自相隔 ~800ms 两帧的 48×27 全局 luma SAD——测的是**镜头**不是**人物**；
  渲染端再用它按 wall-clock 外推最多 600ms。速度旧 + 对象错 + 外推长，三重误差 →
  mask 被推到错误位置，比"原地不动"更差。用户的"负面加成"判断准确。
- **Plan B 路径**：包夹联合（floor ∪ next）本来就不依赖速度就能覆盖人物扫过带；
  floor 那张仍按质心速度外推（overlay ~:3135-3146），质心速度在转身/抬手等形变下有噪声，
  外推反而把 floor mask 推离人物，联合区域歪掉。**有 next 包夹时外推是纯多余的风险项**。

### 2.4 云端路径的结构性天花板（P1，机会最大的一项）

live-capture 的 mask 永远描述"已播过去的帧"，结构性滞后 = 采样间隔 + 抓屏 + 推理，怎么调参
都到不了"不滞后"。而事实是：

- `DanmakuFrameExtractor.open()` **已支持 http(s) URL + 自定义 headers**（~:42-52，
  注释明说"http(s) URLs (NAS proxy) that are seekable"）；
- NAS 播放本来就走本地代理（`NativeMpvProxyServer`），URL 形如 `http://127.0.0.1:<port>/…`；
- `planBActive()` 却只认 `file://` / `/`（~:2830-2835）。

**把 Plan B 放开到本地代理 URL，云端就直接获得与本地同等的 PTS 预计算遮罩**，live 路径连同它
8000 行启发式栈整体退役。这比继续给 live 路径调参收益大一个数量级。

## 3. 改进方案（按此顺序执行）

### Phase T — 时间轴对称化（P0，先做：它同时是遮罩对齐的前置）

**T1 抽出可单测的时钟类**
把 `NativeDanmakuOverlayView` 里的时间轴状态与逻辑（anchor、预测、稳定化、软同步、守卫）
抽成纯 Kotlin 类 `DanmakuTimelineClock`（无 View/Handler 依赖，时间由参数注入），View 持有实例。
仓库已有 JVM 测试先例（`android/app/src/test/.../NativePlayerActivityPanelModelsTest.kt`），
新增 `DanmakuTimelineClockTest`。**先抽取、行为不变、测试锁定现状，再做 T2/T3。**

**T2 对称纠偏，废除棘轮**
- 回退钳制（~:1011-1016）只保留在显式守卫窗口内（seek/恢复播放后的短窗），常态播放删除。
- `softSyncTimeline` 允许负向：小负漂移（-160ms < drift < -死区）以同样的小步长回拉。
  滚动弹幕表现为速度微调，不可见跳变；顶部/底部弹幕的到期时间随时间轴走，同样平滑。
- 恢复负向 rebuild：drift < -500ms（放宽阈值，避免误杀）→ rebuild 到上报位置。
- 暂停时 reanchor 用**上报位置**而非预测值（改 ~:697 与 ~:730-732 两处的取值）。
- `applyPositionSampleLatencyFilter` 的 0 可靠性阈值 42ms 放宽（建议 120ms），或改为
  "延迟只衰减权重、不衰减到 0"——不许它把真实样本整个丢掉。

**T3 Seek 收敛：等权威样本，不猜**
- `hintSeek()`：清屏 + 进入 `SeekHold` 状态（冻结时间轴、清 mask PTS 缓冲——后者现状已做）。
- 退出 `SeekHold` 的唯一条件：seek 完成后第一个 PLAYING 相位的 time-pos 样本
  （mpv `seeking` 属性翻 false 后，见 MpvPlaybackController ~:2255 `onSeekingChanged`），
  在该样本处一次性 rebuild。删除 `SEEK_SETTLE_TOLERANCE_MS=3000` 的"差不多就算到了"逻辑。
- 7 套守卫收敛为一个显式状态机：`Playing / Paused / SeekHold / ResumeSettle`，
  每个状态写清进入/退出条件与允许的纠偏方向，全部进 `DanmakuTimelineClock` 单测。

**T4 漂移可观测性（验收依赖）**
`recordPlaybackSyncStats` 已有统计骨架（~:765），补一条周期日志（复用 `FlyPlayerDanmaku` tag，
VERBOSE 门控，真机 `setprop log.tag.FlyPlayerDanmaku VERBOSE` 开启）：
输出 raw drift / stabilized drift / rebuild·reanchor·softsync 计数。验收看它。

### Phase N — Plan B 放开到网络源（P1，云端质量的决定性一步）

1. `planBActive()` / `currentLocalDecodePath()` 增加：`http://127.0.0.1` / `http://localhost`
   的代理 URL 也返回可解码路径（含必要 query/headers 透传；`DanmakuFrameExtractor.open`
   的 headers 参数已存在）。
2. **先验证再放开**：`NativeMpvProxyServer` 必须支持 Range/seek 语义（MediaExtractor 的
   http 数据源靠 Range 实现 `seekTo`）。写一个小的 instrumented/手动验证步骤：对代理 URL
   `extractFrameAt(60s)` 能在合理时间返回正确帧。不支持 Range 就先补代理，再放开。
3. 失败自动回退：`extractor.open()` 失败或首帧超时 → 记日志、本源标记不可用，回落 live 路径
   （现状行为），**不能让遮罩整体失效**。
4. 带宽/负载守卫：第二路解码对远端流意味着第二份读放大——若代理无共享缓存，加设置开关
   （默认开，弱网用户可关）。注意 UI 文案走 arb/l10n，不写死中文。
5. Emby/fnos 源注意鉴权 headers（entry-token cookie 注入已在 HTTP 层做过，代理转发时应已带上；
   验证一集 Emby 源）。

### Phase L — Plan B 打磨：消灭振荡（P1，与 N 并行安全）

**L1 空步推送（planb-v2 Phase B/C 的欠账，最优先）**
`emitPipelineStep` 不再丢弃 `mask == null` 的步：推一条带 PTS 的"清除步"到 overlay，
渲染端把它入 PTS 缓冲（`MaskFrame.bitmap` 可空化或加 `empty` 标记）。floor 选取命中空步 →
该时刻自然无遮罩。效果：
- 人物离场：mask 在**正确的 PTS** 消失，不再靠 stale 窗残留 ~1.5×步长；
- 模型漏检：漏检步与成功步在时间轴上无缝衔接，不再出现"悬空老化→突然消失→突然回来"的振荡。
同时把 `EMPTY_DEBOUNCE_STEPS` 1 → 2（连续 2 空步才认"真离场"），配合空步推送，
漏检兜底与离场时效两头都稳。

**L2 门控软化（防整张翻转）**
`buildMask` 的 min/max 硬门改为"确认计数"：越过门限需连续 2 步才翻转状态（进一步的时间滞回），
滞回带不变。**不要做 alpha 渐隐**——部分 alpha = 部分擦除 = 弹幕半透明压痕，历史已踩坑
（见 planb-v2 E1 的告诫），mask 只能全有/全无，软化只能发生在时间维度。

**L3 外推退役（对应"运动跟踪负加成"）**
- Plan B：有 next 包夹时 floor 一律零外推（`drawOcclusionMask` ~:3135 处，`unionDrawn` 成立
  则 offX/offY = 0）；仅缓冲尽头（无 next）保留质心外推，且 cap 从"一个步长"收到 150ms。
- live 路径：`motionTrackingEnabled` 默认值 true → false（DanmakuDynamicOcclusion.kt ~:543，
  Flutter 侧设置默认值同步改）。Phase N 落地后 live 只剩兜底地位，外推整段可删。

**L4 预算优先降精度、后拉步长**
`adaptStep`（DanmakuMaskPrecomputePipeline.kt ~:444）现在预算紧只会拉长步长。改为两级：
budgetEma 超过阈值先把推理输入宽度降一档（512→384→320，运行时已支持不同输入宽），
仍不够再拉步长；`STEP_MS_MAX` 960 → 640。原则：**密而糙的 mask 优于稀而精的 mask**
（包夹带宽 ∝ 步长，步长才是观感第一变量）。

### Phase R — live 路径退役瘦身（P2，Phase N 真机验证通过后再做）

Phase N 覆盖本地 + NAS 代理后，live-capture 只剩"真不可 seek 的源"。届时：
1. 删除 tracker 生命周期 / small-multi 多目标 / mask 复用调整 / scale rescue / 歧义前景拒绝
   （DanmakuDynamicOcclusion.kt 中标注对应私有函数群，粗估 4000+ 行），live 简化为
   "全帧分割 + 最新 mask + 无外推 + 降级保护"。
2. 该文件 8420 行拆分：controller 骨架 / live 采样 / Plan B 桥接 三个文件。
3. **必须先真机确认 N 的覆盖面**（用户验证），再动删除；每步独立提交可回滚。

## 4. 验收标准

**时间轴（Phase T）**
- `DanmakuTimelineClockTest` 覆盖：微卡顿后回拉、seek 后一次 rebuild 收敛、暂停/恢复零漂移、
  乱序迟到样本不破坏时间轴。
- 真机：播放 20 分钟含 10 次随机拖动进度条，T4 日志 stabilized drift p95 < 80ms，
  且分布**双侧**（有负有正——证明棘轮已死）。
- 主观：拖动进度条后弹幕内容与画面时刻对上（找一条吐槽具体画面的弹幕对照）。

**遮罩（Phase N/L）**
- 连续镜头内人物始终在画：mask 开/关翻转次数 ≤ 现状的 1/5（数 `planb2 draw` 日志里
  floor 空/非空的翻转）。
- 人物离场：残留 ≤ 1 个步长；弹幕压脸窗口 ≤ 1 个步长。
- 云端 NAS 源走 Plan B 后：`dErr`（floor 选取滞后）分布与本地同量级；主观上无"mask 拖在人物
  身后"。
- 运动镜头：关闭外推后无"mask 飞出人物"现象；包夹带宽随 L4 步长收紧可见变窄。

**通用**
- `cd android && ./gradlew compileFullDebugKotlin` 通过；`flutter analyze` 通过（若动了 Dart 设置层）。
- 每个 Phase 独立提交；真机验证由用户做，提交信息里写明验证方法。

## 5. 执行注意

1. **顺序就是优先级**：T → N/L（可并行）→ R。T 不做完，遮罩对齐的观感改善会被时间轴漂移吃掉。
2. 改渲染/时序参数时保留旧常量注释（这些数字都是真机调出来的，回退要有据可查）。
3. `OCCLUSION_DEBUG_LOG`（overlay ~:232）当前硬编码 true——顺手改成 `Log.isLoggable` 门控，
   别让日志本身影响帧预算。
4. 弹幕设置若新增开关（网络 Plan B、外推），文案一律走 arb/AppLocalizations，禁止硬编码中文、
   禁止 `_t()` 间接层。
5. 大文件（DanmakuDynamicOcclusion.kt 8420 行）编辑前用 grep 重新定位行号，本文行号会漂。
