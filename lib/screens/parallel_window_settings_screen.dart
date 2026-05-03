import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../providers/parallel_window_settings_provider.dart';
import '../theme/app_theme.dart';
import '../ui/adaptive_text.dart';
import '../ui/secondary_host_navigation.dart';

class ParallelWindowSettingsScreen extends StatelessWidget {
  const ParallelWindowSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final settings = context.watch<ParallelWindowSettingsProvider>();
    final l10n = AppLocalizations.of(context);
    final bodySize = AdaptiveText.roleSize(14.5);

    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: buildSecondaryHostAppBar(
        context,
        title: Text(
          l10n.parallelWindowTitle,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: AdaptiveText.roleSize(20, role: AdaptiveFontRole.title),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[colors.backgroundElevated, colors.backgroundBase],
          ),
        ),
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: <Widget>[
              _SettingsBlock(
                child: Column(
                  children: <Widget>[
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: settings.enabled,
                      onChanged: settings.isReady
                          ? (value) => settings.setEnabled(value)
                          : null,
                      title: Text(
                        l10n.parallelWindowEnableTitle,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: AdaptiveText.roleSize(16),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        l10n.parallelWindowEnableSubtitle,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: bodySize,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _SectionTitle(title: l10n.parallelWindowPrimarySideTitle),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: <Widget>[
                        _OptionChip(
                          selected: settings.preferredPrimaryPaneSide == 'left',
                          title: l10n.parallelWindowPrimaryLeftTitle,
                          subtitle: l10n.parallelWindowPrimaryLeftSubtitle,
                          onTap: settings.isReady
                              ? () =>
                                    settings.setPreferredPrimaryPaneSide('left')
                              : null,
                        ),
                        _OptionChip(
                          selected:
                              settings.preferredPrimaryPaneSide == 'right',
                          title: l10n.parallelWindowPrimaryRightTitle,
                          subtitle: l10n.parallelWindowPrimaryRightSubtitle,
                          onTap: settings.isReady
                              ? () => settings.setPreferredPrimaryPaneSide(
                                  'right',
                                )
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _SectionTitle(title: l10n.parallelWindowPlaybackSideTitle),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: <Widget>[
                        _OptionChip(
                          selected:
                              settings.preferredPlaybackPrimaryPaneSide ==
                              'left',
                          title: l10n.parallelWindowPlaybackLeftTitle,
                          subtitle: l10n.parallelWindowPlaybackLeftSubtitle,
                          onTap: settings.isReady
                              ? () => settings
                                    .setPreferredPlaybackPrimaryPaneSide('left')
                              : null,
                        ),
                        _OptionChip(
                          selected:
                              settings.preferredPlaybackPrimaryPaneSide ==
                              'right',
                          title: l10n.parallelWindowPlaybackRightTitle,
                          subtitle: l10n.parallelWindowPlaybackRightSubtitle,
                          onTap: settings.isReady
                              ? () => settings
                                    .setPreferredPlaybackPrimaryPaneSide(
                                      'right',
                                    )
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _SectionTitle(title: l10n.parallelWindowSplitRatioTitle),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: <Widget>[
                        _OptionChip(
                          selected: settings.splitRatioPreset == 'balanced',
                          title: '42 / 58',
                          subtitle: l10n.parallelWindowSplitBalancedSubtitle,
                          onTap: settings.isReady
                              ? () => settings.setSplitRatioPreset('balanced')
                              : null,
                        ),
                        _OptionChip(
                          selected: settings.splitRatioPreset == 'equal',
                          title: '50 / 50',
                          subtitle: l10n.parallelWindowSplitEqualSubtitle,
                          onTap: settings.isReady
                              ? () => settings.setSplitRatioPreset('equal')
                              : null,
                        ),
                        _OptionChip(
                          selected: settings.splitRatioPreset == 'focus_detail',
                          title: '35 / 65',
                          subtitle:
                              l10n.parallelWindowSplitFocusDetailSubtitle,
                          onTap: settings.isReady
                              ? () =>
                                    settings.setSplitRatioPreset('focus_detail')
                              : null,
                        ),
                        _OptionChip(
                          selected: settings.splitRatioPreset == 'focus_home',
                          title: '45 / 55',
                          subtitle: l10n.parallelWindowSplitFocusHomeSubtitle,
                          onTap: settings.isReady
                              ? () => settings.setSplitRatioPreset('focus_home')
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: settings.defaultPlaybackFullscreen,
                      onChanged: settings.isReady
                          ? (value) =>
                                settings.setDefaultPlaybackFullscreen(value)
                          : null,
                      title: Text(
                        l10n.parallelWindowDefaultFullscreenTitle,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: AdaptiveText.roleSize(16),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        settings.defaultPlaybackFullscreen
                            ? l10n.parallelWindowDefaultFullscreenOnSubtitle
                            : l10n.parallelWindowDefaultFullscreenOffSubtitle,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: bodySize,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: settings.immersiveStatusBar,
                      onChanged: settings.isReady
                          ? (value) => settings.setImmersiveStatusBar(value)
                          : null,
                      title: Text(
                        l10n.parallelWindowImmersiveTitle,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: AdaptiveText.roleSize(16),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        settings.immersiveStatusBar
                            ? l10n.parallelWindowImmersiveOnSubtitle
                            : l10n.parallelWindowImmersiveOffSubtitle,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: bodySize,
                        ),
                      ),
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
}

class _SettingsBlock extends StatelessWidget {
  final Widget child;

  const _SettingsBlock({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: AdaptiveText.roleSize(15.5),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _OptionChip({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 260,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? colors.accentSoft : colors.backgroundElevated,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? colors.accent : colors.borderSubtle,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: selected ? colors.accentStrong : colors.textMuted,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: AdaptiveText.roleSize(15),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: AdaptiveText.roleSize(13.5),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
