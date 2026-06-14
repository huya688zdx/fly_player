import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class ImmersiveDetailBackground extends StatefulWidget {
  final List<String> urls;

  /// 低清占位图候选（通常是取色用的 ~360px 小图，多数已在缓存）。在大图 decode/raster
  /// 完成前先铺底，避免详情进入时 hero 区有 ~90ms 空白单帧（首次大图 raster 尖峰）。
  /// 大图就绪后由其 frameBuilder 淡入覆盖在低清之上。为空则退回原行为。
  final List<String> lowResUrls;
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
    this.lowResUrls = const <String>[],
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

  // Cached image subtrees. Rebuilt only when their inputs (urls/token/index/
  // fit/alignment/gap flags) change — never on scroll. The scroll parallax
  // rebuilds the cheap Transform/Stack layers every frame, but the expensive
  // Image.network + LayoutBuilder subtrees are reused as identical widget
  // instances, which Flutter short-circuits — no per-frame image rebuild.
  String _imageLayersSig = '';
  Widget? _mainImageLayer;
  Widget? _gapImageLayer;
  Widget? _blurImageLayer;
  Widget? _lowResImageLayer;

  void _ensureImageLayers({
    required bool isAndroid,
    required bool enableGapBlur,
  }) {
    final sig = <Object?>[
      widget.urls.join(''),
      widget.token,
      _index,
      widget.imageFit,
      widget.imageAlignment,
      widget.fillGapsWithImage,
      widget.lowResUrls.join(''),
      isAndroid,
      enableGapBlur,
    ].join('|');
    if (sig == _imageLayersSig && _mainImageLayer != null) {
      return;
    }
    _imageLayersSig = sig;
    // 低清铺底层：仅在大图 decode/raster 完成前可见，大图淡入后被其不透明像素覆盖。
    // 取低清候选首选项，立即显示、不淡入（小图解码快，多数已在取色缓存里）。
    final lowResUrl = widget.lowResUrls.isNotEmpty
        ? widget.lowResUrls.first
        : '';
    _lowResImageLayer = (lowResUrl.isNotEmpty && widget.token.trim().isNotEmpty)
        ? _LowResBackgroundImage(
            url: lowResUrl,
            token: widget.token,
            fit: widget.imageFit,
            alignment: widget.imageAlignment,
          )
        : null;
    _mainImageLayer = _BackgroundImage(
      urls: widget.urls,
      token: widget.token,
      index: _index,
      fit: widget.imageFit,
      alignment: widget.imageAlignment,
      onErrorNext: _nextFallbackImage,
    );
    _gapImageLayer = (widget.fillGapsWithImage && isAndroid)
        ? Opacity(
            opacity: 0.38,
            child: _BackgroundImage(
              urls: widget.urls,
              token: widget.token,
              index: _index,
              fit: BoxFit.cover,
              alignment: widget.imageAlignment,
              onErrorNext: _nextFallbackImage,
            ),
          )
        : null;
    _blurImageLayer = enableGapBlur
        ? Opacity(
            opacity: 0.72,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: _BackgroundImage(
                urls: widget.urls,
                token: widget.token,
                index: _index,
                fit: BoxFit.cover,
                alignment: widget.imageAlignment,
                onErrorNext: _nextFallbackImage,
              ),
            ),
          )
        : null;
  }

  @override
  void didUpdateWidget(covariant ImmersiveDetailBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.urls, widget.urls) ||
        oldWidget.token != widget.token) {
      _index = 0;
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
    // tint 来源已统一为调用方（DynamicPageThemeScope）传入的 ambientTintOverride /
    // bottomFadeTintColor；本组件内部不再自取 monet tint（已删）。
    final bottomFadeTint =
        widget.bottomFadeTintColor ??
        widget.ambientTintOverride ??
        (isLightSurface ? colors.backgroundElevated : colors.overlayScrim);
    final bottomFogColor = Color.alphaBlend(
      bottomFadeTint.withValues(alpha: isLightSurface ? 0.42 : 0.56),
      bottomFadeBackground,
    );

    final baseScrimAlpha =
        ((widget.enableBottomFade ? 0.0 : (isLightSurface ? 0.0 : 0.03))) *
        overlayOpacity;

    final heroImageHeight = expandedHeroHeight + parallaxMax + 80;

    _ensureImageLayers(isAndroid: isAndroid, enableGapBlur: enableGapBlur);

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
                          if (_blurImageLayer != null) _blurImageLayer!,
                          if (_gapImageLayer != null) _gapImageLayer!,
                          // 低清铺底，与主图同一 Transform.scale 对齐，垫在主图之下。
                          if (_lowResImageLayer != null)
                            Transform.scale(
                              scale: widget.imageScale * scrollZoom,
                              alignment: widget.imageAlignment,
                              child: _lowResImageLayer,
                            ),
                          Transform.scale(
                            scale: widget.imageScale * scrollZoom,
                            alignment: widget.imageAlignment,
                            child: _mainImageLayer,
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
      return Container(color: context.appColors.surface);
    }

    final currentUrl = urls[index];
    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.of(context);
        final isAndroid =
            !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
        final dpr = media.devicePixelRatio.clamp(1.0, 1.6);
        final targetWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : media.size.width;
        final cacheWidth = (targetWidth * dpr).round().clamp(560, 1440);

        return Image.network(
          currentUrl,
          fit: fit,
          alignment: alignment,
          filterQuality: isAndroid ? FilterQuality.low : FilterQuality.medium,
          gaplessPlayback: true,
          cacheWidth: cacheWidth,
          headers: {'Authorization': token, 'Trim-MC-token': token},
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) {
              return child;
            }
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: child,
            );
          },
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

/// 低清铺底图：在大图就绪前先显示的小图（~360px）。不淡入、立即显示，解码开销极小；
/// 失败则透明（让底色透出）。垫在主图之下，主图淡入后被其不透明像素覆盖。
class _LowResBackgroundImage extends StatelessWidget {
  final String url;
  final String token;
  final BoxFit fit;
  final Alignment alignment;

  const _LowResBackgroundImage({
    required this.url,
    required this.token,
    required this.fit,
    required this.alignment,
  });

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: fit,
      alignment: alignment,
      filterQuality: FilterQuality.low,
      gaplessPlayback: true,
      // 低清只需小尺寸解码，省内存与上传开销。
      cacheWidth: 480,
      headers: {'Authorization': token, 'Trim-MC-token': token},
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
}
