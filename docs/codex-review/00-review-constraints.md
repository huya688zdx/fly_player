# Fly Player 全项目评审 —— 约束与评审标准（总纲）

> 本文档是所有评审窗口的**共同标准**，由架构负责人（Claude）制定。
> 每个评审窗口开工前必须完整阅读本文档 + 自己的 TASK 文档。
> **你的职责是找问题、报问题，不是修代码。除 findings 文件与 PROGRESS.md 外，禁止修改任何文件。**

## 0. 项目目标（评审的价值取向）

按优先级排序：

1. **低耦合** —— 层与层、模块与模块之间依赖清晰、单向、可替换。
2. **易维护** —— 文件规模可控、无重复代码、命名与结构一致、错误可追溯。
3. **易扩展** —— 尤其是"多媒体后端"（飞牛 / Emby / 未来 Jellyfin）的接入不需要改公共代码。
4. **高性能** —— 首帧快、滚动不掉帧、播放路径无主线程阻塞、无内存泄漏。

## 1. 分层与耦合约束

- **[C1] 依赖方向**：UI 层（`lib/pages/`、`lib/screens/`、`lib/widgets/`、`lib/ui/`）→ 状态层（`lib/providers/`、`lib/controllers/`）→ 服务层（`lib/services/`、`lib/media_backend/`）→ API 层（`lib/api/`）。**逆向 import 一律违规**（services import widgets、provider import 页面等）。
- **[C2] UI 不得直接依赖具体后端 API**：pages/screens/widgets 直接 `import 'package:.../api/feiniu_api.dart'` 并调用其方法属于待清理耦合，逐条上报（附调用点）。数据获取应经由 `lib/media_backend/` 抽象或 services 层。
- **[C3] 多后端抽象合规**（参照 `docs/multi-backend-abstraction-plan.md`）：
  - 公共组件/公共文件不得出现后端专名（Emby、Feiniu、fn、飞牛）作为类名/文件名/参数名；
  - 不得对后端桥接接口做 `is` / `as` downcast 到具体后端实现；
  - 登录、入口、URL 拼接不得写死单一后端假设；
  - 后端差异应收敛在 `lib/media_backend/` 内部，泄漏到外面的差异判断（`if (backend is Emby...)` 之类）逐条上报。
- **[C4] 弹幕模块独立性**（参照 `lib/danmaku/README.md`）：
  - 弹幕网络请求只允许走 `lib/danmaku/api/`，禁止依赖 `feiniu_api.dart`；
  - 渲染必须是单 `CustomPaint` + `RepaintBoundary`，禁止一条弹幕一个 widget；
  - 弹幕层必须 `IgnorePointer`，不得拦截手势。
- **[C5] 平台通道收敛**：`MethodChannel` / `EventChannel` 的创建与 handler 注册只允许出现在明确的桥接文件（`*_bridge.dart`、`*_service.dart`、专职 store）中；页面/widget 内直接 new channel 属于违规。通道名、方法名字符串应有单一定义点，散落的裸字符串逐条上报。
- **[C6] 单一职责**：一个 service 同时承担网络 + 持久化 + UI 格式化等多职责的，上报并给出拆分方向。

## 2. 可维护性约束

- **[M1] 超大文件**：单个 UI 文件 > 1500 行应可拆分（P2 级建议，给出拆分切面）；player 已确立 part + mixin 模式，新功能应遵循该模式。
- **[M2] 重复/平行代码**：两段相似度高的 UI 或逻辑（复制粘贴改字段）逐条上报，指出应抽取的公共模板。**历史教训**：接新后端时必须复用现成页面 UI、只在数据层分流，禁止手搓平行简陋页面。
- **[M3] i18n 硬约束**：
  - UI 展示文案一律走 `AppLocalizations` getter（arb 生成），**禁止硬编码中文/英文文案**；
  - 禁止 `_t(path, fallback)` / `AppLocalizationLookup` 之类间接查找层（已全量清除，发现回潮即报 P1）。
- **[M4] 错误处理**：空 `catch {}` 吞异常、`catch (e)` 后不记录不上抛、`PlatformException` 未处理，逐条上报。
- **[M5] 死代码**：未被引用的公开成员、注释掉的大段代码、永假分支。
- **[M6] 魔法数字/字符串**：影响行为的常量（超时、阈值、SharedPreferences key）散落多处未收敛的上报。

## 3. 性能约束

