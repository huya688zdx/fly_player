import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../controller/danmaku_controller.dart';
import '../models/danmaku_comment.dart';
import '../models/danmaku_dynamic_occlusion.dart';
import '../models/danmaku_settings.dart';
import 'engine/danmaku_layout.dart';
import 'engine/local_danmaku_item.dart';
import 'engine/local_danmaku_painter.dart';

class DanmakuOverlay extends StatefulWidget {
  final DanmakuController controller;
  final Duration position;
  final bool paused;
  final double playbackSpeedFactor;
  final DanmakuDynamicOcclusionState occlusionState;
  final bool deferViewportSync;

  const DanmakuOverlay({
    super.key,
    required this.controller,
    required this.position,
    required this.paused,
    this.playbackSpeedFactor = 1.0,
    required this.occlusionState,
    this.deferViewportSync = false,
  });

  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

enum _CommentAdmissionResult { admitted, queued, blocked, skipped, dropped }

enum _OverloadLevel { normal, soft, hard }

class _DanmakuRuntimeTuning {
  final _OverloadLevel overloadLevel;
  final int effectiveDurationMs;
  final double effectiveDensity;
  final double effectiveAreaRatio;

  const _DanmakuRuntimeTuning({
    required this.overloadLevel,
    required this.effectiveDurationMs,
    required this.effectiveDensity,
    required this.effectiveAreaRatio,
  });
}

class _PendingScrollComment {
  DanmakuComment comment;
  final int eligibleAtMs;
  final int enqueuedAtMs;
  final int delayBudgetMs;
  final String normalizedText;
  final int timeBucket;
  String displayText;
  int mergedCount;

  _PendingScrollComment({
    required this.comment,
    required this.eligibleAtMs,
    required this.enqueuedAtMs,
    required this.delayBudgetMs,
    required this.normalizedText,
    required this.timeBucket,
    String? displayText,
  }) : mergedCount = 1,
       displayText = displayText ?? comment.text;

  void mergeWith() {
    mergedCount += 1;
    displayText = '${comment.text} x$mergedCount';
  }
}

class _DanmakuOverlayState extends State<DanmakuOverlay>
    with SingleTickerProviderStateMixin {
  static const int _densityBucketScale = 1000;
  static const int _massiveModeThreshold = 1200;
  static const int _minimumDuplicateWindowMs = 2500;
  static const int _staticDanmakuDurationMs = 2600;
  static const int _minVisibleScrollItems = 8;
  static const int _maxVisibleScrollItems = 96;
  static const int _maxPendingVisibleScrollItems = 160;
  static const double _perTrackVisibleScrollMultiplier = 3.2;
  static const double _subtitleReservedAreaRatio = 0.16;
  static const double _lineHeight = 1.2;
  static const int _baseFontWeightIndex = 7;
  static const double _baseStrokeWidth = 0.9;
  static const Duration _maskEmptyStateClearGrace = Duration(milliseconds: 350);
  static const int _maxSchedulingLeadMs = 280;
  static const int _seekResyncThresholdMs = 1500;
  static const int _timelineDriftResyncThresholdMs = 300;
  static const int _pendingQueueMinimumSize = 360;
  static const int _pendingQueueCapacityMultiplier = 12;
  static const int _pendingDrainMinimumBudget = 8;
  static const int _maxPendingDelayMs = 1800;
  static const int _mergeTimeBucketMs = 1000;
  static const int _paintSampleWindowSize = 12;
  static const int _paintSoftThresholdUs = 7000;
  static const int _paintHardThresholdUs = 12000;
  static const int _paintPressureSamples = 6;
  static const int _recoverySamples = 20;
  static const int _schedulerLogIntervalMs = 2000;

  final ValueNotifier<int> _timelineNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _sceneRevision = ValueNotifier<int>(0);
  late final Listenable _painterRepaint = Listenable.merge(<Listenable>[
    _timelineNotifier,
    _sceneRevision,
  ]);
  late final Ticker _ticker = createTicker(_handleTick);

  List<DanmakuComment> _cachedSourceComments = const <DanmakuComment>[];
  List<DanmakuComment> _cachedVisibleComments = const <DanmakuComment>[];
  bool _cachedHideDuplicate = false;
  double _cachedDensity = 1.0;
  int _cachedDuplicateWindowMs = 0;
  List<DanmakuComment> _scheduledComments = const <DanmakuComment>[];
  final Set<String> _emittedCommentIds = <String>{};
  final List<LocalDanmakuItem<DanmakuComment>> _scrollItems =
      <LocalDanmakuItem<DanmakuComment>>[];
  final List<LocalDanmakuItem<DanmakuComment>> _staticItems =
      <LocalDanmakuItem<DanmakuComment>>[];
  final List<_PendingScrollComment> _pendingScrollComments =
      <_PendingScrollComment>[];
  final Set<String> _pendingScrollCommentIds = <String>{};

  double _cachedTrackSnapshotY = -1;
  int _cachedTrackSnapshotScrollCount = -1;
  List<DanmakuScrollTrackItemSnapshot>? _cachedTrackSnapshots;

  DanmakuTrackLayout? _trackLayout;
  int _lastScheduledPositionMs = 0;
  int _lastReportedPositionMs = 0;
  int _timelineMs = 0;
  double _timelineMsAccumulator = 0.0;
  int _lastTickerElapsedUs = 0;
  int? _pendingPauseSyncPositionMs;
  String _lastOptionSignature = '';
  String _lastVisibleWindowSignature = '';
  String _lastViewportSignature = '';
  String _lastTrackLayoutSignature = '';
  String _lastVisualStateSignature = '';
  String _lastTrackMetricsSignature = '';
  String _lastScheduledCommentsSignature = '';
  Size _viewportSize = Size.zero;
  double _devicePixelRatio = 1.0;
  double? _cachedTrackHeightValue;
  ui.Image? _maskImage;
  String? _maskImageKey;
  int _maskLoadGeneration = 0;
  Timer? _maskClearTimer;
  bool _pendingViewportSync = false;
  Size? _pendingViewportSize;
  double? _pendingViewportDevicePixelRatio;
  String? _pendingViewportSignature;
  int _lastSchedulerLogWallClockMs = 0;
  int _schedulerQueuedByCapacityCount = 0;
  int _schedulerQueuedByTrackCount = 0;
  int _schedulerBlockedByCapacityCount = 0;
  int _schedulerBlockedByTrackCount = 0;
  int _schedulerDrainedFromQueueCount = 0;
  int _schedulerDroppedFromQueueCount = 0;
  int _schedulerDroppedByTrimCount = 0;
  int _schedulerMergedCount = 0;
  int _schedulerSampledCount = 0;
  int _schedulerDrainBlockedByTrackCount = 0;
  int _schedulerDrainBlockedBySafetyCount = 0;
  int _lastWindowPendingCount = 0;
  int _lastWindowDrainedCount = 0;
  int _lastWindowBlockedCapacityCount = 0;
  int _queuePressureStreak = 0;
  final List<int> _recentPaintElapsedUs = <int>[];
  _OverloadLevel _overloadLevel = _OverloadLevel.normal;
  int _paintSoftStreak = 0;
  int _paintHardStreak = 0;
  int _recoveryStreak = 0;
  bool _queueHealthyForRecovery = true;
  bool _pendingRuntimeRetune = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
    _lastVisualStateSignature = _buildVisualStateSignature();
    unawaited(_syncMaskImage());
  }

