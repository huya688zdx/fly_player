import 'package:flutter/material.dart';

import '../../media_backend/media_item_card.dart';

/// 底部横向缩略图条：16:9 小图、聚焦放大 + 白描边、评分角标、可选进度条。
/// 图片 URL 由调用方经 DetailArtworkResolver 解析后注入（本组件不接触后端概念）。
class PosterBrowseThumbStrip extends StatelessWidget {
  const PosterBrowseThumbStrip({
    super.key,
    required this.items,
    required this.focusedIndex,
    required this.imageUrlOf,
    required this.onItemTap,
    this.imageHeaders = const <String, String>{},
    this.showProgress = false,
    this.thumbHeight = 72,
  });

  final List<MediaItemCard> items;
  final int focusedIndex;
  final String Function(MediaItemCard item) imageUrlOf;
  final Map<String, String> imageHeaders;
  final void Function(int index) onItemTap;
  final bool showProgress;
  final double thumbHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: thumbHeight + 16,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = items[index];
          final focused = index == focusedIndex;
          final url = imageUrlOf(item);
          final progress = _progress(item);
          return Center(
            child: GestureDetector(
              key: ValueKey('poster_browse_thumb_${item.id}'),
              onTap: () => onItemTap(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                height: focused ? thumbHeight + 12 : thumbHeight,
                width: (focused ? thumbHeight + 12 : thumbHeight) * 16 / 9,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: focused
                      ? Border.all(color: Colors.white, width: 2.5)
                      : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (url.trim().isNotEmpty)
                      Image.network(
                        url,
                        headers: imageHeaders.isEmpty ? null : imageHeaders,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    if (item.rating.trim().isNotEmpty)
                      Positioned(
                        top: 4,
                        right: 5,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            child: Text(
                              '★ ${item.rating.trim()}',
                              style: const TextStyle(
                                color: Color(0xFFFFD166),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (showProgress && progress > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          backgroundColor: Colors.white.withValues(alpha: 0.25),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  double _progress(MediaItemCard item) {
    if (item.durationSeconds <= 0 || item.resumePositionSeconds <= 0) return 0;
    return (item.resumePositionSeconds / item.durationSeconds)
        .clamp(0, 1)
        .toDouble();
  }
}
