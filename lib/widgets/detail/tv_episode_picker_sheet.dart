import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/tv_episode_browser_models.dart';
import '../../models/tv_episode_picker_mode.dart';
import '../../theme/app_theme.dart';
import '../../ui/app_transitions.dart';
import '../../ui/detail_artwork_resolver.dart';
import '../../ui/media_detail_components.dart';
import '../common/liquid_glass.dart';

typedef TvEpisodePickerLoader =
    Future<TvEpisodePickerPayload> Function(String seasonGuid);
typedef TvEpisodePickerModeChanged =
    Future<void> Function(TvEpisodePickerMode mode);

class TvEpisodePickerSheetResult {
  final String seasonGuid;
  final String episodeGuid;
  final TvEpisodePickerMode mode;
  final bool openDetail;

  const TvEpisodePickerSheetResult({
    required this.seasonGuid,
    required this.episodeGuid,
    required this.mode,
    this.openDetail = false,
  });
}

class TvEpisodePickerSheet {
  static Future<TvEpisodePickerSheetResult?> show(
    BuildContext context, {
    required String title,
    required List<TvEpisodeSeasonOptionData> seasons,
    required String initialSeasonGuid,
    required String initialEpisodeGuid,
    required TvEpisodePickerMode initialMode,
    required int rangeSize,
    required String emptyText,
    required String token,
    required TvEpisodePickerLoader loader,
    required TvEpisodePickerModeChanged onModeChanged,
  }) {
    return showModalBottomSheet<TvEpisodePickerSheetResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _TvEpisodePickerSheetBody(
          title: title,
          seasons: seasons,
          initialSeasonGuid: initialSeasonGuid,
          initialEpisodeGuid: initialEpisodeGuid,
          initialMode: initialMode,
          rangeSize: rangeSize,
          emptyText: emptyText,
          token: token,
          loader: loader,
          onModeChanged: onModeChanged,
        );
      },
    );
  }
}

class _TvEpisodePickerSheetBody extends StatefulWidget {
  final String title;
  final List<TvEpisodeSeasonOptionData> seasons;
  final String initialSeasonGuid;
  final String initialEpisodeGuid;
  final TvEpisodePickerMode initialMode;
  final int rangeSize;
  final String emptyText;
  final String token;
  final TvEpisodePickerLoader loader;
  final TvEpisodePickerModeChanged onModeChanged;

  const _TvEpisodePickerSheetBody({
    required this.title,
    required this.seasons,
    required this.initialSeasonGuid,
    required this.initialEpisodeGuid,
    required this.initialMode,
    required this.rangeSize,
    required this.emptyText,
    required this.token,
    required this.loader,
    required this.onModeChanged,
  });

  @override
  State<_TvEpisodePickerSheetBody> createState() =>
      _TvEpisodePickerSheetBodyState();
}

class _TvEpisodePickerSheetBodyState extends State<_TvEpisodePickerSheetBody> {
  late String _selectedSeasonGuid;
  late TvEpisodePickerMode _mode;
  bool _loading = true;
  bool _modeUpdating = false;
  TvEpisodePickerPayload _payload = const TvEpisodePickerPayload(
    totalCount: 0,
    entries: <TvEpisodeCardData>[],
  );
  int _rangeIndex = 0;

  @override
  void initState() {
    super.initState();
    _selectedSeasonGuid = widget.initialSeasonGuid;
    _mode = widget.initialMode;
    _loadSeason(_selectedSeasonGuid);
  }

  Future<void> _loadSeason(String seasonGuid) async {
    setState(() => _loading = true);
    final payload = await widget.loader(seasonGuid);
    if (!mounted || _selectedSeasonGuid != seasonGuid) return;
    setState(() {
      _payload = payload;
      _rangeIndex = _preferredRangeIndex(
        payload.entries,
        selectedEpisodeGuid: widget.initialEpisodeGuid,
        rangeSize: widget.rangeSize,
      );
      _loading = false;
    });
  }

