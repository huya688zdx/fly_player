import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../controller/danmaku_controller.dart';
import '../models/danmaku_comment.dart';
import '../models/danmaku_dynamic_occlusion.dart';
import '../models/danmaku_settings.dart';
import 'danmaku_image_disposer.dart';

/// 高性能 Flutter 弹幕渲染层。
///
/// 设计要点（对应业内做法，解决"越播越掉帧 + 不卡 UI"）：
/// - 单 [CustomPaint] + [Ticker] 驱动，绝不一条弹幕一个 widget；
/// - 每条弹幕预光栅化为 [ui.Image]（描边+填充 → PictureRecorder → toImageSync），
///   LRU 缓存字模；每帧仅 drawImageRect 平移（纹理采样，比 drawParagraph×2 快
///   一个数量级）；ui.Image 由 GC finalizer 回收，淘汰只丢引用即安全；
/// - 只维护/绘制"在屏活动集"，滚出屏幕立刻回收进对象池，工作量不随时间增长；
/// - 车道调度防重叠；密度/去重在发射阶段过滤；
/// - 媒体时间插值：position 仅 ~6Hz 更新，这里用 wall-clock 外推 + 软校正，
///   保证滚动按目标帧率平滑；暂停即冻结；seek 自动重置；
/// - 透明度由 painter 逐条通过 Paint alpha 应用，无 Opacity widget 离屏合成开销。
class FlutterDanmakuOverlay extends StatefulWidget {
  final DanmakuController controller;
  final int positionMs;

  /// 视频真正暂停（非播放相位）：弹幕整体冻结、停止重绘。
  final bool paused;

  /// 弹层/二级界面打开：弹幕继续滚动+回收+重绘，但停止发射新弹幕——避免滚动 UI
  /// 时的排版建图尖刺，又不至于把弹幕整冻。
  final bool suspendSpawn;

  /// 速度增益（如长按 2x）。基础播放倍速通过 position 推进速率自动体现。
  final double playbackSpeedFactor;

  /// AI 动态遮挡状态：当 [DanmakuDynamicOcclusionState.hasUsableMask] 为 true
  /// 且设置中开启了 avoidCenterArea 时，painter 使用 saveLayer + dstOut 将
  /// 遮罩区域从弹幕层"扣除"，使视频内容（人物/字幕）不被弹幕遮挡。
  final DanmakuDynamicOcclusionState occlusionState;

  const FlutterDanmakuOverlay({
    super.key,
    required this.controller,
    required this.positionMs,
    required this.paused,
    this.suspendSpawn = false,
    this.playbackSpeedFactor = 1.0,
    this.occlusionState = DanmakuDynamicOcclusionState.disabled,
  });

  @override
  State<FlutterDanmakuOverlay> createState() => _FlutterDanmakuOverlayState();
}

