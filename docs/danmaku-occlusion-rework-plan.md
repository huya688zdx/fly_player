# 弹幕动态遮罩重做计划

分支：`feat/danmaku-occlusion-seg-rework`

## 背景与已验证结论（2026-06）

旧实现（`DanmakuDynamicOcclusion.kt`，7950 行）用 `PP-HumanSeg v2 Lite`（单前景人像，256×144）+ PicoDet 检测 + small-multi，
配 ~150 个调参常量和几十个形状修补函数。问题：动漫分不了、多人差、小幅运动跟不上、精度糙。

**已用数据否掉的方向：**
- GPU/NPU 加速旧模型 = 死路。旧分割前向仅 ~8ms（天玑9200 CPU），OpenCL 崩溃；瓶颈在管线后处理不在推理。
  现有 FastDeploy AAR 的 JNI 把后端焊死在 ARM CPU，Java 无 GPU/NNAPI 开关。

**已验证可行的方向（PoC，桌面 onnxruntime）：**
- 双模型**语义分割**（非 SOD、非实例分割），按内容路由：
  - 动漫：**ISNet-anime**（skytnt/anime-seg）。只遮角色、不遮风景/物体（纯风景图 mask 全黑），多人全覆盖，轮廓"色块级"。
  - 真人：**u2net_human_seg**。
  - 交叉不通，必须按动漫/真人选模型。
  - 纯 SOD 已否决（会遮车/风景等非人显著物，用户反对）。
- 性能/尺寸拐点（桌面 4 线程 CPU，从 ckpt 重导出小尺寸 onnx）：
  - **512：~250ms，多人 OK ← 多人质量底线**
  - 320：~105ms，多人崩坏；256：~65ms，多人崩坏（仅单大角色可用）
  - ISNetDIS 用 `_upsample_like` 尺寸无关，可任意 32 倍数尺寸重导出。

## 架构决策

不再"整图丢大模型全遮"，改为分层 + 选择性：

1. **定位层**：低分辨率粗筛（ISNet-256，~65ms）整图过一遍，只为定位人物区域（连通域）+ 大小。
   顺带解决动漫无检测器问题（复用同模型粗筛，不需 PicoDet）。
2. **分割层**：只对"值得遮"的 ROI 精修（裁出放大→提升小目标分辨率）。ROI 精修是为质量/选择性，不是省单次算力。
3. **策略层（产品规则已定）**：
   - 多人**按大小过滤**：只遮面积在"有意义区间"的人；太大跳过、极小碎片跳过。
   - 大特写：见渲染层。
4. **渲染层防碎片（产品规则已定）**：把现在的全局 `PorterDuff.DST_OUT`（NativeDanmakuOverlayView.kt:361/2925）
   改成**逐条弹幕**评估遮挡比例——适中镂空保护人物，过高则整条照画（宁可完整压脸，不要切成碎片）。

逐帧成本 = 1 次粗筛 + 偶尔 N 次 ROI（N 通常 0-2，过滤后）+ 多数帧靠跟踪复用不重算。

## 分阶段

- **Phase 0 — 真机性能闸门（生死）✅ 已通过（双旗舰，MNN 3.5.0 fp16，含 GPU readback）：**
  - ISNet-anime 512 GPU：高通 Adreno **Vulkan 156ms**（其 OpenCL 574ms 抖，淘汰）；联发科 Mali-G715 CL≈Vulkan **234ms**（都稳）。CPU2线程：242/457ms。
  - ISNet-anime 256 粗筛 GPU：54/93ms。u2net 真人 320 GPU：197/320ms（真人模型最重）。
  - **结论：后端统一用 Vulkan（两边都好，避开 Adreno 烂 OpenCL）。旗舰全图 512@156-234ms 够用**（2-4次/秒+跟踪）。coarse+ROI 主要为小目标质量。中低端未测，需降级方案（256粗筛/降频/CPU 兜底）。
- **Phase 1 — 模型与路由**：重导出 + 转 MNN（粗筛档 + 精修档 + 真人档）；动漫/真人路由（先每片源开关）。
- **Phase 2 — 定位/分割层（native）**：粗筛→连通域定位→按大小过滤→ROI 精修。复用 tracking/ROI 骨架，砍 PicoDet + small-multi。
- **Phase 3 — 渲染层防碎片**：逐条弹幕遮挡比例策略。
- **Phase 4 — 清理**：删旧 PP-HumanSeg 路径和失效的补丁常量。

