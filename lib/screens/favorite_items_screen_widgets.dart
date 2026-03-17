part of 'favorite_items_screen.dart';

extension _FavoriteItemsScreenWidgets on _FavoriteItemsScreenState {
  Widget _buildTabButton(_FavoriteTab tab, String text) {
    final selected = _selectedTab == tab;
    final colors = context.appColors;
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
                  color: selected ? colors.selectionStrong : colors.textPrimary,
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
                  color: selected ? colors.selection : Colors.transparent,
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
          child: _buildGrid(
            tab: tab,
            baseUrl: provider.baseUrl,
            token: provider.token,
            layout: layout,
          ),
        ),
      ],
    );
  }

  Widget _buildScreen(BuildContext context) {
    final provider = context.read<NasProvider>();
    final layout = MediaLayoutProfile.of(context);
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: AppBar(
        backgroundColor: colors.backgroundBase,
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
        title: Text(_t('layout.sidebar.favorite', '收藏')),
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
                  _t('layout.list.favoriteTabs.all', '全部'),
                ),
                _buildTabButton(
                  _FavoriteTab.movie,
                  _t('layout.list.favoriteTabs.movie', '电影'),
                ),
                _buildTabButton(
                  _FavoriteTab.tv,
                  _t('layout.list.favoriteTabs.tv', '电视节目'),
                ),
                _buildTabButton(
                  _FavoriteTab.episode,
                  _t('layout.list.favoriteTabs.episode', '单集'),
                ),
                _buildTabButton(
                  _FavoriteTab.person,
                  _t('layout.list.favoriteTabs.person', '人物'),
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
    );
  }

  Widget _buildSortFilterRow(MediaLayoutProfile layout, _FavoriteTab tab) {
    final tabData = _dataOf(tab);
    final showFilter = tab != _FavoriteTab.person;
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
    required String baseUrl,
    required String token,
    required MediaLayoutProfile layout,
  }) {
    final data = _dataOf(tab);
    final colors = context.appColors;
    if (data.isLoading && data.items.isEmpty) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
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
          _t('common.other.empty', '没有内容'),
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
          cacheExtent: MediaQuery.of(context).size.height * 2,
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
              urls: _posterCandidates(baseUrl, item, width: 280),
              token: token,
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
              cacheExtent: MediaQuery.of(context).size.height * 2,
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
                final urls = _posterCandidates(baseUrl, posterItem, width: 720);
                final rating = double.tryParse(posterItem.voteAverage);
                final resolutions = posterItem.resolutions
                    .map(_resolutionLabel)
                    .where((value) => value.isNotEmpty)
                    .toList();
                return MediaPosterCard(
                  urls: urls,
                  token: token,
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
          cacheExtent: MediaQuery.of(context).size.height * 2,
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
            final urls = _posterCandidates(
              baseUrl,
              item,
              width: layout.categoryGridRequestWidth,
            );
            final rating = double.tryParse(item.voteAverage);
            final resolutions = item.resolutions
                .map(_resolutionLabel)
                .where((value) => value.isNotEmpty)
                .toList();
            return MediaPosterCard(
              urls: urls,
              token: token,
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
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.accent,
                ),
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
                label: Text(_t('layout.globalError.refresh', '刷新重试')),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: active ? colors.selectionSoft : colors.backgroundElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? colors.selection : colors.borderSubtle,
          ),
        ),
        child: Icon(
          icon,
          color: active ? colors.selectionStrong : colors.textSecondary,
          size: 21,
        ),
      ),
    );
  }
}
