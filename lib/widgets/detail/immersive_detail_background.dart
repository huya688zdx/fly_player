import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../theme/detail_tokens.dart';

class ImmersiveDetailBackground extends StatefulWidget {
  final List<String> urls;
  final String token;
  final double scrollOffset;
  final double posterHeight;

  final double imageScale;
  final BoxFit imageFit;
  final Alignment imageAlignment;

  final bool enableBottomFade;

  final double fadeStart;
  final double fadeMid;

  final bool fillGapsWithImage;
  final bool useMonetTint;

  final double parallaxFactor;
  final bool enableRealtimeBlur;
  final double overlayOpacity;
  final double maxScrollZoom;

  const ImmersiveDetailBackground({
    super.key,
    required this.urls,
    required this.token,
    required this.scrollOffset,
    required this.posterHeight,
    this.imageScale = 1.0,
    this.imageFit = BoxFit.cover,
    this.imageAlignment = Alignment.topCenter,
    this.enableBottomFade = false,
    this.fadeStart = 0.58,
    this.fadeMid = 0.82,
    this.fillGapsWithImage = false,
    this.useMonetTint = false,
    this.parallaxFactor = 0.40,
    this.enableRealtimeBlur = false,
    this.overlayOpacity = 1.0,
    this.maxScrollZoom = 1.24,
  });

  @override
  State<ImmersiveDetailBackground> createState() =>
      _ImmersiveDetailBackgroundState();
}

class _ImmersiveDetailBackgroundState extends State<ImmersiveDetailBackground> {
  int _index = 0;
  Color? _monetTint;
  String _tintUrl = '';

  @override
  void initState() {
    super.initState();
    _refreshMonetTint();
  }

