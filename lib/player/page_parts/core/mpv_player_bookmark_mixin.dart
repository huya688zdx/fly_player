part of '../../mpv_player_page.dart';

const String _playerSettingsBookmarkPageId = 'player_settings_bookmarks';

class _BookmarkMetadata {
  final String mediaType;
  final String ancestorName;
  final String title;
  final String seriesTitle;
  final int seasonNumber;
  final int episodeNumber;

  const _BookmarkMetadata({
    required this.mediaType,
    required this.ancestorName,
    required this.title,
    required this.seriesTitle,
    required this.seasonNumber,
    required this.episodeNumber,
  });
}

extension _MpvPlayerBookmarkMixin on _MpvPlayerPageState {
  String _bookmarkIdentityKey({
    required String itemGuid,
    required String mediaGuid,
  }) {
    final item = itemGuid.trim();
    final media = mediaGuid.trim();
    if (item.isNotEmpty && media.isNotEmpty) return '$item::$media';
    if (item.isNotEmpty) return item;
    return media;
  }

  Future<void> _loadBookmarksForCurrentMedia() async {
    final itemGuid = _currentItemGuid;
    final mediaGuid = _currentMediaGuid;
    final identityKey = _bookmarkIdentityKey(
      itemGuid: itemGuid,
      mediaGuid: mediaGuid,
    );
    final bookmarks = await _bookmarkStore.loadForMedia(
      itemGuid: itemGuid,
      mediaGuid: mediaGuid,
    );
    if (_bookmarkIdentityKey(
          itemGuid: _currentItemGuid,
          mediaGuid: _currentMediaGuid,
        ) !=
        identityKey) {
      return;
    }
    if (!mounted) {
      _bookmarksForCurrentMedia = bookmarks;
      return;
    }
    _updatePlayerState(() => _bookmarksForCurrentMedia = bookmarks);
  }

  String _bookmarkSummaryLabel() {
    final l10n = AppLocalizations.of(context);
    final count = _bookmarksForCurrentMedia.length;
    if (count <= 0) return l10n.playerBookmarkNone;
    return l10n.playerBookmarkCount(count);
  }

  String _bookmarkSummaryText() {
    final l10n = AppLocalizations.of(context);
    if (_bookmarksForCurrentMedia.isEmpty) {
      return l10n.playerBookmarkEmptySummary;
    }
    final first = _bookmarksForCurrentMedia.first;
    return l10n.playerBookmarkRecentSummary(
      _formatDuration(first.position),
      _bookmarksForCurrentMedia.length,
    );
  }

