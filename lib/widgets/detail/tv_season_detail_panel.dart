import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../ui/app_transitions.dart';
import '../../ui/detail_artwork_resolver.dart';
import '../../ui/media_detail_components.dart';
import 'detail_description_section.dart';
import 'detail_icon_button.dart';

class TvSeasonPanelHeader {
  final String title;
  final double titleFontSize;
  final String token;
  final Color? ambientTint;
  final List<String> posterUrls;
  final Animation<double> metaOpacity;
  final Widget metaContent;

  const TvSeasonPanelHeader({
    required this.title,
    required this.titleFontSize,
    required this.token,
    required this.ambientTint,
    required this.posterUrls,
    required this.metaOpacity,
    required this.metaContent,
  });
}

class TvSeasonPanelLayout {
  final double posterWidth;
  final double posterCardHeight;
  final double posterBridgeOverlap;
  final double panelDropOffset;
  final double headerBodyTopPadding;
  final double playLabelFontSize;
  final Duration switchDuration;

  const TvSeasonPanelLayout({
    required this.posterWidth,
    required this.posterCardHeight,
    required this.posterBridgeOverlap,
    required this.panelDropOffset,
    required this.headerBodyTopPadding,
    required this.playLabelFontSize,
    required this.switchDuration,
  });
}

class TvSeasonPanelActions {
  final String playLabel;
  final bool watched;
  final bool downloaded;
  final VoidCallback onPlayTap;
  final VoidCallback onDownloadTap;
  final VoidCallback onWatchedTap;

  /// 可选「收藏整部剧」键。仅传入时显示(Emby 季页面);飞牛季页面不传 → 不显示,保持原样。
  final bool? favorite;
  final VoidCallback? onFavoriteTap;

  const TvSeasonPanelActions({
    required this.playLabel,
    required this.watched,
    this.downloaded = false,
    required this.onPlayTap,
    required this.onDownloadTap,
    required this.onWatchedTap,
    this.favorite,
    this.onFavoriteTap,
  });
}

class TvSeasonPanelContent {
  final bool descriptionVisible;
  final String overview;
  final bool hasOverview;
  final Widget episodeSection;
  final Widget? creditsSection;
  final Widget? linkSection;
  final VoidCallback onOverviewTap;

  const TvSeasonPanelContent({
    required this.descriptionVisible,
    required this.overview,
    required this.hasOverview,
    required this.episodeSection,
    required this.creditsSection,
    required this.linkSection,
    required this.onOverviewTap,
  });
}

class TvSeasonDetailPanel extends StatelessWidget {
  final TvSeasonPanelHeader header;
  final TvSeasonPanelLayout layout;
  final TvSeasonPanelActions actions;
  final TvSeasonPanelContent content;

  const TvSeasonDetailPanel({
    super.key,
    required this.header,
    required this.layout,
    required this.actions,
    required this.content,
  });