class _FlutterDanmakuOverlayState extends State<FlutterDanmakuOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _DanmakuEngine _engine = _DanmakuEngine();
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);

  Size _viewport = Size.zero;
  double _dpr = 1.0;

  // 媒体时间（毫秒，浮点）。视觉时钟匀速推进，只受 playbackSpeedFactor 影响，
  // 不再做"播放速率估计"——速率估计会随 ~6Hz position 回调抖动，直接污染弹幕
  // 平移速度造成肉眼可见的忽快忽慢。position 回调仅用于 seek 重置、stall 恢复
  // 快照，以及每帧"封顶"的平滑微调（见 _onTick）。
  double _renderMediaMs = 0;
  double _lastTickWallMs = 0;
  double _wallNowMs = 0;
  int _lastPosMs = 0;
  double _lastPosWallMs = -1;
  bool _hasPosAnchor = false;
  // 上一次"处理 tick"的 wall 时刻；用于限帧（settings.targetFrameRateHz）。
  // 初始 -1 = 还没处理过，第一帧必出。
  double _lastRenderedWallMs = -1;
  // 上一渲染帧是否有活动弹幕。用于"空闲不强制重绘"：没弹幕时不再每帧 _repaint，
  // 让视频按自身节奏刷新（texture 路径下每次 _repaint 都触发整屏视频合成，Mali
  // 上尤其昂贵）。从"有→无"时仍补一帧把残留弹幕清掉。
  bool _hadActiveLastRender = false;
  // 显示刷新周期（ms）。用于把每帧 dt 量化到整数帧间隔，消除 Flutter 帧时间戳的
  // 亚帧抖动（dt 在 8.33ms 上下抖 ±1ms → 速度抖 ±12% → "一边滚一边颤"）。
  // 从 View.display.refreshRate 取，didChangeDependencies 里刷新。
  double _frameIntervalMs = 1000.0 / 60.0;

  static const double _seekDriftMs = 1500;

  // 诊断日志：每 ~5 秒打印一次引擎/时间锚状态，定位"滚动弹幕越播越少"类问题。
  double _lastDiagLogWallMs = 0;
  int _scrollEmitSinceLastLog = 0;
  int _scrollDropSinceLastLog = 0;

  // ---- AI 遮罩 ----
  static const Duration _maskEmptyStateClearGrace = Duration(milliseconds: 350);
  ui.Image? _maskImage;
  String? _maskImageKey;
  int _maskLoadGeneration = 0;
  Timer? _maskClearTimer;

  @override
  void initState() {
    super.initState();
    _renderMediaMs = widget.positionMs.toDouble();
    _lastPosMs = widget.positionMs;
    widget.controller.addListener(_handleControllerChanged);
    _engine.bindComments(widget.controller.comments);
    _engine.resetTo(_renderMediaMs);
    _ticker = createTicker(_onTick)..start();
    unawaited(_syncMaskImage());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 取当前 FlutterView 的真实刷新率（120Hz 屏→8.33ms，60Hz 屏→16.67ms）。
    final hz = View.of(context).display.refreshRate;
    if (hz.isFinite && hz >= 24.0 && hz <= 240.0) {
      _frameIntervalMs = 1000.0 / hz;
    }
  }

  @override
  void didUpdateWidget(covariant FlutterDanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
      _engine.bindComments(widget.controller.comments);
      _engine.resetTo(_renderMediaMs);
    }
    if (oldWidget.positionMs != widget.positionMs) {
      _onPositionUpdate(widget.positionMs);
    }
    if (_maskStateKey(oldWidget.occlusionState) !=
        _maskStateKey(widget.occlusionState)) {
      unawaited(_syncMaskImage());
    }
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    // 评论集或设置变化：重新绑定并按当前媒体时间重置活动集。
    _engine.bindComments(widget.controller.comments);
  }

  void _onPositionUpdate(int positionMs) {
    final nowWall = _wallNowMs;
    if (_hasPosAnchor && _lastPosWallMs >= 0) {
      final dWall = nowWall - _lastPosWallMs;
      final dPos = (positionMs - _lastPosMs).toDouble();
      final drift = (positionMs - _renderMediaMs).abs();
      if (drift > _seekDriftMs || dPos < 0) {
        // 跳转：直接重置视觉时钟。
        _renderMediaMs = positionMs.toDouble();
        _engine.resetTo(_renderMediaMs);
      } else {
        // ★ "stall 恢复"检测（解决"滚动弹幕越播越少直到消失"）：
        // 缓冲/暂停 < 1.5 秒不触发 seek 重置；恢复后第一次回调里 dWall（含 stall
        // 时长）远大于 dPos（仅恢复后那点播放）。判据：wall > 300ms 且实际播放
        // 不足 70%。处置：把视觉时钟快照回真实位置（stall 期间它匀速空转跑过头了）。
        // 其余情况不在此处步进——steady-state 的微小漂移交给 _onTick 每帧封顶微调，
        // 避免这里 ~6Hz 的离散猛拽造成周期性顿挫。
        // 只向前快照（追上缓冲落后）。**不向后**：暂停瞬间 widget.paused 比视频实际
        // 冻结慢几帧，这几帧弹幕时钟会多走几十 ms 冲到视频前面；若此处向后 snap 回真实
        // 位置，恢复时弹幕就"往后跳一下"。向后的小偏差留着无妨——在 _onTick 死区内、
        // 肉眼无参照看不出；真·后退 seek 由上面 dPos<0 / drift>seek 分支处理。
        final isStallRecovery = dWall > 300 && dPos < dWall * 0.7;
        if (isStallRecovery && positionMs > _renderMediaMs) {
          _renderMediaMs = positionMs.toDouble();
        }
      }
    } else {
      _renderMediaMs = positionMs.toDouble();
      _engine.resetTo(_renderMediaMs);
    }
    _hasPosAnchor = true;
    _lastPosMs = positionMs;
    _lastPosWallMs = nowWall;
  }

  void _onTick(Duration elapsed) {
    final wall = elapsed.inMicroseconds / 1000.0;
    // _wallNowMs 用于 _onPositionUpdate 计算 dWall，必须每次 vsync 都更新，
    // 跟是否真出图无关。
    _wallNowMs = wall;

    final settings = widget.controller.settings;

    // ---- 限帧 ----
    // 在高刷屏（如 120Hz 平板）上，每 vsync (~8.3ms) 都跑会让单帧的 GPU/CPU
    // 预算压到 8.3ms 以内；偶尔一帧超出就是肉眼可见的"颤一下"。
    // 把渲染频率限到 settings.targetFrameRateHz（默认 60Hz）：
    //   - 单帧预算从 8.3ms 拉到 ~16.6ms，atlas flush 等尖刺被吸收
    //   - 帧间隔均匀（每 2 个 vsync 出 1 帧），观感更稳
    //   - 滚动文字本身 60Hz 已经非常顺，肉眼几乎看不出和 120Hz 区别
    // 跳过的 tick 只更新 wall 锚点，_lastTickWallMs 保持上一次出图时刻，
    // 这样下次出图时 dt 累计正确（_renderMediaMs 推进量不少算）。
    final targetFps = settings.targetFrameRateHz.clamp(24, 240).toInt();
    final minRenderIntervalMs = 1000.0 / targetFps - 2.0; // 2ms vsync 容差
    if (_lastRenderedWallMs >= 0 &&
        wall - _lastRenderedWallMs < minRenderIntervalMs) {
      return; // 限帧：跳过本次 vsync
    }
    // 本 tick 通过限帧、参与处理（推进时钟+update）。是否真正 _repaint 由下方
    // "是否有活动弹幕"决定——空闲时不强制重绘。此处统一推进限帧锚点。
    _lastRenderedWallMs = wall;

    // dt 上限 100ms：正常帧率(24-120Hz)dt 在 8-42ms，超 100ms 说明出现了
    // 卡顿/后台冻结，此时不应让 _renderMediaMs 大幅跳跃（否则弹幕时间线偏移，
    // 大量弹幕一次性变为"迟到"被丢弃或被车道拒绝）。
    final dt = _lastTickWallMs == 0
        ? 0.0
        : (wall - _lastTickWallMs).clamp(0.0, 100.0);
    _lastTickWallMs = wall;

    if (!widget.controller.ready || !settings.enabled) {
      if (_engine.hasActive) {
        _engine.clearActive();
        _repaint.value++;
      }
      _hadActiveLastRender = false;
      return;
    }
    // 视频真正暂停：整体冻结，不再每帧 update/repaint，最后一帧静止画面保留。
    if (widget.paused) {
      return;
    }
    if (dt > 0) {
      // 把 dt 量化到整数个显示刷新周期，再推进视觉时钟。
      // 关键（消除"一边滚一边颤/忽快忽慢"）：Flutter 帧时间戳天然在刷新周期上下
      // 抖 ±1ms，直接用 raw dt 推进 → 速度抖 ±12%。量化后弹幕严格按整帧步进
      // （8.33ms 的整数倍），像 CSS/合成器那样线性匀速；真·掉帧(dt≈2 帧)则按 2 帧
      // 正确追上。round 无偏，长期总量≈真实 wall 时间，与媒体时钟的偏差由下方死区兜底。
      final quantSteps = (dt / _frameIntervalMs).round().clamp(1, 8);
      final quantizedDt = quantSteps * _frameIntervalMs;
      _renderMediaMs += quantizedDt * widget.playbackSpeedFactor;
      // 朝权威媒体时间做带"死区"的温和微调。
      // 关键（消除"拉扯感"）：position 回调 ~6Hz 到来时 _lastPosMs 会阶跃更新，
      // 使 drift 每 ~167ms 产生一次台阶 → 若每帧都纠偏，就形成 ~6Hz 的速度微调制，
      // 肉眼即"一顿一顿的拉扯"。死区让 |drift| 在阈值内时**完全不纠偏**，弹幕严格
      // 匀速平移（真·B站式线性）；只有漂移超出死区（真发散：缓冲/变速/长期解码偏速）
      // 才朝死区边缘做封顶收敛，且不收到 0，避免末段又陷入"纠-停-纠"抖动。
      if (_hasPosAnchor && _lastPosWallMs >= 0) {
        final expected =
            _lastPosMs + (wall - _lastPosWallMs) * widget.playbackSpeedFactor;
        final driftMs = expected - _renderMediaMs;
        const deadzoneMs = 60.0;
        if (driftMs > deadzoneMs || driftMs < -deadzoneMs) {
          final target = driftMs > 0
              ? driftMs - deadzoneMs
              : driftMs + deadzoneMs;
          // 纠偏极轻（≤3% 速度）：稳态下量化时钟已与 wall 同步、drift≈0 不触发；
          // 即使刷新率取值略偏导致偶发纠偏，3% 也低于肉眼速度察觉阈值，不会"减速感"。
          final maxCorr = dt * 0.03;
          _renderMediaMs += target.clamp(-maxCorr, maxCorr);
        }
      }
    }
    if (_viewport.width > 0 && _viewport.height > 0) {
      // 弹层/二级界面打开（suspendSpawn）：继续滚动+回收+重绘，但停止发射新弹幕——
      // 排版建图（ui.Paragraph）是单帧尖刺成本，正是"滑 UI 弹幕卡爆"的真凶；
      // 而平移已在屏弹幕的重绘很廉价，保留它观感更顺、又不与滚动 UI 抢渲染。
      final spawnedThisTick = _engine.update(
        currentMediaMs: _renderMediaMs,
        viewport: _viewport,
        dpr: _dpr,
        settings: settings,
        allowSpawn: !widget.suspendSpawn,
      );
      _scrollEmitSinceLastLog += spawnedThisTick.scrollEmitted;
      _scrollDropSinceLastLog += spawnedThisTick.scrollDropped;
    }
    _repaint.value++;
    _lastRenderedWallMs = wall;
    _lastRenderedWallMs = wall;

    // ---- 周期诊断日志（每 ~5 秒一次） ----
    if (wall - _lastDiagLogWallMs > 5000) {
      _lastDiagLogWallMs = wall;
      final scrollActive = _engine.scrollActiveCountForDiag;
      final retryLen = _engine.retryQueueLengthForDiag;
      final nextIdx = _engine.nextIndexForDiag;
      final totalComments = _engine.commentsLengthForDiag;
      // 诊断：视觉时钟与权威媒体时间的瞬时漂移（ms）。稳态应接近 0；持续偏大
      // 说明真实播放速率长期偏离 speedFactor（解码慢/持续缓冲）。
      final clockDriftMs = _hasPosAnchor && _lastPosWallMs >= 0
          ? (_lastPosMs +
                (_wallNowMs - _lastPosWallMs) * widget.playbackSpeedFactor -
                _renderMediaMs)
          : 0.0;
      debugPrint(
        '[DANMAKU][DIAG] mediaMs=${_renderMediaMs.toStringAsFixed(0)} '
        'spd=${widget.playbackSpeedFactor.toStringAsFixed(2)} '
        'drift=${clockDriftMs.toStringAsFixed(0)} '
        'vp=${_viewport.width.toStringAsFixed(0)}x'
        '${_viewport.height.toStringAsFixed(0)} '
        'paused=${widget.paused} suspend=${widget.suspendSpawn} '
        'scrollActive=$scrollActive retryQ=$retryLen '
        'nextIdx=$nextIdx/$totalComments '
        'emit5s=$_scrollEmitSinceLastLog drop5s=$_scrollDropSinceLastLog '
        'recycle5s=${_engine.recycledSinceDiag} '
        'force5s=${_engine.forceRecycledSinceDiag} '
        'stuck20s=${_engine.stuckOver20sCount} '
        'atlasPg=${_engine.atlasPagesCountForDiag} '
        'fallback=${_engine.fallbackActiveCountForDiag} '
        'oldestAge=${_engine.oldestScrollAgeMs.toStringAsFixed(0)} '
        'oldestDur=${_engine.oldestScrollDurationMs.toStringAsFixed(0)}',
      );
      _scrollEmitSinceLastLog = 0;
      _scrollDropSinceLastLog = 0;
      _engine.resetDiagCounters();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    widget.controller.removeListener(_handleControllerChanged);
    _engine.dispose();
    _repaint.dispose();
    _cancelPendingMaskClear();
    // 遮罩 image 必须同步销毁，不能走 deferDispose（260ms 后才 dispose）——
    // 延迟到 surface/Impeller 拆除之后销毁 GPU 纹理会撞已销毁的 Vulkan mutex 闪退。
    // 此处 painter 已随 widget 拆除，无在途帧引用旧遮罩，同步释放安全。
    final mask = _maskImage;
    _maskImage = null;
    _maskImageKey = null;
    mask?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.controller.settings;
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          _viewport = Size(constraints.maxWidth, constraints.maxHeight);
          // 字模光栅化 DPR 上限 2.0：高 DPR 设备（平板 3.0）按 3 倍光栅化字模
          // → 纹理大小 9 倍、GPU 填充量 9 倍。滚动文字本身在动，瞳孔积分使得
          // 1.5×（2.0/3.0）下采样几乎不可察觉，但能省 ~55% 的 raster 成本，
          // 是平板上拉满帧率最便宜的开关。
          // 注意：这里不影响 paint 时的 dst 尺寸（仍按逻辑像素），只影响纹理
          // 的源像素密度。
          _dpr = MediaQuery.of(
            context,
          ).devicePixelRatio.clamp(1.0, 2.0).toDouble();
          // 透明度由 painter 在 drawImageRect 时通过 Paint.color alpha 应用，
          // 不再使用 Opacity widget（省掉额外的离屏合成 pass）。
          return RepaintBoundary(
            child: CustomPaint(
              size: _viewport,
              isComplex: true,
              willChange: true,
              painter: _DanmakuPainter(
                engine: _engine,
                repaint: _repaint,
                maskImage: settings.avoidCenterArea ? _maskImage : null,
                displayAreaRatio: settings.displayAreaRatio,
                captureAreaRatio: widget.occlusionState.captureAreaRatio,
              ),
            ),
          );
        },
      ),
    );
  }

  // ---- AI 遮罩加载/管理 ----

  String _maskStateKey(DanmakuDynamicOcclusionState state) {
    if (!state.hasUsableMask) return '';
    final versionToken = state.maskSignature?.trim().isNotEmpty == true
        ? state.maskSignature!.trim()
        : state.updatedAtMs.toString();
    return '${state.maskPath ?? ''}|$versionToken|'
        '${state.maskWidth}x${state.maskHeight}';
  }

  Future<void> _syncMaskImage() async {
    final nextKey = _maskStateKey(widget.occlusionState);
    if (nextKey.isEmpty) {
      if (_shouldDelayMaskClear()) {
        _scheduleDeferredMaskClear();
        return;
      }
      _cancelPendingMaskClear();
      _maskLoadGeneration += 1;
      if (_maskImage != null || _maskImageKey != null) {
        _disposeMaskImage();
        if (mounted) setState(() {});
      }
      return;
    }
    _cancelPendingMaskClear();
    if (_maskImageKey == nextKey && _maskImage != null) return;
    final generation = ++_maskLoadGeneration;
    final path = widget.occlusionState.maskPath;
    if (path == null || path.trim().isEmpty) {
      _maskLoadGeneration += 1;
      _disposeMaskImage();
      if (mounted) setState(() {});
      return;
    }
    final file = File(path);
    if (!await file.exists()) {
      _maskLoadGeneration += 1;
      if (_maskImage != null || _maskImageKey != null) {
        _disposeMaskImage();
        if (mounted) setState(() {});
      }
      return;
    }
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted || generation != _maskLoadGeneration) {
        DanmakuImageDisposer.deferDispose(frame.image);
        return;
      }
      _disposeMaskImage();
      _maskImage = frame.image;
      _maskImageKey = nextKey;
      setState(() {});
    } catch (_) {
      if (!mounted || generation != _maskLoadGeneration) return;
      _disposeMaskImage();
      setState(() {});
    }
  }

  void _disposeMaskImage() {
    DanmakuImageDisposer.deferDispose(_maskImage);
    _maskImage = null;
    _maskImageKey = null;
  }

  bool _shouldDelayMaskClear() {
    if (_maskImage == null || _maskImageKey == null) return false;
    if (!widget.occlusionState.enabled) return false;
    return widget.occlusionState.backend.trim().toLowerCase() != 'disabled';
  }

  void _scheduleDeferredMaskClear() {
    if (_maskClearTimer != null) return;
    final generation = ++_maskLoadGeneration;
    _maskClearTimer = Timer(_maskEmptyStateClearGrace, () {
      _maskClearTimer = null;
      if (!mounted || generation != _maskLoadGeneration) return;
      if (_maskStateKey(widget.occlusionState).isNotEmpty) return;
      if (_maskImage == null && _maskImageKey == null) return;
      _disposeMaskImage();
      setState(() {});
    });
  }

  void _cancelPendingMaskClear() {
    _maskClearTimer?.cancel();
    _maskClearTimer = null;
  }
}

