import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/parallel_window_settings_provider.dart';
import '../theme/app_theme.dart';
import '../ui/adaptive_text.dart';

class ParallelWindowSettingsScreen extends StatelessWidget {
  const ParallelWindowSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final settings = context.watch<ParallelWindowSettingsProvider>();
    final bodySize = AdaptiveText.roleSize(14.5);

    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: AppBar(
        title: Text(
          '平行窗口设置',
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
              const _DetailHeroCard(
                icon: Icons.splitscreen_outlined,
                title: '平行窗口',
                subtitle: '控制主副屏位置、分屏比例，以及播放时默认优先全屏还是优先进入分屏播放。',
              ),
              const SizedBox(height: 18),
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
                        '启用平行窗口',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: AdaptiveText.roleSize(16),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '开启后，大屏设备的二级页面优先在副屏展开；关闭后恢复普通单屏跳转。',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: bodySize,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const _SectionTitle(title: '主屏位置'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: <Widget>[
                        _OptionChip(
                          selected: settings.preferredPrimaryPaneSide == 'left',
                          title: '左侧主屏',
                          subtitle: '默认首页在左，右侧展开详情或设置。',
                          onTap: settings.isReady
                              ? () =>
                                    settings.setPreferredPrimaryPaneSide('left')
                              : null,
                        ),
                        _OptionChip(
                          selected:
                              settings.preferredPrimaryPaneSide == 'right',
                          title: '右侧主屏',
                          subtitle: '为后续需要右主左副的布局预留。',
                          onTap: settings.isReady
                              ? () => settings.setPreferredPrimaryPaneSide(
                                  'right',
                                )
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const _SectionTitle(title: '播放主屏位置'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: <Widget>[
                        _OptionChip(
                          selected:
                              settings.preferredPlaybackPrimaryPaneSide ==
                              'left',
                          title: '左侧为播放主屏',
                          subtitle: '进入分屏播放后，左边保持播放器，右边放详情或首页。',
                          onTap: settings.isReady
                              ? () => settings
                                    .setPreferredPlaybackPrimaryPaneSide('left')
                              : null,
                        ),
                        _OptionChip(
                          selected:
                              settings.preferredPlaybackPrimaryPaneSide ==
                              'right',
                          title: '右侧为播放主屏',
                          subtitle: '进入分屏播放后，右边保持播放器，左边放详情或首页。',
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
                    const _SectionTitle(title: '分屏比例'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: <Widget>[
                        _OptionChip(
                          selected: settings.splitRatioPreset == 'balanced',
                          title: '42 / 58',
                          subtitle: '默认，兼顾列表浏览和右侧详情。',
                          onTap: settings.isReady
                              ? () => settings.setSplitRatioPreset('balanced')
                              : null,
                        ),
                        _OptionChip(
                          selected: settings.splitRatioPreset == 'equal',
                          title: '50 / 50',
                          subtitle: '左右均衡，适合需要同时操作两侧。',
                          onTap: settings.isReady
                              ? () => settings.setSplitRatioPreset('equal')
                              : null,
                        ),
                        _OptionChip(
                          selected: settings.splitRatioPreset == 'focus_detail',
                          title: '35 / 65',
                          subtitle: '副屏更宽，适合详情和播放信息更重的场景。',
                          onTap: settings.isReady
                              ? () =>
                                    settings.setSplitRatioPreset('focus_detail')
                              : null,
                        ),
                        _OptionChip(
                          selected: settings.splitRatioPreset == 'focus_home',
                          title: '45 / 55',
                          subtitle: '主屏稍宽，适合首页或列表操作更多的场景。',
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
                        '默认播放全屏',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: AdaptiveText.roleSize(16),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        settings.defaultPlaybackFullscreen
                            ? '点击播放后先进入全屏播放器，再由按钮切到分屏。'
                            : '点击播放后优先保持平行窗口分屏，不先放大全屏。',
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
                        '平行窗口沉浸模式',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: AdaptiveText.roleSize(16),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        settings.immersiveStatusBar
                            ? '进入平行窗口后隐藏状态栏，内容直接顶到屏幕顶部。'
                            : '保留状态栏，使用常规分屏显示。',
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

class _DetailHeroCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _DetailHeroCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[colors.surfaceSubtle, colors.backgroundElevated],
        ),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: colors.surfaceStrong,
              borderRadius: BorderRadius.circular(18),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: colors.textPrimary, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: AdaptiveText.roleSize(
                      18,
                      role: AdaptiveFontRole.title,
                    ),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: AdaptiveText.roleSize(14),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
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
