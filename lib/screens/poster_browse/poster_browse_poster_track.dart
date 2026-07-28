import 'package:flutter/material.dart';

import '../../media_backend/media_image_request.dart';
import 'poster_browse_display_item.dart';
import 'poster_browse_poster_card.dart';

class PosterBrowsePosterTrack extends StatelessWidget {
  final List<PosterBrowseDisplayItem> items;
  final int focusedIndex;
  final bool showProgress;
  final MediaImageRequest Function(PosterBrowseDisplayItem item) imageOf;
  final String Function(PosterBrowseDisplayItem item) secondaryLabelOf;
  final void Function(int index) onItemTap;

  const PosterBrowsePosterTrack({
    super.key,
    required this.items,
    required this.focusedIndex,
    required this.showProgress,
    required this.imageOf,
    required this.secondaryLabelOf,
    required this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(width: 18),
      itemBuilder: (context, index) {
        final item = items[index];
        final request = imageOf(item);
        final canLoad = request.canLoad;
        return PosterBrowsePosterCard(
          key: ValueKey('poster_browse_track_item_${item.card.id}'),
          item: item,
          focused: index == focusedIndex,
          showProgress: showProgress,
          imageUrl: canLoad ? request.urls.first : '',
          imageHeaders: canLoad ? request.headers : const <String, String>{},
          secondaryLabel: secondaryLabelOf(item),
          onTap: () => onItemTap(index),
        );
      },
    );
  }
}
