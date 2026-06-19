import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_exception.dart';
import 'storage_access_service.dart';

// compute() 入口：错误日志(实测 ~408KB)的 JSON 编/解码放进 isolate，不阻塞 UI 线程。
String _encodeLogEntries(List<Map<String, dynamic>> list) => jsonEncode(list);
List<Map<String, dynamic>>? _decodeLogEntries(String raw) {
  final value = jsonDecode(raw);
  if (value is! List) return null;
  return value
      .whereType<Map>()
      .map((e) => e.cast<String, dynamic>())
      .toList(growable: false);
}

/// 表示应用日志条目的严重级别。
enum AppLogLevel { error, warning, info }

extension AppLogLevelX on AppLogLevel {
  String get label => switch (this) {
    AppLogLevel.error => 'Error',
    AppLogLevel.warning => 'Warning',
    AppLogLevel.info => 'Info',
  };
}

@immutable
/// 定义可序列化的运行期日志条目。
class AppLogEntry {
  final String id;
  final DateTime timestamp;
  final AppLogLevel level;
  final String source;
  final String message;
  final String? details;
  final String? stackTraceText;

  /// 根据完整字段构造日志条目。
  const AppLogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.source,
    required this.message,
    this.details,
    this.stackTraceText,
  });

  /// 从持久化映射恢复日志条目。
  factory AppLogEntry.fromJson(Map<String, dynamic> json) {
    return AppLogEntry(
      id: json['id'] as String? ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      level: AppLogLevel.values.firstWhere(
        (value) => value.name == json['level'],
        orElse: () => AppLogLevel.error,
      ),
      source: json['source'] as String? ?? 'app',
      message: json['message'] as String? ?? '',
      details: json['details'] as String?,
      stackTraceText: json['stackTraceText'] as String?,
    );
  }

  /// 将日志条目转换为可持久化的映射结构。
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'level': level.name,
      'source': source,
      'message': message,
      'details': details,
      'stackTraceText': stackTraceText,
    };
  }
}

@immutable
/// 描述日志导出的结果信息。
class AppLogExportResult {
  final String path;
  final bool usedExternalStorage;

  /// 根据导出路径与写入位置构造结果对象。
  const AppLogExportResult({
    required this.path,
    required this.usedExternalStorage,
  });
}

/// 统一管理应用内错误、警告与崩溃日志。
class AppLogService extends ChangeNotifier {
  AppLogService._();

  static final AppLogService instance = AppLogService._();

  // 旧版本把全部错误日志(实测 408KB)塞进 SharedPreferences → 每次 getInstance()
  // 都要把整个 prefs map UTF8 解码，卡 UI 线程(实测占 prefs 解码 74%)。改为独立文件
  // 存储 + isolate 编解码，彻底移出 prefs。_prefsKey 仅用于一次性迁移/清理。
  static const String _prefsKey = 'app_error_logs_v1';
  static const String _logsFileName = 'fly_player_error_logs_v1.json';
  static const int _maxEntries = 200;
  static const int _maxCrashJournalBytes = 256 * 1024;
  static const String _runtimeCrashJournalFileName =
      'fly_player_runtime_crash.log';
  static const String _nativeCrashJournalFileName =
      'fly_player_native_crash.log';

  final List<AppLogEntry> _entries = <AppLogEntry>[];
  bool _initialized = false;
  Future<void>? _pendingInitialization;

  List<AppLogEntry> get entries => List<AppLogEntry>.unmodifiable(_entries);

  int get errorCount =>
      _entries.where((entry) => entry.level == AppLogLevel.error).length;

  AppLogEntry? get latestEntry => _entries.isEmpty ? null : _entries.first;

  /// 是否存在可导出的内容：内存条目，或磁盘上的崩溃 journal 文件非空。
  /// 用于导出按钮放行——避免「只有原生崩溃、无 Dart 条目」时被误判为无日志。
  bool get hasExportableLogs {
    if (_entries.isNotEmpty) return true;
    return _crashJournalHasContent(_runtimeCrashJournalFile()) ||
        _crashJournalHasContent(_nativeCrashJournalFile());
  }

