import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/detail_tokens.dart';
import '../../ui/adaptive_text.dart';
import 'detail_meta_lines.dart';
import 'detail_selector_row.dart';

class DetailTitleBlock extends StatelessWidget {
  final String title;
  final String subtitle;
  final double? titleFontSize;
  final Widget? titleChild;
  final Color? titleColor;
  final Color? subtitleColor;
  final List<Shadow>? textShadows;

  const DetailTitleBlock({
    super.key,
    required this.title,
    this.subtitle = '',
    this.titleFontSize,
    this.titleChild,
    this.titleColor,
    this.subtitleColor,
    this.textShadows,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final resolvedTitleColor = titleColor ?? colors.textPrimary;
    final resolvedSubtitleColor = subtitleColor ?? colors.textPrimary;
    final titleSize =
        titleFontSize ??
        AdaptiveText.roleSize(
          DetailTokens.titleFontSize,
          role: AdaptiveFontRole.title,
        );
    final hasSubtitle = subtitle.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasSubtitle)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: resolvedSubtitleColor,
                fontSize: 16,
                fontWeight: FontWeight.w500,
                height: 1.25,
                shadows: textShadows,
              ),
            ),
          ),
        if (titleChild != null)
          titleChild!
        else
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.clip,
            style: TextStyle(
              color: resolvedTitleColor,
              fontSize: titleSize,
              fontWeight: FontWeight.w600,
              height: 1.12,
              shadows: textShadows,
            ),
          ),
      ],
    );
  }
}

class DetailMetaBlock extends StatelessWidget {
  final String metaLineA;
  final String metaLineB;
  final String subtitleLabel;
  final String audioLabel;
  final List<String> capabilityLabels;
  final VoidCallback? onSubtitleTap;
  final VoidCallback? onAudioTap;

  const DetailMetaBlock({
    super.key,
    required this.metaLineA,
    required this.metaLineB,
    required this.subtitleLabel,
    required this.audioLabel,
    required this.capabilityLabels,
    this.onSubtitleTap,
    this.onAudioTap,
  });

  @override
  Widget build(BuildContext context) {
    final uiScale = (MediaQuery.textScalerOf(context).scale(12) / 12).clamp(
      0.95,
      1.35,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DetailMetaLines(metaLineA: metaLineA, metaLineB: metaLineB),
        SizedBox(height: (8 * uiScale).clamp(6.0, 12.0)),
        DetailSelectorRow(
          subtitleLabel: subtitleLabel,
          audioLabel: audioLabel,
          capabilityLabels: capabilityLabels,
          onSubtitleTap: onSubtitleTap,
          onAudioTap: onAudioTap,
        ),
      ],
    );
  }
}
