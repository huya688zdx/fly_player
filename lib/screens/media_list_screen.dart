import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../controllers/item_playback_launcher.dart';
import '../controllers/media_item_action_sheet_controller.dart';
import '../models/media_item.dart';
import '../models/media_library_item.dart';
import '../providers/app_theme_provider.dart';
import '../providers/nas_provider.dart';
import '../services/download_task_service.dart';
import '../services/embedded_detail_launcher.dart';
import '../services/parallel_browse_snapshot.dart';
import '../theme/app_theme.dart';
import '../theme/detail_tokens.dart';
import '../ui/app_transitions.dart';
import '../ui/layout_adaptive.dart';
import '../ui/media_poster_card.dart';
import '../utils/api_url_helper.dart';
import '../utils/app_confirm_dialog.dart';
import '../utils/app_exception.dart';
import '../utils/app_top_tip.dart';
import '../utils/media_locale_store.dart';
import '../utils/media_locale_text.dart';
import '../widgets/common/app_action_sheet.dart';
import '../widgets/common/app_error_state.dart';
import 'category_items_screen.dart';
import 'favorite_items_screen.dart';
import 'person_detail_screen.dart';
import 'play_detail_screen.dart';
import 'search_screen.dart';

part 'media_list_screen_actions.dart';
part 'media_list_screen_widgets.dart';

enum _ContinueWatchingAction {
  viewDetail,
  markWatched,
  favorite,
  restart,
  remove,
}

class MediaListScreen extends StatefulWidget {
  final bool secondaryHost;

  const MediaListScreen({super.key, this.secondaryHost = false});

  @override
  State<MediaListScreen> createState() => _MediaListScreenState();
}

class _MediaListScreenState extends State<MediaListScreen> {
  static const int _fallbackContinueLimit = 12;
  static const int _secondaryContinueLimit = 4;
  static const int _defaultCategoryPreviewLimit = 30;
  static const int _secondaryCategoryPreviewLimit = 8;

  List<MediaItem> _categories = <MediaItem>[];
  Map<String, List<MediaLibraryItem>> _itemsByCategory =
      <String, List<MediaLibraryItem>>{};
  List<MediaLibraryItem> _continueWatching = <MediaLibraryItem>[];
  Map<String, dynamic> _mediaSummary = <String, dynamic>{};
  Map<String, dynamic> _localeMap = <String, dynamic>{};
  String _lastLoadKey = '';

  bool _isLoading = false;
  AppException? _error;

  int get _continueLimit =>
      widget.secondaryHost ? _secondaryContinueLimit : _fallbackContinueLimit;

  int get _categoryPreviewLimit => widget.secondaryHost
      ? _secondaryCategoryPreviewLimit
      : _defaultCategoryPreviewLimit;

  double get _scrollCacheExtent => widget.secondaryHost ? 220 : 1200;

  double _rowCacheExtent(double itemExtent) {
    final multiplier = widget.secondaryHost ? 2 : 6;
    return itemExtent * multiplier;
  }

