# 弹幕 AI 遮罩 Plan B v2 —— 生产者流水线重构计划

> 交接对象：执行模型（Opus 4.8）。本文档自包含：先读"现状诊断"理解为什么改，再按 Phase 顺序执行。
> 前置阅读：`docs/danmaku-occlusion-rework-plan.md`（历史脉络），本文件覆盖其 "Plan B" 章节的下一步。

## 0. 现状诊断（为什么延迟 / 残留 / 跟踪三个问题一直修不掉）

当前代码已经走到 Plan B 的 B1 阶段：本地文件用第二个 MediaCodec 解码"未来帧"→ 分割 → mask 按 PTS
缓冲 → 渲染时按播放进度选取。方向是对的，**但 B1 是寄生在旧实时采样器上的半成品**，三个症状都能
归因到这个架构错位：

### 0.1 延迟出现：mask 密度太低 + 生产节奏被旧调度器绑死

- `DanmakuDynamicOcclusion.captureFrameAndInfer()`（~:2519）里 Plan B 仍然走
  `scheduleNextSample()` → `currentSampleIntervalMs()`（~:8450）的节奏：**每个采样周期只产出一张
  mask**，间隔由 `averageLatencyMs` 退避公式决定（实测 450–700ms，慢机更长）。
- 也就是说 PTS 缓冲里 mask 密度 ≈ 1 张 / 0.5–0.7 秒。24fps 视频里相邻 mask 隔 12–17 帧，
  渲染端 `selectMaskForTimeline()`（NativeDanmakuOverlayView.kt ~:502）选"绝对值最近"的一张，
  对齐误差可达 ±350ms，`maskStaleMaxMs=1100ms` 的容忍又把更糟的也放进来。
- 每个周期 `runPlanBPrecompute()`（~:2898）独立调 `extractFrameAt()`，目标间隔 >1s 就重新
  seek+flush，否则顺序磨帧追进度——**每次只取一帧就丢弃解码器的连续性**，纯浪费。
- `shouldSample()`（~:1625）要求 `hasDanmakuOnScreen`：弹幕刚滚到人物脸上时才开始第一次采样，
  首张 mask 天然晚 ~1s。
- 网络源走 live-capture（PixelCopy）路径：mask 描述的是"已经播过去的帧"，结构性滞后 =
  采样间隔 + CPU 推理 130–460ms，这条路径怎么调参都到不了"不延迟"。

### 0.2 遮罩残留：三个"保旧 mask"机制叠加

- **mask grace**：`applyEmptyResult()` → `tryHoldPreviousMaskAfterEmptyResult()`（~:8074）空结果后
  按 `DANMAKU_AI_EMPTY_RESULT_GRACE_MS` 保留旧 mask。防闪烁的本意没错，但场景切换瞬间 = 旧 mask
  糊在新画面上。scene-cut 检测要等**下一次采样**才触发，期间残留一整个采样间隔。
- **static-skip 误判**：`runMnnFullFrameInference()`（~:3031）用 48×27 luma 网格的
  **全图平均**亮度差 `< DANMAKU_AI_STATIC_SKIP_LUMA_DIFF(3.2)` 判静止，最多连跳 8 次。
  小角色在大背景里移动时全图平均差远小于 3.2 → 被误判静止 → mask 冻结。
  **这同时就是"小幅运动跟不上"的直接原因**（和历史上 PP-HumanSeg 时代的同类抱怨一脉相承）。
- **PTS 选取过松**：nearest + 1100ms staleness 容忍，允许画一张实际属于 1 秒外画面的 mask。

### 0.3 运动追踪：全局平移模型在错误的时间尺度上工作

- 只有一个全局位移估计（`estimateGlobalShift()`，48×27 SAD ±6），没有逐对象运动——这是已知近似。
- 更糟的是时间尺度：速度来自相隔 0.5–0.7s 的两帧，等渲染端用它外推时已经旧了；
  外推又被 cap 在 600ms / 8%（overlay ~:464），被迫扛 700ms 的采样间隙 → 两头不靠。
- **正确解法不是把外推做强，而是把 mask 密度提上去**：步长 ≤300ms 时，外推只需填 ≤300ms 的缝，
  全局平移近似在这个尺度上是够用的。

