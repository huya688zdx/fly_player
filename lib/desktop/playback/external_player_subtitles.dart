import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../danmaku/models/danmaku_comment.dart';
import '../../danmaku/models/danmaku_settings.dart';
import 'desktop_danmaku_lane_tracker.dart';
import 'desktop_danmaku_overlay.dart';

/// 将当前字幕和弹幕合成同一条 ASS，供外部播放器同步播放、暂停和跳转。
class ExternalPlayerSubtitles {
  static Future<String?> prepare({
    required Directory directory,
    String? subtitlePath,
    String? danmakuPath,
    required DanmakuSettings settings,
    bool disableSubtitles = false,
    void Function(int count)? onDanmakuPrepared,
  }) async {
    if (disableSubtitles) subtitlePath = null;
    if (!settings.enabled ||
        danmakuPath == null ||
        !(settings.scrollEnabled ||
            settings.topEnabled ||
            settings.bottomEnabled)) {
      return subtitlePath ?? (disableSubtitles ? writeEmpty(directory) : null);
    }
    final payload = await DesktopDanmakuPayload.load(danmakuPath);
    if (payload.comments.isEmpty) {
      return subtitlePath ?? (disableSubtitles ? writeEmpty(directory) : null);
    }
    final prepared = await compute(_prepare, (
      directory: directory.path,
      subtitle: subtitlePath,
      comments: payload.comments,
      settings: settings,
    ));
    if (prepared != null && prepared != subtitlePath) {
      onDanmakuPrepared?.call(payload.comments.length);
    }
    return prepared ?? (disableSubtitles ? writeEmpty(directory) : null);
  }

  /// 空 ASS 作为本次媒体的字幕轨，覆盖播放器自动选中的内封字幕。
  static Future<String> writeEmpty(Directory directory) async {
    await directory.create(recursive: true);
    final file = File('${directory.path}/subtitles_off.ass');
    await file.writeAsString(_emptyAss, flush: true);
    return file.path;
  }
}

typedef _ExportInput = ({
  String directory,
  String? subtitle,
  List<DanmakuComment> comments,
  DanmakuSettings settings,
});

Future<String?> _prepare(_ExportInput input) async {
  final subtitlePath = input.subtitle;
  var source = _emptyAss;
  String? plainSubtitle;
  if (subtitlePath != null) {
    final extension = subtitlePath.split('.').last.toLowerCase();
    if (!const ['ass', 'srt', 'vtt'].contains(extension)) {
      throw UnsupportedError(
        '暂不支持将 .$extension 字幕与弹幕合并，请选择 ASS、SRT 或 VTT 字幕，或关闭弹幕。',
      );
    }
    final text = await _readSubtitle(File(subtitlePath));
    if (extension == 'ass') {
      source = text;
    } else {
      plainSubtitle = text;
    }
  }
  final document = _AssDocument(source);
  final styleName = document.uniqueStyle('FlyPlayerDanmaku');
  final events = _danmakuEvents(input, document, styleName);
  if (events.isEmpty) return subtitlePath;
  document.addStyle(styleName, fontSize: 22 * document.height / 720);
  if (plainSubtitle != null) {
    document.addEvents(_plainSubtitleEvents(plainSubtitle, document));
  }
  document.addEvents(events);
  final directory = await Directory(input.directory).create(recursive: true);
  final file = File('${directory.path}${Platform.pathSeparator}playback.ass');
  await file.writeAsString(document.lines.join('\n'), flush: true);
  return file.path;
}

Future<String> _readSubtitle(File file) async {
  final bytes = await file.readAsBytes();
  if (bytes.length >= 2 &&
      ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
          (bytes[0] == 0xfe && bytes[1] == 0xff))) {
    if (bytes.length.isOdd) throw const FormatException('UTF-16 字幕内容不完整。');
    final littleEndian = bytes[0] == 0xff;
    return String.fromCharCodes([
      for (var i = 2; i < bytes.length; i += 2)
        littleEndian
            ? bytes[i] | bytes[i + 1] << 8
            : bytes[i] << 8 | bytes[i + 1],
    ]);
  }
  try {
    return utf8.decode(bytes).replaceFirst('\uFEFF', '');
  } on FormatException {
    throw const FormatException('合并字幕需要 UTF-8 或 UTF-16 编码，请先转换字幕编码。');
  }
}

