import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../danmaku/cache/dandanplay_comment_cache_store.dart';
import '../danmaku/settings/danmaku_saved_source_store.dart';
import '../l10n/generated/app_localizations.dart';
import '../player/stores/bookmark_store.dart';
import '../providers/app_theme_provider.dart';
import '../providers/parallel_window_settings_provider.dart';
import '../services/app_log_service.dart';
import '../services/login_history_store.dart';
import '../models/download_task_record.dart';
import 'play_stats/play_stats_database.dart';
import 'download_task_service.dart';
import '../theme/app_theme.dart';
import '../theme/dynamic_theme_runtime_controller.dart';
import '../theme/dynamic_theme_seed_extractor.dart';

/// 定义存储概览中展示的存储分类。
enum StorageItemKind {
  playbackCache,
  downloads,
  screenshots,
  logs,
  appData,
  danmakuAiCache,
  otherCache,
}

/// 定义设置页允许执行的存储清理动作。
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

/// 表示存储概览中的单项统计结果。
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

  /// 根据分类统计信息构造概览条目。
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

/// 汇总设置页存储管理所需的统计快照。
class StorageOverview {
  final int totalBytes;
  final DateTime updatedAt;
  final List<StorageBreakdownItem> items;
  final int bookmarksBytes;
  final int savedThemesBytes;
  final int dynamicThemeCacheBytes;
  final int dynamicThemeCacheEntries;
  final int danmakuSourcesBytes;
  final int danmakuCacheBytes;
  final int loginHistoryBytes;
  final int playStatsBytes;
  final int otherSettingsBytes;

  /// 根据各分类统计结果构造概览对象。
  const StorageOverview({
    required this.totalBytes,
    required this.updatedAt,
    required this.items,
    required this.bookmarksBytes,
    required this.savedThemesBytes,
    required this.dynamicThemeCacheBytes,
    required this.dynamicThemeCacheEntries,
    required this.danmakuSourcesBytes,
    required this.danmakuCacheBytes,
    required this.loginHistoryBytes,
    required this.playStatsBytes,
    required this.otherSettingsBytes,
  });
}

/// 表示一次存储清理动作的执行结果。
class StorageActionResult {
  final bool success;
  final String code;
  final bool restricted;

  /// 根据执行状态与结果代码构造对象。
  const StorageActionResult({
    required this.success,
    this.code = '',
    this.restricted = false,
  });
}

/// 表示一条可管理的播放缓存记录。
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

  /// 根据播放缓存元数据构造对象。
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

  /// 从平台层映射恢复播放缓存记录。
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

/// 标识一份可提升为下载文件的缓存媒体来源。
class CachedMediaSourceIdentity {
  final String itemGuid;
  final String mediaGuid;
  final String videoGuid;
  final String resourceKey;

  /// 根据缓存媒体标识字段构造对象。
  const CachedMediaSourceIdentity({
    required this.itemGuid,
    required this.mediaGuid,
    required this.videoGuid,
    this.resourceKey = '',
  });

  /// 转换为平台层调用所需的映射结构。
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'itemGuid': itemGuid.trim(),
      'mediaGuid': mediaGuid.trim(),
      'videoGuid': videoGuid.trim(),
      'resourceKey': resourceKey.trim(),
    };
  }
}

/// 描述缓存媒体是否允许提升为离线下载文件。
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

  /// 根据缓存可提升性结果构造对象。
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

  /// 从平台层映射恢复缓存可提升性结果。
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

/// 表示缓存媒体提升到目标目录后的执行结果。
class CachedMediaPromoteResult {
  final bool success;
  final String code;
  final String path;
  final String fileName;

  /// 根据缓存提升结果构造对象。
  const CachedMediaPromoteResult({
    required this.success,
    required this.code,
    required this.path,
    required this.fileName,
  });

  /// 从平台层映射恢复缓存提升结果。
  factory CachedMediaPromoteResult.fromMap(Map<String, dynamic> raw) {
    return CachedMediaPromoteResult(
      success: raw['success'] == true,
      code: (raw['code'] ?? '').toString(),
      path: (raw['path'] ?? '').toString(),
      fileName: (raw['fileName'] ?? '').toString(),
    );
  }
}

