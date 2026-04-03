import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_top_tip.dart';
import '../common/named_preset_save_dialog.dart';
import 'dynamic_page_theme_scope.dart';

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

  final selectedAction = await showModalBottomSheet<_DetailMoreSheetResult>(
    context: context,
    backgroundColor: colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      final sheetColors = sheetContext.appColors;
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
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
              Text(
                '更多操作',
                style: TextStyle(
                  color: sheetColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                pageTitle.trim().isEmpty ? '当前详情页' : pageTitle,
                style: TextStyle(
                  color: sheetColors.textSecondary,
                  fontSize: 13.5,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              _DetailMoreActionTile(
                icon: Icons.bookmark_add_outlined,
                title: '保存当前主题',
                subtitle: dynamicReady
                    ? '把当前取色保存成一套可复用的自定义主题'
                    : '当前页面还没有可保存的动态取色结果',
                enabled: dynamicReady,
                onTap: dynamicReady
                    ? () => Navigator.of(sheetContext).pop(actions.first)
                    : null,
              ),
              for (final result in actions.skip(1))
                _DetailMoreActionTile(
                  icon: result.action!.icon,
                  title: result.action!.title,
                  subtitle: result.action!.subtitle,
                  enabled: result.action!.enabled,
                  onTap: result.action!.enabled
                      ? () => Navigator.of(sheetContext).pop(result)
                      : null,
                ),
            ],
          ),
        ),
      );
    },
  );

  if (!context.mounted) {
    return;
  }

  if (selectedAction?.kind == _DetailMoreActionKind.saveTheme) {
    final input = await showSaveThemeDialog(
      context,
      initialName: provider.nextSavedThemeName(),
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
      message: '已保存主题：${input.name}',
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
    title: '保存当前主题',
    initialName: initialName,
    suggestedName: suggestedName,
    initialDescription: initialDescription,
    nameLabel: '主题名称',
    descriptionLabel: '说明（可选）',
    validateName: (name) {
      if (!provider.isSavedThemeNameAvailable(
        name,
        excludingId: existingThemeId,
      )) {
        return '主题名称不能重复';
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
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool enabled;
  final VoidCallback? onTap;

  const _DetailMoreActionTile({
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
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.surfaceSubtle,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.borderSubtle),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colors.backgroundElevated,
                  borderRadius: BorderRadius.circular(12),
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
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
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
