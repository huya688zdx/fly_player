import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

import '../api/feiniu_api.dart';
import '../danmaku/api/dandanplay_api.dart';
import '../danmaku/api/dandanplay_config.dart';
import '../danmaku/api/dandanplay_resolver.dart';
import '../danmaku/models/danmaku_import_result.dart';
import '../danmaku/models/danmaku_saved_source.dart';
import '../danmaku/parser/danmaku_import_parser.dart';
import '../danmaku/settings/danmaku_saved_source_store.dart';
import '../models/download_task_record.dart';
import '../models/download_record_tokens.dart';
import '../models/media_library_item.dart';
import '../models/play_info.dart';
import '../models/stream_list_option.dart';
import '../models/stream_track_data.dart';
import '../providers/nas_provider.dart';
import '../utils/app_exception.dart';
import '../utils/api_url_helper.dart';
import '../utils/swallowed_error_logger.dart';
import 'app_log_service.dart';
import 'storage_access_service.dart';
import 'storage_management_service.dart';

/// 表示发起下载后的即时状态。
enum DownloadStartState { started, downloading, downloaded, importedFromCache }

/// 描述单次发起下载操作的结果。
class DownloadStartResult {
  final DownloadStartState state;
  final DownloadTaskRecord record;

  /// 根据启动状态与对应任务记录构造结果对象。
  const DownloadStartResult({required this.state, required this.record});
}

DownloadTaskRecord? selectDownloadedRecordForItem(
  Iterable<DownloadTaskRecord> records,
  String itemGuid, {
  String mediaGuid = '',
  String resolution = '',
  required bool Function(DownloadTaskRecord record) isAvailable,
}) {
  final normalizedItemGuid = itemGuid.trim();
  final normalizedMediaGuid = mediaGuid.trim();
  final normalizedResolution = resolution.trim().toLowerCase();
  if (normalizedItemGuid.isEmpty) return null;

  bool matchesBase(DownloadTaskRecord record) {
    if (record.itemGuid != normalizedItemGuid) return false;
    if (!isAvailable(record)) return false;
    if (normalizedResolution.isNotEmpty &&
        record.resolution.trim().toLowerCase() != normalizedResolution) {
      return false;
    }
    return true;
  }

  if (normalizedMediaGuid.isNotEmpty) {
    for (final record in records) {
      if (!matchesBase(record)) continue;
      if (record.mediaGuid.trim() == normalizedMediaGuid) return record;
    }
    return null;
  }

  for (final record in records) {
    if (matchesBase(record)) return record;
  }
  if (normalizedResolution.isEmpty) return null;
  for (final record in records) {
    if (record.itemGuid != normalizedItemGuid) continue;
    if (isAvailable(record)) return record;
  }
  return null;
}

/// 根据目标清晰度和媒体版本选择下载流。
StreamListOption? selectDownloadStreamOption(
  List<StreamListOption> options, {
  required String resolution,
  String mediaGuid = '',
}) {
  final normalizedResolution = resolution.trim().toLowerCase();
  final normalizedMediaGuid = mediaGuid.trim();

  bool matchesResolution(StreamListOption option) {
    return normalizedResolution.isEmpty ||
        option.resolutionType.trim().toLowerCase() == normalizedResolution;
  }

  if (normalizedMediaGuid.isNotEmpty) {
    for (final option in options) {
      if (option.mediaGuid.trim() == normalizedMediaGuid &&
          matchesResolution(option)) {
        return option;
      }
    }
    for (final option in options) {
      if (option.mediaGuid.trim() == normalizedMediaGuid) return option;
    }
  }

  for (final option in options) {
    if (matchesResolution(option)) return option;
  }
  return options.isNotEmpty ? options.first : null;
}

/// 描述离线下载恢复扫描的统计结果。
class DownloadRecoveryResult {
  final int scannedVideoCount;
  final int importedCount;
  final int alreadyTrackedCount;
  final int skippedCount;
  final DownloadTaskRecord? preferredRecord;

  /// 根据恢复统计数据构造结果对象。
  const DownloadRecoveryResult({
    required this.scannedVideoCount,
    required this.importedCount,
    required this.alreadyTrackedCount,
    required this.skippedCount,
    this.preferredRecord,
  });
}

/// 统一管理离线下载任务、缓存导入与恢复逻辑。
class DownloadTaskService extends ChangeNotifier {
  DownloadTaskService._();

  static final DownloadTaskService instance = DownloadTaskService._();

  static const String _prefsKey = 'download_task_records_v1';
  static const String _downloadFolderName = 'FlyPlayer';
  static const String _recoveryMetadataFileName = '.flyplayer-download.json';
  static const String _pathRecoveryMetadataSuffix = '.flyplayer-download.json';
  static const MethodChannel _storageChannel = MethodChannel(
    'fly_player/storage',
  );
  static const String _legacyLocalResolution = '\u672c\u5730';
  static const String _interruptedMessage = downloadInterruptedMessageToken;

  static const List<String> _recoveredImageExtensions = <String>[
    '.webp',
    '.jpg',
    '.jpeg',
    '.png',
    '.img',
  ];
  static const Duration _taskProgressPollInterval = Duration(seconds: 2);
  static const int _downloadSpeedEstimateWindowMs = 1200;
  static const int _downloadSpeedPublishIntervalMs = 900;
  static const int _downloadSpeedMinChangeBytesPerSecond = 256 * 1024;

  final List<DownloadTaskRecord> _records = <DownloadTaskRecord>[];
  final Map<String, CancelToken> _cancelTokens = <String, CancelToken>{};

  /// 正在创建中的下载任务（按 条目+版本+清晰度 去重）。
  /// 用于把快速重复点击折叠到同一个在途任务上，避免双击生成两个服务端任务、
  /// 两个下载目录（文件夹「拉屎」）以及多余的暂停任务。
  final Map<String, Future<DownloadStartResult>> _inFlightStarts =
      <String, Future<DownloadStartResult>>{};
  final Map<String, int> _downloadSpeedBytesPerSecond = <String, int>{};
  final Map<String, _DownloadProgressSample> _downloadProgressSamples =
      <String, _DownloadProgressSample>{};
  final Map<String, _DownloadProgressSample> _downloadSpeedAnchorSamples =
      <String, _DownloadProgressSample>{};
  final Map<String, int> _downloadSpeedPublishedAtMs = <String, int>{};
  final Map<String, DownloadTaskProgressInfo> _downloadTaskProgress =
      <String, DownloadTaskProgressInfo>{};
  final Map<String, Timer> _downloadTaskProgressPollers = <String, Timer>{};
  final Set<String> _downloadTaskProgressInFlight = <String>{};

  bool _initialized = false;
  Future<void>? _pendingInitialization;
  Timer? _persistTimer;
  Future<void>? _persistQueue;
  Future<void>? _pendingGroupMetadataRefresh;
  String? _debugRecordsFilePath;

  List<DownloadTaskRecord> get records =>
      List<DownloadTaskRecord>.unmodifiable(_records);

  /// 按任务标识返回当前记录；空标识或不存在的任务返回 `null`。
  DownloadTaskRecord? recordById(String recordId) => _recordById(recordId);

  @visibleForTesting
  void debugReplaceRecordsForTesting(List<DownloadTaskRecord> records) {
    _persistTimer?.cancel();
    _persistTimer = null;
    _persistQueue = null;
    _pendingInitialization = null;
    _initialized = true;
    _cancelTokens.clear();
    for (final timer in _downloadTaskProgressPollers.values) {
      timer.cancel();
    }
    _downloadTaskProgressPollers.clear();
    _downloadTaskProgressInFlight.clear();
    _downloadSpeedBytesPerSecond.clear();
    _downloadProgressSamples.clear();
    _downloadSpeedAnchorSamples.clear();
    _downloadSpeedPublishedAtMs.clear();
    _downloadTaskProgress.clear();
    _records
      ..clear()
      ..addAll(records);
    _sortRecords();
    notifyListeners();
  }

  @visibleForTesting
  void debugSetRecordsFilePathForTesting(String? path) {
    _debugRecordsFilePath = path;
    _recordsPathFuture = null;
  }

  @visibleForTesting
  Future<void> debugUpsertRecordForTesting(
    DownloadTaskRecord record, {
    bool persistImmediately = false,
  }) {
    return _upsertRecord(record, persistImmediately: persistImmediately);
  }

  @visibleForTesting
  Future<void> debugPollDownloadTaskProgressForTesting({
    required String recordId,
    required Future<DownloadTaskProgressInfo?> Function(String remoteTaskId)
    fetchProgress,
  }) {
    return _pollDownloadTaskProgressOnce(
      recordId: recordId,
      fetchProgress: fetchProgress,
    );
  }

  @visibleForTesting
  DownloadTaskProgressInfo? debugTaskProgressForTesting(String recordId) {
    return _downloadTaskProgress[recordId];
  }

  /// 返回所有活跃（下载中或已暂停）的下载任务。
  List<DownloadTaskRecord> get activeRecords {
    return _sortedRecords(
      _records.where(
        (record) =>
            record.status == DownloadTaskStatus.downloading ||
            record.status == DownloadTaskStatus.paused,
      ),
      status: DownloadTaskStatus.downloading,
    );
  }

  /// 返回指定任务最近一次发布的下载速度估计值。
  int downloadSpeedBytesPerSecondFor(String recordId) =>
      _downloadSpeedBytesPerSecond[recordId] ?? 0;

  /// 返回指定任务当前缓存的远端进度信息。
  DownloadTaskProgressInfo? downloadTaskProgressFor(String recordId) =>
      _downloadTaskProgress[recordId];

