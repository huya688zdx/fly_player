import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../providers/parallel_window_settings_provider.dart';
import '../theme/app_theme.dart';
import '../ui/adaptive_text.dart';
import '../ui/secondary_host_navigation.dart';
import '../widgets/common/app_ambient_page.dart';

/// 平行窗口设置：状态头卡（启用开关 + 摘要）→ 实时分屏预览 →
/// 主屏位置 / 播放主屏位置 / 分屏比例分段控件 → 播放行为开关行。
/// 桌面与手机共用同一组件树，窄视口分段纵向堆叠、预览压缩。
/// 颜色全部取自 [context.appColors]，跟随主题预设与动态取色。
class ParallelWindowSettingsScreen extends StatelessWidget {
  const ParallelWindowSettingsScreen({super.key});

  static const Map<String, int> _ratioLeft = <String, int>{
    'balanced': 42,
    'equal': 50,
    'focus_detail': 35,
    'focus_home': 45,
  };
  static const Map<String, int> _ratioRight = <String, int>{
    'balanced': 58,
    'equal': 50,
    'focus_detail': 65,
    'focus_home': 55,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final settings = context.watch<ParallelWindowSettingsProvider>();
    final l10n = AppLocalizations.of(context);
    final compact = MediaQuery.sizeOf(context).width < 720;
    final enabled = settings.enabled && settings.isReady;

    // 比例按主屏方向镜像：42/58 = 主屏 42 / 副屏 58，主屏在右时左右对调。
    final left = _ratioLeft[settings.splitRatioPreset] ?? 42;
    final right = _ratioRight[settings.splitRatioPreset] ?? 58;
    final mainIsLeft = settings.preferredPrimaryPaneSide != 'right';
    final mainPct = mainIsLeft ? left : right;
    final otherPct = mainIsLeft ? right : left;
    final playbackSideIsLeft =
        settings.preferredPlaybackPrimaryPaneSide != 'right';
    final playbackIsMain = playbackSideIsLeft == mainIsLeft;

    final summary = settings.enabled
        ? (settings.primaryOnLeft
              ? l10n.settingsParallelSummaryEnabledLeft
              : l10n.settingsParallelSummaryEnabledRight)
        : l10n.settingsParallelSummaryDisabled;

    Widget lockable(Widget child) => AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.45,
      child: AbsorbPointer(absorbing: !enabled, child: child),
    );

