import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../desktop/desktop_environment.dart';
import '../../desktop/desktop_floating_panel.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../providers/app_theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_top_tip.dart';
import '../common/app_modal_surface.dart';
import '../common/named_preset_save_dialog.dart';

class DetailMoreActionItem {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool enabled;
  final Future<void> Function(BuildContext context)? onTap;

  const DetailMoreActionItem({
    required this.icon,
    required this.title,
    this.subtitle,
    this.enabled = true,
    this.onTap,
  });
}

Future<void> showDetailMoreActionsSheet(
  BuildContext context, {
  required String pageKey,
  required String pageTitle,
  String? suggestedThemeName,
  bool clearRuntimeBroadcastToMain = true,
  List<DetailMoreActionItem> extraActions = const <DetailMoreActionItem>[],
}) async {
  final snapshot = DynamicPageThemeSnapshot.maybeOf(context);
  final provider = context.read<AppThemeProvider>();
  final colors = context.appColors;
  final dynamicReady = snapshot?.hasDynamicTheme == true;
  final dynamicColors = snapshot?.effectiveColors ?? colors;
  final l10n = AppLocalizations.of(context);

  final actions = <_DetailMoreSheetResult>[
    const _DetailMoreSheetResult(
      kind: _DetailMoreActionKind.saveTheme,
      action: null,
    ),
    ...extraActions.map(
      (item) => _DetailMoreSheetResult(
        kind: _DetailMoreActionKind.extraAction,
        action: item,
      ),
    ),
  ];

  final desktop =
      DesktopEnvironment.isDesktopPlatform &&
      MediaQuery.sizeOf(context).width >= 800;
  final sheetTheme = AppThemeBuilder.buildFromColors(
    colors,
    baseTheme: Theme.of(context),
  );
  Widget buildBody(BuildContext sheetContext) => AppRuntimeColorScope(
    colors: colors,
    hasRuntimeColors: dynamicReady || context.hasRuntimeAppColors,
    child: Theme(
      data: sheetTheme,
      child: Builder(
        builder: (sheetContext) {
          final sheetColors = sheetContext.appColors;
          final sheetL10n = AppLocalizations.of(sheetContext);
          final content = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (!desktop) ...[
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: sheetColors.borderStrong,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      sheetL10n.detailMoreActionsTitle,
                      style: TextStyle(
                        color: sheetColors.textPrimary,
                        fontSize: desktop ? 18 : 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (desktop)
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        sheetContext,
                      ).closeButtonTooltip,
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close_rounded, size: 20),
                      color: sheetColors.textSecondary,
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                pageTitle.trim().isEmpty
                    ? sheetL10n.detailCurrentPage
                    : pageTitle,
                maxLines: desktop ? 2 : null,
                overflow: desktop ? TextOverflow.ellipsis : null,
                style: TextStyle(
                  color: sheetColors.textSecondary,
                  fontSize: 13.5,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              _DetailMoreActionTile(
                desktop: desktop,
                icon: Icons.bookmark_add_outlined,
                title: sheetL10n.detailSaveCurrentTheme,
                subtitle: dynamicReady
                    ? sheetL10n.detailSaveCurrentThemeSubtitle
                    : sheetL10n.detailSaveCurrentThemeUnavailable,
                enabled: dynamicReady,
                onTap: dynamicReady
                    ? () => Navigator.of(sheetContext).pop(actions.first)
                    : null,
              ),
              for (final result in actions.skip(1))
                _DetailMoreActionTile(
                  desktop: desktop,
                  icon: result.action!.icon,
                  title: result.action!.title,
                  subtitle: result.action!.subtitle,
                  enabled: result.action!.enabled,
                  onTap: result.action!.enabled
                      ? () => Navigator.of(sheetContext).pop(result)
                      : null,
                ),
            ],
          );
          if (desktop) {
            return DesktopFloatingPanel(
              key: const ValueKey<String>('desktop-detail-more-panel'),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                  child: content,
                ),
              ),
            );
          }
          return SafeArea(
            top: false,
            child: AppModalSurface(
              key: const ValueKey<String>('app-modal-surface-detail-more'),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
              child: content,
            ),
          );
        },
      ),
    ),
  );
  final selectedAction = await (desktop
      ? showDialog<_DetailMoreSheetResult>(
          context: context,
          useRootNavigator: false,
          barrierColor: colors.overlayScrim.withValues(alpha: 0.20),
          builder: (sheetContext) => Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxWidth: 440),
            child: buildBody(sheetContext),
          ),
        )
      : showModalBottomSheet<_DetailMoreSheetResult>(
          context: context,
          backgroundColor: Colors.transparent,
          barrierColor: colors.overlayScrim,
          builder: buildBody,
        ));

  if (!context.mounted) {
    return;
  }

  if (selectedAction?.kind == _DetailMoreActionKind.saveTheme) {
    final input = await showSaveThemeDialog(
      context,
      initialName: provider.nextSavedThemeNameFromBase(
        l10n.themeCustomBaseName,
      ),
      suggestedName: suggestedThemeName,
    );
    if (!context.mounted || input == null) {
      return;
    }
    await provider.saveThemeSnapshot(
      colors: dynamicColors,
      name: input.name,
      description: input.description,
      pageKey: pageKey,
      clearRuntimeBroadcastToMain: clearRuntimeBroadcastToMain,
    );
    if (!context.mounted) {
      return;
    }
    AppTopTip().show(
      context,
      message: l10n.detailThemeSaved(input.name),
      color: context.appColors.success,
    );
    return;
  }

  if (selectedAction?.kind == _DetailMoreActionKind.extraAction) {
    final action = selectedAction?.action;
    if (action != null && action.enabled && action.onTap != null) {
      await action.onTap!(context);
    }
  }
}

