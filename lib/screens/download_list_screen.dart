import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/download_task_record.dart';
import '../models/play_info.dart';
import '../models/playback_stream.dart';
import '../models/stream_track_data.dart';
import '../player/controllers/mpv_player_controller.dart';
import '../player/mpv_player_page.dart';
import '../providers/nas_provider.dart';
import '../services/embedded_detail_launcher.dart';
import '../services/download_task_service.dart';
import '../services/play_stats/play_stats.dart';
import '../theme/app_theme.dart';
import '../ui/app_transitions.dart';
import '../ui/capability_badge_mapper.dart';
import '../ui/media_detail_components.dart';
import '../utils/async_action_guard.dart';
import '../utils/app_top_tip.dart';
import '../utils/play_detail_track_selector.dart';
import '../utils/player_artwork_path_resolver.dart';
import '../utils/playback_resume_position_resolver.dart';
import '../utils/player_title_formatter.dart';

enum DownloadListTab { downloaded, downloading }

extension DownloadListTabX on DownloadListTab {
  String get routeValue => switch (this) {
    DownloadListTab.downloaded => 'downloaded',
    DownloadListTab.downloading => 'downloading',
  };

  DownloadTaskStatus get status => switch (this) {
    DownloadListTab.downloaded => DownloadTaskStatus.downloaded,
    DownloadListTab.downloading => DownloadTaskStatus.downloading,
  };

  String emptyLabel(AppLocalizations l10n) => switch (this) {
    DownloadListTab.downloaded => l10n.downloadEmptyDownloaded,
    DownloadListTab.downloading => l10n.downloadEmptyDownloading,
  };

  static DownloadListTab fromRouteValue(String raw) {
    return DownloadListTab.values.firstWhere(
      (value) => value.routeValue == raw,
      orElse: () => DownloadListTab.downloaded,
    );
  }
}

class DownloadListScreen extends StatefulWidget {
  final DownloadListTab initialTab;

  const DownloadListScreen({
    super.key,
    this.initialTab = DownloadListTab.downloaded,
  });

  @override
  State<DownloadListScreen> createState() => _DownloadListScreenState();
}

class _DownloadListScreenState extends State<DownloadListScreen> {
  final DownloadTaskService _service = DownloadTaskService.instance;
  final AppTopTip _topTip = AppTopTip();
  late DownloadListTab _selectedTab = widget.initialTab;
  late final PageController _pageController = PageController(
    initialPage: _selectedTab.index,
  );
  final Set<String> _selectedGroupIds = <String>{};
  bool _editing = false;
  bool _recoveringDownloads = false;

