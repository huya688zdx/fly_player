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

class _DanmakuOverlayState extends State<DanmakuOverlay>
    with SingleTickerProviderStateMixin {
  static const int _densityBucketScale = 1000;
  static const int _massiveModeThreshold = 1200;
  static const int _minimumDuplicateWindowMs = 2500;
  static const int _staticDanmakuDurationMs = 2600;
  static const double _subtitleReservedAreaRatio = 0.16;
  static const double _lineHeight = 1.0;
  static const int _fontWeightIndex = 7;
  static const double _strokeWidth = 0.9;
  static const Duration _maskEmptyStateClearGrace = Duration(milliseconds: 900);

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

  DanmakuTrackLayout? _trackLayout;
  int _lastScheduledPositionMs = 0;
  int _timelineMs = 0;
  int _lastTickerElapsedUs = 0;
  int? _pendingPauseSyncPositionMs;
  String _lastOptionSignature = '';
  String _lastVisibleWindowSignature = '';
  String _lastViewportSignature = '';
  String _lastTrackLayoutSignature = '';
  Size _viewportSize = Size.zero;
  double _devicePixelRatio = 1.0;
  ui.Image? _maskImage;
  String? _maskImageKey;
  int _maskLoadGeneration = 0;
  Timer? _maskClearTimer;
  bool _pendingViewportSync = false;
  Size? _pendingViewportSize;
  double? _pendingViewportDevicePixelRatio;
  String? _pendingViewportSignature;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
    debugPrint(
      '[DANMAKU][OVERLAY] init overlay=${identityHashCode(this)} '
      'maskKey=${_maskStateKey(widget.occlusionState).isEmpty ? '-' : _maskStateKey(widget.occlusionState)}',
    );
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
      debugPrint(
        '[DANMAKU][OVERLAY] didUpdate overlay=${identityHashCode(this)} '
        'oldKey=${_maskStateKey(oldWidget.occlusionState).isEmpty ? '-' : _maskStateKey(oldWidget.occlusionState)} '
        'newKey=${_maskStateKey(widget.occlusionState).isEmpty ? '-' : _maskStateKey(widget.occlusionState)}',
      );
    }
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
                if (stabilizedPositionMs != widget.position.inMilliseconds) {
                  debugPrint(
                    '[DANMAKU][OVERLAY] stabilize_pause '
                    'reported=${widget.position.inMilliseconds} '
                    'stabilized=$stabilizedPositionMs '
                    'timeline=$_timelineMs scheduled=$_lastScheduledPositionMs',
                  );
                }
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
    debugPrint(
      '[DANMAKU][OVERLAY] dispose overlay=${identityHashCode(this)} '
      'maskKey=${_maskImageKey ?? '-'}',
    );
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
    if (!widget.controller.ready || !widget.controller.settings.enabled) {
      _detachEngineState();
      setState(() {});
      return;
    }
    _syncEngineState();
    setState(() {});
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
              child: Opacity(
                opacity: settings.opacity.clamp(0.2, 1.0),
                child: CustomPaint(
                  painter: LocalDanmakuPainter<DanmakuComment>(
                    repaint: _painterRepaint,
                    scrollItems: _scrollItems,
                    staticItems: _staticItems,
                    timelineListenable: _timelineNotifier,
                    devicePixelRatio: _devicePixelRatio,
                    maskImage: settings.avoidCenterArea ? _maskImage : null,
                    displayAreaRatio: settings.displayAreaRatio,
                    captureAreaRatio: widget.occlusionState.captureAreaRatio,
                  ),
                  size: Size.infinite,
                ),
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
      setState(() {});
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

  void _handleTick(Duration elapsed) {
    final elapsedUs = elapsed.inMicroseconds;
    if (_lastTickerElapsedUs == 0) {
      _lastTickerElapsedUs = elapsedUs;
    } else {
      final deltaUs = elapsedUs - _lastTickerElapsedUs;
      _lastTickerElapsedUs = elapsedUs;
      if (deltaUs > 0) {
        final scaledDeltaMs =
            (deltaUs *
                    _effectivePlaybackSpeedFactor() /
                    Duration.microsecondsPerMillisecond)
                .round();
        if (scaledDeltaMs > 0) {
          _timelineMs += scaledDeltaMs;
        }
      }
    }
    if (_timelineNotifier.value != _timelineMs) {
      _timelineNotifier.value = _timelineMs;
    }
    if (_purgeExpiredItems() &&
        (_scrollItems.isNotEmpty || _staticItems.isNotEmpty)) {
      _bumpScene();
    }
    if (_scrollItems.isEmpty && _staticItems.isEmpty && _ticker.isActive) {
      _pauseTicker();
    }
  }

  void _startTickerIfNeeded() {
    if (widget.paused) {
      _pauseTicker();
      return;
    }
    if (_scrollItems.isEmpty && _staticItems.isEmpty) {
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
    _timelineMs =
        positionMs ??
        (_timelineMs > 0 ? _timelineMs : widget.position.inMilliseconds);
    if (_timelineNotifier.value != _timelineMs) {
      _timelineNotifier.value = _timelineMs;
    }
  }

  void _syncEngineState({bool forceSourceReset = false}) {
    try {
      final settings = widget.controller.settings;
      final currentPositionMs = _resolvedPositionMs();
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

      final sourceChanged =
          forceSourceReset || !identical(comments, _scheduledComments);
      final visibleWindowChanged =
          visibleWindowSignature != _lastVisibleWindowSignature;
      final optionChanged = optionSignature != _lastOptionSignature;
      _lastOptionSignature = optionSignature;

      if (sourceChanged || visibleWindowChanged || optionChanged) {
        _scheduledComments = comments;
        _lastVisibleWindowSignature = visibleWindowSignature;
        _resyncVisibleWindow(
          comments,
          settings,
          currentPositionMs,
          reason: sourceChanged ? 'source' : 'settings',
        );
        return;
      }

      final previousPositionMs = _lastScheduledPositionMs;

      if (currentPositionMs < previousPositionMs - 800) {
        _resyncVisibleWindow(
          comments,
          settings,
          currentPositionMs,
          reason: 'seek_back',
        );
        return;
      }

      if (currentPositionMs > previousPositionMs + 1500) {
        _resyncVisibleWindow(
          comments,
          settings,
          currentPositionMs,
          reason: 'seek_forward',
        );
        return;
      }

      if (currentPositionMs <= previousPositionMs) {
        _syncTickerForPlaybackState(positionMs: currentPositionMs);
        return;
      }

      final startIndex = _upperBound(comments, previousPositionMs);
      final endIndex = _upperBound(comments, currentPositionMs);
      var emittedCount = 0;
      for (var i = startIndex; i < endIndex; i += 1) {
        if (_enqueueComment(comments[i], settings, currentPositionMs)) {
          emittedCount += 1;
        }
      }
      if (emittedCount > 0) {
        _bumpScene();
      }
      _lastScheduledPositionMs = currentPositionMs;
      _syncTickerForPlaybackState(positionMs: currentPositionMs);
    } finally {
      _pendingPauseSyncPositionMs = null;
    }
  }

  void _resyncVisibleWindow(
    List<DanmakuComment> comments,
    DanmakuSettings settings,
    int currentPositionMs, {
    required String reason,
  }) {
    _resetEngineTimeline(clearScreen: true);
    final startMs = math.max(0, currentPositionMs - _activeWindowMs(settings));
    _emitCommentsInRange(
      comments,
      settings,
      startMs: startMs,
      endMs: currentPositionMs,
      currentPositionMs: currentPositionMs,
    );
    _lastScheduledPositionMs = currentPositionMs;
    _bumpScene();
    _syncTickerForPlaybackState();
  }

  void _resetEngineTimeline({required bool clearScreen}) {
    if (clearScreen) {
      _clearActiveItems(notify: false);
    }
    _emittedCommentIds.clear();
  }

  void _detachEngineState() {
    _pauseTicker();
    _clearActiveItems(notify: false);
    _cachedSourceComments = const <DanmakuComment>[];
    _cachedVisibleComments = const <DanmakuComment>[];
    _scheduledComments = const <DanmakuComment>[];
    _emittedCommentIds.clear();
    _trackLayout = null;
    _lastScheduledPositionMs = 0;
    _timelineMs = 0;
    _lastTickerElapsedUs = 0;
    _lastOptionSignature = '';
    _lastVisibleWindowSignature = '';
    _lastTrackLayoutSignature = '';
    if (_timelineNotifier.value != 0) {
      _timelineNotifier.value = 0;
    }
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
    debugPrint(
      '[DANMAKU][OVERLAY] sync overlay=${identityHashCode(this)} '
      'nextKey=${nextKey.isEmpty ? '-' : nextKey} currentKey=${_maskImageKey ?? '-'}',
    );
    if (nextKey.isEmpty) {
      if (_shouldDelayMaskClear()) {
        _scheduleDeferredMaskClear();
        return;
      }
      _cancelPendingMaskClear();
      _maskLoadGeneration += 1;
      if (_maskImage != null || _maskImageKey != null) {
        debugPrint(
          '[DANMAKU][OVERLAY] clear overlay=${identityHashCode(this)} '
          'reason=empty_state currentKey=${_maskImageKey ?? '-'}',
        );
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
      debugPrint(
        '[DANMAKU][OVERLAY] clear overlay=${identityHashCode(this)} '
        'reason=missing_path currentKey=${_maskImageKey ?? '-'}',
      );
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
        debugPrint(
          '[DANMAKU][OVERLAY] clear overlay=${identityHashCode(this)} '
          'reason=file_missing currentKey=${_maskImageKey ?? '-'} path=$path',
        );
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
      debugPrint(
        '[DANMAKU][OVERLAY] apply overlay=${identityHashCode(this)} '
        'key=$nextKey path=$path size=${frame.image.width}x${frame.image.height}',
      );
      _disposeMaskImage();
      _maskImage = frame.image;
      _maskImageKey = nextKey;
      setState(() {});
    } catch (_) {
      if (!mounted || generation != _maskLoadGeneration) {
        return;
      }
      debugPrint(
        '[DANMAKU][OVERLAY] clear overlay=${identityHashCode(this)} '
        'reason=decode_failed currentKey=${_maskImageKey ?? '-'} path=$path',
      );
      _disposeMaskImage();
      setState(() {});
    }
  }

  void _disposeMaskImage() {
    if (_maskImage != null || _maskImageKey != null) {
      debugPrint(
        '[DANMAKU][OVERLAY] dispose_mask overlay=${identityHashCode(this)} '
        'key=${_maskImageKey ?? '-'}',
      );
    }
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
      debugPrint(
        '[DANMAKU][OVERLAY] clear overlay=${identityHashCode(this)} '
        'reason=empty_state_grace_elapsed currentKey=${_maskImageKey ?? '-'}',
      );
      _disposeMaskImage();
      setState(() {});
    });
  }

  void _cancelPendingMaskClear() {
    _maskClearTimer?.cancel();
    _maskClearTimer = null;
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
    _scrollItems.removeWhere((item) {
      final expired = item.isExpired(_timelineMs, viewportSize);
      if (expired) {
        item.dispose();
        changed = true;
      }
      return expired;
    });
    _staticItems.removeWhere((item) {
      final expired = item.isExpired(_timelineMs, viewportSize);
      if (expired) {
        item.dispose();
        changed = true;
      }
      return expired;
    });
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

  bool _enqueueComment(
    DanmakuComment comment,
    DanmakuSettings settings,
    int currentPositionMs,
  ) {
    if (!_isCommentTypeEnabled(comment, settings)) {
      return false;
    }
    if (!_emittedCommentIds.add(comment.id)) {
      return false;
    }
    final layout = _resolveTrackLayout(settings);
    if (layout == null) {
      return false;
    }

    final itemType = _mapItemType(comment.type);
    final durationMs = itemType == LocalDanmakuItemType.scroll
        ? _scrollDurationMs(settings)
        : _staticDanmakuDurationMs;
    final ageMs = math.max(0, currentPositionMs - comment.timeMs);
    if (ageMs >= durationMs) {
      return false;
    }

    final color = settings.colorEnabled ? comment.color : Colors.white;
    final item = LocalDanmakuItem.rasterize<DanmakuComment>(
      content: LocalDanmakuContentItem<DanmakuComment>(
        comment.text,
        color: color,
        type: itemType,
        extra: comment,
      ),
      trackPosition: 0,
      startMs: _timelineMs - ageMs,
      durationMs: durationMs,
      fontSize: _fontSize(settings),
      fontWeight: _fontWeightIndex,
      strokeWidth: _strokeWidth,
      lineHeight: _lineHeight,
      devicePixelRatio: _devicePixelRatio,
    );

    final trackPosition = _pickTrackPosition(
      layout,
      item,
      allowOverlap:
          itemType == LocalDanmakuItemType.scroll &&
          _scheduledComments.length >= _massiveModeThreshold,
      overlapSeed: comment.id,
    );
    if (trackPosition == null) {
      item.dispose();
      return false;
    }

    item.trackPosition = trackPosition;
    if (item.isScroll) {
      _scrollItems.add(item);
    } else {
      _staticItems.add(item);
    }
    return true;
  }

  double? _pickTrackPosition(
    DanmakuTrackLayout layout,
    LocalDanmakuItem<DanmakuComment> item, {
    required bool allowOverlap,
    required String overlapSeed,
  }) {
    final viewportSize = _viewportSize;
    switch (item.content.type) {
      case LocalDanmakuItemType.scroll:
        final trackY = _findTrack(
          layout.topTrackYs,
          seed: overlapSeed,
          canUse: (track) =>
              _scrollCanAddToTrack(track, item.width, viewportSize),
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
    Size viewportSize,
  ) {
    for (final item in _scrollItems) {
      if (item.trackPosition != trackY) continue;
      if (item.isExpired(_timelineMs, viewportSize)) continue;
      final x = item.xFor(viewportSize, _timelineMs);
      final existingEndPosition = x + item.width;
      if (viewportSize.width - existingEndPosition < 0) {
        return false;
      }
      if (item.width < newItemWidth) {
        final existingProgress =
            1 - ((viewportSize.width - x) / (item.width + viewportSize.width));
        final newThreshold =
            viewportSize.width / (viewportSize.width + newItemWidth);
        if (existingProgress > newThreshold) {
          return false;
        }
      }
    }
    return true;
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
    final density = settings.density;
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

  String _normalizeDuplicateKey(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  int _duplicateWindowMs(DanmakuSettings settings) {
    return math.max(_activeWindowMs(settings), _minimumDuplicateWindowMs);
  }

  int _activeWindowMs(DanmakuSettings settings) {
    return math.max(_scrollDurationMs(settings), _staticDanmakuDurationMs);
  }

  int _scrollDurationMs(DanmakuSettings settings) {
    return (_scrollDurationSeconds(settings) * 1000).round();
  }

  double _scrollDurationSeconds(DanmakuSettings settings) {
    final speed = settings.speed.clamp(0.7, 1.8).toDouble();
    return (8.5 / speed).clamp(3.2, 8.5).toDouble();
  }

  double _fontSize(DanmakuSettings settings) {
    return math.max(16.0, 24.0 * settings.fontScale);
  }

  double _trackHeight(DanmakuSettings settings) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: '弹幕',
        style: TextStyle(fontSize: _fontSize(settings), height: _lineHeight),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return textPainter.height + (_textVerticalPadding(settings) * 2.0);
  }

  double _textVerticalPadding(DanmakuSettings settings) {
    return math.max(_strokeWidth + 1.0, _fontSize(settings) * 0.18);
  }

  double _effectiveAreaRatio(DanmakuSettings settings) {
    final base = settings.displayAreaRatio.clamp(0.1, 1.0).toDouble();
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
      settings.speed,
      _effectiveAreaRatio(settings),
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
