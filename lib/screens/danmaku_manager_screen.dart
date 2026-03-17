import 'dart:async';

import 'package:flutter/material.dart';

import '../danmaku/models/danmaku_saved_source.dart';
import '../danmaku/settings/danmaku_saved_source_store.dart';
import '../theme/app_theme.dart';
import '../ui/adaptive_text.dart';
import '../ui/app_transitions.dart';

bool _sourceIsTv(DanmakuSavedSource source) {
  final type = source.mediaType.trim().toLowerCase();
  if (type == 'episode' || type == 'tv') return true;
  if (type == 'movie') return false;
  return source.seriesTitle.trim().isNotEmpty || source.seasonNumber > 0;
}

String _sourceAncestorLabel(DanmakuSavedSource source) {
  final label = source.ancestorName.trim();
  if (label.isNotEmpty) return label;
  return '旧来源';
}

String _sourceSeriesLabel(DanmakuSavedSource source) {
  final label = source.seriesTitle.trim();
  if (label.isNotEmpty) return label;
  final itemTitle = source.itemTitle.trim();
  if (itemTitle.isNotEmpty) return itemTitle;
  final fallback = source.label.trim();
  if (fallback.isNotEmpty) return fallback;
  return '未命名条目';
}

String _sourceSeasonLabel(DanmakuSavedSource source) {
  if (source.seasonNumber <= 0) return '特别篇';
  return '第${source.seasonNumber}季';
}

String _formatSourceTime(int updatedAtMs) {
  if (updatedAtMs <= 0) return '';
  final value = DateTime.fromMillisecondsSinceEpoch(updatedAtMs, isUtc: false);
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$month-$day $hour:$minute';
}

class DanmakuManagerScreen extends StatefulWidget {
  const DanmakuManagerScreen({super.key});

  @override
  State<DanmakuManagerScreen> createState() => _DanmakuManagerScreenState();
}

class _DanmakuManagerScreenState extends State<DanmakuManagerScreen> {
  final DanmakuSavedSourceStore _store = const DanmakuSavedSourceStore();