// ---------------------------------------------------------------------------
// 引擎：活动集、车道调度、发射/回收、字模缓存。
// ---------------------------------------------------------------------------

class _DanmakuEngine {
  static const double _baseFontSp = 22.0;
  static const double _refShortSideDp = 420.0;
  static const double _minViewportScale = 0.76;
  static const double _maxViewportScale = 1.5;
  static const double _strokeBaseDp = 1.5;
  // 穿屏时长基准：在参考宽度 (_refViewportWidth) 下 1x 速度的穿屏媒体毫秒数。
  // 实际穿屏时长 = _scrollBaseMs × (viewport.width / _refViewportWidth) / speedFactor，
  // 使弹幕的绝对视觉速度（dp/s）在不同尺寸设备上保持一致。
  static const double _scrollBaseMs = 8500;
  static const double _scrollMinMs = 3200;
  static const double _staticBaseMs = 2600;
  // 参考视口宽度（dp）：典型手机横屏宽度 ≈ 880dp。
  // 穿屏时长 ∝ sqrt(viewport.width / _refViewportWidth)，亚线性缩放：
  //   手机 870dp → sqrt(0.989) ≈ 1.00  → 8500ms（不变）
  //   平板1600dp → sqrt(1.818) ≈ 1.35  → 11,475ms（合理加长，非线性的 15.5s）
  // 线性缩放（旧方案）导致平板穿屏 15.5s，视觉上极慢；sqrt 保证宽屏"有感知地
  // 慢一些"但不会过分，同时窄屏几乎不受影响。
  static const double _refViewportWidth = 880.0;
  static const double _viewportDurationScaleMin = 0.68;
  static const double _viewportDurationScaleMax = 1.50;
  static const double _spawnCatchUpMs = 600; // 超过此"迟到"的弹幕直接丢弃
  // 每帧最多 *成功发射* 条数：限制单帧处理量。
  static const int _maxSpawnPerUpdate = 6;
  // 每帧最多 *扫描* 条数：即使全部被车道拒绝也不会无限循环（密集弹幕段防卡）。
  static const int _maxIterationsPerUpdate = 30;
  // 重试队列：车道满时 _emit 返回 false 的弹幕暂存于此，下一帧优先重试。
  // 容量有限——超过即丢弃最旧的（与直接丢弃相比多给了 1 帧缓冲，显著减少
  // 密集段滚动弹幕因短暂车道满而永久丢失的数量）。
  static const int _maxRetryQueueSize = 16;
  // 每帧最多"新建字模"(ui.Paragraph 排版 + toImageSync)条数：建图是 UI 线程的尖刺
  // 成本来源，且发生在 _onTick(Ticker 回调，属于 BeginFrame 内)——平板高 DPR 下单个
  // toImageSync ~2-3ms，预算 3 时 cache-miss 帧会同步建 3 个 ≈9ms，叠加 paint 就冲破
  // 120Hz 的 8.3ms 预算，表现为"间歇咯噔卡一下"(DevTools frame timeline 实测 UI 线程
  // ~10ms 尖刺)。降到 1：单帧建图尖刺 ≈3ms，留在预算内；建不出的当帧进 retry 队列下帧
  // 再试，密集段最多稍慢一两帧补齐，观感远好于掉帧。根治还需把字模光栅化错峰预热出
  // BeginFrame（见后续滚动预热方案）。
  static const int _maxGlyphBuildsPerUpdate = 1;
  static const int _maxActiveScroll = 160;
  static const int _glyphCacheMax = 256;
  static const int _dedupWindowMs = 2500;
  // 字模 atlas 配置：单页 1024×512（2MB），最多 8 页（16MB）。
  // 小页关键收益：每次 flush 都要 drawImage(old_atlas) 复制整页内容，
  //   1024×1024（4MB）→ 1024×512（2MB）能把单次 flush 的 GPU 拷贝量减半，
  //   减少弹幕滚动时的"突然颤一下"。
  // 8 页 ×16 条 shelf ≈ 数百~千个字模容量，足够一集番剧用。
  // 极宽弹幕（> 1020 像素物理宽）走 fallback（独立 ui.Image），不进 atlas。
  static const int _atlasPageWidth = 1024;
  static const int _atlasPageHeight = 512;
  static const int _maxAtlasPages = 8;

  final List<_AtlasPage> _atlasPages = <_AtlasPage>[];

  // teardown 硬闸：dispose() 后置位。一旦置位即禁止再 kick 出任何异步 atlas
  // flush（pic.toImage 会创建/销毁离屏 framebuffer），避免在 surface/Impeller
  // 拆除期间向 Vulkan 投递销毁请求 → vkDestroyFramebuffer 撞已销毁 mutex 闪退。
  bool _disposed = false;

  final _GlyphCache _glyphCache = _GlyphCache(_glyphCacheMax);
  final List<_DanmakuItem> _active = <_DanmakuItem>[];
  final List<_DanmakuItem> _pool = <_DanmakuItem>[];
  final Map<String, int> _recentText = <String, int>{};
  final List<DanmakuComment> _retryQueue = <DanmakuComment>[];

  List<DanmakuComment> _comments = const <DanmakuComment>[];
  int _nextIndex = 0;
  int _glyphBuildsThisFrame = 0;

  // 车道：滚动车道带"上一条弹幕快照"，用于判断新条会不会追上前条造成重叠。
  // 因为所有滚动弹幕的 durationMs 相同，宽度 W 的弹幕需要在 d 内跨 (viewport+W)，
  // 所以越宽越快；若忽略宽度只看"前条进入屏幕"就放下一条，后面更宽更快的会追上前条。
  // 顶部弹幕复用滚动车道，故 top 也写入同一份占用快照。
  List<_ScrollLaneState> _scrollLaneStates = <_ScrollLaneState>[];
  List<double> _bottomLaneFreeMs = <double>[];
  List<double> _scrollLaneY = <double>[];
  List<double> _bottomLaneY = <double>[];

  Size _lastViewport = Size.zero;
  double _lastAreaRatio = -1;
  double _lastFontScale = -1;
  bool _lastAvoidSubtitle = false;
  // 上一帧的滚动运动倍速；变化时把屏上滚动弹幕重锚到新速度（保持位置、改速度），
  // 避免"改速度后旧弹幕仍慢、被新快弹幕追上重叠覆盖"。
  double _lastSpeedFactor = -1;

  List<_DanmakuItem> get active => _active;
  bool get hasActive => _active.isNotEmpty;

  // ---- 诊断 getter ----
  int get scrollActiveCountForDiag => _scrollActiveCount();
  int get retryQueueLengthForDiag => _retryQueue.length;
  int get nextIndexForDiag => _nextIndex;
  int get commentsLengthForDiag => _comments.length;
  int get atlasPagesCountForDiag => _atlasPages.length;

  /// 当前帧走 source image 路径（不在 atlas 或 atlas 还未 materialize）的活动数。
  /// - 高 = atlas 太小 / 还在 warmup / async flush 没跟上
  /// - 稳态接近 0 = atlas 命中率高，drawRawAtlas 批绘生效
  int get fallbackActiveCountForDiag {
    var n = 0;
    for (final it in _active) {
      final slot = it.glyph.atlasSlot;
      if (slot == null || !slot.isMaterialized) n++;
    }
    return n;
  }

  void bindComments(List<DanmakuComment> comments) {
    if (identical(comments, _comments)) return;
    _comments = comments;
    // 重新定位发射游标到当前帧位置之后（下次 update/resetTo 会修正）。
    _nextIndex = _lowerBound(_comments, _lastSpawnCursorMs.round());
    _retryQueue.clear();
  }

  double _lastSpawnCursorMs = 0;
  double opacity = 1.0;

  /// 当前渲染所用的媒体时间（毫秒），画笔据此计算滚动位置。
  double get lastMediaMs => _lastSpawnCursorMs;

  void resetTo(double mediaMs) {
    _lastSpawnCursorMs = mediaMs;
    _nextIndex = _lowerBound(_comments, mediaMs.round());
    _recentText.clear();
    _retryQueue.clear();
    _releaseAll();
    // ★ 必须把车道占用状态也清零：否则向前 seek 时旧 freeAtMs 虽然 < 新 currentMs
    // 可以正常使用，但向后 seek 时旧 freeAtMs > 新 currentMs，上面的车道被误判为
    // "忙"，新弹幕只能从下面的车道开始排，表现为"seek 后弹幕从中下方出现"。
    // 直接重新初始化最简单也最稳妥（lane 数量不变，只清里面的 state）。
    for (var i = 0; i < _scrollLaneStates.length; i++) {
      final st = _scrollLaneStates[i];
      st.lastSpawnMs = -1e9;
      st.lastDurationMs = 0;
      st.lastWidth = 0;
      st.freeAtMs = -1e9;
    }
    for (var i = 0; i < _bottomLaneFreeMs.length; i++) {
      _bottomLaneFreeMs[i] = -1e9;
    }
  }

