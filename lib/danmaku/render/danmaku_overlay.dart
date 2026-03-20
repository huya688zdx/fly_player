import 'dart:math' as math;

import 'package:canvas_danmaku/canvas_danmaku.dart' as cd;
import 'package:flutter/material.dart';

import '../controller/danmaku_controller.dart';
import '../models/danmaku_comment.dart';
import '../models/danmaku_settings.dart';

class DanmakuOverlay extends StatefulWidget {
  final DanmakuController controller;
  final Duration position;
  final bool paused;

  const DanmakuOverlay({
    super.key,
    required this.controller,
    required this.position,
    required this.paused,
  });

  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _DanmakuOverlayState extends State<DanmakuOverlay> {
  static const int _densityBucketScale = 1000;
  static const int _massiveModeThreshold = 1200;
  cd.DanmakuController<DanmakuComment>? _engineController;
  List<DanmakuComment> _cachedSourceComments = const <DanmakuComment>[];
  List<DanmakuComment> _cachedVisibleComments = const <DanmakuComment>[];
  bool _cachedHideDuplicate = false;
  double _cachedDensity = 1.0;
  List<DanmakuComment> _scheduledComments = const <DanmakuComment>[];
  final Set<String> _emittedCommentIds = <String>{};
  int _lastScheduledPositionMs = 0;
  String _lastOptionSignature = '';

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
      _resetEngineTimeline(clearScreen: true);
    }
    final positionChanged = oldWidget.position != widget.position;
    final pausedChanged = oldWidget.paused != widget.paused;
    if (positionChanged || pausedChanged) {
      _syncEngineState();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    _syncEngineState(forceSourceReset: true);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.controller.settings;
    if (!widget.controller.ready || !settings.enabled) {
      return const SizedBox.shrink();
    }
    final initialComments = _resolveVisibleComments(
      widget.controller.comments,
      hideDuplicate: settings.hideDuplicate,
      density: settings.density,
    );
    return IgnorePointer(
      child: RepaintBoundary(
        child: cd.DanmakuScreen<DanmakuComment>(
          key: const ValueKey<String>('canvas_danmaku_overlay'),
          option: _buildOption(
            settings,
            visibleCommentCount: initialComments.length,
          ),
          createdController: (engine) {
            _engineController = engine;
            _syncEngineState(forceSourceReset: true);
          },
        ),
      ),
    );
  }

  void _syncEngineState({bool forceSourceReset = false}) {
    final engine = _engineController;
    final settings = widget.controller.settings;
    if (engine == null || !widget.controller.ready || !settings.enabled) {
      return;
    }

    final comments = _resolveVisibleComments(
      widget.controller.comments,
      hideDuplicate: settings.hideDuplicate,
      density: settings.density,
    );
    final optionSignature = _buildOptionSignature(
      settings,
      visibleCommentCount: comments.length,
    );
    if (optionSignature != _lastOptionSignature) {
      _lastOptionSignature = optionSignature;
      engine.updateOption(
        _buildOption(settings, visibleCommentCount: comments.length),
      );
    }
    if (widget.paused) {
      engine.pause();
    } else {
      engine.resume();
    }
    final sourceChanged =
        forceSourceReset || !identical(comments, _scheduledComments);
    if (sourceChanged) {
      _scheduledComments = comments;
      _resetEngineTimeline(clearScreen: true);
      _lastScheduledPositionMs = widget.position.inMilliseconds;
      return;
    }

    final currentPositionMs = widget.position.inMilliseconds;
    final previousPositionMs = _lastScheduledPositionMs;

    if (currentPositionMs < previousPositionMs - 800) {
      _resetEngineTimeline(clearScreen: true);
      _lastScheduledPositionMs = currentPositionMs;
      return;
    }

    if (currentPositionMs > previousPositionMs + 1500) {
      _lastScheduledPositionMs = currentPositionMs;
      return;
    }

    if (currentPositionMs <= previousPositionMs) {
      return;
    }

    final startIndex = _upperBound(comments, previousPositionMs);
    final endIndex = _upperBound(comments, currentPositionMs);
    for (var i = startIndex; i < endIndex; i++) {
      final comment = comments[i];
      if (_emittedCommentIds.add(comment.id)) {
        engine.addDanmaku(_mapComment(comment, settings));
      }
    }
    _lastScheduledPositionMs = currentPositionMs;
  }

