import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../media_backend/media_image_request.dart';
import '../../widgets/detail/detail_hero_overlay.dart';
import 'poster_browse_display_item.dart';

class PosterBrowseMediaInfo extends StatelessWidget {
  final PosterBrowseDisplayItem item;
  final MediaImageRequest logoRequest;
  final String secondaryLabel;
  final List<Widget> metaWidgets;
  final bool compact;
  final bool collapsed;
  final VoidCallback onPlay;
  final VoidCallback onDetail;

  const PosterBrowseMediaInfo({
    super.key,
    required this.item,
    required this.logoRequest,
    required this.secondaryLabel,
    required this.metaWidgets,
    required this.compact,
    this.collapsed = false,
    required this.onPlay,
    required this.onDetail,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final overview = item.overview.trim();
    final secondary = secondaryLabel.trim();
    final spacing = collapsed ? 5.0 : (compact ? 8.0 : 12.0);
    final titleHeight = collapsed ? 60.0 : (compact ? 96.0 : 112.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          key: const ValueKey('poster_browse_title_slot'),
          height: titleHeight,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: ClipRect(
              child: DetailHeroLogoTitle(
                images: logoRequest,
                fallbackTitle: item.title,
                maxHeight: titleHeight,
                maxWidth: collapsed ? 320 : (compact ? 340 : 420),
                fallbackFontSize: collapsed ? 24 : (compact ? 28 : 38),
              ),
            ),
          ),
        ),
        if (secondary.isNotEmpty) ...[
          SizedBox(height: spacing),
          Text(
            key: const ValueKey('poster_browse_secondary_label'),
            secondary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.88),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        if (metaWidgets.isNotEmpty) ...[
          SizedBox(height: collapsed ? 4 : (compact ? 6 : 10)),
          Wrap(
            spacing: collapsed ? 5 : (compact ? 6 : 8),
            runSpacing: collapsed ? 3 : (compact ? 5 : 6),
            children: metaWidgets,
          ),
        ],
        if (overview.isNotEmpty) ...[
          SizedBox(height: spacing),
          Text(
            overview,
            maxLines: collapsed ? 2 : 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.86),
              height: 1.35,
            ),
          ),
        ],
        SizedBox(height: collapsed ? 6 : (compact ? 12 : 18)),
        Wrap(
          spacing: collapsed ? 6 : (compact ? 8 : 12),
          runSpacing: collapsed ? 4 : (compact ? 8 : 10),
          children: [
            ElevatedButton(
              onPressed: onPlay,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  horizontal: collapsed ? 12 : (compact ? 16 : 22),
                  vertical: collapsed ? 6 : (compact ? 9 : 12),
                ),
                visualDensity: compact || collapsed
                    ? VisualDensity.compact
                    : VisualDensity.standard,
              ),
              child: Text(l10n.detailPlay),
            ),
            OutlinedButton(
              onPressed: onDetail,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.72)),
                padding: EdgeInsets.symmetric(
                  horizontal: collapsed ? 12 : (compact ? 14 : 20),
                  vertical: collapsed ? 6 : (compact ? 9 : 12),
                ),
                visualDensity: compact || collapsed
                    ? VisualDensity.compact
                    : VisualDensity.standard,
              ),
              child: Text(l10n.posterBrowseDetail),
            ),
          ],
        ),
      ],
    );
  }
}
