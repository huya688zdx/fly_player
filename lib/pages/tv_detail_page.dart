import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:math' as math;

import '../api/feiniu_api.dart';
import '../controllers/media_item_action_sheet_controller.dart';
import '../controllers/play_detail_item_actions.dart';
import '../controllers/tv_season_playback_launcher.dart';
import '../models/media_library_item.dart';
import '../models/play_info.dart';
import '../providers/app_theme_provider.dart';
import '../providers/nas_provider.dart';
import '../services/detail_runtime_cache.dart';
import '../services/embedded_detail_launcher.dart';
import '../theme/app_theme.dart';
import '../theme/detail_tokens.dart';
import '../ui/adaptive_detail_navigator.dart';
import '../ui/detail_presentation.dart';
import '../ui/layout_adaptive.dart';
import '../ui/player_pane_host_scope.dart';
import '../ui/media_poster_card.dart';
import '../utils/api_url_helper.dart';
import '../utils/app_exception.dart';
import '../utils/detail_top_tip.dart';
import '../utils/imdb_launcher.dart';
import '../utils/media_locale_store.dart';
import '../utils/play_detail_formatters.dart';
import '../utils/tv_hero_adaptive.dart';
import '../widgets/common/app_error_state.dart';
import '../widgets/detail/detail_description_section.dart';
import '../widgets/detail/detail_header.dart';
import '../widgets/detail/detail_hero_overlay.dart';
import '../widgets/detail/detail_more_actions_sheet.dart';
import '../widgets/detail/dynamic_page_theme_scope.dart';
import '../widgets/detail/immersive_detail_background.dart';
import '../widgets/detail/link_section.dart';
import '../widgets/detail/play_control_row.dart';
import '../widgets/detail/theme_save_name_helper.dart';
import 'long_text_overlay_page.dart';

class TvDetailPage extends StatefulWidget {
  final String itemGuid;
  final Map<String, dynamic>? initialItemDetail;
  final String? heroTag;
  final DetailPresentation presentation;

  const TvDetailPage({
    super.key,
    required this.itemGuid,
    this.initialItemDetail,
    this.heroTag,
    this.presentation = DetailPresentation.page,
  });

  @override
  State<TvDetailPage> createState() => _TvDetailPageState();
}

