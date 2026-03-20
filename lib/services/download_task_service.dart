import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/feiniu_api.dart';
import '../models/download_task_record.dart';
import '../models/stream_list_option.dart';
import '../models/stream_track_data.dart';
import '../providers/nas_provider.dart';
import '../utils/app_exception.dart';
import '../utils/api_url_helper.dart';
import 'app_log_service.dart';
import 'storage_access_service.dart';
import 'storage_management_service.dart';

enum DownloadStartState { started, downloading, downloaded, importedFromCache }

class DownloadStartResult {
  final DownloadStartState state;
  final DownloadTaskRecord record;

  const DownloadStartResult({required this.state, required this.record});
}

class DownloadTaskService extends ChangeNotifier {
  DownloadTaskService._();

  static final DownloadTaskService instance = DownloadTaskService._();

  static const String _prefsKey = 'download_task_records_v1';
  static const String _downloadFolderName = 'FlyPlayer';
  static const String _interruptedMessage = '下载已中断';

  static const Duration _taskProgressPollInterval = Duration(seconds: 2);

  final List<DownloadTaskRecord> _records = <DownloadTaskRecord>[];
  final Map<String, CancelToken> _cancelTokens = <String, CancelToken>{};
  final Map<String, int> _downloadSpeedBytesPerSecond = <String, int>{};
  final Map<String, _DownloadProgressSample> _downloadProgressSamples =
      <String, _DownloadProgressSample>{};
  final Map<String, DownloadTaskProgressInfo> _downloadTaskProgress =
      <String, DownloadTaskProgressInfo>{};
  final Map<String, Timer> _downloadTaskProgressPollers = <String, Timer>{};

  bool _initialized = false;
  Future<void>? _pendingInitialization;
  Timer? _persistTimer;
  Future<void>? _pendingGroupMetadataRefresh;

  List<DownloadTaskRecord> get records =>
      List<DownloadTaskRecord>.unmodifiable(_records);

  int downloadSpeedBytesPerSecondFor(String recordId) =>
      _downloadSpeedBytesPerSecond[recordId] ?? 0;

  DownloadTaskProgressInfo? downloadTaskProgressFor(String recordId) =>
      _downloadTaskProgress[recordId];

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

  int get downloadedBytes {
    var total = 0;
    for (final record in _records) {
      if (!_isDownloadedRecordAvailable(record)) continue;
      try {
        total += File(record.filePath).lengthSync();
      } catch (_) {
        total += record.totalBytes;
      }
    }
    return total;
  }

