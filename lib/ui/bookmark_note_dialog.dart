import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

Future<String?> showBookmarkNoteDialog(
  BuildContext context, {
  String title = '书签备注',
  String initialValue = '',
}) async {
  final controller = TextEditingController(text: initialValue);
  try {
    return await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final colors = dialogContext.appColors;
        return AlertDialog(
          backgroundColor: colors.surfaceSubtle,
          title: Text(
            title,
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
              hintText: '记录这个书签的作用，比如名场面、关键转折、复习点',
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
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  } finally {
    controller.dispose();
  }
}