  List<DanmakuSavedSource> _sources = const <DanmakuSavedSource>[];
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
    final sources = await _store.loadAll();
    if (!mounted) return;
    setState(() {
      _sources = sources;
      _loading = false;
    });
  }

  List<_DanmakuAncestorGroup> _ancestorGroups() {
    final buckets = <String, List<DanmakuSavedSource>>{};
    for (final source in _sources) {
      final key = _sourceAncestorLabel(source);
      buckets.putIfAbsent(key, () => <DanmakuSavedSource>[]).add(source);
    }
    final groups =
        buckets.entries
            .map(
              (entry) => _DanmakuAncestorGroup(
                label: entry.key,
                sources: List<DanmakuSavedSource>.from(entry.value)
                  ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs)),
              ),
            )
            .toList(growable: false)
          ..sort(
            (a, b) => b.sources.first.updatedAtMs.compareTo(
              a.sources.first.updatedAtMs,
            ),
          );
    return groups;
  }

  Future<void> _openAncestor(_DanmakuAncestorGroup group) async {
    final hasTvEntries = group.sources.any(_sourceIsTv);
    final routePage = hasTvEntries
        ? _DanmakuSeriesListScreen(
            ancestorLabel: group.label,
            sources: group.sources.where(_sourceIsTv).toList(growable: false),
          )
        : _DanmakuDirectEntryScreen(
            ancestorLabel: group.label,
            sources: group.sources,
          );
    await Navigator.of(
      context,
    ).push(AppTransitions.leftToRightPageTurnRoute(routePage));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final groups = _ancestorGroups();
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: AppBar(
        title: Text(
          '弹幕管理',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: AdaptiveText.roleSize(20, role: AdaptiveFontRole.title),
            fontWeight: FontWeight.w700,
          ),
        ),
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
                    '还没有已保存的弹幕来源',
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
                    return _DanmakuFolderTile(
                      icon: Icons.folder_copy_outlined,
                      title: group.label,
                      subtitle: '共 ${group.sources.length} 个来源',
                      onTap: () => _openAncestor(group),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _DanmakuSeriesListScreen extends StatefulWidget {
  final String ancestorLabel;
  final List<DanmakuSavedSource> sources;

  const _DanmakuSeriesListScreen({
    required this.ancestorLabel,
    required this.sources,
  });

  @override
  State<_DanmakuSeriesListScreen> createState() =>
      _DanmakuSeriesListScreenState();
}

class _DanmakuSeriesListScreenState extends State<_DanmakuSeriesListScreen> {
  final DanmakuSavedSourceStore _store = const DanmakuSavedSourceStore();
  late List<DanmakuSavedSource> _sources = List<DanmakuSavedSource>.from(
    widget.sources,
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
    setState(() {
      _sources =
          all
              .where(
                (source) =>
                    _sourceIsTv(source) &&
                    _sourceAncestorLabel(source) == widget.ancestorLabel,
              )
              .toList(growable: false)
            ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    });
  }

  List<_DanmakuSeriesGroup> _seriesGroups() {
    final buckets = <String, List<DanmakuSavedSource>>{};
    for (final source in _sources) {
      final key = _sourceSeriesLabel(source);
      buckets.putIfAbsent(key, () => <DanmakuSavedSource>[]).add(source);
    }
    final groups =
        buckets.entries
            .map(
              (entry) => _DanmakuSeriesGroup(
                label: entry.key,
                sources: List<DanmakuSavedSource>.from(entry.value)
                  ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs)),
              ),
            )
            .toList(growable: false)
          ..sort(
            (a, b) => b.sources.first.updatedAtMs.compareTo(
              a.sources.first.updatedAtMs,
            ),
          );
    return groups;
  }

  Future<void> _openSeries(_DanmakuSeriesGroup group) async {
    await Navigator.of(context).push(
      AppTransitions.leftToRightPageTurnRoute(
        _DanmakuSeasonListScreen(
          ancestorLabel: widget.ancestorLabel,
          seriesLabel: group.label,
          sources: group.sources,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = _seriesGroups();
    return Scaffold(
      backgroundColor: context.appColors.backgroundBase,
      appBar: AppBar(title: Text(widget.ancestorLabel)),
      body: groups.isEmpty
          ? const SizedBox.shrink()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              itemCount: groups.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final group = groups[index];
                return _DanmakuFolderTile(
                  icon: Icons.tv_outlined,
                  title: group.label,
                  subtitle: '共 ${group.sources.length} 个来源',
                  onTap: () => _openSeries(group),
                );
              },
            ),
    );
  }
}

class _DanmakuSeasonListScreen extends StatefulWidget {
  final String ancestorLabel;
  final String seriesLabel;
  final List<DanmakuSavedSource> sources;

  const _DanmakuSeasonListScreen({
    required this.ancestorLabel,
    required this.seriesLabel,
    required this.sources,
  });

  @override
  State<_DanmakuSeasonListScreen> createState() =>
      _DanmakuSeasonListScreenState();
}

class _DanmakuSeasonListScreenState extends State<_DanmakuSeasonListScreen> {
  final DanmakuSavedSourceStore _store = const DanmakuSavedSourceStore();
  late List<DanmakuSavedSource> _sources = List<DanmakuSavedSource>.from(
    widget.sources,
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
    setState(() {
      _sources =
          all
              .where(
                (source) =>
                    _sourceIsTv(source) &&
                    _sourceAncestorLabel(source) == widget.ancestorLabel &&
                    _sourceSeriesLabel(source) == widget.seriesLabel,
              )
              .toList(growable: false)
            ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    });
  }

  List<_DanmakuSeasonGroup> _seasonGroups() {
    final buckets = <String, List<DanmakuSavedSource>>{};
    final orders = <String, int>{};
    for (final source in _sources) {
      final key = _sourceSeasonLabel(source);
      buckets.putIfAbsent(key, () => <DanmakuSavedSource>[]).add(source);
      orders[key] = source.seasonNumber <= 0 ? 0 : source.seasonNumber;
    }
    final groups =
        buckets.entries
            .map(
              (entry) => _DanmakuSeasonGroup(
                label: entry.key,
                order: orders[entry.key] ?? 9999,
                sources: List<DanmakuSavedSource>.from(entry.value)
                  ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs)),
              ),
            )
            .toList(growable: false)
          ..sort((a, b) => a.order.compareTo(b.order));
    return groups;
  }

  Future<void> _openSeason(_DanmakuSeasonGroup group) async {
    await Navigator.of(context).push(
      AppTransitions.leftToRightPageTurnRoute(
        _DanmakuSeasonDetailScreen(
          ancestorLabel: widget.ancestorLabel,
          seriesLabel: widget.seriesLabel,
          seasonLabel: group.label,
          sources: group.sources,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = _seasonGroups();
    return Scaffold(
      backgroundColor: context.appColors.backgroundBase,
      appBar: AppBar(title: Text(widget.seriesLabel)),
      body: groups.isEmpty
          ? const SizedBox.shrink()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              itemCount: groups.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final group = groups[index];
                return _DanmakuFolderTile(
                  icon: Icons.video_library_outlined,
                  title: group.label,
                  subtitle: '共 ${group.sources.length} 个来源',
                  onTap: () => _openSeason(group),
                );
              },
            ),
    );
  }
}