/// 提供设置页存储统计、清理与缓存提升能力。
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

  /// 加载当前应用可展示的存储概览统计。
  Future<StorageOverview> loadOverview(AppLocalizations l10n) async {
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
    final dynamicThemeCacheBytes =
        DynamicThemeSeedExtractor.estimatePersistentCacheBytes(prefs) +
        DynamicThemeRuntimeController.instance.estimatePersistentCacheBytes(
          prefs,
        );
    final dynamicThemeCacheEntries =
        DynamicThemeSeedExtractor.countPersistentCacheEntries(prefs) +
        DynamicThemeRuntimeController.instance.countPersistentCacheEntries(
          prefs,
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
        dynamicThemeCacheBytes +
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
        title: l10n.storageDownloadsTitle,
        bytes: downloadBytes,
        countLabel: _fileCountLabel(l10n, downloadCount),
        clearAction: StorageClearAction.clearDownloads,
        note: l10n.storageDownloadsNote,
      ),
      StorageBreakdownItem(
        kind: StorageItemKind.playbackCache,
        title: l10n.storagePlaybackFiles,
        bytes: _asInt(playback['bytes']),
        countLabel: _playbackCacheCountLabel(
          l10n: l10n,
          fileCount: _asInt(playback['fileCount']),
          completeCount: _asInt(playback['completeCount']),
        ),
        clearAction: StorageClearAction.clearPlaybackCache,
        clearDisabled: playback['active'] == true,
        note: playback['active'] == true
            ? l10n.storagePlaybackActiveNote
            : null,
      ),
      StorageBreakdownItem(
        kind: StorageItemKind.screenshots,
        title: l10n.storageScreenshotsTitle,
        bytes: _asInt(screenshots['bytes']),
        countLabel: _fileCountLabel(l10n, _asInt(screenshots['fileCount'])),
        clearAction: StorageClearAction.clearScreenshots,
        isRestricted: screenshots['restricted'] == true,
        note: screenshots['restricted'] == true
            ? l10n.storageScreenshotsRestrictedNote
            : null,
      ),
      StorageBreakdownItem(
        kind: StorageItemKind.logs,
        title: l10n.storageLogsTitle,
        bytes: logsBytes,
        countLabel: _jsonListCountLabel(l10n, logsValue),
        clearAction: StorageClearAction.clearLogs,
        isEstimated: true,
        note: l10n.storageLogsNote,
      ),
      StorageBreakdownItem(
        kind: StorageItemKind.danmakuAiCache,
        title: l10n.storageDanmakuAiCacheTitle,
        bytes: _asInt(danmakuAiCache['bytes']),
        countLabel: _fileCountLabel(l10n, _asInt(danmakuAiCache['fileCount'])),
        clearAction: StorageClearAction.clearDanmakuAiCache,
        note: l10n.storageDanmakuAiCacheNote,
      ),
      StorageBreakdownItem(
        kind: StorageItemKind.appData,
        title: l10n.storageAppDataTitle,
        bytes: appDataBytes,
        countLabel: l10n.storageAppDataCount(
          _countStoredEntries(savedThemesValue) +
              _countStoredEntries(loginHistoryValue) +
              _countBookmarkEntries(bookmarksValue) +
              _countDanmakuSourceEntries(danmakuSourcesValue),
        ),
        isEstimated: true,
        note: l10n.storageAppDataOverviewNote(formatBytes(playStatsBytes)),
      ),
      StorageBreakdownItem(
        kind: StorageItemKind.otherCache,
        title: l10n.storageOtherCacheTitle,
        bytes: _asInt(otherCache['bytes']),
        countLabel: _fileCountLabel(l10n, _asInt(otherCache['fileCount'])),
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
      dynamicThemeCacheBytes: dynamicThemeCacheBytes,
      dynamicThemeCacheEntries: dynamicThemeCacheEntries,
      danmakuSourcesBytes: danmakuSourcesBytes,
      danmakuCacheBytes: danmakuCacheBytes,
      loginHistoryBytes: loginHistoryBytes,
      playStatsBytes: playStatsBytes,
      otherSettingsBytes: otherSettingsBytes,
    );
  }

  /// 执行依赖平台层支持的存储清理动作。
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

  /// 清空播放器书签数据。
  Future<void> clearBookmarks() => const BookmarkStore().clearAll();

  /// 清空已保存主题并刷新主题提供者状态。
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

  /// 清空动态主题种子缓存。
  Future<void> clearDynamicThemeSeedCache() async {
    final prefs = await SharedPreferences.getInstance();
    await DynamicThemeRuntimeController.instance.clearCachedSeeds(prefs: prefs);
    await DynamicThemeSeedExtractor.clearCache(prefs: prefs);
  }

  /// 清空已保存弹幕来源及其评论缓存。
  Future<void> clearDanmakuSources() async {
    await const DanmakuSavedSourceStore().clearAll();
    await const DanDanPlayCommentCacheStore().clearAll();
  }

  /// 清空登录历史记录。
  Future<void> clearLoginHistory() => LoginHistoryStore.clear();

  /// 将可重置的播放器与主题设置恢复为默认值。
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
    await DynamicThemeRuntimeController.instance.clearCachedSeeds(prefs: prefs);
    await DynamicThemeSeedExtractor.clearCache(prefs: prefs);
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

  /// 清空应用日志与崩溃日志。
  Future<void> clearLogs() => AppLogService.instance.clear();

  /// 列出当前可管理的播放缓存记录。
  Future<List<PlaybackCacheEntry>> loadPlaybackCacheEntries() async {
    final raw =
        await _channel.invokeListMethod<Object?>('listPlaybackCacheEntries') ??
        const <Object?>[];
    return raw
        .map((item) => PlaybackCacheEntry.fromMap(_normalizeMap(item)))
        .toList(growable: false);
  }

  /// 按资源键批量清理播放缓存记录。
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

  /// 列出当前已下载完成的离线任务记录。
  Future<List<DownloadTaskRecord>> loadDownloadEntries() async {
    final service = DownloadTaskService.instance;
    await service.initialize();
    return service.downloadedRecords;
  }

  /// 按记录标识批量删除已下载离线文件。
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

  /// 查询一份缓存媒体是否允许提升到外部目录。
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

  /// 将缓存媒体提升到目标存储位置。
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

  /// 将字节数格式化为适合界面展示的字符串。
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

  static String _fileCountLabel(AppLocalizations l10n, int count) {
    return l10n.storageFileCount(count <= 0 ? 0 : count);
  }

  static String _playbackCacheCountLabel({
    required AppLocalizations l10n,
    required int fileCount,
    required int completeCount,
  }) {
    final normalizedFileCount = fileCount < 0 ? 0 : fileCount;
    final normalizedCompleteCount = completeCount < 0 ? 0 : completeCount;
    return l10n.storagePlaybackCacheCount(
      normalizedFileCount,
      normalizedCompleteCount,
    );
  }

  static String _jsonListCountLabel(AppLocalizations l10n, Object? value) {
    final count = _countStoredEntries(value);
    return l10n.storageLogsCountLabel(count);
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
