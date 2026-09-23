import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../desktop/desktop_environment.dart';
import '../../desktop/desktop_floating_panel.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/tv_episode_browser_models.dart';
import '../../models/tv_episode_picker_mode.dart';
import '../../theme/app_theme.dart';
import '../../ui/app_transitions.dart';
import '../../ui/detail_artwork_resolver.dart';
import '../../ui/media_detail_components.dart';
import '../common/app_modal_surface.dart';
import '../common/liquid_glass.dart';
import 'package:fly_player/widgets/common/bird_loader.dart';

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
    required String accessCode,
    required String baseUrl,
    required TvEpisodePickerLoader loader,
    required TvEpisodePickerModeChanged onModeChanged,
  }) {
    final desktop =
        DesktopEnvironment.isDesktopPlatform &&
        MediaQuery.sizeOf(context).width >= 800;
    Widget buildBody(BuildContext context) => _TvEpisodePickerSheetBody(
      desktop: desktop,
      title: title,
      seasons: seasons,
      initialSeasonGuid: initialSeasonGuid,
      initialEpisodeGuid: initialEpisodeGuid,
      initialMode: initialMode,
      rangeSize: rangeSize,
      emptyText: emptyText,
      token: token,
      accessCode: accessCode,
      baseUrl: baseUrl,
      loader: loader,
      onModeChanged: onModeChanged,
    );
    if (desktop) {
      final colors = context.appColors;
      final hasRuntimeColors = context.hasRuntimeAppColors;
      return showDialog<TvEpisodePickerSheetResult>(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.all(32),
          constraints: BoxConstraints(
            maxWidth: math.min(860, MediaQuery.sizeOf(context).width * 0.80),
          ),
          child: AppRuntimeColorScope(
            colors: colors,
            hasRuntimeColors: hasRuntimeColors,
            child: buildBody(context),
          ),
        ),
      );
    }
    return showModalBottomSheet<TvEpisodePickerSheetResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: buildBody,
    );
  }
}

class _TvEpisodePickerSheetBody extends StatefulWidget {
  final bool desktop;
  final String title;
  final List<TvEpisodeSeasonOptionData> seasons;
  final String initialSeasonGuid;
  final String initialEpisodeGuid;
  final TvEpisodePickerMode initialMode;
  final int rangeSize;
  final String emptyText;
  final String token;
  final String accessCode;
  final String baseUrl;
  final TvEpisodePickerLoader loader;
  final TvEpisodePickerModeChanged onModeChanged;

  const _TvEpisodePickerSheetBody({
    required this.desktop,
    required this.title,
    required this.seasons,
    required this.initialSeasonGuid,
    required this.initialEpisodeGuid,
    required this.initialMode,
    required this.rangeSize,
    required this.emptyText,
    required this.token,
    required this.accessCode,
    required this.baseUrl,
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
    final height = widget.desktop
        ? math.min(
            600.0,
            math.max(0.0, media.size.height - media.padding.vertical) * 0.78,
          )
        : media.size.height * 0.72;
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
      child: SizedBox(
        width: widget.desktop ? double.infinity : null,
        height: height,
        child: _buildSurface(
          media: media,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.desktop) ...[
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
              ],
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
                          ? const SizedBox(
                              key: ValueKey<String>('saving'),
                              width: 20,
                              height: 20,
                              child: BirdGlyph(size: 20),
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
                  if (widget.desktop)
                    IconButton(
                      tooltip: AppLocalizations.of(context).commonClose,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        Icons.close_rounded,
                        color: colors.textSecondary,
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
                                fontSize: widget.desktop ? 13 : 17,
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
                              color:
                                  widget.seasons[i].guid == _selectedSeasonGuid
                                  ? colors.selection
                                  : colors.textSecondary,
                              fontSize: widget.desktop ? 14 : 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              if (!widget.desktop || ranges.length > 1)
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
                      ? const Center(child: BirdLoader(size: 96))
                      : visibleEntries.isEmpty
                      ? _EmptySheetState(text: widget.emptyText)
                      : _mode == TvEpisodePickerMode.list
                      ? _EpisodeListView(
                          key: ValueKey<String>(
                            'list-${visibleEntries.length}-$_selectedSeasonGuid-$safeRangeIndex',
                          ),
                          desktop: widget.desktop,
                          entries: visibleEntries,
                          initialEpisodeGuid: widget.initialEpisodeGuid,
                          token: widget.token,
                          accessCode: widget.accessCode,
                          baseUrl: widget.baseUrl,
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
                            'grid-${visibleEntries.length}-$_selectedSeasonGuid-$safeRangeIndex',
                          ),
                          desktop: widget.desktop,
                          entries: visibleEntries,
                          initialEpisodeGuid: widget.initialEpisodeGuid,
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
      ),
    );
  }

  Widget _buildSurface({required MediaQueryData media, required Widget child}) {
    if (widget.desktop) {
      return DesktopFloatingPanel(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: child,
        ),
      );
    }
    return AppModalSurface(
      key: const ValueKey<String>('app-modal-surface-episode-picker'),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: media.padding.bottom > 0 ? media.padding.bottom : 16,
      ),
      child: child,
    );
  }

