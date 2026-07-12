import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/item_playback_launcher.dart';
import '../l10n/generated/app_localizations.dart';
import '../player/stores/bookmark_store.dart';
import '../theme/app_theme.dart';
import '../ui/adaptive_text.dart';
import '../ui/bookmark_note_dialog.dart';
import '../ui/bookmark_note_preview.dart';
import '../ui/app_transitions.dart';
import '../ui/secondary_host_navigation.dart';
import '../utils/app_confirm_dialog.dart';

bool _bookmarkIsTv(PlayerBookmarkEntry entry) {
  final type = entry.mediaType.trim().toLowerCase();
  return type == 'episode' || type == 'tv';
}

String _bookmarkAncestorLabel(
  PlayerBookmarkEntry entry,
  AppLocalizations l10n,
) {
  final label = entry.ancestorName.trim();
  if (label.isNotEmpty) return label;
  return l10n.bookmarkManagerLegacyBookmark;
}

String _bookmarkSeriesLabel(PlayerBookmarkEntry entry, AppLocalizations l10n) {
  final seriesTitle = entry.seriesTitle.trim();
  if (seriesTitle.isNotEmpty) return seriesTitle;
  final title = entry.title.trim();
  if (title.isNotEmpty) return title;
  return l10n.bookmarkManagerUnnamedWork;
}

String _bookmarkSeasonLabel(PlayerBookmarkEntry entry, AppLocalizations l10n) {
  if (entry.seasonNumber <= 0) return l10n.bookmarkManagerSpecialSeason;
  return l10n.bookmarkManagerSeasonLabel(entry.seasonNumber);
}

String _bookmarkEpisodeLabel(PlayerBookmarkEntry entry, AppLocalizations l10n) {
  if (entry.episodeNumber > 0) {
    return l10n.bookmarkManagerEpisodeLabel(entry.episodeNumber);
  }
  final title = entry.title.trim();
  if (title.isNotEmpty) return title;
  return l10n.bookmarkManagerUnnamedEpisode;
}

int _bookmarkSeasonOrder(PlayerBookmarkEntry entry) {
  return entry.seasonNumber <= 0 ? 0 : entry.seasonNumber;
}

int _bookmarkEpisodeOrder(PlayerBookmarkEntry entry) {
  return entry.episodeNumber <= 0 ? 9999 : entry.episodeNumber;
}

