import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../ui/app_sheet_transitions.dart';
import 'app_modal_surface.dart';
import 'app_option_list.dart';

class AppCatalogFilterOption {
  final Object value;
  final String label;

  const AppCatalogFilterOption({required this.value, required this.label});
}

class AppCatalogFilterSection {
  final String key;
  final String title;
  final List<AppCatalogFilterOption> options;
  final Set<Object> selectedValues;
  final bool multiSelect;

  const AppCatalogFilterSection({
    required this.key,
    required this.title,
    required this.options,
    this.selectedValues = const <Object>{},
    this.multiSelect = false,
  });
}

class AppCatalogSortOption {
  final String field;
  final String label;

  const AppCatalogSortOption({required this.field, required this.label});
}

class AppCatalogSortResult {
  final String field;
  final String sortType;

  const AppCatalogSortResult({required this.field, required this.sortType});
}

class AppCatalogFilterSheet extends StatefulWidget {
  final List<AppCatalogFilterSection> sections;

  const AppCatalogFilterSheet({super.key, required this.sections});

  static Future<Map<String, Set<Object>>?> show(
    BuildContext context, {
    required List<AppCatalogFilterSection> sections,
  }) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return AppSheetTransitions.showBottomSurface<Map<String, Set<Object>>>(
      context,
      enableDrag: true,
      barrierLabel: l10n.listFilterButton,
      barrierColor: colors.overlayScrim,
      builder: (_) => AppCatalogFilterSheet(sections: sections),
    );
  }

  @override
  State<AppCatalogFilterSheet> createState() => _AppCatalogFilterSheetState();
}

class _AppCatalogFilterSheetState extends State<AppCatalogFilterSheet> {
  late final Map<String, Set<Object>> _selection;

  @override
  void initState() {
    super.initState();
    _selection = <String, Set<Object>>{
      for (final section in widget.sections)
        section.key: Set<Object>.from(section.selectedValues),
    };
  }

  void _select(AppCatalogFilterSection section, Object? value) {
    setState(() {
      final selected = _selection[section.key]!;
      if (value == null) {
        selected.clear();
      } else if (section.multiSelect) {
        if (!selected.add(value)) selected.remove(value);
      } else if (selected.contains(value)) {
        selected.clear();
      } else {
        selected
          ..clear()
          ..add(value);
      }
    });
  }

  void _reset() {
    setState(() {
      for (final values in _selection.values) {
        values.clear();
      }
    });
  }

