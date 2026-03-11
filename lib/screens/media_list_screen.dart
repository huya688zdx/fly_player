import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../models/media_item.dart';
import '../models/media_library_item.dart';
import '../providers/nas_provider.dart';
import '../ui/app_transitions.dart';
import '../ui/layout_adaptive.dart';
import '../ui/media_poster_card.dart';
import '../utils/app_confirm_dialog.dart';
import '../utils/api_url_helper.dart';
import '../utils/app_exception.dart';
import '../utils/media_locale_store.dart';
import '../utils/media_locale_text.dart';
import '../widgets/common/app_error_state.dart';
import 'category_items_screen.dart';
import 'favorite_items_screen.dart';
import 'person_detail_screen.dart';
import 'play_detail_screen.dart';
import 'search_screen.dart';

class MediaListScreen extends StatefulWidget {
  const MediaListScreen({super.key});

  @override
  State<MediaListScreen> createState() => _MediaListScreenState();
}

class _MediaListScreenState extends State<MediaListScreen> {
  static const int _fallbackContinueLimit = 12;

  List<MediaItem> _categories = [];
  Map<String, List<MediaLibraryItem>> _itemsByCategory = {};
  List<MediaLibraryItem> _continueWatching = [];
  Map<String, dynamic> _mediaSummary = {};
  Map<String, dynamic> _localeMap = {};
  String _lastLoadKey = '';

