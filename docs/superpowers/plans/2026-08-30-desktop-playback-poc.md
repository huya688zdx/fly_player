# 桌面播放内核 POC（media_kit/libmpv）实施计划

> **For agentic workers:** Execute these steps inline unless the user explicitly requests another workflow. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用最小成本验证「桌面端以 libmpv 为内核 + Flutter 合成层」的技术可行性：视频通路（硬解/鉴权形态/缩放）与弹幕覆盖层（Flutter 渲染性能）各出一组量化数据，作为是否产品化的决策门。

**Architecture:** POC 以**独立入口**（`poc_main.dart`）挂在仓库内，不接入应用路由、桌面守卫与主壳，零影响验证；内核包装采用 media_kit（libmpv + 各平台纹理胶水），业务代码在产品化阶段（后续 Plan C）一律只依赖 `PlaybackHost`。弹幕压测覆盖层按产品层目标口径实现：文本一次光栅化缓存 `Picture`、单 `CustomPainter`、`RepaintBoundary` 隔离。

**Tech Stack:** Flutter (Dart)、media_kit / media_kit_video / media_kit_libs_windows_video（Linux 阶段加 media_kit_libs_linux）、flutter_test。

**执行目录:** 新 worktree `F:/fly_wt/desktop-playback-poc`（分支 `feat/desktop-playback-poc`，基于 `feat/desktop-shell`）。**POC 代码不进 `feat/desktop-storage`。**

---

### Task 1: POC 分支与依赖

- [ ] **Step 1: 创建独立 worktree**

```bash
cd F:/fly_play_recovered && git worktree add F:/fly_wt/desktop-playback-poc -b feat/desktop-playback-poc feat/desktop-shell
```
Expected: `HEAD is now at a97ebb1`。

- [ ] **Step 2: 取回本计划文件**

```bash
cd F:/fly_wt/desktop-playback-poc && git checkout feat/desktop-storage -- docs/superpowers/plans/2026-08-30-desktop-playback-poc.md
```
Expected: 文件出现在工作区（计划文档随 feat/desktop-storage 提交）。

- [ ] **Step 3: 安装依赖**

```bash
cd F:/fly_wt/desktop-playback-poc && flutter pub add media_kit media_kit_video media_kit_libs_windows_video && flutter pub get
```
Expected: 退出码 0，`pubspec.yaml` dependencies 出现三个包。
（Linux POC 阶段追加：`flutter pub add media_kit_libs_linux`。）

### Task 2: POC 入口与视频通路

**Files:**
- Create: `lib/desktop/playback/poc_main.dart`
- Create: `lib/desktop/playback/playback_poc_screen.dart`

- [ ] **Step 1: 写独立入口**

`lib/desktop/playback/poc_main.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'playback_poc_screen.dart';

/// 桌面播放内核 POC 独立入口：不接入应用路由、守卫与主壳。
/// 运行：
/// flutter run -d windows -t lib/desktop/playback/poc_main.dart
///   --dart-define=POC_MEDIA_URL=<本地文件绝对路径或网络流地址>
///   --dart-define=POC_BENCHMARK_COMMENTS=300
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  const mediaUrl = String.fromEnvironment('POC_MEDIA_URL');
  const benchmarkComments = int.fromEnvironment(
    'POC_BENCHMARK_COMMENTS',
    defaultValue: 0,
  );
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: PlaybackPocScreen(
        mediaUrl: mediaUrl,
        benchmarkComments: benchmarkComments,
      ),
    ),
  );
}
```

- [ ] **Step 2: 写 POC 页面**

