import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_theme_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/settings/theme/theme_settings_color_picker_dialog.dart';
import '../widgets/settings/theme/theme_settings_helpers.dart';
import '../widgets/settings/theme/theme_settings_panels.dart';
import '../widgets/settings/theme/theme_settings_preset_card.dart';
import '../widgets/settings/theme/theme_settings_preview_card.dart';
import '../widgets/settings/theme/theme_settings_samples.dart';

class ThemeSettingsScreen extends StatelessWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final provider = context.watch<AppThemeProvider>();
    final themeColors = provider.themeColors;

    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: AppBar(title: const Text('主题设置')),
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
              ThemeSettingsPreviewCard(
                themeTitle: provider.effectiveThemeTitle,
                backgroundTitle: provider.usesCustomBackgroundColor
                    ? '自定义'
                    : provider.backgroundTone.title,
                actionTitle: provider.usesCustomAccentColor
                    ? '自定义'
                    : provider.accentTone.title,
                selectionTitle: provider.usesCustomSelectionColor
                    ? '自定义'
                    : provider.selectionTone.title,
                linkTitle: provider.usesCustomLinkColor
                    ? '自定义'
                    : provider.linkTone.title,
                colors: themeColors,
              ),
              const SizedBox(height: 18),
              const ThemeSettingsSectionTitle(
                title: '固定主题',
                subtitle:
                    '向右滑动选择整套预设。继续微调下面的颜色分类时，会自动从当前预设切到自定义主题。动态取色在下方单独控制。',
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 212,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: AppThemePreset.values.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return ThemeSettingsPresetCard(
                        title: '自定义',
                        subtitle: '当前固定主题的微调结果会落到这里，方便你继续细调。',
                        previewColors: themeColors,
                        selected: provider.isPresetCustomized,
                        onTap: () {},
                      );
                    }
                    final preset = AppThemePreset.values[index - 1];
                    return ThemeSettingsPresetCard(
                      title: preset.title,
                      subtitle: preset.subtitle,
                      previewColors: provider.previewColorsForPreset(preset),
                      selected:
                          !provider.isPresetCustomized &&
                          provider.preset == preset,
                      onTap: () => provider.applyPreset(preset),
                    );
                  },
                ),
              ),
              const SizedBox(height: 22),
              ThemeSettingsDynamicThemePanel(provider: provider),
              const SizedBox(height: 22),
              const ThemeSettingsSectionTitle(
                title: '颜色分类控制',
                subtitle: '每一类都会展示真实颜色和使用场景。你可以用预设色，也可以直接打开调色盘自定义。',
              ),
              const SizedBox(height: 12),
              ThemeSettingsControlPanel(
                title: '背景主色',
                subtitle:
                    '这里决定页面底色、卡片层级、底栏和深浅氛围。奶白、浅灰、深色都可以直接切换。',
                currentToneTitle: provider.usesCustomBackgroundColor
                    ? '自定义'
                    : provider.backgroundTone.title,
                currentColor: provider.backgroundPreviewColor,
                currentHex: themeSettingsColorHex(
                  provider.backgroundPreviewColor,
                ),
                usesCustomColor: provider.usesCustomBackgroundColor,
                sample: ThemeSettingsBackgroundSample(colors: themeColors),
                onOpenCustomPicker: () => _pickCustomColor(
                  context,
                  title: '自定义背景色',
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
                        label: tone.title,
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
                title: '主操作色',
                subtitle: '主按钮、进度条、开关、确认动作都会跟着变化。',
                currentToneTitle: provider.usesCustomAccentColor
                    ? '自定义'
                    : provider.accentTone.title,
                currentColor: provider.accentPreviewColor,
                currentHex: themeSettingsColorHex(provider.accentPreviewColor),
                usesCustomColor: provider.usesCustomAccentColor,
                sample: ThemeSettingsActionSample(colors: themeColors),
                onOpenCustomPicker: () => _pickCustomColor(
                  context,
                  title: '自定义主操作色',
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
                        label: tone.title,
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
                title: '选中色',
                subtitle: '标签选中态、已选边框和高亮卡片都会跟着变化。',
                currentToneTitle: provider.usesCustomSelectionColor
                    ? '自定义'
                    : provider.selectionTone.title,
                currentColor: provider.selectionPreviewColor,
                currentHex: themeSettingsColorHex(
                  provider.selectionPreviewColor,
                ),
                usesCustomColor: provider.usesCustomSelectionColor,
                sample: ThemeSettingsSelectionSample(colors: themeColors),
                onOpenCustomPicker: () => _pickCustomColor(
                  context,
                  title: '自定义选中色',
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
                        label: tone.title,
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
                title: '链接高亮色',
                subtitle: '“更多”、文字链接和轻量跳转提示都会跟着变化。',
                currentToneTitle: provider.usesCustomLinkColor
                    ? '自定义'
                    : provider.linkTone.title,
                currentColor: provider.linkPreviewColor,
                currentHex: themeSettingsColorHex(provider.linkPreviewColor),
                usesCustomColor: provider.usesCustomLinkColor,
                sample: ThemeSettingsLinkSample(colors: themeColors),
                onOpenCustomPicker: () => _pickCustomColor(
                  context,
                  title: '自定义链接色',
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
                        label: tone.title,
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
    if (result == null) return;
    await onApply(result);
  }
}