  @override
  void didUpdateWidget(covariant DanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
      _detachEngineState();
    }
    final positionChanged = oldWidget.position != widget.position;
    final pausedChanged = oldWidget.paused != widget.paused;
    final maskChanged =
        _maskStateKey(oldWidget.occlusionState) !=
        _maskStateKey(widget.occlusionState);
    if (maskChanged) {
      unawaited(_syncMaskImage());
    }
    if (oldWidget.deferViewportSync && !widget.deferViewportSync) {
      _flushDeferredViewportMetrics();
    }
    if (positionChanged || pausedChanged) {
      if (widget.paused) {
        final freezePositionMs = pausedChanged
            ? () {
                final stabilizedPositionMs = _stabilizePausedPositionMs();
                return stabilizedPositionMs;
              }()
            : (_timelineMs > 0 ? _timelineMs : widget.position.inMilliseconds);
        _pendingPauseSyncPositionMs = freezePositionMs;
        _lastScheduledPositionMs = math.max(
          _lastScheduledPositionMs,
          freezePositionMs,
        );
        _pauseTicker(positionMs: freezePositionMs);
        return;
      }
      if (pausedChanged) {
        _pendingPauseSyncPositionMs = null;
      }
      _syncEngineState();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _maskLoadGeneration += 1;
    _cancelPendingMaskClear();
    _detachEngineState();
    _disposeMaskImage();
    _ticker.dispose();
    _timelineNotifier.dispose();
    _sceneRevision.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    final visualStateSignature = _buildVisualStateSignature();
    if (!widget.controller.ready || !widget.controller.settings.enabled) {
      _detachEngineState();
      if (visualStateSignature != _lastVisualStateSignature) {
        _lastVisualStateSignature = visualStateSignature;
        setState(() {});
      }
      return;
    }
    _syncEngineState();
    if (visualStateSignature != _lastVisualStateSignature) {
      _lastVisualStateSignature = visualStateSignature;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.controller.settings;
    if (!widget.controller.ready || !settings.enabled) {
      _detachEngineState();
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        _updateViewportMetrics(
          constraints.biggest,
          MediaQuery.devicePixelRatioOf(context),
        );
        return IgnorePointer(
          child: RepaintBoundary(
            child: ClipRect(
              child: CustomPaint(
                painter: LocalDanmakuPainter<DanmakuComment>(
                  repaint: _painterRepaint,
                  scrollItems: _scrollItems,
                  staticItems: _staticItems,
                  timelineListenable: _timelineNotifier,
                  devicePixelRatio: _devicePixelRatio,
                  opacity: settings.opacity.clamp(0.2, 1.0),
                  maskImage: settings.avoidCenterArea ? _maskImage : null,
                  displayAreaRatio: _effectiveAreaRatio(settings),
                  captureAreaRatio: widget.occlusionState.captureAreaRatio,
                  occlusionRect: settings.avoidCenterArea
                      ? widget.occlusionState.normalizedRect
                      : null,
                  occlusionMode: widget.occlusionState.occlusionMode,
                  onPaintElapsedUs: _handlePaintElapsedUs,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        );
      },
    );
  }

  void _updateViewportMetrics(Size size, double devicePixelRatio) {
    if (size.isEmpty) return;
    final signature = _buildViewportSignature(size, devicePixelRatio);
    if (widget.deferViewportSync) {
      if (_pendingViewportSync && signature == _pendingViewportSignature) {
        return;
      }
      _pendingViewportSync = true;
      _pendingViewportSize = size;
      _pendingViewportDevicePixelRatio = devicePixelRatio;
      _pendingViewportSignature = signature;
      return;
    }
    if (_pendingViewportSync &&
        signature == _pendingViewportSignature &&
        _lastViewportSignature != signature) {
      _applyViewportMetrics(
        size: size,
        devicePixelRatio: devicePixelRatio,
        signature: signature,
      );
      _clearDeferredViewportMetrics();
      return;
    }
    if (signature == _lastViewportSignature) return;
    _applyViewportMetrics(
      size: size,
      devicePixelRatio: devicePixelRatio,
      signature: signature,
    );
  }

  void _applyViewportMetrics({
    required Size size,
    required double devicePixelRatio,
    required String signature,
  }) {
    _viewportSize = size;
    _devicePixelRatio = devicePixelRatio;
    _lastViewportSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncEngineState(forceSourceReset: true);
    });
  }

  void _flushDeferredViewportMetrics() {
    if (!_pendingViewportSync) return;
    final size = _pendingViewportSize;
    final devicePixelRatio = _pendingViewportDevicePixelRatio;
    final signature = _pendingViewportSignature;
    _clearDeferredViewportMetrics();
    if (size == null || devicePixelRatio == null || signature == null) {
      return;
    }
    if (signature == _lastViewportSignature) {
      return;
    }
    _applyViewportMetrics(
      size: size,
      devicePixelRatio: devicePixelRatio,
      signature: signature,
    );
  }

  void _clearDeferredViewportMetrics() {
    _pendingViewportSync = false;
    _pendingViewportSize = null;
    _pendingViewportDevicePixelRatio = null;
    _pendingViewportSignature = null;
  }

  void _maybeLogSchedulerState() {
    final wallClockMs = DateTime.now().millisecondsSinceEpoch;
    if (wallClockMs - _lastSchedulerLogWallClockMs < _schedulerLogIntervalMs) {
      return;
    }
    _lastSchedulerLogWallClockMs = wallClockMs;
    if (!widget.controller.ready || !widget.controller.settings.enabled) {
      return;
    }
    final settings = widget.controller.settings;
    _evaluateQueuePressure();
    final tuning = _runtimeTuning(settings);
    debugPrint(
      '[DANMAKU][SCHED] '
      'visible=${_visibleScrollItemCountAt(_timelineMs)} '
      'capacity=${_visibleScrollCapacity(settings)} '
      'active=${_scrollItems.length} '
      'pending=${_pendingScrollComments.length} '
      'timeline=$_timelineMs '
      'scheduled=$_lastScheduledPositionMs '
      'overload=${_overloadLevelLabel()} '
      'effectiveDurationMs=${tuning.effectiveDurationMs} '
      'effectiveDensity=${tuning.effectiveDensity.toStringAsFixed(3)} '
      'effectiveAreaRatio=${tuning.effectiveAreaRatio.toStringAsFixed(3)} '
      'queuedCapacity=$_schedulerQueuedByCapacityCount '
      'queuedTrack=$_schedulerQueuedByTrackCount '
      'blockedCapacity=$_schedulerBlockedByCapacityCount '
      'blockedTrack=$_schedulerBlockedByTrackCount '
      'drained=$_schedulerDrainedFromQueueCount '
      'dropped=$_schedulerDroppedFromQueueCount '
      'droppedTrim=$_schedulerDroppedByTrimCount '
      'merged=$_schedulerMergedCount '
      'sampled=$_schedulerSampledCount '
      'drainBlockedByTrack=$_schedulerDrainBlockedByTrackCount '
      'drainBlockedBySafety=$_schedulerDrainBlockedBySafetyCount',
    );
  }

  void _handleTick(Duration elapsed) {
    final elapsedUs = elapsed.inMicroseconds;
    if (_lastTickerElapsedUs == 0) {
      _lastTickerElapsedUs = elapsedUs;
    } else {
      final deltaUs = elapsedUs - _lastTickerElapsedUs;
      _lastTickerElapsedUs = elapsedUs;
      if (deltaUs > 0) {
        final scaledDeltaMs =
            deltaUs *
                    _effectivePlaybackSpeedFactor() /
                    Duration.microsecondsPerMillisecond;
        if (scaledDeltaMs > 0) {
          _timelineMsAccumulator += scaledDeltaMs;
          final newTimelineMs = _timelineMsAccumulator.floor();
          if (newTimelineMs != _timelineMs) {
            _timelineMs = newTimelineMs;
          }
        }
      }
    }
    if (_timelineNotifier.value != _timelineMs) {
      _timelineNotifier.value = _timelineMs;
    }
    _correctTimelineDrift();
    var sceneChanged = false;
    if (_purgeExpiredItems()) {
      sceneChanged = true;
    }
    if (widget.controller.ready &&
        widget.controller.settings.enabled &&
        !_viewportSize.isEmpty) {
      final reportedPositionMs = _resolvedPositionMs();
      final schedulingTargetMs = _resolveSchedulingPositionMs(
        reportedPositionMs,
      );
      final emittedCount = _advanceSchedulingToPosition(
        widget.controller.settings,
        schedulingTargetMs,
      );
      if (emittedCount > 0) {
        sceneChanged = true;
      }
    }
    if (sceneChanged && (_scrollItems.isNotEmpty || _staticItems.isNotEmpty)) {
      _bumpScene();
    }
    _maybeLogSchedulerState();
    if (_scrollItems.isEmpty &&
        _staticItems.isEmpty &&
        _pendingScrollComments.isEmpty &&
        !_hasFutureScheduledComments() &&
        _ticker.isActive) {
      _pauseTicker();
    }
  }

  void _startTickerIfNeeded() {
    if (widget.paused) {
      _pauseTicker();
      return;
    }
    if (_scrollItems.isEmpty &&
        _staticItems.isEmpty &&
        _pendingScrollComments.isEmpty &&
        !_hasFutureScheduledComments()) {
      return;
    }
    if (_ticker.isActive) return;
    _lastTickerElapsedUs = 0;
    _ticker.start();
  }

  void _pauseTicker({int? positionMs}) {
    if (_ticker.isActive) {
      _ticker.stop();
    }
    _lastTickerElapsedUs = 0;
    _setTimelineMs(
      positionMs ??
          (_timelineMs > 0 ? _timelineMs : widget.position.inMilliseconds),
    );
  }

  void _setTimelineMs(int positionMs) {
    _timelineMs = math.max(0, positionMs);
    _timelineMsAccumulator = _timelineMs.toDouble();
    if (_timelineNotifier.value != _timelineMs) {
      _timelineNotifier.value = _timelineMs;
    }
  }

  void _correctTimelineDrift() {
    if (widget.paused || !widget.controller.ready) return;
    final reportedMs = _resolvedPositionMs();
    final driftMs = (_timelineMs - reportedMs).abs();
    if (driftMs >= _timelineDriftResyncThresholdMs) {
      _setTimelineMs(reportedMs);
    }
  }

  void _syncEngineState({bool forceSourceReset = false}) {
    try {
      final settings = widget.controller.settings;
      final currentPositionMs = _resolvedPositionMs();
      final schedulingPositionMs = _resolveSchedulingPositionMs(
        currentPositionMs,
      );
      if (!widget.controller.ready ||
          !settings.enabled ||
          _viewportSize.isEmpty) {
        _syncTickerForPlaybackState(positionMs: currentPositionMs);
        return;
      }

      final comments = _resolveVisibleComments(
        widget.controller.comments,
        settings: settings,
      );
      final optionSignature = _buildOptionSignature(
        settings,
        visibleCommentCount: comments.length,
      );
      final visibleWindowSignature = _buildVisibleWindowSignature(settings);

      final commentsSignature = _buildCommentsSignature(comments);
      final sourceChanged =
          forceSourceReset ||
          commentsSignature != _lastScheduledCommentsSignature;
      final visibleWindowChanged =
          visibleWindowSignature != _lastVisibleWindowSignature;
      final optionChanged = optionSignature != _lastOptionSignature;
      _lastOptionSignature = optionSignature;

      if (sourceChanged || visibleWindowChanged || optionChanged) {
        _scheduledComments = comments;
        _lastScheduledCommentsSignature = commentsSignature;
        _lastVisibleWindowSignature = visibleWindowSignature;
        if (sourceChanged &&
            !forceSourceReset &&
            _canPreserveSceneOnSourceRefresh(currentPositionMs)) {
          debugPrint(
            '[DANMAKU][SOURCE_REFRESH] preserveScene=true '
            'position=$currentPositionMs '
            'activeScroll=${_scrollItems.length} '
            'pending=${_pendingScrollComments.length} '
            'scheduled=$_lastScheduledPositionMs '
            'comments=${comments.length}',
          );
          _lastReportedPositionMs = currentPositionMs;
          _syncTickerForPlaybackState(positionMs: currentPositionMs);
          return;
        }
        _resyncVisibleWindow(
          comments,
          settings,
          schedulingPositionMs,
          reason: sourceChanged ? 'source' : 'settings',
        );
        _lastReportedPositionMs = currentPositionMs;
        return;
      }

      final previousPositionMs = _lastScheduledPositionMs;
      final previousReportedPositionMs = _lastReportedPositionMs;

      if (currentPositionMs <
          previousReportedPositionMs - _seekResyncThresholdMs) {
        _resyncVisibleWindow(
          comments,
          settings,
          currentPositionMs,
          reason: 'seek_back',
        );
        _lastReportedPositionMs = currentPositionMs;
        return;
      }

      if (currentPositionMs >
          previousReportedPositionMs + _seekResyncThresholdMs) {
        _resyncVisibleWindow(
          comments,
          settings,
          currentPositionMs,
          reason: 'seek_forward',
        );
        _lastReportedPositionMs = currentPositionMs;
        return;
      }

      if (currentPositionMs <= previousPositionMs) {
        _lastReportedPositionMs = currentPositionMs;
        _syncTickerForPlaybackState(positionMs: currentPositionMs);
        return;
      }

      final timelineDriftMs = (_timelineMs - currentPositionMs).abs();
      if (timelineDriftMs >= _timelineDriftResyncThresholdMs) {
        _setTimelineMs(currentPositionMs);
      }

      final emittedCount = _advanceSchedulingToPosition(
        settings,
        schedulingPositionMs,
      );
      if (emittedCount > 0) {
        _bumpScene();
      }
      _lastReportedPositionMs = currentPositionMs;
      _syncTickerForPlaybackState(positionMs: currentPositionMs);
    } finally {
      _pendingPauseSyncPositionMs = null;
    }
  }

  bool _canPreserveSceneOnSourceRefresh(int currentPositionMs) {
    if (_scrollItems.isEmpty && _pendingScrollComments.isEmpty) {
      return false;
    }
    if (currentPositionMs <= 0 || _lastReportedPositionMs <= 0) {
      return false;
    }
    final driftMs = (currentPositionMs - _lastReportedPositionMs).abs();
    return driftMs <= _seekResyncThresholdMs;
  }

  void _resyncVisibleWindow(
    List<DanmakuComment> comments,
    DanmakuSettings settings,
    int currentPositionMs, {
    required String reason,
  }) {
    debugPrint(
      '[DANMAKU][RESYNC] reason=$reason '
      'position=$currentPositionMs '
      'scheduled=$_lastScheduledPositionMs '
      'comments=${comments.length} '
      'activeScroll=${_scrollItems.length} '
      'pending=${_pendingScrollComments.length} '
      'timeline=$_timelineMs',
    );
    _resetEngineTimeline(clearScreen: true);
    _setTimelineMs(currentPositionMs);
    final startMs = math.max(0, currentPositionMs - _activeWindowMs(settings));
    _emitCommentsInRange(
      comments,
      settings,
      startMs: startMs,
      endMs: currentPositionMs,
      currentPositionMs: currentPositionMs,
    );
    _lastScheduledPositionMs = currentPositionMs;
    _lastReportedPositionMs = currentPositionMs;
    _bumpScene();
    _syncTickerForPlaybackState();
  }

  void _resetEngineTimeline({required bool clearScreen}) {
    if (clearScreen) {
      _clearActiveItems(notify: false);
      _clearPendingScrollComments();
    }
    _emittedCommentIds.clear();
  }

  void _detachEngineState() {
    _pauseTicker();
    _clearActiveItems(notify: false);
    _cachedSourceComments = const <DanmakuComment>[];
    _cachedVisibleComments = const <DanmakuComment>[];
    _scheduledComments = const <DanmakuComment>[];
    _lastScheduledCommentsSignature = '';
    _emittedCommentIds.clear();
    _clearPendingScrollComments();
    _trackLayout = null;
    _lastScheduledPositionMs = 0;
    _lastReportedPositionMs = 0;
    _timelineMs = 0;
    _lastTickerElapsedUs = 0;
    _lastOptionSignature = '';
    _lastVisibleWindowSignature = '';
    _lastTrackLayoutSignature = '';
    _resetOverloadState();
    _setTimelineMs(0);
    _pendingPauseSyncPositionMs = null;
    _bumpScene();
  }

  String _maskStateKey(DanmakuDynamicOcclusionState state) {
    if (!state.hasUsableMask) {
      return '';
    }
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
        if (mounted) {
          setState(() {});
        }
      }
      return;
    }
    _cancelPendingMaskClear();
    if (_maskImageKey == nextKey && _maskImage != null) {
      return;
    }
    final generation = ++_maskLoadGeneration;
    final path = widget.occlusionState.maskPath;
    if (path == null || path.trim().isEmpty) {
      _maskLoadGeneration += 1;
      _disposeMaskImage();
      if (mounted) {
        setState(() {});
      }
      return;
    }
    final file = File(path);
    if (!await file.exists()) {
      _maskLoadGeneration += 1;
      if (_maskImage != null || _maskImageKey != null) {
        _disposeMaskImage();
        if (mounted) {
          setState(() {});
        }
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
      if (!mounted || generation != _maskLoadGeneration) {
        return;
      }
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
    if (_maskImage == null || _maskImageKey == null) {
      return false;
    }
    if (!widget.occlusionState.enabled) {
      return false;
    }
    return widget.occlusionState.backend.trim().toLowerCase() != 'disabled';
  }

  void _scheduleDeferredMaskClear() {
    if (_maskClearTimer != null) {
      return;
    }
    final generation = ++_maskLoadGeneration;
    _maskClearTimer = Timer(_maskEmptyStateClearGrace, () {
      _maskClearTimer = null;
      if (!mounted || generation != _maskLoadGeneration) {
        return;
      }
      if (_maskStateKey(widget.occlusionState).isNotEmpty) {
        return;
      }
      if (_maskImage == null && _maskImageKey == null) {
        return;
      }
      _disposeMaskImage();
      setState(() {});
    });
  }

  void _cancelPendingMaskClear() {
    _maskClearTimer?.cancel();
    _maskClearTimer = null;
  }

  void _clearPendingScrollComments() {
    _pendingScrollComments.clear();
    _pendingScrollCommentIds.clear();
  }

  void _resetOverloadState() {
    _recentPaintElapsedUs.clear();
    _overloadLevel = _OverloadLevel.normal;
    _paintSoftStreak = 0;
    _paintHardStreak = 0;
    _recoveryStreak = 0;
    _queuePressureStreak = 0;
    _queueHealthyForRecovery = true;
    _lastWindowPendingCount = 0;
    _lastWindowDrainedCount = 0;
    _lastWindowBlockedCapacityCount = 0;
    _schedulerQueuedByCapacityCount = 0;
    _schedulerQueuedByTrackCount = 0;
    _schedulerBlockedByCapacityCount = 0;
    _schedulerBlockedByTrackCount = 0;
    _schedulerDrainedFromQueueCount = 0;
    _schedulerDroppedFromQueueCount = 0;
    _schedulerDroppedByTrimCount = 0;
    _schedulerMergedCount = 0;
    _schedulerSampledCount = 0;
    _schedulerDrainBlockedByTrackCount = 0;
    _schedulerDrainBlockedBySafetyCount = 0;
  }

  void _clearActiveItems({required bool notify}) {
    for (final item in _scrollItems) {
      item.dispose();
    }
    for (final item in _staticItems) {
      item.dispose();
    }
    _scrollItems.clear();
    _staticItems.clear();
    if (notify) {
      _bumpScene();
    }
  }

  bool _purgeExpiredItems() {
    var changed = false;
    final viewportSize = _viewportSize;
    for (var i = _scrollItems.length - 1; i >= 0; i--) {
      if (_scrollItems[i].isExpired(_timelineMs, viewportSize)) {
        _scrollItems[i].dispose();
        _scrollItems.removeAt(i);
        changed = true;
      }
    }
    for (var i = _staticItems.length - 1; i >= 0; i--) {
      if (_staticItems[i].isExpired(_timelineMs, viewportSize)) {
        _staticItems[i].dispose();
        _staticItems.removeAt(i);
        changed = true;
      }
    }
    if (changed) {
      _cachedTrackSnapshotY = -1;
    }
    return changed;
  }

  void _bumpScene() {
    _sceneRevision.value = _sceneRevision.value + 1;
  }

  void _syncTickerForPlaybackState({int? positionMs}) {
    if (widget.paused) {
      _pauseTicker(positionMs: positionMs);
      return;
    }
    _startTickerIfNeeded();
  }

  int _resolvedPositionMs() {
    return _pendingPauseSyncPositionMs ?? widget.position.inMilliseconds;
  }

  int _resolveSchedulingPositionMs(int reportedPositionMs) {
    if (widget.paused || _timelineMs <= 0) {
      return reportedPositionMs;
    }
    return math.min(reportedPositionMs, _timelineMs + _maxSchedulingLeadMs);
  }

  bool _hasFutureScheduledComments() {
    final comments = _scheduledComments;
    if (comments.isEmpty) {
      return false;
    }
    return _upperBound(comments, _lastScheduledPositionMs) < comments.length;
  }

  int _stabilizePausedPositionMs() {
    final renderedTimelineMs = _timelineMs;
    if ((_ticker.isActive ||
            _scrollItems.isNotEmpty ||
            _staticItems.isNotEmpty) &&
        renderedTimelineMs > 0) {
      return renderedTimelineMs;
    }
    return math.max(widget.position.inMilliseconds, _lastScheduledPositionMs);
  }

  double _effectivePlaybackSpeedFactor() {
    return widget.playbackSpeedFactor.clamp(0.25, 4.0).toDouble();
  }

  _DanmakuRuntimeTuning _runtimeTuning(DanmakuSettings settings) {
    final baseAreaRatio = settings.displayAreaRatio.clamp(0.1, 1.0).toDouble();
    final baseDensity = settings.density.clamp(0.2, 1.0).toDouble();
    final baseDurationMs = _baseScrollDurationMs(settings);
    return switch (_overloadLevel) {
      _OverloadLevel.normal => _DanmakuRuntimeTuning(
        overloadLevel: _overloadLevel,
        effectiveDurationMs: baseDurationMs,
        effectiveDensity: baseDensity,
        effectiveAreaRatio: baseAreaRatio,
      ),
      _OverloadLevel.soft => _DanmakuRuntimeTuning(
        overloadLevel: _overloadLevel,
        effectiveDurationMs: math.max(2400, (baseDurationMs * 0.88).round()),
        effectiveDensity: (baseDensity * 0.92).clamp(0.2, 1.0).toDouble(),
        effectiveAreaRatio: (baseAreaRatio + 0.10).clamp(0.1, 0.75).toDouble(),
      ),
      _OverloadLevel.hard => _DanmakuRuntimeTuning(
        overloadLevel: _overloadLevel,
        effectiveDurationMs: math.max(2200, (baseDurationMs * 0.75).round()),
        effectiveDensity: (baseDensity * 0.82).clamp(0.2, 1.0).toDouble(),
        effectiveAreaRatio: (baseAreaRatio + 0.20).clamp(0.1, 0.85).toDouble(),
      ),
    };
  }

  String _overloadLevelLabel() {
    return switch (_overloadLevel) {
      _OverloadLevel.normal => 'normal',
      _OverloadLevel.soft => 'soft',
      _OverloadLevel.hard => 'hard',
    };
  }

  void _handlePaintElapsedUs(int elapsedUs) {
    _recentPaintElapsedUs.add(elapsedUs);
    if (_recentPaintElapsedUs.length > _paintSampleWindowSize) {
      _recentPaintElapsedUs.removeAt(0);
    }
    final averagePaintUs = _averagePaintElapsedUs();
    if (averagePaintUs >= _paintHardThresholdUs) {
      _paintHardStreak += 1;
      _paintSoftStreak += 1;
      _recoveryStreak = 0;
      if (_paintHardStreak >= _paintPressureSamples) {
        _setOverloadLevel(_OverloadLevel.hard);
      }
      return;
    }
    if (averagePaintUs >= _paintSoftThresholdUs) {
      _paintSoftStreak += 1;
      _paintHardStreak = 0;
      _recoveryStreak = 0;
      if (_paintSoftStreak >= _paintPressureSamples &&
          _overloadLevel == _OverloadLevel.normal) {
        _setOverloadLevel(_OverloadLevel.soft);
      }
      return;
    }
    _paintSoftStreak = 0;
    _paintHardStreak = 0;
    if (_queueHealthyForRecovery) {
      _recoveryStreak += 1;
      if (_recoveryStreak >= _recoverySamples) {
        if (_overloadLevel == _OverloadLevel.hard) {
          _setOverloadLevel(_OverloadLevel.soft);
        } else if (_overloadLevel == _OverloadLevel.soft) {
          _setOverloadLevel(_OverloadLevel.normal);
        }
        _recoveryStreak = 0;
      }
    } else {
      _recoveryStreak = 0;
    }
  }

  double _averagePaintElapsedUs() {
    if (_recentPaintElapsedUs.isEmpty) {
      return 0;
    }
    var total = 0;
    for (final sample in _recentPaintElapsedUs) {
      total += sample;
    }
    return total / _recentPaintElapsedUs.length;
  }

  void _setOverloadLevel(_OverloadLevel nextLevel) {
    if (_overloadLevel == nextLevel) {
      return;
    }
    _overloadLevel = nextLevel;
    _scheduleRuntimeRetune();
  }

  void _scheduleRuntimeRetune() {
    if (_pendingRuntimeRetune) {
      return;
    }
    _pendingRuntimeRetune = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingRuntimeRetune = false;
      if (!mounted) {
        return;
      }
      _trackLayout = null;
      _lastTrackLayoutSignature = '';
      _cachedTrackHeightValue = null;
      if (_ticker.isActive ||
          _scrollItems.isNotEmpty ||
          _staticItems.isNotEmpty) {
        _bumpScene();
      }
      setState(() {});
    });
  }

