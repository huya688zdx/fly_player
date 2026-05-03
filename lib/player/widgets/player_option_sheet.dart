import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../ui/app_sheet_transitions.dart';

class PlayerOptionSheetItem {
  final String id;
  final String title;
  final String subtitle;
  final String? badgeText;
  final IconData? trailingIcon;
  final VoidCallback? onTrailingTap;

  const PlayerOptionSheetItem({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.badgeText,
    this.trailingIcon,
    this.onTrailingTap,
  });
}

class PlayerOptionSheetAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const PlayerOptionSheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

class PlayerOptionSheet {
  static Future<String?> show(
    BuildContext context, {
    required String title,
    required List<PlayerOptionSheetItem> items,
    String? selectedId,
    String? sectionLabel,
    List<PlayerOptionSheetAction> headerActions =
        const <PlayerOptionSheetAction>[],
    bool centeredTitle = false,
    bool useCardStyle = false,
  }) {
    return AppSheetTransitions.showAdaptiveSheet<String>(
      context,
      barrierDismissible: true,
      barrierLabel: title,
      barrierColor: Colors.transparent,
      builder: (_) {
        return _PlayerOptionDrawer(
          title: title,
          items: items,
          selectedId: selectedId,
          sectionLabel: sectionLabel,
          headerActions: headerActions,
          centeredTitle: centeredTitle,
          useCardStyle: useCardStyle,
        );
      },
    );
  }
}

class _PlayerOptionDrawer extends StatelessWidget {
  final String title;
  final List<PlayerOptionSheetItem> items;
  final String? selectedId;
  final String? sectionLabel;
  final List<PlayerOptionSheetAction> headerActions;
  final bool centeredTitle;
  final bool useCardStyle;

