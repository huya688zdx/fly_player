import 'package:flutter/material.dart';

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
  final bool showMore;

  const DetailFloatingTopBar({
    super.key,
    required this.onBack,
    required this.onMore,
    required this.title,
    required this.titleOpacity,
    this.showMore = true,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final top = media.padding.top + 6;
    final barOverlayHeight = media.padding.top + DetailTokens.topButtonSize + 10;
    return Positioned.fill(
      child: Stack(
        children: [
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
                  child: const DecoratedBox(
                    decoration: BoxDecoration(color: DetailTokens.pageBackground),
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
                        DetailIconButton(
                          iconAsset: 'assets/icons/back.svg',
                          style: DetailIconButtonStyle.top,
                          onTap: onBack,
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
                            style: const TextStyle(
                              color: Colors.white,
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