  void _evaluateQueuePressure() {
    final pendingDelta =
        _pendingScrollComments.length - _lastWindowPendingCount;
    final drainedDelta =
        _schedulerDrainedFromQueueCount - _lastWindowDrainedCount;
    final blockedCapacityDelta =
        _schedulerBlockedByCapacityCount - _lastWindowBlockedCapacityCount;
    final backlogGrowing = pendingDelta > 0 && drainedDelta == 0;
    final stalledOnCapacity = blockedCapacityDelta > 0 && drainedDelta == 0;
    _queueHealthyForRecovery =
        _pendingScrollComments.isEmpty ||
        drainedDelta > 0 ||
        pendingDelta <= 0 ||
        blockedCapacityDelta == 0;
    if (backlogGrowing || stalledOnCapacity) {
      _queuePressureStreak += 1;
      _recoveryStreak = 0;
      if (_queuePressureStreak >= 2) {
        if (_overloadLevel == _OverloadLevel.normal) {
          _setOverloadLevel(_OverloadLevel.soft);
        } else if (_overloadLevel == _OverloadLevel.soft) {
          _setOverloadLevel(_OverloadLevel.hard);
        }
        _queuePressureStreak = 0;
      }
    } else {
      _queuePressureStreak = 0;
    }
    _lastWindowPendingCount = _pendingScrollComments.length;
    _lastWindowDrainedCount = _schedulerDrainedFromQueueCount;
    _lastWindowBlockedCapacityCount = _schedulerBlockedByCapacityCount;
  }