### 0.4 结论

旧实时路径的所有补偿机制（latency 退避、grace、static-skip、wall-clock 外推、scene-cut burst、
degradation）都是在"mask 又慢又稀"前提下长出来的。Plan B 把推理移出了实时路径，但生产端还在用
旧节奏。**本计划 = 把生产者拆成独立流水线，把密度提到每 240–320ms 一张，然后让渲染端的补偿机制
全面退役（PTS 模式下）。**

## 1. 目标架构

```
┌────────────────────────── 生产者（独立 HandlerThread，后台优先级） ──────────────────────────┐
│ DanmakuMaskPrecomputePipeline（新文件，从 DanmakuDynamicOcclusion 拆出）                      │
│                                                                                              │
│  MediaCodec 顺序解码（永不为追进度反复 seek）                                                  │
│    └→ 每解出一帧：PTS 命中步长网格(240–320ms)？                                               │
│         ├ 否 → releaseOutputBuffer 丢弃（不做 YUV 转换）                                      │
│         └ 是 → YUV→RGB(384) → 静止判定                                                       │
│                  ├ 近似静止 → 复用上一张 mask，仅打新 PTS（零推理成本，密度不降）                │
│                  └ 有变化 → MnnImageSegmenter.run() → mask                                   │
│              同时算相邻步长帧的 luma 位移 → 随 mask 存 per-step velocity + sceneCut 标记       │
│                                                                                              │
│  节奏控制：缓冲覆盖到 pos + AHEAD_MAX(≈2.5s) 就 idle；播放推进消耗后唤醒继续生产                 │
│  边界：seek→清缓冲+重新 prime；pause→缓冲填满后停；倍速→窗口×speed；切集→close                  │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
                          │ (PTS, maskBitmap, velocity, sceneCut)
                          ▼
┌────────────────────────── 消费者（渲染线程，NativeDanmakuOverlayView） ───────────────────────┐
│  每帧 draw：取 PTS ≤ t 的最近一张（不用"绝对值最近"，避免未来 mask 提前遮挡）                    │
│            按该 mask 自带 velocity × (t - pts) 平移，t - pts ≤ 步长，外推量天然小              │
│            mask 带 sceneCut 标记 → 不跨界外推                                                 │
│            staleness 收紧到 ~1.5×步长；超出宁可不画                                            │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
```

关键转变：**采样器（mainHandler 定时器 + 退避 + grace + static-skip）在 Plan B 模式下整体不再参与**；
它只服务网络源的 live-capture 回退路径。

## 2. 分阶段执行

> 执行状态（2026-06，Opus 4.8）：**Phase A ✅ + Phase B ✅ 已真机验证通过并提交**(commit 39b01a4)。
> **渲染防碎片(rework-plan Phase 3) ✅ 已写并编译，待真机**：NativeDanmakuOverlayView 按每条弹幕与蒙版重叠比例分组——
> 重叠 ≥ `occlusionDrawWholeRatio`(0.55) 的整条在蒙版 DST_OUT 之后再画(不镂空,避免碎片);其余照旧镂空。
> 同时把蒙版 alpha 全不透明点对齐到前景阈值 0.5(MASK_EDGE_HIGH 0.55→0.50),修宽弹幕跨人物时低置信区(浅发/背面)的半透明残留。
> **运动跟随已修**：本地(Plan B)永远按帧短程外推跟随(渲染端封顶一个步长不漂移);"蒙版跟随运动"开关只 gate 网络源。
> 真机反馈(A/B)：人物中心半透明残留仍在(默认 motionTracking 关→外推没生效是主因之一,已修)。
> 以下为 A/B 原始计划记录——
>
> ~~执行状态：Phase A+B 已写并编译通过，未真机验证。~~
> Phase C 的核心（PTS 模式不再走旧 grace/static-skip/degradation）已由 A 的路由天然达成（流水线路径根本不进 `runInference`/`applyEmptyResult`）。
> **本轮主动推迟**（理由见下）：① 显式"空 MaskStep"PTS 样本 ② live(网络/NAS)路径 static-skip 改 max-cell-diff ③ Phase D 死代码清理。
> - ①：经现有 `setOcclusionState(state,bitmap)` 通道推空样本会触发 `applyOcclusionState`→`scheduleMaskClear`→`clearMaskPtsBuffer` 把整个 PTS 缓冲清空（NativeDanmakuOverlayView ~:951/3208），盲改有缓冲被误清风险。Phase B 收紧的 staleness(≈1.5×步长≈420ms)已把残留从旧 1100ms+grace 降下来，①是从 420→280ms 的细化，待真机验证后再做。
> - ②：live-capture 是 **NAS http 流**的主路径（本 App 核心场景）；把 static-skip 从 frame-mean 改成 cell-count 会提高网络播放推理频率→热/卡风险，盲改不稳，待真机。
> - ③：用户已明确"推迟到真机验证后"。