class _DanmakuSeasonDetailScreen extends StatefulWidget {
  final String ancestorLabel;
  final String seriesLabel;
  final String seasonLabel;
  final List<DanmakuSavedSource> sources;

  const _DanmakuSeasonDetailScreen({
    required this.ancestorLabel,
    required this.seriesLabel,
    required this.seasonLabel,
    required this.sources,
  });

  @override
  State<_DanmakuSeasonDetailScreen> createState() =>
      _DanmakuSeasonDetailScreenState();
}

class _DanmakuSeasonDetailScreenState
    extends State<_DanmakuSeasonDetailScreen> {
  final DanmakuSavedSourceStore _store = const DanmakuSavedSourceStore();
  late List<DanmakuSavedSource> _sources = List<DanmakuSavedSource>.from(
    widget.sources,
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
    setState(() {
      _sources =
          all
              .where(
                (source) =>
                    _sourceIsTv(source) &&
                    _sourceAncestorLabel(source) == widget.ancestorLabel &&
                    _sourceSeriesLabel(source) == widget.seriesLabel &&
                    _sourceSeasonLabel(source) == widget.seasonLabel,
              )
              .toList(growable: false)
            ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    });
  }

  Future<void> _deleteSource(DanmakuSavedSource source) async {
    await _store.removeSource(
      mediaKey: source.mediaKey,
      sourceKey: source.sourceKey,
    );
  }

  @override
  Widget build(BuildContext context) {
    final localSources = _sources
        .where((source) => source.isLocalFile)
        .toList(growable: false);
    final networkSources = _sources
        .where((source) => source.isDanDanPlay)
        .toList(growable: false);
    return Scaffold(
      backgroundColor: context.appColors.backgroundBase,
      appBar: AppBar(title: Text(widget.seasonLabel)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          if (networkSources.isNotEmpty) ...<Widget>[
            const _DanmakuSectionHeader(title: '网络弹幕'),
            const SizedBox(height: 10),
            _DanmakuSourceGroupCard(
              sources: networkSources,
              onDelete: _deleteSource,
            ),
            const SizedBox(height: 16),
          ],
          if (localSources.isNotEmpty) ...<Widget>[
            const _DanmakuSectionHeader(title: '本地导入'),
            const SizedBox(height: 10),
            _DanmakuSourceGroupCard(
              sources: localSources,
              onDelete: _deleteSource,
            ),
          ],
        ],
      ),
    );
  }
}

class _DanmakuDirectEntryScreen extends StatefulWidget {
  final String ancestorLabel;
  final List<DanmakuSavedSource> sources;

  const _DanmakuDirectEntryScreen({
    required this.ancestorLabel,
    required this.sources,
  });

  @override
  State<_DanmakuDirectEntryScreen> createState() =>
      _DanmakuDirectEntryScreenState();
}

class _DanmakuDirectEntryScreenState extends State<_DanmakuDirectEntryScreen> {
  final DanmakuSavedSourceStore _store = const DanmakuSavedSourceStore();
  late List<DanmakuSavedSource> _sources = List<DanmakuSavedSource>.from(
    widget.sources,
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
    setState(() {
      _sources =
          all
              .where(
                (source) =>
                    !_sourceIsTv(source) &&
                    _sourceAncestorLabel(source) == widget.ancestorLabel,
              )
              .toList(growable: false)
            ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    });
  }

  Future<void> _deleteSource(DanmakuSavedSource source) async {
    await _store.removeSource(
      mediaKey: source.mediaKey,
      sourceKey: source.sourceKey,
    );
  }

