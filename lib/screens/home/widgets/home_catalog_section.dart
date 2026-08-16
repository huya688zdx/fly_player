import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../media_backend/media_image_request.dart';
import '../../../theme/app_theme.dart';
import '../home_presentation_profile.dart';
import 'home_adaptive_pager.dart';
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

/// 按平台展示风格渲染的图片优先媒体库入口。
class HomeCatalogSection extends StatelessWidget {
  const HomeCatalogSection({
    super.key,
    required this.items,
    required this.style,
    required this.onTap,
    this.title = '媒体库',
  });

  final List<HomeCatalogCardData> items;
  final HomeCatalogStyle style;
  final ValueChanged<HomeCatalogCardData> onTap;
  final String title;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final geometry = _CatalogGeometry.forStyle(style);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        HomeSectionHeader(title: title, trailingText: '${items.length} 个'),
        const SizedBox(height: 12),
        HomeAdaptivePager<HomeCatalogCardData>(
          items: items,
          itemId: (item) => item.id,
          itemBuilder: (context, item, width) => _CatalogCard(
            item: item,
            style: style,
            width: width,
            onTap: () => onTap(item),
          ),
          idealItemWidth: geometry.idealWidth,
          itemAspectRatio: geometry.aspectRatio,
          textLinesHeight: 0,
          maxColumns: 5,
        ),
      ],
    );
  }
}

class _CatalogGeometry {
  const _CatalogGeometry({required this.idealWidth, required this.aspectRatio});

  final double idealWidth;
  final double aspectRatio;

  static _CatalogGeometry forStyle(HomeCatalogStyle style) => switch (style) {
    HomeCatalogStyle.posterMosaic => const _CatalogGeometry(
      idealWidth: 190,
      aspectRatio: 3 / 2,
    ),
    HomeCatalogStyle.landscapeArtwork => const _CatalogGeometry(
      idealWidth: 210,
      aspectRatio: 3 / 2,
    ),
    HomeCatalogStyle.artworkGrid => const _CatalogGeometry(
      idealWidth: 172,
      aspectRatio: 1,
    ),
  };
}

class _CatalogCard extends StatelessWidget {
  const _CatalogCard({
    required this.item,
    required this.style,
    required this.width,
    required this.onTap,
  });

  final HomeCatalogCardData item;
  final HomeCatalogStyle style;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final aspectRatio = _CatalogGeometry.forStyle(style).aspectRatio;
    final radius = BorderRadius.circular(15);
    return SizedBox(
      width: width,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Material(
          key: ValueKey<String>('catalog-card-${item.id}'),
          color: colors.surfaceStrong,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                _CatalogArtwork(item: item, style: style),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: <double>[0.52, 1],
                      colors: <Color>[Colors.transparent, Color(0xC2000000)],
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 10,
                  child: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogArtwork extends StatelessWidget {
  const _CatalogArtwork({required this.item, required this.style});

  final HomeCatalogCardData item;
  final HomeCatalogStyle style;

  @override
  Widget build(BuildContext context) {
    final loadable = item.imageRequests
        .where((request) => request.canLoad)
        .take(style == HomeCatalogStyle.posterMosaic ? 3 : 1)
        .toList(growable: false);
    if (loadable.isEmpty) {
      final colors = context.appColors;
      return ColoredBox(
        color: colors.surfaceStrong,
        child: Icon(
          _iconFor(item.mediaType),
          color: colors.textMuted,
          size: 38,
        ),
      );
    }

    if (style != HomeCatalogStyle.posterMosaic) {
      return _CatalogNetworkImage(
        imageKey: ValueKey<String>('catalog-image-${item.id}'),
        request: loadable.first,
      );
    }

    return Row(
      children: <Widget>[
        for (var index = 0; index < loadable.length; index++)
          Expanded(
            child: _CatalogNetworkImage(
              imageKey: ValueKey<String>(
                index == 0
                    ? 'catalog-image-${item.id}'
                    : 'catalog-image-${item.id}-$index',
              ),
              request: loadable[index],
            ),
          ),
      ],
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
  const _CatalogNetworkImage({required this.imageKey, required this.request});

  final Key imageKey;
  final MediaImageRequest request;

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
        final dpr = MediaQuery.devicePixelRatioOf(context);
        return Image.network(
          widget.request.urls[_index],
          key: widget.imageKey,
          headers: widget.request.headers,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          cacheWidth: _stableCacheExtent(constraints.maxWidth, dpr),
          cacheHeight: _stableCacheExtent(constraints.maxHeight, dpr),
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

int? _stableCacheExtent(double logicalExtent, double devicePixelRatio) {
  if (!logicalExtent.isFinite || logicalExtent <= 0) return null;
  final pixels = logicalExtent * devicePixelRatio;
  // 32px 分桶避免轻微分屏/旋转抖动不断生成新的图片缓存键。
  return ((pixels / 32).round() * 32).clamp(64, 2048).toInt();
}