List<String> _danmakuEvents(
  _ExportInput input,
  _AssDocument document,
  String style,
) {
  final settings = input.settings;
  final scale = document.height / 720;
  final fontSize = (22 * settings.fontScale).clamp(13.0, 36.0) * scale;
  final border = 2.2 * settings.fontThickness * scale;
  final laneHeight = fontSize * 1.2 + border + 6 * scale;
  var area = document.height * settings.displayAreaRatio;
  if (settings.avoidSubtitleArea) area = math.min(area, document.height * .76);
  if (settings.avoidCenterArea) area = math.min(area, document.height * .46);
  final count = math.max(
    1,
    (math.max(1, (area / laneHeight).floor()) * settings.density.clamp(.2, 1))
        .round(),
  );
  final stride = count > 1
      ? math.max(laneHeight, (area - laneHeight) / (count - 1))
      : 0.0;
  final tracker = DanmakuLaneTracker();
  final duplicateUntil = <String, int>{};
  final events = <String>[];
  final scrollDuration = (9000 / clampDanmakuSpeed(settings.speed)).round();
  final fixedDuration = (4200 / clampDanmakuSpeed(settings.speed)).round();
  final alpha = ((1 - settings.opacity.clamp(.1, 1)) * 255).round();
  for (final comment in input.comments) {
    final enabled = switch (comment.type) {
      DanmakuCommentType.scroll => settings.scrollEnabled,
      DanmakuCommentType.top => settings.topEnabled,
      DanmakuCommentType.bottom => settings.bottomEnabled,
    };
    if (!enabled || comment.timeMs < 0) continue;
    final plainText = comment.text.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
    if (plainText.isEmpty) continue;
    final duplicateKey = plainText.toLowerCase();
    if (settings.hideDuplicate &&
        (duplicateUntil[duplicateKey] ?? -1) > comment.timeMs) {
      continue;
    }
    final scrolling = comment.type == DanmakuCommentType.scroll;
    final duration = scrolling ? scrollDuration : fixedDuration;
    // 工作 isolate 不调用字体排版；按每个字符 1.2 em 保守占位，避免通常字体下追尾。
    final naturalWidth = plainText.runes.length * fontSize * 1.2 + border * 2;
    final width = math.min(naturalWidth, document.width * .9);
    final horizontalScale = math.min(100.0, width / naturalWidth * 100);
    tracker.beginFrame(
      comments: input.comments,
      settings: settings,
      laneCount: count,
      canvasWidth: document.width,
      oldestTimeMs: comment.timeMs - math.max(scrollDuration, fixedDuration),
    );
    final lane = scrolling
        ? tracker.laneForScroll(
            comment: comment,
            nowMs: comment.timeMs,
            width: width,
            canvasWidth: document.width,
            lifetimeMs: duration,
            gapPx: 20 * scale,
          )
        : tracker.laneForFixed(
            comment: comment,
            nowMs: comment.timeMs,
            lifetimeMs: duration,
          );
    if (lane < 0) continue;
    duplicateUntil[duplicateKey] = comment.timeMs + duration;
    final row = comment.type == DanmakuCommentType.bottom
        ? count - 1 - lane
        : lane;
    final y = _number(row * stride + border / 2 + 2 * scale);
    final position = scrolling
        ? '\\an7\\move(${_number(document.width)},$y,${_number(-width)},$y)'
        : '\\an8\\pos(${_number(document.width / 2)},$y)';
    final color = settings.colorEnabled ? comment.color.toARGB32() : 0xffffffff;
    final bgr = (color & 0xff) << 16 | (color & 0xff00) | (color >> 16 & 0xff);
    final tags =
        '$position\\q2\\fs${_number(fontSize)}'
        '\\fscx${_number(horizontalScale)}\\bord${_number(border)}'
        '\\b${settings.fontThickness >= 1.2 ? 1 : 0}'
        '\\alpha&H${_hex(alpha, 2)}&\\c&H${_hex(bgr, 6)}&';
    events.add(
      document.event(
        comment.timeMs,
        comment.timeMs + duration,
        style,
        '{$tags}${_escapeText(plainText)}',
      ),
    );
  }
  return events;
}

