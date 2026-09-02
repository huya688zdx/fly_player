import 'package:flutter/material.dart';

import '../../desktop/desktop_hover_dropdown.dart';
import '../../theme/app_theme.dart';
import '../../theme/detail_tokens.dart';
import '../../ui/adaptive_text.dart';
import 'capability_badge.dart';

class DetailSelectorRow extends StatefulWidget {
  final String subtitleLabel;
  final String audioLabel;
  final List<String> capabilityLabels;
  final bool showSubtitleArrow;
  final bool showAudioArrow;
  final bool subtitleExpanded;
  final bool audioExpanded;
  final VoidCallback? onSubtitleTap;
  final VoidCallback? onAudioTap;

  /// 桌面悬停弹窗内容（非空且有条目时，鼠标悬停触发件弹出小窗直接点选）。
  final DesktopHoverDropdownSpec? subtitleHoverPopup;
  final DesktopHoverDropdownSpec? audioHoverPopup;

  /// 弹窗展开态回调（复用箭头旋转动画）。
  final ValueChanged<bool>? onSubtitleOpenChanged;
  final ValueChanged<bool>? onAudioOpenChanged;

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
    this.subtitleHoverPopup,
    this.audioHoverPopup,
    this.onSubtitleOpenChanged,
    this.onAudioOpenChanged,
  });

  @override
  State<DetailSelectorRow> createState() => _DetailSelectorRowState();
}

class _DetailSelectorRowState extends State<DetailSelectorRow> {
  // GlobalKey 保持悬停弹窗状态跨页面重建稳定；点开模态 sheet 前先经它收起弹窗。
  final GlobalKey<DesktopHoverDropdownState> _subtitleDropdownKey =
      GlobalKey<DesktopHoverDropdownState>();
  final GlobalKey<DesktopHoverDropdownState> _audioDropdownKey =
      GlobalKey<DesktopHoverDropdownState>();

  VoidCallback? _tapWithPopupDismiss({
    required GlobalKey<DesktopHoverDropdownState> dropdownKey,
    required VoidCallback? original,
  }) {
    if (original == null) return null;
    return () {
      dropdownKey.currentState?.hide();
      original();
    };
  }

  Widget _wrapWithHoverPopup({
    required DesktopHoverDropdownSpec? spec,
    required GlobalKey<DesktopHoverDropdownState> dropdownKey,
    required ValueChanged<bool>? onOpenChanged,
    required Widget label,
  }) {
    if (spec == null) return label;
    return DesktopHoverDropdown(
      key: dropdownKey,
      spec: spec,
      onOpenChanged: onOpenChanged,
      child: label,
    );
  }

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
          _wrapWithHoverPopup(
            spec: widget.subtitleHoverPopup,
            dropdownKey: _subtitleDropdownKey,
            onOpenChanged: widget.onSubtitleOpenChanged,
            label: _SelectorLabel(
              label: widget.subtitleLabel,
              showArrow: widget.showSubtitleArrow,
              expanded: widget.subtitleExpanded,
              onTap: _tapWithPopupDismiss(
                dropdownKey: _subtitleDropdownKey,
                original: widget.onSubtitleTap,
              ),
            ),
          ),
          SizedBox(width: selectorGap),
          _wrapWithHoverPopup(
            spec: widget.audioHoverPopup,
            dropdownKey: _audioDropdownKey,
            onOpenChanged: widget.onAudioOpenChanged,
            label: _SelectorLabel(
              label: widget.audioLabel,
              showArrow: widget.showAudioArrow,
              expanded: widget.audioExpanded,
              onTap: _tapWithPopupDismiss(
                dropdownKey: _audioDropdownKey,
                original: widget.onAudioTap,
              ),
            ),
          ),
          SizedBox(width: selectorInnerGap),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: widget.capabilityLabels
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
    final colors = context.appColors;
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
              color: colors.textSecondary,
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
              child: Icon(
                Icons.keyboard_arrow_down,
                color: colors.textMuted,
                size: DetailTokens.selectorArrowSize,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
