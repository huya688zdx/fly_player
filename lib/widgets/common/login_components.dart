import 'package:flutter/material.dart';
import '../../desktop/desktop_environment.dart';
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
    this.accountStyle = false,
    this.busyLabel,
  });

  final bool isSubmitting;
  final String label;
  final VoidCallback? onPressed;
  final bool accountStyle;
  final String? busyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buttonColor = accountStyle
        ? context.appColors.accentStrong
        : loginAccentColor(context);
    final buttonForeground =
        ThemeData.estimateBrightnessForColor(buttonColor) == Brightness.dark
        ? Colors.white
        : Colors.black;
    final button = ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: buttonColor,
        foregroundColor: buttonForeground,
        disabledBackgroundColor: buttonColor.withValues(alpha: 0.45),
        disabledForegroundColor: accountStyle ? buttonForeground : null,
        minimumSize: accountStyle ? const Size(0, 52) : null,
        padding: accountStyle
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 14)
            : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(accountStyle ? 11 : 14),
        ),
        elevation: 0,
        textStyle: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      child: accountStyle
          ? Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isSubmitting) ...[
                  BirdGlyph(size: 20, color: buttonForeground),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Text(
                    isSubmitting ? busyLabel ?? label : label,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            )
          : isSubmitting
          ? SizedBox(
              width: 22,
              height: 22,
              child: BirdGlyph(size: 22, color: buttonForeground),
            )
          : Text(label),
    );
    return accountStyle ? button : SizedBox(height: 52, child: button);
  }
}

class LoginPageShell extends StatelessWidget {
  const LoginPageShell({super.key, required this.child, required this.flyMode});

  final Widget child;
  final bool flyMode;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop =
            DesktopEnvironment.isDesktopPlatform && constraints.maxWidth >= 900;
        final pagePadding = desktop ? 32.0 : 20.0;
        final content = desktop
            ? ClipRRect(
                borderRadius: BorderRadius.circular(23),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(23),
                    border: Border.all(color: colors.borderSubtle),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: 0.43,
                            heightFactor: 1,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Color.alphaBlend(
                                  colors.accent.withValues(alpha: 0.07),
                                  colors.surfaceSubtle,
                                ),
                                border: Border(
                                  right: BorderSide(color: colors.borderSubtle),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 43,
                            child: Padding(
                              key: Key(
                                flyMode
                                    ? 'flyLoginDesktopBrand'
                                    : 'connectionWideBrandPane',
                              ),
                              padding: const EdgeInsets.all(40),
                              child: _LoginBrand(flyMode: flyMode),
                            ),
                          ),
                          Expanded(
                            flex: 57,
                            child: Padding(
                              key: Key(
                                flyMode
                                    ? 'flyLoginDesktopForm'
                                    : 'connectionWideFormPane',
                              ),
                              padding: const EdgeInsets.all(32),
                              child: child,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            : child;
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.all(pagePadding),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - pagePadding * 2).clamp(
                0.0,
                double.infinity,
              ),
            ),
            child: Align(
              alignment: desktop ? Alignment.center : Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: desktop ? 1104 : 526),
                child: content,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LoginBrand extends StatelessWidget {
  const _LoginBrand({required this.flyMode});

  final bool flyMode;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LoginLogoHeader(title: l10n.connectionAppName),
        const SizedBox(height: 48),
        Text(
          flyMode ? l10n.accountBrandFlyTitle : l10n.accountBrandDirectTitle,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 32,
            height: 1.4,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          flyMode
              ? l10n.accountBrandFlyDescription
              : l10n.accountBrandDirectDescription,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 14,
            height: 1.8,
          ),
        ),
        const SizedBox(height: 48),
        Icon(
          flyMode ? Icons.account_tree_outlined : Icons.dns_outlined,
          color: colors.accentStrong,
          size: 28,
        ),
        const SizedBox(height: 16),
        Text(
          flyMode ? l10n.accountBrandFlyPath : l10n.accountBrandDirectPath,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 14,
            height: 1.8,
          ),
        ),
      ],
    );
  }
}

class LoginConnectionModeBar extends StatelessWidget {
  const LoginConnectionModeBar({
    super.key,
    required this.flyMode,
    required this.onSwitch,
  });

  final bool flyMode;
  final VoidCallback? onSwitch;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    Widget option({
      required bool fly,
      required String label,
      required IconData icon,
    }) {
      final selected = flyMode == fly;
      return Expanded(
        child: Semantics(
          selected: selected,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? colors.accentStrong : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: TextButton(
              key: !flyMode && fly
                  ? const Key('connectionSwitchToFlyAccount')
                  : null,
              onPressed: selected ? null : onSwitch,
              style: TextButton.styleFrom(
                foregroundColor: colors.textSecondary,
                disabledForegroundColor: selected
                    ? colors.textPrimary
                    : colors.textMuted,
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
                shape: const RoundedRectangleBorder(),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                  Flexible(child: Text(label, textAlign: TextAlign.center)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          option(
            fly: true,
            label: l10n.accountConnectionFlyMode,
            icon: Icons.person_outline_rounded,
          ),
          option(
            fly: false,
            label: l10n.accountConnectionDirectMode,
            icon: Icons.account_tree_outlined,
          ),
        ],
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
    this.externalLabel = false,
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
  final bool externalLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final label = labelText?.trim() ?? '';
    final fieldStyle = TextStyle(
      color: enabled || !externalLabel ? colors.textPrimary : colors.textMuted,
      fontSize: externalLabel ? 14 : 16,
      fontWeight: FontWeight.w500,
    );
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: colors.borderSubtle),
    );
    final fieldDecoration = InputDecoration(
      labelText: externalLabel || label.isEmpty ? null : label,
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
      border: externalLabel ? outline : InputBorder.none,
      enabledBorder: externalLabel ? outline : null,
      focusedBorder: externalLabel
          ? outline.copyWith(
              borderSide: BorderSide(color: colors.accentStrong, width: 1.5),
            )
          : null,
      disabledBorder: externalLabel ? outline : null,
      filled: externalLabel ? true : null,
      fillColor: externalLabel ? colors.surfaceSubtle : null,
      constraints: externalLabel ? const BoxConstraints(minHeight: 48) : null,
      contentPadding: externalLabel
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 14)
          : const EdgeInsets.symmetric(vertical: 10),
      prefixIcon: externalLabel && leadingIcon != null
          ? Icon(leadingIcon, color: colors.textMuted, size: 20)
          : null,
      suffixIcon: suffix,
    );
    final field = validator != null
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
          );
    if (externalLabel) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label.isNotEmpty) ...[
            Text(
              label,
              style: TextStyle(
                color: enabled ? colors.textSecondary : colors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Semantics(label: label, child: field),
        ],
      );
    }
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
          Expanded(child: field),
        ],
      ),
    );
  }
}
