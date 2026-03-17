import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String content,
  required String cancelText,
  required String confirmText,
  Color? confirmColor,
}) async {
  final colors = context.appColors;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      final screenWidth = MediaQuery.sizeOf(dialogContext).width;
      final horizontalInset = screenWidth >= 1100
          ? screenWidth * 0.18
          : screenWidth >= 820
          ? screenWidth * 0.14
          : 24.0;
      final maxDialogWidth = screenWidth >= 1100
          ? 720.0
          : screenWidth >= 820
          ? 640.0
          : 560.0;
      return Dialog(
        backgroundColor: colors.surface,
        insetPadding: EdgeInsets.symmetric(horizontal: horizontalInset),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxDialogWidth),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  content,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 30),
                Row(
                  children: [
                    Expanded(
                      child: _DialogActionButton(
                        label: cancelText,
                        backgroundColor: colors.surfaceStrong,
                        foregroundColor: colors.textSecondary,
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _DialogActionButton(
                        label: confirmText,
                        backgroundColor: confirmColor ?? colors.danger,
                        foregroundColor: colors.textPrimary,
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return result ?? false;
}

class _DialogActionButton extends StatelessWidget {
  const _DialogActionButton({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      ),
    );
  }
}
