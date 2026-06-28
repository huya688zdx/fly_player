import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/download_record_tokens.dart';
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
import '../utils/download_record_localizer.dart';

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
    final l10n = AppLocalizations.of(context);
    final overview = await _service.loadOverview(l10n);
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
        final l10n = AppLocalizations.of(context);
        final message = switch (result.code) {
          'playback_active' => l10n.storagePlaybackActiveMessage,
          _ => l10n.storageClearFailedMessage,
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
    final l10n = AppLocalizations.of(context);
    final confirmed = await _confirmDialog(
      title: l10n.storageClearSelectedCacheTitle,
      message: l10n.storageClearSelectedCacheMessage,
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
          'playback_active' => l10n.storagePlaybackActiveMessage,
          'empty_selection' => l10n.storageEmptyPlaybackSelection,
          _ => l10n.storageClearFailedMessage,
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
        message: l10n.storageSelectedPlaybackCleared,
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
    final l10n = AppLocalizations.of(context);
    final confirmed = await _confirmDialog(
      title: l10n.storageClearSelectedDownloadsTitle,
      message: l10n.storageClearSelectedDownloadsMessage,
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
          'empty_selection' => l10n.storageEmptyDownloadSelection,
          _ => l10n.storageClearFailedMessage,
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
        message: l10n.storageSelectedDownloadsCleared,
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
        .split(' · ')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    for (final segment in segments.reversed) {
      if (RegExp(r'\d{3,4}|4k', caseSensitive: false).hasMatch(segment)) {
        return segment;
      }
    }
    return AppLocalizations.of(context).storageCacheResolutionFallback;
  }

  String _playbackEntryTitle(PlaybackCacheEntry entry) {
    final title = entry.title.trim();
    if (title.isNotEmpty) return title;
    final seriesTitle = entry.seriesTitle.trim();
    if (seriesTitle.isNotEmpty) return seriesTitle;
    return AppLocalizations.of(context).storageCacheVideoFallback;
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
      return AppLocalizations.of(
        context,
      ).storageSeasonGroupTitle(seriesTitle, entry.seasonNumber);
    }
    if (entry.episodeNumber > 0) {
      return AppLocalizations.of(context).storageSpecialGroupTitle(seriesTitle);
    }
    return seriesTitle;
  }

  String _playbackPromoteSummaryMessage({
    required int convertedCount,
    required int existingCount,
    required int unavailableCount,
  }) {
    final parts = <String>[];
    final l10n = AppLocalizations.of(context);
    if (convertedCount > 0) {
      parts.add(l10n.storagePromoteConverted(convertedCount));
    }
    if (existingCount > 0) {
      parts.add(l10n.storagePromoteExisting(existingCount));
    }
    if (unavailableCount > 0) {
      parts.add(l10n.storagePromoteUnavailable(unavailableCount));
    }
    if (parts.isEmpty) {
      return l10n.storageNoConvertibleCache;
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
              child: Text(AppLocalizations.of(context).commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(AppLocalizations.of(context).commonConfirm),
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
    final l10n = AppLocalizations.of(context);
    final overview = _overview;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: buildSecondaryHostAppBar(
        context,
        title: Text(l10n.storageTitle),
        actions: <Widget>[
          IconButton(
            onPressed: _working ? null : _loadOverview,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: l10n.storageRefreshTooltip,
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
                      title: l10n.storageClearItemTitle(item.title),
                      message: l10n.storageClearItemMessage(item.title),
                    );
                    if (confirmed != true || !mounted) return;
                    await _runSystemAction(
                      action,
                      successMessage: l10n.storageClearItemSuccess(item.title),
                      restrictedMessage: l10n.storageClearItemRestricted(
                        item.title,
                      ),
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
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          backgroundColor: colors.backgroundElevated,
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.commonConfirm),
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
      final l10n = AppLocalizations.of(context);
      _topTip.show(
        context,
        message: l10n.storageActionCompleted(title),
        color: context.appColors.success,
      );
    } catch (_) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      _topTip.show(
        context,
        message: l10n.storageActionFailed(title),
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
    final l10n = AppLocalizations.of(context);
    final overview = widget.overview;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: buildSecondaryHostAppBar(
        context,
        title: Text(l10n.storageAppDataDangerTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.storageAppDataTitle,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.storageAppDataDescription,
                  style: TextStyle(color: colors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 14),
                _DangerActionRow(
                  title: l10n.storageClearBookmarksTitle,
                  subtitle: l10n.storageClearBookmarksSubtitle,
                  trailing: widget.formatBytes(overview.bookmarksBytes),
                  busy: _working,
                  onTap: () => _runDangerAction(
                    title: l10n.storageClearBookmarksTitle,
                    message: l10n.storageClearBookmarksMessage,
                    onConfirmed: _service.clearBookmarks,
                  ),
                ),
                const Divider(height: 24),
                _DangerActionRow(
                  title: l10n.storageClearSavedThemesTitle,
                  subtitle: l10n.storageClearSavedThemesSubtitle,
                  trailing: widget.formatBytes(overview.savedThemesBytes),
                  busy: _working,
                  onTap: () => _runDangerAction(
                    title: l10n.storageClearSavedThemesTitle,
                    message: l10n.storageClearSavedThemesMessage,
                    onConfirmed: () => _service.clearSavedThemes(
                      context.read<AppThemeProvider>(),
                    ),
                  ),
                ),
                const Divider(height: 24),
                _DangerActionRow(
                  title: l10n.storageClearDynamicThemeTitle,
                  subtitle: l10n.storageClearDynamicThemeSubtitle,
                  trailing: widget.formatBytes(overview.dynamicThemeCacheBytes),
                  busy: _working,
                  onTap: () => _runDangerAction(
                    title: l10n.storageClearDynamicThemeTitle,
                    message: l10n.storageClearDynamicThemeMessage,
                    onConfirmed: _service.clearDynamicThemeSeedCache,
                  ),
                ),
                const Divider(height: 24),
                _DangerActionRow(
                  title: l10n.storageClearDanmakuSourcesTitle,
                  subtitle: l10n.storageClearDanmakuSourcesSubtitle,
                  trailing: widget.formatBytes(
                    overview.danmakuSourcesBytes + overview.danmakuCacheBytes,
                  ),
                  busy: _working,
                  onTap: () => _runDangerAction(
                    title: l10n.storageClearDanmakuSourcesTitle,
                    message: l10n.storageClearDanmakuSourcesMessage,
                    onConfirmed: _service.clearDanmakuSources,
                  ),
                ),
                const Divider(height: 24),
                _DangerActionRow(
                  title: l10n.storageClearLoginHistoryTitle,
                  subtitle: l10n.storageClearLoginHistorySubtitle,
                  trailing: widget.formatBytes(overview.loginHistoryBytes),
                  busy: _working,
                  onTap: () => _runDangerAction(
                    title: l10n.storageClearLoginHistoryTitle,
                    message: l10n.storageClearLoginHistoryMessage,
                    onConfirmed: _service.clearLoginHistory,
                  ),
                ),
                const Divider(height: 24),
                _DangerActionRow(
                  title: l10n.storageResetSettingsTitle,
                  subtitle: l10n.storageResetSettingsSubtitle,
                  trailing: widget.formatBytes(overview.otherSettingsBytes),
                  busy: _working,
                  onTap: () => _runDangerAction(
                    title: l10n.storageResetSettingsTitle,
                    message: l10n.storageResetSettingsMessage,
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
    final l10n = AppLocalizations.of(context);
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
                  l10n.storageTotalUsage,
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
                  l10n.storageLastRefreshed('$hh:$mm'),
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
    final l10n = AppLocalizations.of(context);
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
                              selectedItem?.title ?? l10n.storageTotal,
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
                    l10n.storageNoUsageData,
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
                l10n.storageUsageCategory,
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
    final l10n = AppLocalizations.of(context);
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.storageCategoryDetails,
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
                    ].join(' · '),
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

const int _storageEntryPageSize = 8;

class _ParsedStorageSeason {
  final String seriesTitle;
  final String seasonLabel;
  final int seasonSort;

  const _ParsedStorageSeason({
    required this.seriesTitle,
    required this.seasonLabel,
    required this.seasonSort,
  });
}

class _StorageSeriesGroup<T> {
  final String id;
  final String title;
  final int bytes;
  final int latestAtMs;
  final List<_StorageSeasonGroup<T>> seasons;

  const _StorageSeriesGroup({
    required this.id,
    required this.title,
    required this.bytes,
    required this.latestAtMs,
    required this.seasons,
  });

  int get entryCount =>
      seasons.fold<int>(0, (sum, season) => sum + season.entries.length);

  Iterable<T> get entries sync* {
    for (final season in seasons) {
      yield* season.entries;
    }
  }
}

class _StorageSeasonGroup<T> {
  final String id;
  final String title;
  final int bytes;
  final int latestAtMs;
  final int sortIndex;
  final List<T> entries;

  const _StorageSeasonGroup({
    required this.id,
    required this.title,
    required this.bytes,
    required this.latestAtMs,
    required this.sortIndex,
    required this.entries,
  });
}

class _MutableStorageSeriesGroup<T> {
  final String id;
  final String title;
  final Map<String, _MutableStorageSeasonGroup<T>> seasons =
      <String, _MutableStorageSeasonGroup<T>>{};

  _MutableStorageSeriesGroup({required this.id, required this.title});
}

class _MutableStorageSeasonGroup<T> {
  final String id;
  final String title;
  final int sortIndex;
  final List<T> entries = <T>[];

  _MutableStorageSeasonGroup({
    required this.id,
    required this.title,
    required this.sortIndex,
  });
}

class _GroupedStorageTree<T> extends StatelessWidget {
  final List<_StorageSeriesGroup<T>> groups;
  final String Function(int bytes) formatBytes;
  final bool busy;
  final bool Function(T entry) selectable;
  final bool Function(T entry) selected;
  final void Function(T entry, bool selected) onToggleSelected;
  final String Function(T entry) entryTitle;
  final String Function(T entry) entrySubtitle;
  final String Function(T entry) entryTrailing;
  final int maxSubtitleLines;

  const _GroupedStorageTree({
    required this.groups,
    required this.formatBytes,
    required this.busy,
    required this.selectable,
    required this.selected,
    required this.onToggleSelected,
    required this.entryTitle,
    required this.entrySubtitle,
    required this.entryTrailing,
    this.maxSubtitleLines = 2,
  });

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) return const SizedBox.shrink();
    final pageCount = math.max(
      1,
      (groups.length / _storageEntryPageSize).ceil(),
    );
    return DefaultTabController(
      key: ValueKey<int>(pageCount),
      length: pageCount,
      child: Column(
        children: <Widget>[
          if (pageCount > 1) ...<Widget>[
            _StoragePageTabs(pageCount: pageCount, totalCount: groups.length),
            const SizedBox(height: 8),
          ],
          Builder(
            builder: (context) {
              final controller = DefaultTabController.of(context);
              return AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  final pageIndex = controller.index.clamp(0, pageCount - 1);
                  final pageGroups = groups
                      .skip(pageIndex * _storageEntryPageSize)
                      .take(_storageEntryPageSize)
                      .toList(growable: false);
                  return Column(
                    children: <Widget>[
                      for (final group in pageGroups)
                        _seriesTile(context, group),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _seriesTile(BuildContext context, _StorageSeriesGroup<T> group) {
    final colors = context.appColors;
    final selectionValue = _selectionValue(group.entries);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey<String>('storage-series-${group.id}'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        leading: Checkbox(
          tristate: true,
          value: selectionValue,
          onChanged: busy ? null : (_) => _toggleEntries(group.entries),
        ),
        title: Text(
          group.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          AppLocalizations.of(context).storageSeriesGroupSubtitle(
            group.seasons.length,
            group.entryCount,
            formatBytes(group.bytes),
            _formatStorageTimeMs(group.latestAtMs),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.textMuted, fontSize: 11),
        ),
        children: <Widget>[
          for (final season in group.seasons) _seasonTile(context, season),
        ],
      ),
    );
  }

  Widget _seasonTile(BuildContext context, _StorageSeasonGroup<T> season) {
    final colors = context.appColors;
    final selectionValue = _selectionValue(season.entries);
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey<String>('storage-season-${season.id}'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          leading: Checkbox(
            tristate: true,
            value: selectionValue,
            onChanged: busy ? null : (_) => _toggleEntries(season.entries),
          ),
          title: Text(
            season.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            AppLocalizations.of(context).storageSeasonGroupSubtitle(
              season.entries.length,
              formatBytes(season.bytes),
              _formatStorageTimeMs(season.latestAtMs),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textMuted, fontSize: 11),
          ),
          children: <Widget>[
            for (final entry in season.entries) _entryTile(entry),
          ],
        ),
      ),
    );
  }

  Widget _entryTile(T entry) {
    return Padding(
      padding: const EdgeInsets.only(left: 32),
      child: CheckboxListTile(
        value: selected(entry),
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        onChanged: busy || !selectable(entry)
            ? null
            : (value) => onToggleSelected(entry, value ?? false),
        title: Text(
          entryTitle(entry),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          entrySubtitle(entry),
          maxLines: maxSubtitleLines,
          overflow: TextOverflow.ellipsis,
        ),
        secondary: Text(
          entryTrailing(entry),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  bool? _selectionValue(Iterable<T> entries) {
    final selectableEntries = entries.where(selectable).toList(growable: false);
    if (selectableEntries.isEmpty) return false;
    final selectedCount = selectableEntries.where(selected).length;
    if (selectedCount == 0) return false;
    if (selectedCount == selectableEntries.length) return true;
    return null;
  }

  void _toggleEntries(Iterable<T> entries) {
    final selectableEntries = entries.where(selectable).toList(growable: false);
    final nextSelected = _selectionValue(selectableEntries) != true;
    for (final entry in selectableEntries) {
      onToggleSelected(entry, nextSelected);
    }
  }
}

class _StoragePageTabs extends StatelessWidget {
  final int pageCount;
  final int totalCount;

  const _StoragePageTabs({required this.pageCount, required this.totalCount});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            AppLocalizations.of(
              context,
            ).storageGroupedPageSummary(totalCount, _storageEntryPageSize),
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: colors.textPrimary,
            unselectedLabelColor: colors.textMuted,
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            tabs: <Widget>[
              for (var i = 0; i < pageCount; i++) Tab(text: '${i + 1}'),
            ],
          ),
        ],
      ),
    );
  }
}

List<_StorageSeriesGroup<PlaybackCacheEntry>> _buildPlaybackGroups(
  List<PlaybackCacheEntry> entries,
  AppLocalizations l10n,
) {
  final seriesMap = <String, _MutableStorageSeriesGroup<PlaybackCacheEntry>>{};
  for (final entry in entries) {
    final seriesTitle = _cleanStorageLabel(entry.seriesTitle).isNotEmpty
        ? _cleanStorageLabel(entry.seriesTitle)
        : _cleanStorageLabel(entry.title).isNotEmpty
        ? _cleanStorageLabel(entry.title)
        : l10n.storageUnknownWork;
    final seasonLabel = entry.seasonNumber > 0
        ? l10n.storageSeasonNumberSpaced(entry.seasonNumber)
        : l10n.storageUngroupedSeason;
    final seasonSort = entry.seasonNumber > 0 ? entry.seasonNumber : 999999;
    final seriesId = _storageStableId('playback-series', seriesTitle);
    final series = seriesMap.putIfAbsent(
      seriesId,
      () => _MutableStorageSeriesGroup<PlaybackCacheEntry>(
        id: seriesId,
        title: seriesTitle,
      ),
    );
    final seasonId = _storageStableId(seriesId, seasonLabel);
    final season = series.seasons.putIfAbsent(
      seasonId,
      () => _MutableStorageSeasonGroup<PlaybackCacheEntry>(
        id: seasonId,
        title: seasonLabel,
        sortIndex: seasonSort,
      ),
    );
    season.entries.add(entry);
  }
  return _finalizeStorageGroups<PlaybackCacheEntry>(
    seriesMap.values,
    bytesOf: (entry) => entry.bytes,
    latestMsOf: (entry) => entry.lastAccessAt.millisecondsSinceEpoch,
    compareEntries: (left, right) {
      final episodeCompare = _playbackEpisodeSort(
        left,
      ).compareTo(_playbackEpisodeSort(right));
      if (episodeCompare != 0) return episodeCompare;
      return right.lastAccessAt.compareTo(left.lastAccessAt);
    },
  );
}

List<_StorageSeriesGroup<DownloadTaskRecord>> _buildDownloadGroups(
  List<DownloadTaskRecord> entries,
  AppLocalizations l10n,
) {
  final seriesMap = <String, _MutableStorageSeriesGroup<DownloadTaskRecord>>{};
  for (final entry in entries) {
    final parsed = _downloadSeriesSeason(entry, l10n);
    final seriesId = _storageStableId('download-series', parsed.seriesTitle);
    final series = seriesMap.putIfAbsent(
      seriesId,
      () => _MutableStorageSeriesGroup<DownloadTaskRecord>(
        id: seriesId,
        title: parsed.seriesTitle,
      ),
    );
    final seasonId = _storageStableId(seriesId, parsed.seasonLabel);
    final season = series.seasons.putIfAbsent(
      seasonId,
      () => _MutableStorageSeasonGroup<DownloadTaskRecord>(
        id: seasonId,
        title: parsed.seasonLabel,
        sortIndex: parsed.seasonSort,
      ),
    );
    season.entries.add(entry);
  }
  return _finalizeStorageGroups<DownloadTaskRecord>(
    seriesMap.values,
    bytesOf: (entry) => entry.totalBytes,
    latestMsOf: (entry) => entry.updatedAtMs,
    compareEntries: (left, right) {
      final episodeCompare = _downloadEpisodeSort(
        left,
      ).compareTo(_downloadEpisodeSort(right));
      if (episodeCompare != 0) return episodeCompare;
      return right.updatedAtMs.compareTo(left.updatedAtMs);
    },
  );
}

List<_StorageSeriesGroup<T>> _finalizeStorageGroups<T>(
  Iterable<_MutableStorageSeriesGroup<T>> mutableGroups, {
  required int Function(T entry) bytesOf,
  required int Function(T entry) latestMsOf,
  required int Function(T left, T right) compareEntries,
}) {
  final groups = mutableGroups
      .map((series) {
        final seasons =
            series.seasons.values
                .map((season) {
                  season.entries.sort(compareEntries);
                  final bytes = season.entries.fold<int>(
                    0,
                    (sum, entry) => sum + bytesOf(entry),
                  );
                  final latestAtMs = season.entries.fold<int>(
                    0,
                    (latest, entry) => math.max(latest, latestMsOf(entry)),
                  );
                  return _StorageSeasonGroup<T>(
                    id: season.id,
                    title: season.title,
                    bytes: bytes,
                    latestAtMs: latestAtMs,
                    sortIndex: season.sortIndex,
                    entries: List<T>.unmodifiable(season.entries),
                  );
                })
                .toList(growable: false)
              ..sort((left, right) {
                final sortCompare = left.sortIndex.compareTo(right.sortIndex);
                if (sortCompare != 0) return sortCompare;
                return right.latestAtMs.compareTo(left.latestAtMs);
              });
        final bytes = seasons.fold<int>(0, (sum, season) => sum + season.bytes);
        final latestAtMs = seasons.fold<int>(
          0,
          (latest, season) => math.max(latest, season.latestAtMs),
        );
        return _StorageSeriesGroup<T>(
          id: series.id,
          title: series.title,
          bytes: bytes,
          latestAtMs: latestAtMs,
          seasons: seasons,
        );
      })
      .toList(growable: false);
  groups.sort((left, right) => right.latestAtMs.compareTo(left.latestAtMs));
  return groups;
}

_ParsedStorageSeason _downloadSeriesSeason(
  DownloadTaskRecord entry,
  AppLocalizations l10n,
) {
  final candidates =
      <String>[entry.groupTitle, _parentFolderName(entry.filePath)]
          .map(_cleanStorageLabel)
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
  for (final candidate in candidates) {
    final parsed = _parseSeriesSeasonLabel(candidate, l10n);
    if (parsed.seriesTitle.trim().isNotEmpty) return parsed;
  }
  final fallbackTitle = _cleanStorageLabel(entry.title).isNotEmpty
      ? _cleanStorageLabel(entry.title)
      : l10n.storageUnknownWork;
  return _ParsedStorageSeason(
    seriesTitle: fallbackTitle,
    seasonLabel: l10n.storageUngroupedSeason,
    seasonSort: 999999,
  );
}

_ParsedStorageSeason _parseSeriesSeasonLabel(
  String rawLabel,
  AppLocalizations l10n,
) {
  final label = _cleanStorageLabel(rawLabel);
  if (label.isEmpty) {
    return _ParsedStorageSeason(
      seriesTitle: l10n.storageUnknownWork,
      seasonLabel: l10n.storageUngroupedSeason,
      seasonSort: 999999,
    );
  }
  final downloadSeasonTokenPattern = RegExp(
    '^(.*?)\\s*${RegExp.escape(downloadSeasonLabelTokenPrefix)}(\\d+)\$',
  );
  final downloadSeasonTokenMatch = downloadSeasonTokenPattern.firstMatch(label);
  if (downloadSeasonTokenMatch != null) {
    final series = _cleanStorageLabel(downloadSeasonTokenMatch.group(1) ?? '');
    final season = int.tryParse(downloadSeasonTokenMatch.group(2) ?? '') ?? 0;
    if (series.isNotEmpty && season > 0) {
      return _ParsedStorageSeason(
        seriesTitle: series,
        seasonLabel: l10n.storageSeasonNumberSpaced(season),
        seasonSort: season,
      );
    }
  }
  final patterns = <RegExp>[
    RegExp(r'^(.*?)\s+Season\s*-?\s*(\d+)$', caseSensitive: false),
    RegExp(r'^(.*?)\s+S(\d+)$', caseSensitive: false),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(label);
    if (match == null) continue;
    final series = _cleanStorageLabel(match.group(1) ?? '');
    final season = int.tryParse(match.group(2) ?? '') ?? 0;
    if (series.isEmpty || season <= 0) continue;
    return _ParsedStorageSeason(
      seriesTitle: series,
      seasonLabel: l10n.storageSeasonNumberSpaced(season),
      seasonSort: season,
    );
  }
  if (label.toLowerCase().contains('special')) {
    final series = _cleanStorageLabel(
      label.replaceAll(RegExp('specials?', caseSensitive: false), ''),
    );
    return _ParsedStorageSeason(
      seriesTitle: series.isEmpty ? label : series,
      seasonLabel: l10n.bookmarkManagerSpecialSeason,
      seasonSort: 0,
    );
  }
  return _ParsedStorageSeason(
    seriesTitle: label,
    seasonLabel: l10n.storageUngroupedSeason,
    seasonSort: 999999,
  );
}

String _playbackEpisodeTitle(PlaybackCacheEntry entry, AppLocalizations l10n) {
  final title = _cleanStorageLabel(entry.title);
  if (entry.episodeNumber > 0) {
    return l10n
        .storageEpisodeTitleWithNumber(entry.episodeNumber, title)
        .trim();
  }
  return title.isEmpty ? l10n.storageUnknownEpisode : title;
}

String _downloadEpisodeTitle(DownloadTaskRecord entry, AppLocalizations l10n) {
  final title = _cleanStorageLabel(entry.title);
  if (title.isNotEmpty) return title;
  final fileName = _cleanStorageLabel(entry.fileName);
  return fileName.isEmpty ? l10n.storageUnknownEpisode : fileName;
}

int _playbackEpisodeSort(PlaybackCacheEntry entry) {
  if (entry.episodeNumber > 0) return entry.episodeNumber;
  return _episodeNumberFromText(entry.title) ?? 999999;
}

int _downloadEpisodeSort(DownloadTaskRecord entry) {
  return _episodeNumberFromText(entry.title) ??
      _episodeNumberFromText(entry.fileName) ??
      999999;
}

int? _episodeNumberFromText(String raw) {
  final text = _cleanStorageLabel(raw);
  if (text.isEmpty) return null;
  final patterns = <RegExp>[
    RegExp(r'\bE(\d{1,4})\b', caseSensitive: false),
    RegExp(r'\b(\d{1,4})\b'),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(text);
    final value = int.tryParse(match?.group(1) ?? '');
    if (value != null && value > 0) return value;
  }
  return null;
}

String _parentFolderName(String filePath) {
  final normalized = filePath.replaceAll('\\', '/');
  final parts = normalized
      .split('/')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.length < 2) return '';
  return parts[parts.length - 2];
}

String _storageStableId(String prefix, String value) {
  return '$prefix:${_cleanStorageLabel(value).toLowerCase()}';
}

String _cleanStorageLabel(String raw) {
  return raw.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _formatStorageTimeMs(int updatedAtMs) {
  if (updatedAtMs <= 0) return '-';
  final dateTime = DateTime.fromMillisecondsSinceEpoch(updatedAtMs);
  final hh = dateTime.hour.toString().padLeft(2, '0');
  final mm = dateTime.minute.toString().padLeft(2, '0');
  return '${dateTime.month}/${dateTime.day} $hh:$mm';
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
    final l10n = AppLocalizations.of(context);
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
    final groups = _buildPlaybackGroups(entries, l10n);
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
            title: l10n.storagePlaybackFiles,
            primaryAction: TextButton(
              onPressed: loading || busy || selectableEntries.isEmpty
                  ? null
                  : () => onToggleSelectAll(!allSelected),
              child: Text(
                allSelected ? l10n.commonDeselectAll : l10n.commonSelectAll,
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
                    l10n.storagePromoteSelected(promotableSelectedCount),
                  ),
                ),
                FilledButton.tonal(
                  onPressed: busy || selectedKeys.isEmpty
                      ? null
                      : onClearSelected,
                  child: Text(l10n.storageClearSelected(selectedKeys.length)),
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
                l10n.storageNoPlaybackCache,
                style: TextStyle(color: colors.textMuted, fontSize: 13),
              ),
            )
          else if (groups.isNotEmpty)
            _GroupedStorageTree<PlaybackCacheEntry>(
              groups: groups,
              formatBytes: formatBytes,
              busy: busy,
              selectable: (entry) => entry.bytes > 0,
              selected: (entry) => selectedKeys.contains(entry.resourceKey),
              onToggleSelected: (entry, selected) =>
                  onToggleSelected(entry.resourceKey, selected),
              entryTitle: (entry) => _playbackEpisodeTitle(entry, l10n),
              entrySubtitle: (entry) => [
                if (entry.subtitle.trim().isNotEmpty) entry.subtitle.trim(),
                if (entry.resolution.trim().isNotEmpty) entry.resolution.trim(),
                entry.complete
                    ? l10n.storageCompleteCache
                    : l10n.storageIncompleteCache,
                _formatAccessTime(entry.lastAccessAt),
              ].join(' · '),
              entryTrailing: (entry) => formatBytes(entry.bytes),
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
                    entry.complete
                        ? l10n.storageCompletedCache
                        : l10n.storageIncompleteCache,
                    _formatAccessTime(entry.lastAccessAt),
                  ].join(' · '),
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
    final l10n = AppLocalizations.of(context);
    final selectableEntries = entries
        .where((entry) => entry.filePath.trim().isNotEmpty)
        .toList(growable: false);
    final allSelected =
        selectableEntries.isNotEmpty &&
        selectableEntries.every((entry) => selectedIds.contains(entry.id));
    final groups = _buildDownloadGroups(entries, l10n);
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
            title: l10n.storageDownloadFiles,
            primaryAction: TextButton(
              onPressed: loading || busy || selectableEntries.isEmpty
                  ? null
                  : () => onToggleSelectAll(!allSelected),
              child: Text(
                allSelected ? l10n.commonDeselectAll : l10n.commonSelectAll,
              ),
            ),
            secondaryAction: FilledButton.tonal(
              onPressed: busy || selectedIds.isEmpty ? null : onClearSelected,
              child: Text(l10n.storageClearSelected(selectedIds.length)),
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
                l10n.storageNoDownloadFiles,
                style: TextStyle(color: colors.textMuted, fontSize: 13),
              ),
            )
          else if (groups.isNotEmpty)
            _GroupedStorageTree<DownloadTaskRecord>(
              groups: groups,
              formatBytes: formatBytes,
              busy: busy,
              selectable: (entry) => entry.filePath.trim().isNotEmpty,
              selected: (entry) => selectedIds.contains(entry.id),
              onToggleSelected: (entry, selected) =>
                  onToggleSelected(entry.id, selected),
              entryTitle: (entry) => _downloadEpisodeTitle(entry, l10n),
              entrySubtitle: (entry) => [
                if (entry.resolution.trim().isNotEmpty)
                  localizeDownloadResolution(entry.resolution, l10n),
                if (entry.durationText.trim().isNotEmpty)
                  localizeDownloadDurationText(entry.durationText, l10n),
                _formatUpdatedTime(entry.updatedAtMs),
                entry.filePath,
              ].join(' · '),
              entryTrailing: (entry) => formatBytes(entry.totalBytes),
              maxSubtitleLines: 3,
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
                    if (entry.resolution.trim().isNotEmpty)
                      localizeDownloadResolution(entry.resolution, l10n),
                    if (entry.durationText.trim().isNotEmpty)
                      localizeDownloadDurationText(entry.durationText, l10n),
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
    final l10n = AppLocalizations.of(context);
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
                      l10n.storageEnterManagement,
                    ].join(' · '),
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
    final l10n = AppLocalizations.of(context);
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
                  if (item.isEstimated) l10n.storageEstimated,
                  if (item.isRestricted) l10n.storageRestricted,
                ].join(' · '),
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
            child: Text(l10n.commonClear),
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
        TextButton(
          onPressed: busy ? null : onTap,
          child: Text(AppLocalizations.of(context).commonClear),
        ),
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
