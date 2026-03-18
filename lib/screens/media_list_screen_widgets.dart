part of 'media_list_screen.dart';

extension _MediaListScreenWidgets on _MediaListScreenState {
  Widget _buildScreen(BuildContext context) {
    final provider = context.read<NasProvider>();
    final baseUrl = provider.baseUrl;
    final token = provider.token;
    final colors = context.appColors;
    final hasRuntimeDynamicTheme = context.select<AppThemeProvider, bool>(
      (themeProvider) =>
          themeProvider.dynamicThemeEnabled &&
          themeProvider.runtimeDynamicThemeSeed != null,
    );

    final body = _buildBody(baseUrl, token);

    return Scaffold(
      backgroundColor: hasRuntimeDynamicTheme
          ? Colors.transparent
          : colors.backgroundBase,
      appBar: AppBar(
        backgroundColor: hasRuntimeDynamicTheme
            ? Colors.transparent
            : colors.backgroundBase,
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
        title: Text(_t('layout.sidebar.home', '首页')),
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

  Widget _buildBody(String baseUrl, String token) {
    final layout = MediaLayoutProfile.of(context);
    final isConfigured = context.watch<NasProvider>().isConfigured;
    final colors = context.appColors;
    if (!isConfigured) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            '请先到“设置”页登录 NAS，再返回影视页加载内容。',
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
          _t('common.other.empty', '没有内容'),
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
        physics: const AlwaysScrollableScrollPhysics(),
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
  }) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildCategoryStrip(baseUrl, token, layout),
        const SizedBox(height: 10),
        if (_continueWatching.isNotEmpty) ...<Widget>[
          Text(
            _t('layout.list.continueWatching', '继续观看'),
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
                _t('common.actions.favorite.favorite', '收藏'),
                favorite,
                onTap: _openFavorites,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildStatCard(
                _t('layout.sidebar.allList', '全部影视'),
                total,
                onTap: _openAllItems,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildStatCard(
                _t('layout.sidebar.movieList', '电影'),
                movie,
                onTap: () => _openAllItemsByType(
                  _t('layout.sidebar.movieList', '电影'),
                  const <String>['Movie'],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildStatCard(
                _t('layout.sidebar.tvList', '电视剧'),
                tv,
                onTap: () => _openAllItemsByType(
                  _t('layout.sidebar.tvList', '电视剧'),
                  const <String>['TV'],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildStatCard(
                _t('layout.sidebar.otherList', '其他'),
                other,
                onTap: () => _openAllItemsByType(
                  _t('layout.sidebar.otherList', '其他'),
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
          final posters = source.take(3).toList();
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
                    ? _t('layout.list.filter.type.movie', '电影')
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

  Widget _buildStatCard(String label, int value, {VoidCallback? onTap}) {
    final colors = context.appColors;
    final hasRuntimeDynamicTheme = context.select<AppThemeProvider, bool>(
      (themeProvider) =>
          themeProvider.dynamicThemeEnabled &&
          themeProvider.runtimeDynamicThemeSeed != null,
    );
    final child = Container(
      height: 58,
      decoration: BoxDecoration(
        color: hasRuntimeDynamicTheme ? colors.surfaceStrong : colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: hasRuntimeDynamicTheme
            ? Border.all(color: colors.borderSubtle, width: 0.8)
            : null,
      ),
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
    );
    if (onTap == null) return child;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: child,
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
            _t('common.other.empty', '没有内容'),
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

    return RepaintBoundary(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: cardWidth,
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.borderSubtle, width: 0.8),
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: Container(
                    color: colors.backgroundElevated,
                    padding: const EdgeInsets.fromLTRB(6, 8, 6, 24),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(normalized.length, (index) {
                          return Padding(
                            padding: EdgeInsets.only(
                              right: index == normalized.length - 1 ? 0 : 2,
                            ),
                            child: SizedBox(
                              width: miniPosterWidth,
                              height: miniPosterHeight,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                clipBehavior: Clip.hardEdge,
                                child: _PosterImage(
                                  urls: normalized[index],
                                  token: token,
                                  lightweight: lightweight,
                                  fallback: Container(
                                    color: colors.surfaceStrong,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Colors.transparent,
                          Colors.transparent,
                          (isLightSurface
                                  ? colors.backgroundElevated
                                  : colors.overlayScrim)
                              .withValues(alpha: 0.08),
                          (isLightSurface
                                  ? colors.backgroundBase
                                  : colors.overlayScrim)
                              .withValues(alpha: isLightSurface ? 0.42 : 0.46),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 7,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: const TextScaler.linear(1.0),
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.05,
                      shadows: <Shadow>[
                        Shadow(
                          color: Color(0xB0000000),
                          blurRadius: 6,
                          offset: Offset(0, 1),
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

  @override
  void didUpdateWidget(covariant _PosterImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.urls, widget.urls)) {
      _index = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty ||
        _index >= widget.urls.length ||
        widget.token.trim().isEmpty) {
      return widget.fallback;
    }

    final current = widget.urls[_index];
    final headers = <String, String>{
      'Authorization': widget.token,
      'Trim-MC-token': widget.token,
    };

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
          headers: headers,
          filterQuality: FilterQuality.none,
          gaplessPlayback: true,
          cacheWidth: cacheWidth,
          cacheHeight: cacheHeight,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            final loaded = wasSynchronouslyLoaded || frame != null;
            if (widget.lightweight) {
              return loaded ? child : widget.fallback;
            }
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                widget.fallback,
                AnimatedOpacity(
                  opacity: loaded ? 1 : 0,
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.linear,
                  child: child,
                ),
              ],
            );
          },
          errorBuilder: (context, error, stackTrace) {
            if (_index < widget.urls.length - 1) {
              final nextUrl = widget.urls[_index + 1];
              debugPrint(
                '[IMG][MEDIA_LIST] failed url=$current error=$error -> fallback=$nextUrl',
              );
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() => _index++);
                }
              });
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
}
