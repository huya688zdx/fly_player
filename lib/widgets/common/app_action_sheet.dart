import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../ui/app_sheet_transitions.dart';
import 'app_option_list.dart';

class AppActionSheetOption<T> {
  final T value;
  final String label;
  final bool destructive;

  const AppActionSheetOption({
    required this.value,
    required this.label,
    this.destructive = false,
  });
}

Future<T?> showAppActionSheet<T>(
  BuildContext context, {
  required String title,
  required List<AppActionSheetOption<T>> options,
  String? cancelText,
}) async {
  await HapticFeedback.mediumImpact();
  if (!context.mounted) return null;

  final colors = context.appColors;
  final l10n = AppLocalizations.of(context);
  return AppSheetTransitions.showBottomSurface<T>(
    context,
    enableDrag: true,
    barrierDismissible: true,
    barrierLabel: cancelText ?? l10n.commonCancel,
    barrierColor: colors.overlayScrim,
    builder: (_) => _AppActionSheetBody<T>(title: title, options: options),
  );
}

class _AppActionSheetBody<T> extends StatelessWidget {
  const _AppActionSheetBody({required this.title, required this.options});

  final String title;
  final List<AppActionSheetOption<T>> options;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return AppOptionSheetPanel(
      surfaceKey: const ValueKey<String>('app-modal-surface-action-sheet'),
      title: title,
      maxHeight: media.size.height * .72,
      child: ListView.separated(
        key: const ValueKey<String>('action-sheet-options'),
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final option = options[index];
          return AppOptionListTile(
            tileKey: ValueKey<String>('action-sheet-option-$index'),
            indicatorKey: ValueKey<String>('action-sheet-selection-$index'),
            title: option.label,
            destructive: option.destructive,
            showIndicator: false,
            outlined: true,
            onTap: () {
              if (AppSheetTransitions.maybeClose<T>(context, option.value)) {
                return;
              }
              Navigator.of(context).pop(option.value);
            },
          );
        },
      ),
    );
  }
}
