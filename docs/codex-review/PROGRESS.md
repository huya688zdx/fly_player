# 全项目评审进度总览

> 本轮评审范围：**Flutter 层 + Flutter↔Android 桥接层**。安卓原生层内部实现暂不评审。
> 标准与协议见 `00-review-constraints.md`。每个 Codex 窗口认领一个 TASK，互不越界。

## 进度看板（各窗口自行更新自己那一行）

| 任务 | 范围 | 规模 | findings 文件 | 状态 | 备注 |
|---|---|---|---|---|---|
| A | 核心骨架 + api + media_backend + providers/controllers/models | ~17k 行 | findings/A.md | DONE | |
| B | services + play_stats + utils | ~17k 行 | findings/B.md | DONE | |
| C | 平台桥接层 + 通道契约核对 | 桥接文件 + Kotlin 对照 | findings/C.md | DONE | |
| D | 播放器核心（page 宿主 + core/view mixin + controllers + stores） | ~23k 行 | findings/D.md | DONE | |
| E | 播放器 UI（settings/danmaku mixin + panels/widgets）+ danmaku 模块 | ~25k 行 | findings/E.md | DONE | |
| F | 详情页 pages + 浏览类 screens | ~19k 行 | findings/F.md | DONE | |
| G | 设置/工具/登录类 screens | ~20k 行 | findings/G.md | DONE | |
| H | widgets + ui + theme 公共基建 | ~17.5k 行 | findings/H.md | DONE | |

状态取值：`未开始` → `第一轮进行中` → `第二轮自复核` → `DONE`

## 各窗口启动提示词（复制给对应 Codex 窗口）

把 `<X>` 换成任务字母，对应文档名见上表：

```
请完整阅读 docs/codex-review/00-review-constraints.md 和 docs/codex-review/TASK-<X>-*.md，
然后严格按文档中的工作协议执行代码评审。
这是长期挂机任务：发现的问题立即增量写入你的 findings 文件并更新 checkpoint；
任何时候上下文被压缩或会话重启，先重读这两个文档和 findings 文件头部的 checkpoint，
从断点继续，不要重审已完成的文件。只报告问题，不要修改任何代码。
```

各任务文档名：
- A: `TASK-A-core-backend.md`
- B: `TASK-B-services-utils.md`
- C: `TASK-C-platform-bridge.md`
- D: `TASK-D-player-core.md`
- E: `TASK-E-player-ui-danmaku.md`
- F: `TASK-F-detail-browse.md`
- G: `TASK-G-screens-tools-settings.md`
- H: `TASK-H-widgets-ui-theme.md`

## 建议启动顺序（窗口不够时的优先级）

1. **C（桥接）**——用户明确要求的重点，且范围最小、独立性最强。
2. **A（核心骨架/多后端抽象）**——其结论影响后续修复的整体方向。
3. **D（播放器核心）**——性能最敏感区。
4. **F（详情/浏览页）**——多后端迁移进行中，耦合问题最多。
5. B / E / G / H 随配额并行补上。

## 评审完成后（由 Claude 负责，Codex 不做）

全部 DONE 后，由 Claude 汇总 8 份 findings：去重跨任务重复项、按 P0→P3 排序、
输出统一修复计划到 `docs/codex-review/FIX-PLAN.md`。
