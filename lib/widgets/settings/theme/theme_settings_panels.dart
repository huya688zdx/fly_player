import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../providers/app_theme_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_theme_l10n.dart';
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
    final l10n = AppLocalizations.of(context);
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
                                    l10n.themeCustomLabel,
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
                      label: Text(l10n.themePaletteButton),
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
    final l10n = AppLocalizations.of(context);
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
              l10n.themeCustomLabel,
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
    final l10n = AppLocalizations.of(context);
    final customLabel = l10n.themeCustomLabel;
    final items = <String>[
      '${l10n.themeRecipePresetLabel}: ${AppThemeL10n.presetTitle(l10n, provider.preset)}',
      '${l10n.themeRecipeBackgroundLabel}: ${provider.usesCustomBackgroundColor ? '$customLabel ${themeSettingsColorHex(provider.backgroundPreviewColor)}' : AppThemeL10n.backgroundToneTitle(l10n, provider.backgroundTone)}',
      '${l10n.themeRecipeAccentLabel}: ${provider.usesCustomAccentColor ? '$customLabel ${themeSettingsColorHex(provider.accentPreviewColor)}' : AppThemeL10n.accentToneTitle(l10n, provider.accentTone)}',
      '${l10n.themeRecipeSelectionLabel}: ${provider.usesCustomSelectionColor ? '$customLabel ${themeSettingsColorHex(provider.selectionPreviewColor)}' : AppThemeL10n.accentToneTitle(l10n, provider.selectionTone)}',
      '${l10n.themeRecipeLinkLabel}: ${provider.usesCustomLinkColor ? '$customLabel ${themeSettingsColorHex(provider.linkPreviewColor)}' : AppThemeL10n.accentToneTitle(l10n, provider.linkTone)}',
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
            l10n.themeRecipeCurrentTitle,
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
    final l10n = AppLocalizations.of(context);
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
                      l10n.themeDynamicTitle,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: AdaptiveText.roleSize(15.5),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.themeDynamicSubtitle,
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
                  enabled
                      ? l10n.themeDynamicScopeDetailsAndPeople
                      : l10n.themeDynamicScopeOff,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: AdaptiveText.roleSize(13.8),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.themeDynamicDescription,
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
                          label:
                              AppThemeL10n.dynamicThemeIntensitySettingsTitle(
                                l10n,
                                intensity,
                              ),
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
                const SizedBox(height: 12),
                Text(
                  enabled
                      ? AppThemeL10n.dynamicThemeBehaviorDescription(
                          l10n,
                          provider.dynamicThemeIntensity,
                        )
                      : l10n.themeDynamicDisabled,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: AdaptiveText.roleSize(12.8),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.themeDynamicPlayerNote,
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: AdaptiveText.roleSize(12.2),
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
