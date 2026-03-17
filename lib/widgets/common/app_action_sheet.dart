import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

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
  String cancelText = '取消',
}) async {
  await HapticFeedback.mediumImpact();
  if (!context.mounted) return null;

  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) {
      final colors = context.appColors;
      final media = MediaQuery.of(context);
      final screenWidth = media.size.width;
      final textScale = media.textScaler.scale(1).clamp(1.0, 1.12);
      final horizontalPadding = (screenWidth * 0.045).clamp(16.0, 22.0);
      final topPadding = (screenWidth * 0.038).clamp(12.0, 16.0);
      final titleFontSize = (screenWidth * 0.052).clamp(17.0, 19.0);
      final titleBottomGap = (screenWidth * 0.046).clamp(16.0, 20.0);
      final buttonHeight = (screenWidth * 0.158).clamp(56.0, 66.0);
      final buttonRadius = (screenWidth * 0.04).clamp(14.0, 17.0);
      final buttonFontSize = (screenWidth * 0.056 * textScale).clamp(
        17.0,
        20.0,
      );
      final buttonGap = (screenWidth * 0.032).clamp(10.0, 14.0);
      final bottomInset = media.padding.bottom > 0
          ? media.padding.bottom
          : 16.0;

      return SafeArea(
        top: false,
        child: Container(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            topPadding,
            horizontalPadding,
            bottomInset,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: colors.borderSubtle),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: media.size.height * 0.82),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: titleBottomGap),
                  for (final option in options) ...[
                    _ActionSheetButton(
                      label: option.label,
                      destructive: option.destructive,
                      height: buttonHeight,
                      radius: buttonRadius,
                      fontSize: buttonFontSize,
                      onTap: () => Navigator.of(context).pop(option.value),
                    ),
                    SizedBox(height: buttonGap),
                  ],
                  _ActionSheetButton(
                    label: cancelText,
                    secondary: true,
                    height: buttonHeight,
                    radius: buttonRadius,
                    fontSize: buttonFontSize,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _ActionSheetButton extends StatelessWidget {
  final String label;
  final bool destructive;
  final bool secondary;
  final double height;
  final double radius;
  final double fontSize;
  final VoidCallback onTap;

  const _ActionSheetButton({
    required this.label,
    required this.onTap,
    required this.height,
    required this.radius,
    required this.fontSize,
    this.destructive = false,
    this.secondary = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final backgroundColor = destructive
        ? colors.danger
        : secondary
        ? colors.surfaceStrong
        : colors.accent;
    final foregroundColor = secondary
        ? colors.textSecondary
        : colors.textPrimary;

    return SizedBox(
      height: height,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
          side: BorderSide(
            color: secondary ? colors.borderSubtle : Colors.transparent,
          ),
          elevation: 0,
          padding: EdgeInsets.zero,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
