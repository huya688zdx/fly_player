# TASK E —— 播放器 UI（设置/面板/组件）与弹幕模块评审

> 先完整阅读 `docs/codex-review/00-review-constraints.md`（约束标准 + 工作协议），再开工。
> findings 写入 `docs/codex-review/findings/E.md`，编号前缀 `E-`。

## 范围（约 2.5 万行）

1. `lib/player/page_parts/settings/`（设置抽屉、音频、字幕、视频调整等 mixin，~6.4k 行）
2. `lib/player/page_parts/danmaku/`（弹幕 mixin，~2.8k 行）
3. `lib/player/panels/`（~1.7k 行）
4. `lib/player/widgets/`（~6.1k 行；`player_system_controls.dart` 的通道部分归 TASK C，UI 部分归你）
5. `lib/player/mpv_settings_l10n.dart`
6. `lib/danmaku/` 全部（21 个文件，~8.2k 行）——**先读 `lib/danmaku/README.md`**，它定义了该模块的架构红线

## 本区域重点检查项

1. **[C4] 弹幕架构红线逐条核查**（README 是判据）：
   - 数据源 / 设置 / 渲染三层是否真分离（渲染层 import 数据源实现 = 违规）；
   - 单 `CustomPaint` + `RepaintBoundary`、`IgnorePointer` 是否守住；
   - 弹幕网络请求是否全部走 `lib/danmaku/api/`，有没有摸 `feiniu_api.dart`。
2. **弹幕渲染热路径**（每帧执行，性能问题报 P1）：
   - paint 方法内的对象分配（TextPainter/Paint/Path 每帧新建？应缓存的布局结果有没有缓存）；
   - 弹幕轨道分配算法复杂度（弹幕量大时是否 O(n²)）；
   - 设置变更（透明度/字号/速度）是重建全部弹幕还是增量应用。
3. **设置抽屉 mixin 群**：
   - 设置项读写与 mpv 属性同步的一致性（UI 显示值 vs 实际生效值脱节）；
   - 抽屉打开时机的昂贵操作（同步读盘、全量枚举轨道）；
   - 各设置 mixin 之间复制粘贴的抽屉骨架代码（[M2]，指出可抽取的公共模板）。
4. **player/widgets/**：无状态化机会（能 const 的没 const）；深层嵌套的 build 巨函数（给拆分切面）。
5. **弹幕源选择（DanDanPlay）**：API 调用错误路径、鉴权失败的用户反馈、按集保存源的边界（切集串台防护）。
6. 通用项全查：[M3] i18n（播放器内 toast/标签是重灾区）、[M4]、[P6]、[P7]。

## 完成标准

第一轮逐文件 + 第二轮自复核（见 00 文档第 7 节协议），最后更新 PROGRESS.md 中 TASK E 状态为 DONE。
