import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../providers/app_theme_provider.dart';
import '../theme/app_theme.dart';
import '../theme/app_theme_l10n.dart';
import '../ui/secondary_host_navigation.dart';
import '../utils/app_top_tip.dart';
import '../widgets/common/app_ambient_page.dart';
import '../widgets/detail/detail_more_actions_sheet.dart';
import '../widgets/settings/theme/theme_settings_color_picker_dialog.dart';
import '../widgets/settings/theme/theme_settings_helpers.dart';
import '../widgets/settings/theme/theme_settings_panels.dart';
import '../widgets/settings/theme/theme_settings_samples.dart';

class ThemeCustomRecipeScreen extends StatelessWidget {
  const ThemeCustomRecipeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppThemeProvider>();
    final themeColors = provider.themeColors;
    final l10n = AppLocalizations.of(context);

    // 页面自绘与首页同源的氛围底（整面覆盖，防转场残影）。
    return AppAmbientPage(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: buildSecondaryHostAppBar(
          context,
          title: Text(l10n.settingsCustomRecipeTitle),
          actions: <Widget>[
            TextButton(
              onPressed: () async {
                final result = await showSaveThemeDialog(
                  context,
                  initialName: provider.nextSavedThemeNameFromBase(
                    l10n.themeCustomBaseName,
                  ),
                  suggestedName: provider.nextSavedThemeNameFromBase(
                    l10n.themeCustomBaseName,
                  ),
                );
                if (!context.mounted || result == null) {
                  return;
                }
                await provider.saveThemeSnapshot(
                  colors: provider.themeColors,
                  name: result.name,
                  description: result.description,
                  clearRuntimeBroadcastToMain: false,
                );
                if (!context.mounted) {
                  return;
                }
                AppTopTip().show(
                  context,
                  message: l10n.detailThemeSaved(result.name),
                  color: context.appColors.success,
                );
              },
              child: Text(l10n.detailSaveCurrentTheme),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: <Widget>[
              ThemeSettingsSectionTitle(
                title: l10n.settingsCustomRecipeTitle,
                subtitle: l10n.themeCustomRecipePageSubtitle,
              ),
              const SizedBox(height: 12),
              ThemeSettingsControlPanel(
                title: l10n.themeBackgroundControlTitle,
                subtitle: l10n.themeBackgroundControlSubtitle,
                currentToneTitle: provider.usesCustomBackgroundColor
                    ? l10n.themeCustomLabel
                    : AppThemeL10n.backgroundToneTitle(
                        l10n,
                        provider.backgroundTone,
                      ),
                currentColor: provider.backgroundPreviewColor,
                currentHex: themeSettingsColorHex(
                  provider.backgroundPreviewColor,
                ),
                usesCustomColor: provider.usesCustomBackgroundColor,
                sample: ThemeSettingsBackgroundSample(colors: themeColors),
                onOpenCustomPicker: () => _pickCustomColor(
                  context,
                  title: l10n.themeCustomBackgroundPickerTitle,
                  initialColor:
                      provider.customBackgroundColor ??
                      provider.backgroundPreviewColor,
                  quickColors: AppBackgroundTone.values
                      .map((tone) => tone.tint)
                      .toList(growable: false),
                  onApply: provider.setCustomBackgroundColor,
                ),
                options: AppBackgroundTone.values
                    .map(
                      (tone) => ThemeSettingsColorOptionChip(
                        label: AppThemeL10n.backgroundToneTitle(l10n, tone),
                        swatchColor: tone.tint,
                        selected:
                            !provider.usesCustomBackgroundColor &&
                            provider.backgroundTone == tone,
                        onTap: () => provider.setBackgroundTone(tone),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 14),
              ThemeSettingsControlPanel(
                title: l10n.themeAccentControlTitle,
                subtitle: l10n.themeAccentControlSubtitle,
                currentToneTitle: provider.usesCustomAccentColor
                    ? l10n.themeCustomLabel
                    : AppThemeL10n.accentToneTitle(l10n, provider.accentTone),
                currentColor: provider.accentPreviewColor,
                currentHex: themeSettingsColorHex(provider.accentPreviewColor),
                usesCustomColor: provider.usesCustomAccentColor,
                sample: ThemeSettingsActionSample(colors: themeColors),
                onOpenCustomPicker: () => _pickCustomColor(
                  context,
                  title: l10n.themeCustomAccentPickerTitle,
                  initialColor:
                      provider.customAccentColor ?? provider.accentPreviewColor,
                  quickColors: AppAccentTone.values
                      .map((tone) => tone.color)
                      .toList(growable: false),
                  onApply: provider.setCustomAccentColor,
                ),
                options: AppAccentTone.values
                    .map(
                      (tone) => ThemeSettingsColorOptionChip(
                        label: AppThemeL10n.accentToneTitle(l10n, tone),
                        swatchColor: tone.color,
                        selected:
                            !provider.usesCustomAccentColor &&
                            provider.accentTone == tone,
                        onTap: () => provider.setAccentTone(tone),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 14),
              ThemeSettingsControlPanel(
                title: l10n.themeSelectionControlTitle,
                subtitle: l10n.themeSelectionControlSubtitle,
                currentToneTitle: provider.usesCustomSelectionColor
                    ? l10n.themeCustomLabel
                    : AppThemeL10n.accentToneTitle(
                        l10n,
                        provider.selectionTone,
                      ),
                currentColor: provider.selectionPreviewColor,
                currentHex: themeSettingsColorHex(
                  provider.selectionPreviewColor,
                ),
                usesCustomColor: provider.usesCustomSelectionColor,
                sample: ThemeSettingsSelectionSample(colors: themeColors),
                onOpenCustomPicker: () => _pickCustomColor(
                  context,
                  title: l10n.themeCustomSelectionPickerTitle,
                  initialColor:
                      provider.customSelectionColor ??
                      provider.selectionPreviewColor,
                  quickColors: AppAccentTone.values
                      .map((tone) => tone.color)
                      .toList(growable: false),
                  onApply: provider.setCustomSelectionColor,
                ),
                options: AppAccentTone.values
                    .map(
                      (tone) => ThemeSettingsColorOptionChip(
                        label: AppThemeL10n.accentToneTitle(l10n, tone),
                        swatchColor: tone.color,
                        selected:
                            !provider.usesCustomSelectionColor &&
                            provider.selectionTone == tone,
                        onTap: () => provider.setSelectionTone(tone),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 14),
              ThemeSettingsControlPanel(
                title: l10n.themeLinkControlTitle,
                subtitle: l10n.themeLinkControlSubtitle,
                currentToneTitle: provider.usesCustomLinkColor
                    ? l10n.themeCustomLabel
                    : AppThemeL10n.accentToneTitle(l10n, provider.linkTone),
                currentColor: provider.linkPreviewColor,
                currentHex: themeSettingsColorHex(provider.linkPreviewColor),
                usesCustomColor: provider.usesCustomLinkColor,
                sample: ThemeSettingsLinkSample(colors: themeColors),
                onOpenCustomPicker: () => _pickCustomColor(
                  context,
                  title: l10n.themeCustomLinkPickerTitle,
                  initialColor:
                      provider.customLinkColor ?? provider.linkPreviewColor,
                  quickColors: AppAccentTone.values
                      .map((tone) => tone.strongColor)
                      .toList(growable: false),
                  onApply: provider.setCustomLinkColor,
                ),
                options: AppAccentTone.values
                    .map(
                      (tone) => ThemeSettingsColorOptionChip(
                        label: AppThemeL10n.accentToneTitle(l10n, tone),
                        swatchColor: tone.strongColor,
                        selected:
                            !provider.usesCustomLinkColor &&
                            provider.linkTone == tone,
                        onTap: () => provider.setLinkTone(tone),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 16),
              ThemeSettingsRecipePanel(provider: provider),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _pickCustomColor(
    BuildContext context, {
    required String title,
    required Color initialColor,
    required List<Color> quickColors,
    required Future<void> Function(Color value) onApply,
  }) async {
    final result = await showDialog<Color>(
      context: context,
      builder: (_) => ThemeSettingsColorPickerDialog(
        title: title,
        initialColor: initialColor,
        quickColors: quickColors,
      ),
    );
    if (result == null) {
      return;
    }
    await onApply(result);
  }
}