  Future<void> _toggleMode() async {
    if (_modeUpdating) return;
    final previousMode = _mode;
    final nextMode = previousMode == TvEpisodePickerMode.list
        ? TvEpisodePickerMode.grid
        : TvEpisodePickerMode.list;
    setState(() {
      _mode = nextMode;
      _modeUpdating = true;
    });
    try {
      await widget.onModeChanged(nextMode);
    } catch (_) {
      if (!mounted) return;
      setState(() => _mode = previousMode);
    } finally {
      if (mounted) {
        setState(() => _modeUpdating = false);
      } else {
        _modeUpdating = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final media = MediaQuery.of(context);
    final height = media.size.height * 0.72;
    final ranges = _buildEpisodeRanges(
      _payload.entries,
      rangeSize: widget.rangeSize,
    );
    final safeRangeIndex = ranges.isEmpty
        ? 0
        : _rangeIndex.clamp(0, ranges.length - 1);
    final visibleEntries = ranges.isEmpty
        ? const <TvEpisodeCardData>[]
        : ranges[safeRangeIndex];

    return SafeArea(
      top: false,
      bottom: false,
      child: Container(
        height: height,
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 10,
          bottom: media.padding.bottom > 0 ? media.padding.bottom : 16,
        ),
        decoration: BoxDecoration(
          color: colors.backgroundElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.borderStrong,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      color: colors.accent,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _modeUpdating
                      ? null
                      : () {
                          unawaited(_toggleMode());
                        },
                  splashRadius: 22,
                  icon: AnimatedSwitcher(
                    duration: AppTransitions.switchDuration,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeOutCubic,
                    child: _modeUpdating
                        ? SizedBox(
                            key: const ValueKey<String>('saving'),
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.accent,
                            ),
                          )
                        : Icon(
                            key: ValueKey<TvEpisodePickerMode>(_mode),
                            _mode == TvEpisodePickerMode.list
                                ? Icons.grid_view_rounded
                                : Icons.view_list_rounded,
                            color: colors.textSecondary,
                          ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (widget.seasons.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (int i = 0; i < widget.seasons.length; i++) ...[
                      if (i > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            '/',
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      InkWell(
                        onTap: () {
                          final guid = widget.seasons[i].guid;
                          if (guid == _selectedSeasonGuid) return;
                          setState(() => _selectedSeasonGuid = guid);
                          _loadSeason(guid);
                        },
                        child: Text(
                          widget.seasons[i].label,
                          style: TextStyle(
                            color: widget.seasons[i].guid == _selectedSeasonGuid
                                ? colors.selection
                                : colors.textSecondary,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 14),
            if (ranges.length > 1)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: ranges.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final start = index * widget.rangeSize + 1;
                      final end = start + ranges[index].length - 1;
                      final selected = index == safeRangeIndex;
                      return InkWell(
                        onTap: () => setState(() => _rangeIndex = index),
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedContainer(
                          duration: AppTransitions.switchDuration,
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: liquidGlassDecoration(
                            context,
                            radius: 10,
                            tone: selected
                                ? LiquidGlassTone.accent
                                : LiquidGlassTone.neutral,
                            selected: selected,
                          ),
                          child: Text(
                            '$start - $end',
                            style: TextStyle(
                              color: selected
                                  ? colors.selectionStrong
                                  : colors.textSecondary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            const SizedBox(height: 14),
            Expanded(
              child: AnimatedSwitcher(
                duration: AppTransitions.contentSwitchDuration,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeOutCubic,
                child: _loading
                    ? Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.accent,
                        ),
                      )
                    : visibleEntries.isEmpty
                    ? _EmptySheetState(text: widget.emptyText)
                    : _mode == TvEpisodePickerMode.list
                    ? _EpisodeListView(
                        key: ValueKey<String>(
                          'list-${visibleEntries.length}-$_selectedSeasonGuid',
                        ),
                        entries: visibleEntries,
                        token: widget.token,
                        onTap: (guid) => Navigator.of(context).pop(
                          TvEpisodePickerSheetResult(
                            seasonGuid: _selectedSeasonGuid,
                            episodeGuid: guid,
                            mode: _mode,
                            openDetail: true,
                          ),
                        ),
                      )
                    : _EpisodeGridView(
                        key: ValueKey<String>(
                          'grid-${visibleEntries.length}-$_selectedSeasonGuid',
                        ),
                        entries: visibleEntries,
                        onTap: (guid) => Navigator.of(context).pop(
                          TvEpisodePickerSheetResult(
                            seasonGuid: _selectedSeasonGuid,
                            episodeGuid: guid,
                            mode: _mode,
                            openDetail: true,
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _preferredRangeIndex(
    List<TvEpisodeCardData> entries, {
    required String selectedEpisodeGuid,
    required int rangeSize,
  }) {
    if (entries.isEmpty || rangeSize <= 0) return 0;
    final index = entries.indexWhere(
      (entry) => entry.guid == selectedEpisodeGuid,
    );
    if (index < 0) return 0;
    return index ~/ rangeSize;
  }
}

List<List<TvEpisodeCardData>> _buildEpisodeRanges(
  List<TvEpisodeCardData> entries, {
  required int rangeSize,
}) {
  if (entries.isEmpty || rangeSize <= 0) {
    return const <List<TvEpisodeCardData>>[];
  }
  final ranges = <List<TvEpisodeCardData>>[];
  for (int i = 0; i < entries.length; i += rangeSize) {
    final end = (i + rangeSize).clamp(0, entries.length);
    ranges.add(entries.sublist(i, end));
  }
  return ranges;
}

class _EpisodeListView extends StatelessWidget {
  final List<TvEpisodeCardData> entries;
  final String token;
  final ValueChanged<String> onTap;

  const _EpisodeListView({
    super.key,
    required this.entries,
    required this.token,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ListView.separated(
      itemCount: entries.length,
      padding: EdgeInsets.zero,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return InkWell(
          onTap: () => onTap(entry.guid),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: liquidGlassDecoration(
              context,
              radius: 14,
              tone: entry.selected
                  ? LiquidGlassTone.accent
                  : LiquidGlassTone.neutral,
              selected: entry.selected,
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 122,
                    height: 68,
                    child: DetailHeroImage(
                      images: mediaImageRequestForUrls(
                        entry.imageUrls,
                        token: token,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        entry.durationText,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  entry.statusLabel,
                  style: TextStyle(
                    color: _episodeStatusColor(context, entry.statusTone),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Color _episodeStatusColor(BuildContext context, TvEpisodeStatusTone tone) {
  final colors = context.appColors;
  return switch (tone) {
    TvEpisodeStatusTone.none => Colors.transparent,
    TvEpisodeStatusTone.secondary => colors.textSecondary,
    TvEpisodeStatusTone.accent => colors.accent,
  };
}

class _EpisodeGridView extends StatelessWidget {
  final List<TvEpisodeCardData> entries;
  final ValueChanged<String> onTap;

  const _EpisodeGridView({
    super.key,
    required this.entries,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 320 ? 6 : 5;
        return GridView.builder(
          itemCount: entries.length,
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1,
          ),
          itemBuilder: (context, index) {
            final entry = entries[index];
            final selected = entry.selected;
            return InkWell(
              onTap: () => onTap(entry.guid),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: AppTransitions.switchDuration,
                curve: Curves.easeOutCubic,
                decoration: liquidGlassDecoration(
                  context,
                  radius: 12,
                  tone: selected
                      ? LiquidGlassTone.accent
                      : LiquidGlassTone.neutral,
                  selected: selected,
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Text(
                        entry.shortLabel,
                        style: TextStyle(
                          color: selected
                              ? colors.selectionStrong
                              : colors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (entry.completed)
                      const Positioned(
                        right: 0,
                        bottom: 0,
                        child: _EpisodeCompletedBadge(),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _EpisodeCompletedBadge extends StatelessWidget {
  const _EpisodeCompletedBadge();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: colors.surfaceStrong,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(7),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: Center(
        child: SvgPicture.asset(
          'assets/icons/episode_completed_badge.svg',
          width: 7,
          height: 7,
          colorFilter: ColorFilter.mode(colors.textSecondary, BlendMode.srcIn),
        ),
      ),
    );
  }
}

class _EmptySheetState extends StatelessWidget {
  final String text;

  const _EmptySheetState({required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Text(
        text,
        style: TextStyle(
          color: colors.textSecondary,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
