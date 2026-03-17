part of mpv_player_page;

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
    final count = _bookmarksForCurrentMedia.length;
    if (count <= 0) return '无书签';
    return '$count 个';
  }

  String _bookmarkSummaryText() {
    if (_bookmarksForCurrentMedia.isEmpty) {
      return '为当前片段记录关键时间点，之后可以快速跳回。';
    }
    final first = _bookmarksForCurrentMedia.first;
    return '最近书签 ${_formatDuration(first.position)}，共 ${_bookmarksForCurrentMedia.length} 个。';
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
    final note = await showBookmarkNoteDialog(context, title: '添加书签备注');
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
      '已添加书签 ${_formatDuration(entry.position)}',
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
    _showTopTip('已删除书签', context.appColors.warning, revealControls: false);
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
    _showTopTip('当前片段书签已清空', context.appColors.warning, revealControls: false);
  }

  Future<void> _seekToBookmark(
    PlayerBookmarkEntry entry,
    PlayerNestedSheetController<void> drawer,
  ) async {
    drawer.close();
    await _controller.seek(entry.position);
    if (!mounted) return;
    _showTopTip(
      '已跳转到 ${_formatDuration(entry.position)}',
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
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: '书签',
        onBack: drawer.popPage,
        actions: <Widget>[
          PlaybackSettingsHeaderAction(
            icon: Icons.add_rounded,
            label: '添加当前',
            onTap: () =>
                unawaited(_addBookmarkAtCurrentPosition(drawer: drawer)),
          ),
          if (_bookmarksForCurrentMedia.isNotEmpty)
            PlaybackSettingsHeaderAction(
              icon: Icons.delete_sweep_rounded,
              label: '清空',
              onTap: () => unawaited(_clearBookmarksForCurrentMedia(drawer)),
            ),
        ],
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          PlaybackSettingsStatusCard(
            title: _currentTitle.trim().isEmpty ? '当前片段' : _currentTitle,
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
                  '还没有书签，点击右上角“添加当前”即可记录当前时间点。',
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
                subtitle:
                    '创建于 ${_formatBookmarkCreatedAt(entry.value.createdAt)}',
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
            TextButton(onPressed: onJump, child: const Text('跳转')),
            const SizedBox(width: 4),
            TextButton(onPressed: onDelete, child: const Text('删除')),
          ],
        ),
      ),
    );
  }
}
