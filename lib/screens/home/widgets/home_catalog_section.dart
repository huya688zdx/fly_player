import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../media_backend/media_image_request.dart';
import '../../../theme/app_theme.dart';
import 'home_horizontal_shelf.dart';
import 'home_section_header.dart';

/// 媒体库内容类型，仅用于选择无图占位图标。
enum HomeCatalogMediaType { movies, series, collections, mixed, other }

/// 媒体库入口所需的后端中立展示数据。
class HomeCatalogCardData {
  const HomeCatalogCardData({
    required this.id,
    required this.title,
    required this.mediaType,
    required this.imageRequests,
  });

  final String id;
  final String title;
  final HomeCatalogMediaType mediaType;
  final List<MediaImageRequest> imageRequests;
}

/// 使用竖版海报簇渲染的媒体库入口。
class HomeCatalogSection extends StatelessWidget {
  const HomeCatalogSection({
    super.key,
    required this.items,
    required this.onTap,
    this.stableImageCacheWidth,
    this.title = '媒体库',
  });

  final List<HomeCatalogCardData> items;
  final ValueChanged<HomeCatalogCardData> onTap;

  /// 稳定的物理像素解码宽度；只影响图片缓存键，不参与响应式布局。
  final int? stableImageCacheWidth;
  final String title;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        HomeSectionHeader(title: title),
        const SizedBox(height: 12),
        HomeHorizontalShelf<HomeCatalogCardData>(
          storageKey: 'catalogs',
          items: items,
          itemBuilder: (context, item, width) => _CatalogCard(
            item: item,
            width: width,
            stableImageCacheWidth: stableImageCacheWidth,
            onTap: () => onTap(item),
          ),
          minItemWidth: 156,
          maxItemWidth: 184,
          idealItemWidth: 184,
          itemAspectRatio: 1.08,
          textLinesHeight: 0,
          gap: 12,
        ),
      ],
    );
  }
}

class _CatalogCard extends StatelessWidget {
  const _CatalogCard({
    required this.item,
    required this.width,
    required this.stableImageCacheWidth,
    required this.onTap,
  });

  final HomeCatalogCardData item;
  final double width;
  final int? stableImageCacheWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final radius = BorderRadius.circular(15);
    return SizedBox(
      width: width,
      child: Material(
        key: ValueKey<String>('catalog-card-${item.id}'),
        color: colors.surfaceStrong,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: colors.accent.withValues(alpha: .18)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            children: <Widget>[
              Expanded(
                child: _CatalogArtwork(
                  key: ValueKey<String>('catalog-artwork-${item.id}'),
                  item: item,
                  stableImageCacheWidth: stableImageCacheWidth,
                ),
              ),
              SizedBox(
                height: 36,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      item.title,
                      key: ValueKey<String>('catalog-title-${item.id}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.15,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogArtwork extends StatelessWidget {
  const _CatalogArtwork({
    super.key,
    required this.item,
    required this.stableImageCacheWidth,
  });

  final HomeCatalogCardData item;
  final int? stableImageCacheWidth;

  @override
  Widget build(BuildContext context) {
    final loadable = item.imageRequests
        .where((request) => request.canLoad)
        .take(2)
        .toList(growable: false);
    return LayoutBuilder(
      builder: (context, constraints) {
        final posterHeight = (constraints.maxHeight - 14).clamp(
          0.0,
          constraints.maxHeight,
        );
        final posterWidth = posterHeight * 2 / 3;
        final posterCount = loadable.isEmpty ? 1 : loadable.length;
        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            for (var index = 0; index < posterCount; index++)
              Center(
                child: Transform.translate(
                  offset: posterCount == 1
                      ? Offset.zero
                      : Offset(
                          (index == 0 ? -.18 : .18) * posterWidth,
                          index == 0 ? 3 : -3,
                        ),
                  child: SizedBox(
                    width: posterWidth,
                    height: posterHeight,
                    child: AspectRatio(
                      key: ValueKey<String>('catalog-poster-${item.id}-$index'),
                      aspectRatio: 2 / 3,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: index < loadable.length
                            ? _CatalogNetworkImage(
                                imageKey: ValueKey<String>(
                                  index == 0
                                      ? 'catalog-image-${item.id}'
                                      : 'catalog-image-${item.id}-$index',
                                ),
                                request: loadable[index],
                                stableImageCacheWidth: stableImageCacheWidth,
                              )
                            : _CatalogPlaceholder(mediaType: item.mediaType),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CatalogPlaceholder extends StatelessWidget {
  const _CatalogPlaceholder({required this.mediaType});

  final HomeCatalogMediaType mediaType;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ColoredBox(
      color: colors.surfaceStrong,
      child: Icon(_iconFor(mediaType), color: colors.textMuted, size: 38),
    );
  }

  IconData _iconFor(HomeCatalogMediaType type) => switch (type) {
    HomeCatalogMediaType.movies => Icons.movie_outlined,
    HomeCatalogMediaType.series => Icons.tv_outlined,
    HomeCatalogMediaType.collections => Icons.video_collection_outlined,
    HomeCatalogMediaType.mixed => Icons.video_library_outlined,
    HomeCatalogMediaType.other => Icons.folder_outlined,
  };
}

class _CatalogNetworkImage extends StatefulWidget {
  const _CatalogNetworkImage({
    required this.imageKey,
    required this.request,
    required this.stableImageCacheWidth,
  });

  final Key imageKey;
  final MediaImageRequest request;
  final int? stableImageCacheWidth;

  @override
  State<_CatalogNetworkImage> createState() => _CatalogNetworkImageState();
}

class _CatalogNetworkImageState extends State<_CatalogNetworkImage> {
  int _index = 0;
  bool _fallbackScheduled = false;
  int _requestGeneration = 0;

  @override
  void didUpdateWidget(covariant _CatalogNetworkImage oldWidget) {
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
    final colors = context.appColors;
    final fallback = ColoredBox(color: colors.surfaceStrong);
    if (!widget.request.canLoad || _index >= widget.request.urls.length) {
      return fallback;
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
            return fallback;
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
  // 32px 分桶避免轻微分屏/旋转抖动不断生成新的图片缓存键。
  return ((physicalWidth / 32).round() * 32).clamp(64, 2048).toInt();
}