  int _visibleScrollCapacity(DanmakuSettings settings) {
    final trackCount = _resolveTrackLayout(settings)?.topTrackYs.length ?? 0;
    if (trackCount <= 0) {
      return _minVisibleScrollItems;
    }
    final density = _runtimeTuning(settings).effectiveDensity;
    final scaledMultiplier = _perTrackVisibleScrollMultiplier * density;
    final dynamicMinimum = math.max(_minVisibleScrollItems, trackCount * 2);
    return math.max(
      dynamicMinimum,
      math.min(_maxVisibleScrollItems, (trackCount * scaledMultiplier).round()),
    );
  }

  int _visibleScrollLimit(
    DanmakuSettings settings, {
    required bool fromPending,
  }) {
    final baseCapacity = _visibleScrollCapacity(settings);
    if (!fromPending) {
      return baseCapacity;
    }
    return _pendingVisibleSafetyLimit(settings);
  }

  int _pendingVisibleSafetyLimit(DanmakuSettings settings) {
    final baseCapacity = _visibleScrollCapacity(settings);
    return math.max(
      _maxVisibleScrollItems,
      math.min(_maxPendingVisibleScrollItems, baseCapacity * 3),
    );
  }

  int _visibleScrollItemCountAt(int timelineMs) {
    final viewportSize = _viewportSize;
    if (viewportSize.isEmpty) {
      return 0;
    }
    var count = 0;
    for (final item in _scrollItems) {
      if (item.isExpired(timelineMs, viewportSize)) {
        continue;
      }
      final x = item.xFor(viewportSize, timelineMs);
      if (x < viewportSize.width && x + item.width > 0) {
        count += 1;
      }
    }
    return count;
  }

