import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../ui/app_sheet_transitions.dart';

class TrackOptionSheetItem {
  final String id;
  final String title;
  final String subtitle;

  const TrackOptionSheetItem({
    required this.id,
    required this.title,
    this.subtitle = '',
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

    final child = SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.vertical(
            top: const Radius.circular(24),
            bottom: Radius.circular(floating ? 24 : 0),
          ),
        ),
        padding: EdgeInsets.fromLTRB(
          floating ? 22 : 16,
          floating ? 20 : 12,
          floating ? 22 : 16,
          floating ? 22 : 18,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final selected = item.id == selectedId;
                    return _OptionTile(
                      item: item,
                      selected: selected,
                      onTap: () => Navigator.of(context).pop(item.id),
                    );
                  },
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
    return Material(
      color: colors.surfaceSubtle,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
          child: Row(
            children: [
              _SelectionDot(selected: selected),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 35 / 2,
                        fontWeight: FontWeight.w500,
                        height: 1.15,
                      ),
                    ),
                    if (item.subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        item.subtitle,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 30 / 2,
                          fontWeight: FontWeight.w500,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionDot extends StatelessWidget {
  final bool selected;

  const _SelectionDot({required this.selected});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final active = colors.selection;
    final inactive = colors.chipBorder;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: selected ? active : inactive, width: 2.2),
        color: selected ? active : Colors.transparent,
      ),
      child: selected
          ? Icon(Icons.check, color: colors.textPrimary, size: 16)
          : null,
    );
  }
}