  bool _crashJournalHasContent(File file) {
    try {
      return file.existsSync() && file.readAsStringSync().trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// 初始化日志服务并从本地存储恢复历史记录。
  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    if (_pendingInitialization != null) return _pendingInitialization!;

    _pendingInitialization = _loadFromStorage().whenComplete(() {
      _initialized = true;
      _pendingInitialization = null;
    });
    return _pendingInitialization!;
  }

  Future<void> _loadFromStorage() async {
    try {
      final raw = await _readPersistedRaw();
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = await compute(_decodeLogEntries, raw);
        if (decoded != null) {
          _entries
            ..clear()
            ..addAll(
              decoded
                  .map(AppLogEntry.fromJson)
                  .where((entry) => entry.message.trim().isNotEmpty),
            );
          _entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          if (_entries.length > _maxEntries) {
            _entries.removeRange(_maxEntries, _entries.length);
          }
          notifyListeners();
        }
      }
    } catch (_) {
      _entries.clear();
    }
    // JSON 主存只保存 Dart 侧条目；原生崩溃(Kotlin UncaughtExceptionHandler)与被硬
    // 崩溃截断、未来得及异步 _persist 的 runtime 条目都只落在崩溃日志文件里。这里把
    // 两个 journal 解析合并进 _entries，让设置→日志界面能直接看到原生崩溃。
    await _mergeCrashJournals();
  }

  /// 解析原生 / runtime 崩溃日志文件，去重后并入内存日志列表。
  Future<void> _mergeCrashJournals() async {
    final merged = <AppLogEntry>[
      ..._parseCrashJournalFile(_nativeCrashJournalFile()),
      ..._parseCrashJournalFile(_runtimeCrashJournalFile()),
    ];
    if (merged.isEmpty) return;
    final keys = _entries.map(_dedupKey).toSet();
    var added = false;
    for (final entry in merged) {
      if (keys.add(_dedupKey(entry))) {
        _entries.add(entry);
        added = true;
      }
    }
    if (!added) return;
    _entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (_entries.length > _maxEntries) {
      _entries.removeRange(_maxEntries, _entries.length);
    }
    notifyListeners();
    // 持久化到 JSON 主存，使其在 journal 触顶轮换(256KB 清空)后仍存活。
    unawaited(_persist());
  }

  // 崩溃 journal 与 _entries 时间精度不同(journal 仅到秒)，用「级别+秒级时间+消息」
  // 作为去重键；runtime journal 多为 _entries 的镜像，借此过滤掉重复项。
  String _dedupKey(AppLogEntry entry) =>
      '${entry.level.name}|${_formatTimestamp(entry.timestamp)}|${entry.message.trim()}';

  List<AppLogEntry> _parseCrashJournalFile(File file) {
    try {
      if (!file.existsSync()) return const <AppLogEntry>[];
      final content = file.readAsStringSync();
      if (content.trim().isEmpty) return const <AppLogEntry>[];
      return _parseCrashJournal(content);
    } catch (_) {
      return const <AppLogEntry>[];
    }
  }

