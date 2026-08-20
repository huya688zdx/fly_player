import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/generated/app_localizations.dart';
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
  String? cancelText,
}) async {
  await HapticFeedback.mediumImpact();
  if (!context.mounted) return null;

  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) {
      final colors = context.appColors;
      final l10n = AppLocalizations.of(context);
      final media = MediaQuery.of(context);
      final screenWidth = media.size.width;
      final inheritedScale = media.textScaler.scale(1);
      final columns = screenWidth >= 360 && inheritedScale < 1.3 ? 2 : 1;
      final horizontalPadding = (screenWidth * 0.045).clamp(16.0, 22.0);
      final topPadding = (screenWidth * 0.038).clamp(12.0, 16.0);
      final titleFontSize = (screenWidth * 0.052).clamp(17.0, 19.0);
      final titleBottomGap = (screenWidth * 0.046).clamp(16.0, 20.0);
      final scaledButtonText = media.textScaler.scale(16);
      final buttonHeight = columns == 1
          ? math.max(50.0, scaledButtonText * 2.6).toDouble()
          : 50.0;
      final buttonRadius = (screenWidth * 0.04).clamp(14.0, 17.0);
      const buttonFontSize = 16.0;
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
                  GridView.builder(
                    key: ValueKey('action-sheet-grid-$columns'),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent: buttonHeight,
                      crossAxisSpacing: buttonGap,
                      mainAxisSpacing: buttonGap,
                    ),
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options[index];
                      return _ActionSheetButton(
                        label: option.label,
                        destructive: option.destructive,
                        height: buttonHeight,
                        radius: buttonRadius,
                        fontSize: buttonFontSize,
                        onTap: () => Navigator.of(context).pop(option.value),
                      );
                    },
                  ),
                  SizedBox(height: buttonGap),
                  _ActionSheetButton(
                    label: cancelText ?? l10n.commonCancel,
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
        ? Color.alphaBlend(
            colors.danger.withValues(alpha: .14),
            colors.surfaceStrong,
          )
        : colors.surfaceStrong;
    final foregroundColor = destructive
        ? (ThemeData.estimateBrightnessForColor(backgroundColor) ==
                  Brightness.dark
              ? Colors.white
              : const Color(0xFF1B1B1B))
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
