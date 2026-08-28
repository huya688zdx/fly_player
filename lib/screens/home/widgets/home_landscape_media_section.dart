import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../media_backend/media_image_request.dart';
import '../../../theme/app_theme.dart';
import '../../../ui/media_placeholder.dart';
import 'home_horizontal_shelf.dart';
import 'home_section_header.dart';

/// 横版媒体卡所需的后端中立展示数据。
class HomeLandscapeCardData {
  const HomeLandscapeCardData({
    required this.id,
    required this.title,
    required this.contextText,
    required this.imageRequest,
  });

  final String id;
  final String title;
  final String contextText;
  final MediaImageRequest imageRequest;
}

/// 用于下一集等剧集内容的连续横向媒体架。
class HomeLandscapeMediaSection extends StatelessWidget {
  const HomeLandscapeMediaSection({
    super.key,
    required this.items,
    required this.title,
    required this.onOpenDetail,
    required this.onLongPress,
    this.storageKey = 'landscape-media',
    this.stableImageCacheWidth,
  });

  final List<HomeLandscapeCardData> items;
  final String title;
  final ValueChanged<HomeLandscapeCardData> onOpenDetail;
  final ValueChanged<HomeLandscapeCardData> onLongPress;
  final String storageKey;

  /// 稳定的物理像素解码宽度；只影响图片缓存键。
  final int? stableImageCacheWidth;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        HomeSectionHeader(title: title),
        const SizedBox(height: 12),
        HomeHorizontalShelf<HomeLandscapeCardData>(
          storageKey: storageKey,
          items: items,
          itemBuilder: (context, item, width) => _LandscapeCard(
            item: item,
            width: width,
            stableImageCacheWidth: stableImageCacheWidth,
            onOpenDetail: () => onOpenDetail(item),
            onLongPress: () => onLongPress(item),
          ),
          minItemWidth: 176,
          maxItemWidth: 210,
          idealItemWidth: 210,
          itemAspectRatio: 16 / 10,
          textLinesHeight: 44,
          gap: 12,
        ),
      ],
    );
  }
}

class _LandscapeCard extends StatelessWidget {
  const _LandscapeCard({
    required this.item,
    required this.width,
    required this.stableImageCacheWidth,
    required this.onOpenDetail,
    required this.onLongPress,
  });

  final HomeLandscapeCardData item;
  final double width;
  final int? stableImageCacheWidth;
  final VoidCallback onOpenDetail;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final radius = BorderRadius.circular(14);
    return Material(
      key: ValueKey<String>('landscape-card-${item.id}'),
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpenDetail,
        onLongPress: onLongPress,
        borderRadius: radius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: radius,
              child: SizedBox(
                key: ValueKey<String>('landscape-artwork-${item.id}'),
                width: width,
                height: width / (16 / 10),
                child: _LandscapeArtwork(
                  item: item,
                  stableImageCacheWidth: stableImageCacheWidth,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              item.contextText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w400,
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LandscapeArtwork extends StatelessWidget {
  const _LandscapeArtwork({
    required this.item,
    required this.stableImageCacheWidth,
  });

  final HomeLandscapeCardData item;
  final int? stableImageCacheWidth;

  @override
  Widget build(BuildContext context) {
    const fallback = MediaPlaceholder();
    if (!item.imageRequest.canLoad) return fallback;

    return _LandscapeNetworkImage(
      imageKey: ValueKey<String>('landscape-image-${item.id}'),
      request: item.imageRequest,
      stableImageCacheWidth: stableImageCacheWidth,
      fallback: fallback,
    );
  }
}

class _LandscapeNetworkImage extends StatefulWidget {
  const _LandscapeNetworkImage({
    required this.imageKey,
    required this.request,
    required this.stableImageCacheWidth,
    required this.fallback,
  });

  final Key imageKey;
  final MediaImageRequest request;
  final int? stableImageCacheWidth;
  final Widget fallback;

  @override
  State<_LandscapeNetworkImage> createState() => _LandscapeNetworkImageState();
}

class _LandscapeNetworkImageState extends State<_LandscapeNetworkImage> {
  int _index = 0;
  bool _fallbackScheduled = false;
  int _requestGeneration = 0;

  @override
  void didUpdateWidget(covariant _LandscapeNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.request.urls, widget.request.urls) ||
        !mapEquals(oldWidget.request.headers, widget.request.headers) ||
        oldWidget.request.selfAuthenticated !=
            widget.request.selfAuthenticated) {
      _index = 0;
      _fallbackScheduled = false;
      _requestGeneration++;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.request.canLoad || _index >= widget.request.urls.length) {
      return widget.fallback;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final requestedCacheWidth =
            widget.stableImageCacheWidth?.toDouble() ??
            constraints.maxWidth * MediaQuery.devicePixelRatioOf(context);
        return Image.network(
          widget.request.urls[_index],
          key: widget.imageKey,
          headers: widget.request.headers,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          cacheWidth: _bucketCacheWidth(requestedCacheWidth),
          errorBuilder: (context, error, stackTrace) {
            _scheduleFallback();
            return widget.fallback;
          },
        );
      },
    );
  }

  void _scheduleFallback() {
    if (_fallbackScheduled || _index + 1 >= widget.request.urls.length) {
      return;
    }
    _fallbackScheduled = true;
    final scheduledGeneration = _requestGeneration;
    final scheduledIndex = _index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || scheduledGeneration != _requestGeneration) return;
      setState(() {
        _fallbackScheduled = false;
        if (_index == scheduledIndex &&
            _index + 1 < widget.request.urls.length) {
          _index++;
        }
      });
    });
  }
}

int? _bucketCacheWidth(double physicalWidth) {
  if (!physicalWidth.isFinite || physicalWidth <= 0) return null;
  return ((physicalWidth / 32).round() * 32).clamp(64, 2048).toInt();
}
