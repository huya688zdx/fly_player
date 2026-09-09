# 飞翔播放器 · Windows 桌面端设计规划

> 配套原型：`design/desktop/index.html`（+ `styles.css` / `app.js`，纯静态、零依赖，双击即可打开）。
> 本文说明原型的每一步设计如何映射到现有 Flutter 代码，以及落地到 Flutter 桌面端的改造建议。

---

## 一、设计原则（从现有代码推导）

1. **信息架构完全不动**：现有双 tab（影视 / 设置）+ URI 路由 + 详情页体系全部保留，桌面端只换"容器"——底部胶囊导航 → 左侧栏，单栏页面 → 可分栏。
2. **键鼠优先**：每个手机端"长按动作表"升级为右键菜单；所有页面键盘可达（数字键切导航、Esc 逐级返回、`Ctrl+K` 全局搜索、空格/方向键控制播放）。
3. **复用分屏体系**：代码里已有完整的 pane 化详情页（`DetailHostScreen` + `EmbeddedDetailLauncher` + 42/58、50/50、35/65、45/55 比例预设），桌面端把它从"平板可选"提升为"核心交互"：浏览 | 详情 双栏。
4. **视觉零迁移成本**：全部颜色 token 取自 `lib/theme/app_theme.dart` 的 midnight 预设，7 套主题 + 8 个强调色在原型里可实时切换验证。

## 二、布局骨架映射

| 手机/平板现状 | 桌面端方案 | 对应现有代码 |
|---|---|---|
| 底部悬浮胶囊 `_LiquidGlassBottomNavigation`（2 tab） | 左侧栏 216px：影视 / 沉浸浏览 / 搜索 / 收藏 / 下载 + 设置，底部 NAS 连接状态卡 | `main.dart MainNavigation`、`MainPrimaryTab` |
| AppBar 右上角搜索/大屏浏览图标 | 侧栏独立项 + 首页右上搜索框（`Ctrl+K`） | `media_list_screen.dart` AppBar actions |
| 全屏单页导航 | 主内容区 + 可选右侧详情栏（分屏） | `detail_host_screen.dart`、`EmbeddedDetailLauncher` |
| 无标题栏（Android 沉浸式） | Windows 标题栏：应用身份 + **URI 路由指示器**（实时显示 `flyplayer:///...` 当前路由） + 最小化/最大化/关闭 | `main.dart _buildRoute()` |
| 长按弹出动作表 | 卡片右键菜单（播放/详情/分屏打开/收藏/下载/已看） | `media_item_action_sheet_controller.dart` |

## 三、路由映射（原型可点）

| 原型 hash | 展示为 | 真实路由 |
|---|---|---|
| `#/home` | 首页 | `/` |
| `#/tv?id=tv_ferry` | 剧集详情 | `/detail/item?itemGuid=…` |
| `#/season?id=…&s=1` | 季选集页 | `/detail/season?seriesGuid=…&season=…` |
| `#/screen/search` `#/screen/favorites` `#/screen/downloads` `#/screen/settings` `#/screen/category?type=…` `#/poster-browse` | 各次级页 | 同名 `/screen/*` 路由 |
| 分屏打开详情 | 标题栏显示 `主路由 ⇢ 详情路由` | `/detail/host`（pane 模式） |

完整跳转链路（原型已验证）：**首页续看卡/海报 → 剧集详情 → 季卡 → 季选集页 → 单集 → 播放器**，Esc 逐级返回。

## 四、各页面设计要点

### 首页
- 区块顺序与 `home_presentation_profile.dart` 完全一致：媒体库入口（collage 卡 1.34）→ 继续观看（16:10 横版卡 + 进度条 + 圆形播放钮 + 已下载徽章）→ 播放下一集 → 最近添加 → 统计行（5 张玻璃卡，可点跳转）→ 各库海报行。
- 横向货架在桌面端增加**悬停出现左右箭头**（点击滚动 80% 视口宽）；海报卡 hover 上浮 + 光泽扫过 + accent 描边。
- 海报卡规格照抄 `media_poster_card.dart`：2:3、圆角 10、左上评分徽章、右下清晰度徽章、已看角标、底部黑渐变。

### 详情页（电影 / 剧集）
- 沉浸 hero（backdrop + 左重渐变 + logo 英文名 + 大标题）对应 `ImmersiveDetailBackground`；滚动后浮层标题淡入，对应 `DetailFloatingTopBar` collapse。
- 能力徽章行（字幕/音轨/HDR）= `DetailSelectorRow`；6px 进度 + 主播放按钮（56px 高、accent 填充）+ 收藏/下载/已看圆钮 = `PlayActionBar`；版本 chips = `DetailResolutionSection`；演职员圆形头像行点击进人物页（原型 toast 占位）。
- 桌面增强：右侧文件信息双卡（路径/容器/码率/音轨），对应 `FileInfoSection`。

