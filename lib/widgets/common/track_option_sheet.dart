import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../ui/app_sheet_transitions.dart';
import 'app_modal_surface.dart';

class TrackOptionSheetItem {
  final String id;
  final String title;
  final String subtitle;

  /// 非空时该项显示删除按钮；点击回调后由外部负责移除该项并刷新面板。
  final VoidCallback? onDelete;

  const TrackOptionSheetItem({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.onDelete,
  });
}

class TrackOptionSheet {
  static Future<String?> show(
    BuildContext context, {
    required String title,
    required List<TrackOptionSheetItem> items,
    String? selectedId,
  }) {
    final colors = context.appColors;
    final media = MediaQuery.of(context);
    final isLandscape = media.size.width > media.size.height;
    final body = _TrackOptionSheetBody(
      title: title,
      items: items,
      selectedId: selectedId,
      floating: isLandscape,
    );
    if (isLandscape) {
      return showDialog<String>(
        context: context,
        useRootNavigator: false,
        barrierDismissible: true,
        barrierColor: colors.overlayScrim,
        builder: (_) => body,
      );
    }
    return AppSheetTransitions.showBottomSurface<String>(
      context,
      barrierDismissible: true,
      barrierLabel: title,
      barrierColor: colors.overlayScrim,
      builder: (_) => body,
    );
  }
}

class _TrackOptionSheetBody extends StatelessWidget {
  final String title;
  final List<TrackOptionSheetItem> items;
  final String? selectedId;
  final bool floating;

  const _TrackOptionSheetBody({
    required this.title,
    required this.items,
    required this.selectedId,
    required this.floating,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final media = MediaQuery.of(context);
    final maxHeight = floating
        ? (media.size.height * 0.78).clamp(320.0, 560.0)
        : media.size.height * 0.7;
    final maxWidth = (media.size.width * 0.62).clamp(520.0, 760.0);
    final bottomContentPadding = math.max(
      media.padding.bottom,
      floating ? 22.0 : 18.0,
    );

    final child = SafeArea(
      top: false,
      bottom: false,
      child: AppModalSurface(
        key: const ValueKey<String>('app-modal-surface-track-options'),
        floating: floating,
        padding: EdgeInsets.fromLTRB(
          floating ? 22 : 16,
          floating ? 20 : 16,
          floating ? 22 : 16,
          bottomContentPadding,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: DecoratedBox(
                  key: const ValueKey<String>('track-option-group'),
                  decoration: BoxDecoration(
                    color: appModalTileColor(colors),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: appModalTileBorderColor(colors)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        thickness: 1,
                        indent: 54,
                        color: colors.borderSubtle.withValues(alpha: 0.72),
                      ),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final selected = item.id == selectedId;
                        return _OptionTile(
                          item: item,
                          selected: selected,
                          onTap: () {
                            if (AppSheetTransitions.maybeClose<String>(
                              context,
                              item.id,
                            )) {
                              return;
                            }
                            Navigator.of(context).pop(item.id);
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (floating) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: SizedBox(width: maxWidth, child: child),
      );
    }

    return child;
  }
}

class _OptionTile extends StatelessWidget {
  final TrackOptionSheetItem item;
  final bool selected;
  final VoidCallback onTap;

  const _OptionTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final onDelete = item.onDelete;
    return AnimatedContainer(
      key: ValueKey<String>('track-option-tile-${item.id}'),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected ? appModalTileColor(colors, selected: true) : null,
        border: Border.all(
          color: selected
              ? appModalTileBorderColor(colors, selected: true)
              : Colors.transparent,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
            child: Row(
              children: [
                _SelectionDot(id: item.id, selected: selected),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 16,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          height: 1.25,
                        ),
                      ),
                      if (item.subtitle.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          item.subtitle,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onDelete != null)
                  IconButton(
                    onPressed: onDelete,
                    icon: Icon(
                      Icons.delete_outline,
                      color: colors.textSecondary,
                      size: 19,
                    ),
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).deleteButtonTooltip,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionDot extends StatelessWidget {
  final String id;
  final bool selected;

  const _SelectionDot({required this.id, required this.selected});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final active = colors.selection;
    final inactive = colors.chipBorder;
    return Container(
      key: ValueKey<String>('track-selection-$id'),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: selected ? active : inactive, width: 1.8),
        color: selected ? active : Colors.transparent,
      ),
      child: selected
          ? Icon(Icons.check_rounded, color: colors.textPrimary, size: 14)
          : null,
    );
  }
}