  @override
  void initState() {
    super.initState();
    unawaited(DownloadTaskService.instance.initialize());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        EmbeddedDetailLauncher.reportBrowseSnapshot(
          const ParallelBrowseSnapshot.home(originTab: 0),
        ),
      );
    });
  }

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
            limit: _categoryPreviewLimit,
          );
          itemsByCategory[category.id] = items;
          allItems.addAll(items);
        } catch (error) {
          debugPrint('[UI][HOME] category load failed ${category.id}: $error');
          itemsByCategory[category.id] = <MediaLibraryItem>[];
        }
      }

      final continueWatching = playList.isNotEmpty
          ? playList.take(_continueLimit).toList()
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
    } catch (error) {
      debugPrint('[UI][HOME] load failed $error');
      if (!mounted) return;
      setState(() {
        _error = AppException.from(
          error,
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
      final playList = await api.getPlayList(forceRefresh: true);
      if (!mounted) return;
      setState(() {
        _continueWatching = playList.take(_continueLimit).toList();
      });
    } catch (error) {
      debugPrint('[UI][HOME] continue watching refresh failed $error');
    }
  }

  void _showHomeSnackBar(String message, {Color? backgroundColor}) {
    if (!mounted) return;
    AppTopTip().show(
      context,
      message: message,
      color: backgroundColor ?? context.appColors.success,
    );
  }

  void _replaceItemLocally(
    String itemGuid,
    MediaLibraryItem Function(MediaLibraryItem item) transform,
  ) {
    if (!mounted) return;
    setState(() {
      _continueWatching = _continueWatching
          .map((item) => item.guid == itemGuid ? transform(item) : item)
          .toList(growable: false);
      _itemsByCategory = _itemsByCategory.map((key, value) {
        return MapEntry(
          key,
          value
              .map((item) => item.guid == itemGuid ? transform(item) : item)
              .toList(growable: false),
        );
      });
    });
  }

  void _applyState(VoidCallback update) {
    if (!mounted) return;
    setState(update);
  }

  List<MediaLibraryItem> _pickContinueWatching(List<MediaLibraryItem> items) {
    final watched =
        items
            .where(
              (item) => item.watched > 0 || item.watchedTs > 0 || item.ts > 0,
            )
            .toList()
          ..sort((a, b) => b.watchedTs.compareTo(a.watchedTs));

    if (watched.isNotEmpty) {
      return watched.take(_continueLimit).toList();
    }
    return items.take(_continueLimit).toList();
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
    Map<String, Object?> params = const <String, Object?>{},
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
    unawaited(_openCategoryAsync(category));
  }

  void _openAllItems() {
    unawaited(
      _openCategoryAsync(
        MediaItem(id: '', name: _t('layout.sidebar.allList', '全部影视')),
      ),
    );
    return;
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
    unawaited(
      _openCategoryAsync(
        MediaItem(id: '', name: title),
        initialTypeTags: types,
      ),
    );
    return;
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
    unawaited(_openFavoritesAsync());
    return;
    Navigator.of(
      context,
    ).push(AppTransitions.fadeSlideRoute(const FavoriteItemsScreen()));
  }

  Future<void> _openCategoryAsync(
    MediaItem category, {
    List<String>? initialTypeTags,
  }) async {
    if (await EmbeddedDetailLauncher.openCategory(
      context: context,
      category: category,
      initialTypeTags: initialTypeTags,
    )) {
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      AppTransitions.fadeSlideRoute(
        CategoryItemsScreen(
          category: category,
          initialTypeTags: initialTypeTags,
        ),
      ),
    );
  }

  Future<void> _openFavoritesAsync() async {
    if (await EmbeddedDetailLauncher.openFavorites(context: context)) {
      return;
    }
    if (!mounted) return;
    Navigator.of(
      context,
    ).push(AppTransitions.fadeSlideRoute(const FavoriteItemsScreen()));
  }

  Future<void> _openSearchAsync() async {
    if (await EmbeddedDetailLauncher.openSearch(context: context)) {
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      AppTransitions.fadeSlideRoute(SearchScreen(initialLocaleMap: _localeMap)),
    );
  }

  Future<void> _openItemDetail(MediaLibraryItem item, {String? heroTag}) async {
    if (item.guid.trim().isEmpty) return;
    if (_isPersonItem(item)) {
      if (await EmbeddedDetailLauncher.openPersonDetail(
        context: context,
        personGuid: item.guid,
        initialName: item.displayTitle,
      )) {
        return;
      }
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
    if (await EmbeddedDetailLauncher.openItemDetail(
      item.guid,
      context: context,
    )) {
      return;
    }
    if (!mounted) return;
    final warmupUrls = _posterCandidates(
      provider.baseUrl,
      item.poster.trim(),
      width: 560,
    );
    if (warmupUrls.isNotEmpty) {
      try {
        await precacheImage(
          NetworkImage(
            warmupUrls.first,
            headers: <String, String>{
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
          heroTag: heroTag,
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
        final episodeText = _t(
          'layout.subheading.tv.episodes',
          '共 {count} 集',
          params: <String, Object?>{'count': episodes},
        );
        if (period.isEmpty) return episodeText;
        return '$episodeText · $period';
      }
    }
    if (seasonCount > 0) {
      final seasonText = _t(
        'layout.subheading.tv.seasons',
        '共 {count} 季',
        params: <String, Object?>{'count': seasonCount},
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
      params: <String, Object?>{'number': season},
    );
    final episodeText = _t(
      'layout.subheading.episode.number',
      '第 {number} 集',
      params: <String, Object?>{'number': episode},
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
        params: <String, Object?>{'number': episode},
      );
      return '$specialText · $episodeText';
    }
    return _episodeText(item);
  }

  double _progressValue(MediaLibraryItem item) {
    if (item.duration <= 0) return 0;
    final watchedTs = item.ts > 0 ? item.ts : item.watchedTs;
    if (watchedTs <= 0) return 0;
    final raw = watchedTs / item.duration;
    return raw.clamp(0, 1).toDouble();
  }

  @override
  Widget build(BuildContext context) => _buildScreen(context);
}
