part of 'fly_catalog_screen.dart';

extension _FlyCatalogView on _FlyCatalogScreenState {
  Widget _buildCatalog(BuildContext context) {
    final account = context.watch<FlyAccountController>();
    if (account.session == null) return const FlyLoginScreen();
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return AppAmbientPage(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: buildSecondaryHostAppBar(
          context,
          title: Text(l10n.flyCatalogSyncedTitles),
          actions: [
            AppInfoPopoverAnchor(
              title: l10n.flyCatalogSyncedTitles,
              description: l10n.flyCatalogSyncedInfoDescription,
              detail: l10n.flyCatalogSyncedInfoConnectionHint,
              child: Tooltip(
                message: l10n.flyCatalogSyncedInfoTooltip,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    Icons.info_outline_rounded,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: l10n.flyAccountTitle,
              icon: const Icon(Icons.dns_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const FlyBindingsScreen(),
                ),
              ),
            ),
            IconButton(
              tooltip: l10n.flyCatalogRefreshTitles,
              icon: const Icon(Icons.refresh_rounded),
              onPressed: loading ? null : () => _load(),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final inset = constraints.maxWidth >= 900 ? 28.0 : 16.0;
            final gap = constraints.maxWidth >= 900 ? 20.0 : 14.0;
            final available = constraints.maxWidth - inset * 2;
            final columns = ((available + gap) / (160 + gap)).floor().clamp(
              2,
              7,
            );
            final width = (available - gap * (columns - 1)) / columns;
            final textHeight =
                MediaQuery.textScalerOf(context).scale(14) * 3 + 20;
            return RefreshIndicator(
              onRefresh: () => _load(),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(inset, 8, inset, 20),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.cloud_done_outlined,
                                size: 18,
                                color: colors.accent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  account.activeBinding?['label'] as String? ??
                                      l10n.flyCatalogAllSources,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: colors.textSecondary),
                                ),
                              ),
                              if (total != null)
                                Text(
                                  l10n.flyCatalogTitleCount(total!),
                                  style: TextStyle(color: colors.textSecondary),
                                ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          TextField(
                            controller: search,
                            onSubmitted: (_) => _load(),
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                              hintText: l10n.flyCatalogSearchHint,
                              filled: true,
                              fillColor: colors.surface.withValues(alpha: .7),
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: IconButton(
                                tooltip: l10n.flyCatalogSearchTitles,
                                onPressed: loading ? null : () => _load(),
                                icon: const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 20,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 14,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              for (final filter in [
                                ('', l10n.commonAll),
                                ('series', l10n.playStatsMediaTypeSeries),
                                ('movie', l10n.listTypeMovie),
                              ])
                                ChoiceChip(
                                  label: Text(filter.$2),
                                  selected: _kind == filter.$1,
                                  onSelected: loading
                                      ? null
                                      : (_) => _setKind(filter.$1),
                                ),
                            ],
                          ),
                          if (message != null && items.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 18,
                                  color: colors.textSecondary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    message!,
                                    style: TextStyle(
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => _load(),
                                  child: Text(l10n.commonRetry),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (!loading && items.isEmpty && message != null)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AppErrorState(
                            error: AppException(
                              kind: AppExceptionKind.transient,
                              action: l10n.flyCatalogLoadTitlesAction,
                              message: message!,
                            ),
                            onRetry: () => _load(),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                            child: Text(
                              message!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (loading && items.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: BirdLoader(size: 90)),
                    )
                  else if (items.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.video_library_outlined,
                                size: 52,
                                color: colors.textSecondary.withValues(
                                  alpha: .5,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                search.text.trim().isEmpty
                                    ? l10n.flyCatalogEmpty
                                    : l10n.flyCatalogNoSearchResults,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                search.text.trim().isEmpty
                                    ? l10n.flyCatalogEmptyHint
                                    : l10n.flyCatalogNoSearchResultsHint,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: colors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (items.isNotEmpty)
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: inset),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: gap,
                          mainAxisSpacing: 20,
                          mainAxisExtent: width * 1.5 + textHeight,
                        ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final item = items[index];
                          return _FlyCatalogCard(
                            key: ValueKey('$_account:$_binding:${item['id']}'),
                            item: item,
                            opening: _opening == item['id'],
                            onTap: _opening.isEmpty
                                ? () => _openItem(item)
                                : null,
                            onInfo: () => _showInfo(item),
                          );
                        }, childCount: items.length),
                      ),
                    ),
                  if (cursor != null)
                    SliverToBoxAdapter(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: OutlinedButton.icon(
                            onPressed: loading ? null : () => _load(more: true),
                            icon: loading
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.expand_more_rounded),
                            label: Text(l10n.flyCatalogLoadMore),
                          ),
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FlyCatalogCard extends StatelessWidget {
  const _FlyCatalogCard({
    super.key,
    required this.item,
    required this.opening,
    required this.onTap,
    required this.onInfo,
  });
  final Map<String, dynamic> item;
  final bool opening;
  final VoidCallback? onTap;
  final VoidCallback onInfo;
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final title = item['title'] as String? ?? '';
    final rating = (item['rating'] as num?)?.toDouble();
    return HoverLift(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: colors.surface,
                      child: item['poster_url'] == null
                          ? Icon(
                              Icons.movie_outlined,
                              size: 40,
                              color: colors.textSecondary.withValues(alpha: .5),
                            )
                          : FlyCatalogPoster(mediaId: item['id'] as String),
                    ),
                    if (rating != null && rating > 0)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colors.accent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            rating.toStringAsFixed(1),
                            style: TextStyle(
                              color:
                                  ThemeData.estimateBrightnessForColor(
                                        colors.accent,
                                      ) ==
                                      Brightness.dark
                                  ? Colors.white
                                  : Colors.black,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Material(
                        color: colors.surface.withValues(alpha: .92),
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: l10n.flyCatalogSyncInfoForTitle(title),
                          onPressed: onInfo,
                          constraints: const BoxConstraints.tightFor(
                            width: 34,
                            height: 34,
                          ),
                          padding: EdgeInsets.zero,
                          iconSize: 19,
                          icon: Icon(
                            Icons.info_outline_rounded,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    if (opening)
                      ColoredBox(
                        color: Colors.black38,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: colors.accent,
                            strokeWidth: 3,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (item['year'] != null) '${item['year']}',
                _kindLabel(l10n, item['kind']),
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