- **[P1] 禁止 BackdropFilter / 模糊玻璃回潮**：项目已决策回归纯色（raster 掉帧问题），发现任何新增/残留的 `BackdropFilter`、`ImageFilter.blur` 用于大面积 UI 的即报 P1。
- **[P2] 列表懒加载**：长列表必须 `ListView.builder` / `SliverList`；`Column` + `map().toList()` 渲染不定长数据的上报。
- **[P3] 图片解码尺寸**：网络大图（海报、剧照、背景）必须有 `cacheWidth/cacheHeight` 或等效受控尺寸；无约束解码原图的上报。
- **[P4] rebuild 粒度**：高频事件（播放进度、位置流、每秒 tick）触发整页 `setState` 的报 P1；Provider 应使用 `select` / 局部 `Consumer` 缩小重建范围。
- **[P5] build 内昂贵操作**：`build()` 中做 IO、JSON 解析、列表排序/过滤大数据、每帧创建大对象的上报；大 JSON（>100KB 量级）应考虑 `compute`。
- **[P6] 资源泄漏**：`Timer`、`StreamSubscription`、`AnimationController`、`FocusNode`、`TextEditingController` 未 dispose；MethodChannel handler 未卸载；`addListener` 未 remove。
- **[P7] async gap 安全**：`await` 之后使用 `context` / 调 `setState` 未检查 `mounted` 的逐条上报（这是崩溃源，报 P0/P1）。

## 4. severity 定级

| 级别 | 定义 |
|---|---|
| **P0** | 崩溃、数据丢失、明确的内存/资源泄漏、竞态导致功能错乱 |
| **P1** | 明显性能问题（掉帧/阻塞主线程）、架构违规且实际阻碍多后端扩展、i18n 间接层回潮 |
| **P2** | 耦合/重复/可维护性问题，不立即出事但持续增加维护成本 |
| **P3** | 风格与一致性建议 |

## 5. 证据要求

- 每条 finding 必须给出 `文件路径:行号` + 关键代码摘录（≤10 行）。
- **禁止臆测**：没有读到代码就不写结论；推断但未验证的结论必须标 `[需复核]`。
- 性能问题尽量说明触发路径（什么操作、什么频率会踩到）。

## 6. finding 输出格式（统一）

写入你的 findings 文件（`docs/codex-review/findings/<你的任务字母>.md`），每条格式：

```markdown
### [A-012] 一句话标题
- 级别: P1
- 分类: 性能 / 耦合 / 可维护性 / 可扩展性 / Bug / 约束违规(C3)
- 位置: lib/xxx/yyy.dart:123
- 问题: 具体描述，含代码摘录
- 建议方向: 一两句话的修复思路（不要写完整代码）
- 状态: 待复核
```

编号前缀用你的任务字母（A/B/C/D/E/F/G/H），全文件内递增，**不要重排已有编号**。

## 7. 工作协议（防上下文压缩丢失 + 挂机续跑，所有窗口必须遵守）

1. **开工顺序**：读本文档 → 读你的 TASK 文档 → 读你的 findings 文件头部的 checkpoint 区块（若存在）→ 从断点继续。
2. **findings 文件头部维护 checkpoint 区块**，每审完一个文件立即更新：

   ```markdown
   <!-- CHECKPOINT
   已审文件数: 17 / 42
   最后完成: lib/services/foo_service.dart
   下一个: lib/services/bar_service.dart
   阶段: 第一轮逐文件评审 | 第二轮自复核 | 已完成
   更新时间: 2026-07-02 21:30
   -->
   ```

3. **增量落盘**：发现问题立即追加写入 findings 文件，**绝不攒在内存/上下文里等最后一起写**。上下文随时可能被压缩，落盘的才是真的。
4. **大文件分段读**：单次读取不超过 ~400 行，按段推进；不要把几千行的文件一次性拉进上下文。
5. **压缩/重启恢复**：任何时候发现自己不记得任务细节（被压缩了或新会话），立即重做第 1 步。已审过的文件（checkpoint 之前的）不要重审。
6. **第一轮完成后进入第二轮自复核**：逐条重新打开 finding 对应的代码，验证真实性，把 `状态` 改为 `已确认` 或 `撤回(原因)`；误报直接标撤回，不删除条目。
7. **两轮全部完成后**：把 `docs/codex-review/PROGRESS.md` 中自己那一行状态改为 `DONE`，并在 findings 文件末尾写一段 ≤20 行的总结（问题分布、最值得优先处理的 3~5 条）。
8. **禁止事项**：不改代码文件；不动其他任务的 findings 文件；不运行会改动仓库状态的命令（build 产物类除外）；不 git commit。
