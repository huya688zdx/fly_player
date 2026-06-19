# iOS26 液态玻璃组件改造 — 设计文档

日期：2026-06-19
分支：feat/native-player-overhaul

## 目标

把首页与详情/剧集/合集页中**静态的扁平组件**（卡片、标签、徽章、按钮、分段、信息块、选择器）统一改造成 **iOS26 液态玻璃风味**，并沿用已落地的**低成本静态磨砂方案**。

## 约束（硬性）

- **零 `BackdropFilter`**：实时高斯模糊在滚动区逐帧重算、掉帧。已在分类卡 + 底栏验证过，本次全部沿用「半透明磨砂渐变 + 镜面高光」模拟玻璃，开销近似普通装饰容器，可被缓存为静态层。
- **主题感知**：跟随 `context.appColors`，按背景明度（`backgroundBase.computeLuminance() >= 0.58`）自适应深/浅两套透明度。
- **只换皮，不改布局/行为**：不动尺寸结构、点击逻辑、数据流；仅替换装饰与叠层。
- **不动** `immersive_detail_background.dart` 的 hero 背景模糊（hero 基本不滚动、单张全幅，开销可接受）。

## 共享组件（新增 `lib/widgets/common/liquid_glass.dart`）

把已散落在分类卡/底栏的磨砂配方收敛为一份可复用件：

- `enum LiquidGlassTone { neutral, accent, strong }` — 中性玻璃 / 带强调色暖晕 / 更实（遮挡背景）。
- `BoxDecoration liquidGlassDecoration(BuildContext, {double radius, LiquidGlassTone tone, bool selected})`
  — 产出磨砂渐变填充 + 半透明白发丝边的装饰；`selected` 时加重强调色与边亮度。
- `class LiquidGlass extends StatelessWidget` — 玻璃容器：包 `liquidGlassDecoration` + 可选镜面高光叠层（`sheen`）+ 可选 `onTap`（用 `Material/InkWell`）+ `padding`/`radius`。用于卡片、chip、分段段、信息块。
- `class LiquidGlassSheen extends StatelessWidget` — 仅高光叠层（左上径向镜面 + 顶沿发丝高光），可叠在**实心**按钮上，给主操作按钮玻璃质感而不磨砂。

性能：全部静态渐变，无 `saveLayer`/模糊；位于滚动区的实例外层保留/补 `RepaintBoundary`。

## 各组件处理

### 首页
- 统计卡（收藏/全部影视/电影/电视剧/其他）— `media_list_screen_widgets.dart`：实心 → `LiquidGlass`（neutral，小圆角）。

### 详情 / 剧集页
| 组件 | 文件 | 处理 |
|---|---|---|
| 播放按钮（继续播放/特别篇/第N集） | `play_action_bar.dart`、`play_control_row.dart` | **保留实心强调色**，叠 `LiquidGlassSheen` + 发丝边；不磨砂 |
| 清晰度标签 4K/1080P SDR | `detail_resolution_section.dart`、`resolution_selector.dart` | `LiquidGlass` chip；选中态 `selected=true`（accent） |
| 能力徽章 1080/SDR/立体声 | `capability_badge.dart` | `LiquidGlass` chip（neutral，最小圆角） |
| 音轨/字幕下拉 | `detail_selector_row.dart` | `LiquidGlass`（neutral）包裹 |
| 类型标签 chip | `detail_tag_chip.dart` | `LiquidGlass` chip（neutral） |
| 文件位置卡 | `file_info_section.dart` | `LiquidGlass` 卡（neutral，大圆角） |
| 视频信息卡 | `video_info_section.dart` | `LiquidGlass` 卡（neutral，大圆角） |
| IMDB / TMDB | `link_section.dart` | `LiquidGlass` chip |
| 圆形图标按钮（收藏/下载/已看） | `detail_icon_button.dart` | `LiquidGlass`（圆形，neutral）+ sheen |
| 信息块 | `detail_info_block.dart` | `LiquidGlass` 卡 |
| 共N集按钮 + 1-30/31-38 选集分段 | `tv_episode_browser_section.dart` | 按钮=`LiquidGlass` chip；分段=选中段 strong/accent、未选中段 neutral 弱 |
| 选集弹层 | `tv_episode_picker_sheet.dart` | 弹层内 chip/卡 → `LiquidGlass` |
| 下载弹层 | `tv_season_download_sheet.dart` | 同上 |
| 共享详情组件 | `media_detail_components.dart` | 内含的 chip/卡 → `LiquidGlass` |

### 合集页（`media_collection_detail_page.dart`）
- `_CollectionToolButton`、`_TopBarIconButton` → `LiquidGlass` + sheen。

## 非目标（YAGNI）
- 不加真实模糊/降级开关、不加额外入场动画（选集分段已有的选中滑动保留）。
- 不重构无关代码、不改主题系统。

## 验证
- `flutter analyze` 无 issue；`dart format` 通过。
- 真机滑首页/详情，`_FrameTimingLogger` 的 `[PERF][FRAME]` raster 不应因本次上升。
- 浅色/深色两套主题各自观感正确（明度自适应分支）。

## 受影响文件
新增 1：`lib/widgets/common/liquid_glass.dart`
改动约 15：上表所列各文件（仅装饰层替换）。
