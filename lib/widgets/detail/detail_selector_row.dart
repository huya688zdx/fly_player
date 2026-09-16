import 'package:flutter/material.dart';

import '../../desktop/desktop_environment.dart';
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
  // 两个入口共用同一玻璃外壳，切换时只改变锚点与内容。
  final GlobalKey<DesktopHoverDropdownState> _dropdownKey =
      GlobalKey<DesktopHoverDropdownState>();
  final GlobalKey _subtitleAnchorKey = GlobalKey();
  final GlobalKey _audioAnchorKey = GlobalKey();
  bool _audioActive = false;
  bool _popupOpen = false;

  void _notifyOpenChanged(bool open) {
    _popupOpen = open;
    (_audioActive ? widget.onAudioOpenChanged : widget.onSubtitleOpenChanged)
        ?.call(open);
  }

  void _showPopup(bool audio) {
    if (_audioActive != audio) {
      final wasOpen = _popupOpen;
      if (wasOpen) _notifyOpenChanged(false);
      setState(() => _audioActive = audio);
      // 已打开时 show 不会再次通知，因此将展开态交给新的入口。
      if (wasOpen) _notifyOpenChanged(true);
    }
    _dropdownKey.currentState?.show();
  }

  /// 桌面端选轨由悬停小窗完整承接：点击不再唤起模态 sheet（触屏无 hover，
  /// 保留点按打开 sheet）；触屏/未接弹窗时点按先收起弹窗再走原回调。
  VoidCallback? _triggerTap({
    required DesktopHoverDropdownSpec? spec,
    required VoidCallback? original,
  }) {
    if (original == null) return null;
    if (spec != null && DesktopEnvironment.isDesktopPlatform) {
      return () {};
    }
    return () {
      _dropdownKey.currentState?.hide();
      original();
    };
  }

  Widget _wrapWithHoverPopup({
    required DesktopHoverDropdownSpec? spec,
    required bool audio,
    required Widget label,
  }) {
    if (spec == null || !DesktopEnvironment.isDesktopPlatform) return label;
    return MouseRegion(
      key: audio ? _audioAnchorKey : _subtitleAnchorKey,
      onEnter: (_) => _showPopup(audio),
      onExit: (_) => _dropdownKey.currentState?.hide(delayed: true),
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
    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: rowHeight),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _wrapWithHoverPopup(
            spec: widget.subtitleHoverPopup,
            audio: false,
            label: _SelectorLabel(
              label: widget.subtitleLabel,
              showArrow: widget.showSubtitleArrow,
              expanded: widget.subtitleExpanded,
              onTap: _triggerTap(
                spec: widget.subtitleHoverPopup,
                original: widget.onSubtitleTap,
              ),
            ),
          ),
          SizedBox(width: selectorGap),
          _wrapWithHoverPopup(
            spec: widget.audioHoverPopup,
            audio: true,
            label: _SelectorLabel(
              label: widget.audioLabel,
              showArrow: widget.showAudioArrow,
              expanded: widget.audioExpanded,
              onTap: _triggerTap(
                spec: widget.audioHoverPopup,
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
    if (!DesktopEnvironment.isDesktopPlatform ||
        (widget.subtitleHoverPopup == null && widget.audioHoverPopup == null)) {
      return row;
    }
    return DesktopHoverDropdown(
      key: _dropdownKey,
      anchorKey: _audioActive ? _audioAnchorKey : _subtitleAnchorKey,
      spec: _audioActive ? widget.audioHoverPopup : widget.subtitleHoverPopup,
      onOpenChanged: _notifyOpenChanged,
      child: row,
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