## 框架选择

移动端推理选 **MNN**（GPU/NPU delegate 成熟，ISNet/U2Net ONNX 转换顺）。替代现有 FastDeploy（CPU 焊死）。

## PoC 资产位置

`%TEMP%\dmpoc`：`poc.py`（推理可视化）、`export.py`（从 ckpt 重导出小尺寸 onnx，`torch.load(weights_only=True)` 安全加载）、
`models/`（isnet-anime-512/320/256.onnx、u2net_human_seg.onnx、*-fp16.mnn、*-int8.mnn）、`inputs/`、`outputs/`、`bench/`（bench.cpp + mnnbench）。

## 模型体积（MNN 量化）

| 精度 | 单模型 | 说明 |
|---|---|---|
| fp32 | 168MB | 不用 |
| fp16 | 84MB | GPU 本就 fp16，质量无损 |
| **int8** | **42MB** | 权重量化，最小，**已验证基本无损**（多人 IoU 0.993、单人 1.000，视觉无退化）← 采用 |

**int8 锁定**：isnet-anime-512-int8.mnn 42.2MB + u2net_human_seg-int8.mnn 42.3MB = ~84.5MB。
只需 1 个 isnet 模型（256/512 用同权重 resize）。打包进 `src/full/assets/models/`；删掉 fastdeploy(76MB)+paddle 模型后净体积近中性（略降）。
MNN 运行时 .so 仅 ~7MB（libMNN 2.4 + Vulkan 0.7 + CL 2.1 + c++_shared 1.8 + libmnnseg 0.056）。

## Phase 1 已完成（已编译验证，未在 App 内运行）

- `src/full/cpp/mnn_seg_jni.cpp` —— MNN Interpreter JNI bridge（nativeCreate/nativeRun/nativeDestroy）。
- `src/full/jniLibs/arm64-v8a/`：libmnnseg.so（自编）+ libMNN/Vulkan/CL/c++_shared.so（MNN 3.5.0 预编译）。
- `src/full/kotlin/.../MnnSegNative.kt`（JNI 绑定，System.loadLibrary("mnnseg")）。
- `src/full/kotlin/.../MnnImageSegmenter.kt`（自包含分割器：bitmap→NCHW 归一化→run→min-max 归一化；createAnime/createHuman，默认 Vulkan）。

**编译 libmnnseg.so（NDK 28，外部编译，仿 mpv 预编译 .so 模式）：**
```
clang++ --target=aarch64-linux-android24 -std=c++14 -O2 -shared -fPIC \
  -I<mnn_include> src/full/cpp/mnn_seg_jni.cpp -o src/full/jniLibs/arm64-v8a/libmnnseg.so \
  -L<mnn_android_arm64> -lMNN -llog
```
MNN 头文件从源码 tag 3.5.0 的 include/MNN 抓；android .so 从 `mnn_3.5.0_android_..._cpu_opencl_vulkan.zip` 取。

## 待办（需能跑 flutter build 的环境迭代）

- ~~int8 质量快验~~ ✅ 已做：int8 基本无损（多人 IoU 0.993），采用 int8。模型已生成在 `%TEMP%\dmpoc\models\*-int8.mnn`，待放入 assets。
- ~~gradle noCompress 加 mnn~~ ✅；`src/full/jniLibs` 由 AGP 自动并入 full flavor，无需改 srcDir。移除 `fullImplementation(fastdeploy.aar)` 留到检测也换掉之后。

### Phase 2 — Chunk 1 ✅ 已写（待用户构建验证）
把**分割后端换成 MNN**（检测暂留 Paddle/PicoDet）。改动：
- `src/full/assets/models/mnn_seg/isnet-anime-512-int8.mnn`（44MB）入包。
- `DanmakuSegmentationRuntime.kt`(src/full)：新增 `MnnSegmentationRuntime`(实现现有接口,backend复用PADDLE,512方形)；工厂 `create()`→`createMnnRuntime()`(缓存感知拷贝asset→cache→`MnnImageSegmenter.createAnime`,默认Vulkan)；`shouldAttempt`→查MNN可用+asset存在。旧 PaddleSeg 类/方法保留但不再调用。
- `MnnSegNative` 显式预加载 libMNN。
- **坑(已修)**：MNN 预编译包自带的 `libc++_shared.so` 较旧，缺 `std::from_chars` 浮点符号；`pickFirst` 选中它会顶替 mpv 的新版 libc++ → `libmpv.so` dlopen 失败("cannot locate symbol _ZNSt6__ndk127__from_chars_floating_point")→ **本地播放直接挂**。修法：**不要把 MNN 的 libc++_shared.so 放进 jniLibs**（已删 `src/full/jniLibs/arm64-v8a/libc++_shared.so`），让 pickFirst 用 mpv 的新版超集 libc++，mpv 和 MNN 都满足。
- 验证点：动漫遮罩应明显变好(多人/轮廓)、风景不误遮；fastdeploy 仍在(检测用)。已知：小目标ROI仍由PicoDet喂、small-multi会多次跑512(略慢)、旧mask后处理是按PP-HumanSeg调的可能过度接受/拒绝——下一块处理。