  const _PlayerOptionDrawer({
    required this.title,
    required this.items,
    required this.selectedId,
    required this.sectionLabel,
    required this.headerActions,
    required this.centeredTitle,
    required this.useCardStyle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final media = MediaQuery.of(context);
    final drawerWidth = _drawerWidth(media.size);
    final isLandscape = media.size.width > media.size.height;
    final topInset = isLandscape ? 0.0 : null;
    const bottomInset = 0.0;
    const sideInset = 0.0;
    final sheetHeight = isLandscape
        ? null
        : math.max(300.0, media.size.height * 0.45);
    const borderRadius = BorderRadius.zero;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => AppSheetTransitions.close(context),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            top: topInset,
            left: isLandscape ? null : sideInset,
            right: sideInset,
            bottom: bottomInset,
            width: isLandscape ? drawerWidth : null,
            height: sheetHeight,
            child: ClipRRect(
              borderRadius: borderRadius,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  color: Color.alphaBlend(
                    colors.surface.withValues(alpha: isLandscape ? 0.88 : 0.94),
                    colors.overlayScrim.withValues(
                      alpha: isLandscape ? 0.22 : 0.34,
                    ),
                  ),
                  border: isLandscape
                      ? Border.all(color: colors.borderSubtle)
                      : null,
                ),
                child: _DrawerBody(
                  title: title,
                  items: items,
                  selectedId: selectedId,
                  sectionLabel: sectionLabel,
                  headerActions: headerActions,
                  landscape: isLandscape,
                  centeredTitle: centeredTitle,
                  useCardStyle: useCardStyle,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _drawerWidth(Size size) {
    final screenWidth = size.width;
    final screenHeight = size.height;
    final isLandscape = screenWidth > screenHeight;

    if (!isLandscape) {
      return math.min(screenWidth - 24, math.max(320, screenWidth * 0.84));
    }

    if (screenWidth >= 1400) {
      return math.min(460, math.max(360, screenWidth * 0.31));
    }
    if (screenWidth >= 1000) {
      return math.min(430, math.max(340, screenWidth * 0.33));
    }
    return math.min(400, math.max(320, screenWidth * 0.38));
  }
}

class _DrawerBody extends StatelessWidget {
  final String title;
  final List<PlayerOptionSheetItem> items;
  final String? selectedId;
  final String? sectionLabel;
  final List<PlayerOptionSheetAction> headerActions;
  final bool landscape;
  final bool centeredTitle;
  final bool useCardStyle;

  const _DrawerBody({
    required this.title,
    required this.items,
    required this.selectedId,
    required this.sectionLabel,
    required this.headerActions,
    required this.landscape,
    required this.centeredTitle,
    required this.useCardStyle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        landscape ? 18 : 16,
        landscape ? math.max(MediaQuery.of(context).padding.top, 16) : 16,
        landscape ? 12 : 16,
        landscape
            ? math.max(MediaQuery.of(context).padding.bottom, 14)
            : math.max(MediaQuery.of(context).padding.bottom, 10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: centeredTitle ? 0 : 2),
                  child: Text(
                    title,
                    textAlign: centeredTitle
                        ? TextAlign.center
                        : TextAlign.start,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: centeredTitle
                          ? (landscape ? 20 : 18)
                          : (landscape ? 18 : 16),
                      fontWeight: FontWeight.w700,
                      height: 1.08,
                    ),
                  ),
                ),
              ),
              if (headerActions.isNotEmpty)
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: headerActions
                      .map((action) => _HeaderActionChip(action: action))
                      .toList(),
                ),
            ],
          ),
          SizedBox(height: landscape ? 14 : 10),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: items.length,
              separatorBuilder: (_, __) => SizedBox(
                height: useCardStyle
                    ? (landscape ? 12 : 10)
                    : (landscape ? 12 : 0),
              ),
              itemBuilder: (context, index) {
                final item = items[index];
                return _DrawerOptionTile(
                  item: item,
                  selected: item.id == selectedId,
                  landscape: landscape,
                  useCardStyle: useCardStyle,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderActionChip extends StatelessWidget {
  final PlayerOptionSheetAction action;

  const _HeaderActionChip({required this.action});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.backgroundElevated.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.borderStrong),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, color: colors.textPrimary, size: 18),
              const SizedBox(width: 6),
              Text(
                action.label,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerOptionTile extends StatelessWidget {
  final PlayerOptionSheetItem item;
  final bool selected;
  final bool landscape;
  final bool useCardStyle;

  const _DrawerOptionTile({
    required this.item,
    required this.selected,
    required this.landscape,
    required this.useCardStyle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final effectiveCardStyle = useCardStyle || landscape;
    final titleColor = colors.textPrimary;
    final subtitleColor = selected ? colors.textSecondary : colors.textMuted;
    final tileRadius = effectiveCardStyle
        ? BorderRadius.circular(18)
        : (selected ? BorderRadius.circular(12) : BorderRadius.zero);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => AppSheetTransitions.close(context, item.id),
        borderRadius: tileRadius,
        child: Ink(
          padding: EdgeInsets.symmetric(
            horizontal: effectiveCardStyle ? 14 : 0,
            vertical: effectiveCardStyle ? 14 : 8,
          ),
          decoration: BoxDecoration(
            color: effectiveCardStyle
                ? (selected
                      ? colors.selectionSoft
                      : colors.surface.withValues(alpha: 0.64))
                : (selected ? colors.selectionSoft : Colors.transparent),
            borderRadius: tileRadius,
            border: effectiveCardStyle
                ? Border.all(
                    color: selected ? colors.selection : colors.borderSubtle,
                    width: selected ? 1.2 : 0.9,
                  )
                : (selected
                      ? Border.all(color: colors.selection, width: 1.1)
                      : const Border(
                          bottom: BorderSide(
                            color: Color(0x1FFFFFFF),
                            width: 0.6,
                          ),
                        )),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _SelectionMarker(selected: selected),
              SizedBox(width: landscape ? 12 : 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          item.title,
                          style: TextStyle(
                            color: titleColor,
                            fontSize: landscape ? 14.5 : 15,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                        if ((item.badgeText ?? '').trim().isNotEmpty)
                          _OptionBadge(label: item.badgeText!.trim()),
                      ],
                    ),
                    if (item.subtitle.trim().isNotEmpty) ...[
                      SizedBox(height: landscape ? 2 : 3),
                      Text(
                        item.subtitle,
                        style: TextStyle(
                          color: subtitleColor,
                          fontSize: landscape ? 11.5 : 11,
                          fontWeight: FontWeight.w500,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (item.trailingIcon != null) ...[
                const SizedBox(width: 12),
                _TrailingActionButton(
                  icon: item.trailingIcon!,
                  onTap: item.onTrailingTap,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionBadge extends StatelessWidget {
  final String label;

  const _OptionBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: colors.chipBackground,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.chipText,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}

class _SelectionMarker extends StatelessWidget {
  final bool selected;

  const _SelectionMarker({required this.selected});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? colors.selection : Colors.transparent,
        border: Border.all(
          color: selected ? colors.selection : colors.chipBorder,
          width: 2,
        ),
      ),
      child: selected
          ? Icon(Icons.check_rounded, color: colors.textPrimary, size: 16)
          : null,
    );
  }
}

class _TrailingActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _TrailingActionButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon),
      color: colors.textSecondary,
      splashRadius: 16,
      iconSize: 20,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
    );
  }
}
