import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../danmaku/cache/dandanplay_comment_cache_store.dart';
import '../danmaku/settings/danmaku_saved_source_store.dart';
import '../player/stores/bookmark_store.dart';
import '../providers/app_theme_provider.dart';
import '../providers/parallel_window_settings_provider.dart';
import '../services/app_log_service.dart';
import '../services/login_history_store.dart';
import '../models/download_task_record.dart';
import 'play_stats/play_stats_database.dart';
import 'download_task_service.dart';
import '../theme/app_theme.dart';

enum StorageItemKind {
  playbackCache,
  downloads,
  screenshots,
  logs,
  appData,
  danmakuAiCache,
  otherCache,
}

enum StorageClearAction {
  clearPlaybackCache,
  clearDownloads,
  clearScreenshots,
  clearLogs,
  clearDanmakuAiCache,
  clearOtherCache,
  clearBookmarks,
  clearSavedThemes,
  clearDanmakuSources,
  clearLoginHistory,
  resetSettings,
}

class StorageBreakdownItem {
  final StorageItemKind kind;
  final String title;
  final int bytes;
  final String countLabel;
  final bool isEstimated;
  final bool isRestricted;
  final bool clearDisabled;
  final StorageClearAction? clearAction;
  final String? note;

  const StorageBreakdownItem({
    required this.kind,
    required this.title,
    required this.bytes,
    this.countLabel = '',
    this.isEstimated = false,
    this.isRestricted = false,
    this.clearDisabled = false,
    this.clearAction,
    this.note,
  });
}

class StorageOverview {
  final int totalBytes;
  final DateTime updatedAt;
  final List<StorageBreakdownItem> items;
  final int bookmarksBytes;
  final int savedThemesBytes;
  final int danmakuSourcesBytes;
  final int danmakuCacheBytes;
  final int loginHistoryBytes;
  final int playStatsBytes;
  final int otherSettingsBytes;

  const StorageOverview({
    required this.totalBytes,
    required this.updatedAt,
    required this.items,
    required this.bookmarksBytes,
    required this.savedThemesBytes,
    required this.danmakuSourcesBytes,
    required this.danmakuCacheBytes,
    required this.loginHistoryBytes,
    required this.playStatsBytes,
    required this.otherSettingsBytes,
  });
}

class StorageActionResult {
  final bool success;
  final String code;
  final bool restricted;

  const StorageActionResult({
    required this.success,
    this.code = '',
    this.restricted = false,
  });
}

class PlaybackCacheEntry {
  final String resourceKey;
  final String itemGuid;
  final String mediaGuid;
  final String videoGuid;
  final String title;
  final String seriesTitle;
  final int seasonNumber;
  final int episodeNumber;
  final String resolution;
  final String subtitle;
  final int bytes;
  final int totalBytes;
  final bool complete;
  final String mimeType;
  final DateTime lastAccessAt;

  const PlaybackCacheEntry({
    required this.resourceKey,
    required this.itemGuid,
    required this.mediaGuid,
    required this.videoGuid,
    required this.title,
    required this.seriesTitle,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.resolution,
    required this.subtitle,
    required this.bytes,
    required this.totalBytes,
    required this.complete,
    required this.mimeType,
    required this.lastAccessAt,
  });

