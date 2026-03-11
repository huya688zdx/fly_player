import 'package:flutter/material.dart';

import '../../theme/detail_tokens.dart';

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
        barrierColor: const Color(0xBF020812),
        builder: (_) => body,
      );
    }
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
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
    final media = MediaQuery.of(context);
    final maxHeight = floating
        ? (media.size.height * 0.78).clamp(320.0, 560.0)
        : media.size.height * 0.7;
    final maxWidth = (media.size.width * 0.62).clamp(520.0, 760.0);

    final child = SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: DetailTokens.panelBackground,
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
                style: const TextStyle(
                  color: DetailTokens.textPrimary,
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
        child: SizedBox(
          width: maxWidth,
          child: child,
        ),
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
    return Material(
      color: const Color(0xFF2A3441),
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
                      style: const TextStyle(
                        color: DetailTokens.textPrimary,
                        fontSize: 35 / 2,
                        fontWeight: FontWeight.w500,
                        height: 1.15,
                      ),
                    ),
                    if (item.subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        item.subtitle,
                        style: const TextStyle(
                          color: Color(0xFFAFC0D5),
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
    const active = DetailTokens.progressActive;
    const inactive = Color(0xFF4A5F7D);
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: selected ? active : inactive, width: 2.2),
        color: selected ? active : Colors.transparent,
      ),
      child: selected
          ? const Icon(Icons.check, color: Colors.white, size: 16)
          : null,
    );
  }
}
