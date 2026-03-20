import 'package:flutter/material.dart';

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
  String nameLabel = '名称',
  String descriptionLabel = '描述',
  String emptyNameErrorText = '请输入名称',
  String confirmLabel = '保存',
  int maxNameLength = 32,
  String? Function(String name)? validateName,
}) {
  return showDialog<NamedPresetDialogResult>(
    context: context,
    builder: (_) => _NamedPresetSaveDialog(
      title: title,
      initialName: initialName,
      suggestedName: suggestedName,
      initialDescription: initialDescription,
      nameLabel: nameLabel,
      descriptionLabel: descriptionLabel,
      emptyNameErrorText: emptyNameErrorText,
      confirmLabel: confirmLabel,
      maxNameLength: maxNameLength,
      validateName: validateName,
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
    final suggestedName = widget.suggestedName?.trim() ?? '';
    return AlertDialog(
      backgroundColor: colors.surfaceSubtle,
      title: Text(
        widget.title,
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: SizedBox(
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
                          child: const Text('自动填入'),
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
                hintText: '可选，简单写一下这个预设的用途',
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
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