  /// 初始化下载任务服务并恢复本地持久化记录。
  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    if (_pendingInitialization != null) return _pendingInitialization!;
    _pendingInitialization = _loadFromStorage().whenComplete(() {
      _initialized = true;
      _pendingInitialization = null;
    });
    return _pendingInitialization!;
  }

  List<DownloadTaskRecord> get downloadedRecords =>
      _records.where(_isDownloadedRecordAvailable).toList(growable: false);

  int get downloadedRecordCount => downloadedRecords.length;

  /// 已下载文件的磁盘实际占用合计。改成异步：记录多时逐条 lengthSync 会卡 UI 线程；
  /// 这里用 Future.wait 并发取长度，避免串行 await 把耗时按记录数放大。
  Future<int> downloadedBytes() async {
    final sizes = await Future.wait(<Future<int>>[
      for (final record in _records)
        if (_isDownloadedRecordAvailable(record)) _recordDiskBytes(record),
    ]);
    return sizes.fold<int>(0, (sum, value) => sum + value);
  }

  /// 单条记录的磁盘占用；文件不可读时退回记录里的 totalBytes（沿用旧同步实现语义）。
  Future<int> _recordDiskBytes(DownloadTaskRecord record) async {
    try {
      return await File(record.filePath).length();
    } catch (_) {
      return record.totalBytes;
    }
  }

  /// 按状态返回排序后的下载任务列表。
  List<DownloadTaskRecord> recordsByStatus(DownloadTaskStatus status) {
    return _sortedRecords(
      _records.where((record) => _matchesStatus(record, status)),
      status: status,
    );
  }

  /// 按状态对下载任务分组，并返回排序后的分组列表。
  List<DownloadTaskGroup> groupsByStatus(DownloadTaskStatus status) {
    final grouped = <String, List<DownloadTaskRecord>>{};
    for (final record in _records) {
      if (!_matchesStatus(record, status)) continue;
      final canonicalGroupId = _canonicalGroupId(record);
      grouped.putIfAbsent(canonicalGroupId, () => <DownloadTaskRecord>[]);
      grouped[canonicalGroupId]!.add(record);
    }
    final groups =
        grouped.entries
            .map(
              (entry) => DownloadTaskGroup(
                id: entry.key,
                title: _displayGroupTitleForRecord(entry.value.first),
                records: _sortedRecords(entry.value, status: status),
              ),
            )
            .toList(growable: false)
          ..sort(
            (a, b) => compareDownloadTaskRecordsForDisplay(
              a.leadRecord,
              b.leadRecord,
              statusHint: status,
            ),
          );
    return groups;
  }

  /// 返回指定分组下的任务记录，并可按状态进一步过滤。
  List<DownloadTaskRecord> recordsForGroup(
    String groupId, {
    DownloadTaskStatus? status,
  }) {
    return _sortedRecords(
      _records.where(
        (record) =>
            _canonicalGroupId(record) == groupId &&
            (status == null || _matchesStatus(record, status)),
      ),
      status: status,
    );
  }

  /// 生成用于界面展示的下载任务标题。
  String displayTitleForRecord(DownloadTaskRecord record) {
    return _displayRecordTitleForRecord(record);
  }

  /// 按分组标识查询下载任务分组。
  DownloadTaskGroup? groupById(String groupId, {DownloadTaskStatus? status}) {
    final records = recordsForGroup(groupId, status: status);
    if (records.isEmpty) return null;
    return DownloadTaskGroup(
      id: groupId,
      title: _displayGroupTitleForRecord(records.first),
      records: records,
    );
  }

  /// 计算指定条目当前在下载入口上的动作状态。
  DownloadActionState actionStateForItem(String itemGuid) {
    return actionStateForItemVersion(itemGuid);
  }

  DownloadActionState actionStateForItemVersion(
    String itemGuid, {
    String mediaGuid = '',
  }) {
    final normalized = itemGuid.trim();
    final normalizedMediaGuid = mediaGuid.trim();
    if (normalized.isEmpty) return DownloadActionState.idle;

    bool matchesItem(DownloadTaskRecord record) {
      if (record.itemGuid != normalized) return false;
      if (normalizedMediaGuid.isNotEmpty &&
          record.mediaGuid.trim() != normalizedMediaGuid) {
        return false;
      }
      return true;
    }

    final downloaded = _records.firstWhere(
      (record) => matchesItem(record) && _isDownloadedRecordAvailable(record),
      orElse: () => _emptyRecord,
    );
    if (downloaded != _emptyRecord) {
      return const DownloadActionState(downloaded: true);
    }
    final downloading = _records.firstWhere(
      (record) =>
          matchesItem(record) &&
          record.status == DownloadTaskStatus.downloading,
      orElse: () => _emptyRecord,
    );
    if (downloading != _emptyRecord) {
      return const DownloadActionState(downloading: true);
    }
    final paused = _records.firstWhere(
      (record) =>
          matchesItem(record) && record.status == DownloadTaskStatus.paused,
      orElse: () => _emptyRecord,
    );
    if (paused != _emptyRecord) {
      return const DownloadActionState(paused: true);
    }
    final failed = _records.firstWhere(
      (record) =>
          matchesItem(record) && record.status == DownloadTaskStatus.failed,
      orElse: () => _emptyRecord,
    );
    if (failed != _emptyRecord) {
      return const DownloadActionState(failed: true);
    }
    return DownloadActionState.idle;
  }

  /// 批量计算多个条目的下载动作状态。
  Map<String, DownloadActionState> actionStatesForItems(
    Iterable<String> itemGuids,
  ) {
    final result = <String, DownloadActionState>{};
    for (final itemGuid in itemGuids) {
      final normalized = itemGuid.trim();
      if (normalized.isEmpty) continue;
      result[normalized] = actionStateForItem(normalized);
    }
    return result;
  }

  /// 查询指定条目及清晰度对应的已下载记录。
  DownloadTaskRecord? downloadedRecordForItem(
    String itemGuid, {
    String mediaGuid = '',
    String resolution = '',
  }) {
    return selectDownloadedRecordForItem(
      _records,
      itemGuid,
      mediaGuid: mediaGuid,
      resolution: resolution,
      isAvailable: _isDownloadedRecordAvailable,
    );
  }

  /// 返回指定条目的全部已下载记录。
  List<DownloadTaskRecord> downloadedRecordsForItem(String itemGuid) {
    final normalizedItemGuid = itemGuid.trim();
    if (normalizedItemGuid.isEmpty) return const <DownloadTaskRecord>[];
    return _records
        .where(
          (record) =>
              record.itemGuid == normalizedItemGuid &&
              _isDownloadedRecordAvailable(record),
        )
        .toList(growable: false);
  }

  /// 按本地文件路径查找已登记的下载记录。
  DownloadTaskRecord? downloadedRecordForFilePath(String filePath) {
    final normalizedPath = _normalizeFilePathForComparison(filePath);
    if (normalizedPath.isEmpty) return null;
    for (final record in _records) {
      if (!_isDownloadedRecordAvailable(record)) continue;
      if (_normalizeFilePathForComparison(record.filePath) == normalizedPath) {
        return record;
      }
    }
    return null;
  }

  /// 扫描下载目录并恢复未登记的本地离线资源。
  Future<DownloadRecoveryResult> recoverDownloadedFiles({
    bool requestStorageAccess = true,
    NasProvider? provider,
  }) async {
    await initialize();
    return _recoverDownloadedFilesInternal(
      requestStorageAccess: requestStorageAccess,
      backendLookup: _createRecoveredBackendLookup(provider),
    );
  }

  /// 针对外部打开的本地媒体尝试补建对应的下载记录。
  Future<DownloadTaskRecord?> recoverDownloadedRecordForExternalOpen({
    required String sourceUrl,
    required String displayName,
    int sizeBytes = 0,
    NasProvider? provider,
  }) async {
    await initialize();
    final backendLookup = _createRecoveredBackendLookup(provider);
    final directPath = _localFilePathFromUrl(sourceUrl);
    if (directPath != null && directPath.trim().isNotEmpty) {
      final existing = downloadedRecordForFilePath(directPath);
      if (existing != null) {
        return _refreshRecoveredRecordArtifacts(
          existing,
          File(directPath),
          backendLookup: backendLookup,
        );
      }
      final file = File(directPath);
      if (await _looksRecoverableDownloadFile(
        file,
        expectedDisplayName: displayName,
        expectedSizeBytes: sizeBytes,
      )) {
        return _importRecoveredVideoFile(
          file,
          expectedDisplayName: displayName,
          expectedSizeBytes: sizeBytes,
          backendLookup: backendLookup,
        );
      }
      return null;
    }

    final existingBySignature = await _downloadedRecordForFileSignature(
      displayName: displayName,
      sizeBytes: sizeBytes,
    );
    if (existingBySignature != null) {
      final path = existingBySignature.filePath.trim();
      if (path.isEmpty) return existingBySignature;
      return _refreshRecoveredRecordArtifacts(
        existingBySignature,
        File(path),
        backendLookup: backendLookup,
      );
    }

    final result = await _recoverDownloadedFilesInternal(
      requestStorageAccess: false,
      preferredDisplayName: displayName,
      preferredSizeBytes: sizeBytes,
      stopAfterPreferredMatch: true,
      backendLookup: backendLookup,
    );
    return result.preferredRecord;
  }

  /// 判断指定条目是否已存在目标清晰度的离线副本。
  bool hasDownloadedResolution(
    String itemGuid,
    String resolution, {
    String mediaGuid = '',
  }) {
    final normalizedItemGuid = itemGuid.trim();
    final normalizedMediaGuid = mediaGuid.trim();
    final normalizedResolution = _normalizeResolutionKey(resolution);
    if (normalizedItemGuid.isEmpty || normalizedResolution.isEmpty) {
      return false;
    }
    for (final record in _records) {
      if (record.itemGuid != normalizedItemGuid) continue;
      if (normalizedMediaGuid.isNotEmpty &&
          record.mediaGuid.trim() != normalizedMediaGuid) {
        continue;
      }
      if (!_isDownloadedRecordAvailable(record)) continue;
      if (_normalizeResolutionKey(record.resolution) == normalizedResolution) {
        return true;
      }
    }
    return false;
  }

  /// 删除已下载记录及其关联文件，并返回实际清理数量。
  Future<int> clearDownloadedRecords({Iterable<String>? recordIds}) async {
    await initialize();
    final targetIds = recordIds
        ?.map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final targets = _records
        .where((record) {
          if (!_isDownloadedRecordAvailable(record)) return false;
          return targetIds == null || targetIds.contains(record.id);
        })
        .toList(growable: false);
    if (targets.isEmpty) return 0;

    final remainingGroupDirectories = _records
        .where(
          (record) =>
              !targets.any((target) => target.id == record.id) &&
              record.filePath.trim().isNotEmpty,
        )
        .map((record) => _recoveredGroupDirectoryForVideo(record.filePath).path)
        .toSet();
    final affectedGroupDirectories = <String>{};

    for (final record in targets) {
      _cancelTokens.remove(record.id)?.cancel();
      _clearDownloadSpeed(record.id);
      _stopDownloadTaskProgressPolling(record.id);
      final path = record.filePath.trim();
      if (path.isEmpty) continue;
      affectedGroupDirectories.add(_recoveredGroupDirectoryForVideo(path).path);
      await _deleteRecordArtifacts(record);
    }

    _records.removeWhere(
      (record) => targets.any((target) => target.id == record.id),
    );
    for (final groupDirectory in affectedGroupDirectories) {
      if (remainingGroupDirectories.contains(groupDirectory)) continue;
      await _deleteSharedGroupArtwork(groupDirectory);
      await _deleteEmptyDirectoriesUpward(Directory(groupDirectory));
    }
    _sortRecords();
    notifyListeners();
    await _persist();
    return targets.length;
  }

  /// 暂停指定下载任务，保留已下载的部分文件并通知服务端取消。
  Future<void> pauseDownload(NasProvider provider, String recordId) async {
    await initialize();
    final index = _records.indexWhere((record) => record.id == recordId);
    if (index < 0) {
      debugPrint('[DL] pause: record not found id=$recordId');
      return;
    }
    final record = _records[index];
    if (record.status != DownloadTaskStatus.downloading) {
      debugPrint(
        '[DL] pause: status not downloading (current=${record.status.storageValue}) id=$recordId',
      );
      return;
    }
    debugPrint('[DL] pause: cancel token and mark paused id=$recordId');
    _cancelTokens.remove(recordId)?.cancel();
    _clearDownloadSpeed(recordId);
    _stopDownloadTaskProgressPolling(recordId);
    _records[index] = record.copyWith(
      status: DownloadTaskStatus.paused,
      errorMessage: '',
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    _sortRecords();
    notifyListeners();
    await _persist();
  }

  /// 恢复已暂停的下载任务，从断点继续。
  Future<void> resumeDownload(NasProvider provider, String recordId) async {
    await initialize();
    final index = _records.indexWhere((record) => record.id == recordId);
    if (index < 0) {
      debugPrint('[DL] resume: record not found id=$recordId');
      return;
    }
    final pausedRecord = _records[index];
    if (pausedRecord.status != DownloadTaskStatus.paused) {
      debugPrint(
        '[DL] resume: status not paused (current=${pausedRecord.status.storageValue}) id=$recordId',
      );
      return;
    }

    final file = File(pausedRecord.filePath);
    final resumeOffset = file.existsSync() ? file.lengthSync() : 0;
    debugPrint(
      '[DL] resume: fileExists=${file.existsSync()} fileSize=$resumeOffset totalBytes=${pausedRecord.totalBytes} downloadedBytes=${pausedRecord.downloadedBytes}',
    );

    final api = FeiniuApi(provider);

    // Use the existing server-side task — official flow reuses the same
    // task ID across pause/resume cycles. Only create a new task if the
    // original was never created or expired.
    var effectiveTaskId = pausedRecord.remoteTaskId.trim();
    if (effectiveTaskId.isEmpty) {
      debugPrint('[DL] resume: remoteTaskId empty, creating new task');
      try {
        effectiveTaskId = await api.createDownloadTask(
          mediaGuid: pausedRecord.mediaGuid.trim().isNotEmpty
              ? pausedRecord.mediaGuid.trim()
              : pausedRecord.itemGuid,
          itemGuid: pausedRecord.itemGuid,
          resolution: pausedRecord.resolution,
        );
        final updatedRecord = _recordById(recordId)?.copyWith(
          remoteTaskId: effectiveTaskId,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        );
        if (updatedRecord != null) {
          _records[index] = updatedRecord;
        }
        // Poll for transcode since this is a fresh task.
        if (_shouldPollTaskProgressForResolution(pausedRecord.resolution)) {
          debugPrint('[DL] resume: transcode polling for new task');
          _startDownloadTaskProgressPolling(
            api: api,
            record: _recordById(recordId)!,
          );
          while (true) {
            final activeRecord = _recordById(recordId);
            if (activeRecord == null ||
                activeRecord.status != DownloadTaskStatus.downloading) {
              return;
            }
            try {
              final progress = await api.getDownloadTaskProgress(
                activeRecord.remoteTaskId,
              );
              if (progress != null && progress.status != 0) break;
            } catch (_) {}
            await Future<void>.delayed(_taskProgressPollInterval);
          }
        }
      } catch (error) {
        debugPrint('[DL] resume: create new task failed, error=$error');
        _setRecordPaused(index, recordId, errorMessage: '$error');
        return;
      }
    }

    final downloadUrl = api.buildDownloadTaskUrl(effectiveTaskId);
    if (downloadUrl.trim().isEmpty) {
      _setRecordPaused(
        index,
        recordId,
        errorMessage: downloadResourceUnavailableMessageToken,
      );
      return;
    }

    debugPrint(
      '[DL] resume: using existing taskId=$effectiveTaskId resumeOffset=$resumeOffset path=${file.path}',
    );

    // Always write to a .part file so partial data survives cancel.
    // We use dio.get + ResponseType.stream + manual RandomAccessFile writes
    // instead of dio.download because dio.download may remove the partial
    // file on cancel (observed on Android).
    await file.parent.create(recursive: true);
    final partFile = File('${file.path}.part');
    // If there's leftover .part data from a previous cancelled run, use it
    // as the starting offset.
    final partOffset = partFile.existsSync() ? partFile.lengthSync() : 0;
    final effectiveOffset = resumeOffset + partOffset;
    debugPrint(
      '[DL] resume: resumeOffset=$resumeOffset partOffset=$partOffset effectiveOffset=$effectiveOffset',
    );

    // Update record NOW that we know the real starting point (includes .part data).
    _records[index] = pausedRecord.copyWith(
      status: DownloadTaskStatus.downloading,
      downloadedBytes: effectiveOffset,
      errorMessage: '',
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    notifyListeners();

    RandomAccessFile? raf;
    final cancelToken = CancelToken();
    _cancelTokens[recordId] = cancelToken;

    try {
      final dio = Dio();
      final headers = api.buildPlaybackHeadersForUrl(
        downloadUrl,
        includeInitialRangeHeader: false,
        extraHeaders: <String, String>{'Range': 'bytes=$effectiveOffset-'},
      );

      // Open the .part file for append (or create if it doesn't exist).
      raf = await partFile.open(mode: FileMode.append);

      var lastPersistedBytes = effectiveOffset;
      final response = await dio.get<ResponseBody>(
        downloadUrl,
        cancelToken: cancelToken,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
          followRedirects: false,
          receiveTimeout: const Duration(hours: 2),
          sendTimeout: const Duration(seconds: 30),
          validateStatus: (status) => status == 200 || status == 206,
        ),
      );
      final stream = response.data!.stream;
      await for (final chunk in stream) {
        await raf.writeFrom(chunk);
        final now = DateTime.now().millisecondsSinceEpoch;
        final activeRecord = _recordById(recordId) ?? pausedRecord;
        // raf is opened in append mode so positionSync() already includes
        // any pre-existing .part data. Only add resumeOffset (target file).
        final absoluteReceived = resumeOffset + raf.positionSync();
        final rawFileSize = response.headers.map['file-size']?.first;
        final totalFromHeaders = rawFileSize != null
            ? int.tryParse(rawFileSize)
            : null;
        final normalizedTotal = totalFromHeaders != null && totalFromHeaders > 0
            ? totalFromHeaders
            : activeRecord.totalBytes;
        if (totalFromHeaders != null &&
            totalFromHeaders != activeRecord.totalBytes) {
          debugPrint(
            '[DL] resume: server file-size=$totalFromHeaders was=${activeRecord.totalBytes}',
          );
        }
        _updateDownloadSpeed(recordId, absoluteReceived, now);
        _stopDownloadTaskProgressPolling(recordId);
        final shouldPersist =
            absoluteReceived == normalizedTotal ||
            absoluteReceived - lastPersistedBytes >= 512 * 1024;
        final updated = activeRecord.copyWith(
          downloadedBytes: math.max(absoluteReceived, 0),
          totalBytes: normalizedTotal > 0
              ? normalizedTotal
              : activeRecord.totalBytes,
          updatedAtMs: now,
        );
        _upsertRecord(updated, persistImmediately: shouldPersist);
        if (shouldPersist) {
          lastPersistedBytes = absoluteReceived;
        }
      }
      await raf.close();
      raf = null;

      // Download completed — move .part to target.
      if (file.existsSync() && resumeOffset > 0) {
        // Append .part data to the existing partial file.
        final sink = file.openWrite(mode: FileMode.append);
        try {
          await partFile.openRead().pipe(sink);
        } finally {
          await sink.close();
        }
        await partFile.delete();
      } else {
        // No existing partial — just rename .part to target.
        if (file.existsSync()) {
          await file.delete();
        }
        await partFile.rename(file.path);
      }

      final actualBytes = await file.length();
      final completedRecord = _recordById(recordId) ?? pausedRecord;
      _upsertRecord(
        completedRecord.copyWith(
          downloadedBytes: actualBytes,
          totalBytes: actualBytes > 0
              ? actualBytes
              : completedRecord.totalBytes,
          status: DownloadTaskStatus.downloaded,
          errorMessage: '',
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
        persistImmediately: true,
      );
    } catch (error, stackTrace) {
      // Make sure the .part file is properly flushed and closed first.
      if (raf != null) {
        try {
          await raf.flush();
          await raf.close();
        } catch (_) {}
        raf = null;
      }
      final failedRecord = _recordById(recordId) ?? pausedRecord;
      final canceled = error is DioException && CancelToken.isCancel(error);
      if (!canceled) {
        await AppLogService.instance.recordWarning(
          error: error,
          stackTrace: stackTrace,
          source: 'download_resume',
          details:
              'item=${failedRecord.itemGuid} task=${failedRecord.remoteTaskId}',
        );
      }
      if (canceled && _cancelTokens[recordId] != cancelToken) {
        debugPrint(
          '[DL] resume catch: token mismatch. partFile=${partFile.existsSync()} partSize=${partFile.existsSync() ? partFile.lengthSync() : 0} targetFile=${file.existsSync()}',
        );
        return;
      }
      final totalSaved =
          (partFile.existsSync() ? partFile.lengthSync() : 0) +
          (file.existsSync() ? file.lengthSync() : 0);
      debugPrint(
        '[DL] resume catch: canceled=$canceled totalSaved=$totalSaved',
      );
      _upsertRecord(
        failedRecord.copyWith(
          status: DownloadTaskStatus.paused,
          downloadedBytes: totalSaved,
          errorMessage: canceled ? '' : '$error',
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
        persistImmediately: true,
      );
    } finally {
      if (raf != null) {
        try {
          await raf.flush();
          await raf.close();
        } catch (_) {}
      }
      _cancelTokens.remove(recordId);
    }
  }

  void _setRecordPaused(
    int index,
    String recordId, {
    String errorMessage = '',
  }) {
    final freshIndex = _records.indexWhere((record) => record.id == recordId);
    if (freshIndex < 0) return;
    _records[freshIndex] = _records[freshIndex].copyWith(
      status: DownloadTaskStatus.paused,
      errorMessage: errorMessage,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    notifyListeners();
    unawaited(_persist());
  }

  /// 删除下载中或已暂停的任务，同时取消下载并清理部分文件。
  Future<int> clearActiveDownloadRecords({Iterable<String>? recordIds}) async {
    await initialize();
    final targetIds = recordIds
        ?.map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final targets = _records
        .where((record) {
          if (record.status != DownloadTaskStatus.downloading &&
              record.status != DownloadTaskStatus.paused) {
            return false;
          }
          return targetIds == null || targetIds.contains(record.id);
        })
        .toList(growable: false);
    if (targets.isEmpty) return 0;

    final remainingGroupDirectories = _records
        .where(
          (record) =>
              !targets.any((target) => target.id == record.id) &&
              record.filePath.trim().isNotEmpty,
        )
        .map((record) => _recoveredGroupDirectoryForVideo(record.filePath).path)
        .toSet();
    final affectedGroupDirectories = <String>{};

    for (final record in targets) {
      _cancelTokens.remove(record.id)?.cancel();
      _clearDownloadSpeed(record.id);
      _stopDownloadTaskProgressPolling(record.id);
      final path = record.filePath.trim();
      if (path.isEmpty) continue;
      affectedGroupDirectories.add(_recoveredGroupDirectoryForVideo(path).path);
      // 取消下载只删了视频文件会残留专属目录 / .part / 封面（文件夹「拉屎」），
      // 这里与已下载项删除一致：清掉断点文件并递归删除整个记录目录。
      await _deleteIfExists(File('$path.part'));
      await _deleteRecordArtifacts(record);
    }

    _records.removeWhere(
      (record) => targets.any((target) => target.id == record.id),
    );
    for (final groupDirectory in affectedGroupDirectories) {
      if (remainingGroupDirectories.contains(groupDirectory)) continue;
      await _deleteSharedGroupArtwork(groupDirectory);
      await _deleteEmptyDirectoriesUpward(Directory(groupDirectory));
    }
    _sortRecords();
    notifyListeners();
    await _persist();
    return targets.length;
  }

  /// 重新拉取已下载分组的展示元数据。
  Future<void> refreshDownloadedGroupMetadata(NasProvider provider) {
    if (_pendingGroupMetadataRefresh != null) {
      return _pendingGroupMetadataRefresh!;
    }
    _pendingGroupMetadataRefresh =
        _refreshDownloadedGroupMetadataInternal(provider).whenComplete(() {
          _pendingGroupMetadataRefresh = null;
        });
    return _pendingGroupMetadataRefresh!;
  }

  /// 创建或复用离线下载任务，并返回启动结果。
  ///
  /// 同一 条目+版本+清晰度 的并发调用会折叠到同一个在途任务上：快速双击
  /// 「下载」不会再生成两个服务端任务 / 两个下载目录。
  Future<DownloadStartResult> startDownload({
    required NasProvider provider,
    required String itemGuid,
    required String resolution,
    String mediaGuid = '',
    required String title,
    required String groupId,
    required String groupTitle,
    required String durationText,
    required List<String> posterUrls,
    List<String> groupPosterUrls = const <String>[],
    SubtitleTrackOption? preferredSubtitleTrack,
    String preferredSubtitleGuid = '',
  }) {
    final dedupKey =
        '${itemGuid.trim()}|${mediaGuid.trim()}|${resolution.trim().toLowerCase()}';
    final inFlight = _inFlightStarts[dedupKey];
    if (inFlight != null) return inFlight;
    final future = _runStartDownload(
      provider: provider,
      itemGuid: itemGuid,
      resolution: resolution,
      mediaGuid: mediaGuid,
      title: title,
      groupId: groupId,
      groupTitle: groupTitle,
      durationText: durationText,
      posterUrls: posterUrls,
      groupPosterUrls: groupPosterUrls,
      preferredSubtitleTrack: preferredSubtitleTrack,
      preferredSubtitleGuid: preferredSubtitleGuid,
    );
    _inFlightStarts[dedupKey] = future;
    return future.whenComplete(() {
      if (identical(_inFlightStarts[dedupKey], future)) {
        _inFlightStarts.remove(dedupKey);
      }
    });
  }

  Future<DownloadStartResult> _runStartDownload({
    required NasProvider provider,
    required String itemGuid,
    required String resolution,
    String mediaGuid = '',
    required String title,
    required String groupId,
    required String groupTitle,
    required String durationText,
    required List<String> posterUrls,
    List<String> groupPosterUrls = const <String>[],
    SubtitleTrackOption? preferredSubtitleTrack,
    String preferredSubtitleGuid = '',
  }) async {
    await initialize();

    final normalizedItemGuid = itemGuid.trim();
    final normalizedResolution = resolution.trim();
    final normalizedMediaGuid = mediaGuid.trim();
    if (normalizedItemGuid.isEmpty || normalizedResolution.isEmpty) {
      throw AppException.api(
        action: 'download start',
        message: 'Missing download parameters',
      );
    }

    final existingDownloaded = _findLatestRecord(
      itemGuid: normalizedItemGuid,
      mediaGuid: normalizedMediaGuid,
      resolution: normalizedResolution,
      status: DownloadTaskStatus.downloaded,
    );
    if (existingDownloaded != null &&
        existingDownloaded.filePath.trim().isNotEmpty &&
        File(existingDownloaded.filePath).existsSync()) {
      return DownloadStartResult(
        state: DownloadStartState.downloaded,
        record: existingDownloaded,
      );
    }

    final existingDownloading = _findLatestRecord(
      itemGuid: normalizedItemGuid,
      mediaGuid: normalizedMediaGuid,
      resolution: normalizedResolution,
      status: DownloadTaskStatus.downloading,
    );
    if (existingDownloading != null) {
      return DownloadStartResult(
        state: DownloadStartState.downloading,
        record: existingDownloading,
      );
    }
    final existingPaused = _findLatestRecord(
      itemGuid: normalizedItemGuid,
      mediaGuid: normalizedMediaGuid,
      resolution: normalizedResolution,
      status: DownloadTaskStatus.paused,
    );
    if (existingPaused != null) {
      return DownloadStartResult(
        state: DownloadStartState.downloading,
        record: existingPaused,
      );
    }

    final api = FeiniuApi(provider);
    final streamData = await api.getStreamTrackData(normalizedItemGuid);
    final matchedOption = _pickStreamOption(
      streamData.options,
      resolution: normalizedResolution,
      mediaGuid: normalizedMediaGuid,
    );

    // Use the matched stream option for metadata (file info, subtitles, etc.)
    // but fall back to the first available option if no exact match.
    final metadataOption =
        matchedOption ??
        (streamData.options.isNotEmpty ? streamData.options.first : null);

    final fileInfo = metadataOption != null
        ? streamData.fileForMedia(metadataOption.mediaGuid)
        : null;
    final resolvedSubtitleTrack = metadataOption != null
        ? _resolveDownloadSubtitleTrack(
            streamData.subtitlesForMedia(metadataOption.mediaGuid),
            preferredSubtitleTrack: preferredSubtitleTrack,
            preferredSubtitleGuid: preferredSubtitleGuid,
          )
        : null;
    final persistedAudioTracks = metadataOption != null
        ? List<AudioTrackOption>.from(
            streamData.audiosForMedia(metadataOption.mediaGuid),
          )
        : const <AudioTrackOption>[];
    final persistedSubtitleTracks = metadataOption != null
        ? List<SubtitleTrackOption>.from(
            streamData.subtitlesForMedia(metadataOption.mediaGuid),
          )
        : const <SubtitleTrackOption>[];

    // Only attempt cache import when the stream option exactly matches the
    // user-selected download resolution — prevents cross-resolution cache reuse.
    if (matchedOption != null) {
      final importedFromCache = await importCachedMedia(
        provider: provider,
        identity: CachedMediaSourceIdentity(
          itemGuid: normalizedItemGuid,
          mediaGuid: matchedOption.mediaGuid,
          videoGuid: matchedOption.videoGuid,
        ),
        resolution: normalizedResolution,
        title: title,
        groupId: groupId,
        groupTitle: groupTitle,
        durationText: durationText,
        posterUrls: posterUrls,
        groupPosterUrls: groupPosterUrls,
        fileInfo: fileInfo,
        audioTracks: persistedAudioTracks,
        subtitleTracks: persistedSubtitleTracks,
        subtitleTrack: resolvedSubtitleTrack,
      );
      if (importedFromCache != null) {
        return importedFromCache;
      }
    }

    // Always use the user-selected resolution for the download task.
    // stream/list resolutionType must NOT override it.
    final taskMediaGuid = metadataOption?.mediaGuid ?? normalizedItemGuid;
    final remoteTaskId = await api.createDownloadTask(
      mediaGuid: taskMediaGuid,
      itemGuid: normalizedItemGuid,
      resolution: normalizedResolution,
    );
    final downloadUrl = api.buildDownloadTaskUrl(remoteTaskId);
    if (downloadUrl.trim().isEmpty) {
      throw AppException.api(
        action: 'download start',
        message: 'Missing download task url',
      );
    }

    final safeFileName = _resolveFileName(
      fileInfo,
      title,
      normalizedResolution,
    );
    final filePath = await _buildDownloadFilePath(
      groupTitle: groupTitle,
      fileName: safeFileName,
    );
    final cachedPosterUrls = await _cacheArtworkUrls(
      provider: provider,
      sourceUrls: posterUrls,
      videoFilePath: filePath,
      suffix: 'cover',
    );
    final cachedGroupPosterUrls =
        _shouldReuseEpisodeArtworkForGroup(
          posterUrls: posterUrls,
          groupPosterUrls: groupPosterUrls,
        )
        ? cachedPosterUrls
        : await _cacheArtworkUrls(
            provider: provider,
            sourceUrls: groupPosterUrls,
            videoFilePath: filePath,
            suffix: 'group_cover',
          );

    final now = DateTime.now().millisecondsSinceEpoch;
    final record = DownloadTaskRecord(
      id: _buildId(),
      remoteTaskId: remoteTaskId,
      itemGuid: normalizedItemGuid,
      mediaGuid: taskMediaGuid,
      groupId: groupId.trim().isEmpty ? normalizedItemGuid : groupId.trim(),
      groupTitle: groupTitle.trim().isEmpty ? title.trim() : groupTitle.trim(),
      title: title.trim(),
      durationText: durationText.trim(),
      posterUrls: cachedPosterUrls,
      groupPosterUrls: cachedGroupPosterUrls,
      resolution: normalizedResolution,
      fileName: safeFileName,
      filePath: filePath,
      totalBytes: fileInfo?.size ?? 0,
      downloadedBytes: 0,
      audioTracks: persistedAudioTracks,
      subtitleTracks: persistedSubtitleTracks,
      status: DownloadTaskStatus.downloading,
      errorMessage: '',
      createdAtMs: now,
      updatedAtMs: now,
    );
    _upsertRecord(record, persistImmediately: true);
    _clearDownloadSpeed(record.id);
    unawaited(_prefetchDanmakuForDownload(provider: provider, record: record));
    final sourceResolution = metadataOption?.resolutionType;
    final needsTranscode = _shouldPollTaskProgressForResolution(
      record.resolution,
      sourceResolution: sourceResolution,
    );
    if (needsTranscode) {
      _startDownloadTaskProgressPolling(api: api, record: record);
    }

    unawaited(
      needsTranscode
          ? _waitForTranscodeThenDownload(
              api,
              record,
              downloadUrl,
              subtitleTrack: resolvedSubtitleTrack,
            )
          : _performDownload(
              api,
              record,
              downloadUrl,
              subtitleTrack: resolvedSubtitleTrack,
            ),
    );
    return DownloadStartResult(
      state: DownloadStartState.started,
      record: record,
    );
  }

  /// Polls download task progress until transcode completes, then starts
  /// the actual download. For non-transcode tasks use _performDownload directly.
  Future<void> _waitForTranscodeThenDownload(
    FeiniuApi api,
    DownloadTaskRecord record,
    String downloadUrl, {
    SubtitleTrackOption? subtitleTrack,
  }) async {
    // Brief initial delay to avoid immediate API spam before transcode starts.
    await Future<void>.delayed(const Duration(seconds: 1));

    while (true) {
      final activeRecord = _recordById(record.id);
      if (activeRecord == null ||
          activeRecord.status != DownloadTaskStatus.downloading) {
        return;
      }
      try {
        final progress = await api.getDownloadTaskProgress(
          activeRecord.remoteTaskId,
        );
        // status != 0 indicates transcode has finished (ready or errored).
        if (progress != null && progress.status != 0) {
          break;
        }
      } catch (_) {
        // Polling error – retry after delay.
      }
      await Future<void>.delayed(_taskProgressPollInterval);
    }

    final activeRecord = _recordById(record.id);
    if (activeRecord == null ||
        activeRecord.status != DownloadTaskStatus.downloading) {
      return;
    }
    unawaited(
      _performDownload(
        api,
        activeRecord,
        downloadUrl,
        subtitleTrack: subtitleTrack,
      ),
    );
  }

  /// 将已存在的本地缓存媒体导入为下载记录。
  Future<DownloadStartResult?> importCachedMedia({
    NasProvider? provider,
    required CachedMediaSourceIdentity identity,
    required String resolution,
    required String title,
    required String groupId,
    required String groupTitle,
    required String durationText,
    required List<String> posterUrls,
    required List<String> groupPosterUrls,
    StreamFileInfo? fileInfo,
    List<AudioTrackOption> audioTracks = const <AudioTrackOption>[],
    List<SubtitleTrackOption> subtitleTracks = const <SubtitleTrackOption>[],
    SubtitleTrackOption? subtitleTrack,
    String? subtitleFilePath,
  }) async {
    await initialize();
    final itemGuid = identity.itemGuid.trim();
    final mediaGuid = identity.mediaGuid.trim();
    final videoGuid = identity.videoGuid.trim();
    final normalizedResolution = _normalizeImportedCacheResolution(resolution);
    if (itemGuid.isEmpty || mediaGuid.isEmpty || videoGuid.isEmpty) {
      return null;
    }

    final existingDownloaded = _findLatestRecord(
      itemGuid: itemGuid,
      resolution: normalizedResolution,
      status: DownloadTaskStatus.downloaded,
    );
    if (existingDownloaded != null &&
        existingDownloaded.filePath.trim().isNotEmpty &&
        File(existingDownloaded.filePath).existsSync()) {
      await _clearImportedCacheEntry(identity);
      return DownloadStartResult(
        state: DownloadStartState.downloaded,
        record: existingDownloaded,
      );
    }

    final existingDownloading = _findLatestRecord(
      itemGuid: itemGuid,
      resolution: normalizedResolution,
      status: DownloadTaskStatus.downloading,
    );
    if (existingDownloading != null) {
      return DownloadStartResult(
        state: DownloadStartState.downloading,
        record: existingDownloading,
      );
    }
    final existingPaused = _findLatestRecord(
      itemGuid: itemGuid,
      resolution: normalizedResolution,
      status: DownloadTaskStatus.paused,
    );
    if (existingPaused != null) {
      return DownloadStartResult(
        state: DownloadStartState.downloading,
        record: existingPaused,
      );
    }

    final storageService = StorageManagementService.instance;
    CachedMediaDownloadability downloadability;
    try {
      downloadability = await storageService.canPromoteCachedMedia(identity);
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'check cached media promotability',
        id: itemGuid,
        error: error,
        stackTrace: stackTrace,
        source: 'download_task_service',
        details: 'mediaGuid=$mediaGuid | videoGuid=$videoGuid',
      );
      return null;
    }
    if (!downloadability.found || !downloadability.downloadable) {
      return null;
    }

    CachedMediaPromoteResult promoteResult;
    try {
      promoteResult = await storageService.promoteCachedMedia(
        identity,
        targetMode: 'appExternalMovies',
      );
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'promote cached media',
        id: itemGuid,
        error: error,
        stackTrace: stackTrace,
        source: 'download_task_service',
        details: 'mediaGuid=$mediaGuid | videoGuid=$videoGuid',
      );
      return null;
    }
    if (!promoteResult.success || promoteResult.path.trim().isEmpty) {
      return null;
    }

    final promotedFile = File(promoteResult.path.trim());
    if (!promotedFile.existsSync()) {
      return null;
    }

    String? finalFilePath;
    var finalVideoPath = promotedFile.path;
    var finalVideoFileName = promoteResult.fileName.trim();
    try {
      final importedFileName = _resolveImportedFileName(
        promotedFileName: promoteResult.fileName,
        suggestedFileName: downloadability.suggestedFileName,
        fileInfo: fileInfo,
        title: title,
        resolution: normalizedResolution,
      );
      try {
        finalFilePath = await _buildDownloadFilePath(
          groupTitle: groupTitle,
          fileName: importedFileName,
        );
        await _relocateImportedFile(promotedFile.path, finalFilePath);
        finalVideoPath = finalFilePath;
        finalVideoFileName = importedFileName;
      } catch (error, stackTrace) {
        await AppLogService.instance.recordWarning(
          error: error,
          stackTrace: stackTrace,
          source: 'cache-import-relocate',
          details:
              'item=$itemGuid media=$mediaGuid video=$videoGuid fallback=promoted_path',
        );
        finalVideoPath = promotedFile.path;
        finalVideoFileName = promotedFile.uri.pathSegments.isNotEmpty
            ? promotedFile.uri.pathSegments.last
            : promotedFile.path.split(Platform.pathSeparator).last;
      }
      if (finalVideoPath.trim().isEmpty) {
        return null;
      }
      final resolvedVideoPath = finalVideoPath;
      final resolvedFileName = finalVideoFileName.trim().isEmpty
          ? importedFileName
          : finalVideoFileName.trim();

      final importArtwork = provider == null
          ? _ImportedCacheArtwork(
              posterUrls: posterUrls,
              groupPosterUrls: groupPosterUrls.isNotEmpty
                  ? groupPosterUrls
                  : posterUrls,
            )
          : await _resolveImportedCacheArtwork(
              provider: provider,
              itemGuid: itemGuid,
              fallbackPosterUrls: posterUrls,
              fallbackGroupPosterUrls: groupPosterUrls,
            );

      final cachedPosterUrls = provider == null
          ? importArtwork.posterUrls
          : await _cacheArtworkUrls(
              provider: provider,
              sourceUrls: importArtwork.posterUrls,
              videoFilePath: resolvedVideoPath,
              suffix: 'cover',
            );
      final cachedGroupPosterUrls =
          _shouldReuseEpisodeArtworkForGroup(
            posterUrls: importArtwork.posterUrls,
            groupPosterUrls: importArtwork.groupPosterUrls,
          )
          ? cachedPosterUrls
          : (provider == null
                ? importArtwork.groupPosterUrls
                : await _cacheArtworkUrls(
                    provider: provider,
                    sourceUrls: importArtwork.groupPosterUrls,
                    videoFilePath: resolvedVideoPath,
                    suffix: 'group_cover',
                  ));

      final actualBytes = await File(resolvedVideoPath).length();
      final api = provider == null ? null : FeiniuApi(provider);
      StreamTrackData? importedTrackData;
      if (api != null &&
          (audioTracks.isEmpty ||
              subtitleTracks.isEmpty ||
              subtitleTrack == null)) {
        try {
          importedTrackData = await api.getStreamTrackData(itemGuid);
        } catch (_) {}
      }
      final persistedAudioTracks = audioTracks.isNotEmpty
          ? audioTracks
          : (mediaGuid.isEmpty
                ? const <AudioTrackOption>[]
                : importedTrackData?.audiosForMedia(mediaGuid) ??
                      const <AudioTrackOption>[]);
      final persistedSubtitleTracks = subtitleTracks.isNotEmpty
          ? subtitleTracks
          : (mediaGuid.isEmpty
                ? const <SubtitleTrackOption>[]
                : importedTrackData?.subtitlesForMedia(mediaGuid) ??
                      const <SubtitleTrackOption>[]);
      final resolvedSubtitleTrack =
          subtitleTrack ??
          _resolveDownloadSubtitleTrack(persistedSubtitleTracks) ??
          await _resolveImportedCacheSubtitleTrack(
            api: api,
            itemGuid: itemGuid,
            mediaGuid: mediaGuid,
          );
      var record = DownloadTaskRecord(
        id: _buildId(),
        remoteTaskId: downloadability.resourceKey.trim().isEmpty
            ? 'cache_import'
            : 'cache:${downloadability.resourceKey.trim()}',
        itemGuid: itemGuid,
        mediaGuid: mediaGuid,
        groupId: groupId.trim().isEmpty ? itemGuid : groupId.trim(),
        groupTitle: groupTitle.trim().isEmpty
            ? title.trim()
            : groupTitle.trim(),
        title: title.trim(),
        durationText: durationText.trim(),
        posterUrls: cachedPosterUrls,
        groupPosterUrls: cachedGroupPosterUrls,
        resolution: normalizedResolution,
        fileName: resolvedFileName,
        filePath: resolvedVideoPath,
        totalBytes: math.max(
          actualBytes,
          math.max(downloadability.totalBytes, fileInfo?.size ?? 0),
        ),
        downloadedBytes: actualBytes,
        audioTracks: persistedAudioTracks,
        subtitleTracks: persistedSubtitleTracks,
        status: DownloadTaskStatus.downloaded,
        errorMessage: '',
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      final materializedSubtitlePath = await _materializeSubtitleForRecord(
        api: api,
        record: record,
        subtitleTrack: resolvedSubtitleTrack,
        localSubtitleFilePath: subtitleFilePath,
      );
      final refreshedBytes = await File(resolvedVideoPath).length();
      record = record.copyWith(
        totalBytes: math.max(
          refreshedBytes,
          math.max(downloadability.totalBytes, fileInfo?.size ?? 0),
        ),
        downloadedBytes: refreshedBytes,
        subtitleTracks: _persistedSubtitleTracksForRecord(
          record: record,
          subtitleTracks: record.subtitleTracks,
          subtitleTrack: resolvedSubtitleTrack,
          localSubtitlePath: materializedSubtitlePath,
        ),
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      _upsertRecord(record, persistImmediately: true);
      if (provider != null) {
        unawaited(
          _prefetchDanmakuForDownload(provider: provider, record: record),
        );
      }
      await _clearImportedCacheEntry(
        identity,
        resolvedResourceKey: downloadability.resourceKey,
      );
      return DownloadStartResult(
        state: DownloadStartState.importedFromCache,
        record: record,
      );
    } catch (_) {
      if (finalFilePath != null) {
        await _deleteIfExists(File(finalFilePath));
      }
      if (promotedFile.existsSync() && promotedFile.path != finalVideoPath) {
        await _deleteIfExists(promotedFile);
      }
      return null;
    } finally {
      if (promotedFile.existsSync() && promotedFile.path != finalVideoPath) {
        await _deleteIfExists(promotedFile);
      }
    }
  }

  Future<void> _performDownload(
    FeiniuApi api,
    DownloadTaskRecord record,
    String downloadUrl, {
    SubtitleTrackOption? subtitleTrack,
  }) async {
    final file = File(record.filePath);
    final cancelToken = CancelToken();
    _cancelTokens[record.id] = cancelToken;
    RandomAccessFile? raf;
    try {
      await file.parent.create(recursive: true);
      final partFile = File('${file.path}.part');
      // If there's a leftover .part from a cancelled attempt, use it.
      final startingOffset = partFile.existsSync() ? partFile.lengthSync() : 0;
      if (file.existsSync() && startingOffset == 0) {
        debugPrint(
          '[DL] _performDownload: deleting stale target path=${file.path}',
        );
        await file.delete();
      }
      debugPrint(
        '[DL] _performDownload: starting download path=${file.path} startingOffset=$startingOffset',
      );

      final dio = Dio();
      final headers = api.buildPlaybackHeadersForUrl(
        downloadUrl,
        includeInitialRangeHeader: false,
        extraHeaders: <String, String>{'Range': 'bytes=$startingOffset-'},
      );

      raf = await partFile.open(mode: FileMode.append);
      var lastPersistedBytes = startingOffset;

      // 服务端下载任务在 createDownloadTask 之后可能需要片刻才就绪；过早请求会拿到
      // 非 200/206 状态，旧逻辑会把任务直接打成「暂停」——表现为下载源画质时一进去
      // 就是暂停、要手动点继续。这里对首个连接做有限次重试，让任务就绪后自动开始，
      // 同时若任务在此期间被暂停/删除则立即放弃，不会卡死。
      Response<ResponseBody>? response;
      Object? lastConnectError;
      for (var attempt = 0; attempt < 5; attempt++) {
        try {
          response = await dio.get<ResponseBody>(
            downloadUrl,
            cancelToken: cancelToken,
            options: Options(
              headers: headers,
              responseType: ResponseType.stream,
              followRedirects: false,
              receiveTimeout: const Duration(hours: 2),
              sendTimeout: const Duration(seconds: 30),
              validateStatus: (status) => status == 200 || status == 206,
            ),
          );
          break;
        } catch (error) {
          if (error is DioException && CancelToken.isCancel(error)) rethrow;
          lastConnectError = error;
          final current = _recordById(record.id);
          if (current == null ||
              current.status != DownloadTaskStatus.downloading) {
            rethrow;
          }
          await Future<void>.delayed(
            Duration(milliseconds: 800 * (attempt + 1)),
          );
        }
      }
      if (response == null) {
        throw lastConnectError ?? Exception('download connection failed');
      }
      final stream = response.data!.stream;
      await for (final chunk in stream) {
        await raf.writeFrom(chunk);
        final now = DateTime.now().millisecondsSinceEpoch;
        final activeRecord = _recordById(record.id) ?? record;
        // raf is opened in append mode so positionSync() already includes
        // any pre-existing .part data.
        final absoluteReceived = raf.positionSync();
        final rawFileSize = response.headers.map['file-size']?.first;
        final totalFromHeaders = rawFileSize != null
            ? int.tryParse(rawFileSize)
            : null;
        final normalizedTotal = totalFromHeaders != null && totalFromHeaders > 0
            ? totalFromHeaders
            : activeRecord.totalBytes;
        _updateDownloadSpeed(record.id, absoluteReceived, now);
        if (absoluteReceived > 0) {
          _stopDownloadTaskProgressPolling(record.id);
        }
        final shouldPersist =
            absoluteReceived == normalizedTotal ||
            absoluteReceived - lastPersistedBytes >= 512 * 1024;
        final updated = activeRecord.copyWith(
          downloadedBytes: math.max(absoluteReceived, 0),
          totalBytes: normalizedTotal > 0
              ? normalizedTotal
              : activeRecord.totalBytes,
          updatedAtMs: now,
        );
        _upsertRecord(updated, persistImmediately: shouldPersist);
        if (shouldPersist) {
          lastPersistedBytes = absoluteReceived;
        }
      }
      await raf.flush();
      await raf.close();
      raf = null;

      // Move .part to target.
      if (file.existsSync()) {
        await file.delete();
      }
      await partFile.rename(file.path);

      final actualBytes = await file.length();
      final completedRecord = _recordById(record.id) ?? record;
      final materializedSubtitlePath = await _materializeSubtitleForRecord(
        api: api,
        record: completedRecord,
        subtitleTrack: subtitleTrack,
      );
      _upsertRecord(
        completedRecord.copyWith(
          downloadedBytes: actualBytes,
          totalBytes: actualBytes > 0
              ? actualBytes
              : completedRecord.totalBytes,
          subtitleTracks: _persistedSubtitleTracksForRecord(
            record: completedRecord,
            subtitleTracks: completedRecord.subtitleTracks,
            subtitleTrack: subtitleTrack,
            localSubtitlePath: materializedSubtitlePath,
          ),
          status: DownloadTaskStatus.downloaded,
          errorMessage: '',
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
        persistImmediately: true,
      );
    } catch (error, stackTrace) {
      // Flush and close the .part file so data is preserved on cancel.
      if (raf != null) {
        try {
          await raf.flush();
          await raf.close();
        } catch (_) {}
        raf = null;
      }
      final failedRecord = _recordById(record.id) ?? record;
      final canceled = error is DioException && CancelToken.isCancel(error);
      if (!canceled) {
        await AppLogService.instance.recordWarning(
          error: error,
          stackTrace: stackTrace,
          source: 'download',
          details:
              'item=${failedRecord.itemGuid} task=${failedRecord.remoteTaskId}',
        );
      }
      if (canceled && _cancelTokens[record.id] != cancelToken) {
        debugPrint(
          '[DL] _performDownload catch: token mismatch. currentStatus=${failedRecord.status.storageValue}',
        );
        return;
      }
      // .part file has the partial data; the target file may also exist.
      final partFile = File('${file.path}.part');
      final totalSaved =
          (partFile.existsSync() ? partFile.lengthSync() : 0) +
          (file.existsSync() ? file.lengthSync() : 0);
      debugPrint(
        '[DL] _performDownload catch: canceled=$canceled totalSaved=$totalSaved',
      );
      _upsertRecord(
        failedRecord.copyWith(
          status: DownloadTaskStatus.paused,
          downloadedBytes: totalSaved,
          errorMessage: canceled ? '' : '$error',
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
        persistImmediately: true,
      );
    } finally {
      if (raf != null) {
        try {
          await raf.flush();
          await raf.close();
        } catch (_) {}
      }
      _cancelTokens.remove(record.id);
    }
  }

  static const String _recordsFileName = 'download_task_records_v1.json';
  static Future<String>? _recordsPathFuture;
  Future<File> _recordsFile() async {
    final debugPath = _debugRecordsFilePath;
    if (debugPath != null) {
      return File(debugPath);
    }
    final path = await (_recordsPathFuture ??= () async {
      final dir = await getDatabasesPath();
      return '$dir/$_recordsFileName';
    }());
    return File(path);
  }

  /// 优先读文件；文件不存在则从旧 SharedPreferences 迁移一次并删除该 prefs 大 blob
  /// (实测 49KB，被 AppThemeProvider 每 1.5s 的 reload 反复解码)。
  Future<String?> _readPersistedRaw() async {
    final file = await _recordsFile();
    if (await file.exists()) return file.readAsString();
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(_prefsKey);
      if (legacy != null && legacy.trim().isNotEmpty) {
        await file.writeAsString(legacy, flush: true);
      }
      if (prefs.containsKey(_prefsKey)) await prefs.remove(_prefsKey);
      return legacy;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadFromStorage() async {
    try {
      final raw = await _readPersistedRaw();
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _records
        ..clear()
        ..addAll(
          decoded
              .whereType<Map>()
              .map((value) => value.cast<String, dynamic>())
              .map(DownloadTaskRecord.fromJson)
              .where((record) => record.id.trim().isNotEmpty),
        );
      for (int index = 0; index < _records.length; index++) {
        final record = _records[index];
        if (record.status == DownloadTaskStatus.downloading) {
          final fileExists =
              record.filePath.trim().isNotEmpty &&
              File(record.filePath).existsSync();
          _records[index] = record.copyWith(
            status: fileExists
                ? DownloadTaskStatus.paused
                : DownloadTaskStatus.failed,
            errorMessage: fileExists ? '' : _interruptedMessage,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          );
        }
      }
      await _normalizeLegacyGroupArtwork();
      _sortRecords();
      notifyListeners();
      await _persist();
      for (final record in _records) {
        if (_isDownloadedRecordAvailable(record)) {
          unawaited(_writeRecoveryMetadata(record));
        }
      }
    } catch (_) {
      _records.clear();
    }
  }

  Future<void> _upsertRecord(
    DownloadTaskRecord record, {
    bool persistImmediately = false,
  }) {
    if (record.status != DownloadTaskStatus.downloading) {
      _clearDownloadSpeed(record.id);
      _stopDownloadTaskProgressPolling(record.id);
    }
    final index = _records.indexWhere((entry) => entry.id == record.id);
    if (index >= 0) {
      _records[index] = record;
    } else {
      _records.add(record);
    }
    _sortRecords();
    notifyListeners();
    Future<void> persistFuture;
    if (persistImmediately) {
      _persistTimer?.cancel();
      _persistTimer = null;
      persistFuture = _persist();
    } else {
      _schedulePersist();
      persistFuture = Future<void>.value();
    }
    if (_isDownloadedRecordAvailable(record)) {
      unawaited(_writeRecoveryMetadata(record));
    }
    return persistFuture;
  }

  void _sortRecords() {
    _records.sort(compareDownloadTaskRecordsForDisplay);
  }

  List<DownloadTaskRecord> _sortedRecords(
    Iterable<DownloadTaskRecord> records, {
    DownloadTaskStatus? status,
  }) {
    final sorted = List<DownloadTaskRecord>.from(records);
    sorted.sort(
      (lhs, rhs) =>
          compareDownloadTaskRecordsForDisplay(lhs, rhs, statusHint: status),
    );
    return sorted;
  }

  DownloadTaskRecord? _recordById(String recordId) {
    final targetId = recordId.trim();
    if (targetId.isEmpty) return null;
    for (final entry in _records) {
      if (entry.id == targetId) return entry;
    }
    return null;
  }

  Future<DownloadRecoveryResult> _recoverDownloadedFilesInternal({
    required bool requestStorageAccess,
    String preferredDisplayName = '',
    int preferredSizeBytes = 0,
    bool stopAfterPreferredMatch = false,
    _RecoveredBackendLookup? backendLookup,
  }) async {
    final roots = await _downloadRecoveryRoots(
      requestStorageAccess: requestStorageAccess,
    );
    if (roots.isEmpty) {
      return const DownloadRecoveryResult(
        scannedVideoCount: 0,
        importedCount: 0,
        alreadyTrackedCount: 0,
        skippedCount: 0,
      );
    }

    var scannedVideoCount = 0;
    var importedCount = 0;
    var alreadyTrackedCount = 0;
    var skippedCount = 0;
    DownloadTaskRecord? preferredRecord;
    final seenPaths = <String>{};
    final scanOnlyPreferred =
        stopAfterPreferredMatch &&
        (preferredDisplayName.trim().isNotEmpty || preferredSizeBytes > 0);

    for (final root in roots) {
      try {
        if (!await root.exists()) continue;
        await for (final entity in root.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is! File) continue;
          final normalizedPath = _normalizeFilePathForComparison(entity.path);
          if (normalizedPath.isEmpty || !seenPaths.add(normalizedPath)) {
            continue;
          }
          if (!_isRecoverableVideoFileName(entity.path)) continue;
          scannedVideoCount += 1;
          if (scanOnlyPreferred &&
              !await _matchesRecoveredFileSignature(
                entity,
                displayName: preferredDisplayName,
                sizeBytes: preferredSizeBytes,
              )) {
            continue;
          }

          final existing = downloadedRecordForFilePath(entity.path);
          if (existing != null) {
            alreadyTrackedCount += 1;
            final refreshed = await _refreshRecoveredRecordArtifacts(
              existing,
              entity,
              backendLookup: backendLookup,
            );
            if (await _recordMatchesRecoveredFileSignature(
              refreshed,
              displayName: preferredDisplayName,
              sizeBytes: preferredSizeBytes,
            )) {
              preferredRecord ??= refreshed;
              if (stopAfterPreferredMatch) {
                return DownloadRecoveryResult(
                  scannedVideoCount: scannedVideoCount,
                  importedCount: importedCount,
                  alreadyTrackedCount: alreadyTrackedCount,
                  skippedCount: skippedCount,
                  preferredRecord: preferredRecord,
                );
              }
            }
            continue;
          }

          final imported = await _importRecoveredVideoFile(
            entity,
            expectedDisplayName: preferredDisplayName,
            expectedSizeBytes: preferredSizeBytes,
            backendLookup: backendLookup,
          );
          if (imported == null) {
            skippedCount += 1;
            continue;
          }
          importedCount += 1;
          if (await _recordMatchesRecoveredFileSignature(
            imported,
            displayName: preferredDisplayName,
            sizeBytes: preferredSizeBytes,
          )) {
            preferredRecord ??= imported;
            if (stopAfterPreferredMatch) {
              return DownloadRecoveryResult(
                scannedVideoCount: scannedVideoCount,
                importedCount: importedCount,
                alreadyTrackedCount: alreadyTrackedCount,
                skippedCount: skippedCount,
                preferredRecord: preferredRecord,
              );
            }
          }
        }
      } catch (_) {}
    }

    return DownloadRecoveryResult(
      scannedVideoCount: scannedVideoCount,
      importedCount: importedCount,
      alreadyTrackedCount: alreadyTrackedCount,
      skippedCount: skippedCount,
      preferredRecord: preferredRecord,
    );
  }

  Future<DownloadTaskRecord?> _downloadedRecordForFileSignature({
    required String displayName,
    required int sizeBytes,
  }) async {
    final normalizedName = _normalizeRecoveredFileName(displayName);
    if (normalizedName.isEmpty) return null;
    final matches = <DownloadTaskRecord>[];
    for (final record in downloadedRecords) {
      if (_normalizeRecoveredFileName(record.fileName) != normalizedName) {
        continue;
      }
      if (sizeBytes > 0 &&
          !await _recordMatchesRecoveredFileSignature(
            record,
            displayName: displayName,
            sizeBytes: sizeBytes,
          )) {
        continue;
      }
      matches.add(record);
    }
    return matches.length == 1 ? matches.first : null;
  }

  Future<bool> _looksRecoverableDownloadFile(
    File file, {
    required String expectedDisplayName,
    required int expectedSizeBytes,
  }) async {
    if (!_isRecoverableVideoFileName(file.path)) return false;
    if (!await file.exists()) return false;
    final metadata = await _readRecoveryMetadataForFile(file);
    if (metadata == null && !_pathLooksInsideFlyPlayerDownloadRoot(file.path)) {
      return false;
    }
    final actualBytes = await file.length();
    return _passesRecoveryIntegrityCheck(
      actualBytes: actualBytes,
      metadata: metadata,
      expectedSizeBytes: expectedSizeBytes,
    );
  }

  Future<DownloadTaskRecord?> _importRecoveredVideoFile(
    File file, {
    required String expectedDisplayName,
    required int expectedSizeBytes,
    _RecoveredBackendLookup? backendLookup,
  }) async {
    try {
      if (!_isRecoverableVideoFileName(file.path)) return null;
      if (!await file.exists()) return null;
      final actualBytes = await file.length();
      final metadata = await _readRecoveryMetadataForFile(file);
      if (!_passesRecoveryIntegrityCheck(
        actualBytes: actualBytes,
        metadata: metadata,
        expectedSizeBytes: expectedSizeBytes,
      )) {
        return null;
      }
      final existing = downloadedRecordForFilePath(file.path);
      if (existing != null) {
        return _refreshRecoveredRecordArtifacts(
          existing,
          file,
          backendLookup: backendLookup,
        );
      }
      final context = await _buildRecoveredVideoContext(
        file: file,
        actualBytes: actualBytes,
        metadata: metadata,
        existingRecord: null,
        backendLookup: backendLookup,
      );
      final record = _buildRecoveredRecord(context: context);
      _upsertRecord(record, persistImmediately: true);
      await _writeRecoveryMetadata(record);
      await _recoverLocalDanmakuForRecord(record, backendLookup: backendLookup);
      return record;
    } catch (error, stackTrace) {
      unawaited(
        AppLogService.instance.recordWarning(
          error: error,
          stackTrace: stackTrace,
          source: 'download-recovery',
          details: 'path=${file.path}',
        ),
      );
      return null;
    }
  }

  Future<DownloadTaskRecord> _refreshRecoveredRecordArtifacts(
    DownloadTaskRecord record,
    File file, {
    _RecoveredBackendLookup? backendLookup,
  }) async {
    try {
      if (!await file.exists()) return record;
      final actualBytes = await file.length();
      final metadata = await _readRecoveryMetadataForFile(file);
      final context = await _buildRecoveredVideoContext(
        file: file,
        actualBytes: actualBytes,
        metadata: metadata,
        existingRecord: record,
        backendLookup: backendLookup,
      );
      final refreshed = _mergeRecoveredArtifacts(record, context);
      if (!_sameDownloadRecordForRecovery(record, refreshed)) {
        _upsertRecord(refreshed, persistImmediately: true);
        await _writeRecoveryMetadata(refreshed);
      }
      await _recoverLocalDanmakuForRecord(
        refreshed,
        backendLookup: backendLookup,
      );
      return refreshed;
    } catch (error, stackTrace) {
      unawaited(
        AppLogService.instance.recordWarning(
          error: error,
          stackTrace: stackTrace,
          source: 'download-recovery-refresh',
          details: 'path=${file.path}',
        ),
      );
      return record;
    }
  }

  DownloadTaskRecord _buildRecoveredRecord({
    required _RecoveredVideoContext context,
  }) {
    final file = context.file;
    final actualBytes = context.actualBytes;
    final metadata = context.metadata;
    final fileName = context.fileName;
    final title = context.title;
    final recoveredItemGuid = context.itemGuid.trim();
    final recoveredMediaGuid = context.mediaGuid.trim();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (metadata != null) {
      final metadataIsGenericRecovered = _isGenericRecoveredRecord(metadata);
      final id = _resolveRecoveredRecordId(
        preferredId: metadata.id,
        filePath: file.path,
        actualBytes: actualBytes,
      );
      final useRecoveredPosterUrls = _shouldPreferRecoveredLocalArtwork(
        record: metadata,
        currentUrls: metadata.posterUrls,
        recoveredUrls: context.posterUrls,
      );
      final useRecoveredGroupPosterUrls = _shouldPreferRecoveredLocalArtwork(
        record: metadata,
        currentUrls: metadata.groupPosterUrls,
        recoveredUrls: context.groupPosterUrls,
      );
      return metadata.copyWith(
        id: id,
        remoteTaskId: metadata.remoteTaskId.trim().isEmpty
            ? 'recovered'
            : metadata.remoteTaskId,
        itemGuid:
            (metadata.itemGuid.trim().isEmpty || metadataIsGenericRecovered) &&
                recoveredItemGuid.isNotEmpty
            ? recoveredItemGuid
            : metadata.itemGuid,
        mediaGuid:
            (metadata.mediaGuid.trim().isEmpty || metadataIsGenericRecovered) &&
                recoveredMediaGuid.isNotEmpty
            ? recoveredMediaGuid
            : metadata.mediaGuid,
        groupId: metadata.groupId.trim().isEmpty || metadataIsGenericRecovered
            ? context.groupId
            : metadata.groupId,
        groupTitle:
            metadata.groupTitle.trim().isEmpty || metadataIsGenericRecovered
            ? context.groupTitle
            : metadata.groupTitle,
        title: metadata.title.trim().isEmpty || metadataIsGenericRecovered
            ? title
            : metadata.title,
        durationText:
            metadata.durationText.trim().isEmpty || metadataIsGenericRecovered
            ? context.durationText
            : metadata.durationText,
        posterUrls: useRecoveredPosterUrls
            ? context.posterUrls
            : metadata.posterUrls,
        groupPosterUrls: useRecoveredGroupPosterUrls
            ? context.groupPosterUrls
            : metadata.groupPosterUrls,
        resolution:
            _shouldPreferRecoveredResolution(
              record: metadata,
              recoveredResolution: context.resolution,
            )
            ? context.resolution
            : metadata.resolution,
        fileName: fileName,
        filePath: file.path,
        totalBytes: math.max(
          actualBytes,
          math.max(metadata.totalBytes, metadata.downloadedBytes),
        ),
        downloadedBytes: actualBytes,
        status: DownloadTaskStatus.downloaded,
        errorMessage: '',
        createdAtMs: metadata.createdAtMs > 0 ? metadata.createdAtMs : now,
        updatedAtMs: now,
      );
    }

    final identity = _stableRecoveryId(file.path, actualBytes);
    return DownloadTaskRecord(
      id: 'download_recovered_$identity',
      remoteTaskId: 'recovered',
      itemGuid: recoveredItemGuid,
      mediaGuid: recoveredMediaGuid.isNotEmpty
          ? recoveredMediaGuid
          : 'recovered-media-$identity',
      groupId: context.groupId,
      groupTitle: context.groupTitle,
      title: title,
      durationText: context.durationText,
      posterUrls: context.posterUrls,
      groupPosterUrls: context.groupPosterUrls,
      resolution: context.resolution,
      fileName: fileName,
      filePath: file.path,
      totalBytes: actualBytes,
      downloadedBytes: actualBytes,
      status: DownloadTaskStatus.downloaded,
      errorMessage: '',
      createdAtMs: now,
      updatedAtMs: now,
    );
  }

  DownloadTaskRecord _mergeRecoveredArtifacts(
    DownloadTaskRecord record,
    _RecoveredVideoContext context,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final isGenericRecovered = _isGenericRecoveredRecord(record);
    final recoveredItemGuid = context.itemGuid.trim();
    final recoveredMediaGuid = context.mediaGuid.trim();
    final currentGroupTitle = record.groupTitle.trim();
    final shouldReplaceGroupTitle =
        currentGroupTitle.isEmpty ||
        (isGenericRecovered && currentGroupTitle != context.groupTitle);
    final currentGroupId = record.groupId.trim();
    final shouldReplaceGroupId =
        currentGroupId.isEmpty ||
        (isGenericRecovered && currentGroupId != context.groupId);
    final posterUrls =
        _shouldPreferRecoveredLocalArtwork(
          record: record,
          currentUrls: record.posterUrls,
          recoveredUrls: context.posterUrls,
        )
        ? context.posterUrls
        : record.posterUrls;
    final groupPosterUrls =
        _shouldPreferRecoveredLocalArtwork(
          record: record,
          currentUrls: record.groupPosterUrls,
          recoveredUrls: context.groupPosterUrls,
        )
        ? context.groupPosterUrls
        : record.groupPosterUrls;
    return record.copyWith(
      itemGuid:
          (record.itemGuid.trim().isEmpty || isGenericRecovered) &&
              recoveredItemGuid.isNotEmpty
          ? recoveredItemGuid
          : record.itemGuid,
      mediaGuid:
          (record.mediaGuid.trim().isEmpty || isGenericRecovered) &&
              recoveredMediaGuid.isNotEmpty
          ? recoveredMediaGuid
          : record.mediaGuid,
      groupId: shouldReplaceGroupId ? context.groupId : record.groupId,
      groupTitle: shouldReplaceGroupTitle
          ? context.groupTitle
          : record.groupTitle,
      title: record.title.trim().isEmpty || isGenericRecovered
          ? context.title
          : record.title,
      durationText: record.durationText.trim().isEmpty || isGenericRecovered
          ? context.durationText
          : record.durationText,
      posterUrls: posterUrls,
      groupPosterUrls: groupPosterUrls,
      resolution:
          _shouldPreferRecoveredResolution(
            record: record,
            recoveredResolution: context.resolution,
          )
          ? context.resolution
          : record.resolution,
      fileName: context.fileName,
      filePath: context.file.path,
      totalBytes: math.max(
        context.actualBytes,
        math.max(record.totalBytes, record.downloadedBytes),
      ),
      downloadedBytes: context.actualBytes,
      status: DownloadTaskStatus.downloaded,
      errorMessage: '',
      updatedAtMs: now,
    );
  }

  bool _sameDownloadRecordForRecovery(
    DownloadTaskRecord left,
    DownloadTaskRecord right,
  ) {
    return left.id == right.id &&
        left.remoteTaskId == right.remoteTaskId &&
        left.itemGuid == right.itemGuid &&
        left.mediaGuid == right.mediaGuid &&
        left.groupId == right.groupId &&
        left.groupTitle == right.groupTitle &&
        left.title == right.title &&
        left.durationText == right.durationText &&
        _sameStringList(left.posterUrls, right.posterUrls) &&
        _sameStringList(left.groupPosterUrls, right.groupPosterUrls) &&
        left.resolution == right.resolution &&
        left.fileName == right.fileName &&
        left.filePath == right.filePath &&
        left.totalBytes == right.totalBytes &&
        left.downloadedBytes == right.downloadedBytes &&
        _sameAudioTrackList(left.audioTracks, right.audioTracks) &&
        _sameSubtitleTrackList(left.subtitleTracks, right.subtitleTracks) &&
        left.status == right.status &&
        left.errorMessage == right.errorMessage;
  }

  bool _sameStringList(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  bool _sameAudioTrackList(
    List<AudioTrackOption> left,
    List<AudioTrackOption> right,
  ) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      final lhs = left[index];
      final rhs = right[index];
      if (lhs.mediaGuid != rhs.mediaGuid ||
          lhs.guid != rhs.guid ||
          lhs.title != rhs.title ||
          lhs.codecName != rhs.codecName ||
          lhs.profile != rhs.profile ||
          lhs.language != rhs.language ||
          lhs.audioType != rhs.audioType ||
          lhs.channelLayout != rhs.channelLayout ||
          lhs.channels != rhs.channels ||
          lhs.sampleRate != rhs.sampleRate ||
          lhs.bps != rhs.bps ||
          lhs.index != rhs.index ||
          lhs.isDefault != rhs.isDefault) {
        return false;
      }
    }
    return true;
  }

  bool _sameSubtitleTrackList(
    List<SubtitleTrackOption> left,
    List<SubtitleTrackOption> right,
  ) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      final lhs = left[index];
      final rhs = right[index];
      if (lhs.mediaGuid != rhs.mediaGuid ||
          lhs.guid != rhs.guid ||
          lhs.title != rhs.title ||
          lhs.codecName != rhs.codecName ||
          lhs.format != rhs.format ||
          lhs.language != rhs.language ||
          lhs.index != rhs.index ||
          lhs.isDefault != rhs.isDefault ||
          lhs.forced != rhs.forced ||
          lhs.isExternal != rhs.isExternal ||
          lhs.extraFile != rhs.extraFile ||
          lhs.isBitmap != rhs.isBitmap) {
        return false;
      }
    }
    return true;
  }

  bool _isGenericRecoveredRecord(DownloadTaskRecord record) {
    return record.remoteTaskId.trim() == 'recovered' ||
        record.itemGuid.trim().isEmpty ||
        record.id.startsWith('download_recovered_');
  }

  bool _shouldPreferRecoveredLocalArtwork({
    required DownloadTaskRecord record,
    required List<String> currentUrls,
    required List<String> recoveredUrls,
  }) {
    if (recoveredUrls.isEmpty) return false;
    if (currentUrls.isEmpty) return true;
    return record.remoteTaskId.trim() == 'recovered' ||
        record.itemGuid.trim().isEmpty ||
        record.id.startsWith('download_recovered_');
  }

  bool _shouldPreferRecoveredResolution({
    required DownloadTaskRecord record,
    required String recoveredResolution,
  }) {
    final normalizedRecovered = recoveredResolution.trim();
    if (normalizedRecovered.isEmpty) return false;
    final current = record.resolution.trim();
    if (current.isEmpty) return true;
    if (_isGenericRecoveredRecord(record)) {
      return current != normalizedRecovered &&
          (_isLocalRecoveredResolution(current) ||
              !_isLocalRecoveredResolution(normalizedRecovered));
    }
    return false;
  }

  bool _isLocalRecoveredResolution(String value) {
    final normalized = value.trim();
    return normalized == downloadLocalResolutionToken ||
        normalized == _legacyLocalResolution;
  }

  _RecoveredBackendLookup? _createRecoveredBackendLookup(
    NasProvider? provider,
  ) {
    if (provider == null || !provider.isConfigured) return null;
    return _RecoveredBackendLookup(provider);
  }

  Future<_RecoveredBackendMetadata?> _resolveRecoveredBackendMetadata({
    required _RecoveredBackendLookup? lookup,
    required DownloadTaskRecord? sourceRecord,
    required String filePath,
    required String fileName,
    required String localTitle,
    required String localGroupTitle,
  }) async {
    if (lookup == null) return null;
    final playInfo = await _resolveRecoveredBackendPlayInfo(
      lookup: lookup,
      sourceRecord: sourceRecord,
      fileName: fileName,
      localTitle: localTitle,
      localGroupTitle: localGroupTitle,
    );
    if (playInfo == null) return null;

    final item = playInfo.item;
    final itemGuid = item.guid.trim().isNotEmpty
        ? item.guid.trim()
        : (sourceRecord?.itemGuid.trim() ?? '');
    if (itemGuid.isEmpty) return null;
    final mediaGuid = playInfo.mediaGuid.trim().isNotEmpty
        ? playInfo.mediaGuid.trim()
        : (sourceRecord?.mediaGuid.trim() ?? '');
    final title = _backendEpisodeTitle(item, fallbackTitle: localTitle);
    final durationText = _backendDurationText(item);
    final resolution = _backendResolutionText(item);
    final episodePosterUrls = _backendImageCandidates(lookup.provider, <String>[
      item.stillPath,
      item.posters,
      item.backdrops,
    ]);
    final cachedPosterUrls = episodePosterUrls.isEmpty
        ? const <String>[]
        : await _cacheRecoveredBackendArtworkUrls(
            provider: lookup.provider,
            sourceUrls: episodePosterUrls,
            videoFilePath: filePath,
            suffix: 'cover',
          );

    final lookupRecord = (sourceRecord ?? _emptyRecord).copyWith(
      itemGuid: itemGuid,
      mediaGuid: mediaGuid,
      groupId: playInfo.parentGuid.trim().isNotEmpty
          ? playInfo.parentGuid.trim()
          : (sourceRecord?.groupId ?? ''),
      groupTitle: localGroupTitle,
      filePath: filePath,
      status: DownloadTaskStatus.downloaded,
    );
    final groupMeta = await _loadRecoveredBackendGroupMeta(
      lookup,
      lookupRecord,
    );
    final fallbackGroupTitle = _composeGroupTitle(
      seriesTitle: item.tvTitle,
      collectionTitle: item.parentTitle,
    );
    final groupTitle = groupMeta?.title.trim().isNotEmpty == true
        ? groupMeta!.title
        : (fallbackGroupTitle.trim().isNotEmpty
              ? fallbackGroupTitle.trim()
              : localGroupTitle);
    final groupId = groupMeta?.id.trim().isNotEmpty == true
        ? groupMeta!.id
        : (playInfo.parentGuid.trim().isNotEmpty
              ? playInfo.parentGuid.trim()
              : (sourceRecord?.groupId.trim().isNotEmpty == true
                    ? sourceRecord!.groupId.trim()
                    : _inferRecoveredGroupId(
                        filePath,
                        groupTitle: groupTitle,
                      )));
    final groupPosterSourceUrls = groupMeta?.posterUrls.isNotEmpty == true
        ? groupMeta!.posterUrls
        : _backendImageCandidates(lookup.provider, <String>[
            item.posters,
            item.backdrops,
          ]);
    final cachedGroupPosterUrls = groupPosterSourceUrls.isEmpty
        ? const <String>[]
        : await _cacheRecoveredBackendArtworkUrls(
            provider: lookup.provider,
            sourceUrls: groupPosterSourceUrls,
            videoFilePath: filePath,
            suffix: 'group_cover',
          );

    return _RecoveredBackendMetadata(
      itemGuid: itemGuid,
      mediaGuid: mediaGuid,
      groupId: groupId,
      groupTitle: groupTitle,
      title: title,
      durationText: durationText,
      resolution: resolution,
      posterUrls: cachedPosterUrls,
      groupPosterUrls: cachedGroupPosterUrls,
    );
  }

  Future<PlayInfoData?> _resolveRecoveredBackendPlayInfo({
    required _RecoveredBackendLookup lookup,
    required DownloadTaskRecord? sourceRecord,
    required String fileName,
    required String localTitle,
    required String localGroupTitle,
  }) async {
    final directGuid = sourceRecord?.itemGuid.trim() ?? '';
    if (directGuid.isNotEmpty) {
      return _loadRecoveredBackendPlayInfo(lookup, directGuid);
    }

    final episodeNumber = _parseRecoveredEpisodeNumber(
      <String>[localTitle, fileName].join(' '),
    );
    final seasonNumber = _parseRecoveredSeasonNumber(localGroupTitle);
    final query = _recoveredBackendSeriesQuery(
      localGroupTitle: localGroupTitle,
      localTitle: localTitle,
      fileName: fileName,
    );
    if (query.isEmpty) return null;

    final itemGuid = await _resolveRecoveredBackendGuidFromSearch(
      lookup: lookup,
      query: query,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      localTitle: localTitle,
      localGroupTitle: localGroupTitle,
    );
    if (itemGuid.isEmpty) return null;
    return _loadRecoveredBackendPlayInfo(lookup, itemGuid);
  }

  Future<PlayInfoData?> _loadRecoveredBackendPlayInfo(
    _RecoveredBackendLookup lookup,
    String itemGuid,
  ) {
    final normalizedGuid = itemGuid.trim();
    if (normalizedGuid.isEmpty) return Future<PlayInfoData?>.value();
    return lookup.playInfoByItemGuid.putIfAbsent(normalizedGuid, () async {
      try {
        return await lookup.api.getPlayInfo(normalizedGuid);
      } catch (_) {
        return null;
      }
    });
  }

  Future<_StoredGroupMeta?> _loadRecoveredBackendGroupMeta(
    _RecoveredBackendLookup lookup,
    DownloadTaskRecord record,
  ) {
    final itemGuid = record.itemGuid.trim();
    if (itemGuid.isEmpty) return Future<_StoredGroupMeta?>.value();
    return lookup.groupMetaByItemGuid.putIfAbsent(itemGuid, () {
      return _resolveStoredGroupMeta(
        api: lookup.api,
        provider: lookup.provider,
        record: record,
      );
    });
  }

  Future<String> _resolveRecoveredBackendGuidFromSearch({
    required _RecoveredBackendLookup lookup,
    required String query,
    required int seasonNumber,
    required int episodeNumber,
    required String localTitle,
    required String localGroupTitle,
  }) async {
    final results = await _loadRecoveredBackendSearch(lookup, query);
    if (results.isEmpty) return '';

    if (episodeNumber > 0) {
      for (final item in results) {
        if (!_isRecoveredBackendEpisodeCandidate(item)) continue;
        if (_mediaItemEpisodeNumber(item) == episodeNumber &&
            item.guid.trim().isNotEmpty) {
          return item.guid.trim();
        }
      }
    } else {
      final direct = results
          .where(
            (item) =>
                item.guid.trim().isNotEmpty &&
                _isRecoveredBackendPlayableCandidate(item),
          )
          .toList(growable: false);
      if (direct.length == 1) return direct.first.guid.trim();
    }

    final ranked = _rankRecoveredBackendSearchResults(
      results,
      query: query,
      localGroupTitle: localGroupTitle,
    );
    for (final item in ranked) {
      final resolvedGuid = await _resolveRecoveredBackendGuidFromContainer(
        lookup: lookup,
        item: item,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        localTitle: localTitle,
        localGroupTitle: localGroupTitle,
      );
      if (resolvedGuid.isNotEmpty) return resolvedGuid;
    }
    return '';
  }

  Future<List<MediaLibraryItem>> _loadRecoveredBackendSearch(
    _RecoveredBackendLookup lookup,
    String query,
  ) {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return Future<List<MediaLibraryItem>>.value(const <MediaLibraryItem>[]);
    }
    return lookup.searchByQuery.putIfAbsent(normalizedQuery, () async {
      try {
        return await lookup.api.searchList(normalizedQuery);
      } catch (_) {
        return const <MediaLibraryItem>[];
      }
    });
  }

  Future<String> _resolveRecoveredBackendGuidFromContainer({
    required _RecoveredBackendLookup lookup,
    required MediaLibraryItem item,
    required int seasonNumber,
    required int episodeNumber,
    required String localTitle,
    required String localGroupTitle,
  }) async {
    final guid = item.guid.trim();
    if (guid.isEmpty) return '';
    final type = item.type.trim().toLowerCase();
    if (_isRecoveredBackendEpisodeCandidate(item)) {
      if (episodeNumber <= 0 ||
          _mediaItemEpisodeNumber(item) == episodeNumber ||
          _looseTitleMatches(localTitle, item.title)) {
        return guid;
      }
      return '';
    }
    if (_isRecoveredBackendPlayableCandidate(item) && episodeNumber <= 0) {
      return guid;
    }
    if (type.contains('season')) {
      return _resolveRecoveredBackendGuidFromSeason(
        lookup: lookup,
        season: item,
        episodeNumber: episodeNumber,
        localTitle: localTitle,
      );
    }
    if (type.contains('tv')) {
      final seasons = await _loadRecoveredBackendSeasons(lookup, guid);
      final season = _pickRecoveredBackendSeason(
        seasons,
        seasonNumber: seasonNumber,
        localGroupTitle: localGroupTitle,
      );
      if (season == null) return '';
      return _resolveRecoveredBackendGuidFromSeason(
        lookup: lookup,
        season: season,
        episodeNumber: episodeNumber,
        localTitle: localTitle,
      );
    }
    if (item.numberOfEpisodes > 0) {
      return _resolveRecoveredBackendGuidFromSeason(
        lookup: lookup,
        season: item,
        episodeNumber: episodeNumber,
        localTitle: localTitle,
      );
    }
    return '';
  }

  Future<String> _resolveRecoveredBackendGuidFromSeason({
    required _RecoveredBackendLookup lookup,
    required MediaLibraryItem season,
    required int episodeNumber,
    required String localTitle,
  }) async {
    if (season.guid.trim().isEmpty) return '';
    final episodes = await _loadRecoveredBackendEpisodes(
      lookup,
      season.guid.trim(),
    );
    if (episodes.isEmpty) return '';
    if (episodeNumber > 0) {
      for (final episode in episodes) {
        if (_mediaItemEpisodeNumber(episode) == episodeNumber &&
            episode.guid.trim().isNotEmpty) {
          return episode.guid.trim();
        }
      }
    }
    for (final episode in episodes) {
      if (episode.guid.trim().isEmpty) continue;
      if (_looseTitleMatches(localTitle, episode.title)) {
        return episode.guid.trim();
      }
    }
    return episodes.length == 1 ? episodes.first.guid.trim() : '';
  }

  Future<List<MediaLibraryItem>> _loadRecoveredBackendSeasons(
    _RecoveredBackendLookup lookup,
    String itemGuid,
  ) {
    final guid = itemGuid.trim();
    if (guid.isEmpty) {
      return Future<List<MediaLibraryItem>>.value(const <MediaLibraryItem>[]);
    }
    return lookup.seasonsByItemGuid.putIfAbsent(guid, () async {
      try {
        return await lookup.api.getSeasonList(guid);
      } catch (_) {
        return const <MediaLibraryItem>[];
      }
    });
  }

  Future<List<MediaLibraryItem>> _loadRecoveredBackendEpisodes(
    _RecoveredBackendLookup lookup,
    String seasonGuid,
  ) {
    final guid = seasonGuid.trim();
    if (guid.isEmpty) {
      return Future<List<MediaLibraryItem>>.value(const <MediaLibraryItem>[]);
    }
    return lookup.episodesBySeasonGuid.putIfAbsent(guid, () async {
      try {
        return await lookup.api.getEpisodeList(guid);
      } catch (_) {
        return const <MediaLibraryItem>[];
      }
    });
  }

  List<MediaLibraryItem> _rankRecoveredBackendSearchResults(
    List<MediaLibraryItem> results, {
    required String query,
    required String localGroupTitle,
  }) {
    final ranked = List<MediaLibraryItem>.from(
      results.where((item) => item.guid.trim().isNotEmpty),
    );
    ranked.sort((left, right) {
      return _recoveredBackendSearchScore(
        right,
        query: query,
        localGroupTitle: localGroupTitle,
      ).compareTo(
        _recoveredBackendSearchScore(
          left,
          query: query,
          localGroupTitle: localGroupTitle,
        ),
      );
    });
    return ranked;
  }

  int _recoveredBackendSearchScore(
    MediaLibraryItem item, {
    required String query,
    required String localGroupTitle,
  }) {
    final queryToken = _normalizeLooseFileToken(query);
    final groupToken = _normalizeLooseFileToken(localGroupTitle);
    final titleTokens = <String>[
      item.title,
      item.tvTitle,
      item.parentTitle,
      item.ancestorName,
    ].map(_normalizeLooseFileToken).where((value) => value.isNotEmpty).toList();
    var score = 0;
    for (final token in titleTokens) {
      if (token == queryToken) score += 100;
      if (queryToken.isNotEmpty && token.contains(queryToken)) score += 50;
      if (groupToken.isNotEmpty && groupToken.contains(token)) score += 20;
      if (groupToken.isNotEmpty && token.contains(groupToken)) score += 20;
    }
    final type = item.type.trim().toLowerCase();
    if (type.contains('tv')) score += 12;
    if (type.contains('season')) score += 10;
    if (type.contains('episode')) score += 8;
    if (type.contains('movie') || type == 'video') score += 4;
    return score;
  }

  MediaLibraryItem? _pickRecoveredBackendSeason(
    List<MediaLibraryItem> seasons, {
    required int seasonNumber,
    required String localGroupTitle,
  }) {
    if (seasons.isEmpty) return null;
    if (seasonNumber > 0) {
      for (final season in seasons) {
        if (_mediaItemSeasonNumber(season) == seasonNumber) return season;
      }
    }
    for (final season in seasons) {
      if (_looseTitleMatches(localGroupTitle, season.title) ||
          _looseTitleMatches(localGroupTitle, season.parentTitle)) {
        return season;
      }
    }
    return seasons.length == 1 ? seasons.first : null;
  }

  bool _isRecoveredBackendEpisodeCandidate(MediaLibraryItem item) {
    final type = item.type.trim().toLowerCase();
    if (type.contains('episode')) return true;
    return item.episodeNumber > 0 && item.guid.trim().isNotEmpty;
  }

  bool _isRecoveredBackendPlayableCandidate(MediaLibraryItem item) {
    final type = item.type.trim().toLowerCase();
    return type.contains('movie') || type == 'video';
  }

  int _mediaItemEpisodeNumber(MediaLibraryItem item) {
    if (item.episodeNumber > 0) return item.episodeNumber;
    return _parseRecoveredEpisodeNumber(
      <String>[item.title, item.path].join(' '),
    );
  }

  int _mediaItemSeasonNumber(MediaLibraryItem item) {
    if (item.seasonNumber > 0) return item.seasonNumber;
    return _parseRecoveredSeasonNumber(
      <String>[item.title, item.parentTitle].join(' '),
    );
  }

  int _parseRecoveredSeasonNumber(String value) {
    final text = value.trim();
    if (text.isEmpty) return 0;
    for (final pattern in <RegExp>[
      RegExp('\u7b2c\\s*(\\d{1,3})\\s*[\u5b63\u90e8]'),
      RegExp(r'\bseason\s*(\d{1,3})\b', caseSensitive: false),
      RegExp(r'\bs\s*(\d{1,3})\b', caseSensitive: false),
    ]) {
      final match = pattern.firstMatch(text);
      final number = match == null
          ? 0
          : int.tryParse(match.group(1) ?? '') ?? 0;
      if (number > 0) return number;
    }
    return 0;
  }

  int _parseRecoveredEpisodeNumber(String value) {
    final text = value.trim();
    if (text.isEmpty) return 0;
    for (final pattern in <RegExp>[
      RegExp(r'\bS\s*\d{1,3}\s*E\s*(\d{1,4})\b', caseSensitive: false),
      RegExp('\u7b2c\\s*(\\d{1,4})\\s*[\u96c6\u8bdd\u8a71]'),
      RegExp(r'\bEP?\s*(\d{1,4})\b', caseSensitive: false),
      RegExp(r'(?:^|[\s._\-\[\(])0*(\d{1,4})(?:[\s._\-\]\)]|$)'),
    ]) {
      for (final match in pattern.allMatches(text)) {
        final number = int.tryParse(match.group(1) ?? '') ?? 0;
        if (_isPlausibleRecoveredEpisodeNumber(number)) return number;
      }
    }
    return 0;
  }

  bool _isPlausibleRecoveredEpisodeNumber(int number) {
    if (number <= 0 || number > 500) return false;
    return !const <int>{480, 720, 1080, 1440, 2160}.contains(number);
  }

  String _recoveredBackendSeriesQuery({
    required String localGroupTitle,
    required String localTitle,
    required String fileName,
  }) {
    var query = _stripTrailingRecoveredSeasonText(localGroupTitle);
    query = query
        .replaceFirst(
          RegExp(
            '\u7b2c\\s*\\d{1,3}\\s*[\u5b63\u90e8]\\s*\$',
            caseSensitive: false,
          ),
          '',
        )
        .replaceFirst(
          RegExp(r'\bseason\s*\d{1,3}\s*$', caseSensitive: false),
          '',
        )
        .trim();
    query = _trimRecoveredTitleSeparators(query);
    if (query.isNotEmpty) return query;
    final title = _normalizeRecoveredEpisodeTitle(
      localTitle,
      groupTitle: localGroupTitle,
      fileName: fileName,
    );
    return _trimRecoveredTitleSeparators(title);
  }

  bool _looseTitleMatches(String left, String right) {
    final leftToken = _normalizeLooseFileToken(left);
    final rightToken = _normalizeLooseFileToken(right);
    if (leftToken.isEmpty || rightToken.isEmpty) return false;
    return leftToken == rightToken ||
        leftToken.contains(rightToken) ||
        rightToken.contains(leftToken);
  }

  String _backendEpisodeTitle(PlayItem item, {required String fallbackTitle}) {
    final title = item.title.trim();
    final tvTitle = item.tvTitle.trim();
    final parentTitle = item.parentTitle.trim();
    var cleanTitle = title;
    if (cleanTitle == tvTitle || cleanTitle == parentTitle) {
      cleanTitle = '';
    }
    final episodeNumber = item.episodeNumber;
    if (episodeNumber > 0) {
      if (_titleStartsWithEpisodeNumber(cleanTitle, episodeNumber)) {
        return cleanTitle;
      }
      final prefix = '\u7b2c $episodeNumber \u96c6';
      if (cleanTitle.isEmpty) return prefix;
      return '$prefix $cleanTitle';
    }
    if (cleanTitle.isNotEmpty) return cleanTitle;
    return fallbackTitle.trim();
  }

  bool _titleStartsWithEpisodeNumber(String title, int episodeNumber) {
    if (title.trim().isEmpty || episodeNumber <= 0) return false;
    final parsed = _parseRecoveredEpisodeNumber(title);
    if (parsed != episodeNumber) return false;
    final normalized = title.trim().toLowerCase();
    return normalized.startsWith('\u7b2c') ||
        normalized.startsWith('e') ||
        normalized.startsWith('ep') ||
        normalized.startsWith('s');
  }

  String _backendDurationText(PlayItem item) {
    if (item.runtime > 0) return '${item.runtime}\u5206\u949f';
    return _formatRecoveredDurationText(item.duration);
  }

  String _backendResolutionText(PlayItem item) {
    for (final resolution in item.resolutions) {
      final normalized = resolution.trim();
      if (normalized.isNotEmpty) return normalized;
    }
    return '';
  }

  List<String> _backendImageCandidates(
    NasProvider provider,
    Iterable<String> paths,
  ) {
    for (final rawPath in paths) {
      final path = rawPath.trim();
      if (path.isEmpty) continue;
      if (_isLocalPath(path) ||
          path.startsWith('file://') ||
          path.startsWith('http://') ||
          path.startsWith('https://')) {
        return <String>[path];
      }
      return ApiUrlHelper.imageCandidates(provider.baseUrl, path, width: 720);
    }
    return const <String>[];
  }

  String _preferRecoveredBackendResolution({
    required String localResolution,
    required String backendResolution,
  }) {
    final local = localResolution.trim();
    final backend = backendResolution.trim();
    if (backend.isEmpty) return local;
    if (local.isEmpty) return backend;
    final localHasQuality = RegExp(
      r'(?:4k|\d{3,4})',
      caseSensitive: false,
    ).hasMatch(local);
    final backendHasQuality = RegExp(
      r'(?:4k|\d{3,4})',
      caseSensitive: false,
    ).hasMatch(backend);
    if (!localHasQuality && backendHasQuality) return backend;
    return local;
  }

  Future<_RecoveredVideoContext> _buildRecoveredVideoContext({
    required File file,
    required int actualBytes,
    required DownloadTaskRecord? metadata,
    required DownloadTaskRecord? existingRecord,
    required _RecoveredBackendLookup? backendLookup,
  }) async {
    final fileName = _lastPathSegment(file.path);
    final fileTitle = _fileNameBase(fileName).trim();
    final fallbackTitle = fileTitle.isEmpty ? fileName : fileTitle;
    final mediaMetadata = await _readRecoveredLocalVideoMetadata(file.path);
    final localResolution = _inferRecoveredResolution(
      fileName,
      width: mediaMetadata?.width ?? 0,
      height: mediaMetadata?.height ?? 0,
    );
    final localDurationText = _formatRecoveredDurationText(
      ((mediaMetadata?.durationMs ?? 0) / 1000).round(),
    );
    final rawTitle = _inferRecoveredEpisodeTitle(
      file.path,
      fallbackTitle: fallbackTitle,
    );
    final groupTitle = _inferRecoveredGroupTitle(
      file.path,
      fallbackTitle: rawTitle,
    );
    final title = _normalizeRecoveredEpisodeTitle(
      rawTitle,
      groupTitle: groupTitle,
      fileName: fileName,
    );
    final localPosterUrls = _recoverEpisodePosterUrls(file.path);
    final localGroupPosterUrls = _recoverGroupPosterUrls(
      file.path,
      fallbackUrls: localPosterUrls,
    );
    final backendMetadata = await _resolveRecoveredBackendMetadata(
      lookup: backendLookup,
      sourceRecord: metadata ?? existingRecord,
      filePath: file.path,
      fileName: fileName,
      localTitle: title,
      localGroupTitle: groupTitle,
    );
    final effectivePosterUrls = backendMetadata?.posterUrls.isNotEmpty == true
        ? backendMetadata!.posterUrls
        : localPosterUrls;
    final effectiveGroupPosterUrls =
        backendMetadata?.groupPosterUrls.isNotEmpty == true
        ? backendMetadata!.groupPosterUrls
        : localGroupPosterUrls;
    final effectiveDurationText =
        backendMetadata?.durationText.trim().isNotEmpty == true
        ? backendMetadata!.durationText
        : localDurationText;
    final effectiveResolution = _preferRecoveredBackendResolution(
      localResolution: localResolution,
      backendResolution: backendMetadata?.resolution ?? '',
    );
    return _RecoveredVideoContext(
      file: file,
      actualBytes: actualBytes,
      metadata: metadata,
      itemGuid: backendMetadata?.itemGuid ?? '',
      mediaGuid: backendMetadata?.mediaGuid ?? '',
      fileName: fileName,
      title: backendMetadata?.title.trim().isNotEmpty == true
          ? backendMetadata!.title
          : title,
      groupId: backendMetadata?.groupId.trim().isNotEmpty == true
          ? backendMetadata!.groupId
          : _inferRecoveredGroupId(file.path, groupTitle: groupTitle),
      groupTitle: backendMetadata?.groupTitle.trim().isNotEmpty == true
          ? backendMetadata!.groupTitle
          : groupTitle,
      durationText: effectiveDurationText,
      resolution: effectiveResolution,
      posterUrls: effectivePosterUrls,
      groupPosterUrls: effectiveGroupPosterUrls,
    );
  }

  Future<_LocalVideoMetadata?> _readRecoveredLocalVideoMetadata(
    String filePath,
  ) async {
    if (!Platform.isAndroid) return null;
    try {
      final raw = await _storageChannel.invokeMethod<Map<dynamic, dynamic>>(
        'readLocalVideoMetadata',
        <String, Object?>{'path': filePath},
      );
      if (raw == null || raw.isEmpty) return null;
      return _LocalVideoMetadata(
        durationMs: _intFromDynamic(raw['durationMs']),
        width: _intFromDynamic(raw['width']),
        height: _intFromDynamic(raw['height']),
      );
    } catch (_) {
      return null;
    }
  }

  int _intFromDynamic(dynamic value) {
    return switch (value) {
      final int number => number,
      final num number => number.toInt(),
      final String text => int.tryParse(text.trim()) ?? 0,
      _ => 0,
    };
  }

  String _inferRecoveredGroupId(String filePath, {required String groupTitle}) {
    final groupDirectory = _recoveredGroupDirectoryForVideo(filePath).path;
    final normalizedGroupDirectory = _normalizeFilePathForComparison(
      groupDirectory,
    );
    if (normalizedGroupDirectory.isNotEmpty) {
      return 'recovered-group-${_stableRecoveryId(normalizedGroupDirectory, 0)}';
    }
    return 'recovered-group-${_stableRecoveryId(groupTitle, 0)}';
  }

  List<String> _recoverEpisodePosterUrls(String videoFilePath) {
    final videoFile = File(videoFilePath);
    final directory = videoFile.parent;
    final baseName = _fileNameBase(_lastPathSegment(videoFilePath));
    return _firstExistingFileUris(<File>[
      ..._imageNameCandidates(
        directory: directory,
        names: <String>[
          'cover',
          '${baseName}_cover',
          '${baseName}_poster',
          baseName,
          'poster',
          'folder',
          'thumb',
          'thumbnail',
          'still',
          'backdrop',
        ],
      ),
      ..._directoryImageCandidates(
        directory,
        preferredNames: <String>{
          'cover',
          '${baseName}_cover',
          '${baseName}_poster',
          baseName,
          'poster',
          'folder',
          'thumb',
          'thumbnail',
          'still',
          'backdrop',
        },
      ),
    ]);
  }

  List<String> _recoverGroupPosterUrls(
    String videoFilePath, {
    required List<String> fallbackUrls,
  }) {
    final groupDirectory = _recoveredGroupDirectoryForVideo(videoFilePath);
    final artworkDirectory = Directory(
      _recoveredGroupArtworkDirectory(videoFilePath),
    );
    final urls = _firstExistingFileUris(<File>[
      ..._imageNameCandidates(
        directory: artworkDirectory,
        names: const <String>[
          'group_cover',
          'poster',
          'folder',
          'cover',
          'thumb',
          'thumbnail',
        ],
      ),
      ..._directoryImageCandidates(
        artworkDirectory,
        preferredNames: const <String>{
          'group_cover',
          'poster',
          'folder',
          'cover',
          'thumb',
          'thumbnail',
        },
      ),
      ..._imageNameCandidates(
        directory: groupDirectory,
        names: const <String>[
          'group_cover',
          'poster',
          'folder',
          'cover',
          'thumb',
          'thumbnail',
        ],
      ),
      ..._directoryImageCandidates(
        groupDirectory,
        preferredNames: const <String>{
          'group_cover',
          'poster',
          'folder',
          'cover',
          'thumb',
          'thumbnail',
        },
      ),
    ]);
    return urls.isNotEmpty ? urls : fallbackUrls;
  }

  Iterable<File> _imageNameCandidates({
    required Directory directory,
    required List<String> names,
  }) sync* {
    for (final name in names) {
      for (final extension in _recoveredImageExtensions) {
        yield File('${directory.path}${Platform.pathSeparator}$name$extension');
      }
    }
  }

  List<File> _directoryImageCandidates(
    Directory directory, {
    required Set<String> preferredNames,
  }) {
    try {
      if (!directory.existsSync()) return const <File>[];
      final preferredTokens = preferredNames
          .map(_normalizeLooseFileToken)
          .where((value) => value.isNotEmpty)
          .toSet();
      final files = directory
          .listSync(followLinks: false)
          .whereType<File>()
          .where(_isRecoveredImageFile)
          .toList(growable: false);
      files.sort((left, right) {
        final leftScore = _recoveredImageCandidateScore(
          left,
          preferredTokens: preferredTokens,
        );
        final rightScore = _recoveredImageCandidateScore(
          right,
          preferredTokens: preferredTokens,
        );
        if (leftScore != rightScore) return rightScore.compareTo(leftScore);
        return left.path.compareTo(right.path);
      });
      return files;
    } catch (_) {
      return const <File>[];
    }
  }

  int _recoveredImageCandidateScore(
    File file, {
    required Set<String> preferredTokens,
  }) {
    final baseName = _fileNameBase(_lastPathSegment(file.path));
    final token = _normalizeLooseFileToken(baseName);
    if (preferredTokens.contains(token)) return 1000;
    for (final preferred in preferredTokens) {
      if (preferred.isNotEmpty && token.contains(preferred)) return 800;
      if (preferred.isNotEmpty && preferred.contains(token)) return 700;
    }
    if (token.contains('cover')) return 600;
    if (token.contains('poster')) return 550;
    if (token.contains('thumb') || token.contains('thumbnail')) return 500;
    if (token.contains('still')) return 450;
    if (token.contains('backdrop')) return 400;
    if (token.contains('folder')) return 350;
    return 100;
  }

  bool _isRecoveredImageFile(File file) {
    final extension = _extensionOfFileName(_lastPathSegment(file.path));
    if (!_recoveredImageExtensions.contains('.$extension')) return false;
    try {
      return file.lengthSync() > 0;
    } catch (_) {
      return false;
    }
  }

  List<String> _firstExistingFileUris(Iterable<File> candidates) {
    final seen = <String>{};
    for (final candidate in candidates) {
      final normalizedPath = _normalizeFilePathForComparison(candidate.path);
      if (normalizedPath.isEmpty || !seen.add(normalizedPath)) continue;
      if (!candidate.existsSync()) continue;
      return <String>[Uri.file(candidate.path).toString()];
    }
    return const <String>[];
  }

  Future<void> _recoverLocalDanmakuForRecord(
    DownloadTaskRecord record, {
    _RecoveredBackendLookup? backendLookup,
  }) async {
    final videoPath = record.filePath.trim();
    if (videoPath.isEmpty || !File(videoPath).existsSync()) return;
    final candidates = _localDanmakuCandidatesForVideo(videoPath);
    if (candidates.isEmpty) return;
    final targets = await _danmakuRecoveryTargetsForRecord(
      record,
      backendLookup: backendLookup,
    );
    if (targets.isEmpty) return;
    const store = DanmakuSavedSourceStore();
    var allTargetsHaveExistingLocalSource = true;
    for (final target in targets) {
      final previousSources = await store.loadForMedia(target.mediaKey);
      final hasExistingLocalSource = previousSources.any(
        _isReadableLocalDanmakuSource,
      );
      if (!hasExistingLocalSource) {
        allTargetsHaveExistingLocalSource = false;
      }
    }
    if (allTargetsHaveExistingLocalSource) return;

    DanmakuImportResult? parsed;
    File? sourceFile;
    for (final candidate in candidates) {
      try {
        final result = await DanmakuImportParser.parseFile(candidate.path);
        if (result.comments.isEmpty) continue;
        parsed = result;
        sourceFile = candidate;
        break;
      } catch (_) {}
    }
    if (parsed == null || sourceFile == null) return;

    for (final target in targets) {
      final label = parsed.sourceLabel.trim().isNotEmpty
          ? parsed.sourceLabel.trim()
          : _lastPathSegment(sourceFile.path);
      final source = DanmakuSavedSource(
        type: DanmakuSavedSourceType.downloadedFile,
        mediaKey: target.mediaKey,
        sourceKey: sourceFile.path,
        label: label,
        detail: sourceFile.path,
        ancestorName: record.groupTitle.trim(),
        seriesTitle: record.groupTitle.trim(),
        itemTitle: record.title.trim(),
        itemGuid: record.itemGuid.trim(),
        seasonGuid: target.seasonGuid,
        mediaGuid: record.mediaGuid.trim().isNotEmpty
            ? record.mediaGuid.trim()
            : record.id,
        seasonNumber: 0,
        episodeNumber: 0,
        mediaType: record.itemGuid.trim().isEmpty ? 'local' : '',
        commentCount: parsed.comments.length,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      await _saveDanmakuSourceWithLocalPriority(store: store, source: source);
    }
  }

  Future<List<_DanmakuRecoveryTarget>> _danmakuRecoveryTargetsForRecord(
    DownloadTaskRecord record, {
    _RecoveredBackendLookup? backendLookup,
  }) async {
    final mediaGuid = record.mediaGuid.trim().isNotEmpty
        ? record.mediaGuid.trim()
        : record.id;
    final itemGuid = record.itemGuid.trim();
    final groupId = record.groupId.trim();
    final targets = <_DanmakuRecoveryTarget>[];
    void addTarget(String seasonGuid) {
      final mediaKey = _buildDanmakuMediaKey(
        itemGuid: itemGuid,
        mediaGuid: mediaGuid,
        seasonGuid: seasonGuid,
        seasonNumber: 0,
        episodeNumber: 0,
        seriesTitle: record.groupTitle,
        itemTitle: record.title,
      );
      if (mediaKey.trim().isEmpty ||
          targets.any((target) => target.mediaKey == mediaKey)) {
        return;
      }
      targets.add(
        _DanmakuRecoveryTarget(mediaKey: mediaKey, seasonGuid: seasonGuid),
      );
    }

    addTarget(groupId);
    if (groupId.isNotEmpty) addTarget('');
    final playInfo = await _recoveredPlayInfoForDanmakuTarget(
      record,
      backendLookup,
    );
    if (playInfo != null) {
      final item = playInfo.item;
      final resolvedItemGuid = item.guid.trim().isNotEmpty
          ? item.guid.trim()
          : itemGuid;
      final resolvedMediaGuid = record.mediaGuid.trim().isNotEmpty
          ? record.mediaGuid.trim()
          : playInfo.mediaGuid.trim();
      final resolvedSeasonGuid = playInfo.parentGuid.trim().isNotEmpty
          ? playInfo.parentGuid.trim()
          : groupId;
      final resolvedSeriesTitle = item.tvTitle.trim().isNotEmpty
          ? item.tvTitle.trim()
          : record.groupTitle;
      final resolvedItemTitle = item.title.trim().isNotEmpty
          ? item.title.trim()
          : record.title;
      final mediaKey = _buildDanmakuMediaKey(
        itemGuid: resolvedItemGuid,
        mediaGuid: resolvedMediaGuid,
        seasonGuid: resolvedSeasonGuid,
        seasonNumber: item.seasonNumber,
        episodeNumber: item.episodeNumber,
        seriesTitle: resolvedSeriesTitle,
        itemTitle: resolvedItemTitle,
      );
      if (mediaKey.trim().isNotEmpty &&
          !targets.any((target) => target.mediaKey == mediaKey)) {
        targets.add(
          _DanmakuRecoveryTarget(
            mediaKey: mediaKey,
            seasonGuid: resolvedSeasonGuid,
          ),
        );
      }
    }
    return targets;
  }

  Future<PlayInfoData?> _recoveredPlayInfoForDanmakuTarget(
    DownloadTaskRecord record,
    _RecoveredBackendLookup? backendLookup,
  ) {
    final itemGuid = record.itemGuid.trim();
    if (itemGuid.isEmpty || backendLookup == null) {
      return Future<PlayInfoData?>.value();
    }
    return _loadRecoveredBackendPlayInfo(backendLookup, itemGuid);
  }

  List<File> _localDanmakuCandidatesForVideo(String videoFilePath) {
    final videoFile = File(videoFilePath);
    final directory = videoFile.parent;
    if (!directory.existsSync()) return const <File>[];
    final baseName = _fileNameBase(_lastPathSegment(videoFilePath));
    final candidates = <String, File>{};
    void add(File file) {
      final normalizedPath = _normalizeFilePathForComparison(file.path);
      if (normalizedPath.isEmpty || candidates.containsKey(normalizedPath)) {
        return;
      }
      if (!file.existsSync()) return;
      candidates[normalizedPath] = file;
    }

    for (final suffix in const <String>[
      '',
      '.danmaku',
      '.danmu',
      '.comment',
      '.comments',
    ]) {
      for (final extension in const <String>['.xml', '.json']) {
        add(
          File(
            '${directory.path}${Platform.pathSeparator}$baseName$suffix$extension',
          ),
        );
      }
    }

    try {
      for (final entity in directory.listSync(followLinks: false)) {
        if (entity is! File) continue;
        if (!_isRecoverableDanmakuFileName(entity.path, baseName: baseName)) {
          continue;
        }
        add(entity);
      }
    } catch (_) {}
    return candidates.values.toList(growable: false);
  }

  File? _downloadedDanmakuFileForVideo(String videoFilePath) {
    final normalizedPath = videoFilePath.trim();
    if (normalizedPath.isEmpty) return null;
    final videoFile = File(normalizedPath);
    final baseName = _fileNameBase(_lastPathSegment(normalizedPath)).trim();
    if (baseName.isEmpty) return null;
    return File(
      '${videoFile.parent.path}${Platform.pathSeparator}$baseName.danmaku.json',
    );
  }

  Future<File?> _writeDownloadedDanmakuFile({
    required DownloadTaskRecord record,
    required DanDanPlayPlaybackResolveResult resolved,
  }) async {
    if (resolved.result.comments.isEmpty) return null;
    final targetFile = _downloadedDanmakuFileForVideo(record.filePath);
    if (targetFile == null) return null;
    final payload = <String, Object?>{
      'schemaVersion': 1,
      'source': 'dandanplay',
      'episodeId': resolved.item.episodeId,
      'sourceLabel': resolved.result.sourceLabel,
      'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      'comments': resolved.result.comments
          .map(
            (comment) => <String, Object?>{
              'id': comment.id,
              'time': comment.timeMs / 1000.0,
              'mode': _danmakuCommentMode(comment.type.index),
              'color': comment.color.toARGB32() & 0x00ffffff,
              'text': comment.text,
            },
          )
          .toList(growable: false),
    };
    await targetFile.parent.create(recursive: true);
    await targetFile.writeAsString(jsonEncode(payload), flush: true);
    return targetFile;
  }

  int _danmakuCommentMode(int typeIndex) {
    return switch (typeIndex) {
      1 => 4,
      2 => 5,
      _ => 1,
    };
  }

  /// 下载时/恢复时把弹幕源写入保存库。这些源都是**自动注册**（随片下载缓存或下载时
  /// 在线匹配到的网络源），不是用户手动选择，**绝不**主动设为 active 源——active 槽位只留
  /// 给用户在播放页手动点选的源（优先级：手动 > 本地导入 > 网络 > 本地下载，由
  /// `_tryLoadPreferredDanmakuSource` / `NativeDanmakuPrefetch` 解析）。这里仅在已存在
  /// 用户手动 active 源时确保不被覆盖。
  Future<void> _saveDanmakuSourceWithLocalPriority({
    required DanmakuSavedSourceStore store,
    required DanmakuSavedSource source,
  }) async {
    final previousActiveSourceKey =
        (await store.loadActiveSourceKey(source.mediaKey))?.trim() ?? '';

    await store.saveSource(source);

    // 保留用户既有的手动 active 选择（saveSource 不应清掉它）。
    if (previousActiveSourceKey.isNotEmpty &&
        previousActiveSourceKey != source.sourceKey) {
      await store.setActiveSourceKey(
        mediaKey: source.mediaKey,
        sourceKey: previousActiveSourceKey,
      );
    }
  }

  bool _isReadableLocalDanmakuSource(DanmakuSavedSource source) {
    if (!source.isFileBased) return false;
    final sourceKey = source.sourceKey.trim();
    if (sourceKey.isEmpty) return false;
    if (StorageAccessService.isScopedIdentifier(sourceKey)) return true;
    try {
      return File(sourceKey).existsSync();
    } catch (_) {
      return false;
    }
  }

  bool _isRecoverableDanmakuFileName(
    String filePath, {
    required String baseName,
  }) {
    final fileName = _lastPathSegment(filePath);
    final lower = fileName.toLowerCase();
    if (lower == _recoveryMetadataFileName ||
        lower.endsWith(_pathRecoveryMetadataSuffix)) {
      return false;
    }
    final extension = _extensionOfFileName(fileName);
    if (extension != 'xml' && extension != 'json') return false;
    final candidateBase = _fileNameBase(fileName);
    final normalizedCandidate = _normalizeLooseFileToken(candidateBase);
    final normalizedBase = _normalizeLooseFileToken(baseName);
    if (normalizedBase.isNotEmpty &&
        (normalizedCandidate == normalizedBase ||
            normalizedCandidate.startsWith(normalizedBase) ||
            normalizedCandidate.contains(normalizedBase))) {
      return true;
    }
    return lower.contains('danmaku') ||
        lower.contains('danmu') ||
        lower.contains('comment') ||
        lower.contains('\u5f39\u5e55');
  }

  String _normalizeLooseFileToken(String value) {
    return value.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9\u4e00-\u9fff]+'),
      '',
    );
  }

  String _resolveRecoveredRecordId({
    required String preferredId,
    required String filePath,
    required int actualBytes,
  }) {
    final normalizedPreferredId = preferredId.trim();
    if (normalizedPreferredId.isNotEmpty) {
      final existing = _recordById(normalizedPreferredId);
      if (existing == null ||
          _normalizeFilePathForComparison(existing.filePath) ==
              _normalizeFilePathForComparison(filePath) ||
          !File(existing.filePath).existsSync()) {
        return normalizedPreferredId;
      }
    }
    return 'download_recovered_${_stableRecoveryId(filePath, actualBytes)}';
  }

  Future<List<Directory>> _downloadRecoveryRoots({
    required bool requestStorageAccess,
  }) async {
    final paths = <String>{};
    for (final record in _records) {
      final root = _flyPlayerDownloadRootFromPath(record.filePath);
      if (root != null) paths.add(root);
    }
    try {
      var hasAccess = await StorageAccessService.hasFileAccess();
      if (!hasAccess && requestStorageAccess) {
        hasAccess = await StorageAccessService.requestFileAccess();
      }
      if (hasAccess) {
        final root = await StorageAccessService.primaryStorageRoot();
        final storageRoot = root.trim().isEmpty
            ? '/storage/emulated/0'
            : root.trim();
        paths.add('$storageRoot/Download/$_downloadFolderName');
      }
    } catch (_) {}

    return paths
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .map(Directory.new)
        .toList(growable: false);
  }

  Future<bool> _matchesRecoveredFileSignature(
    File file, {
    required String displayName,
    required int sizeBytes,
  }) async {
    final expectedName = _normalizeRecoveredFileName(displayName);
    if (expectedName.isNotEmpty &&
        _normalizeRecoveredFileName(_lastPathSegment(file.path)) !=
            expectedName) {
      return false;
    }
    if (expectedName.isEmpty && sizeBytes <= 0) return false;
    if (sizeBytes <= 0) return true;
    try {
      return _bytesClose(await file.length(), sizeBytes);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _recordMatchesRecoveredFileSignature(
    DownloadTaskRecord record, {
    required String displayName,
    required int sizeBytes,
  }) async {
    final expectedName = _normalizeRecoveredFileName(displayName);
    if (expectedName.isNotEmpty &&
        _normalizeRecoveredFileName(record.fileName) != expectedName) {
      return false;
    }
    if (expectedName.isEmpty && sizeBytes <= 0) return false;
    if (sizeBytes <= 0) return true;
    try {
      return _bytesClose(await File(record.filePath).length(), sizeBytes);
    } catch (_) {
      return _bytesClose(record.downloadedBytes, sizeBytes) ||
          _bytesClose(record.totalBytes, sizeBytes);
    }
  }

  bool _passesRecoveryIntegrityCheck({
    required int actualBytes,
    required DownloadTaskRecord? metadata,
    required int expectedSizeBytes,
  }) {
    if (actualBytes <= 0) return false;
    if (expectedSizeBytes > 0 && !_bytesClose(actualBytes, expectedSizeBytes)) {
      return false;
    }
    final expectedBytes = metadata == null
        ? 0
        : math.max(metadata.totalBytes, metadata.downloadedBytes);
    if (expectedBytes > 0) {
      final tolerance = math.max(1024 * 1024, (expectedBytes * 0.05).round());
      return actualBytes + tolerance >= expectedBytes;
    }
    return actualBytes >= 64 * 1024;
  }

  bool _bytesClose(int actualBytes, int expectedBytes) {
    if (expectedBytes <= 0) return true;
    final delta = (actualBytes - expectedBytes).abs();
    final tolerance = math.max(4096, (expectedBytes * 0.01).round());
    return delta <= tolerance;
  }

  Future<void> _writeRecoveryMetadata(DownloadTaskRecord record) async {
    try {
      if (!_isDownloadedRecordAvailable(record)) return;
      final videoFile = File(record.filePath);
      final metadataFile = _recoveryMetadataFileForVideoPath(record.filePath);
      await metadataFile.parent.create(recursive: true);
      await metadataFile.writeAsString(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'fileSizeBytes': await videoFile.length(),
          'record': record.toJson(),
        }),
        flush: true,
      );
    } catch (_) {}
  }

  Future<DownloadTaskRecord?> _readRecoveryMetadataForFile(
    File videoFile,
  ) async {
    final candidates = <_RecoveryMetadataCandidate>[
      _RecoveryMetadataCandidate(
        file: File('${videoFile.path}$_pathRecoveryMetadataSuffix'),
        pathSpecific: true,
      ),
      _RecoveryMetadataCandidate(
        file: File(
          '${videoFile.parent.path}${Platform.pathSeparator}$_recoveryMetadataFileName',
        ),
        pathSpecific: false,
      ),
    ];
    for (final candidate in candidates) {
      try {
        if (!await candidate.file.exists()) continue;
        final decoded = jsonDecode(await candidate.file.readAsString());
        if (decoded is! Map) continue;
        final rawRecord = decoded['record'] ?? decoded['downloadTaskRecord'];
        final recordMap = rawRecord is Map ? rawRecord : decoded;
        final record = DownloadTaskRecord.fromJson(
          Map<String, dynamic>.from(recordMap),
        );
        if (!_metadataBelongsToFile(
          record,
          videoFile,
          pathSpecific: candidate.pathSpecific,
        )) {
          continue;
        }
        return record;
      } catch (_) {}
    }
    return null;
  }

  bool _metadataBelongsToFile(
    DownloadTaskRecord record,
    File videoFile, {
    required bool pathSpecific,
  }) {
    if (pathSpecific) return true;
    final fileName = _normalizeRecoveredFileName(
      _lastPathSegment(videoFile.path),
    );
    final recordFileName = _normalizeRecoveredFileName(record.fileName);
    if (recordFileName.isNotEmpty && recordFileName == fileName) return true;
    final recordPathFileName = _normalizeRecoveredFileName(
      _lastPathSegment(record.filePath),
    );
    if (recordPathFileName.isNotEmpty && recordPathFileName == fileName) {
      return true;
    }
    return _isDedicatedRecordDirectory(videoFile.path);
  }

  File _recoveryMetadataFileForVideoPath(String videoFilePath) {
    final videoFile = File(videoFilePath);
    if (_isDedicatedRecordDirectory(videoFilePath)) {
      return File(
        '${videoFile.parent.path}${Platform.pathSeparator}$_recoveryMetadataFileName',
      );
    }
    return File('$videoFilePath$_pathRecoveryMetadataSuffix');
  }

  bool _isRecoverableVideoFileName(String value) {
    final fileName = _lastPathSegment(value).toLowerCase();
    if (fileName.isEmpty ||
        fileName.endsWith('.part') ||
        fileName.endsWith('.tmp') ||
        fileName.endsWith('.download') ||
        fileName.endsWith('.crdownload')) {
      return false;
    }
    return _videoFileExtensions.contains(_extensionOfFileName(fileName));
  }

  String _extensionOfFileName(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex >= fileName.length - 1) return '';
    return fileName.substring(dotIndex + 1).toLowerCase();
  }

  String _normalizeRecoveredFileName(String value) {
    final normalized = value.trim().replaceAll('\\', '/');
    final name = normalized.contains('/')
        ? normalized.substring(normalized.lastIndexOf('/') + 1)
        : normalized;
    return name.trim().toLowerCase();
  }

  String _lastPathSegment(String path) {
    final normalized = path.replaceAll('\\', '/');
    final trimmed = normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    final slashIndex = trimmed.lastIndexOf('/');
    if (slashIndex < 0) return trimmed;
    return trimmed.substring(slashIndex + 1);
  }

  String _inferRecoveredGroupTitle(
    String filePath, {
    required String fallbackTitle,
  }) {
    final root = _flyPlayerDownloadRootFromPath(filePath);
    if (root != null) {
      final relative = _relativePathSegments(
        rootPath: root,
        childPath: File(filePath).parent.path,
      );
      if (relative.length >= 2) {
        return relative.take(relative.length - 1).join(' ');
      }
      if (relative.isNotEmpty) return relative.join(' ');
    }
    final groupDirectory = _recoveredGroupDirectoryForVideo(filePath);
    final candidate = _lastPathSegment(groupDirectory.path);
    final normalized = candidate.trim();
    if (normalized.isEmpty || normalized == _downloadFolderName) {
      return fallbackTitle.trim().isEmpty ? 'Downloads' : fallbackTitle.trim();
    }
    return normalized;
  }

  String _inferRecoveredEpisodeTitle(
    String filePath, {
    required String fallbackTitle,
  }) {
    final root = _flyPlayerDownloadRootFromPath(filePath);
    if (root != null) {
      final relative = _relativePathSegments(
        rootPath: root,
        childPath: File(filePath).parent.path,
      );
      if (relative.length >= 2) {
        final candidate = relative.last.trim();
        if (candidate.isNotEmpty) return candidate;
      }
    }
    if (_isDedicatedRecordDirectory(filePath)) {
      final candidate = _lastPathSegment(File(filePath).parent.path).trim();
      if (candidate.isNotEmpty) return candidate;
    }
    return fallbackTitle.trim();
  }

  String _normalizeRecoveredEpisodeTitle(
    String rawTitle, {
    required String groupTitle,
    required String fileName,
  }) {
    final fallback = rawTitle.trim().isNotEmpty
        ? rawTitle.trim()
        : _fileNameBase(fileName).trim();
    var title = fallback;
    final prefixes = _recoveredEpisodeTitlePrefixes(groupTitle);
    for (final prefix in prefixes) {
      title = _stripLooseLeadingText(title, prefix);
    }
    title = _stripLeadingRecoveredSeasonText(title);
    title = _trimRecoveredTitleSeparators(title);
    if (title.isNotEmpty && title != groupTitle.trim()) return title;

    final fileBase = _fileNameBase(fileName).trim();
    if (fileBase.isNotEmpty && fileBase != fallback) {
      title = fileBase;
      for (final prefix in prefixes) {
        title = _stripLooseLeadingText(title, prefix);
      }
      title = _stripLeadingRecoveredSeasonText(title);
      title = _trimRecoveredTitleSeparators(title);
      if (title.isNotEmpty && title != groupTitle.trim()) return title;
    }
    return fallback;
  }

  List<String> _recoveredEpisodeTitlePrefixes(String groupTitle) {
    final prefixes = <String>[];
    void add(String value) {
      final normalized = value.trim();
      if (normalized.isEmpty) return;
      if (prefixes.any(
        (entry) =>
            _normalizeLooseFileToken(entry) ==
            _normalizeLooseFileToken(normalized),
      )) {
        return;
      }
      prefixes.add(normalized);
    }

    add(groupTitle);
    add(_stripTrailingRecoveredSeasonText(groupTitle));
    return prefixes..sort((left, right) => right.length.compareTo(left.length));
  }

  String _stripTrailingRecoveredSeasonText(String value) {
    return value
        .replaceFirst(
          RegExp(
            r'\s*(第\s*\d+\s*[季部卷]|season\s*\d+|s\d{1,2})\s*$',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }

  String _stripLeadingRecoveredSeasonText(String value) {
    return value
        .replaceFirst(
          RegExp(
            r'^\s*(第\s*\d+\s*[季部卷]|season\s*\d+|s\d{1,2})\s*',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }

  String _stripLooseLeadingText(String title, String prefix) {
    final normalizedPrefix = _normalizeLooseFileToken(prefix);
    if (normalizedPrefix.isEmpty) return title;
    var tokenIndex = 0;
    var endIndex = 0;
    for (var index = 0; index < title.length; index += 1) {
      final char = title[index];
      if (_isRecoveredTitleSeparator(char)) {
        continue;
      }
      if (tokenIndex >= normalizedPrefix.length) break;
      if (char.toLowerCase() != normalizedPrefix[tokenIndex]) {
        return title;
      }
      tokenIndex += 1;
      endIndex = index + 1;
      if (tokenIndex == normalizedPrefix.length) {
        return _trimRecoveredTitleSeparators(title.substring(endIndex));
      }
    }
    return title;
  }

  String _trimRecoveredTitleSeparators(String value) {
    var result = value.trim();
    while (result.isNotEmpty && _isRecoveredTitleSeparator(result[0])) {
      result = result.substring(1).trimLeft();
    }
    while (result.isNotEmpty &&
        _isRecoveredTitleSeparator(result[result.length - 1])) {
      result = result.substring(0, result.length - 1).trimRight();
    }
    return result;
  }

  bool _isRecoveredTitleSeparator(String char) {
    return char.trim().isEmpty ||
        const <String>{
          '-',
          '_',
          '.',
          '·',
          '•',
          ':',
          '：',
          '|',
          '/',
          '\\',
          '[',
          ']',
          '(',
          ')',
          '（',
          '）',
          '【',
          '】',
          '「',
          '」',
          '『',
          '』',
          ',',
          '，',
        }.contains(char);
  }

  Directory _recoveredGroupDirectoryForVideo(String videoFilePath) {
    final root = _flyPlayerDownloadRootFromPath(videoFilePath);
    if (root != null) {
      final videoDirectory = File(videoFilePath).parent;
      final relative = _relativePathSegments(
        rootPath: root,
        childPath: videoDirectory.path,
      );
      if (relative.length >= 2) {
        return Directory(
          <String>[root, ...relative.take(relative.length - 1)].join('/'),
        );
      }
    }
    return _groupDirectoryForVideo(videoFilePath);
  }

  String _recoveredGroupArtworkDirectory(String videoFilePath) {
    final groupDirectory = _recoveredGroupDirectoryForVideo(videoFilePath);
    return '${groupDirectory.path}${Platform.pathSeparator}_artwork';
  }

  List<String> _relativePathSegments({
    required String rootPath,
    required String childPath,
  }) {
    final normalizedRoot = rootPath.trim().replaceAll('\\', '/');
    final normalizedChild = childPath.trim().replaceAll('\\', '/');
    if (normalizedRoot.isEmpty || normalizedChild.isEmpty) {
      return const <String>[];
    }
    final lowerRoot = normalizedRoot.toLowerCase();
    final lowerChild = normalizedChild.toLowerCase();
    if (!lowerChild.startsWith(lowerRoot)) return const <String>[];
    var relative = normalizedChild.substring(normalizedRoot.length);
    while (relative.startsWith('/')) {
      relative = relative.substring(1);
    }
    if (relative.trim().isEmpty) return const <String>[];
    return relative
        .split('/')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
  }

  String _inferRecoveredResolution(
    String fileName, {
    int width = 0,
    int height = 0,
  }) {
    if (width > 0 && height > 0) {
      final longSide = math.max(width, height);
      final shortSide = math.min(width, height);
      if (longSide >= 3500 || shortSide >= 1800) return '2160p';
      if (longSide >= 2500 || shortSide >= 1200) return '1440p';
      if (longSide >= 1700 || shortSide >= 900) return '1080p';
      if (longSide >= 1100 || shortSide >= 650) return '720p';
      if (longSide >= 700 || shortSide >= 360) return '480p';
    }
    final normalized = fileName.toLowerCase();
    if (normalized.contains('2160p') || normalized.contains('4k')) {
      return '2160p';
    }
    for (final value in const <String>['1440p', '1080p', '720p', '480p']) {
      if (normalized.contains(value)) return value;
    }
    return downloadLocalResolutionToken;
  }

  String _formatRecoveredDurationText(int durationSeconds) {
    if (durationSeconds <= 0) return '';
    return '$downloadRecoveredDurationTokenPrefix$durationSeconds';
  }

  String _stableRecoveryId(String raw, int bytes) {
    final digest = crypto.sha256
        .convert(utf8.encode('$raw|${bytes.clamp(0, 1 << 62)}'))
        .toString();
    return digest.substring(0, 24);
  }

  String _normalizeFilePathForComparison(String path) {
    final normalized = path.trim().replaceAll('\\', '/');
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  String? _flyPlayerDownloadRootFromPath(String path) {
    final normalized = path.trim().replaceAll('\\', '/');
    if (normalized.isEmpty) return null;
    final lower = normalized.toLowerCase();
    const marker = '/download/flyplayer';
    final markerIndex = lower.indexOf(marker);
    if (markerIndex < 0) return null;
    return normalized.substring(0, markerIndex + marker.length);
  }

  bool _pathLooksInsideFlyPlayerDownloadRoot(String path) {
    final root = _flyPlayerDownloadRootFromPath(path);
    if (root == null) return false;
    final normalizedRoot = _normalizeFilePathForComparison(root);
    final normalizedPath = _normalizeFilePathForComparison(path);
    return normalizedPath.length > normalizedRoot.length &&
        normalizedPath.startsWith('$normalizedRoot/');
  }

  void _updateDownloadSpeed(String recordId, int received, int timestampMs) {
    final previous = _downloadProgressSamples[recordId];
    final currentSample = _DownloadProgressSample(
      receivedBytes: received,
      timestampMs: timestampMs,
    );
    if (previous != null && received >= previous.receivedBytes) {
      final anchor = _downloadSpeedAnchorSamples[recordId] ?? previous;
      final deltaBytes = received - anchor.receivedBytes;
      final deltaMs = timestampMs - anchor.timestampMs;
      final hasAnchor = _downloadSpeedAnchorSamples.containsKey(recordId);
      final effectiveWindowMs = hasAnchor
          ? _downloadSpeedEstimateWindowMs
          : 400;
      if (deltaBytes >= 0 && deltaMs >= effectiveWindowMs) {
        final estimatedBytesPerSecond = ((deltaBytes * 1000) / deltaMs).round();
        final currentSpeed = _downloadSpeedBytesPerSecond[recordId] ?? 0;
        final smoothedBytesPerSecond = currentSpeed <= 0
            ? estimatedBytesPerSecond
            : ((currentSpeed * 5) + estimatedBytesPerSecond) ~/ 6;
        final lastPublishedAt = _downloadSpeedPublishedAtMs[recordId] ?? 0;
        final shouldPublish =
            lastPublishedAt <= 0 ||
            timestampMs - lastPublishedAt >= _downloadSpeedPublishIntervalMs ||
            _isMeaningfulDownloadSpeedShift(
              currentSpeed: currentSpeed,
              nextSpeed: smoothedBytesPerSecond,
            );
        if (shouldPublish) {
          _downloadSpeedBytesPerSecond[recordId] = smoothedBytesPerSecond;
          _downloadSpeedPublishedAtMs[recordId] = timestampMs;
          notifyListeners();
        }
        _downloadSpeedAnchorSamples[recordId] = currentSample;
      }
    }
    _downloadProgressSamples[recordId] = currentSample;
  }

  void _clearDownloadSpeed(String recordId) {
    _downloadSpeedBytesPerSecond.remove(recordId);
    _downloadProgressSamples.remove(recordId);
    _downloadSpeedAnchorSamples.remove(recordId);
    _downloadSpeedPublishedAtMs.remove(recordId);
  }

  bool _isMeaningfulDownloadSpeedShift({
    required int currentSpeed,
    required int nextSpeed,
  }) {
    if (currentSpeed <= 0 || nextSpeed <= 0) {
      return true;
    }
    final delta = (currentSpeed - nextSpeed).abs();
    if (delta < _downloadSpeedMinChangeBytesPerSecond) {
      return false;
    }
    return delta >= ((currentSpeed * 18) ~/ 100);
  }

  /// Returns true if the server may need time (transcode) before the file is
  /// ready. The first option in the stream list is the source quality — it
  /// never needs transcode. Anything below the source resolution may need it.
  /// On resume (sourceResolution is null) polling is unnecessary because the
  /// initial download already handled transcode and we reuse the same task.
  bool _shouldPollTaskProgressForResolution(
    String resolution, {
    String? sourceResolution,
  }) {
    final normalized = resolution.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    // The first option in the stream list is the highest/source quality.
    if (sourceResolution != null) {
      return sourceResolution.trim().toLowerCase() != normalized;
    }
    // Resume — task was already created, no transcode polling needed.
    return false;
  }

  void _startDownloadTaskProgressPolling({
    required FeiniuApi api,
    required DownloadTaskRecord record,
  }) {
    if (record.remoteTaskId.trim().isEmpty) return;
    _stopDownloadTaskProgressPolling(record.id, notify: false);

    Future<void> pollOnce() async {
      await _pollDownloadTaskProgressOnce(
        recordId: record.id,
        fetchProgress: api.getDownloadTaskProgress,
      );
    }

    _downloadTaskProgressPollers[record.id] = Timer.periodic(
      _taskProgressPollInterval,
      (_) => unawaited(pollOnce()),
    );
    unawaited(pollOnce());
  }

  Future<void> _pollDownloadTaskProgressOnce({
    required String recordId,
    required Future<DownloadTaskProgressInfo?> Function(String remoteTaskId)
    fetchProgress,
  }) async {
    if (!_downloadTaskProgressInFlight.add(recordId)) {
      return;
    }
    try {
      final activeRecord = _records.firstWhere(
        (entry) => entry.id == recordId,
        orElse: () => DownloadTaskService._emptyRecord,
      );
      if (activeRecord == _emptyRecord ||
          activeRecord.status != DownloadTaskStatus.downloading) {
        _stopDownloadTaskProgressPolling(recordId);
        return;
      }
      final progress = await fetchProgress(activeRecord.remoteTaskId);
      final previous = _downloadTaskProgress[recordId];
      if (progress == null || progress.status != 0) {
        _stopDownloadTaskProgressPolling(recordId, notify: previous != null);
        return;
      }
      final normalized = DownloadTaskProgressInfo(
        status: progress.status,
        percents: progress.percents.clamp(0, 100).toInt(),
      );
      if (previous?.status == normalized.status &&
          previous?.percents == normalized.percents) {
        return;
      }
      _downloadTaskProgress[recordId] = normalized;
      notifyListeners();
    } catch (_) {
    } finally {
      _downloadTaskProgressInFlight.remove(recordId);
    }
  }

  void _stopDownloadTaskProgressPolling(String recordId, {bool notify = true}) {
    _downloadTaskProgressPollers.remove(recordId)?.cancel();
    _downloadTaskProgressInFlight.remove(recordId);
    final removed = _downloadTaskProgress.remove(recordId);
    if (notify && removed != null) {
      notifyListeners();
    }
  }

  Future<void> _normalizeLegacyGroupArtwork() async {
    for (int index = 0; index < _records.length; index++) {
      final record = _records[index];
      if (record.groupPosterUrls.isEmpty || record.posterUrls.isEmpty) continue;
      final sameArtwork = await _hasSameArtworkContent(
        record.groupPosterUrls.first,
        record.posterUrls.first,
      );
      if (!sameArtwork) continue;
      _records[index] = record.copyWith(groupPosterUrls: const <String>[]);
    }
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(_persist());
    });
  }

  Future<void> _persist() async {
    final previous = _persistQueue ?? Future<void>.value();
    final current = previous.catchError((Object _) {}).then((_) async {
      final encoded = jsonEncode(
        _records.map((entry) => entry.toJson()).toList(growable: false),
      );
      final file = await _recordsFile();
      final tmp = File(
        '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      await tmp.writeAsString(encoded, flush: true);
      await tmp.rename(file.path);
    });
    _persistQueue = current;
    try {
      await current;
    } catch (error, stackTrace) {
      await AppLogService.instance.recordWarning(
        error: error,
        stackTrace: stackTrace,
        source: 'download_records_persist',
      );
    } finally {
      if (identical(_persistQueue, current)) {
        _persistQueue = null;
      }
    }
  }

  Future<void> _refreshDownloadedGroupMetadataInternal(
    NasProvider provider,
  ) async {
    await initialize();
    final groups = groupsByStatus(DownloadTaskStatus.downloaded);
    if (groups.isEmpty) return;
    final api = FeiniuApi(provider);
    var changed = false;
    for (final group in groups) {
      final meta = await _resolveStoredGroupMeta(
        api: api,
        provider: provider,
        record: group.leadRecord,
      );
      if (meta == null) continue;
      for (int index = 0; index < _records.length; index++) {
        final record = _records[index];
        if (_canonicalGroupId(record) != group.id) continue;
        final cachedGroupPosterUrls = meta.posterUrls.isEmpty
            ? const <String>[]
            : await _cacheArtworkUrls(
                provider: provider,
                sourceUrls: meta.posterUrls,
                videoFilePath: record.filePath,
                suffix: 'group_cover',
                overwrite: true,
              );
        final updated = record.copyWith(
          groupId: meta.id,
          groupTitle: meta.title,
          groupPosterUrls: cachedGroupPosterUrls,
        );
        if (_isSameGroupMeta(record, updated)) continue;
        _records[index] = updated;
        changed = true;
      }
    }
    if (!changed) return;
    _sortRecords();
    notifyListeners();
    await _persist();
  }

  StreamListOption? _pickStreamOption(
    List<StreamListOption> options, {
    required String resolution,
    String mediaGuid = '',
  }) {
    return selectDownloadStreamOption(
      options,
      resolution: resolution,
      mediaGuid: mediaGuid,
    );
  }

  Future<String> _buildDownloadFilePath({
    required String groupTitle,
    required String fileName,
  }) async {
    var hasAccess = await StorageAccessService.hasFileAccess();
    if (!hasAccess) {
      await StorageAccessService.requestFileAccess();
      hasAccess = await StorageAccessService.hasFileAccess();
    }
    if (!hasAccess) {
      throw const FileSystemException('missing external storage permission');
    }
    final root = await StorageAccessService.primaryStorageRoot();
    final storageRoot = root.trim().isEmpty
        ? '/storage/emulated/0'
        : root.trim();
    final safeGroupTitle = _sanitizePathSegment(groupTitle);
    final safeFileName = _sanitizeFileName(fileName);
    final groupDirectory = Directory(
      '$storageRoot/Download/$_downloadFolderName/$safeGroupTitle',
    );
    await groupDirectory.create(recursive: true);
    final recordDirectoryPath = _resolveUniqueDirectoryPath(
      groupDirectory.path,
      _sanitizePathSegment(_fileNameBase(safeFileName)),
    );
    final recordDirectory = Directory(recordDirectoryPath);
    await recordDirectory.create(recursive: true);
    return '${recordDirectory.path}/$safeFileName';
  }

  String _resolveFileName(
    StreamFileInfo? fileInfo,
    String title,
    String resolution,
  ) {
    final source = (fileInfo?.fileName ?? '').trim();
    if (source.isNotEmpty) {
      return _sanitizeFileName(source);
    }
    final safeTitle = _sanitizeFileName(
      title.trim().isEmpty ? 'download' : title,
    );
    final suffix = resolution.trim().isEmpty ? '' : '_${resolution.trim()}';
    return '$safeTitle$suffix.mkv';
  }

  String _resolveImportedFileName({
    required String promotedFileName,
    required String suggestedFileName,
    required StreamFileInfo? fileInfo,
    required String title,
    required String resolution,
  }) {
    final promoted = promotedFileName.trim();
    if (promoted.isNotEmpty) {
      return _sanitizeFileName(promoted);
    }
    final suggested = suggestedFileName.trim();
    if (suggested.isNotEmpty) {
      return _sanitizeFileName(suggested);
    }
    if (fileInfo != null) {
      return _resolveFileName(fileInfo, title, resolution);
    }
    final safeTitle = _sanitizeFileName(
      title.trim().isEmpty ? 'download' : title,
    );
    final suffix = resolution.trim().isEmpty ? '' : '_${resolution.trim()}';
    return '$safeTitle$suffix.mp4';
  }

  Future<void> _relocateImportedFile(
    String sourcePath,
    String targetPath,
  ) async {
    final sourceFile = File(sourcePath);
    final targetFile = File(targetPath);
    await targetFile.parent.create(recursive: true);
    if (targetFile.existsSync()) {
      await targetFile.delete();
    }
    try {
      await sourceFile.rename(targetFile.path);
      return;
    } catch (_) {}
    await sourceFile.copy(targetFile.path);
    if (sourceFile.existsSync()) {
      await sourceFile.delete();
    }
  }

  Future<List<String>> _cacheArtworkUrls({
    required NasProvider provider,
    required List<String> sourceUrls,
    required String videoFilePath,
    required String suffix,
    bool overwrite = false,
  }) async {
    final normalizedUrls = sourceUrls
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (normalizedUrls.isEmpty) return const <String>[];

    final firstUrl = normalizedUrls.first;
    if (_isLocalPath(firstUrl) || firstUrl.startsWith('file://')) {
      return <String>[firstUrl];
    }

    final targetPath = _artworkFilePath(videoFilePath, suffix, firstUrl);
    final targetFile = File(targetPath);
    try {
      final shouldWrite = overwrite || !targetFile.existsSync();
      if (shouldWrite) {
        final response = await Dio().get<List<int>>(
          firstUrl,
          options: Options(
            responseType: ResponseType.bytes,
            headers: <String, String>{
              'Authorization': provider.token,
              'Trim-MC-token': provider.token,
            },
            receiveTimeout: const Duration(seconds: 30),
            sendTimeout: const Duration(seconds: 15),
            validateStatus: (status) => status == 200,
          ),
        );
        final bytes = response.data;
        if (bytes == null || bytes.isEmpty) {
          return normalizedUrls;
        }
        await targetFile.parent.create(recursive: true);
        await targetFile.writeAsBytes(bytes, flush: true);
      }
      return <String>[Uri.file(targetFile.path).toString()];
    } catch (_) {
      if (targetFile.existsSync()) {
        return <String>[Uri.file(targetFile.path).toString()];
      }
      return normalizedUrls;
    }
  }

  Future<List<String>> _cacheRecoveredBackendArtworkUrls({
    required NasProvider provider,
    required List<String> sourceUrls,
    required String videoFilePath,
    required String suffix,
  }) async {
    final urls = await _cacheArtworkUrls(
      provider: provider,
      sourceUrls: sourceUrls,
      videoFilePath: videoFilePath,
      suffix: suffix,
      overwrite: true,
    );
    if (suffix == 'group_cover') {
      await _deleteRedundantEpisodeGroupArtwork(videoFilePath);
    }
    return await _existingLocalArtworkUrls(urls);
  }

  /// 解析下载记录可离线使用的封面：优先 record 中已落盘的本地封面（缓存成功时 posterUrls/
  /// groupPosterUrls 即 file://），其次按命名规则探测视频同目录 / group 目录下已下载的 cover
  /// 文件（缓存成功但 record 仍存在线 URL 的兜底）；都没有才返回空，由调用方再退在线 URL。
  /// 离线选集取图（Flutter 选集面板 + 原生壳 episodes）共用此入口。
  /// 改成异步：原先整条链路（existsSync/listSync/lengthSync）在主 isolate 做目录扫描，
  /// 选集列表按记录数批量解析时会明显卡顿。
  Future<String> resolveExistingLocalCover(DownloadTaskRecord record) async {
    final fromRecord = await _existingLocalArtworkUrls(<String>[
      ...record.posterUrls,
      ...record.groupPosterUrls,
    ]);
    if (fromRecord.isNotEmpty) return fromRecord.first;
    final probed = await _probeDownloadedCoverFiles(record.filePath);
    if (probed.isNotEmpty) return probed.first;
    return '';
  }

  /// 扫描该下载在磁盘上的相关目录，找出已落盘的封面图（不依赖具体文件名）。优先 cover/
  /// poster 命名，其余图片兜底。覆盖 <视频目录> / <视频目录>/_artwork / group 的 _artwork。
  Future<List<String>> _probeDownloadedCoverFiles(String videoFilePath) async {
    final normalized = videoFilePath.trim();
    if (normalized.isEmpty) return const <String>[];
    final sep = Platform.pathSeparator;
    final videoParent = File(normalized).parent.path;
    final dirs = <String>{
      videoParent,
      '$videoParent${sep}_artwork',
      _groupArtworkDirectory(normalized),
    };
    final preferred = <String>[]; // cover*/poster* 优先
    final others = <String>[]; // 目录内其它图片兜底
    for (final dirPath in dirs) {
      try {
        final dir = Directory(dirPath);
        if (!await dir.exists()) continue;
        final entities = await dir.list(followLinks: false).toList();
        for (final entity in entities) {
          if (entity is! File) continue;
          final name =
              (entity.uri.pathSegments.isNotEmpty
                      ? entity.uri.pathSegments.last
                      : entity.path.split(sep).last)
                  .toLowerCase();
          final isImage = _recoveredImageExtensions.any(
            (ext) => name.endsWith(ext),
          );
          if (!isImage) continue;
          if (await entity.length() <= 0) continue;
          final url = Uri.file(entity.path).toString();
          if (name.contains('cover') || name.contains('poster')) {
            preferred.add(url);
          } else {
            others.add(url);
          }
        }
      } catch (_) {}
    }
    return <String>[...preferred, ...others];
  }

  Future<List<String>> _existingLocalArtworkUrls(List<String> urls) async {
    final result = <String>[];
    for (final url in urls) {
      final path = _localFilePathFromUrl(url) ?? (_isLocalPath(url) ? url : '');
      if (path.trim().isEmpty) continue;
      try {
        final file = File(path);
        if (await file.exists() && await file.length() > 0) {
          result.add(Uri.file(file.path).toString());
        }
      } catch (_) {}
    }
    return result;
  }

  bool _shouldReuseEpisodeArtworkForGroup({
    required List<String> posterUrls,
    required List<String> groupPosterUrls,
  }) {
    final posterKeys = _normalizedArtworkIdentitySet(posterUrls);
    final groupPosterKeys = _normalizedArtworkIdentitySet(groupPosterUrls);
    if (posterKeys.isEmpty || groupPosterKeys.isEmpty) return false;
    if (posterKeys.length != groupPosterKeys.length) return false;
    return posterKeys.containsAll(groupPosterKeys);
  }

  Set<String> _normalizedArtworkIdentitySet(List<String> urls) {
    return urls
        .map(_normalizeArtworkIdentity)
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  String _normalizeArtworkIdentity(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return trimmed.toLowerCase();
    if (uri.hasScheme && uri.scheme != 'file') {
      final path = uri.path.trim().toLowerCase();
      final width = uri.queryParameters['w'] ?? uri.queryParameters['width'];
      final height = uri.queryParameters['h'] ?? uri.queryParameters['height'];
      return <String>[
        uri.host.toLowerCase(),
        path,
        width ?? '',
        height ?? '',
      ].join('|');
    }
    return trimmed.replaceAll('\\', '/').toLowerCase();
  }

  Future<void> _deleteRedundantEpisodeGroupArtwork(String videoFilePath) async {
    final videoFile = File(videoFilePath);
    final episodeDirectory = videoFile.parent;
    final groupArtworkPath = _normalizeFilePathForComparison(
      _recoveredGroupArtworkDirectory(videoFilePath),
    );
    final episodeArtworkDirectory = Directory(
      '${episodeDirectory.path}${Platform.pathSeparator}_artwork',
    );
    final baseName = _fileNameBase(_lastPathSegment(videoFilePath));

    for (final extension in _recoveredImageExtensions) {
      await _deleteIfExists(
        File(
          '${episodeDirectory.path}${Platform.pathSeparator}group_cover$extension',
        ),
      );
      await _deleteIfExists(
        File(
          '${episodeDirectory.path}${Platform.pathSeparator}${baseName}_group_cover$extension',
        ),
      );
    }

    if (_normalizeFilePathForComparison(episodeArtworkDirectory.path) ==
        groupArtworkPath) {
      return;
    }
    for (final extension in _recoveredImageExtensions) {
      await _deleteIfExists(
        File(
          '${episodeArtworkDirectory.path}${Platform.pathSeparator}group_cover$extension',
        ),
      );
    }
    await _deleteEmptyDirectoriesUpward(episodeArtworkDirectory);
  }

  String _artworkFilePath(
    String videoFilePath,
    String suffix,
    String sourceUrl,
  ) {
    final extension = _imageExtensionFromUrl(sourceUrl);
    if (suffix == 'group_cover') {
      final groupArtworkDirectory = Directory(
        _groupArtworkDirectory(videoFilePath),
      );
      return '${groupArtworkDirectory.path}/group_cover$extension';
    }
    final episodeDirectory = File(videoFilePath).parent;
    final baseName = suffix == 'cover'
        ? 'cover'
        : '${_fileNameBase(episodeDirectory.uri.pathSegments.isNotEmpty ? episodeDirectory.uri.pathSegments.last : videoFilePath)}_$suffix';
    return '${episodeDirectory.path}/$baseName$extension';
  }

  String _groupArtworkDirectory(String videoFilePath) {
    final groupDirectory = _recoveredGroupDirectoryForVideo(videoFilePath);
    return '${groupDirectory.path}${Platform.pathSeparator}_artwork';
  }

  Directory _groupDirectoryForVideo(String videoFilePath) {
    final videoFile = File(videoFilePath);
    final episodeDirectory = videoFile.parent;
    if (_isDedicatedRecordDirectory(videoFilePath)) {
      return episodeDirectory.parent;
    }
    return episodeDirectory;
  }

  bool _isDedicatedRecordDirectory(String videoFilePath) {
    final videoFile = File(videoFilePath);
    final directoryName = _sanitizePathSegment(
      videoFile.parent.uri.pathSegments.isNotEmpty
          ? videoFile.parent.uri.pathSegments.last
          : videoFile.parent.path,
    );
    final baseName = _sanitizePathSegment(
      _fileNameBase(
        videoFile.uri.pathSegments.isNotEmpty
            ? videoFile.uri.pathSegments.last
            : videoFilePath,
      ),
    );
    return directoryName == baseName ||
        directoryName.startsWith('${baseName}_');
  }

  String _fileNameBase(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot <= 0) return fileName;
    return fileName.substring(0, lastDot);
  }

  String _imageExtensionFromUrl(String sourceUrl) {
    final uri = Uri.tryParse(sourceUrl.trim());
    final path = (uri?.path ?? sourceUrl).toLowerCase();
    for (final ext in const <String>['.jpg', '.jpeg', '.png', '.webp']) {
      if (path.endsWith(ext)) return ext;
    }
    return '.img';
  }

  bool _isLocalPath(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.startsWith('/')) return true;
    return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(trimmed);
  }

  Future<_StoredGroupMeta?> _resolveStoredGroupMeta({
    required FeiniuApi api,
    required NasProvider provider,
    required DownloadTaskRecord record,
  }) async {
    try {
      final detail = await api.getItemDetail(record.itemGuid);
      final item = _detailItem(detail);
      final seriesTitle = (item['tv_title'] ?? '').toString().trim();
      final candidates = <String>{
        (detail['parent_guid'] ?? '').toString().trim(),
        (item['parent_guid'] ?? '').toString().trim(),
      }.where((value) => value.isNotEmpty).toList(growable: false);

      for (final guid in candidates) {
        final parentDetail = await api.getItemDetail(guid);
        final parentItem = _detailItem(parentDetail);
        final collectionTitle = _collectionTitleFromMap(parentItem);
        final posterPath = (parentItem['posters'] ?? parentItem['poster'] ?? '')
            .toString()
            .trim();
        return _StoredGroupMeta(
          id: guid,
          title: _composeGroupTitle(
            seriesTitle: seriesTitle,
            collectionTitle: collectionTitle,
          ),
          posterUrls: posterPath.isEmpty
              ? const <String>[]
              : ApiUrlHelper.imageCandidates(
                  provider.baseUrl,
                  posterPath,
                  width: 720,
                ),
        );
      }

      final currentCollectionTitle = _collectionTitleFromMap(item);
      if (currentCollectionTitle.isEmpty) return null;
      final currentGuid = (item['guid'] ?? detail['guid'] ?? '')
          .toString()
          .trim();
      final currentPosterPath = (item['posters'] ?? item['poster'] ?? '')
          .toString()
          .trim();
      return _StoredGroupMeta(
        id: currentGuid.isEmpty ? record.groupId : currentGuid,
        title: _composeGroupTitle(
          seriesTitle: seriesTitle,
          collectionTitle: currentCollectionTitle,
        ),
        posterUrls: currentPosterPath.isEmpty
            ? const <String>[]
            : ApiUrlHelper.imageCandidates(
                provider.baseUrl,
                currentPosterPath,
                width: 720,
              ),
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _detailItem(Map<String, dynamic> detail) {
    final nested = detail['item'];
    if (nested is Map<String, dynamic>) return nested;
    return detail;
  }

  static String _collectionTitleFromMap(Map<String, dynamic> item) {
    final title = (item['title'] ?? '').toString().trim();
    if (title.isNotEmpty) return title;
    final seasonNumber = int.tryParse('${item['season_number'] ?? ''}') ?? 0;
    if (seasonNumber > 0) return '$downloadSeasonLabelTokenPrefix$seasonNumber';
    return '';
  }

  static String _composeGroupTitle({
    required String seriesTitle,
    required String collectionTitle,
  }) {
    final series = seriesTitle.trim();
    final collection = collectionTitle.trim();
    if (series.isEmpty) return collection;
    if (collection.isEmpty || collection == series) return series;
    return '$series $collection';
  }

  bool _isSameGroupMeta(DownloadTaskRecord lhs, DownloadTaskRecord rhs) {
    if (lhs.groupId != rhs.groupId) return false;
    if (lhs.groupTitle != rhs.groupTitle) return false;
    if (lhs.groupPosterUrls.length != rhs.groupPosterUrls.length) return false;
    for (int index = 0; index < lhs.groupPosterUrls.length; index++) {
      if (lhs.groupPosterUrls[index] != rhs.groupPosterUrls[index]) {
        return false;
      }
    }
    return true;
  }

  Future<bool> _hasSameArtworkContent(String lhs, String rhs) async {
    final leftPath = _localFilePathFromUrl(lhs);
    final rightPath = _localFilePathFromUrl(rhs);
    if (leftPath == null || rightPath == null) return false;
    if (leftPath == rightPath) return true;
    try {
      final leftFile = File(leftPath);
      final rightFile = File(rightPath);
      if (!await leftFile.exists() || !await rightFile.exists()) return false;
      final leftLength = await leftFile.length();
      final rightLength = await rightFile.length();
      if (leftLength != rightLength) return false;
      final leftBytes = await leftFile.readAsBytes();
      final rightBytes = await rightFile.readAsBytes();
      if (leftBytes.lengthInBytes != rightBytes.lengthInBytes) return false;
      for (int index = 0; index < leftBytes.length; index++) {
        if (leftBytes[index] != rightBytes[index]) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  String? _localFilePathFromUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri?.scheme == 'file') {
      try {
        return uri!.toFilePath(windows: Platform.isWindows);
      } catch (_) {
        return null;
      }
    }
    if (_isLocalPath(trimmed)) return trimmed;
    return null;
  }

  String _sanitizePathSegment(String raw) {
    final normalized = raw.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return normalized.isEmpty ? 'Downloads' : normalized;
  }

  String _sanitizeFileName(String raw) {
    final normalized = raw.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return normalized.isEmpty ? 'download.mkv' : normalized;
  }

  Future<void> _deleteRecordArtifacts(DownloadTaskRecord record) async {
    final path = record.filePath.trim();
    if (path.isEmpty) return;
    final videoFile = File(path);
    final episodeDirectory = videoFile.parent;
    final baseName = _fileNameBase(
      videoFile.uri.pathSegments.isNotEmpty
          ? videoFile.uri.pathSegments.last
          : path,
    );

    if (_isDedicatedRecordDirectory(path)) {
      try {
        if (await episodeDirectory.exists()) {
          await episodeDirectory.delete(recursive: true);
        }
      } catch (_) {}
      return;
    }

    try {
      if (await videoFile.exists()) {
        await videoFile.delete();
      }
    } catch (_) {}

    for (final extension in const <String>[
      '.ass',
      '.ssa',
      '.srt',
      '.vtt',
      '.sub',
      '.sup',
      '.idx',
      '.lrc',
    ]) {
      final subtitleFile = File('${episodeDirectory.path}/$baseName$extension');
      try {
        if (await subtitleFile.exists()) {
          await subtitleFile.delete();
        }
      } catch (_) {}
    }

    for (final danmakuFile in _localDanmakuCandidatesForVideo(path)) {
      await _deleteIfExists(danmakuFile);
    }

    for (final extension in _recoveredImageExtensions) {
      await _deleteIfExists(File('${episodeDirectory.path}/cover$extension'));
      await _deleteIfExists(
        File('${episodeDirectory.path}/${baseName}_cover$extension'),
      );
      await _deleteIfExists(
        File('${episodeDirectory.path}/group_cover$extension'),
      );
      await _deleteIfExists(
        File('${episodeDirectory.path}/${baseName}_group_cover$extension'),
      );
    }
    await _deleteRedundantEpisodeGroupArtwork(path);
    await _deleteIfExists(_recoveryMetadataFileForVideoPath(path));
    await _deleteIfExists(File('$path$_pathRecoveryMetadataSuffix'));
    await _deleteEmptyDirectoriesUpward(episodeDirectory);
  }

  Future<void> _deleteSharedGroupArtwork(String groupDirectoryPath) async {
    final artworkDirectory = Directory(
      '$groupDirectoryPath${Platform.pathSeparator}_artwork',
    );
    try {
      if (await artworkDirectory.exists()) {
        await artworkDirectory.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<void> _deleteEmptyDirectoriesUpward(Directory directory) async {
    var current = directory;
    while (true) {
      final path = current.path;
      final normalizedPath = path.replaceAll('\\', '/');
      if (!normalizedPath.contains('/$_downloadFolderName')) {
        break;
      }
      try {
        if (!await current.exists()) {
          current = current.parent;
          continue;
        }
        final entries = await current.list().toList();
        if (entries.isNotEmpty) break;
        await current.delete();
      } catch (_) {
        break;
      }
      final parent = current.parent;
      if (parent.path == current.path) break;
      current = parent;
      if (!current.path
          .replaceAll('\\', '/')
          .contains('/$_downloadFolderName')) {
        break;
      }
    }
  }

  String _resolveUniqueDirectoryPath(String parentPath, String directoryName) {
    final safeDirectoryName = _sanitizePathSegment(directoryName);
    // Try to reuse an existing empty directory first to avoid proliferation.
    var index = 1;
    var baseCandidate = '$parentPath/$safeDirectoryName';
    while (Directory(baseCandidate).existsSync() ||
        File(baseCandidate).existsSync()) {
      final dir = Directory(baseCandidate);
      if (dir.existsSync() && dir.listSync().isEmpty) {
        return baseCandidate; // Reuse empty directory.
      }
      baseCandidate = '$parentPath/${safeDirectoryName}_$index';
      index += 1;
    }
    return baseCandidate;
  }

  SubtitleTrackOption? _resolveDownloadSubtitleTrack(
    List<SubtitleTrackOption> tracks, {
    SubtitleTrackOption? preferredSubtitleTrack,
    String preferredSubtitleGuid = '',
  }) {
    final subtitleCandidates = tracks
        .where(_isDownloadableSubtitleTrack)
        .toList(growable: false);
    if (subtitleCandidates.isEmpty) return null;

    final preferredGuid = preferredSubtitleGuid.trim();
    final preferredTrack = preferredSubtitleTrack;
    if (preferredTrack != null &&
        _isDownloadableSubtitleTrack(preferredTrack)) {
      for (final track in subtitleCandidates) {
        if (track.guid == preferredTrack.guid) {
          return track;
        }
      }
      if (preferredTrack.mediaGuid.trim().isEmpty ||
          preferredTrack.mediaGuid == subtitleCandidates.first.mediaGuid) {
        return preferredTrack;
      }
    }
    if (preferredGuid.isNotEmpty) {
      for (final track in subtitleCandidates) {
        if (track.guid == preferredGuid) return track;
      }
    }
    for (final track in subtitleCandidates) {
      if (track.isDefaultOption) return track;
    }
    return subtitleCandidates.first;
  }

  bool _isDownloadableSubtitleTrack(SubtitleTrackOption track) {
    if (track.guid.trim().isEmpty || track.guid.startsWith('local:')) {
      return false;
    }
    if (track.isBitmap == 1) return false;
    return track.isExternal == 1 || track.extraFile == 1;
  }

  Future<String?> _materializeSubtitleForRecord({
    required FeiniuApi? api,
    required DownloadTaskRecord record,
    required SubtitleTrackOption? subtitleTrack,
    String? localSubtitleFilePath,
  }) async {
    final localFilePath = _resolveImportedLocalSubtitlePath(
      subtitleTrack: subtitleTrack,
      explicitFilePath: localSubtitleFilePath,
    );
    if (localFilePath != null) {
      try {
        final sourceFile = File(localFilePath);
        if (!sourceFile.existsSync()) return null;
        if (subtitleTrack == null) return null;
        final targetFile = File(
          _subtitleFilePath(record.filePath, subtitleTrack),
        );
        await targetFile.parent.create(recursive: true);
        if (targetFile.existsSync()) {
          await targetFile.delete();
        }
        await sourceFile.copy(targetFile.path);
        return targetFile.path;
      } catch (error, stackTrace) {
        await AppLogService.instance.recordWarning(
          error: error,
          stackTrace: stackTrace,
          source: 'download-subtitle-local',
          details:
              'item=${record.itemGuid} subtitle=${subtitleTrack?.guid ?? ''} media=${record.mediaGuid}',
        );
      }
      return null;
    }
    if (subtitleTrack == null || api == null) return null;
    if (!_isDownloadableSubtitleTrack(subtitleTrack)) return null;
    try {
      final text = await api.downloadSubtitleText(subtitleTrack.guid);
      if (text.trim().isEmpty) return null;
      final targetFile = File(
        _subtitleFilePath(record.filePath, subtitleTrack),
      );
      await targetFile.parent.create(recursive: true);
      await targetFile.writeAsString(text, flush: true);
      return targetFile.path;
    } catch (error, stackTrace) {
      await AppLogService.instance.recordWarning(
        error: error,
        stackTrace: stackTrace,
        source: 'download-subtitle',
        details:
            'item=${record.itemGuid} subtitle=${subtitleTrack.guid} media=${record.mediaGuid}',
      );
    }
    return null;
  }

  List<SubtitleTrackOption> _persistedSubtitleTracksForRecord({
    required DownloadTaskRecord record,
    required List<SubtitleTrackOption> subtitleTracks,
    required SubtitleTrackOption? subtitleTrack,
    required String? localSubtitlePath,
  }) {
    final next = List<SubtitleTrackOption>.from(subtitleTracks);
    if (subtitleTrack == null || localSubtitlePath == null) {
      return next;
    }
    final localTrack = _buildPersistedLocalSubtitleTrack(
      record: record,
      sourceTrack: subtitleTrack,
      localSubtitlePath: localSubtitlePath,
    );
    next.removeWhere((track) => track.guid.trim() == localTrack.guid);
    next.add(localTrack);
    return next;
  }

  SubtitleTrackOption _buildPersistedLocalSubtitleTrack({
    required DownloadTaskRecord record,
    required SubtitleTrackOption sourceTrack,
    required String localSubtitlePath,
  }) {
    final localFile = File(localSubtitlePath);
    final fileName = localFile.uri.pathSegments.isNotEmpty
        ? localFile.uri.pathSegments.last
        : localFile.path.split(Platform.pathSeparator).last;
    final guid =
        'local:${Uri.file(localFile.path, windows: Platform.isWindows)}';
    final extension = _subtitleExtension(sourceTrack);
    return SubtitleTrackOption(
      mediaGuid: record.mediaGuid.trim().isNotEmpty
          ? record.mediaGuid.trim()
          : sourceTrack.mediaGuid,
      guid: guid,
      title: fileName,
      codecName: extension,
      format: extension,
      language: sourceTrack.language.trim(),
      index: -1,
      isDefault: sourceTrack.isDefault,
      forced: sourceTrack.forced,
      isExternal: 1,
      extraFile: 1,
      isBitmap: sourceTrack.isBitmap,
    );
  }

  Future<SubtitleTrackOption?> _resolveImportedCacheSubtitleTrack({
    required FeiniuApi? api,
    required String itemGuid,
    required String mediaGuid,
  }) async {
    if (api == null) return null;
    final normalizedItemGuid = itemGuid.trim();
    final normalizedMediaGuid = mediaGuid.trim();
    if (normalizedItemGuid.isEmpty || normalizedMediaGuid.isEmpty) {
      return null;
    }
    try {
      final streamData = await api.getStreamTrackData(normalizedItemGuid);
      return _resolveDownloadSubtitleTrack(
        streamData.subtitlesForMedia(normalizedMediaGuid),
      );
    } catch (_) {
      return null;
    }
  }

  Future<_ImportedCacheArtwork> _resolveImportedCacheArtwork({
    required NasProvider provider,
    required String itemGuid,
    required List<String> fallbackPosterUrls,
    required List<String> fallbackGroupPosterUrls,
  }) async {
    final detailPosterUrls = await _fetchItemPosterUrls(
      provider: provider,
      itemGuid: itemGuid,
    );
    final normalizedFallbackPosterUrls = _normalizedArtworkUrls(
      fallbackPosterUrls,
    );
    final normalizedFallbackGroupPosterUrls = _normalizedArtworkUrls(
      fallbackGroupPosterUrls,
    );
    final resolvedPosterUrls = detailPosterUrls.isNotEmpty
        ? detailPosterUrls
        : normalizedFallbackPosterUrls;
    var resolvedGroupPosterUrls = normalizedFallbackGroupPosterUrls;
    if (resolvedGroupPosterUrls.isEmpty) {
      resolvedGroupPosterUrls = resolvedPosterUrls;
    }
    return _ImportedCacheArtwork(
      posterUrls: resolvedPosterUrls,
      groupPosterUrls: resolvedGroupPosterUrls,
    );
  }

  Future<List<String>> _fetchItemPosterUrls({
    required NasProvider provider,
    required String itemGuid,
  }) async {
    final normalizedItemGuid = itemGuid.trim();
    if (normalizedItemGuid.isEmpty) return const <String>[];
    try {
      final api = FeiniuApi(provider);
      final detail = await api.getItemDetail(normalizedItemGuid);
      final rawItem = detail['item'];
      final item = rawItem is Map
          ? rawItem.map((key, value) => MapEntry('$key', value))
          : detail;
      final posterPath = (item['posters'] ?? item['poster'] ?? '')
          .toString()
          .trim();
      if (posterPath.isEmpty) return const <String>[];
      return ApiUrlHelper.imageCandidates(
        provider.baseUrl,
        posterPath,
        width: 720,
        preferDirectPath: true,
      );
    } catch (_) {
      return const <String>[];
    }
  }

  List<String> _normalizedArtworkUrls(List<String> sourceUrls) {
    return sourceUrls
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  String _subtitleFilePath(
    String videoFilePath,
    SubtitleTrackOption subtitleTrack,
  ) {
    final videoFile = File(videoFilePath);
    final baseName = _fileNameBase(
      videoFile.uri.pathSegments.isNotEmpty
          ? videoFile.uri.pathSegments.last
          : videoFilePath,
    );
    final extension = _subtitleExtension(subtitleTrack);
    return '${videoFile.parent.path}/$baseName.$extension';
  }

  String? _resolveImportedLocalSubtitlePath({
    required SubtitleTrackOption? subtitleTrack,
    String? explicitFilePath,
  }) {
    final normalizedPath = (explicitFilePath ?? '').trim();
    if (normalizedPath.isNotEmpty) {
      return normalizedPath;
    }
    final guid = subtitleTrack?.guid.trim() ?? '';
    if (!guid.startsWith('local:')) {
      return null;
    }
    final fileUri = Uri.tryParse(guid.substring('local:'.length));
    if (fileUri == null || fileUri.scheme != 'file') {
      return null;
    }
    try {
      return fileUri.toFilePath(windows: Platform.isWindows);
    } catch (_) {
      return null;
    }
  }

  String _subtitleExtension(SubtitleTrackOption subtitleTrack) {
    final format = subtitleTrack.format.trim().toLowerCase();
    if (format.isNotEmpty) {
      final normalized = format.replaceAll(RegExp(r'[^a-z0-9]+'), '');
      if (normalized.isNotEmpty) return normalized;
    }
    final codec = subtitleTrack.codecName.trim().toLowerCase();
    if (codec.contains('srt')) return 'srt';
    if (codec.contains('ssa')) return 'ssa';
    if (codec.contains('vtt')) return 'vtt';
    return 'ass';
  }

  Future<void> _prefetchDanmakuForDownload({
    required NasProvider provider,
    required DownloadTaskRecord record,
  }) async {
    final normalizedItemGuid = record.itemGuid.trim();
    if (normalizedItemGuid.isEmpty) {
      return;
    }
    try {
      final api = FeiniuApi(provider);
      final playInfo = await api.getPlayInfo(normalizedItemGuid);
      final item = playInfo.item;
      // 持久化 tmid/季集号到下载记录：离线时弹幕 tmid 精确搜索 + 选集/弹幕集匹配仍可用，
      // 与 DanDanPlay 是否配置/匹配成功无关（playItem 离线拿不到，这里趁在线落盘）。
      final metaTmid = item.trimId.trim();
      final metaSeason = item.seasonNumber;
      final metaEpisode = item.episodeNumber;
      if (metaTmid.isNotEmpty || metaSeason > 0 || metaEpisode > 0) {
        final base = _recordById(record.id) ?? record;
        if (base.tmdbId != metaTmid ||
            base.seasonNumber != metaSeason ||
            base.episodeNumber != metaEpisode) {
          _upsertRecord(
            base.copyWith(
              tmdbId: metaTmid.isNotEmpty ? metaTmid : null,
              seasonNumber: metaSeason > 0 ? metaSeason : null,
              episodeNumber: metaEpisode > 0 ? metaEpisode : null,
            ),
            persistImmediately: true,
          );
        }
      }
      if (!await DanDanPlayConfig.ensureConfigured()) {
        return;
      }
      final seriesTitle = _downloadDanmakuSeriesTitle(
        item: item,
        record: record,
      );
      final itemTitle = item.title.trim().isNotEmpty
          ? item.title.trim()
          : record.title.trim();
      final sourceItemGuid = item.guid.trim().isNotEmpty
          ? item.guid.trim()
          : normalizedItemGuid;
      final sourceMediaGuid = record.mediaGuid.trim().isNotEmpty
          ? record.mediaGuid.trim()
          : playInfo.mediaGuid.trim();
      final sourceSeasonGuid = playInfo.parentGuid.trim();
      final mediaKey = _buildDanmakuMediaKey(
        itemGuid: sourceItemGuid,
        mediaGuid: sourceMediaGuid,
        seasonGuid: sourceSeasonGuid,
        seasonNumber: item.seasonNumber,
        episodeNumber: item.episodeNumber,
        seriesTitle: seriesTitle,
        itemTitle: itemTitle,
      );
      final resolver = DanDanPlayResolver(
        DanDanPlayApi(
          appId: DanDanPlayConfig.appId,
          appSecrets: DanDanPlayConfig.appSecrets,
        ),
      );
      final resolved = await resolver.resolveForPlayback(
        seriesTitle: seriesTitle,
        itemTitle: itemTitle,
        seasonNumber: item.seasonNumber,
        episodeNumber: item.episodeNumber,
        tmdbId: item.trimId.trim(),
      );
      if (resolved == null) {
        return;
      }
      const store = DanmakuSavedSourceStore();
      final savedAtMs = DateTime.now().millisecondsSinceEpoch;
      final source = DanmakuSavedSource(
        type: DanmakuSavedSourceType.danDanPlay,
        mediaKey: mediaKey,
        sourceKey: resolved.item.episodeId.toString(),
        label: resolved.item.displayTitle,
        detail: resolved.item.displaySubtitle,
        ancestorName: item.ancestorName.trim().isNotEmpty
            ? item.ancestorName.trim()
            : record.groupTitle.trim(),
        seriesTitle: seriesTitle,
        itemTitle: itemTitle,
        itemGuid: sourceItemGuid,
        seasonGuid: sourceSeasonGuid,
        mediaGuid: sourceMediaGuid,
        seasonNumber: item.seasonNumber,
        episodeNumber: item.episodeNumber,
        mediaType: item.type.trim(),
        commentCount: resolved.result.comments.length,
        updatedAtMs: savedAtMs,
      );
      await _saveDanmakuSourceWithLocalPriority(store: store, source: source);

      final localFile = await _writeDownloadedDanmakuFile(
        record: record,
        resolved: resolved,
      );
      if (localFile != null) {
        final targets = <_DanmakuRecoveryTarget>[];
        void addTarget(_DanmakuRecoveryTarget target) {
          if (target.mediaKey.trim().isEmpty ||
              targets.any((entry) => entry.mediaKey == target.mediaKey)) {
            return;
          }
          targets.add(target);
        }

        addTarget(
          _DanmakuRecoveryTarget(
            mediaKey: mediaKey,
            seasonGuid: sourceSeasonGuid,
          ),
        );
        for (final target in await _danmakuRecoveryTargetsForRecord(record)) {
          addTarget(target);
        }

        final localLabel = _lastPathSegment(localFile.path);
        final localDetail = resolved.result.sourceLabel.trim().isNotEmpty
            ? resolved.result.sourceLabel.trim()
            : localFile.path;
        final ancestorName = item.ancestorName.trim().isNotEmpty
            ? item.ancestorName.trim()
            : record.groupTitle.trim();
        for (final target in targets) {
          await _saveDanmakuSourceWithLocalPriority(
            store: store,
            source: DanmakuSavedSource(
              type: DanmakuSavedSourceType.downloadedFile,
              mediaKey: target.mediaKey,
              sourceKey: localFile.path,
              label: localLabel,
              detail: localDetail,
              ancestorName: ancestorName,
              seriesTitle: seriesTitle,
              itemTitle: itemTitle,
              itemGuid: sourceItemGuid,
              seasonGuid: target.seasonGuid,
              mediaGuid: sourceMediaGuid,
              seasonNumber: item.seasonNumber,
              episodeNumber: item.episodeNumber,
              mediaType: item.type.trim(),
              commentCount: resolved.result.comments.length,
              updatedAtMs: savedAtMs,
            ),
          );
        }
      }
    } catch (error, stackTrace) {
      await AppLogService.instance.recordWarning(
        error: error,
        stackTrace: stackTrace,
        source: 'download-danmaku-prefetch',
        details: 'item=${record.itemGuid} media=${record.mediaGuid}',
      );
    }
  }

  String _downloadDanmakuSeriesTitle({
    required PlayItem item,
    required DownloadTaskRecord record,
  }) {
    final tvTitle = item.tvTitle.trim();
    if (tvTitle.isNotEmpty) {
      return tvTitle;
    }
    final parentTitle = item.parentTitle.trim();
    if (parentTitle.isNotEmpty) {
      return parentTitle;
    }
    final groupTitle = record.groupTitle.trim();
    if (groupTitle.isNotEmpty) {
      return groupTitle;
    }
    return item.title.trim().isNotEmpty
        ? item.title.trim()
        : record.title.trim();
  }

  String _buildDanmakuMediaKey({
    required String itemGuid,
    required String mediaGuid,
    required String seasonGuid,
    required int seasonNumber,
    required int episodeNumber,
    required String seriesTitle,
    required String itemTitle,
  }) {
    final normalizedItemGuid = itemGuid.trim();
    final normalizedMediaGuid = mediaGuid.trim();
    final normalizedSeasonGuid = seasonGuid.trim();
    if (normalizedItemGuid.isNotEmpty ||
        normalizedMediaGuid.isNotEmpty ||
        normalizedSeasonGuid.isNotEmpty ||
        episodeNumber > 0) {
      return <String>[
        'v2',
        'item=$normalizedItemGuid',
        'media=$normalizedMediaGuid',
        'season=$normalizedSeasonGuid',
        's=$seasonNumber',
        'e=$episodeNumber',
      ].join('|');
    }
    final title = (seriesTitle.trim().isNotEmpty ? seriesTitle : itemTitle)
        .trim();
    return 'fallback:v2:$title:$seasonNumber:$episodeNumber';
  }

  DownloadTaskRecord? _findLatestRecord({
    required String itemGuid,
    required String resolution,
    required DownloadTaskStatus status,
    String mediaGuid = '',
  }) {
    final normalizedMediaGuid = mediaGuid.trim();
    try {
      return _records.firstWhere(
        (record) =>
            record.itemGuid == itemGuid &&
            (normalizedMediaGuid.isEmpty ||
                record.mediaGuid.trim() == normalizedMediaGuid) &&
            record.resolution.trim().toLowerCase() ==
                resolution.trim().toLowerCase() &&
            record.status == status,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearImportedCacheEntry(
    CachedMediaSourceIdentity identity, {
    String resolvedResourceKey = '',
  }) async {
    final explicitKey = identity.resourceKey.trim();
    var resourceKey = resolvedResourceKey.trim().isNotEmpty
        ? resolvedResourceKey.trim()
        : explicitKey;
    if (resourceKey.isEmpty) {
      try {
        final downloadability = await StorageManagementService.instance
            .canPromoteCachedMedia(identity);
        resourceKey = downloadability.resourceKey.trim();
      } catch (_) {
        resourceKey = '';
      }
    }
    if (resourceKey.isEmpty) return;
    try {
      await StorageManagementService.instance.clearPlaybackCacheEntries(
        <String>[resourceKey],
      );
    } catch (_) {}
  }

  String _buildId() {
    return 'download_${DateTime.now().microsecondsSinceEpoch}';
  }

  bool _matchesStatus(DownloadTaskRecord record, DownloadTaskStatus status) {
    if (record.status != status) return false;
    if (status != DownloadTaskStatus.downloaded) return true;
    return _isDownloadedRecordAvailable(record);
  }

  String _normalizeResolutionKey(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return '';
    final digitMatch = RegExp(r'(\d{3,4})').firstMatch(normalized);
    if (digitMatch != null) return digitMatch.group(1) ?? normalized;
    return normalized;
  }

  String _normalizeImportedCacheResolution(String value) {
    final normalized = value.trim();
    if (normalized.isNotEmpty) return normalized;
    return downloadCacheResolutionToken;
  }

  bool _isDownloadedRecordAvailable(DownloadTaskRecord record) {
    if (record.status != DownloadTaskStatus.downloaded) return false;
    final path = record.filePath.trim();
    if (path.isEmpty) return false;
    return File(path).existsSync();
  }

  String _canonicalGroupId(DownloadTaskRecord record) {
    if (_isGenericRecoveredRecord(record)) {
      if (record.itemGuid.trim().isNotEmpty &&
          record.groupId.trim().isNotEmpty) {
        return record.groupId.trim();
      }
      final path = record.filePath.trim();
      if (path.isNotEmpty) {
        final groupTitle = _displayGroupTitleForRecord(record);
        return _inferRecoveredGroupId(path, groupTitle: groupTitle);
      }
    }
    final title = record.groupTitle.trim();
    if (title.isNotEmpty) return title;
    final groupId = record.groupId.trim();
    if (groupId.isNotEmpty) return groupId;
    return record.itemGuid.trim();
  }

  String _displayGroupTitleForRecord(DownloadTaskRecord record) {
    if (_isGenericRecoveredRecord(record)) {
      if (record.itemGuid.trim().isNotEmpty &&
          record.groupTitle.trim().isNotEmpty) {
        return record.groupTitle.trim();
      }
      final path = record.filePath.trim();
      if (path.isNotEmpty) {
        return _inferRecoveredGroupTitle(
          path,
          fallbackTitle: record.groupTitle.trim().isNotEmpty
              ? record.groupTitle.trim()
              : record.title.trim(),
        );
      }
    }
    final groupTitle = record.groupTitle.trim();
    if (groupTitle.isNotEmpty) return groupTitle;
    final title = record.title.trim();
    if (title.isNotEmpty) return title;
    return record.fileName.trim();
  }

  String _displayRecordTitleForRecord(DownloadTaskRecord record) {
    final title = record.title.trim();
    if (!_isGenericRecoveredRecord(record)) {
      if (title.isNotEmpty) return title;
      return record.fileName.trim();
    }

    final path = record.filePath.trim();
    final fileName = record.fileName.trim().isNotEmpty
        ? record.fileName.trim()
        : (path.isNotEmpty ? _lastPathSegment(path) : '');
    final fallbackTitle = title.isNotEmpty
        ? title
        : (fileName.isNotEmpty ? _fileNameBase(fileName).trim() : '');
    if (path.isEmpty) return fallbackTitle;
    final groupTitle = _displayGroupTitleForRecord(record);
    final rawTitle = title.isNotEmpty
        ? title
        : _inferRecoveredEpisodeTitle(path, fallbackTitle: fallbackTitle);
    final displayTitle = _normalizeRecoveredEpisodeTitle(
      rawTitle,
      groupTitle: groupTitle,
      fileName: fileName,
    );
    return displayTitle.trim().isNotEmpty ? displayTitle : fallbackTitle;
  }

  static const Set<String> _videoFileExtensions = <String>{
    'mp4',
    'm4v',
    'mkv',
    'webm',
    'avi',
    'mov',
    'wmv',
    'flv',
    'ts',
    'm2ts',
    'mts',
    '3gp',
    '3g2',
    'mpg',
    'mpeg',
    'ogv',
    'rm',
    'rmvb',
    'vob',
    'asf',
    'f4v',
  };

  static const DownloadTaskRecord _emptyRecord = DownloadTaskRecord(
    id: '__empty__',
    remoteTaskId: '',
    itemGuid: '',
    mediaGuid: '',
    groupId: '',
    groupTitle: '',
    title: '',
    durationText: '',
    posterUrls: <String>[],
    groupPosterUrls: <String>[],
    resolution: '',
    fileName: '',
    filePath: '',
    totalBytes: 0,
    downloadedBytes: 0,
    status: DownloadTaskStatus.failed,
    errorMessage: '',
    createdAtMs: 0,
    updatedAtMs: 0,
  );
}

class _RecoveryMetadataCandidate {
  final File file;
  final bool pathSpecific;

  const _RecoveryMetadataCandidate({
    required this.file,
    required this.pathSpecific,
  });
}

class _RecoveredVideoContext {
  final File file;
  final int actualBytes;
  final DownloadTaskRecord? metadata;
  final String itemGuid;
  final String mediaGuid;
  final String fileName;
  final String title;
  final String groupId;
  final String groupTitle;
  final String durationText;
  final String resolution;
  final List<String> posterUrls;
  final List<String> groupPosterUrls;

  const _RecoveredVideoContext({
    required this.file,
    required this.actualBytes,
    required this.metadata,
    required this.itemGuid,
    required this.mediaGuid,
    required this.fileName,
    required this.title,
    required this.groupId,
    required this.groupTitle,
    required this.durationText,
    required this.resolution,
    required this.posterUrls,
    required this.groupPosterUrls,
  });
}

class _RecoveredBackendLookup {
  final NasProvider provider;
  final FeiniuApi api;
  final Map<String, Future<PlayInfoData?>> playInfoByItemGuid =
      <String, Future<PlayInfoData?>>{};
  final Map<String, Future<_StoredGroupMeta?>> groupMetaByItemGuid =
      <String, Future<_StoredGroupMeta?>>{};
  final Map<String, Future<List<MediaLibraryItem>>> searchByQuery =
      <String, Future<List<MediaLibraryItem>>>{};
  final Map<String, Future<List<MediaLibraryItem>>> seasonsByItemGuid =
      <String, Future<List<MediaLibraryItem>>>{};
  final Map<String, Future<List<MediaLibraryItem>>> episodesBySeasonGuid =
      <String, Future<List<MediaLibraryItem>>>{};

  _RecoveredBackendLookup(this.provider) : api = FeiniuApi(provider);
}

class _RecoveredBackendMetadata {
  final String itemGuid;
  final String mediaGuid;
  final String groupId;
  final String groupTitle;
  final String title;
  final String durationText;
  final String resolution;
  final List<String> posterUrls;
  final List<String> groupPosterUrls;

  const _RecoveredBackendMetadata({
    required this.itemGuid,
    required this.mediaGuid,
    required this.groupId,
    required this.groupTitle,
    required this.title,
    required this.durationText,
    required this.resolution,
    required this.posterUrls,
    required this.groupPosterUrls,
  });
}

class _LocalVideoMetadata {
  final int durationMs;
  final int width;
  final int height;

  const _LocalVideoMetadata({
    required this.durationMs,
    required this.width,
    required this.height,
  });
}

class _DanmakuRecoveryTarget {
  final String mediaKey;
  final String seasonGuid;

  const _DanmakuRecoveryTarget({
    required this.mediaKey,
    required this.seasonGuid,
  });
}

class _ImportedCacheArtwork {
  final List<String> posterUrls;
  final List<String> groupPosterUrls;

  const _ImportedCacheArtwork({
    required this.posterUrls,
    required this.groupPosterUrls,
  });
}

class _DownloadProgressSample {
  final int receivedBytes;
  final int timestampMs;

  const _DownloadProgressSample({
    required this.receivedBytes,
    required this.timestampMs,
  });
}

class _StoredGroupMeta {
  final String id;
  final String title;
  final List<String> posterUrls;

  const _StoredGroupMeta({
    required this.id,
    required this.title,
    required this.posterUrls,
  });
}
