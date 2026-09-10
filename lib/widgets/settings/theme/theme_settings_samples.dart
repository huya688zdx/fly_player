import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../ui/adaptive_text.dart';
import 'theme_settings_helpers.dart';

class ThemeSettingsBackgroundSample extends StatelessWidget {
  final AppThemeColors colors;

  const ThemeSettingsBackgroundSample({super.key, required this.colors});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: _ThemeSampleSwatch(
            title: l10n.themeSamplePage,
            color: colors.backgroundBase,
            borderColor: colors.borderSubtle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ThemeSampleSwatch(
            title: l10n.themeSampleCard,
            color: colors.surface,
            borderColor: colors.borderSubtle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ThemeSampleSwatch(
            title: l10n.themeSampleBottomBar,
            color: colors.navBarBackground,
            borderColor: colors.borderSubtle,
          ),
        ),
      ],
    );
  }
}

class ThemeSettingsActionSample extends StatelessWidget {
  final AppThemeColors colors;

  const ThemeSettingsActionSample({super.key, required this.colors});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  l10n.themeSampleContinuePlay,
                  style: TextStyle(
                    color: themeSettingsForegroundOn(colors.accent),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: colors.surfaceStrong,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.borderSubtle),
                ),
                alignment: Alignment.center,
                child: Text(
                  l10n.themeSampleSecondaryAction,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 6,
          decoration: BoxDecoration(
            color: colors.accentSoft,
            borderRadius: BorderRadius.circular(999),
          ),
          child: FractionallySizedBox(
            widthFactor: 0.58,
            alignment: Alignment.centerLeft,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ThemeSettingsSelectionSample extends StatelessWidget {
  final AppThemeColors colors;

  const ThemeSettingsSelectionSample({super.key, required this.colors});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: colors.selectionSoft,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.selection),
          ),
          child: Text(
            l10n.themeSampleSelected,
            style: TextStyle(
              color: colors.selectionStrong,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: colors.surfaceStrong,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.borderSubtle),
          ),
          child: Text(
            l10n.themeSampleUnselected,
            style: TextStyle(
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class ThemeSettingsLinkSample extends StatelessWidget {
  final AppThemeColors colors;

  const ThemeSettingsLinkSample({super.key, required this.colors});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: <Widget>[
        Text(
          l10n.themePreviewMore,
          style: TextStyle(
            color: colors.link,
            fontWeight: FontWeight.w700,
            fontSize: AdaptiveText.roleSize(14),
          ),
        ),
        const SizedBox(width: 8),
        Container(width: 1, height: 14, color: colors.borderSubtle),
        const SizedBox(width: 8),
        Icon(Icons.open_in_new_rounded, color: colors.link, size: 18),
        const SizedBox(width: 8),
        Text(
          l10n.themeSampleViewDetails,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: AdaptiveText.roleSize(13.2),
          ),
        ),
      ],
    );
  }
}

class _ThemeSampleSwatch extends StatelessWidget {
  final String title;
  final Color color;
  final Color borderColor;

  const _ThemeSampleSwatch({
    required this.title,
    required this.color,
    required this.borderColor,
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
            color: colors.textMuted,
            fontSize: AdaptiveText.roleSize(11.5),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
        ),
      ],
    );
  }
}