  ({int scrollEmitted, int scrollDropped}) update({
    required double currentMediaMs,
    required Size viewport,
    required double dpr,
    required DanmakuSettings settings,
    bool allowSpawn = true,
  }) {
    opacity = settings.opacity.clamp(0.1, 1.0).toDouble();
    _ensureLanes(viewport, dpr, settings);
    // 速度变化时：把屏上滚动弹幕重锚到新速度（保持当前位置、之后按新速度走），
    // 使全屏速度统一——否则旧弹幕仍按旧(慢)速、被新发的快弹幕追上并重叠覆盖。
    final speedFactor = resolveDanmakuMotionSpeedFactor(settings.speed);
    if (_lastSpeedFactor > 0 &&
        (speedFactor - _lastSpeedFactor).abs() > 0.001 &&
        _active.isNotEmpty) {
      _reanchorScrollSpeed(currentMediaMs, viewport, settings, speedFactor);
    }
    _lastSpeedFactor = speedFactor;
    _recycle(currentMediaMs, viewport.width);
    var emit = 0;
    var drop = 0;
    if (allowSpawn) {
      final stats = _spawn(currentMediaMs, viewport, dpr, settings);
      emit = stats.scrollEmitted;
      drop = stats.scrollDropped;
    } else {
      // 暂停发射期间（弹层打开）：把发射游标推进到当前媒体时间，
      // 这样恢复发射时不会把这段时间积压的弹幕一次性补发出来（避免轰炸 + 建图尖刺）。
      _nextIndex = _lowerBound(_comments, currentMediaMs.round());
    }
    _lastSpawnCursorMs = currentMediaMs;
    return (scrollEmitted: emit, scrollDropped: drop);
  }

  /// 滚动弹幕穿屏时长（所有滚动弹幕同一值，与字宽无关）。
  /// = baseMs×widthScale / 倍速，并按速度范围放开上下界，保证最慢/最快都能生效。
  double _scrollDurationMs(Size viewport, double speedFactor) {
    final widthScale = math
        .sqrt(viewport.width / _refViewportWidth)
        .clamp(_viewportDurationScaleMin, _viewportDurationScaleMax)
        .toDouble();
    final scaledBaseMs = _scrollBaseMs * widthScale;
    final fastFloorMs = math.min(_scrollMinMs, scaledBaseMs / danmakuSpeedMax);
    final slowCeilMs = scaledBaseMs / danmakuSpeedMin;
    return (scaledBaseMs / speedFactor)
        .clamp(fastFloorMs, slowCeilMs)
        .toDouble();
  }

  /// 速度变更：把屏上滚动弹幕重锚到新时长——保持每条当前位置不跳，之后按新速度走。
  /// 同时按新时长重建车道占用，使后续发射的间距正确、不与已在屏的追碰。
  void _reanchorScrollSpeed(
    double currentMs,
    Size viewport,
    DanmakuSettings settings,
    double speedFactor,
  ) {
    final newDuration = _scrollDurationMs(viewport, speedFactor);
    if (newDuration <= 0) return;
    // 1) 逐条重锚：保持当前进度(位置)，仅换新时长。
    //    progress = (now - spawn)/oldDur；新 spawn' = now - progress×newDur。
    for (final item in _active) {
      if (item.type != DanmakuCommentType.scroll) continue;
      final oldDur = item.durationMs;
      if (oldDur <= 0) continue;
      final progress = ((currentMs - item.spawnMs) / oldDur).clamp(0.0, 1.0);
      item.spawnMs = currentMs - progress * newDuration;
      item.durationMs = newDuration;
    }
    // 2) 用重锚后的活动项重建滚动车道占用(freeAtMs 等)，否则后续发射按旧时长间距会追碰。
    final fontPx = _fontSizePx(viewport, settings.fontScale);
    for (final st in _scrollLaneStates) {
      st.lastSpawnMs = -1e9;
      st.lastDurationMs = newDuration;
      st.lastWidth = 0;
      st.freeAtMs = -1e9;
    }
    for (final item in _active) {
      if (item.type != DanmakuCommentType.scroll) continue;
      final lane = _scrollLaneY.indexOf(item.y);
      if (lane < 0 || lane >= _scrollLaneStates.length) continue;
      final st = _scrollLaneStates[lane];
      if (item.spawnMs <= st.lastSpawnMs) continue;
      final travel = viewport.width + item.width;
      final clearProgress = (item.width + fontPx * 0.8) / travel;
      st.lastSpawnMs = item.spawnMs;
      st.lastWidth = item.width;
      st.freeAtMs = item.spawnMs + newDuration * clearProgress;
    }
  }

  // ---- 车道布局 ----

  void _ensureLanes(Size viewport, double dpr, DanmakuSettings settings) {
    final areaRatio = settings.displayAreaRatio.clamp(0.25, 1.0).toDouble();
    if (viewport == _lastViewport &&
        areaRatio == _lastAreaRatio &&
        settings.fontScale == _lastFontScale &&
        settings.avoidSubtitleArea == _lastAvoidSubtitle &&
        _scrollLaneY.isNotEmpty) {
      return;
    }
    _lastViewport = viewport;
    _lastAreaRatio = areaRatio;
    _lastFontScale = settings.fontScale;
    _lastAvoidSubtitle = settings.avoidSubtitleArea;

    final fontPx = _fontSizePx(viewport, settings.fontScale);
    // 行高 1.35 倍字号：比 1.55 更紧凑，小屏能多排 1-2 条车道，显示面积接近用户
    // 设定的 areaRatio；保留 ~35% 行间距仍能防止相邻弹幕文字触碰。
    final trackHeight = fontPx * 1.35;
    final edgePad = trackHeight * 0.10;
    final areaHeight = (viewport.height * areaRatio - edgePad).clamp(
      0.0,
      viewport.height,
    );
    final subtitleReserve = settings.avoidSubtitleArea
        ? viewport.height * 0.16
        : 0.0;

    // 用 round() 代替 floor()：areaRatio 是用户期望值而非硬裁剪上限，四舍五入
    // 避免 4.8 条→4 条的"差一条"误差，使实际显示面积更接近设定值。
    // 同时限制不超过按 viewport 满高计算的最大车道数，保证不溢出视口。
    final maxLanesForViewport = trackHeight <= 0
        ? 0
        : ((viewport.height - edgePad) / trackHeight)
              .floor()
              .clamp(0, 64)
              .toInt();
    final laneCount = trackHeight <= 0
        ? 0
        : (areaHeight / trackHeight).round().clamp(0, maxLanesForViewport);
    _scrollLaneY = List<double>.generate(
      laneCount,
      (i) => edgePad + i * trackHeight,
      growable: false,
    );
    final bottomMaxLanesForViewport = trackHeight <= 0
        ? 0
        : (((viewport.height - subtitleReserve - edgePad)) / trackHeight)
              .floor()
              .clamp(0, 64)
              .toInt();
    final bottomCount = trackHeight <= 0
        ? 0
        : (((viewport.height - subtitleReserve) * areaRatio) / trackHeight)
              .round()
              .clamp(0, bottomMaxLanesForViewport);
    _bottomLaneY = List<double>.generate(
      bottomCount,
      (i) =>
          viewport.height - subtitleReserve - edgePad - (i + 1) * trackHeight,
      growable: false,
    );
    _scrollLaneStates = List<_ScrollLaneState>.generate(
      _scrollLaneY.length,
      (_) => _ScrollLaneState(),
      growable: false,
    );
    _bottomLaneFreeMs = List<double>.filled(_bottomLaneY.length, -1e9);
  }

  double _fontSizePx(Size viewport, double fontScale) {
    final shortSide = math.min(viewport.width, viewport.height);
    final scale = (shortSide / _refShortSideDp)
        .clamp(_minViewportScale, _maxViewportScale)
        .toDouble();
    return _baseFontSp * fontScale.clamp(0.6, 1.4).toDouble() * scale;
  }

  // ---- 发射 ----

  ({int scrollEmitted, int scrollDropped}) _spawn(
    double currentMediaMs,
    Size viewport,
    double dpr,
    DanmakuSettings settings,
  ) {
    final density = settings.density.clamp(0.2, 1.0).toDouble();
    final hideDuplicate = settings.hideDuplicate;
    var spawned = 0;
    var iterations = 0;
    var scrollEmitted = 0;
    var scrollDropped = 0;
    _glyphBuildsThisFrame = 0;

    // ① 重试上一帧因车道满而未放下的弹幕 ─────────────────────────
    if (_retryQueue.isNotEmpty) {
      var kept = 0;
      for (var i = 0; i < _retryQueue.length; i++) {
        final c = _retryQueue[i];
        if (currentMediaMs - c.timeMs > _spawnCatchUpMs) {
          if (c.type == DanmakuCommentType.scroll) scrollDropped++;
          continue;
        }
        if (spawned >= _maxSpawnPerUpdate) {
          _retryQueue[kept++] = c;
          continue;
        }
        if (_emit(c, currentMediaMs, viewport, dpr, settings)) {
          spawned++;
          if (c.type == DanmakuCommentType.scroll) scrollEmitted++;
        } else {
          _retryQueue[kept++] = c;
        }
      }
      _retryQueue.length = kept;
    }

    // ② 处理新到的弹幕 ─────────────────────────
    if (_comments.isEmpty) {
      return (scrollEmitted: scrollEmitted, scrollDropped: scrollDropped);
    }
    while (_nextIndex < _comments.length &&
        _comments[_nextIndex].timeMs <= currentMediaMs) {
      final comment = _comments[_nextIndex];
      _nextIndex++;
      if (currentMediaMs - comment.timeMs > _spawnCatchUpMs) {
        if (comment.type == DanmakuCommentType.scroll) scrollDropped++;
        continue;
      }
      if (!_typeEnabled(comment.type, settings)) continue;
      if (density < 0.999 && _commentBucket(comment) >= (density * 1000)) {
        if (comment.type == DanmakuCommentType.scroll) scrollDropped++;
        continue;
      }
      if (hideDuplicate && _isDuplicate(comment, currentMediaMs)) {
        if (comment.type == DanmakuCommentType.scroll) scrollDropped++;
        continue;
      }
      if (_emit(comment, currentMediaMs, viewport, dpr, settings)) {
        spawned++;
        if (comment.type == DanmakuCommentType.scroll) scrollEmitted++;
      } else {
        // 车道满：加入重试队列，下一帧再试。队列已满则最旧的（队头）溢出丢弃。
        if (_retryQueue.length >= _maxRetryQueueSize) {
          final dropped = _retryQueue.removeAt(0);
          if (dropped.type == DanmakuCommentType.scroll) scrollDropped++;
        }
        _retryQueue.add(comment);
      }
      iterations++;
      if (spawned >= _maxSpawnPerUpdate ||
          iterations >= _maxIterationsPerUpdate) {
        break;
      }
    }
    return (scrollEmitted: scrollEmitted, scrollDropped: scrollDropped);
  }

