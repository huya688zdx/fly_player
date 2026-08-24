import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../media_backend/home_catalog_presentation.dart';
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

/// 按后端真实图片能力生成首页媒体库入口图。
List<MediaImageRequest> homeCatalogImageRequestsForPresentation({
  required HomeCatalogPresentation presentation,
  required List<MediaImageRequest> catalogRequests,
  List<MediaImageRequest> previewPrimaryRequests = const <MediaImageRequest>[],
  List<MediaImageRequest> previewBackdropRequests = const <MediaImageRequest>[],
}) {
  if (presentation == HomeCatalogPresentation.officialCollage) {
    return catalogRequests
        .where((request) => request.canLoad)
        .take(3)
        .toList(growable: false);
  }

  final ordered = presentation == HomeCatalogPresentation.cinematicBackdrop
      ? <MediaImageRequest>[
          ...previewBackdropRequests,
          ...catalogRequests,
          ...previewPrimaryRequests,
        ]
      : <MediaImageRequest>[
          ...catalogRequests,
          ...previewBackdropRequests,
          ...previewPrimaryRequests,
        ];
  final loadable = ordered.where((request) => request.canLoad).toList();
  if (loadable.isEmpty) return const <MediaImageRequest>[];

  final first = loadable.first;
  final seen = <String>{};
  final urls = <String>[
    for (final request in loadable)
      if (mapEquals(request.headers, first.headers) &&
          request.selfAuthenticated == first.selfAuthenticated)
        for (final url in request.urls)
          if (seen.add(url)) url,
  ];
  return <MediaImageRequest>[
    MediaImageRequest(
      urls: urls,
      headers: first.headers,
      selfAuthenticated: first.selfAuthenticated,
    ),
  ];
}

/// 按后端图片能力渲染的媒体库入口。
class HomeCatalogSection extends StatelessWidget {
  const HomeCatalogSection({
    super.key,
    required this.items,
    required this.onTap,
    this.presentation = HomeCatalogPresentation.officialCollage,
    this.stableImageCacheWidth,
    this.title = '媒体库',
  });

  final List<HomeCatalogCardData> items;
  final ValueChanged<HomeCatalogCardData> onTap;
  final HomeCatalogPresentation presentation;

  /// 稳定的物理像素解码宽度；只影响图片缓存键，不参与响应式布局。
  final int? stableImageCacheWidth;
  final String title;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final shelfMetrics = switch (presentation) {
      HomeCatalogPresentation.officialCollage => const (
        minWidth: 108.0,
        maxWidth: 120.0,
        idealWidth: 120.0,
        aspectRatio: 1.34,
        textHeight: 0.0,
      ),
      HomeCatalogPresentation.cinematicBackdrop => const (
        minWidth: 180.0,
        maxWidth: 196.0,
        idealWidth: 196.0,
        aspectRatio: 16 / 9,
        textHeight: 0.0,
      ),
      HomeCatalogPresentation.clearGallery => const (
        minWidth: 148.0,
        maxWidth: 160.0,
        idealWidth: 160.0,
        aspectRatio: 16 / 9,
        textHeight: 26.0,
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        HomeSectionHeader(title: title),
        const SizedBox(height: 8),
        HomeHorizontalShelf<HomeCatalogCardData>(
          storageKey: 'catalogs',
          items: items,
          itemBuilder: (context, item, width) => _CatalogCard(
            item: item,
            width: width,
            presentation: presentation,
            stableImageCacheWidth: stableImageCacheWidth,
            onTap: () => onTap(item),
          ),
          minItemWidth: shelfMetrics.minWidth,
          maxItemWidth: shelfMetrics.maxWidth,
          idealItemWidth: shelfMetrics.idealWidth,
          itemAspectRatio: shelfMetrics.aspectRatio,
          textLinesHeight: shelfMetrics.textHeight,
          gap: 10,
        ),
      ],
    );
  }
}

class _CatalogCard extends StatelessWidget {
  const _CatalogCard({
    required this.item,
    required this.width,
    required this.presentation,
    required this.stableImageCacheWidth,
    required this.onTap,
  });

  final HomeCatalogCardData item;
  final double width;
  final HomeCatalogPresentation presentation;
  final int? stableImageCacheWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final radius = BorderRadius.circular(
      presentation == HomeCatalogPresentation.officialCollage ? 13 : 15,
    );
    return SizedBox(
      width: width,
      child: Material(
        key: ValueKey<String>('catalog-card-${item.id}'),
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: colors.accent.withValues(alpha: .16),
          highlightColor: colors.accent.withValues(alpha: .08),
          child: _CatalogCardBody(
            item: item,
            presentation: presentation,
            stableImageCacheWidth: stableImageCacheWidth,
          ),
        ),
      ),
    );
  }
}

class _CatalogCardBody extends StatelessWidget {
  const _CatalogCardBody({
    required this.item,
    required this.presentation,
    required this.stableImageCacheWidth,
  });

  final HomeCatalogCardData item;
  final HomeCatalogPresentation presentation;
  final int? stableImageCacheWidth;

  @override
  Widget build(BuildContext context) {
    return switch (presentation) {
      HomeCatalogPresentation.officialCollage => _FeiniuCatalogCardBody(
        item: item,
        stableImageCacheWidth: stableImageCacheWidth,
      ),
      HomeCatalogPresentation.cinematicBackdrop => _EmbyCatalogCardBody(
        item: item,
        stableImageCacheWidth: stableImageCacheWidth,
      ),
      HomeCatalogPresentation.clearGallery => _JellyfinCatalogCardBody(
        item: item,
        stableImageCacheWidth: stableImageCacheWidth,
      ),
    };
  }
}

