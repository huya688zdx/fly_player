import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../media_backend/media_image_request.dart';
import '../../theme/app_theme.dart';
import '../../ui/capability_badge_mapper.dart';
import '../../ui/media_placeholder.dart';

class MediaLibraryListTile extends StatelessWidget {
  final MediaImageRequest images;
  final String title;
  final String subtitle;
  final List<String> resolutions;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMoreTap;

  const MediaLibraryListTile({
    super.key,
    required this.images,
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
                child: _ListThumb(images: images),
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
  final MediaImageRequest images;

  const _ListThumb({required this.images});

  @override
  Widget build(BuildContext context) {
    // H-018:"能否加载"改由 MediaImageRequest.canLoad 承载——飞牛无 token
    // 仍回退占位,Emby 自鉴权直链(api_key)即使 NAS token 为空也照常加载。
    if (!images.canLoad) {
      return const MediaPlaceholder();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.of(context).devicePixelRatio.clamp(1.0, 2.0);
        final cacheWidth = constraints.maxWidth.isFinite
            ? (constraints.maxWidth * dpr).round().clamp(96, 220)
            : 160;
        // 图源是竖版海报(约2:3),此处缩略图框是横版(约16:10)。cacheWidth+
        // cacheHeight 双维同传会走 ResizeImagePolicy.exact 精确缩放(不保比
        // 例),把人脸/构图压扁;只传 cacheWidth 单维解码保比例,cover 再按高
        // 裁剪即可(同 media_collection_browser.dart 的 _ListThumb 修法)。
        return Image.network(
          images.urls.first,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.none,
          cacheWidth: cacheWidth,
          headers: images.headers,
          errorBuilder: (_, __, ___) {
            return const MediaPlaceholder();
          },
        );
      },
    );
  }
}
