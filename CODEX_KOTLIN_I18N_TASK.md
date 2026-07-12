# Codex 任务书：Kotlin/Android 原生层硬编码文案 i18n 化

> 执行者：Codex。监督者：Claude。框架（`strings.xml` 骨架 + 示范替换）已由监督者搭好，你的工作是**照模板把剩余硬编码 UI 文案重复替换完**。本文件是唯一权威指令。

---

## 0. 一句话目标

把 `android/app/src/main/kotlin/` 下**所有面向用户的硬编码中文 UI 文案**外置到 `res/values/strings.xml`，Kotlin 侧改用 `getString(R.string.xxx)`，保证**编译通过、运行时显示不变**，然后**分批提交**。

---

## 0.1 执行纪律：持续作业，不要中途停止（最高优先级）

- 这是**长任务**，目标是把 `android/.../kotlin/` 全部跑完。**做完一批立即开始下一批，不要停下来等确认、不要问「要不要继续」。**
- **不要因为「单个批次完成」就结束整个任务。** 一批 commit 完成后紧接下一批，直到所有文件 + 收尾扫描全部完成。
- 即使**用尽当前时间/额度（如 5 小时上限）也继续推进**；中断后下次启动**从上次断点的下一批继续**，直到原生层再无可迁移的硬编码 UI 文案。
- 唯一允许停下的情形：①编译报错且你无法自行修复；②出现本任务书未覆盖、需监督者裁决的边界。两种情形都先把当前批次提交或回滚到干净状态、写清卡点再停。其余一切继续。

---

## 1. 已搭好的框架（直接复用，禁止另起炉灶）

| 项 | 值 |
|---|---|
| 资源文件 | `android/app/src/main/res/values/strings.xml`（**已创建**，含示范 key + 分组注释） |
| 引用方式 | `context.getString(R.string.xxx)` / `getString(R.string.xxx)` / 带参 `getString(R.string.xxx, arg)` |
| `R` 类 | 文件里**已在用** `R.xxx`（如 `R.mipmap.ic_launcher`），**无需额外 import** `R` |
| 不新增语言 | 与 Flutter 任务一致：**只做文案外置**，**不建 `values-en/` 等第二语言目录** |

### 已完成的示范替换（你的模板，照抄这个套路）
- `NativePlaybackMediaService.kt`：通知动作 `"暂停"/"播放"/"快进10秒"`、`"正在播放"` → `getString(R.string.notification_*)`（Service 自带 Context，直接 `getString`）。
- `NativePlayerActivity.kt:3444` 附近：`contentDescription = "切换为列表"/"切换为宫格"` → `context.getString(R.string.player_episode_switch_to_*)`（在 `View.apply{}` 块内，用 **View 的 `context`**，不要用 Activity 的 `getString`，会被 receiver 遮蔽）。

---

## 2. Context 获取策略（Kotlin i18n 的最大难点，务必照此判断）

| 所在类型 | 怎么拿字符串 |
|---|---|
| `Activity` 方法体内 | 直接 `getString(R.string.x)` |
| `Service` 方法体内 | 直接 `getString(R.string.x)` |
| `View.apply { }` / 自定义 View 内 | 用 **`context.getString(...)`**（View 自带 `context`），**别用外层 Activity 的 `getString`** |
| `Fragment` 内 | `getString(R.string.x)`（Fragment 有该方法） |
| **无 Context 的纯逻辑类**（mapper / store / parser / model / coordinator 等） | **不要硬塞 Context**。两种合规做法：①该文案其实是给开发者看的日志/异常 → 按第 3 节**不迁移**；②确实展示给用户 → 把 `Context`（或已取好的 `String`）作为参数从调用方传入，由有 Context 的上层取好再传下来 |

> 红线：**不要为了 i18n 给纯逻辑类硬加 `Context` 依赖或静态持有 `applicationContext`**。拿不准就放进「待确认清单」交监督者。

---

## 3. 哪些要迁移 / 哪些不迁移

### ✅ 必须迁移（用户屏幕上会看到的）
- `Toast.makeText(..., "中文", ...)`
- 通知：`setContentTitle/setContentText/NotificationCompat.Action` 的文案、通知 channel 的**用户可见名称/描述**
- 对话框：`AlertDialog` 的 `setTitle/setMessage`、按钮文案
- `contentDescription`（无障碍标签，读屏会念）
- 直接 `setText("中文")` 到可见 `TextView`/按钮 的文案

### ❌ 不要迁移（保持原样）
- **注释**里的中文（不动）
- **日志**：`Log.d/Log.e/Log.w/println`、`Exception("内部错误...")` 等**纯给开发者**的文案
- **协议常量**：`MethodChannel("...")` 名、mpv 属性/选项 key、Intent action、SharedPreferences 存储 key、JSON 字段名、enum/常量名
- `android:label` 等产品名（`fly_player`，英文，不动）
- 已经走 `getString` 的代码

