# 桌面播放内核 PoC（media_kit/libmpv）实施与实测记录

> 本文件已经按 2026-08-30 的实际实现与真机结果收敛；旧版不可编译的示例代码和未经验证的结论已移除。

## 目标与边界

**目标：** 用独立 Windows 入口验证“libmpv 视频纹理 + Flutter 弹幕层 + Flutter 控制层”的最低可行性，包括普通网络视频、自定义 HTTP 请求头、`BoxFit.contain`、播放/暂停、±10 秒 seek，以及固定口径的弹幕帧耗时。

**非目标：** 不接入应用路由，不解除桌面播放守卫，不实现完整播放器壳、选集抽屉、轨道/章节/截图/PiP、播放统计、缓存管理、Linux/macOS 适配或 Android 防遮挡等产品功能。

**不改动范围：** `PlaybackHost`、现有四个播放入口、桌面守卫、储存宿主、Android 原生播放器和 `design/desktop` 原型。

**原型使用边界：** `design/desktop/index.html` 只作为播放器层级、视觉密度和交互意图参考。PoC 仅落地视频层、不可点击的弹幕层和最小控制层；顶部工具栏、完整底栏、自动隐藏、快捷键和选集抽屉留给产品化阶段。

## 执行环境

- Worktree：`F:/fly_wt/desktop-playback-poc`
- 分支：`feat/desktop-playback-poc`
- 固定基线：`feat/desktop-storage@738cf2b`
- Flutter 3.41.6 / Dart 3.11.4
- media_kit 1.2.6 / media_kit_video 2.0.1 / media_kit_libs_windows_video 1.0.11
- CPU：AMD Ryzen 7 7735HS
- GPU：AMD Radeon 680M（系统另有两个虚拟显示适配器）
- 内存：13.7 GB

## 最小验收标准

1. 独立 Windows release 构建通过，且不接入主应用。
2. 普通 MP4 能产生视频纹理，播放/暂停可用，原生诊断能读出硬解和掉帧属性。
3. 仓库外 JSON 请求头文件能传递到媒体请求，界面错误不泄露 URL 或 header 值。
4. 弹幕层不拦截输入、不逐帧重建组件；预热 10 秒后固定采样 60 秒，输出 build/raster/total 的 p50、p95、p99 和超过 16.67 ms 的比例。
5. 对 100/300/600 条弹幕分别留档；HLS 已知风险必须实测，不能仅凭普通 MP4 成功判定可产品化。

## 实施清单

### 1. 隔离分支与依赖

- [x] 从 `738cf2b` 创建独立 worktree，未修改 `feat/desktop-storage`。
- [x] 精确锁定三个 media_kit 依赖并更新 `pubspec.lock`。
- [x] 修复根 `.gitignore` 对任意名为 `flutter` 的目录的误忽略，纳入 Windows runner 必需的 `windows/flutter/{CMakeLists.txt,generated_*}`；ephemeral 产物仍不入库。

### 2. 视频、鉴权与控制层

- [x] 新增独立入口 `lib/desktop/playback/poc_main.dart`。
- [x] 新增 `lib/desktop/playback/playback_poc_screen.dart`。
- [x] 使用 `MediaKit.ensureInitialized()`、`Player`、`VideoController` 和 `NoVideoControls`。
- [x] 使用三层 `Stack`：`Video(BoxFit.contain)` / 弹幕 / Flutter 控制层。
- [x] 实现播放/暂停、±10 秒 seek、进度条和时长显示。
- [x] 支持 `POC_HTTP_HEADERS_FILE` 指向仓库外的 JSON object；只接受字符串键值，错误信息不回显敏感值。
- [x] 每秒读取 `hwdec-current`、`decoder-frame-drop-count` 和 `frame-drop-count`。

运行示例：

```powershell
flutter run -d windows --release -t lib/desktop/playback/poc_main.dart `
  --dart-define=POC_MEDIA_URL=<本地绝对路径或网络 URL> `
  --dart-define=POC_BENCHMARK_COMMENTS=300 `
  --dart-define=POC_HTTP_HEADERS_FILE=<仓库外 JSON 文件绝对路径>
