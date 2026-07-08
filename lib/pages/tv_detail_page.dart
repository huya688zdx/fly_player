import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:math' as math;

import '../api/feiniu_api.dart';
import '../controllers/media_item_action_sheet_controller.dart';
import '../controllers/tv_season_playback_launcher.dart';
import '../l10n/generated/app_localizations.dart';
import '../media_backend/action/media_library_item_action_target.dart';
import '../media_backend/detail/media_detail.dart';
import '../media_backend/detail/media_episode_summary.dart';
import '../media_backend/detail/media_season_summary.dart';
import '../media_backend/media_backend.dart';
import '../media_backend/media_backend_kind.dart';
import '../media_backend/media_image_ref.dart';
import '../models/media_library_item.dart';
import '../models/play_info.dart';
import '../providers/app_theme_provider.dart';
import '../providers/media_backend_provider.dart';
import '../providers/nas_provider.dart';
import '../services/detail_runtime_cache.dart';
import '../services/embedded_detail_launcher.dart';
import '../services/native_playback_reentry.dart';
import '../services/native_player_bridge.dart';
import '../theme/app_theme.dart';
import '../theme/detail_tokens.dart';
import '../ui/adaptive_detail_navigator.dart';
import '../ui/credit_person_presenter.dart';
import '../ui/detail_artwork_resolver.dart';
import '../ui/detail_presentation.dart';
import '../ui/layout_adaptive.dart';
import '../ui/player_pane_host_scope.dart';
import '../ui/media_poster_card.dart';
import '../ui/region_name_localizer.dart';
import '../ui/route_transition_gate.dart';
import '../utils/api_url_helper.dart';
import '../utils/app_exception.dart';
import '../utils/detail_top_tip.dart';
import '../utils/imdb_launcher.dart';
import '../utils/play_detail_formatters.dart';
import '../utils/tv_hero_adaptive.dart';
import '../widgets/common/app_error_state.dart';
import '../widgets/detail/credits_section.dart';
import '../widgets/detail/detail_description_section.dart';
import '../widgets/detail/detail_header.dart';
import '../widgets/detail/detail_hero_overlay.dart';
import '../widgets/detail/detail_loading_skeleton.dart';
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
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _scrollOffsetNotifier = ValueNotifier<double>(0);
  static const Duration _favoriteTapCooldown = Duration(milliseconds: 900);
  static const Duration _watchedTapCooldown = Duration(milliseconds: 900);

  bool _loading = true;
  AppException? _error;
  Map<String, dynamic> _detail = const {};
  bool _usedInitialDetail = false;
  // 中立(Emby 等公共后端)展示态:`_neutralDisplayOnly` 时飞牛 build 路径整段不进,
  // 走 `_buildNeutralBody`(读 `_neutralDetail`/`_neutralSeasons`,播放/收藏/已看占位禁用)。
  bool _neutralDisplayOnly = false;
  MediaDetail? _neutralDetail;
  List<MediaSeasonSummary> _neutralSeasons = const [];
  // 中立(Emby)系列页主播放键的「续看/首集」目标：按键文案显示「第 X 季 第 Y 集」+ 点击起播
  // 复用同一目标（避免点击再解析）。null=尚未解析或无可播单集。
  MediaEpisodeSummary? _neutralPlayTarget;
  List<MediaLibraryItem> _seasonItems = const [];
  Object? _reentryToken;
  Map<int, String> _genresMapZhCn = const {};
  Map<String, String> _locateMapZhCn = const <String, String>{};
  PlayInfoData? _playInfo;
  String _imdbId = '';
  String _trimId = '';
  bool _descriptionVisible = false;
  bool _seasonCardsVisible = false;
  bool _deferredLoadStarted = false;
  bool _seasonItemsResolved = false;
  bool _artworkReady = false;
  bool _suppressGlobalThemeSyncUntilFullDetail = false;
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
  final Map<String, dynamic> _localeMap = const <String, dynamic>{};

  bool get _isPane => widget.presentation == DetailPresentation.pane;
  bool get _useRuntimeCache => _isPane;

  void _openCreditPerson(CreditPersonItem person) {
    final guid = person.personGuid.trim();
    if (guid.isEmpty) return;
    AdaptiveDetailNavigator.open<void>(
      context,
      AdaptiveDetailRequest.person(
        personGuid: guid,
        initialName: person.name,
        initialLocaleMap: _localeMap,
      ),
      presentation: _isPane ? DetailPresentation.pane : DetailPresentation.page,
    );
  }

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
    if (_reentryToken != null) {
      NativePlayerBridge.unbindReentry(_reentryToken!);
      _reentryToken = null;
    }
    super.dispose();
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    if ((offset - _scrollOffsetNotifier.value).abs() > 0.5) {
      _scrollOffsetNotifier.value = offset;
    }
  }

  Future<void> _load() async {
    _deferredTimer?.cancel();
    _descriptionPopController.reset();
    _seasonCardPopController.reset();
    setState(() {
      _loading = true;
      _error = null;
      _descriptionVisible = false;
      _seasonCardsVisible = false;
      _deferredLoadStarted = false;
      _seasonItemsResolved = false;
      _artworkReady = false;
      _suppressGlobalThemeSyncUntilFullDetail = false;
      _neutralDisplayOnly = false;
      _neutralDetail = null;
      _neutralSeasons = const [];
      _seasonItems = const [];
      _genresMapZhCn = const {};
      _locateMapZhCn = const <String, String>{};
      _playInfo = null;
    });
    // 非飞牛后端(Emby):走中立展示路,不调任何 FeiniuApi。飞牛分支整段保持原样。
    final backend = context.read<MediaBackendProvider>().backend;
    if (backend.capabilities.kind != MediaBackendKind.feiniu) {
      await _loadNeutral();
      return;
    }
    try {
      final api = FeiniuApi(context.read<NasProvider>());
      final canUseInitial =
          !_usedInitialDetail && widget.initialItemDetail != null;
      if (canUseInitial) {
        final detail = widget.initialItemDetail!;
        if (!mounted) return;
        setState(() {
          _applyBaseDetail(detail);
          _usedInitialDetail = true;
          _suppressGlobalThemeSyncUntilFullDetail = true;
          _loading = false;
        });
        _startDeferredLoad();
        unawaited(_refreshBaseDetail(api));
        return;
      }
      final detail = await _loadItemDetail(api, widget.itemGuid);
      if (!mounted) return;
      // 把"骨架→正文"的整树替换推迟到转场结束后，避免它落在 380ms 转场窗口
      // 中段与 enter 动画叠加（网络通常已慢于转场，此处多为即时 resolve）。
      await RouteTransitionGate.of(context);
      if (!mounted) return;
      setState(() {
        _applyBaseDetail(detail);
        _suppressGlobalThemeSyncUntilFullDetail = false;
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

  /// 中立(Emby)加载:取 `MediaDetail` + 季列表,设展示态。播放接线一律不取(占位)。
  Future<void> _loadNeutral() async {
    try {
      final backend = context.read<MediaBackendProvider>().backend;
      final detail = await backend.getItemDetail(widget.itemGuid);
      // 季列表 best-effort:失败不阻断详情展示(空列表 → 空态)。
      List<MediaSeasonSummary> seasons;
      try {
        seasons = await backend.getItemSeasons(widget.itemGuid);
        seasons = List<MediaSeasonSummary>.of(seasons)
          ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
      } catch (_) {
        seasons = const <MediaSeasonSummary>[];
      }
      if (!mounted) return;
      await RouteTransitionGate.of(context);
      if (!mounted) return;
      setState(() {
        _neutralDisplayOnly = true;
        _neutralDetail = detail;
        _neutralSeasons = seasons;
        _liked = detail.favorite;
        _watched = detail.watched;
        _imdbId = detail.externalIds.imdbId;
        _trimId = detail.externalIds.tmdbId;
        _seasonItemsResolved = true;
        _artworkReady = true;
        _loading = false;
      });
      // 主播放键「续看/首集」目标 best-effort 解析（含季/集号供按键文案）：不阻断详情展示，
      // 解析完更新按键标签（解析前先显示「播放」）。
      unawaited(_resolveNeutralPlayTarget(backend));
      // 复用飞牛的入场动画(描述/季卡 pop)。
      _descriptionVisible = true;
      _descriptionPopController.forward(from: 0);
      if (seasons.isNotEmpty) {
        _seasonCardsVisible = true;
        _seasonCardPopController.forward(from: 0);
      }
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

  void _applyBaseDetail(Map<String, dynamic> detail) {
    _detail = detail;
    _imdbId = _extractImdbId(detail);
    _trimId = _extractTrimId(detail);
    final item = detail['item'] is Map<String, dynamic>
        ? detail['item'] as Map<String, dynamic>
        : detail;
    _liked = _asInt(item['is_favorite']) == 1;
    _watched = _asInt(item['is_watched']) == 1;
  }

  Future<void> _refreshBaseDetail(FeiniuApi api) async {
    try {
      final detail = await _loadItemDetail(api, widget.itemGuid);
      if (!mounted) return;
      setState(() {
        _applyBaseDetail(detail);
        _suppressGlobalThemeSyncUntilFullDetail = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _suppressGlobalThemeSyncUntilFullDetail = false;
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
    final l10n = AppLocalizations.of(context);
    final target = season.toActionTarget();
    await const MediaItemActionSheetController().show(
      context,
      target: target,
      title: MediaItemActionSheetController.seasonTitle(
        l10n,
        _title(item),
        target,
      ),
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
    unawaited(_loadDeferredSections());
    unawaited(_scheduleDescriptionReveal());
  }

  // 描述 pop 动画的 180ms 起始延迟永远等转场结束后再起，避免它落在 380ms
  // 转场窗口中段。
  Future<void> _scheduleDescriptionReveal() async {
    await RouteTransitionGate.of(context);
    if (!mounted) return;
    _deferredTimer?.cancel();
    _deferredTimer = Timer(_deferredSectionStartDelay, () {
      if (!mounted) return;
      setState(() {
        _descriptionVisible = true;
        _artworkReady = _seasonItemsResolved;
      });
      _descriptionPopController.forward(from: 0);
    });
  }

  // 出错时返回 null，让调用方决定是否跳过该段（区别于"成功但为空"）。
  Future<T?> _guardSection<T>(Future<T> Function() task) async {
    try {
      return await task();
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadDeferredSections() async {
    if (_deferredLoadStarted || !mounted) return;
    _deferredLoadStarted = true;
    final api = FeiniuApi(context.read<NasProvider>());

    // IO 立即并发发起（不推迟网络），只把"应用到可见树"的 setState 推迟到转场
    // 结束后。原先 genres/locate/playInfo 的 3×140ms 串行间隔删除，并发取后一次
    // 性合并为单次 setState。
    final seasonItemsFuture = _guardSection<List<MediaLibraryItem>>(
      () => _loadSeasonItems(api, widget.itemGuid),
    );
    final genresFuture = _guardSection<Map<int, String>>(
      () => api.getTagGenresMap(lan: 'zh-CN'),
    );
    final locateFuture = _guardSection<Map<String, String>>(
      () => api.getTagIso3166Map(lan: 'zh-CN'),
    );
    final playInfoFuture = _guardSection<PlayInfoData?>(
      () => _loadPlayInfoOrNull(api, widget.itemGuid),
    );

    final seasonItems = await seasonItemsFuture;
    if (!mounted) return;
    await RouteTransitionGate.of(context);
    if (!mounted) return;
    if (seasonItems != null) {
      seasonItems.sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
      setState(() {
        _seasonItems = seasonItems;
        _seasonItemsResolved = true;
        _seasonCardsVisible = seasonItems.isNotEmpty;
        _artworkReady = _descriptionVisible;
      });
      if (seasonItems.isNotEmpty) {
        _seasonCardPopController.forward(from: 0);
      }
    } else {
      setState(() {
        _seasonItemsResolved = true;
        _artworkReady = _descriptionVisible;
      });
    }

    final genres = await genresFuture;
    final locate = await locateFuture;
    final playInfo = await playInfoFuture;
    if (!mounted) return;
    if (genres == null && locate == null && playInfo == null) return;
    setState(() {
      if (genres != null) _genresMapZhCn = genres;
      if (locate != null) _locateMapZhCn = locate;
      if (playInfo != null) _playInfo = playInfo;
    });
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

  String _tvPrimaryLabel(Map<String, dynamic> item) {
    final fromPlayInfo = _playInfo?.item;
    final season = fromPlayInfo?.seasonNumber ?? _asInt(item['season_number']);
    final episode =
        fromPlayInfo?.episodeNumber ?? _asInt(item['episode_number']);

    if (season == 0) {
      if (episode > 0) {
        return AppLocalizations.of(context).detailSpecialEpisodeNumber(episode);
      }
      return AppLocalizations.of(context).detailSeasonSpecial;
    }
    if (season > 0 && episode > 0) {
      return AppLocalizations.of(
        context,
      ).detailSeasonEpisodeNumber(season, episode);
    }
    if (season > 0) {
      return AppLocalizations.of(context).detailSeasonNumber(season);
    }
    if (episode > 0) {
      return AppLocalizations.of(context).detailEpisodeNumber(episode);
    }
    return AppLocalizations.of(context).detailPlay;
  }

  String _year(String date) => date.length >= 4 ? date.substring(0, 4) : '';

  String _seasonTitle(MediaLibraryItem item) {
    if (item.seasonNumber > 0) {
      return AppLocalizations.of(context).detailSeasonNumber(item.seasonNumber);
    }
    final title = item.title.trim();
    return title.isNotEmpty
        ? title
        : AppLocalizations.of(context).detailSeasonDefault;
  }

  String _seasonSubtitle(MediaLibraryItem item) {
    final episodes = item.localNumberOfEpisodes > 0
        ? item.localNumberOfEpisodes
        : item.episodeNumber;
    final year = _year(item.releaseDate);
    final parts = <String>[];
    if (episodes > 0) {
      parts.add(AppLocalizations.of(context).detailEpisodeTotal(episodes));
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
        l10n: AppLocalizations.of(context),
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
    return buildThemeSaveNameBase(
      l10n: AppLocalizations.of(context),
      title: title,
    );
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
      padding: const EdgeInsets.symmetric(horizontal: 4),
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
    String ratingStar = '',
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
    // Emby 自有评分（飞牛此区不展示，故仅中立路径传入；与详情页 ⭐ 风格一致）。
    if (ratingStar.isNotEmpty) {
      addSegment(_buildMetaTagText('⭐ $ratingStar'));
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
    if (!mounted) return;
    switch (result) {
      case ImdbLaunchResult.success:
        return;
      case ImdbLaunchResult.empty:
        _showTopTip(
          AppLocalizations.of(context).detailImdbEmpty,
          context.appColors.warning,
        );
      case ImdbLaunchResult.failed:
        _showTopTip(
          AppLocalizations.of(context).detailImdbOpenFailed,
          context.appColors.danger,
        );
    }
  }

  Future<void> _openTmdb() async {
    final result = await ImdbLauncher.openTmdbExternal(_trimId);
    if (!mounted) return;
    switch (result) {
      case ImdbLaunchResult.success:
        return;
      case ImdbLaunchResult.empty:
        _showTopTip(
          AppLocalizations.of(context).detailTmdbEmpty,
          context.appColors.warning,
        );
      case ImdbLaunchResult.failed:
        _showTopTip(
          AppLocalizations.of(context).detailTmdbOpenFailed,
          context.appColors.danger,
        );
    }
  }

  /// 中立(Emby)系列页:沉浸背景 + hero + meta + 播放占位 + 描述 + 季栅格 + 演职员 + 链接。
  /// 飞牛专属(PlayControlRow/动态主题取色拼接/原生 reentry)不进;图源走 [DetailArtworkResolver]
  /// (Emby 完整 api_key 直链直接透传)。播放/收藏/已看本阶段占位禁用。
  Widget _buildNeutralBody(AppThemeColors colors, Color? ambientTint) {
    final detail = _neutralDetail!;
    final capabilities = context
        .read<MediaBackendProvider>()
        .backend
        .capabilities;
    final provider = context.read<NasProvider>();
    final artworkResolver = DetailArtworkResolver(
      baseUrl: provider.baseUrl,
      token: provider.token,
    );
    final layout = MediaLayoutProfile.of(context);
    final media = MediaQuery.of(context);
    final screenSize = media.size;
    final heroAdaptive = TvHeroAdaptive.resolve(
      screenSize,
      devicePixelRatio: media.devicePixelRatio,
    );
    final posterHeightMax = screenSize.height * 0.48;
    final posterHeightMin = math.min(300.0, posterHeightMax);
    final posterHeight = math
        .min(
          screenSize.height * heroAdaptive.posterHeightRatio,
          screenSize.width / 1.55,
        )
        .clamp(posterHeightMin, posterHeightMax)
        .toDouble();
    final collapseRangeMax = math.max(1.0, posterHeight);
    final collapseRange = (posterHeight - media.padding.top - kToolbarHeight)
        .clamp(1.0, collapseRangeMax);

    final title = detail.title.trim().isNotEmpty
        ? detail.title.trim()
        : detail.displayTitle;
    final overview = detail.overview.trim();
    final heroUrls = artworkResolver.resolveRef(detail.backdropImage).urls;
    final logoUrls = artworkResolver.resolveRef(detail.logoImage).urls;
    final heroTitleChild = logoUrls.isNotEmpty
        ? DetailHeroLogoTitle(
            urls: logoUrls,
            token: '',
            fallbackTitle: title,
            maxHeight: 124,
            maxWidth:
                screenSize.width - (DetailTokens.screenHorizontalPadding * 2),
          )
        : null;

    // 与飞牛系列页同一行式 meta（题材空格连 / 地区 / 库名），用同一 `_buildTvMetaLine`。
    // Emby 无「库/合集名」(ancestorName) 字段；评分为 Emby 自有，作为末段 ⭐ 追加。
    final genreNames = detail.genreLabels
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    // 地区本地化（mapper 无 l10n）：英文国名 / ISO code → 中文，未知原样；飞牛已是中文则透传。
    final countryText = RegionNameLocalizer.localizeAll(
      AppLocalizations.of(context),
      detail.regionLabels,
    ).map((e) => e.trim()).where((e) => e.isNotEmpty).join(' ');
    final ratingStar = detail.rating.trim();
    final hasMetaLine =
        genreNames.isNotEmpty ||
        countryText.isNotEmpty ||
        ratingStar.isNotEmpty;

    final creditItems = detail.people
        .map(
          (p) => CreditPersonItem(
            personGuid: p.id,
            name: CreditPersonPresenter.displayName(
              p,
              AppLocalizations.of(context),
            ),
            subtitle: CreditPersonPresenter.displaySubTitle(
              p,
              AppLocalizations.of(context),
            ),
            imageUrls: artworkResolver.resolveRef(p.avatar, width: 180).urls,
          ),
        )
        .toList();

    final seasonCount = _neutralSeasons.length;

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
                lowResUrls: const <String>[],
                token: '',
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
                  titleChild: heroTitleChild,
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
                            contentRating: '',
                            genreNames: genreNames,
                            countryText: countryText,
                            ancestorName: '',
                            ratingStar: ratingStar,
                          ),
                        ),
                      const SizedBox(height: 14),
                      // 与飞牛系列页同一动作行：主播放键 + 收藏 + 已看（按能力门控，下载暂不支持）。
                      PlayControlRow(
                        primaryText: _playPreparing
                            ? AppLocalizations.of(
                                context,
                              ).detailPreparingPlayback
                            : _neutralPlayLabel(),
                        primaryEnabled: !_playPreparing,
                        liked: _liked,
                        watched: _watched,
                        showDownload: false,
                        onPrimaryTap: _playPreparing
                            ? null
                            : _launchPrimaryPlayback,
                        onLikeTap: capabilities.supportsFavorite
                            ? _toggleFavorite
                            : null,
                        onWatchedTap: capabilities.supportsWatched
                            ? _toggleWatched
                            : null,
                      ),
                      const SizedBox(height: 12),
                      if (overview.isNotEmpty) ...[
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
                                sectionTitle: AppLocalizations.of(
                                  context,
                                ).detailOverviewTitle,
                                content: overview,
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Text(
                        AppLocalizations.of(
                          context,
                        ).detailTvSeasonCount(seasonCount),
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildNeutralSeasonGrid(
                        colors: colors,
                        layout: layout,
                        artworkResolver: artworkResolver,
                        title: title,
                        backdropRef: detail.backdropImage,
                      ),
                      if (creditItems.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        CreditsSection(
                          title: AppLocalizations.of(
                            context,
                          ).detailCastCrewTitle,
                          items: creditItems,
                          token: '',
                          onTap: _openCreditPerson,
                        ),
                      ],
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
                onBack: () =>
                    unawaited(EmbeddedDetailLauncher.closeHostOrPop(context)),
                onMore: () => unawaited(
                  showDetailMoreActionsSheet(
                    context,
                    pageKey: widget.itemGuid,
                    pageTitle: title,
                    suggestedThemeName: context
                        .read<AppThemeProvider>()
                        .nextSavedThemeNameFromBase(title),
                    clearRuntimeBroadcastToMain:
                        PlayerPaneHostScope.maybeOf(context) == null,
                  ),
                ),
                title: title,
                titleOpacity: centerTitleOpacity,
                showBack: true,
              );
            },
          ),
        ],
      ),
    );
  }

  /// 中立季栅格:季卡用 [MediaSeasonSummary] + resolver 直链;点击转最小 [MediaLibraryItem]
  /// 经 [AdaptiveDetailRequest.season] 导航(数据层适配,非 UID if(isEmby))。空态占位。
  Widget _buildNeutralSeasonGrid({
    required AppThemeColors colors,
    required MediaLayoutProfile layout,
    required DetailArtworkResolver artworkResolver,
    required String title,
    required MediaImageRef backdropRef,
  }) {
    if (_neutralSeasons.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          AppLocalizations.of(context).detailSeasonEmpty,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    return AnimatedBuilder(
      animation: _seasonCardPopController,
      builder: (context, child) {
        return Opacity(
          opacity: _seasonCardsVisible ? _seasonCardOpacity.value : 0,
          child: Transform.translate(
            offset: Offset(
              0,
              _seasonCardsVisible ? _seasonCardTranslateY.value : 10,
            ),
            child: Transform.scale(
              scale: _seasonCardsVisible ? _seasonCardScale.value : 0.97,
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
          itemCount: _neutralSeasons.length,
          separatorBuilder: (_, __) => SizedBox(width: layout.itemGap),
          itemBuilder: (context, index) {
            final season = _neutralSeasons[index];
            return SizedBox(
              width: layout.homePosterCardWidth,
              child: MediaPosterCard(
                urls: artworkResolver
                    .resolveRef(
                      season.primaryImage,
                      width: layout.homePosterRequestWidth,
                    )
                    .urls,
                token: '',
                title: _neutralSeasonTitle(season),
                subtitle: _neutralSeasonSubtitle(season),
                imageHeight: layout.homePosterImageHeight,
                titleFontSize: layout.homePosterTitleFontSize,
                subtitleFontSize: layout.homePosterSubtitleFontSize,
                onTap: () {
                  AdaptiveDetailNavigator.open<void>(
                    context,
                    AdaptiveDetailRequest.season(
                      parentGuid: widget.itemGuid,
                      seriesTitle: title,
                      backdropPath: backdropRef.url,
                      seasonItem: _seasonItemFromSummary(season),
                    ),
                    presentation: _isPane
                        ? DetailPresentation.pane
                        : DetailPresentation.page,
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  String _neutralSeasonTitle(MediaSeasonSummary season) {
    if (season.seasonNumber > 0) {
      return AppLocalizations.of(
        context,
      ).detailSeasonNumber(season.seasonNumber);
    }
    final t = season.title.trim();
    return t.isNotEmpty ? t : AppLocalizations.of(context).detailSeasonDefault;
  }

  String _neutralSeasonSubtitle(MediaSeasonSummary season) {
    final episodes = season.localNumberOfEpisodes > 0
        ? season.localNumberOfEpisodes
        : season.numberOfEpisodes;
    if (episodes <= 0) return '';
    return AppLocalizations.of(context).detailEpisodeTotal(episodes);
  }

  /// 把中立季摘要转成季详情页所需的最小 [MediaLibraryItem](导航层数据适配)。
  /// 海报存 Emby 完整直链,季详情页中立路按完整直链透传。
  MediaLibraryItem _seasonItemFromSummary(MediaSeasonSummary season) {
    return MediaLibraryItem.fromJson(<String, dynamic>{
      'guid': season.id,
      'title': season.title,
      'type': 'tv',
      'poster': season.primaryImage.url,
      'season_number': season.seasonNumber,
      'number_of_episodes': season.numberOfEpisodes,
      'local_number_of_episodes': season.localNumberOfEpisodes,
    });
  }

  /// 解析中立(Emby)系列页主播放键的续看/首集目标，更新按键文案。best-effort：失败保持「播放」。
  Future<void> _resolveNeutralPlayTarget(MediaBackend backend) async {
    try {
      final target = await backend.resolveSeriesNextUpEpisode(widget.itemGuid);
      if (!mounted || target == null) return;
      setState(() => _neutralPlayTarget = target);
    } catch (_) {}
  }

  /// 中立(Emby)主播放键文案：解析到续看/首集则显示「第 X 季 第 Y 集」（与飞牛同 l10n key），
  /// 否则「播放」。
  String _neutralPlayLabel() {
    final target = _neutralPlayTarget;
    if (target != null && target.seasonNumber > 0 && target.episodeNumber > 0) {
      return AppLocalizations.of(
        context,
      ).detailSeasonEpisodeNumber(target.seasonNumber, target.episodeNumber);
    }
    if (target != null && target.episodeNumber > 0) {
      return AppLocalizations.of(
        context,
      ).detailEpisodeNumber(target.episodeNumber);
    }
    return AppLocalizations.of(context).detailPlay;
  }

  Future<void> _launchPrimaryPlayback() async {
    if (_playPreparing) {
      _showTopTip(
        AppLocalizations.of(context).detailPreparingPlayback,
        context.appColors.warning,
      );
      return;
    }
    setState(() => _playPreparing = true);
    try {
      final nas = context.read<NasProvider>();
      final backend = context.read<MediaBackendProvider>().backend;
      final isFeiniu = backend.capabilities.kind == MediaBackendKind.feiniu;
      final seriesTitle = isFeiniu
          ? _title(
              _detail['item'] is Map<String, dynamic>
                  ? _detail['item'] as Map<String, dynamic>
                  : _detail,
            )
          : (_neutralDetail?.title ?? '');
      // Emby 系列 guid 不可直接播（无 MediaSources），起播具体单集：复用加载时已解析的续看/
      // 首集目标（按键文案同源）；尚未解析好则即时解析一次。飞牛由 launcher/NAS 自行解析，
      // 原样传系列 guid。
      final playItemId = isFeiniu
          ? widget.itemGuid
          : (_neutralPlayTarget?.id ??
                await backend.resolveSeriesPlaybackTarget(widget.itemGuid));
      if (!mounted) return;
      if (playItemId.trim().isEmpty) {
        _showTopTip(
          AppLocalizations.of(context).detailPlayInfoFailed,
          context.appColors.danger,
        );
        return;
      }
      // 反向通道：剧详情进原生壳，经统一 binder 按后端接线（剧详情只有季列表、无单集列表，
      // 故无选集静态兜底，选集数据由后端按 seriesGuid 派生）。画质切换回传当前集 guid →
      // resolveForNative 重解析（launcher 已后端中立）。
      _reentryToken = NativePlaybackReentry.bind(
        backend: backend,
        nas: nas,
        l10n: AppLocalizations.of(context),
        onResolvePlayback:
            (
              itemGuid, {
              qualityIndex,
              qualityMediaGuid,
              startPositionMs,
              subtitleGuid,
              audioGuid,
              audioTrackIndex,
              subtitleTrackIndex,
              preferredQualityResolution,
            }) async {
              if (!mounted) return null;
              return const TvSeasonPlaybackLauncher().resolveForNative(
                context,
                itemGuid: itemGuid,
                seriesTitle: seriesTitle,
                seriesGuid: widget.itemGuid,
                qualityIndex: qualityIndex,
                qualityMediaGuid: qualityMediaGuid,
                startPositionMs: startPositionMs,
                subtitleGuid: subtitleGuid,
                audioGuid: audioGuid,
                audioTrackIndex: audioTrackIndex,
                subtitleTrackIndex: subtitleTrackIndex,
                preferredQualityResolution: preferredQualityResolution,
              );
            },
      );
      final result = await const TvSeasonPlaybackLauncher().open(
        context,
        itemGuid: playItemId,
        seriesTitle: seriesTitle,
        seriesGuid: widget.itemGuid,
      );
      if (!mounted) return;
      // 续播信息卡仅飞牛（Emby 无 PlayInfoData）。
      if (isFeiniu) {
        final api = FeiniuApi(context.read<NasProvider>());
        final info = await _loadPlayInfoOrNull(api, widget.itemGuid);
        if (!mounted) return;
        if (info != null) {
          setState(() => _playInfo = info);
        }
      } else {
        // 播放回来后重新解析续看目标，使主播放键文案跟最新进度走（否则停留在首次加载值）。
        unawaited(_resolveNeutralPlayTarget(backend));
      }
      if (result != null) {
        unawaited(_refreshDetailSilently());
      }
    } catch (_) {
      _showTopTip(
        AppLocalizations.of(context).detailPlayInfoFailed,
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
        AppLocalizations.of(context).commonClickTooFastRetryLater,
        context.appColors.warning,
      );
      return;
    }
    _lastFavoriteTapAt = now;
    _favoriteUpdating = true;
    final l10n = AppLocalizations.of(context);
    try {
      // 统一走中立后端接口:飞牛→FeiniuApi.setFavorite、Emby→FavoriteItems 端点，文案同口径。
      final backend = context.read<MediaBackendProvider>().backend;
      final state = await backend.setItemFavorite(
        widget.itemGuid,
        favorite: !_liked,
      );
      if (!mounted) return;
      setState(() => _liked = state);
      _showTopTip(
        state ? l10n.actionFavoriteAdded : l10n.actionFavoriteRemoved,
        state ? context.appColors.success : context.appColors.textMuted,
      );
    } catch (_) {
      _showTopTip(
        _liked
            ? AppLocalizations.of(context).detailUnfavoriteFailed
            : AppLocalizations.of(context).detailFavoriteFailed,
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
        AppLocalizations.of(context).commonClickTooFastRetryLater,
        context.appColors.warning,
      );
      return;
    }
    _lastWatchedTapAt = now;
    _watchedUpdating = true;
    final l10n = AppLocalizations.of(context);
    try {
      // 统一走中立后端接口:飞牛→FeiniuApi.setWatched、Emby→PlayedItems 端点，文案同口径。
      final backend = context.read<MediaBackendProvider>().backend;
      final state = await backend.setItemWatched(
        widget.itemGuid,
        watched: !_watched,
      );
      if (!mounted) return;
      setState(() {
        _applyWatchedStateLocally(state);
      });
      _showTopTip(
        state ? l10n.actionMarkedAsWatched : l10n.actionMarkedAsUnwatched,
        state ? context.appColors.success : context.appColors.textMuted,
      );
      // 飞牛已看切换需回灌 PlayInfo（更新跨 UI 的已看/进度态）；中立后端无此通道,跳过。
      if (backend.capabilities.kind == MediaBackendKind.feiniu) {
        unawaited(_refreshDetailSilently());
      }
    } catch (_) {
      _showTopTip(
        _watched
            ? AppLocalizations.of(context).detailMarkUnwatchedFailed
            : AppLocalizations.of(context).detailMarkWatchedFailed,
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
    final (
      dynamicThemeEnabled: dynamicThemeEnabled,
      dynamicThemeIntensity: dynamicThemeIntensity,
    ) = context
        .select<
          AppThemeProvider,
          ({
            bool dynamicThemeEnabled,
            AppDynamicThemeIntensity dynamicThemeIntensity,
          })
        >(
          (themeProvider) => (
            dynamicThemeEnabled: themeProvider.dynamicThemeEnabled,
            dynamicThemeIntensity: themeProvider.dynamicThemeIntensity,
          ),
        );
    final nasProvider = context.read<NasProvider>();
    final inPlayerPaneHost = PlayerPaneHostScope.maybeOf(context) != null;
    final deferArtwork = _loading || !_artworkReady;
    var dynamicThemeImageUrl = '';
    if (_neutralDisplayOnly && _neutralDetail != null) {
      // 中立态:动态取色图源用 Emby 完整直链(backdrop 优先,回退海报),不走飞牛拼接。
      final neutral = _neutralDetail!;
      final ref = neutral.backdropImage.isNotEmpty
          ? neutral.backdropImage
          : neutral.primaryImage;
      dynamicThemeImageUrl = ref.url;
    } else if (_detail.isNotEmpty) {
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
    final dynamicThemeKey = _isPane && widget.itemGuid.trim().isNotEmpty
        ? 'tv-season-series:${widget.itemGuid.trim()}'
        : widget.itemGuid;
    final allowRuntimeThemeSync = dynamicThemeIntensity
        .allowsGlobalRuntimeThemeSync(
          inPlayerPaneHost: inPlayerPaneHost,
          isPane: _isPane,
        );
    final dynamicThemeScopeEnabled = dynamicThemeEnabled;
    final syncGlobalTheme =
        dynamicThemeScopeEnabled &&
        allowRuntimeThemeSync &&
        !_suppressGlobalThemeSyncUntilFullDetail;
    return DynamicPageThemeScope(
      pageKey: dynamicThemeKey,
      imageUrl: dynamicThemeImageUrl,
      token: _neutralDisplayOnly ? '' : nasProvider.token,
      enabled: dynamicThemeScopeEnabled,
      allowLiveResolve: !deferArtwork,
      syncGlobalTheme: syncGlobalTheme,
      deferLocalThemeApplyUntilGlobalSync: _isPane && allowRuntimeThemeSync,
      intensity: dynamicThemeIntensity,
      builder: (context, ambientTint) {
        final colors = context.appColors;
        if (_loading) {
          return DetailLoadingSkeleton(presentation: widget.presentation);
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

        // 中立(Emby)展示路:飞牛 build 整段不进。
        if (_neutralDisplayOnly && _neutralDetail != null) {
          return _buildNeutralBody(colors, ambientTint);
        }

        final provider = context.read<NasProvider>();
        final layout = MediaLayoutProfile.of(context);
        final media = MediaQuery.of(context);
        final screenSize = media.size;
        final heroAdaptive = TvHeroAdaptive.resolve(
          screenSize,
          devicePixelRatio: media.devicePixelRatio,
        );
        final posterHeightMax = screenSize.height * 0.48;
        final posterHeightMin = math.min(300.0, posterHeightMax);
        final posterHeight = math
            .min(
              screenSize.height * heroAdaptive.posterHeightRatio,
              screenSize.width / 1.55,
            )
            .clamp(posterHeightMin, posterHeightMax)
            .toDouble();
        final collapseRangeMax = math.max(1.0, posterHeight);
        final collapseRange =
            (posterHeight - media.padding.top - kToolbarHeight).clamp(
              1.0,
              collapseRangeMax,
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
        final showSeasonPlaceholders = !_seasonItemsResolved && seasonCount > 0;
        final seasonPlaceholderCount = seasonCount.clamp(1, 4);
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

        final heroUrls = deferArtwork
            ? const <String>[]
            : ApiUrlHelper.imageCandidates(
                provider.baseUrl,
                _backdrops(item),
                width: backdropRequestWidth,
              );
        final heroLowResUrls = deferArtwork
            ? const <String>[]
            : ApiUrlHelper.imageCandidates(
                provider.baseUrl,
                _backdrops(item),
                width: 360,
              );
        final logoUrls = deferArtwork
            ? const <String>[]
            : ApiUrlHelper.imageCandidates(
                provider.baseUrl,
                (item['logos'] ?? '').toString(),
                width: logoRequestWidth,
              );
        final heroTitleChild = deferArtwork
            ? const SizedBox.shrink()
            : (logoUrls.isNotEmpty
                  ? DetailHeroLogoTitle(
                      urls: logoUrls,
                      token: provider.token,
                      fallbackTitle: title,
                      maxHeight: 124,
                      maxWidth:
                          screenSize.width -
                          (DetailTokens.screenHorizontalPadding * 2),
                    )
                  : null);

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
                    lowResUrls: heroLowResUrls,
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
                      titleChild: heroTitleChild,
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
                                  sectionTitle: AppLocalizations.of(
                                    context,
                                  ).detailOverviewTitle,
                                  content: overview,
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            AppLocalizations.of(
                              context,
                            ).detailTvSeasonCount(seasonCount),
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
                                        urls: deferArtwork
                                            ? const <String>[]
                                            : _posterCandidates(
                                                provider.baseUrl,
                                                season.poster,
                                                width: layout
                                                    .homePosterRequestWidth,
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
                          else if (showSeasonPlaceholders)
                            SizedBox(
                              height: layout.homePosterRowHeight,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: seasonPlaceholderCount,
                                separatorBuilder: (_, __) =>
                                    SizedBox(width: layout.itemGap),
                                itemBuilder: (context, index) {
                                  final seasonNumber = index + 1;
                                  return SizedBox(
                                    width: layout.homePosterCardWidth,
                                    child: MediaPosterCard(
                                      urls: const <String>[],
                                      token: provider.token,
                                      title: AppLocalizations.of(
                                        context,
                                      ).detailSeasonNumber(seasonNumber),
                                      subtitle: AppLocalizations.of(
                                        context,
                                      ).commonLoading,
                                      imageHeight: layout.homePosterImageHeight,
                                      titleFontSize:
                                          layout.homePosterTitleFontSize,
                                      subtitleFontSize:
                                          layout.homePosterSubtitleFontSize,
                                    ),
                                  );
                                },
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
                                AppLocalizations.of(context).detailSeasonEmpty,
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
                    showBack: true,
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
