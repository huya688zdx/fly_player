import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/detail_tokens.dart';
import '../../ui/adaptive_text.dart';
import '../../ui/app_transitions.dart';
import 'detail_icon_button.dart';

class PlayControlRow extends StatelessWidget {
  final String primaryText;
  final bool primaryEnabled;
  final bool liked;
  final bool watched;
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
    this.onPrimaryTap,
    this.onLikeTap,
    this.onDownloadTap,
    this.onWatchedTap,
    this.showDownload = true,
  });

  @override
  Widget build(BuildContext context) {
    final playTextSize = AdaptiveText.roleSize(
      DetailTokens.playTextFontSize,
      role: AdaptiveFontRole.button,
    );
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            onPressed: primaryEnabled ? onPrimaryTap ?? () {} : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(DetailTokens.playButtonHeight),
              backgroundColor: DetailTokens.primaryButton,
              disabledBackgroundColor: DetailTokens.primaryButtonDisabled,
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
                        color: DetailTokens.textPrimary,
                        fontSize: playTextSize,
                        fontWeight: FontWeight.w500,
                      ),
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
            onTap: onDownloadTap,
          ),
        ],
        const SizedBox(width: 10),
        DetailIconButton(
          iconAsset: 'assets/icons/check.svg',
          selected: watched,
          onTap: onWatchedTap,
        ),
      ],
    );
  }
}
