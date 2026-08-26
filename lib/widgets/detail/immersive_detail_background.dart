import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../media_backend/media_image_request.dart';
import '../../theme/app_theme.dart';
import '../../ui/route_transition_gate.dart';

class ImmersiveDetailBackground extends StatefulWidget {
  final MediaImageRequest images;

  /// 低清占位图候选（通常是取色用的 ~360px 小图，多数已在缓存）。在大图 decode/raster
  /// 完成前先铺底，避免详情进入时 hero 区有 ~90ms 空白单帧（首次大图 raster 尖峰）。
  /// 大图就绪后由其 frameBuilder 淡入覆盖在低清之上。为空则退回原行为。
  /// 注意封面同源垫底规则：垫底图必须与主图同源，调用方宁可传空。
  final MediaImageRequest lowResImages;
  final double scrollOffset;
  final double posterHeight;

  final double imageScale;
  final BoxFit imageFit;
  final Alignment imageAlignment;

  final bool fillGapsWithImage;
  final Color? ambientTintOverride;
  final Color? transitionTintColor;
  final Color? transitionBodyColor;

  final double parallaxFactor;
  final double overlayOpacity;
  final double maxScrollZoom;

  const ImmersiveDetailBackground({
    super.key,
    required this.images,
    this.lowResImages = MediaImageRequest.empty,
    required this.scrollOffset,
    required this.posterHeight,
    this.imageScale = 1.0,
    this.imageFit = BoxFit.cover,
    this.imageAlignment = Alignment.topCenter,
    this.fillGapsWithImage = false,
    this.ambientTintOverride,
    this.transitionTintColor,
    this.transitionBodyColor,
    this.parallaxFactor = 0.40,
    this.overlayOpacity = 1.0,
    this.maxScrollZoom = 1.24,
  });

  @override
  State<ImmersiveDetailBackground> createState() =>
      _ImmersiveDetailBackgroundState();
}

class _ImmersiveDetailBackgroundState extends State<ImmersiveDetailBackground> {
  int _index = 0;

  // 主图首帧就绪后延时卸载低清铺底层：低清层只在大图 decode 前有用，之后
  // 永久留树会让 hero 区每帧多合成一张全幅位图。延时要盖过主图 180ms 淡入，
  // 避免淡入中途抽掉底图露出底色。
  bool _mainImageReady = false;
  Timer? _lowResUnloadTimer;

  // Cached image subtrees. Rebuilt only when their inputs (urls/token/index/
  // fit/alignment/gap flags) change — never on scroll. The scroll parallax
  // rebuilds the cheap Transform/Stack layers every frame, but the expensive
  // Image.network + LayoutBuilder subtrees are reused as identical widget
  // instances, which Flutter short-circuits — no per-frame image rebuild.
  String _imageLayersSig = '';
  Widget? _mainImageLayer;
  Widget? _gapImageLayer;
  Widget? _lowResImageLayer;

  void _ensureImageLayers({required bool isAndroid}) {
    final sig = <Object?>[
      widget.images.urls.join(''),
      widget.images.headers.values.join(''),
      _index,
      widget.imageFit,
      widget.imageAlignment,
      widget.fillGapsWithImage,
      widget.lowResImages.urls.join(''),
      isAndroid,
    ].join('|');
    if (sig == _imageLayersSig && _mainImageLayer != null) {
      return;
    }
    _imageLayersSig = sig;
    // 低清铺底层：仅在大图 decode/raster 完成前可见，大图淡入后被其不透明像素覆盖。
    // 取低清候选首选项，立即显示、不淡入（小图解码快，多数已在取色缓存里）。
    // 与 _BackgroundImage 同款鉴权判定：MediaImageRequest.canLoad 统一承载。
    _lowResImageLayer = widget.lowResImages.canLoad
        ? _LowResBackgroundImage(
            url: widget.lowResImages.urls.first,
            headers: widget.lowResImages.headers,
            fit: widget.imageFit,
            alignment: widget.imageAlignment,
          )
        : null;
    _mainImageLayer = _BackgroundImage(
      images: widget.images,
      index: _index,
      fit: widget.imageFit,
      alignment: widget.imageAlignment,
      onErrorNext: _nextFallbackImage,
      onFirstFrame: _handleMainImageFirstFrame,
    );
    _gapImageLayer = (widget.fillGapsWithImage && isAndroid)
        ? Opacity(
            opacity: 0.38,
            child: _BackgroundImage(
              images: widget.images,
              index: _index,
              fit: BoxFit.cover,
              alignment: widget.imageAlignment,
              onErrorNext: _nextFallbackImage,
            ),
          )
        : null;
  }

