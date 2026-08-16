import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../media_backend/media_image_request.dart';
import '../../../theme/app_theme.dart';
import 'home_adaptive_pager.dart';
import 'home_section_header.dart';

/// 继续观看卡片所需的后端中立展示数据。
class HomeContinueCardData {
  const HomeContinueCardData({
    required this.id,
    required this.title,
    required this.contextText,
    required this.progress,
    required this.imageRequest,
    required this.downloaded,
    this.heroTag,
  });

  final String id;
  final String title;
  final String contextText;
  final double progress;
  final MediaImageRequest imageRequest;
  final bool downloaded;
  final String? heroTag;
}

/// 图片优先的继续观看区块。
class HomeContinueWatchingSection extends StatelessWidget {
  const HomeContinueWatchingSection({
    super.key,
    required this.items,
    required this.onOpenDetail,
    required this.onPlay,
    required this.onLongPress,
    this.stableImageCacheWidth,
    this.title = '继续观看',
  });

  final List<HomeContinueCardData> items;
  final ValueChanged<HomeContinueCardData> onOpenDetail;
  final ValueChanged<HomeContinueCardData> onPlay;
  final ValueChanged<HomeContinueCardData> onLongPress;

  /// 稳定的物理像素解码宽度；只影响图片缓存键，不参与响应式布局。
  final int? stableImageCacheWidth;
  final String title;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        HomeSectionHeader(title: title, trailingText: '${items.length} 条'),
        const SizedBox(height: 12),
        HomeAdaptivePager<HomeContinueCardData>(
          items: items,
          itemId: (item) => item.id,
          idealItemWidth: 190,
          itemAspectRatio: 16 / 10,
          maxColumns: 5,
          itemBuilder: (context, item, width) => _ContinueCard(
            item: item,
            width: width,
            stableImageCacheWidth: stableImageCacheWidth,
            onOpenDetail: () => onOpenDetail(item),
            onPlay: () => onPlay(item),
            onLongPress: () => onLongPress(item),
          ),
        ),
      ],
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.item,
    required this.width,
    required this.stableImageCacheWidth,
    required this.onOpenDetail,
    required this.onPlay,
    required this.onLongPress,
  });

  final HomeContinueCardData item;
  final double width;
  final int? stableImageCacheWidth;
  final VoidCallback onOpenDetail;
  final VoidCallback onPlay;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(14);
    final imageHeight = width / (16 / 10);
    final artwork = _ContinueArtwork(
      item: item,
      stableImageCacheWidth: stableImageCacheWidth,
    );
    final heroTag = item.heroTag?.trim() ?? '';
    final heroArtwork = heroTag.isEmpty
        ? artwork
        : Hero(tag: heroTag, child: artwork);

    return Material(
      key: ValueKey<String>('continue-card-${item.id}'),
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
                width: width,
                height: imageHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    heroArtwork,
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: <double>[0.48, 1],
                          colors: <Color>[
                            Colors.transparent,
                            Color(0xB8000000),
                          ],
                        ),
                      ),
                    ),
                    if (item.downloaded)
                      const Positioned(
                        left: 9,
                        bottom: 11,
                        child: _DownloadedBadge(),
                      ),
                    Positioned(
                      right: 8,
                      bottom: 4,
                      child: IconButton(
                        key: ValueKey<String>('continue-play-${item.id}'),
                        onPressed: onPlay,
                        tooltip: '继续播放',
                        icon: DecoratedBox(
                          key: ValueKey<String>(
                            'continue-play-visual-${item.id}',
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox.square(
                            dimension: 38,
                            child: Icon(Icons.play_arrow_rounded, size: 22),
                          ),
                        ),
                        style: IconButton.styleFrom(
                          foregroundColor: scheme.onPrimary,
                          minimumSize: const Size.square(48),
                          maximumSize: const Size.square(48),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        key: ValueKey<String>('continue-progress-${item.id}'),
                        value: item.progress.clamp(0.0, 1.0).toDouble(),
                        minHeight: 3,
                        color: colors.accent,
                        backgroundColor: Colors.white.withValues(alpha: .20),
                      ),
                    ),
                  ],
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

class _ContinueArtwork extends StatelessWidget {
  const _ContinueArtwork({
    required this.item,
    required this.stableImageCacheWidth,
  });

  final HomeContinueCardData item;
  final int? stableImageCacheWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final request = item.imageRequest;
    if (!request.canLoad) {
      return ColoredBox(
        color: colors.surfaceStrong,
        child: Icon(Icons.movie_outlined, color: colors.textMuted, size: 36),
      );
    }
    return _FallbackNetworkImage(
      imageKey: ValueKey<String>('continue-image-${item.id}'),
      request: request,
      stableImageCacheWidth: stableImageCacheWidth,
      fallback: ColoredBox(
        color: colors.surfaceStrong,
        child: Icon(Icons.movie_outlined, color: colors.textMuted, size: 36),
      ),
    );
  }
}

class _DownloadedBadge extends StatelessWidget {
  const _DownloadedBadge();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '已下载',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .58),
          borderRadius: BorderRadius.circular(7),
        ),
        child: const Icon(
          Icons.download_done_rounded,
          color: Colors.white,
          size: 15,
        ),
      ),
    );
  }
}

class _FallbackNetworkImage extends StatefulWidget {
  const _FallbackNetworkImage({
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
  State<_FallbackNetworkImage> createState() => _FallbackNetworkImageState();
}

class _FallbackNetworkImageState extends State<_FallbackNetworkImage> {
  int _index = 0;
  bool _fallbackScheduled = false;
  int _requestGeneration = 0;

  @override
  void didUpdateWidget(covariant _FallbackNetworkImage oldWidget) {
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
  // 32px 分桶避免轻微分屏/旋转抖动不断生成新的图片缓存键。
  return ((physicalWidth / 32).round() * 32).clamp(64, 2048).toInt();
}
