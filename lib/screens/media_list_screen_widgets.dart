part of 'media_list_screen.dart';

extension _MediaListScreenWidgets on _MediaListScreenState {
  Widget _buildScreen(BuildContext context) {
    final provider = context.read<NasProvider>();
    final baseUrl = provider.baseUrl;
    final token = provider.token;
    final colors = context.appColors;
    final hasRuntimeDynamicTheme = context.hasRuntimeAppColors;
    final topSurfaceColor = hasRuntimeDynamicTheme
        ? Color.alphaBlend(
            colors.accentSoft.withValues(alpha: 0.16),
            colors.backgroundElevated,
          )
        : colors.backgroundBase;

    final body = _buildBody(
      baseUrl,
      token,
      hasRuntimeDynamicTheme: hasRuntimeDynamicTheme,
    );

    return Scaffold(
      backgroundColor: topSurfaceColor,
      appBar: AppBar(
        backgroundColor: topSurfaceColor,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colors.textPrimary,
        iconTheme: IconThemeData(color: colors.textPrimary),
        actionsIconTheme: IconThemeData(color: colors.textPrimary),
        titleTextStyle: TextStyle(
          color: colors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.secondaryHost
              ? () => EmbeddedDetailLauncher.closeHostOrPop(context)
              : _confirmLogout,
        ),
        title: Text(AppLocalizations.of(context).homeTitle),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              unawaited(_openSearchAsync());
            },
          ),
        ],
      ),
      body: hasRuntimeDynamicTheme
          ? DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Color.alphaBlend(
                      colors.accentSoft.withValues(alpha: 0.16),
                      colors.backgroundElevated,
                    ),
                    Color.alphaBlend(
                      colors.selectionSoft.withValues(alpha: 0.10),
                      colors.backgroundBase,
                    ),
                    colors.backgroundBase,
                  ],
                  stops: const <double>[0.0, 0.28, 0.68],
                ),
              ),
              child: body,
            )
          : body,
    );
  }

  Widget _buildBody(
    String baseUrl,
    String token, {
    required bool hasRuntimeDynamicTheme,
  }) {
    final layout = MediaLayoutProfile.of(context);
    final session = context.watch<BackendSessionProvider>();
    final embyReady =
        session.currentKind == MediaBackendKind.emby && session.isConfigured;
    final isConfigured = embyReady || context.watch<NasProvider>().isConfigured;
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    if (!isConfigured) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            l10n.homeLoginRequired,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, fontSize: 15),
          ),
        ),
      );
    }

    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }

    if (_error != null) {
      return AppErrorState(
        error: _error!,
        localeMap: _localeMap,
        onRetry: _fetchHomeData,
      );
    }

    if (_categories.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context).commonEmpty,
          style: TextStyle(color: colors.textSecondary),
        ),
      );
    }

    final total = _summaryInt('total', 0);
    final movie = _summaryInt('movie', 0);
    final tv = _summaryInt('tv', 0);
    final favorite = _summaryInt('favorite', 0);
    final other = _summaryInt('other', 0);

    return RefreshIndicator(
      onRefresh: _fetchHomeData,
      child: CustomScrollView(
        cacheExtent: _scrollCacheExtent,
        physics: const ClampingScrollPhysics(),
        slivers: <Widget>[
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              layout.pageHorizontalPadding,
              layout.itemGap,
              layout.pageHorizontalPadding,
              14,
            ),
            sliver: SliverToBoxAdapter(
              child: RepaintBoundary(
                child: _buildHomeTopSection(
                  baseUrl: baseUrl,
                  token: token,
                  layout: layout,
                  favorite: favorite,
                  total: total,
                  movie: movie,
                  tv: tv,
                  other: other,
                  hasRuntimeDynamicTheme: hasRuntimeDynamicTheme,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              layout.pageHorizontalPadding,
              0,
              layout.pageHorizontalPadding,
              20,
            ),
            sliver: SliverList.builder(
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _buildSectionTitle(category),
                      const SizedBox(height: 8),
                      _buildPosterRow(
                        _itemsByCategory[category.id] ?? <MediaLibraryItem>[],
                        baseUrl,
                        token,
                        layout,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeTopSection({
    required String baseUrl,
    required String token,
    required MediaLayoutProfile layout,
    required int favorite,
    required int total,
    required int movie,
    required int tv,
    required int other,
    required bool hasRuntimeDynamicTheme,
  }) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildCategoryStrip(baseUrl, token, layout),
        const SizedBox(height: 10),
        if (_continueWatching.isNotEmpty) ...<Widget>[
          Text(
            AppLocalizations.of(context).homeContinueWatching,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: layout.continueRowHeight,
            child: ListView.separated(
              padding: EdgeInsets.zero,
              scrollDirection: Axis.horizontal,
              cacheExtent: _rowCacheExtent(layout.continueCardWidth),
              itemCount: _continueWatching.length,
              separatorBuilder: (_, __) => SizedBox(width: layout.itemGap),
              itemBuilder: (context, index) {
                final item = _continueWatching[index];
                return _buildContinueItem(item, baseUrl, token, layout);
              },
            ),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: <Widget>[
            Expanded(
              child: _buildStatCard(
                AppLocalizations.of(context).actionFavoriteAdd,
                favorite,
                hasRuntimeDynamicTheme: hasRuntimeDynamicTheme,
                onTap: _openFavorites,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildStatCard(
                AppLocalizations.of(context).mediaAllItemsTitle,
                total,
                hasRuntimeDynamicTheme: hasRuntimeDynamicTheme,
                onTap: _openAllItems,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildStatCard(
                AppLocalizations.of(context).listTypeMovie,
                movie,
                hasRuntimeDynamicTheme: hasRuntimeDynamicTheme,
                onTap: () => _openAllItemsByType(
                  AppLocalizations.of(context).listTypeMovie,
                  const <String>['Movie'],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildStatCard(
                AppLocalizations.of(context).listTypeTv,
                tv,
                hasRuntimeDynamicTheme: hasRuntimeDynamicTheme,
                onTap: () => _openAllItemsByType(
                  AppLocalizations.of(context).listTypeTv,
                  const <String>['TV'],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildStatCard(
                AppLocalizations.of(context).commonOther,
                other,
                hasRuntimeDynamicTheme: hasRuntimeDynamicTheme,
                onTap: () => _openAllItemsByType(
                  AppLocalizations.of(context).commonOther,
                  const <String>['Directory', 'Video'],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCategoryStrip(
    String baseUrl,
    String token,
    MediaLayoutProfile layout,
  ) {
    final count = min(_categories.length, widget.secondaryHost ? 6 : 10);
    return SizedBox(
      height: layout.categoryStripHeight,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        scrollDirection: Axis.horizontal,
        cacheExtent: _rowCacheExtent(layout.categoryCardWidth),
        itemCount: count,
        separatorBuilder: (_, __) => SizedBox(width: layout.itemGap),
        itemBuilder: (context, index) {
          final category = _categories[index];
          final source = category.posters.isNotEmpty
              ? category.posters
              : (category.path?.isNotEmpty ?? false)
              ? <String>[category.path!]
              : const <String>[];
          final posterLimit = widget.secondaryHost ? 1 : 2;
          final posters = source.take(posterLimit).toList();
          return _CategoryPosterCard(
            title: category.name,
            posterUrls: posters
                .map(
                  (path) => _posterCandidates(
                    baseUrl,
                    path,
                    width: (layout.categoryMiniPosterWidth * 3).round(),
                  ),
                )
                .toList(),
            token: token,
            lightweight: widget.secondaryHost,
            cardWidth: layout.categoryCardWidth,
            miniPosterWidth: layout.categoryMiniPosterWidth,
            miniPosterHeight: layout.categoryMiniPosterHeight,
            onTap: () => _openCategory(category),
          );
        },
      ),
    );
  }

  Widget _buildContinueItem(
    MediaLibraryItem item,
    String baseUrl,
    String token,
    MediaLayoutProfile layout,
  ) {
    final colors = context.appColors;
    final heroTag = 'home_continue_${item.guid}';
    final urls = _posterCandidates(
      baseUrl,
      item.poster,
      width: layout.homeContinueRequestWidth,
    );
    final progress = _progressValue(item);
    final progressActiveColor = DetailTokens.progressActiveOf(context);
    return InkWell(
      onTap: () => _openItemDetail(item, heroTag: heroTag),
      onLongPress: () {
        unawaited(_showContinueWatchingActionsV2(item, heroTag: heroTag));
      },
      borderRadius: BorderRadius.circular(10),
      child: RepaintBoundary(
        child: SizedBox(
          width: layout.continueCardWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Hero(
                tag: heroTag,
                child: Container(
                  height: layout.continueImageHeight,
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: colors.surface,
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      _PosterImage(
                        urls: urls,
                        token: token,
                        lightweight: widget.secondaryHost,
                        fallback: Center(
                          child: Icon(
                            Icons.movie,
                            color: colors.textMuted.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: _ContinueDownloadBadge(itemGuid: item.guid),
                      ),
                      if (progress > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final visualWidth =
                                  (constraints.maxWidth * progress).clamp(
                                    4.0,
                                    constraints.maxWidth,
                                  );
                              return Align(
                                alignment: Alignment.centerLeft,
                                child: SizedBox(
                                  width: visualWidth,
                                  height: 5,
                                  child: ColoredBox(color: progressActiveColor),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                item.type.trim().toLowerCase() == 'movie'
                    ? AppLocalizations.of(context).listTypeMovie
                    : _continueEpisodeText(item),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    int value, {
    required bool hasRuntimeDynamicTheme,
    VoidCallback? onTap,
  }) {
    final colors = context.appColors;
    // hasRuntimeDynamicTheme 保留以兼容调用方；玻璃外观对两种主题一致。
    return LiquidGlass(
      radius: 10,
      onTap: onTap,
      child: SizedBox(
        height: 58,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(color: colors.textPrimary, fontSize: 13),
            ),
            Text(
              '$value',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(MediaItem category) {
    final colors = context.appColors;
    return InkWell(
      onTap: () => _openCategory(category),
      child: Row(
        children: <Widget>[
          Text(
            category.name,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: colors.textMuted, size: 20),
        ],
      ),
    );
  }

  Widget _buildPosterRow(
    List<MediaLibraryItem> items,
    String baseUrl,
    String token,
    MediaLayoutProfile layout,
  ) {
    final colors = context.appColors;
    if (items.isEmpty) {
      return SizedBox(
        height: 220,
        child: Center(
          child: Text(
            AppLocalizations.of(context).commonEmpty,
            style: TextStyle(color: colors.textMuted),
          ),
        ),
      );
    }

    final maxCount = min(items.length, 12);
    return SizedBox(
      height: layout.homePosterRowHeight,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        scrollDirection: Axis.horizontal,
        cacheExtent: _rowCacheExtent(layout.homePosterCardWidth),
        itemCount: maxCount,
        separatorBuilder: (_, __) => SizedBox(width: layout.itemGap),
        itemBuilder: (context, index) {
          final item = items[index];
          final urls = _posterCandidates(
            baseUrl,
            item.poster,
            width: layout.homePosterRequestWidth,
          );
          final rating = double.tryParse(item.voteAverage);
          final resolutions = item.resolutions
              .map(_resolutionLabel)
              .where((value) => value.isNotEmpty)
              .toList();

          return SizedBox(
            width: layout.homePosterCardWidth,
            child: MediaPosterCard(
              urls: urls,
              token: token,
              title: item.displayTitle,
              subtitle: _cardSubtitle(item),
              rating: rating,
              resolutions: resolutions,
              watched: item.watched == 1,
              imageHeight: layout.homePosterImageHeight,
              titleFontSize: layout.homePosterTitleFontSize,
              subtitleFontSize: layout.homePosterSubtitleFontSize,
              imageFit: _isEpisodeItem(item) ? BoxFit.contain : BoxFit.cover,
              heroTag: 'home_row_${item.guid}_$index',
              onTap: () => _openItemDetail(
                item,
                heroTag: 'home_row_${item.guid}_$index',
              ),
              onLongPress: () => _showPosterItemActions(item),
            ),
          );
        },
      ),
    );
  }
}

class _CategoryPosterCard extends StatelessWidget {
  final String title;
  final List<List<String>> posterUrls;
  final String token;
  final bool lightweight;
  final double cardWidth;
  final double miniPosterWidth;
  final double miniPosterHeight;
  final VoidCallback? onTap;

  const _CategoryPosterCard({
    required this.title,
    required this.posterUrls,
    required this.token,
    this.lightweight = false,
    required this.cardWidth,
    required this.miniPosterWidth,
    required this.miniPosterHeight,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLightSurface = colors.backgroundBase.computeLuminance() >= 0.58;
    final normalized = posterUrls.take(3).toList();
    final radius = BorderRadius.circular(16);

    // iOS26 磨砂玻璃：半透明磨砂基底 + 镜面高光 + 发丝边。
    // 不用 BackdropFilter（实时模糊在滚动区逐帧重算、很掉帧），改用半透明
    // 渐变模拟玻璃；因此基底比真模糊版略实一点，才能读出“玻璃”质感。
    final glassFill = isLightSurface
        ? Colors.white.withValues(alpha: 0.42)
        : Colors.white.withValues(alpha: 0.16);
    final glassEdge = isLightSurface
        ? Colors.white.withValues(alpha: 0.70)
        : Colors.white.withValues(alpha: 0.16);
    final bottomVeil = isLightSurface
        ? colors.backgroundBase.withValues(alpha: 0.12)
        : colors.backgroundBase.withValues(alpha: 0.30);

    return RepaintBoundary(
      child: SizedBox(
        width: cardWidth,
        child: ClipRRect(
          borderRadius: radius,
          // 静态磨砂渐变模拟玻璃：卡片成为可缓存的静态层，滚动时不再逐帧模糊。
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(color: glassEdge, width: 0.8),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      Colors.white.withValues(
                        alpha: isLightSurface ? 0.50 : 0.22,
                      ),
                      glassFill,
                      colors.accentSoft.withValues(
                        alpha: isLightSurface ? 0.14 : 0.09,
                      ),
                    ],
                  ),
                ),
                child: Stack(
                  children: <Widget>[
                    // 左上镜面高光，模拟玻璃对光的反射。
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(-0.78, -0.95),
                            radius: 1.3,
                            colors: <Color>[
                              Colors.white.withValues(
                                alpha: isLightSurface ? 0.38 : 0.14,
                              ),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    // 海报簇（轻微倾斜叠放，每张带玻璃描边）。
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 30),
                        child: Center(
                          child: _PosterCluster(
                            posterUrls: normalized,
                            token: token,
                            lightweight: lightweight,
                            miniPosterWidth: miniPosterWidth,
                            miniPosterHeight: miniPosterHeight,
                            fallbackColor: colors.surfaceStrong.withValues(
                              alpha: isLightSurface ? 0.30 : 0.18,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 底部柔化，保证标题清晰可读。
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const <double>[0.0, 0.6, 1.0],
                            colors: <Color>[
                              Colors.transparent,
                              Colors.transparent,
                              bottomVeil,
                            ],
                          ),
                        ),
                      ),
                    ),
                    // 顶沿发丝高光，强化玻璃边缘的清脆感。
                    Positioned(
                      left: 1,
                      right: 1,
                      top: 1,
                      child: Container(
                        height: 1,
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16),
                          ),
                          color: Colors.white.withValues(
                            alpha: isLightSurface ? 0.60 : 0.24,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textScaler: const TextScaler.linear(1.0),
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1.05,
                          shadows: <Shadow>[
                            Shadow(
                              color: colors.backgroundBase.withValues(
                                alpha: isLightSurface ? 0.28 : 0.46,
                              ),
                              blurRadius: 5,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 分类卡内的海报簇：1~3 张迷你海报，轻微倾斜叠放，每张带玻璃描边。
class _PosterCluster extends StatelessWidget {
  final List<List<String>> posterUrls;
  final String token;
  final bool lightweight;
  final double miniPosterWidth;
  final double miniPosterHeight;
  final Color fallbackColor;

  const _PosterCluster({
    required this.posterUrls,
    required this.token,
    required this.lightweight,
    required this.miniPosterWidth,
    required this.miniPosterHeight,
    required this.fallbackColor,
  });

  @override
  Widget build(BuildContext context) {
    if (posterUrls.isEmpty) {
      return SizedBox(
        width: miniPosterWidth,
        height: miniPosterHeight,
        child: _GlassMiniPoster(child: ColoredBox(color: fallbackColor)),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(posterUrls.length, (index) {
        final tilt = posterUrls.length == 1
            ? 0.0
            : (index.isEven ? -0.018 : 0.018);
        return Padding(
          padding: EdgeInsets.only(
            right: index == posterUrls.length - 1 ? 0 : 5,
          ),
          child: Transform.rotate(
            angle: tilt,
            child: SizedBox(
              width: miniPosterWidth,
              height: miniPosterHeight,
              child: _GlassMiniPoster(
                child: _PosterImage(
                  urls: posterUrls[index],
                  token: token,
                  lightweight: lightweight,
                  fallback: ColoredBox(color: fallbackColor),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// 迷你海报的玻璃描边外框，圆角 + 半透明白边。
class _GlassMiniPoster extends StatelessWidget {
  final Widget child;

  const _GlassMiniPoster({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLightSurface = colors.backgroundBase.computeLuminance() >= 0.58;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: Colors.white.withValues(alpha: isLightSurface ? 0.48 : 0.18),
          width: 0.6,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        clipBehavior: Clip.hardEdge,
        child: child,
      ),
    );
  }
}

class _ContinueDownloadBadge extends StatelessWidget {
  final String itemGuid;

  const _ContinueDownloadBadge({required this.itemGuid});

  static const Color _backgroundColor = Color(0x94000000);
  static const Color _borderColor = Color(0xB33A82F7);
  static const Color _textColor = Color(0xFFF3F8FF);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DownloadTaskService.instance,
      builder: (context, child) {
        final downloaded = DownloadTaskService.instance
            .actionStateForItem(itemGuid)
            .downloaded;
        if (!downloaded) {
          return const SizedBox.shrink();
        }
        return child!;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _backgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _borderColor, width: 0.8),
        ),
        child: Text(
          AppLocalizations.of(context).downloadDownloaded,
          style: const TextStyle(
            color: _textColor,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _PosterImage extends StatefulWidget {
  final List<String> urls;
  final String token;
  final bool lightweight;
  final Widget fallback;

  const _PosterImage({
    required this.urls,
    required this.token,
    this.lightweight = false,
    required this.fallback,
  });

  @override
  State<_PosterImage> createState() => _PosterImageState();
}

class _PosterImageState extends State<_PosterImage> {
  int _index = 0;
  bool _fallbackScheduled = false;

  @override
  void didUpdateWidget(covariant _PosterImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.urls, widget.urls)) {
      _index = 0;
      _fallbackScheduled = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUrl = widget.urls.isNotEmpty && _index < widget.urls.length;
    final activeUrl = hasUrl ? widget.urls[_index] : '';
    // 空 token 默认回退（飞牛图需 NAS token）；自带凭据 URL（Emby `?api_key=`）照常加载。
    final selfAuthenticated = activeUrl.contains('api_key=');
    if (!hasUrl || (widget.token.trim().isEmpty && !selfAuthenticated)) {
      return widget.fallback;
    }

    final current = activeUrl;
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.of(context).devicePixelRatio;
        final cacheWidth = constraints.maxWidth.isFinite
            ? (constraints.maxWidth * dpr).round().clamp(80, 1000)
            : null;
        final cacheHeight = constraints.maxHeight.isFinite
            ? (constraints.maxHeight * dpr).round().clamp(80, 1000)
            : null;

        return Image.network(
          current,
          fit: BoxFit.cover,
          headers: nasImageHeaders(widget.token, url: current),
          filterQuality: FilterQuality.none,
          gaplessPlayback: true,
          cacheWidth: cacheWidth,
          cacheHeight: cacheHeight,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            final loaded = wasSynchronouslyLoaded || frame != null;
            return _buildImageFrame(child, loaded);
          },
          errorBuilder: (context, error, stackTrace) {
            if (_index < widget.urls.length - 1) {
              final nextUrl = widget.urls[_index + 1];
              debugPrint(
                '[IMG][MEDIA_LIST] failed url=$current error=$error -> fallback=$nextUrl',
              );
              _scheduleFallback();
              return widget.fallback;
            }
            debugPrint(
              '[IMG][MEDIA_LIST] failed url=$current error=$error -> no_more_fallback',
            );
            return widget.fallback;
          },
        );
      },
    );
  }

  Widget _buildImageFrame(Widget child, bool loaded) {
    if (loaded) return child;
    return widget.fallback;
  }

  void _scheduleFallback() {
    if (_fallbackScheduled) return;
    _fallbackScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_index >= widget.urls.length - 1) {
        _fallbackScheduled = false;
        return;
      }
      setState(() {
        _fallbackScheduled = false;
        _index += 1;
      });
    });
  }
}