  void _resetEngineTimeline({required bool clearScreen}) {
    if (clearScreen) {
      _engineController?.clear();
    }
    _emittedCommentIds.clear();
  }

  List<DanmakuComment> _resolveVisibleComments(
    List<DanmakuComment> sourceComments, {
    required bool hideDuplicate,
    required double density,
  }) {
    if (identical(sourceComments, _cachedSourceComments) &&
        hideDuplicate == _cachedHideDuplicate &&
        (density - _cachedDensity).abs() < 0.0001) {
      return _cachedVisibleComments;
    }
    _cachedSourceComments = sourceComments;
    _cachedHideDuplicate = hideDuplicate;
    _cachedDensity = density;
    if (sourceComments.isEmpty) {
      _cachedVisibleComments = sourceComments;
      return _cachedVisibleComments;
    }
    var visibleComments = sourceComments;
    if (hideDuplicate) {
      final seen = <String>{};
      visibleComments = sourceComments
          .where((comment) {
            final key = comment.text.trim();
            if (key.isEmpty || seen.contains(key)) return false;
            seen.add(key);
            return true;
          })
          .toList(growable: false);
    }
    _cachedVisibleComments = _applyDensity(
      visibleComments,
      density.clamp(0.2, 1.0),
    );
    return _cachedVisibleComments;
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
    for (var i = 0; i < id.length; i++) {
      hash = ((hash * 33) ^ id.codeUnitAt(i)) & 0x7fffffff;
    }
    return hash % _densityBucketScale;
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

  String _buildOptionSignature(
    DanmakuSettings settings, {
    required int visibleCommentCount,
  }) {
    return <Object>[
      settings.fontScale,
      settings.speed,
      settings.displayAreaRatio,
      settings.opacity,
      settings.topEnabled,
      settings.bottomEnabled,
      settings.scrollEnabled,
      settings.avoidSubtitleArea,
      visibleCommentCount >= _massiveModeThreshold,
    ].join('|');
  }

  cd.DanmakuOption _buildOption(
    DanmakuSettings settings, {
    required int visibleCommentCount,
  }) {
    final durationSeconds = (8.5 / settings.speed).clamp(3.2, 8.5);
    final fontSize = math.max(16.0, 24.0 * settings.fontScale);
    return cd.DanmakuOption(
      fontSize: fontSize,
      fontWeight: 7,
      area: settings.displayAreaRatio.clamp(0.1, 1.0),
      duration: durationSeconds,
      staticDuration: 2.6,
      opacity: settings.opacity.clamp(0.2, 1.0),
      hideTop: !settings.topEnabled,
      hideBottom: !settings.bottomEnabled,
      hideScroll: !settings.scrollEnabled,
      hideSpecial: true,
      strokeWidth: 0.9,
      massiveMode: visibleCommentCount >= _massiveModeThreshold,
      safeArea: settings.avoidSubtitleArea,
      lineHeight: 1.0,
    );
  }

  cd.DanmakuContentItem<DanmakuComment> _mapComment(
    DanmakuComment comment,
    DanmakuSettings settings,
  ) {
    final color = settings.colorEnabled ? comment.color : Colors.white;
    return cd.DanmakuContentItem<DanmakuComment>(
      comment.text,
      color: color,
      type: switch (comment.type) {
        DanmakuCommentType.top => cd.DanmakuItemType.top,
        DanmakuCommentType.bottom => cd.DanmakuItemType.bottom,
        DanmakuCommentType.scroll => cd.DanmakuItemType.scroll,
      },
      isColorful: color != Colors.white,
      extra: comment,
    );
  }
}
