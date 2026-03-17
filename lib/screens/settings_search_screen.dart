import 'dart:async';

import 'package:flutter/material.dart';

import '../services/settings_search_store.dart';
import '../theme/app_theme.dart';
import '../ui/adaptive_text.dart';
import '../ui/app_transitions.dart';

class SettingsSearchEntry {
  final String id;
  final String title;
  final String subtitle;
  final String location;
  final List<String> keywords;
  final Widget Function()? destinationBuilder;
  final VoidCallback onSelect;

  const SettingsSearchEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.location,
    required this.keywords,
    this.destinationBuilder,
    required this.onSelect,
  });

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    final haystack = <String>[
      title,
      subtitle,
      location,
      ...keywords,
    ].join(' ').toLowerCase();
    return haystack.contains(normalized);
  }

  bool startsWithQuery(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return title.toLowerCase().startsWith(normalized) ||
        subtitle.toLowerCase().startsWith(normalized);
  }
}

class SettingsSearchScreen extends StatefulWidget {
  final List<SettingsSearchEntry> entries;

  const SettingsSearchScreen({super.key, required this.entries});

  @override
  State<SettingsSearchScreen> createState() => _SettingsSearchScreenState();
}

class _SettingsSearchScreenState extends State<SettingsSearchScreen> {
  static const int _defaultVisibleCount = 6;

  final TextEditingController _controller = TextEditingController();
  final SettingsSearchStore _store = const SettingsSearchStore();

  String _query = '';
  Map<String, int> _usageById = const <String, int>{};

  @override
  void initState() {
    super.initState();
    unawaited(_loadUsage());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadUsage() async {
    final usageById = await _store.loadUsage();
    if (!mounted) return;
    setState(() => _usageById = usageById);
  }

  Future<void> _handleSelect(SettingsSearchEntry entry) async {
    unawaited(_store.recordUse(entry.id));
    if (!mounted) return;
    final destinationBuilder = entry.destinationBuilder;
    if (destinationBuilder != null) {
      await Navigator.of(context).push(
        AppTransitions.leftToRightPageTurnRoute<void>(destinationBuilder()),
      );
      return;
    }
    Navigator.of(context).pop();
    entry.onSelect();
  }

  List<SettingsSearchEntry> get _visibleEntries {
    final query = _query.trim();
    final entries =
        widget.entries.where((entry) => entry.matches(query)).toList()
          ..sort((a, b) {
            if (query.isNotEmpty) {
              final aStarts = a.startsWithQuery(query);
              final bStarts = b.startsWithQuery(query);
              if (aStarts != bStarts) {
                return aStarts ? -1 : 1;
              }
            }
            final usageCompare = (_usageById[b.id] ?? 0).compareTo(
              _usageById[a.id] ?? 0,
            );
            if (usageCompare != 0) return usageCompare;
            return a.title.compareTo(b.title);
          });
    if (query.isNotEmpty) {
      return entries;
    }
    return entries.take(_defaultVisibleCount).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final visibleEntries = _visibleEntries;
    final hasQuery = _query.trim().isNotEmpty;
    final sectionTitle = hasQuery ? '搜索结果' : '常用入口';

    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: AppBar(
        titleSpacing: 0,
        title: Container(
          height: 42,
          decoration: BoxDecoration(
            color: colors.backgroundElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.borderSubtle),
          ),
          child: Row(
            children: <Widget>[
              const SizedBox(width: 12),
              Icon(Icons.search_rounded, color: colors.textSecondary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  onChanged: (value) => setState(() => _query = value),
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: AdaptiveText.roleSize(15),
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: '搜索设置项',
                    hintStyle: TextStyle(
                      color: colors.textMuted,
                      fontSize: AdaptiveText.roleSize(15),
                    ),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              if (hasQuery)
                IconButton(
                  onPressed: () {
                    _controller.clear();
                    setState(() => _query = '');
                  },
                  icon: Icon(
                    Icons.close_rounded,
                    color: colors.textSecondary,
                    size: 18,
                  ),
                )
              else
                const SizedBox(width: 8),
            ],
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
          child: visibleEntries.isEmpty
              ? Center(
                  child: Text(
                    hasQuery ? '没有找到相关设置项。' : '先输入关键字，或从常用入口开始。',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: AdaptiveText.roleSize(14),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                      child: Text(
                        sectionTitle,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: AdaptiveText.roleSize(15.5),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    for (
                      var index = 0;
                      index < visibleEntries.length;
                      index++
                    ) ...[
                      _SearchResultTile(
                        entry: visibleEntries[index],
                        onTap: () => _handleSelect(visibleEntries[index]),
                      ),
                      if (index != visibleEntries.length - 1)
                        const SizedBox(height: 12),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final SettingsSearchEntry entry;
  final VoidCallback onTap;

  const _SearchResultTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.borderSubtle),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.backgroundElevated,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.manage_search_rounded,
                  color: colors.accentStrong,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.title,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: AdaptiveText.roleSize(15.5),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: AdaptiveText.roleSize(13),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry.location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.accentStrong,
                        fontSize: AdaptiveText.roleSize(12.5),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
