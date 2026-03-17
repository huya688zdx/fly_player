import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/tv_episode_browser_models.dart';
import '../../models/tv_episode_picker_mode.dart';
import '../../theme/app_theme.dart';
import '../../theme/detail_tokens.dart';
import '../../ui/app_transitions.dart';
import '../../ui/media_detail_components.dart';
import 'capability_badge.dart';

class TvEpisodeBrowserSection extends StatelessWidget {
  final String title;
  final String totalLabel;
  final List<TvEpisodeSeasonOptionData> seasons;
  final List<TvEpisodeCardData> episodes;
  final int selectedRangeIndex;
  final int rangeSize;
  final int previewCount;
  final String emptyText;
  final String detailText;
  final String token;
  final TvEpisodePickerMode mode;
  final ValueChanged<String> onSeasonSelected;
  final ValueChanged<int> onRangeSelected;
  final ValueChanged<String> onEpisodeSelected;
  final ValueChanged<String> onEpisodeLongPress;
  final ValueChanged<String> onEpisodeDetailTap;
  final VoidCallback onOpenPicker;

  const TvEpisodeBrowserSection({
    super.key,
    required this.title,
    required this.totalLabel,
    required this.seasons,
    required this.episodes,
    required this.selectedRangeIndex,
    required this.rangeSize,
    required this.previewCount,
    required this.emptyText,
    required this.detailText,
    required this.token,
    required this.mode,
    required this.onSeasonSelected,
    required this.onRangeSelected,
    required this.onEpisodeSelected,
    required this.onEpisodeLongPress,
    required this.onEpisodeDetailTap,
    required this.onOpenPicker,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final ranges = _buildRanges(episodes, rangeSize: rangeSize);
    final safeRangeIndex = ranges.isEmpty
        ? 0
        : selectedRangeIndex.clamp(0, ranges.length - 1);
    final visibleEntries = ranges.isEmpty
        ? const <TvEpisodeCardData>[]
        : ranges[safeRangeIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onOpenPicker,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceStrong.withValues(alpha: 0.86),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colors.borderSubtle.withValues(alpha: 0.9),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          totalLabel,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: colors.textSecondary,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (seasons.isNotEmpty)
          _SeasonTabs(seasons: seasons, onTap: onSeasonSelected),
        if (seasons.isNotEmpty) const SizedBox(height: 12),
        if (ranges.length > 1)
          _RangeChips(
            ranges: ranges,
            selectedIndex: safeRangeIndex,
            onTap: onRangeSelected,
          ),
        if (ranges.length > 1) const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: AppTransitions.contentSwitchDuration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          child: visibleEntries.isEmpty
              ? _EmptyState(text: emptyText)
              : mode == TvEpisodePickerMode.grid
              ? _EpisodeButtonStrip(
                  key: ValueKey<String>(
                    'button-${visibleEntries.length}-${visibleEntries.first.guid}-${visibleEntries.last.guid}',
                  ),
                  entries: visibleEntries,
                  onEpisodeSelected: onEpisodeSelected,
                )
              : _PreviewGrid(
                  key: ValueKey<String>(
                    'preview-${visibleEntries.length}-${visibleEntries.first.guid}-${visibleEntries.last.guid}',
                  ),
                  entries: visibleEntries,
                  token: token,
                  detailText: detailText,
                  onEpisodeSelected: onEpisodeSelected,
                  onEpisodeLongPress: onEpisodeLongPress,
                  onEpisodeDetailTap: onEpisodeDetailTap,
                ),
        ),
      ],
    );
  }
}

