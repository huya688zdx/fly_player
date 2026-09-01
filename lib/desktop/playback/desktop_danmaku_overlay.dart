import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:media_kit/media_kit.dart';

import '../../danmaku/models/danmaku_comment.dart';
import '../../danmaku/models/danmaku_settings.dart';
import '../../danmaku/parser/danmaku_import_parser.dart';

class DesktopDanmakuPayload {
  const DesktopDanmakuPayload({
    required this.sourceLabel,
    required this.comments,
  });

  final String sourceLabel;
  final List<DanmakuComment> comments;

  static Future<DesktopDanmakuPayload> load(String path) async {
    final file = File(path);
    final raw = await file.readAsString();
    final normalized = raw.trimLeft();
    final decoded = normalized.startsWith('{') || normalized.startsWith('[')
        ? jsonDecode(raw)
        : null;
    if (decoded is Map && decoded['commentsCompact'] is List) {
      final comments = <DanmakuComment>[];
      for (final rawComment in decoded['commentsCompact'] as List) {
        if (rawComment is! List || rawComment.length < 5) continue;
        final text = '${rawComment[2] ?? ''}'.trim();
        if (text.isEmpty) continue;
        comments.add(
          DanmakuComment(
            id: '${rawComment[0] ?? ''}',
            timeMs: (rawComment[1] as num?)?.toInt() ?? 0,
            text: text,
            type: switch ((rawComment[3] as num?)?.toInt() ?? 0) {
              1 => DanmakuCommentType.top,
              2 => DanmakuCommentType.bottom,
              _ => DanmakuCommentType.scroll,
            },
            color: Color((rawComment[4] as num?)?.toInt() ?? 0xFFFFFFFF),
          ),
        );
      }
      comments.sort((left, right) => left.timeMs.compareTo(right.timeMs));
      return DesktopDanmakuPayload(
        sourceLabel: '${decoded['sourceKey'] ?? file.uri.pathSegments.last}',
        comments: List<DanmakuComment>.unmodifiable(comments),
      );
    }
    final result = await DanmakuImportParser.parseFile(path);
    return DesktopDanmakuPayload(
      sourceLabel: result.sourceLabel,
      comments: result.comments,
    );
  }
}

/// Windows 播放器的 Flutter 弹幕层。
///
/// 只使用一个 CustomPaint，并直接读取 media_kit 的播放时钟；不会为每条弹幕创建 Widget。
class DesktopDanmakuOverlay extends StatefulWidget {
  const DesktopDanmakuOverlay({
    super.key,
    required this.player,
    required this.comments,
    required this.settings,
  });

  final Player player;
  final List<DanmakuComment> comments;
  final DanmakuSettings settings;

  @override
  State<DesktopDanmakuOverlay> createState() => _DesktopDanmakuOverlayState();
}

