import 'dart:io';

import '../api/feiniu_api.dart';
import '../playback/playback_source.dart';

/// mpv 不读取 HLS 的 WebVTT rendition；按整片时间预取小窗口，交给 libass。
/// 每个播放宿主持有一份，仅由飞牛分支接线。
class FeiniuSegmentedSubtitle {
  FeiniuSegmentedSubtitle(this.api);

  final FeiniuApi api;
  String _key = '';
  List<({String path, double start, double end})> _segments = [];
  final Map<String, String> _texts = {};
  Directory? _directory;
  String _lastBody = '';
  int _revision = 0;

  Future<String?>? _pending;
  bool _disposed = false;

  Future<String?> resolve(MpvMediaSource source, Duration position) {
    if (_disposed || _pending != null) return Future.value(null);
    final pending = _resolve(source, position);
    _pending = pending;
    return pending.whenComplete(() => _pending = null);
  }

  Future<String?> _resolve(MpvMediaSource source, Duration position) async {
    final track = source.subtitleTracks
        .where((track) => track.guid == source.subtitleTrackGuid)
        .firstOrNull;
    final link = source.playLink ?? '';
    if (!source.playbackMode.isServerManaged ||
        link.isEmpty ||
        track == null ||
        track.isExternal == 1 ||
        track.extraFile == 1 ||
        track.isBitmap == 1 ||
        track.guid.startsWith('local:') ||
        {'sup', 'pgs', 'dvb', 'sub'}.contains(track.format.toLowerCase())) {
      return null;
    }
    final key = '$link|${track.guid}|${source.loadNonce}';
    if (_key != key) {
      _key = key;
      _segments = [];
      _texts.clear();
      _lastBody = '';
    }
    try {
      if (_segments.isEmpty) {
        final master = await api.readServerSubtitleResource(link);
        final rendition = master
            .split('\n')
            .where(
              (line) =>
                  line.startsWith('#EXT-X-MEDIA:') &&
                  line.contains('TYPE=SUBTITLES'),
            );
        if (rendition.isEmpty) return null;
        final path = RegExp(
          r'URI="([^"]+)"',
        ).firstMatch(rendition.first)?.group(1);
        if (path == null) return null;
        final playlistUri = Uri.parse(link).resolve(path);
        final playlist = await api.readServerSubtitleResource(
          playlistUri.toString(),
        );
        double cursor = 0;
        double duration = 0;
        for (final raw in playlist.split('\n')) {
          final line = raw.trim();
          if (line.startsWith('#EXTINF:')) {
            duration = double.tryParse(line.substring(8).split(',').first) ?? 0;
          } else if (line.isNotEmpty && !line.startsWith('#') && duration > 0) {
            _segments.add((
              path: playlistUri.resolve(line).toString(),
              start: cursor,
              end: cursor + duration,
            ));
            cursor += duration;
            duration = 0;
          }
        }
      }
      final seconds = position.inMilliseconds / 1000;
      final window = _segments
          .where(
            (segment) =>
                segment.end > seconds - 4 && segment.start < seconds + 16,
          )
          .toList();
      // 起播前的分段可能未生成；失败的分段留到下一次刷新重试。
      await Future.wait(
        window.map((segment) async {
          if (_texts.containsKey(segment.path)) return;
          try {
            final text = await api.readServerSubtitleResource(segment.path);
            if (text.trimLeft().startsWith('WEBVTT')) {
              _texts[segment.path] = text;
            }
          } catch (_) {
            // 不让单个尚未生成的分段阻塞播放。
          }
        }),
      );
      final paths = window.map((segment) => segment.path).toSet();
      _texts.removeWhere((path, _) => !paths.contains(path));
      final body = mergeSegments(
        window.map((segment) => _texts[segment.path] ?? ''),
      );
      if (_texts.isEmpty || body == _lastBody) return null;
      _directory ??= await Directory.systemTemp.createTemp('fly_feiniu_sub_');
      final file = File('${_directory!.path}/window_${_revision % 2}.vtt');
      await file.writeAsString(body, flush: true);
      _revision++;
      _lastBody = body;
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// 飞牛分段已使用整片时间轴，跨分段重复的 cue 只保留一次。
  static String mergeSegments(Iterable<String> segments) {
    final cues = <String>{};
    for (final text in segments) {
      for (final block in text.replaceAll('\r', '').split(RegExp(r'\n\s*\n'))) {
        if (block.contains(' --> ')) cues.add(block.trim());
      }
    }
    return 'WEBVTT\n\n${cues.join('\n\n')}\n';
  }

  Future<void> dispose() async {
    _disposed = true;
    await _pending;
    final directory = _directory;
    _directory = null;
    try {
      if (directory != null && await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } on FileSystemException {
      // 内核仍占用临时文件时，不阻止播放页退出。
    }
  }
}
