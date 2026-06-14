import 'dart:math' as math;

import 'package:canvas_danmaku/canvas_danmaku.dart' as open_danmaku;
import 'package:flutter/material.dart';

import '../controller/danmaku_controller.dart';
import '../models/danmaku_comment.dart';
import '../models/danmaku_dynamic_occlusion.dart';
import '../models/danmaku_settings.dart';

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

class _DanmakuOverlayState extends State<DanmakuOverlay> {
  static const int _densityBucketScale = 1000;
  static const int _minimumDuplicateWindowMs = 2500;
  static const int _staticDanmakuDurationMs = 2600;
  static const int _seekResyncThresholdMs = 1500;
  static const int _massiveModeThreshold = 1200;
  static const double _subtitleReservedAreaRatio = 0.16;
  static const double _lineHeight = 1.0;
  static const double _strokeWidth = 1.5;

  open_danmaku.DanmakuController<DanmakuComment>? _renderer;
  bool _pendingPostFrameSync = false;
  String _lastCommentsSignature = '';
  String _lastOptionSignature = '';
  int _lastReportedPositionMs = 0;
  int _lastScheduledPositionMs = 0;

  List<DanmakuComment> _cachedSourceComments = const <DanmakuComment>[];
  List<DanmakuComment> _cachedVisibleComments = const <DanmakuComment>[];
  bool _cachedHideDuplicate = false;
  double _cachedDensity = 1.0;
  int _cachedDuplicateWindowMs = 0;
  List<DanmakuComment> _scheduledComments = const <DanmakuComment>[];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant DanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
      _clearRenderer();
      _schedulePostFrameSync();
      return;
    }
    final positionChanged = oldWidget.position != widget.position;
    final pausedChanged = oldWidget.paused != widget.paused;
    if (positionChanged || pausedChanged) {
      _syncRenderer();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    _syncRenderer(forceResync: true);
    if (mounted) {
      setState(() {});
    }
  }

  void _handleRendererCreated(
    open_danmaku.DanmakuController<DanmakuComment> renderer,
  ) {
    _renderer = renderer;
    _schedulePostFrameSync();
  }

  void _schedulePostFrameSync() {
    if (_pendingPostFrameSync) {
      return;
    }
    _pendingPostFrameSync = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingPostFrameSync = false;
      if (!mounted) {
        return;
      }
      _syncRenderer(forceResync: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.controller.settings;
    if (!widget.controller.ready || !settings.enabled) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: open_danmaku.DanmakuScreen<DanmakuComment>(
        createdController: _handleRendererCreated,
        option: _buildRendererOption(settings),
      ),
    );
  }

  void _syncRenderer({bool forceResync = false}) {
    final renderer = _renderer;
    if (renderer == null) {
      return;
    }
    if (!widget.controller.ready) {
      _clearRenderer();
      return;
    }
    final settings = widget.controller.settings;
    if (!settings.enabled) {
      _clearRenderer();
      return;
    }
    if (renderer.viewWidth <= 0 || renderer.viewHeight <= 0) {
      _schedulePostFrameSync();
      return;
    }

    final currentPositionMs = widget.position.inMilliseconds;
    final visibleComments = _resolveVisibleComments(
      widget.controller.comments,
      settings: settings,
    );
    final commentsSignature = _buildCommentsSignature(visibleComments);
    final previousOptionSignature = _lastOptionSignature;
    final optionSignature = _buildOptionSignature(
      settings,
      visibleCommentCount: visibleComments.length,
    );
    final sourceChanged = commentsSignature != _lastCommentsSignature;
    final optionChanged = optionSignature != _lastOptionSignature;
    _scheduledComments = visibleComments;

    if (optionChanged) {
      renderer.updateOption(_buildRendererOption(settings));
      _lastOptionSignature = optionSignature;
    }

    final requiresResync =
        forceResync ||
        sourceChanged ||
        _shouldResyncForSeek(currentPositionMs) ||
        _shouldResyncForOptionChange(previousOptionSignature);
    if (requiresResync) {
      _lastCommentsSignature = commentsSignature;
      _resyncRenderer(settings, currentPositionMs);
    } else if (currentPositionMs > _lastScheduledPositionMs) {
      _emitCommentsInRange(
        settings,
        startMs: _lastScheduledPositionMs,
        endMs: currentPositionMs,
        currentPositionMs: currentPositionMs,
      );
      _lastScheduledPositionMs = currentPositionMs;
      _lastReportedPositionMs = currentPositionMs;
    } else {
      _lastReportedPositionMs = currentPositionMs;
    }

    _syncPlaybackState();
  }

  void _syncPlaybackState() {
    final renderer = _renderer;
    if (renderer == null) {
      return;
    }
    if (widget.paused) {
      if (renderer.running) {
        renderer.pause();
      }
      return;
    }
    if (!renderer.running) {
      renderer.resume();
    }
  }

  bool _shouldResyncForSeek(int currentPositionMs) {
    if (_lastReportedPositionMs == 0 && _lastScheduledPositionMs == 0) {
      return true;
    }
    return (currentPositionMs - _lastReportedPositionMs).abs() >
        _seekResyncThresholdMs;
  }

  void _resyncRenderer(DanmakuSettings settings, int currentPositionMs) {
    final renderer = _renderer;
    if (renderer == null) {
      return;
    }
    renderer.clear();
    final startMs = math.max(0, currentPositionMs - _activeWindowMs(settings));
    _emitCommentsInRange(
      settings,
      startMs: startMs,
      endMs: currentPositionMs,
      currentPositionMs: currentPositionMs,
      catchUp: true,
    );
    _lastScheduledPositionMs = currentPositionMs;
    _lastReportedPositionMs = currentPositionMs;
  }

  void _clearRenderer() {
    _renderer?.clear();
    _lastCommentsSignature = '';
    _lastOptionSignature = '';
    _lastReportedPositionMs = 0;
    _lastScheduledPositionMs = 0;
  }

  void _emitCommentsInRange(
    DanmakuSettings settings, {
    required int startMs,
    required int endMs,
    required int currentPositionMs,
    bool catchUp = false,
  }) {
    final comments = _scheduledComments;
    if (comments.isEmpty || endMs < startMs) {
      return;
    }
    final startIndex = _lowerBound(comments, startMs);
    final endIndex = _upperBound(comments, endMs);
    for (var index = startIndex; index < endIndex; index += 1) {
      _enqueueComment(
        comments[index],
        settings,
        currentPositionMs: currentPositionMs,
        catchUp: catchUp,
      );
    }
  }

  void _enqueueComment(
    DanmakuComment comment,
    DanmakuSettings settings, {
    required int currentPositionMs,
    required bool catchUp,
  }) {
    final renderer = _renderer;
    if (renderer == null || !_isCommentTypeEnabled(comment, settings)) {
      return;
    }
    final itemType = _mapItemType(comment.type);
    final durationMs = itemType == open_danmaku.DanmakuItemType.scroll
        ? _scrollDurationMs(settings)
        : _staticDurationMs(settings);
    final ageMs = math.max(0, currentPositionMs - comment.timeMs);
    if (ageMs >= durationMs) {
      return;
    }

    final beforeScrollCount = renderer.scrollDanmaku.length;
    renderer.addDanmaku(
      open_danmaku.DanmakuContentItem<DanmakuComment>(
        comment.text,
        color: settings.colorEnabled ? comment.color : Colors.white,
        type: itemType,
        extra: comment,
      ),
    );
    if (!catchUp || itemType != open_danmaku.DanmakuItemType.scroll) {
      return;
    }
    if (renderer.scrollDanmaku.length <= beforeScrollCount) {
      return;
    }
    final item = renderer.scrollDanmaku.last;
    final viewportWidth = renderer.viewWidth;
    if (viewportWidth <= 0) {
      return;
    }
    final progress = ageMs / durationMs;
    item.xPosition = viewportWidth - (progress * (viewportWidth + item.width));
  }

  open_danmaku.DanmakuOption _buildRendererOption(DanmakuSettings settings) {
    return open_danmaku.DanmakuOption(
      fontSize: _fontSize(settings),
      fontWeight: 7,
      area: _resolveRendererArea(settings),
      duration: _scrollDurationMs(settings) / 1000,
      staticDuration: _staticDurationMs(settings) / 1000,
      opacity: settings.opacity.clamp(0.2, 1.0).toDouble(),
      hideTop: !settings.topEnabled,
      hideBottom: !settings.bottomEnabled,
      hideScroll: !settings.scrollEnabled,
      strokeWidth: _strokeWidth,
      massiveMode: _scheduledComments.length >= _massiveModeThreshold,
      safeArea: settings.avoidSubtitleArea,
      lineHeight: _lineHeight,
    );
  }

  double _resolveRendererArea(DanmakuSettings settings) {
    final ratio = settings.displayAreaRatio.clamp(0.1, 1.0).toDouble();
    final effectiveRatio = _effectiveAreaRatio(settings);
    if (ratio <= 0.10 + 0.0001) {
      return 0.10;
    }
    if (ratio <= 0.25 + 0.0001) {
      return 0.20;
    }
    if (ratio <= 0.50 + 0.0001) {
      return 0.38;
    }
    if (ratio <= 0.75 + 0.0001) {
      return 0.62;
    }
    return effectiveRatio >= 0.99 ? 1.0 : 0.82;
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
            if (key.isEmpty) {
              return false;
            }
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
    return math.max(_scrollDurationMs(settings), _minimumDuplicateWindowMs);
  }

  int _activeWindowMs(DanmakuSettings settings) {
    return math.max(_scrollDurationMs(settings), _staticDurationMs(settings));
  }

  int _scrollDurationMs(DanmakuSettings settings) {
    final speedFactor = resolveDanmakuMotionSpeedFactor(settings.speed);
    return ((8.5 / speedFactor).clamp(3.2, 8.5) * 1000).round();
  }

  int _staticDurationMs(DanmakuSettings settings) {
    return (_staticDanmakuDurationMs /
            resolveDanmakuMotionSpeedFactor(settings.speed))
        .round();
  }

  double _fontSize(DanmakuSettings settings) {
    return math.max(16.0, 24.0 * settings.fontScale);
  }

  double _effectiveAreaRatio(DanmakuSettings settings) {
    final base = settings.displayAreaRatio.clamp(0.1, 1.0).toDouble();
    if (!settings.avoidSubtitleArea) {
      return base;
    }
    return math.min(base, 1.0 - _subtitleReservedAreaRatio);
  }

  String _buildOptionSignature(
    DanmakuSettings settings, {
    required int visibleCommentCount,
  }) {
    return <Object>[
      settings.fontScale.toStringAsFixed(3),
      settings.speed.toStringAsFixed(3),
      settings.displayAreaRatio.toStringAsFixed(3),
      settings.opacity.toStringAsFixed(3),
      settings.topEnabled,
      settings.bottomEnabled,
      settings.scrollEnabled,
      settings.avoidSubtitleArea,
      settings.colorEnabled,
      visibleCommentCount >= _massiveModeThreshold,
    ].join('|');
  }

  bool _shouldResyncForOptionChange(String previousOptionSignature) {
    if (previousOptionSignature.isEmpty) {
      return true;
    }
    return previousOptionSignature != _lastOptionSignature;
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
        .where((comment) => _commentBucket(comment) < threshold)
        .toList(growable: false);
    if (filtered.isNotEmpty) {
      return filtered;
    }
    return comments.take(1).toList(growable: false);
  }

  int _commentBucket(DanmakuComment comment) {
    var hash = comment.timeMs & 0x7fffffff;
    final id = comment.id;
    for (var index = 0; index < id.length; index += 1) {
      hash = ((hash * 33) ^ id.codeUnitAt(index)) & 0x7fffffff;
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

  open_danmaku.DanmakuItemType _mapItemType(DanmakuCommentType type) {
    return switch (type) {
      DanmakuCommentType.top => open_danmaku.DanmakuItemType.top,
      DanmakuCommentType.bottom => open_danmaku.DanmakuItemType.bottom,
      DanmakuCommentType.scroll => open_danmaku.DanmakuItemType.scroll,
    };
  }
}