  @override
  void didUpdateWidget(covariant ImmersiveDetailBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.images.urls, widget.images.urls) ||
        !mapEquals(oldWidget.images.headers, widget.images.headers)) {
      _index = 0;
      _resetMainImageReady();
    }
  }

  @override
  void dispose() {
    _lowResUnloadTimer?.cancel();
    super.dispose();
  }

  void _resetMainImageReady() {
    _lowResUnloadTimer?.cancel();
    _lowResUnloadTimer = null;
    _mainImageReady = false;
  }

  // 主图首帧回调来自 frameBuilder（build 期间），不能直接 setState；起一次性
  // 延时（260ms > 180ms 淡入）后再卸低清层。已就绪/已排程则幂等跳过。
  void _handleMainImageFirstFrame() {
    if (_mainImageReady || _lowResUnloadTimer != null || !mounted) {
      return;
    }
    if (_lowResImageLayer == null) {
      _mainImageReady = true;
      return;
    }
    _lowResUnloadTimer = Timer(const Duration(milliseconds: 260), () {
      _lowResUnloadTimer = null;
      if (!mounted) {
        return;
      }
      setState(() => _mainImageReady = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final colors = context.appColors;
    final isLightSurface = colors.backgroundBase.computeLuminance() >= 0.58;
    final ambientTint = widget.ambientTintOverride;

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

    final zoomT = Curves.easeOutCubic.transform(
      (topOverscroll / 160).clamp(0.0, 1.0),
    );
    final scrollZoom =
        1.0 + ((widget.maxScrollZoom.clamp(1.0, 1.3) - 1.0) * zoomT);

    final overlayOpacity = widget.overlayOpacity.clamp(0.0, 1.0);
    final transitionBody = widget.transitionBodyColor ?? colors.backgroundBase;
    final transitionTint =
        widget.transitionTintColor ??
        ambientTint ??
        (isLightSurface ? colors.backgroundElevated : colors.overlayScrim);
    final transitionSurface = Color.alphaBlend(
      transitionTint.withValues(alpha: isLightSurface ? 0.08 : 0.12),
      transitionBody,
    );
    // 交接层必须是海报裁切区域的一部分，不能作为兄弟层延伸到正文；
    // 这样滚动时烟雾遮罩始终附着在图片上，正文只承接稳定的取色底面。
    final minimumImageBlend = heroHeight < 168.0 ? heroHeight : 168.0;
    final transitionImageBlend = (heroHeight * 0.42)
        .clamp(minimumImageBlend, 252.0)
        .toDouble();
    final transitionTop = (expandedHeroHeight - transitionImageBlend)
        .clamp(0.0, double.infinity)
        .toDouble();
    final baseScrimAlpha = (isLightSurface ? 0.0 : 0.03) * overlayOpacity;

    final heroImageHeight = expandedHeroHeight + parallaxMax + 80;

    _ensureImageLayers(isAndroid: isAndroid);

    return RepaintBoundary(
      child: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: colors.backgroundBase)),
          if (ambientTint != null)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const ValueKey<String>('detail-background-ambient-wash'),
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(-0.35, -0.72),
                      radius: 1.52,
                      colors: <Color>[
                        ambientTint.withValues(
                          alpha: isLightSurface ? 0.14 : 0.22,
                        ),
                        ambientTint.withValues(
                          alpha: isLightSurface ? 0.07 : 0.11,
                        ),
                        // 页面下半部仍保留微弱色相，避免正文退回固定深蓝底；
                        // 强度足够辨认取色差异，同时不影响正文对比度。
                        ambientTint.withValues(
                          alpha: isLightSurface ? 0.025 : 0.045,
                        ),
                      ],
                      stops: const <double>[0, 0.54, 1],
                    ),
                  ),
                ),
              ),
            ),

          Positioned(
            key: const ValueKey<String>('detail-hero-image-region'),
            top: 0,
            left: 0,
            right: 0,
            height: expandedHeroHeight,
            child: Transform.translate(
              key: const ValueKey<String>('detail-hero-region-scroll-follow'),
              offset: Offset(0, -collapseOffset),
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Transform.translate(
                      key: const ValueKey<String>('detail-hero-image-parallax'),
                      offset: Offset(0, collapseOffset - parallaxShift),
                      child: SizedBox(
                        width: screenWidth,
                        height: heroImageHeight,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (_gapImageLayer != null) _gapImageLayer!,
                            // 低清铺底，与主图同一 Transform.scale 对齐，垫在主图之下；
                            // 主图就绪（淡入完成）后卸载，不再参与每帧合成。
                            if (_lowResImageLayer != null && !_mainImageReady)
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
                    Positioned(
                      key: const ValueKey<String>('detail-hero-transition'),
                      left: 0,
                      right: 0,
                      top: transitionTop,
                      height: transitionImageBlend,
                      child: RepaintBoundary(
                        child: IgnorePointer(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              DecoratedBox(
                                key: const ValueKey<String>(
                                  'detail-hero-transition-veil',
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: <Color>[
                                      Colors.transparent,
                                      transitionTint.withValues(
                                        alpha: isLightSurface ? 0.025 : 0.04,
                                      ),
                                      transitionTint.withValues(
                                        alpha: isLightSurface ? 0.07 : 0.10,
                                      ),
                                    ],
                                    stops: const <double>[0.0, 0.58, 1.0],
                                  ),
                                ),
                              ),
                              DecoratedBox(
                                key: const ValueKey<String>(
                                  'detail-hero-transition-gradient',
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: <Color>[
                                      Colors.transparent,
                                      colors.overlayScrim.withValues(
                                        alpha: isLightSurface ? 0.03 : 0.08,
                                      ),
                                      transitionSurface.withValues(
                                        alpha: isLightSurface ? 0.16 : 0.22,
                                      ),
                                      transitionSurface.withValues(
                                        alpha: isLightSurface ? 0.52 : 0.62,
                                      ),
                                      transitionSurface,
                                    ],
                                    stops: const <double>[
                                      0.0,
                                      0.28,
                                      0.56,
                                      0.82,
                                      1.0,
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _nextFallbackImage(int failedIndex) {
    if (!mounted || _index + 1 >= widget.images.urls.length) {
      return;
    }
    if (failedIndex != _index) return;
    setState(() {
      _index += 1;
      // 主图换成兜底候选，重新等它的首帧，低清层先回树垫底。
      _resetMainImageReady();
    });
  }
}

class _BackgroundImage extends StatelessWidget {
  final MediaImageRequest images;
  final int index;
  final BoxFit fit;
  final Alignment alignment;
  final ValueChanged<int> onErrorNext;

  /// 首帧就绪（含同步缓存命中）时回调。在 frameBuilder（build 期间）触发，
  /// 接收方不得直接 setState。仅主图层挂接（低清卸载时机）。
  final VoidCallback? onFirstFrame;

  const _BackgroundImage({
    required this.images,
    required this.index,
    required this.fit,
    required this.alignment,
    required this.onErrorNext,
    this.onFirstFrame,
  });

  @override
  Widget build(BuildContext context) {
    final urls = images.urls;
    final hasUrl = index < urls.length;
    final currentUrl = hasUrl ? urls[index] : '';
    // 无候选或无鉴权（既无 header 也非自鉴权直链）时回退底色，
    // 判定语义由 MediaImageRequest.canLoad 统一承载。
    if (!hasUrl || !images.canLoad) {
      return Container(color: context.appColors.surface);
    }
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
          headers: images.headers,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) {
              onFirstFrame?.call();
            }
            if (wasSynchronouslyLoaded) {
              return child;
            }
            // 路由转场进行中跳过 180ms 淡入直接呈现：转场自身已把整页包在
            // FadeTransition 里，再嵌一层分数透明度会在 hero 区域（最高 78%
            // 屏高、低清+大图两张位图）上叠加离屏合成，恰逢大图首帧纹理
            // 上传，正是 push 尾段丢帧点。
            if (RouteTransitionGate.isTransitioning(context)) {
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
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => onErrorNext(index),
            );
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
  final Map<String, String> headers;
  final BoxFit fit;
  final Alignment alignment;

  const _LowResBackgroundImage({
    required this.url,
    required this.headers,
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
      headers: headers,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
}
