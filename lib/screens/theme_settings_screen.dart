import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_theme_provider.dart';
import '../theme/app_theme.dart';
import '../ui/app_transitions.dart';
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
                themeTitle: provider.currentThemeTitle,
                themeSubtitle: provider.currentThemeSubtitle,
                colors: provider.selectedThemeBaseColors,
              ),
              const SizedBox(height: 18),
              const ThemeSettingsSectionTitle(
                title: '固定主题',
                subtitle: '这里保留官方预设。切换后会直接作为全局主题生效，不影响你下面保存过的自定义主题。',
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 212,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: AppThemePreset.values.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final preset = AppThemePreset.values[index];
                    return ThemeSettingsPresetCard(
                      title: preset.title,
                      subtitle: preset.subtitle,
                      previewColors: provider.previewColorsForPreset(preset),
                      selected:
                          provider.isPresetActive && provider.preset == preset,
                      onTap: () => provider.applyPreset(preset),
                    );
                  },
                ),
              ),
              const SizedBox(height: 22),
              ThemeSettingsDynamicThemePanel(provider: provider),
              const SizedBox(height: 22),
              const ThemeSettingsSectionTitle(
                title: '自定义主题',
                subtitle: '当前自定义用于继续调色；保存过的主题是独立预设，可应用、重命名和删除。',
              ),
              const SizedBox(height: 12),
              _CurrentCustomThemeCard(provider: provider),
              if (provider.savedThemes.isNotEmpty) ...<Widget>[
                const SizedBox(height: 14),
                SizedBox(
                  height: 212,
                  child: ListView.separated(
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
    return ThemeSettingsPresetCard(
      title: '当前自定义',
      subtitle: '进入三级菜单继续编辑颜色分类控制和当前配方。',
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
    return SizedBox(
      width: 232,
      child: Stack(
        children: <Widget>[
          ThemeSettingsPresetCard(
            title: theme.name,
            subtitle: theme.description.trim().isEmpty
                ? '已保存主题'
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
              itemBuilder: (context) =>
                  const <PopupMenuEntry<_SavedThemeMenuAction>>[
                    PopupMenuItem<_SavedThemeMenuAction>(
                      value: _SavedThemeMenuAction.rename,
                      child: Text('重命名'),
                    ),
                    PopupMenuItem<_SavedThemeMenuAction>(
                      value: _SavedThemeMenuAction.delete,
                      child: Text('删除'),
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
            '还没有已保存主题',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '去详情页右上角三点，使用“保存当前主题”把喜欢的取色存下来。',
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
