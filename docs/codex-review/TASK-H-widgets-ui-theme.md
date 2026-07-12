# TASK H —— 公共组件库 / UI 基建 / 主题系统评审

> 先完整阅读 `docs/codex-review/00-review-constraints.md`（约束标准 + 工作协议），再开工。
> findings 写入 `docs/codex-review/findings/H.md`，编号前缀 `H-`。

## 范围（约 1.75 万行）

1. `lib/widgets/` 全部 43 个文件（含 `widgets/common/liquid_glass.dart`、`widgets/settings/`）
2. `lib/ui/` 全部 24 个文件（含 `layout_adaptive.dart`、`media_poster_card.dart`）
3. `lib/theme/` 全部 8 个文件（`dynamic_theme_seed_extractor.dart` 的通道部分归 TASK C，取色逻辑归你）

## 本区域重点检查项

1. **[P1] 玻璃/模糊残留清剿**——本任务第一优先级：项目已决策回归纯色，全量 grep `BackdropFilter` / `ImageFilter.blur` / `blur`，逐个残留点上报；`liquid_glass.dart` 已纯色化，确认没有死掉的模糊代码路径残留（[M5]）和仍在付出的无谓合成成本（透明层叠加、saveLayer）。
2. **组件 API 设计（公共库的可扩展性）**：
   - 参数超过 ~8 个的组件（应改配置对象或拆分）；
   - 为单一调用方特化的"伪公共组件"（bool 开关满天飞，每加一个使用场景就加一个 flag）；
   - [C3] 公共组件里出现后端专名或后端特定字段假设。
3. **`media_poster_card.dart` 与 `layout_adaptive.dart`**：全 app 列表/网格的基础件，性能问题放大百倍——
   - 每个卡片的 build 成本（阴影、圆角裁剪 `clipBehavior`、saveLayer）；
   - [P3] 图片解码尺寸是否与卡片实际尺寸匹配；
   - 自适应布局计算是否每帧重算（应缓存 breakpoint 结果）。
4. **主题系统**：
   - 动态取色（palette_generator）链路：取色时机、缓存命中（`DynamicThemeRuntimeController` / seed 缓存）、取色失败回退；
   - 主题切换触发的 rebuild 范围（[P4]）；
   - 颜色/尺寸 token 是否收敛（[M6]，散落的硬编码 Color/EdgeInsets 成体系问题就报）。
5. **const 与重建**：公共组件能 const 没 const、没有 `RepaintBoundary` 隔离的高频重绘区域。
6. **[M5] 死组件**：widgets/ui 下没有任何调用方的组件（grep 引用验证后再报）。
7. 通用项全查：[M3] i18n、[M4]、[P6]、[P7]。

## 完成标准

第一轮逐文件 + 第二轮自复核（见 00 文档第 7 节协议），最后更新 PROGRESS.md 中 TASK H 状态为 DONE。
