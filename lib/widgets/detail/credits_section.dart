import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../desktop/desktop.dart';
import '../../media_backend/media_image_request.dart';
import '../../theme/app_theme.dart';
import '../../theme/detail_tokens.dart';
import '../../ui/layout_adaptive.dart';

class CreditPersonItem {
  final String personGuid;
  final String name;
  final String subtitle;
  final MediaImageRequest images;

  const CreditPersonItem({
    this.personGuid = '',
    required this.name,
    required this.subtitle,
    this.images = MediaImageRequest.empty,
  });
}

class CreditsSection extends StatelessWidget {
  final String title;
  final List<CreditPersonItem> items;
  final ValueChanged<CreditPersonItem>? onTap;

  const CreditsSection({
    super.key,
    required this.title,
    required this.items,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final colors = context.appColors;
    final media = MediaQuery.of(context);
    final shortestSide = media.size.shortestSide;
    final scale = (shortestSide / 411).clamp(0.88, 1.0);
    final textScale = media.textScaler.scale(1).clamp(1.0, 1.2);
    final avatarSize = (78.0 * scale).clamp(68.0, 80.0);
    final cardWidth = (avatarSize + 6).clamp(74.0, 88.0);
    final nameSize = (12.6 * scale).clamp(11.3, 13.2);
    final subtitleSize = (10.6 * scale).clamp(9.8, 11.4);
    final textBlockHeight = (46.0 * textScale).clamp(46.0, 56.0);
    final sectionHeight = avatarSize + textBlockHeight;
    final itemGap = (10.0 * scale).clamp(7.0, 10.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: sectionHeight,
          // 桌面档接入悬停翻页箭头（与首页海报行/选集行同款）；非桌面档原样透出。
          child: HoverScrollRow(
            enabled: MediaLayoutProfile.of(context).isDesktopTier,
            edgePadding: DetailTokens.screenHorizontalPadding,
            builder: (controller) => ListView.separated(
              controller: controller,
              scrollDirection: Axis.horizontal,
              cacheExtent: (cardWidth + itemGap) * 2,
              itemCount: items.length,
              padding: EdgeInsets.zero,
              separatorBuilder: (_, __) => SizedBox(width: itemGap),
              itemBuilder: (context, index) {
                final item = items[index];
                return _CreditPersonCard(
                  item: item,
                  cardWidth: cardWidth,
                  avatarSize: avatarSize,
                  nameSize: nameSize,
                  subtitleSize: subtitleSize,
                  onTap: onTap,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _CreditPersonCard extends StatelessWidget {
  final CreditPersonItem item;
  final double cardWidth;
  final double avatarSize;
  final double nameSize;
  final double subtitleSize;
  final ValueChanged<CreditPersonItem>? onTap;

  const _CreditPersonCard({
    required this.item,
    required this.cardWidth,
    required this.avatarSize,
    required this.nameSize,
    required this.subtitleSize,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final card = SizedBox(
      width: cardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipOval(
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: avatarSize,
              height: avatarSize,
              child: _CreditAvatar(images: item.images),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: nameSize,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: subtitleSize,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return card;
    return InkWell(
      onTap: () => onTap!(item),
      borderRadius: BorderRadius.circular(12),
      child: card,
    );
  }
}

class _CreditAvatar extends StatefulWidget {
  final MediaImageRequest images;

  const _CreditAvatar({required this.images});

  @override
  State<_CreditAvatar> createState() => _CreditAvatarState();
}

class _CreditAvatarState extends State<_CreditAvatar> {
  int _index = 0;

  @override
  void didUpdateWidget(covariant _CreditAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final urlsChanged = !listEquals(oldWidget.images.urls, widget.images.urls);
    final headersChanged = !mapEquals(
      oldWidget.images.headers,
      widget.images.headers,
    );
    if (urlsChanged || headersChanged) {
      _index = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final urls = widget.images.urls;
    final hasUrl = _index < urls.length;
    // 无候选或无鉴权(既无 header 也非自鉴权直链)时回退占位,
    // 判定语义由 MediaImageRequest.canLoad 统一承载。
    if (!hasUrl || !widget.images.canLoad) {
      return Container(
        color: colors.surfaceStrong,
        alignment: Alignment.center,
        child: Icon(
          Icons.person,
          color: colors.textMuted.withValues(alpha: 0.72),
          size: 36,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.of(context).devicePixelRatio.clamp(1.0, 1.8);
        final cacheW = constraints.maxWidth.isFinite
            ? (constraints.maxWidth * dpr).round().clamp(96, 180)
            : 144;
        return Image.network(
          urls[_index],
          fit: BoxFit.cover,
          alignment: Alignment.center,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
          cacheWidth: cacheW,
          headers: widget.images.headers,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: child,
            );
          },
          errorBuilder: (_, error, ___) {
            if (_index + 1 < urls.length) {
              final currentUrl = urls[_index];
              final nextUrl = urls[_index + 1];
              debugPrint(
                '[IMG][CREDIT_AVATAR] failed url=$currentUrl error=$error -> fallback=$nextUrl',
              );
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _index += 1);
              });
              return const SizedBox.expand();
            }
            debugPrint(
              '[IMG][CREDIT_AVATAR] failed url=${urls[_index]} error=$error -> no_more_fallback',
            );
            return Container(
              color: colors.surfaceStrong,
              alignment: Alignment.center,
              child: Icon(
                Icons.person,
                color: colors.textMuted.withValues(alpha: 0.72),
                size: 36,
              ),
            );
          },
        );
      },
    );
  }
}