  int _visibleScrollItemCountOnTrack(
    double trackY,
    int timelineMs,
    Size viewportSize,
  ) {
    var count = 0;
    for (final item in _scrollItems) {
      if (item.trackPosition != trackY) {
        continue;
      }
      if (item.isExpired(timelineMs, viewportSize)) {
        continue;
      }
      final x = item.xFor(viewportSize, timelineMs);
      if (x < viewportSize.width && x + item.width > 0) {
        count += 1;
      }
    }
    return count;
  }

  int _maxVisibleScrollItemsPerTrack(
    DanmakuSettings settings, {
    required bool fromPending,
  }) {
    final trackCount = _resolveTrackLayout(settings)?.topTrackYs.length ?? 0;
    if (trackCount <= 0) {
      return 3;
    }
    final basePerTrack = math.max(
      3,
      (_visibleScrollCapacity(settings) / trackCount).ceil(),
    );
    if (!fromPending) {
      return math.min(4, basePerTrack);
    }
    final pendingHeadroom = switch (_overloadLevel) {
      _OverloadLevel.normal => 0,
      _OverloadLevel.soft => 1,
      _OverloadLevel.hard => 2,
    };
    return math.min(6, basePerTrack + pendingHeadroom);
  }

  int _pendingDrainBudget(DanmakuSettings settings) {
    return math.max(
      _pendingDrainMinimumBudget,
      _visibleScrollCapacity(settings) ~/ 3,
    );
  }

  int _pendingDelayBudgetMs(DanmakuSettings settings) {
    final durationBasedBudget = (_scrollDurationMs(settings) * 2.5).round();
    return math.max(_maxPendingDelayMs, durationBasedBudget);
  }

  int _maxPendingScrollCount(DanmakuSettings settings) {
    return math.max(
      _visibleScrollCapacity(settings) * _pendingQueueCapacityMultiplier,
      _pendingQueueMinimumSize,
    );
  }

