import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../providers/app_theme_provider.dart';
import '../theme/app_theme.dart';
import '../theme/app_theme_l10n.dart';
import '../ui/adaptive_text.dart';
import '../ui/app_transitions.dart';
import '../ui/secondary_host_navigation.dart';
import '../widgets/common/app_ambient_page.dart';
import '../widgets/detail/detail_more_actions_sheet.dart';
import '../widgets/settings/theme/theme_settings_helpers.dart';
import '../widgets/settings/theme/theme_settings_panels.dart';
import '../widgets/settings/theme/theme_settings_preset_card.dart';
import '../widgets/settings/theme/theme_settings_preview_card.dart';
import 'theme_custom_recipe_screen.dart';

/// 主题设置：紧凑英雄预览（色板簇 + mini 应用示意）→ 固定主题网格 →
/// 色彩自定义（四行色调，行内色板圈即点即生效）→ 动态取色 → 自定义主题
/// （当前配方入口 + 已保存主题网格）。桌面网格 4 列，窄视口 3/2 列。
class ThemeSettingsScreen extends StatelessWidget {
  const ThemeSettingsScreen({super.key});

  SliverGridDelegate _gridDelegate(double width) {
    final columns = width >= 980 ? 4 : (width >= 620 ? 3 : 2);
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      mainAxisExtent: 200,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppThemeProvider>();
    final l10n = AppLocalizations.of(context);

    // 页面自绘与首页同源的氛围底（整面覆盖，防转场残影）。
    return AppAmbientPage(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: buildSecondaryHostAppBar(
          context,
          title: Text(l10n.settingsThemeTitle),
          actions: <Widget>[
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: _StatusPill(
                  text: AppThemeL10n.currentThemeTitle(l10n, provider),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: <Widget>[
              ThemeSettingsPreviewCard(
                themeTitle: AppThemeL10n.currentThemeTitle(l10n, provider),
                themeSubtitle: AppThemeL10n.currentThemeSubtitle(
                  l10n,
                  provider,
                ),
                colors: provider.selectedThemeBaseColors,
              ),
              const SizedBox(height: 18),
              ThemeSettingsSectionTitle(
                title: l10n.themeFixedSectionTitle,
                subtitle: l10n.themeFixedSectionSubtitle,
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) => GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: _gridDelegate(constraints.maxWidth),
                  itemCount: AppThemePreset.values.length,
                  itemBuilder: (context, index) {
                    final preset = AppThemePreset.values[index];
                    return ThemeSettingsPresetCard(
                      title: AppThemeL10n.presetTitle(l10n, preset),
                      subtitle: AppThemeL10n.presetSubtitle(l10n, preset),
                      previewColors: provider.previewColorsForPreset(preset),
                      selected:
                          provider.isPresetActive && provider.preset == preset,
                      onTap: () => provider.applyPreset(preset),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
              _ToneCustomizationCard(provider: provider),
              const SizedBox(height: 18),
              ThemeSettingsDynamicThemePanel(provider: provider),
              const SizedBox(height: 22),
              ThemeSettingsSectionTitle(
                title: l10n.settingsCustomThemeTitle,
                subtitle: l10n.themeCustomSectionSubtitle,
              ),
              const SizedBox(height: 12),
              _CurrentCustomThemeRow(provider: provider),
              if (provider.savedThemes.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) => GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    gridDelegate: _gridDelegate(constraints.maxWidth),
                    itemCount: provider.savedThemes.length,
                    itemBuilder: (context, index) {
                      final savedTheme = provider.savedThemes[index];
                      return _SavedThemeCard(
                        theme: savedTheme,
                        selected:
                            provider.isSavedThemeActive &&
                            provider.activeSavedThemeId == savedTheme.id,
                      );
                    },
                  ),
                ),
              ] else ...<Widget>[
                const SizedBox(height: 12),
                const _EmptySavedThemesCard(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 色彩自定义：背景 / 主操作 / 选中 / 链接四行，行内色板圈即点即生效；
/// 「调色盘」进入配方页做深度编辑（HSV、快速颜色、另存主题）。
class _ToneCustomizationCard extends StatelessWidget {
  final AppThemeProvider provider;

  const _ToneCustomizationCard({required this.provider});

  Future<void> _openRecipe(BuildContext context) async {
    await Navigator.of(context).push(
      AppTransitions.leftToRightPageTurnRoute<void>(
        const ThemeCustomRecipeScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        children: <Widget>[
          _ToneRow(
            title: l10n.themeBackgroundControlTitle,
            subtitle: l10n.themeBackgroundControlSubtitle,
            currentColor: provider.backgroundPreviewColor,
            usesCustom: provider.usesCustomBackgroundColor,
            chips: <_ToneChip>[
              for (final tone in AppBackgroundTone.values)
                _ToneChip(
                  color: tone.tint,
                  tooltip: AppThemeL10n.backgroundToneTitle(l10n, tone),
                  selected:
                      provider.backgroundTone == tone &&
                      !provider.usesCustomBackgroundColor,
                  onTap: () => provider.setBackgroundTone(tone),
                ),
            ],
            onOpenPalette: () => _openRecipe(context),
          ),
          _ToneRow(
            title: l10n.themeAccentControlTitle,
            subtitle: l10n.themeAccentControlSubtitle,
            currentColor: provider.accentPreviewColor,
            usesCustom: provider.usesCustomAccentColor,
            chips: <_ToneChip>[
              for (final tone in AppAccentTone.values)
                _ToneChip(
                  color: tone.color,
                  tooltip: AppThemeL10n.accentToneTitle(l10n, tone),
                  selected:
                      provider.accentTone == tone &&
                      !provider.usesCustomAccentColor,
                  onTap: () => provider.setAccentTone(tone),
                ),
            ],
            onOpenPalette: () => _openRecipe(context),
          ),
          _ToneRow(
            title: l10n.themeSelectionControlTitle,
            subtitle: l10n.themeSelectionControlSubtitle,
            currentColor: provider.selectionPreviewColor,
            usesCustom: provider.usesCustomSelectionColor,
            chips: <_ToneChip>[
              for (final tone in AppAccentTone.values)
                _ToneChip(
                  color: tone.color,
                  tooltip: AppThemeL10n.accentToneTitle(l10n, tone),
                  selected:
                      provider.selectionTone == tone &&
                      !provider.usesCustomSelectionColor,
                  onTap: () => provider.setSelectionTone(tone),
                ),
            ],
            onOpenPalette: () => _openRecipe(context),
          ),
          _ToneRow(
            title: l10n.themeLinkControlTitle,
            subtitle: l10n.themeLinkControlSubtitle,
            currentColor: provider.linkPreviewColor,
            usesCustom: provider.usesCustomLinkColor,
            chips: <_ToneChip>[
              for (final tone in AppAccentTone.values)
                _ToneChip(
                  color: tone.color,
                  tooltip: AppThemeL10n.accentToneTitle(l10n, tone),
                  selected:
                      provider.linkTone == tone &&
                      !provider.usesCustomLinkColor,
                  onTap: () => provider.setLinkTone(tone),
                ),
            ],
            onOpenPalette: () => _openRecipe(context),
          ),
        ],
      ),
    );
  }
}

class _ToneChip {
  final Color color;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  const _ToneChip({
    required this.color,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });
}

/// 单行色调控制：当前色块 + 名称（自定义徽章）+ 色板圈 + 调色盘入口。
class _ToneRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color currentColor;
  final bool usesCustom;
  final List<_ToneChip> chips;
  final VoidCallback onOpenPalette;

  const _ToneRow({
    required this.title,
    required this.subtitle,
    required this.currentColor,
    required this.usesCustom,
    required this.chips,
    required this.onOpenPalette,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: <Widget>[
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: currentColor,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: themeSettingsVisibleBorderFor(currentColor),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 148,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: AdaptiveText.roleSize(13.5),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (usesCustom) ...<Widget>[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: colors.accentSoft,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: colors.accent.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          AppLocalizations.of(context).themeCustomLabel,
                          style: TextStyle(
                            color: colors.accentStrong,
                            fontSize: AdaptiveText.roleSize(10),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
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
          const SizedBox(width: 12),
          Expanded(
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: <Widget>[
                for (final chip in chips)
                  Tooltip(
                    message: chip.tooltip,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(99),
                      onTap: chip.onTap,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: chip.color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: chip.selected
                                ? colors.accent
                                : colors.textPrimary.withValues(alpha: 0.18),
                            width: chip.selected ? 2.5 : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _PaletteButton(onOpenPalette: onOpenPalette),
        ],
      ),
    );
  }
}

/// 调色盘入口：进入自定义配方页做深度编辑。
class _PaletteButton extends StatelessWidget {
  final VoidCallback onOpenPalette;

  const _PaletteButton({required this.onOpenPalette});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onOpenPalette,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.palette_outlined, size: 13, color: colors.textSecondary),
            const SizedBox(width: 5),
            Text(
              l10n.themePaletteButton,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: AdaptiveText.roleSize(11.5),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 当前自定义配方入口行：点击激活当前自定义并进入配方页。
class _CurrentCustomThemeRow extends StatelessWidget {
  final AppThemeProvider provider;

  const _CurrentCustomThemeRow({required this.provider});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        await provider.activateCurrentCustomTheme();
        if (!context.mounted) {
          return;
        }
        await Navigator.of(context).push(
          AppTransitions.leftToRightPageTurnRoute<void>(
            const ThemeCustomRecipeScreen(),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: provider.isCurrentCustomActive
                ? colors.selection
                : colors.borderSubtle,
          ),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: provider.themeColors.accent,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: themeSettingsVisibleBorderFor(
                    provider.themeColors.accent,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    l10n.themeCurrentCustomTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: AdaptiveText.roleSize(13.5),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    l10n.themeCurrentCustomCardSubtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: AdaptiveText.roleSize(11.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: colors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedThemeCard extends StatelessWidget {
  final SavedCustomTheme theme;
  final bool selected;

  const _SavedThemeCard({required this.theme, required this.selected});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<AppThemeProvider>();
    final l10n = AppLocalizations.of(context);
    return Stack(
      children: <Widget>[
        ThemeSettingsPresetCard(
          title: theme.name,
          subtitle: theme.description.trim().isEmpty
              ? l10n.themeSavedDefaultSubtitle
              : theme.description,
          previewColors: theme.colorsSnapshot,
          selected: selected,
          onTap: () => provider.applySavedTheme(theme.id),
        ),
        Positioned(
          top: 10,
          right: 10,
          child: PopupMenuButton<_SavedThemeMenuAction>(
            icon: Icon(
              Icons.more_horiz_rounded,
              color: context.appColors.textSecondary,
              size: 18,
            ),
            onSelected: (action) async {
              if (action == _SavedThemeMenuAction.rename) {
                final result = await showSaveThemeDialog(
                  context,
                  initialName: theme.name,
                  initialDescription: theme.description,
                  existingThemeId: theme.id,
                );
                if (result == null) {
                  return;
                }
                await provider.renameSavedTheme(
                  theme.id,
                  name: result.name,
                  description: result.description,
                );
                return;
              }
              await provider.deleteSavedTheme(theme.id);
            },
            itemBuilder: (context) => <PopupMenuEntry<_SavedThemeMenuAction>>[
              PopupMenuItem<_SavedThemeMenuAction>(
                value: _SavedThemeMenuAction.rename,
                child: Text(l10n.commonRename),
              ),
              PopupMenuItem<_SavedThemeMenuAction>(
                value: _SavedThemeMenuAction.delete,
                child: Text(l10n.commonDelete),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptySavedThemesCard extends StatelessWidget {
  const _EmptySavedThemesCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.themeNoSavedThemesTitle,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.themeNoSavedThemesSubtitle,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13.2,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

enum _SavedThemeMenuAction { rename, delete }

/// 状态摘要胶囊：appbar 行尾显示当前主题名。
class _StatusPill extends StatelessWidget {
  final String text;

  const _StatusPill({required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: colors.accentSoft,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: colors.accent.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: colors.accentStrong,
          fontSize: AdaptiveText.roleSize(11.5),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