  bool _isLoading = false;
  AppException? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<NasProvider>();
    final loadKey = '${provider.baseUrl}|${provider.token}';
    if (provider.isConfigured && loadKey != _lastLoadKey) {
      _lastLoadKey = loadKey;
      _fetchHomeData();
    }
  }

  Future<void> _fetchHomeData() async {
    debugPrint('[UI][HOME] start loading home data');
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final provider = context.read<NasProvider>();
      final api = FeiniuApi(provider);
      final categories = await api.getMediaList();
      final summary = await api.getMediaSummary();
      final playList = await api.getPlayList();
      final localeMap = await MediaLocaleStore.load(provider);

      final itemsByCategory = <String, List<MediaLibraryItem>>{};
      final allItems = <MediaLibraryItem>[];

      for (final category in categories) {
        try {
          final items = await api.getItemsByCategoryGuid(
            category.id,
            page: 1,
            limit: 30,
          );
          itemsByCategory[category.id] = items;
          allItems.addAll(items);
        } catch (e) {
          debugPrint('[UI][HOME] category load failed ${category.id}: $e');
          itemsByCategory[category.id] = [];
        }
      }

      final continueWatching = playList.isNotEmpty
          ? playList.take(_fallbackContinueLimit).toList()
          : _pickContinueWatching(allItems);

      if (!mounted) return;
      setState(() {
        _categories = categories;
        _itemsByCategory = itemsByCategory;
        _continueWatching = continueWatching;
        _mediaSummary = summary;
        _localeMap = localeMap;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[UI][HOME] load failed $e');
      if (!mounted) return;
      setState(() {
        _error = AppException.from(
          e,
          action: 'home data',
          fallbackKind: AppExceptionKind.transient,
        );
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshContinueWatching() async {
    final provider = context.read<NasProvider>();
    if (!provider.isConfigured) return;

    try {
      final api = FeiniuApi(provider);
      final playList = await api.getPlayList();
      if (!mounted) return;
      setState(() {
        _continueWatching = playList.take(_fallbackContinueLimit).toList();
      });
    } catch (error) {
      debugPrint('[UI][HOME] continue watching refresh failed $error');
    }
  }

  List<MediaLibraryItem> _pickContinueWatching(List<MediaLibraryItem> items) {
    final watched =
        items
            .where((e) => e.watched > 0 || e.watchedTs > 0 || e.ts > 0)
            .toList()
          ..sort((a, b) => b.watchedTs.compareTo(a.watchedTs));

    if (watched.isNotEmpty) {
      return watched.take(_fallbackContinueLimit).toList();
    }
    return items.take(_fallbackContinueLimit).toList();
  }

  int _summaryInt(String key, int fallback) {
    final value = _mediaSummary[key];
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  String _t(
    String path,
    String fallback, {
    Map<String, Object?> params = const {},
  }) {
    return MediaLocaleText.text(
      _localeMap,
      path,
      fallback: fallback,
      params: params,
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: _t('auth.exit.title', '退出登录'),
      content: _t('auth.exit.content', '确认退出当前帐号？'),
      cancelText: _t('common.actions.default.cancel', '取消'),
      confirmText: _t('common.actions.default.default', '确认'),
    );
    if (!mounted || !confirmed) return;
    await context.read<NasProvider>().logout();
  }

  void _openCategory(MediaItem category) {
    Navigator.of(context).push(
      AppTransitions.fadeSlideRoute(CategoryItemsScreen(category: category)),
    );
  }

  void _openAllItems() {
    Navigator.of(context).push(
      AppTransitions.fadeSlideRoute(
        CategoryItemsScreen(
          category: MediaItem(
            id: '',
            name: _t('layout.sidebar.allList', '全部影视'),
          ),
        ),
      ),
    );
  }

  void _openAllItemsByType(String title, List<String> types) {
    Navigator.of(context).push(
      AppTransitions.fadeSlideRoute(
        CategoryItemsScreen(
          category: MediaItem(id: '', name: title),
          initialTypeTags: types,
        ),
      ),
    );
  }

  void _openFavorites() {
    Navigator.of(
      context,
    ).push(AppTransitions.fadeSlideRoute(const FavoriteItemsScreen()));
  }

  Future<void> _openItemDetail(MediaLibraryItem item, {String? heroTag}) async {
    if (item.guid.trim().isEmpty) return;
    if (_isPersonItem(item)) {
      if (!mounted) return;
      Navigator.of(context).push(
        AppTransitions.leftToRightPageTurnRoute(
          PersonDetailScreen(
            personGuid: item.guid,
            initialName: item.displayTitle,
            initialLocaleMap: _localeMap,
          ),
        ),
      );
      return;
    }
    final navigator = Navigator.of(context);
    final provider = context.read<NasProvider>();
    final heroPath = item.poster.trim();
    final warmupUrls = _posterCandidates(
      provider.baseUrl,
      heroPath,
      width: 560,
    );
    if (warmupUrls.isNotEmpty) {
      try {
        await precacheImage(
          NetworkImage(
            warmupUrls.first,
            headers: {
              'Authorization': provider.token,
              'Trim-MC-token': provider.token,
            },
          ),
          navigator.context,
        ).timeout(const Duration(milliseconds: 140));
      } catch (error) {
        debugPrint(
          '[IMG][PRECACHE][HOME] failed url=${warmupUrls.first} error=$error',
        );
      }
    }
    Map<String, dynamic>? initialDetail;
    try {
      initialDetail = await FeiniuApi(
        provider,
      ).getItemDetail(item.guid).timeout(const Duration(milliseconds: 240));
    } catch (_) {}
    if (!mounted) return;
    await navigator.push(
      AppTransitions.leftToRightPageTurnRoute(
        PlayDetailScreen(
          itemGuid: item.guid,
          heroTag: null,
          initialItemDetail: initialDetail,
        ),
      ),
    );
    if (!mounted) return;
    unawaited(_refreshContinueWatching());
  }

  bool _isEpisodeItem(MediaLibraryItem item) {
    return item.type.trim().toLowerCase() == 'episode';
  }

  bool _isPersonItem(MediaLibraryItem item) {
    return item.type.trim().toLowerCase() == 'person';
  }

  List<String> _posterCandidates(
    String baseUrl,
    String rawPath, {
    int width = 400,
  }) {
    return ApiUrlHelper.imageCandidates(baseUrl, rawPath, width: width);
  }

  String _year(String date) => date.length >= 4 ? date.substring(0, 4) : '';

  String _cardSubtitle(MediaLibraryItem item) {
    final start = item.firstAirDate.isNotEmpty
        ? item.firstAirDate
        : item.releaseDate;
    final startYear = _year(start);
    final endYear = _year(item.lastAirDate);
    final period =
        (startYear.isNotEmpty && endYear.isNotEmpty && endYear != startYear)
        ? '$startYear-$endYear'
        : startYear;

    final seasonCount = item.localNumberOfSeasons > 0
        ? item.localNumberOfSeasons
        : item.numberOfSeasons;
    final episodeCount = item.localNumberOfEpisodes > 0
        ? item.localNumberOfEpisodes
        : (item.numberOfEpisodes > 0
              ? item.numberOfEpisodes
              : item.episodeNumber);

    if (seasonCount == 1) {
      final episodes = episodeCount;
      if (episodes > 0) {
        final epText = _t(
          'layout.subheading.tv.episodes',
          '共 {count} 集',
          params: {'count': episodes},
        );
        if (period.isEmpty) return epText;
        return '$epText · $period';
      }
    }
    if (seasonCount > 0) {
      final seasonText = _t(
        'layout.subheading.tv.seasons',
        '共 {count} 季',
        params: {'count': seasonCount},
      );
      if (period.isEmpty) return seasonText;
      return '$seasonText · $period';
    }
    return period;
  }

  String _resolutionLabel(String value) {
    final text = value.trim();
    final match = RegExp(
      r'^(\d{3,4})p$',
      caseSensitive: false,
    ).firstMatch(text);
    if (match != null) return match.group(1) ?? text;
    return text;
  }

  String _episodeText(MediaLibraryItem item) {
    final season = item.seasonNumber > 0 ? item.seasonNumber : 1;
    final episode = item.episodeNumber > 0 ? item.episodeNumber : 1;
    final seasonText = _t(
      'layout.subheading.season.number',
      '第 {number} 季',
      params: {'number': season},
    );
    final episodeText = _t(
      'layout.subheading.episode.number',
      '第 {number} 集',
      params: {'number': episode},
    );
    return '$seasonText · $episodeText';
  }

  String _continueEpisodeText(MediaLibraryItem item) {
    final episode = item.episodeNumber > 0 ? item.episodeNumber : 1;
    if (item.seasonNumber == 0) {
      final specialText = _t('layout.subheading.season.special', '特别篇');
      final episodeText = _t(
        'layout.subheading.episode.number',
        '第 {number} 集',
        params: {'number': episode},
      );
      return '$specialText · $episodeText';
    }
    return _episodeText(item);
  }

  double _progressValue(MediaLibraryItem item) {
    if (item.duration <= 0) return 0;
    final raw = item.ts / item.duration;
    return raw.clamp(0, 1).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<NasProvider>();
    final baseUrl = provider.baseUrl;
    final token = provider.token;

    return Scaffold(
      backgroundColor: const Color(0xFF07101B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF07101B),
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _confirmLogout();
          },
        ),
        title: Text(_t('layout.sidebar.home', '首页')),
        actions: [
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
      body: _buildBody(baseUrl, token),
    );
  }

  Widget _buildBody(String baseUrl, String token) {
    final layout = MediaLayoutProfile.of(context);
    final isConfigured = context.watch<NasProvider>().isConfigured;
    if (!isConfigured) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            '请先到“设置”页登录 NAS，再返回影视页加载内容。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ),
      );
    }

    if (_isLoading) return const Center(child: CircularProgressIndicator());

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
          style: const TextStyle(color: Colors.white70),
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
        cacheExtent: 1200,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
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
                    children: [
                      _buildSectionTitle(category),
                      const SizedBox(height: 8),
                      _buildPosterRow(
                        _itemsByCategory[category.id] ?? [],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCategoryStrip(baseUrl, token, layout),
        const SizedBox(height: 10),
        if (_continueWatching.isNotEmpty) ...[
          Text(
            _t('layout.list.continueWatching', '继续观看'),
            style: const TextStyle(
              color: Colors.white,
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
              cacheExtent: layout.continueCardWidth * 5,
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
          children: [
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
                  const ['Movie'],
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
                  const ['TV'],
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
                  const ['Directory', 'Video'],
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
    final count = min(_categories.length, 10);
    return SizedBox(
      height: layout.categoryStripHeight,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        scrollDirection: Axis.horizontal,
        cacheExtent: layout.categoryCardWidth * 6,
        itemCount: count,
        separatorBuilder: (_, __) => SizedBox(width: layout.itemGap),
        itemBuilder: (context, index) {
          final category = _categories[index];
          final source = category.posters.isNotEmpty
              ? category.posters
              : (category.path?.isNotEmpty ?? false)
              ? [category.path!]
              : const <String>[];
          final posters = source.take(3).toList();
          return _CategoryPosterCard(
            title: category.name,
            posterUrls: posters
                .map(
                  (e) => _posterCandidates(
                    baseUrl,
                    e,
                    width: (layout.categoryMiniPosterWidth * 3).round(),
                  ),
                )
                .toList(),
            token: token,
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
    final heroTag = 'home_continue_${item.guid}';
    final urls = _posterCandidates(
      baseUrl,
      item.poster,
      width: layout.homeContinueRequestWidth,
    );
    final progress = _progressValue(item);
    return InkWell(
      onTap: () => _openItemDetail(item, heroTag: heroTag),
      borderRadius: BorderRadius.circular(10),
      child: RepaintBoundary(
        child: SizedBox(
          width: layout.continueCardWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Hero(
                tag: heroTag,
                child: Container(
                  height: layout.continueImageHeight,
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: const Color(0xFF243041),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _PosterImage(
                        urls: urls,
                        token: token,
                        fallback: const Center(
                          child: Icon(Icons.movie, color: Colors.white38),
                        ),
                      ),
                      if (progress > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            height: 4,
                            color: const Color(0x557B8CA3),
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: progress,
                              child: Container(color: const Color(0xFF2D87FF)),
                            ),
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
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                _continueEpisodeText(item),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, int value, {VoidCallback? onTap}) {
    final child = Container(
      height: 58,
      decoration: BoxDecoration(
        color: const Color(0xFF1D2735),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          Text(
            '$value',
            style: const TextStyle(
              color: Colors.white,
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
    return InkWell(
      onTap: () => _openCategory(category),
      child: Row(
        children: [
          Text(
            category.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: Colors.white54, size: 20),
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
    if (items.isEmpty) {
      return SizedBox(
        height: 220,
        child: Center(
          child: Text(
            _t('common.other.empty', '没有内容'),
            style: const TextStyle(color: Colors.white54),
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
        cacheExtent: layout.homePosterCardWidth * 6,
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
              .where((e) => e.isNotEmpty)
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
              imageHeight: layout.homePosterImageHeight,
              titleFontSize: layout.homePosterTitleFontSize,
              subtitleFontSize: layout.homePosterSubtitleFontSize,
              imageFit: _isEpisodeItem(item) ? BoxFit.contain : BoxFit.cover,
              heroTag: 'home_row_${item.guid}_$index',
              onTap: () => _openItemDetail(
                item,
                heroTag: 'home_row_${item.guid}_$index',
              ),
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
  final double cardWidth;
  final double miniPosterWidth;
  final double miniPosterHeight;
  final VoidCallback? onTap;

  const _CategoryPosterCard({
    required this.title,
    required this.posterUrls,
    required this.token,
    required this.cardWidth,
    required this.miniPosterWidth,
    required this.miniPosterHeight,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
              color: const Color(0xFF131D2A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0x3361768E), width: 0.8),
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    color: const Color(0xFF111A27),
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
                                  fallback: Container(
                                    color: const Color(0xFF223142),
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
                        colors: [
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.08),
                          Colors.black.withValues(alpha: 0.46),
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.05,
                      shadows: [
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
  final Widget fallback;

  const _PosterImage({
    required this.urls,
    required this.token,
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
    final headers = widget.token.trim().isNotEmpty
        ? <String, String>{
            'Authorization': widget.token,
            'Trim-MC-token': widget.token,
          }
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.of(context).devicePixelRatio;
        final cacheW = constraints.maxWidth.isFinite
            ? (constraints.maxWidth * dpr).round().clamp(80, 1000)
            : null;
        final cacheH = constraints.maxHeight.isFinite
            ? (constraints.maxHeight * dpr).round().clamp(80, 1000)
            : null;
        return Image.network(
          current,
          fit: BoxFit.cover,
          headers: headers,
          filterQuality: FilterQuality.none,
          gaplessPlayback: true,
          cacheWidth: cacheW,
          cacheHeight: cacheH,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            final loaded = wasSynchronouslyLoaded || frame != null;
            return Stack(
              fit: StackFit.expand,
              children: [
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
                if (mounted) setState(() => _index++);
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