  @override
  void didUpdateWidget(covariant ImmersiveDetailBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.urls, widget.urls) ||
        oldWidget.useMonetTint != widget.useMonetTint ||
        oldWidget.token != widget.token) {
      _index = 0;
      _monetTint = null;
      _tintUrl = '';
      _refreshMonetTint();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    final mediaSize = MediaQuery.of(context).size;
    final screenWidth = mediaSize.width;
    final screenHeight = mediaSize.height;

    final heroHeight = widget.posterHeight.clamp(
      screenHeight * 0.32,
      screenHeight * 0.78,
    );
    final topOverscroll = (-widget.scrollOffset).clamp(0.0, 220.0);
    final expandedHeroHeight = heroHeight + topOverscroll;

    final parallaxMax = (screenHeight * 0.85).clamp(180.0, 560.0);

    final collapseOffset = widget.scrollOffset.clamp(0.0, double.infinity);
    final parallaxShift = (collapseOffset * widget.parallaxFactor).clamp(
      0.0,
      parallaxMax,
    );

    final blurT = (collapseOffset / 240).clamp(0.0, 1.0);
    final sigma = lerpDouble(0, 18, blurT) ?? 0;

    final effectiveSigma = (widget.enableRealtimeBlur && !isAndroid)
        ? sigma
        : 0.0;
    final zoomT = Curves.easeOutCubic.transform(
      (topOverscroll / 160).clamp(0.0, 1.0),
    );
    final scrollZoom =
        1.0 + ((widget.maxScrollZoom.clamp(1.0, 1.3) - 1.0) * zoomT);

    final enableGapBlur =
        widget.enableRealtimeBlur && widget.fillGapsWithImage && !isAndroid;

    final fusionStart = widget.fadeStart.clamp(0.30, 0.72).toDouble();
    final overlayOpacity = widget.overlayOpacity.clamp(0.0, 1.0);
    final layerA = (fusionStart + 0.10)
        .clamp(fusionStart + 0.05, 0.84)
        .toDouble();
    final layerB = (fusionStart + 0.22).clamp(layerA + 0.05, 0.92).toDouble();
    final layerC = (fusionStart + 0.34).clamp(layerB + 0.05, 0.97).toDouble();

    final ambientTint = _monetTint?.withValues(alpha: 0.28);
    final baseScrimAlpha =
        (widget.enableBottomFade ? 0.03 : 0.15) * overlayOpacity;
    final radialEndColor =
        ambientTint ??
        Colors.black.withValues(
          alpha: (widget.enableBottomFade ? 0.05 : 0.19) * overlayOpacity,
        );
    final topShadeStrong = Colors.black.withValues(
      alpha: 0.30 * overlayOpacity,
    );
    final topShadeMid = Colors.black.withValues(alpha: 0.10 * overlayOpacity);

    final heroImageHeight = expandedHeroHeight + parallaxMax + 80;

    return RepaintBoundary(
      child: Stack(
        children: [
          Positioned.fill(child: Container(color: DetailTokens.pageBackground)),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: expandedHeroHeight,
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Transform.translate(
                    offset: Offset(0, -parallaxShift),
                    child: SizedBox(
                      width: screenWidth,
                      height: heroImageHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (enableGapBlur)
                            Opacity(
                              opacity: 0.72,
                              child: ImageFiltered(
                                imageFilter: ImageFilter.blur(
                                  sigmaX: 10,
                                  sigmaY: 10,
                                ),
                                child: _BackgroundImage(
                                  urls: widget.urls,
                                  token: widget.token,
                                  index: _index,
                                  fit: BoxFit.cover,
                                  alignment: widget.imageAlignment,
                                  onErrorNext: _nextFallbackImage,
                                ),
                              ),
                            ),
                          if (widget.fillGapsWithImage && isAndroid)
                            Opacity(
                              opacity: 0.38,
                              child: _BackgroundImage(
                                urls: widget.urls,
                                token: widget.token,
                                index: _index,
                                fit: BoxFit.cover,
                                alignment: widget.imageAlignment,
                                onErrorNext: _nextFallbackImage,
                              ),
                            ),
                          Transform.scale(
                            scale: widget.imageScale * scrollZoom,
                            alignment: widget.imageAlignment,
                            child: _BackgroundImage(
                              urls: widget.urls,
                              token: widget.token,
                              index: _index,
                              fit: widget.imageFit,
                              alignment: widget.imageAlignment,
                              onErrorNext: _nextFallbackImage,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: baseScrimAlpha),
                    ),
                  ),

                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0.0, -0.12),
                          radius: 1.18,
                          colors: [Colors.transparent, radialEndColor],
                          stops: const [0.42, 1.0],
                        ),
                      ),
                    ),
                  ),

                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            topShadeStrong,
                            topShadeMid,
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.16, 0.34],
                        ),
                      ),
                    ),
                  ),

                  if (effectiveSigma > 0.01)
                    BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: effectiveSigma,
                        sigmaY: effectiveSigma,
                      ),
                      child: const SizedBox.expand(),
                    ),
                ],
              ),
            ),
          ),

          if (widget.enableBottomFade)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: expandedHeroHeight + 220,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: const [
                        Colors.transparent,
                        Colors.transparent,
                        Color(0x1F000000),
                        Color(0x1F000000),
                        Color(0x4D000000),
                        Color(0x4D000000),
                        Color(0x8A000000),
                        Color(0x8A000000),
                        DetailTokens.pageBackground,
                      ],
                      stops: [
                        0.0,
                        fusionStart,
                        layerA,
                        layerA,
                        layerB,
                        layerB,
                        layerC,
                        layerC,
                        1.0,
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _nextFallbackImage() {
    if (_index + 1 < widget.urls.length) {
      setState(() => _index += 1);
      _refreshMonetTint();
    }
  }

  Future<void> _refreshMonetTint() async {
    if (!widget.useMonetTint ||
        widget.urls.isEmpty ||
        _index >= widget.urls.length) {
      if (_monetTint != null && mounted) {
        setState(() => _monetTint = null);
      }
      return;
    }

    final url = widget.urls[_index];
    if (_tintUrl == url && _monetTint != null) return;

    _tintUrl = url;

    try {
      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(
          url,
          headers: {
            'Authorization': widget.token,
            'Trim-MC-token': widget.token,
          },
        ),
        maximumColorCount: 14,
        size: const Size(220, 140),
      );

      final seed =
          palette.darkVibrantColor?.color ??
          palette.dominantColor?.color ??
          palette.mutedColor?.color;

      if (seed == null || !mounted) return;

      var hsl = HSLColor.fromColor(seed);
      hsl = hsl.withSaturation((hsl.saturation * 0.45).clamp(0.08, 0.28));
      hsl = hsl.withLightness((hsl.lightness * 0.45).clamp(0.10, 0.22));

      setState(() => _monetTint = hsl.toColor());
    } catch (_) {
      if (mounted) setState(() => _monetTint = null);
    }
  }
}

class _BackgroundImage extends StatelessWidget {
  final List<String> urls;
  final String token;
  final int index;
  final BoxFit fit;
  final Alignment alignment;
  final VoidCallback onErrorNext;

  const _BackgroundImage({
    required this.urls,
    required this.token,
    required this.index,
    required this.fit,
    required this.alignment,
    required this.onErrorNext,
  });

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty || index >= urls.length || token.trim().isEmpty) {
      return Container(color: DetailTokens.panelBackground);
    }

    final currentUrl = urls[index];

    return Image.network(
      currentUrl,
      fit: fit,
      alignment: alignment,
      headers: {'Authorization': token, 'Trim-MC-token': token},
      errorBuilder: (_, error, ___) {
        final nextUrl = index + 1 < urls.length ? urls[index + 1] : null;
        debugPrint(
          nextUrl != null
              ? '[IMG][DETAIL_BG] failed url=$currentUrl error=$error -> fallback=$nextUrl'
              : '[IMG][DETAIL_BG] failed url=$currentUrl error=$error -> no_more_fallback',
        );
        WidgetsBinding.instance.addPostFrameCallback((_) => onErrorNext());
        return Container(color: DetailTokens.panelBackground);
      },
    );
  }
}
