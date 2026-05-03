import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';

Future<String?> showBookmarkNoteDialog(
  BuildContext context, {
  String? title,
  String initialValue = '',
}) async {
  final controller = TextEditingController(text: initialValue);
  try {
    return await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final colors = dialogContext.appColors;
        final l10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          backgroundColor: colors.surfaceSubtle,
          title: Text(
            title ?? l10n.bookmarkNoteDialogTitle,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            minLines: 2,
            maxLength: 120,
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: l10n.bookmarkNoteDialogHint,
              hintStyle: TextStyle(color: colors.textMuted),
              filled: true,
              fillColor: colors.backgroundElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: colors.borderSubtle),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: colors.borderSubtle),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: colors.accent),
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: Text(l10n.commonSave),
            ),
          ],
        );
      },
    );
  } finally {
    controller.dispose();
  }
}
