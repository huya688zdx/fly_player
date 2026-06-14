# 原生播放页 UI 优化与二级界面接入设计

- 日期：2026-06-14
- 范围：仅改 Android 原生播放页 `NativePlayerActivity.kt` 及必要的原生播放 UI 支撑；Flutter 播放页只作为参考，不修改 Flutter 播放 UI。
- 选定方向：B 方案，保留 Flutter 播放 UI 的信息架构，改成更适合横屏原生播放器的右侧快捷轨道 + 二级分页抽屉。

## 1. 背景

当前恢复后的原生播放页已经能大体播放，弹幕也已恢复，但 UI 仍有几个明显问题：

1. 顶部、底部按钮存在恢复痕迹，文字和状态不够统一。
2. 二级界面虽然有 `panelStack`、`panelNavRow`、`panelSlider`、`panelToggle` 等基础能力，但视觉粗糙，和 Flutter 播放页的抽屉体验不一致。
3. 音轨、字幕、画质等关键能力已有数据和部分方法，但没有以合理的二级界面方式完整接入。
4. 设置入口层级偏杂，播放主界面和设置面板需要重新整理信息优先级。

Flutter 播放 UI 中可作为参考的结构：

- 顶部控制栏：`lib/player/widgets/player_controls_chrome.dart`
- 二级分页抽屉：`lib/player/widgets/player_nested_sheet.dart`
- 通用选项抽屉：`lib/player/widgets/player_option_sheet.dart`
- 音轨抽屉：`lib/player/page_parts/settings/mpv_player_audio_drawer_mixin.dart`
- 字幕抽屉：`lib/player/page_parts/settings/mpv_player_subtitle_drawer_mixin.dart`

## 2. 目标

1. 播放页主界面更像一个完整播放器，而不是恢复临时界面。
2. 横屏使用右侧快捷轨道，快速进入字幕、音轨、画质、弹幕、设置。
3. 二级界面统一成分页抽屉，支持一级页、子页、返回、选中态列表、滑杆、开关、分段选择。
4. 音轨和字幕接入现有数据与播放重载逻辑。
5. 保持改动集中，第一轮不重做 Flutter 播放页，不引入新的跨端 UI 框架。

## 3. 非目标

1. 不重写播放器内核、mpv 控制器或弹幕渲染逻辑。
2. 不改 Flutter 播放页的交互和样式。
3. 不在第一轮实现远程字幕搜索、本地字幕文件浏览等复杂 Flutter 功能；原生侧先接入已有字幕列表、关闭字幕、字幕样式调整。
4. 不追求像素级复刻 Flutter，优先保证原生横屏体验合理、稳定、可编译。

## 4. 信息架构

### 主播放界面

顶部：

- 返回
- 标题
- PIP（支持设备显示）
- 听视频
- 截图
- AB 循环
- 弹幕设置快捷入口
- 更多/设置

底部：

- 当前时间
- 进度条和章节/书签/AB 标记
- 总时长
- 播放/暂停
- 下一集
- 弹幕开关
- 选集
- 倍速
- 音轨
- 字幕
- 画质

横屏右侧快捷轨道：

- 字幕
- 音轨
- 画质
- 弹幕
- 设置

竖屏或窄屏：

- 不强行显示右侧轨道，入口保留在底部控制栏和更多面板。

### 二级抽屉

抽屉根页为“播放控制”，包含：

- 字幕：显示当前字幕摘要，进入字幕页。
- 音轨：显示当前音轨摘要，进入音轨页。
- 画质：显示当前画质摘要，进入画质页。
- 弹幕：显示开关状态，进入弹幕设置页。
- 播放设置：进入设置根页。
- 选集：进入选集页。

字幕页：

- “关闭字幕”作为第一项。
- 列出 `subtitleTracks`。
- 当前项高亮。
- 选择字幕后使用现有 `requestTrackReload(audioGuid, subtitleGuid, qualityIndex)` 或 `applySubtitleByGuid` 路径。
- 子页“字幕调整”：延迟、位置、字号缩放、重置。

