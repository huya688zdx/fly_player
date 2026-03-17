import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../theme/app_theme.dart';

class CreditPersonItem {
  final String personGuid;
  final String name;
  final String subtitle;
  final List<String> imageUrls;

  const CreditPersonItem({
    this.personGuid = '',
    required this.name,
    required this.subtitle,
    this.imageUrls = const [],
  });
}

class CreditsSection extends StatelessWidget {
  final String title;
  final List<CreditPersonItem> items;
  final String token;
  final ValueChanged<CreditPersonItem>? onTap;

  const CreditsSection({
    super.key,
    required this.title,
    required this.items,
    required this.token,
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
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            padding: EdgeInsets.zero,
            separatorBuilder: (_, __) => SizedBox(width: itemGap),
            itemBuilder: (context, index) {
              final item = items[index];
              return _CreditPersonCard(
                item: item,
                token: token,
                cardWidth: cardWidth,
                avatarSize: avatarSize,
                nameSize: nameSize,
                subtitleSize: subtitleSize,
                onTap: onTap,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CreditPersonCard extends StatelessWidget {
  final CreditPersonItem item;
  final String token;
  final double cardWidth;
  final double avatarSize;
  final double nameSize;
  final double subtitleSize;
  final ValueChanged<CreditPersonItem>? onTap;

  const _CreditPersonCard({
    required this.item,
    required this.token,
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
              child: _CreditAvatar(urls: item.imageUrls, token: token),
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
  final List<String> urls;
  final String token;

  const _CreditAvatar({required this.urls, required this.token});

  @override
  State<_CreditAvatar> createState() => _CreditAvatarState();
}

class _CreditAvatarState extends State<_CreditAvatar> {
  int _index = 0;

  @override
  void didUpdateWidget(covariant _CreditAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final urlsChanged = !listEquals(oldWidget.urls, widget.urls);
    final tokenChanged = oldWidget.token != widget.token;
    if (urlsChanged || tokenChanged) {
      _index = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (widget.urls.isEmpty ||
        _index >= widget.urls.length ||
        widget.token.trim().isEmpty) {
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
        final dpr = MediaQuery.of(context).devicePixelRatio;
        final cacheW = constraints.maxWidth.isFinite
            ? (constraints.maxWidth * dpr).round().clamp(128, 768)
            : 320;
        return Image.network(
          widget.urls[_index],
          fit: BoxFit.cover,
          alignment: Alignment.center,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
          cacheWidth: cacheW,
          headers: {
            'Authorization': widget.token,
            'Trim-MC-token': widget.token,
          },
          errorBuilder: (_, error, ___) {
            if (_index + 1 < widget.urls.length) {
              final currentUrl = widget.urls[_index];
              final nextUrl = widget.urls[_index + 1];
              debugPrint(
                '[IMG][CREDIT_AVATAR] failed url=$currentUrl error=$error -> fallback=$nextUrl',
              );
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _index += 1);
              });
              return const SizedBox.expand();
            }
            debugPrint(
              '[IMG][CREDIT_AVATAR] failed url=${widget.urls[_index]} error=$error -> no_more_fallback',
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