### 季选集页（`TvSeasonDetailPage`）
- 海报悬浮桥接头图（poster 与面板重叠）+ 金色评分 `#F2D34B` + 播放第 1 集。
- 季切换 tabs + 分段 chips（全部/1-6/7-12）+ **全量选集网格**（桌面有空间，从手机端"前 4 集预览 + 底部抽屉"扩展为直接平铺：封面缩略图、集号、标题、时长、已看/看到 x%）。
- 点任意集 → 播放器，并把该季写入选集面板。

### 播放器（桌面需要自建，替代 `NativePlayerActivity`）
- 全屏覆盖层：顶部（返回/标题/弹幕开关/画质/截图/小窗）、中央大播放钮（闲置自动隐藏 UI）、底部（缓冲+进度拖拽、上一集/下一集、音量滑杆、时间、弹幕设置/字幕/音轨/倍速/**选集面板**/设置/全屏）。
- **右侧选集抽屉** = 原生壳"选集面板"的桌面版：季 tabs + 封面缩略图列表 + 当前进度高亮 + 已看勾。
- 弹幕层独立开关；快捷键：Space、←→ 快进退 10s、↑↓ 音量、F 全屏、Esc 退出。
- 落地建议：Flutter 桌面端用 `media_kit`（libmpv）直接内嵌 Widget，播放逻辑仍复用 `ItemPlaybackLauncher` 解析出的 `MpvMediaSource`，不再经 MethodChannel 拉 Activity。

### 沉浸浏览（`/screen/poster-browse` 大屏布局）
- 左侧媒体信息区（索引/标题/评分/简介/播放）+ 底部海报轨道（焦点放大 + accent 光环、远端淡出）+ 背景随焦点取色，`←→` 切焦点、`Enter` 进详情 —— 即 `PosterBrowseLargeLayout` 的桌面化。

### 设置（桌面双栏）
- 左侧分类（外观主题/播放器/弹幕/下载/存储/统计/快捷键/关于）+ 右侧内容。
- **7 套主题预设 + 8 个强调色点击实时生效**（原型用 CSS 变量模拟 `AppThemeColors` token 替换）；动态主题三档强度、氛围光晕开关等一一对应设置项。

### 分屏浏览（核心桌面特性）
- 侧栏底部开关「分屏浏览」：开启后主区变为 `浏览列 | 详情栏`，点击任意海报在右栏打开详情，**主列表位置不动**（对应副栏版首页的 reduced 数据策略）。
- 比例 chips 42/58、50/50、35/65 直接使用 `parallel_window_settings_screen.dart` 的既有预设；Esc 关闭详情栏。
- 原型实现方式（把详情页 DOM 移入右栏容器）演示了现有代码"详情页已支持 pane 模式"的可行性。

## 五、落地到 Flutter 桌面端的改造清单

1. **窗口壳**：`window_manager`/`bitsdojo_window` 自绘标题栏（或保留系统标题栏），记住窗口尺寸/位置；标题栏可放迷你播放条。
2. **导航容器**：`NavigationRail`（或自定义侧栏）替换 `MainNavigation` 的 IndexedStack+底栏；路由表 `_buildRoute()` 不变，桌面端多一层 `ShellRoute` 提供双栏插槽。
3. **分屏**：`DetailPresentation.pane` 已存在 → 桌面端默认 presentation 策略改为"宽屏开分屏，窄屏全页"，比例预设直接复用。
4. **播放内核**：`media_kit` + 自建控制层（本原型即 UX 规格）；弹幕渲染层已有 Flutter 侧数据源可接。
5. **输入适配**：全局 `Shortcuts/Actions` 注册快捷键；卡片 `MouseRegion` hover 效果 + `onSecondaryTapUp` 右键菜单；焦点遍历（TV 风格 focus 已有部分基础）。
6. **视觉**：主题系统无需改动，仅需为桌面补充 hover/pressed 态 token 与更密的栅格断点（≥1280 双栏、≥1680 三列货架）。

## 六、原型文件说明

| 文件 | 内容 |
|---|---|
| `index.html` | 布局骨架：标题栏 / 侧栏 / 9 个页面 section / 播放器覆盖层 / 选集抽屉 / 右键菜单 / 快捷键弹窗 |
| `styles.css` | 全部视觉 token（7 预设 + 8 强调色 `[data-theme]`/`[data-accent]` 切换）、组件样式、分屏栅格、播放器/弹幕动画 |
| `app.js` | 路由器（hash ↔ URI 映射）、数据 mock（16 部作品）、各页渲染器、分屏挂载逻辑、播放器状态机、快捷键 |

本地预览：直接双击 `index.html`，或在 `design/desktop` 下起任意静态服务器（如 `python -m http.server`）。