  List<DownloadTaskRecord> recordsByStatus(DownloadTaskStatus status) {
    return _records
        .where((record) => _matchesStatus(record, status))
        .toList(growable: false);
  }

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
                title: entry.value.first.groupTitle,
                records: List<DownloadTaskRecord>.from(entry.value)
                  ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs)),
              ),
            )
            .toList(growable: false)
          ..sort(
            (a, b) =>
                b.leadRecord.updatedAtMs.compareTo(a.leadRecord.updatedAtMs),
          );
    return groups;
  }

  List<DownloadTaskRecord> recordsForGroup(
    String groupId, {
    DownloadTaskStatus? status,
  }) {
    return _records
        .where(
          (record) =>
              _canonicalGroupId(record) == groupId &&
              (status == null || _matchesStatus(record, status)),
        )
        .toList(growable: false)
      ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
  }

  DownloadTaskGroup? groupById(String groupId, {DownloadTaskStatus? status}) {
    final records = recordsForGroup(groupId, status: status);
    if (records.isEmpty) return null;
    return DownloadTaskGroup(
      id: groupId,
      title: records.first.groupTitle,
      records: records,
    );
  }

  DownloadActionState actionStateForItem(String itemGuid) {
    final normalized = itemGuid.trim();
    if (normalized.isEmpty) return DownloadActionState.idle;
    final downloaded = _records.firstWhere(
      (record) =>
          record.itemGuid == normalized && _isDownloadedRecordAvailable(record),
      orElse: () => _emptyRecord,
    );
    if (downloaded != _emptyRecord) {
      return const DownloadActionState(downloaded: true);
    }
    final downloading = _records.firstWhere(
      (record) =>
          record.itemGuid == normalized &&
          record.status == DownloadTaskStatus.downloading,
      orElse: () => _emptyRecord,
    );
    if (downloading != _emptyRecord) {
      return const DownloadActionState(downloading: true);
    }
    final failed = _records.firstWhere(
      (record) =>
          record.itemGuid == normalized &&
          record.status == DownloadTaskStatus.failed,
      orElse: () => _emptyRecord,
    );
    if (failed != _emptyRecord) {
      return const DownloadActionState(failed: true);
    }
    return DownloadActionState.idle;
  }

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

  DownloadTaskRecord? downloadedRecordForItem(
    String itemGuid, {
    String resolution = '',
  }) {
    final normalizedItemGuid = itemGuid.trim();
    final normalizedResolution = resolution.trim().toLowerCase();
    if (normalizedItemGuid.isEmpty) return null;
    for (final record in _records) {
      if (record.itemGuid != normalizedItemGuid) continue;
      if (!_isDownloadedRecordAvailable(record)) continue;
      if (normalizedResolution.isNotEmpty &&
          record.resolution.trim().toLowerCase() != normalizedResolution) {
        continue;
      }
      return record;
    }
    if (normalizedResolution.isEmpty) return null;
    for (final record in _records) {
      if (record.itemGuid != normalizedItemGuid) continue;
      if (_isDownloadedRecordAvailable(record)) return record;
    }
    return null;
  }

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

  bool hasDownloadedResolution(String itemGuid, String resolution) {
    final normalizedItemGuid = itemGuid.trim();
    final normalizedResolution = _normalizeResolutionKey(resolution);
    if (normalizedItemGuid.isEmpty || normalizedResolution.isEmpty) {
      return false;
    }
    for (final record in _records) {
      if (record.itemGuid != normalizedItemGuid) continue;
      if (!_isDownloadedRecordAvailable(record)) continue;
      if (_normalizeResolutionKey(record.resolution) == normalizedResolution) {
        return true;
      }
    }
    return false;
  }

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
        .map((record) => _groupDirectoryForVideo(record.filePath).path)
        .toSet();
    final affectedGroupDirectories = <String>{};

    for (final record in targets) {
      _cancelTokens.remove(record.id)?.cancel();
      _clearDownloadSpeed(record.id);
      _stopDownloadTaskProgressPolling(record.id);
      final path = record.filePath.trim();
      if (path.isEmpty) continue;
      affectedGroupDirectories.add(_groupDirectoryForVideo(path).path);
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

  Future<DownloadStartResult> startDownload({
    required NasProvider provider,
    required String itemGuid,
    required String resolution,
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
    if (normalizedItemGuid.isEmpty || normalizedResolution.isEmpty) {
      throw AppException.api(
        action: 'download start',
        message: 'Missing download parameters',
      );
    }

    final existingDownloaded = _findLatestRecord(
      itemGuid: normalizedItemGuid,
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
      resolution: normalizedResolution,
      status: DownloadTaskStatus.downloading,
    );
    if (existingDownloading != null) {
      return DownloadStartResult(
        state: DownloadStartState.downloading,
        record: existingDownloading,
      );
    }

    final api = FeiniuApi(provider);
    final streamData = await api.getStreamTrackData(normalizedItemGuid);
    final option = _pickStreamOption(
      streamData.options,
      resolution: normalizedResolution,
    );
    if (option == null) {
      throw AppException.api(
        action: 'download start',
        message: 'No stream option matched download resolution',
      );
    }

    final fileInfo = streamData.fileForMedia(option.mediaGuid);
    if (fileInfo == null) {
      throw AppException.api(
        action: 'download start',
        message: 'Missing stream file info',
      );
    }
    final resolvedSubtitleTrack = _resolveDownloadSubtitleTrack(
      streamData.subtitlesForMedia(option.mediaGuid),
      preferredSubtitleTrack: preferredSubtitleTrack,
      preferredSubtitleGuid: preferredSubtitleGuid,
    );
    final importedFromCache = await importCachedMedia(
      provider: provider,
      identity: CachedMediaSourceIdentity(
        itemGuid: normalizedItemGuid,
        mediaGuid: option.mediaGuid,
        videoGuid: option.videoGuid,
      ),
      resolution: normalizedResolution,
      title: title,
      groupId: groupId,
      groupTitle: groupTitle,
      durationText: durationText,
      posterUrls: posterUrls,
      groupPosterUrls: groupPosterUrls,
      fileInfo: fileInfo,
      subtitleTrack: resolvedSubtitleTrack,
    );
    if (importedFromCache != null) {
      return importedFromCache;
    }

    final remoteTaskId = await api.createDownloadTask(
      mediaGuid: option.mediaGuid,
      itemGuid: normalizedItemGuid,
      resolution: option.resolutionType.trim().isEmpty
          ? normalizedResolution
          : option.resolutionType.trim(),
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
    final cachedGroupPosterUrls = await _cacheArtworkUrls(
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
      mediaGuid: option.mediaGuid,
      groupId: groupId.trim().isEmpty ? normalizedItemGuid : groupId.trim(),
      groupTitle: groupTitle.trim().isEmpty ? title.trim() : groupTitle.trim(),
      title: title.trim(),
      durationText: durationText.trim(),
      posterUrls: cachedPosterUrls,
      groupPosterUrls: cachedGroupPosterUrls,
      resolution: normalizedResolution,
      fileName: safeFileName,
      filePath: filePath,
      totalBytes: fileInfo.size > 0 ? fileInfo.size : 0,
      downloadedBytes: 0,
      status: DownloadTaskStatus.downloading,
      errorMessage: '',
      createdAtMs: now,
      updatedAtMs: now,
    );
    _upsertRecord(record, persistImmediately: true);
    _clearDownloadSpeed(record.id);
    if (_shouldPollTaskProgressForResolution(record.resolution)) {
      _startDownloadTaskProgressPolling(api: api, record: record);
    }

    unawaited(
      _performDownload(
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
    SubtitleTrackOption? subtitleTrack,
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

    final storageService = StorageManagementService.instance;
    CachedMediaDownloadability downloadability;
    try {
      downloadability = await storageService.canPromoteCachedMedia(identity);
    } catch (_) {
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
    } catch (_) {
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
    try {
      final importedFileName = _resolveImportedFileName(
        promotedFileName: promoteResult.fileName,
        suggestedFileName: downloadability.suggestedFileName,
        fileInfo: fileInfo,
        title: title,
        resolution: normalizedResolution,
      );
      finalFilePath = await _buildDownloadFilePath(
        groupTitle: groupTitle,
        fileName: importedFileName,
      );
      await _relocateImportedFile(promotedFile.path, finalFilePath);

      final cachedPosterUrls = provider == null
          ? posterUrls
          : await _cacheArtworkUrls(
              provider: provider,
              sourceUrls: posterUrls,
              videoFilePath: finalFilePath,
              suffix: 'cover',
            );
      final cachedGroupPosterUrls = provider == null
          ? groupPosterUrls
          : await _cacheArtworkUrls(
              provider: provider,
              sourceUrls: groupPosterUrls,
              videoFilePath: finalFilePath,
              suffix: 'group_cover',
            );

      final actualBytes = await File(finalFilePath).length();
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
        fileName: importedFileName,
        filePath: finalFilePath,
        totalBytes: math.max(
          actualBytes,
          math.max(downloadability.totalBytes, fileInfo?.size ?? 0),
        ),
        downloadedBytes: actualBytes,
        status: DownloadTaskStatus.downloaded,
        errorMessage: '',
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      if (provider != null) {
        final api = FeiniuApi(provider);
        await _materializeSubtitleForRecord(
          api: api,
          record: record,
          subtitleTrack: subtitleTrack,
        );
      }
      final refreshedBytes = await File(finalFilePath).length();
      record = record.copyWith(
        totalBytes: math.max(
          refreshedBytes,
          math.max(downloadability.totalBytes, fileInfo?.size ?? 0),
        ),
        downloadedBytes: refreshedBytes,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      _upsertRecord(record, persistImmediately: true);
      return DownloadStartResult(
        state: DownloadStartState.importedFromCache,
        record: record,
      );
    } catch (_) {
      if (finalFilePath != null) {
        await _deleteIfExists(File(finalFilePath));
      }
      if (promotedFile.existsSync()) {
        await _deleteIfExists(promotedFile);
      }
      return null;
    } finally {
      if (promotedFile.existsSync()) {
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
    try {
      await file.parent.create(recursive: true);
      if (file.existsSync()) {
        await file.delete();
      }

      final dio = Dio();
      final headers = api.buildPlaybackHeadersForUrl(
        downloadUrl,
        includeInitialRangeHeader: false,
        extraHeaders: const <String, String>{'Range': 'bytes=0-'},
      );

      var lastPersistedBytes = 0;
      await dio.download(
        downloadUrl,
        file.path,
        cancelToken: cancelToken,
        options: Options(
          headers: headers,
          responseType: ResponseType.bytes,
          followRedirects: false,
          receiveTimeout: const Duration(hours: 2),
          sendTimeout: const Duration(seconds: 30),
          validateStatus: (status) => status == 200 || status == 206,
        ),
        onReceiveProgress: (received, total) {
          final normalizedTotal = total > 0 ? total : record.totalBytes;
          if (received == record.downloadedBytes) return;
          final now = DateTime.now().millisecondsSinceEpoch;
          _updateDownloadSpeed(record.id, received, now);
          if (received > 0) {
            _stopDownloadTaskProgressPolling(record.id);
          }
          final shouldPersist =
              received == normalizedTotal ||
              received - lastPersistedBytes >= 512 * 1024;
          final updated = record.copyWith(
            downloadedBytes: math.max(received, 0),
            totalBytes: normalizedTotal > 0
                ? normalizedTotal
                : record.totalBytes,
            updatedAtMs: now,
          );
          _upsertRecord(updated, persistImmediately: shouldPersist);
          if (shouldPersist) {
            lastPersistedBytes = received;
          }
        },
      );

      final actualBytes = await file.length();
      await _materializeSubtitleForRecord(
        api: api,
        record: record,
        subtitleTrack: subtitleTrack,
      );
      _upsertRecord(
        record.copyWith(
          downloadedBytes: actualBytes,
          totalBytes: actualBytes > 0 ? actualBytes : record.totalBytes,
          status: DownloadTaskStatus.downloaded,
          errorMessage: '',
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
        persistImmediately: true,
      );
    } catch (error, stackTrace) {
      final canceled = error is DioException && CancelToken.isCancel(error);
      if (!canceled) {
        await AppLogService.instance.recordWarning(
          error: error,
          stackTrace: stackTrace,
          source: 'download',
          details: 'item=${record.itemGuid} task=${record.remoteTaskId}',
        );
      }
      if (file.existsSync()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      _upsertRecord(
        record.copyWith(
          status: DownloadTaskStatus.failed,
          downloadedBytes: 0,
          errorMessage: canceled ? '下载已取消' : '$error',
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
        persistImmediately: true,
      );
    } finally {
      _cancelTokens.remove(record.id);
    }
  }

  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
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
          _records[index] = record.copyWith(
            status: DownloadTaskStatus.failed,
            errorMessage: _interruptedMessage,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          );
        }
      }
      await _normalizeLegacyGroupArtwork();
      _sortRecords();
      notifyListeners();
      await _persist();
    } catch (_) {
      _records.clear();
    }
  }

  void _upsertRecord(
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
    if (persistImmediately) {
      unawaited(_persist());
      _persistTimer?.cancel();
      _persistTimer = null;
    } else {
      _schedulePersist();
    }
  }

  void _sortRecords() {
    _records.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
  }

  void _updateDownloadSpeed(String recordId, int received, int timestampMs) {
    final previous = _downloadProgressSamples[recordId];
    if (previous != null) {
      final deltaBytes = received - previous.receivedBytes;
      final deltaMs = timestampMs - previous.timestampMs;
      if (deltaBytes >= 0 && deltaMs > 0) {
        final instantBytesPerSecond = ((deltaBytes * 1000) / deltaMs).round();
        final currentSpeed = _downloadSpeedBytesPerSecond[recordId] ?? 0;
        _downloadSpeedBytesPerSecond[recordId] = currentSpeed <= 0
            ? instantBytesPerSecond
            : ((currentSpeed * 2) + instantBytesPerSecond) ~/ 3;
      }
    }
    _downloadProgressSamples[recordId] = _DownloadProgressSample(
      receivedBytes: received,
      timestampMs: timestampMs,
    );
  }

  void _clearDownloadSpeed(String recordId) {
    _downloadSpeedBytesPerSecond.remove(recordId);
    _downloadProgressSamples.remove(recordId);
  }

  bool _shouldPollTaskProgressForResolution(String resolution) {
    final normalized = resolution.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return normalized != '原画' && normalized != 'source';
  }

  void _startDownloadTaskProgressPolling({
    required FeiniuApi api,
    required DownloadTaskRecord record,
  }) {
    if (record.remoteTaskId.trim().isEmpty) return;
    _stopDownloadTaskProgressPolling(record.id, notify: false);

    Future<void> pollOnce() async {
      final activeRecord = _records.firstWhere(
        (entry) => entry.id == record.id,
        orElse: () => DownloadTaskService._emptyRecord,
      );
      if (activeRecord == _emptyRecord ||
          activeRecord.status != DownloadTaskStatus.downloading) {
        _stopDownloadTaskProgressPolling(record.id);
        return;
      }
      try {
        final progress = await api.getDownloadTaskProgress(
          activeRecord.remoteTaskId,
        );
        final previous = _downloadTaskProgress[record.id];
        if (progress == null || progress.status != 0) {
          _stopDownloadTaskProgressPolling(record.id, notify: previous != null);
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
        _downloadTaskProgress[record.id] = normalized;
        notifyListeners();
      } catch (_) {}
    }

    _downloadTaskProgressPollers[record.id] = Timer.periodic(
      _taskProgressPollInterval,
      (_) => unawaited(pollOnce()),
    );
    unawaited(pollOnce());
  }

  void _stopDownloadTaskProgressPolling(String recordId, {bool notify = true}) {
    _downloadTaskProgressPollers.remove(recordId)?.cancel();
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
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        _records.map((entry) => entry.toJson()).toList(growable: false),
      );
      await prefs.setString(_prefsKey, encoded);
    } catch (_) {}
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
  }) {
    final normalizedResolution = resolution.trim().toLowerCase();
    for (final option in options) {
      if (option.resolutionType.trim().toLowerCase() == normalizedResolution) {
        return option;
      }
    }
    return options.isNotEmpty ? options.first : null;
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
    StreamFileInfo fileInfo,
    String title,
    String resolution,
  ) {
    final source = fileInfo.fileName.trim();
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

    try {
      final targetPath = _artworkFilePath(videoFilePath, suffix, firstUrl);
      final targetFile = File(targetPath);
      if (overwrite && targetFile.existsSync()) {
        await targetFile.delete();
      }
      if (!targetFile.existsSync()) {
        await targetFile.parent.create(recursive: true);
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
        await targetFile.writeAsBytes(bytes, flush: true);
      }
      return <String>[Uri.file(targetFile.path).toString()];
    } catch (_) {
      return normalizedUrls;
    }
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
    final groupDirectory = _groupDirectoryForVideo(videoFilePath);
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
    if (seasonNumber > 0) return '第$seasonNumber季';
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
        return uri!.toFilePath();
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

    await _deleteIfExists(File('${episodeDirectory.path}/cover.webp'));
    await _deleteIfExists(File('${episodeDirectory.path}/cover.jpg'));
    await _deleteIfExists(File('${episodeDirectory.path}/cover.jpeg'));
    await _deleteIfExists(
      File('${episodeDirectory.path}/${baseName}_cover.webp'),
    );
    await _deleteIfExists(
      File('${episodeDirectory.path}/${baseName}_cover.jpg'),
    );
    await _deleteIfExists(
      File('${episodeDirectory.path}/${baseName}_cover.jpeg'),
    );
    await _deleteIfExists(
      File('${episodeDirectory.path}/${baseName}_group_cover.webp'),
    );
    await _deleteIfExists(
      File('${episodeDirectory.path}/${baseName}_group_cover.jpg'),
    );
    await _deleteIfExists(
      File('${episodeDirectory.path}/${baseName}_group_cover.jpeg'),
    );
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
    var candidate = '$parentPath/$safeDirectoryName';
    var index = 1;
    while (Directory(candidate).existsSync() || File(candidate).existsSync()) {
      candidate = '$parentPath/${safeDirectoryName}_$index';
      index += 1;
    }
    return candidate;
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

  Future<void> _materializeSubtitleForRecord({
    required FeiniuApi api,
    required DownloadTaskRecord record,
    required SubtitleTrackOption? subtitleTrack,
  }) async {
    if (subtitleTrack == null) return;
    try {
      final text = await api.downloadSubtitleText(subtitleTrack.guid);
      if (text.trim().isEmpty) return;
      final targetFile = File(
        _subtitleFilePath(record.filePath, subtitleTrack),
      );
      await targetFile.parent.create(recursive: true);
      await targetFile.writeAsString(text, flush: true);
    } catch (error, stackTrace) {
      await AppLogService.instance.recordWarning(
        error: error,
        stackTrace: stackTrace,
        source: 'download-subtitle',
        details:
            'item=${record.itemGuid} subtitle=${subtitleTrack.guid} media=${record.mediaGuid}',
      );
    }
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

  DownloadTaskRecord? _findLatestRecord({
    required String itemGuid,
    required String resolution,
    required DownloadTaskStatus status,
  }) {
    try {
      return _records.firstWhere(
        (record) =>
            record.itemGuid == itemGuid &&
            record.resolution.trim().toLowerCase() ==
                resolution.trim().toLowerCase() &&
            record.status == status,
      );
    } catch (_) {
      return null;
    }
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
    return '缓存';
  }

  bool _isDownloadedRecordAvailable(DownloadTaskRecord record) {
    if (record.status != DownloadTaskStatus.downloaded) return false;
    final path = record.filePath.trim();
    if (path.isEmpty) return false;
    return File(path).existsSync();
  }

  String _canonicalGroupId(DownloadTaskRecord record) {
    final title = record.groupTitle.trim();
    if (title.isNotEmpty) return title;
    final groupId = record.groupId.trim();
    if (groupId.isNotEmpty) return groupId;
    return record.itemGuid.trim();
  }

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