List<String> _plainSubtitleEvents(String source, _AssDocument document) {
  final events = <String>[];
  final timing = RegExp(
    r'^((?:\d+:)?\d{2}:\d{2}[.,]\d{3})\s+-->\s+((?:\d+:)?\d{2}:\d{2}[.,]\d{3})(?:\s+.*)?$',
  );
  for (final block
      in source.replaceAll('\r', '').split(RegExp(r'\n[ \t]*\n'))) {
    final lines = block.trim().split('\n');
    if (RegExp(r'^(NOTE|STYLE|REGION)(\s|$)').hasMatch(lines.first)) continue;
    final index = lines.indexWhere((line) => timing.hasMatch(line.trim()));
    if (index < 0) {
      if (block.contains('-->')) throw const FormatException('字幕包含无法读取的时间轴。');
      continue;
    }
    final match = timing.firstMatch(lines[index].trim())!;
    final start = _parseTime(match[1]!);
    final end = _parseTime(match[2]!);
    if (end <= start) throw const FormatException('字幕结束时间必须晚于开始时间。');
    final text = lines
        .skip(index + 1)
        .join('\n')
        .replaceAll(RegExp(r'<[^>]*>'), '');
    if (text.isEmpty) continue;
    events.add(
      document.event(start, end, 'Default', _escapeText(_decodeEntities(text))),
    );
  }
  if (events.isEmpty && source.trim().isNotEmpty) {
    throw const FormatException('未能读取 SRT/VTT 字幕时间轴，无法合并弹幕。');
  }
  return events;
}

String _decodeEntities(String text) => text.replaceAllMapped(
  RegExp(r'&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos|nbsp);'),
  (match) {
    final entity = match[1]!;
    if (entity.startsWith('#')) {
      final code = entity.startsWith('#x')
          ? int.tryParse(entity.substring(2), radix: 16)
          : int.tryParse(entity.substring(1));
      return code != null && code > 0 && code <= 0x10ffff
          ? String.fromCharCode(code)
          : '';
    }
    return const {
      'amp': '&',
      'lt': '<',
      'gt': '>',
      'quot': '"',
      'apos': "'",
      'nbsp': ' ',
    }[entity]!;
  },
);

// ASS 各渲染器对转义花括号的解释不一致，使用全角字符阻止外部文本注入标签。
String _escapeText(String text) => text
    .replaceAll('\\', '＼')
    .replaceAll('{', '｛')
    .replaceAll('}', '｝')
    .replaceAll(RegExp(r'[\x00-\x08\x0b-\x1f]'), '')
    .replaceAll('\n', r'\N');

int _parseTime(String text) {
  final parts = text.replaceAll(',', '.').split(':');
  final seconds = double.parse(parts.removeLast());
  final minutes = int.parse(parts.removeLast());
  final hours = parts.isEmpty ? 0 : int.parse(parts.single);
  return ((hours * 3600 + minutes * 60 + seconds) * 1000).round();
}

String _time(int ms) {
  final cs = ms ~/ 10;
  String two(int value) => value.toString().padLeft(2, '0');
  return '${cs ~/ 360000}:${two(cs ~/ 6000 % 60)}:${two(cs ~/ 100 % 60)}.${two(cs % 100)}';
}

String _number(num value) => value.toStringAsFixed(2);
String _hex(int value, int length) =>
    value.toRadixString(16).padLeft(length, '0').toUpperCase();