  // journal 块以 "[级别] 时间戳 ..." 行开头(Kotlin 用 [native])；消息可能多行，故以
  // header 行而非空行切块，避免多行消息被截断。
  static final RegExp _journalHeaderPattern = RegExp(
    r'^\[(error|warning|info|native)\]\s+'
    r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})(?:\s+(.*))?$',
  );

  List<AppLogEntry> _parseCrashJournal(String content) {
    final blocks = <List<String>>[];
    List<String>? current;
    for (final raw in content.split('\n')) {
      final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      if (_journalHeaderPattern.hasMatch(line)) {
        current = <String>[line];
        blocks.add(current);
      } else {
        current?.add(line);
      }
    }
    final result = <AppLogEntry>[];
    for (var i = 0; i < blocks.length; i++) {
      final entry = _parseCrashJournalBlock(blocks[i], i);
      if (entry != null) result.add(entry);
    }
    return result;
  }

  AppLogEntry? _parseCrashJournalBlock(List<String> block, int index) {
    if (block.isEmpty) return null;
    final header = _journalHeaderPattern.firstMatch(block.first);
    if (header == null) return null;
    final timestamp = DateTime.tryParse(
      header.group(2)!.replaceFirst(' ', 'T'),
    );
    if (timestamp == null) return null;
    final tag = header.group(1)!;
    final rest = header.group(3)?.trim() ?? '';
    final isNative = tag == 'native';
    final level = isNative
        ? AppLogLevel.error
        : AppLogLevel.values.firstWhere(
            (value) => value.name == tag,
            orElse: () => AppLogLevel.error,
          );
    final source = isNative ? 'native' : (rest.isEmpty ? 'app' : rest);

    final messageLines = <String>[];
    final stackLines = <String>[];
    final detailParts = <String>[if (isNative && rest.isNotEmpty) rest];
    var inStack = false;
    for (var i = 1; i < block.length; i++) {
      final line = block[i];
      if (inStack) {
        stackLines.add(line);
        continue;
      }
      if (line == 'stackTrace:') {
        inStack = true;
        continue;
      }
      final detail = RegExp(r'^details:\s?(.*)$').firstMatch(line);
      if (detail != null) {
        final value = detail.group(1)?.trim() ?? '';
        if (value.isNotEmpty) detailParts.add(value);
        continue;
      }
      messageLines.add(line);
    }

    final message = messageLines.join('\n').trim();
    if (message.isEmpty) return null;
    final stack = stackLines.join('\n').trim();
    return AppLogEntry(
      id: 'journal_${timestamp.microsecondsSinceEpoch}_$index',
      timestamp: timestamp,
      level: level,
      source: source,
      message: message,
      details: detailParts.isEmpty ? null : detailParts.join(' | '),
      stackTraceText: stack.isEmpty ? null : stack,
    );
  }

  /// 读持久化原文：优先文件；文件不存在则从旧 SharedPreferences **迁移一次**到文件，
  /// 并删除该 prefs 大 blob（408KB，撑爆 prefs map 导致每次 getInstance 解码卡顿）。
  Future<String?> _readPersistedRaw() async {
    final file = _logsFile();
    if (await file.exists()) {
      return file.readAsString();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(_prefsKey);
      if (legacy != null && legacy.trim().isNotEmpty) {
        await file.writeAsString(legacy, flush: true);
      }
      if (prefs.containsKey(_prefsKey)) {
        await prefs.remove(_prefsKey);
      }
      return legacy;
    } catch (_) {
      return null;
    }
  }

  File _logsFile() => File('${Directory.systemTemp.path}/$_logsFileName');

  /// 清空已保存的日志及关联崩溃日志文件。
  Future<void> clear() async {
    await initialize();
    _entries.clear();
    notifyListeners();
    _deleteCrashJournalSync(_runtimeCrashJournalFile());
    _deleteCrashJournalSync(_nativeCrashJournalFile());
    await _persist();
  }

  /// 记录一条错误级别日志。
  Future<void> recordError({
    required Object error,
    StackTrace? stackTrace,
    required String source,
    String? details,
  }) async {
    await record(
      level: AppLogLevel.error,
      error: error,
      stackTrace: stackTrace,
      source: source,
      details: details,
    );
  }

  /// 记录一条警告级别日志。
  Future<void> recordWarning({
    required Object error,
    StackTrace? stackTrace,
    required String source,
    String? details,
  }) async {
    await record(
      level: AppLogLevel.warning,
      error: error,
      stackTrace: stackTrace,
      source: source,
      details: details,
    );
  }

  /// 以指定级别写入一条日志记录。
  Future<void> record({
    required AppLogLevel level,
    required Object error,
    StackTrace? stackTrace,
    required String source,
    String? details,
  }) async {
    await initialize();
    final entry = _buildEntry(
      level: level,
      error: error,
      stackTrace: stackTrace,
      source: source,
      details: details,
    );
    _append(entry);
    if (level == AppLogLevel.error) {
      _appendCrashJournalSync(entry);
    }
  }

  /// 记录 Flutter 框架上报的异常信息。
  Future<void> recordFlutterError(FlutterErrorDetails details) async {
    await initialize();
    final entry = _buildFlutterErrorEntry(details);
    _append(entry);
    _appendCrashJournalSync(entry);
  }

  /// 以同步方式记录错误级别日志，适用于异常恢复链路。
  void recordErrorSync({
    required Object error,
    StackTrace? stackTrace,
    required String source,
    String? details,
  }) {
    final entry = _buildEntry(
      level: AppLogLevel.error,
      error: error,
      stackTrace: stackTrace,
      source: source,
      details: details,
    );
    _append(entry);
    _appendCrashJournalSync(entry);
  }

  /// 以同步方式记录 Flutter 框架异常。
  void recordFlutterErrorSync(FlutterErrorDetails details) {
    final entry = _buildFlutterErrorEntry(details);
    _append(entry);
    _appendCrashJournalSync(entry);
  }

  /// 将当前日志导出为文本文件并返回导出结果。
  Future<AppLogExportResult> exportToTxt() async {
    await initialize();
    final fileName = 'fly_player_logs_${_timestampForFile(DateTime.now())}.txt';
    final text = _buildExportText();

    try {
      final targetPath = await _buildExternalExportPath(fileName);
      final file = File(targetPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(text, flush: true);
      return AppLogExportResult(path: file.path, usedExternalStorage: true);
    } on MissingPluginException {
      return _writeToTempFile(fileName, text);
    } on PlatformException {
      return _writeToTempFile(fileName, text);
    } on FileSystemException {
      return _writeToTempFile(fileName, text);
    }
  }

  void _append(AppLogEntry entry) {
    _entries.insert(0, entry);
    if (_entries.length > _maxEntries) {
      _entries.removeRange(_maxEntries, _entries.length);
    }
    notifyListeners();
    unawaited(_persist());
  }

  Future<void> _persist() async {
    try {
      final list = _entries
          .map((entry) => entry.toJson())
          .toList(growable: false);
      final encoded = await compute(_encodeLogEntries, list);
      final file = _logsFile();
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(encoded, flush: true);
      await tmp.rename(file.path);
    } catch (_) {}
  }

  Future<String> _buildExternalExportPath(String fileName) async {
    var hasAccess = await StorageAccessService.hasFileAccess();
    if (!hasAccess) {
      await StorageAccessService.requestFileAccess();
      hasAccess = await StorageAccessService.hasFileAccess();
    }
    if (!hasAccess) {
      throw const FileSystemException('missing external storage permission');
    }

    final root = await StorageAccessService.primaryStorageRoot();
    final normalizedRoot = root.trim().isEmpty ? '/storage/emulated/0' : root;
    return '$normalizedRoot/Download/$fileName';
  }

  Future<AppLogExportResult> _writeToTempFile(
    String fileName,
    String text,
  ) async {
    final file = File('${Directory.systemTemp.path}/$fileName');
    await file.parent.create(recursive: true);
    await file.writeAsString(text, flush: true);
    return AppLogExportResult(path: file.path, usedExternalStorage: false);
  }

  String _buildExportText() {
    final buffer = StringBuffer()
      ..writeln('Fly Player Log Export')
      ..writeln('Generated At: ${_formatTimestamp(DateTime.now())}')
      ..writeln('Entry Count: ${_entries.length}')
      ..writeln('');

    if (_entries.isEmpty) {
      buffer.writeln('No in-app log entries recorded.');
    } else {
      for (final entry in _entries) {
        buffer.writeln(
          '[${entry.level.label}] ${_formatTimestamp(entry.timestamp)} ${entry.source}',
        );
        buffer.writeln(entry.message);
        if (entry.details != null && entry.details!.trim().isNotEmpty) {
          buffer.writeln('Details: ${entry.details!.trim()}');
        }
        if (entry.stackTraceText != null &&
            entry.stackTraceText!.trim().isNotEmpty) {
          buffer.writeln('StackTrace:');
          buffer.writeln(entry.stackTraceText!.trim());
        }
        buffer.writeln('');
      }
    }

    _appendCrashJournalSection(
      buffer: buffer,
      title: 'Runtime Crash Journal',
      file: _runtimeCrashJournalFile(),
    );
    _appendCrashJournalSection(
      buffer: buffer,
      title: 'Native Crash Journal',
      file: _nativeCrashJournalFile(),
    );
    return buffer.toString().trimRight();
  }

  AppLogEntry _buildEntry({
    required AppLogLevel level,
    required Object error,
    StackTrace? stackTrace,
    required String source,
    String? details,
  }) {
    final resolvedMessage = error is AppException ? error.message : '$error';
    final resolvedDetails = <String>[
      if (error is AppException && error.action.trim().isNotEmpty)
        'action=${error.action}',
      if (error is AppException && error.code != null) 'code=${error.code}',
      if (error is AppException && error.httpStatus != null)
        'http=${error.httpStatus}',
      if (details != null && details.trim().isNotEmpty) details.trim(),
    ].join(' | ');
    return AppLogEntry(
      id: _buildId(),
      timestamp: DateTime.now(),
      level: level,
      source: source,
      message: resolvedMessage,
      details: resolvedDetails.isEmpty ? null : resolvedDetails,
      stackTraceText:
          (error is AppException ? error.stackTrace ?? stackTrace : stackTrace)
              ?.toString(),
    );
  }

  AppLogEntry _buildFlutterErrorEntry(FlutterErrorDetails details) {
    return AppLogEntry(
      id: _buildId(),
      timestamp: DateTime.now(),
      level: AppLogLevel.error,
      source: 'flutter',
      message: details.exceptionAsString(),
      details: details.context?.toDescription(),
      stackTraceText: details.stack?.toString(),
    );
  }

  void _appendCrashJournalSync(AppLogEntry entry) {
    try {
      final file = _runtimeCrashJournalFile();
      file.parent.createSync(recursive: true);
      if (file.existsSync() && file.lengthSync() > _maxCrashJournalBytes) {
        file.writeAsStringSync('', flush: true);
      }
      file.writeAsStringSync(
        _formatCrashJournalEntry(entry),
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }

  String _formatCrashJournalEntry(AppLogEntry entry) {
    final buffer = StringBuffer()
      ..writeln(
        '[${entry.level.name}] ${_formatTimestamp(entry.timestamp)} ${entry.source}',
      )
      ..writeln(entry.message);
    if (entry.details != null && entry.details!.trim().isNotEmpty) {
      buffer.writeln('details: ${entry.details!.trim()}');
    }
    if (entry.stackTraceText != null &&
        entry.stackTraceText!.trim().isNotEmpty) {
      buffer.writeln('stackTrace:');
      buffer.writeln(entry.stackTraceText!.trim());
    }
    buffer.writeln('');
    return buffer.toString();
  }

  void _appendCrashJournalSection({
    required StringBuffer buffer,
    required String title,
    required File file,
  }) {
    final content = _readCrashJournalSync(file);
    if (content == null) return;
    buffer
      ..writeln('')
      ..writeln('===== $title =====')
      ..writeln(content.trimRight());
  }

  String? _readCrashJournalSync(File file) {
    try {
      if (!file.existsSync()) return null;
      final content = file.readAsStringSync();
      return content.trim().isEmpty ? null : content;
    } catch (_) {
      return null;
    }
  }

  void _deleteCrashJournalSync(File file) {
    try {
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
  }

  File _runtimeCrashJournalFile() {
    return File('${Directory.systemTemp.path}/$_runtimeCrashJournalFileName');
  }

  File _nativeCrashJournalFile() {
    return File('${Directory.systemTemp.path}/$_nativeCrashJournalFileName');
  }

  String _buildId() {
    final millis = DateTime.now().microsecondsSinceEpoch;
    return 'log_$millis';
  }

  /// 按日志导出所使用的本地时间格式格式化时间戳。
  static String formatTimestamp(DateTime value) => _formatTimestamp(value);

  static String _formatTimestamp(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute:$second';
  }

  static String _timestampForFile(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    return '${local.year}$month${day}_$hour$minute$second';
  }
}
