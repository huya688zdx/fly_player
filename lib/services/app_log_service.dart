import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_exception.dart';
import 'storage_access_service.dart';

enum AppLogLevel { error, warning, info }

extension AppLogLevelX on AppLogLevel {
  String get label => switch (this) {
    AppLogLevel.error => '错误',
    AppLogLevel.warning => '警告',
    AppLogLevel.info => '信息',
  };
}

@immutable
class AppLogEntry {
  final String id;
  final DateTime timestamp;
  final AppLogLevel level;
  final String source;
  final String message;
  final String? details;
  final String? stackTraceText;

  const AppLogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.source,
    required this.message,
    this.details,
    this.stackTraceText,
  });

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
class AppLogExportResult {
  final String path;
  final bool usedExternalStorage;

  const AppLogExportResult({
    required this.path,
    required this.usedExternalStorage,
  });
}

class AppLogService extends ChangeNotifier {
  AppLogService._();

  static final AppLogService instance = AppLogService._();

  static const String _prefsKey = 'app_error_logs_v1';
  static const int _maxEntries = 200;

  final List<AppLogEntry> _entries = <AppLogEntry>[];
  bool _initialized = false;
  Future<void>? _pendingInitialization;

  List<AppLogEntry> get entries => List<AppLogEntry>.unmodifiable(_entries);

  int get errorCount =>
      _entries.where((entry) => entry.level == AppLogLevel.error).length;

  AppLogEntry? get latestEntry => _entries.isEmpty ? null : _entries.first;

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
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _entries
        ..clear()
        ..addAll(
          decoded
              .whereType<Map>()
              .map((value) => value.cast<String, dynamic>())
              .map(AppLogEntry.fromJson)
              .where((entry) => entry.message.trim().isNotEmpty),
        );
      _entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (_entries.length > _maxEntries) {
        _entries.removeRange(_maxEntries, _entries.length);
      }
      notifyListeners();
    } catch (_) {
      _entries.clear();
    }
  }

  Future<void> clear() async {
    await initialize();
    _entries.clear();
    notifyListeners();
    await _persist();
  }

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

  Future<void> record({
    required AppLogLevel level,
    required Object error,
    StackTrace? stackTrace,
    required String source,
    String? details,
  }) async {
    await initialize();
    final resolvedMessage = error is AppException ? error.message : '$error';
    final resolvedDetails = <String>[
      if (error is AppException && error.action.trim().isNotEmpty)
        'action=${error.action}',
      if (error is AppException && error.code != null) 'code=${error.code}',
      if (error is AppException && error.httpStatus != null)
        'http=${error.httpStatus}',
      if (details != null && details.trim().isNotEmpty) details.trim(),
    ].join(' | ');
    _append(
      AppLogEntry(
        id: _buildId(),
        timestamp: DateTime.now(),
        level: level,
        source: source,
        message: resolvedMessage,
        details: resolvedDetails.isEmpty ? null : resolvedDetails,
        stackTraceText:
            (error is AppException
                    ? error.stackTrace ?? stackTrace
                    : stackTrace)
                ?.toString(),
      ),
    );
  }

  Future<void> recordFlutterError(FlutterErrorDetails details) async {
    await initialize();
    _append(
      AppLogEntry(
        id: _buildId(),
        timestamp: DateTime.now(),
        level: AppLogLevel.error,
        source: 'flutter',
        message: details.exceptionAsString(),
        details: details.context?.toDescription(),
        stackTraceText: details.stack?.toString(),
      ),
    );
  }

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
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        _entries.map((entry) => entry.toJson()).toList(growable: false),
      );
      await prefs.setString(_prefsKey, encoded);
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
      ..writeln('Fly Player 日志导出')
      ..writeln('生成时间: ${_formatTimestamp(DateTime.now())}')
      ..writeln('日志数量: ${_entries.length}')
      ..writeln('');

    if (_entries.isEmpty) {
      buffer.writeln('当前没有已记录的错误日志。');
      return buffer.toString();
    }

    for (final entry in _entries) {
      buffer.writeln(
        '[${entry.level.label}] ${_formatTimestamp(entry.timestamp)} ${entry.source}',
      );
      buffer.writeln(entry.message);
      if (entry.details != null && entry.details!.trim().isNotEmpty) {
        buffer.writeln('详情: ${entry.details!.trim()}');
      }
      if (entry.stackTraceText != null &&
          entry.stackTraceText!.trim().isNotEmpty) {
        buffer.writeln('堆栈:');
        buffer.writeln(entry.stackTraceText!.trim());
      }
      buffer.writeln('');
    }
    return buffer.toString().trimRight();
  }

  String _buildId() {
    final millis = DateTime.now().microsecondsSinceEpoch;
    return 'log_$millis';
  }

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
