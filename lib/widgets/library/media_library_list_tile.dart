import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/app_theme.dart';
import '../../ui/capability_badge_mapper.dart';

class MediaLibraryListTile extends StatelessWidget {
  final List<String> urls;
  final String token;
  final String title;
  final String subtitle;
  final List<String> resolutions;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMoreTap;

  const MediaLibraryListTile({
    super.key,
    required this.urls,
    required this.token,
    required this.title,
    required this.subtitle,
    required this.resolutions,
    required this.onTap,
    required this.onLongPress,
    required this.onMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final resolutionAsset = _resolutionBadgeAsset(resolutions);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
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
                    title,
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
                      if (resolutionAsset != null)
                        SizedBox(
                          height: 18,
                          child: SvgPicture.asset(
                            resolutionAsset,
                            fit: BoxFit.contain,
                            colorFilter: ColorFilter.mode(
                              colors.chipText,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                      Text(
                        subtitle,
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
              onPressed: onMoreTap,
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
  }
}

String? _resolutionBadgeAsset(List<String> resolutions) {
  if (resolutions.isEmpty) {
    return null;
  }
  final normalized = CapabilityBadgeMapper.normalize(resolutions.first);
  return CapabilityBadgeMapper.badgeAsset(normalized);
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.of(context).devicePixelRatio.clamp(1.0, 2.0);
        final cacheWidth = constraints.maxWidth.isFinite
            ? (constraints.maxWidth * dpr).round().clamp(96, 220)
            : 160;
        final cacheHeight = constraints.maxHeight.isFinite
            ? (constraints.maxHeight * dpr).round().clamp(72, 160)
            : 104;
        return Image.network(
          urls.first,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.none,
          cacheWidth: cacheWidth,
          cacheHeight: cacheHeight,
          headers: <String, String>{
            'Authorization': token,
            'Trim-MC-token': token,
          },
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
      },
    );
  }
}
