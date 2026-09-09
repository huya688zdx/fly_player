import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/detail_tokens.dart';
import '../../ui/app_transitions.dart';
import '../app_atmospheric_background.dart';
import 'detail_icon_button.dart';

// Immersive header spacer only: no pinned app bar, no title transfer.
class DetailHeader extends StatelessWidget {
  const DetailHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return const SliverToBoxAdapter(
      child: SizedBox(height: DetailTokens.headerExpandedHeight),
    );
  }
}

class DetailFloatingTopBar extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onMore;
  final String title;
  final double titleOpacity;
  final bool showBack;
  final bool showMore;
  final bool showBackgroundOverlay;

  /// 页面取色晕染色（媒体详情页 DynamicPageThemeScope 给出的 ambientTint）。
  /// 非空时下滑顶栏的遮罩底色混入同色调，避免顶栏与页面的取色晕染脱节。
  final Color? ambientTint;

  /// 页面背景走 AppAtmosphericBackground 氛围系统（人物详情页）时置 true：
  /// 遮罩改用氛围底色（动态取色时含取色混入），否则平铺 backgroundBase。
  final bool atmosphereOverlay;

  const DetailFloatingTopBar({
    super.key,
    required this.onBack,
    required this.onMore,
    required this.title,
    required this.titleOpacity,
    this.showBack = true,
    this.showMore = true,
    this.showBackgroundOverlay = true,
    this.ambientTint,
    this.atmosphereOverlay = false,
  });

  /// 遮罩底色：跟随页面的取色晕染系统，让下滑出现的顶栏与页面底色同源。
  Color _overlayColor(BuildContext context) {
    final colors = context.appColors;
    final tint = ambientTint;
    if (tint != null) {
      final isLight = colors.backgroundBase.computeLuminance() >= 0.58;
      return Color.alphaBlend(
        tint.withValues(alpha: isLight ? 0.12 : 0.18),
        colors.backgroundBase,
      );
    }
    if (atmosphereOverlay) {
      final snapshot = DynamicPageThemeSnapshot.maybeOf(context);
      return AppAtmospherePalette.resolve(
        baseColors: context.baseAppColors,
        effectiveColors: colors,
        hasDynamicTheme:
            (snapshot?.hasDynamicTheme ?? false) || context.hasRuntimeAppColors,
      ).base;
    }
    return colors.backgroundBase;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final top = media.padding.top + 6;
    final barOverlayHeight =
        media.padding.top + DetailTokens.topButtonSize + 10;
    final overlayColor = _overlayColor(context);
    return Positioned.fill(
      child: Stack(
        children: [
          if (showBackgroundOverlay)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  duration: AppTransitions.topBarFadeDuration,
                  opacity: titleOpacity.clamp(0.0, 1.0),
                  child: SizedBox(
                    height: barOverlayHeight,
                    child: DecoratedBox(
                      // 纵向渐隐到透明：遮罩下方与页面内容/晕染自然衔接，
                      // 不再是一条平色硬边横带；标题区仍保持足够遮蔽。
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            overlayColor,
                            overlayColor.withValues(alpha: 0.86),
                            overlayColor.withValues(alpha: 0),
                          ],
                          stops: const <double>[0.0, 0.52, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            top: top,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                height: DetailTokens.topButtonSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        showBack
                            ? DetailIconButton(
                                iconAsset: 'assets/icons/back.svg',
                                style: DetailIconButtonStyle.top,
                                onTap: onBack,
                              )
                            : const SizedBox(
                                width: DetailTokens.topButtonSize,
                                height: DetailTokens.topButtonSize,
                              ),
                        showMore
                            ? DetailIconButton(
                                iconAsset: 'assets/icons/more.svg',
                                style: DetailIconButtonStyle.top,
                                onTap: onMore,
                              )
                            : const SizedBox(
                                width: DetailTokens.topButtonSize,
                                height: DetailTokens.topButtonSize,
                              ),
                      ],
                    ),
                    IgnorePointer(
                      child: AnimatedOpacity(
                        duration: AppTransitions.topBarFadeDuration,
                        opacity: titleOpacity.clamp(0.0, 1.0),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 72),
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: context.appColors.textPrimary,
                              fontSize: 34 / 2,
                              fontWeight: FontWeight.w600,
                              height: 1.1,
                            ),
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
}
