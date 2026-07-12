# Codex 任务书：Flutter 层硬编码文案全面 i18n 化

> 执行者：Codex。监督者：Claude。本文件是**唯一权威指令**，开工前务必通读，执行中遇到与本文件冲突的旧习惯一律以本文件为准。

---

## 0. 一句话目标

把 `lib/` 下**所有面向用户的硬编码中文 UI 文案**全部迁移到 l10n（`AppLocalizations`），保证 `flutter analyze` 干净、`flutter gen-l10n` 成功、运行时显示不变，然后**分批提交**。

---

## 0.1 执行纪律：持续作业，不要中途停止（最高优先级）

- 这是一个**长任务**，目标是把 `lib/` 全部跑完。**做完一批立即开始下一批，不要停下来等确认、不要问「要不要继续」。**
- **不要因为「单个批次完成」就结束整个任务。** 一批 commit 完成后，紧接着进入下一批，直到第 5 节列出的所有批次 + 收尾扫描全部完成。
- 即使**用尽当前时间/额度（如 5 小时上限）也继续推进**；中断后下次启动**从上次断点的下一批继续**，直到 `lib/` 再无可迁移的硬编码 UI 文案。
- 唯一允许停下的情形：
  1. `flutter analyze` 或 `flutter gen-l10n` **报错且你无法自行修复**；
  2. 出现第 9 节所说、本任务书未覆盖、需要监督者裁决的边界情况。
  以上两种情形：**把当前批次改动提交或回滚到干净状态**，写清楚卡点，再停。其余一切情况一律继续。
- 完成判定（全部满足才算整个任务结束）：`rg` 全 `lib/` 已无面向用户的硬编码中文 UI 文案（注释/日志/协议常量除外）、所有批次均已 commit、`flutter analyze` 干净。

---

## 1. 现有 i18n 基础设施（必须复用，禁止另起炉灶）

| 项 | 值 |
|---|---|
| l10n 配置 | `l10n.yaml`（项目根） |
| arb 目录 | `lib/l10n/` |
| **模板 arb** | `lib/l10n/app_zh_CN.arb`（`template-arb-file`，新增 key 以它为准） |
| **同步 arb** | `lib/l10n/app_zh.arb`（必须与模板**逐 key 同步**） |
| 生成目录 | `lib/l10n/generated/`（**自动生成，禁止手改**） |
| 生成类 | `AppLocalizations`（`nullable-getter: false`） |
| 现有 key 数量 | 约 2400 条，已成体系 |
| `pubspec.yaml` | `generate: true` 已开启 |

### 取值方式（唯一正确写法）

```dart
// widget 内（有 BuildContext）：
final l10n = AppLocalizations.of(context);
Text(l10n.commonCancel);

// 直接内联也可：
title: AppLocalizations.of(context).playerAudioSelectTitle,
```

```dart
// controller / service / 无 BuildContext 的纯逻辑层：
// 不要在这些层 import flutter material 去硬拿 context。
// 由调用方（widget）取好 l10n，作为参数传进来：
static String _seasonLabel(AppLocalizations l10n, int seasonNumber) => ...
void showSheet(BuildContext context, {required AppLocalizations l10n}) { ... }
```

> 参考现有实现：`lib/controllers/media_item_action_sheet_controller.dart` 已是「widget 取 l10n → 传参进 controller」的范式，照抄这个范式。

---

## 2. 绝对禁止事项（违反即返工）

1. **禁止 `_t(path, fallback)` 这类间接层**，禁止 `AppLocalizationLookup`、禁止任何「字符串路径 + 兜底文案」的封装。一律直接用 `AppLocalizations` 的 getter。（项目已专门清除过这种间接层，不要复活它。）
2. **禁止臆造 key**：每个 key 必须真实存在于两个 arb 文件中并能通过 `gen-l10n` 生成 getter。
3. **禁止只改一个 arb**：`app_zh_CN.arb` 和 `app_zh.arb` 必须同时加同一个 key、同一个中文值。
4. **禁止动态拼接中文**：不要写 `'第' + n + '集'`。用带占位符的 key：`l10n.episodeLabel(n)`。
5. **禁止改动 `lib/l10n/generated/` 下的任何文件**（它们由工具生成）。
6. **禁止改变运行时显示文案**：迁移前后用户看到的中文必须**一字不差**。

---

## 3. 哪些要迁移 / 哪些不迁移

### ✅ 必须迁移（面向用户的 UI 文案）
- `Text('...')`、`SnackBar`、`Tooltip`、`AlertDialog` 的标题/正文/按钮、`hintText`、`labelText`、`semanticLabel`
- 列表项标题、空态文案、错误提示、加载文案、菜单项、设置项标题与副标题
- 任何最终会渲染到屏幕给用户看的中文字符串

### ❌ 不要迁移（保持原样）
- **代码注释**里的中文（注释保留中文，不动）
- **日志 / 诊断字符串**：`debugPrint`、`log()`、`assert` 消息、异常 `throw Exception('内部错误...')` 中**纯给开发者看**的文案（除非它会直接展示给用户）
- **log tag / channel name / mpv option key / 网络参数 key**（如 `MethodChannel('...')`、mpv 属性名、API 字段名）——这些是协议常量，不是 UI
- **enum 名、map 的 key、SharedPreferences 的存储 key**
- 已经走 `AppLocalizations` 的代码

> 判断准则：**「这个字符串会不会出现在用户屏幕上？」** 是 → 迁移；只有开发者/机器会看到 → 不动。拿不准的，标注到交付报告的「待确认清单」里，不要擅自迁移也不要擅自跳过。