`lib/desktop/playback/playback_poc_screen.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'danmaku_benchmark_overlay.dart';

/// 桌面播放内核 POC 页：media_kit（libmpv）视频通路 + 弹幕压测叠加。
class PlaybackPocScreen extends StatefulWidget {
  const PlaybackPocScreen({
    super.key,
    required this.mediaUrl,
    required this.benchmarkComments,
  });

  /// 为空时只显示弹幕压测层（不依赖媒体文件）。
  final String mediaUrl;

  /// 并发弹幕条数；0 表示不叠加压测层。
  final int benchmarkComments;

  @override
  State<PlaybackPocScreen> createState() => _PlaybackPocScreenState();
}

class _PlaybackPocScreenState extends State<PlaybackPocScreen> {
  final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  @override
  void initState() {
    super.initState();
    if (widget.mediaUrl.isNotEmpty) {
      _player.open(Media(widget.mediaUrl));
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (widget.mediaUrl.isNotEmpty) Video(controller: _controller),
          if (widget.benchmarkComments > 0)
            RepaintBoundary(
              child: DanmakuBenchmarkOverlay(
                commentCount: widget.benchmarkComments,
              ),
            ),
          _buildControlBar(),
        ],
      ),
    );
  }

  Widget _buildControlBar() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              onPressed: () {
                if (_player.state.playing) {
                  _player.pause();
                } else {
                  _player.play();
                }
              },
              icon: StreamBuilder<bool>(
                stream: _player.stream.playing,
                initialData: _player.state.playing,
                builder: (context, snapshot) => Icon(
                  snapshot.data == true ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
              ),
            ),
            IconButton(
              onPressed: () => _player.seek(Duration.zero),
              icon: const Icon(Icons.replay, color: Colors.white),
            ),
            StreamBuilder<Duration>(
              stream: _player.stream.position,
              builder: (context, snapshot) => Text(
                snapshot.data?.toString().split('.').first ?? '0:00:00',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: 静态检查**

Run: `cd F:/fly_wt/desktop-playback-poc && flutter analyze lib/desktop/playback`
Expected: `No issues found!`。

- [ ] **Step 4: 视频通路烟测（本地文件）**

Run（URL 换成本机任一 4K/高码率视频绝对路径）:
```bash
cd F:/fly_wt/desktop-playback-poc && flutter run -d windows -t lib/desktop/playback/poc_main.dart --dart-define=POC_MEDIA_URL=D:/sample-4k.mp4
```
验收清单（逐项记录）:
1. 播放/暂停/回零 seek 响应正常；
2. 拉伸窗口、进出最大化无撕裂/花屏；
3. 任务管理器 → GPU → "Video Decode" 引擎有占用（确认硬解，非 CPU 软解）；
4. 4K60 片源无肉眼掉帧（对照桌面 mpv 播放器）。

- [ ] **Step 5: 提交 POC 骨架**

```bash
cd F:/fly_wt/desktop-playback-poc && git add lib/desktop/playback pubspec.yaml pubspec.lock docs/superpowers/plans/2026-08-30-desktop-playback-poc.md && git commit -m "feat(desktop-poc): media_kit 播放通路 POC 入口"
```

### Task 3: 弹幕压测覆盖层

**Files:**
- Create: `lib/desktop/playback/danmaku_benchmark_overlay.dart`

- [ ] **Step 1: 写压测覆盖层**

`lib/desktop/playback/danmaku_benchmark_overlay.dart`：

```dart
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

const int _benchmarkLaneCount = 14;
const Duration _benchmarkCrossingDuration = Duration(seconds: 12);

/// 弹幕压测覆盖层：衡量桌面端 Flutter 弹幕渲染的 raster 帧耗时是否达标。
///
/// 实现口径与产品层一致：每条弹幕文本只布局/光栅化一次并缓存为 Picture，
/// 每帧仅按新坐标重绘缓存内容；调用方必须用 RepaintBoundary 包裹本组件，
/// 保证弹幕层与视频控制层互不触发重绘。左上角实时显示 raster 帧耗时
/// （指数滑动平均）。产品层仅将 setState 驱动换为 ValueNotifier，其余口径不变。
class DanmakuBenchmarkOverlay extends StatefulWidget {
  const DanmakuBenchmarkOverlay({super.key, required this.commentCount});

  /// 并发弹幕条数。
  final int commentCount;

  @override
  State<DanmakuBenchmarkOverlay> createState() =>
      _DanmakuBenchmarkOverlayState();
}