String _formatBookmarkTime(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

String _formatBookmarkCreatedAt(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$month-$day $hour:$minute';
}

class BookmarkManagerScreen extends StatefulWidget {
  const BookmarkManagerScreen({super.key});

  @override
  State<BookmarkManagerScreen> createState() => _BookmarkManagerScreenState();
}

class _BookmarkManagerScreenState extends State<BookmarkManagerScreen> {
  final BookmarkStore _store = const BookmarkStore();

  List<PlayerBookmarkEntry> _bookmarks = const <PlayerBookmarkEntry>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _store.changes.addListener(_handleStoreChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    _store.changes.removeListener(_handleStoreChanged);
    super.dispose();
  }

  void _handleStoreChanged() {
    unawaited(_load());
  }

  Future<void> _load() async {
    final entries = await _store.loadAll();
    if (!mounted) return;
    setState(() {
      _bookmarks = entries;
      _loading = false;
    });
  }

  Future<void> _clearAll() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.bookmarkClearConfirmTitle,
      content: l10n.bookmarkClearConfirmContent,
      cancelText: l10n.commonCancel,
      confirmText: l10n.commonClear,
    );
    if (!confirmed) return;
    await _store.clearAll();
  }

  List<_AncestorGroup> _ancestorGroups() {
    final l10n = AppLocalizations.of(context);
    final buckets = <String, List<PlayerBookmarkEntry>>{};
    for (final entry in _bookmarks) {
      final key = _bookmarkAncestorLabel(entry, l10n);
      buckets.putIfAbsent(key, () => <PlayerBookmarkEntry>[]).add(entry);
    }
    final groups =
        buckets.entries
            .map(
              (entry) => _AncestorGroup(
                label: entry.key,
                entries: List<PlayerBookmarkEntry>.from(entry.value)
                  ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs)),
              ),
            )
            .toList(growable: false)
          ..sort(
            (a, b) => b.entries.first.createdAtMs.compareTo(
              a.entries.first.createdAtMs,
            ),
          );
    return groups;
  }

  Future<void> _openAncestor(_AncestorGroup group) async {
    final hasTvEntries = group.entries.any(_bookmarkIsTv);
    final routePage = hasTvEntries
        ? _BookmarkSeriesListScreen(
            ancestorLabel: group.label,
            entries: group.entries.where(_bookmarkIsTv).toList(growable: false),
          )
        : _BookmarkDirectEntryScreen(
            ancestorLabel: group.label,
            entries: group.entries,
          );
    await Navigator.of(
      context,
    ).push(AppTransitions.leftToRightPageTurnRoute(routePage));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final groups = _ancestorGroups();
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: buildSecondaryHostAppBar(
        context,
        title: Text(
          l10n.settingsBookmarkManagerTitle,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: AdaptiveText.roleSize(20, role: AdaptiveFontRole.title),
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: <Widget>[
          if (_bookmarks.isNotEmpty)
            TextButton(onPressed: _clearAll, child: Text(l10n.commonClear)),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[colors.backgroundElevated, colors.backgroundBase],
          ),
        ),
        child: SafeArea(
          top: false,
          child: _loading
              ? Center(child: CircularProgressIndicator(color: colors.accent))
              : groups.isEmpty
              ? Center(
                  child: Text(
                    l10n.settingsBookmarkEmptySummary,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: AdaptiveText.roleSize(
                        15,
                        role: AdaptiveFontRole.body,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  itemCount: groups.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final group = groups[index];
                    return _BookmarkFolderTile(
                      icon: Icons.folder_copy_outlined,
                      title: group.label,
                      subtitle: l10n.settingsBookmarkCountSummary(
                        group.entries.length,
                      ),
                      onTap: () => _openAncestor(group),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _BookmarkSeriesListScreen extends StatefulWidget {
  final String ancestorLabel;
  final List<PlayerBookmarkEntry> entries;

  const _BookmarkSeriesListScreen({
    required this.ancestorLabel,
    required this.entries,
  });

  @override
  State<_BookmarkSeriesListScreen> createState() =>
      _BookmarkSeriesListScreenState();
}

class _BookmarkSeriesListScreenState extends State<_BookmarkSeriesListScreen> {
  final BookmarkStore _store = const BookmarkStore();
  late List<PlayerBookmarkEntry> _entries = List<PlayerBookmarkEntry>.from(
    widget.entries,
  );

  @override
  void initState() {
    super.initState();
    _store.changes.addListener(_handleStoreChanged);
  }

  @override
  void dispose() {
    _store.changes.removeListener(_handleStoreChanged);
    super.dispose();
  }

  void _handleStoreChanged() {
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final all = await _store.loadAll();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _entries =
          all
              .where(
                (entry) =>
                    _bookmarkIsTv(entry) &&
                    _bookmarkAncestorLabel(entry, l10n) == widget.ancestorLabel,
              )
              .toList(growable: false)
            ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    });
  }

  List<_SeriesGroup> _seriesGroups() {
    final l10n = AppLocalizations.of(context);
    final buckets = <String, List<PlayerBookmarkEntry>>{};
    for (final entry in _entries) {
      final key = _bookmarkSeriesLabel(entry, l10n);
      buckets.putIfAbsent(key, () => <PlayerBookmarkEntry>[]).add(entry);
    }
    final groups =
        buckets.entries
            .map(
              (entry) => _SeriesGroup(
                label: entry.key,
                entries: List<PlayerBookmarkEntry>.from(entry.value)
                  ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs)),
              ),
            )
            .toList(growable: false)
          ..sort(
            (a, b) => b.entries.first.createdAtMs.compareTo(
              a.entries.first.createdAtMs,
            ),
          );
    return groups;
  }

  Future<void> _openSeries(_SeriesGroup group) async {
    await Navigator.of(context).push(
      AppTransitions.leftToRightPageTurnRoute(
        _BookmarkSeasonListScreen(
          ancestorLabel: widget.ancestorLabel,
          seriesLabel: group.label,
          entries: group.entries,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final groups = _seriesGroups();
    return Scaffold(
      backgroundColor: context.appColors.backgroundBase,
      appBar: buildSecondaryHostAppBar(
        context,
        title: Text(widget.ancestorLabel),
      ),
      body: groups.isEmpty
          ? const SizedBox.shrink()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              itemCount: groups.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final group = groups[index];
                return _BookmarkFolderTile(
                  icon: Icons.tv_outlined,
                  title: group.label,
                  subtitle: l10n.settingsBookmarkCountSummary(
                    group.entries.length,
                  ),
                  onTap: () => _openSeries(group),
                );
              },
            ),
    );
  }
}

class _BookmarkSeasonListScreen extends StatefulWidget {
  final String ancestorLabel;
  final String seriesLabel;
  final List<PlayerBookmarkEntry> entries;

  const _BookmarkSeasonListScreen({
    required this.ancestorLabel,
    required this.seriesLabel,
    required this.entries,
  });

  @override
  State<_BookmarkSeasonListScreen> createState() =>
      _BookmarkSeasonListScreenState();
}

class _BookmarkSeasonListScreenState extends State<_BookmarkSeasonListScreen> {
  final BookmarkStore _store = const BookmarkStore();
  late List<PlayerBookmarkEntry> _entries = List<PlayerBookmarkEntry>.from(
    widget.entries,
  );

  @override
  void initState() {
    super.initState();
    _store.changes.addListener(_handleStoreChanged);
  }

  @override
  void dispose() {
    _store.changes.removeListener(_handleStoreChanged);
    super.dispose();
  }

  void _handleStoreChanged() {
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final all = await _store.loadAll();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _entries =
          all
              .where(
                (entry) =>
                    _bookmarkIsTv(entry) &&
                    _bookmarkAncestorLabel(entry, l10n) ==
                        widget.ancestorLabel &&
                    _bookmarkSeriesLabel(entry, l10n) == widget.seriesLabel,
              )
              .toList(growable: false)
            ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    });
  }

  List<_SeasonGroup> _seasonGroups() {
    final l10n = AppLocalizations.of(context);
    final buckets = <String, List<PlayerBookmarkEntry>>{};
    final orders = <String, int>{};
    for (final entry in _entries) {
      final key = _bookmarkSeasonLabel(entry, l10n);
      buckets.putIfAbsent(key, () => <PlayerBookmarkEntry>[]).add(entry);
      orders[key] = _bookmarkSeasonOrder(entry);
    }
    final groups =
        buckets.entries
            .map(
              (entry) => _SeasonGroup(
                label: entry.key,
                order: orders[entry.key] ?? 9999,
                entries: List<PlayerBookmarkEntry>.from(entry.value)
                  ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs)),
              ),
            )
            .toList(growable: false)
          ..sort((a, b) => a.order.compareTo(b.order));
    return groups;
  }

  Future<void> _openSeason(_SeasonGroup group) async {
    await Navigator.of(context).push(
      AppTransitions.leftToRightPageTurnRoute(
        _BookmarkEpisodeListScreen(
          ancestorLabel: widget.ancestorLabel,
          seriesLabel: widget.seriesLabel,
          seasonLabel: group.label,
          entries: group.entries,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final groups = _seasonGroups();
    return Scaffold(
      backgroundColor: context.appColors.backgroundBase,
      appBar: buildSecondaryHostAppBar(
        context,
        title: Text(widget.seriesLabel),
      ),
      body: groups.isEmpty
          ? const SizedBox.shrink()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              itemCount: groups.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final group = groups[index];
                return _BookmarkFolderTile(
                  icon: Icons.video_library_outlined,
                  title: group.label,
                  subtitle: l10n.settingsBookmarkCountSummary(
                    group.entries.length,
                  ),
                  onTap: () => _openSeason(group),
                );
              },
            ),
    );
  }
}

class _BookmarkEpisodeListScreen extends StatefulWidget {
  final String ancestorLabel;
  final String seriesLabel;
  final String seasonLabel;
  final List<PlayerBookmarkEntry> entries;

  const _BookmarkEpisodeListScreen({
    required this.ancestorLabel,
    required this.seriesLabel,
    required this.seasonLabel,
    required this.entries,
  });

  @override
  State<_BookmarkEpisodeListScreen> createState() =>
      _BookmarkEpisodeListScreenState();
}

class _BookmarkEpisodeListScreenState
    extends State<_BookmarkEpisodeListScreen> {
  final BookmarkStore _store = const BookmarkStore();
  late List<PlayerBookmarkEntry> _entries = List<PlayerBookmarkEntry>.from(
    widget.entries,
  );

  @override
  void initState() {
    super.initState();
    _store.changes.addListener(_handleStoreChanged);
  }

  @override
  void dispose() {
    _store.changes.removeListener(_handleStoreChanged);
    super.dispose();
  }

  void _handleStoreChanged() {
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final all = await _store.loadAll();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _entries =
          all
              .where(
                (entry) =>
                    _bookmarkIsTv(entry) &&
                    _bookmarkAncestorLabel(entry, l10n) ==
                        widget.ancestorLabel &&
                    _bookmarkSeriesLabel(entry, l10n) == widget.seriesLabel &&
                    _bookmarkSeasonLabel(entry, l10n) == widget.seasonLabel,
              )
              .toList(growable: false)
            ..sort((a, b) => a.positionMs.compareTo(b.positionMs));
    });
  }

  List<_EpisodeGroup> _episodeGroups() {
    final l10n = AppLocalizations.of(context);
    final buckets = <String, List<PlayerBookmarkEntry>>{};
    final orders = <String, int>{};
    for (final entry in _entries) {
      final key = _bookmarkEpisodeLabel(entry, l10n);
      buckets.putIfAbsent(key, () => <PlayerBookmarkEntry>[]).add(entry);
      orders[key] = _bookmarkEpisodeOrder(entry);
    }
    final groups =
        buckets.entries
            .map(
              (entry) => _EpisodeGroup(
                label: entry.key,
                order: orders[entry.key] ?? 9999,
                bookmarks: List<PlayerBookmarkEntry>.from(entry.value)
                  ..sort((a, b) => a.positionMs.compareTo(b.positionMs)),
              ),
            )
            .toList(growable: false)
          ..sort((a, b) => a.order.compareTo(b.order));
    return groups;
  }

  Future<void> _openEpisode(_EpisodeGroup group) async {
    await Navigator.of(context).push(
      AppTransitions.leftToRightPageTurnRoute(
        _BookmarkEpisodeBookmarksScreen(
          ancestorLabel: widget.ancestorLabel,
          seriesLabel: widget.seriesLabel,
          seasonLabel: widget.seasonLabel,
          episodeLabel: group.label,
          entries: group.bookmarks,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final groups = _episodeGroups();
    return Scaffold(
      backgroundColor: context.appColors.backgroundBase,
      appBar: buildSecondaryHostAppBar(
        context,
        title: Text(widget.seasonLabel),
      ),
      body: groups.isEmpty
          ? const SizedBox.shrink()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              itemCount: groups.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final group = groups[index];
                return _BookmarkFolderTile(
                  icon: Icons.movie_filter_outlined,
                  title: group.label,
                  subtitle: l10n.settingsBookmarkCountSummary(
                    group.bookmarks.length,
                  ),
                  onTap: () => _openEpisode(group),
                );
              },
            ),
    );
  }
}