### 3.1 语言切换设置（特别说明）

- `lib/screens/app_settings_screen.dart` 里的**语言切换设置面板**及相关文案，**纳入本次迁移范围**，确保它每一条文案都走 `AppLocalizations`、无任何硬编码遗漏。
- **本次不新增任何语言**：`AppLocaleMode` 维持 `system` / `zhCN` 两项，**不要**新增英文/`app_en.arb`、不要动 `supportedLocales`、不要改 `AppLocaleProvider` 的枚举。只做文案外置。
- 语言切换已正确接到 `MaterialApp.locale`（`lib/main.dart`），**不要重构这条链路**。

---

## 4. 命名规范（key 命名）

- camelCase，**按功能域加前缀**，沿用现有体系。已有前缀示例：
  - 通用：`common*`（`commonCancel`/`commonSave`/`commonNoData`）
  - 导航/设置：`nav*` / `settings*`
  - 播放器：`player*`
  - 弹幕：`danmaku*`
  - 媒体/合集：`media*` / `collection*`
  - 鉴权：`auth*`
- **先搜索再新增**：加 key 前先在 `app_zh_CN.arb` 里 grep 同义文案，**能复用就复用**（例如「取消」一律用 `commonCancel`，绝不再造 `cancelButton`）。
- 占位符/复数用 arb 标准写法，并补 `@key` 元数据块：
```json
"collectionItemCount": "共 {count} 项",
"@collectionItemCount": {
  "placeholders": { "count": { "type": "int" } }
}
```
  生成后调用：`l10n.collectionItemCount(count)`。

---

## 5. 工作流程（强制分批，禁止一把梭）

按目录/模块**分批**处理，每批是一个可独立验证、可独立提交的闭环：

> 建议批次顺序（由简到繁，每批一个 commit）：
> 1. `lib/screens/`（各二级页面）
> 2. `lib/widgets/detail/`（详情页组件）
> 3. `lib/pages/`（详情主页面）
> 4. `lib/player/page_parts/`（播放器各 mixin，量大，可再拆子批）
> 5. `lib/danmaku/`（弹幕 UI 部分）
> 6. `lib/controllers/` + `lib/services/`（仅迁移确实展示给用户的部分）
> 7. 收尾扫描：全 `lib/` 复查遗漏

**每一批的标准步骤：**
1. 用 `rg` 在该批目录里找硬编码中文 UI 文案（排除注释/日志/协议常量，见第 3 节）。
2. 对每条文案：先在 arb 里找可复用 key；没有则在**两个 arb** 同时新增 key（值为原中文）。
3. 改代码：把硬编码替换成 `AppLocalizations.of(context).xxx`（或传参的 `l10n.xxx`）。
4. 跑 `flutter gen-l10n`（或 `flutter pub get`）重新生成。
5. 跑 `flutter analyze`，必须**零报错零新增 warning**。
6. 自检（第 6 节）通过后提交（第 7 节）。

---

## 6. 每批自检清单（全过才能提交）

- [ ] `app_zh_CN.arb` 与 `app_zh.arb` 的 key 集合完全一致（数量、名字都对得上）。
- [ ] 所有新增 key 都能在 `lib/l10n/generated/app_localizations.dart` 里找到对应 getter。
- [ ] `flutter gen-l10n` 成功，无报错。
- [ ] `flutter analyze` 干净（与本批改动前相比无新增问题）。
- [ ] 本批没有动 `generated/` 目录、没有动注释、没有改协议常量。
- [ ] 抽查 3~5 条迁移点，确认运行时文案与原中文一字不差。
- [ ] 没有引入 `_t(...)` 间接层、没有臆造 key。

> arb 双文件同步可用一条命令快速核对 key 数：
> `rg -c '^\s*"' lib/l10n/app_zh_CN.arb lib/l10n/app_zh.arb`（仅作粗核，最终以 `gen-l10n` 成功为准）

---

## 7. 提交规范

- **每批一个 commit**，不要把所有批塞进一个巨型 commit。
- commit message 用中文，格式：
  ```
  i18n(flutter): <模块> 硬编码文案迁移至 l10n

  - 迁移 <目录/文件> 共 N 条 UI 文案
  - 新增 key M 个（已同步 app_zh_CN.arb / app_zh.arb）
  - flutter analyze 通过，运行时文案不变
  ```
- 不要 `--no-verify`，不要跳过 hook。
- 提交前确认 `git status` 不包含 `generated/` 之外的意外改动。

---

## 8. 交付报告（每批完成后回报给监督者）

每批结束输出一段简报，包含：
1. 本批覆盖的目录/文件清单。
2. 新增了哪些 key（key 名 + 中文值）。
3. 复用了哪些已有 key。
4. **待确认清单**：拿不准该不该迁移的字符串（文件:行 + 原文 + 你的判断倾向），交监督者裁决。
5. `flutter analyze` 结果截图/文本。

---

## 9. 边界与升级

- 遇到「同一句中文在多处出现」→ 统一成**一个 key**复用。
- 遇到「中文里嵌变量/复数/性别」→ 用 arb 占位符，**不要**字符串拼接。
- 遇到「不确定是 UI 还是协议常量」→ **不要赌**，放进待确认清单。
- 遇到本文件没覆盖的情况 → 停下，写进待确认清单，**不要自行扩大改动范围**。

---

## 10. 范围红线

只做 Flutter 层（`lib/`）的 i18n 迁移。**不要碰 Android/Kotlin 层**（那是另一个独立任务，有单独的任务书）。不要顺手重构、不要改业务逻辑、不要动样式与布局。**只做文案外置这一件事。**