  factory PlaybackCacheEntry.fromMap(Map<String, dynamic> raw) {
    final lastAccessMs = raw['lastAccessAtMs'] is num
        ? (raw['lastAccessAtMs'] as num).toInt()
        : 0;
    return PlaybackCacheEntry(
      resourceKey: (raw['resourceKey'] ?? '').toString(),
      itemGuid: (raw['itemGuid'] ?? '').toString(),
      mediaGuid: (raw['mediaGuid'] ?? '').toString(),
      videoGuid: (raw['videoGuid'] ?? '').toString(),
      title: (raw['title'] ?? '').toString(),
      seriesTitle: (raw['seriesTitle'] ?? '').toString(),
      seasonNumber: raw['seasonNumber'] is num
          ? (raw['seasonNumber'] as num).toInt()
          : 0,
      episodeNumber: raw['episodeNumber'] is num
          ? (raw['episodeNumber'] as num).toInt()
          : 0,
      resolution: (raw['resolution'] ?? '').toString(),
      subtitle: (raw['subtitle'] ?? '').toString(),
      bytes: raw['bytes'] is num ? (raw['bytes'] as num).toInt() : 0,
      totalBytes: raw['totalBytes'] is num
          ? (raw['totalBytes'] as num).toInt()
          : 0,
      complete: raw['complete'] == true,
      mimeType: (raw['mimeType'] ?? '').toString(),
      lastAccessAt: DateTime.fromMillisecondsSinceEpoch(lastAccessMs),
    );
  }
}

class CachedMediaSourceIdentity {
  final String itemGuid;
  final String mediaGuid;
  final String videoGuid;
  final String resourceKey;

  const CachedMediaSourceIdentity({
    required this.itemGuid,
    required this.mediaGuid,
    required this.videoGuid,
    this.resourceKey = '',
  });

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'itemGuid': itemGuid.trim(),
      'mediaGuid': mediaGuid.trim(),
      'videoGuid': videoGuid.trim(),
      'resourceKey': resourceKey.trim(),
    };
  }
}

class CachedMediaDownloadability {
  final bool found;
  final bool downloadable;
  final String code;
  final String resourceKey;
  final int bytes;
  final int totalBytes;
  final String mimeType;
  final String suggestedFileName;
  final String title;

  const CachedMediaDownloadability({
    required this.found,
    required this.downloadable,
    required this.code,
    required this.resourceKey,
    required this.bytes,
    required this.totalBytes,
    required this.mimeType,
    required this.suggestedFileName,
    required this.title,
  });

  factory CachedMediaDownloadability.fromMap(Map<String, dynamic> raw) {
    return CachedMediaDownloadability(
      found: raw['found'] == true,
      downloadable: raw['downloadable'] == true,
      code: (raw['code'] ?? '').toString(),
      resourceKey: (raw['resourceKey'] ?? '').toString(),
      bytes: raw['bytes'] is num ? (raw['bytes'] as num).toInt() : 0,
      totalBytes: raw['totalBytes'] is num
          ? (raw['totalBytes'] as num).toInt()
          : 0,
      mimeType: (raw['mimeType'] ?? '').toString(),
      suggestedFileName: (raw['suggestedFileName'] ?? '').toString(),
      title: (raw['title'] ?? '').toString(),
    );
  }
}

class CachedMediaPromoteResult {
  final bool success;
  final String code;
  final String path;
  final String fileName;

  const CachedMediaPromoteResult({
    required this.success,
    required this.code,
    required this.path,
    required this.fileName,
  });

  factory CachedMediaPromoteResult.fromMap(Map<String, dynamic> raw) {
    return CachedMediaPromoteResult(
      success: raw['success'] == true,
      code: (raw['code'] ?? '').toString(),
      path: (raw['path'] ?? '').toString(),
      fileName: (raw['fileName'] ?? '').toString(),
    );
  }
}

class StorageManagementService {
  StorageManagementService._();

  static final StorageManagementService instance = StorageManagementService._();

  static const MethodChannel _channel = MethodChannel('fly_player/storage');

