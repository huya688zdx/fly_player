import 'package:flutter/material.dart';

Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String content,
  required String cancelText,
  required String confirmText,
  Color confirmColor = const Color(0xFF9B002A),
}) async {
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
        backgroundColor: const Color(0xFF171D26),
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  content,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFAAB5C8),
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
                        backgroundColor: const Color(0xFF303946),
                        foregroundColor: const Color(0xFFD7DFEE),
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _DialogActionButton(
                        label: confirmText,
                        backgroundColor: confirmColor,
                        foregroundColor: Colors.white,
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