  int _preferredRangeIndex(
    List<TvEpisodeCardData> entries, {
    required String selectedEpisodeGuid,
    required int rangeSize,
  }) {
    if (entries.isEmpty || rangeSize <= 0) return 0;
    final index = _currentEpisodeIndex(entries, selectedEpisodeGuid);
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

int _currentEpisodeIndex(List<TvEpisodeCardData> entries, String episodeGuid) {
  final selectedIndex = entries.indexWhere((entry) => entry.selected);
  return selectedIndex >= 0
      ? selectedIndex
      : entries.indexWhere((entry) => entry.guid == episodeGuid);
}

// 只在视图首次创建时定位，后续重建不会覆盖用户手动滚动的位置。
double _initialEpisodeOffset({
  required List<TvEpisodeCardData> entries,
  required String episodeGuid,
  required int columns,
  required double rowHeight,
  required double spacing,
  required double viewportHeight,
}) {
  final index = _currentEpisodeIndex(entries, episodeGuid);
  if (index < 0) return 0;
  final stride = rowHeight + spacing;
  final contentHeight =
      ((entries.length + columns - 1) ~/ columns) * stride - spacing;
  return ((index ~/ columns) * stride - (viewportHeight - rowHeight) / 2).clamp(
    0.0,
    math.max(0.0, contentHeight - viewportHeight),
  );
}

class _EpisodeListView extends StatefulWidget {
  final bool desktop;
  final List<TvEpisodeCardData> entries;
  final String initialEpisodeGuid;
  final String token;
  final String accessCode;
  final String baseUrl;
  final ValueChanged<String> onTap;

  const _EpisodeListView({
    super.key,
    required this.desktop,
    required this.entries,
    required this.initialEpisodeGuid,
    required this.token,
    required this.accessCode,
    required this.baseUrl,
    required this.onTap,
  });

  @override
  State<_EpisodeListView> createState() => _EpisodeListViewState();
}

class _EpisodeListViewState extends State<_EpisodeListView> {
  ScrollController? _scrollController;

  @override
  void dispose() {
    _scrollController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.desktop) {
      return ListView.separated(
        itemCount: widget.entries.length,
        padding: EdgeInsets.zero,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: _buildEntry,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 640 ? 2 : 1;
        final controller = _scrollController ??= ScrollController(
          initialScrollOffset: _initialEpisodeOffset(
            entries: widget.entries,
            episodeGuid: widget.initialEpisodeGuid,
            columns: columns,
            rowHeight: 80,
            spacing: 12,
            viewportHeight: constraints.maxHeight,
          ),
        );
        return Scrollbar(
          controller: controller,
          thumbVisibility: true,
          child: GridView.builder(
            controller: controller,
            itemCount: widget.entries.length,
            padding: const EdgeInsets.only(right: 12),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisExtent: 80,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
            ),
            itemBuilder: _buildEntry,
          ),
        );
      },
    );
  }