  Future<_BookmarkMetadata> _fetchBookmarkMetadata() async {
    final fallback = _BookmarkMetadata(
      mediaType: _currentMediaType.trim(),
      ancestorName: _currentAncestorName.trim(),
      title: _currentTitle.trim(),
      seriesTitle: _currentSeriesTitle.trim(),
      seasonNumber: _currentSeasonNumber,
      episodeNumber: _currentEpisodeNumber,
    );
    final itemGuid = _currentItemGuid.trim();
    if (_externalLocalSource) return fallback;
    if (itemGuid.isEmpty) return fallback;
    try {
      final playInfo = await FeiniuApi(
        context.read<NasProvider>(),
      ).getPlayInfo(itemGuid);
      final item = playInfo.item;
      return _BookmarkMetadata(
        mediaType: item.type.trim().isNotEmpty
            ? item.type.trim()
            : fallback.mediaType,
        ancestorName: item.ancestorName.trim().isNotEmpty
            ? item.ancestorName.trim()
            : fallback.ancestorName,
        title: item.title.trim().isNotEmpty
            ? item.title.trim()
            : fallback.title,
        seriesTitle: item.tvTitle.trim().isNotEmpty
            ? item.tvTitle.trim()
            : fallback.seriesTitle,
        seasonNumber: item.seasonNumber,
        episodeNumber: item.episodeNumber,
      );
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _addBookmarkAtCurrentPosition({
    PlayerNestedSheetController<void>? drawer,
  }) async {
    final l10n = AppLocalizations.of(context);
    final note = await showBookmarkNoteDialog(
      context,
      title: l10n.playerBookmarkNoteDialogTitle,
    );
    if (note == null) return;
    final position = _displayPosition(_controller.value.value);
    final durationSeconds = _durationSeconds;
    final metadata = await _fetchBookmarkMetadata();
    final entry = await _bookmarkStore.add(
      itemGuid: _currentItemGuid,
      mediaGuid: _currentMediaGuid,
      mediaType: metadata.mediaType,
      ancestorName: metadata.ancestorName,
      title: metadata.title,
      seriesTitle: metadata.seriesTitle,
      seasonNumber: metadata.seasonNumber,
      episodeNumber: metadata.episodeNumber,
      position: position,
      durationSeconds: durationSeconds,
      note: note,
    );
    await _loadBookmarksForCurrentMedia();
    if (!mounted) return;
    drawer?.refresh();
    _showTopTip(
      l10n.playerBookmarkAdded(_formatDuration(entry.position)),
      context.appColors.success,
      revealControls: false,
    );
  }

  Future<void> _removeBookmark(
    PlayerBookmarkEntry entry, {
    PlayerNestedSheetController<void>? drawer,
  }) async {
    await _bookmarkStore.remove(entry.id);
    await _loadBookmarksForCurrentMedia();
    if (!mounted) return;
    drawer?.refresh();
    _showTopTip(
      AppLocalizations.of(context).playerBookmarkDeleted,
      context.appColors.warning,
      revealControls: false,
    );
  }

  Future<void> _clearBookmarksForCurrentMedia(
    PlayerNestedSheetController<void> drawer,
  ) async {
    await _bookmarkStore.clearForMedia(
      itemGuid: _currentItemGuid,
      mediaGuid: _currentMediaGuid,
    );
    await _loadBookmarksForCurrentMedia();
    if (!mounted) return;
    drawer.refresh();
    _showTopTip(
      AppLocalizations.of(context).playerBookmarkCleared,
      context.appColors.warning,
      revealControls: false,
    );
  }

  Future<void> _seekToBookmark(
    PlayerBookmarkEntry entry,
    PlayerNestedSheetController<void> drawer,
  ) async {
    drawer.close();
    await _seekWithStats(entry.position, userInitiated: true);
    if (!mounted) return;
    _showTopTip(
      AppLocalizations.of(
        context,
      ).playerBookmarkJumped(_formatDuration(entry.position)),
      context.appColors.accent,
    );
  }

  List<PlayerProgressChapterMarker> _bookmarkProgressMarkers(
    Duration duration,
  ) {
    if (duration <= Duration.zero || _bookmarksForCurrentMedia.isEmpty) {
      return const <PlayerProgressChapterMarker>[];
    }
    final currentMs = _displayPosition(_controller.value.value).inMilliseconds;
    return _bookmarksForCurrentMedia
        .where((entry) => entry.positionMs > 0)
        .map(
          (entry) => PlayerProgressChapterMarker(
            fraction:
                entry.positionMs.clamp(0, duration.inMilliseconds).toDouble() /
                duration.inMilliseconds,
            active: (entry.positionMs - currentMs).abs() <= 2000,
            kind: PlayerProgressMarkerKind.bookmark,
            snapTarget: false,
          ),
        )
        .toList(growable: false);
  }

  Widget _buildPlaybackSettingsBookmarkPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    final l10n = AppLocalizations.of(context);
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: l10n.playerBookmarkTitle,
        onBack: drawer.popPage,
        actions: <Widget>[
          PlaybackSettingsHeaderAction(
            icon: Icons.add_rounded,
            label: l10n.playerBookmarkAddCurrent,
            onTap: () =>
                unawaited(_addBookmarkAtCurrentPosition(drawer: drawer)),
          ),
          if (_bookmarksForCurrentMedia.isNotEmpty)
            PlaybackSettingsHeaderAction(
              icon: Icons.delete_sweep_rounded,
              label: l10n.commonClear,
              onTap: () => unawaited(_clearBookmarksForCurrentMedia(drawer)),
            ),
        ],
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          PlaybackSettingsStatusCard(
            title: _currentTitle.trim().isEmpty
                ? l10n.playerBookmarkCurrentSegment
                : _currentTitle,
            value: _bookmarkSummaryLabel(),
            description: _bookmarkSummaryText(),
          ),
          if (_bookmarksForCurrentMedia.isNotEmpty) const SizedBox(height: 12),
          if (_bookmarksForCurrentMedia.isEmpty)
            DecoratedBox(
              decoration: _settingsCardDecoration(context),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  l10n.playerBookmarkEmptyPrompt,
                  style: TextStyle(
                    color: context.appColors.textSecondary,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ),
            )
          else
            ..._bookmarksForCurrentMedia.asMap().entries.expand((entry) sync* {
              yield _PlaybackBookmarkTile(
                note: entry.value.note,
                timeLabel: _formatDuration(entry.value.position),
                subtitle: l10n.playerBookmarkCreatedAt(
                  _formatBookmarkCreatedAt(entry.value.createdAt),
                ),
                onJump: () => unawaited(_seekToBookmark(entry.value, drawer)),
                onDelete: () =>
                    unawaited(_removeBookmark(entry.value, drawer: drawer)),
              );
              if (entry.key != _bookmarksForCurrentMedia.length - 1) {
                yield const SizedBox(height: 12);
              }
            }),
        ],
      ),
    );
  }

  String _formatBookmarkCreatedAt(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }
}

class _PlaybackBookmarkTile extends StatelessWidget {
  final String note;
  final String timeLabel;
  final String subtitle;
  final VoidCallback onJump;
  final VoidCallback onDelete;

  const _PlaybackBookmarkTile({
    required this.note,
    required this.timeLabel,
    required this.subtitle,
    required this.onJump,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return DecoratedBox(
      decoration: _settingsCardDecoration(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    timeLabel,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  if (note.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    BookmarkNotePreview(note: note),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: onJump,
              child: Text(AppLocalizations.of(context).commonJump),
            ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: onDelete,
              child: Text(AppLocalizations.of(context).commonDelete),
            ),
          ],
        ),
      ),
    );
  }
}