  List<_DanmakuDirectGroup> _groups() {
    final buckets = <String, List<DanmakuSavedSource>>{};
    for (final source in _sources) {
      final key = _sourceSeriesLabel(source);
      buckets.putIfAbsent(key, () => <DanmakuSavedSource>[]).add(source);
    }
    final groups =
        buckets.entries
            .map(
              (entry) => _DanmakuDirectGroup(
                label: entry.key,
                sources: List<DanmakuSavedSource>.from(entry.value)
                  ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs)),
              ),
            )
            .toList(growable: false)
          ..sort(
            (a, b) => b.sources.first.updatedAtMs.compareTo(
              a.sources.first.updatedAtMs,
            ),
          );
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final groups = _groups();
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: AppBar(title: Text(widget.ancestorLabel)),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        itemCount: groups.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final group = groups[index];
          final networkSources = group.sources
              .where((source) => source.isDanDanPlay)
              .toList(growable: false);
          final localSources = group.sources
              .where((source) => source.isLocalFile)
              .toList(growable: false);
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
                  if (networkSources.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    const _DanmakuSectionHeader(title: '网络弹幕'),
                    const SizedBox(height: 8),
                    _DanmakuSourceGroupCard(
                      sources: networkSources,
                      onDelete: _deleteSource,
                    ),
                  ],
                  if (localSources.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    const _DanmakuSectionHeader(title: '本地导入'),
                    const SizedBox(height: 8),
                    _DanmakuSourceGroupCard(
                      sources: localSources,
                      onDelete: _deleteSource,
                    ),
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

class _DanmakuSourceGroupCard extends StatelessWidget {
  final List<DanmakuSavedSource> sources;
  final Future<void> Function(DanmakuSavedSource source) onDelete;

  const _DanmakuSourceGroupCard({
    required this.sources,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: colors.surface.withValues(alpha: 0.72),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          children: [
            for (var i = 0; i < sources.length; i++) ...<Widget>[
              _DanmakuSourceRow(
                source: sources[i],
                onDelete: () => onDelete(sources[i]),
              ),
              if (i != sources.length - 1)
                Divider(height: 14, color: colors.borderSubtle),
            ],
          ],
        ),
      ),
    );
  }
}

class _DanmakuSourceRow extends StatelessWidget {
  final DanmakuSavedSource source;
  final VoidCallback onDelete;

  const _DanmakuSourceRow({required this.source, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final meta = <String>[
      if (source.commentCount > 0) '${source.commentCount} 条',
      if (_formatSourceTime(source.updatedAtMs).isNotEmpty)
        _formatSourceTime(source.updatedAtMs),
    ].join('  ·  ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  source.label.trim().isEmpty ? '未命名弹幕来源' : source.label.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: AdaptiveText.roleSize(
                      14,
                      role: AdaptiveFontRole.title,
                    ),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (source.detail.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    source.detail.trim(),
                    maxLines: 2,
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
                if (meta.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    meta,
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: AdaptiveText.roleSize(
                        11,
                        role: AdaptiveFontRole.body,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton(onPressed: onDelete, child: const Text('删除')),
        ],
      ),
    );
  }
}

class _DanmakuFolderTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DanmakuFolderTile({
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

class _DanmakuSectionHeader extends StatelessWidget {
  final String title;

  const _DanmakuSectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        color: context.appColors.textSecondary,
        fontSize: AdaptiveText.roleSize(13, role: AdaptiveFontRole.body),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _DanmakuAncestorGroup {
  final String label;
  final List<DanmakuSavedSource> sources;

  const _DanmakuAncestorGroup({required this.label, required this.sources});
}

class _DanmakuSeriesGroup {
  final String label;
  final List<DanmakuSavedSource> sources;

  const _DanmakuSeriesGroup({required this.label, required this.sources});
}

class _DanmakuSeasonGroup {
  final String label;
  final int order;
  final List<DanmakuSavedSource> sources;

  const _DanmakuSeasonGroup({
    required this.label,
    required this.order,
    required this.sources,
  });
}

class _DanmakuDirectGroup {
  final String label;
  final List<DanmakuSavedSource> sources;

  const _DanmakuDirectGroup({required this.label, required this.sources});
}