class _TvDetailPageState extends State<TvDetailPage>
    with TickerProviderStateMixin {
  static const Duration _descriptionPopDuration = Duration(milliseconds: 320);
  static const Duration _seasonCardPopDuration = Duration(milliseconds: 320);
  static const Duration _deferredSectionStartDelay = Duration(
    milliseconds: 180,
  );
  static const Duration _deferredSectionStepDelay = Duration(milliseconds: 140);
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _scrollOffsetNotifier = ValueNotifier<double>(0);
  static const Duration _favoriteTapCooldown = Duration(milliseconds: 900);
  static const Duration _watchedTapCooldown = Duration(milliseconds: 900);

  bool _loading = true;
  AppException? _error;
  Map<String, dynamic> _detail = const {};
  bool _usedInitialDetail = false;
  List<MediaLibraryItem> _seasonItems = const [];
  Map<int, String> _genresMapZhCn = const {};
  Map<String, String> _locateMapZhCn = const <String, String>{};
  PlayInfoData? _playInfo;
  String _imdbId = '';
  String _trimId = '';
  bool _descriptionVisible = false;
  bool _seasonCardsVisible = false;
  bool _deferredLoadStarted = false;
  Timer? _deferredTimer;
  late final AnimationController _descriptionPopController;
  late final AnimationController _seasonCardPopController;
  late final Animation<double> _descriptionOpacity;
  late final Animation<double> _descriptionScale;
  late final Animation<double> _descriptionTranslateY;
  late final Animation<double> _seasonCardOpacity;
  late final Animation<double> _seasonCardScale;
  late final Animation<double> _seasonCardTranslateY;

  bool _liked = false;
  bool _favoriteUpdating = false;
  DateTime _lastFavoriteTapAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _watched = false;
  bool _watchedUpdating = false;
  DateTime _lastWatchedTapAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _playPreparing = false;
  final DetailTopTip _topTip = DetailTopTip();
  Map<String, dynamic> _localeMap = const <String, dynamic>{};

  bool get _isPane => widget.presentation == DetailPresentation.pane;
  bool get _useRuntimeCache => _isPane;

  @override
  void initState() {
    super.initState();
    _descriptionPopController = AnimationController(
      vsync: this,
      duration: _descriptionPopDuration,
    );
    final descriptionCurve = CurvedAnimation(
      parent: _descriptionPopController,
      curve: Curves.easeOutCubic,
    );
    _descriptionOpacity = CurvedAnimation(
      parent: _descriptionPopController,
      curve: const Interval(0.0, 1.0, curve: Curves.linear),
    );
    _descriptionScale = Tween<double>(
      begin: 0.97,
      end: 1.0,
    ).animate(descriptionCurve);
    _descriptionTranslateY = Tween<double>(
      begin: 10,
      end: 0,
    ).animate(descriptionCurve);
    _seasonCardPopController = AnimationController(
      vsync: this,
      duration: _seasonCardPopDuration,
    );
    final seasonCardCurve = CurvedAnimation(
      parent: _seasonCardPopController,
      curve: Curves.easeOutCubic,
    );
    _seasonCardOpacity = CurvedAnimation(
      parent: _seasonCardPopController,
      curve: const Interval(0.0, 1.0, curve: Curves.linear),
    );
    _seasonCardScale = Tween<double>(
      begin: 0.97,
      end: 1.0,
    ).animate(seasonCardCurve);
    _seasonCardTranslateY = Tween<double>(
      begin: 10,
      end: 0,
    ).animate(seasonCardCurve);
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _topTip.dispose();
    _deferredTimer?.cancel();
    _descriptionPopController.dispose();
    _seasonCardPopController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _scrollOffsetNotifier.dispose();
    super.dispose();
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    if ((offset - _scrollOffsetNotifier.value).abs() > 0.5) {
      _scrollOffsetNotifier.value = offset;
    }
  }

  String _t(
    String path,
    String fallback, {
    Map<String, Object?> params = const <String, Object?>{},
  }) {
    return MediaLocaleStore.text(
      _localeMap,
      path,
      fallback: fallback,
      params: params,
    );
  }

  Future<void> _ensureLocaleMapLoaded() async {
    if (_localeMap.isNotEmpty) return;
    final provider = context.read<NasProvider>();
    final localeMap = await MediaLocaleStore.load(provider);
    if (!mounted || localeMap.isEmpty) return;
    setState(() {
      _localeMap = localeMap;
    });
  }

  Future<void> _load() async {
    unawaited(_ensureLocaleMapLoaded());
    _deferredTimer?.cancel();
    _descriptionPopController.reset();
    _seasonCardPopController.reset();
    setState(() {
      _loading = true;
      _error = null;
      _descriptionVisible = false;
      _seasonCardsVisible = false;
      _deferredLoadStarted = false;
      _seasonItems = const [];
      _genresMapZhCn = const {};
      _locateMapZhCn = const <String, String>{};
      _playInfo = null;
    });
    try {
      final api = FeiniuApi(context.read<NasProvider>());
      final canUseInitial =
          !_usedInitialDetail && widget.initialItemDetail != null;
      final Map<String, dynamic> detail = canUseInitial
          ? widget.initialItemDetail!
          : await _loadItemDetail(api, widget.itemGuid);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        if (canUseInitial) _usedInitialDetail = true;
        _imdbId = _extractImdbId(detail);
        _trimId = _extractTrimId(detail);
        final item = detail['item'] is Map<String, dynamic>
            ? detail['item'] as Map<String, dynamic>
            : detail;
        _liked = _asInt(item['is_favorite']) == 1;
        _watched = _asInt(item['is_watched']) == 1;
        _loading = false;
      });
      _startDeferredLoad();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppException.from(
          e,
          action: 'tv detail',
          fallbackKind: AppExceptionKind.transient,
        );
        _loading = false;
      });
    }
  }

  void _applyWatchedStateLocally(bool watched) {
    final nextFlag = watched ? 1 : 0;
    final currentItem = _detail['item'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(_detail['item'] as Map<String, dynamic>)
        : Map<String, dynamic>.from(_detail);
    currentItem['is_watched'] = nextFlag;
    final nextDetail = Map<String, dynamic>.from(_detail);
    if (_detail['item'] is Map<String, dynamic>) {
      nextDetail['item'] = currentItem;
    } else {
      nextDetail
        ..clear()
        ..addAll(currentItem);
    }
    _detail = nextDetail;
    _watched = watched;
  }

  void _replaceSeasonItemLocally(
    String itemGuid,
    MediaLibraryItem Function(MediaLibraryItem item) transform,
  ) {
    if (!mounted) return;
    setState(() {
      _seasonItems = _seasonItems
          .map((item) => item.guid == itemGuid ? transform(item) : item)
          .toList(growable: false);
    });
  }

  Future<void> _showSeasonItemActions(MediaLibraryItem season) async {
    final item = _detail['item'] is Map<String, dynamic>
        ? _detail['item'] as Map<String, dynamic>
        : _detail;
    await const MediaItemActionSheetController().show(
      context,
      item: season,
      title: MediaItemActionSheetController.seasonTitle(_title(item), season),
      localeMap: _localeMap,
      initialWatched: season.watched == 1,
      onChanged: (state) {
        _replaceSeasonItemLocally(
          season.guid,
          (current) => current.copyWith(watched: state.watched ? 1 : 0),
        );
      },
    );
  }

  Future<void> _refreshDetailSilently() async {
    try {
      final api = FeiniuApi(context.read<NasProvider>());
      final detail = await _loadItemDetail(api, widget.itemGuid);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _imdbId = _extractImdbId(detail);
        _trimId = _extractTrimId(detail);
        final item = detail['item'] is Map<String, dynamic>
            ? detail['item'] as Map<String, dynamic>
            : detail;
        _liked = _asInt(item['is_favorite']) == 1;
        _watched = _asInt(item['is_watched']) == 1;
      });
    } catch (_) {
      // Keep local optimistic state if silent sync fails.
    }
  }

  void _startDeferredLoad() {
    _deferredTimer?.cancel();
    _deferredTimer = Timer(_deferredSectionStartDelay, () {
      if (!mounted) return;
      setState(() => _descriptionVisible = true);
      _descriptionPopController.forward(from: 0);
      unawaited(_loadDeferredSections());
    });
  }

  Future<void> _loadDeferredSections() async {
    if (_deferredLoadStarted || !mounted) return;
    _deferredLoadStarted = true;
    final api = FeiniuApi(context.read<NasProvider>());

    try {
      final seasonItems = await _loadSeasonItems(api, widget.itemGuid);
      if (!mounted) return;
      seasonItems.sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
      setState(() {
        _seasonItems = seasonItems;
        _seasonCardsVisible = seasonItems.isNotEmpty;
      });
      if (seasonItems.isNotEmpty) {
        _seasonCardPopController.forward(from: 0);
      }
    } catch (_) {}

    await Future<void>.delayed(_deferredSectionStepDelay);
    if (!mounted) return;
    try {
      final genres = await api.getTagGenresMap(lan: 'zh-CN');
      if (!mounted) return;
      setState(() => _genresMapZhCn = genres);
    } catch (_) {}

    await Future<void>.delayed(_deferredSectionStepDelay);
    if (!mounted) return;
    try {
      final locateMap = await api.getTagIso3166Map(lan: 'zh-CN');
      if (!mounted) return;
      setState(() => _locateMapZhCn = locateMap);
    } catch (_) {}

    await Future<void>.delayed(_deferredSectionStepDelay);
    if (!mounted) return;
    try {
      final playInfo = await _loadPlayInfoOrNull(api, widget.itemGuid);
      if (!mounted || playInfo == null) return;
      setState(() => _playInfo = playInfo);
    } catch (_) {}
  }

  int _asInt(dynamic value) => int.tryParse('$value') ?? 0;

  String _title(Map<String, dynamic> item) {
    final tvTitle = (item['tv_title'] ?? '').toString().trim();
    final title = (item['title'] ?? '').toString().trim();
    return tvTitle.isNotEmpty ? tvTitle : title;
  }

  String _overview(Map<String, dynamic> item) {
    return (item['overview'] ?? '').toString();
  }

  String _backdrops(Map<String, dynamic> item) {
    final backdrops = (item['backdrops'] ?? '').toString();
    if (backdrops.isNotEmpty) return backdrops;
    final still = (item['still_path'] ?? '').toString();
    if (still.isNotEmpty) return still;
    return (item['posters'] ?? '').toString();
  }

  // ignore: unused_element
  String _tvPrimaryText(Map<String, dynamic> item) {
    final fromPlayInfo = _playInfo?.item;
    final seasonNumber = _asInt(item['season_number']);
    final earlyEpisode =
        fromPlayInfo?.episodeNumber ?? _asInt(item['episode_number']);
    if (seasonNumber == 0) {
      final specialLabel = _t('layout.subheading.season.special', '特别篇');
      if (earlyEpisode > 0) {
        return '$specialLabel 集 $earlyEpisode';
      }
      return specialLabel;
    }
    if (seasonNumber == 0) {
      final specialLabel = _t('layout.subheading.season.special', '特别篇');
      if (earlyEpisode > 0) {
        return '$specialLabel 集 $earlyEpisode';
      }
      return specialLabel;
    }
    final seriesTitle = (fromPlayInfo?.tvTitle ?? item['tv_title'] ?? '')
        .toString()
        .trim();
    final ancestorName = (item['ancestor_name'] ?? '').toString().trim();
    final season = fromPlayInfo?.seasonNumber ?? _asInt(item['season_number']);
    final episode =
        fromPlayInfo?.episodeNumber ?? _asInt(item['episode_number']);
    for (final candidate in <String>[
      (fromPlayInfo?.displaySubTitle ?? '').trim(),
      (fromPlayInfo?.title ?? '').trim(),
      (item['title'] ?? '').toString().trim(),
      (item['parent_title'] ?? '').toString().trim(),
    ]) {
      if (candidate.isEmpty ||
          candidate == seriesTitle ||
          candidate == ancestorName) {
        continue;
      }
      if (episode > 0) {
        return '$candidate 集 $episode';
      }
      break;
    }
    if (season > 0 && episode > 0) {
      return _t(
        'layout.subheading.seasonEpisode.number',
        '季 {season} 集 {episode}',
        params: {'season': season, 'episode': episode},
      );
    }
    if (season > 0) {
      return _t(
        'layout.subheading.season.number',
        '第 {number} 季',
        params: {'number': season},
      );
    }
    if (episode > 0) {
      return _t(
        'layout.subheading.episode.number',
        '第 {number} 集',
        params: {'number': episode},
      );
    }
    return _t('player.play.play', '播放');
  }

  String _tvPrimaryLabel(Map<String, dynamic> item) {
    final fromPlayInfo = _playInfo?.item;
    final season = fromPlayInfo?.seasonNumber ?? _asInt(item['season_number']);
    final episode =
        fromPlayInfo?.episodeNumber ?? _asInt(item['episode_number']);

    if (season == 0) {
      final specialLabel = _t('layout.subheading.season.special', '特别篇');
      if (episode > 0) {
        return '$specialLabel 集 $episode';
      }
      return specialLabel;
    }
    if (season > 0 && episode > 0) {
      return _t(
        'layout.subheading.seasonEpisode.number',
        '季 {season} 集 {episode}',
        params: {'season': season, 'episode': episode},
      );
    }
    if (season > 0) {
      return _t(
        'layout.subheading.season.number',
        '第 {number} 季',
        params: {'number': season},
      );
    }
    if (episode > 0) {
      return _t(
        'layout.subheading.episode.number',
        '第 {number} 集',
        params: {'number': episode},
      );
    }
    return _t('player.play.play', '播放');
  }

  String _year(String date) => date.length >= 4 ? date.substring(0, 4) : '';

  String _seasonTitle(MediaLibraryItem item) {
    if (item.seasonNumber > 0) {
      return _t(
        'layout.subheading.season.number',
        '第 {number} 季',
        params: {'number': item.seasonNumber},
      );
    }
    final title = item.title.trim();
    return title.isNotEmpty
        ? title
        : _t('layout.subheading.season.default', '季');
  }

  String _seasonSubtitle(MediaLibraryItem item) {
    final episodes = item.localNumberOfEpisodes > 0
        ? item.localNumberOfEpisodes
        : item.episodeNumber;
    final year = _year(item.releaseDate);
    final parts = <String>[];
    if (episodes > 0) {
      parts.add(
        _t(
          'layout.subheading.tv.episodes',
          '共 {count} 集',
          params: {'count': episodes},
        ),
      );
    }
    if (year.isNotEmpty) parts.add(year);
    return parts.join(' \u00b7 ');
  }

  String _suggestedThemeNameBase(Map<String, dynamic> item) {
    final playItem = _playInfo?.item;
    final itemType = (playItem?.type ?? item['type'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final title = _title(item);
    if (itemType == 'episode') {
      return buildThemeSaveNameBase(
        title: title,
        seriesTitle: playItem?.tvTitle.trim().isNotEmpty == true
            ? playItem!.tvTitle.trim()
            : title,
        seasonNumber: playItem?.seasonNumber ?? _asInt(item['season_number']),
        episodeNumber:
            playItem?.episodeNumber ?? _asInt(item['episode_number']),
        isEpisode: true,
      );
    }
    return buildThemeSaveNameBase(title: title);
  }

  List<String> _genreNamesForMeta(dynamic rawGenres) {
    if (rawGenres is! List) return const [];
    return PlayDetailFormatters.genreNamesFromIds(
      rawGenres,
      genreMap: _genresMapZhCn,
      maxCount: 5,
    );
  }

  Widget _buildMetaTagText(String text) {
    final colors = context.appColors;
    final metaForeground = colors.textPrimary.withValues(alpha: 0.78);
    return Text(
      text,
      style: TextStyle(
        color: metaForeground,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        height: 1.34,
        letterSpacing: 0.1,
      ),
    );
  }

  Widget _buildMetaDivider() {
    final colors = context.appColors;
    final dividerForeground = colors.textPrimary.withValues(alpha: 0.52);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        '/',
        style: TextStyle(
          color: dividerForeground,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          height: 1.34,
        ),
      ),
    );
  }

  Widget _buildTvMetaLine({
    required String contentRating,
    required List<String> genreNames,
    required String countryText,
    required String ancestorName,
  }) {
    final children = <Widget>[];

    void addSegment(Widget child) {
      if (children.isNotEmpty) {
        children.add(_buildMetaDivider());
      }
      children.add(child);
    }

    if (contentRating.isNotEmpty) {
      addSegment(_buildMetaTagText(contentRating));
    }
    if (genreNames.isNotEmpty) {
      addSegment(_buildMetaTagText(genreNames.join(' ')));
    }
    if (countryText.isNotEmpty) {
      addSegment(_buildMetaTagText(countryText));
    }
    if (ancestorName.isNotEmpty) {
      final colors = context.appColors;
      final iconForeground = colors.textPrimary.withValues(alpha: 0.60);
      addSegment(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.public_outlined, size: 14, color: iconForeground),
            const SizedBox(width: 4),
            _buildMetaTagText(ancestorName),
          ],
        ),
      );
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 6,
      children: children,
    );
  }

  List<String> _posterCandidates(
    String baseUrl,
    String rawPath, {
    int width = 360,
  }) {
    return ApiUrlHelper.imageCandidates(baseUrl, rawPath, width: width);
  }

  void _showTopTip(String message, Color color) {
    if (!mounted) return;
    _topTip.show(context, message: message, color: color);
  }

  String _extractImdbId(Map<String, dynamic> data) {
    final direct = (data['imdb_id'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;
    final item = data['item'];
    if (item is Map<String, dynamic>) {
      final nested = (item['imdb_id'] ?? '').toString().trim();
      if (nested.isNotEmpty) return nested;
    }
    return '';
  }

  String _extractTrimId(Map<String, dynamic> data) {
    final direct = (data['trim_id'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;
    final item = data['item'];
    if (item is Map<String, dynamic>) {
      final nested = (item['trim_id'] ?? '').toString().trim();
      if (nested.isNotEmpty) return nested;
    }
    return '';
  }

  Future<void> _openImdb() async {
    final result = await ImdbLauncher.openExternal(_imdbId);
    switch (result) {
      case ImdbLaunchResult.success:
        return;
      case ImdbLaunchResult.empty:
        _showTopTip(
          _t('layout.details.castAndCrew.imdb', '暂无 IMDB 链接'),
          context.appColors.warning,
        );
      case ImdbLaunchResult.failed:
        _showTopTip(
          _t('layout.details.castAndCrew.imdbOpenFailed', '无法打开 IMDB 链接'),
          context.appColors.danger,
        );
    }
  }

  Future<void> _openTmdb() async {
    final result = await ImdbLauncher.openTmdbExternal(_trimId);
    switch (result) {
      case ImdbLaunchResult.success:
        return;
      case ImdbLaunchResult.empty:
        _showTopTip('暂无 TMDB 链接', context.appColors.warning);
      case ImdbLaunchResult.failed:
        _showTopTip('无法打开 TMDB 链接', context.appColors.danger);
    }
  }

  // ignore: unused_element
  Future<void> _onPrimaryPlayTap() async {
    if (_playPreparing) {
      _showTopTip(
        _t('player.play.preparing', '正在准备播放'),
        context.appColors.warning,
      );
      return;
    }
    _playPreparing = true;
    try {
      final api = FeiniuApi(context.read<NasProvider>());
      final info = await _loadPlayInfo(api, widget.itemGuid);
      if (!mounted) return;
      setState(() => _playInfo = info);
      _showTopTip(
        _t('player.play.placeholder', '播放接口已预留'),
        context.appColors.success,
      );
      // TODO: hook real player launch here with `info`.
    } catch (_) {
      _showTopTip(
        _t('player.play.playInfoFailed', '获取播放信息失败'),
        context.appColors.danger,
      );
    } finally {
      _playPreparing = false;
    }
  }

  Future<void> _launchPrimaryPlayback() async {
    if (_playPreparing) {
      _showTopTip(
        _t('player.play.preparing', '正在准备播放'),
        context.appColors.warning,
      );
      return;
    }
    setState(() => _playPreparing = true);
    try {
      final item = _detail['item'] is Map<String, dynamic>
          ? _detail['item'] as Map<String, dynamic>
          : _detail;
      final result = await const TvSeasonPlaybackLauncher().open(
        context,
        itemGuid: widget.itemGuid,
        seriesTitle: _title(item),
      );
      if (!mounted) return;
      final api = FeiniuApi(context.read<NasProvider>());
      final info = await _loadPlayInfoOrNull(api, widget.itemGuid);
      if (!mounted) return;
      if (info != null) {
        setState(() => _playInfo = info);
      }
      if (result != null) {
        unawaited(_refreshDetailSilently());
      }
    } catch (_) {
      _showTopTip(
        _t('player.play.playInfoFailed', '获取播放信息失败'),
        context.appColors.danger,
      );
    } finally {
      if (mounted) {
        setState(() => _playPreparing = false);
      } else {
        _playPreparing = false;
      }
    }
  }

  Future<void> _toggleFavorite() async {
    final now = DateTime.now();
    if (_favoriteUpdating ||
        now.difference(_lastFavoriteTapAt) < _favoriteTapCooldown) {
      _showTopTip(
        _t('layout.globalError.clickToRetry', '点击过快，请稍后再试'),
        context.appColors.warning,
      );
      return;
    }
    _lastFavoriteTapAt = now;
    _favoriteUpdating = true;
    try {
      final api = FeiniuApi(context.read<NasProvider>());
      final result = await PlayDetailItemActions(
        api,
        localeMap: _localeMap,
      ).toggleFavorite(itemGuid: widget.itemGuid, currentLiked: _liked);
      if (!mounted) return;
      setState(() => _liked = result.state);
      _showTopTip(
        result.message,
        result.state ? context.appColors.success : context.appColors.textMuted,
      );
    } catch (_) {
      _showTopTip(
        _liked
            ? _t('common.actions.favorite.unfavoriteFailed', '取消收藏失败')
            : _t('common.actions.favorite.favoriteFailed', '收藏失败'),
        context.appColors.danger,
      );
    } finally {
      _favoriteUpdating = false;
    }
  }

  Future<void> _toggleWatched() async {
    final now = DateTime.now();
    if (_watchedUpdating ||
        now.difference(_lastWatchedTapAt) < _watchedTapCooldown) {
      _showTopTip(
        _t('layout.globalError.clickToRetry', '点击过快，请稍后再试'),
        context.appColors.warning,
      );
      return;
    }
    _lastWatchedTapAt = now;
    _watchedUpdating = true;
    try {
      final api = FeiniuApi(context.read<NasProvider>());
      final result = await PlayDetailItemActions(
        api,
        localeMap: _localeMap,
      ).toggleWatched(itemGuid: widget.itemGuid, currentWatched: _watched);
      if (!mounted) return;
      setState(() {
        _applyWatchedStateLocally(result.state);
      });
      _showTopTip(
        result.message,
        result.state ? context.appColors.success : context.appColors.textMuted,
      );
      if (result.needRefresh) {
        unawaited(_refreshDetailSilently());
      }
    } catch (_) {
      _showTopTip(
        _watched
            ? _t('common.actions.watched.markedAsUnwatchedFailed', '标记为未观看失败')
            : _t('common.actions.watched.markedAsWatchedFailed', '标记为已观看失败'),
        context.appColors.danger,
      );
    } finally {
      _watchedUpdating = false;
    }
  }

  Future<Map<String, dynamic>> _loadItemDetail(FeiniuApi api, String itemGuid) {
    if (!_useRuntimeCache) {
      return api.getItemDetail(itemGuid);
    }
    return DetailRuntimeCache.instance.getOrLoad<Map<String, dynamic>>(
      bucket: 'item_detail',
      key: itemGuid,
      loader: () => api.getItemDetail(itemGuid),
    );
  }

  Future<List<MediaLibraryItem>> _loadSeasonItems(
    FeiniuApi api,
    String itemGuid,
  ) {
    if (!_useRuntimeCache) {
      return api.getSeasonList(itemGuid);
    }
    return DetailRuntimeCache.instance.getOrLoad<List<MediaLibraryItem>>(
      bucket: 'season_list',
      key: itemGuid,
      loader: () => api.getSeasonList(itemGuid),
    );
  }

  Future<PlayInfoData> _loadPlayInfo(FeiniuApi api, String itemGuid) {
    if (!_useRuntimeCache) {
      return api.getPlayInfo(itemGuid);
    }
    return DetailRuntimeCache.instance.getOrLoad<PlayInfoData>(
      bucket: 'play_info',
      key: itemGuid,
      loader: () => api.getPlayInfo(itemGuid),
    );
  }

  Future<PlayInfoData?> _loadPlayInfoOrNull(
    FeiniuApi api,
    String itemGuid,
  ) async {
    try {
      return await _loadPlayInfo(api, itemGuid);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<AppThemeProvider>();
    final nasProvider = context.read<NasProvider>();
    final inPlayerPaneHost = PlayerPaneHostScope.maybeOf(context) != null;
    var dynamicThemeImageUrl = '';
    if (_detail.isNotEmpty) {
      final item = _detail['item'] is Map<String, dynamic>
          ? _detail['item'] as Map<String, dynamic>
          : _detail;
      final urls = ApiUrlHelper.imageCandidates(
        nasProvider.baseUrl,
        _backdrops(item),
        width: 360,
      );
      if (urls.isNotEmpty) {
        dynamicThemeImageUrl = urls.first;
      }
    } else if (widget.initialItemDetail != null) {
      final item = widget.initialItemDetail!['item'] is Map<String, dynamic>
          ? widget.initialItemDetail!['item'] as Map<String, dynamic>
          : widget.initialItemDetail!;
      final urls = ApiUrlHelper.imageCandidates(
        nasProvider.baseUrl,
        _backdrops(item),
        width: 360,
      );
      if (urls.isNotEmpty) {
        dynamicThemeImageUrl = urls.first;
      }
    }

    final dynamicThemeIntensity = themeProvider.dynamicThemeIntensity;
    return DynamicPageThemeScope(
      pageKey: widget.itemGuid,
      imageUrl: dynamicThemeImageUrl,
      token: nasProvider.token,
      enabled: themeProvider.dynamicThemeEnabled,
      syncGlobalTheme: dynamicThemeIntensity.allowsGlobalRuntimeThemeSync(
        inPlayerPaneHost: inPlayerPaneHost,
        isPane: _isPane,
      ),
      intensity: dynamicThemeIntensity,
      builder: (context, ambientTint) {
        final colors = context.appColors;
        if (_loading) {
          return Scaffold(
            backgroundColor: colors.backgroundBase,
            body: SizedBox.shrink(),
          );
        }
        if (_error != null) {
          return Scaffold(
            backgroundColor: colors.backgroundBase,
            appBar: _isPane
                ? null
                : AppBar(backgroundColor: colors.backgroundBase),
            body: AppErrorState(
              error: _error!,
              localeMap: _localeMap,
              onRetry: _load,
            ),
          );
        }

        final provider = context.read<NasProvider>();
        final layout = MediaLayoutProfile.of(context);
        final media = MediaQuery.of(context);
        final screenSize = media.size;
        final heroAdaptive = TvHeroAdaptive.resolve(
          screenSize,
          devicePixelRatio: media.devicePixelRatio,
        );
        final posterHeight = math
            .min(
              screenSize.height * heroAdaptive.posterHeightRatio,
              screenSize.width / 1.55,
            )
            .clamp(300.0, screenSize.height * 0.48)
            .toDouble();
        final collapseRange =
            (posterHeight - media.padding.top - kToolbarHeight).clamp(
              1.0,
              posterHeight,
            );

        final item = _detail['item'] is Map<String, dynamic>
            ? _detail['item'] as Map<String, dynamic>
            : _detail;

        final title = _title(item);
        final overview = _overview(item);
        final primaryText = _tvPrimaryLabel(item);
        final seasons = _asInt(item['number_of_seasons']);
        final localSeasons = _asInt(item['local_number_of_seasons']);
        final seasonCount = localSeasons > 0 ? localSeasons : seasons;
        final contentRating = (item['content_ratings'] ?? '').toString().trim();
        final genreNames = _genreNamesForMeta(item['genres']);
        final countryNames = PlayDetailFormatters.countryNamesFromCodes(
          item['production_countries'] is List
              ? item['production_countries'] as List
              : const [],
          locateMap: _locateMapZhCn,
        );
        final countryText = countryNames.isNotEmpty ? countryNames.first : '';
        final ancestorName = (item['ancestor_name'] ?? '').toString().trim();
        final hasMetaLine =
            contentRating.isNotEmpty ||
            genreNames.isNotEmpty ||
            countryText.isNotEmpty ||
            ancestorName.isNotEmpty;
        final backdropRequestWidth =
            (_isPane ? screenSize.width * media.devicePixelRatio * 1.2 : 1200.0)
                .clamp(720.0, 1200.0)
                .round();
        final logoRequestWidth =
            (_isPane ? screenSize.width * media.devicePixelRatio : 1200.0)
                .clamp(480.0, 1200.0)
                .round();

        final heroUrls = ApiUrlHelper.imageCandidates(
          provider.baseUrl,
          _backdrops(item),
          width: backdropRequestWidth,
        );
        final logoUrls = ApiUrlHelper.imageCandidates(
          provider.baseUrl,
          (item['logos'] ?? '').toString(),
          width: logoRequestWidth,
        );

        return Scaffold(
          backgroundColor: colors.backgroundBase,
          body: Stack(
            fit: StackFit.expand,
            children: [
              ValueListenableBuilder<double>(
                valueListenable: _scrollOffsetNotifier,
                builder: (context, offset, _) {
                  return ImmersiveDetailBackground(
                    urls: heroUrls,
                    token: provider.token,
                    scrollOffset: offset,
                    posterHeight: posterHeight,
                    imageScale: heroAdaptive.imageScale * 1.04,
                    imageFit: BoxFit.cover,
                    imageAlignment: Alignment(
                      heroAdaptive.imageAlignX,
                      heroAdaptive.imageAlignY,
                    ),
                    fillGapsWithImage: false,
                    enableBottomFade: false,
                    fadeStart: heroAdaptive.fadeStart,
                    fadeMid: heroAdaptive.fadeMid,
                    useMonetTint: false,
                    overlayOpacity: 0.74,
                    maxScrollZoom: 1.38,
                    ambientTintOverride: ambientTint,
                  );
                },
              ),
              CustomScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(
                    child: DetailHeroOverlay(
                      height: posterHeight,
                      title: title,
                      useSoftGradient: true,
                      titleChild: logoUrls.isNotEmpty
                          ? DetailHeroLogoTitle(
                              urls: logoUrls,
                              token: provider.token,
                              fallbackTitle: title,
                              maxHeight: 124,
                              maxWidth:
                                  screenSize.width -
                                  (DetailTokens.screenHorizontalPadding * 2),
                            )
                          : null,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Container(
                      color: colors.backgroundBase,
                      padding: const EdgeInsets.fromLTRB(
                        DetailTokens.screenHorizontalPadding,
                        8,
                        DetailTokens.screenHorizontalPadding,
                        18,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (hasMetaLine)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: _buildTvMetaLine(
                                contentRating: contentRating,
                                genreNames: genreNames,
                                countryText: countryText,
                                ancestorName: ancestorName,
                              ),
                            ),
                          const SizedBox(height: 14),
                          PlayControlRow(
                            primaryText: primaryText,
                            primaryEnabled: true,
                            liked: _liked,
                            watched: _watched,
                            showDownload: false,
                            onPrimaryTap: _launchPrimaryPlayback,
                            onLikeTap: _toggleFavorite,
                            onWatchedTap: _toggleWatched,
                          ),
                          const SizedBox(height: 12),
                          AnimatedBuilder(
                            animation: _descriptionPopController,
                            builder: (context, child) {
                              return Opacity(
                                opacity: _descriptionVisible
                                    ? _descriptionOpacity.value
                                    : 0,
                                child: Transform.translate(
                                  offset: Offset(
                                    0,
                                    _descriptionVisible
                                        ? _descriptionTranslateY.value
                                        : 10,
                                  ),
                                  child: Transform.scale(
                                    scale: _descriptionVisible
                                        ? _descriptionScale.value
                                        : 0.97,
                                    alignment: Alignment.topCenter,
                                    child: child,
                                  ),
                                ),
                              );
                            },
                            child: DetailDescriptionSection(
                              text: overview,
                              onMoreTap: () {
                                LongTextOverlayPage.show(
                                  context,
                                  title: title,
                                  sectionTitle: _t(
                                    'layout.details.overview.overview',
                                    '简介',
                                  ),
                                  content: overview,
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _t(
                              'layout.subheading.tv.seasons',
                              '共 {count} 季',
                              params: {'count': seasonCount},
                            ),
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_seasonItems.isNotEmpty)
                            AnimatedBuilder(
                              animation: _seasonCardPopController,
                              builder: (context, child) {
                                return Opacity(
                                  opacity: _seasonCardsVisible
                                      ? _seasonCardOpacity.value
                                      : 0,
                                  child: Transform.translate(
                                    offset: Offset(
                                      0,
                                      _seasonCardsVisible
                                          ? _seasonCardTranslateY.value
                                          : 10,
                                    ),
                                    child: Transform.scale(
                                      scale: _seasonCardsVisible
                                          ? _seasonCardScale.value
                                          : 0.97,
                                      alignment: Alignment.topCenter,
                                      child: child,
                                    ),
                                  ),
                                );
                              },
                              child: SizedBox(
                                height: layout.homePosterRowHeight,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _seasonItems.length,
                                  separatorBuilder: (_, __) =>
                                      SizedBox(width: layout.itemGap),
                                  itemBuilder: (context, index) {
                                    final season = _seasonItems[index];
                                    final rating = double.tryParse(
                                      season.voteAverage,
                                    );
                                    return SizedBox(
                                      width: layout.homePosterCardWidth,
                                      child: MediaPosterCard(
                                        urls: _posterCandidates(
                                          provider.baseUrl,
                                          season.poster,
                                          width: layout.homePosterRequestWidth,
                                        ),
                                        token: provider.token,
                                        title: _seasonTitle(season),
                                        subtitle: _seasonSubtitle(season),
                                        rating: (rating != null && rating > 0)
                                            ? rating
                                            : null,
                                        resolutions: season.resolutions,
                                        watched: season.watched == 1,
                                        imageHeight:
                                            layout.homePosterImageHeight,
                                        titleFontSize:
                                            layout.homePosterTitleFontSize,
                                        subtitleFontSize:
                                            layout.homePosterSubtitleFontSize,
                                        onTap: () {
                                          AdaptiveDetailNavigator.open<void>(
                                            context,
                                            AdaptiveDetailRequest.season(
                                              parentGuid: widget.itemGuid,
                                              seriesTitle: title,
                                              backdropPath: _backdrops(item),
                                              seasonItem: season,
                                              initialSeasonItems: _seasonItems,
                                            ),
                                            presentation: _isPane
                                                ? DetailPresentation.pane
                                                : DetailPresentation.page,
                                          );
                                        },
                                        onLongPress: () {
                                          unawaited(
                                            _showSeasonItemActions(season),
                                          );
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                            )
                          else
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: colors.surface,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                _t('layout.details.season.empty', '暂无季列表'),
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          LinkSection(
                            imdbId: _imdbId,
                            tmdbId: _trimId,
                            onImdbTap: _openImdb,
                            onTmdbTap: _openTmdb,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              ValueListenableBuilder<double>(
                valueListenable: _scrollOffsetNotifier,
                builder: (context, offset, _) {
                  final collapseT = (offset / collapseRange).clamp(0.0, 1.0);
                  final centerTitleOpacity = ((collapseT - 0.84) / 0.12).clamp(
                    0.0,
                    1.0,
                  );
                  return DetailFloatingTopBar(
                    onBack: () => unawaited(
                      EmbeddedDetailLauncher.closeHostOrPop(context),
                    ),
                    onMore: () => unawaited(
                      showDetailMoreActionsSheet(
                        context,
                        pageKey: widget.itemGuid,
                        pageTitle: title,
                        suggestedThemeName: context
                            .read<AppThemeProvider>()
                            .nextSavedThemeNameFromBase(
                              _suggestedThemeNameBase(item),
                            ),
                        clearRuntimeBroadcastToMain: !inPlayerPaneHost,
                      ),
                    ),
                    title: title,
                    titleOpacity: centerTitleOpacity,
                    showBack: !_isPane,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