  String _normalizedMergeKey(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  int _pendingTimeBucket(int timeMs) {
    return timeMs ~/ _mergeTimeBucketMs;
  }

  bool _mergePendingScrollComment(DanmakuComment comment, {int? skipIndex}) {
    if (_overloadLevel == _OverloadLevel.normal) {
      return false;
    }
    final normalizedText = _normalizedMergeKey(comment.text);
    if (normalizedText.isEmpty) {
      return false;
    }
    final bucket = _pendingTimeBucket(comment.timeMs);
    for (var i = _pendingScrollComments.length - 1; i >= 0; i -= 1) {
      if (skipIndex != null && i == skipIndex) {
        continue;
      }
      final pending = _pendingScrollComments[i];
      if (pending.normalizedText != normalizedText ||
          pending.timeBucket != bucket) {
        continue;
      }
      pending.mergeWith();
      _schedulerMergedCount += 1;
      _emittedCommentIds.add(comment.id);
      return true;
    }
    return false;
  }

  bool _queuePendingScrollComment(
    DanmakuComment comment,
    DanmakuSettings settings,
    int currentPositionMs,
  ) {
    if (_pendingScrollCommentIds.contains(comment.id) ||
        _emittedCommentIds.contains(comment.id)) {
      return false;
    }
    if (_mergePendingScrollComment(comment)) {
      return true;
    }
    final normalizedText = _normalizedMergeKey(comment.text);
    _pendingScrollCommentIds.add(comment.id);
    _pendingScrollComments.add(
      _PendingScrollComment(
        comment: comment,
        eligibleAtMs: currentPositionMs,
        enqueuedAtMs: currentPositionMs,
        delayBudgetMs: _pendingDelayBudgetMs(settings),
        normalizedText: normalizedText,
        timeBucket: _pendingTimeBucket(comment.timeMs),
      ),
    );
    _trimPendingScrollQueue(settings);
    return true;
  }

  void _trimPendingScrollQueue(DanmakuSettings settings) {
    final maxPendingCount = _maxPendingScrollCount(settings);
    while (_pendingScrollComments.length > maxPendingCount) {
      final trimIndex = _pickPendingTrimIndex(settings);
      _dropPendingScrollCommentAt(trimIndex, markEmitted: true, reason: 'trim');
    }
  }

  int _pickPendingTrimIndex(DanmakuSettings settings) {
    if (_pendingScrollComments.isEmpty) {
      return -1;
    }
    final timelineMs = math.max(_timelineMs, _lastScheduledPositionMs);
    for (var index = 0; index < _pendingScrollComments.length; index += 1) {
      final pending = _pendingScrollComments[index];
      final queuedDurationMs = timelineMs - pending.enqueuedAtMs;
      if (queuedDurationMs >= pending.delayBudgetMs) {
        return index;
      }
      final missedVisibleWindow =
          timelineMs - pending.comment.timeMs >= _scrollDurationMs(settings);
      if (missedVisibleWindow) {
        return index;
      }
    }
    return 0;
  }

  void _dropPendingScrollCommentAt(
    int index, {
    required bool markEmitted,
    required String reason,
  }) {
    if (index < 0 || index >= _pendingScrollComments.length) {
      return;
    }
    final pending = _pendingScrollComments.removeAt(index);
    _pendingScrollCommentIds.remove(pending.comment.id);
    _schedulerDroppedFromQueueCount += 1;
    if (reason == 'trim') {
      _schedulerDroppedByTrimCount += 1;
    }
    if (markEmitted) {
      _emittedCommentIds.add(pending.comment.id);
    }
  }

  int _drainPendingScrollComments(
    DanmakuSettings settings,
    int currentPositionMs,
  ) {
    if (_pendingScrollComments.isEmpty || !settings.scrollEnabled) {
      return 0;
    }
    final successBudget = _pendingDrainBudget(settings);
    final scanBudget = math.max(successBudget * 4, 24);
    var admittedCount = 0;
    var scannedCount = 0;
    var index = 0;
    while (index < _pendingScrollComments.length && scannedCount < scanBudget) {
      final pending = _pendingScrollComments[index];
      if (currentPositionMs < pending.eligibleAtMs) {
        break;
      }
      scannedCount += 1;
      final result = _tryAdmitComment(
        pending.comment,
        settings,
        currentPositionMs,
        queueOnBlocked: false,
        fromPending: true,
        textOverride: pending.displayText,
      );
      switch (result) {
        case _CommentAdmissionResult.admitted:
          _pendingScrollCommentIds.remove(pending.comment.id);
          _pendingScrollComments.removeAt(index);
          admittedCount += 1;
          _schedulerDrainedFromQueueCount += 1;
          if (admittedCount >= successBudget) {
            return admittedCount;
          }
          continue;
        case _CommentAdmissionResult.dropped:
        case _CommentAdmissionResult.skipped:
          _pendingScrollCommentIds.remove(pending.comment.id);
          _pendingScrollComments.removeAt(index);
          continue;
        case _CommentAdmissionResult.blocked:
        case _CommentAdmissionResult.queued:
          index += 1;
          continue;
      }
    }
    return admittedCount;
  }

  int _emitCommentsInRange(
    List<DanmakuComment> comments,
    DanmakuSettings settings, {
    required int startMs,
    required int endMs,
    required int currentPositionMs,
  }) {
    if (comments.isEmpty || endMs < startMs) {
      return 0;
    }
    final startIndex = _lowerBound(comments, startMs);
    final endIndex = _upperBound(comments, endMs);
    var emittedCount = 0;
    for (var i = startIndex; i < endIndex; i += 1) {
      if (_enqueueComment(comments[i], settings, currentPositionMs)) {
        emittedCount += 1;
      }
    }
    return emittedCount;
  }

  int _advanceSchedulingToPosition(
    DanmakuSettings settings,
    int currentPositionMs,
  ) {
    var emittedCount = _drainPendingScrollComments(settings, currentPositionMs);
    if (_scheduledComments.isEmpty ||
        currentPositionMs <= _lastScheduledPositionMs) {
      return emittedCount;
    }
    final startIndex = _upperBound(
      _scheduledComments,
      _lastScheduledPositionMs,
    );
    final endIndex = _upperBound(_scheduledComments, currentPositionMs);
    for (var i = startIndex; i < endIndex; i += 1) {
      if (_enqueueComment(_scheduledComments[i], settings, currentPositionMs)) {
        emittedCount += 1;
      }
    }
    _lastScheduledPositionMs = currentPositionMs;
    return emittedCount;
  }

  bool _enqueueComment(
    DanmakuComment comment,
    DanmakuSettings settings,
    int currentPositionMs,
  ) {
    final result = _tryAdmitComment(
      comment,
      settings,
      currentPositionMs,
      queueOnBlocked: true,
      fromPending: false,
      textOverride: null,
    );
    return result == _CommentAdmissionResult.admitted;
  }

  _CommentAdmissionResult _tryAdmitComment(
    DanmakuComment comment,
    DanmakuSettings settings,
    int currentPositionMs, {
    required bool queueOnBlocked,
    required bool fromPending,
    required String? textOverride,
  }) {
    if (!_isCommentTypeEnabled(comment, settings)) {
      return _CommentAdmissionResult.skipped;
    }
    if (_emittedCommentIds.contains(comment.id)) {
      return _CommentAdmissionResult.skipped;
    }
    if (!fromPending && _pendingScrollCommentIds.contains(comment.id)) {
      return _CommentAdmissionResult.queued;
    }
    final layout = _resolveTrackLayout(settings);
    if (layout == null) {
      return _CommentAdmissionResult.blocked;
    }

    final itemType = _mapItemType(comment.type);
    final durationMs = itemType == LocalDanmakuItemType.scroll
        ? _scrollDurationMs(settings)
        : _staticDurationMs(settings);
    final ageMs = fromPending && itemType == LocalDanmakuItemType.scroll
        ? 0
        : math.max(0, currentPositionMs - comment.timeMs);
    if (ageMs >= durationMs) {
      if (itemType == LocalDanmakuItemType.scroll) {
        _emittedCommentIds.add(comment.id);
      }
      return _CommentAdmissionResult.dropped;
    }
    final visibleScrollCount = _visibleScrollItemCountAt(_timelineMs);
    final visibleScrollLimit = _visibleScrollLimit(
      settings,
      fromPending: fromPending,
    );
    if (itemType == LocalDanmakuItemType.scroll &&
        !fromPending &&
        visibleScrollCount >= visibleScrollLimit) {
      if (queueOnBlocked &&
          _queuePendingScrollComment(comment, settings, currentPositionMs)) {
        _schedulerQueuedByCapacityCount += 1;
        return _CommentAdmissionResult.queued;
      }
      _schedulerBlockedByCapacityCount += 1;
      return _CommentAdmissionResult.blocked;
    }
    final rawStartMs = _timelineMs - ageMs;
    final effectiveStartMs = fromPending
        ? rawStartMs
        : math.max(comment.timeMs, rawStartMs);
    final color = settings.colorEnabled ? comment.color : Colors.white;
    final item = LocalDanmakuItem.rasterize<DanmakuComment>(
      content: LocalDanmakuContentItem<DanmakuComment>(
        textOverride ?? comment.text,
        color: color,
        type: itemType,
        extra: comment,
      ),
      trackPosition: 0,
      startMs: effectiveStartMs,
      durationMs: durationMs,
      fontSize: _fontSize(settings),
      fontWeight: _fontWeightIndex(settings),
      strokeWidth: _strokeWidth(settings),
      lineHeight: _lineHeight,
      devicePixelRatio: _devicePixelRatio,
    );

    final trackPosition = _pickTrackPosition(
      layout,
      item,
      settings: settings,
      fromPending: fromPending,
      allowOverlap: false,
      overlapSeed: comment.id,
    );
    if (trackPosition == null) {
      item.dispose();
      if (itemType == LocalDanmakuItemType.scroll &&
          queueOnBlocked &&
          _queuePendingScrollComment(comment, settings, currentPositionMs)) {
        _schedulerQueuedByTrackCount += 1;
        return _CommentAdmissionResult.queued;
      }
      if (itemType == LocalDanmakuItemType.scroll) {
        _schedulerBlockedByTrackCount += 1;
        if (fromPending) {
          _schedulerDrainBlockedByTrackCount += 1;
        }
      }
      return _CommentAdmissionResult.blocked;
    }
    if (itemType == LocalDanmakuItemType.scroll &&
        fromPending &&
        visibleScrollCount >= _pendingVisibleSafetyLimit(settings)) {
      item.dispose();
      _schedulerBlockedByCapacityCount += 1;
      _schedulerDrainBlockedBySafetyCount += 1;
      return _CommentAdmissionResult.blocked;
    }

    _emittedCommentIds.add(comment.id);
    item.trackPosition = trackPosition;
    if (item.isScroll) {
      _scrollItems.add(item);
      _cachedTrackSnapshotY = -1;
    } else {
      _staticItems.add(item);
    }
    return _CommentAdmissionResult.admitted;
  }

  double? _pickTrackPosition(
    DanmakuTrackLayout layout,
    LocalDanmakuItem<DanmakuComment> item, {
    required DanmakuSettings settings,
    required bool fromPending,
    required bool allowOverlap,
    required String overlapSeed,
  }) {
    final viewportSize = _viewportSize;
    switch (item.content.type) {
      case LocalDanmakuItemType.scroll:
        final trackY = _findTrack(
          layout.topTrackYs,
          seed: overlapSeed,
          canUse: (track) => _scrollCanAddToTrack(
            track,
            item.width,
            viewportSize,
            settings: settings,
            fromPending: fromPending,
          ),
        );
        if (trackY != null) {
          return trackY;
        }
        if (allowOverlap && layout.topTrackYs.isNotEmpty) {
          return _fallbackTrack(layout.topTrackYs, overlapSeed);
        }
        return null;
      case LocalDanmakuItemType.top:
        return _findTrack(
          layout.topTrackYs,
          seed: overlapSeed,
          canUse: (track) =>
              _staticCanAddToTrack(track, LocalDanmakuItemType.top),
        );
      case LocalDanmakuItemType.bottom:
        return _findTrack(
          layout.bottomTrackOffsets,
          seed: overlapSeed,
          canUse: (track) =>
              _staticCanAddToTrack(track, LocalDanmakuItemType.bottom),
        );
    }
  }

  double? _findTrack(
    List<double> tracks, {
    required String seed,
    required bool Function(double track) canUse,
  }) {
    if (tracks.isEmpty) {
      return null;
    }
    final startIndex = _seedTrackIndex(seed, tracks.length);
    for (var offset = 0; offset < tracks.length; offset += 1) {
      final track = tracks[(startIndex + offset) % tracks.length];
      if (canUse(track)) {
        return track;
      }
    }
    return null;
  }

  int _seedTrackIndex(String seed, int length) {
    if (length <= 1) {
      return 0;
    }
    var hash = 0;
    for (var i = 0; i < seed.length; i += 1) {
      hash = ((hash * 33) ^ seed.codeUnitAt(i)) & 0x7fffffff;
    }
    return hash % length;
  }

  bool _scrollCanAddToTrack(
    double trackY,
    double newItemWidth,
    Size viewportSize, {
    required DanmakuSettings settings,
    required bool fromPending,
  }) {
    final visibleOnTrack = _visibleScrollItemCountOnTrack(
      trackY,
      _timelineMs,
      viewportSize,
    );
    if (visibleOnTrack >=
        _maxVisibleScrollItemsPerTrack(settings, fromPending: fromPending)) {
      return false;
    }
    final cachedY = _cachedTrackSnapshotY;
    final cachedCount = _cachedTrackSnapshotScrollCount;
    List<DanmakuScrollTrackItemSnapshot> trackSnapshots;
    if (cachedY == trackY && cachedCount == _scrollItems.length && _cachedTrackSnapshots != null) {
      trackSnapshots = _cachedTrackSnapshots!;
    } else {
      trackSnapshots = _scrollItems
          .where((item) => item.trackPosition == trackY)
          .map(
            (item) => DanmakuScrollTrackItemSnapshot(
              width: item.width,
              startMs: item.startMs,
              durationMs: item.durationMs,
            ),
          )
          .toList(growable: false);
      _cachedTrackSnapshotY = trackY;
      _cachedTrackSnapshotScrollCount = _scrollItems.length;
      _cachedTrackSnapshots = trackSnapshots;
    }
    return DanmakuScrollTrackScheduler.canAddToTrack(
      visibleItems: trackSnapshots,
      viewportWidth: viewportSize.width,
      timelineMs: _timelineMs,
      newItemWidth: newItemWidth,
      newItemDurationMs: _scrollDurationMs(widget.controller.settings),
      minGap: 20.0,
    );
  }

  bool _staticCanAddToTrack(double trackPosition, LocalDanmakuItemType type) {
    for (final item in _staticItems) {
      if (item.content.type != type) continue;
      if (item.trackPosition != trackPosition) continue;
      if (item.isExpired(_timelineMs, _viewportSize)) continue;
      return false;
    }
    return true;
  }

  double _fallbackTrack(List<double> tracks, String seed) {
    var hash = 0;
    for (var i = 0; i < seed.length; i += 1) {
      hash = ((hash * 33) ^ seed.codeUnitAt(i)) & 0x7fffffff;
    }
    return tracks[hash % tracks.length];
  }

  DanmakuTrackLayout? _resolveTrackLayout(DanmakuSettings settings) {
    if (_viewportSize.isEmpty) return null;
    final signature = _buildTrackLayoutSignature(settings);
    if (_trackLayout != null && signature == _lastTrackLayoutSignature) {
      return _trackLayout;
    }
    _lastTrackLayoutSignature = signature;
    _trackLayout = DanmakuTrackLayoutEngine.compute(
      viewportSize: _viewportSize,
      trackHeight: _trackHeight(settings),
      areaRatio: _effectiveAreaRatio(settings),
      avoidSubtitleArea: settings.avoidSubtitleArea,
      avoidCenterArea: false,
      subtitleReservedAreaRatio: _subtitleReservedAreaRatio,
    );
    return _trackLayout;
  }

  List<DanmakuComment> _resolveVisibleComments(
    List<DanmakuComment> sourceComments, {
    required DanmakuSettings settings,
  }) {
    final hideDuplicate = settings.hideDuplicate;
    final density = _effectiveSamplingDensity(settings);
    final duplicateWindowMs = _duplicateWindowMs(settings);
    if (identical(sourceComments, _cachedSourceComments) &&
        hideDuplicate == _cachedHideDuplicate &&
        (density - _cachedDensity).abs() < 0.0001 &&
        duplicateWindowMs == _cachedDuplicateWindowMs) {
      return _cachedVisibleComments;
    }
    _cachedSourceComments = sourceComments;
    _cachedHideDuplicate = hideDuplicate;
    _cachedDensity = density;
    _cachedDuplicateWindowMs = duplicateWindowMs;
    if (sourceComments.isEmpty) {
      _cachedVisibleComments = sourceComments;
      return _cachedVisibleComments;
    }
    var visibleComments = sourceComments;
    if (hideDuplicate) {
      final seenTimeByText = <String, int>{};
      visibleComments = sourceComments
          .where((comment) {
            final key = _normalizeDuplicateKey(comment.text);
            if (key.isEmpty) return false;
            final lastSeenAtMs = seenTimeByText[key];
            seenTimeByText[key] = comment.timeMs;
            if (lastSeenAtMs == null) {
              return true;
            }
            return comment.timeMs - lastSeenAtMs >= duplicateWindowMs;
          })
          .toList(growable: false);
    }
    final densityValue = density.clamp(0.2, 1.0).toDouble();
    _cachedVisibleComments = _applyDensity(visibleComments, densityValue);
    return _cachedVisibleComments;
  }

  double _effectiveSamplingDensity(DanmakuSettings settings) {
    final baseDensity = _runtimeTuning(settings).effectiveDensity;
    if (_overloadLevel == _OverloadLevel.normal &&
        _pendingScrollComments.isEmpty &&
        _queuePressureStreak == 0) {
      return baseDensity;
    }
    final currentLayout = _resolveTrackLayout(settings);
    if (currentLayout == null || _viewportSize.isEmpty) {
      return baseDensity;
    }
    final referenceLayout = DanmakuTrackLayoutEngine.compute(
      viewportSize: _viewportSize,
      trackHeight: _trackHeight(settings),
      areaRatio: 1.0,
      avoidSubtitleArea: settings.avoidSubtitleArea,
      avoidCenterArea: false,
      subtitleReservedAreaRatio: _subtitleReservedAreaRatio,
    );
    final currentCapacity = _samplingLaneCapacity(currentLayout, settings);
    final referenceCapacity = _samplingLaneCapacity(referenceLayout, settings);
    if (currentCapacity <= 0 || referenceCapacity <= 0) {
      return baseDensity;
    }
    final capacityScale = currentCapacity / referenceCapacity;
    final easedCapacityScale = resolveDanmakuDensityCapacityScale(
      capacityScale,
    );
    return (baseDensity * easedCapacityScale)
        .clamp(1 / _densityBucketScale, 1.0)
        .toDouble();
  }

  double _samplingLaneCapacity(
    DanmakuTrackLayout layout,
    DanmakuSettings settings,
  ) {
    var capacity = 0.0;
    if (settings.scrollEnabled || settings.topEnabled) {
      capacity += layout.topTrackYs.length;
    }
    if (settings.bottomEnabled) {
      capacity += layout.bottomTrackOffsets.length;
    }
    return capacity;
  }

  String _normalizeDuplicateKey(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  int _duplicateWindowMs(DanmakuSettings settings) {
    return math.max(_scrollDurationMs(settings), _minimumDuplicateWindowMs);
  }

  int _activeWindowMs(DanmakuSettings settings) {
    return math.max(_scrollDurationMs(settings), _staticDurationMs(settings));
  }

  int _scrollDurationMs(DanmakuSettings settings) {
    return _runtimeTuning(settings).effectiveDurationMs;
  }

  int _staticDurationMs(DanmakuSettings settings) {
    return (_staticDanmakuDurationMs /
            resolveDanmakuMotionSpeedFactor(settings.speed))
        .round();
  }

  int _baseScrollDurationMs(DanmakuSettings settings) {
    final viewportDurationScale = resolveDanmakuViewportMotionDurationScale(
      _viewportSize.shortestSide,
    );
    return (_scrollDurationSeconds(settings) * viewportDurationScale * 1000)
        .round();
  }

  double _scrollDurationSeconds(DanmakuSettings settings) {
    final speedFactor = resolveDanmakuMotionSpeedFactor(settings.speed);
    return (8.5 / speedFactor).clamp(3.2, 8.5).toDouble();
  }

  double _viewportAdaptiveScale() {
    if (_viewportSize.isEmpty) {
      return 1.0;
    }
    final safeDevicePixelRatio = math.max(1.0, _devicePixelRatio);
    final shortSideDp = _viewportSize.shortestSide / safeDevicePixelRatio;
    return (shortSideDp / 420.0).clamp(0.72, 1.35).toDouble();
  }

  double _fontSize(DanmakuSettings settings) {
    final viewportScale = _viewportAdaptiveScale();
    return math.max(12.0, 24.0 * settings.fontScale * viewportScale);
  }

  double _fontThickness(DanmakuSettings settings) {
    return settings.fontThickness.clamp(0.8, 1.4).toDouble();
  }

  int _fontWeightIndex(DanmakuSettings settings) {
    final thickness = _fontThickness(settings);
    if (thickness <= 0.8) {
      return math.max(0, _baseFontWeightIndex - 1);
    }
    if (thickness >= 1.3) {
      return math.min(FontWeight.values.length - 1, _baseFontWeightIndex + 1);
    }
    return _baseFontWeightIndex;
  }

  double _strokeWidth(DanmakuSettings settings) {
    return _baseStrokeWidth *
        _fontThickness(settings) *
        _viewportAdaptiveScale();
  }

  double _trackHeight(DanmakuSettings settings) {
    final signature = _buildTrackMetricsSignature(settings);
    if (_cachedTrackHeightValue != null &&
        signature == _lastTrackMetricsSignature) {
      return _cachedTrackHeightValue!;
    }
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'Danmaku',
        style: TextStyle(
          fontSize: _fontSize(settings),
          height: _lineHeight,
          fontWeight: FontWeight.values[_fontWeightIndex(settings)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _lastTrackMetricsSignature = signature;
    _cachedTrackHeightValue =
        textPainter.height + (_textVerticalPadding(settings) * 2.0);
    return _cachedTrackHeightValue!;
  }

  double _textVerticalPadding(DanmakuSettings settings) {
    return math.max(_strokeWidth(settings) + 1.0, _fontSize(settings) * 0.38);
  }

  double _effectiveAreaRatio(DanmakuSettings settings) {
    final base = _runtimeTuning(settings).effectiveAreaRatio;
    if (!settings.avoidSubtitleArea) {
      return base;
    }
    return math.min(base, 1.0 - _subtitleReservedAreaRatio);
  }

  String _buildVisibleWindowSignature(DanmakuSettings settings) {
    return <Object>[
      settings.colorEnabled,
      settings.scrollEnabled,
      settings.topEnabled,
      settings.bottomEnabled,
    ].join('|');
  }

  String _buildOptionSignature(
    DanmakuSettings settings, {
    required int visibleCommentCount,
  }) {
    return <Object>[
      settings.fontScale,
      settings.fontThickness.toStringAsFixed(3),
      settings.speed,
      settings.displayAreaRatio.toStringAsFixed(3),
      settings.density.toStringAsFixed(3),
      settings.topEnabled,
      settings.bottomEnabled,
      settings.scrollEnabled,
      settings.avoidSubtitleArea,
      visibleCommentCount >= _massiveModeThreshold,
      _lastViewportSignature,
    ].join('|');
  }

  String _buildTrackLayoutSignature(DanmakuSettings settings) {
    return <Object>[
      _lastViewportSignature,
      _fontSize(settings).toStringAsFixed(2),
      _trackHeight(settings).toStringAsFixed(2),
      _effectiveAreaRatio(settings).toStringAsFixed(3),
      settings.avoidSubtitleArea,
      settings.avoidCenterArea,
    ].join('|');
  }

  String _buildTrackMetricsSignature(DanmakuSettings settings) {
    return <Object>[
      _fontSize(settings).toStringAsFixed(2),
      _fontWeightIndex(settings),
      _strokeWidth(settings).toStringAsFixed(2),
      _lineHeight.toStringAsFixed(2),
    ].join('|');
  }

  String _buildVisualStateSignature() {
    final settings = widget.controller.settings;
    return <Object>[
      widget.controller.ready,
      settings.enabled,
      settings.opacity.toStringAsFixed(3),
      settings.avoidCenterArea,
      settings.displayAreaRatio.toStringAsFixed(3),
    ].join('|');
  }

  String _buildCommentsSignature(List<DanmakuComment> comments) {
    if (comments.isEmpty) {
      return '0';
    }
    var hash = 0;
    for (final comment in comments) {
      hash = 0x1fffffff & (hash + comment.id.hashCode);
      hash = 0x1fffffff & (hash + comment.timeMs.hashCode);
      hash = 0x1fffffff & (hash + comment.type.hashCode);
      hash = 0x1fffffff & (hash + comment.text.hashCode);
      hash = 0x1fffffff & (hash + comment.color.toARGB32().hashCode);
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash ^= (hash >> 6);
    }
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    hash ^= (hash >> 11);
    hash = 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
    final first = comments.first;
    final last = comments.last;
    return <Object>[
      comments.length,
      first.id,
      first.timeMs,
      last.id,
      last.timeMs,
      hash,
    ].join('|');
  }

  String _buildViewportSignature(Size size, double devicePixelRatio) {
    return <Object>[
      size.width.toStringAsFixed(2),
      size.height.toStringAsFixed(2),
      devicePixelRatio.toStringAsFixed(2),
    ].join('|');
  }

  int _lowerBound(List<DanmakuComment> comments, int targetMs) {
    var low = 0;
    var high = comments.length;
    while (low < high) {
      final mid = low + ((high - low) >> 1);
      if (comments[mid].timeMs < targetMs) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  int _upperBound(List<DanmakuComment> comments, int targetMs) {
    var low = 0;
    var high = comments.length;
    while (low < high) {
      final mid = low + ((high - low) >> 1);
      if (comments[mid].timeMs <= targetMs) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  List<DanmakuComment> _applyDensity(
    List<DanmakuComment> comments,
    double density,
  ) {
    if (comments.isEmpty || density >= 0.999) {
      return comments;
    }
    final threshold = (density * _densityBucketScale).round().clamp(
      1,
      _densityBucketScale,
    );
    final filtered = comments
        .where((comment) {
          return _commentBucket(comment) < threshold;
        })
        .toList(growable: false);
    if (filtered.isNotEmpty) {
      return filtered;
    }
    return comments.take(1).toList(growable: false);
  }

  int _commentBucket(DanmakuComment comment) {
    var hash = comment.timeMs & 0x7fffffff;
    final id = comment.id;
    for (var i = 0; i < id.length; i += 1) {
      hash = ((hash * 33) ^ id.codeUnitAt(i)) & 0x7fffffff;
    }
    return hash % _densityBucketScale;
  }

  bool _isCommentTypeEnabled(DanmakuComment comment, DanmakuSettings settings) {
    return switch (comment.type) {
      DanmakuCommentType.scroll => settings.scrollEnabled,
      DanmakuCommentType.top => settings.topEnabled,
      DanmakuCommentType.bottom => settings.bottomEnabled,
    };
  }

  LocalDanmakuItemType _mapItemType(DanmakuCommentType type) {
    return switch (type) {
      DanmakuCommentType.top => LocalDanmakuItemType.top,
      DanmakuCommentType.bottom => LocalDanmakuItemType.bottom,
      DanmakuCommentType.scroll => LocalDanmakuItemType.scroll,
    };
  }
}
