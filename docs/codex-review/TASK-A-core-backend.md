# TASK A —— 核心骨架与多后端抽象层评审

> 先完整阅读 `docs/codex-review/00-review-constraints.md`（约束标准 + 工作协议），再开工。
> findings 写入 `docs/codex-review/findings/A.md`，编号前缀 `A-`。

## 范围（约 1.7 万行）

按此顺序逐文件评审：

1. `lib/main.dart`（路由解析 `_buildRoute()`、Provider 装配、启动链路）
2. `lib/api/`（4 个文件，重点 `feiniu_api.dart`）
3. `lib/media_backend/`（28 个文件，多后端抽象层核心）
4. `lib/providers/`（6 个文件）
5. `lib/controllers/`（8 个文件）
6. `lib/models/`（17 个文件）

## 排除

- 不审 `lib/l10n/`（生成代码）。
- `lib/providers/nas_provider.dart` 中的 MethodChannel 部分只记录位置不深审（归 TASK C），其余逻辑正常审。

## 本区域重点检查项

1. **[C3] 多后端抽象是不是真抽象**——这是本任务的第一优先级：
   - `lib/media_backend/` 的接口设计里有没有为飞牛/Emby 特化的参数、字段、方法名泄漏到公共接口；
   - 调用方拿到抽象接口后有没有 downcast 回具体实现；
   - 新增一个 Jellyfin 后端需要改多少公共文件？凡是"接新后端必须改"的公共代码点，逐个上报为可扩展性问题。
2. **[C2] `feiniu_api.dart` 的直接消费者**：全局 grep 它的 import，列出所有 UI/页面直接调用点（本任务只汇总清单，具体页面细节由 F/G 窗口审）。
3. **`lib/api/feiniu_api.dart` 本身**（~3.7k 行量级）：单一职责([C6])、错误处理([M4])、Dio 拦截器/超时/重试策略、是否混入了与 NAS API 无关的职责。
4. **models 层**：JSON 解析健壮性（字段缺失/类型不符会不会抛）、模型里混入 UI 展示逻辑（应属 presenter）的情况。
5. **providers**：粒度是否过粗（一个 provider 变更导致大范围 rebuild，[P4]）、生命周期与 dispose（[P6]）。
6. **路由**：`_buildRoute()` 的 URI 解析健壮性（非法参数、缺参会不会崩）；路由 payload 传递方式是否类型安全。
7. 通用项全查：[M3] i18n、[M4] 错误处理、[M5] 死代码、[P7] async gap。

## 完成标准

第一轮逐文件 + 第二轮自复核（见 00 文档第 7 节协议），最后更新 PROGRESS.md 中 TASK A 状态为 DONE。
