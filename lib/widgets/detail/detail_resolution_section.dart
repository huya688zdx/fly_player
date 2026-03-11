import 'package:flutter/material.dart';

import 'resolution_selector.dart';

class DetailResolutionSection extends StatelessWidget {
  final List<String> options;
  final String? selected;
  final ValueChanged<int>? onSelected;

  const DetailResolutionSection({
    super.key,
    required this.options,
    this.selected,
    this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        ResolutionSelector(
          options: options,
          selected: selected,
          onSelected: onSelected,
        ),
      ],
    );
  }
}

