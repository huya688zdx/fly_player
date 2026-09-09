import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// 播放器章节条目（来自 mpv chapter-list）。
class DesktopPlayerChapter {
  const DesktopPlayerChapter({required this.title, required this.position});

  final String title;
  final Duration position;
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
      if (chapters.isNotEmpty) value = List.unmodifiable(chapters);
      if (chapters.isEmpty && retry) {
        _retryTimer = Timer(const Duration(milliseconds: 2500), () {
          if (generation == _generation) {
            unawaited(_load(generation, retry: false));
          }
        });
      }
    } catch (_) {
      // 章节不可用不影响媒体播放，也不在后台无限轮询。
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