  Widget _buildEntry(BuildContext context, int index) {
    final colors = context.appColors;
    final entry = widget.entries[index];
    final duration = Text(
      entry.durationText,
      maxLines: widget.desktop ? 1 : null,
      overflow: widget.desktop ? TextOverflow.ellipsis : null,
      style: TextStyle(
        color: colors.textSecondary,
        fontSize: widget.desktop ? 11 : 13,
      ),
    );
    final status = Text(
      entry.statusLabel,
      style: TextStyle(
        color: _episodeStatusColor(context, entry.statusTone),
        fontSize: widget.desktop ? 11 : 13,
        fontWeight: FontWeight.w600,
      ),
    );
    return InkWell(
      onTap: () => widget.onTap(entry.guid),
      borderRadius: BorderRadius.circular(widget.desktop ? 10 : 14),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: widget.desktop && !entry.selected
            ? BoxDecoration(
                color: colors.surface.withValues(alpha: 0.40),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: colors.borderSubtle.withValues(alpha: 0.60),
                  width: 0.7,
                ),
              )
            : liquidGlassDecoration(
                context,
                radius: widget.desktop ? 10 : 14,
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
                width: widget.desktop ? 96 : 122,
                height: widget.desktop ? 54 : 68,
                child: DetailHeroImage(
                  images: preferPreservedImageRequest(
                    preserved: entry.imageRequest,
                    fallbackUrls: entry.imageUrls,
                    fallbackToken: widget.token,
                    fallbackAccessCode: widget.accessCode,
                    fallbackBaseUrl: widget.baseUrl,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: widget.desktop
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: widget.desktop ? 13 : 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: widget.desktop ? 6 : 8),
                  if (widget.desktop)
                    Row(
                      children: [
                        Expanded(child: duration),
                        const SizedBox(width: 8),
                        status,
                      ],
                    )
                  else
                    duration,
                ],
              ),
            ),
            if (!widget.desktop) ...[const SizedBox(width: 12), status],
          ],
        ),
      ),
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

class _EpisodeGridView extends StatefulWidget {
  final bool desktop;
  final List<TvEpisodeCardData> entries;
  final String initialEpisodeGuid;
  final ValueChanged<String> onTap;

  const _EpisodeGridView({
    super.key,
    required this.desktop,
    required this.entries,
    required this.initialEpisodeGuid,
    required this.onTap,
  });

  @override
  State<_EpisodeGridView> createState() => _EpisodeGridViewState();
}

class _EpisodeGridViewState extends State<_EpisodeGridView> {
  ScrollController? _scrollController;

  @override
  void dispose() {
    _scrollController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = widget.desktop
            ? math.max(1, (constraints.maxWidth - 12) ~/ 80)
            : constraints.maxWidth >= 320
            ? 6
            : 5;
        if (widget.desktop) {
          _scrollController ??= ScrollController(
            initialScrollOffset: _initialEpisodeOffset(
              entries: widget.entries,
              episodeGuid: widget.initialEpisodeGuid,
              columns: crossAxisCount,
              rowHeight:
                  (constraints.maxWidth - 12 - 10 * (crossAxisCount - 1)) /
                  crossAxisCount,
              spacing: 10,
              viewportHeight: constraints.maxHeight,
            ),
          );
        }
        final grid = GridView.builder(
          controller: widget.desktop ? _scrollController : null,
          itemCount: widget.entries.length,
          padding: widget.desktop
              ? const EdgeInsets.only(right: 12)
              : EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1,
          ),
          itemBuilder: (context, index) {
            final entry = widget.entries[index];
            final selected = entry.selected;
            return InkWell(
              onTap: () => widget.onTap(entry.guid),
              borderRadius: BorderRadius.circular(widget.desktop ? 10 : 12),
              child: AnimatedContainer(
                duration: AppTransitions.switchDuration,
                curve: Curves.easeOutCubic,
                decoration: widget.desktop && !selected
                    ? BoxDecoration(
                        color: colors.surface.withValues(alpha: 0.40),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: colors.borderSubtle.withValues(alpha: 0.60),
                          width: 0.7,
                        ),
                      )
                    : liquidGlassDecoration(
                        context,
                        radius: widget.desktop ? 10 : 12,
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
        return widget.desktop
            ? Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: grid,
              )
            : grid;
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