  static const String _logPrefsKey = 'app_error_logs_v1';
  static const String _bookmarkPrefsKey = 'player_bookmarks_v1';
  static const String _savedThemesKey = 'app_theme_saved_themes_v1';
  static const String _activeSavedThemeIdKey =
      'app_theme_active_saved_theme_id';
  static const String _themeSourceTypeKey = 'app_theme_source_type';
  static const String _danmakuSourcesKey = 'player_danmaku_saved_sources_v1';
  static const String _danmakuSettingsKey = 'player_danmaku_settings_v1';
  static const String _loginHistoryKey = 'login_history_v1';
  static const String _settingsSearchUsageKey = 'settings_search_usage_v1';
  static const String _mpvPrefPrefix = 'player_mpv_setting_';
  static const String _mpvVideoAdjustPrefPrefix = 'player_mpv_video_adjust_';
  static const String _savedPicturePresetsKey =
      'player_mpv_saved_picture_presets_v1';
  static const String _savedAudioPresetsKey =
      'player_mpv_saved_audio_presets_v1';
  static const String _mpvAudioEqPresetsKey = 'player_mpv_audio_eq_presets';
  static const String _downloadTaskRecordsKey = 'download_task_records_v1';
  static const String _playbackClientIdKey = 'playback_client_id';
  static const String _searchHistoryKeyPrefix = 'search_history_v1::';
  static const Set<String> _nasConfigKeys = <String>{
    'base_url',
    'resolved_base_url',
    'user_name',
    'password',
    'token',
    'remember_password',
  };

  static const Set<String> _themeResetKeys = <String>{
    'app_theme_preset',
    'app_theme_background_tone',
    'app_theme_accent_tone',
    'app_theme_selection_tone',
    'app_theme_link_tone',
    'app_theme_custom_background',
    'app_theme_custom_accent',
    'app_theme_custom_selection',
    'app_theme_custom_link',
    'app_theme_dynamic_mode',
    'app_theme_dynamic_intensity',
    'app_theme_source_type',
    'app_theme_runtime_dynamic_page_key',
    'app_theme_runtime_dynamic_background_seed',
    'app_theme_runtime_dynamic_accent_seed',
    'app_theme_runtime_dynamic_selection_seed',
    'app_theme_runtime_dynamic_link_seed',
    'app_theme_runtime_dynamic_prefer_light_surface',
    'app_theme_runtime_dynamic_session_id',
    'app_theme_revision',
    _activeSavedThemeIdKey,
  };

  static const Set<String> _settingsResetKeys = <String>{
    'player_auto_play_enabled',
    'player_auto_rotate_enabled',
    'player_extreme_playback_enabled',
    'player_performance_overlay_enabled',
    'player_fps_overlay_enabled',
    'player_performance_overlay_offset_x',
    'player_performance_overlay_offset_y',
    'player_decoder_mode',
    'player_display_aspect_ratio',
    'player_intro_outro_enabled',
    'player_intro_outro_source_mode',
    'player_intro_outro_chapter_mode',
    'player_intro_outro_intro_max_seconds',
    'player_intro_outro_outro_max_seconds',
    'screenshot_include_subtitles',
    'screenshot_save_path_mode',
    _danmakuSettingsKey,
    _settingsSearchUsageKey,
  };

