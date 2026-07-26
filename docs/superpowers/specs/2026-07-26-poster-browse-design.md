# 大屏海报浏览页设计（Poster Browse Screen）

日期：2026-07-26
状态：已获用户批准的设计规格（待出实现计划）

## 背景与目标

给播放首页新增一个"大屏海报式"浏览体验。经方案比选（顶部英雄轮播 / 沉浸全屏海报页 / 海报墙 / 横屏电视风格浏览页），选定 **横屏电视风格浏览页**：横屏全屏，聚焦条目的 backdrop 铺满背景，左下信息区（含评分），底部多行类别缩略图条，焦点驱动背景切换。

已确认的关键决策：

| 决策点 | 结论 |
| --- | --- |
| 形态 | D · 横屏浏览页（电视风格），带评分展示 |
| 定位 | 独立新页面，首页 AppBar 入口进入；不替换现有首页 |
| 内容结构 | 多行类别（继续观看 / 最近添加 / 各媒体库），上下滑切行，左右滑选条目 |
| 后端范围 | 飞牛 + Emby + Jellyfin 全部支持，行构成按后端能力降级 |
| 交互 | 首点缩略图=聚焦（切背景/标题/评分）；再点同一张或"详情"按钮=进详情；"播放"按钮=直接播 |
| 评分 | 信息区 ★ 大字 + 缩略图右上角小角标；无评分数据时两处隐藏、不占位 |

## 1. 页面定位与入口

- 新页面 `PosterBrowseScreen`，文件 `lib/screens/poster_browse_screen.dart`。
- 路由 `/screen/poster-browse`，在 `lib/main.dart` `_buildRoute()` 注册（跟随现有 `/screen/*` 规范）。
- 入口：首页（`MediaListScreen`）AppBar 搜索图标旁新增图标按钮。
- 进入时 `SystemChrome.setPreferredOrientations` 强制横屏 + `setEnabledSystemUIMode` 沉浸式（隐藏状态栏/导航栏）；退出恢复竖屏与系统 UI。
- 分屏副宿主（`MediaListScreen(secondaryHost: true)`，见 `lib/screens/detail_host_screen.dart`）**不显示入口**——横屏全屏与分屏窗口冲突。

## 2. 数据层（MediaBackend 扩展）

### 2.1 新接口方法

`lib/media_backend/media_backend.dart` 新增（默认空实现模式，与 `queryFavoriteItems` 等一致）：

```dart
/// 最近添加条目。后端不支持时返回空列表，UI 隐藏对应行。
Future<List<MediaItemCard>> getLatestItems({int limit = 20}) async => const [];
```

- **Emby**：override 走 `/Users/{userId}/Items/Latest`（映射到 `MediaItemCard`，保留 backdrop 直链与 rating）。
- **Jellyfin**：继承 Emby 实现，零额外代码。
- **飞牛**：override 走 `FeiniuApi.getItemsPage`，payload `sort_column=create_time, sort_type=DESC`（该接口原生支持此排序字段）；跨库合并取前 N。实测若排序不生效则返回空列表。

不新增 capability 开关：空列表即"不支持"，行为自然降级。

### 2.2 行构成

行构成为**纯函数**（输入：各数据源结果；输出：行列表），顺序：

1. 继续观看 —— `backend.getContinueWatching()`；飞牛保留 `FeiniuApi.getPlayList` 旁路（与首页 `_loadContinueWatching` 同款，保住 ts/续播富字段）
2. 最近添加 —— `backend.getLatestItems()`
3. 每个媒体库一行 —— `backend.getCatalogs()` + `getCatalogPreviewItems(catalogId)`

规则：任何行数据为空 → 整行隐藏，不留空位；行内条目上限约 20。

### 2.3 加载策略

- 首帧优先读 `HomeDataCache` 快照（继续观看 + 媒体库行即刻渲染），同时后台并行拉全量数据，diff 后更新。
- 后端切换检测：`didChangeDependencies` + loadKey（`BackendSessionProvider.currentKind` + 配置态），与首页同款模式，切后端自动重载。

## 3. UI 结构与组件复用

页面自上而下三层（Stack）：