### Phase A — 生产者流水线（核心，新文件 `DanmakuMaskPrecomputePipeline.kt`）✅

放在 `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/mpv/`。

实现要点：自带后台 `HandlerThread`(THREAD_PRIORITY_BACKGROUND)；自持 `DanmakuFrameExtractor`+seg runtime(工厂直建 PADDLE 档，lite 工厂 shouldAttempt=false→干净不启动)；
顺序 `extractFrameAt` 拉流(复用其只转换命中帧、forward-decode 不重 seek 的特性)；step 网格 280ms(自适应到 480)；AHEAD_MAX 2500ms×speed 封顶后 idle；
static 复用判据 = **max-cell-diff/changed-cell-count**(修 0.2 均值误判根因)；per-step velocity(estimateGlobalShift/步长) + sceneCut(均值大跳)；
每步 onStep→主线程 `emitPipelineStep` 走现有 state 通道下发(maskPtsMs/velocity/sceneCut/aspect)。`evaluateSamplingState` 里 planBActive→停旧采样环、`ensurePrecomputePipeline().start()`。
旧 `runPlanBPrecompute` 对本地源已成 dead code(Phase D 删)。`MpvPlaybackController` 加 `playbackSpeedProvider={state.speed}`。

1. **持有**：`DanmakuFrameExtractor`（改造，见下）、seg runtime（经现有
   `DanmakuSegmentationRuntimeFactory`）、自己的 `HandlerThread`
   （`Process.THREAD_PRIORITY_BACKGROUND`，不在延迟路径上，慢点无所谓，但绝不能抢 UI/解码核）。
2. **改造 `DanmakuFrameExtractor`**：从"extractFrameAt 单帧请求"改为**连续生产模式**——
   `decodeNext(stepUs): Frame?` 顺序拉流，内部只在外部 seek 时 flush；非步长命中的输出 buffer
   直接 release，不做 YUV 转换（YUV→RGB 是纯 Kotlin 循环，只对命中帧做）。现有
   anti-spiral/FORCE_SEEK 逻辑保留为兜底。
3. **环形缓冲**：`ArrayDeque<MaskStep>`，`MaskStep(ptsMs, mask: Bitmap?, vxPerMs, vyPerMs,
   sceneCut: Boolean)`。`mask == null` 表示该步长点判空（无人物/超上限），渲染端画空——
   **空也是一个明确的 PTS 样本**，这让"该不该清 mask"不再需要 grace 猜测。
4. **静止复用**：用 `sampleMotionLumaGrid` 比较相邻步长帧，判据改为
   **max-cell-diff 或 changed-cell-count**（不是全图均值！修 0.2 的误判根因），近似静止时复制上一
   张 mask 引用、只打新 PTS。静态对话场景的推理成本趋近 0，密度不降。
5. **velocity / sceneCut**：相邻步长帧的 `estimateGlobalShift`（现成函数搬过来）除以步长 →
   per-step velocity 存进 MaskStep；位移搜索失败 + luma 差异巨大 → `sceneCut = true`。
6. **节奏**：生产到缓冲覆盖 `pos + AHEAD_MAX(2500ms)` 即 wait；消费侧（播放进度回调）推进后
   notify。初始 prime：从 `pos + 300ms` 的前一个关键帧 seek 起步。
