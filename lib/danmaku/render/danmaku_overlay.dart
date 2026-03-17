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
  cd.DanmakuController<DanmakuComment>? _engineController;
  List<DanmakuComment> _cachedSourceComments = const <DanmakuComment>[];
  List<DanmakuComment> _cachedVisibleComments = const <DanmakuComment>[];
  bool _cachedHideDuplicate = false;
  List<DanmakuComment> _scheduledComments = const <DanmakuComment>[];
  final Set<String> _emittedCommentIds = <String>{};
  int _lastScheduledPositionMs = 0;

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
    return IgnorePointer(
      child: RepaintBoundary(
        child: cd.DanmakuScreen<DanmakuComment>(
          key: const ValueKey<String>('canvas_danmaku_overlay'),
          option: _buildOption(settings),
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

    engine.updateOption(_buildOption(settings));
    if (widget.paused) {
      engine.pause();
    } else {
      engine.resume();
    }

    final comments = _resolveVisibleComments(
      widget.controller.comments,
      hideDuplicate: settings.hideDuplicate,
    );
    final sourceChanged = forceSourceReset || !identical(comments, _scheduledComments);
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
  }) {
    if (identical(sourceComments, _cachedSourceComments) &&
        hideDuplicate == _cachedHideDuplicate) {
      return _cachedVisibleComments;
    }
    _cachedSourceComments = sourceComments;
    _cachedHideDuplicate = hideDuplicate;
    if (!hideDuplicate || sourceComments.isEmpty) {
      _cachedVisibleComments = sourceComments;
      return _cachedVisibleComments;
    }
    final seen = <String>{};
    _cachedVisibleComments = sourceComments.where((comment) {
      final key = comment.text.trim();
      if (key.isEmpty || seen.contains(key)) return false;
      seen.add(key);
      return true;
    }).toList(growable: false);
    return _cachedVisibleComments;
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

  cd.DanmakuOption _buildOption(DanmakuSettings settings) {
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
      massiveMode: false,
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
