import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// 播放器章节条目（来自 mpv chapter-list）。
class DesktopPlayerChapter {
  const DesktopPlayerChapter({required this.title, required this.position});

  final String title;
  final Duration position;
}

final _introChapterTitle = RegExp(
  r'(^|[^a-z])(op|opening|intro)(?=$|[^a-z])|片头|片頭',
  caseSensitive: false,
);
final _outroChapterTitle = RegExp(
  r'(^|[^a-z])(ed|ending|outro|credits)(?=$|[^a-z])|片尾',
  caseSensitive: false,
);

/// 只根据明确的片头/片尾名称识别；普通编号章节不猜测跳过范围。
({Duration? introStart, Duration? introEnd, Duration? outroStart})
desktopChapterSkipBounds(
  List<DesktopPlayerChapter> chapters,
  Duration duration,
) {
  Duration? introStart;
  Duration? introEnd;
  Duration? outroStart;
  for (var index = 0; index < chapters.length; index++) {
    final chapter = chapters[index];
    final start = chapter.position;
    if (start < Duration.zero || start >= duration) continue;
    if (introEnd == null &&
        _introChapterTitle.hasMatch(chapter.title) &&
        index + 1 < chapters.length) {
      final end = chapters[index + 1].position;
      if (end > start && end < duration) {
        introStart = start;
        introEnd = end;
      }
    }
    if (outroStart == null && _outroChapterTitle.hasMatch(chapter.title)) {
      outroStart = start;
    }
  }
  return (introStart: introStart, introEnd: introEnd, outroStart: outroStart);
}

/// 设置页和播放提示共用实际生效的范围；固定时长必须单独开启。
({
  Duration? introStart,
  Duration? introEnd,
  Duration? outroStart,
  bool introFromChapter,
  bool outroFromChapter,
})
desktopPlaybackSkipBounds(
  List<DesktopPlayerChapter> chapters,
  Duration duration, {
  required bool chapterEnabled,
  required bool fixedDurationEnabled,
  required int introMinutes,
  required int outroMinutes,
}) {
  final detected = desktopChapterSkipBounds(
    chapterEnabled ? chapters : const [],
    duration,
  );
  var introStart = detected.introStart;
  var introEnd = detected.introEnd;
  var outroStart = detected.outroStart;
  if (fixedDurationEnabled && duration > Duration.zero) {
    if (introEnd == null) {
      introStart = Duration.zero;
      introEnd = Duration(minutes: introMinutes);
    }
    outroStart ??= duration - Duration(minutes: outroMinutes);
  }
  if (introEnd != null &&
      (introEnd <= const Duration(seconds: 2) || introEnd >= duration)) {
    introStart = introEnd = null;
  }
  if (outroStart != null &&
      (outroStart <= Duration.zero || outroStart >= duration)) {
    outroStart = null;
  }
  if (introEnd != null && outroStart != null && introEnd >= outroStart) {
    introStart = introEnd = outroStart = null;
  }
  return (
    introStart: introStart,
    introEnd: introEnd,
    outroStart: outroStart,
    introFromChapter: detected.introEnd != null,
    outroFromChapter: detected.outroStart != null,
  );
}

/// 每个媒体只读一次章节，文件头尚未就绪时最多补读一次。
/// 换源和退出均使旧读取失效，并取消尚未开始的补读。
class DesktopPlaybackChapters
    extends ValueNotifier<List<DesktopPlayerChapter>> {
  DesktopPlaybackChapters(this.readChapters) : super(const []);

  final Future<String> Function() readChapters;
  Timer? _retryTimer;
  int _generation = 0;
  bool _requested = false;

  void load(Duration duration) {
    if (duration <= Duration.zero || _requested) return;
    _requested = true;
    unawaited(_load(_generation, retry: true));
  }

  Future<void> _load(int generation, {required bool retry}) async {
    try {
      final decoded = jsonDecode(await readChapters());
      if (generation != _generation) return;
      final chapters = <DesktopPlayerChapter>[];
      if (decoded is List) {
        for (final item in decoded) {
          if (item is! Map || item['time'] is! num) continue;
          final seconds = (item['time'] as num).toDouble();
          if (!seconds.isFinite || seconds < 0) continue;
          chapters.add(
            DesktopPlayerChapter(
              title: '${item['title'] ?? ''}',
              position: Duration(milliseconds: (seconds * 1000).round()),
            ),
          );
        }
      }
      if (chapters.isNotEmpty) {
        value = List.unmodifiable(chapters);
        return;
      }
    } catch (_) {
      // 章节不可用不影响媒体播放，也不在后台无限轮询。
    }
    if (generation == _generation && retry) {
      _retryTimer = Timer(const Duration(milliseconds: 2500), () {
        if (generation == _generation) {
          unawaited(_load(generation, retry: false));
        }
      });
    }
  }

  void reset() {
    _generation++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _requested = false;
    if (value.isNotEmpty) value = const [];
  }

  @override
  void dispose() {
    _generation++;
    _retryTimer?.cancel();
    super.dispose();
  }
}