  Future<StorageOverview> loadOverview() async {
    final nativeRaw =
        await _channel.invokeMapMethod<Object?, Object?>(
          'getStorageOverview',
        ) ??
        <Object?, Object?>{};
    final native = _normalizeMap(nativeRaw);
    final prefs = await SharedPreferences.getInstance();
    final downloadService = DownloadTaskService.instance;
    await downloadService.initialize();

    final bookmarksValue = prefs.get(_bookmarkPrefsKey);
    final savedThemesValue = prefs.get(_savedThemesKey);
    final danmakuSourcesValue = prefs.get(_danmakuSourcesKey);
    final loginHistoryValue = prefs.get(_loginHistoryKey);
    final logsValue = prefs.get(_logPrefsKey);

    final bookmarksBytes = _estimatePrefEntryBytes(
      _bookmarkPrefsKey,
      bookmarksValue,
    );
    final savedThemesBytes =
        _estimatePrefEntryBytes(_savedThemesKey, savedThemesValue) +
        _estimatePrefEntryBytes(
          _activeSavedThemeIdKey,
          prefs.get(_activeSavedThemeIdKey),
        );
    final danmakuSourcesBytes = _estimatePrefEntryBytes(
      _danmakuSourcesKey,
      danmakuSourcesValue,
    );
    final danmakuCacheBytes = await _estimateDanmakuCacheBytes();
    final loginHistoryBytes = _estimatePrefEntryBytes(
      _loginHistoryKey,
      loginHistoryValue,
    );
    final playStatsBytes = await _estimatePlayStatsBytes();
    final logsBytes = _estimatePrefEntryBytes(_logPrefsKey, logsValue);
    final nativeSettingsBytes = _asInt(native['nativeSettingsBytes']);
    final otherSettingsBytes =
        _estimateResettableSettingsBytes(prefs) + nativeSettingsBytes;
    final extraAppDataBytes = _estimateAdditionalAppDataBytes(prefs);
    final appDataBytes =
        bookmarksBytes +
        savedThemesBytes +
        danmakuSourcesBytes +
        danmakuCacheBytes +
        loginHistoryBytes +
        playStatsBytes +
        otherSettingsBytes +
        extraAppDataBytes;

    final playback = _normalizeMap(native['playbackCache']);
    final downloadBytes = downloadService.downloadedBytes;
    final downloadCount = downloadService.downloadedRecordCount;
    final screenshots = _normalizeMap(native['screenshots']);
    final danmakuAiCache = _normalizeMap(native['danmakuAiCache']);
    final otherCache = _normalizeMap(native['otherCache']);

    final items = <StorageBreakdownItem>[
      StorageBreakdownItem(
        kind: StorageItemKind.downloads,
        title: '本地下载',
        bytes: downloadBytes,
        countLabel: _fileCountLabel(downloadCount),
        clearAction: StorageClearAction.clearDownloads,
        note: '已下载完成的视频文件',
      ),
      StorageBreakdownItem(
        kind: StorageItemKind.playbackCache,
        title: '播放缓存',
        bytes: _asInt(playback['bytes']),
        countLabel: _playbackCacheCountLabel(
          fileCount: _asInt(playback['fileCount']),
          completeCount: _asInt(playback['completeCount']),
        ),
        clearAction: StorageClearAction.clearPlaybackCache,
        clearDisabled: playback['active'] == true,
        note: playback['active'] == true ? '播放中不可清理' : null,
      ),
      StorageBreakdownItem(
        kind: StorageItemKind.screenshots,
        title: '截图文件',
        bytes: _asInt(screenshots['bytes']),
        countLabel: _fileCountLabel(_asInt(screenshots['fileCount'])),
        clearAction: StorageClearAction.clearScreenshots,
        isRestricted: screenshots['restricted'] == true,
        note: screenshots['restricted'] == true ? '未授权时仅统计应用目录' : null,
      ),
      StorageBreakdownItem(
        kind: StorageItemKind.logs,
        title: '日志',
        bytes: logsBytes,
        countLabel: _jsonListCountLabel(logsValue, unit: '条'),
        clearAction: StorageClearAction.clearLogs,
        isEstimated: true,
        note: '应用内日志，不含导出文件',
      ),
      StorageBreakdownItem(
        kind: StorageItemKind.danmakuAiCache,
        title: '弹幕蒙版缓存',
        bytes: _asInt(danmakuAiCache['bytes']),
        countLabel: _fileCountLabel(_asInt(danmakuAiCache['fileCount'])),
        clearAction: StorageClearAction.clearDanmakuAiCache,
        note: '每集的人像分割缩略图与蒙版 warm-start 缓存',
      ),
      StorageBreakdownItem(
        kind: StorageItemKind.appData,
        title: '应用数据',
        bytes: appDataBytes,
        countLabel:
            '${_countStoredEntries(savedThemesValue) + _countStoredEntries(loginHistoryValue) + _countBookmarkEntries(bookmarksValue) + _countDanmakuSourceEntries(danmakuSourcesValue)} 项',
        isEstimated: true,
        note: '含书签、主题、弹幕来源和设置估算值 / 播放统计(SQLite) ${formatBytes(playStatsBytes)}',
      ),
      StorageBreakdownItem(
        kind: StorageItemKind.otherCache,
        title: '其他缓存',
        bytes: _asInt(otherCache['bytes']),
        countLabel: _fileCountLabel(_asInt(otherCache['fileCount'])),
        clearAction: StorageClearAction.clearOtherCache,
      ),
    ];

    final totalBytes = items.fold<int>(0, (sum, item) => sum + item.bytes);
    return StorageOverview(
      totalBytes: totalBytes,
      updatedAt: DateTime.now(),
      items: items,
      bookmarksBytes: bookmarksBytes,
      savedThemesBytes: savedThemesBytes,
      danmakuSourcesBytes: danmakuSourcesBytes,
      danmakuCacheBytes: danmakuCacheBytes,
      loginHistoryBytes: loginHistoryBytes,
      playStatsBytes: playStatsBytes,
      otherSettingsBytes: otherSettingsBytes,
    );
  }