class _DesktopDanmakuOverlayState extends State<DesktopDanmakuOverlay>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);
  late final Ticker _ticker;
  late final StreamSubscription<Duration> _positionSubscription;
  late final StreamSubscription<bool> _playingSubscription;
  late final StreamSubscription<double> _rateSubscription;

  Duration _anchorPosition = Duration.zero;
  Duration _anchorClock = Duration.zero;
  Duration _clock = Duration.zero;
  Duration _lastRepaintAt = Duration.zero;
  bool _playing = false;
  double _rate = 1;

  @override
  void initState() {
    super.initState();
    _anchorPosition = widget.player.state.position;
    _playing = widget.player.state.playing;
    _rate = widget.player.state.rate;
    _ticker = createTicker(_onTick)..start();
    _positionSubscription = widget.player.stream.position.listen((position) {
      _anchorPosition = position;
      _anchorClock = _clock;
      _repaint.value += 1;
    });
    _playingSubscription = widget.player.stream.playing.listen((playing) {
      _anchorPosition = _currentPosition();
      _anchorClock = _clock;
      _playing = playing;
      _repaint.value += 1;
    });
    _rateSubscription = widget.player.stream.rate.listen((rate) {
      _anchorPosition = _currentPosition();
      _anchorClock = _clock;
      _rate = rate.isFinite && rate > 0 ? rate : 1;
    });
  }

  void _onTick(Duration elapsed) {
    _clock = elapsed;
    if (!_playing || !widget.settings.enabled || widget.comments.isEmpty) {
      return;
    }
    final fps = normalizeDanmakuFrameRateHz(widget.settings.targetFrameRateHz);
    final minimumInterval = Duration(microseconds: 1000000 ~/ fps);
    if (elapsed - _lastRepaintAt < minimumInterval) return;
    _lastRepaintAt = elapsed;
    _repaint.value += 1;
  }

  Duration _currentPosition() {
    if (!_playing) return _anchorPosition;
    final elapsed = _clock - _anchorClock;
    return _anchorPosition +
        Duration(microseconds: (elapsed.inMicroseconds * _rate).round());
  }

  @override
  void dispose() {
    _ticker.dispose();
    unawaited(_positionSubscription.cancel());
    unawaited(_playingSubscription.cancel());
    unawaited(_rateSubscription.cancel());
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.settings.enabled || widget.comments.isEmpty) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _DesktopDanmakuPainter(
            comments: widget.comments,
            settings: widget.settings,
            positionProvider: _currentPosition,
            repaint: _repaint,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _DesktopDanmakuPainter extends CustomPainter {
  _DesktopDanmakuPainter({
    required this.comments,
    required this.settings,
    required this.positionProvider,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final List<DanmakuComment> comments;
  final DanmakuSettings settings;
  final Duration Function() positionProvider;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || comments.isEmpty) return;
    final nowMs = positionProvider().inMilliseconds;
    final scrollLifetimeMs = (9000 / settings.speed).round();
    final fixedLifetimeMs = (4200 / settings.speed).round();
    final maximumLifetimeMs = math.max(scrollLifetimeMs, fixedLifetimeMs);
    final fontSize = (22 * settings.fontScale).clamp(13.0, 36.0).toDouble();
    final laneHeight = fontSize + 10;
    var areaHeight = size.height * settings.displayAreaRatio;
    if (settings.avoidSubtitleArea) {
      areaHeight = math.min(areaHeight, size.height * 0.76);
    }
    if (settings.avoidCenterArea) {
      areaHeight = math.min(areaHeight, size.height * 0.46);
    }
    final rawLaneCount = math.max(1, (areaHeight / laneHeight).floor());
    final laneCount = math.max(
      1,
      (rawLaneCount * settings.density.clamp(0.2, 1.0)).round(),
    );
    final scrollRects = List<List<Rect>>.generate(laneCount, (_) => <Rect>[]);
    final topLanes = List<bool>.filled(laneCount, false);
    final bottomLanes = List<bool>.filled(laneCount, false);
    final duplicateTexts = <String>{};

    var index = _lowerBound(nowMs - maximumLifetimeMs);
    while (index < comments.length) {
      final comment = comments[index++];
      if (comment.timeMs > nowMs) break;
      if (!_typeEnabled(comment.type)) continue;
      final ageMs = nowMs - comment.timeMs;
      final lifetimeMs = comment.type == DanmakuCommentType.scroll
          ? scrollLifetimeMs
          : fixedLifetimeMs;
      if (ageMs < 0 || ageMs >= lifetimeMs) continue;
      final normalizedText = comment.text.trim().toLowerCase();
      if (settings.hideDuplicate && !duplicateTexts.add(normalizedText)) {
        continue;
      }
      final textPainter = _textPainter(comment, fontSize, stroke: false)
        ..layout(maxWidth: size.width * 0.72);
      final progress = ageMs / lifetimeMs;
      Offset? offset;
      if (comment.type == DanmakuCommentType.scroll) {
        final x = size.width - progress * (size.width + textPainter.width);
        final rect = Rect.fromLTWH(x, 0, textPainter.width, textPainter.height);
        for (var lane = 0; lane < laneCount; lane++) {
          final laneRect = rect.shift(Offset(0, lane * laneHeight));
          if (scrollRects[lane].any(
            (other) => other.inflate(20).overlaps(laneRect),
          )) {
            continue;
          }
          scrollRects[lane].add(laneRect);
          offset = laneRect.topLeft;
          break;
        }
      } else {
        final occupied = comment.type == DanmakuCommentType.top
            ? topLanes
            : bottomLanes;
        final lane = occupied.indexOf(false);
        if (lane >= 0) {
          occupied[lane] = true;
          final y = comment.type == DanmakuCommentType.top
              ? lane * laneHeight
              : areaHeight - ((lane + 1) * laneHeight);
          offset = Offset((size.width - textPainter.width) / 2, math.max(0, y));
        }
      }
      if (offset == null) continue;
      final strokePainter = _textPainter(comment, fontSize, stroke: true)
        ..layout(maxWidth: size.width * 0.72);
      strokePainter.paint(canvas, offset);
      textPainter.paint(canvas, offset);
    }
  }

  TextPainter _textPainter(
    DanmakuComment comment,
    double fontSize, {
    required bool stroke,
  }) {
    final alpha = (settings.opacity.clamp(0.1, 1.0) * 255).round();
    final baseColor = settings.colorEnabled ? comment.color : Colors.white;
    final paint = Paint()
      ..color = stroke
          ? Colors.black.withAlpha((alpha * 0.82).round())
          : baseColor.withAlpha(alpha)
      ..style = stroke ? PaintingStyle.stroke : PaintingStyle.fill
      ..strokeWidth = 2.2 * settings.fontThickness;
    return TextPainter(
      text: TextSpan(
        text: comment.text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: settings.fontThickness >= 1.2
              ? FontWeight.w700
              : FontWeight.w600,
          height: 1.05,
          foreground: paint,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      ellipsis: '…',
    );
  }

  bool _typeEnabled(DanmakuCommentType type) => switch (type) {
    DanmakuCommentType.scroll => settings.scrollEnabled,
    DanmakuCommentType.top => settings.topEnabled,
    DanmakuCommentType.bottom => settings.bottomEnabled,
  };

  int _lowerBound(int targetMs) {
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

  @override
  bool shouldRepaint(covariant _DesktopDanmakuPainter oldDelegate) {
    return oldDelegate.comments != comments || oldDelegate.settings != settings;
  }
}
