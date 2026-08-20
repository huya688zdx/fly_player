import 'package:flutter/material.dart';

import 'poster_browse_display_item.dart';

@immutable
class PosterBrowsePosterCardMetrics {
  static const double imageAspectRatio = 1.5;
  static const double imageTextGap = 8;
  static const double secondaryTextGap = 3;

  const PosterBrowsePosterCardMetrics._();

  static double textHeight({
    required String text,
    required TextStyle style,
    required int maxLines,
    required double width,
    required TextScaler textScaler,
  }) {
    if (text.trim().isEmpty || maxLines <= 0 || width <= 0) {
      return 0;
    }
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: width);
    return painter.height;
  }

  static double contentHeight({
    required double width,
    required String title,
    required String secondaryLabel,
    required TextStyle titleStyle,
    required TextStyle secondaryStyle,
    required int titleMaxLines,
    required bool showSecondary,
    required TextScaler textScaler,
  }) {
    final titleHeight = textHeight(
      text: title,
      style: titleStyle,
      maxLines: titleMaxLines,
      width: width,
      textScaler: textScaler,
    );
    final secondaryText = showSecondary ? secondaryLabel.trim() : '';
    final secondaryHeight = textHeight(
      text: secondaryText,
      style: secondaryStyle,
      maxLines: 1,
      width: width,
      textScaler: textScaler,
    );
    return width * imageAspectRatio +
        imageTextGap +
        titleHeight +
        (secondaryHeight > 0 ? secondaryTextGap + secondaryHeight : 0);
  }
}

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
  final double? availableHeight;
  final int titleMaxLines;
  final bool showSecondary;
  final bool showTitle;
  final double focusScale;

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
    this.availableHeight,
    this.titleMaxLines = 2,
    this.showSecondary = true,
    this.showTitle = true,
    this.focusScale = 1.025,
  });

  @override
  Widget build(BuildContext context) {
    if (availableHeight != null && availableHeight! <= 0) {
      return SizedBox(width: width, height: 0);
    }
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: focused ? FontWeight.w600 : FontWeight.w500,
    );
    final secondaryStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.72),
    );
    final textHeight = showTitle
        ? PosterBrowsePosterCardMetrics.contentHeight(
                width: width,
                title: item.title,
                secondaryLabel: showSecondary ? secondaryLabel : '',
                titleStyle: titleStyle ?? const TextStyle(),
                secondaryStyle: secondaryStyle ?? const TextStyle(),
                titleMaxLines: titleMaxLines,
                showSecondary: showSecondary,
                textScaler: MediaQuery.textScalerOf(context),
              ) -
              width * PosterBrowsePosterCardMetrics.imageAspectRatio -
              PosterBrowsePosterCardMetrics.imageTextGap
        : 0;
    final imageHeight = availableHeight == null
        ? width * PosterBrowsePosterCardMetrics.imageAspectRatio
        : (availableHeight! -
                  textHeight -
                  PosterBrowsePosterCardMetrics.imageTextGap)
              .clamp(
                0.0,
                width * PosterBrowsePosterCardMetrics.imageAspectRatio,
              )
              .toDouble();
    final progressValue = _progressValue;

    return Semantics(
      label: item.title,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: availableHeight,
          child: Transform.scale(
            scale: focused ? focusScale : 1.0,
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
                if (showTitle) ...[
                  Text(
                    item.title,
                    maxLines: titleMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                  if (showSecondary && secondaryLabel.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      secondaryLabel.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: secondaryStyle,
                    ),
                  ],
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