### 3.1 背景层

- 复用 `ImmersiveDetailBackground`（`lib/widgets/detail/immersive_detail_background.dart`），图源 = 聚焦条目 backdrop 候选链，经 `DetailArtworkResolver` 统一解析（飞牛相对路径 / Emby 直链两分支同一入口）。
- 该组件自带底部渐隐；左侧渐变（保证信息区文字可读）另加一层 `DecoratedBox(LinearGradient)` 叠加。
- 动态取色：外层包 `DynamicPageThemeScope(pageKey: 聚焦条目 guid, imageUrl: backdropUrl)`，builder 的 `ambientTint` 喂 `ImmersiveDetailBackground.ambientTintOverride`。**pageKey 与详情页同键**（条目 guid）→ seed 缓存共享，从本页进详情零闪。

### 3.2 信息区（左下）

- 内容：分类标签（当前行名）→ 大标题 → 元信息行（★评分 · 年份 · 题材 · 时长 · 4K/HDR 能力角标）→ 简介（最多 2 行省略）→ 「播放」「详情」按钮。
- 任一元数据缺失时隐藏该项、不占位。
- 顶部仅"返回 + 时钟"。
- 所有文案走 l10n（arb / AppLocalizations getter），禁止硬编码中文与 `_t` 间接层。

### 3.3 缩略图行区（底部）

- 新写轻量组件：横向 `ListView` + 聚焦项 `AnimatedScale` 放大 + 白描边；16:9 横版小图（backdrop 小尺寸，无 backdrop 回退海报图 cover 裁切）。
- 评分小角标（右上）；继续观看行条目带底部进度条。
- 上下滑切行：垂直方向手势切换当前行，下一行在底部半露提示可滑。
- 交互：点非聚焦缩略图 = 聚焦；点已聚焦缩略图 = 进详情。

### 3.4 播放/详情动作

- **详情**：走现有详情路由（电影/剧集判型逻辑与首页卡片一致），hero 转场可选（同 guid seed 缓存已保证无闪）。
- **播放**：电影直接 `backend.getPlayback` → 原生播放器；剧集先 `resolveSeriesPlaybackTarget` + `resolveSeriesNextUpEpisode` 定位到集再播。复用详情页现有的启动播放封装；若其与页面耦合过深，抽出共用 helper，不复制逻辑。

## 4. 性能与视觉细节

- 焦点切换节流：背景图加载与取色请求 300ms 防抖；相邻 ±2 张 backdrop 预取。
- 背景切换：纯 `FadeTransition` 交叉淡入。**禁止** BackdropFilter/玻璃（项目已回归纯色）；**禁止**低清铺底（既有结论：垫底图与主图不同源=闪，宁可纯色等待），图未到时显示纯 ambient 色底。
- 背景大图与缩略图小图分开请求尺寸与 `decodeWidth`，遵循首页现有请求宽度规范。
- 无 backdrop 条目：竖版海报 cover 拉满 + 加重压暗层；再没有就纯 ambient 色底。

## 5. 错误与降级

- 单行请求失败：该行隐藏，其余行正常渲染。
- 全部行失败：整页错误态 + 重试按钮。
- 横屏恢复：退出恢复竖屏放 `dispose` + 返回拦截双保险，防异常退出后卡横屏。

## 6. 测试

- 行构成纯函数单测：飞牛/Emby/Jellyfin 三种能力组合 → 期望行列表（含空行隐藏、飞牛最近添加为空时的降级）。
- `getLatestItems`：Emby mapper 单测 + 飞牛 payload 构造单测（跟随 `test/media_backend/` 现有模式）。
- 更新 `test/media_backend/multi_backend_abstraction_boundary_test.dart` 边界守卫（新方法入册）。
- 焦点节流逻辑单测。
- 实机验收：三后端手测——进入/退出横屏恢复、行切换、聚焦切背景、进详情、直接播放、弱网表现。

## 非目标（本期不做）

- 不改现有首页版式（仅加一个入口图标）。
- 不做遥控器/DPad 焦点导航（纯触摸；Android TV 适配另立项目）。
- 不做自动轮播。
- 不做分屏副宿主内的大屏页。
