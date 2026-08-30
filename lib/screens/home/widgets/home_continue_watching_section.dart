import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../desktop/desktop.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../media_backend/media_image_request.dart';
import '../../../theme/app_theme.dart';
import '../../../ui/layout_adaptive.dart';
import '../../../ui/media_placeholder.dart';
import 'home_horizontal_shelf.dart';
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
  });

  final String id;
  final String title;
  final String contextText;
  final double progress;
  final MediaImageRequest imageRequest;
  final bool downloaded;
}

/// 图片优先的继续观看区块。
class HomeContinueWatchingSection extends StatelessWidget {
  const HomeContinueWatchingSection({
    super.key,
    required this.items,
    required this.onOpenDetail,
    required this.onPlay,
    required this.onLongPress,
    this.onSecondaryTap,
    this.stableImageCacheWidth,
    this.title = '继续观看',
  });

  final List<HomeContinueCardData> items;
  final ValueChanged<HomeContinueCardData> onOpenDetail;
  final ValueChanged<HomeContinueCardData> onPlay;
  final ValueChanged<HomeContinueCardData> onLongPress;

  /// 桌面档右键回调（非桌面档不触发，可为空）。
  final void Function(HomeContinueCardData item, Offset globalPosition)?
  onSecondaryTap;

  /// 稳定的物理像素解码宽度；只影响图片缓存键，不参与响应式布局。
  final int? stableImageCacheWidth;
  final String title;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final secondaryTap = onSecondaryTap;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 176;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            HomeSectionHeader(title: title),
            const SizedBox(height: 12),
            HomeHorizontalShelf<HomeContinueCardData>(
              storageKey: 'continue-watching',
              items: items,
              itemBuilder: (context, item, width) => _ContinueCard(
                item: item,
                width: width,
                stableImageCacheWidth: stableImageCacheWidth,
                onOpenDetail: () => onOpenDetail(item),
                onPlay: () => onPlay(item),
                onLongPress: () => onLongPress(item),
                onSecondaryTapUp: secondaryTap == null
                    ? null
                    : (position) => secondaryTap(item, position),
              ),
              minItemWidth: 176,
              maxItemWidth: 188,
              idealItemWidth: 188,
              itemAspectRatio: 16 / 10,
              textLinesHeight: compact ? 68 : 44,
              gap: 12,
            ),
          ],
        );
      },
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
    required this.onSecondaryTapUp,
  });

  final HomeContinueCardData item;
  final double width;
  final int? stableImageCacheWidth;
  final VoidCallback onOpenDetail;
  final VoidCallback onPlay;
  final VoidCallback onLongPress;
  final void Function(Offset globalPosition)? onSecondaryTapUp;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final playForeground = Color.lerp(Colors.white, colors.accent, .12)!;
    final playFill = Color.alphaBlend(
      colors.accent.withValues(alpha: .18),
      colors.overlayScrim.withValues(alpha: .82),
    );
    final radius = BorderRadius.circular(14);
    final imageHeight = width / (16 / 10);
    final compactDownloaded = item.downloaded && width < 176;
    final artwork = _ContinueArtwork(
      item: item,
      stableImageCacheWidth: stableImageCacheWidth,
    );

    final card = Material(
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
                    artwork,
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
                    if (item.downloaded && !compactDownloaded)
                      const Positioned(
                        top: 9,
                        right: 9,
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
                            color: playFill,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colors.accent.withValues(alpha: .58),
                              width: .8,
                            ),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: Colors.black.withValues(alpha: .30),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                              BoxShadow(
                                color: colors.accent.withValues(alpha: .14),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                          child: const SizedBox.square(
                            dimension: 36,
                            child: Icon(Icons.play_arrow_rounded, size: 21),
                          ),
                        ),
                        style: IconButton.styleFrom(
                          foregroundColor: playForeground,
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
                        minHeight: 2.5,
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
            if (compactDownloaded) ...<Widget>[
              const SizedBox(height: 3),
              const _DownloadedBadge(),
            ],
          ],
        ),
      ),
    );

    // 桌面档外包悬停浮起并接入右键菜单；非桌面档输出与旧版一致。
    if (!MediaLayoutProfile.of(context).isDesktopTier) {
      return card;
    }
    final secondaryHandler = onSecondaryTapUp;
    return GestureDetector(
      onSecondaryTapUp: secondaryHandler == null
          ? null
          : (details) => secondaryHandler(details.globalPosition),
      child: HoverLift(child: card),
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
    final request = item.imageRequest;
    if (!request.canLoad) {
      return const MediaPlaceholder();
    }
    return _FallbackNetworkImage(
      imageKey: ValueKey<String>('continue-image-${item.id}'),
      request: request,
      stableImageCacheWidth: stableImageCacheWidth,
      fallback: const MediaPlaceholder(),
    );
  }
}

class _DownloadedBadge extends StatelessWidget {
  const _DownloadedBadge();

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context).downloadDownloaded;
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .58),
          borderRadius: BorderRadius.circular(7),
        ),
        child: ExcludeSemantics(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
          ),
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
