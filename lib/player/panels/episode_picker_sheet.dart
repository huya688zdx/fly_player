import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../models/tv_episode_browser_models.dart';
import '../../models/tv_episode_picker_mode.dart';
import '../../theme/app_theme.dart';
import '../../ui/app_sheet_transitions.dart';
import '../../ui/app_transitions.dart';
import '../../utils/api_url_helper.dart';

class EpisodePickerSheetItem {
  final String id;
  final String shortLabel;
  final String title;
  final String durationLabel;
  final String statusLabel;
  final Color statusColor;
  final String posterPath;
  final bool completed;
  final bool? _isPlaying;
  final bool selected;

  bool get isPlaying => _isPlaying ?? false;

  const EpisodePickerSheetItem({
    required this.id,
    required this.shortLabel,
    required this.title,
    required this.durationLabel,
    required this.statusLabel,
    required this.statusColor,
    required this.posterPath,
    required this.completed,
    bool? isPlaying,
    required this.selected,
  }) : _isPlaying = isPlaying;
}

class EpisodePickerSeasonSheetData {
  final String seasonGuid;
  final String seasonLabel;
  final String preferredItemId;
  final List<EpisodePickerSheetItem> items;

  const EpisodePickerSeasonSheetData({
    required this.seasonGuid,
    required this.seasonLabel,
    required this.preferredItemId,
    required this.items,
  });
}

class EpisodePickerSheetResult {
  final String seasonGuid;
  final String itemId;

  const EpisodePickerSheetResult({
    required this.seasonGuid,
    required this.itemId,
  });
}

typedef EpisodePickerSeasonLoader =
    Future<EpisodePickerSeasonSheetData> Function(String seasonGuid);

class EpisodePickerSheetWarmupData {
  final EpisodePickerSeasonSheetData seasonData;
  final List<TvEpisodeSeasonOptionData> seasons;

  const EpisodePickerSheetWarmupData({
    required this.seasonData,
    required this.seasons,
  });
}

typedef EpisodePickerWarmupLoader =
    Future<EpisodePickerSheetWarmupData> Function();

class EpisodePickerSheet {
  static Future<EpisodePickerSheetResult?> show(
    BuildContext context, {
    required String barrierTitle,
    required String seriesTitle,
    required EpisodePickerSeasonSheetData initialSeasonData,
    required String initialSeasonGuid,
    required TvEpisodePickerMode initialMode,
    required int rangeSize,
    required Future<void> Function(TvEpisodePickerMode mode) onModeChanged,
    required String baseUrl,
    required String token,
    required EpisodePickerSeasonLoader seasonLoader,
    EpisodePickerWarmupLoader? warmupLoader,
    List<TvEpisodeSeasonOptionData> seasons =
        const <TvEpisodeSeasonOptionData>[],
  }) {
    return AppSheetTransitions.showAdaptiveSheet<EpisodePickerSheetResult>(
      context,
      barrierDismissible: true,
      barrierLabel: barrierTitle,
      barrierColor: context.appColors.overlayScrim.withValues(alpha: 0.32),
      builder: (_) {
        return _EpisodePickerDialog(
          barrierTitle: barrierTitle,
          seriesTitle: seriesTitle,
          initialSeasonData: initialSeasonData,
          initialSeasonGuid: initialSeasonGuid,
          initialMode: initialMode,
          rangeSize: rangeSize,
          onModeChanged: onModeChanged,
          baseUrl: baseUrl,
          token: token,
          seasonLoader: seasonLoader,
          warmupLoader: warmupLoader,
          seasons: seasons,
        );
      },
    );
  }
}

class _EpisodePickerDialog extends StatefulWidget {
  final String barrierTitle;
  final String seriesTitle;
  final EpisodePickerSeasonSheetData initialSeasonData;
  final String initialSeasonGuid;
  final TvEpisodePickerMode initialMode;
  final int rangeSize;
  final Future<void> Function(TvEpisodePickerMode mode) onModeChanged;
  final String baseUrl;
  final String token;
  final EpisodePickerSeasonLoader seasonLoader;
  final EpisodePickerWarmupLoader? warmupLoader;
  final List<TvEpisodeSeasonOptionData> seasons;

  const _EpisodePickerDialog({
    required this.barrierTitle,
    required this.seriesTitle,
    required this.initialSeasonData,
    required this.initialSeasonGuid,
    required this.initialMode,
    required this.rangeSize,
    required this.onModeChanged,
    required this.baseUrl,
    required this.token,
    required this.seasonLoader,
    this.warmupLoader,
    required this.seasons,
  });

  @override
  State<_EpisodePickerDialog> createState() => _EpisodePickerDialogState();
}