> 判断准则同 Flutter 任务：**「这个字符串会不会出现在用户屏幕（或被读屏念出）？」** 是 → 迁移；只有开发者/机器看到 → 不动。`NativePlayerActivity.kt` 等文件里**绝大多数中文是注释和日志**，不要误迁。拿不准的进「待确认清单」，不要擅自处理。

---

## 4. 命名规范（strings.xml 的 key）

- **snake_case**（Android 惯例，区别于 Flutter 的 camelCase）。
- **按模块前缀分组**，沿用 `strings.xml` 里已有分组：`notification_*` / `player_*`，并按需新增 `detail_*` / `parallel_*` / `mpv_*` / `storage_*` / `screenshot_*` 等。
- **先搜索再新增**：加 key 前在 `strings.xml` 里找同义文案能复用就复用（如「确定/取消」统一一个 key）。
- 含格式参数用占位符：`<string name="player_speed_x">%1$.2f 倍速</string>` → `getString(R.string.player_speed_x, speed)`。
- **转义规则**（写进 strings.xml 时务必遵守，否则编译失败或显示异常）：
  - `'` → `\'`（或整串用双引号包裹）
  - `"` → `\"`
  - `&` → `&amp;`，`<` → `&lt;`
  - `%` 字面量（非占位符）→ `%%`
  - 文案首尾若需保留空格，用 `"…"` 双引号包裹整串。

---

## 5. 工作流程（强制分批，禁止一把梭）

按文件分批，建议顺序（由「用户可见文案密集」到「零散」）：
> 1. `NativePlaybackMediaService.kt`（通知，示范已起头，补完整文件）
> 2. `NativePlayerActivity.kt`（量最大，但**多数是注释/日志**；只挑 Toast/Dialog/contentDescription/可见 setText，**可再拆子批**）
> 3. `ExternalLocalVideoActivity.kt` / `PlaybackSessionManager.kt`（含 Toast/通知）
> 4. `mpv/output/*.kt`（轨道/视频/音频设置里给用户的提示）
> 5. 其余 `*.kt` 逐个扫，仅迁移确实可见的文案
> 6. 收尾扫描：全 `kotlin/` 复查遗漏

**每批标准步骤：**
1. 用 `rg` 在该文件找硬编码中文，逐条按第 3 节判定「迁/不迁」。
2. 迁的：在 `strings.xml` 对应分组新增（或复用）key。
3. 改 Kotlin：按第 2 节策略改为 `getString(R.string.xxx)`。
4. 编译验证（第 6 节）。
5. 自检通过后提交（第 7 节）。

---

## 6. 编译与自检（全过才能提交）

```bash
# Windows（项目根）：编译 Kotlin / 出 debug 包，二选一
cd android && ./gradlew.bat compileDebugKotlin    # 快，仅验证 Kotlin 编译
# 或
flutter build apk --debug                          # 完整构建
```

每批自检清单：
- [ ] 编译通过（`compileDebugKotlin` 或 `build apk --debug` 成功）。
- [ ] 所有新增 `R.string.xxx` 在 `strings.xml` 里都有对应 `<string>`。
- [ ] 没有给纯逻辑类硬塞 Context（第 2 节红线）。
- [ ] 没有动注释、没有迁日志/协议常量。
- [ ] 抽查 3~5 处，确认运行时文案与原中文一字不差。
- [ ] `strings.xml` 转义正确（无未转义的 `'` `%` `&` `<`）。

---

## 7. 提交规范

- **每批一个 commit**，中文 message：
  ```
  i18n(android): <文件/模块> 硬编码文案外置到 strings.xml

  - 迁移 <文件> 共 N 条用户可见文案
  - strings.xml 新增 key M 个（snake_case，<前缀> 分组）
  - compileDebugKotlin 通过，运行时文案不变
  ```
- 不要 `--no-verify`，不跳过 hook。提交前 `git status` 确认无意外改动。

---

## 8. 交付报告（每批回报监督者）

1. 本批覆盖的文件。
2. 新增 key（key 名 + 中文值）/ 复用的 key。
3. **待确认清单**：拿不准迁不迁、或纯逻辑类无 Context 难取的（文件:行 + 原文 + 倾向），交监督者裁决。
4. 编译结果。

---

## 9. 范围红线

只做 `android/app/src/main/kotlin/` 的原生文案外置 + 配套 `strings.xml`。**不要碰 Flutter 层 `lib/`**（那是另一份任务书）。不要顺手重构、不改业务逻辑、不改 mpv/协议常量、不加第二语言。**只做文案外置这一件事。**
