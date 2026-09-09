import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/common/app_modal_surface.dart';

/// 通用确认弹窗：紧凑桌面尺寸（固定 380 宽内距），标题 + 一句话正文 + 双按钮。
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
      return Dialog(
        backgroundColor: context.appModalBackgroundColor,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  content,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: _DialogActionButton(
                        label: cancelText,
                        backgroundColor: appModalTileColor(colors),
                        foregroundColor: colors.textSecondary,
                        borderColor: appModalTileBorderColor(colors),
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                      ),
                    ),
                    const SizedBox(width: 10),
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
    this.borderColor,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onPressed;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
            side: borderColor == null
                ? BorderSide.none
                : BorderSide(color: borderColor!),
          ),
          textStyle: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}