class _EpisodePickerDialogState extends State<_EpisodePickerDialog> {
  late final ScrollController _scrollController;
  late TvEpisodePickerMode _mode;
  GlobalKey _scrollTargetItemKey = GlobalKey();

  bool _modeUpdating = false;
  bool _seasonLoading = false;
  bool _warmupLoading = false;
  int _rangeIndex = 0;
  int _seasonLoadToken = 0;
  late String _selectedSeasonGuid;
  late EpisodePickerSeasonSheetData _seasonData;
  late List<TvEpisodeSeasonOptionData> _seasons;

  // Cached computations to avoid allocations in every build.
  List<List<EpisodePickerSheetItem>>? _cachedRanges;
  Object? _cachedRangesKey;
  List<TvEpisodeSeasonOptionData>? _cachedSeasonOptions;
  Object? _cachedSeasonOptionsKey;
  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _mode = widget.initialMode;
    _selectedSeasonGuid = widget.initialSeasonGuid;
    _seasonData = widget.initialSeasonData;
    _seasons = List<TvEpisodeSeasonOptionData>.from(widget.seasons);
    _rangeIndex = _preferredRangeIndex(_seasonData);
    _cachedRanges = _computeRanges();
    _cachedRangesKey = _rangeCacheKey;
    if (widget.warmupLoader != null) {
      _warmupLoading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _warmupInitialData();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpToPreferredItem();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
      if (mounted) {
        setState(() => _mode = previousMode);
      } else {
        _mode = previousMode;
      }
    } finally {
      if (mounted) {
        setState(() => _modeUpdating = false);
      } else {
        _modeUpdating = false;
      }
      _scheduleJumpToPreferredItem();
    }
  }

  Future<void> _warmupInitialData() async {
    final loader = widget.warmupLoader;
    if (loader == null) return;
    try {
      final data = await loader();
      if (!mounted) return;
      _scrollTargetItemKey = GlobalKey();
      setState(() {
        _seasons = data.seasons;
        if (_selectedSeasonGuid == widget.initialSeasonGuid) {
          _selectedSeasonGuid = data.seasonData.seasonGuid;
          _seasonData = data.seasonData;
          _rangeIndex = _preferredRangeIndex(data.seasonData);
        }
        _warmupLoading = false;
      });
      _scheduleJumpToPreferredItem();
    } catch (_) {
      if (!mounted) return;
      setState(() => _warmupLoading = false);
    }
  }

  Future<void> _selectSeason(String seasonGuid) async {
    if (_selectedSeasonGuid == seasonGuid || _seasonLoading) {
      return;
    }
    final loadToken = ++_seasonLoadToken;
    setState(() {
      _selectedSeasonGuid = seasonGuid;
      _seasonLoading = true;
      _rangeIndex = 0;
    });
    try {
      final data = await widget.seasonLoader(seasonGuid);
      if (!mounted ||
          _seasonLoadToken != loadToken ||
          _selectedSeasonGuid != seasonGuid) {
        return;
      }
      _scrollTargetItemKey = GlobalKey();
      setState(() {
        _seasonData = data;
        _rangeIndex = _preferredRangeIndex(data);
      });
      _scheduleJumpToPreferredItem();
    } finally {
      if (mounted && _seasonLoadToken == loadToken) {
        setState(() => _seasonLoading = false);
      } else if (_seasonLoadToken == loadToken) {
        _seasonLoading = false;
      }
    }
  }

  void _setRangeIndex(int index) {
    if (_rangeIndex == index) return;
    setState(() {
      _rangeIndex = index;
    });
    _scheduleJumpToPreferredItem();
  }

  void _scheduleJumpToPreferredItem() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpToPreferredItem();
    });
  }

  void _jumpToPreferredItem() {
    if (!_scrollController.hasClients) return;
    final targetId = _preferredItemId();
    if (targetId.isEmpty) {
      _scrollController.jumpTo(0);
      return;
    }
    final visibleItems = _visibleItems();
    if (!visibleItems.any((item) => item.id == targetId)) {
      _scrollController.jumpTo(0);
      return;
    }
    final targetContext = _scrollTargetItemKey.currentContext;
    if (targetContext == null) {
      _scrollController.jumpTo(0);
      return;
    }
    Scrollable.ensureVisible(
      targetContext,
      alignment: 0.06,
      duration: Duration.zero,
    );
  }

  int _preferredRangeIndex(EpisodePickerSeasonSheetData data) {
    if (data.items.isEmpty || widget.rangeSize <= 0) return 0;
    final preferredId = data.preferredItemId.trim();
    if (preferredId.isEmpty) return 0;
    final index = data.items.indexWhere((item) => item.id == preferredId);
    if (index < 0) return 0;
    return index ~/ widget.rangeSize;
  }

  Object get _rangeCacheKey => _seasonData.items;

  List<List<EpisodePickerSheetItem>> _computeRanges() {
    if (_seasonData.items.isEmpty || widget.rangeSize <= 0) {
      return const <List<EpisodePickerSheetItem>>[];
    }
    final ranges = <List<EpisodePickerSheetItem>>[];
    for (int i = 0; i < _seasonData.items.length; i += widget.rangeSize) {
      final end = math.min(i + widget.rangeSize, _seasonData.items.length);
      ranges.add(_seasonData.items.sublist(i, end));
    }
    return ranges;
  }

  List<List<EpisodePickerSheetItem>> _ranges() {
    final key = _rangeCacheKey;
    if (_cachedRanges == null || _cachedRangesKey != key) {
      _cachedRanges = _computeRanges();
      _cachedRangesKey = key;
    }
    return _cachedRanges!;
  }

  List<EpisodePickerSheetItem> _visibleItems() {
    final ranges = _ranges();
    if (ranges.isEmpty) return const <EpisodePickerSheetItem>[];
    final safeRangeIndex = _rangeIndex.clamp(0, ranges.length - 1).toInt();
    return ranges[safeRangeIndex];
  }

  String _preferredItemId() {
    final preferredId = _seasonData.preferredItemId.trim();
    if (preferredId.isNotEmpty) return preferredId;
    for (final item in _seasonData.items) {
      if (item.selected) return item.id;
    }
    return _seasonData.items.isNotEmpty ? _seasonData.items.first.id : '';
  }

  bool _hasSeasonSwitcher() => _seasons.length > 1;

  String _seasonCountLabel(BuildContext context) {
    final count = _seasons.length;
    return count > 1
        ? AppLocalizations.of(context).playerSeasonCountLabel(count)
        : '';
  }

  Object get _seasonOptionsCacheKey =>
      Object.hash(_seasons.length, _selectedSeasonGuid);

  List<TvEpisodeSeasonOptionData> _seasonOptions() {
    final key = _seasonOptionsCacheKey;
    if (_cachedSeasonOptions == null || _cachedSeasonOptionsKey != key) {
      _cachedSeasonOptions = _seasons
          .map(
            (season) => TvEpisodeSeasonOptionData(
              guid: season.guid,
              label: season.label,
              selected: season.guid == _selectedSeasonGuid,
            ),
          )
          .toList(growable: false);
      _cachedSeasonOptionsKey = key;
    }
    return _cachedSeasonOptions!;
  }

  Future<void> _showSeasonMenu(BuildContext triggerContext) async {
    if (!_hasSeasonSwitcher() || _seasonLoading) return;
    final colors = context.appColors;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final triggerBox = triggerContext.findRenderObject() as RenderBox?;
    final overlayBox = overlay?.context.findRenderObject() as RenderBox?;
    if (overlay == null || triggerBox == null || overlayBox == null) return;
    final triggerOffset = triggerBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final triggerRect = Rect.fromLTWH(
      triggerOffset.dx,
      triggerOffset.dy,
      triggerBox.size.width,
      triggerBox.size.height,
    );
    const horizontalMargin = 16.0;
    const verticalGap = 8.0;
    const itemExtent = 56.0;
    const menuVerticalPadding = 10.0;
    final overlaySize = overlayBox.size;
    final safePadding = MediaQuery.paddingOf(context);
    final menuWidth = triggerBox.size.width
        .clamp(
          220.0,
          math.min(320.0, overlaySize.width - (horizontalMargin * 2)),
        )
        .toDouble();
    final left = triggerRect.left
        .clamp(
          horizontalMargin,
          overlaySize.width - menuWidth - horizontalMargin,
        )
        .toDouble();
    final estimatedHeight =
        (_seasonOptions().length * itemExtent) + (menuVerticalPadding * 2);
    final availableBelow =
        overlaySize.height -
        safePadding.bottom -
        triggerRect.bottom -
        verticalGap;
    final availableAbove = triggerRect.top - safePadding.top - verticalGap;
    final showBelow =
        availableBelow >= estimatedHeight || availableBelow >= availableAbove;
    final maxHeight = math
        .max(
          itemExtent + (menuVerticalPadding * 2),
          math.min(
            estimatedHeight,
            (showBelow ? availableBelow : availableAbove).clamp(
              itemExtent + (menuVerticalPadding * 2),
              420.0,
            ),
          ),
        )
        .toDouble();
    final options = _seasonOptions();
    final completer = Completer<String?>();
    OverlayEntry? entry;

    void closeMenu([String? value]) {
      if (completer.isCompleted) return;
      completer.complete(value);
      entry?.remove();
      entry = null;
    }

    entry = OverlayEntry(
      builder: (_) {
        return Positioned.fill(
          child: Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => closeMenu(),
                  ),
                ),
                Positioned(
                  left: left,
                  width: menuWidth,
                  top: showBelow ? triggerRect.bottom + verticalGap : null,
                  bottom: showBelow
                      ? null
                      : overlaySize.height - triggerRect.top + verticalGap,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxHeight),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: colors.borderSubtle),
                        boxShadow: [
                          BoxShadow(
                            color: colors.overlayScrim.withValues(alpha: 0.24),
                            blurRadius: 20,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: menuVerticalPadding,
                        ),
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (context, index) {
                          final season = options[index];
                          return InkWell(
                            onTap: () => closeMenu(season.guid),
                            borderRadius: BorderRadius.circular(14),
                            child: _SeasonMenuItem(
                              label: season.label,
                              selected: season.selected,
                              width: menuWidth - 20,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    overlay.insert(entry!);
    final selection = await completer.future;
    if (selection != null && selection != _selectedSeasonGuid) {
      await _selectSeason(selection);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final media = MediaQuery.of(context);
    final isWide = media.size.width > media.size.height;
    final compactWide = isWide && media.size.width < 1100;
    final width = _panelWidth(media.size.width, isWide: isWide);
    final topInset = isWide ? 0.0 : null;
    const bottomInset = 0.0;
    const rightInset = 0.0;
    final leftInset = isWide ? null : 0.0;
    final sheetHeight = isWide
        ? null
        : math.max(420.0, media.size.height * 0.72);
    final ranges = _ranges();
    final safeRangeIndex = ranges.isEmpty
        ? 0
        : _rangeIndex.clamp(0, ranges.length - 1).toInt();
    final visibleItems = ranges.isEmpty
        ? const <EpisodePickerSheetItem>[]
        : ranges[safeRangeIndex];
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
        .clamp(1.0, 3.0)
        .toDouble();

    final seriesTitle = widget.seriesTitle.trim();
    final currentSeasonLabel = _seasonData.seasonLabel.trim();
    final plainHeading = [
      if (seriesTitle.isNotEmpty) seriesTitle,
      if (currentSeasonLabel.isNotEmpty) currentSeasonLabel,
    ].join(' ').trim();

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => AppSheetTransitions.close(context),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            top: topInset,
            left: leftInset,
            right: rightInset,
            bottom: bottomInset,
            width: isWide ? width : null,
            height: sheetHeight,
            child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    colors.surface.withValues(alpha: isWide ? 0.9 : 0.95),
                    colors.overlayScrim.withValues(alpha: isWide ? 0.24 : 0.36),
                  ),
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: null,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      isWide ? (compactWide ? 16 : 20) : 16,
                      isWide
                          ? math.max(media.padding.top, compactWide ? 12 : 16)
                          : 12,
                      isWide ? (compactWide ? 12 : 16) : 16,
                      isWide
                          ? math.max(
                              media.padding.bottom,
                              compactWide ? 12 : 16,
                            )
                          : math.max(media.padding.bottom, 12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isWide)
                          Center(
                            child: Container(
                              width: 36,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 14),
                              decoration: BoxDecoration(
                                color: colors.borderStrong,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _EpisodePickerHeader(
                                seriesTitle: seriesTitle,
                                seasonLabel: currentSeasonLabel,
                                seasonCountLabel: _seasonCountLabel(context),
                                hasSeasonSwitcher: _hasSeasonSwitcher(),
                                seasonLoading: _seasonLoading || _warmupLoading,
                                onTap: _hasSeasonSwitcher()
                                    ? _showSeasonMenu
                                    : null,
                                colors: colors,
                                fallbackHeading: plainHeading.isEmpty
                                    ? widget.barrierTitle
                                    : plainHeading,
                                compactWide: compactWide,
                                isWide: isWide,
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              onPressed: _modeUpdating ? null : _toggleMode,
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
                                        key: ValueKey<TvEpisodePickerMode>(
                                          _mode,
                                        ),
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
                        if (ranges.length > 1)
                          Container(
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                            decoration: BoxDecoration(
                              color: colors.surface,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: SingleChildScrollView(
                              key: ValueKey<String>(
                                'ranges-$_selectedSeasonGuid-${ranges.length}',
                              ),
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: Row(
                                children: [
                                  for (
                                    int index = 0;
                                    index < ranges.length;
                                    index++
                                  ) ...[
                                    if (index > 0) const SizedBox(width: 8),
                                    () {
                                      final start =
                                          index * widget.rangeSize + 1;
                                      final end =
                                          start + ranges[index].length - 1;
                                      final selected = index == safeRangeIndex;
                                      return GestureDetector(
                                        onTap: () => _setRangeIndex(index),
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: selected
                                                ? colors.selectionSoft
                                                : colors.surfaceStrong,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 8,
                                            ),
                                            child: Text(
                                              '$start-$end',
                                              style: TextStyle(
                                                color: selected
                                                    ? colors.selectionStrong
                                                    : colors.textSecondary,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }(),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        if (ranges.length > 1) const SizedBox(height: 10),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: AppTransitions.contentSwitchDuration,
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeOutCubic,
                            child:
                                (_seasonLoading || _warmupLoading) &&
                                    visibleItems.isEmpty
                                ? Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: colors.accent,
                                      ),
                                    ),
                                  )
                                : visibleItems.isEmpty
                                ? _EmptySheetState(
                                    text: AppLocalizations.of(
                                      context,
                                    ).playerNoEpisodes,
                                  )
                                : _mode == TvEpisodePickerMode.list
                                ? _EpisodeListView(
                                    key: ValueKey<String>(
                                      'list-$safeRangeIndex-${visibleItems.length}-$_selectedSeasonGuid',
                                    ),
                                    controller: _scrollController,
                                    scrollTargetId: _preferredItemId(),
                                    scrollTargetKey: _scrollTargetItemKey,
                                    items: visibleItems,
                                    baseUrl: widget.baseUrl,
                                    token: widget.token,
                                    devicePixelRatio: devicePixelRatio,
                                    onTap: (itemId) =>
                                        AppSheetTransitions.close(
                                          context,
                                          EpisodePickerSheetResult(
                                            seasonGuid: _selectedSeasonGuid,
                                            itemId: itemId,
                                          ),
                                        ),
                                  )
                                : _EpisodeGridView(
                                    key: ValueKey<String>(
                                      'grid-$safeRangeIndex-${visibleItems.length}-$_selectedSeasonGuid',
                                    ),
                                    controller: _scrollController,
                                    scrollTargetId: _preferredItemId(),
                                    scrollTargetKey: _scrollTargetItemKey,
                                    items: visibleItems,
                                    devicePixelRatio: devicePixelRatio,
                                    onTap: (itemId) =>
                                        AppSheetTransitions.close(
                                          context,
                                          EpisodePickerSheetResult(
                                            seasonGuid: _selectedSeasonGuid,
                                            itemId: itemId,
                                          ),
                                        ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ),
        ],
      ),
    );
  }

  double _panelWidth(double screenWidth, {required bool isWide}) {
    if (!isWide) {
      return screenWidth - 28;
    }
    if (screenWidth < 900) {
      return screenWidth * 0.56;
    }
    if (screenWidth < 1200) {
      return screenWidth * 0.46;
    }
    return math.min(620, screenWidth * 0.44);
  }
}

class _EpisodePickerHeader extends StatelessWidget {
  final String seriesTitle;
  final String seasonLabel;
  final String seasonCountLabel;
  final bool hasSeasonSwitcher;
  final bool seasonLoading;
  final ValueChanged<BuildContext>? onTap;
  final AppThemeColors colors;
  final String fallbackHeading;
  final bool compactWide;
  final bool isWide;

  const _EpisodePickerHeader({
    required this.seriesTitle,
    required this.seasonLabel,
    required this.seasonCountLabel,
    required this.hasSeasonSwitcher,
    required this.seasonLoading,
    required this.onTap,
    required this.colors,
    required this.fallbackHeading,
    required this.compactWide,
    required this.isWide,
  });

  @override
  Widget build(BuildContext context) {
    final titleStyle = TextStyle(
      color: colors.textPrimary,
      fontSize: isWide ? (compactWide ? 22 : 24) : 20,
      fontWeight: FontWeight.w700,
      height: 1.1,
    );

    if (!hasSeasonSwitcher || seasonLabel.isEmpty) {
      final text = [
        if (seriesTitle.isNotEmpty) seriesTitle,
        if (seasonLabel.isNotEmpty) seasonLabel,
      ].join(' ').trim();
      return Text(
        text.isEmpty ? fallbackHeading : text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: titleStyle,
      );
    }

    final seasonSwitcher = Builder(
      builder: (triggerContext) => InkWell(
        onTap: onTap == null ? null : () => onTap!(triggerContext),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  seasonLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: titleStyle.copyWith(
                    color: colors.selectionStrong,
                    decoration: TextDecoration.underline,
                    decorationColor: colors.selectionStrong.withValues(
                      alpha: 0.9,
                    ),
                    decorationThickness: 1.8,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              if (seasonLoading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: colors.selectionStrong,
                  ),
                )
              else if (onTap != null)
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: colors.selectionStrong,
                ),
            ],
          ),
        ),
      ),
    );

    return Row(
      children: [
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (seriesTitle.isNotEmpty)
                Flexible(
                  flex: 4,
                  fit: FlexFit.loose,
                  child: Text(
                    seriesTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: titleStyle,
                  ),
                ),
              if (seriesTitle.isNotEmpty) const SizedBox(width: 10),
              Flexible(flex: 2, fit: FlexFit.loose, child: seasonSwitcher),
            ],
          ),
        ),
        if (seasonCountLabel.isNotEmpty) ...[
          const SizedBox(width: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceStrong,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: colors.borderSubtle),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Text(
                seasonCountLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SeasonMenuItem extends StatelessWidget {
  final String label;
  final bool selected;
  final double width;

  const _SeasonMenuItem({
    required this.label,
    required this.selected,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? colors.selectionSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? colors.selectionStrong
                        : colors.textPrimary,
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: colors.selectionStrong,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

const double _episodeListItemExtent = 100.0;

class _EpisodeListView extends StatelessWidget {
  final ScrollController controller;
  final String scrollTargetId;
  final GlobalKey scrollTargetKey;
  final List<EpisodePickerSheetItem> items;
  final String baseUrl;
  final String token;
  final double devicePixelRatio;
  final ValueChanged<String> onTap;

  const _EpisodeListView({
    super.key,
    required this.controller,
    required this.scrollTargetId,
    required this.scrollTargetKey,
    required this.items,
    required this.baseUrl,
    required this.token,
    required this.devicePixelRatio,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      padding: EdgeInsets.zero,
      itemCount: items.length,
      itemExtent: _episodeListItemExtent,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: false,
      itemBuilder: (context, index) {
        final item = items[index];
        final Key tileKey = item.id == scrollTargetId
            ? scrollTargetKey
            : ValueKey<String>(item.id);
        return RepaintBoundary(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _EpisodeListTile(
              key: tileKey,
              item: item,
              baseUrl: baseUrl,
              token: token,
              devicePixelRatio: devicePixelRatio,
              onTap: () => onTap(item.id),
            ),
          ),
        );
      },
    );
  }
}

class _EpisodeGridView extends StatelessWidget {
  final ScrollController controller;
  final String scrollTargetId;
  final GlobalKey scrollTargetKey;
  final List<EpisodePickerSheetItem> items;
  final double devicePixelRatio;
  final ValueChanged<String> onTap;

  const _EpisodeGridView({
    super.key,
    required this.controller,
    required this.scrollTargetId,
    required this.scrollTargetKey,
    required this.items,
    required this.devicePixelRatio,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 360 ? 6 : 5;
        return GridView.builder(
          controller: controller,
          itemCount: items.length,
          padding: EdgeInsets.zero,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: false,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            final Key tileKey = item.id == scrollTargetId
                ? scrollTargetKey
                : ValueKey<String>(item.id);
            return RepaintBoundary(
              child: GestureDetector(
                key: tileKey,
                onTap: () => onTap(item.id),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: item.selected ? colors.selectionSoft : colors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Text(
                          item.shortLabel,
                          style: TextStyle(
                            color: item.selected
                                ? colors.selectionStrong
                                : colors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (item.completed)
                        const Positioned(
                          right: 0,
                          bottom: 0,
                          child: _EpisodeCompletedBadge(),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _EpisodeListTile extends StatelessWidget {
  final EpisodePickerSheetItem item;
  final String baseUrl;
  final String token;
  final double devicePixelRatio;
  final VoidCallback onTap;

  const _EpisodeListTile({
    super.key,
    required this.item,
    required this.baseUrl,
    required this.token,
    required this.devicePixelRatio,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: item.selected ? colors.selectionSoft : colors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
              children: [
                _EpisodePoster(
                  baseUrl: baseUrl,
                  token: token,
                  posterPath: item.posterPath,
                  showCurrentMarker: item.selected || item.isPlaying,
                  devicePixelRatio: devicePixelRatio,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.title,
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
                        item.durationLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  item.statusLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: item.statusColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }
}

class _EpisodePoster extends StatelessWidget {
  final String baseUrl;
  final String token;
  final String posterPath;
  final bool showCurrentMarker;
  final double devicePixelRatio;

  const _EpisodePoster({
    required this.baseUrl,
    required this.token,
    required this.posterPath,
    required this.showCurrentMarker,
    required this.devicePixelRatio,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    const posterWidth = 122.0;
    const posterHeight = 68.0;
    final cacheWidth = (posterWidth * devicePixelRatio).round();
    final cacheHeight = (posterHeight * devicePixelRatio).round();
    return SizedBox(
      width: posterWidth,
      height: posterHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: colors.surfaceStrong,
              child: _EpisodePosterImage(
                urls: ApiUrlHelper.imageCandidates(
                  baseUrl,
                  posterPath,
                  width: cacheWidth,
                ),
                token: token,
                cacheWidth: cacheWidth,
                cacheHeight: cacheHeight,
              ),
            ),
            Positioned.fill(
              child: ColoredBox(
                color: colors.overlayScrim.withValues(alpha: 0.12),
              ),
            ),
            if (showCurrentMarker)
              const Positioned.fill(
                child: IgnorePointer(
                  child: Center(child: _PosterNowPlayingIndicator()),
                ),
              ),
          ],
        ),
      ),
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
      child: Icon(
        Icons.check_rounded,
        size: 8,
        color: colors.textSecondary,
      ),
    );
  }
}

class _PosterNowPlayingIndicator extends StatefulWidget {
  const _PosterNowPlayingIndicator();

  @override
  State<_PosterNowPlayingIndicator> createState() =>
      _PosterNowPlayingIndicatorState();
}

class _PosterNowPlayingIndicatorState extends State<_PosterNowPlayingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const double _badgeWidth = 34.0;
  static const double _badgeHeight = 22.0;
  static const double _barWidth = 2.8;
  static const double _barSpacing = 1.8;
  static const double _minBarHeight = _badgeHeight * 0.24;
  static const double _maxBarHeight = _badgeHeight * 0.92;
  static const List<double> _waveSeeds = <double>[
    0.03, 0.41, 0.17, 0.76, 0.29, 0.63,
  ];
  static const List<double> _waveSpeed = <double>[
    1.05, 0.82, 1.27, 0.91, 1.18, 0.74,
  ];
  static const int _barCount = 6;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 920),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // Pre-compute bar colors once per build (changes only on theme change).
    final barColors = List<Color>.generate(_barCount, (i) {
      return Color.lerp(
        Colors.white,
        colors.accent,
        0.28 + (i / _barCount) * 0.32,
      )!;
    }, growable: false);

    return RepaintBoundary(
      child: SizedBox(
        width: _badgeWidth,
        height: _badgeHeight,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _WaveformBarPainter(
                animationValue: _controller.value,
                barColors: barColors,
              ),
              size: const Size(_badgeWidth, _badgeHeight),
            );
          },
        ),
      ),
    );
  }
}

class _WaveformBarPainter extends CustomPainter {
  final double animationValue;
  final List<Color> barColors;

  const _WaveformBarPainter({
    required this.animationValue,
    required this.barColors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const totalBarsWidth = _PosterNowPlayingIndicatorState._barCount *
            (_PosterNowPlayingIndicatorState._barWidth +
                _PosterNowPlayingIndicatorState._barSpacing) -
        _PosterNowPlayingIndicatorState._barSpacing;
    final startX = (size.width - totalBarsWidth) / 2;

    final paint = Paint();

    for (int i = 0; i < _PosterNowPlayingIndicatorState._barCount; i++) {
      final phase = (animationValue *
              _PosterNowPlayingIndicatorState._waveSpeed[i] +
          _PosterNowPlayingIndicatorState._waveSeeds[i]) %
          1.0;
      final secondaryPhase =
          (animationValue *
                  (_PosterNowPlayingIndicatorState._waveSpeed[i] * 1.7) +
              _PosterNowPlayingIndicatorState._waveSeeds[i] * 0.73) %
              1.0;
      final primaryWave = 0.5 + 0.5 * math.sin(phase * math.pi * 2);
      final secondaryWave =
          0.5 + 0.5 * math.cos(secondaryPhase * math.pi * 2);
      final mixedWave = (primaryWave * 0.68) + (secondaryWave * 0.32);
      final barHeight = lerpDouble(
        _PosterNowPlayingIndicatorState._minBarHeight,
        _PosterNowPlayingIndicatorState._maxBarHeight,
        Curves.easeInOut.transform(mixedWave.clamp(0.0, 1.0)),
      )!;

      final barX =
          startX + i * (_PosterNowPlayingIndicatorState._barWidth + _PosterNowPlayingIndicatorState._barSpacing);
      final barY = size.height - barHeight;
      final barRect = RRect.fromLTRBR(
        barX,
        barY,
        barX + _PosterNowPlayingIndicatorState._barWidth,
        size.height,
        const Radius.circular(999),
      );

      // Draw shadow
      paint
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawRRect(
        barRect.shift(const Offset(0, 1)),
        paint,
      );

      // Draw gradient bar
      paint
        ..maskFilter = null
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.white.withValues(alpha: 0.98),
            barColors[i],
          ],
        ).createShader(Rect.fromLTWH(barX, barY,
            _PosterNowPlayingIndicatorState._barWidth, barHeight));
      canvas.drawRRect(barRect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformBarPainter oldDelegate) {
    return animationValue != oldDelegate.animationValue ||
        barColors != oldDelegate.barColors;
  }
}

class _EpisodePosterImage extends StatefulWidget {
  final List<String> urls;
  final String token;
  final int cacheWidth;
  final int cacheHeight;

  const _EpisodePosterImage({
    required this.urls,
    required this.token,
    required this.cacheWidth,
    required this.cacheHeight,
  });

  @override
  State<_EpisodePosterImage> createState() => _EpisodePosterImageState();
}

class _EpisodePosterImageState extends State<_EpisodePosterImage> {
  int _index = 0;
  bool _advancing = false;
  bool? _localFileExists;
  String? _localCheckPath;
  int _localCheckGeneration = 0;

  @override
  void initState() {
    super.initState();
    _maybeStartLocalExistsCheck();
  }

  @override
  void didUpdateWidget(covariant _EpisodePosterImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urls != widget.urls || oldWidget.token != widget.token) {
      _index = 0;
      _advancing = false;
    }
    _maybeStartLocalExistsCheck();
  }

  void _maybeStartLocalExistsCheck() {
    if (widget.urls.isEmpty || _index >= widget.urls.length) {
      _invalidateLocalCheck();
      return;
    }
    final current = widget.urls[_index].trim();
    if (!_isLocalImageCandidate(current)) {
      _invalidateLocalCheck();
      return;
    }
    final localFile = _localImageFile(current);
    if (localFile == null) {
      _invalidateLocalCheck();
      _localFileExists = false;
      _localCheckPath = current;
      return;
    }
    if (_localCheckPath == current && _localFileExists != null) {
      return;
    }
    _localCheckPath = current;
    _localFileExists = null;
    final generation = ++_localCheckGeneration;
    localFile.exists().then((exists) {
      if (!mounted) return;
      if (generation != _localCheckGeneration) return;
      if (_localCheckPath != current) return;
      setState(() {
        _localFileExists = exists;
      });
    }).catchError((_) {
      if (!mounted) return;
      if (generation != _localCheckGeneration) return;
      if (_localCheckPath != current) return;
      setState(() {
        _localFileExists = false;
      });
    });
  }

  void _invalidateLocalCheck() {
    _localCheckGeneration++;
    _localCheckPath = null;
    _localFileExists = null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (widget.urls.isEmpty || _index >= widget.urls.length) {
      return Center(
        child: Icon(
          Icons.movie_outlined,
          color: colors.textPrimary.withValues(alpha: 0.30),
          size: 28,
        ),
      );
    }

    final current = widget.urls[_index].trim();
    final localFile = _localImageFile(current);
    if (_isLocalImageCandidate(current)) {
      if (localFile == null) {
        return _advanceOrBrokenPlaceholder(colors);
      }
      if (_localCheckPath != current || _localFileExists == null) {
        return const SizedBox.expand();
      }
      if (_localFileExists == false) {
        return _advanceOrBrokenPlaceholder(colors);
      }
      return Image.file(
        localFile,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        cacheWidth: widget.cacheWidth,
        cacheHeight: widget.cacheHeight,
        filterQuality: FilterQuality.none,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _advanceOrBrokenPlaceholder(colors),
      );
    }

    if (widget.token.trim().isEmpty) {
      return Center(
        child: Icon(
          Icons.movie_outlined,
          color: colors.textPrimary.withValues(alpha: 0.30),
          size: 28,
        ),
      );
    }

    final headers = <String, String>{
      'Authorization': widget.token,
      'Trim-MC-token': widget.token,
    };

    return Image.network(
      current,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      cacheWidth: widget.cacheWidth,
      cacheHeight: widget.cacheHeight,
      filterQuality: FilterQuality.none,
      gaplessPlayback: true,
      headers: headers,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        final loaded = wasSynchronouslyLoaded || frame != null;
        if (loaded) return child;
        return ColoredBox(color: colors.surfaceStrong);
      },
      errorBuilder: (_, __, ___) {
        return _advanceOrBrokenPlaceholder(colors);
      },
    );
  }

  bool _isLocalImageCandidate(String value) {
    final uri = Uri.tryParse(value);
    if (uri?.scheme == 'file') return true;
    if ((uri?.scheme ?? '').isNotEmpty) return false;
    return value.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value);
  }

  File? _localImageFile(String value) {
    final uri = Uri.tryParse(value);
    if (uri?.scheme == 'file') {
      try {
        return File(uri!.toFilePath(windows: Platform.isWindows));
      } catch (_) {
        return null;
      }
    }
    if (!_isLocalImageCandidate(value)) return null;
    return File(value);
  }

  Widget _advanceOrBrokenPlaceholder(AppThemeColors colors) {
    if (_index + 1 < widget.urls.length) {
      if (!_advancing) {
        _advancing = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _advancing = false;
          _maybeStartLocalExistsCheck();
          setState(() => _index += 1);
        });
      }
      return const SizedBox.expand();
    }
    return Center(
      child: Icon(
        Icons.broken_image_outlined,
        color: colors.textPrimary.withValues(alpha: 0.30),
        size: 28,
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
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
