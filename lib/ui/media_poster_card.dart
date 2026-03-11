import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'capability_badge_mapper.dart';

class MediaPosterCard extends StatelessWidget {
  final List<String> urls;
  final String token;
  final String title;
  final String subtitle;
  final double? rating;
  final List<String> resolutions;
  final double imageHeight;
  final double titleFontSize;
  final double subtitleFontSize;
  final bool expandImageToFit;
  final BoxFit imageFit;
  final String? heroTag;
  final VoidCallback? onTap;

  const MediaPosterCard({
    super.key,
    required this.urls,
    required this.token,
    required this.title,
    required this.subtitle,
    required this.imageHeight,
    this.rating,
    this.resolutions = const [],
    this.titleFontSize = 12,
    this.subtitleFontSize = 11,
    this.expandImageToFit = false,
    this.imageFit = BoxFit.cover,
    this.heroTag,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final posterArea = heroTag == null || heroTag!.isEmpty
        ? _buildPosterArea()
        : Hero(tag: heroTag!, child: _buildPosterArea());
    return RepaintBoundary(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (expandImageToFit) Expanded(child: posterArea) else posterArea,
            const SizedBox(height: 3),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: titleFontSize,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white60,
                fontSize: subtitleFontSize,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPosterArea() {
    return Stack(
      children: [
        Container(
          height: expandImageToFit ? null : imageHeight,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: const Color(0xFF1B2532),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.8,
            ),
          ),
          child: _PosterImage(
            urls: urls,
            token: token,
            fit: imageFit,
            fallback: const Center(
              child: Icon(Icons.movie, color: Colors.white38),
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
        if (resolutions.isNotEmpty)
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
  final Widget fallback;

  const _PosterImage({
    required this.urls,
    required this.token,
    required this.fit,
    required this.fallback,
  });

  @override
  State<_PosterImage> createState() => _PosterImageState();
}

class _PosterImageState extends State<_PosterImage> {
  int _index = 0;

  @override
  void didUpdateWidget(covariant _PosterImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urls != widget.urls) {
      _index = 0;
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
            ? (constraints.maxHeight * dpr).round().clamp(120, 1800)
            : null;
        final headers = <String, String>{
          'Authorization': widget.token,
          'Trim-MC-token': widget.token,
        };
        return Image.network(
          url,
          fit: widget.fit,
          alignment: Alignment.center,
          filterQuality: FilterQuality.none,
          gaplessPlayback: true,
          cacheWidth: cacheW,
          cacheHeight: cacheH,
          headers: headers,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            final loaded = wasSynchronouslyLoaded || frame != null;
            if (loaded) return child;
            return Stack(
              fit: StackFit.expand,
              children: [
                widget.fallback,
                AnimatedOpacity(
                  opacity: 0,
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  child: child,
                ),
              ],
            );
          },
          errorBuilder: (context, error, stackTrace) {
            if (_index + 1 < widget.urls.length) {
              final nextUrl = widget.urls[_index + 1];
              debugPrint(
                '[IMG][POSTER] failed url=$url error=$error -> fallback=$nextUrl',
              );
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _index += 1;
                  });
                }
              });
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
}
