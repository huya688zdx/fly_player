import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../providers/app_locale_provider.dart';
import '../ui/adaptive_text.dart';
import '../ui/secondary_host_navigation.dart';
import '../widgets/common/app_ambient_page.dart';

/// 应用语言子页：选择后立即保存，保留页面以显示当前选中项。
class LanguageSettingsScreen extends StatelessWidget {
  const LanguageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = context.watch<AppLocaleProvider>();
    return AppAmbientPage(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: buildSecondaryHostAppBar(
          context,
          title: Text(l10n.settingsLanguageTitle),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: <Widget>[
              _LanguageOptionTile(
                mode: AppLocaleMode.system,
                groupValue: locale.mode,
                title: l10n.languageSystem,
                subtitle: l10n.languageSystemSubtitle,
                onSelected: () =>
                    unawaited(locale.setMode(AppLocaleMode.system)),
              ),
              const SizedBox(height: 8),
              _LanguageOptionTile(
                mode: AppLocaleMode.zhCN,
                groupValue: locale.mode,
                title: l10n.languageZhCN,
                subtitle: l10n.languageZhCNSubtitle,
                onSelected: () => unawaited(locale.setMode(AppLocaleMode.zhCN)),
              ),
              const SizedBox(height: 8),
              _LanguageOptionTile(
                mode: AppLocaleMode.en,
                groupValue: locale.mode,
                title: l10n.languageEn,
                subtitle: l10n.languageEnSubtitle,
                onSelected: () => unawaited(locale.setMode(AppLocaleMode.en)),
              ),
              const SizedBox(height: 8),
              _LanguageOptionTile(
                mode: AppLocaleMode.ja,
                groupValue: locale.mode,
                title: l10n.languageJa,
                subtitle: l10n.languageJaSubtitle,
                onSelected: () => unawaited(locale.setMode(AppLocaleMode.ja)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageOptionTile extends StatelessWidget {
  final AppLocaleMode mode;
  final AppLocaleMode groupValue;
  final String title;
  final String subtitle;
  final VoidCallback onSelected;

  const _LanguageOptionTile({
    required this.mode,
    required this.groupValue,
    required this.title,
    required this.subtitle,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppAmbientPage.controlColorsOf(context);
    final selected = mode == groupValue;
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onTap: onSelected,
      selected: selected,
      selectedTileColor: colors.selection.withValues(alpha: 0.08),
      leading: Icon(
        selected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_off_rounded,
        color: selected ? colors.accent : colors.textMuted,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: AdaptiveText.roleSize(15.5),
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: colors.textSecondary,
          fontSize: AdaptiveText.roleSize(13),
        ),
      ),
    );
  }
}
