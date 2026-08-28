part of 'favorite_items_screen.dart';

extension _FavoriteItemsScreenWidgets on _FavoriteItemsScreenState {
  Widget _buildTabButton(_FavoriteTab tab, String text) {
    final selected = _selectedTab == tab;
    final colors = context.appColors;
    final selectedColors = AppTonalControlPalette.resolve(
      colors: colors,
      active: true,
    );
    return Expanded(
      child: InkWell(
        onTap: () => _switchTab(tab),
        child: SizedBox(
          height: 42,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                text,
                style: TextStyle(
                  color: selected
                      ? selectedColors.foreground
                      : colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 16,
                height: 3,
                decoration: BoxDecoration(
                  color: selected
                      ? selectedColors.foreground
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentTabPage(
    MediaLayoutProfile layout,
    NasProvider provider,
    _FavoriteTab tab,
  ) {
    return Column(
      children: <Widget>[
        _buildSortFilterRow(layout, tab),
        Expanded(
          child: _buildGrid(tab: tab, layout: layout),
        ),
      ],
    );
  }

  Widget _buildScreen(BuildContext context) {
    final provider = context.read<NasProvider>();
    final layout = MediaLayoutProfile.of(context);
    final colors = context.appColors;
    final atmosphere = AppAtmospherePalette.resolve(
      baseColors: context.baseAppColors,
      effectiveColors: colors,
      hasDynamicTheme: context.hasRuntimeAppColors,
    );
    return AppAtmosphericBackground(
      palette: atmosphere,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          foregroundColor: colors.textPrimary,
          iconTheme: IconThemeData(color: colors.textPrimary),
          actionsIconTheme: IconThemeData(color: colors.textPrimary),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              unawaited(
                widget.secondaryHost
                    ? EmbeddedDetailLauncher.closeHostOrPop(context)
                    : Navigator.of(context).maybePop(),
              );
            },
          ),
          titleTextStyle: TextStyle(
            color: colors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
          title: Text(AppLocalizations.of(context).actionFavoriteAdd),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                Navigator.of(context).push(
                  AppTransitions.fadeSlideRoute(
                    SearchScreen(initialLocaleMap: _localeMap),
                  ),
                );
              },
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: <Widget>[
                  _buildTabButton(
                    _FavoriteTab.all,
                    AppLocalizations.of(context).commonAll,
                  ),
                  _buildTabButton(
                    _FavoriteTab.movie,
                    AppLocalizations.of(context).listTypeMovie,
                  ),
                  _buildTabButton(
                    _FavoriteTab.tv,
                    AppLocalizations.of(context).listTypeTv,
                  ),
                  _buildTabButton(
                    _FavoriteTab.episode,
                    AppLocalizations.of(context).favoriteTabEpisodes,
                  ),
                  _buildTabButton(
                    _FavoriteTab.person,
                    AppLocalizations.of(context).favoriteTabPeople,
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const BouncingScrollPhysics(),
                children: _FavoriteTab.values
                    .map((tab) => _buildCurrentTabPage(layout, provider, tab))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSortFilterRow(MediaLayoutProfile layout, _FavoriteTab tab) {
    final tabData = _dataOf(tab);
    final showFilter = tab != _FavoriteTab.person && _isFeiniuBackend;
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Row(
              children: <Widget>[
                InkWell(
                  onTap: _openSortSheet,
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: <Widget>[
                      Text(
                        _sortLabelFor(_sortColumn),
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _sortType == 'ASC'
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        size: 16,
                        color: colors.textSecondary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${max(tabData.total, tabData.items.length)}',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _FavoriteToolButton(
            icon: Icons.grid_view_rounded,
            active: _viewType != MediaCollectionViewType.list,
            onTap: _openLayoutSheet,
          ),
          if (showFilter) ...<Widget>[
            const SizedBox(width: 10),
            Tooltip(
              message: _filterSummaryLabel,
              child: _FavoriteToolButton(
                icon: Icons.filter_alt_outlined,
                active: _hasActiveFilters,
                onTap: _openFilterSheet,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGrid({
    required _FavoriteTab tab,
    required MediaLayoutProfile layout,
  }) {
    final data = _dataOf(tab);
    final colors = context.appColors;
    if (data.isLoading && data.items.isEmpty) {
      return const Center(child: BirdLoader(size: 120));
    }
    if (data.error != null) {
      return AppErrorState(
        error: data.error!,
        localeMap: _localeMap,
        onRetry: () => _fetch(tab: tab, reset: true),
      );
    }
    if (data.items.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context).commonEmpty,
          style: TextStyle(color: colors.textSecondary),
        ),
      );
    }

    final bottomPadding =
        16.0 + (data.isLoadingMore || data.loadMoreError != null ? 44.0 : 0.0);
    late final Widget content;

    switch (_viewType) {
      case MediaCollectionViewType.list:
        content = ListView.separated(
          controller: _tabScrollControllers[tab],
          cacheExtent: _viewportCacheExtent(context),
          padding: EdgeInsets.fromLTRB(
            layout.pageHorizontalPadding,
            0,
            layout.pageHorizontalPadding,
            bottomPadding,
          ),
          itemCount: data.items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final item = data.items[index];
            return MediaLibraryListTile(
              images: _posterImages(item, width: 280),
              title: item.displayTitle,
              subtitle: _cardSubtitle(item),
              resolutions: item.resolutions
                  .map(_resolutionLabel)
                  .where((value) => value.isNotEmpty)
                  .toList(),
              onTap: () => _openItemDetail(item),
              onLongPress: () => _showFavoriteItemActions(item),
              onMoreTap: () => _showFavoriteItemActions(item),
            );
          },
        );
      case MediaCollectionViewType.horizontalPoster:
        content = LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = layout.isTablet ? 3 : 2;
            final availableWidth =
                constraints.maxWidth -
                layout.pageHorizontalPadding * 2 -
                layout.itemGap * (crossAxisCount - 1);
            final cardWidth = availableWidth / crossAxisCount;
            final imageHeight = cardWidth * 0.56;
            final rowHeight = imageHeight + 58;

            return GridView.builder(
              controller: _tabScrollControllers[tab],
              cacheExtent: _viewportCacheExtent(context),
              padding: EdgeInsets.fromLTRB(
                layout.pageHorizontalPadding,
                0,
                layout.pageHorizontalPadding,
                bottomPadding,
              ),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: layout.itemGap,
                crossAxisSpacing: layout.itemGap,
                mainAxisExtent: rowHeight,
              ),
              itemCount: data.items.length,
              itemBuilder: (context, index) {
                final item = data.items[index];
                final posterItem = _posterWallDisplayItem(item);
                final images = _posterImages(posterItem, width: 720);
                final rating = double.tryParse(posterItem.voteAverage);
                final resolutions = posterItem.resolutions
                    .map(_resolutionLabel)
                    .where((value) => value.isNotEmpty)
                    .toList();
                return MediaPosterCard(
                  images: images,
                  title: item.displayTitle,
                  subtitle: _cardSubtitle(item),
                  imageAspectRatioHint: posterItem.hasPosterSize
                      ? posterItem.posterWidth / posterItem.posterHeight
                      : null,
                  rating: rating,
                  resolutions: resolutions,
                  watched: item.watched == 1,
                  imageHeight: imageHeight,
                  titleFontSize: layout.homePosterTitleFontSize,
                  subtitleFontSize: layout.homePosterSubtitleFontSize,
                  expandImageToFit: false,
                  imageFit: BoxFit.contain,
                  autoFitByImageAspect: false,
                  heroTag: 'favorite_${tab.index}_${item.guid}_$index',
                  onTap: () => _openItemDetail(item),
                  onLongPress: () => _showFavoriteItemActions(item),
                );
              },
            );
          },
        );
      case MediaCollectionViewType.verticalPoster:
        content = GridView.builder(
          controller: _tabScrollControllers[tab],
          cacheExtent: _viewportCacheExtent(context),
          padding: EdgeInsets.fromLTRB(
            layout.pageHorizontalPadding,
            0,
            layout.pageHorizontalPadding,
            bottomPadding,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: layout.categoryGridColumns,
            mainAxisSpacing: layout.itemGap,
            crossAxisSpacing: layout.itemGap,
            mainAxisExtent: layout.categoryGridRowHeight,
          ),
          itemCount: data.items.length,
          itemBuilder: (context, index) {
            final item = data.items[index];
            final images = _posterImages(
              item,
              width: layout.categoryGridRequestWidth,
            );
            final rating = double.tryParse(item.voteAverage);
            final resolutions = item.resolutions
                .map(_resolutionLabel)
                .where((value) => value.isNotEmpty)
                .toList();
            return MediaPosterCard(
              images: images,
              title: item.displayTitle,
              subtitle: _cardSubtitle(item),
              rating: rating,
              resolutions: resolutions,
              watched: item.watched == 1,
              imageHeight: layout.categoryGridImageHeight,
              titleFontSize: layout.homePosterTitleFontSize,
              subtitleFontSize: layout.homePosterSubtitleFontSize,
              expandImageToFit: false,
              imageFit: _isEpisodeItem(item) ? BoxFit.contain : BoxFit.cover,
              heroTag: 'favorite_${tab.index}_${item.guid}_$index',
              onTap: () => _openItemDetail(item),
              onLongPress: () => _showFavoriteItemActions(item),
            );
          },
        );
    }

    return Stack(
      children: <Widget>[
        content,
        if (data.isLoadingMore)
          const Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: BirdGlyph(size: 20),
              ),
            ),
          ),
        if (data.loadMoreError != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 6,
            child: Center(
              child: TextButton.icon(
                onPressed: () => _fetch(tab: tab, reset: false),
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(AppLocalizations.of(context).commonRefreshRetry),
              ),
            ),
          ),
      ],
    );
  }
}

class _FavoriteToolButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _FavoriteToolButton({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final control = AppTonalControlPalette.resolve(
      colors: colors,
      active: active,
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: control.fill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: control.border),
        ),
        child: Icon(icon, color: control.foreground, size: 21),
      ),
    );
  }
}