7. **边界处理**（即原 B4）：
   - seek：清缓冲 → extractor.seekTo → 重新 prime。复用现有 `hintSeek` 通知链。
   - pause：缓冲填满后线程自然 idle，无需特殊处理；恢复播放即被唤醒。
   - 倍速：`AHEAD_MAX × speed`，步长不变（mask 是按视频时间轴的）。
   - 切集/换源：close + 重建（沿用 `ensureFrameExtractor` 的 URL 比对逻辑）。
8. **门控**：`planBActive()` 判定不变（仅本地文件）；但**去掉 `hasDanmakuOnScreen` 对生产的门控**
   ——`sourceLoaded && config.enabled` 即开始 prime（有 AHEAD_MAX 封顶，空转成本固定且小）。
   live-capture 路径的门控保持原样。
9. **预算自适应**：步长初始 280ms；若单步"解码+转换+推理"耗时 EMA > 步长×0.8，步长×1.25 退避
   （上限 480ms），恢复快时回落。这替代旧的全套 latency 退避机制。

### Phase B — 渲染端：包夹选取 + 短程外推（`NativeDanmakuOverlayView.kt`）✅

实现：`MaskFrame` 增 `vxPerMs/vyPerMs/sceneCut/stepMs`；`selectMaskForTimeline` 改 **floor**(PTS≤t 的最新一张，全为未来则 null)；
`maskStaleMaxMs` 改 var、每次 push 设为 `步长×1.5`(下限 360ms)；draw 在 ptsMaskMode 下用**该帧自带 velocity**外推、extrapMs=`(t-pts).coerceIn(0,步长)`(天然不跨 cut，sceneCut 帧 velocity=0)，
wall-clock 外推分支仅 live 路径保留；state 加 `maskSceneCut` 字段串起来。
> 注：①显式空 PTS 样本(MaskFrame.bitmap 可空)未做，见顶部推迟说明。

1. `selectMaskForTimeline` 改为 **floor 选取**（PTS ≤ t 的最近一张）；下一张存在时可用
   `(t - pts) / step` 做位置外推（用 MaskStep 自带 velocity，而不是 controller 推过来的旧全局速度）。
2. `maskStaleMaxMs` 从 1100ms 收紧到 `步长 × 1.5`（动态，随 state 下发）。
3. PTS 模式下**删除** wall-clock 外推（`maskAnchorUptimeMs` 分支）和 controller 侧 velocity 的消费；
   这两者只为 live-capture 路径保留。
4. sceneCut 标记的 MaskStep：选取它时外推量强制 0；它之前的 mask 不允许外推跨过它的 PTS。
5. 数据通道：现有 `setOcclusionState(state, runtimeMaskBitmap)` 一次推一张的模式保留可用
   （生产者每完成一步推一次），`maskPtsBuffer` 结构升级为带 velocity/sceneCut 字段。
   注意现有 `pushMaskFrame` 每次 `Bitmap.copy`——384² ARGB ≈ 0.6MB/张，cap 12 ≈ 7MB，可接受，
   但生产者侧已经为每步分配新 bitmap 的话，渲染端可以直接持有引用 + 明确所有权（推荐：
   controller 不再 recycle 推出去的 bitmap，所有权移交 overlay，省一次 copy）。

### Phase C — 旧机制退役与 live 路径小修

1. PTS 模式下不再走 `applyEmptyResult`/mask grace/static-skip/degradation/scene-cut burst——
   生产者推"空 MaskStep"天然表达"此刻无遮罩"。`DanmakuDynamicOcclusion` 里这些机制保留给
   live-capture 路径，但用 `planBActive()` 短路。
2. live 路径顺手修 static-skip 判据（同 Phase A.4 的 max-cell-diff），网络源的"冻结/残留"也会缓解。
3. `latestMaskPtsMs` 在 `runPlanBPrecompute` 失败路径上的残值问题随旧函数删除一并消失
   （Phase A 后 `runPlanBPrecompute` 整体废弃）。

### Phase D — 验证、质量回升、清理

1. **可观测性**（验收依赖此项，先做）：logcat 周期汇总
   `planb2 step=?ms produced=? reused=? empty=? segMs(p50/p95) drawPtsErr(p50/p95) bufferAheadMs=?`。
   渲染端统计每次 draw 的 `t - selectedPts` 分布。
