import 'package:flutter/material.dart';

import '../../../providers/app_theme_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../ui/adaptive_text.dart';
import 'theme_settings_helpers.dart';

class ThemeSettingsSectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const ThemeSettingsSectionTitle({
    super.key,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: AdaptiveText.roleSize(17, role: AdaptiveFontRole.title),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: TextStyle(
            color: colors.textMuted,
            fontSize: AdaptiveText.roleSize(13.4),
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class ThemeSettingsControlPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final String currentToneTitle;
  final Color currentColor;
  final String currentHex;
  final bool usesCustomColor;
  final Widget sample;
  final List<Widget> options;
  final VoidCallback onOpenCustomPicker;

  const ThemeSettingsControlPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.currentToneTitle,
    required this.currentColor,
    required this.currentHex,
    required this.usesCustomColor,
    required this.sample,
    required this.options,
    required this.onOpenCustomPicker,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: AdaptiveText.roleSize(15.5),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: AdaptiveText.roleSize(13.2),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surfaceSubtle,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.borderSubtle),
            ),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: currentColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: themeSettingsVisibleBorderFor(currentColor),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Text(
                                currentToneTitle,
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: AdaptiveText.roleSize(14.4),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (usesCustomColor) ...<Widget>[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.selectionSoft,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: colors.selection),
                                  ),
                                  child: Text(
                                    '自定义',
                                    style: TextStyle(
                                      color: colors.selectionStrong,
                                      fontSize: AdaptiveText.roleSize(11.5),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            currentHex,
                            style: TextStyle(
                              color: colors.textMuted,
                              fontSize: AdaptiveText.roleSize(12.8),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onOpenCustomPicker,
                      icon: const Icon(Icons.palette_outlined, size: 18),
                      label: const Text('调色盘'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                sample,
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              ...options,
              ThemeSettingsCustomColorChip(
                color: currentColor,
                selected: usesCustomColor,
                onTap: onOpenCustomPicker,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ThemeSettingsColorOptionChip extends StatelessWidget {
  final String label;
  final Color swatchColor;
  final bool selected;
  final VoidCallback onTap;

  const ThemeSettingsColorOptionChip({
    super.key,
    required this.label,
    required this.swatchColor,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? colors.selectionSoft : colors.surfaceSubtle,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? colors.selection : colors.borderSubtle,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: swatchColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: AdaptiveText.roleSize(13.5),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ThemeSettingsCustomColorChip extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const ThemeSettingsCustomColorChip({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? colors.selectionSoft : colors.surfaceSubtle,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? colors.selection : colors.borderSubtle,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    color,
                    Colors.white,
                    Colors.black.withValues(alpha: 0.78),
                  ],
                ),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '自定义',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: AdaptiveText.roleSize(13.5),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.palette_outlined, color: colors.textMuted, size: 16),
          ],
        ),
      ),
    );
  }
}

class ThemeSettingsRecipePanel extends StatelessWidget {
  final AppThemeProvider provider;

  const ThemeSettingsRecipePanel({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final items = <String>[
      '预设: ${provider.preset.title}',
      '背景: ${provider.usesCustomBackgroundColor ? '自定义 ${themeSettingsColorHex(provider.backgroundPreviewColor)}' : provider.backgroundTone.title}',
      '主操作: ${provider.usesCustomAccentColor ? '自定义 ${themeSettingsColorHex(provider.accentPreviewColor)}' : provider.accentTone.title}',
      '选中色: ${provider.usesCustomSelectionColor ? '自定义 ${themeSettingsColorHex(provider.selectionPreviewColor)}' : provider.selectionTone.title}',
      '链接色: ${provider.usesCustomLinkColor ? '自定义 ${themeSettingsColorHex(provider.linkPreviewColor)}' : provider.linkTone.title}',
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '当前配方',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: AdaptiveText.roleSize(15.5),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                item,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: AdaptiveText.roleSize(13.3),
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ThemeSettingsDynamicThemePanel extends StatelessWidget {
  final AppThemeProvider provider;

  const ThemeSettingsDynamicThemePanel({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final enabled = provider.dynamicThemeEnabled;
    final visibleIntensities = <AppDynamicThemeIntensity>[
      AppDynamicThemeIntensity.subtle,
      AppDynamicThemeIntensity.medium,
      AppDynamicThemeIntensity.vivid,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '动态取色主题',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: AdaptiveText.roleSize(15.5),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '进入详情页后根据海报临时取色，退出恢复当前主题。会保留你选的深色或奶白基础风格，不会乱跳明暗。',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: AdaptiveText.roleSize(13.2),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch(
                value: enabled,
                onChanged: (value) {
                  provider.setDynamicThemeMode(
                    value
                        ? AppDynamicThemeMode.detailsAndPeople
                        : AppDynamicThemeMode.off,
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surfaceSubtle,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  enabled ? '当前范围: 详情页和人物页' : '当前范围: 已关闭',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: AdaptiveText.roleSize(13.8),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'V1 先控制背景主色系、面板层级、桥接渐变和环境 tint，按钮与链接继续保持你手动设定的固定颜色。',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: AdaptiveText.roleSize(12.8),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: visibleIntensities
                      .map(
                        (intensity) => ThemeSettingsColorOptionChip(
                          label: intensity.settingsTitle,
                          swatchColor: provider.backgroundPreviewColor,
                          selected:
                              enabled &&
                              provider.dynamicThemeIntensity == intensity,
                          onTap: () {
                            provider.setDynamicThemeIntensity(intensity);
                            if (!enabled) {
                              provider.setDynamicThemeMode(
                                AppDynamicThemeMode.detailsAndPeople,
                              );
                            }
                          },
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
