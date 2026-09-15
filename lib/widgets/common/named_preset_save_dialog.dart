import 'package:flutter/material.dart';

import '../../desktop/desktop_environment.dart';
import '../../desktop/desktop_floating_panel.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';

class NamedPresetDialogResult {
  final String name;
  final String description;

  const NamedPresetDialogResult({
    required this.name,
    required this.description,
  });
}

Future<NamedPresetDialogResult?> showNamedPresetSaveDialog(
  BuildContext context, {
  required String title,
  required String initialName,
  String? suggestedName,
  String initialDescription = '',
  String? nameLabel,
  String? descriptionLabel,
  String? emptyNameErrorText,
  String? confirmLabel,
  int maxNameLength = 32,
  String? Function(String name)? validateName,
}) {
  final colors = context.appColors;
  final desktop =
      DesktopEnvironment.isDesktopPlatform &&
      MediaQuery.sizeOf(context).width >= 800;
  final dialogTheme = AppThemeBuilder.buildFromColors(
    colors,
    baseTheme: Theme.of(context),
  );
  return showDialog<NamedPresetDialogResult>(
    context: context,
    barrierColor: desktop
        ? colors.overlayScrim.withValues(alpha: 0.20)
        : Colors.black54,
    builder: (_) => AppRuntimeColorScope(
      colors: colors,
      hasRuntimeColors: context.hasRuntimeAppColors,
      child: Theme(
        data: dialogTheme,
        child: _NamedPresetSaveDialog(
          title: title,
          initialName: initialName,
          suggestedName: suggestedName,
          initialDescription: initialDescription,
          nameLabel: nameLabel ?? AppLocalizations.of(context).presetNameLabel,
          descriptionLabel:
              descriptionLabel ??
              AppLocalizations.of(context).presetDescriptionLabel,
          emptyNameErrorText:
              emptyNameErrorText ??
              AppLocalizations.of(context).presetNameRequired,
          confirmLabel: confirmLabel ?? AppLocalizations.of(context).commonSave,
          maxNameLength: maxNameLength,
          validateName: validateName,
        ),
      ),
    ),
  );
}

class _NamedPresetSaveDialog extends StatefulWidget {
  final String title;
  final String initialName;
  final String? suggestedName;
  final String initialDescription;
  final String nameLabel;
  final String descriptionLabel;
  final String emptyNameErrorText;
  final String confirmLabel;
  final int maxNameLength;
  final String? Function(String name)? validateName;

  const _NamedPresetSaveDialog({
    required this.title,
    required this.initialName,
    required this.suggestedName,
    required this.initialDescription,
    required this.nameLabel,
    required this.descriptionLabel,
    required this.emptyNameErrorText,
    required this.confirmLabel,
    required this.maxNameLength,
    required this.validateName,
  });

  @override
  State<_NamedPresetSaveDialog> createState() => _NamedPresetSaveDialogState();
}

class _NamedPresetSaveDialogState extends State<_NamedPresetSaveDialog> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.initialName,
  );
  late final TextEditingController _descriptionController =
      TextEditingController(text: widget.initialDescription);
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _applySuggestedName() {
    final suggested = widget.suggestedName?.trim() ?? '';
    if (suggested.isEmpty) return;
    _nameController.text = suggested;
    _nameController.selection = TextSelection.fromPosition(
      TextPosition(offset: _nameController.text.length),
    );
    if (_errorText != null) {
      setState(() => _errorText = null);
    }
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = widget.emptyNameErrorText);
      return;
    }
    final validationError = widget.validateName?.call(name);
    if (validationError != null && validationError.trim().isNotEmpty) {
      setState(() => _errorText = validationError);
      return;
    }
    Navigator.of(context).pop(
      NamedPresetDialogResult(
        name: name,
        description: _descriptionController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final desktop =
        DesktopEnvironment.isDesktopPlatform &&
        MediaQuery.sizeOf(context).width >= 800;
    final suggestedName = widget.suggestedName?.trim() ?? '';
    final title = Text(
      widget.title,
      style: TextStyle(
        color: colors.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    );
    final content = SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _nameController,
            autofocus: true,
            maxLength: widget.maxNameLength,
            onChanged: (_) {
              if (_errorText != null) {
                setState(() => _errorText = null);
              }
            },
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              labelText: widget.nameLabel,
              errorText: _errorText,
              suffixIcon: suggestedName.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: TextButton(
                        onPressed: _applySuggestedName,
                        child: Text(l10n.presetAutoFill),
                      ),
                    )
                  : null,
              suffixIconConstraints: const BoxConstraints(
                minWidth: 88,
                minHeight: 40,
              ),
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
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            maxLines: 3,
            minLines: 2,
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              labelText: widget.descriptionLabel,
              hintText: l10n.presetDescriptionHint,
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
        ],
      ),
    );
    final actions = <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l10n.commonCancel),
      ),
      FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
    ];
    if (desktop) {
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 440),
        child: DesktopFloatingPanel(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: title),
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 20),
                      color: colors.textSecondary,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Flexible(child: SingleChildScrollView(child: content)),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  spacing: 8,
                  children: actions,
                ),
              ],
            ),
          ),
        ),
      );
    }
    return AlertDialog(
      backgroundColor: context.appModalBackgroundColor,
      title: title,
      content: content,
      actions: actions,
    );
  }
}
