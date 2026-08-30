import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../desktop/desktop.dart';
import '../l10n/generated/app_localizations.dart';
import '../providers/app_theme_provider.dart';
import '../ui/layout_adaptive.dart';
import '../theme/app_theme.dart';
import '../theme/app_theme_l10n.dart';
import '../ui/app_transitions.dart';
import '../ui/secondary_host_navigation.dart';
import '../widgets/detail/detail_more_actions_sheet.dart';
import '../widgets/settings/theme/theme_settings_panels.dart';
import '../widgets/settings/theme/theme_settings_preset_card.dart';
import '../widgets/settings/theme/theme_settings_preview_card.dart';
import 'theme_custom_recipe_screen.dart';

class ThemeSettingsScreen extends StatelessWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final provider = context.watch<AppThemeProvider>();
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: buildSecondaryHostAppBar(
        context,
        title: Text(l10n.settingsThemeTitle),
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
              SizedBox(
                height: 212,
                child: HoverScrollRow(
                  enabled: MediaLayoutProfile.of(context).isDesktopTier,
                  builder: (controller) => ListView.separated(
                    controller: controller,
                    scrollDirection: Axis.horizontal,
                    itemCount: AppThemePreset.values.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final preset = AppThemePreset.values[index];
                      return ThemeSettingsPresetCard(
                        title: AppThemeL10n.presetTitle(l10n, preset),
                        subtitle: AppThemeL10n.presetSubtitle(l10n, preset),
                        previewColors: provider.previewColorsForPreset(preset),
                        selected:
                            provider.isPresetActive &&
                            provider.preset == preset,
                        onTap: () => provider.applyPreset(preset),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 22),
              ThemeSettingsDynamicThemePanel(provider: provider),
              const SizedBox(height: 22),
              ThemeSettingsSectionTitle(
                title: l10n.settingsCustomThemeTitle,
                subtitle: l10n.themeCustomSectionSubtitle,
              ),
              const SizedBox(height: 12),
              _CurrentCustomThemeCard(provider: provider),
              if (provider.savedThemes.isNotEmpty) ...<Widget>[
                const SizedBox(height: 14),
                SizedBox(
                  height: 212,
                  child: HoverScrollRow(
                    enabled: MediaLayoutProfile.of(context).isDesktopTier,
                    builder: (controller) => ListView.separated(
                      controller: controller,
                      scrollDirection: Axis.horizontal,
                      itemCount: provider.savedThemes.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
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
                ),
              ] else ...<Widget>[
                const SizedBox(height: 14),
                _EmptySavedThemesCard(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrentCustomThemeCard extends StatelessWidget {
  final AppThemeProvider provider;

  const _CurrentCustomThemeCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ThemeSettingsPresetCard(
      title: l10n.themeCurrentCustomTitle,
      subtitle: l10n.themeCurrentCustomCardSubtitle,
      previewColors: provider.themeColors,
      selected: provider.isCurrentCustomActive,
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
    return SizedBox(
      width: 232,
      child: Stack(
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
      ),
    );
  }
}

class _EmptySavedThemesCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
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