  Future<StorageActionResult> clearSystemAction(
    StorageClearAction action,
  ) async {
    if (action == StorageClearAction.clearDownloads) {
      final removed = await DownloadTaskService.instance
          .clearDownloadedRecords();
      return StorageActionResult(
        success: true,
        code: removed > 0 ? 'cleared' : 'empty',
      );
    }
    final actionName = switch (action) {
      StorageClearAction.clearPlaybackCache => 'clearPlaybackCache',
      StorageClearAction.clearDanmakuAiCache => 'clearDanmakuAiCache',
      StorageClearAction.clearOtherCache => 'clearOtherCache',
      StorageClearAction.clearScreenshots => 'clearScreenshots',
      _ => '',
    };
    if (actionName.isEmpty) {
      return const StorageActionResult(success: false, code: 'invalid_action');
    }
    if (action == StorageClearAction.clearScreenshots) {
      final hasAccess =
          await _channel.invokeMethod<bool>('hasFileAccess') ?? false;
      if (!hasAccess) {
        await _channel.invokeMethod<bool>('requestFileAccess');
      }
    }
    final raw =
        await _channel.invokeMapMethod<Object?, Object?>(
          'clearStorageAction',
          <String, Object?>{'action': actionName},
        ) ??
        <Object?, Object?>{};
    final result = _normalizeMap(raw);
    return StorageActionResult(
      success: result['success'] == true,
      code: (result['code'] ?? '').toString(),
      restricted: result['restricted'] == true,
    );
  }

  Future<void> clearBookmarks() => const BookmarkStore().clearAll();

