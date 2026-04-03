import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/download_task_record.dart';
import '../providers/app_theme_provider.dart';
import '../providers/nas_provider.dart';
import '../providers/parallel_window_settings_provider.dart';
import '../services/download_task_service.dart';
import '../services/storage_management_service.dart';
import '../theme/app_theme.dart';
import '../ui/app_transitions.dart';
import '../ui/secondary_host_navigation.dart';
import '../utils/app_top_tip.dart';

class StorageManagementScreen extends StatefulWidget {
  const StorageManagementScreen({super.key});

  @override
  State<StorageManagementScreen> createState() =>
      _StorageManagementScreenState();
}

class _StorageManagementScreenState extends State<StorageManagementScreen> {
  final StorageManagementService _service = StorageManagementService.instance;
  final AppTopTip _topTip = AppTopTip();

  StorageOverview? _overview;
  bool _loading = true;
  bool _working = false;
  bool _playbackExpanded = false;
  bool _playbackLoading = false;
  List<PlaybackCacheEntry> _playbackEntries = const <PlaybackCacheEntry>[];
  final Set<String> _selectedPlaybackKeys = <String>{};
  bool _downloadsExpanded = false;
  bool _downloadsLoading = false;
  List<DownloadTaskRecord> _downloadEntries = const <DownloadTaskRecord>[];
  final Set<String> _selectedDownloadIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadOverview();
  }

  @override
  void dispose() {
    _topTip.dispose();
    super.dispose();
  }

  Future<void> _loadOverview() async {
    setState(() => _loading = true);
    final overview = await _service.loadOverview();
    if (!mounted) return;
    setState(() {
      _overview = overview;
      _loading = false;
    });
  }

  Future<void> _loadPlaybackEntries() async {
    if (_playbackLoading) return;
    setState(() => _playbackLoading = true);
    final entries = await _service.loadPlaybackCacheEntries();
    if (!mounted) return;
    setState(() {
      _playbackEntries = entries;
      _selectedPlaybackKeys.removeWhere(
        (key) => !entries.any((entry) => entry.resourceKey == key),
      );
      _playbackLoading = false;
    });
  }

  Future<void> _togglePlaybackExpanded() async {
    final nextExpanded = !_playbackExpanded;
    setState(() => _playbackExpanded = nextExpanded);
    if (nextExpanded) {
      await _loadPlaybackEntries();
    }
  }

  Future<void> _loadDownloadEntries() async {
    if (_downloadsLoading) return;
    setState(() => _downloadsLoading = true);
    final entries = await _service.loadDownloadEntries();
    if (!mounted) return;
    setState(() {
      _downloadEntries = entries;
      _selectedDownloadIds.removeWhere(
        (id) => !entries.any((entry) => entry.id == id),
      );
      _downloadsLoading = false;
    });
  }

  Future<void> _toggleDownloadsExpanded() async {
    final nextExpanded = !_downloadsExpanded;
    setState(() => _downloadsExpanded = nextExpanded);
    if (nextExpanded) {
      await _loadDownloadEntries();
    }
  }

  Future<void> _runSystemAction(
    StorageClearAction action, {
    required String successMessage,
    String restrictedMessage = '',
  }) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final result = await _service.clearSystemAction(action);
      if (!mounted) return;
      if (!result.success) {
        final message = switch (result.code) {
          'playback_active' => '播放中不可清理播放缓存',
          _ => '清理失败，请稍后重试',
        };
        _topTip.show(
          context,
          message: message,
          color: context.appColors.warning,
        );
        return;
      }
      await _loadOverview();
      if (_playbackExpanded) {
        await _loadPlaybackEntries();
      }
      if (_downloadsExpanded) {
        await _loadDownloadEntries();
      }
      if (!mounted) return;
      _topTip.show(
        context,
        message: result.restricted && restrictedMessage.isNotEmpty
            ? restrictedMessage
            : successMessage,
        color: context.appColors.success,
      );
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _clearSelectedPlaybackCache() async {
    if (_working || _selectedPlaybackKeys.isEmpty) return;
    final confirmed = await _confirmDialog(
      title: '清理选中缓存',
      message: '将删除选中的播放缓存文件，删除后需要重新缓存。是否继续？',
    );
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    try {
      final result = await _service.clearPlaybackCacheEntries(
        _selectedPlaybackKeys.toList(growable: false),
      );
      if (!mounted) return;
      if (!result.success) {
        final message = switch (result.code) {
          'playback_active' => '播放中不可清理播放缓存',
          'empty_selection' => '请先勾选要清理的缓存',
          _ => '清理失败，请稍后重试',
        };
        _topTip.show(
          context,
          message: message,
          color: context.appColors.warning,
        );
        return;
      }
      await _loadOverview();
      await _loadPlaybackEntries();
      if (!mounted) return;
      setState(() => _selectedPlaybackKeys.clear());
      _topTip.show(
        context,
        message: '已清理选中的播放缓存',
        color: context.appColors.success,
      );
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _promoteSelectedPlaybackCache() async {
    if (_working || _selectedPlaybackKeys.isEmpty) return;
    final nasProvider = context.read<NasProvider>();
    final selectedEntries = _playbackEntries
        .where((entry) => _selectedPlaybackKeys.contains(entry.resourceKey))
        .toList(growable: false);
    if (selectedEntries.isEmpty) return;
    setState(() => _working = true);
    try {
      final downloadService = DownloadTaskService.instance;
      await downloadService.initialize();
      final provider = nasProvider.isConfigured ? nasProvider : null;
      var convertedCount = 0;
      var existingCount = 0;
      var unavailableCount = 0;
      for (final entry in selectedEntries) {
        if (!_canPromotePlaybackEntry(entry)) {
          unavailableCount += 1;
          continue;
        }
        final result = await downloadService.importCachedMedia(
          provider: provider,
          identity: CachedMediaSourceIdentity(
            itemGuid: entry.itemGuid,
            mediaGuid: entry.mediaGuid,
            videoGuid: entry.videoGuid,
            resourceKey: entry.resourceKey,
          ),
          resolution: _playbackEntryResolution(entry),
          title: _playbackEntryTitle(entry),
          groupId: _playbackEntryGroupId(entry),
          groupTitle: _playbackEntryGroupTitle(entry),
          durationText: '',
          posterUrls: const <String>[],
          groupPosterUrls: const <String>[],
        );
        if (result == null) {
          unavailableCount += 1;
          continue;
        }
        switch (result.state) {
          case DownloadStartState.importedFromCache:
            convertedCount += 1;
            break;
          case DownloadStartState.downloaded:
            existingCount += 1;
            break;
          case DownloadStartState.downloading:
          case DownloadStartState.started:
            unavailableCount += 1;
            break;
        }
      }
      await _loadOverview();
      await _loadPlaybackEntries();
      if (_downloadsExpanded) {
        await _loadDownloadEntries();
      }
      if (!mounted) return;
      setState(() => _selectedPlaybackKeys.clear());
      final message = _playbackPromoteSummaryMessage(
        convertedCount: convertedCount,
        existingCount: existingCount,
        unavailableCount: unavailableCount,
      );
      _topTip.show(
        context,
        message: message,
        color: convertedCount > 0
            ? context.appColors.success
            : context.appColors.warning,
      );
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _clearSelectedDownloads() async {
    if (_working || _selectedDownloadIds.isEmpty) return;
    final confirmed = await _confirmDialog(
      title: '清理已下载文件',
      message: '将删除选中的本地下载文件，删除后需要重新下载。是否继续？',
    );
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    try {
      final result = await _service.clearDownloadEntries(
        _selectedDownloadIds.toList(growable: false),
      );
      if (!mounted) return;
      if (!result.success) {
        final message = switch (result.code) {
          'empty_selection' => '请先勾选要清理的下载文件',
          _ => '清理失败，请稍后重试',
        };
        _topTip.show(
          context,
          message: message,
          color: context.appColors.warning,
        );
        return;
      }
      await _loadOverview();
      await _loadDownloadEntries();
      if (!mounted) return;
      setState(() => _selectedDownloadIds.clear());
      _topTip.show(
        context,
        message: '已清理选中的下载文件',
        color: context.appColors.success,
      );
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  bool _canPromotePlaybackEntry(PlaybackCacheEntry entry) {
    return entry.complete &&
        entry.itemGuid.trim().isNotEmpty &&
        entry.mediaGuid.trim().isNotEmpty &&
        entry.videoGuid.trim().isNotEmpty;
  }

  String _playbackEntryResolution(PlaybackCacheEntry entry) {
    final resolution = entry.resolution.trim();
    if (resolution.isNotEmpty) return resolution;
    final segments = entry.subtitle
        .split('路')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    for (final segment in segments.reversed) {
      if (RegExp(r'\d{3,4}|4k', caseSensitive: false).hasMatch(segment)) {
        return segment;
      }
    }
    return '缓存';
  }

  String _playbackEntryTitle(PlaybackCacheEntry entry) {
    final title = entry.title.trim();
    if (title.isNotEmpty) return title;
    final seriesTitle = entry.seriesTitle.trim();
    if (seriesTitle.isNotEmpty) return seriesTitle;
    return '缓存视频';
  }

  String _playbackEntryGroupId(PlaybackCacheEntry entry) {
    final seriesTitle = entry.seriesTitle.trim();
    if (seriesTitle.isNotEmpty && entry.seasonNumber > 0) {
      return '$seriesTitle::season:${entry.seasonNumber}';
    }
    if (seriesTitle.isNotEmpty && entry.episodeNumber > 0) {
      return '$seriesTitle::specials';
    }
    final itemGuid = entry.itemGuid.trim();
    if (itemGuid.isNotEmpty) return itemGuid;
    return entry.resourceKey.trim();
  }

  String _playbackEntryGroupTitle(PlaybackCacheEntry entry) {
    final seriesTitle = entry.seriesTitle.trim();
    if (seriesTitle.isEmpty) {
      return _playbackEntryTitle(entry);
    }
    if (entry.seasonNumber > 0) {
      return '$seriesTitle 第${entry.seasonNumber}季';
    }
    if (entry.episodeNumber > 0) {
      return '$seriesTitle 特别篇';
    }
    return seriesTitle;
  }

  String _playbackPromoteSummaryMessage({
    required int convertedCount,
    required int existingCount,
    required int unavailableCount,
  }) {
    final parts = <String>[];
    if (convertedCount > 0) {
      parts.add('已转为下载 $convertedCount 项');
    }
    if (existingCount > 0) {
      parts.add('已有下载 $existingCount 项');
    }
    if (unavailableCount > 0) {
      parts.add('不可转换 $unavailableCount 项');
    }
    if (parts.isEmpty) {
      return '当前没有可转换的完整缓存';
    }
    return parts.join('，');
  }

  Future<bool?> _confirmDialog({
    required String title,
    required String message,
  }) {
    final colors = context.appColors;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: colors.backgroundElevated,
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确认'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openAppDataDetails(StorageOverview overview) async {
    await Navigator.of(context).push<void>(
      AppTransitions.leftToRightPageTurnRoute<void>(
        StorageAppDataScreen(
          overview: overview,
          formatBytes: _service.formatBytes,
        ),
      ),
    );
    if (mounted) {
      await _loadOverview();
    }
  }

  Color _colorFor(StorageItemKind kind, AppThemeColors colors) {
    return switch (kind) {
      StorageItemKind.playbackCache => const Color(0xFF8B5CF6),
      StorageItemKind.downloads => const Color(0xFF22C55E),
      StorageItemKind.screenshots => const Color(0xFF06B6D4),
      StorageItemKind.logs => const Color(0xFFF59E0B),
      StorageItemKind.appData => const Color(0xFF60A5FA),
      StorageItemKind.danmakuAiCache => const Color(0xFFEC4899),
      StorageItemKind.otherCache => const Color(0xFF64748B),
    };
  }

  StorageBreakdownItem? _itemOfKind(
    StorageOverview overview,
    StorageItemKind kind,
  ) {
    for (final item in overview.items) {
      if (item.kind == kind) return item;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final overview = _overview;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: buildSecondaryHostAppBar(
        context,
        title: const Text('储存管理'),
        actions: <Widget>[
          IconButton(
            onPressed: _working ? null : _loadOverview,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
          ),
        ],
      ),
      body: _loading || overview == null
          ? Center(child: CircularProgressIndicator(color: colors.accent))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: <Widget>[
                _StorageOverviewCard(
                  totalLabel: _service.formatBytes(overview.totalBytes),
                  updatedAt: overview.updatedAt,
                ),
                const SizedBox(height: 14),
                _StorageChartCard(
                  items: overview.items,
                  colorFor: (kind) => _colorFor(kind, colors),
                  formatBytes: _service.formatBytes,
                ),
                const SizedBox(height: 14),
                _StorageCategoriesCard(
                  playbackItem: _itemOfKind(
                    overview,
                    StorageItemKind.playbackCache,
                  ),
                  downloadsItem: _itemOfKind(
                    overview,
                    StorageItemKind.downloads,
                  ),
                  screenshotsItem: _itemOfKind(
                    overview,
                    StorageItemKind.screenshots,
                  ),
                  logsItem: _itemOfKind(overview, StorageItemKind.logs),
                  danmakuAiCacheItem: _itemOfKind(
                    overview,
                    StorageItemKind.danmakuAiCache,
                  ),
                  appDataItem: _itemOfKind(overview, StorageItemKind.appData),
                  otherCacheItem: _itemOfKind(
                    overview,
                    StorageItemKind.otherCache,
                  ),
                  colorFor: (kind) => _colorFor(kind, colors),
                  formatBytes: _service.formatBytes,
                  busy: _working,
                  playbackExpanded: _playbackExpanded,
                  playbackLoading: _playbackLoading,
                  playbackEntries: _playbackEntries,
                  selectedPlaybackKeys: _selectedPlaybackKeys,
                  downloadsExpanded: _downloadsExpanded,
                  downloadsLoading: _downloadsLoading,
                  downloadEntries: _downloadEntries,
                  selectedDownloadIds: _selectedDownloadIds,
                  onTogglePlaybackExpanded: _togglePlaybackExpanded,
                  onToggleDownloadsExpanded: _toggleDownloadsExpanded,
                  onTogglePlaybackSelected: (resourceKey, selected) {
                    setState(() {
                      if (selected) {
                        _selectedPlaybackKeys.add(resourceKey);
                      } else {
                        _selectedPlaybackKeys.remove(resourceKey);
                      }
                    });
                  },
                  onToggleDownloadSelected: (recordId, selected) {
                    setState(() {
                      if (selected) {
                        _selectedDownloadIds.add(recordId);
                      } else {
                        _selectedDownloadIds.remove(recordId);
                      }
                    });
                  },
                  onToggleSelectAllPlayback: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedPlaybackKeys
                          ..clear()
                          ..addAll(
                            _playbackEntries.map((entry) => entry.resourceKey),
                          );
                      } else {
                        _selectedPlaybackKeys.clear();
                      }
                    });
                  },
                  onToggleSelectAllDownloads: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedDownloadIds
                          ..clear()
                          ..addAll(_downloadEntries.map((entry) => entry.id));
                      } else {
                        _selectedDownloadIds.clear();
                      }
                    });
                  },
                  onClearSelectedPlayback: _clearSelectedPlaybackCache,
                  onPromoteSelectedPlayback: _promoteSelectedPlaybackCache,
                  onClearSelectedDownloads: _clearSelectedDownloads,
                  onClearSystemItem: (item) async {
                    final action = item.clearAction;
                    if (action == null) return;
                    final confirmed = await _confirmDialog(
                      title: '清理${item.title}',
                      message: '将清理${item.title}，对应文件会被删除。是否继续？',
                    );
                    if (confirmed != true || !mounted) return;
                    await _runSystemAction(
                      action,
                      successMessage: '${item.title}已清理',
                      restrictedMessage: '${item.title}已部分清理，公共目录未授权',
                    );
                  },
                  onOpenAppData: () => _openAppDataDetails(overview),
                ),
              ],
            ),
    );
  }
}

