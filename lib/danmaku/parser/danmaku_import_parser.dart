import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/danmaku_comment.dart';
import '../models/danmaku_import_result.dart';

class DanmakuImportParser {
  static DanmakuImportResult parseXmlString(
    String content, {
    String sourceLabel = 'Network Danmaku',
  }) {
    final comments = _parseXmlComments(content);
    if (comments.isEmpty) {
      throw const FormatException('No usable danmaku comments were recognized');
    }
    return DanmakuImportResult(sourceLabel: sourceLabel, comments: comments);
  }

  static DanmakuImportResult parseContentString(
    String content, {
    String sourceLabel = 'Network Danmaku',
  }) {
    final comments = _parseContentComments(content);
    if (comments.isEmpty) {
      throw _buildContentFormatException(content);
    }
    return DanmakuImportResult(sourceLabel: sourceLabel, comments: comments);
  }

  static Future<DanmakuImportResult> parseFile(String path) async {
    final payload = await Isolate.run<Map<String, Object?>>(
      () => _parseFilePayload(path),
    );
    return _decodePayload(payload);
  }

  static Future<DanmakuImportResult> parseBytes(
    Uint8List bytes, {
    required String fileName,
  }) async {
    final payload = await Isolate.run<Map<String, Object?>>(
      () => _parseBytesPayload(bytes, fileName),
    );
    return _decodePayload(payload);
  }