class _FeiniuCatalogCardBody extends StatelessWidget {
  const _FeiniuCatalogCardBody({
    required this.item,
    required this.stableImageCacheWidth,
  });

  final HomeCatalogCardData item;
  final int? stableImageCacheWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final baseColors = context.baseAppColors;
    final loadable = item.imageRequests
        .where((request) => request.canLoad)
        .take(3)
        .toList(growable: false);
    final imageCount = loadable.isEmpty ? 1 : loadable.length;
    return DecoratedBox(
      key: ValueKey<String>('catalog-frame-${item.id}'),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colors.accent.withValues(alpha: .06),
          baseColors.surface,
        ),
        border: Border.all(
          color: Color.alphaBlend(
            colors.accent.withValues(alpha: .24),
            baseColors.borderStrong,
          ),
        ),
        borderRadius: BorderRadius.circular(13),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          key: ValueKey<String>('catalog-artwork-${item.id}'),
          fit: StackFit.expand,
          children: <Widget>[
            Padding(
              key: ValueKey<String>('catalog-image-inset-${item.id}'),
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final posterWidth = constraints.maxWidth / 3;
                  final posterHeight = posterWidth * 1.5;
                  return Align(
                    alignment: Alignment.topCenter,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: posterWidth * imageCount,
                        height: posterHeight,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            for (var index = 0; index < imageCount; index++)
                              SizedBox(
                                key: ValueKey<String>(
                                  'catalog-poster-${item.id}-$index',
                                ),
                                width: posterWidth,
                                child: index < loadable.length
                                    ? _CatalogNetworkImage(
                                        imageKey: ValueKey<String>(
                                          index == 0
                                              ? 'catalog-image-${item.id}'
                                              : 'catalog-image-${item.id}-$index',
                                        ),
                                        request: loadable[index],
                                        stableImageCacheWidth:
                                            stableImageCacheWidth,
                                      )
                                    : _CatalogPlaceholder(
                                        mediaType: item.mediaType,
                                      ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.transparent,
                    Color(0x15000000),
                    Color(0xD9000000),
                  ],
                  stops: <double>[.40, .58, 1],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Text(
                  item.title,
                  key: ValueKey<String>('catalog-title-${item.id}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                    shadows: <Shadow>[
                      Shadow(color: Colors.black87, blurRadius: 8),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmbyCatalogCardBody extends StatelessWidget {
  const _EmbyCatalogCardBody({
    required this.item,
    required this.stableImageCacheWidth,
  });

  final HomeCatalogCardData item;
  final int? stableImageCacheWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Stack(
      key: ValueKey<String>('catalog-artwork-${item.id}'),
      fit: StackFit.expand,
      children: <Widget>[
        _SingleCatalogArtwork(
          item: item,
          stableImageCacheWidth: stableImageCacheWidth,
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Colors.transparent,
                Color(0x18000000),
                Color(0xE6000000),
              ],
              stops: <double>[.32, .56, 1],
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Text(
              item.title,
              key: ValueKey<String>('catalog-title-${item.id}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.1,
                shadows: <Shadow>[Shadow(color: Colors.black87, blurRadius: 8)],
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomLeft,
          child: FractionallySizedBox(
            widthFactor: .42,
            child: ColoredBox(
              key: ValueKey<String>('catalog-accent-${item.id}'),
              color: colors.accent,
              child: const SizedBox(height: 3),
            ),
          ),
        ),
      ],
    );
  }
}

class _JellyfinCatalogCardBody extends StatelessWidget {
  const _JellyfinCatalogCardBody({
    required this.item,
    required this.stableImageCacheWidth,
  });

  final HomeCatalogCardData item;
  final int? stableImageCacheWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: DecoratedBox(
            key: ValueKey<String>('catalog-accent-${item.id}'),
            decoration: BoxDecoration(
              border: Border.all(color: colors.accent.withValues(alpha: .32)),
              borderRadius: BorderRadius.circular(15),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox.expand(
                key: ValueKey<String>('catalog-artwork-${item.id}'),
                child: _SingleCatalogArtwork(
                  item: item,
                  stableImageCacheWidth: stableImageCacheWidth,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 9),
        Text(
          item.title,
          key: ValueKey<String>('catalog-title-${item.id}'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.12,
          ),
        ),
      ],
    );
  }
}

class _SingleCatalogArtwork extends StatelessWidget {
  const _SingleCatalogArtwork({
    required this.item,
    required this.stableImageCacheWidth,
  });

  final HomeCatalogCardData item;
  final int? stableImageCacheWidth;

  @override
  Widget build(BuildContext context) {
    final request = item.imageRequests
        .where((candidate) => candidate.canLoad)
        .firstOrNull;
    return SizedBox(
      key: ValueKey<String>('catalog-poster-${item.id}-0'),
      child: request == null
          ? _CatalogPlaceholder(mediaType: item.mediaType)
          : _CatalogNetworkImage(
              imageKey: ValueKey<String>('catalog-image-${item.id}'),
              request: request,
              stableImageCacheWidth: stableImageCacheWidth,
            ),
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