class StorageAppDataScreen extends StatefulWidget {
  final StorageOverview overview;
  final String Function(int bytes) formatBytes;

  const StorageAppDataScreen({
    super.key,
    required this.overview,
    required this.formatBytes,
  });

  @override
  State<StorageAppDataScreen> createState() => _StorageAppDataScreenState();
}

class _StorageAppDataScreenState extends State<StorageAppDataScreen> {
  final StorageManagementService _service = StorageManagementService.instance;
  final AppTopTip _topTip = AppTopTip();
  bool _working = false;

  @override
  void dispose() {
    _topTip.dispose();
    super.dispose();
  }

  Future<void> _runDangerAction({
    required String title,
    required String message,
    required Future<void> Function() onConfirmed,
  }) async {
    if (_working) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = context.appColors;
        return AlertDialog(
          backgroundColor: colors.backgroundElevated,
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('鍙栨秷'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('纭'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    try {
      await onConfirmed();
      if (!mounted) return;
      _topTip.show(
        context,
        message: '$title已完成',
        color: context.appColors.success,
      );
    } catch (_) {
      if (!mounted) return;
      _topTip.show(
        context,
        message: '$title失败，请稍后重试',
        color: context.appColors.warning,
      );
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final overview = widget.overview;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: buildSecondaryHostAppBar(context, title: const Text('应用数据与危险操作')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '应用数据',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '这些内容通常是用户记录和个性化配置，不会和普通缓存一起清理。',
                  style: TextStyle(color: colors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 14),
                _DangerActionRow(
                  title: '清空书签',
                  subtitle: '仅删除播放书签记录',
                  trailing: widget.formatBytes(overview.bookmarksBytes),
                  busy: _working,
                  onTap: () => _runDangerAction(
                    title: '清空书签',
                    message: '将删除全部播放书签，此操作不可恢复。',
                    onConfirmed: _service.clearBookmarks,
                  ),
                ),
                const Divider(height: 24),
                _DangerActionRow(
                  title: '清空已保存主题',
                  subtitle: '保留当前自定义配置',
                  trailing: widget.formatBytes(overview.savedThemesBytes),
                  busy: _working,
                  onTap: () => _runDangerAction(
                    title: '清空已保存主题',
                    message: '将删除已保存主题，但不会影响当前自定义配置。',
                    onConfirmed: () => _service.clearSavedThemes(
                      context.read<AppThemeProvider>(),
                    ),
                  ),
                ),
                const Divider(height: 24),
                _DangerActionRow(
                  title: '清空弹幕来源',
                  subtitle: '删除已保存的弹幕来源记录',
                  trailing: widget.formatBytes(
                    overview.danmakuSourcesBytes + overview.danmakuCacheBytes,
                  ),
                  busy: _working,
                  onTap: () => _runDangerAction(
                    title: '清空弹幕来源',
                    message: '将删除已保存的弹幕来源记录。',
                    onConfirmed: _service.clearDanmakuSources,
                  ),
                ),
                const Divider(height: 24),
                _DangerActionRow(
                  title: '清空登录历史',
                  subtitle: '不会退出当前会话',
                  trailing: widget.formatBytes(overview.loginHistoryBytes),
                  busy: _working,
                  onTap: () => _runDangerAction(
                    title: '清空登录历史',
                    message: '将删除历史登录记录，不会退出当前登录。',
                    onConfirmed: _service.clearLoginHistory,
                  ),
                ),
                const Divider(height: 24),
                _DangerActionRow(
                  title: '重置设置',
                  subtitle: '主题、播放器、截图、弹幕与平行窗口设置',
                  trailing: widget.formatBytes(overview.otherSettingsBytes),
                  busy: _working,
                  onTap: () => _runDangerAction(
                    title: '重置设置',
                    message: '将重置主题、播放器、截图、弹幕和平行窗口设置，不会清理缓存和用户文件。',
                    onConfirmed: () => _service.resetSettings(
                      themeProvider: context.read<AppThemeProvider>(),
                      parallelWindowSettingsProvider: context
                          .read<ParallelWindowSettingsProvider>(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StorageOverviewCard extends StatelessWidget {
  final String totalLabel;
  final DateTime updatedAt;

  const _StorageOverviewCard({
    required this.totalLabel,
    required this.updatedAt,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final hh = updatedAt.hour.toString().padLeft(2, '0');
    final mm = updatedAt.minute.toString().padLeft(2, '0');
    return _SectionCard(
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.storage_rounded, color: colors.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '总占用',
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  totalLabel,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '上次刷新 $hh:$mm',
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StorageChartCard extends StatefulWidget {
  final List<StorageBreakdownItem> items;
  final Color Function(StorageItemKind kind) colorFor;
  final String Function(int bytes) formatBytes;

  const _StorageChartCard({
    required this.items,
    required this.colorFor,
    required this.formatBytes,
  });

  @override
  State<_StorageChartCard> createState() => _StorageChartCardState();
}

class _StorageChartCardState extends State<_StorageChartCard>
    with SingleTickerProviderStateMixin {
  StorageItemKind? _selectedKind;
  StorageItemKind? _animatedKind;
  late final AnimationController _selectionController;
  late final CurvedAnimation _selectionCurve;

  @override
  void initState() {
    super.initState();
    _selectionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _selectionCurve = CurvedAnimation(
      parent: _selectionController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _selectionController.dispose();
    super.dispose();
  }

  StorageItemKind? _effectiveSelectedKind(List<StorageBreakdownItem> items) {
    if (items.isEmpty) return null;
    final selected = _selectedKind;
    if (selected != null && items.any((item) => item.kind == selected)) {
      return selected;
    }
    return null;
  }

  Future<void> _toggleSelected(StorageItemKind kind) async {
    if (_selectedKind == kind) {
      setState(() {
        _selectedKind = null;
        _animatedKind = kind;
      });
      await _selectionController.reverse(from: _selectionController.value);
      if (!mounted) return;
      setState(() => _animatedKind = null);
      return;
    }

    setState(() {
      _selectedKind = kind;
      _animatedKind = kind;
    });
    await _selectionController.forward(from: 0);
  }

  StorageBreakdownItem? _itemAtOffset(
    Offset position,
    Size size,
    List<StorageBreakdownItem> items,
    int totalBytes,
  ) {
    if (items.isEmpty || totalBytes <= 0) return null;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 18;
    final strokeWidth = math.max(20.0, radius * 0.28);
    final distance = (position - center).distance;
    final innerRadius = radius - strokeWidth / 2 - 10;
    final outerRadius = radius + strokeWidth / 2 + 10;
    if (distance < innerRadius || distance > outerRadius) {
      return null;
    }

    final rawAngle = math.atan2(
      position.dy - center.dy,
      position.dx - center.dx,
    );
    var angle = rawAngle + math.pi / 2;
    if (angle < 0) {
      angle += math.pi * 2;
    }

    var start = 0.0;
    for (final item in items) {
      final sweep = (item.bytes / totalBytes) * math.pi * 2;
      if (angle >= start && angle <= start + sweep) {
        return item;
      }
      start += sweep;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final activeItems = widget.items
        .where((item) => item.bytes > 0)
        .toList(growable: false);
    final total = activeItems.fold<int>(0, (sum, item) => sum + item.bytes);
    final selectedKind = _effectiveSelectedKind(activeItems);
    final highlightKind =
        selectedKind ??
        (_animatedKind != null &&
                activeItems.any((item) => item.kind == _animatedKind)
            ? _animatedKind
            : null);
    final selectedItem = selectedKind == null
        ? null
        : activeItems.cast<StorageBreakdownItem?>().firstWhere(
            (item) => item?.kind == selectedKind,
            orElse: () => null,
          );
    return _SectionCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactLayout = constraints.maxWidth < 430;
          final wideLegendWidth = compactLayout
              ? constraints.maxWidth
              : (constraints.maxWidth * 0.46).clamp(220.0, 320.0);
          final wideLegendTwoColumns =
              !compactLayout &&
              wideLegendWidth >= 240 &&
              activeItems.length > 2;
          final donutSize = compactLayout
              ? 200.0
              : (constraints.maxWidth - wideLegendWidth - 18).clamp(
                  190.0,
                  250.0,
                );
          final donut = SizedBox.square(
            dimension: donutSize,
            child: AnimatedBuilder(
              animation: _selectionCurve,
              builder: (context, child) {
                return CustomPaint(
                  painter: _StorageDonutPainter(
                    items: activeItems,
                    colorFor: widget.colorFor,
                    totalBytes: total,
                    trackColor: colors.borderSubtle,
                    selectedKind: highlightKind,
                    progress: _selectionCurve.value,
                  ),
                  child: child,
                );
              },
              child: LayoutBuilder(
                builder: (context, donutConstraints) {
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) {
                      final tapped = _itemAtOffset(
                        details.localPosition,
                        donutConstraints.biggest,
                        activeItems,
                        total,
                      );
                      if (tapped == null) return;
                      _toggleSelected(tapped.kind);
                    },
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: ScaleTransition(
                              scale: Tween<double>(
                                begin: 0.96,
                                end: 1,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: Column(
                          key: ValueKey<StorageItemKind?>(selectedKind),
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              selectedItem?.title ?? '总计',
                              style: TextStyle(
                                color: selectedItem == null
                                    ? colors.textSecondary
                                    : widget.colorFor(selectedItem.kind),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.formatBytes(selectedItem?.bytes ?? total),
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (selectedItem != null) ...<Widget>[
                              const SizedBox(height: 4),
                              Text(
                                '${(selectedItem.bytes / total * 100).toStringAsFixed(1)}%',
                                style: TextStyle(
                                  color: colors.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );

          final legend = activeItems.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    '暂无占用数据',
                    style: TextStyle(color: colors.textMuted, fontSize: 13),
                  ),
                )
              : compactLayout
              ? Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: activeItems
                      .map((item) {
                        final ratio = total <= 0 ? 0 : item.bytes / total * 100;
                        final itemWidth = ((constraints.maxWidth - 12) / 2)
                            .clamp(120.0, 220.0);
                        return SizedBox(
                          width: itemWidth,
                          child: _StorageChartLegendItem(
                            item: item,
                            ratioLabel:
                                '${ratio.toStringAsFixed(1)}% · ${widget.formatBytes(item.bytes)}',
                            color: widget.colorFor(item.kind),
                            selected: item.kind == selectedKind,
                            onTap: () => _toggleSelected(item.kind),
                          ),
                        );
                      })
                      .toList(growable: false),
                )
              : SizedBox(
                  width: wideLegendWidth,
                  child: wideLegendTwoColumns
                      ? GridView.builder(
                          primary: false,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: 1.55,
                              ),
                          itemCount: activeItems.length,
                          itemBuilder: (context, index) {
                            final item = activeItems[index];
                            final ratio = total <= 0
                                ? 0
                                : item.bytes / total * 100;
                            return _StorageChartLegendItem(
                              item: item,
                              ratioLabel:
                                  '${ratio.toStringAsFixed(1)}% · ${widget.formatBytes(item.bytes)}',
                              color: widget.colorFor(item.kind),
                              selected: item.kind == selectedKind,
                              onTap: () => _toggleSelected(item.kind),
                            );
                          },
                        )
                      : ListView.separated(
                          primary: false,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: activeItems.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final item = activeItems[index];
                            final ratio = total <= 0
                                ? 0
                                : item.bytes / total * 100;
                            return _StorageChartLegendItem(
                              item: item,
                              ratioLabel:
                                  '${ratio.toStringAsFixed(1)}% · ${widget.formatBytes(item.bytes)}',
                              color: widget.colorFor(item.kind),
                              selected: item.kind == selectedKind,
                              onTap: () => _toggleSelected(item.kind),
                            );
                          },
                        ),
                );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '占用分类',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              if (compactLayout) ...<Widget>[
                donut,
                const SizedBox(height: 16),
                legend,
              ] else
                SizedBox(
                  height: 250,
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: donut,
                        ),
                      ),
                      const SizedBox(width: 18),
                      legend,
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StorageChartLegendItem extends StatelessWidget {
  final StorageBreakdownItem item;
  final String ratioLabel;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _StorageChartLegendItem({
    required this.item,
    required this.ratioLabel,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.55)
                : Colors.transparent,
          ),
          boxShadow: selected
              ? <BoxShadow>[
                  BoxShadow(
                    color: color.withValues(alpha: 0.16),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ]
              : const <BoxShadow>[],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: selected ? 11 : 10,
                  height: selected ? 11 : 10,
                  margin: const EdgeInsets.only(top: 3),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ratioLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              height: 2,
              width: selected ? 36 : 0,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StorageCategoriesCard extends StatelessWidget {
  final StorageBreakdownItem? playbackItem;
  final StorageBreakdownItem? downloadsItem;
  final StorageBreakdownItem? screenshotsItem;
  final StorageBreakdownItem? logsItem;
  final StorageBreakdownItem? danmakuAiCacheItem;
  final StorageBreakdownItem? appDataItem;
  final StorageBreakdownItem? otherCacheItem;
  final Color Function(StorageItemKind kind) colorFor;
  final String Function(int bytes) formatBytes;
  final bool busy;
  final bool playbackExpanded;
  final bool playbackLoading;
  final List<PlaybackCacheEntry> playbackEntries;
  final Set<String> selectedPlaybackKeys;
  final bool downloadsExpanded;
  final bool downloadsLoading;
  final List<DownloadTaskRecord> downloadEntries;
  final Set<String> selectedDownloadIds;
  final Future<void> Function() onTogglePlaybackExpanded;
  final Future<void> Function() onToggleDownloadsExpanded;
  final void Function(String resourceKey, bool selected)
  onTogglePlaybackSelected;
  final void Function(String recordId, bool selected) onToggleDownloadSelected;
  final void Function(bool selected) onToggleSelectAllPlayback;
  final void Function(bool selected) onToggleSelectAllDownloads;
  final Future<void> Function() onClearSelectedPlayback;
  final Future<void> Function() onPromoteSelectedPlayback;
  final Future<void> Function() onClearSelectedDownloads;
  final Future<void> Function(StorageBreakdownItem item) onClearSystemItem;
  final VoidCallback onOpenAppData;

  const _StorageCategoriesCard({
    required this.playbackItem,
    required this.downloadsItem,
    required this.screenshotsItem,
    required this.logsItem,
    required this.danmakuAiCacheItem,
    required this.appDataItem,
    required this.otherCacheItem,
    required this.colorFor,
    required this.formatBytes,
    required this.busy,
    required this.playbackExpanded,
    required this.playbackLoading,
    required this.playbackEntries,
    required this.selectedPlaybackKeys,
    required this.downloadsExpanded,
    required this.downloadsLoading,
    required this.downloadEntries,
    required this.selectedDownloadIds,
    required this.onTogglePlaybackExpanded,
    required this.onToggleDownloadsExpanded,
    required this.onTogglePlaybackSelected,
    required this.onToggleDownloadSelected,
    required this.onToggleSelectAllPlayback,
    required this.onToggleSelectAllDownloads,
    required this.onClearSelectedPlayback,
    required this.onPromoteSelectedPlayback,
    required this.onClearSelectedDownloads,
    required this.onClearSystemItem,
    required this.onOpenAppData,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '分类详情',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          if (playbackItem != null) ...<Widget>[
            _ExpandableStorageRow(
              item: playbackItem!,
              color: colorFor(playbackItem!.kind),
              formatBytes: formatBytes,
              expanded: playbackExpanded,
              busy: busy,
              onTap: onTogglePlaybackExpanded,
            ),
            if (playbackExpanded) ...<Widget>[
              const SizedBox(height: 12),
              _PlaybackEntryPanel(
                entries: playbackEntries,
                selectedKeys: selectedPlaybackKeys,
                loading: playbackLoading,
                busy: busy,
                formatBytes: formatBytes,
                onToggleSelected: onTogglePlaybackSelected,
                onToggleSelectAll: onToggleSelectAllPlayback,
                onPromoteSelected: onPromoteSelectedPlayback,
                onClearSelected: onClearSelectedPlayback,
              ),
            ],
            const Divider(height: 24),
          ],
          if (downloadsItem != null) ...<Widget>[
            _ExpandableStorageRow(
              item: downloadsItem!,
              color: colorFor(downloadsItem!.kind),
              formatBytes: formatBytes,
              expanded: downloadsExpanded,
              busy: busy,
              onTap: onToggleDownloadsExpanded,
            ),
            if (downloadsExpanded) ...<Widget>[
              const SizedBox(height: 12),
              _DownloadEntryPanel(
                entries: downloadEntries,
                selectedIds: selectedDownloadIds,
                loading: downloadsLoading,
                busy: busy,
                formatBytes: formatBytes,
                onToggleSelected: onToggleDownloadSelected,
                onToggleSelectAll: onToggleSelectAllDownloads,
                onClearSelected: onClearSelectedDownloads,
              ),
            ],
            const Divider(height: 24),
          ],
          if (screenshotsItem != null) ...<Widget>[
            _StorageItemRow(
              item: screenshotsItem!,
              color: colorFor(screenshotsItem!.kind),
              formatBytes: formatBytes,
              busy: busy,
              onClear: screenshotsItem!.clearAction == null
                  ? null
                  : () => onClearSystemItem(screenshotsItem!),
            ),
            const Divider(height: 24),
          ],
          if (logsItem != null) ...<Widget>[
            _StorageItemRow(
              item: logsItem!,
              color: colorFor(logsItem!.kind),
              formatBytes: formatBytes,
              busy: busy,
              onClear: logsItem!.clearAction == null
                  ? null
                  : () => onClearSystemItem(logsItem!),
            ),
            const Divider(height: 24),
          ],
          if (danmakuAiCacheItem != null) ...<Widget>[
            _StorageItemRow(
              item: danmakuAiCacheItem!,
              color: colorFor(danmakuAiCacheItem!.kind),
              formatBytes: formatBytes,
              busy: busy,
              onClear: danmakuAiCacheItem!.clearAction == null
                  ? null
                  : () => onClearSystemItem(danmakuAiCacheItem!),
            ),
            const Divider(height: 24),
          ],
          if (appDataItem != null) ...<Widget>[
            _NavigateStorageRow(
              item: appDataItem!,
              color: colorFor(appDataItem!.kind),
              formatBytes: formatBytes,
              onTap: onOpenAppData,
            ),
            const Divider(height: 24),
          ],
          if (otherCacheItem != null)
            _StorageItemRow(
              item: otherCacheItem!,
              color: colorFor(otherCacheItem!.kind),
              formatBytes: formatBytes,
              busy: busy,
              onClear: otherCacheItem!.clearAction == null
                  ? null
                  : () => onClearSystemItem(otherCacheItem!),
            ),
        ],
      ),
    );
  }
}

class _ExpandableStorageRow extends StatelessWidget {
  final StorageBreakdownItem item;
  final Color color;
  final String Function(int bytes) formatBytes;
  final bool expanded;
  final bool busy;
  final Future<void> Function() onTap;

  const _ExpandableStorageRow({
    required this.item,
    required this.color,
    required this.formatBytes,
    required this.expanded,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.only(top: 5),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          item.title,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        formatBytes(item.bytes),
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (item.countLabel.isNotEmpty) item.countLabel,
                      if (item.note?.trim().isNotEmpty == true) item.note!,
                    ].join(' 路'),
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              color: colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaybackEntryPanel extends StatelessWidget {
  final List<PlaybackCacheEntry> entries;
  final Set<String> selectedKeys;
  final bool loading;
  final bool busy;
  final String Function(int bytes) formatBytes;
  final void Function(String resourceKey, bool selected) onToggleSelected;
  final void Function(bool selected) onToggleSelectAll;
  final Future<void> Function() onPromoteSelected;
  final Future<void> Function() onClearSelected;

  const _PlaybackEntryPanel({
    required this.entries,
    required this.selectedKeys,
    required this.loading,
    required this.busy,
    required this.formatBytes,
    required this.onToggleSelected,
    required this.onToggleSelectAll,
    required this.onPromoteSelected,
    required this.onClearSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final selectableEntries = entries
        .where((entry) => entry.bytes > 0)
        .toList(growable: false);
    final promotableSelectedCount = entries
        .where(
          (entry) =>
              selectedKeys.contains(entry.resourceKey) &&
              entry.complete &&
              entry.itemGuid.trim().isNotEmpty &&
              entry.mediaGuid.trim().isNotEmpty &&
              entry.videoGuid.trim().isNotEmpty,
        )
        .length;
    final allSelected =
        selectableEntries.isNotEmpty &&
        selectableEntries.every(
          (entry) => selectedKeys.contains(entry.resourceKey),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.backgroundElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        children: <Widget>[
          _SelectionPanelHeader(
            title: '\u7f13\u5b58\u6761\u76ee',
            primaryAction: TextButton(
              onPressed: loading || busy || selectableEntries.isEmpty
                  ? null
                  : () => onToggleSelectAll(!allSelected),
              child: Text(
                allSelected ? '\u53d6\u6d88\u5168\u9009' : '\u5168\u9009',
              ),
            ),
            secondaryAction: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                FilledButton(
                  onPressed: busy || promotableSelectedCount == 0
                      ? null
                      : onPromoteSelected,
                  child: Text(
                    '\u8f6c\u4e3a\u4e0b\u8f7d ($promotableSelectedCount)',
                  ),
                ),
                FilledButton.tonal(
                  onPressed: busy || selectedKeys.isEmpty
                      ? null
                      : onClearSelected,
                  child: Text(
                    '\u6e05\u7406\u9009\u4e2d (${selectedKeys.length})',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                '当前没有可清理的播放缓存。',
                style: TextStyle(color: colors.textMuted, fontSize: 13),
              ),
            )
          else
            ...entries.map((entry) {
              final checked = selectedKeys.contains(entry.resourceKey);
              return CheckboxListTile(
                value: checked,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                onChanged: busy
                    ? null
                    : (value) =>
                          onToggleSelected(entry.resourceKey, value ?? false),
                title: Text(
                  entry.title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  [
                    if (entry.subtitle.isNotEmpty) entry.subtitle,
                    entry.complete ? '已完整缓存' : '未完整缓存',
                    _formatAccessTime(entry.lastAccessAt),
                  ].join(' 路'),
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
                secondary: Text(
                  formatBytes(entry.bytes),
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  static String _formatAccessTime(DateTime dateTime) {
    final hh = dateTime.hour.toString().padLeft(2, '0');
    final mm = dateTime.minute.toString().padLeft(2, '0');
    return '${dateTime.month}/${dateTime.day} $hh:$mm';
  }
}

class _DownloadEntryPanel extends StatelessWidget {
  final List<DownloadTaskRecord> entries;
  final Set<String> selectedIds;
  final bool loading;
  final bool busy;
  final String Function(int bytes) formatBytes;
  final void Function(String recordId, bool selected) onToggleSelected;
  final void Function(bool selected) onToggleSelectAll;
  final Future<void> Function() onClearSelected;

  const _DownloadEntryPanel({
    required this.entries,
    required this.selectedIds,
    required this.loading,
    required this.busy,
    required this.formatBytes,
    required this.onToggleSelected,
    required this.onToggleSelectAll,
    required this.onClearSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final selectableEntries = entries
        .where((entry) => entry.filePath.trim().isNotEmpty)
        .toList(growable: false);
    final allSelected =
        selectableEntries.isNotEmpty &&
        selectableEntries.every((entry) => selectedIds.contains(entry.id));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.backgroundElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        children: <Widget>[
          _SelectionPanelHeader(
            title: '\u4e0b\u8f7d\u6587\u4ef6',
            primaryAction: TextButton(
              onPressed: loading || busy || selectableEntries.isEmpty
                  ? null
                  : () => onToggleSelectAll(!allSelected),
              child: Text(
                allSelected ? '\u53d6\u6d88\u5168\u9009' : '\u5168\u9009',
              ),
            ),
            secondaryAction: FilledButton.tonal(
              onPressed: busy || selectedIds.isEmpty ? null : onClearSelected,
              child: Text('\u6e05\u7406\u9009\u4e2d (${selectedIds.length})'),
            ),
          ),
          const SizedBox(height: 8),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                '当前没有可查看的本地下载文件。',
                style: TextStyle(color: colors.textMuted, fontSize: 13),
              ),
            )
          else
            ...entries.map((entry) {
              final checked = selectedIds.contains(entry.id);
              return CheckboxListTile(
                value: checked,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                onChanged: busy
                    ? null
                    : (value) => onToggleSelected(entry.id, value ?? false),
                title: Text(
                  entry.title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  [
                    if (entry.resolution.trim().isNotEmpty) entry.resolution,
                    if (entry.durationText.trim().isNotEmpty)
                      entry.durationText,
                    _formatUpdatedTime(entry.updatedAtMs),
                    entry.filePath,
                  ].join(' ·'),
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                secondary: Text(
                  formatBytes(entry.totalBytes),
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  static String _formatUpdatedTime(int updatedAtMs) {
    if (updatedAtMs <= 0) return '-';
    final dateTime = DateTime.fromMillisecondsSinceEpoch(updatedAtMs);
    final hh = dateTime.hour.toString().padLeft(2, '0');
    final mm = dateTime.minute.toString().padLeft(2, '0');
    return '${dateTime.month}/${dateTime.day} $hh:$mm';
  }
}

class _SelectionPanelHeader extends StatelessWidget {
  final String title;
  final Widget primaryAction;
  final Widget secondaryAction;
  const _SelectionPanelHeader({
    required this.title,
    required this.primaryAction,
    required this.secondaryAction,
  });
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 320;
        final titleWidget = Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        );
        final actions = Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[primaryAction, secondaryAction],
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              titleWidget,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: actions),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: titleWidget),
            const SizedBox(width: 12),
            Flexible(
              child: Align(alignment: Alignment.centerRight, child: actions),
            ),
          ],
        );
      },
    );
  }
}

class _NavigateStorageRow extends StatelessWidget {
  final StorageBreakdownItem item;
  final Color color;
  final String Function(int bytes) formatBytes;
  final VoidCallback onTap;

  const _NavigateStorageRow({
    required this.item,
    required this.color,
    required this.formatBytes,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.only(top: 5),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          item.title,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        formatBytes(item.bytes),
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (item.countLabel.isNotEmpty) item.countLabel,
                      if (item.note?.trim().isNotEmpty == true) item.note!,
                      '进入管理',
                    ].join(' 路'),
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _StorageItemRow extends StatelessWidget {
  final StorageBreakdownItem item;
  final Color color;
  final String Function(int bytes) formatBytes;
  final bool busy;
  final VoidCallback? onClear;

  const _StorageItemRow({
    required this.item,
    required this.color,
    required this.formatBytes,
    required this.busy,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      item.title,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    formatBytes(item.bytes),
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (item.countLabel.isNotEmpty) item.countLabel,
                  if (item.isEstimated) '估算',
                  if (item.isRestricted) '权限受限',
                ].join(' 路'),
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
              if (item.note?.trim().isNotEmpty == true) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  item.note!,
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        if (onClear != null) ...<Widget>[
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: busy || item.clearDisabled ? null : onClear,
            child: const Text('清理'),
          ),
        ],
      ],
    );
  }
}

class _DangerActionRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final String trailing;
  final bool busy;
  final VoidCallback onTap;

  const _DangerActionRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          trailing,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 12),
        TextButton(onPressed: busy ? null : onTap, child: const Text('清空')),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;

  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.backgroundElevated,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.borderSubtle),
      ),
      padding: const EdgeInsets.all(18),
      child: child,
    );
  }
}

class _StorageDonutPainter extends CustomPainter {
  final List<StorageBreakdownItem> items;
  final Color Function(StorageItemKind kind) colorFor;
  final int totalBytes;
  final Color trackColor;
  final StorageItemKind? selectedKind;
  final double progress;

  const _StorageDonutPainter({
    required this.items,
    required this.colorFor,
    required this.totalBytes,
    required this.trackColor,
    required this.selectedKind,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 18;
    final strokeWidth = math.max(20.0, radius * 0.28);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2, false, trackPaint);
    if (totalBytes <= 0 || items.isEmpty) return;
    var startAngle = -math.pi / 2;
    for (final item in items) {
      final sweepAngle = (item.bytes / totalBytes) * math.pi * 2;
      final isSelected = item.kind == selectedKind;
      final segmentColor = colorFor(item.kind);
      final midAngle = startAngle + sweepAngle / 2;
      final popOutOffset = isSelected ? 10.0 * progress : 0.0;
      final segmentCenter = Offset(
        center.dx + math.cos(midAngle) * popOutOffset,
        center.dy + math.sin(midAngle) * popOutOffset,
      );
      final segmentRect = Rect.fromCircle(
        center: segmentCenter,
        radius: radius + (2.0 * progress),
      );
      final paint = Paint()
        ..color = segmentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected
            ? strokeWidth + (3.0 * progress)
            : strokeWidth
        ..strokeCap = StrokeCap.butt;
      if (isSelected) {
        final glowPaint = Paint()
          ..color = segmentColor.withValues(alpha: 0.18 * progress)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth + (10.0 * progress)
          ..strokeCap = StrokeCap.butt
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
        canvas.drawArc(segmentRect, startAngle, sweepAngle, false, glowPaint);
      }
      canvas.drawArc(segmentRect, startAngle, sweepAngle, false, paint);
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _StorageDonutPainter oldDelegate) {
    return oldDelegate.items != items ||
        oldDelegate.totalBytes != totalBytes ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.selectedKind != selectedKind ||
        oldDelegate.progress != progress;
  }
}
