part of 'media_list_screen.dart';

extension _MediaListScreenWidgets on _MediaListScreenState {
  Widget _buildScreen(BuildContext context) {
    final provider = context.read<NasProvider>();
    final imageCredentials = mediaImageCredentialsForBackend(
      backendKind: context
          .read<MediaBackendProvider>()
          .backend
          .capabilities
          .kind,
      token: provider.token,
      accessCode: provider.accessCode,
      baseUrl: provider.baseUrl,
    );
    final baseUrl = imageCredentials.baseUrl;
    final token = imageCredentials.token;
    final accessCode = imageCredentials.accessCode;
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
      accessCode,
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
          fontWeight: FontWeight.w600,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.secondaryHost
              ? () => EmbeddedDetailLauncher.closeHostOrPop(context)
              : _confirmLogout,
        ),
        title: Text(AppLocalizations.of(context).homeTitle),
        actions: <Widget>[
          if (!widget.secondaryHost)
            IconButton(
              icon: const Icon(Icons.connected_tv_outlined),
              tooltip: AppLocalizations.of(context).posterBrowseEntryTooltip,
              onPressed: () {
                Navigator.of(context).pushNamed('/screen/poster-browse');
              },
            ),
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
    String token,
    String accessCode, {
    required bool hasRuntimeDynamicTheme,
  }) {
    final layout = MediaLayoutProfile.of(context);
    final session = context.watch<BackendSessionProvider>();
    final serverReady =
        session.currentKind.isServerFamily && session.isConfigured;
    final isConfigured =
        serverReady || context.watch<NasProvider>().isConfigured;
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

    final backendKind = context
        .read<MediaBackendProvider>()
        .backend
        .capabilities
        .kind;
    final profile = HomePresentationProfile.forKind(backendKind);
    final sections = visibleHomeSections(
      profile: profile,
      hasCatalogs: _categories.isNotEmpty,
      hasContinueWatching: _continueWatching.isNotEmpty,
      hasSummary: _mediaSummary.isNotEmpty,
      hasNextUp: _nextUp.isNotEmpty,
      hasLatest: _latest.isNotEmpty,
    );

    if (sections.isEmpty) {
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
              widget.secondaryHost
                  ? 20
                  : MainNavigationMetrics.contentBottomInset(
                      MediaQuery.viewPaddingOf(context).bottom,
                    ),
            ),
            sliver: SliverList.builder(
              itemCount: sections.length,
              itemBuilder: (context, index) {
                final section = sections[index];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == sections.length - 1
                        ? 0
                        : layout.sectionGap,
                  ),
                  child: RepaintBoundary(
                    child: _buildHomeSection(
                      section: section,
                      baseUrl: baseUrl,
                      token: token,
                      accessCode: accessCode,
                      layout: layout,
                      favorite: favorite,
                      total: total,
                      movie: movie,
                      tv: tv,
                      other: other,
                      hasRuntimeDynamicTheme: hasRuntimeDynamicTheme,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeSection({
    required HomeSectionKind section,
    required String baseUrl,
    required String token,
    required String accessCode,
    required MediaLayoutProfile layout,
    required int favorite,
    required int total,
    required int movie,
    required int tv,
    required int other,
    required bool hasRuntimeDynamicTheme,
  }) {
    final l10n = AppLocalizations.of(context);
    return switch (section) {
      HomeSectionKind.catalogs => _buildHomeCatalogs(
        baseUrl: baseUrl,
        token: token,
        accessCode: accessCode,
        layout: layout,
      ),
      HomeSectionKind.continueWatching => _buildHomeContinueWatching(
        baseUrl: baseUrl,
        token: token,
        accessCode: accessCode,
        layout: layout,
      ),
      HomeSectionKind.summary => _buildHomeSummary(
        favorite: favorite,
        total: total,
        movie: movie,
        tv: tv,
        other: other,
        hasRuntimeDynamicTheme: hasRuntimeDynamicTheme,
      ),
      HomeSectionKind.nextUp => _buildHomeNextUpShelf(
        title: l10n.nativeNotificationActionNextEpisode,
        items: _nextUp,
        baseUrl: baseUrl,
        token: token,
        accessCode: accessCode,
        layout: layout,
      ),
      HomeSectionKind.latest => _buildHomeMediaShelf(
        title: l10n.posterBrowseRowLatest,
        items: _latest,
        heroTagPrefix: 'home_latest',
        baseUrl: baseUrl,
        token: token,
        accessCode: accessCode,
        layout: layout,
      ),
      HomeSectionKind.catalogPreviews => _buildCatalogPreviews(
        baseUrl: baseUrl,
        token: token,
        accessCode: accessCode,
        layout: layout,
      ),
    };
  }

  Widget _buildHomeCatalogs({
    required String baseUrl,
    required String token,
    required String accessCode,
    required MediaLayoutProfile layout,
  }) {
    final backendKind = context
        .read<MediaBackendProvider>()
        .backend
        .capabilities
        .kind;
    final catalogPresentation = backendKind.homeCatalogPresentation;
    final categoriesById = <String, MediaItem>{
      for (final category in _categories) category.id: category,
    };
    final items = _categories
        .map(
          (category) => HomeCatalogCardData(
            id: category.id,
            title: category.name,
            mediaType: _homeCatalogMediaType(category),
            imageRequests: _homeCatalogImageRequests(
              category,
              presentation: catalogPresentation,
              baseUrl: baseUrl,
              token: token,
              accessCode: accessCode,
              requestWidth: layout.homeCatalogRequestWidth,
            ),
          ),
        )
        .toList(growable: false);
    return HomeCatalogSection(
      title: AppLocalizations.of(context).posterBrowseRowCatalogs,
      presentation: catalogPresentation,
      items: items,
      stableImageCacheWidth: layout.homeCatalogDecodeWidth,
      onTap: (item) {
        final category = categoriesById[item.id];
        if (category != null) _openCategory(category);
      },
    );
  }

  List<MediaImageRequest> _homeCatalogImageRequests(
    MediaItem category, {
    required HomeCatalogPresentation presentation,
    required String baseUrl,
    required String token,
    required String accessCode,
    required int requestWidth,
  }) {
    final sourcePaths = category.posters.isNotEmpty
        ? category.posters
        : (category.path?.trim().isNotEmpty ?? false)
        ? <String>[category.path!.trim()]
        : const <String>[];
    final preserved = _catalogImageRequests[category.id] ?? const [];
    const limit = 3;
    final candidateCount = min(
      max(sourcePaths.length, preserved.length),
      limit,
    );
    final catalogRequests = List<MediaImageRequest>.generate(candidateCount, (
      index,
    ) {
      final preservedRequest = index < preserved.length
          ? preserved[index]
          : null;
      final fallbackUrls = index < sourcePaths.length
          ? _posterCandidates(baseUrl, sourcePaths[index], width: requestWidth)
          : const <String>[];
      return preferPreservedImageRequest(
        preserved: preservedRequest?.canLoad == true ? preservedRequest : null,
        fallbackUrls: fallbackUrls,
        fallbackToken: token,
        fallbackAccessCode: accessCode,
        fallbackBaseUrl: baseUrl,
      );
    }).where((request) => request.canLoad).toList(growable: false);
    final previewItems = _itemsByCategory[category.id] ?? const [];
    return homeCatalogImageRequestsForPresentation(
      presentation: presentation,
      catalogRequests: catalogRequests,
      previewBackdropRequests: <MediaImageRequest>[
        for (final item in previewItems)
          if (_backdropImageRequests[item.guid]?.canLoad == true)
            _backdropImageRequests[item.guid]!,
      ],
      previewPrimaryRequests: <MediaImageRequest>[
        for (final item in previewItems)
          if (_itemImageRequests[item.guid]?.canLoad == true)
            _itemImageRequests[item.guid]!,
      ],
    );
  }

  HomeCatalogMediaType _homeCatalogMediaType(MediaItem category) {
    return switch (category.type?.trim().toLowerCase()) {
      'movie' || 'movies' => HomeCatalogMediaType.movies,
      'tv' || 'series' || 'tvshows' => HomeCatalogMediaType.series,
      'boxset' ||
      'boxsets' ||
      'collection' ||
      'collections' => HomeCatalogMediaType.collections,
      'mixed' => HomeCatalogMediaType.mixed,
      _ => HomeCatalogMediaType.other,
    };
  }

  Widget _buildHomeContinueWatching({
    required String baseUrl,
    required String token,
    required String accessCode,
    required MediaLayoutProfile layout,
  }) {
    return ListenableBuilder(
      listenable: DownloadTaskService.instance,
      builder: (context, _) {
        final itemsById = <String, MediaLibraryItem>{
          for (final item in _continueWatching) item.guid: item,
        };
        final cards = _continueWatching
            .map(
              (item) => HomeContinueCardData(
                id: item.guid,
                title: item.displayTitle,
                contextText: _continueContextText(item),
                progress: _progressValue(item),
                imageRequest: _homeLandscapeImageRequest(
                  item,
                  baseUrl: baseUrl,
                  token: token,
                  accessCode: accessCode,
                  requestWidth: layout.homeContinueRequestWidth,
                ),
                downloaded: DownloadTaskService.instance
                    .actionStateForItem(item.guid)
                    .downloaded,
              ),
            )
            .toList(growable: false);
        return HomeContinueWatchingSection(
          title: AppLocalizations.of(context).homeContinueWatching,
          items: cards,
          stableImageCacheWidth: layout.continueDecodeWidth,
          onOpenDetail: (card) {
            final item = itemsById[card.id];
            if (item != null) {
              _openItemDetail(
                continueDetailTarget(
                  item,
                  context
                      .read<MediaBackendProvider>()
                      .backend
                      .capabilities
                      .kind,
                ),
              );
            }
          },
          onPlay: (card) {
            final item = itemsById[card.id];
            if (item != null) unawaited(_playContinueItem(item));
          },
          onLongPress: (card) {
            final item = itemsById[card.id];
            if (item != null) {
              unawaited(_showContinueWatchingActionsV2(item));
            }
          },
        );
      },
    );
  }

  Widget _buildHomeNextUpShelf({
    required String title,
    required List<MediaLibraryItem> items,
    required String baseUrl,
    required String token,
    required String accessCode,
    required MediaLayoutProfile layout,
  }) {
    final itemsById = <String, MediaLibraryItem>{
      for (final item in items) item.guid: item,
    };
    final cards = items
        .map(
          (item) => HomeLandscapeCardData(
            id: item.guid,
            title: item.displayTitle,
            contextText: _continueEpisodeText(item),
            imageRequest: _homeLandscapeImageRequest(
              item,
              baseUrl: baseUrl,
              token: token,
              accessCode: accessCode,
              requestWidth: layout.homeContinueRequestWidth,
            ),
          ),
        )
        .toList(growable: false);
    return HomeLandscapeMediaSection(
      title: title,
      storageKey: 'next-up',
      items: cards,
      stableImageCacheWidth: layout.continueDecodeWidth,
      onOpenDetail: (card) {
        final item = itemsById[card.id];
        if (item != null) _openItemDetail(item);
      },
      onLongPress: (card) {
        final item = itemsById[card.id];
        if (item != null) _showPosterItemActions(item);
      },
    );
  }

  MediaImageRequest _homeLandscapeImageRequest(
    MediaLibraryItem item, {
    required String baseUrl,
    required String token,
    required String accessCode,
    required int requestWidth,
  }) {
    final backdropFallback = item.backdropUrl.trim().isEmpty
        ? const <String>[]
        : <String>[item.backdropUrl.trim()];
    final backdrop = preferPreservedImageRequest(
      preserved: _backdropImageRequests[item.guid],
      fallbackUrls: backdropFallback,
      fallbackToken: token,
      fallbackAccessCode: accessCode,
      fallbackBaseUrl: baseUrl,
    );
    final poster = preferPreservedImageRequest(
      preserved: _itemImageRequests[item.guid],
      fallbackUrls: _posterCandidates(
        baseUrl,
        item.poster,
        width: requestWidth,
      ),
      fallbackToken: token,
      fallbackAccessCode: accessCode,
      fallbackBaseUrl: baseUrl,
    );
    if (!backdrop.canLoad) return poster;
    if (!poster.canLoad ||
        !mapEquals(backdrop.headers, poster.headers) ||
        backdrop.selfAuthenticated != poster.selfAuthenticated) {
      return backdrop;
    }
    return MediaImageRequest(
      urls: <String>{...backdrop.urls, ...poster.urls}.toList(growable: false),
      headers: backdrop.headers,
      selfAuthenticated: backdrop.selfAuthenticated,
    );
  }

  String _continueContextText(MediaLibraryItem item) {
    final l10n = AppLocalizations.of(context);
    return item.type.trim().toLowerCase() == 'movie'
        ? l10n.listTypeMovie
        : _continueEpisodeText(item);
  }

  Widget _buildHomeSummary({
    required int favorite,
    required int total,
    required int movie,
    required int tv,
    required int other,
    required bool hasRuntimeDynamicTheme,
  }) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: _buildStatCard(
            l10n.actionFavoriteAdd,
            favorite,
            hasRuntimeDynamicTheme: hasRuntimeDynamicTheme,
            onTap: _openFavorites,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _buildStatCard(
            l10n.mediaAllItemsTitle,
            total,
            hasRuntimeDynamicTheme: hasRuntimeDynamicTheme,
            onTap: _openAllItems,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _buildStatCard(
            l10n.listTypeMovie,
            movie,
            hasRuntimeDynamicTheme: hasRuntimeDynamicTheme,
            onTap: () => _openAllItemsByType(l10n.listTypeMovie, const <String>[
              'Movie',
            ]),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _buildStatCard(
            l10n.listTypeTv,
            tv,
            hasRuntimeDynamicTheme: hasRuntimeDynamicTheme,
            onTap: () =>
                _openAllItemsByType(l10n.listTypeTv, const <String>['TV']),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _buildStatCard(
            l10n.commonOther,
            other,
            hasRuntimeDynamicTheme: hasRuntimeDynamicTheme,
            onTap: () => _openAllItemsByType(l10n.commonOther, const <String>[
              'Directory',
              'Video',
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildHomeMediaShelf({
    required String title,
    required List<MediaLibraryItem> items,
    required String heroTagPrefix,
    required String baseUrl,
    required String token,
    required String accessCode,
    required MediaLayoutProfile layout,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        HomeSectionHeader(title: title),
        const SizedBox(height: 8),
        _buildPosterRow(
          items,
          baseUrl,
          token,
          accessCode,
          layout,
          heroTagPrefix: heroTagPrefix,
        ),
      ],
    );
  }

  Widget _buildCatalogPreviews({
    required String baseUrl,
    required String token,
    required String accessCode,
    required MediaLayoutProfile layout,
  }) {
    final categories = _categories
        .where(
          (category) =>
              (_itemsByCategory[category.id] ?? const <MediaLibraryItem>[])
                  .isNotEmpty,
        )
        .toList(growable: false);
    if (categories.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var index = 0; index < categories.length; index++) ...<Widget>[
          if (index > 0) SizedBox(height: layout.sectionGap),
          _buildSectionTitle(categories[index]),
          const SizedBox(height: 8),
          _buildPosterRow(
            _itemsByCategory[categories[index].id]!,
            baseUrl,
            token,
            accessCode,
            layout,
            heroTagPrefix: 'home_catalog_${categories[index].id}',
          ),
        ],
      ],
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
                fontWeight: FontWeight.w600,
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
              fontWeight: FontWeight.w600,
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
    String accessCode,
    MediaLayoutProfile layout, {
    required String heroTagPrefix,
  }) {
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
      height: layout.homePosterRowHeightFor(MediaQuery.textScalerOf(context)),
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
              images: preferPreservedImageRequest(
                preserved: _itemImageRequests[item.guid],
                fallbackUrls: urls,
                fallbackToken: token,
                fallbackAccessCode: accessCode,
                fallbackBaseUrl: baseUrl,
              ),
              title: item.displayTitle,
              subtitle: _cardSubtitle(item),
              rating: rating,
              resolutions: resolutions,
              watched: item.watched == 1,
              imageHeight: layout.homePosterImageHeight,
              decodeWidth: layout.homePosterDecodeWidth,
              titleFontSize: layout.homePosterTitleFontSize,
              subtitleFontSize: layout.homePosterSubtitleFontSize,
              titleFontWeight: FontWeight.w500,
              subtitleFontWeight: FontWeight.w400,
              imageFit: _isEpisodeItem(item) ? BoxFit.contain : BoxFit.cover,
              heroTag: '${heroTagPrefix}_${item.guid}_$index',
              onTap: () => _openItemDetail(
                item,
                heroTag: '${heroTagPrefix}_${item.guid}_$index',
              ),
              onLongPress: () => _showPosterItemActions(item),
            ),
          );
        },
      ),
    );
  }
}
