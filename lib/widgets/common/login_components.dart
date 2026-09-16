import 'package:flutter/material.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import 'bird_loader.dart';

const Color loginAccentColorDark = Color(0xFF567A98);
const Color loginAccentColorLight = Color(0xFF456B86);

Color loginAccentColor(BuildContext context) {
  return Theme.of(context).brightness == Brightness.light
      ? loginAccentColorLight
      : loginAccentColorDark;
}

class LoginSubmitButton extends StatelessWidget {
  const LoginSubmitButton({
    super.key,
    required this.isSubmitting,
    required this.label,
    required this.onPressed,
  });

  final bool isSubmitting;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buttonColor = loginAccentColor(context);
    final buttonForeground =
        ThemeData.estimateBrightnessForColor(buttonColor) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonColor,
          foregroundColor: buttonForeground,
          disabledBackgroundColor: buttonColor.withValues(alpha: 0.45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
          textStyle: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        child: isSubmitting
            ? SizedBox(
                width: 22,
                height: 22,
                child: BirdGlyph(size: 22, color: buttonForeground),
              )
            : Text(label),
      ),
    );
  }
}

class LoginLogoHeader extends StatelessWidget {
  final String title;

  const LoginLogoHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Image.asset(
          'lib/img/app_logo.png',
          width: 44,
          height: 44,
          fit: BoxFit.contain,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                key: const Key('connectionBrandTitle'),
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                AppLocalizations.of(context).connectionTagline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class LoginFormPanel extends StatelessWidget {
  const LoginFormPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: child,
      ),
    );
  }
}

class LoginField extends StatelessWidget {
  const LoginField({
    super.key,
    required this.controller,
    required this.hintText,
    this.labelText,
    this.leadingIcon,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.obscureText = false,
    this.suffix,
    this.onSubmitted,
    this.textFieldKey,
    this.enabled = true,
    this.validator,
  });

  final TextEditingController controller;
  final String hintText;
  final String? labelText;
  final IconData? leadingIcon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool obscureText;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;
  final Key? textFieldKey;
  final bool enabled;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final label = labelText?.trim() ?? '';
    final fieldStyle = TextStyle(
      color: colors.textPrimary,
      fontSize: 16,
      fontWeight: FontWeight.w500,
    );
    final fieldDecoration = InputDecoration(
      labelText: label.isEmpty ? null : label,
      hintText: hintText,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelStyle: TextStyle(
        color: colors.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      hintStyle: TextStyle(
        color: colors.textMuted,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      border: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(vertical: 10),
      suffixIcon: suffix,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: colors.surfaceSubtle,
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Row(
        children: [
          if (leadingIcon != null) ...[
            const SizedBox(width: 18),
            Icon(leadingIcon, color: colors.textMuted, size: 21),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: validator != null
                ? TextFormField(
                    key: textFieldKey,
                    controller: controller,
                    enabled: enabled,
                    obscureText: obscureText,
                    autocorrect: false,
                    enableSuggestions: !obscureText,
                    keyboardType: keyboardType,
                    textInputAction: textInputAction,
                    autofillHints: autofillHints,
                    onFieldSubmitted: onSubmitted,
                    validator: validator,
                    style: fieldStyle,
                    decoration: fieldDecoration,
                  )
                : TextField(
                    enabled: enabled,
                    key: textFieldKey,
                    controller: controller,
                    obscureText: obscureText,
                    keyboardType: keyboardType,
                    textInputAction: textInputAction,
                    autofillHints: autofillHints,
                    onSubmitted: onSubmitted,
                    style: fieldStyle,
                    decoration: fieldDecoration,
                  ),
          ),
        ],
      ),
    );
  }
}
