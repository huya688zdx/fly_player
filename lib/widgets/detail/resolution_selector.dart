import 'package:flutter/material.dart';

import 'detail_tag_chip.dart';

class ResolutionSelector extends StatelessWidget {
  final List<String> options;
  final String? selected;
  final ValueChanged<int>? onSelected;

  const ResolutionSelector({
    super.key,
    required this.options,
    this.selected,
    this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.asMap().entries.map((entry) {
        final index = entry.key;
        final option = entry.value;
        return GestureDetector(
          onTap: onSelected == null ? null : () => onSelected!(index),
          child: DetailTagChip(
            label: option,
            selected: selected != null && selected == '$index:$option',
          ),
        );
      }).toList(),
    );
  }
}