    // 页面自绘与首页同源的氛围底（整面覆盖，防转场残影）。
    return AppAmbientPage(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: buildSecondaryHostAppBar(
          context,
          title: Text(
            l10n.parallelWindowTitle,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: AdaptiveText.roleSize(17, role: AdaptiveFontRole.title),
              fontWeight: FontWeight.w700,
            ),
          ),
          actions: <Widget>[
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: _StatusPill(text: summary, enabled: enabled),
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              compact ? 14 : 24,
              12,
              compact ? 14 : 24,
              28,
            ),
            children: <Widget>[
              _SettingsCard(
                children: <Widget>[
                  _SwitchRow(
                    title: l10n.parallelWindowEnableTitle,
                    subtitle: l10n.parallelWindowEnableSubtitle,
                    value: settings.enabled,
                    onChanged: settings.isReady
                        ? (value) => settings.setEnabled(value)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _PreviewCard(
                enabled: enabled,
                mainIsLeft: mainIsLeft,
                mainPct: mainPct,
                otherPct: otherPct,
                playbackOnMain: playbackIsMain,
                playbackSideIsLeft:
                    settings.preferredPlaybackPrimaryPaneSide != 'right',
                compact: compact,
                disabledText: l10n.settingsParallelSummaryDisabled,
              ),
              lockable(
                Column(
                  children: <Widget>[
                    const SizedBox(height: 14),
                    _SegmentCard(
                      icon: Icons.dashboard_outlined,
                      title: l10n.parallelWindowPrimarySideTitle,
                      children: <Widget>[
                        _buildSideSegment(
                          context,
                          kind: _SideSegmentKind.primary,
                          side: 'left',
                          selected:
                              settings.preferredPrimaryPaneSide != 'right',
                          enabled: settings.isReady,
                        ),
                        _buildSideSegment(
                          context,
                          kind: _SideSegmentKind.primary,
                          side: 'right',
                          selected:
                              settings.preferredPrimaryPaneSide == 'right',
                          enabled: settings.isReady,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _SegmentCard(
                      icon: Icons.play_circle_outline_rounded,
                      title: l10n.parallelWindowPlaybackSideTitle,
                      children: <Widget>[
                        _buildSideSegment(
                          context,
                          kind: _SideSegmentKind.playback,
                          side: 'left',
                          selected:
                              settings.preferredPlaybackPrimaryPaneSide !=
                              'right',
                          enabled: settings.isReady,
                        ),
                        _buildSideSegment(
                          context,
                          kind: _SideSegmentKind.playback,
                          side: 'right',
                          selected:
                              settings.preferredPlaybackPrimaryPaneSide ==
                              'right',
                          enabled: settings.isReady,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _SegmentCard(
                      icon: Icons.vertical_split_rounded,
                      title: l10n.parallelWindowSplitRatioTitle,
                      children: <Widget>[
                        for (final preset in const <String>[
                          'balanced',
                          'equal',
                          'focus_detail',
                          'focus_home',
                        ])
                          _buildRatioSegment(
                            context,
                            preset: preset,
                            selected: settings.splitRatioPreset == preset,
                            enabled: settings.isReady,
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _SettingsCard(
                      children: <Widget>[
                        _SwitchRow(
                          title: l10n.parallelWindowDefaultFullscreenTitle,
                          subtitle: settings.defaultPlaybackFullscreen
                              ? l10n.parallelWindowDefaultFullscreenOnSubtitle
                              : l10n.parallelWindowDefaultFullscreenOffSubtitle,
                          value: settings.defaultPlaybackFullscreen,
                          onChanged: settings.isReady
                              ? (value) =>
                                    settings.setDefaultPlaybackFullscreen(value)
                              : null,
                        ),
                        const _CardDivider(),
                        _SwitchRow(
                          title: l10n.parallelWindowImmersiveTitle,
                          subtitle: settings.immersiveStatusBar
                              ? l10n.parallelWindowImmersiveOnSubtitle
                              : l10n.parallelWindowImmersiveOffSubtitle,
                          value: settings.immersiveStatusBar,
                          onChanged: settings.isReady
                              ? (value) => settings.setImmersiveStatusBar(value)
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSideSegment(
    BuildContext context, {
    required _SideSegmentKind kind,
    required String side,
    required bool selected,
    required bool enabled,
  }) {
    final l10n = AppLocalizations.of(context);
    final bool isLeft = side == 'left';
    // 迷你示意：主屏侧着色并占所选比例宽度，播放类示意叠加播放三角。
    final int mainShare = kind == _SideSegmentKind.primary
        ? (isLeft ? _ratioLeft['balanced']! : _ratioRight['balanced']!)
        : (isLeft ? _ratioRight['balanced']! : _ratioLeft['balanced']!);
    final String title;
    final String subtitle;
    if (kind == _SideSegmentKind.primary) {
      title = isLeft
          ? l10n.parallelWindowPrimaryLeftTitle
          : l10n.parallelWindowPrimaryRightTitle;
      subtitle = isLeft
          ? l10n.parallelWindowPrimaryLeftSubtitle
          : l10n.parallelWindowPrimaryRightSubtitle;
    } else {
      title = isLeft
          ? l10n.parallelWindowPlaybackLeftTitle
          : l10n.parallelWindowPlaybackRightTitle;
      subtitle = isLeft
          ? l10n.parallelWindowPlaybackLeftSubtitle
          : l10n.parallelWindowPlaybackRightSubtitle;
    }
    return _SegmentItem(
      selected: selected,
      enabled: enabled,
      onTap: () {
        if (kind == _SideSegmentKind.primary) {
          context
              .read<ParallelWindowSettingsProvider>()
              .setPreferredPrimaryPaneSide(side);
        } else {
          context
              .read<ParallelWindowSettingsProvider>()
              .setPreferredPlaybackPrimaryPaneSide(side);
        }
      },
      leading: _MiniSplitGlyph(
        mainShare: mainShare,
        highlightedSide: isLeft ? 'left' : 'right',
        showPlay: kind == _SideSegmentKind.playback,
        playOnLeft: isLeft,
        selected: selected,
      ),
      title: title,
      subtitle: subtitle,
    );
  }

  Widget _buildRatioSegment(
    BuildContext context, {
    required String preset,
    required bool selected,
    required bool enabled,
  }) {
    final l10n = AppLocalizations.of(context);
    final left = _ratioLeft[preset] ?? 42;
    final right = _ratioRight[preset] ?? 58;
    final String subtitle;
    switch (preset) {
      case 'equal':
        subtitle = l10n.parallelWindowSplitEqualSubtitle;
      case 'focus_detail':
        subtitle = l10n.parallelWindowSplitFocusDetailSubtitle;
      case 'focus_home':
        subtitle = l10n.parallelWindowSplitFocusHomeSubtitle;
      default:
        subtitle = l10n.parallelWindowSplitBalancedSubtitle;
    }
    return _SegmentItem(
      selected: selected,
      enabled: enabled,
      dense: true,
      onTap: () => context
          .read<ParallelWindowSettingsProvider>()
          .setSplitRatioPreset(preset),
      leading: _MiniSplitGlyph(
        mainShare: left,
        highlightedSide: 'left',
        selected: selected,
      ),
      title: '$left / $right',
      subtitle: subtitle,
      monospaceTitle: true,
    );
  }
}

enum _SideSegmentKind { primary, playback }

/// 设置卡：surface 底 + 发丝边框，纵向排布内容行。
class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(children: children),
    );
  }
}

/// 分段控件卡：图标 + 标题的组头，选项横向铺开（窄视口纵向堆叠）。
class _SegmentCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _SegmentCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final compact = MediaQuery.sizeOf(context).width < 720;
    return _SettingsCard(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: <Widget>[
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: colors.selectionSoft,
                  borderRadius: BorderRadius.circular(7),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 13, color: colors.selection),
              ),
              const SizedBox(width: 9),
              Text(
                title,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: AdaptiveText.roleSize(13),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
        compact
            ? Column(
                children: <Widget>[
                  for (var i = 0; i < children.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(height: 8),
                    children[i],
                  ],
                ],
              )
            : IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (var i = 0; i < children.length; i++) ...<Widget>[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(child: children[i]),
                    ],
                  ],
                ),
              ),
      ],
    );
  }
}

/// 分段选项：迷你分屏示意 + 标题 + 描述；选中 accent 微底 + 高亮边。
class _SegmentItem extends StatelessWidget {
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final Widget leading;
  final String title;
  final String subtitle;
  final bool dense;
  final bool monospaceTitle;

  const _SegmentItem({
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.leading,
    required this.title,
    required this.subtitle,
    this.dense = false,
    this.monospaceTitle = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.symmetric(
          horizontal: 13,
          vertical: dense ? 10 : 12,
        ),
        decoration: BoxDecoration(
          color: selected ? colors.accentSoft : colors.surfaceSubtle,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected
                ? colors.accent.withValues(alpha: 0.5)
                : colors.borderSubtle,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                leading,
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? colors.accentStrong
                          : colors.textPrimary,
                      fontSize: AdaptiveText.roleSize(13.5),
                      fontWeight: FontWeight.w700,
                      fontFamily: monospaceTitle ? 'monospace' : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              style: TextStyle(
                color: selected ? colors.textPrimary : colors.textSecondary,
                fontSize: AdaptiveText.roleSize(11.5),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 迷你分屏示意：两段比例条，主屏侧按 [mainShare] 着色；
/// [showPlay] 时在着色侧叠加播放三角。
class _MiniSplitGlyph extends StatelessWidget {
  final int mainShare;
  final String highlightedSide;
  final bool showPlay;
  final bool playOnLeft;
  final bool selected;

  const _MiniSplitGlyph({
    required this.mainShare,
    required this.highlightedSide,
    required this.selected,
    this.showPlay = false,
    this.playOnLeft = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final fill = selected
        ? colors.accent.withValues(alpha: 0.85)
        : colors.textMuted.withValues(alpha: 0.35);
    final empty = colors.textMuted.withValues(alpha: 0.12);
    Widget side({
      required int flex,
      required Color color,
      required bool play,
    }) => Expanded(
      flex: flex,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          ColoredBox(color: color, child: const SizedBox.expand()),
          if (play)
            Icon(Icons.play_arrow_rounded, size: 11, color: colors.textPrimary),
        ],
      ),
    );
    final leftShare = highlightedSide == 'left' ? mainShare : 100 - mainShare;
    final rightShare = 100 - leftShare;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 30,
        height: 18,
        child: Row(
          children: <Widget>[
            side(
              flex: leftShare,
              color: highlightedSide == 'left' ? fill : empty,
              play: showPlay && playOnLeft,
            ),
            Container(width: 1, color: colors.borderSubtle),
            side(
              flex: rightShare,
              color: highlightedSide == 'right' ? fill : empty,
              play: showPlay && !playOnLeft,
            ),
          ],
        ),
      ),
    );
  }
}

/// 实时分屏预览：两块按当前比例变形的窗格，主屏 accent 着色，
/// 播放侧显示播放图标；关闭状态盖「单屏模式」水印。
class _PreviewCard extends StatelessWidget {
  final bool enabled;
  final bool mainIsLeft;
  final int mainPct;
  final int otherPct;
  final bool playbackOnMain;
  final bool playbackSideIsLeft;
  final bool compact;
  final String disabledText;

  const _PreviewCard({
    required this.enabled,
    required this.mainIsLeft,
    required this.mainPct,
    required this.otherPct,
    required this.playbackOnMain,
    required this.playbackSideIsLeft,
    required this.compact,
    required this.disabledText,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final leftPct = mainIsLeft ? mainPct : otherPct;
    final rightPct = mainIsLeft ? otherPct : mainPct;
    final otherSideIsLeft = !mainIsLeft;

    Widget pane({
      required bool isMain,
      required int pct,
      required String name,
      required String role,
      required bool showPlay,
    }) {
      final iconColor = isMain ? colors.accent : colors.textSecondary;
      return Expanded(
        flex: pct,
        child: Container(
          color: isMain ? colors.accentSoft : colors.surfaceSubtle,
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: colors.backgroundBase.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: isMain
                            ? colors.accent.withValues(alpha: 0.5)
                            : colors.borderSubtle,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      isMain
                          ? Icons.grid_view_rounded
                          : (showPlay
                                ? Icons.play_arrow_rounded
                                : Icons.article_outlined),
                      size: 17,
                      color: showPlay && !isMain ? colors.selection : iconColor,
                    ),
                  ),
                  if (showPlay && isMain)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: colors.selection,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          size: 11,
                          color: colors.backgroundBase,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: AdaptiveText.roleSize(12),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                role,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: AdaptiveText.roleSize(10.5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final mainPane = pane(
      isMain: true,
      pct: mainPct,
      name: l10n.parallelWindowPreviewMain,
      role: l10n.parallelWindowPreviewMainRole,
      showPlay: playbackOnMain,
    );
    final otherPane = pane(
      isMain: false,
      pct: otherPct,
      name: playbackSideIsLeft == otherSideIsLeft
          ? l10n.parallelWindowPreviewPlayer
          : l10n.parallelWindowPreviewSecondary,
      role: playbackSideIsLeft == otherSideIsLeft
          ? l10n.parallelWindowPreviewPlayerRole
          : l10n.parallelWindowPreviewSecondaryRole,
      showPlay: playbackSideIsLeft == otherSideIsLeft,
    );
    final leftPane = mainIsLeft ? mainPane : otherPane;
    final rightPane = mainIsLeft ? otherPane : mainPane;

    return _SettingsCard(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: <Widget>[
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: colors.selectionSoft,
                  borderRadius: BorderRadius.circular(7),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.preview_outlined,
                  size: 13,
                  color: colors.selection,
                ),
              ),
              const SizedBox(width: 9),
              Text(
                l10n.parallelWindowPreviewTitle,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: AdaptiveText.roleSize(13),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            children: <Widget>[
              Container(
                decoration: BoxDecoration(
                  color: colors.backgroundBase,
                  border: Border.all(color: colors.borderSubtle),
                ),
                child: SizedBox(
                  height: compact ? 150 : 190,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      leftPane,
                      Container(width: 1, color: colors.borderSubtle),
                      rightPane,
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 10,
                child: Text(
                  '$leftPct% / $rightPct%',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: AdaptiveText.roleSize(10.5),
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              if (!enabled)
                Positioned.fill(
                  child: ColoredBox(
                    color: colors.backgroundBase.withValues(alpha: 0.72),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.rectangle_outlined,
                            size: 16,
                            color: colors.textMuted,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            disabledText,
                            style: TextStyle(
                              color: colors.textMuted,
                              fontSize: AdaptiveText.roleSize(12.5),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 开关行：标题 + 动态副标题 + 行尾开关（与设置首页行尾开关同色制）。
class _SwitchRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: AdaptiveText.roleSize(15),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: AdaptiveText.roleSize(12.5),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: colors.selection,
            activeTrackColor: colors.selection.withValues(alpha: 0.45),
          ),
        ],
      ),
    );
  }
}

/// 状态摘要胶囊：appbar 行尾展示当前形态（已开启 · 左侧主屏 / 已关闭）。
class _StatusPill extends StatelessWidget {
  final String text;
  final bool enabled;

  const _StatusPill({required this.text, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: enabled ? colors.accentSoft : colors.surface,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: enabled
              ? colors.accent.withValues(alpha: 0.45)
              : colors.borderSubtle,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: enabled ? colors.accentStrong : colors.textMuted,
          fontSize: AdaptiveText.roleSize(11.5),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(height: 1, color: colors.borderSubtle),
    );
  }
}