  bool _typeEnabled(DanmakuCommentType type, DanmakuSettings settings) {
    return switch (type) {
      DanmakuCommentType.scroll => settings.scrollEnabled,
      DanmakuCommentType.top => settings.topEnabled,
      DanmakuCommentType.bottom => settings.bottomEnabled,
    };
  }

  bool _isDuplicate(DanmakuComment comment, double currentMs) {
    final key = comment.text.trim();
    if (key.isEmpty) return true;
    final last = _recentText[key];
    _recentText[key] = currentMs.round();
    if (_recentText.length > 512) {
      _recentText.remove(_recentText.keys.first);
    }
    return last != null && (currentMs - last) < _dedupWindowMs;
  }

  int _commentBucket(DanmakuComment comment) {
    var hash = comment.timeMs & 0x7fffffff;
    final id = comment.id;
    for (var i = 0; i < id.length; i++) {
      hash = ((hash * 33) ^ id.codeUnitAt(i)) & 0x7fffffff;
    }
    return hash % 1000;
  }

  /// 尝试将一条弹幕放入活动集。返回 true = 成功放入，false = 被拒（车道满/无车道）。
  /// 调用方根据返回值决定是否消耗 spawned 预算——被拒的不消耗，避免密集弹幕段
  /// 滚动评论被批量丢弃后整段消失。
  bool _emit(
    DanmakuComment comment,
    double currentMediaMs,
    Size viewport,
    double dpr,
    DanmakuSettings settings,
  ) {
    final fontPx = _fontSizePx(viewport, settings.fontScale);
    final strokePx = (_strokeBaseDp * settings.fontThickness.clamp(0.8, 1.4))
        .toDouble();
    final color = settings.colorEnabled ? comment.color : Colors.white;
    final speedFactor = resolveDanmakuMotionSpeedFactor(settings.speed);

    if (comment.type == DanmakuCommentType.scroll) {
      if (_scrollActiveCount() >= _maxActiveScroll) return false;
      // 快预筛：所有车道都还没腾出"进入区"就直接返回，省掉一次 ui.Paragraph 建图。
      // 真正的防追碰判定要等拿到字宽后再做（见 _pickScrollLane）。
      if (!_hasEntryReadyScrollLane(currentMediaMs)) return false;
      final glyph = _acquireGlyph(comment.text, color, fontPx, strokePx, dpr);
      if (glyph == null) return false; // 建图预算用尽：当帧丢弃，摊到后续帧。
      // 穿屏时长 ∝ sqrt(viewport.width / ref)：亚线性缩放。
      // 纯线性（旧方案）在平板上导致 15.5s 穿屏，视觉极慢；sqrt 保证宽屏
      // 适度加长（手机≈8.5s，平板≈11.5s）而不过分，且窄屏几乎无感。
      final widthScale = math
          .sqrt(viewport.width / _refViewportWidth)
          .clamp(_viewportDurationScaleMin, _viewportDurationScaleMax)
          .toDouble();
      final scaledBaseMs = _scrollBaseMs * widthScale;
      // 时长上界要随速度范围放开，否则"speed<1(更慢)"会被 clamp 到 base、永远变不慢。
      // 下界用读得清的固定地板与"最快倍速对应时长"取较小，保证最快档也能真的快。
      final fastFloorMs = math.min(
        _scrollMinMs,
        scaledBaseMs / danmakuSpeedMax,
      );
      final slowCeilMs = scaledBaseMs / danmakuSpeedMin;
      final durationMs = (scaledBaseMs / speedFactor)
          .clamp(fastFloorMs, slowCeilMs)
          .toDouble();
      final lane = _pickScrollLane(currentMediaMs, glyph.width, viewport.width);
      if (lane < 0) return false;
      final item = _obtain()
        ..type = DanmakuCommentType.scroll
        ..glyph = glyph
        ..spawnMs = currentMediaMs
        ..durationMs = durationMs
        ..y = _scrollLaneY[lane]
        ..width = glyph.width;
      _active.add(item);
      // 该车道下次可发射：上一条完全进入 + 间隙；同时记下宽度/时长用于追碰判定。
      final travel = viewport.width + glyph.width;
      final clearProgress = (glyph.width + fontPx * 0.8) / travel;
      final st = _scrollLaneStates[lane];
      st.lastSpawnMs = currentMediaMs;
      st.lastDurationMs = durationMs;
      st.lastWidth = glyph.width;
      st.freeAtMs = currentMediaMs + durationMs * clearProgress;
      return true;
    } else {
      final isTop = comment.type == DanmakuCommentType.top;
      // 顶部弹幕与滚动弹幕共用同一组车道与占用记录，避免二者在同一 Y 重叠。
      final lane = isTop
          ? _pickStaticTopLane(currentMediaMs)
          : _pickStaticBottomLane(currentMediaMs);
      if (lane < 0) return false;
      final glyph = _acquireGlyph(comment.text, color, fontPx, strokePx, dpr);
      if (glyph == null) return false;
      final durationMs = _staticBaseMs / speedFactor;
      final laneYs = isTop ? _scrollLaneY : _bottomLaneY;
      final item = _obtain()
        ..type = comment.type
        ..glyph = glyph
        ..spawnMs = currentMediaMs
        ..durationMs = durationMs
        ..y = laneYs[lane]
        ..width = glyph.width
        ..centerX = (viewport.width - glyph.width) / 2;
      _active.add(item);
      if (isTop) {
        // top 占据滚动车道 → 重置宽度记录，避免随后到的滚动弹幕被误判为"会追上"。
        final st = _scrollLaneStates[lane];
        st.lastSpawnMs = currentMediaMs;
        st.lastDurationMs = durationMs;
        st.lastWidth = 0;
        st.freeAtMs = currentMediaMs + durationMs;
      } else {
        _bottomLaneFreeMs[lane] = currentMediaMs + durationMs;
      }
      return true;
    }
  }

  /// 取字模：命中缓存直接返回（廉价）；未命中则受当帧建图预算限制，
  /// 超额返回 null（调用方丢弃该弹幕），把光栅化尖刺摊到多帧。
  _Glyph? _acquireGlyph(
    String text,
    Color color,
    double fontPx,
    double strokePx,
    double dpr,
  ) {
    final key = _GlyphKey(
      text: text,
      colorValue: color.toARGB32(),
      fontSizeKey: fontPx.round(),
      thicknessKey: (strokePx * 10).round(),
      dprKey: (dpr * 10).round(),
    );
    final cached = _glyphCache.peek(key);
    if (cached != null) return cached;
    if (_glyphBuildsThisFrame >= _maxGlyphBuildsPerUpdate) return null;
    final built = _buildGlyph(text, color, fontPx, strokePx, dpr);
    if (built == null) return null;
    _glyphCache.store(key, built);
    _glyphBuildsThisFrame++;
    return built;
  }

  int _scrollActiveCount() {
    var n = 0;
    for (final it in _active) {
      if (it.type == DanmakuCommentType.scroll) n++;
    }
    return n;
  }

  bool _hasEntryReadyScrollLane(double currentMs) {
    for (var i = 0; i < _scrollLaneStates.length; i++) {
      if (currentMs >= _scrollLaneStates[i].freeAtMs) return true;
    }
    return false;
  }

  /// 挑滚动车道：除"前条进入区已清空"外，再验证一遍"新条不会追上前条"。
  ///
  /// 所有滚动弹幕用同一 [durationMs] 跨 (viewport + 自身宽度)，故越宽越快。
  /// 若新条更宽（更快），需要前条进度 ≥ newW/(viewport + newW) —— 这样前条
  /// 在新条左缘走到屏幕左边 (x=0) 时已经退出，二者不会在屏上相撞。
  /// 推导：t 时刻新条左缘 = viewport - (t/d)*(viewport+newW)；前条右缘
  /// = (1 - prevProgress(t))*(viewport+prevW)；令 gap=0 解出的 t* 不超过
  /// 前条出屏时间，等价于上述阈值条件。
  int _pickScrollLane(double currentMs, double newWidth, double viewportWidth) {
    for (var i = 0; i < _scrollLaneStates.length; i++) {
      final st = _scrollLaneStates[i];
      if (currentMs < st.freeAtMs) continue;
      if (newWidth > st.lastWidth && st.lastWidth > 0) {
        final prevAge = currentMs - st.lastSpawnMs;
        if (prevAge < st.lastDurationMs) {
          final prevProgress = prevAge / st.lastDurationMs;
          final requiredProgress = newWidth / (viewportWidth + newWidth);
          if (prevProgress < requiredProgress) continue;
        }
      }
      return i;
    }
    return -1;
  }

  /// 顶部弹幕仅使用最靠近屏幕顶部的几条车道；若这些车道被滚动弹幕占满则丢弃，
  /// 绝不退到屏幕中部——宁可少显示一条，也不让顶部弹幕跑到画面中央。
  int _pickStaticTopLane(double currentMs) {
    final totalLanes = _scrollLaneStates.length;
    if (totalLanes == 0) return -1;
    // 最多使用前 1/3 车道（至少 1 条，至多 3 条）。
    final maxLane = (totalLanes / 3).ceil().clamp(1, 3);
    for (var i = 0; i < maxLane; i++) {
      if (currentMs >= _scrollLaneStates[i].freeAtMs) return i;
    }
    return -1;
  }

  int _pickStaticBottomLane(double currentMs) {
    for (var i = 0; i < _bottomLaneFreeMs.length; i++) {
      if (currentMs >= _bottomLaneFreeMs[i]) return i;
    }
    return -1;
  }

  // ---- 回收 ----

  // 诊断：_recycle 统计与最老滚动项快照（外部由 diag 日志读取）。
  int recycledSinceDiag = 0;
  int forceRecycledSinceDiag = 0;
  int stuckOver20sCount = 0;
  double oldestScrollAgeMs = 0;
  double oldestScrollDurationMs = 0;
  double oldestScrollWidth = 0;
  double oldestScrollLeftPlusWidth = 0;

  void resetDiagCounters() {
    recycledSinceDiag = 0;
    forceRecycledSinceDiag = 0;
  }

