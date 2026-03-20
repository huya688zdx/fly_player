import 'dart:collection';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../theme/app_theme.dart';
import '../../theme/dynamic_theme_seed_extractor.dart';

const int _maxImmersiveTintCacheEntries = 24;
final LinkedHashMap<String, Color?> _immersiveTintCache =
    LinkedHashMap<String, Color?>();

Color? _cachedImmersiveTint(String url) {
  final hadEntry = _immersiveTintCache.containsKey(url);
  final cached = _immersiveTintCache.remove(url);
  if (hadEntry) {
    _immersiveTintCache[url] = cached;
  }
  return cached;
}

void _storeImmersiveTint(String url, Color? tint) {
  _immersiveTintCache.remove(url);
  _immersiveTintCache[url] = tint;
  while (_immersiveTintCache.length > _maxImmersiveTintCacheEntries) {
    _immersiveTintCache.remove(_immersiveTintCache.keys.first);
  }
}

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
  final Color? ambientTintOverride;
  final Color? bottomFadeTintColor;
  final Color? bottomFadeBackgroundColor;
  final double bottomFadeExtraHeight;

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
    this.ambientTintOverride,
    this.bottomFadeTintColor,
    this.bottomFadeBackgroundColor,
    this.bottomFadeExtraHeight = 180,
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
        oldWidget.ambientTintOverride != widget.ambientTintOverride ||
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
    final colors = context.appColors;
    final isLightSurface = colors.backgroundBase.computeLuminance() >= 0.58;

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

    final fusionStart = widget.fadeStart.clamp(0.30, 0.86).toDouble();
    final fusionMid = widget.fadeMid.clamp(fusionStart + 0.06, 0.94).toDouble();
    final overlayOpacity = widget.overlayOpacity.clamp(0.0, 1.0);
    final layerA = (fusionStart + ((fusionMid - fusionStart) * 0.36))
        .clamp(fusionStart + 0.04, fusionMid - 0.02)
        .toDouble();
    final layerB = fusionMid.toDouble();
    final layerC = (fusionMid + ((1.0 - fusionMid) * 0.42))
        .clamp(layerB + 0.04, 0.98)
        .toDouble();
    final layerD = (layerC + ((1.0 - layerC) * 0.52))
        .clamp(layerC + 0.04, 0.995)
        .toDouble();

    final bottomFadeBackground =
        widget.bottomFadeBackgroundColor ?? colors.backgroundBase;
    final bottomFadeTint =
        widget.bottomFadeTintColor ??
        widget.ambientTintOverride ??
        _monetTint ??
        (isLightSurface ? colors.backgroundElevated : colors.overlayScrim);
    final bottomFogColor = Color.alphaBlend(
      bottomFadeTint.withValues(alpha: isLightSurface ? 0.42 : 0.56),
      bottomFadeBackground,
    );
    final baseScrimAlpha =
        ((widget.enableBottomFade ? 0.0 : (isLightSurface ? 0.0 : 0.03))) *
        overlayOpacity;

    final heroImageHeight = expandedHeroHeight + parallaxMax + 80;

    return RepaintBoundary(
      child: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: colors.backgroundBase)),

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
                      color: colors.overlayScrim.withValues(
                        alpha: baseScrimAlpha,
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
              height: expandedHeroHeight + widget.bottomFadeExtraHeight,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        bottomFogColor.withValues(
                          alpha: isLightSurface ? 0.08 : 0.10,
                        ),
                        bottomFogColor.withValues(
                          alpha: isLightSurface ? 0.18 : 0.22,
                        ),
                        bottomFogColor.withValues(
                          alpha: isLightSurface ? 0.34 : 0.40,
                        ),
                        bottomFadeBackground.withValues(
                          alpha: isLightSurface ? 0.68 : 0.62,
                        ),
                        bottomFadeBackground.withValues(
                          alpha: isLightSurface ? 0.90 : 0.86,
                        ),
                        bottomFadeBackground,
                      ],
                      stops: [
                        0.0,
                        fusionStart,
                        layerA,
                        layerB,
                        layerC,
                        layerD,
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
    if (widget.ambientTintOverride != null ||
        !widget.useMonetTint ||
        widget.urls.isEmpty ||
        _index >= widget.urls.length) {
      if (_monetTint != null && mounted) {
        setState(() => _monetTint = null);
      }
      return;
    }

    final url = widget.urls[_index];
    if (_tintUrl == url && _monetTint != null) return;
    if (_immersiveTintCache.containsKey(url)) {
      final cachedTint = _cachedImmersiveTint(url);
      if (!mounted || _tintUrl == url && _monetTint == cachedTint) return;
      _tintUrl = url;
      setState(() => _monetTint = cachedTint);
      return;
    }

    _tintUrl = url;
    final requestedUrl = url;

    try {
      Color? tint;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final seed = await DynamicThemeSeedExtractor.extract(
          imageUrl: requestedUrl,
          token: widget.token,
        );
        tint = seed == null ? null : _deriveTintColor(seed.backgroundSeed);
      }
      tint ??= await _extractTintWithPalette(requestedUrl);
      _storeImmersiveTint(requestedUrl, tint);
      if (!mounted || _tintUrl != requestedUrl) return;
      setState(() => _monetTint = tint);
    } catch (_) {
      _storeImmersiveTint(requestedUrl, null);
      if (mounted && _tintUrl == requestedUrl) {
        setState(() => _monetTint = null);
      }
    }
  }

  Future<Color?> _extractTintWithPalette(String url) async {
    final palette = await PaletteGenerator.fromImageProvider(
      NetworkImage(
        url,
        headers: {'Authorization': widget.token, 'Trim-MC-token': widget.token},
      ),
      maximumColorCount: 14,
      size: const Size(220, 140),
    );

    final seed =
        palette.darkVibrantColor?.color ??
        palette.dominantColor?.color ??
        palette.mutedColor?.color;
    return seed == null ? null : _deriveTintColor(seed);
  }

  Color _deriveTintColor(Color seed) {
    var hsl = HSLColor.fromColor(seed);
    hsl = hsl.withSaturation((hsl.saturation * 0.45).clamp(0.08, 0.28));
    hsl = hsl.withLightness((hsl.lightness * 0.45).clamp(0.10, 0.22));
    return hsl.toColor();
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
      return Container(color: context.appColors.surface);
    }

    final currentUrl = urls[index];
    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.of(context);
        final dpr = media.devicePixelRatio.clamp(1.0, 2.2);
        final targetWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : media.size.width;
        final cacheWidth = (targetWidth * dpr).round().clamp(720, 2048);

        return Image.network(
          currentUrl,
          fit: fit,
          alignment: alignment,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          cacheWidth: cacheWidth,
          headers: {'Authorization': token, 'Trim-MC-token': token},
          errorBuilder: (_, error, ___) {
            final nextUrl = index + 1 < urls.length ? urls[index + 1] : null;
            debugPrint(
              nextUrl != null
                  ? '[IMG][DETAIL_BG] failed url=$currentUrl error=$error -> fallback=$nextUrl'
                  : '[IMG][DETAIL_BG] failed url=$currentUrl error=$error -> no_more_fallback',
            );
            WidgetsBinding.instance.addPostFrameCallback((_) => onErrorNext());
            return Container(color: context.appColors.surface);
          },
        );
      },
    );
  }
}
