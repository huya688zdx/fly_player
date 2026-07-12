# TASK D —— 播放器核心链路评审

> 先完整阅读 `docs/codex-review/00-review-constraints.md`（约束标准 + 工作协议），再开工。
> findings 写入 `docs/codex-review/findings/D.md`，编号前缀 `D-`。

## 范围（约 2.3 万行）

1. `lib/player/mpv_player_page.dart`（宿主 widget，~1.3k 行）
2. `lib/player/page_parts/core/`（运行时、源切换、选集、书签、A-B 循环、系统会话等 mixin，~8k 行）
3. `lib/player/page_parts/view/`（视频视图、手势层、overlay 堆叠，~3k 行）
4. `lib/player/controllers/`（~6.3k 行，重点 `mpv_player_controller.dart`）
5. `lib/player/services/`（**除** `native_player_bridge.dart`、`native_panel_bridge.dart`，那两个归 TASK C）
6. `lib/player/stores/`（~2.8k 行）
7. `lib/player/models/`

## 排除

- `page_parts/settings/`、`page_parts/danmaku/`、`panels/`、`widgets/` 归 TASK E。
- MethodChannel 通道契约细节归 TASK C；但 controller 内**围绕通道的状态机逻辑**（谁先谁后、竞态）属于你。

## 本区域重点检查项

这是全项目性能最敏感的区域，性能问题优先定 P0/P1。

1. **mixin 间耦合**：~20 个 mixin 共享 State 成员变量——
   - 梳理哪些字段被 3 个以上 mixin 读写（隐式共享可变状态 = 耦合重灾区）；
   - mixin 之间有没有隐含的初始化顺序依赖（A 的 initState 逻辑假设 B 已就绪）；
   - 上报"改一个 mixin 必须懂另外几个"的具体案例。
2. **播放生命周期状态机**：加载→播放→切源→切集→退出的每条路径——
   - 竞态：快速连续切集/切源时，前一次异步结果回来覆盖新状态的窗口（报 P0）；
   - `dispose` 后仍可能触发的回调/Timer/订阅（[P6]/[P7]）；
   - 退出播放器的清理是否完整（proxy、通道 handler、wakelock、系统会话）。
3. **[P4] 高频事件的 rebuild 粒度**：进度/位置回调（每秒甚至更频）驱动 UI 的路径——是走 `ValueListenable`/局部刷新，还是整页 setState？逐个高频源核查。
4. **手势层**：手势竞技场冲突（拖动进度 vs 音量/亮度 vs 缩放）；手势回调里的昂贵计算。
5. **续播/记忆逻辑**：resume 位置的读写时机、多处写入是否会互相覆盖。
6. **stores/**：持久化读写频率（有没有每 tick 写盘）；与 controller 的职责边界。
7. 通用项全查：[M1] 超大文件切面、[M3] i18n、[M4] 错误处理、[P5]、[P7]。

## 完成标准

第一轮逐文件 + 第二轮自复核（见 00 文档第 7 节协议），最后更新 PROGRESS.md 中 TASK D 状态为 DONE。