class _BookmarkEpisodeBookmarksScreen extends StatefulWidget {
  final String ancestorLabel;
  final String seriesLabel;
  final String seasonLabel;
  final String episodeLabel;
  final List<PlayerBookmarkEntry> entries;

  const _BookmarkEpisodeBookmarksScreen({
    required this.ancestorLabel,
    required this.seriesLabel,
    required this.seasonLabel,
    required this.episodeLabel,
    required this.entries,
  });

  @override
  State<_BookmarkEpisodeBookmarksScreen> createState() =>
      _BookmarkEpisodeBookmarksScreenState();
}

class _BookmarkEpisodeBookmarksScreenState
    extends State<_BookmarkEpisodeBookmarksScreen> {
  final BookmarkStore _store = const BookmarkStore();
  final ItemPlaybackLauncher _launcher = const ItemPlaybackLauncher();
  late List<PlayerBookmarkEntry> _entries = List<PlayerBookmarkEntry>.from(
    widget.entries,
  );

  @override
  void initState() {
    super.initState();
    _store.changes.addListener(_handleStoreChanged);
  }

  @override
  void dispose() {
    _store.changes.removeListener(_handleStoreChanged);
    super.dispose();
  }

  void _handleStoreChanged() {
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final all = await _store.loadAll();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _entries =
          all
              .where(
                (entry) =>
                    _bookmarkIsTv(entry) &&
                    _bookmarkAncestorLabel(entry, l10n) ==
                        widget.ancestorLabel &&
                    _bookmarkSeriesLabel(entry, l10n) == widget.seriesLabel &&
                    _bookmarkSeasonLabel(entry, l10n) == widget.seasonLabel &&
                    _bookmarkEpisodeLabel(entry, l10n) == widget.episodeLabel,
              )
              .toList(growable: false)
            ..sort((a, b) => a.positionMs.compareTo(b.positionMs));
    });
  }

  Future<void> _deleteBookmark(PlayerBookmarkEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.bookmarkDeleteConfirmTitle,
      content: l10n.bookmarkDeleteConfirmContent,
      cancelText: l10n.commonCancel,
      confirmText: l10n.commonDelete,
    );
    if (!confirmed) return;
    await _store.remove(entry.id);
  }

  Future<void> _editBookmarkNote(PlayerBookmarkEntry entry) async {
    final note = await showBookmarkNoteDialog(
      context,
      title: AppLocalizations.of(context).bookmarkManagerEditNoteTitle,
      initialValue: entry.note,
    );
    if (note == null) return;
    await _store.updateNote(id: entry.id, note: note);
  }

  Future<void> _openBookmark(PlayerBookmarkEntry entry) async {
    final itemGuid = entry.itemGuid.trim();
    if (itemGuid.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    await _launcher.open(
      context,
      itemGuid: itemGuid,
      fallbackTitle: _bookmarkSeriesLabel(entry, l10n),
      resumePosition: entry.position,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: buildSecondaryHostAppBar(
        context,
        title: Text(widget.episodeLabel),
      ),
      body: _entries.isEmpty
          ? Center(
              child: Text(
                l10n.bookmarkManagerNoEpisodeBookmarks,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: AdaptiveText.roleSize(
                    14,
                    role: AdaptiveFontRole.body,
                  ),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              itemCount: _entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final entry = _entries[index];
                return _RichBookmarkEntryCard(
                  note: entry.note,
                  title: _formatBookmarkTime(entry.position),
                  subtitle: l10n.playerBookmarkCreatedAt(
                    _formatBookmarkCreatedAt(entry.createdAt),
                  ),
                  onTap: () => _openBookmark(entry),
                  onEdit: () => _editBookmarkNote(entry),
                  onDelete: () => _deleteBookmark(entry),
                );
              },
            ),
    );
  }
}