  Future<void> clearSavedThemes(AppThemeProvider themeProvider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_savedThemesKey);
    await prefs.remove(_activeSavedThemeIdKey);
    if (prefs.getString(_themeSourceTypeKey) ==
        AppThemeSourceType.savedCustomTheme.storageValue) {
      await prefs.setString(
        _themeSourceTypeKey,
        AppThemeSourceType.currentCustom.storageValue,
      );
    }
    await themeProvider.load();
  }

  Future<void> clearDanmakuSources() async {
    await const DanmakuSavedSourceStore().clearAll();
    await const DanDanPlayCommentCacheStore().clearAll();
  }

  Future<void> clearLoginHistory() => LoginHistoryStore.clear();

  Future<void> resetSettings({
    required AppThemeProvider themeProvider,
    required ParallelWindowSettingsProvider parallelWindowSettingsProvider,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (_settingsResetKeys.contains(key) ||
          _themeResetKeys.contains(key) ||
          key.startsWith(_mpvPrefPrefix) ||
          key.startsWith(_mpvVideoAdjustPrefPrefix) ||
          key == _savedPicturePresetsKey ||
          key == _savedAudioPresetsKey ||
          key == _mpvAudioEqPresetsKey) {
        await prefs.remove(key);
      }
    }
    await _channel.invokeMethod<Object?>(
      'clearStorageAction',
      const <String, Object?>{'action': 'clearParallelWindowSettings'},
    );
    await _channel.invokeMethod<Object?>(
      'clearStorageAction',
      const <String, Object?>{'action': 'clearScopedTreeAccess'},
    );
    await themeProvider.load();
    await parallelWindowSettingsProvider.load();
  }

  Future<void> clearLogs() => AppLogService.instance.clear();

  Future<List<PlaybackCacheEntry>> loadPlaybackCacheEntries() async {
    final raw =
        await _channel.invokeListMethod<Object?>('listPlaybackCacheEntries') ??
        const <Object?>[];
    return raw
        .map((item) => PlaybackCacheEntry.fromMap(_normalizeMap(item)))
        .toList(growable: false);
  }

  Future<StorageActionResult> clearPlaybackCacheEntries(
    List<String> resourceKeys,
  ) async {
    final normalized = resourceKeys
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty)
        .toList(growable: false);
    if (normalized.isEmpty) {
      return const StorageActionResult(success: false, code: 'empty_selection');
    }
    final raw =
        await _channel.invokeMapMethod<Object?, Object?>(
          'clearPlaybackCacheEntries',
          <String, Object?>{'resourceKeys': normalized},
        ) ??
        <Object?, Object?>{};
    final result = _normalizeMap(raw);
    return StorageActionResult(
      success: result['success'] == true,
      code: (result['code'] ?? '').toString(),
      restricted: result['restricted'] == true,
    );
  }

  Future<List<DownloadTaskRecord>> loadDownloadEntries() async {
    final service = DownloadTaskService.instance;
    await service.initialize();
    return service.downloadedRecords;
  }

  Future<StorageActionResult> clearDownloadEntries(
    List<String> recordIds,
  ) async {
    final normalized = recordIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (normalized.isEmpty) {
      return const StorageActionResult(success: false, code: 'empty_selection');
    }
    final removed = await DownloadTaskService.instance.clearDownloadedRecords(
      recordIds: normalized,
    );
    return StorageActionResult(
      success: removed > 0,
      code: removed > 0 ? 'cleared' : 'empty_selection',
    );
  }

  Future<CachedMediaDownloadability> canPromoteCachedMedia(
    CachedMediaSourceIdentity identity,
  ) async {
    final raw =
        await _channel.invokeMapMethod<Object?, Object?>(
          'queryCachedDownloadable',
          identity.toMap(),
        ) ??
        <Object?, Object?>{};
    return CachedMediaDownloadability.fromMap(_normalizeMap(raw));
  }

  Future<CachedMediaPromoteResult> promoteCachedMedia(
    CachedMediaSourceIdentity identity, {
    String targetMode = 'appExternalMovies',
  }) async {
    if (targetMode == 'publicDownloads') {
      final hasAccess =
          await _channel.invokeMethod<bool>('hasFileAccess') ?? false;
      if (!hasAccess) {
        await _channel.invokeMethod<bool>('requestFileAccess');
      }
    }
    final raw =
        await _channel.invokeMapMethod<Object?, Object?>(
          'promoteCachedMedia',
          <String, Object?>{...identity.toMap(), 'targetMode': targetMode},
        ) ??
        <Object?, Object?>{};
    return CachedMediaPromoteResult.fromMap(_normalizeMap(raw));
  }

  String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    final fractionDigits = value >= 100 ? 0 : (value >= 10 ? 1 : 2);
    return '${value.toStringAsFixed(fractionDigits)} ${units[unitIndex]}';
  }

  static Map<String, dynamic> _normalizeMap(Object? raw) {
    if (raw is Map<Object?, Object?>) {
      final normalized = <String, dynamic>{};
      raw.forEach((key, value) {
        normalized[key?.toString() ?? ''] = _normalizeValue(value);
      });
      return normalized;
    }
    return <String, dynamic>{};
  }

  static dynamic _normalizeValue(Object? value) {
    if (value is Map<Object?, Object?>) {
      return _normalizeMap(value);
    }
    if (value is List) {
      return value.map(_normalizeValue).toList(growable: false);
    }
    return value;
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  static int _estimateResettableSettingsBytes(SharedPreferences prefs) {
    var total = 0;
    for (final key in prefs.getKeys()) {
      if (key == _bookmarkPrefsKey ||
          key == _savedThemesKey ||
          key == _activeSavedThemeIdKey ||
          key == _danmakuSourcesKey ||
          key == _loginHistoryKey ||
          key == _logPrefsKey) {
        continue;
      }
      if (_settingsResetKeys.contains(key) ||
          _themeResetKeys.contains(key) ||
          key.startsWith(_mpvPrefPrefix) ||
          key.startsWith(_mpvVideoAdjustPrefPrefix) ||
          key == _savedPicturePresetsKey ||
          key == _savedAudioPresetsKey ||
          key == _mpvAudioEqPresetsKey) {
        total += _estimatePrefEntryBytes(key, prefs.get(key));
      }
    }
    return total;
  }

  static int _estimateAdditionalAppDataBytes(SharedPreferences prefs) {
    var total = 0;
    for (final key in prefs.getKeys()) {
      if (_isAdditionalAppDataKey(key)) {
        total += _estimatePrefEntryBytes(key, prefs.get(key));
      }
    }
    return total;
  }

  static bool _isAdditionalAppDataKey(String key) {
    return _nasConfigKeys.contains(key) ||
        key.startsWith(_searchHistoryKeyPrefix) ||
        key == _downloadTaskRecordsKey ||
        key == _playbackClientIdKey;
  }

  static int _estimatePrefEntryBytes(String key, Object? value) {
    return utf8.encode(key).length + _estimateValueBytes(value);
  }

  static int _estimateValueBytes(Object? value) {
    if (value == null) return 0;
    if (value is String) return utf8.encode(value).length;
    if (value is List<String>) {
      return value.fold<int>(0, (sum, item) => sum + utf8.encode(item).length);
    }
    return utf8.encode(jsonEncode(value)).length;
  }

  static String _fileCountLabel(int count) {
    if (count <= 0) return '0 个文件';
    return '$count 个文件';
  }

  static String _playbackCacheCountLabel({
    required int fileCount,
    required int completeCount,
  }) {
    final normalizedFileCount = fileCount < 0 ? 0 : fileCount;
    final normalizedCompleteCount = completeCount < 0 ? 0 : completeCount;
    return '$normalizedFileCount 个缓存 · $normalizedCompleteCount 个完整';
  }

  static String _jsonListCountLabel(Object? value, {required String unit}) {
    final count = _countStoredEntries(value);
    return '$count $unit';
  }

  static int _countStoredEntries(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) return decoded.length;
      } catch (_) {
        return 1;
      }
      return 1;
    }
    if (value is List) return value.length;
    return value == null ? 0 : 1;
  }

  static int _countBookmarkEntries(Object? value) {
    if (value is! String || value.trim().isEmpty) return 0;
    try {
      final decoded = jsonDecode(value);
      return decoded is List ? decoded.length : 0;
    } catch (_) {
      return 0;
    }
  }

  static int _countDanmakuSourceEntries(Object? value) {
    if (value is! String || value.trim().isEmpty) return 0;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map) return 0;
      final sources = decoded['sources'];
      return sources is List ? sources.length : 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<int> _estimatePlayStatsBytes() async {
    try {
      final databasesPath = await getDatabasesPath();
      final basePath = p.join(
        databasesPath,
        SqflitePlayStatsDatabase.databaseName,
      );
      var total = 0;
      for (final path in <String>[basePath, '$basePath-wal', '$basePath-shm']) {
        final file = File(path);
        if (await file.exists()) {
          total += await file.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  static Future<int> _estimateDanmakuCacheBytes() async {
    try {
      final databasesPath = await getDatabasesPath();
      final basePath = p.join(
        databasesPath,
        DanDanPlayCommentCacheStore.databaseName,
      );
      var total = 0;
      for (final path in <String>[basePath, '$basePath-wal', '$basePath-shm']) {
        final file = File(path);
        if (await file.exists()) {
          total += await file.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }
}
