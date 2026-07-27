import 'package:flutter/material.dart';

import '../../media_backend/media_image_request.dart';
import '../../theme/app_theme.dart';
import '../../theme/detail_tokens.dart';
import 'detail_info_block.dart';

class DetailHeroOverlay extends StatelessWidget {
  final double height;
  final String title;
  final String subtitle;
  final double? titleFontSize;
  final double bottomInset;
  final bool useSoftGradient;
  final Widget? titleChild;

  const DetailHeroOverlay({
    super.key,
    required this.height,
    required this.title,
    this.subtitle = '',
    this.titleFontSize,
    this.bottomInset = 36,
    this.useSoftGradient = false,
    this.titleChild,
  });

  @override
  Widget build(BuildContext context) {
    final themeColors = context.appColors;
    final isLightSurface =
        themeColors.backgroundBase.computeLuminance() >= 0.58;
    final colors = useSoftGradient
        ? isLightSurface
              ? [
                  Colors.transparent,
                  themeColors.backgroundBase.withValues(alpha: 0.05),
                  themeColors.backgroundBase.withValues(alpha: 0.12),
                  themeColors.backgroundBase.withValues(alpha: 0.26),
                  themeColors.backgroundBase.withValues(alpha: 0.62),
                  themeColors.backgroundBase,
                ]
              : [
                  Colors.transparent,
                  themeColors.overlayScrim.withValues(alpha: 0.08),
                  themeColors.overlayScrim.withValues(alpha: 0.14),
                  themeColors.overlayScrim.withValues(alpha: 0.28),
                  themeColors.overlayScrim.withValues(alpha: 0.52),
                  themeColors.backgroundBase,
                ]
        : isLightSurface
        ? [
            Colors.transparent,
            themeColors.backgroundBase.withValues(alpha: 0.08),
            themeColors.backgroundBase.withValues(alpha: 0.20),
            themeColors.backgroundBase.withValues(alpha: 0.40),
            themeColors.backgroundBase.withValues(alpha: 0.76),
            themeColors.backgroundBase,
          ]
        : [
            Colors.transparent,
            themeColors.overlayScrim.withValues(alpha: 0.20),
            themeColors.overlayScrim.withValues(alpha: 0.46),
            themeColors.overlayScrim.withValues(alpha: 0.58),
            themeColors.overlayScrim.withValues(alpha: 0.66),
            themeColors.backgroundBase,
          ];
    final onImageShadows = <Shadow>[
      Shadow(
        color: Colors.black.withValues(alpha: 0.30),
        blurRadius: 18,
        offset: const Offset(0, 3),
      ),
    ];
    final stops = useSoftGradient
        ? const [0.0, 0.46, 0.68, 0.82, 0.92, 1.0]
        : const [0.0, 0.50, 0.74, 0.86, 0.92, 1.0];

    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            left: 0,
            right: 0,
            top: 0,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: colors,
                    stops: stops,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: DetailTokens.screenHorizontalPadding,
            right: DetailTokens.screenHorizontalPadding,
            bottom: bottomInset,
            child: DetailTitleBlock(
              title: title,
              subtitle: subtitle,
              titleFontSize: titleFontSize,
              titleChild: titleChild,
              titleColor: Colors.white,
              subtitleColor: Colors.white.withValues(alpha: 0.92),
              textShadows: onImageShadows,
            ),
          ),
        ],
      ),
    );
  }
}

class DetailHeroLogoTitle extends StatefulWidget {
  final MediaImageRequest images;
  final String fallbackTitle;
  final double maxHeight;
  final double maxWidth;
  final double? fallbackFontSize;

  const DetailHeroLogoTitle({
    super.key,
    required this.images,
    required this.fallbackTitle,
    required this.maxHeight,
    required this.maxWidth,
    this.fallbackFontSize,
  });

  @override
  State<DetailHeroLogoTitle> createState() => _DetailHeroLogoTitleState();
}

class _DetailHeroLogoTitleState extends State<DetailHeroLogoTitle> {
  int _index = 0;

  @override
  void didUpdateWidget(covariant DetailHeroLogoTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.images.urls != widget.images.urls ||
        oldWidget.images.headers != widget.images.headers) {
      _index = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.images.urls;
    final hasUrl = _index < urls.length;
    // 无候选或无鉴权(既无 header 也非自鉴权直链)时回退标题文本,
    // 判定语义由 MediaImageRequest.canLoad 统一承载。
    if (!hasUrl || !widget.images.canLoad) {
      return _fallbackTitle(context);
    }

    final url = urls[_index];
    // logo 宽度受屏宽约束(数值很大且非真实尺寸),高度才是有效约束;
    // 只按 maxHeight 换算 cacheHeight,宽度交给解码器按原始比例自适应,
    // 避免宽高都传导致非等比拉伸。
    final dpr = MediaQuery.of(context).devicePixelRatio.clamp(1.0, 1.8);
    final cacheHeight = (widget.maxHeight * dpr).round();
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: widget.maxWidth,
        maxHeight: widget.maxHeight,
      ),
      child: Image.network(
        url,
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        filterQuality: FilterQuality.medium,
        cacheHeight: cacheHeight,
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
        errorBuilder: (context, error, stackTrace) {
          if (_index + 1 < widget.images.urls.length) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _index += 1;
                });
              }
            });
          }
          return _fallbackTitle(context);
        },
      ),
    );
  }

  Widget _fallbackTitle(BuildContext context) {
    return Text(
      widget.fallbackTitle,
      maxLines: 2,
      overflow: TextOverflow.clip,
      style: TextStyle(
        color: Colors.white,
        fontSize: widget.fallbackFontSize ?? DetailTokens.titleFontSize,
        fontWeight: FontWeight.w600,
        height: 1.12,
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 18,
            offset: const Offset(0, 3),
          ),
        ],
      ),
    );
  }
}
