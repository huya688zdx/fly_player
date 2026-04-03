import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
    required this.seasons,
  });

  @override
  State<_EpisodePickerDialog> createState() => _EpisodePickerDialogState();
}

class _EpisodePickerDialogState extends State<_EpisodePickerDialog> {
  late final ScrollController _scrollController;
  late TvEpisodePickerMode _mode;
  final Map<String, GlobalKey> _itemKeys = <String, GlobalKey>{};

  bool _modeUpdating = false;
  bool _seasonLoading = false;
  int _rangeIndex = 0;
  int _seasonLoadToken = 0;
  late String _selectedSeasonGuid;
  late EpisodePickerSeasonSheetData _seasonData;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _mode = widget.initialMode;
    _selectedSeasonGuid = widget.initialSeasonGuid;
    _seasonData = widget.initialSeasonData;
    _rangeIndex = _preferredRangeIndex(_seasonData);
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
      _itemKeys.clear();
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
    final targetContext = _itemKeys[targetId]?.currentContext;
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

  List<List<EpisodePickerSheetItem>> _ranges() {
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

  bool _hasSeasonSwitcher() => widget.seasons.isNotEmpty;

  String _seasonCountLabel() {
    final count = widget.seasons.length;
    return count > 1 ? '$count季' : '';
  }

  List<TvEpisodeSeasonOptionData> _seasonOptions() {
    return widget.seasons
        .map(
          (season) => TvEpisodeSeasonOptionData(
            guid: season.guid,
            label: season.label,
            selected: season.guid == _selectedSeasonGuid,
          ),
        )
        .toList(growable: false);
  }

  Future<void> _showSeasonMenu(BuildContext triggerContext) async {
    if (!_hasSeasonSwitcher() || _seasonLoading) return;
    final colors = context.appColors;
    final triggerBox = triggerContext.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (triggerBox == null || overlayBox == null) return;
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
    final menuWidth = triggerBox.size.width.clamp(220.0, 320.0);
    final selection = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(triggerRect.left, triggerRect.bottom + 8, menuWidth, 0),
        Offset.zero & overlayBox.size,
      ),
      color: colors.surface,
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      items: [
        for (final season in _seasonOptions())
          PopupMenuItem<String>(
            value: season.guid,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: _SeasonMenuItem(
              label: season.label,
              selected: season.selected,
              width: menuWidth - 20,
            ),
          ),
      ],
    );
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
    const borderRadius = BorderRadius.zero;
    final ranges = _ranges();
    final safeRangeIndex = ranges.isEmpty
        ? 0
        : _rangeIndex.clamp(0, ranges.length - 1).toInt();
    final visibleItems = ranges.isEmpty
        ? const <EpisodePickerSheetItem>[]
        : ranges[safeRangeIndex];
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
              onTap: () => Navigator.of(context).maybePop(),
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
            child: ClipRRect(
              borderRadius: borderRadius,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  color: Color.alphaBlend(
                    colors.surface.withValues(alpha: isWide ? 0.9 : 0.95),
                    colors.overlayScrim.withValues(alpha: isWide ? 0.24 : 0.36),
                  ),
                  border: isWide
                      ? Border.all(color: colors.borderSubtle)
                      : null,
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
                                seasonCountLabel: _seasonCountLabel(),
                                hasSeasonSwitcher: _hasSeasonSwitcher(),
                                seasonLoading: _seasonLoading,
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
                                      return InkWell(
                                        onTap: () => _setRangeIndex(index),
                                        borderRadius: BorderRadius.circular(10),
                                        child: AnimatedContainer(
                                          duration:
                                              AppTransitions.switchDuration,
                                          curve: Curves.easeOutCubic,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: selected
                                                ? colors.selectionSoft
                                                : colors.surfaceStrong,
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: selected
                                                  ? colors.selection
                                                  : Colors.transparent,
                                            ),
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
                            child: _seasonLoading
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
                                ? const _EmptySheetState(text: '暂无选集')
                                : _mode == TvEpisodePickerMode.list
                                ? _EpisodeListView(
                                    key: ValueKey<String>(
                                      'list-$safeRangeIndex-${visibleItems.length}-$_selectedSeasonGuid',
                                    ),
                                    controller: _scrollController,
                                    itemKeys: _itemKeys,
                                    items: visibleItems,
                                    baseUrl: widget.baseUrl,
                                    token: widget.token,
                                    onTap: (itemId) =>
                                        Navigator.of(context).pop(
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
                                    itemKeys: _itemKeys,
                                    items: visibleItems,
                                    onTap: (itemId) =>
                                        Navigator.of(context).pop(
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

    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              if (seriesTitle.isNotEmpty)
                Expanded(
                  child: Text(
                    seriesTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                ),
              if (seriesTitle.isNotEmpty) const SizedBox(width: 10),
              Flexible(
                child: Builder(
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
                              style: titleStyle.copyWith(
                                color: colors.selectionStrong,
                                decoration: TextDecoration.underline,
                                decorationColor: colors.selectionStrong
                                    .withValues(alpha: 0.9),
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
                ),
              ),
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

class _EpisodeListView extends StatelessWidget {
  final ScrollController controller;
  final Map<String, GlobalKey> itemKeys;
  final List<EpisodePickerSheetItem> items;
  final String baseUrl;
  final String token;
  final ValueChanged<String> onTap;

  const _EpisodeListView({
    super.key,
    required this.controller,
    required this.itemKeys,
    required this.items,
    required this.baseUrl,
    required this.token,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: controller,
      padding: EdgeInsets.zero,
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = items[index];
        final itemKey = itemKeys.putIfAbsent(item.id, () => GlobalKey());
        return _EpisodeListTile(
          key: itemKey,
          item: item,
          baseUrl: baseUrl,
          token: token,
          onTap: () => onTap(item.id),
        );
      },
    );
  }
}

class _EpisodeGridView extends StatelessWidget {
  final ScrollController controller;
  final Map<String, GlobalKey> itemKeys;
  final List<EpisodePickerSheetItem> items;
  final ValueChanged<String> onTap;

  const _EpisodeGridView({
    super.key,
    required this.controller,
    required this.itemKeys,
    required this.items,
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
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            final itemKey = itemKeys.putIfAbsent(item.id, () => GlobalKey());
            return InkWell(
              key: itemKey,
              onTap: () => onTap(item.id),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: AppTransitions.switchDuration,
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: item.selected
                        ? colors.selection
                        : colors.borderSubtle,
                  ),
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
  final VoidCallback onTap;

  const _EpisodeListTile({
    super.key,
    required this.item,
    required this.baseUrl,
    required this.token,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: item.selected ? colors.selection : colors.borderSubtle,
          ),
        ),
        child: Row(
          children: [
            _EpisodePoster(
              baseUrl: baseUrl,
              token: token,
              posterPath: item.posterPath,
              showCurrentMarker: item.selected || item.isPlaying,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
    );
  }
}

class _EpisodePoster extends StatelessWidget {
  final String baseUrl;
  final String token;
  final String posterPath;
  final bool showCurrentMarker;

  const _EpisodePoster({
    required this.baseUrl,
    required this.token,
    required this.posterPath,
    required this.showCurrentMarker,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SizedBox(
      width: 122,
      height: 68,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: colors.surfaceStrong,
              child: _EpisodePosterImage(
                urls: ApiUrlHelper.imageCandidates(
                  baseUrl,
                  posterPath,
                  width: 560,
                ),
                token: token,
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.transparent,
                      colors.overlayScrim.withValues(alpha: 0.10),
                      colors.overlayScrim.withValues(alpha: 0.24),
                    ],
                  ),
                ),
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

class _PosterNowPlayingIndicator extends StatefulWidget {
  const _PosterNowPlayingIndicator();

  @override
  State<_PosterNowPlayingIndicator> createState() =>
      _PosterNowPlayingIndicatorState();
}

class _PosterNowPlayingIndicatorState extends State<_PosterNowPlayingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

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
    const badgeWidth = 34.0;
    const badgeHeight = 22.0;
    const barWidth = 2.8;
    const barSpacing = 1.8;
    const minBarHeight = badgeHeight * 0.24;
    const maxBarHeight = badgeHeight * 0.92;
    const waveSeeds = <double>[0.03, 0.41, 0.17, 0.76, 0.29, 0.63];
    const waveSpeed = <double>[1.05, 0.82, 1.27, 0.91, 1.18, 0.74];

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return SizedBox(
          width: badgeWidth,
          height: badgeHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List<Widget>.generate(waveSeeds.length, (index) {
              final phase =
                  (_controller.value * waveSpeed[index] + waveSeeds[index]) %
                  1.0;
              final secondaryPhase =
                  (_controller.value * (waveSpeed[index] * 1.7) +
                      waveSeeds[index] * 0.73) %
                  1.0;
              final primaryWave = 0.5 + 0.5 * math.sin(phase * math.pi * 2);
              final secondaryWave =
                  0.5 + 0.5 * math.cos(secondaryPhase * math.pi * 2);
              final mixedWave = (primaryWave * 0.68) + (secondaryWave * 0.32);
              final height = lerpDouble(
                minBarHeight,
                maxBarHeight,
                Curves.easeInOut.transform(mixedWave.clamp(0.0, 1.0)),
              )!;
              final highlight = Color.lerp(
                Colors.white,
                colors.accent,
                0.28 + (index / waveSeeds.length) * 0.32,
              )!;
              return Container(
                width: barWidth,
                height: height,
                margin: const EdgeInsets.symmetric(
                  horizontal: barSpacing * 0.5,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.white.withValues(alpha: 0.98),
                      highlight,
                    ],
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 5,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

class _EpisodePosterImage extends StatefulWidget {
  final List<String> urls;
  final String token;

  const _EpisodePosterImage({required this.urls, required this.token});

  @override
  State<_EpisodePosterImage> createState() => _EpisodePosterImageState();
}

class _EpisodePosterImageState extends State<_EpisodePosterImage> {
  int _index = 0;

  @override
  void didUpdateWidget(covariant _EpisodePosterImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urls != widget.urls || oldWidget.token != widget.token) {
      _index = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (widget.urls.isEmpty ||
        _index >= widget.urls.length ||
        widget.token.trim().isEmpty) {
      return Center(
        child: Icon(
          Icons.movie_outlined,
          color: colors.textPrimary.withValues(alpha: 0.30),
          size: 28,
        ),
      );
    }

    final current = widget.urls[_index];
    final headers = <String, String>{
      'Authorization': widget.token,
      'Trim-MC-token': widget.token,
    };

    return Image.network(
      current,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      filterQuality: FilterQuality.none,
      headers: headers,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        final loaded = wasSynchronouslyLoaded || frame != null;
        if (loaded) return child;
        return Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              color: colors.accent,
            ),
          ),
        );
      },
      errorBuilder: (_, __, ___) {
        if (_index + 1 < widget.urls.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _index += 1);
            }
          });
          return const SizedBox.expand();
        }
        return Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: colors.textPrimary.withValues(alpha: 0.30),
            size: 28,
          ),
        );
      },
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