音轨页：

- 列出 `audioTracks`。
- 当前项高亮。
- 选择音轨后使用现有 `requestTrackReload(audioGuid, subtitleGuid, qualityIndex)`。
- 子页“音频调整”：音频延迟，后续可继续接 EQ。

画质页：

- 列出 `qualities`。
- 当前项高亮。
- 选择后走现有 `requestQuality`，保留当前音轨和字幕选择。

设置页：

- 画面调整
- 字幕设置
- 音频设置
- 画质与解码
- 弹幕设置
- 弹幕源
- 片头片尾跳过
- 书签
- 视频/轨道信息

## 5. 视觉原则

1. 主界面按钮使用半透明玻璃态，按钮尺寸稳定，避免文字撑开布局。
2. 抽屉背景接近 Flutter 的深色播放器主题，边框弱化，选中态使用蓝色强调。
3. 列表项统一为标题、副标题、选中标记、可选尾部状态。
4. 高频入口用图标或短标签，低频项放入抽屉，不堆在底栏。
5. 文本必须可读，不再保留恢复时出现的乱码标签。

## 6. 技术设计

### 组件层

在 `NativePlayerActivity.kt` 内先保守复用现有结构，新增或整理以下原生 View helper：

- `panelPrimaryTile`
- `panelOptionTile`
- `panelActionChip`
- `panelQuickRailButton`
- `currentAudioLabel`
- `currentSubtitleLabel`
- `currentQualityLabel`

第一轮不拆新 Kotlin 文件，避免恢复期文件移动带来额外风险。等 UI 稳定后，再考虑把面板组件抽到独立类。

### 状态层

继续使用现有字段：

- `loadArgsMap`
- `selectedAudioGuid`
- `selectedSubtitleGuid`
- `qualityList()`
- `trackList("audioTracks")`
- `trackList("subtitleTracks")`

补齐显示摘要和选中判断：

- 音轨：以 guid 匹配 `selectedAudioGuid`，为空时回退 `loadArgsMap["audioTrackGuid"]`。
- 字幕：以 guid 匹配 `selectedSubtitleGuid`，空字符串表示关闭。
- 画质：优先匹配分辨率/码率/qualityIndex，无法确认时显示当前 `currentQualityLabel()`。

### 行为层

音轨切换：

```text
选择 audioGuid
→ 更新 selectedAudioGuid
→ requestTrackReload(audioGuid, selectedSubtitleGuid, qualityIndex = null)
→ 关闭抽屉或刷新当前页状态
```

字幕切换：

```text
选择 subtitleGuid 或空字符串
→ 更新 selectedSubtitleGuid
→ 外挂/服务端字幕走现有字幕解析和 session reload 路径
→ 关闭抽屉或刷新当前页状态
```

画质切换：

```text
选择 qualityIndex
→ requestQuality(qualityIndex)
→ 保留 selectedAudioGuid / selectedSubtitleGuid
```

## 7. 验证

第一轮实现完成后至少验证：

1. `.\gradlew :app:compileFullProfileKotlin`
2. `.\gradlew :app:compileLiteProfileKotlin`
3. `flutter build apk --profile --flavor full`
4. 真机手动检查：
   - 播放页顶部/底部 UI 不遮挡、不乱码。
   - 横屏右侧快捷轨道可打开对应二级页。
   - 音轨列表可显示和切换。
   - 字幕列表可显示、关闭和切换。
   - 画质切换后音轨/字幕选择不丢。
   - 弹幕设置仍能打开，弹幕显示不回退。

## 8. 实施顺序

1. 先整理面板基础组件和主界面按钮文案，保证视觉一致。
2. 添加右侧快捷轨道和“播放控制”根页。
3. 接入字幕页、音轨页、画质页。
4. 调整设置根页分组和入口。
5. 编译验证，再做真机微调。
