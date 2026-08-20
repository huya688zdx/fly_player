import 'package:flutter/material.dart';

import 'poster_browse_display_item.dart';

class PosterBrowsePosterCard extends StatelessWidget {
  static const double defaultWidth = 116;

  final PosterBrowseDisplayItem item;
  final bool focused;
  final bool showProgress;
  final String imageUrl;
  final Map<String, String> imageHeaders;
  final String secondaryLabel;
  final VoidCallback onTap;
  final double width;

  const PosterBrowsePosterCard({
    super.key,
    required this.item,
    required this.focused,
    required this.showProgress,
    required this.imageUrl,
    required this.imageHeaders,
    required this.secondaryLabel,
    required this.onTap,
    this.width = defaultWidth,
  });

  @override
  Widget build(BuildContext context) {
    final imageHeight = width * 1.5;
    final progressValue = _progressValue;

    return Semantics(
      label: item.title,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: width,
          child: Transform.scale(
            scale: focused ? 1.025 : 1.0,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: width,
                  height: imageHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _PosterImage(
                        url: imageUrl,
                        headers: imageHeaders,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      if (item.ratingText.trim().isNotEmpty)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: _RatingBadge(text: item.ratingText.trim()),
                        ),
                      if (progressValue != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(12),
                            ),
                            child: LinearProgressIndicator(
                              minHeight: 4,
                              value: progressValue,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.24,
                              ),
                            ),
                          ),
                        ),
                      if (focused)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: focused ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                if (secondaryLabel.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    secondaryLabel.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).textTheme.bodySmall?.color?.withValues(alpha: 0.72),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  double? get _progressValue {
    final duration = item.durationSeconds;
    final resume = item.card.resumePositionSeconds;
    if (!showProgress || duration <= 0 || resume <= 0) {
      return null;
    }
    return (resume / duration).clamp(0.0, 1.0).toDouble();
  }
}

class _PosterImage extends StatelessWidget {
  final String url;
  final Map<String, String> headers;
  final BorderRadius borderRadius;

  const _PosterImage({
    required this.url,
    required this.headers,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: borderRadius,
      ),
    );
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) {
      return placeholder;
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: Image(
        image: NetworkImage(
          trimmedUrl,
          headers: headers.isEmpty ? null : headers,
        ),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) => placeholder,
      ),
    );
  }
}

class _RatingBadge extends StatelessWidget {
  final String text;

  const _RatingBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          '★ $text',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }
}