  void _confirm() {
    AppSheetTransitions.close<Map<String, Set<Object>>>(
      context,
      <String, Set<Object>>{
        for (final entry in _selection.entries)
          entry.key: Set<Object>.from(entry.value),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final media = MediaQuery.of(context);
    final maximum = media.size.height * 0.82;
    final preferred = widget.sections.length <= 2 ? 460.0 : maximum;
    final height = math.min(maximum, preferred);

    return _CatalogSheetFrame(
      surfaceKey: const ValueKey<String>('app-modal-surface-catalog-filter'),
      dragHandleKey: const ValueKey<String>('catalog-filter-drag-handle'),
      title: l10n.listFilterButton,
      height: height,
      actions: Row(
        children: [
          Expanded(
            child: _CatalogSheetButton(
              label: l10n.listFilterResetButton,
              onPressed: _reset,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _CatalogSheetButton(
              label: l10n.commonConfirm,
              primary: true,
              onPressed: _confirm,
            ),
          ),
        ],
      ),
      child: ListView.separated(
        key: const ValueKey<String>('catalog-filter-sections'),
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: widget.sections.length,
        separatorBuilder: (_, __) => const SizedBox(height: 18),
        itemBuilder: (context, index) {
          final section = widget.sections[index];
          final selected = _selection[section.key]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.title,
                style: TextStyle(
                  color: context.appColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _CatalogFilterChip(
                    label: l10n.listFilterAll,
                    selected: selected.isEmpty,
                    onTap: () => _select(section, null),
                  ),
                  for (final option in section.options)
                    _CatalogFilterChip(
                      label: option.label,
                      selected: selected.contains(option.value),
                      onTap: () => _select(section, option.value),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 工具栏下方的内联筛选面板：点击筛选按钮原地展开/收起（AnimatedSize 包裹由
/// 使用方控制），替代弹窗。选项即点即筛选，由 [onOptionSelected] 通知使用方。
class AppCatalogFilterInlinePanel extends StatelessWidget {
  const AppCatalogFilterInlinePanel({
    super.key,
    required this.sections,
    required this.onOptionSelected,
    required this.onCollapse,
  });

  final List<AppCatalogFilterSection> sections;
  final void Function(AppCatalogFilterSection section, Object? value)
  onOptionSelected;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.48,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (var i = 0; i < sections.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(height: 10),
                  _InlineFilterSectionRow(
                    section: sections[i],
                    onOptionSelected: onOptionSelected,
                  ),
                ],
                Center(
                  child: InkWell(
                    onTap: onCollapse,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            l10n.listFilterCollapse,
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Icon(
                            Icons.keyboard_arrow_up_rounded,
                            size: 18,
                            color: colors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineFilterSectionRow extends StatelessWidget {
  const _InlineFilterSectionRow({
    required this.section,
    required this.onOptionSelected,
  });

  final AppCatalogFilterSection section;
  final void Function(AppCatalogFilterSection section, Object? value)
  onOptionSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selected = section.selectedValues;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 84,
          child: Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(
              section.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.appColors.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              _InlineFilterChip(
                label: l10n.listFilterAll,
                selected: selected.isEmpty,
                onTap: () => onOptionSelected(section, null),
              ),
              for (final option in section.options)
                _InlineFilterChip(
                  label: option.label,
                  selected: selected.contains(option.value),
                  onTap: () => onOptionSelected(section, option.value),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InlineFilterChip extends StatelessWidget {
  const _InlineFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final radius = BorderRadius.circular(10);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: appModalTileColor(colors, selected: selected),
            borderRadius: radius,
            border: Border.all(
              color: selected
                  ? appModalTileBorderColor(colors, selected: true)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (selected) ...<Widget>[
                Icon(
                  Icons.check_rounded,
                  size: 14,
                  color: colors.selectionStrong,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? colors.textPrimary : colors.chipText,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppCatalogSortSheet extends StatelessWidget {
  final List<AppCatalogSortOption> options;
  final String selectedField;
  final String sortType;

  const AppCatalogSortSheet({
    super.key,
    required this.options,
    required this.selectedField,
    required this.sortType,
  });

  static Future<AppCatalogSortResult?> show(
    BuildContext context, {
    required List<AppCatalogSortOption> options,
    required String selectedField,
    required String sortType,
  }) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return AppSheetTransitions.showBottomSurface<AppCatalogSortResult>(
      context,
      enableDrag: true,
      barrierLabel: l10n.listSortTitle,
      barrierColor: colors.overlayScrim,
      builder: (_) => AppCatalogSortSheet(
        options: options,
        selectedField: selectedField,
        sortType: sortType,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final media = MediaQuery.of(context);
    final preferred = 126.0 + options.length * 62;
    final height = math.min(media.size.height * 0.72, preferred);

    return AppOptionSheetPanel(
      surfaceKey: const ValueKey<String>('app-modal-surface-catalog-sort'),
      title: l10n.listSortTitle,
      maxHeight: height,
      child: ListView.separated(
        key: const ValueKey<String>('catalog-sort-options'),
        padding: EdgeInsets.zero,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (context, index) {
          final option = options[index];
          final selected = option.field == selectedField;
          return _CatalogSortTile(
            option: option,
            selected: selected,
            sortType: sortType,
            onTap: () {
              final nextType = selected
                  ? (sortType == 'ASC' ? 'DESC' : 'ASC')
                  : 'DESC';
              AppSheetTransitions.close<AppCatalogSortResult>(
                context,
                AppCatalogSortResult(field: option.field, sortType: nextType),
              );
            },
          );
        },
      ),
    );
  }
}

class _CatalogSheetFrame extends StatelessWidget {
  final Key surfaceKey;
  final Key dragHandleKey;
  final String title;
  final double height;
  final Widget child;
  final Widget? actions;

  const _CatalogSheetFrame({
    required this.surfaceKey,
    required this.dragHandleKey,
    required this.title,
    required this.height,
    required this.child,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: AppModalSurface(
        key: surfaceKey,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
            child: Column(
              children: [
                Container(
                  key: dragHandleKey,
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.textMuted.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const SizedBox(width: 40),
                    Expanded(
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => AppSheetTransitions.close(context),
                      icon: Icon(
                        Icons.close_rounded,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(child: child),
                if (actions != null) ...[const SizedBox(height: 12), actions!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CatalogFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final radius = BorderRadius.circular(14);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: appModalTileColor(colors, selected: selected),
            borderRadius: radius,
            border: Border.all(
              color: selected
                  ? appModalTileBorderColor(colors, selected: true)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: colors.selectionStrong,
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? colors.textPrimary : colors.chipText,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogSortTile extends StatelessWidget {
  final AppCatalogSortOption option;
  final bool selected;
  final String sortType;
  final VoidCallback onTap;

  const _CatalogSortTile({
    required this.option,
    required this.selected,
    required this.sortType,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppOptionListTile(
      tileKey: ValueKey<String>('catalog-sort-option-${option.field}'),
      indicatorKey: ValueKey<String>('catalog-sort-selection-${option.field}'),
      title: option.label,
      subtitle: selected
          ? (sortType == 'ASC' ? l10n.listSortAsc : l10n.listSortDesc)
          : '',
      selected: selected,
      onTap: onTap,
    );
  }
}

class _CatalogSheetButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool primary;

  const _CatalogSheetButton({
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll<Size>(Size.fromHeight(50)),
      shape: WidgetStatePropertyAll<RoundedRectangleBorder>(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      textStyle: const WidgetStatePropertyAll<TextStyle>(
        TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    );
    if (primary) {
      return FilledButton(
        onPressed: onPressed,
        style: style,
        child: Text(label),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: style.copyWith(
        foregroundColor: WidgetStatePropertyAll<Color>(colors.textSecondary),
        side: WidgetStatePropertyAll<BorderSide>(
          BorderSide(color: colors.borderSubtle),
        ),
      ),
      child: Text(label),
    );
  }
}
