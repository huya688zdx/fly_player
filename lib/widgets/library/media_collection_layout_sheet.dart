import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../models/media_collection_view_type.dart';
import '../../theme/app_theme.dart';

class MediaCollectionLayoutSheet extends StatelessWidget {
  final MediaCollectionViewType currentViewType;

  const MediaCollectionLayoutSheet({super.key, required this.currentViewType});

  static Future<MediaCollectionViewType?> show(
    BuildContext context, {
    required MediaCollectionViewType currentViewType,
  }) {
    final colors = context.appColors;
    return showModalBottomSheet<MediaCollectionViewType>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.backgroundElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return MediaCollectionLayoutSheet(currentViewType: currentViewType);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final media = MediaQuery.of(context);
    final compact = media.size.height < 740;
    final verticalGap = compact ? 16.0 : 22.0;
    final sectionGap = compact ? 10.0 : 12.0;
    final bottomPadding = media.padding.bottom + 20.0;
    final posterWallSelected = currentViewType.isPosterWall;
    final horizontalSelected =
        currentViewType == MediaCollectionViewType.horizontalPoster;
    final verticalSelected =
        currentViewType == MediaCollectionViewType.verticalPoster;
    final listSelected = currentViewType == MediaCollectionViewType.list;
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.82),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 10, 20, bottomPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 56,
                  height: 5,
                  decoration: BoxDecoration(
                    color: colors.borderStrong,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              SizedBox(height: compact ? 14 : 18),
              Center(
                child: Text(
                  l10n.collectionLayoutTitle,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(height: verticalGap),
              Text(
                l10n.collectionLayoutViewSection,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: sectionGap),
              Row(
                children: [
                  Expanded(
                    child: _LayoutChoiceTile(
                      title: l10n.collectionLayoutPosterWall,
                      icon: Icons.grid_view_rounded,
                      selected: posterWallSelected,
                      compact: compact,
                      onTap: () {
                        Navigator.of(context).pop(
                          horizontalSelected
                              ? MediaCollectionViewType.horizontalPoster
                              : MediaCollectionViewType.verticalPoster,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _LayoutChoiceTile(
                      title: l10n.collectionLayoutList,
                      icon: Icons.view_list_rounded,
                      selected: listSelected,
                      compact: compact,
                      onTap: () {
                        Navigator.of(context).pop(MediaCollectionViewType.list);
                      },
                    ),
                  ),
                ],
              ),
              if (posterWallSelected) ...[
                SizedBox(height: verticalGap),
                Text(
                  l10n.collectionLayoutPosterSection,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: sectionGap),
                Row(
                  children: [
                    Expanded(
                      child: _LayoutChoiceTile(
                        title: l10n.collectionLayoutHorizontalPoster,
                        icon: Icons.crop_16_9_rounded,
                        selected: horizontalSelected,
                        compact: compact,
                        onTap: () {
                          Navigator.of(
                            context,
                          ).pop(MediaCollectionViewType.horizontalPoster);
                        },
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _LayoutChoiceTile(
                        title: l10n.collectionLayoutVerticalPoster,
                        icon: Icons.crop_portrait_rounded,
                        selected: verticalSelected,
                        compact: compact,
                        onTap: () {
                          Navigator.of(
                            context,
                          ).pop(MediaCollectionViewType.verticalPoster);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LayoutChoiceTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  const _LayoutChoiceTile({
    required this.title,
    required this.icon,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final borderColor = selected ? colors.selection : colors.borderSubtle;
    final backgroundColor = selected
        ? colors.selectionSoft
        : colors.surfaceStrong;
    final contentColor = selected ? colors.selectionStrong : colors.textPrimary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: compact ? 64 : 74,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor, width: selected ? 1.2 : 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: contentColor, size: compact ? 20 : 22),
            SizedBox(width: compact ? 8 : 10),
            Text(
              title,
              style: TextStyle(
                color: contentColor,
                fontSize: compact ? 15 : 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
