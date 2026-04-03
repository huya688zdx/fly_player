import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_theme_provider.dart';
import '../theme/app_theme.dart';
import '../ui/secondary_host_navigation.dart';
import '../utils/app_top_tip.dart';
import '../widgets/detail/detail_more_actions_sheet.dart';
import '../widgets/settings/theme/theme_settings_color_picker_dialog.dart';
import '../widgets/settings/theme/theme_settings_helpers.dart';
import '../widgets/settings/theme/theme_settings_panels.dart';
import '../widgets/settings/theme/theme_settings_samples.dart';

class ThemeCustomRecipeScreen extends StatelessWidget {
  const ThemeCustomRecipeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final provider = context.watch<AppThemeProvider>();
    final themeColors = provider.themeColors;

    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: buildSecondaryHostAppBar(
        context,
        title: const Text('颜色分类控制'),
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              final result = await showSaveThemeDialog(
                context,
                initialName: provider.nextSavedThemeName(),
                suggestedName: provider.nextSavedThemeNameFromBase('自定义主题'),
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
                message: '已保存主题：${result.name}',
                color: context.appColors.success,
              );
            },
            child: const Text('保存主题'),
          ),
        ],
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
              const ThemeSettingsSectionTitle(
                title: '颜色分类控制',
                subtitle: '这里保存的是当前自定义配方。你可以继续逐项微调，然后把喜欢的结果另存为新的自定义主题。',
              ),
              const SizedBox(height: 12),
              ThemeSettingsControlPanel(
                title: '背景主色',
                subtitle: '控制页面底色、卡片层级、导航栏和整体氛围基调。',
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
                subtitle: '控制主按钮、进度条、确认动作和主要强调元素。',
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
                subtitle: '控制选中态、边框高亮和标签状态。',
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
                subtitle: '控制“更多”、跳转文本和轻量提示的强调色。',
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
    if (result == null) {
      return;
    }
    await onApply(result);
  }
}
