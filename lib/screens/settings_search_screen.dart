import 'dart:async';

import 'package:flutter/material.dart';

import '../desktop/desktop_floating_panel.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/settings_search_store.dart';
import '../theme/app_theme.dart';
import '../ui/adaptive_text.dart';
import '../widgets/common/app_ambient_page.dart';

class SettingsSearchEntry {
  final String id;
  final String title;
  final String subtitle;
  final String location;
  final List<String> keywords;
  final Future<void> Function() onSelect;

  const SettingsSearchEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.location,
    required this.keywords,
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

  final bool asPanel;
  final TextEditingController? controller;
  final VoidCallback? onClose;

  const SettingsSearchScreen({
    super.key,
    required this.entries,
    this.asPanel = false,
    this.controller,
    this.onClose,
  }) : assert(!asPanel || (controller != null && onClose != null));

  @override
  State<SettingsSearchScreen> createState() => _SettingsSearchScreenState();
}

class _SettingsSearchScreenState extends State<SettingsSearchScreen> {
  static const int _defaultVisibleCount = 6;

  late final TextEditingController _controller;
  final SettingsSearchStore _store = const SettingsSearchStore();

  String _query = '';
  Map<String, int> _usageById = const <String, int>{};

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _query = _controller.text;
    _controller.addListener(_handleQueryChanged);
    unawaited(_loadUsage());
  }

  @override
  void dispose() {
    _controller.removeListener(_handleQueryChanged);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _handleQueryChanged() {
    if (_query != _controller.text) {
      setState(() => _query = _controller.text);
    }
  }

  Future<void> _loadUsage() async {
    final usageById = await _store.loadUsage();
    if (!mounted) return;
    setState(() => _usageById = usageById);
  }

  Future<void> _handleSelect(SettingsSearchEntry entry) async {
    unawaited(_store.recordUse(entry.id));
    if (!mounted) return;
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context).pop();
    }
    await entry.onSelect();
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
    final l10n = AppLocalizations.of(context);
    final sectionTitle = hasQuery
        ? l10n.settingsSearchResults
        : l10n.settingsSearchFrequent;

    final searchField = Container(
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
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: AdaptiveText.roleSize(15),
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: l10n.settingsSearchHint,
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
    );
    final body = SafeArea(
      top: false,
      child: visibleEntries.isEmpty
          ? Center(
              child: Text(
                hasQuery
                    ? l10n.settingsSearchEmptyResults
                    : l10n.settingsSearchEmptyPrompt,
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
                for (var index = 0; index < visibleEntries.length; index++) ...[
                  _SearchResultTile(
                    entry: visibleEntries[index],
                    inPanel: widget.asPanel,
                    onTap: () => _handleSelect(visibleEntries[index]),
                  ),
                  if (index != visibleEntries.length - 1)
                    SizedBox(height: widget.asPanel ? 4 : 12),
                ],
              ],
            ),
    );
    if (widget.asPanel) {
      return DesktopFloatingPanel(child: body);
    }
    return AppAmbientPage(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(titleSpacing: 0, title: searchField),
        body: body,
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final SettingsSearchEntry entry;
  final VoidCallback onTap;
  final bool inPanel;

  const _SearchResultTile({
    required this.entry,
    required this.onTap,
    this.inPanel = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(inPanel ? 10 : 20),
        onTap: onTap,
        child: Ink(
          padding: EdgeInsets.all(inPanel ? 12 : 16),
          decoration: BoxDecoration(
            color: inPanel ? Colors.transparent : colors.surface,
            borderRadius: BorderRadius.circular(inPanel ? 10 : 20),
            border: inPanel ? null : Border.all(color: colors.borderSubtle),
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
