import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../ui/app_sheet_transitions.dart';
import 'app_option_list.dart';

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
    final child = AppOptionSheetPanel(
      surfaceKey: const ValueKey<String>('app-modal-surface-track-options'),
      title: title,
      floating: floating,
      maxHeight: maxHeight,
      child: ListView.separated(
        key: const ValueKey<String>('track-option-group'),
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (context, index) {
          final item = items[index];
          final selected = item.id == selectedId;
          return AppOptionListTile(
            tileKey: ValueKey<String>('track-option-tile-${item.id}'),
            indicatorKey: ValueKey<String>('track-selection-${item.id}'),
            title: item.title,
            subtitle: item.subtitle,
            selected: selected,
            trailing: item.onDelete == null
                ? null
                : IconButton(
                    onPressed: item.onDelete,
                    icon: Icon(
                      Icons.delete_outline,
                      color: colors.textSecondary,
                      size: 19,
                    ),
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).deleteButtonTooltip,
                  ),
            onTap: () {
              if (AppSheetTransitions.maybeClose<String>(context, item.id)) {
                return;
              }
              Navigator.of(context).pop(item.id);
            },
          );
        },
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