class _BookmarkDirectEntryScreen extends StatefulWidget {
  final String ancestorLabel;
  final List<PlayerBookmarkEntry> entries;

  const _BookmarkDirectEntryScreen({
    required this.ancestorLabel,
    required this.entries,
  });

  @override
  State<_BookmarkDirectEntryScreen> createState() =>
      _BookmarkDirectEntryScreenState();
}

class _BookmarkDirectEntryScreenState
    extends State<_BookmarkDirectEntryScreen> {
  final BookmarkStore _store = const BookmarkStore();
  final ItemPlaybackLauncher _launcher = const ItemPlaybackLauncher();
  late List<PlayerBookmarkEntry> _entries = List<PlayerBookmarkEntry>.from(
    widget.entries,
  );

  @override
  void initState() {
    super.initState();
    _store.changes.addListener(_handleStoreChanged);
  }

  @override
  void dispose() {
    _store.changes.removeListener(_handleStoreChanged);
    super.dispose();
  }

  void _handleStoreChanged() {
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final all = await _store.loadAll();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _entries =
          all
              .where(
                (entry) =>
                    !_bookmarkIsTv(entry) &&
                    _bookmarkAncestorLabel(entry, l10n) == widget.ancestorLabel,
              )
              .toList(growable: false)
            ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    });
  }

  Future<void> _deleteBookmark(PlayerBookmarkEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.bookmarkDeleteConfirmTitle,
      content: l10n.bookmarkDeleteConfirmContent,
      cancelText: l10n.commonCancel,
      confirmText: l10n.commonDelete,
    );
    if (!confirmed) return;
    await _store.remove(entry.id);
  }

  Future<void> _editBookmarkNote(PlayerBookmarkEntry entry) async {
    final note = await showBookmarkNoteDialog(
      context,
      title: AppLocalizations.of(context).bookmarkManagerEditNoteTitle,
      initialValue: entry.note,
    );
    if (note == null) return;
    await _store.updateNote(id: entry.id, note: note);
  }

  Future<void> _openBookmark(PlayerBookmarkEntry entry) async {
    final itemGuid = entry.itemGuid.trim();
    if (itemGuid.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    await _launcher.open(
      context,
      itemGuid: itemGuid,
      fallbackTitle: _bookmarkSeriesLabel(entry, l10n),
      resumePosition: entry.position,
    );
  }

  List<_DirectEntryGroup> _groups() {
    final l10n = AppLocalizations.of(context);
    final buckets = <String, List<PlayerBookmarkEntry>>{};
    for (final entry in _entries) {
      final key = _bookmarkSeriesLabel(entry, l10n);
      buckets.putIfAbsent(key, () => <PlayerBookmarkEntry>[]).add(entry);
    }
    final groups =
        buckets.entries
            .map(
              (entry) => _DirectEntryGroup(
                label: entry.key,
                bookmarks: List<PlayerBookmarkEntry>.from(entry.value)
                  ..sort((a, b) => a.positionMs.compareTo(b.positionMs)),
              ),
            )
            .toList(growable: false)
          ..sort((a, b) => a.label.compareTo(b.label));
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final groups = _groups();
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: buildSecondaryHostAppBar(
        context,
        title: Text(widget.ancestorLabel),
      ),
      body: groups.isEmpty
          ? const SizedBox.shrink()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              itemCount: groups.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final group = groups[index];
                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    color: colors.surfaceSubtle,
                    border: Border.all(color: colors.borderSubtle),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          group.label,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: AdaptiveText.roleSize(
                              16,
                              role: AdaptiveFontRole.title,
                            ),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (var i = 0; i < group.bookmarks.length; i++) ...[
                          _RichBookmarkEntryRow(
                            entry: group.bookmarks[i],
                            onTap: () => _openBookmark(group.bookmarks[i]),
                            onEdit: () => _editBookmarkNote(group.bookmarks[i]),
                            onDelete: () => _deleteBookmark(group.bookmarks[i]),
                          ),
                          if (i != group.bookmarks.length - 1)
                            Divider(color: colors.borderSubtle, height: 14),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _BookmarkFolderTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _BookmarkFolderTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: colors.surfaceSubtle,
            border: Border.all(color: colors.borderSubtle),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.backgroundElevated,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: colors.textPrimary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: AdaptiveText.roleSize(
                            16,
                            role: AdaptiveFontRole.title,
                          ),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: AdaptiveText.roleSize(
                            12,
                            role: AdaptiveFontRole.body,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: colors.textMuted,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RichBookmarkEntryCard extends StatelessWidget {
  final String note;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RichBookmarkEntryCard({
    required this.note,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: colors.surfaceSubtle,
            border: Border.all(color: colors.borderSubtle),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: AdaptiveText.roleSize(
                            18,
                            role: AdaptiveFontRole.title,
                          ),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: AdaptiveText.roleSize(
                            12,
                            role: AdaptiveFontRole.body,
                          ),
                          height: 1.35,
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
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextButton(
                      onPressed: onEdit,
                      child: Text(l10n.bookmarkManagerNoteAction),
                    ),
                    TextButton(
                      onPressed: onDelete,
                      child: Text(l10n.commonDelete),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RichBookmarkEntryRow extends StatelessWidget {
  final PlayerBookmarkEntry entry;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RichBookmarkEntryRow({
    required this.entry,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${_formatBookmarkTime(entry.position)}  ·  ${_formatBookmarkCreatedAt(entry.createdAt)}',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: AdaptiveText.roleSize(
                        12,
                        role: AdaptiveFontRole.body,
                      ),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onEdit,
                  child: Text(l10n.bookmarkManagerNoteAction),
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
            if (entry.note.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 8),
                child: BookmarkNotePreview(note: entry.note),
              ),
          ],
        ),
      ),
    );
  }
}

class _AncestorGroup {
  final String label;
  final List<PlayerBookmarkEntry> entries;

  const _AncestorGroup({required this.label, required this.entries});
}

class _SeriesGroup {
  final String label;
  final List<PlayerBookmarkEntry> entries;

  const _SeriesGroup({required this.label, required this.entries});
}

class _SeasonGroup {
  final String label;
  final int order;
  final List<PlayerBookmarkEntry> entries;

  const _SeasonGroup({
    required this.label,
    required this.order,
    required this.entries,
  });
}

class _EpisodeGroup {
  final String label;
  final int order;
  final List<PlayerBookmarkEntry> bookmarks;

  const _EpisodeGroup({
    required this.label,
    required this.order,
    required this.bookmarks,
  });
}

class _DirectEntryGroup {
  final String label;
  final List<PlayerBookmarkEntry> bookmarks;

  const _DirectEntryGroup({required this.label, required this.bookmarks});
}
