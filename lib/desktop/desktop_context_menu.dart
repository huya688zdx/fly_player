import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 桌面右键菜单项（移动端长按动作表的桌面形态；动作集合复用
/// media_item_action_sheet_controller，本模块只负责展示与触发）。
class DesktopContextMenuEntry {
  final String label;
  final IconData icon;
  final bool destructive;
  final VoidCallback? onSelected;

  const DesktopContextMenuEntry({
    required this.label,
    required this.icon,
    this.destructive = false,
    this.onSelected,
  });
}

/// 在全局坐标 [position] 弹出桌面右键菜单；点击外部 / Esc 自动关闭。
///
/// 复用 Material [showMenu]，使菜单自动跟随 7 套主题预设与亮暗模式。
Future<void> showDesktopContextMenu(
  BuildContext context, {
  required Offset position,
  required List<DesktopContextMenuEntry> entries,
}) {
  if (entries.isEmpty) return Future<void>.value();
  final RenderBox overlay =
      Overlay.of(context, rootOverlay: true).context.findRenderObject()!
          as RenderBox;
  final theme = Theme.of(context);
  return showMenu<int>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromPoints(position, position),
      Offset.zero & overlay.size,
    ),
    elevation: 8,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
    color: theme.extension<AppThemeColors>()?.surfaceStrong ??
        theme.colorScheme.surface,
    items: [
      for (var i = 0; i < entries.length; i++)
        PopupMenuItem<int>(
          value: i,
          height: 38,
          child: Row(
            children: [
              Icon(
                entries[i].icon,
                size: 16,
                color: entries[i].destructive
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Text(
                entries[i].label,
                style: TextStyle(
                  fontSize: 13,
                  color: entries[i].destructive
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
    ],
  ).then((choice) {
    if (choice == null) return;
    entries[choice].onSelected?.call();
  });
}
