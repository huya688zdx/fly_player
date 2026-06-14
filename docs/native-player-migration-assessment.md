# 渐进式播放器原生化 — 可行性评估

> 背景：弹幕丝滑度问题最终定位为 Flutter + 外部视频渲染的架构铁律——
> 视频在 Flutter 场景（texture backend）则和弹幕抢 raster；视频走独立
> SurfaceView（surface backend）则 Flutter UI 走 Hybrid Composition 而卡二级界面。
> 二者不可兼得。本文评估"渐进式原生化"作为彻底两全的方案。

## 0. 一句话结论

**可行，而且接缝比想象中有利**——mpv 内核、播放控制、状态、原生弹幕（含 AI 遮挡）
都已经在原生侧，原生化主要是"补一层控制 UI"，不是从零做播放器。但全量对齐
仍是 **2–4 个月（单人）** 的工程。**强烈建议先确认 `A + 60Hz` 不够用，再投入。**

---

## 1. 为什么要做（根因回顾）

| 路线 | 弹幕 | 二级界面 | 原因 |
|---|---|---|---|
| A. Flutter 弹幕 + texture | 受视频拖累 | 顺 | 视频纹理和弹幕共用 Flutter raster 线 |
| B. 原生弹幕 + surface | 丝滑 | **卡** | Flutter UI 叠在 SurfaceView 上 → Hybrid Composition 每帧同步合成 |

卡的根源是 **"Flutter UI 叠加在 SurfaceView 之上"** 触发 HC。
纯原生播放壳（SurfaceView + 原生弹幕 + 原生/Compose 控制 UI）三者同在原生 View
层级，由系统 SurfaceFlinger 正常合成，**没有跨引擎 overlay → 两全**。

---

## 2. 当前架构分层现状（有利条件）

### 已在原生侧（可直接复用，无需重写）
- **mpv 内核**：`MpvPlaybackController` — `load / play / pause / seek / setSpeed /
  setAudioTrack / setSubtitleTrack / setSubtitleDelay / setSubtitlePosition /
  setSubtitleScale / …` 全套控制 + 属性观察 + 状态。
- **视频输出**：`MpvPlayerView` / `VideoOutputTarget`（`SurfaceViewVideoOutputTarget`
  已就绪）。
- **原生弹幕**：`NativeDanmakuOverlayView`（3079 行）— 数据接收（分块 `setPayload`）、
  车道调度、AI 动态遮挡（`setOcclusionState` + PixelCopy 抓帧）、播放位置同步。
- **会话/系统集成**：`PlaybackSessionManager` / `PlaybackSessionCoordinator`、PIP、
  媒体会话、`ParallelWindowCoordinator`（分屏）。

### 在 Flutter 侧（本次评估的迁移对象）
`MpvPlayerPage` 的 ~20 个 mixin 全是 UI + 编排：
- **播放常用层**：控制条、手势（双击/横拖 seek/长按倍速/上下亮度音量）、进度、
  顶部信息、加载/错误提示。
- **二级界面**：设置抽屉宿主、弹幕设置多页、音轨/EQ、字幕样式、视频调整、
  OP/ED、mpv 高级设置、剧集浏览、画质切换、书签、A-B 循环、截图、弹幕源/管理。
- **编排**：源切换/续播、弹幕数据拉取（`lib/danmaku/api` DanDanPlay）、播放统计、
  动态主题。

> 关键判断：**"执行层"几乎全在原生，Flutter 主要是"表现层 + 编排层"。**
> 所以原生化 = 补一层原生控制 UI + 把编排接缝挪到原生，而不是重做播放内核。

---

## 3. 目标架构（渐进原生化）

```
┌─────────────────────────────────────────────┐
│ 原生播放壳 Activity（无 Flutter overlay）        │
│  ┌─────────────────────────────────────────┐ │
│  │ SurfaceView（mpv 视频，独立硬件层）          │ │
│  ├─────────────────────────────────────────┤ │
│  │ NativeDanmakuOverlayView（原生弹幕）         │ │
│  ├─────────────────────────────────────────┤ │
│  │ Compose 控制层（控制条/手势/进度/常用操作）   │ │ ← 新建，直接调 MpvPlaybackController
│  └─────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
        │ 按需启动（不叠加在 SurfaceView 上）
        ▼
┌─────────────────────────────────────────────┐
│ 二级界面（低频）：独立全屏页                       │
│  - 选项①：保留 Flutter（独立 FlutterActivity，    │
│    打开时视频 PIP/暂停，不触发 HC 叠加）           │
│  - 选项②：Compose 原生                          │
└─────────────────────────────────────────────┘
```