```

### 3. 弹幕压测层

- [x] 新增 `lib/desktop/playback/danmaku_benchmark_overlay.dart`。
- [x] 用 `PictureRecorder + Canvas + TextPainter.paint` 预录文字绘制指令；未使用不存在的 `TextPainter.toPicture`。
- [x] `AnimationController` 直接通知 `CustomPainter.repaint`，没有逐帧 `setState`。
- [x] 外层使用 `IgnorePointer + RepaintBoundary`，隔离输入和重绘。
- [x] 数量变化时释放旧 `ui.Picture` 并重新执行预热/采样。
- [x] 采样完成后在界面和终端同时输出指标，便于复跑留档。

### 4. 静态和构建验证

- [x] `dart format --output=none --set-exit-if-changed lib/desktop/playback`
- [x] `flutter analyze lib/desktop/playback` → `No issues found!`
- [x] `flutter build windows --release -t lib/desktop/playback/poc_main.dart`
- [x] `git diff --check` 无空白错误；仅有 Git 的 CRLF 转换提示。

## PoC 实测记录（2026-08-30）

### 普通 MP4 与最小控制

- 使用公开 854×480 MP4 运行 release 构建，视频纹理成功创建。
- 日志显示 Direct3D Feature Level 11_0、`Using H/W rendering`；界面诊断为 `hwdec: d3d11va-copy`，decoder/frame drops 均为 0。
- 播放/暂停按钮状态切换已人工确认。
- 这只能证明普通视频基础通路；尚未完成本地 4K60、窗口缩放、长跑和 ±10 秒 seek 的人工验收，不据此声称高码率达标。

### 自定义 HTTP 请求头

- 用本地受控服务要求 `X-Poc-Key`，播放器从仓库外 JSON 文件读取 header。
- 服务端记录 `key_ok=True` 且收到 `Range: bytes=0-`，随后播放器创建 854×480 视频纹理。
- 结论：`POC_HTTP_HEADERS_FILE → Media(httpHeaders:) → HTTP 请求` 链路通过；真实 NAS 的 cookie/token/重定向组合仍需单独验证。

### 固定 60 秒弹幕矩阵

同一台机器、同一公开 MP4、Windows release 构建；每组先预热 10 秒。单位为 μs。

| 条数 | 样本 | build p50/p95/p99 | raster p50/p95/p99 | raster >16.67ms | total p50/p95/p99 | total >16.67ms |
|---:|---:|---:|---:|---:|---:|---:|
| 100 | 5675 | 532 / 1441 / 1854 | 5283 / 8229 / 10290 | 0.1% | 6960 / 11872 / 16767 | 1.0% |
| 300 | 2538 | 1014 / 1688 / 2236 | 10070 / 13558 / 17203 | 1.4% | 15164 / 24835 / 30153 | 40.9% |
| 600 | 3246 | 1760 / 2576 / 3045 | 18280 / 20806 / 22637 | 95.2% | 29284 / 37915 / 40879 | 100.0% |

判定：100 条可接受；300 条的 raster 大多未超预算，但合成总耗时已明显超预算；600 条 raster 与 total 均不达标。当前 `ui.Picture` 是绘制指令录制，不是位图缓存，因此不能把结果描述成“文字只光栅化一次”。

运行期间还多次出现 Flutter engine 的 `Reported frame time is older than the last one; clamping`。这可能影响 `FrameTiming` 的可信度，下一轮优化前应先用 DevTools timeline 或外部帧率工具交叉验证。

### HLS 风险流

- 测试流：`https://abc-news-dmd-streams-1.akamaized.net/out/v1/701126012d044971b3fa89406a440133/index.m3u8`
- 播放列表本身 HTTP 200，但运行约 40 秒后仍为 `00:00 / 00:00`、`hwdec: n/a`，没有视频画面。
- 现象与 media_kit 已公开的 Windows HLS/libmpv 问题一致；不能通过改 Flutter 控制层解决。

## 决策门

| 子项 | 结论 | 说明 |
|---|---|---|
| 普通 MP4 视频纹理 | 通过 | 可播放，硬件渲染与 d3d11va-copy 可观测 |
| 自定义 HTTP headers | 通过 | 受控服务确认 header 与 Range 请求 |
| 100 条弹幕 | 通过 | raster 与 total 的超预算比例较低 |
| 300/600 条弹幕 | 不通过 | 300 条 total、600 条 raster/total 明显超预算 |
| Windows HLS | 不通过 | 公开风险流无法进入播放状态 |
| 直接产品化 | **暂不通过** | 先解决/替换 Windows libmpv，并优化弹幕绘制口径 |

## 下一阶段的最小工作

先只做两个独立、可证伪的验证，不提前施工完整播放器：

1. **Windows libmpv 替换实验：** 用新版 libmpv 替换 media_kit Windows 包内的旧二进制，复跑同一 HLS；若仍失败，记录 mpv 日志后再决定 fork 或自有 FFI 胶水。
2. **弹幕绘制实验：** 比较文字 atlas/位图缓存与当前 Picture 指令重放，在 300/600 条下复跑相同 10+60 秒矩阵，并用 timeline 交叉验证帧时间。

只有两项通过后才写产品化 Plan C。Plan C 至少要明确：

- 为 `PlaybackHost` 提供平台选择/注入，而不是新增第二套业务入口。
- 收口当前四个直接构造 `NativePlaybackHost` 的位置：`item_playback_launcher.dart`、`tv_season_playback_launcher.dart`、`play_detail_page.dart`、`download_list_screen.dart`。
- 定义桌面宿主的加载、进度、错误、退出和播放状态契约，并验证真实 NAS 鉴权与重定向。
- 按 `design/desktop` 原型逐项产品化顶部/底部控制、自动隐藏、快捷键和选集抽屉；不把 PoC 控制条当成最终 UI。

## 剩余人工验收

- [ ] 本地 4K60 / 高码率文件与窗口缩放、最大化。
- [ ] ±10 秒 seek、拖动 seek 的完整人工回归。
- [ ] 300 条 10 分钟长跑与内存趋势。
- [ ] 低端 iGPU 复跑 100/300 条。
- [ ] 真实 NAS header/cookie/重定向链路。

这些项目不阻塞“PoC 代码完成”，但阻塞“可进入产品化”的结论。

## 用户决策与正式接入（2026-08-30）

用户确认接受上述已知风险并进入代码开发。本轮已完成最小正式接入：

- 新增 `DesktopPlaybackHost` 与 `playbackHostFor(context)`，Windows 推入根 Navigator，Android 保持 `NativePlaybackHost`。
- 四个现有播放入口已收口到平台宿主；Windows 分支早于 Android 反向通道、弹幕预取和回前台状态标记。
- 新增正式 `DesktopPlaybackScreen`，实现媒体 headers、断点、暂停状态、倍速、进度、音量、全屏、键盘快捷键和控制层自动隐藏。
- Linux/macOS 仍保持未开放提示；Windows HLS、真实弹幕、选集切换、轨道/截图/PiP 和播放统计仍不在本轮范围。