  @override
  void initState() {
    super.initState();
    _service.initialize();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _service.refreshDownloadedGroupMetadata(context.read<NasProvider>());
    });
  }

  @override
  void dispose() {
    _topTip.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _handleGroupLongPress(String groupId) async {
    if (_selectedTab != DownloadListTab.downloaded) return;
    await HapticFeedback.mediumImpact();
    if (!mounted) return;
    setState(() {
      _editing = true;
      _selectedGroupIds.add(groupId);
    });
  }

  void _resetEditingState() {
    _editing = false;
    _selectedGroupIds.clear();
  }

  Future<void> _handleRecoverDownloadedFiles() async {
    if (_recoveringDownloads) return;
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final provider = context.read<NasProvider>();
    setState(() => _recoveringDownloads = true);
    try {
      final result = await _service.recoverDownloadedFiles(provider: provider);
      if (!mounted) return;
      final importedCount = result.importedCount;
      if (importedCount > 0) {
        _topTip.show(
          context,
          message: l10n.downloadImportedLocalVideos(importedCount),
          color: colors.success,
        );
      } else if (result.scannedVideoCount > 0 ||
          result.alreadyTrackedCount > 0) {
        _topTip.show(
          context,
          message: l10n.downloadNoImportableVideos,
          color: colors.warning,
        );
      } else {
        _topTip.show(
          context,
          message: l10n.downloadNoRecoverableFiles,
          color: colors.warning,
        );
      }
    } catch (_) {
      if (!mounted) return;
      _topTip.show(
        context,
        message: l10n.downloadRefreshFilesFailed,
        color: colors.warning,
      );
    } finally {
      if (mounted) {
        setState(() => _recoveringDownloads = false);
      }
    }
  }

  Future<void> _switchTab(DownloadListTab tab, {bool animate = true}) async {
    if (_selectedTab == tab) return;
    if (!mounted) return;
    setState(() {
      _selectedTab = tab;
      _resetEditingState();
    });
    if (animate) {
      await _pageController.animateToPage(
        tab.index,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else if (_pageController.hasClients) {
      _pageController.jumpToPage(tab.index);
    }
  }

  void _handlePageChanged(int index) {
    final nextTab = DownloadListTab.values[index];
    if (_selectedTab == nextTab) return;
    if (!mounted) return;
    setState(() {
      _selectedTab = nextTab;
      _resetEditingState();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final token = context.watch<NasProvider>().token;

    return Scaffold(
      backgroundColor: colors.backgroundBase,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 14, 0),
              child: Row(
                children: <Widget>[
                  _TopActionButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: () {
                      unawaited(EmbeddedDetailLauncher.closeHostOrPop(context));
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Center(
                      child: _DownloadTabSwitcher(
                        selectedTab: _selectedTab,
                        onChanged: (tab) => unawaited(_switchTab(tab)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _TopActionButton(
                    icon: Icons.refresh_rounded,
                    tooltip: l10n.downloadRefreshFilesTooltip,
                    busy: _recoveringDownloads,
                    onTap: _recoveringDownloads
                        ? null
                        : () => unawaited(_handleRecoverDownloadedFiles()),
                  ),
                  const SizedBox(width: 4),
                  AnimatedBuilder(
                    animation: _service,
                    builder: (context, _) {
                      final canEdit =
                          _selectedTab == DownloadListTab.downloaded &&
                          _service
                              .groupsByStatus(DownloadTaskStatus.downloaded)
                              .isNotEmpty;
                      return TextButton(
                        onPressed: !canEdit
                            ? null
                            : () {
                                setState(() {
                                  _editing = !_editing;
                                  if (!_editing) {
                                    _selectedGroupIds.clear();
                                  }
                                });
                              },
                        style: TextButton.styleFrom(
                          foregroundColor: _editing
                              ? colors.textPrimary
                              : colors.textMuted,
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        child: Text(
                          _editing ? l10n.commonCancel : l10n.commonEdit,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedBuilder(
                animation: _service,
                builder: (context, _) {
                  final downloadedGroups = _service.groupsByStatus(
                    DownloadTaskStatus.downloaded,
                  );
                  if (downloadedGroups.isEmpty && _editing) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted || !_editing) return;
                      setState(() {
                        _editing = false;
                        _selectedGroupIds.clear();
                      });
                    });
                  }
                  _selectedGroupIds.removeWhere(
                    (id) => !downloadedGroups.any((group) => group.id == id),
                  );
                  final downloadingRecords = _service.recordsByStatus(
                    DownloadTaskStatus.downloading,
                  );
                  return PageView(
                    controller: _pageController,
                    onPageChanged: _handlePageChanged,
                    physics: const BouncingScrollPhysics(),
                    children: <Widget>[
                      _buildDownloadedPage(
                        context: context,
                        token: token,
                        groups: downloadedGroups,
                      ),
                      _buildDownloadingPage(
                        context: context,
                        token: token,
                        records: downloadingRecords,
                      ),
                    ],
                  );
                },
              ),
            ),
            if (_editing) ...<Widget>[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () {
                          final groups = _service.groupsByStatus(
                            _selectedTab.status,
                          );
                          setState(() {
                            if (_selectedGroupIds.length == groups.length &&
                                groups.isNotEmpty) {
                              _selectedGroupIds.clear();
                            } else {
                              _selectedGroupIds
                                ..clear()
                                ..addAll(groups.map((group) => group.id));
                            }
                          });
                        },
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(58),
                          backgroundColor: colors.surfaceStrong,
                          foregroundColor: colors.textPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: Text(
                          _selectedGroupIds.length ==
                                      _service
                                          .groupsByStatus(_selectedTab.status)
                                          .length &&
                                  _service
                                      .groupsByStatus(_selectedTab.status)
                                      .isNotEmpty
                              ? l10n.commonDeselectAll
                              : l10n.commonSelectAll,
                        ),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: FilledButton(
                        onPressed: _selectedGroupIds.isEmpty
                            ? null
                            : () => _confirmDeleteSelectedGroups(context),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(58),
                          backgroundColor: const Color(0xFF7E0913),
                          disabledBackgroundColor: const Color(
                            0xFF7E0913,
                          ).withValues(alpha: 0.35),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: Text(l10n.commonDelete),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _toggleGroupSelection(String groupId) {
    setState(() {
      if (_selectedGroupIds.contains(groupId)) {
        _selectedGroupIds.remove(groupId);
      } else {
        _selectedGroupIds.add(groupId);
      }
    });
  }

  Future<void> _openDownloadedGroupDetail(DownloadTaskGroup group) async {
    final provider = context.read<NasProvider>();
    final navigator = Navigator.of(context);
    if (provider.isConfigured) {
      final handled = await EmbeddedDetailLauncher.openDownloadDetail(
        context: context,
        groupId: group.id,
        tab: DownloadListTab.downloaded.routeValue,
      );
      if (handled || !mounted) return;
    }
    await navigator.push(
      AppTransitions.leftToRightPageTurnRoute<void>(
        DownloadGroupDetailScreen(
          groupId: group.id,
          initialTab: DownloadListTab.downloaded,
        ),
      ),
    );
  }

  Widget _buildDownloadedPage({
    required BuildContext context,
    required String token,
    required List<DownloadTaskGroup> groups,
  }) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    if (groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const _DownloadEmptyArtwork(),
            const SizedBox(height: 18),
            Text(
              DownloadListTab.downloaded.emptyLabel(l10n),
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      key: const PageStorageKey<String>('downloaded_groups'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      itemCount: groups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final group = groups[index];
        return _DownloadGroupCard(
          key: ValueKey<String>(group.id),
          group: group,
          token: token,
          tab: DownloadListTab.downloaded,
          editing: _editing,
          selected: _selectedGroupIds.contains(group.id),
          onLongPress: () => _handleGroupLongPress(group.id),
          onSelectToggle: _editing
              ? () => _toggleGroupSelection(group.id)
              : null,
          onTap: _editing
              ? () => _toggleGroupSelection(group.id)
              : () => unawaited(_openDownloadedGroupDetail(group)),
        );
      },
    );
  }

  Widget _buildDownloadingPage({
    required BuildContext context,
    required String token,
    required List<DownloadTaskRecord> records,
  }) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    if (records.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const _DownloadEmptyArtwork(),
            const SizedBox(height: 18),
            Text(
              DownloadListTab.downloading.emptyLabel(l10n),
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      key: const PageStorageKey<String>('downloading_records'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      itemCount: records.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final record = records[index];
        return _DownloadRecordRow(
          key: ValueKey<String>(record.id),
          record: record,
          token: token,
          downloadSpeedBytesPerSecond: _service.downloadSpeedBytesPerSecondFor(
            record.id,
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteSelectedGroups(BuildContext context) async {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
            decoration: BoxDecoration(
              color: colors.backgroundElevated,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  l10n.downloadDeleteFilesTitle,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  l10n.downloadDeleteFilesContent,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () => Navigator.of(sheetContext).pop(false),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          backgroundColor: colors.surfaceStrong,
                          foregroundColor: colors.textPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: Text(l10n.commonCancel),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(sheetContext).pop(true),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          backgroundColor: const Color(0xFF7E0913),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: Text(l10n.commonDelete),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (confirmed != true || !mounted) return;
    final groups = _service.groupsByStatus(_selectedTab.status);
    final recordIds = groups
        .where((group) => _selectedGroupIds.contains(group.id))
        .expand((group) => group.records.map((record) => record.id))
        .toSet()
        .toList(growable: false);
    await _service.clearDownloadedRecords(recordIds: recordIds);
    if (!mounted) return;
    setState(() {
      _selectedGroupIds.clear();
      _editing = false;
    });
  }
}

class DownloadGroupDetailScreen extends StatefulWidget {
  final String groupId;
  final DownloadListTab initialTab;

  const DownloadGroupDetailScreen({
    super.key,
    required this.groupId,
    this.initialTab = DownloadListTab.downloaded,
  });

  @override
  State<DownloadGroupDetailScreen> createState() =>
      _DownloadGroupDetailScreenState();
}

class _DownloadGroupDetailScreenState extends State<DownloadGroupDetailScreen> {
  final DownloadTaskService _service = DownloadTaskService.instance;
  final AppTopTip _topTip = AppTopTip();
  late final DownloadListTab _selectedTab = widget.initialTab;
  final Set<String> _selectedRecordIds = <String>{};
  bool _editing = false;
  String? _playLaunchingRecordId;

  @override
  void initState() {
    super.initState();
    _service.initialize();
  }

  @override
  void dispose() {
    _topTip.dispose();
    super.dispose();
  }

  Future<void> _handleRecordLongPress(String recordId) async {
    if (_selectedTab != DownloadListTab.downloaded) return;
    await HapticFeedback.mediumImpact();
    if (!mounted) return;
    setState(() {
      _editing = true;
      _selectedRecordIds.add(recordId);
    });
  }

  Future<void> _playDownloadedRecord(DownloadTaskRecord record) async {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final actionKey = 'download_group_play:${widget.groupId.trim()}';
    if (_playLaunchingRecordId != null ||
        AsyncActionGuard.isRunning(actionKey)) {
      _topTip.show(
        context,
        message: l10n.downloadPreparingPlayback,
        color: colors.warning,
      );
      return;
    }

    setState(() {
      _playLaunchingRecordId = record.id;
    });

    try {
      await AsyncActionGuard.run<void>(
        actionKey,
        settleDuration: const Duration(milliseconds: 500),
        action: () async {
          final navigator = Navigator.of(context);
          final path = record.filePath.trim();
          if (path.isEmpty || !File(path).existsSync()) {
            _topTip.show(
              context,
              message: l10n.downloadLocalFileMissing,
              color: colors.warning,
            );
            return;
          }
          final provider = context.read<NasProvider>();
          final api = FeiniuApi(provider);
          final canUseEmbeddedHost = provider.isConfigured;
          final fallbackTitle = _playerTitleForRecord(record);
          final normalizedItemGuid = record.itemGuid.trim();
          PlayInfoData? initialPlayInfo;
          StreamTrackData? trackData;
          PlaybackStreamData? playbackStream;
          try {
            initialPlayInfo = await api.getPlayInfo(normalizedItemGuid);
          } catch (_) {}
          final resolvedMediaGuid = record.mediaGuid.trim().isNotEmpty
              ? record.mediaGuid.trim()
              : (initialPlayInfo?.mediaGuid.trim().isNotEmpty == true
                    ? initialPlayInfo!.mediaGuid.trim()
                    : normalizedItemGuid);
          try {
            trackData = await api.getStreamTrackData(normalizedItemGuid);
          } catch (_) {}
          try {
            if (resolvedMediaGuid.isNotEmpty) {
              playbackStream = await api.getPlaybackStream(resolvedMediaGuid);
            }
          } catch (_) {}
          final playItem = initialPlayInfo?.item;
          final title = playItem == null
              ? fallbackTitle
              : formatPlayerTitleFromPlayItem(
                  playItem,
                  fallbackTitle: fallbackTitle,
                );
          final trackVideo = resolvedMediaGuid.isEmpty
              ? null
              : trackData?.videoForMedia(resolvedMediaGuid);
          final playbackVideo = playbackStream?.videoStream;
          final mergedQualities = mergePlaybackQualitiesWithStreamTrackData(
            playbackStream?.qualities ?? const <PlaybackQualityOption>[],
            trackData,
          );
          final fallbackAudioTracks = record.audioTracks;
          final audioTracks = playbackStream?.audioStreams.isNotEmpty == true
              ? playbackStream!.audioStreams
              : (resolvedMediaGuid.isEmpty
                    ? fallbackAudioTracks
                    : trackData?.audiosForMedia(resolvedMediaGuid) ??
                          fallbackAudioTracks);
          final selectedAudio = PlayDetailTrackSelector.selectedOrFirstAudio(
            selectedAudioGuid: initialPlayInfo?.audioGuid ?? '',
            audioTracks: audioTracks,
          );
          final fallbackSubtitleTracks = record.subtitleTracks;
          final subtitleTracks =
              playbackStream?.subtitleStreams.isNotEmpty == true
              ? PlayDetailTrackSelector.mergeSubtitleTracks(
                  primaryTracks: playbackStream!.subtitleStreams,
                  extraTracks: resolvedMediaGuid.isEmpty
                      ? fallbackSubtitleTracks
                      : trackData?.subtitlesForMedia(resolvedMediaGuid) ??
                            fallbackSubtitleTracks,
                )
              : (resolvedMediaGuid.isEmpty
                    ? fallbackSubtitleTracks
                    : trackData?.subtitlesForMedia(resolvedMediaGuid) ??
                          fallbackSubtitleTracks);
          final selectedSubtitle =
              PlayDetailTrackSelector.selectedOrFirstSubtitle(
                selectedSubtitleGuid: initialPlayInfo?.subtitleGuid ?? '',
                subtitleTracks: subtitleTracks,
              );
          final embeddedSubtitleTrackIndex =
              PlayDetailTrackSelector.embeddedSubtitleTrackIndex(
                selectedSubtitle: selectedSubtitle,
                subtitleTracks: subtitleTracks,
              );
          final networkDurationSeconds = playItem?.duration ?? 0;
          final watchedSeconds = initialPlayInfo == null
              ? 0
              : (initialPlayInfo.ts > 0
                    ? initialPlayInfo.ts
                    : playItem?.watchedTs ?? 0);
          final networkCompleted =
              initialPlayInfo != null &&
              networkDurationSeconds > 0 &&
              ((networkDurationSeconds - watchedSeconds) <= 0 ||
                  playItem?.isWatched == 1);
          final resume = await PlaybackResumePositionResolver.resolve(
            videoIds: <String>[
              playItem?.guid ?? '',
              normalizedItemGuid,
              record.itemGuid,
              record.id,
            ],
            durationSeconds: networkDurationSeconds,
            networkPositionSeconds: watchedSeconds,
            networkPositionAvailable: initialPlayInfo != null,
            networkCompleted: networkCompleted,
          );
          final durationSeconds = resume.effectiveDurationSeconds;
          final source = MpvMediaSource.localFile(
            filePath: path,
            itemGuid: playItem?.guid.trim().isNotEmpty == true
                ? playItem!.guid.trim()
                : normalizedItemGuid,
            seriesGuid: initialPlayInfo?.grandGuid.trim() ?? '',
            seasonGuid: initialPlayInfo?.parentGuid.trim().isNotEmpty == true
                ? initialPlayInfo!.parentGuid.trim()
                : record.groupId.trim(),
            posterPath: playItem == null
                ? (record.posterUrls.isNotEmpty
                      ? record.posterUrls.first
                      : (record.groupPosterUrls.isNotEmpty
                            ? record.groupPosterUrls.first
                            : ''))
                : resolvePlayerArtworkPathForPlayItem(playItem),
            mediaGuid: resolvedMediaGuid,
            mediaType: playItem?.type ?? '',
            ancestorName: playItem?.ancestorName ?? '',
            videoGuid: trackVideo?.guid.trim().isNotEmpty == true
                ? trackVideo!.guid.trim()
                : (playbackVideo?.guid.trim().isNotEmpty == true
                      ? playbackVideo!.guid.trim()
                      : resolvedMediaGuid),
            title: title,
            seriesTitle: (playItem?.tvTitle ?? '').trim().isNotEmpty
                ? playItem!.tvTitle.trim()
                : record.groupTitle.trim(),
            seasonNumber: playItem?.seasonNumber ?? 0,
            tmdbId: playItem?.trimId ?? '',
            episodeNumber: playItem?.episodeNumber ?? 0,
            startPosition: resume.position,
            audioTrackGuid: selectedAudio?.guid ?? initialPlayInfo?.audioGuid,
            subtitleTrackIndex: embeddedSubtitleTrackIndex,
            subtitleTrackGuid: initialPlayInfo?.subtitleGuid,
            resolution: record.resolution.trim().isNotEmpty
                ? record.resolution.trim()
                : (playbackVideo?.resolutionType.trim().isNotEmpty == true
                      ? playbackVideo!.resolutionType.trim()
                      : trackVideo?.resolutionType ?? ''),
            bitrate: playbackVideo?.bps ?? trackVideo?.bps ?? 0,
            durationSeconds: durationSeconds,
            videoWidth: playbackVideo?.width ?? trackVideo?.width ?? 0,
            videoHeight: playbackVideo?.height ?? trackVideo?.height ?? 0,
            videoCodecName:
                playbackVideo?.codecName ?? trackVideo?.codecName ?? '',
            videoProfile: playbackVideo?.profile ?? trackVideo?.profile ?? '',
            colorSpace:
                playbackVideo?.colorSpace ?? trackVideo?.colorSpace ?? '',
            colorTransfer:
                playbackVideo?.colorTransfer ?? trackVideo?.colorTransfer ?? '',
            colorPrimaries:
                playbackVideo?.colorPrimaries ??
                trackVideo?.colorPrimaries ??
                '',
            bitDepth: playbackVideo?.bitDepth ?? trackVideo?.bitDepth ?? 0,
            audioTracks: audioTracks,
            subtitleTracks: subtitleTracks,
            qualities: mergedQualities,
            playbackSpeed: 1.0,
          );

          if (!mounted) return;
          if (canUseEmbeddedHost) {
            final embeddedResult =
                await EmbeddedDetailLauncher.openFullscreenPlayer(
                  context: context,
                  title: title,
                  source: source,
                  initialPlayInfo: initialPlayInfo,
                  startSource: PlayStartSource.manual,
                );
            if (embeddedResult.handled || !mounted) return;
          }
          await navigator.push(
            AppTransitions.playerRoute(
              MpvPlayerPage(
                title: title,
                source: source,
                initialPlayInfo: initialPlayInfo,
                startSource: PlayStartSource.manual,
              ),
            ),
          );
        },
      );
    } finally {
      if (!mounted) {
        _playLaunchingRecordId = null;
      } else if (_playLaunchingRecordId == record.id) {
        setState(() {
          _playLaunchingRecordId = null;
        });
      }
    }
  }

  String _playerTitleForRecord(DownloadTaskRecord record) {
    final groupTitle = record.groupTitle.trim();
    final recordTitle = DownloadTaskService.instance
        .displayTitleForRecord(record)
        .trim();
    if (recordTitle.isEmpty) {
      return groupTitle.isNotEmpty ? groupTitle : record.fileName.trim();
    }
    if (groupTitle.isEmpty || recordTitle.startsWith(groupTitle)) {
      return recordTitle;
    }
    return '$groupTitle $recordTitle';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final token = context.watch<NasProvider>().token;

    return Scaffold(
      backgroundColor: colors.backgroundBase,
      body: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: _service,
          builder: (context, _) {
            final group = _service.groupById(
              widget.groupId,
              status: _selectedTab.status,
            );
            final title = group?.title.trim().isNotEmpty == true
                ? group!.title
                : l10n.downloadDetailTitle;
            final records = group?.records ?? const <DownloadTaskRecord>[];
            if (records.isEmpty && _editing) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || !_editing) return;
                setState(() {
                  _editing = false;
                  _selectedRecordIds.clear();
                });
              });
            }
            _selectedRecordIds.removeWhere(
              (id) => !records.any((record) => record.id == id),
            );
            final selectedCount = _selectedRecordIds.length;
            final launchingRecordId = _playLaunchingRecordId;

            return Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 14, 0),
                  child: Row(
                    children: <Widget>[
                      _TopActionButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        onTap: () {
                          unawaited(
                            EmbeddedDetailLauncher.closeHostOrPop(context),
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _editing
                              ? l10n.downloadSelectedCount(selectedCount)
                              : title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed:
                            records.isEmpty ||
                                launchingRecordId != null ||
                                _selectedTab != DownloadListTab.downloaded
                            ? null
                            : () {
                                setState(() {
                                  _editing = !_editing;
                                  if (!_editing) {
                                    _selectedRecordIds.clear();
                                  }
                                });
                              },
                        style: TextButton.styleFrom(
                          foregroundColor: _editing
                              ? colors.textPrimary
                              : colors.textMuted,
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        child: Text(
                          _editing ? l10n.commonCancel : l10n.commonEdit,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: records.isEmpty
                      ? Center(
                          child: Text(
                            _selectedTab.emptyLabel(l10n),
                            style: TextStyle(
                              color: colors.textMuted,
                              fontSize: 16,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                          itemCount: records.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 18),
                          itemBuilder: (context, index) {
                            final record = records[index];
                            return _DownloadRecordRow(
                              key: ValueKey<String>(record.id),
                              record: record,
                              token: token,
                              busy: launchingRecordId == record.id,
                              dimmed:
                                  launchingRecordId != null &&
                                  launchingRecordId != record.id,
                              downloadSpeedBytesPerSecond: _service
                                  .downloadSpeedBytesPerSecondFor(record.id),
                              editing: _editing,
                              selected: _selectedRecordIds.contains(record.id),
                              onLongPress: launchingRecordId != null
                                  ? null
                                  : () => _handleRecordLongPress(record.id),
                              onSelectToggle: _editing
                                  ? (launchingRecordId != null
                                        ? null
                                        : () =>
                                              _toggleRecordSelection(record.id))
                                  : null,
                              onTap: launchingRecordId != null
                                  ? null
                                  : _editing
                                  ? () => _toggleRecordSelection(record.id)
                                  : _selectedTab != DownloadListTab.downloaded
                                  ? null
                                  : () => _playDownloadedRecord(record),
                            );
                          },
                        ),
                ),
                if (_editing) ...<Widget>[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: records.isEmpty
                                ? null
                                : () {
                                    setState(() {
                                      if (_selectedRecordIds.length ==
                                          records.length) {
                                        _selectedRecordIds.clear();
                                      } else {
                                        _selectedRecordIds
                                          ..clear()
                                          ..addAll(
                                            records.map((record) => record.id),
                                          );
                                      }
                                    });
                                  },
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(58),
                              backgroundColor: colors.surfaceStrong,
                              foregroundColor: colors.textPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: Text(
                              _selectedRecordIds.length == records.length &&
                                      records.isNotEmpty
                                  ? l10n.commonDeselectAll
                                  : l10n.commonSelectAll,
                            ),
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: FilledButton(
                            onPressed: _selectedRecordIds.isEmpty
                                ? null
                                : () => _confirmDeleteSelected(context),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(58),
                              backgroundColor: const Color(0xFF7E0913),
                              disabledBackgroundColor: const Color(
                                0xFF7E0913,
                              ).withValues(alpha: 0.35),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: Text(l10n.commonDelete),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  void _toggleRecordSelection(String recordId) {
    setState(() {
      if (_selectedRecordIds.contains(recordId)) {
        _selectedRecordIds.remove(recordId);
      } else {
        _selectedRecordIds.add(recordId);
      }
    });
  }

  Future<void> _confirmDeleteSelected(BuildContext context) async {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
            decoration: BoxDecoration(
              color: colors.backgroundElevated,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  l10n.downloadDeleteFilesTitle,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  l10n.downloadDeleteFilesContent,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () => Navigator.of(sheetContext).pop(false),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          backgroundColor: colors.surfaceStrong,
                          foregroundColor: colors.textPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: Text(l10n.commonCancel),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(sheetContext).pop(true),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          backgroundColor: const Color(0xFF7E0913),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: Text(l10n.commonDelete),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (confirmed != true || !mounted) return;
    await _service.clearDownloadedRecords(recordIds: _selectedRecordIds);
    if (!mounted) return;
    setState(() {
      _selectedRecordIds.clear();
      _editing = false;
    });
  }
}

class _DownloadGroupCard extends StatelessWidget {
  final DownloadTaskGroup group;
  final String token;
  final DownloadListTab tab;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool editing;
  final bool selected;
  final VoidCallback? onSelectToggle;

  const _DownloadGroupCard({
    super.key,
    required this.group,
    required this.token,
    required this.tab,
    required this.onTap,
    this.onLongPress,
    this.editing = false,
    this.selected = false,
    this.onSelectToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final lead = group.leadRecord;
    final isDownloading = tab == DownloadListTab.downloading;
    final sizeLabel = _formatBytes(
      isDownloading ? group.downloadedBytes : group.totalBytes,
    );
    final trailingLabel = isDownloading
        ? _formatBytes(group.totalBytes)
        : l10n.downloadVideoCount(group.itemCount);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? colors.surfaceStrong.withValues(alpha: 0.96)
              : colors.surface.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? colors.selectionStrong : colors.borderSubtle,
          ),
          boxShadow: selected
              ? <BoxShadow>[
                  BoxShadow(
                    color: colors.selectionStrong.withValues(alpha: 0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : const <BoxShadow>[],
        ),
        child: Row(
          children: <Widget>[
            _AnimatedSelectionSlot(
              visible: editing,
              selected: selected,
              onTap: onSelectToggle,
            ),
            SizedBox(
              width: 146,
              height: 82,
              child: _DownloadGroupPosterImage(
                urls: lead.groupPosterUrls,
                token: token,
                badgeLabel: lead.resolution,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: SizedBox(
                height: 82,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        group.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            sizeLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.selectionStrong,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              trailingLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.textMuted,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadRecordRow extends StatelessWidget {
  final DownloadTaskRecord record;
  final String token;
  final int downloadSpeedBytesPerSecond;
  final bool busy;
  final bool dimmed;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool editing;
  final bool selected;
  final VoidCallback? onSelectToggle;

  const _DownloadRecordRow({
    super.key,
    required this.record,
    required this.token,
    this.downloadSpeedBytesPerSecond = 0,
    this.busy = false,
    this.dimmed = false,
    this.onTap,
    this.onLongPress,
    this.editing = false,
    this.selected = false,
    this.onSelectToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final isDownloading = record.status == DownloadTaskStatus.downloading;
    final taskProgress = DownloadTaskService.instance.downloadTaskProgressFor(
      record.id,
    );
    final transcodePercent = (taskProgress?.percents ?? 0).clamp(0, 100);
    final isTranscoding =
        isDownloading &&
        record.downloadedBytes <= 0 &&
        taskProgress?.status == 0;
    final leadingMeta = isTranscoding
        ? l10n.downloadTranscodingPercent(transcodePercent)
        : (isDownloading && downloadSpeedBytesPerSecond > 0
              ? _formatTransferRate(downloadSpeedBytesPerSecond)
              : (isDownloading
                    ? l10n.downloadCalculating
                    : _formatBytes(record.totalBytes)));
    final trailingMeta = isTranscoding
        ? ''
        : (isDownloading
              ? _formatBytes(record.totalBytes)
              : (record.durationText.trim().isEmpty
                    ? record.resolution
                    : record.durationText));
    final progressValue = isTranscoding
        ? transcodePercent / 100
        : (record.totalBytes > 0
              ? (record.downloadedBytes / record.totalBytes).clamp(0.0, 1.0)
              : null);
    final progressPercent = progressValue == null
        ? null
        : (progressValue * 100).round().clamp(0, 100);
    final progressLabel = progressPercent == null
        ? l10n.downloadWaiting
        : '$progressPercent%';
    final progressAccent = isTranscoding
        ? colors.warning
        : colors.selectionStrong;
    final transferLabel = isTranscoding
        ? (record.totalBytes > 0
              ? _formatBytes(record.totalBytes)
              : l10n.downloadPendingGenerate)
        : (record.totalBytes > 0
              ? '${_formatBytes(record.downloadedBytes)} / ${_formatBytes(record.totalBytes)}'
              : _formatBytes(record.downloadedBytes));
    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: editing
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
          : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: editing
            ? (selected
                  ? colors.surfaceStrong.withValues(alpha: 0.96)
                  : colors.surface.withValues(alpha: 0.52))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: editing
            ? Border.all(
                color: selected ? colors.selectionStrong : colors.borderSubtle,
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _AnimatedSelectionSlot(
            visible: editing,
            selected: selected,
            topPadding: 28,
            onTap: onSelectToggle,
          ),
          SizedBox(
            width: isDownloading ? 128 : 146,
            height: isDownloading ? 72 : 82,
            child: _DownloadPosterImage(
              urls: record.posterUrls,
              token: token,
              badgeLabel: record.resolution,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    DownloadTaskService.instance.displayTitleForRecord(record),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  if (isDownloading) ...<Widget>[
                    const SizedBox(height: 12),
                    _DownloadProgressPanel(
                      statusLabel: isTranscoding
                          ? l10n.downloadTranscoding
                          : l10n.downloadDownloading,
                      progressLabel: progressLabel,
                      progressValue: progressValue,
                      accentColor: progressAccent,
                      leadingIcon: isTranscoding
                          ? Icons.auto_awesome_rounded
                          : Icons.speed_rounded,
                      leadingLabel: isTranscoding
                          ? l10n.downloadCurrentStage
                          : l10n.downloadSpeed,
                      leadingValue: isTranscoding
                          ? l10n.downloadCloudTranscoding
                          : leadingMeta,
                      trailingIcon: isTranscoding
                          ? Icons.movie_creation_outlined
                          : Icons.folder_zip_outlined,
                      trailingLabel: isTranscoding
                          ? l10n.downloadEstimatedFile
                          : l10n.downloadTransferredTotal,
                      trailingValue: transferLabel,
                    ),
                  ] else ...<Widget>[
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Text(
                          leadingMeta,
                          style: TextStyle(
                            color: colors.selectionStrong,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (trailingMeta.isNotEmpty) ...<Widget>[
                          const SizedBox(width: 10),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                trailingMeta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.textMuted,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                        if (busy) ...<Widget>[
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.selectionStrong,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
    final wrappedChild = AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      opacity: dimmed ? 0.56 : 1,
      child: child,
    );
    if (onTap == null) return wrappedChild;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(16),
      child: wrappedChild,
    );
  }
}

class _DownloadProgressPanel extends StatelessWidget {
  final String statusLabel;
  final String progressLabel;
  final double? progressValue;
  final Color accentColor;
  final IconData leadingIcon;
  final String leadingLabel;
  final String leadingValue;
  final IconData trailingIcon;
  final String trailingLabel;
  final String trailingValue;

  const _DownloadProgressPanel({
    required this.statusLabel,
    required this.progressLabel,
    required this.progressValue,
    required this.accentColor,
    required this.leadingIcon,
    required this.leadingLabel,
    required this.leadingValue,
    required this.trailingIcon,
    required this.trailingLabel,
    required this.trailingValue,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final chipFill = Color.lerp(colors.surfaceStrong, accentColor, 0.18)!;
    final chipBorder = accentColor.withValues(alpha: 0.24);
    final percentFill = Color.lerp(colors.surfaceStrong, accentColor, 0.1)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: chipFill,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: chipBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(leadingIcon, size: 14, color: accentColor),
                  const SizedBox(width: 6),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: Container(
                key: ValueKey<String>(progressLabel),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: percentFill,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: chipBorder),
                ),
                child: Text(
                  progressLabel,
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _DownloadProgressBar(
          progressValue: progressValue,
          accentColor: accentColor,
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: _DownloadMetricTile(
                icon: leadingIcon,
                label: leadingLabel,
                value: leadingValue,
                accentColor: accentColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DownloadMetricTile(
                icon: trailingIcon,
                label: trailingLabel,
                value: trailingValue,
                accentColor: accentColor,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DownloadProgressBar extends StatelessWidget {
  final double? progressValue;
  final Color accentColor;

  const _DownloadProgressBar({
    required this.progressValue,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final targetValue = (progressValue ?? 0.12).clamp(0.0, 1.0);
    final highlightColor = Color.lerp(accentColor, Colors.white, 0.24)!;

    return Container(
      height: 12,
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: colors.surfaceStrong.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.borderSubtle.withValues(alpha: 0.72)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: <Color>[
                    colors.backgroundBase.withValues(alpha: 0.16),
                    colors.surface.withValues(alpha: 0.04),
                  ],
                ),
              ),
            ),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: targetValue),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: value.clamp(0.0, 1.0),
                    child: child,
                  ),
                );
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: <Color>[accentColor, highlightColor],
                  ),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.22),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Colors.white.withValues(alpha: 0.22),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: 18,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: <Color>[
                              Colors.white.withValues(alpha: 0),
                              Colors.white.withValues(alpha: 0.28),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadMetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color accentColor;

  const _DownloadMetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final tileFill = Color.lerp(colors.surfaceStrong, accentColor, 0.08)!;
    final iconFill = Color.lerp(colors.surfaceStrong, accentColor, 0.18)!;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: tileFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: iconFill,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 15, color: accentColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
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

class _TopActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool busy;

  const _TopActionButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final child = InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        width: 36,
        height: 36,
        child: busy
            ? Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.textPrimary,
                  ),
                ),
              )
            : Icon(
                icon,
                color: onTap == null
                    ? colors.textMuted.withValues(alpha: 0.55)
                    : colors.textPrimary,
                size: 20,
              ),
      ),
    );
    if (tooltip == null || tooltip!.trim().isEmpty) return child;
    return Tooltip(message: tooltip!, child: child);
  }
}

class _AnimatedSelectionSlot extends StatelessWidget {
  final bool visible;
  final bool selected;
  final double topPadding;
  final VoidCallback? onTap;

  const _AnimatedSelectionSlot({
    required this.visible,
    required this.selected,
    required this.onTap,
    this.topPadding = 0,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.centerLeft,
      child: visible
          ? Padding(
              padding: EdgeInsets.only(top: topPadding, right: 14),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(14),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: selected ? colors.selection : colors.surfaceStrong,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? colors.selection : colors.borderStrong,
                    ),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeIn,
                    child: selected
                        ? Icon(
                            Icons.check,
                            key: const ValueKey<String>('download-selected'),
                            size: 16,
                            color: colors.textPrimary,
                          )
                        : const SizedBox(
                            key: ValueKey<String>('download-unselected'),
                            width: 16,
                            height: 16,
                          ),
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

class _DownloadPosterImage extends StatelessWidget {
  final List<String> urls;
  final String token;
  final String badgeLabel;

  const _DownloadPosterImage({
    required this.urls,
    required this.token,
    required this.badgeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedBadge = CapabilityBadgeMapper.normalize(badgeLabel);
    final badgeAsset = CapabilityBadgeMapper.badgeAsset(normalizedBadge);
    final colors = context.appColors;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ColoredBox(
            color: colors.surfaceStrong.withValues(alpha: 0.92),
            child: DetailHeroImage(urls: urls, token: token, fit: BoxFit.cover),
          ),
          if (normalizedBadge.isNotEmpty)
            Positioned(
              right: 0,
              bottom: 4,
              child: badgeAsset != null
                  ? SizedBox(
                      height: 16,
                      child: SvgPicture.asset(badgeAsset, fit: BoxFit.contain),
                    )
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF3F342E),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Text(
                          normalizedBadge,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

class _DownloadGroupPosterImage extends StatelessWidget {
  final List<String> urls;
  final String token;
  final String badgeLabel;

  const _DownloadGroupPosterImage({
    required this.urls,
    required this.token,
    required this.badgeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final normalizedBadge = CapabilityBadgeMapper.normalize(badgeLabel);
    final badgeAsset = CapabilityBadgeMapper.badgeAsset(normalizedBadge);

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ColoredBox(color: colors.surfaceStrong.withValues(alpha: 0.92)),
          Center(
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: DetailHeroImage(
                urls: urls,
                token: token,
                fit: BoxFit.contain,
              ),
            ),
          ),
          if (normalizedBadge.isNotEmpty)
            Positioned(
              right: 0,
              bottom: 4,
              child: badgeAsset != null
                  ? SizedBox(
                      height: 16,
                      child: SvgPicture.asset(badgeAsset, fit: BoxFit.contain),
                    )
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF3F342E),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Text(
                          normalizedBadge,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

class _DownloadTabSwitcher extends StatelessWidget {
  final DownloadListTab selectedTab;
  final ValueChanged<DownloadListTab> onChanged;

  const _DownloadTabSwitcher({
    required this.selectedTab,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 248),
      child: Container(
        height: 46,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: colors.surfaceStrong.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.borderStrong),
        ),
        child: Row(
          children: <Widget>[
            _DownloadTabChip(
              label: l10n.downloadDownloadedTab,
              selected: selectedTab == DownloadListTab.downloaded,
              onTap: () => onChanged(DownloadListTab.downloaded),
            ),
            const SizedBox(width: 6),
            _DownloadTabChip(
              label: l10n.downloadDownloadingTab,
              selected: selectedTab == DownloadListTab.downloading,
              onTap: () => onChanged(DownloadListTab.downloading),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadTabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DownloadTabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected ? colors.backgroundBase : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? colors.textPrimary : colors.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _DownloadEmptyArtwork extends StatelessWidget {
  const _DownloadEmptyArtwork();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: 116,
      height: 116,
      decoration: BoxDecoration(
        color: colors.surfaceStrong.withValues(alpha: 0.7),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.folder_open_rounded, size: 52, color: colors.textMuted),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  final fixed = value >= 100 ? 0 : 2;
  return '${value.toStringAsFixed(fixed)} ${units[unitIndex]}';
}

String _formatTransferRate(int bytesPerSecond) {
  if (bytesPerSecond <= 0) return '0 B/s';
  const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytesPerSecond.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  final fixed = value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(fixed)} ${units[unitIndex]}/s';
}