  void _recycle(double currentMediaMs, double viewportWidth) {
    var w = 0;
    var oldestAge = 0.0;
    var oldestDur = 0.0;
    var oldestWidth = 0.0;
    var oldestLPW = 0.0;
    var stuck20s = 0;
    for (var r = 0; r < _active.length; r++) {
      final item = _active[r];
      // 统一用时间检查回收：滚动和静态同样的判据 (age >= durationMs 即回收)。
      // 数学上等价于"scrollLeft+width 是否 > 0"，但单次浮点减法+比较，不依赖
      // viewport 参数，更可靠也更便宜。
      final age = currentMediaMs - item.spawnMs;
      var alive = age < item.durationMs;
      if (alive && item.type == DanmakuCommentType.scroll && age > 20000) {
        // 完全不该发生（dur 上限 ~12s）；进了说明状态被破坏，强制回收。
        alive = false;
        forceRecycledSinceDiag++;
      }
      if (item.type == DanmakuCommentType.scroll && age > 15000) {
        stuck20s++;
      }
      if (alive) {
        _active[w++] = item;
        if (item.type == DanmakuCommentType.scroll) {
          final age = currentMediaMs - item.spawnMs;
          if (age > oldestAge) {
            oldestAge = age;
            oldestDur = item.durationMs;
            oldestWidth = item.width;
            oldestLPW =
                item.scrollLeft(currentMediaMs, viewportWidth) + item.width;
          }
        }
      } else {
        _release(item);
        recycledSinceDiag++;
      }
    }
    if (w < _active.length) {
      _active.removeRange(w, _active.length);
    }
    oldestScrollAgeMs = oldestAge;
    oldestScrollDurationMs = oldestDur;
    oldestScrollWidth = oldestWidth;
    oldestScrollLeftPlusWidth = oldestLPW;
    stuckOver20sCount = stuck20s;
  }

  // ---- 对象池 ----

  _DanmakuItem _obtain() {
    if (_pool.isNotEmpty) return _pool.removeLast();
    return _DanmakuItem();
  }

  void _release(_DanmakuItem item) {
    if (_pool.length < 256) _pool.add(item);
  }

  void _releaseAll() {
    for (final it in _active) {
      _release(it);
    }
    _active.clear();
  }

  void clearActive() => _releaseAll();

  // ---- Atlas 管理 ----

  /// 试在 atlas 上分配一块 w×h 像素的空间。null = 字模比单页还大（极宽文本）
  /// 或 atlas 已满且没有可安全淘汰的页，调用方应走 fallback（单独 ui.Image）。
  _AtlasSlot? _allocAtlasSlot(int w, int h) {
    // 注：曾在 Mali 上禁用 atlas（彼时 atlas 的 pic.toImage 离屏渲染会与 mpv-Vulkan
    // 争用 GPU 造成 raster 尖刺）。现已让 Mali 上 mpv 走 GLES（见 MpvGpuBackend），
    // 双 Vulkan 争用消除，atlas 离屏渲染不再尖刺；而 source 直绘在密集弹幕下每条一次
    // drawImageRect 反而把 avgRaster 推高（实测 scrollActive~20 时 ~2.4ms、avgTotal
    // ~9ms 超 120Hz 预算 → 颤抖）。恢复 atlas：drawRawAtlas 批绘一次画一组，raster 回落。
    // ① 任一现存页能放下就用
    for (final page in _atlasPages) {
      final slot = page.tryAlloc(w, h);
      if (slot != null) return slot;
    }
    // ② 还没到 max：直接开新页
    if (_atlasPages.length < _maxAtlasPages) {
      final page = _AtlasPage(_atlasPageWidth, _atlasPageHeight);
      _atlasPages.add(page);
      return page.tryAlloc(w, h);
    }
    // ③ 到 max 了：只淘汰"完全无引用"的页（缓存 + active 都不指向它）
    //   绝不能淘汰还有在屏弹幕引用的页——否则用户会看到弹幕滚到一半凭空消失。
    final referenced = <_AtlasPage>{};
    for (final glyph in _glyphCache.entriesForDiag.values) {
      final slot = glyph.atlasSlot;
      if (slot != null) referenced.add(slot.page);
    }
    for (final item in _active) {
      final slot = item.glyph.atlasSlot;
      if (slot != null) referenced.add(slot.page);
    }
    final evictableIdx = _atlasPages.indexWhere((p) => !referenced.contains(p));
    if (evictableIdx >= 0) {
      final evicted = _atlasPages.removeAt(evictableIdx);
      // 缓存里指向 evicted 的条目其实都已经 LRU 淘汰过（不在 referenced 里），
      // 但保险起见再清一遍。
      _glyphCache.removeWhere((k, v) => identical(v.atlasSlot?.page, evicted));
      evicted.disposeAll();
      final page = _AtlasPage(_atlasPageWidth, _atlasPageHeight);
      _atlasPages.add(page);
      return page.tryAlloc(w, h);
    }
    // ④ 所有页都还有引用：让 caller 走 fallback
    return null;
  }

  /// 异步 kick-off：所有 dirty 且未在 flush 中的页都触发一次 async flush。
  /// **不阻塞**，立即返回。UI 线程不需要等 GPU。
  /// 在 atlas materialize 之前，painter 通过 _Glyph 的 source image 兜底，
  /// 几帧后 flush 完成自动切到 drawRawAtlas 批绘。
  void kickoffAtlasFlushes() {
    if (_disposed) return;
    for (final page in _atlasPages) {
      if (page.shouldFlushNow()) {
        unawaited(page.flushAsync());
      }
    }
    // 字模一旦 materialize 进 atlas，其独立源 image 就成了死重量——之前靠 GC
    // finalizer 回收，会攒成一批在某次 GC 里集中销毁（实测 ~123ms 卡顿尖刺），
    // 且 finalizer 可能在 teardown 后才跑去销毁 GPU 纹理 → 闪退。这里在 UI 线程
    // 上确定性释放已 materialize 的源（active 项必引用未被淘汰的页，故安全）。
    for (final it in _active) {
      it.glyph.releaseSourceIfMaterialized();
    }
  }

  void _disposeAllAtlasPages() {
    for (final page in _atlasPages) {
      page.disposeAll();
    }
    _atlasPages.clear();
  }

  // ---- Atlas 管理 ----

  // ---- 字模光栅化（按物理像素，预渲染为 ui.Image）----

