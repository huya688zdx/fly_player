import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_theme.dart';
import 'capability_badge_mapper.dart';

class MediaPosterCard extends StatelessWidget {
  final List<String> urls;
  final String token;
  final String title;
  final String subtitle;
  final double? imageAspectRatioHint;
  final double? rating;
  final List<String> resolutions;
  final bool watched;
  final double imageHeight;
  final double titleFontSize;
  final double subtitleFontSize;
  final bool expandImageToFit;
  final BoxFit imageFit;
  final bool autoFitByImageAspect;
  final String? heroTag;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const MediaPosterCard({
    super.key,
    required this.urls,
    required this.token,
    required this.title,
    required this.subtitle,
    required this.imageHeight,
    this.imageAspectRatioHint,
    this.rating,
    this.resolutions = const [],
    this.watched = false,
    this.titleFontSize = 12,
    this.subtitleFontSize = 11,
    this.expandImageToFit = false,
    this.imageFit = BoxFit.cover,
    this.autoFitByImageAspect = false,
    this.heroTag,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final posterArea = heroTag == null || heroTag!.isEmpty
        ? _buildPosterArea()
        : Hero(tag: heroTag!, child: _buildPosterArea());
    return RepaintBoundary(
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (expandImageToFit)
                Expanded(
                  child: SizedBox(width: double.infinity, child: posterArea),
                )
              else
                SizedBox(width: double.infinity, child: posterArea),
              const SizedBox(height: 3),
              SizedBox(
                width: double.infinity,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: titleFontSize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: subtitleFontSize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPosterArea() {
    const fallback = AppThemePalette.fallback;
    return SizedBox(
      width: double.infinity,
      height: expandImageToFit ? null : imageHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: fallback.surfaceStrong,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 0.6,
              ),
            ),
            child: _PosterImage(
              urls: urls,
              token: token,
              fit: imageFit,
              aspectRatioHint: imageAspectRatioHint,
              autoFitByImageAspect: autoFitByImageAspect,
              fallback: Center(
                child: Icon(
                  Icons.movie,
                  color: fallback.textMuted.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
          if (rating != null && rating! > 0)
            Positioned(
              left: 6,
              top: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFC5A425),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  rating!.toStringAsFixed(1),
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          if (resolutions.isNotEmpty || watched)
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    widthFactor: 1,
                    heightFactor: 0.60,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.12),
                            Colors.black.withValues(alpha: 0.32),
                          ],
                          stops: const [0.0, 0.7, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (watched)
            Positioned(
              left: 6,
              bottom: 4,
              child: SvgPicture.asset(
                'assets/icons/watched_selected.svg',
                width: 16,
                height: 16,
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
            ),
          if (resolutions.isNotEmpty)
            Positioned(
              right: 0,
              bottom: 4,
              child: Row(
                children: [
                  for (int i = 0; i < resolutions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 0),
                    _PosterCapabilityBadge(label: resolutions[i]),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PosterCapabilityBadge extends StatelessWidget {
  final String label;

  const _PosterCapabilityBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final normalized = CapabilityBadgeMapper.normalize(label);
    if (normalized.isEmpty) return const SizedBox.shrink();

    final asset = CapabilityBadgeMapper.badgeAsset(normalized);
    if (asset != null) {
      return SizedBox(
        height: 14,
        child: SvgPicture.asset(asset, fit: BoxFit.contain),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(color: const Color(0xFFD6DEE8), width: 1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        normalized,
        style: const TextStyle(
          color: Color(0xFFD6DEE8),
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
    );
  }
}

class _PosterImage extends StatefulWidget {
  final List<String> urls;
  final String token;
  final BoxFit fit;
  final double? aspectRatioHint;
  final bool autoFitByImageAspect;
  final Widget fallback;

  const _PosterImage({
    required this.urls,
    required this.token,
    required this.fit,
    required this.aspectRatioHint,
    required this.autoFitByImageAspect,
    required this.fallback,
  });

  @override
  State<_PosterImage> createState() => _PosterImageState();
}

class _PosterImageState extends State<_PosterImage> {
  int _index = 0;
  bool _fallbackScheduled = false;
  late Map<String, String> _headers;

  @override
  void initState() {
    super.initState();
    _headers = _imageHeaders(widget.token);
  }

  @override
  void didUpdateWidget(covariant _PosterImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.urls, widget.urls)) {
      _index = 0;
      _fallbackScheduled = false;
    }
    if (oldWidget.token != widget.token) {
      _headers = _imageHeaders(widget.token);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty ||
        _index >= widget.urls.length ||
        widget.token.trim().isEmpty) {
      return widget.fallback;
    }

    final url = widget.urls[_index];
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.of(context).devicePixelRatio;
        final cacheW = constraints.maxWidth.isFinite
            ? (constraints.maxWidth * dpr).round().clamp(120, 1200)
            : null;
        final cacheH = constraints.maxHeight.isFinite
            ? (constraints.maxHeight * dpr).round().clamp(120, 1200)
            : null;
        return Image.network(
          url,
          fit: widget.fit,
          alignment: Alignment.center,
          filterQuality: FilterQuality.none,
          gaplessPlayback: true,
          cacheWidth: cacheW,
          cacheHeight: cacheH,
          headers: _headers,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            final loaded = wasSynchronouslyLoaded || frame != null;
            if (loaded) return child;
            return widget.fallback;
          },
          errorBuilder: (context, error, stackTrace) {
            if (_index + 1 < widget.urls.length) {
              final nextUrl = widget.urls[_index + 1];
              debugPrint(
                '[IMG][POSTER] failed url=$url error=$error -> fallback=$nextUrl',
              );
              _scheduleFallback();
              return widget.fallback;
            }
            debugPrint(
              '[IMG][POSTER] failed url=$url error=$error -> no_more_fallback',
            );
            return widget.fallback;
          },
        );
      },
    );
  }

  void _scheduleFallback() {
    if (_fallbackScheduled) return;
    _fallbackScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_index + 1 >= widget.urls.length) {
        _fallbackScheduled = false;
        return;
      }
      setState(() {
        _fallbackScheduled = false;
        _index += 1;
      });
    });
  }
}

Map<String, String> _imageHeaders(String token) {
  return <String, String>{'Authorization': token, 'Trim-MC-token': token};
}