**核心原则**：播放中常驻可见的层 = 纯原生（丝滑）；低频二级页 = 独立全屏
（不叠加 → 不卡），可继续用 Flutter 省重写。

---

## 4. 分阶段计划

### 阶段 1：原生播放壳 MVP（先验证"真两全"）
**目标**：证明原生壳下弹幕丝滑 + 控制不卡，再决定是否继续投入。
- Compose 控制层：播放/暂停、进度条+拖动、时间、缓冲、顶部标题/返回。
- 手势：双击暂停、横拖 seek、长按倍速、上下亮度/音量、单击显隐 UI。
- 直接调 `MpvPlaybackController`（不经 Flutter channel）。
- 弹幕：复用 `NativeDanmakuOverlayView`；**弹幕数据先保留 Flutter headless 服务
  拉取**（见 §5.1），原生壳通过 channel 请求并 `setPayload`。
- 入口：从现有详情页"播放"进入这个原生壳 Activity（与现有 Flutter 播放器并存，
  灰度切换）。
- **产出**：80% 使用时长（播放+常用控制）纯原生丝滑。可量化对比。

### 阶段 2：二级界面"独立页化"
- 设置/剧集/弹幕管理等改为独立全屏页打开，打开时视频 PIP 或暂停，**不叠加**。
- 优先选项①（保留 Flutter 独立页）省重写；高频项（如画质/弹幕开关）做成原生
  快捷面板放控制层里。
- **产出**：二级界面不再卡。

### 阶段 3：全功能对齐 + 收尾
- 逐一对齐：AI 遮挡设置、音轨/EQ、字幕样式、视频调整、OP/ED、书签、A-B、
  截图、画质、续播、播放统计回传、动态主题。
- 分屏（ParallelWindow）兼容（高风险，见 §5.3）。
- 旧 Flutter 播放器下线。

---

## 5. 关键接缝与风险

### 5.1 弹幕数据通路（中风险）
现状：DanDanPlay 拉取/匹配/缓存在 Flutter（`lib/danmaku/api`、`source`、`cache`）。
原生壳需要弹幕数据。
- **阶段 1 方案**：保留一个 headless Flutter 服务（或后台引擎）继续拉弹幕，
  通过 channel 把 `commentsCompact` 推给原生 `setPayload`（通路已存在）。
- **长期**：评估是否把弹幕拉取也原生化（去掉 Flutter 依赖），或保留 headless。

### 5.2 状态回传 app 其余部分（低风险）
播放进度/续播/播放统计需要回流给 Flutter 端（详情页"继续观看"、`play_stats`）。
保留一条 channel 回传即可，量小。

### 5.3 分屏 ParallelWindow（高风险，建议后置）
当前分屏用多 Flutter 引擎实现。原生播放壳 + Flutter detail pane 的组合要重新设计
合成与生命周期。建议**阶段 3 再处理**，或分屏场景暂时回退旧 Flutter 播放器。

### 5.4 动态主题（低风险）
播放器原生 UI 可固定深色，或通过 channel 接收主题种子。播放器本就偏深色，影响小。

### 5.5 功能回归面（测试成本）
20+ 功能模块逐一对齐，测试量大。灰度并存（新原生壳 + 旧 Flutter 播放器开关切换）
可降低风险。

---

## 6. 工作量量级（粗估，单人）

| 阶段 | 内容 | 量级 |
|---|---|---|
| 1 | 原生播放壳 MVP（控制+手势+弹幕接缝+状态） | 2–4 周 |
| 2 | 二级页独立化 | 1–2 周 |
| 3 | 全功能对齐 + 分屏 + 收尾 | 4–8 周 |
| | **合计** | **约 2–4 个月** |

---

## 7. 建议与决策点

1. **先验 `A + 60Hz`（零成本）**：UI 尖刺已修（0.9ms）+ raster 11ms 都落进 60Hz
   的 16.6ms 预算，很可能已"够顺"。若够，本工程不必启动。
2. **若 60Hz 仍有残留**：先做 `A + 60Hz + 关 atlas`（source 直绘稳态 ~2.4ms、无
   flush 尖刺）——小改动，可能就是 Flutter 路线的终点。
3. **只有以上都不满意，才启动渐进原生化**，且**从阶段 1 MVP 验证开始**——先用
   2–4 周做出原生壳，实测确认"真两全"，再决定是否投入阶段 2/3。不要一上来就
   全量重写。

> 决策本质：用 2–4 个月换"120Hz 满帧丝滑 + 二级界面顺"。是否值得，取决于
> A+60Hz 到底差多少。**先把那 1 分钟的测试做了。**