List<List<TvEpisodeCardData>> _buildRanges(
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

class _SeasonTabs extends StatelessWidget {
  final List<TvEpisodeSeasonOptionData> seasons;
  final ValueChanged<String> onTap;

  const _SeasonTabs({required this.seasons, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < seasons.length; i++) ...[
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
              onTap: () => onTap(seasons[i].guid),
              child: AnimatedDefaultTextStyle(
                duration: AppTransitions.switchDuration,
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  color: seasons[i].selected
                      ? colors.selection
                      : colors.textSecondary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
                child: Text(seasons[i].label),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RangeChips extends StatelessWidget {
  final List<List<TvEpisodeCardData>> ranges;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _RangeChips({
    required this.ranges,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: ranges.length,
        padding: EdgeInsets.zero,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final start = index * rangeSizeHint(ranges, index) + 1;
          final end = start + ranges[index].length - 1;
          final selected = index == selectedIndex;
          return InkWell(
            onTap: () => onTap(index),
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: AppTransitions.switchDuration,
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? colors.selectionSoft : colors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? colors.selection : colors.chipBorder,
                ),
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
    );
  }

  int rangeSizeHint(List<List<TvEpisodeCardData>> ranges, int index) {
    if (ranges.isEmpty) return 1;
    return ranges.first.length;
  }
}

class _PreviewGrid extends StatelessWidget {
  final List<TvEpisodeCardData> entries;
  final String token;
  final String detailText;
  final ValueChanged<String> onEpisodeSelected;
  final ValueChanged<String> onEpisodeLongPress;
  final ValueChanged<String> onEpisodeDetailTap;

  const _PreviewGrid({
    super.key,
    required this.entries,
    required this.token,
    required this.detailText,
    required this.onEpisodeSelected,
    required this.onEpisodeLongPress,
    required this.onEpisodeDetailTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cardWidth =
            ((width - DetailTokens.screenHorizontalPadding * 2 - 10) / 2).clamp(
              160.0,
              206.0,
            );
        final imageHeight = cardWidth * 9 / 16;
        final textScale = MediaQuery.of(
          context,
        ).textScaler.scale(1).clamp(1.0, 1.2);
        final summaryHeight = (32.0 * textScale).clamp(32.0, 44.0);
        final itemHeight = imageHeight + summaryHeight + 64;
        return SizedBox(
          height: itemHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(right: 4),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return RepaintBoundary(
                child: SizedBox(
                  width: cardWidth,
                  child: _PreviewCard(
                    entry: entry,
                    token: token,
                    imageHeight: imageHeight,
                    detailText: detailText,
                    onSelect: () => onEpisodeSelected(entry.guid),
                    onLongPress: () => onEpisodeLongPress(entry.guid),
                    onDetail: () => onEpisodeDetailTap(entry.guid),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _EpisodeButtonStrip extends StatelessWidget {
  final List<TvEpisodeCardData> entries;
  final ValueChanged<String> onEpisodeSelected;

  const _EpisodeButtonStrip({
    super.key,
    required this.entries,
    required this.onEpisodeSelected,
  });

  @override
  Widget build(BuildContext context) {
    const tileSize = 68.0;
    return SizedBox(
      height: tileSize,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(right: 4),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final entry = entries[index];
          return SizedBox(
            width: tileSize,
            child: _EpisodeButtonTile(
              entry: entry,
              selected: entry.selected,
              onTap: () => onEpisodeSelected(entry.guid),
            ),
          );
        },
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final TvEpisodeCardData entry;
  final String token;
  final double imageHeight;
  final String detailText;
  final VoidCallback onSelect;
  final VoidCallback onLongPress;
  final VoidCallback onDetail;

  const _PreviewCard({
    required this.entry,
    required this.token,
    required this.imageHeight,
    required this.detailText,
    required this.onSelect,
    required this.onLongPress,
    required this.onDetail,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onSelect,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                height: imageHeight,
                child: _EpisodePoster(
                  imageUrls: entry.imageUrls,
                  token: token,
                  resolutions: entry.resolutions,
                  showWatchedIcon: entry.completed,
                  progress: entry.progress,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 15,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _EpisodeSummaryLine(
            summary: entry.summary,
            fontSize: 13,
            detailText: detailText,
            onDetailTap: onDetail,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          entry.durationText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
      ],
    );
  }
}

class _EpisodeButtonTile extends StatelessWidget {
  final TvEpisodeCardData entry;
  final bool selected;
  final VoidCallback onTap;

  const _EpisodeButtonTile({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: AppTransitions.switchDuration,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? colors.selection : colors.borderSubtle,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Text(
                entry.shortLabel,
                style: TextStyle(
                  color: selected ? colors.selectionStrong : colors.textPrimary,
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
  }
}

class _EpisodeCompletedBadge extends StatelessWidget {
  const _EpisodeCompletedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: const BoxDecoration(
        color: Color(0xFF3D4A5B),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(7),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: Center(
        child: SvgPicture.asset(
          'assets/icons/episode_completed_badge.svg',
          width: 7,
          height: 7,
          colorFilter: const ColorFilter.mode(
            Color(0xFFB8C5D6),
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}

class _EpisodePoster extends StatelessWidget {
  final List<String> imageUrls;
  final String token;
  final List<String> resolutions;
  final bool showWatchedIcon;
  final double progress;

  const _EpisodePoster({
    required this.imageUrls,
    required this.token,
    required this.resolutions,
    required this.showWatchedIcon,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final normalizedProgress = progress.clamp(0.0, 1.0);
    final progressActiveColor = DetailTokens.progressActiveOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DetailHeroImage(urls: imageUrls, token: token),
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  widthFactor: 1,
                  heightFactor: 0.58,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          colors.overlayScrim.withValues(alpha: 0.14),
                          colors.overlayScrim.withValues(alpha: 0.34),
                        ],
                        stops: const [0.0, 0.65, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (showWatchedIcon)
            Positioned(
              left: 6,
              bottom: 6,
              child: SvgPicture.asset(
                'assets/icons/watched_selected.svg',
                width: 16,
                height: 16,
                colorFilter: ColorFilter.mode(
                  context.appColors.textPrimary,
                  BlendMode.srcIn,
                ),
              ),
            ),
          if (resolutions.isNotEmpty)
            Positioned(
              right: 4,
              bottom: 4,
              child: Row(
                children: [
                  for (int i = 0; i < resolutions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    CapabilityBadge(label: resolutions[i]),
                  ],
                ],
              ),
            ),
          if (normalizedProgress > 0 && !showWatchedIcon)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final visualWidth =
                      (constraints.maxWidth * normalizedProgress).clamp(
                        4.0,
                        constraints.maxWidth,
                      );
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: visualWidth,
                      height: 5,
                      child: ColoredBox(color: progressActiveColor),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String text;

  const _EmptyState({required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
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

class _EpisodeSummaryLine extends StatelessWidget {
  final String summary;
  final double fontSize;
  final String detailText;
  final VoidCallback onDetailTap;

  const _EpisodeSummaryLine({
    required this.summary,
    required this.fontSize,
    required this.detailText,
    required this.onDetailTap,
  });

  bool _exceedsTwoLines({
    required BuildContext context,
    required double maxWidth,
    required InlineSpan text,
  }) {
    final painter = TextPainter(
      text: text,
      maxLines: 2,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: maxWidth);
    return painter.didExceedMaxLines;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (summary.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final normalStyle = TextStyle(
      color: colors.textSecondary,
      fontSize: fontSize,
      height: 1.2,
    );
    final detailStyle = TextStyle(
      color: colors.link,
      fontWeight: FontWeight.w600,
      fontSize: fontSize - 1,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final safeWidth = maxWidth > 8 ? maxWidth - 8 : maxWidth;
        if (maxWidth <= 0) return const SizedBox.shrink();

        final plain = TextSpan(text: summary, style: normalStyle);
        final overflowed = _exceedsTwoLines(
          context: context,
          maxWidth: safeWidth,
          text: plain,
        );
        if (!overflowed) {
          return Text(
            summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: normalStyle,
          );
        }

        const suffixNormal = '...';
        int low = 0;
        int high = summary.length;
        int best = 0;
        while (low <= high) {
          final mid = (low + high) >> 1;
          final candidate = summary.substring(0, mid).trimRight();
          final span = TextSpan(
            children: [
              TextSpan(text: candidate, style: normalStyle),
              TextSpan(text: suffixNormal, style: normalStyle),
              TextSpan(text: detailText, style: detailStyle),
            ],
          );
          final fits = !_exceedsTwoLines(
            context: context,
            maxWidth: safeWidth,
            text: span,
          );
          if (fits) {
            best = mid;
            low = mid + 1;
          } else {
            high = mid - 1;
          }
        }

        final fitted = summary.substring(0, best).trimRight();
        return RichText(
          maxLines: 2,
          overflow: TextOverflow.clip,
          text: TextSpan(
            children: [
              TextSpan(text: fitted, style: normalStyle),
              TextSpan(text: suffixNormal, style: normalStyle),
              TextSpan(
                text: detailText,
                style: detailStyle,
                recognizer: TapGestureRecognizer()..onTap = onDetailTap,
              ),
            ],
          ),
        );
      },
    );
  }
}
