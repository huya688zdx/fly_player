import 'package:flutter/material.dart';

import '../../theme/detail_tokens.dart';
import '../../ui/adaptive_text.dart';
import 'capability_badge.dart';

class DetailSelectorRow extends StatelessWidget {
  final String subtitleLabel;
  final String audioLabel;
  final List<String> capabilityLabels;
  final bool showSubtitleArrow;
  final bool showAudioArrow;
  final bool subtitleExpanded;
  final bool audioExpanded;
  final VoidCallback? onSubtitleTap;
  final VoidCallback? onAudioTap;

  const DetailSelectorRow({
    super.key,
    required this.subtitleLabel,
    required this.audioLabel,
    required this.capabilityLabels,
    this.showSubtitleArrow = true,
    this.showAudioArrow = true,
    this.subtitleExpanded = false,
    this.audioExpanded = false,
    this.onSubtitleTap,
    this.onAudioTap,
  });

  @override
  Widget build(BuildContext context) {
    final uiScale = (MediaQuery.textScalerOf(context).scale(12) / 12).clamp(
      0.95,
      1.35,
    );
    final rowHeight = (22 * uiScale).clamp(20.0, 32.0);
    final selectorGap = (15 * uiScale).clamp(12.0, 18.0);
    final selectorInnerGap = (10 * uiScale).clamp(8.0, 14.0);
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: rowHeight),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _SelectorLabel(
            label: subtitleLabel,
            showArrow: showSubtitleArrow,
            expanded: subtitleExpanded,
            onTap: onSubtitleTap,
          ),
          SizedBox(width: selectorGap),
          _SelectorLabel(
            label: audioLabel,
            showArrow: showAudioArrow,
            expanded: audioExpanded,
            onTap: onAudioTap,
          ),
          SizedBox(width: selectorInnerGap),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: capabilityLabels
                    .map((label) => CapabilityBadge(label: label))
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectorLabel extends StatelessWidget {
  final String label;
  final bool showArrow;
  final bool expanded;
  final VoidCallback? onTap;

  const _SelectorLabel({
    required this.label,
    this.showArrow = true,
    this.expanded = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selectorSize = AdaptiveText.roleSize(
      DetailTokens.selectorFontSize,
      role: AdaptiveFontRole.caption,
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: DetailTokens.selectorText,
              fontSize: selectorSize,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (showArrow) ...[
            const SizedBox(width: 2),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: const Icon(
                Icons.keyboard_arrow_down,
                color: DetailTokens.selectorIcon,
                size: DetailTokens.selectorArrowSize,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
