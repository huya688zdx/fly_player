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

/// 飞牛按条目保存的片头片尾跳过配置（单位秒，对应 play.setConfigByItem 的
/// skip_opening / skip_ending）。
class DesktopIntroOutroConfig {
  const DesktopIntroOutroConfig({
    required this.guid,
    this.introSeconds,
    this.outroSeconds,
  });

  /// 保存该配置的条目 guid（play_config.guid，缺省回退父条目）。
  final String guid;
  final int? introSeconds;
  final int? outroSeconds;
}

/// 只根据明确的片头/片尾名称识别；普通编号章节不猜测跳过范围。
/// [outroEnd] = ED 章节之后若还有其他章节，取下一章节起点（ED 后有正片/彩蛋时只跳片尾曲本身）；
/// ED 是最后一个章节时为 null，此时跳过会走到文件结尾。
({Duration? introStart, Duration? introEnd, Duration? outroStart, Duration? outroEnd})
desktopChapterSkipBounds(
  List<DesktopPlayerChapter> chapters,
  Duration duration,
) {
  Duration? introStart;
  Duration? introEnd;
  Duration? outroStart;
  var outroIndex = -1;
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
      outroIndex = index;
    }
  }
  Duration? outroEnd;
  if (outroIndex >= 0 && outroIndex + 1 < chapters.length) {
    final end = chapters[outroIndex + 1].position;
    if (outroStart != null && end > outroStart && end < duration) {
      outroEnd = end;
    }
  }
  return (
    introStart: introStart,
    introEnd: introEnd,
    outroStart: outroStart,
    outroEnd: outroEnd,
  );
}

/// 设置页和播放提示共用实际生效的范围；固定时长必须单独开启。
/// 固定时长单位为秒，与飞牛 `play.setConfigByItem` 的 skip_opening/skip_ending 一致。
/// [outroEnd] 非空时片尾跳过只到该边界（ED 章节后有其他内容），为空时覆盖到文件结尾。
typedef DesktopPlaybackSkipBounds =
    ({
      Duration? introStart,
      Duration? introEnd,
      Duration? outroStart,
      Duration? outroEnd,
      bool introFromChapter,
      bool outroFromChapter,
    });

({
  Duration? introStart,
  Duration? introEnd,
  Duration? outroStart,
  Duration? outroEnd,
  bool introFromChapter,
  bool outroFromChapter,
})
desktopPlaybackSkipBounds(
  List<DesktopPlayerChapter> chapters,
  Duration duration, {
  required bool chapterEnabled,
  required bool fixedDurationEnabled,
  required int introSeconds,
  required int outroSeconds,
}) {
  final detected = desktopChapterSkipBounds(
    chapterEnabled ? chapters : const [],
    duration,
  );
  var introStart = detected.introStart;
  var introEnd = detected.introEnd;
  var outroStart = detected.outroStart;
  var outroEnd = detected.outroEnd;
  if (fixedDurationEnabled && duration > Duration.zero) {
    if (introEnd == null && introSeconds > 0) {
      introStart = Duration.zero;
      introEnd = Duration(seconds: introSeconds);
    }
    if (outroStart == null && outroSeconds > 0) {
      outroStart = duration - Duration(seconds: outroSeconds);
    }
  }
  if (introEnd != null &&
      (introEnd <= const Duration(seconds: 2) || introEnd >= duration)) {
    introStart = introEnd = null;
  }
  if (outroStart != null &&
      (outroStart <= Duration.zero || outroStart >= duration)) {
    outroStart = null;
  }
  if (outroEnd != null &&
      (outroStart == null || outroEnd <= outroStart || outroEnd >= duration)) {
    outroEnd = null;
  }
  if (introEnd != null && outroStart != null && introEnd >= outroStart) {
    introStart = introEnd = outroStart = null;
    outroEnd = null;
  }
  return (
    introStart: introStart,
    introEnd: introEnd,
    outroStart: outroStart,
    outroEnd: outroEnd,
    introFromChapter: detected.introEnd != null,
    outroFromChapter: detected.outroStart != null,
  );
}

/// 自动跳过模式下的执行时间点：提示出现位置 + 倒计时，但不早于范围起点、
/// 不晚于范围终点（范围比倒计时短时在终点执行）。倒计时基于播放位置，暂停即冻结。
/// 桌面端与安卓 nativeSkipAutoAdvanceAtMs 语义一致。
Duration? desktopSkipAutoAdvanceAt({
  required bool intro,
  required DesktopPlaybackSkipBounds bounds,
  required Duration shownPosition,
  required int countdownSeconds,
  required Duration duration,
}) {
  final lead = Duration(seconds: countdownSeconds);
  if (intro) {
    final end = bounds.introEnd;
    if (end == null) return null;
    final start = bounds.introStart ?? Duration.zero;
    var at = shownPosition + lead;
    if (start > at) at = start;
    if (at > end) at = end;
    return at;
  }
  final start = bounds.outroStart;
  if (start == null) return null;
  var at = shownPosition + lead;
  if (start > at) at = start;
  final end = bounds.outroEnd ?? duration;
  if (at > end) at = end;
  return at;
}

/// 拖动进度条的轻微吸附：落点距章节线或跳过窗口边界不足 [radius] 时贴到该标记，
/// 只在很靠近时生效，远离标记的微调不受影响。无命中时原样返回。
Duration snapSeekTargetToMarkers(
  Duration target,
  Iterable<Duration> markers, {
  Duration radius = const Duration(seconds: 3),
}) {
  Duration? best;
  var bestDelta = radius;
  for (final marker in markers) {
    final delta = (marker - target).abs();
    if (delta < bestDelta) {
      bestDelta = delta;
      best = marker;
    }
  }
  return best ?? target;
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