class _AssDocument {
  _AssDocument(String source)
    : lines = source.replaceAll('\r', '').split('\n') {
    if (_section('script info') < 0 ||
        _section('v4+ styles') < 0 ||
        _section('events') < 0) {
      throw UnsupportedError('弹幕合并仅支持 ASS v4+ 字幕，不支持旧 SSA 或不完整的 ASS 文件。');
    }
    styleFormat = _format('v4+ styles');
    eventFormat = _format('events');
    if (!styleFormat.contains('name') ||
        !eventFormat.toSet().containsAll(['start', 'end', 'style', 'text']) ||
        eventFormat.last != 'text') {
      throw UnsupportedError('ASS 字幕格式字段不完整，无法安全合并弹幕。');
    }
    width = _resolution('PlayResX');
    height = _resolution('PlayResY');
    if (width == 0 && height == 0) {
      width = 384;
      height = 288;
    } else if (width == 0) {
      width = height == 1024 ? 1280 : height * 4 / 3;
    } else if (height == 0) {
      height = width == 1280 ? 1024 : width * 3 / 4;
    }
  }

  final List<String> lines;
  late final List<String> styleFormat;
  late final List<String> eventFormat;
  late double width;
  late double height;

  int _section(String name) =>
      lines.indexWhere((line) => line.trim().toLowerCase() == '[$name]');
  int _end(String name) {
    final index = lines.indexWhere(
      (line) => line.trim().startsWith('['),
      _section(name) + 1,
    );
    return index < 0 ? lines.length : index;
  }

  List<String> _format(String section) {
    final formats = lines
        .sublist(_section(section) + 1, _end(section))
        .where((line) => line.trimLeft().toLowerCase().startsWith('format:'));
    if (formats.isEmpty) throw const FormatException('ASS 字幕缺少 Format 字段。');
    return formats.last
        .substring(formats.last.indexOf(':') + 1)
        .split(',')
        .map((field) => field.trim().toLowerCase())
        .toList();
  }

  double _resolution(String key) {
    for (final line in lines.sublist(
      _section('script info') + 1,
      _end('script info'),
    )) {
      if (line.trimLeft().toLowerCase().startsWith('${key.toLowerCase()}:')) {
        final value = double.tryParse(
          line.substring(line.indexOf(':') + 1).trim(),
        );
        return value != null && value.isFinite && value > 0 ? value : 0;
      }
    }
    return 0;
  }

  String uniqueStyle(String base) {
    var name = base;
    var suffix = 1;
    while (lines.any((line) => line.contains(name))) {
      name = '$base${suffix++}';
    }
    return name;
  }

  void addStyle(String name, {required double fontSize}) {
    final values = <String, String>{
      'name': name,
      'fontname': 'Microsoft YaHei',
      'fontsize': _number(fontSize),
      'primarycolour': '&H00FFFFFF',
      'secondarycolour': '&H00FFFFFF',
      'outlinecolour': '&H00000000',
      'backcolour': '&H00000000',
      'scalex': '100',
      'scaley': '100',
      'borderstyle': '1',
      'outline': '2',
      'alignment': '7',
      'encoding': '1',
    };
    lines.insert(
      _end('v4+ styles'),
      'Style: ${styleFormat.map((key) => values[key] ?? '0').join(',')}',
    );
  }

  String event(int start, int end, String style, String text) {
    final values = {
      'layer': '0',
      'start': _time(start),
      'end': _time(end),
      'style': style,
      'marginl': '0',
      'marginr': '0',
      'marginv': '0',
      'text': text,
    };
    return 'Dialogue: ${eventFormat.map((key) => values[key] ?? '').join(',')}';
  }

  void addEvents(List<String> events) =>
      lines.insertAll(_end('events'), events);
}

const _emptyAss = '''[Script Info]
ScriptType: v4.00+
PlayResX: 1280
PlayResY: 720
WrapStyle: 0
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Microsoft YaHei,32,&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,0,2,30,30,24,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
''';
