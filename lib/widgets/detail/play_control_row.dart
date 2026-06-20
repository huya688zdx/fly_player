import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/app_theme.dart';
import '../../theme/detail_tokens.dart';
import '../../ui/adaptive_text.dart';
import '../../ui/app_transitions.dart';
import '../common/liquid_glass.dart';
import 'detail_icon_button.dart';

class PlayControlRow extends StatelessWidget {
  final String primaryText;
  final bool primaryEnabled;
  final bool liked;
  final bool watched;
  final bool downloaded;
  final VoidCallback? onPrimaryTap;
  final VoidCallback? onLikeTap;
  final VoidCallback? onDownloadTap;
  final VoidCallback? onWatchedTap;
  final bool showDownload;

  const PlayControlRow({
    super.key,
    required this.primaryText,
    required this.primaryEnabled,
    required this.liked,
    required this.watched,
    this.downloaded = false,
    this.onPrimaryTap,
    this.onLikeTap,
    this.onDownloadTap,
    this.onWatchedTap,
    this.showDownload = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final primaryForeground = Theme.of(context).colorScheme.onPrimary;
    final playTextSize = AdaptiveText.roleSize(
      DetailTokens.playTextFontSize,
      role: AdaptiveFontRole.button,
    );
    return Row(
      children: [
        Expanded(
          // 保留实心强调色主按钮，仅叠 iOS26 镜面高光，不磨砂。
          child: SizedBox(
            height: DetailTokens.playButtonHeight,
            child: ClipRRect(
              borderRadius: DetailTokens.playButtonBorderRadius,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  FilledButton(
                    onPressed: primaryEnabled ? onPrimaryTap ?? () {} : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(
                        DetailTokens.playButtonHeight,
                      ),
                      backgroundColor: colors.accent,
                      foregroundColor: primaryForeground,
                      disabledBackgroundColor: colors.accent.withValues(
                        alpha: 0.32,
                      ),
                      shape: const RoundedRectangleBorder(
                        borderRadius: DetailTokens.playButtonBorderRadius,
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SvgPicture.asset(
                            'assets/icons/play.svg',
                            width: DetailTokens.playButtonIconSize,
                            height: DetailTokens.playButtonIconSize,
                            colorFilter: ColorFilter.mode(
                              primaryForeground,
                              BlendMode.srcIn,
                            ),
                          ),
                          const SizedBox(width: 10),
                          AppTransitions.crossFadeSwitch(
                            switchKey: 'play-row-primary-$primaryText',
                            duration: AppTransitions.switchDuration,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              primaryText,
                              key: ValueKey<String>(primaryText),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: primaryForeground,
                                fontSize: playTextSize,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const IgnorePointer(
                    child: LiquidGlassSheen(
                      radius: DetailTokens.playButtonRadius,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        DetailIconButton(
          iconAsset: 'assets/icons/heart.svg',
          selected: liked,
          onTap: onLikeTap,
        ),
        if (showDownload) ...[
          const SizedBox(width: 10),
          DetailIconButton(
            iconAsset: 'assets/icons/download.svg',
            selectedIconAsset: 'assets/icons/check.svg',
            selected: downloaded,
            onTap: onDownloadTap,
          ),
        ],
        const SizedBox(width: 10),
        DetailIconButton(
          iconAsset: 'assets/icons/watched.svg',
          selectedIconAsset: 'assets/icons/watched_selected.svg',
          selected: watched,
          onTap: onWatchedTap,
        ),
      ],
    );
  }
}