class _DanmakuBenchmarkOverlayState extends State<DanmakuBenchmarkOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final List<_CachedDanmaku> _cached = <_CachedDanmaku>[];
  Duration _elapsed = Duration.zero;
  double _averageRasterMs = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addTimingsCallback(_onTimings);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeTimingsCallback(_onTimings);
    _ticker.dispose();
    for (final item in _cached) {
      item.picture.dispose();
    }
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    final average =
        timings.fold<double>(
              0,
              (sum, timing) =>
                  sum + timing.rasterDuration.inMicroseconds / 1000,
            ) /
            timings.length;
    setState(() {
      _averageRasterMs = _averageRasterMs <= 0
          ? average
          : _averageRasterMs * 0.9 + average * 0.1;
    });
  }

  void _onTick(Duration elapsed) {
    setState(() => _elapsed = elapsed);
  }

  List<_CachedDanmaku> _ensureCached() {
    if (_cached.length == widget.commentCount) return _cached;
    for (final item in _cached) {
      item.picture.dispose();
    }
    _cached.clear();
    for (var index = 0; index < widget.commentCount; index++) {
      final painter = TextPainter(
        text: const TextSpan(
          text: '$index · 弹幕压测 —— 覆盖层光栅化基准 Benchmark 0123',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            shadows: <Shadow>[Shadow(blurRadius: 2, offset: Offset(1, 1))],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      _cached.add(
        _CachedDanmaku(
          picture: painter.toPicture(
            cullRect: Offset.zero & Size(painter.width, painter.height),
          ),
          width: painter.width,
          lane: index % _benchmarkLaneCount,
          phase: (index * 37 % 100) / 100,
        ),
      );
      painter.dispose();
    }
    return _cached;
  }

  @override
  Widget build(BuildContext context) {
    final cached = _ensureCached();
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: CustomPaint(
            painter: _DanmakuPainter(cached: cached, elapsed: _elapsed),
          ),
        ),
        Positioned(
          left: 12,
          top: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: Colors.black54,
            child: Text(
              '${widget.commentCount} 条 · raster $_averageRasterMs ms',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }
}

class _CachedDanmaku {
  const _CachedDanmaku({
    required this.picture,
    required this.width,
    required this.lane,
    required this.phase,
  });

  final ui.Picture picture;
  final double width;
  final int lane;

  /// 0..1 起始相位，避免同车道弹幕同帧出发。
  final double phase;
}

class _DanmakuPainter extends CustomPainter {
  _DanmakuPainter({required this.cached, required this.elapsed});

  final List<_CachedDanmaku> cached;
  final Duration elapsed;

  @override
  void paint(Canvas canvas, Size size) {
    final laneHeight = size.height / _benchmarkLaneCount;
    for (final item in cached) {
      final progress =
          (elapsed.inMicroseconds / _benchmarkCrossingDuration.inMicroseconds +
                  item.phase) %
              1.0;
      final x = size.width - progress * (size.width + item.width);
      final y = item.lane * laneHeight;
      canvas
        ..save()
        ..translate(x, y)
        ..drawPicture(item.picture)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_DanmakuPainter oldDelegate) =>
      oldDelegate.elapsed != elapsed || !identical(oldDelegate.cached, cached);
}
```

- [ ] **Step 2: 静态检查**

Run: `cd F:/fly_wt/desktop-playback-poc && flutter analyze lib/desktop/playback`
Expected: `No issues found!`。

- [ ] **Step 3: 压测矩阵（视频 + 弹幕同开）**

Run（每组记录 overlay 左上角 raster ms，窗口先调至 1080p 全屏再 4K）:
```bash
cd F:/fly_wt/desktop-playback-poc && flutter run -d windows -t lib/desktop/playback/poc_main.dart --dart-define=POC_MEDIA_URL=D:/sample-4k.mp4 --dart-define=POC_BENCHMARK_COMMENTS=100
# 依次改 POC_BENCHMARK_COMMENTS=300 / 600 重复
```
验收线:
1. 300 条 @1080p 全屏：raster 平均 < 8ms（60Hz 留一半余量）；
2. 600 条 @4K：raster 平均 < 16ms（描边开启；关闭描边的达标线 < 8ms 留作产品层降级开关）；
3. 最低支持配置机器（老 iGPU，如 Intel HD 520 级别）上复跑第 1 项；
4. 10 分钟长跑（300 条 + 视频）：无 crash、内存无持续上涨趋势。

- [ ] **Step 4: 提交压测层**

```bash
cd F:/fly_wt/desktop-playback-poc && git add lib/desktop/playback/danmaku_benchmark_overlay.dart && git commit -m "feat(desktop-poc): 弹幕覆盖层光栅化压测（Picture 缓存口径）"
```

### Task 4: 决策门与后续计划

- [ ] **Step 1: 汇总数据并判定**

| 结果 | 动作 |
|---|---|
| 视频通路 ✅ + 弹幕达标 ✅ | 写 Plan C：产品化接入（`DesktopMediaKitPlaybackHost` 实现 `PlaybackHost`、`MpvMediaSource`→media_kit 映射、`mpv_proxy_server.dart` NAS 鉴权流验证、轨道/章节/截图映射、`*playback_launcher` 桌面守卫解除、`DesktopStorageManagementHost` 补播放缓存统计） |
| 视频通路 ✅ + 弹幕不达标 ⚠️ | Plan C 照常，另立 Plan C-b：弹幕下沉为分平台原生 overlay 纹理（Windows Direct2D / Linux GL / macOS Metal） |
| 视频通路不达标 ❌ | 评估社区 fork（noelex / drwankingstein）或自写 dart:ffi + render API 胶水，POC 结论回填本表 |

- [ ] **Step 2: 归档 POC 结论**

把每项实测数据（含机器配置）追加到本文件末尾「POC 实测记录」小节并提交：

```bash
cd F:/fly_wt/desktop-playback-poc && git add docs/superpowers/plans/2026-08-30-desktop-playback-poc.md && git commit -m "docs(desktop-poc): 实测数据与决策门结论"
```

---

## 已知边界

- NAS 真实流的鉴权形态（`Media(httpHeaders:)` vs `mpv_proxy_server.dart` 本地代理）在 Plan C 验证，POC 只验证本地/普通网络流。
- 防遮挡（Android 为 Paddle Lite）桌面端一期不实现，Plan C 中按设置开关默认关闭。
- `flutter analyze`/`flutter test` 只能覆盖代码正确性；本计划的验收项全部依赖真机人工观察，属于决策门输入。
