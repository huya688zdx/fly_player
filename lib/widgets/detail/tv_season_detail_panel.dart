import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../ui/app_transitions.dart';
import '../../ui/media_detail_components.dart';
import 'detail_description_section.dart';
import 'detail_icon_button.dart';

class TvSeasonDetailPanel extends StatelessWidget {
  final String title;
  final double titleFontSize;
  final String token;
  final Color? ambientTint;
  final List<String> posterUrls;
  final double posterWidth;
  final double posterCardHeight;
  final double posterBridgeOverlap;
  final double panelDropOffset;
  final double headerBodyTopPadding;
  final Animation<double> headerMetaOpacity;
  final Widget metaContent;
  final String playLabel;
  final double playLabelFontSize;
  final bool watched;
  final bool descriptionVisible;
  final Duration switchDuration;
  final String overview;
  final bool hasOverview;
  final Widget episodeSection;
  final Widget? creditsSection;
  final Widget? linkSection;
  final VoidCallback onPlayTap;
  final VoidCallback onDownloadTap;
  final VoidCallback onWatchedTap;
  final VoidCallback onOverviewTap;

  const TvSeasonDetailPanel({
    super.key,
    required this.title,
    required this.titleFontSize,
    required this.token,
    required this.ambientTint,
    required this.posterUrls,
    required this.posterWidth,
    required this.posterCardHeight,
    required this.posterBridgeOverlap,
    required this.panelDropOffset,
    required this.headerBodyTopPadding,
    required this.headerMetaOpacity,
    required this.metaContent,
    required this.playLabel,
    required this.playLabelFontSize,
    required this.watched,
    required this.descriptionVisible,
    required this.switchDuration,
    required this.overview,
    required this.hasOverview,
    required this.episodeSection,
    required this.creditsSection,
    required this.linkSection,
    required this.onPlayTap,
    required this.onDownloadTap,
    required this.onWatchedTap,
    required this.onOverviewTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final primaryForeground = Theme.of(context).colorScheme.onPrimary;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: -posterBridgeOverlap - panelDropOffset,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  width: posterWidth,
                  height: posterCardHeight,
                  child: DetailHeroImage(urls: posterUrls, token: token),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: AnimatedBuilder(
                    animation: headerMetaOpacity,
                    builder: (context, child) {
                      return Opacity(
                        opacity: headerMetaOpacity.value,
                        child: child,
                      );
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        metaContent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: headerBodyTopPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: DetailPrimaryPlayButton(
                      text: playLabel,
                      textSwitchKey: 'play-label-$playLabel',
                      textStyle: TextStyle(
                        fontSize: playLabelFontSize,
                        fontWeight: FontWeight.w600,
                      ),
                      onTap: onPlayTap,
                      backgroundColor: colors.accent,
                      foregroundColor: primaryForeground,
                    ),
                  ),
                  const SizedBox(width: 12),
                  DetailIconButton(
                    iconAsset: 'assets/icons/download.svg',
                    onTap: onDownloadTap,
                  ),
                  const SizedBox(width: 10),
                  DetailIconButton(
                    iconAsset: 'assets/icons/watched.svg',
                    selectedIconAsset: 'assets/icons/watched_selected.svg',
                    selected: watched,
                    onTap: onWatchedTap,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              AnimatedSize(
                duration: switchDuration,
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppTransitions.fadeDownSwitch(
                      switchKey:
                          'overview-$descriptionVisible-${hasOverview ? 1 : 0}-${overview.hashCode}',
                      duration: switchDuration,
                      child: (hasOverview && descriptionVisible)
                          ? DetailDescriptionSection(
                              text: overview,
                              maxLines: 3,
                              baseFontSize: 14,
                              onMoreTap: onOverviewTap,
                            )
                          : const SizedBox.shrink(),
                    ),
                    SizedBox(height: hasOverview ? 12 : 16),
                  ],
                ),
              ),
              episodeSection,
              if (creditsSection != null) ...[
                const SizedBox(height: 20),
                creditsSection!,
              ],
              if (linkSection != null) ...[
                const SizedBox(height: 20),
                linkSection!,
              ],
            ],
          ),
        ),
      ],
    );
  }
}