### Phase 2 — Chunk 2 ✅ 已写（待用户构建验证）
**全图 MNN 路径**（动漫遮罩的关键——PicoDet 检测不了动漫角色，必须去检测）。改动 `src/main/DanmakuDynamicOcclusion.kt`：
- 常量 `DANMAKU_AI_MNN_FULL_FRAME=true` + mask 阈值/最小前景比。
- 新增 `runMnnFullFrameInference`：`ensureRuntime()`→对整帧 `runtime.run(bitmap)`(ISNet 512)→`buildFullFrameMaskResult`(前景比<1.2%判空;否则软mask,normalizedRect=(0,0,1,1))→`applyMaskResult`(updateTrackingState=false,空motion样本)/`applyEmptyResult`。复用现有 emit/cache/render。
- `runInference` 顶部分支：full-frame 时早返回走新路径；旧检测路径整体变 dead code(留待Phase4删)。
- 也修了 `MnnImageSegmenter.preprocess` 性能：逐像素 getPixel(~2s)→`createScaledBitmap`+`getPixels`批量(~200ms)。
- 验证点：动漫遮罩应能出(多人/风景正确)、单帧 ~200ms、logcat `mode=mnn_full_frame`。可能的对齐问题：320x320 方形 capture 映射到 16:9 overlay，若 mask 上下错位再调 normalizedRect/capture 宽高比。
- 仍在(Phase4再清)：fastdeploy.aar(检测/旧seg已不调用但还链接)、旧 runInference 死代码、旧补丁常量。

### Phase 2 — Chunk 2.1 延迟优化 ✅ 已写（待验证）
实测 error.log：int8 模型在 Vulkan 上 inferenceMs≈1100ms（benchmark 是 fp32 234ms），采样被退避顶到 1200ms → 滞后 ~2.4s。
- **根因：int8 权重量化 GPU 慢 3 倍**（实测 512 Vulkan：fp32 218ms / fp16 243ms / **int8 716ms** / int8 OpenCL 1160ms）。int8 是给 CPU 省体积的，GPU 无优化 kernel。
- 改：打包模型 int8→**fp16**（88MB，~250ms）；`DANMAKU_MNN_SEG_MODEL_FILE` 改名。
- 采样间隔调小：DEFAULT 800→450、MAX 1200→700、高刷 650/780/900→420/440/460。lag ~2.4s→~700ms。
- 仍是静态 mask（采样间隔内不动）。若还嫌跟不上，下一步**运动补偿**（全图多人较复杂，旧单ROI那套不能直接套）。

### Phase 2 — Chunk 2.2 运动补偿 ✅ 已写（待验证）
采样地板 ~680ms（推理 ~400ms+尖峰），调参到头，做运动补偿填补采样间隙。
- **Controller**(`DanmakuDynamicOcclusion.kt`)：`updateGlobalMotionVelocity`——每采样把帧缩到 48×27 luma 网格、对上一帧做 ±6 SAD 全局位移搜索→速度(归一化/ms，EMA 平滑)；存 `latestMaskVelocityX/Y`；在 `runMnnFullFrameInference` 里调用；`DanmakuDynamicOcclusionState` 加 `maskVelocityX/Y` 字段(默认0)，applyMaskResult 的 emitState 写入。
- **Overlay**(`NativeDanmakuOverlayView.kt`)：视图存 `maskVelocityX/Y`+`maskAnchorUptimeMs`(setOcclusionState 时锚定)；`drawOcclusionMask` 每帧按 `速度×已过时间×尺寸` 偏移 `maskDstRect`(上限 18% 尺寸 / 900ms)。靠弹幕动画的逐帧 invalidate 驱动。
- 验证点：镜头平移时 mask 跟手很多；个体运动是近似(全局平移)。若方向反了→翻 vx/vy 符号；抖动→调 EMA/上限。
- 全局平移对镜头运动最好；多人各自运动只能近似。

