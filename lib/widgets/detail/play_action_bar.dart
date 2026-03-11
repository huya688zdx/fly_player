import 'package:flutter/material.dart';

import '../../theme/detail_tokens.dart';
import '../../ui/adaptive_text.dart';
import '../../ui/app_transitions.dart';
import 'play_control_row.dart';

class PlayActionBar extends StatelessWidget {
  final double progress;
  final String remainText;
  final bool showProgress;
  final String primaryText;
  final bool primaryEnabled;
  final bool liked;
  final bool watched;
  final VoidCallback? onPrimaryTap;
  final VoidCallback? onLikeTap;
  final VoidCallback? onDownloadTap;
  final VoidCallback? onWatchedTap;

  const PlayActionBar({
    super.key,
    required this.progress,
    required this.remainText,
    required this.showProgress,
    required this.primaryText,
    required this.primaryEnabled,
    required this.liked,
    required this.watched,
    this.onPrimaryTap,
    this.onLikeTap,
    this.onDownloadTap,
    this.onWatchedTap,
  });

  @override
  Widget build(BuildContext context) {
    final remainSize = AdaptiveText.roleSize(
      DetailTokens.remainFontSize,
      role: AdaptiveFontRole.caption,
    );
    return Column(
      children: [
        AnimatedSize(
          duration: AppTransitions.progressSizeDuration,
          curve: AppTransitions.easeOut,
          child: AnimatedSwitcher(
            duration: AppTransitions.progressFadeDuration,
            switchInCurve: AppTransitions.progressIn,
            switchOutCurve: AppTransitions.progressOut,
            transitionBuilder: AppTransitions.fadeTransitionBuilder,
            child: showProgress
                ? Column(
                    key: const ValueKey('progress-visible'),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                DetailTokens.progressRadius,
                              ),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: DetailTokens.progressHeight,
                                backgroundColor: DetailTokens.progressTrack,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  DetailTokens.progressActive,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            remainText,
                            style: TextStyle(
                              color: DetailTokens.textSecondary,
                              fontSize: remainSize,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  )
                : const SizedBox(key: ValueKey('progress-hidden')),
          ),
        ),
        PlayControlRow(
          primaryText: primaryText,
          primaryEnabled: primaryEnabled,
          liked: liked,
          watched: watched,
          onPrimaryTap: onPrimaryTap,
          onLikeTap: onLikeTap,
          onDownloadTap: onDownloadTap,
          onWatchedTap: onWatchedTap,
        ),
      ],
    );
  }
}