typedef SaveThemeDialogResult = NamedPresetDialogResult;

Future<SaveThemeDialogResult?> showSaveThemeDialog(
  BuildContext context, {
  required String initialName,
  String? suggestedName,
  String initialDescription = '',
  String? existingThemeId,
}) async {
  final provider = context.read<AppThemeProvider>();
  return showNamedPresetSaveDialog(
    context,
    title: AppLocalizations.of(context).detailSaveCurrentTheme,
    initialName: initialName,
    suggestedName: suggestedName,
    initialDescription: initialDescription,
    nameLabel: AppLocalizations.of(context).detailThemeNameLabel,
    descriptionLabel: AppLocalizations.of(context).detailThemeDescriptionLabel,
    validateName: (name) {
      if (!provider.isSavedThemeNameAvailable(
        name,
        excludingId: existingThemeId,
      )) {
        return AppLocalizations.of(context).detailThemeNameDuplicate;
      }
      return null;
    },
  );
}

enum _DetailMoreActionKind { saveTheme, extraAction }

class _DetailMoreSheetResult {
  final _DetailMoreActionKind kind;
  final DetailMoreActionItem? action;

  const _DetailMoreSheetResult({required this.kind, required this.action});
}

class _DetailMoreActionTile extends StatelessWidget {
  final bool desktop;
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool enabled;
  final VoidCallback? onTap;

  const _DetailMoreActionTile({
    required this.desktop,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final textColor = enabled ? colors.textPrimary : colors.textMuted;
    return Opacity(
      opacity: enabled ? 1 : 0.58,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(desktop ? 12 : 18),
        hoverColor: colors.textPrimary.withValues(alpha: 0.05),
        focusColor: colors.selection.withValues(alpha: 0.10),
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: EdgeInsets.all(desktop ? 12 : 14),
          decoration: BoxDecoration(
            color: desktop ? null : appModalTileColor(colors),
            borderRadius: BorderRadius.circular(desktop ? 12 : 18),
            border: desktop
                ? null
                : Border.all(color: appModalTileBorderColor(colors)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: desktop
                      ? colors.accent.withValues(alpha: 0.10)
                      : appModalTileColor(colors, selected: true),
                  borderRadius: BorderRadius.circular(12),
                  border: desktop
                      ? null
                      : Border.all(
                          color: appModalTileBorderColor(
                            colors,
                            selected: true,
                          ),
                        ),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: colors.accentStrong, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        color: textColor,
                        fontSize: desktop ? 14 : 15,
                        fontWeight: desktop ? FontWeight.w600 : FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12.8,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