### Phase 2 — Chunk 2.3 性能/遮罩上限 ✅ 已写（待验证）
用户反馈：弹幕掉帧(吃性能)、延迟仍明显、人占大半屏时整屏被遮。
- **遮罩上限**：`buildFullFrameMaskResult` 前景 ratio > `DANMAKU_AI_MNN_MAX_FOREGROUND_RATIO=0.55` → 返回 null 不遮（大特写弹幕保持可读，对应用户最早"大特写不遮"）。
- **GPU→CPU 推理**：根因是 GPU 争抢——旧 Paddle 是 CPU(~8ms)不抢 GPU，换 MNN 走 Vulkan 每 640ms 占 GPU ~300ms → 和 mpv/Impeller/弹幕渲染抢 → 掉帧。`createMnnRuntime` 改 `BACKEND_CPU, threads=2`。CPU ~250-460ms（比 GPU 略慢），靠运动补偿+遮罩上限扛。
- 待观察：CPU 是否引入 UI 线程争抢(Flutter build jank)；若是→降推理线程优先级或回 GPU+拉长间隔。中低端 CPU 更慢→间隔退避→延迟升。

### Phase 2 — Chunk 2.4 384降精度 ✅ + Chunk 4 去Paddle ✅
- 384 fp16：推理 ~340→~130ms、间隔自动降 500；遮罩上限 0.55；CPU 后端避 GPU 争抢(但 UI 周期抢核小卡)。
- 去 Paddle：删 fastdeploy.aar(76MB)+模型(13MB)；src/full 纯 MNN；检测工厂 no-op。full AI 184MB→~95MB。

## Plan B — 预计算架构（已定，执行中）
**要求**：高性能 + 不影响播放 + 效果好。**核心**：MediaCodec 超前解码未来帧 → 后台预算 mask(按 PTS) → 渲染按当前进度查表。推理移出渲染实时路径 → 消除延迟、不抢渲染、且可调回 512/GPU 提质(不再受延迟约束)。
**接入点**：壳 `NativePlayerActivity`；源 `loadArgs["url"]`；进度 mpv；分割复用 `MnnImageSegmenter`；渲染 `NativeDanmakuOverlayView.drawOcclusionMask`。PixelCopy 抓帧不用于 Plan B。
**解码器**：MediaCodec 顺序超前(否决 MMR：反复 seek 拖播放)。
**分块**：B1 `DanmakuFrameExtractor`(MediaExtractor+MediaCodec→getOutputImage YUV→RGB Bitmap，独立可测) → B2 PTS→mask 环缓冲+控制器改播放进度驱动 → B3 渲染按 PTS 选 → B4 同步边界(seek/暂停/倍速/切集) → B5 提质(512/GPU)。
**风险**：同步边界、几何对齐、网络源 seek、第二解码器会话(SoC限并发)。先只本地文件。

### Phase 2 — Chunk 3（渲染防碎片）待做
**编排器（src/main DanmakuDynamicOcclusion.kt）**：检测+分割两段式深度耦合，删 fastdeploy 必须同时改编排器——
  用 ISNet-256 粗筛整图 → 连通域定位人物+大小（替代 PicoDet）→ 按大小过滤选 ROI → ROI 跑 512 精修（MnnImageSegmenter）。
  砍掉 PicoDet/small-multi/DanmakuDetectionRuntime。复用现有 tracking/ROI/cache。DanmakuSegmentationRuntimeFactory 改为产出 MnnImageSegmenter。
- **Phase 3（渲染，NativeDanmakuOverlayView.kt）**：全局 DST_OUT(:361/:2925) → 逐条弹幕评估遮挡比例：适中镂空、过高整条照画。
- **Phase 4（清理）**：删 src/full 旧 Paddle 实现、pp_humansegv2_lite/picodet 模型、失效补丁常量；lite 替身保持同 API。
- **注意**：当前工作区有 42 项未提交 WIP，且 `src/main/jniLibs` 的 mpv .so（libmpv/libavcodec…）被删，整体构建可能本就不通，重写前需先恢复可构建状态。
