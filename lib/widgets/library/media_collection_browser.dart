import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../models/media_collection_view_type.dart';
import '../../models/media_library_item.dart';
import '../../theme/app_theme.dart';
import '../../ui/capability_badge_mapper.dart';
import '../../ui/layout_adaptive.dart';
import '../../ui/media_poster_card.dart';
import '../../utils/api_url_helper.dart';
import '../../utils/nas_image_headers.dart';

class MediaCollectionBrowserSliver extends StatelessWidget {
  final List<MediaLibraryItem> items;
  final String baseUrl;
  final String token;
  final MediaCollectionViewType viewType;
  final ValueChanged<MediaLibraryItem> onItemTap;
  final ValueChanged<MediaLibraryItem> onItemLongPress;
  final ValueChanged<MediaLibraryItem> onItemMoreTap;

  const MediaCollectionBrowserSliver({
    super.key,
    required this.items,
    required this.baseUrl,
    required this.token,
    required this.viewType,
    required this.onItemTap,
    required this.onItemLongPress,
    required this.onItemMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (items.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 24),
          child: Center(
            child: Text(
              AppLocalizations.of(context).commonEmpty,
              style: TextStyle(color: colors.textSecondary, fontSize: 15),
            ),
          ),
        ),
      );
    }

    switch (viewType) {
      case MediaCollectionViewType.list:
        return _ListSliverLayout(
          items: items,
          baseUrl: baseUrl,
          token: token,
          onItemTap: onItemTap,
          onItemLongPress: onItemLongPress,
          onItemMoreTap: onItemMoreTap,
        );
      case MediaCollectionViewType.horizontalPoster:
        return _PosterGridSliverLayout(
          items: items,
          baseUrl: baseUrl,
          token: token,
          horizontal: true,
          onItemTap: onItemTap,
          onItemLongPress: onItemLongPress,
        );
      case MediaCollectionViewType.verticalPoster:
        return _PosterGridSliverLayout(
          items: items,
          baseUrl: baseUrl,
          token: token,
          horizontal: false,
          onItemTap: onItemTap,
          onItemLongPress: onItemLongPress,
        );
    }
  }
}

class _PosterGridSliverLayout extends StatelessWidget {
  final List<MediaLibraryItem> items;
  final String baseUrl;
  final String token;
  final bool horizontal;
  final ValueChanged<MediaLibraryItem> onItemTap;
  final ValueChanged<MediaLibraryItem> onItemLongPress;

  const _PosterGridSliverLayout({
    required this.items,
    required this.baseUrl,
    required this.token,
    required this.horizontal,
    required this.onItemTap,
    required this.onItemLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final layout = MediaLayoutProfile.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = horizontal
        ? (layout.isTablet ? 3 : 2)
        : layout.categoryGridColumns;
    final spacing = layout.itemGap;
    final availableWidth =
        width -
        layout.pageHorizontalPadding * 2 -
        spacing * (crossAxisCount - 1);
    final cardWidth = availableWidth / crossAxisCount;
    final imageHeight = horizontal
        ? cardWidth * 0.56
        : layout.categoryGridImageHeight;
    final rowHeight = horizontal
        ? imageHeight + 58
        : layout.categoryGridRowHeight;

    return SliverPadding(
      padding: const EdgeInsets.only(bottom: 16),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          mainAxisExtent: rowHeight,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final item = items[index];
          return MediaPosterCard(
            urls: _posterCandidates(
              baseUrl,
              item,
              width: horizontal ? 720 : layout.categoryGridRequestWidth,
              preferDirectPath: horizontal,
            ),
            token: token,
            title: item.displayTitle,
            subtitle: _subtitleFor(context, item),
            imageAspectRatioHint: item.hasPosterSize
                ? item.posterWidth / item.posterHeight
                : null,
            rating: _ratingFor(item),
            resolutions: item.resolutions
                .map(_resolutionLabel)
                .where((e) => e.isNotEmpty)
                .toList(growable: false),
            watched: item.watched == 1,
            imageHeight: imageHeight,
            titleFontSize: layout.homePosterTitleFontSize,
            subtitleFontSize: layout.homePosterSubtitleFontSize,
            expandImageToFit: false,
            imageFit: horizontal
                ? BoxFit.contain
                : (_isEpisodeItem(item) ? BoxFit.contain : BoxFit.cover),
            autoFitByImageAspect: false,
            onTap: () => onItemTap(item),
            onLongPress: () => onItemLongPress(item),
          );
        }, childCount: items.length),
      ),
    );
  }
}

String? _resolutionBadgeAsset(MediaLibraryItem item) {
  if (item.resolutions.isEmpty) {
    return null;
  }
  final normalized = CapabilityBadgeMapper.normalize(item.resolutions.first);
  return CapabilityBadgeMapper.badgeAsset(normalized);
}

class _ResolutionBadge extends StatelessWidget {
  final String asset;

  const _ResolutionBadge({required this.asset});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SizedBox(
      height: 18,
      child: SvgPicture.asset(
        asset,
        fit: BoxFit.contain,
        colorFilter: ColorFilter.mode(colors.chipText, BlendMode.srcIn),
      ),
    );
  }
}

