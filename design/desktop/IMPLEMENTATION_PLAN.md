# Windows 桌面端实施规划（播放页以外）

> 设计来源：`design/desktop/DESIGN_NOTES.md` + `design/desktop/index.html` 原型（已验证）。
> 本轮范围：**桌面端浏览/管理 UI**。播放页/播放内核明确搁置（后续需兼顾 Linux，可能 macOS / iOS，候选 media_kit/libmpv，另行立项）。
> 基线：`main@9500db2`（含海报卡统一 wip 快照；不含当前 poster-browse 分支未合并的 2 个播放器修复——与本轮无关）。

## 一、分支树

```
main (9500db2)
└─ feat/desktop-shell                 ← 主干：桌面基础模块 + windows 平台目录（本轮由主干进程直接开发）
   ├─ feat/desktop-nav                ← A：桌面侧栏 Shell + 键盘快捷键（进程 A）
   ├─ feat/desktop-home               ← B：桌面首页布局 + 悬停/右键菜单 + 三后端表现（进程 B）
   ├─ feat/desktop-settings           ← C：双栏设置页（进程 C）
   └─ feat/desktop-detail-pane        ← D：分屏详情宿主 + 播放入口桌面守卫（进程 D）
```

合并顺序：A → trunk，随后 B/C/D 依次 rebase + 合并（文件所有权互斥，预期无冲突）。
每个分支合入前必须：`flutter analyze` 不新增问题（基线 1 个既有 warning）+ `flutter test` 不新增失败（基线 2 个既有失败）。

## 二、进程/任务分配与文件所有权（互斥）

| 进程 | 分支 | 负责文件（独占） | 交付物 |
|---|---|---|---|
| 主干 | feat/desktop-shell | `lib/desktop/**`、`windows/**`、`design/desktop/**`、AGENTS.md | 基础模块：环境判定 / 断点 / 分屏控制器 / HoverLift / 右键菜单 / token；windows runner |
| A | feat/desktop-nav | `lib/main.dart`（MainNavigation 区段）、`lib/desktop/desktop_shell.dart`、`lib/desktop/desktop_side_bar.dart`、对应测试 | 桌面侧栏 Shell（≥1024px 生效）、快捷键（Ctrl+K/数字/Esc）、分屏开关挂点 |
| B | feat/desktop-home | `lib/ui/layout_adaptive.dart`、`lib/screens/media_list_screen*.dart`、`lib/screens/home/**`、对应测试 | 桌面密度档位、货架悬停箭头、卡片 HoverLift、卡片右键菜单（复用动作表逻辑） |
| C | feat/desktop-settings | `lib/screens/app_settings_screen.dart`、`lib/screens/settings/**`、对应测试 | ≥1024px 双栏设置（左分类右内容），窄屏保持现状 |
| D | feat/desktop-detail-pane | `lib/desktop/desktop_detail_pane_host.dart`、`lib/screens/detail_host_screen.dart`（如需复用）、`lib/controllers/item_playback_launcher.dart`、对应测试 | `PlayerPaneHostController` 桌面实现（内嵌 Navigator，复用 pane 模式详情页）；播放入口桌面守卫（提示内核规划中） |

跨分支集成缝（由主干在合并时处理）：`DesktopSplitController.paneHostBuilder` —— A 的 Shell 读取该字段渲染右栏；D 在合并进 trunk 时接线。

## 三、三后端（飞牛 / Emby / Jellyfin）表现要求

首页与分类页已按后端给出三种卡片表现（`home_catalog_presentation.dart`）：
- 飞牛 `officialCollage`（1:1.34 拼贴卡）
- Emby `cinematicBackdrop`（16:9 大图卡）
- Jellyfin `clearGallery`（16:9 描边画廊卡）

桌面化改造**必须**：
1. 三种表现在桌面密度下逐一验证（B 需新增覆盖三种 presentation 的 widget 测试）；
2. 图片请求宽度维持 `MediaLayoutProfile` 的固定物理解码宽度策略（不随分屏/窗口抖动改变缓存键）；
3. 详情 pane（D）不得绕过 `DetailArtworkResolver` / `MediaImageRef` 的后端中立取图管线（飞牛相对路径 + NAS header 与 Emby/Jellyfin 自鉴权直链两条路都要通）；
4. 侧栏/设置中的后端能力开关（如“最近添加”区块有无）不得假定后端类型，继续走 `media_backend_capabilities.dart`。

## 四、代码复用清单（禁止复制粘贴的部分）

- 分屏详情：`PlayerPaneHostScope`/`PlayerPaneHostController`（`lib/ui/player_pane_host_scope.dart`）已有 Flutter 侧 pane 通道，`EmbeddedDetailLauncher` 在 scope 存在时完全不走平台通道 —— D 直接实现该接口，不改接口本身。
- pane 模式页面：`PlayDetailScreen` / `TvDetailPage` / `TvSeasonDetailPage` / `PersonDetailScreen` 均已支持 `DetailPresentation.pane`，D 复用 `DetailHostScreen` 的内嵌 Navigator 思路。
- 卡片动作：右键菜单复用 `media_item_action_sheet_controller.dart` 的既有动作集合，仅换触发方式（onSecondaryTapUp）。
- 导航：侧栏次级入口直接 `pushNamed('/screen/search')` 等既有命名路由；不新建路由表。
- 主题：桌面 token 只存尺寸/圆角/动效，颜色一律 `context.appColors` 读取，保证 7 套主题与亮暗模式自动生效。

## 五、里程碑

| # | 内容 | 完成判据 |
|---|---|---|
| M1 | 主干基础模块 + windows 平台目录 | ✅ c5c8f56 + 1d3adbe |
| M2 | A 合入：桌面 Shell 生效 | ✅ 8b16aed（feat/desktop-nav d59c826） |
| M3 | B/C/D 合入 | ✅ 575b3a3（B）/ a2b3259（D）/ 16099b9（C），D 宿主已在 Shell 接线 |
| M4 | trunk 终验 | ✅ analyze 1 issue = 基线既有 warning；test 1054 过 / 2 失败（与基线相同 2 条），新增 34 测试全绿 |

## 六、明确不做（本轮）

- 播放页/播放内核（media_kit 选型另立分支）；桌面端播放入口仅做守卫提示。
- 自绘 Windows 标题栏（需要 window_manager 等新依赖，放到 M4 后评估；路由指示器概念保留在原型）。
- 沉浸浏览页（/screen/poster-browse）的桌面化改造（现有大屏布局已可用）。
- iOS / macOS 打包与签名。