2. **验收标准**：
   - drawPtsErr p95 ≤ 步长（即 mask 总是"当前或 ≤1 步之前"的）。
   - 场景切换：旧 mask 残留 ≤ 1 个步长（主观上"切镜头瞬间糊脸"消失）。
   - 平移镜头：mask 跟手（外推缝隙 ≤ 步长，全局平移近似足够）。
   - 弹幕帧率：与关闭 AI 遮罩相比无可感知掉帧（生产线程后台优先级 + 解码不抢 mpv 的验证点）。
   - 编译验证：`gradlew compileFullDebugKotlin`（PowerShell、关沙箱）；真机验证由用户做。
3. **质量回升**（原 B5）：流水线稳定后实测预算，富余则输入 384→512（推理 ~2 倍），或步长收到
   240ms。一次只动一个变量。
4. **清理**（原 Phase 4，此时才安全）：删 `DanmakuDynamicOcclusion.kt` 中旧检测路径死代码
   （PicoDet/small-multi/tracking/补丁常量，7950 行 → 预计减半）、`runPlanBPrecompute`、
   旧外推字段。渲染防碎片（逐条弹幕遮挡比例，原 Phase 3）作为独立后续，不混入本次。

### Phase E — 本地(Plan B)遮罩与人物时差修复（包夹双 mask）

> 背景：A+B 真机后用户反馈——本地预计算路径整体可用，但**运动较多的人物出现"mask 拖在人物身后"
> 的时差感**。根因诊断（按贡献排序）：
> 1. **floor 选取天然滞后 0~1 个步长**（280ms，退避后最长 480ms）：画的永远是"过去那张"。
> 2. **外推速度测的是相机不是人物**：per-step velocity 来自整帧 48×27 luma 全局 SAD
>    （`DanmakuMaskPrecomputePipeline.estimateVelocity`），背景像素占绝对多数——
>    人物动/镜头不动时速度≈0，外推完全不工作，偏差 = 整个步长。
> 3. 外推只能平移；抬手/转身/趋近镜头等形变，平移补不了。
> 4. **预计算的根本优势没用上**：当前时刻 t 被缓冲里的 mask(t0) 和 mask(t1) 包夹着
>    （t1 的"未来 mask"已经存在！），不需要预测，可以包夹。

执行顺序 E0 → E1 → 真机 → E2 → 真机 → 决定 E3。每步独立提交。

**E0 — 先排查系统性偏置（10 分钟检查，执行 E1 前做）**
overlay 的 `timelineMs` 是弹幕时间轴（对 mpv position 做过 soft-sync 平滑），若它相对真实视频
PTS 有恒定 lead/lag，floor 选取会放大感知偏差。加临时 debug 日志对比 `currentTimelineMs` 与
mpv `time-pos`×1000；恒差 >80ms 则在 mask 选取处加常量补偿。（E1 的包夹同时也能吸收小偏置，
此项只为排除"全是 bias 造成"的可能。）

**E1 — 渲染端包夹联合绘制（核心，改 `NativeDanmakuOverlayView.kt`）**
1. `selectMaskForTimeline` 升级为返回 **bracket 对**：floor 帧 + 缓冲中它的下一帧（若存在）。
2. draw：先按现状画 floor mask（含外推）；若 next 满足
   `next.sceneCut == false && next.bitmap !== floor.bitmap`（静止复用是同一引用 → 自动跳过）
   → **以同样的 DST_OUT、全 alpha 再画一张 next mask**。
   - **不要做加权 cross-fade**：部分 alpha = 部分擦除 = 弹幕半透明压痕，这个坑历史上已踩过
     （"人物中心半透明残留"），联合必须两张都全 alpha。
   - next mask 不做外推（它本身就是"未来位置"）。
3. 效果：两张 mask 的并集覆盖人物从 t0→t1 扫过的区域，人物任意时刻都在并集内 → 时差观感消失，
   且**不依赖任何速度估计的准确性**。
4. 代价：运动瞬间擦除区域变大（弹幕在人物运动轨迹带上被多擦一点）。与"宁可保人物"的既有产品
   取向一致；静止场景因引用复用完全零开销、零变化。

