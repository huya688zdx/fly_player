import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/detail_tokens.dart';
import '../../ui/app_transitions.dart';
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

  const DetailFloatingTopBar({
    super.key,
    required this.onBack,
    required this.onMore,
    required this.title,
    required this.titleOpacity,
    this.showBack = true,
    this.showMore = true,
    this.showBackgroundOverlay = true,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final colors = context.appColors;
    final top = media.padding.top + 6;
    final barOverlayHeight =
        media.padding.top + DetailTokens.topButtonSize + 10;
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
                      decoration: BoxDecoration(color: colors.backgroundBase),
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