  static DanmakuImportResult _decodePayload(Map<String, Object?> payload) {
    final rawComments =
        (payload['comments'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<Object?, Object?>>()
            .toList(growable: false);
    final comments = rawComments
        .map(
          (item) => DanmakuComment(
            id: item['id'] as String? ?? '',
            timeMs: item['timeMs'] as int? ?? 0,
            text: item['text'] as String? ?? '',
            type: DanmakuCommentType.values[item['type'] as int? ?? 0],
            color: Color(item['color'] as int? ?? Colors.white.toARGB32()),
          ),
        )
        .toList(growable: false);
    return DanmakuImportResult(
      sourceLabel: payload['sourceLabel'] as String? ?? '',
      comments: comments,
    );
  }

  static List<DanmakuComment> _parseContentComments(String content) {
    final normalized = content.trim();
    if (normalized.isEmpty) {
      return const <DanmakuComment>[];
    }
    if (normalized.startsWith('{') || normalized.startsWith('[')) {
      return _parseJsonComments(normalized);
    }
    return _parseXmlComments(normalized);
  }

  static List<DanmakuComment> _parseXmlComments(String content) {
    if (content.contains('<i>') && content.contains('<d ')) {
      return _parseBilibiliXmlComments(content);
    }
    if (content.contains('<Danmaku') || content.contains('<item')) {
      return _parseDanDanPlayXmlComments(content);
    }
    return const <DanmakuComment>[];
  }

  static List<DanmakuComment> _parseBilibiliXmlComments(String content) {
    final regExp = RegExp(
      r'<d\s+[^>]*p="([^"]+)"[^>]*>(.*?)</d>',
      multiLine: true,
      dotAll: true,
    );
    final comments = <DanmakuComment>[];
    var index = 0;
    for (final match in regExp.allMatches(content)) {
      final p = match.group(1)?.trim() ?? '';
      final text = _decodeXmlEntities(match.group(2)?.trim() ?? '');
      if (p.isEmpty || text.isEmpty) continue;
      final parts = p.split(',');
      if (parts.length < 4) continue;
      final timeMs = ((double.tryParse(parts[0]) ?? 0) * 1000).round();
      final mode = int.tryParse(parts[1]) ?? 1;
      final colorValue = int.tryParse(parts[3]) ?? 0xFFFFFF;
      comments.add(
        DanmakuComment(
          id: 'xml-$index',
          timeMs: timeMs,
          text: text,
          type: _mapMode(mode),
          color: Color(0xFF000000 | colorValue),
        ),
      );
      index += 1;
    }
    return comments;
  }

  static List<DanmakuComment> _parseDanDanPlayXmlComments(String content) {
    final itemPattern = RegExp(
      r'<item\b([^>]*)\/?>',
      multiLine: true,
      dotAll: true,
    );
    final comments = <DanmakuComment>[];
    var index = 0;
    for (final match in itemPattern.allMatches(content)) {
      final attrs = match.group(1) ?? '';
      final text = _readXmlAttribute(attrs, 'text').trim();
      if (text.isEmpty) continue;
      final timeMs = _readTimeMs(_readXmlAttribute(attrs, 'time'));
      final mode = _readInt(_readXmlAttribute(attrs, 'mode'), fallback: 1);
      final color = _readColor(_readXmlAttribute(attrs, 'color'));
      comments.add(
        DanmakuComment(
          id: 'ddp-$index',
          timeMs: timeMs,
          text: _decodeXmlEntities(text),
          type: _mapMode(mode),
          color: color,
        ),
      );
      index += 1;
    }
    return comments;
  }

  static List<DanmakuComment> _parseJsonComments(String content) {
    final decoded = jsonDecode(content);
    final list = switch (decoded) {
      final List<dynamic> data => data,
      final Map<String, dynamic> data when data['comments'] is List<dynamic> =>
        data['comments'] as List<dynamic>,
      final Map<String, dynamic> data when data['data'] is List<dynamic> =>
        data['data'] as List<dynamic>,
      _ => const <dynamic>[],
    };
    final comments = <DanmakuComment>[];
    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final p = (map['p'] ?? '').toString().trim();
      dynamic timeRaw = map['timeMs'] ?? map['time'] ?? map['progress'];
      dynamic modeRaw = map['mode'] ?? map['type'];
      dynamic colorRaw = map['color'];
      if (p.isNotEmpty) {
        final parts = p.split(',');
        if (timeRaw == null && parts.isNotEmpty) {
          timeRaw = parts[0];
        }
        if (modeRaw == null && parts.length > 1) {
          modeRaw = parts[1];
        }
        if (colorRaw == null && parts.length > 2) {
          colorRaw = parts[2];
        }
      }
      final text = (map['text'] ?? map['content'] ?? map['m'] ?? '')
          .toString()
          .trim();
      if (text.isEmpty) continue;
      comments.add(
        DanmakuComment(
          id: (map['id'] ?? map['cid'] ?? 'json-$i').toString(),
          timeMs: _readTimeMs(timeRaw),
          text: text,
          type: _mapMode(_readInt(modeRaw, fallback: 1)),
          color: _readColor(colorRaw),
        ),
      );
    }
    return comments;
  }

  static FormatException _buildContentFormatException(String content) {
    final normalized = content.trimLeft();
    if (normalized.isEmpty) {
      return const FormatException('Danmaku content is empty');
    }
    if (normalized.startsWith('{') || normalized.startsWith('[')) {
      return const FormatException(
        'Danmaku API returned JSON but no usable comments were found',
      );
    }
    if (normalized.startsWith('<!DOCTYPE') ||
        normalized.startsWith('<html') ||
        normalized.startsWith('<HTML')) {
      return const FormatException(
        'Danmaku API returned HTML instead of comment data',
      );
    }
    return const FormatException('No usable danmaku comments were recognized');
  }

  static int _readTimeMs(dynamic value) {
    return switch (value) {
      final num number =>
        number > 1000 ? number.round() : (number * 1000).round(),
      final String text => _readStringTimeMs(text),
      _ => 0,
    };
  }

  static int _readStringTimeMs(String value) {
    final text = value.trim();
    if (text.isEmpty) return 0;
    if (text.contains(':')) {
      final parts = text.split(':');
      var seconds = 0.0;
      for (final part in parts) {
        final unit = double.tryParse(part.trim()) ?? 0.0;
        seconds = (seconds * 60) + unit;
      }
      return (seconds * 1000).round();
    }
    if (text.contains('.')) {
      final seconds = double.tryParse(text);
      if (seconds == null) return 0;
      return (seconds * 1000).round();
    }
    final parsedInt = int.tryParse(text);
    if (parsedInt != null) {
      return parsedInt > 1000 ? parsedInt : parsedInt * 1000;
    }
    final parsedDouble = double.tryParse(text);
    if (parsedDouble == null) return 0;
    return parsedDouble > 1000
        ? parsedDouble.round()
        : (parsedDouble * 1000).round();
  }

  static int _readInt(dynamic value, {required int fallback}) {
    return switch (value) {
      final num number => number.toInt(),
      final String text => int.tryParse(text) ?? fallback,
      _ => fallback,
    };
  }

  static Color _readColor(dynamic value) {
    if (value is num) {
      return Color(0xFF000000 | value.toInt());
    }
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return Colors.white;
    if (text.startsWith('#')) {
      final hex = text.substring(1);
      final parsed = int.tryParse(hex, radix: 16);
      if (parsed != null) {
        return Color(hex.length <= 6 ? 0xFF000000 | parsed : parsed);
      }
    }
    final parsed = int.tryParse(text);
    if (parsed != null) {
      return Color(0xFF000000 | parsed);
    }
    return Colors.white;
  }

  static DanmakuCommentType _mapMode(int mode) {
    return switch (mode) {
      4 => DanmakuCommentType.bottom,
      5 => DanmakuCommentType.top,
      _ => DanmakuCommentType.scroll,
    };
  }

  static String _decodeXmlEntities(String value) {
    return value
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }

  static String _readXmlAttribute(String source, String name) {
    final pattern = RegExp('$name="([^"]*)"');
    final match = pattern.firstMatch(source);
    return match?.group(1) ?? '';
  }
}

Map<String, Object?> _parseFilePayload(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw const FileSystemException('File does not exist');
  }
  final fileName = file.path.split(Platform.pathSeparator).last;
  final content = file.readAsStringSync();
  return _buildPayload(fileName: fileName, content: content);
}

Map<String, Object?> _parseBytesPayload(Uint8List bytes, String fileName) {
  if (bytes.isEmpty) {
    throw const FormatException('File content is empty');
  }
  final content = utf8.decode(bytes, allowMalformed: true);
  return _buildPayload(fileName: fileName, content: content);
}

Map<String, Object?> _buildPayload({
  required String fileName,
  required String content,
}) {
  final extension = fileName.contains('.')
      ? fileName.split('.').last.toLowerCase()
      : '';
  final comments = switch (extension) {
    'xml' => DanmakuImportParser._parseXmlComments(content),
    'json' => DanmakuImportParser._parseJsonComments(content),
    _ => throw const FormatException(
      'Only XML and JSON danmaku files are supported',
    ),
  };
  if (comments.isEmpty) {
    throw const FormatException('No usable danmaku comments were recognized');
  }
  return <String, Object?>{
    'sourceLabel': fileName,
    'comments': comments
        .map(
          (item) => <String, Object?>{
            'id': item.id,
            'timeMs': item.timeMs,
            'text': item.text,
            'type': item.type.index,
            'color': item.color.toARGB32(),
          },
        )
        .toList(growable: false),
  };
}