**E2 — 运动自适应步长收缩（生产端，`DanmakuMaskPrecomputePipeline.kt`）**
现状步长只会 280→480 退避，永不收缩到 280 以下。增加：相邻步长帧的 changed-cell-count
（静止判定的同一份数据，反向用）超过阈值 → 下一步步长减半（下限 140ms），运动平息后回落 280。
联合遮罩"扫过带"宽度 ∝ 步长×人物速度，步长越小带越窄、包夹越贴身。预算依旧由静止复用 +
现有 stepBudgetEma 退避兜底（运动镜头多花的推理，静止镜头省回来）；推理耗时跟不上时
budget 退避优先级高于运动收缩。

**E3 —（可选，E1/E2 真机后再决定）人物质心速度替代相机速度**
生产端对相邻两步 mask 的**前景质心**算位移（前景统计在 `buildFullFrameMaskResult` 同款循环里
顺带可得），velocity 改用 Δ质心/步长 → floor 外推从"跟相机"变"跟人物"。
防抖：前景占比相邻两步变化 >30%（人物进出画面/多人变动）时速度置零。
若 E1 包夹后观感已达标，E3 不做——包夹不依赖速度，质心法只是让 floor 那张画得更准一点。

**验收**
- 人物快速移动：mask 不再拖尾/时差感消失（核心主观指标）。
- 静止对话：与现状零差异（union 不触发）。
- 运动瞬间擦除面积略增：预期内，不算回归。
- 新增日志：`planb2 draw union=?%`（union 实际触发占比）+ 保留 drawPtsErr。
- 编译 `gradlew compileFullDebugKotlin`；真机验证由用户做。

## 3. 风险与对策

| 风险 | 对策 |
|---|---|
| 第二 HW 解码器与 mpv 争抢（SoC 并发解码上限） | 顺序解码对解码器远比反复 seek 友好（B1 的磨帧/anti-spiral 主要是 seek 模式造成的）。仍卡 → 改软解：`MediaCodecList` 选 `software` 解码器，384 输出软解完全够用且不占 HW 会话 |
| CPU 预算：~3.5 张/s × ~130ms(384, 2线程) ≈ 0.9 核 | 静止复用把实际推理次数砍到远低于步长密度（对话/静止镜头占大头）；再超预算走步长退避；线程后台优先级保证只偷闲核 |
| 步长网格命中判定在 VFR / 非常规帧率源上漂移 | 命中条件用 `ptsUs >= nextStepUs` 而非等值匹配，命中后 `nextStepUs += stepUs` |
| seek 风暴（用户拖进度条连续 seek） | prime 加 150ms 防抖；seek guard 期间不生产 |
| 内存：缓冲 bitmap | cap 12 张 × 0.6MB ≈ 7MB；所有权移交后无双份 |
| 网络源无改善 | 本期明确不动（live 路径维持现状 + static-skip 判据小修）。后续可选：对 NAS 代理源试顺序预读（顺序读不放大带宽，B1 否决网络源的依据是 seek 模式下 1.5–2.5s/帧，不适用于顺序模式，值得重测） |

## 4. 执行注意（给执行模型）

- **不要在 `DanmakuDynamicOcclusion.kt` 里继续堆代码**。生产者流水线必须是新文件；该文件已 7950 行，
  本计划是它瘦身的开始，不是继续生长的理由。
- 改动顺序严格 A → B → C → D。A 完成后即可编译 + 真机看效果（B 之前渲染端仍用 nearest 选取，
  仅密度提升就应有可见改善），每个 Phase 一个提交。
- 所有新常量集中放流水线文件顶部，**不要**散进 `DanmakuDynamicOcclusion.kt` 的常量海里。
- `MnnImageSegmenter` / `MnnSegNative` / `DanmakuSegmentationRuntimeFactory`（src/full 与 lite 替身）
  接口不动；lite flavor 没有 MNN，流水线在 runtime 创建失败时必须干净地不启动（行为 = 现状）。
- 编译验证命令与环境见 memory/`native-shell-build-verify`：PowerShell + 关沙箱跑
  `./gradlew compileFullDebugKotlin`。真机验证由用户负责，提交信息里列出验证点。