class _ListThumb extends StatelessWidget {
  final List<String> urls;
  final String token;

  const _ListThumb({required this.urls, required this.token});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (urls.isEmpty || token.trim().isEmpty) {
      return Container(
        color: colors.surfaceStrong,
        alignment: Alignment.center,
        child: Icon(
          Icons.movie,
          color: colors.textMuted.withValues(alpha: 0.5),
        ),
      );
    }
    // 列表缩略图固定显示 72x46,按 DPR 换算解码宽度。图源是竖版海报(约2:3,
    // 服务端只按宽等比缩放),cacheWidth/cacheHeight 双维会走等同 BoxFit.fill
    // 的精确缩放(不保比例),解码成 72:46 后 cover 无图可裁、直接把人脸压扁；
    // 只传 cacheWidth 单维解码保比例,cover 才能正常按高裁剪。
    final dpr = MediaQuery.of(context).devicePixelRatio.clamp(1.0, 1.8);
    return Image.network(
      urls.first,
      fit: BoxFit.cover,
      cacheWidth: (72 * dpr).round(),
      headers: nasImageHeaders(token, url: urls.first),
      errorBuilder: (_, __, ___) {
        return Container(
          color: colors.surfaceStrong,
          alignment: Alignment.center,
          child: Icon(
            Icons.movie,
            color: colors.textMuted.withValues(alpha: 0.5),
          ),
        );
      },
    );
  }
}

List<String> _posterCandidates(
  String baseUrl,
  MediaLibraryItem item, {
  int width = 400,
  bool preferDirectPath = false,
}) {
  final paths = <String>[
    if (item.poster.trim().isNotEmpty) item.poster.trim(),
    ...item.posterList.where((path) => path.trim().isNotEmpty),
  ];
  final unique = <String>{};
  final ordered = <String>[];
  for (final path in paths) {
    if (unique.add(path)) {
      ordered.add(path);
    }
  }
  if (ordered.isEmpty) {
    return const <String>[];
  }
  return ordered
      .expand(
        (path) => ApiUrlHelper.imageCandidates(
          baseUrl,
          path,
          width: width,
          preferDirectPath: preferDirectPath,
        ),
      )
      .toList(growable: false);
}

class _ListSliverLayout extends StatelessWidget {
  final List<MediaLibraryItem> items;
  final String baseUrl;
  final String token;
  final ValueChanged<MediaLibraryItem> onItemTap;
  final ValueChanged<MediaLibraryItem> onItemLongPress;
  final ValueChanged<MediaLibraryItem> onItemMoreTap;

  const _ListSliverLayout({
    required this.items,
    required this.baseUrl,
    required this.token,
    required this.onItemTap,
    required this.onItemLongPress,
    required this.onItemMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final childCount = items.length * 2 - 1;
    return SliverPadding(
      padding: const EdgeInsets.only(bottom: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          if (index.isOdd) {
            return const SizedBox(height: 8);
          }
          final item = items[index ~/ 2];
          final urls = _posterCandidates(baseUrl, item, width: 280);
          return InkWell(
            onTap: () => onItemTap(item),
            onLongPress: () => onItemLongPress(item),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.borderSubtle),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 72,
                      height: 46,
                      child: _ListThumb(urls: urls, token: token),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            height: 1.12,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (_resolutionBadgeAsset(item) != null)
                              _ResolutionBadge(
                                asset: _resolutionBadgeAsset(item)!,
                              ),
                            Text(
                              _subtitleFor(context, item),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => onItemMoreTap(item),
                    splashRadius: 20,
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      color: colors.textMuted,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          );
        }, childCount: childCount),
      ),
    );
  }
}

String _subtitleFor(BuildContext context, MediaLibraryItem item) {
  final l10n = AppLocalizations.of(context);
  final lowerType = item.type.trim().toLowerCase();
  if (lowerType == 'directory') {
    final count = item.numberOfItem > 0
        ? item.numberOfItem
        : item.localNumberOfEpisodes;
    return count > 0
        ? l10n.collectionItemCount(count)
        : l10n.resourceTypeDirectory;
  }
  if (item.duration > 0) {
    final minutes = item.duration ~/ 60;
    final seconds = item.duration % 60;
    return seconds == 0
        ? l10n.commonDurationMinutes(minutes)
        : l10n.commonDurationMinutesSeconds(minutes, seconds);
  }
  if (item.releaseDate.length >= 4) {
    return item.releaseDate.substring(0, 4);
  }
  return lowerType == 'video' ? l10n.resourceTypeVideo : item.type;
}

bool _isEpisodeItem(MediaLibraryItem item) {
  return item.type.trim().toLowerCase() == 'episode';
}

double? _ratingFor(MediaLibraryItem item) {
  final rating = double.tryParse(item.voteAverage);
  if (rating == null || rating <= 0) {
    return null;
  }
  return rating;
}

String _resolutionLabel(String value) {
  final text = value.trim();
  final match = RegExp(r'^(\d{3,4})p$', caseSensitive: false).firstMatch(text);
  if (match != null) {
    return match.group(1) ?? text;
  }
  return text.toUpperCase();
}