  _Glyph? _buildGlyph(
    String text,
    Color color,
    double fontPx,
    double strokePx,
    double dpr,
  ) {
    final display = text.trim();
    if (display.isEmpty) return null;
    final fontWeight = strokePx >= 1.7 ? FontWeight.w700 : FontWeight.w600;

    ui.Paragraph buildPara({Paint? foreground, Color? fillColor}) {
      final builder =
          ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textDirection: TextDirection.ltr,
              maxLines: 1,
              fontWeight: fontWeight,
              fontSize: fontPx,
            ),
          )..pushStyle(
            ui.TextStyle(
              color: fillColor,
              foreground: foreground,
              fontSize: fontPx,
              fontWeight: fontWeight,
              height: 1.0,
            ),
          );
      builder.addText(display);
      final paragraph = builder.build();
      paragraph.layout(const ui.ParagraphConstraints(width: 100000.0));
      return paragraph;
    }

    final stroke = buildPara(
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokePx
        ..color = const Color(0xCC000000),
    );
    final fill = buildPara(fillColor: color);
    final textWidth = fill.maxIntrinsicWidth;
    final textHeight = fill.height;
    if (textWidth <= 0 || textHeight <= 0) return null;

    // 逻辑尺寸 = 文字 + 描边余量 + 顶部额外余量。
    // height:1.0 的行盒会把字形上缘的溢出(带上标/重音/CJK 顶部)连同描边一起裁掉，
    // 表现为"弹幕上面被削一点"。给图像顶部多留 ~0.15×字号的余量并把文字下移同量；
    // 车道高 trackHeight=1.35×字号，足够容纳，文字只是更居中、不再被削。
    final topExtra = fontPx * 0.15;
    final logicalWidth = textWidth + strokePx;
    final logicalHeight = textHeight + strokePx + topExtra;
    final halfStroke = strokePx / 2.0;
    final drawDy = halfStroke + topExtra;

    // 一次性将描边+填充光栅化为 ui.Image。优先尝试塞进 atlas（后续 painter
    // 用 drawRawAtlas 一次画一组）；atlas 装不下（极宽文本）退回独立 image。
    final pixelW = (logicalWidth * dpr).ceil();
    final pixelH = (logicalHeight * dpr).ceil();
    final rec = ui.PictureRecorder();
    Canvas(rec)
      ..scale(dpr)
      ..drawParagraph(stroke, Offset(halfStroke, drawDy))
      ..drawParagraph(fill, Offset(halfStroke, drawDy));
    final picture = rec.endRecording();
    final image = picture.toImageSync(pixelW, pixelH);
    picture.dispose();

    final slot = _allocAtlasSlot(pixelW, pixelH);
    if (slot != null) {
      // 调度：异步 flush 时把 image 盖到 atlas。在 atlas materialize 之前，
      // _Glyph 用 image 自己兜底渲染（drawImageRect 路径），不会卡 UI 线程。
      slot.page.schedule(image, slot.pixelX, slot.pixelY, pixelW, pixelH);
      return _Glyph.atlas(
        slot: slot,
        sourceImage: image,
        width: logicalWidth,
        height: logicalHeight,
      );
    }
    return _Glyph.fallback(
      image: image,
      width: logicalWidth,
      height: logicalHeight,
    );
  }

  int _lowerBound(List<DanmakuComment> list, int targetMs) {
    var low = 0;
    var high = list.length;
    while (low < high) {
      final mid = low + ((high - low) >> 1);
      if (list[mid].timeMs < targetMs) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  void dispose() {
    _disposed = true;
    // 同步把所有字模源 image 销毁（atlas-backed 与 fallback 都释放），不留给 GC
    // finalizer——否则它们会在 surface/Impeller 拆除之后才去销毁 GPU 资源，
    // 撞上已销毁的 Vulkan mutex 闪退。此时已无任何在屏弹幕，释放绝对安全。
    for (final glyph in _glyphCache.entriesForDiag.values) {
      glyph.disposeSource();
    }
    for (final it in _active) {
      it.glyph.disposeSource();
    }
    _releaseAll();
    _pool.clear();
    _glyphCache.clear();
    _recentText.clear();
    _retryQueue.clear();
    _disposeAllAtlasPages();
  }
}

// ---------------------------------------------------------------------------
// 滚动车道占用快照：除"何时可放下一条"外，还要记下上一条的 spawn/duration/width，
// 才能判断新条会不会因更宽（更快）而追上前条。
// ---------------------------------------------------------------------------

class _ScrollLaneState {
  double freeAtMs = -1e9;
  double lastSpawnMs = -1e9;
  double lastDurationMs = 1;
  double lastWidth = 0;
}

// ---------------------------------------------------------------------------
// 活动弹幕项。
// ---------------------------------------------------------------------------

class _DanmakuItem {
  DanmakuCommentType type = DanmakuCommentType.scroll;
  late _Glyph glyph;
  double spawnMs = 0;
  double durationMs = 1;
  double y = 0;
  double width = 0;
  double centerX = 0; // 顶/底弹幕用

  /// 滚动弹幕的左边缘 x（媒体时间）。从 viewport 右侧进入，向左移动。
  double scrollLeft(double currentMs, double viewportWidth) {
    final progress = ((currentMs - spawnMs) / durationMs)
        .clamp(0.0, 1.0)
        .toDouble();
    final travel = viewportWidth + width;
    return viewportWidth - progress * travel;
  }
}

// ---------------------------------------------------------------------------
// 字模缓存（LRU；缓存 ui.Image，淘汰只丢引用，由 GC finalizer 回收）。
// ---------------------------------------------------------------------------

class _GlyphKey {
  final String text;
  final int colorValue;
  final int fontSizeKey;
  final int thicknessKey;
  final int dprKey;

  const _GlyphKey({
    required this.text,
    required this.colorValue,
    required this.fontSizeKey,
    required this.thicknessKey,
    required this.dprKey,
  });

  @override
  bool operator ==(Object other) {
    return other is _GlyphKey &&
        other.text == text &&
        other.colorValue == colorValue &&
        other.fontSizeKey == fontSizeKey &&
        other.thicknessKey == thicknessKey &&
        other.dprKey == dprKey;
  }

  @override
  int get hashCode =>
      Object.hash(text, colorValue, fontSizeKey, thicknessKey, dprKey);
}

// ---------------------------------------------------------------------------
// 字模 Atlas：所有字模光栅化到 1024x1024 大纹理上，painter 用 drawRawAtlas
// 一次 GPU 调用画完整组弹幕，把 N 次 drawImageRect（N 次纹理绑定+状态切换）
// 合并成 K 次（K = atlas 页数，通常 1~2）。N=160 → 1~2 大约能省 1.5~3ms/帧。
// ---------------------------------------------------------------------------

/// Atlas 中分配给一个字模的位置。
class _AtlasSlot {
  final _AtlasPage page;
  final int pixelX;
  final int pixelY;
  final int pixelW;
  final int pixelH;

  /// 预算好的 src rect（指向 atlas image 内的子区域）。
  final Rect srcRect;

  /// 分配时 page._pendingGen 的值。当 page._committedGen >= scheduledGen，
  /// 说明本 slot 已经被画进当前的 atlas image，可以走 atlas 路径；
  /// 否则 atlas 还没把本 slot 的像素 stamp 上来，painter 应用 source image 兜底。
  final int scheduledGen;

  _AtlasSlot(
    this.page,
    this.pixelX,
    this.pixelY,
    this.pixelW,
    this.pixelH,
    this.scheduledGen,
  ) : srcRect = Rect.fromLTWH(
        pixelX.toDouble(),
        pixelY.toDouble(),
        pixelW.toDouble(),
        pixelH.toDouble(),
      );

  ui.Image? get image => page._image;
  bool get isMaterialized => page._committedGen >= scheduledGen;
}

/// 一次待 stamp 的字模：源 ui.Image + atlas 目标位置。flush 时把源画到 atlas。
class _AtlasStamp {
  final ui.Image source;
  final int dstX;
  final int dstY;
  final int dstW;
  final int dstH;
  _AtlasStamp(this.source, this.dstX, this.dstY, this.dstW, this.dstH);
}

/// 一页 atlas（一个 ui.Image）。Shelf packing：水平排满后下一行。
/// flushAsync() 用 picture.toImage()（异步），不阻塞 UI 线程。
/// 数据流：
///   _pendingGen：新 slot 拿到的代号；schedule 时 slot 持这个代号。
///   _committedGen：当前 _image 包含到哪一代为止；slot.scheduledGen <= 这个值
///                  说明该 slot 已经入 atlas，可以走 drawRawAtlas 路径。
/// 在 atlas 尚未 materialize 之前，_Glyph 用 _sourceImage 兜底渲染，所以
/// 这里 flush 时 **不** 释放源 image（由 _Glyph 持有，GC 自然回收）。
class _AtlasPage {
  static const int _slotPad = 2;

  // flush 批处理：每次 flushAsync 都要 pic.toImage 整页（1024×512）重渲染——这是
  // 一次离屏 GPU 渲染，会与视频/主帧合成抢 GPU，密集弹幕段表现为 raster 尖刺
  // （实测 14~27ms）。之前每帧只要 dirty 就 flush，导致密集段几乎每帧整页重渲。
  // 改为：攒够 _flushStampThreshold 个待入字模、或已等待 _flushMaxWaitFrames 帧
  // 才 flush。把 flush 次数压到 1/3~1/6，尖刺随之消失。等待期间新字模继续走
  // source image 兜底（drawImageRect），观感无损。
  static const int _flushStampThreshold = 8;
  static const int _flushMaxWaitFrames = 6;

  final int width;
  final int height;
  ui.Image? _image;
  int _committedGen = -1;
  int _pendingGen = 0;
  bool _flushInFlight = false;
  bool _evicted = false;
  int _shelfX = 0;
  int _shelfY = 0;
  int _shelfH = 0;
  int _waitedFrames = 0;
  final List<_AtlasStamp> _pending = <_AtlasStamp>[];

  _AtlasPage(this.width, this.height);

  bool get isDirty => _pending.isNotEmpty;
  bool get isFlushInFlight => _flushInFlight;

  /// 是否到了该 flush 的时机（攒够批量或等待够久）。调用方每帧对 dirty 页调用一次。
  bool shouldFlushNow() {
    if (!isDirty || _flushInFlight || _evicted) return false;
    _waitedFrames++;
    return _pending.length >= _flushStampThreshold ||
        _waitedFrames >= _flushMaxWaitFrames;
  }

  /// 尝试在本页分配空间。null = 装不下（应换页或走 fallback）。
  _AtlasSlot? tryAlloc(int w, int h) {
    final wp = w + _slotPad * 2;
    final hp = h + _slotPad * 2;
    if (wp > width || hp > height) return null;
    if (_shelfX + wp <= width && hp <= _shelfH) {
      final slot = _AtlasSlot(
        this,
        _shelfX + _slotPad,
        _shelfY + _slotPad,
        w,
        h,
        _pendingGen,
      );
      _shelfX += wp;
      return slot;
    }
    final newY = _shelfY + _shelfH;
    if (newY + hp > height) return null;
    _shelfX = wp;
    _shelfY = newY;
    _shelfH = hp;
    return _AtlasSlot(this, _slotPad, newY + _slotPad, w, h, _pendingGen);
  }

  void schedule(ui.Image source, int x, int y, int w, int h) {
    _pending.add(_AtlasStamp(source, x, y, w, h));
  }

  /// 异步 flush：在 GPU 上把 pending 列表的源 image 盖到新 atlas image，
  /// 完成后原子替换 _image 并推 _committedGen。**不阻塞 UI 线程**，相邻几帧
  /// 内的弹幕会通过 _Glyph._sourceImage 兜底渲染（drawImageRect），完成后
  /// 自动切换到 drawRawAtlas 批绘路径。
  Future<void> flushAsync() async {
    if (_flushInFlight || _pending.isEmpty || _evicted) return;
    _flushInFlight = true;
    _waitedFrames = 0;
    final flushingGen = _pendingGen;
    _pendingGen++; // 在此之后 schedule 的 slot 走下一代
    final stamps = List<_AtlasStamp>.from(_pending);
    _pending.clear();

    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    final copyPaint = Paint()..isAntiAlias = false;
    if (_image != null) {
      canvas.drawImage(_image!, Offset.zero, copyPaint);
    }
    final stampPaint = Paint()
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false;
    for (final s in stamps) {
      final src = Rect.fromLTWH(
        0,
        0,
        s.source.width.toDouble(),
        s.source.height.toDouble(),
      );
      final dst = Rect.fromLTWH(
        s.dstX.toDouble(),
        s.dstY.toDouble(),
        s.dstW.toDouble(),
        s.dstH.toDouble(),
      );
      canvas.drawImageRect(s.source, src, dst, stampPaint);
    }
    final pic = rec.endRecording();
    try {
      final newImg = await pic.toImage(width, height);
      if (_evicted) {
        newImg.dispose();
        return;
      }
      final oldImg = _image;
      _image = newImg;
      _committedGen = flushingGen;
      oldImg?.dispose();
    } finally {
      pic.dispose();
      _flushInFlight = false;
      // 不释放 stamps[i].source —— 已经被 _Glyph._sourceImage 持有，
      // 让 _Glyph 离开 cache 时 GC 自然回收。
    }
  }

  void disposeAll() {
    _evicted = true;
    _image?.dispose();
    _image = null;
    _pending.clear();
  }
}

class _Glyph {
  /// atlasSlot 不为 null = 字模目标在 atlas 里（materialized 后用 drawRawAtlas）。
  /// _sourceImage = 字模独立 ui.Image：
  ///   - atlasSlot==null：字模太大装不下 atlas，永远走 source 路径
  ///   - atlasSlot!=null 且未 materialize：用 source 兜底，几帧后 atlas 就绪自动切
  ///   - atlasSlot!=null 且已 materialize：source 不再被 image getter 用，但仍
  ///     被本 _Glyph 强引用，等 _Glyph 自己被 GC（cache 淘汰）后 GC 回收 source
  final _AtlasSlot? atlasSlot;
  final ui.Image _sourceImage;
  final double width; // 逻辑像素（含描边余量）
  final double height;
  final Rect _sourceSrcRect;

  /// 源 image 是否已确定性释放。释放后只能走 atlas 路径绘制（atlas-backed），
  /// fallback 字模（atlasSlot==null）永不释放源，故此标志只会对 atlas-backed 置位。
  bool _sourceReleased = false;

  _Glyph.atlas({
    required _AtlasSlot slot,
    required ui.Image sourceImage,
    required this.width,
    required this.height,
  }) : atlasSlot = slot,
       _sourceImage = sourceImage,
       _sourceSrcRect = Rect.fromLTWH(
         0,
         0,
         sourceImage.width.toDouble(),
         sourceImage.height.toDouble(),
       );

  _Glyph.fallback({
    required ui.Image image,
    required this.width,
    required this.height,
  }) : atlasSlot = null,
       _sourceImage = image,
       _sourceSrcRect = Rect.fromLTWH(
         0,
         0,
         image.width.toDouble(),
         image.height.toDouble(),
       );

  /// 当前用于绘制的 image：atlas 已 materialize 用 atlas image，否则 source。
  ui.Image get image {
    final slot = atlasSlot;
    if (slot != null && slot.isMaterialized) {
      final atlasImg = slot.image;
      if (atlasImg != null) return atlasImg;
    }
    return _sourceImage;
  }

  /// 对应 image 的 src rect：atlas image 用 slot.srcRect，source image 用整图。
  Rect get srcRect {
    final slot = atlasSlot;
    if (slot != null && slot.isMaterialized && slot.image != null) {
      return slot.srcRect;
    }
    return _sourceSrcRect;
  }

  /// 已绘制完成且字模已进 atlas 时释放源 image。
  /// 仅 atlas-backed 且 materialize（atlas image 已就绪）时释放：此后 image getter
  /// 恒走 atlas 分支，不会再读源。调用方需保证仅对在屏（active）字模调用——active
  /// 引用的页绝不会被淘汰，故 atlas image 不会变 null。fallback 字模直接跳过。
  void releaseSourceIfMaterialized() {
    if (_sourceReleased) return;
    final slot = atlasSlot;
    if (slot == null) return; // fallback：源是唯一可绘 image，永不释放
    if (slot.isMaterialized && slot.image != null) {
      _sourceImage.dispose();
      _sourceReleased = true;
    }
  }

  /// teardown 专用：无条件同步释放源 image（含 fallback）。仅在引擎 dispose、
  /// 确认再无任何在屏绘制时调用。幂等。
  void disposeSource() {
    if (_sourceReleased) return;
    _sourceImage.dispose();
    _sourceReleased = true;
  }
}

class _GlyphCache {
  final int maxEntries;
  final LinkedHashMap<_GlyphKey, _Glyph> _entries =
      LinkedHashMap<_GlyphKey, _Glyph>();

  _GlyphCache(this.maxEntries);

  /// 查缓存，命中则提到最近使用并返回；未命中返回 null（不建图）。
  _Glyph? peek(_GlyphKey key) {
    final existing = _entries.remove(key);
    if (existing != null) {
      _entries[key] = existing; // 提到最近使用
      return existing;
    }
    return null;
  }

  /// 写入新建好的字模，并按 LRU 淘汰最久未用项。
  void store(_GlyphKey key, _Glyph glyph) {
    _entries[key] = glyph;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void clear() {
    _entries.clear();
  }

  /// 删除满足 test 的条目（atlas 页淘汰时用来同步清缓存）。
  void removeWhere(bool Function(_GlyphKey, _Glyph) test) {
    _entries.removeWhere(test);
  }

  /// 给 atlas 引用扫描用：只读 view，不会改变 LRU 顺序。
  Map<_GlyphKey, _Glyph> get entriesForDiag => _entries;
}

// ---------------------------------------------------------------------------
// 画笔：每帧绘制活动集（一次 drawImageRect / 条），由 ticker 触发 repaint。
// ---------------------------------------------------------------------------

class _DanmakuPainter extends CustomPainter {
  final _DanmakuEngine engine;
  final ui.Image? maskImage;
  final double displayAreaRatio;
  final double captureAreaRatio;

  _DanmakuPainter({
    required this.engine,
    required Listenable repaint,
    required this.maskImage,
    required this.displayAreaRatio,
    required this.captureAreaRatio,
  }) : super(repaint: repaint);

  // isAntiAlias=false：弹幕字模已经预光栅化为 ui.Image（描边+填充），其边缘
  // 已自带抗锯齿。drawImageRect 时再开 AA 是双重抗锯齿，纯属浪费 GPU。
  // FilterQuality.low（双线性）也比默认的更省。
  static final Paint _imgPaint = Paint()
    ..filterQuality = FilterQuality.low
    ..isAntiAlias = false;
  static final Paint _maskPaint = Paint()
    ..blendMode = BlendMode.dstOut
    ..filterQuality = FilterQuality.low
    ..isAntiAlias = false;

  // 批绘缓冲：按 ui.Image 分组的 RSTransform + src Rect 数组。
  // 同一 image 的所有 item 一次 drawRawAtlas 提交，把 N 次 drawImageRect 的
  // 纹理绑定/状态切换合并成 K 次（K=不同 image 数，通常 1~3）。
  // 复用 painter 实例存活期内的存储，避免每帧 alloc。
  final Map<ui.Image, _DrawBatch> _drawBatches = <ui.Image, _DrawBatch>{};
  final List<_DrawBatch> _batchPool = <_DrawBatch>[];

  _DrawBatch _obtainBatch() {
    if (_batchPool.isNotEmpty) {
      final b = _batchPool.removeLast();
      b.count = 0;
      return b;
    }
    return _DrawBatch();
  }

  void _recycleBatches() {
    for (final b in _drawBatches.values) {
      _batchPool.add(b);
    }
    _drawBatches.clear();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final items = engine.active;
    if (items.isEmpty) return;

    // 异步 kick-off atlas flush：不阻塞 UI 线程。本帧未 materialize 的字模
    // 走 source image 兜底（drawImageRect 那条路），下一帧或几帧后 atlas 就绪
    // 自动切到 drawRawAtlas 批绘路径。
    engine.kickoffAtlasFlushes();

    final currentMs = engine.lastMediaMs;
    final currentMask = maskImage;
    final hasMask = currentMask != null;

    // 有遮罩时先 saveLayer：弹幕画到离屏层后，用 dstOut 把遮罩区域"扣掉"，
    // 最终合成回主 canvas —— 与旧 LocalDanmakuPainter 一致。
    if (hasMask) {
      canvas.saveLayer(Offset.zero & size, Paint());
    }

    final opacity = engine.opacity;
    final paint = _imgPaint;
    paint.color = opacity < 0.999
        ? Color.fromARGB((opacity * 255).round(), 255, 255, 255)
        : const Color(0xFFFFFFFF);

    // ① 按 image 分组累积 transform + src rect
    //   - atlas 已 materialize 的 item：image = atlas page ui.Image（多 item 共享 → 真正批绘）
    //   - atlas 未 materialize 或 fallback 的 item：image = 自己的 source ui.Image
    //     （每个独立 image → 等价于一次 drawImage，不批绘但能正常显示）
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final glyph = item.glyph;
      final image = glyph.image;
      final double left;
      if (item.type == DanmakuCommentType.scroll) {
        left = item.scrollLeft(currentMs, size.width);
        if (left >= size.width || left + item.width <= 0) continue;
      } else {
        left = item.centerX;
      }
      var batch = _drawBatches[image];
      if (batch == null) {
        batch = _obtainBatch();
        _drawBatches[image] = batch;
      }
      batch.add(glyph, left, item.y);
    }

    // ② 每组一次 drawRawAtlas 提交：把 N 次 GPU draw 合成 K 次
    for (final entry in _drawBatches.entries) {
      final batch = entry.value;
      if (batch.count == 0) continue;
      canvas.drawRawAtlas(
        entry.key,
        batch.transformsView,
        batch.rectsView,
        null,
        null,
        null,
        paint,
      );
    }

    _recycleBatches();

    // 应用 AI 遮罩：在弹幕层上用 dstOut 模式绘制遮罩图，把检测到的内容区域扣除。
    if (currentMask != null) {
      final destinationCoverage = clampDanmakuAreaRatio(displayAreaRatio);
      final sourceCoverage = resolveDanmakuMaskSourceCoverageRatio(
        displayAreaRatio: displayAreaRatio,
        captureAreaRatio: captureAreaRatio,
      );
      final maskSrc = Rect.fromLTWH(
        0,
        0,
        currentMask.width.toDouble(),
        currentMask.height.toDouble() * sourceCoverage,
      );
      final maskDst = Rect.fromLTWH(
        0,
        0,
        size.width,
        size.height * destinationCoverage,
      );
      canvas.drawImageRect(currentMask, maskSrc, maskDst, _maskPaint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _DanmakuPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// 单次 drawRawAtlas 批的缓冲：累积 RSTransform(4 float)+ src Rect(4 float)。
// 内部 Float32List 按指数倍增 ([64]→[128]→...)，复用避免每帧 alloc。
// ---------------------------------------------------------------------------

class _DrawBatch {
  static const int _initialCapacity = 64;

  Float32List _transforms = Float32List(_initialCapacity * 4);
  Float32List _rects = Float32List(_initialCapacity * 4);
  int count = 0;

  void add(_Glyph glyph, double left, double y) {
    if ((count + 1) * 4 > _transforms.length) {
      final newCap = _transforms.length * 2;
      final newT = Float32List(newCap);
      final newR = Float32List(newCap);
      newT.setRange(0, _transforms.length, _transforms);
      newR.setRange(0, _rects.length, _rects);
      _transforms = newT;
      _rects = newR;
    }
    // RSTransform 表示 scale+rotate+translate：四元组 (scos, ssin, tx, ty)，
    // 无旋转时 scos=scale, ssin=0。
    // glyph.image 的源宽 = glyph.srcRect.width（物理像素 = 逻辑 * dpr）；
    // 我们要画到 logical width，scale = glyph.width / glyph.srcRect.width = 1/dpr。
    // drawRawAtlas 把 src rect 左上角 (sx,sy) 变换后画到 (tx, ty)，因此
    // tx = 目标 left, ty = 目标 top。
    final scale = glyph.width / glyph.srcRect.width;
    final i = count * 4;
    _transforms[i] = scale;
    _transforms[i + 1] = 0.0;
    _transforms[i + 2] = left;
    _transforms[i + 3] = y;
    _rects[i] = glyph.srcRect.left;
    _rects[i + 1] = glyph.srcRect.top;
    _rects[i + 2] = glyph.srcRect.right;
    _rects[i + 3] = glyph.srcRect.bottom;
    count++;
  }

  /// 返回供 drawRawAtlas 用的视图（长度恰好为 count*4）。
  /// 使用 Float32List.sublistView 避免拷贝。
  Float32List get transformsView {
    if (count * 4 == _transforms.length) return _transforms;
    return Float32List.sublistView(_transforms, 0, count * 4);
  }

  Float32List get rectsView {
    if (count * 4 == _rects.length) return _rects;
    return Float32List.sublistView(_rects, 0, count * 4);
  }
}