  factory TvSeasonDetailPanel.legacy({
    Key? key,
    required String title,
    required double titleFontSize,
    required String token,
    required Color? ambientTint,
    required List<String> posterUrls,
    required double posterWidth,
    required double posterCardHeight,
    required double posterBridgeOverlap,
    required double panelDropOffset,
    required double headerBodyTopPadding,
    required Animation<double> headerMetaOpacity,
    required Widget metaContent,
    required String playLabel,
    required double playLabelFontSize,
    required bool watched,
    bool downloaded = false,
    required bool descriptionVisible,
    required Duration switchDuration,
    required String overview,
    required bool hasOverview,
    required Widget episodeSection,
    required Widget? creditsSection,
    required Widget? linkSection,
    required VoidCallback onPlayTap,
    required VoidCallback onDownloadTap,
    required VoidCallback onWatchedTap,
    required VoidCallback onOverviewTap,
    bool? favorite,
    VoidCallback? onFavoriteTap,
  }) {
    return TvSeasonDetailPanel(
      key: key,
      header: TvSeasonPanelHeader(
        title: title,
        titleFontSize: titleFontSize,
        token: token,
        ambientTint: ambientTint,
        posterUrls: posterUrls,
        metaOpacity: headerMetaOpacity,
        metaContent: metaContent,
      ),
      layout: TvSeasonPanelLayout(
        posterWidth: posterWidth,
        posterCardHeight: posterCardHeight,
        posterBridgeOverlap: posterBridgeOverlap,
        panelDropOffset: panelDropOffset,
        headerBodyTopPadding: headerBodyTopPadding,
        playLabelFontSize: playLabelFontSize,
        switchDuration: switchDuration,
      ),
      actions: TvSeasonPanelActions(
        playLabel: playLabel,
        watched: watched,
        downloaded: downloaded,
        onPlayTap: onPlayTap,
        onDownloadTap: onDownloadTap,
        onWatchedTap: onWatchedTap,
        favorite: favorite,
        onFavoriteTap: onFavoriteTap,
      ),
      content: TvSeasonPanelContent(
        descriptionVisible: descriptionVisible,
        overview: overview,
        hasOverview: hasOverview,
        episodeSection: episodeSection,
        creditsSection: creditsSection,
        linkSection: linkSection,
        onOverviewTap: onOverviewTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final primaryForeground = Theme.of(context).colorScheme.onPrimary;
    final title = header.title;
    final titleFontSize = header.titleFontSize;
    final token = header.token;
    final posterUrls = header.posterUrls;
    final headerMetaOpacity = header.metaOpacity;
    final metaContent = header.metaContent;
    final posterWidth = layout.posterWidth;
    final posterCardHeight = layout.posterCardHeight;
    final posterBridgeOverlap = layout.posterBridgeOverlap;
    final panelDropOffset = layout.panelDropOffset;
    final headerBodyTopPadding = layout.headerBodyTopPadding;
    final playLabelFontSize = layout.playLabelFontSize;
    final switchDuration = layout.switchDuration;
    final playLabel = actions.playLabel;
    final watched = actions.watched;
    final downloaded = actions.downloaded;
    final onPlayTap = actions.onPlayTap;
    final onDownloadTap = actions.onDownloadTap;
    final onWatchedTap = actions.onWatchedTap;
    final favorite = actions.favorite;
    final onFavoriteTap = actions.onFavoriteTap;
    final descriptionVisible = content.descriptionVisible;
    final overview = content.overview;
    final hasOverview = content.hasOverview;
    final episodeSection = content.episodeSection;
    final creditsSection = content.creditsSection;
    final linkSection = content.linkSection;
    final onOverviewTap = content.onOverviewTap;
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
                  child: DetailHeroImage(
                    images: mediaImageRequestForUrls(
                      posterUrls,
                      token: token,
                    ),
                  ),
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
              AnimatedBuilder(
                animation: headerMetaOpacity,
                builder: (context, child) {
                  return Opacity(
                    opacity: headerMetaOpacity.value,
                    child: child,
                  );
                },
                child: Row(
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
                    if (favorite != null && onFavoriteTap != null) ...[
                      DetailIconButton(
                        iconAsset: 'assets/icons/heart.svg',
                        selected: favorite,
                        onTap: onFavoriteTap,
                      ),
                      const SizedBox(width: 10),
                    ],
                    DetailIconButton(
                      iconAsset: 'assets/icons/download.svg',
                      selectedIconAsset: 'assets/icons/check.svg',
                      selected: downloaded,
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
              ),
              const SizedBox(height: 10),
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
                    SizedBox(height: hasOverview ? 12 : 8),
                  ],
                ),
              ),
              episodeSection,
              if (creditsSection != null) ...[
                const SizedBox(height: 20),
                creditsSection,
              ],
              if (linkSection != null) ...[
                const SizedBox(height: 20),
                linkSection,
              ],
            ],
          ),
        ),
      ],
    );
  }
}
