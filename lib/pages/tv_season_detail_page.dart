import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../models/media_library_item.dart';
import '../models/person_credit.dart';
import '../models/play_info.dart';
import '../providers/nas_provider.dart';
import '../screens/person_detail_screen.dart';
import '../screens/play_detail_screen.dart';
import '../theme/detail_tokens.dart';
import '../ui/app_transitions.dart';
import '../ui/media_detail_components.dart';
import '../utils/api_url_helper.dart';
import '../utils/app_exception.dart';
import '../utils/detail_top_tip.dart';
import '../utils/imdb_launcher.dart';
import '../utils/media_locale_store.dart';
import '../utils/tv_hero_adaptive.dart';
import '../widgets/common/app_error_state.dart';
import '../widgets/detail/credits_section.dart';
import '../widgets/detail/detail_description_section.dart';
import '../widgets/detail/detail_header.dart';
import '../widgets/detail/detail_icon_button.dart';
import '../widgets/detail/immersive_detail_background.dart';
import '../widgets/detail/link_section.dart';
import 'long_text_overlay_page.dart';

class TvSeasonDetailPage extends StatefulWidget {
  final String parentGuid;
  final String seriesTitle;
  final String backdropPath;
  final MediaLibraryItem seasonItem;

  const TvSeasonDetailPage({
    super.key,
    required this.parentGuid,
    required this.seriesTitle,
    required this.backdropPath,
    required this.seasonItem,
  });

  @override
  State<TvSeasonDetailPage> createState() => _TvSeasonDetailPageState();
}

class _TvSeasonDetailPageState extends State<TvSeasonDetailPage>
    with TickerProviderStateMixin {
  static const int _episodePageSize = 30;
  static const double _landscapePanelDropRatio = 0.10;
  static const double _portraitPanelDropRatio = 0.04;
  static const double _portraitOverlayRatio = 0.45;
  static const double _landscapeOverlayRatio = 0.66;
  static const double _topInsetPosterRatio = 0.55;
  static const List<double> _heroOverlayStops = <double>[
    0.0,
    0.30,
    0.45,
    0.55,
    0.60,
    1.0,
  ];
  static const List<double> _heroOverlayAlphas = <double>[
    0.99,
    0.99,
    0.99,
    0.20,
    0.10,
    0.0,
  ];
  static const Duration _watchedTapCooldown = Duration(milliseconds: 900);
  static const Duration _headerFadeDuration = Duration(milliseconds: 360);
  static const Duration _seasonDataFadeDuration = Duration(milliseconds: 240);
  static const Duration _deferredStartDelay = Duration(milliseconds: 160);
  static const Duration _deferredEpisodeDelay = Duration(milliseconds: 120);
  static const Duration _deferredCreditsDelay = Duration(milliseconds: 140);

  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _scrollOffsetNotifier = ValueNotifier<double>(0);
  final DetailTopTip _topTip = DetailTopTip();
  Map<String, dynamic> _localeMap = const <String, dynamic>{};

  bool _loading = true;
  AppException? _error;

  String _selectedSeasonGuid = '';
  List<MediaLibraryItem> _seasonItems = const [];
  List<MediaLibraryItem> _episodeItems = const [];
  List<PersonCredit> _personCredits = const [];
  Map<String, dynamic> _detail = const {};
  PlayInfoData? _playInfo;
  String _imdbId = '';
  String _trimId = '';

  bool _watched = false;
  bool _watchedUpdating = false;
  DateTime _lastWatchedTapAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _seasonSwitching = false;
  int _episodeRangeIndex = 0;
  int _seasonLoadSeq = 0;

  bool _descriptionVisible = false;
  bool _episodesVisible = false;
  bool _creditsVisible = false;
  Timer? _deferredLoadTimer;
  String _cachedImageBaseUrl = '';
  final Map<String, List<String>> _imageCandidateCache =
  <String, List<String>>{};

  late final AnimationController _headerFadeController;
  late final Animation<double> _headerMetaOpacity;

  @override
  void initState() {
    super.initState();
    _headerFadeController = AnimationController(
      vsync: this,
      duration: _headerFadeDuration,
    );
    _headerMetaOpacity = CurvedAnimation(
      parent: _headerFadeController,
      curve: const Interval(0.34, 1.0, curve: Curves.linear),
    );

    _selectedSeasonGuid = widget.seasonItem.guid;
    _scrollController.addListener(_onScroll);
    _loadSeasonData(_selectedSeasonGuid, showLoading: true);
  }

  @override
  void dispose() {
    _topTip.dispose();
    _deferredLoadTimer?.cancel();
    _headerFadeController.dispose();
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

  void _resetScrollToTop() {
    if (_scrollOffsetNotifier.value != 0) {
      _scrollOffsetNotifier.value = 0;
    }
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollOffsetNotifier.value != 0) {
        _scrollOffsetNotifier.value = 0;
      }
      if (_scrollController.hasClients && _scrollController.offset != 0) {
        _scrollController.jumpTo(0);
      }
    });
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

  int _asInt(dynamic value) => int.tryParse('$value') ?? 0;

  String _year(String date) => date.length >= 4 ? date.substring(0, 4) : '';

  Map<String, dynamic> _itemMap(Map<String, dynamic> raw) {
    final item = raw['item'];
    if (item is Map<String, dynamic>) return item;
    return raw;
  }

  MediaLibraryItem _currentSeason() {
    for (final season in _seasonItems) {
      if (season.guid == _selectedSeasonGuid) return season;
    }
    return widget.seasonItem;
  }

  String _seasonLabel(MediaLibraryItem season) {
    if (season.seasonNumber > 0) {
      return _t(
        'layout.subheading.season.number',
        '第 {number} 季',
        params: {'number': season.seasonNumber},
      );
    }
    final title = season.title.trim();
    return title.isNotEmpty
        ? title
        : _t('layout.subheading.season.default', '季信息');
  }

  String _playLabel() {
    final item = _playInfo?.item;
    final episodeNo = item?.episodeNumber ?? 1;
    if (episodeNo > 0) {
      return _t(
        'layout.subheading.episode.number',
        '第 {number} 集',
        params: {'number': episodeNo},
      );
    }
    return _t('player.play.play', '播放');
  }

  String _episodeTitle(MediaLibraryItem item, int index) {
    final cleanTitle = item.title.trim().replaceAll(
      RegExp(r'\.(mkv|mp4|m4v|avi|ts|flv|mov)$', caseSensitive: false),
      '',
    );
    final episodeNo = item.episodeNumber;
    if (episodeNo > 0) {
      return cleanTitle.isNotEmpty
          ? '$episodeNo.$cleanTitle'
          : '$episodeNo.${_t(
        'layout.subheading.episode.number',
        '第 {number} 集',
        params: {'number': episodeNo},
      )}';
    }
    final fallback = cleanTitle.isNotEmpty
        ? cleanTitle
        : _t(
      'layout.subheading.episode.number',
      '第 {number} 集',
      params: {'number': index + 1},
    );
    return '${_t('layout.subheading.episode.unknown', '未知集数')}.$fallback';
  }

  String _durationText(int seconds) {
    if (seconds <= 0) return '';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '$h小时$m分钟$s秒';
    if (m > 0) return '$m分钟$s秒';
    return '$s秒';
  }

  void _openEpisodeIntro(MediaLibraryItem episode, int absoluteIndex) {
    final content = episode.overview.trim().isEmpty
        ? _t('layout.details.overview.empty', '暂无简介')
        : episode.overview.trim();
    LongTextOverlayPage.show(
      context,
      title: _episodeTitle(episode, absoluteIndex),
      sectionTitle: _t('layout.details.overview.overview', '简介'),
      content: content,
    );
  }

  bool _hasMeaningfulText(String? value) {
    final text = (value ?? '').trim();
    return text.isNotEmpty &&
        text != _t('layout.details.overview.empty', '暂无简介') &&
        text != _t('layout.details.episode.empty', '暂无剧集信息');
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

  List<List<MediaLibraryItem>> _episodeRanges() {
    if (_episodeItems.isEmpty) return const [];
    final out = <List<MediaLibraryItem>>[];
    for (int i = 0; i < _episodeItems.length; i += _episodePageSize) {
      final end = (i + _episodePageSize).clamp(0, _episodeItems.length);
      out.add(_episodeItems.sublist(i, end));
    }
    return out;
  }

  String _episodeListSignature() {
    if (_episodeItems.isEmpty) return 'none';
    final first = _episodeItems.first.guid;
    final last = _episodeItems.last.guid;
    return '${_episodeItems.length}:$first:$last';
  }

  String _creditListSignature() {
    if (_personCredits.isEmpty) return 'none';
    final first = _personCredits.first.displayName;
    final last = _personCredits.last.displayName;
    return '${_personCredits.length}:$first:$last';
  }

  List<String> _imageCandidates(String rawPath, {int width = 860}) {
    final provider = context.read<NasProvider>();
    final baseUrl = provider.baseUrl;
    if (_cachedImageBaseUrl != baseUrl) {
      _cachedImageBaseUrl = baseUrl;
      _imageCandidateCache.clear();
    }
    final key = '$width|$rawPath';
    final cached = _imageCandidateCache[key];
    if (cached != null) return cached;
    final generated = List<String>.unmodifiable(
      ApiUrlHelper.imageCandidates(baseUrl, rawPath, width: width),
    );
    _imageCandidateCache[key] = generated;
    return generated;
  }

  Future<PlayInfoData?> _loadPlayInfoOrNull(FeiniuApi api, String guid) async {
    try {
      return await api.getPlayInfo(guid);
    } catch (_) {
      return null;
    }
  }

  LinearGradient _heroOverlayGradient() {
    const base = DetailTokens.pageBackground;
    return LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: _heroOverlayAlphas
          .map((alpha) => base.withValues(alpha: alpha))
          .toList(growable: false),
      stops: _heroOverlayStops,
    );
  }

  Widget _seasonNumberWidget(MediaLibraryItem season) {
    final seasonNo = season.seasonNumber;
    if (seasonNo <= 0) {
      return Text(
        _seasonLabel(season),
        style: const TextStyle(
          color: DetailTokens.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w500,
        ),
      );
    }
    return Row(
      children: [
        const Text(
          '第',
          style: TextStyle(
            color: DetailTokens.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        AppTransitions.crossFadeSwitch(
          switchKey: 'season-no-$seasonNo',
          duration: _seasonDataFadeDuration,
          child: Text(
            '$seasonNo',
            key: ValueKey<int>(seasonNo),
            style: const TextStyle(
              color: DetailTokens.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Text(
          '季',
          style: TextStyle(
            color: DetailTokens.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  void _showTopTip(String message, Color color) {
    if (!mounted) return;
    _topTip.show(context, message: message, color: color);
  }

  void _startEntryAnimations() {
    _headerFadeController.forward(from: 0);
  }

  void _resetEntryAnimations() {
    _headerFadeController.reset();
  }

  Future<void> _openImdb() async {
    final result = await ImdbLauncher.openExternal(_imdbId);
    switch (result) {
      case ImdbLaunchResult.success:
        return;
      case ImdbLaunchResult.empty:
        _showTopTip(
          _t('layout.details.castAndCrew.imdb', '暂无 IMDB 链接'),
          const Color(0xFFB8860B),
        );
      case ImdbLaunchResult.failed:
        _showTopTip(
          _t('layout.details.castAndCrew.imdbOpenFailed', '无法打开 IMDB 链接'),
          const Color(0xFFD64545),
        );
    }
  }

  Future<void> _openTmdb() async {
    final result = await ImdbLauncher.openTmdbExternal(_trimId);
    switch (result) {
      case ImdbLaunchResult.success:
        return;
      case ImdbLaunchResult.empty:
        _showTopTip('暂无 TMDB 链接', const Color(0xFFB8860B));
      case ImdbLaunchResult.failed:
        _showTopTip('无法打开 TMDB 链接', const Color(0xFFD64545));
    }
  }

  void _openCreditPerson(CreditPersonItem person) {
    final guid = person.personGuid.trim();
    if (guid.isEmpty) return;
    Navigator.of(context).push(
      AppTransitions.leftToRightPageTurnRoute(
        PersonDetailScreen(personGuid: guid, initialName: person.name),
      ),
    );
  }

  Future<void> _loadSeasonData(
      String requestedGuid, {
        required bool showLoading,
      }) async {
    unawaited(_ensureLocaleMapLoaded());
    _deferredLoadTimer?.cancel();
    if (showLoading) _resetEntryAnimations();
    final seq = ++_seasonLoadSeq;

    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
        _descriptionVisible = false;
      });
    }

    try {
      final api = FeiniuApi(context.read<NasProvider>());
      final seasons = await api.getSeasonList(widget.parentGuid);
      final target = seasons.any((s) => s.guid == requestedGuid)
          ? requestedGuid
          : (seasons.isNotEmpty ? seasons.first.guid : requestedGuid);

      final results = await Future.wait<dynamic>([
        api.getItemDetail(target),
        _loadPlayInfoOrNull(api, target),
      ]);

      if (!mounted || seq != _seasonLoadSeq) return;
      final detail = results[0] as Map<String, dynamic>;
      final playInfo = results[1] as PlayInfoData?;
      setState(() {
        _seasonItems = seasons;
        _selectedSeasonGuid = target;
        _detail = detail;
        _playInfo = playInfo;
        _imdbId = _extractImdbId(detail);
        _trimId = _extractTrimId(detail);
        _watched = _asInt(_itemMap(detail)['is_watched']) == 1;
        if (showLoading) {
          _episodeItems = const [];
          _personCredits = const [];
          _episodeRangeIndex = 0;
          _episodesVisible = false;
          _creditsVisible = false;
        }
        _descriptionVisible = !showLoading;
        _loading = false;
        _error = null;
      });
      _resetScrollToTop();
      if (showLoading) _startEntryAnimations();
      _startDeferredLoad(seq: seq, seasonGuid: target);
    } catch (e) {
      if (!mounted || seq != _seasonLoadSeq) return;
      setState(() {
        _error = AppException.from(
          e,
          action: 'tv season detail',
          fallbackKind: AppExceptionKind.transient,
        );
        _loading = false;
      });
    }
  }

  void _startDeferredLoad({required int seq, required String seasonGuid}) {
    _deferredLoadTimer?.cancel();
    _deferredLoadTimer = Timer(_deferredStartDelay, () {
      if (!mounted ||
          seq != _seasonLoadSeq ||
          seasonGuid != _selectedSeasonGuid) {
        return;
      }
      setState(() => _descriptionVisible = true);
      unawaited(_loadDeferredSections(seq: seq, seasonGuid: seasonGuid));
    });
  }

  Future<void> _loadDeferredSections({
    required int seq,
    required String seasonGuid,
  }) async {
    await Future<void>.delayed(_deferredEpisodeDelay);
    if (!mounted ||
        seq != _seasonLoadSeq ||
        seasonGuid != _selectedSeasonGuid) {
      return;
    }

    final api = FeiniuApi(context.read<NasProvider>());
    try {
      final episodes = await api.getEpisodeList(seasonGuid);
      if (!mounted ||
          seq != _seasonLoadSeq ||
          seasonGuid != _selectedSeasonGuid) {
        return;
      }
      setState(() {
        _episodeItems = episodes;
        _episodeRangeIndex = 0;
        _episodesVisible = episodes.isNotEmpty;
      });
    } catch (_) {}

    await Future<void>.delayed(_deferredCreditsDelay);
    if (!mounted ||
        seq != _seasonLoadSeq ||
        seasonGuid != _selectedSeasonGuid) {
      return;
    }
    try {
      final people = await api.getPersonList(seasonGuid);
      if (!mounted ||
          seq != _seasonLoadSeq ||
          seasonGuid != _selectedSeasonGuid) {
        return;
      }
      setState(() {
        _personCredits = people;
        _creditsVisible = people.isNotEmpty;
      });
    } catch (_) {
      if (!mounted ||
          seq != _seasonLoadSeq ||
          seasonGuid != _selectedSeasonGuid) {
        return;
      }
    }
  }

  Future<void> _switchSeason(String seasonGuid) async {
    if (_selectedSeasonGuid == seasonGuid || _seasonSwitching) return;
    _resetScrollToTop();
    setState(() {
      _seasonSwitching = true;
      _selectedSeasonGuid = seasonGuid;
      _detail = const <String, dynamic>{};
      _playInfo = null;
      _imdbId = '';
      _error = null;
      _episodeItems = const [];
      _personCredits = const [];
      _episodeRangeIndex = 0;
      _episodesVisible = false;
      _creditsVisible = false;
      _descriptionVisible = false;
    });
    try {
      await _loadSeasonData(seasonGuid, showLoading: false);
    } finally {
      if (mounted) {
        _resetScrollToTop();
        setState(() {
          _seasonSwitching = false;
        });
      } else {
        _seasonSwitching = false;
      }
    }
  }

  Future<void> _onPlayTap() async {
    final season = _currentSeason();
    try {
      final info = await FeiniuApi(
        context.read<NasProvider>(),
      ).getPlayInfo(season.guid);
      if (!mounted) return;
      setState(() => _playInfo = info);
      _showTopTip(
        _t('player.play.placeholder', '播放接口已预留'),
        const Color(0xFF19A35B),
      );
    } catch (_) {
      _showTopTip(
        _t('player.play.playInfoFailed', '获取播放信息失败'),
        const Color(0xFFD64545),
      );
    }
  }

  Future<void> _toggleWatched() async {
    final season = _currentSeason();
    final now = DateTime.now();
    if (_watchedUpdating ||
        now.difference(_lastWatchedTapAt) < _watchedTapCooldown) {
      _showTopTip(
        _t('layout.globalError.clickToRetry', '点击过快，请稍后重试'),
        const Color(0xFFB8860B),
      );
      return;
    }
    _lastWatchedTapAt = now;
    _watchedUpdating = true;
    try {
      final watched = await FeiniuApi(
        context.read<NasProvider>(),
      ).setWatched(season.guid, watched: !_watched);
      if (!mounted) return;
      setState(() => _watched = watched);
      _showTopTip(
        watched
            ? _t('common.actions.watched.markedAsWatched', '已标记为已观看')
            : _t('common.actions.watched.markedAsUnwatched', '已标记为未观看'),
        watched ? const Color(0xFF19A35B) : const Color(0xFF3B4A5E),
      );
    } catch (_) {
      _showTopTip(
        _watched
            ? _t(
          'common.actions.watched.markedAsUnwatchedFailed',
          '取消已观看失败',
        )
            : _t(
          'common.actions.watched.markedAsWatchedFailed',
          '标记已观看失败',
        ),
        const Color(0xFFD64545),
      );
    } finally {
      _watchedUpdating = false;
    }
  }

  Future<void> _openEpisodeDetail(MediaLibraryItem episode) async {
    Map<String, dynamic>? initialDetail;
    try {
      initialDetail = await FeiniuApi(
        context.read<NasProvider>(),
      ).getItemDetail(episode.guid).timeout(const Duration(milliseconds: 240));
    } catch (_) {}
    if (!mounted) return;
    await Navigator.of(context).push(
      AppTransitions.leftToRightPageTurnRoute(
        PlayDetailScreen(
          itemGuid: episode.guid,
          heroTag: null,
          initialItemDetail: initialDetail,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: DetailTokens.pageBackground,
        appBar: AppBar(backgroundColor: DetailTokens.pageBackground),
        body: AppErrorState(
          error: _error!,
          localeMap: _localeMap,
          onRetry: () => _loadSeasonData(_selectedSeasonGuid, showLoading: true),
        ),
      );
    }

    final provider = context.read<NasProvider>();
    final media = MediaQuery.of(context);
    final screenSize = media.size;
    final textScale = media.textScaler.scale(1).clamp(1.0, 1.35);
    final aspect = screenSize.height / screenSize.width;
    final shortestSide = screenSize.shortestSide;
    final isLandscape = screenSize.width > screenSize.height;
    final isTablet = shortestSide >= 720.0;
    final heroAdaptive = TvHeroAdaptive.resolve(
      screenSize,
      devicePixelRatio: media.devicePixelRatio,
    );
    final posterHeightRatio = isLandscape ? 0.42 : 0.35;
    final posterHeight = screenSize.height * posterHeightRatio;
    final collapseRange = (posterHeight - media.padding.top - kToolbarHeight)
        .clamp(120.0, 360.0);

    final item = _itemMap(_detail);
    final season = _currentSeason();
    final overview = (item['overview'] ?? season.overview).toString().trim();
    final hasOverview = _hasMeaningfulText(overview);
    final year = _year(season.releaseDate);
    final rating = double.tryParse(season.voteAverage) ?? 0;
    final title = widget.seriesTitle;
    final playLabel = _playLabel();

    final backdropUrls = _imageCandidates(widget.backdropPath, width: 1200);
    final posterUrls = _imageCandidates(season.poster, width: 560);

    final episodeRanges = _episodeRanges();
    final safeRangeIndex = episodeRanges.isEmpty
        ? 0
        : _episodeRangeIndex.clamp(0, episodeRanges.length - 1);
    final visibleEpisodes = episodeRanges.isEmpty
        ? const <MediaLibraryItem>[]
        : episodeRanges[safeRangeIndex];

    final creditItems = _personCredits
        .map(
          (p) => CreditPersonItem(
        personGuid: p.personGuid,
        name: p.displayName,
        subtitle: p.displaySubTitle,
        imageUrls: _imageCandidates(p.profilePath, width: 280),
      ),
    )
        .toList();

    final posterWidth = (screenSize.width * (isLandscape ? 0.30 : 0.36)).clamp(
      136.0,
      isLandscape ? 182.0 : 188.0,
    );
    final posterCardHeight = posterWidth * 1.45;
    final posterBridgeOverlap = (posterCardHeight * 0.45).clamp(52.0, 92.0);
    final panelDropOffset = isLandscape
        ? (posterHeight * _landscapePanelDropRatio).clamp(24.0, 80.0)
        : (posterHeight * _portraitPanelDropRatio).clamp(8.0, 36.0);
    final tallComp = ((aspect - 1.90) * 80.0).clamp(0.0, 36.0);
    final tabletInsetComp = isTablet
        ? (screenSize.height * (isLandscape ? 0.06 : 0.075)).clamp(
      isLandscape ? 80.0 : 120.0,
      isLandscape ? 220.0 : 280.0,
    )
        : 0.0;
    final headerBodyTopPadding =
    (posterCardHeight - posterBridgeOverlap + 12 - panelDropOffset).clamp(
      60.0,
      360.0,
    );
    final heroOverlayExtra = isLandscape
        ? (posterCardHeight * _landscapeOverlayRatio).clamp(150.0, 170.0)
        : (posterCardHeight * _portraitOverlayRatio).clamp(112.0, 132.0);
    final heroOverlayHeight = posterHeight + heroOverlayExtra;
    final heroOverlayGradient = _heroOverlayGradient();
    final topContentInset =
        media.padding.top +
            kToolbarHeight +
            (posterCardHeight * _topInsetPosterRatio) +
            panelDropOffset +
            tallComp +
            tabletInsetComp;
    final heroImageScale = isLandscape
        ? (heroAdaptive.imageScale * 1.08)
        : heroAdaptive.imageScale;
    final titleFontSize = isLandscape
        ? (screenSize.width * 0.028).clamp(30.0, 38.0)
        : 24.0;
    final episodeCardWidth =
    ((screenSize.width - DetailTokens.screenHorizontalPadding * 2 - 10) / 2)
        .clamp(160.0, 206.0);
    final episodeImageHeight = episodeCardWidth * 9 / 16;
    final playLabelFontSize = (20.0 * textScale).clamp(18.0, 24.0);
    final episodeTitleFontSize = (15.0 * textScale).clamp(14.0, 18.0);
    final episodeMetaFontSize = (13.0 * textScale).clamp(12.0, 16.0);
    const episodeTitleLineFactor = 1.20;
    const episodeMetaLineFactor = 1.20;
    final episodeSummaryHeight =
    (episodeMetaFontSize * 2 * episodeMetaLineFactor + 2.0).clamp(
      34.0,
      58.0,
    );
    final episodeRangeChipHeight = isLandscape ? 44.0 : 38.0;
    final episodeRangeChipVPadding = isLandscape ? 10.0 : 8.0;
    final episodeCardSafeBottom = isLandscape ? 18.0 : 12.0;
    final episodeCardExtraHeight =
        8.0 +
            (episodeTitleFontSize * episodeTitleLineFactor) +
            4.0 +
            episodeSummaryHeight +
            4.0 +
            (episodeMetaFontSize * episodeMetaLineFactor) +
            episodeCardSafeBottom;

    return Scaffold(
      backgroundColor: DetailTokens.pageBackground,
      body: AppTransitions.crossFadeSwitch(
        switchKey: 'page-state-${_loading ? 'loading' : 'ready'}',
        duration: _seasonDataFadeDuration,
        child: _loading
            ? const SizedBox.expand()
            : Stack(
          fit: StackFit.expand,
          children: [
            ValueListenableBuilder<double>(
              valueListenable: _scrollOffsetNotifier,
              builder: (context, offset, _) {
                return ImmersiveDetailBackground(
                  urls: backdropUrls,
                  token: provider.token,
                  scrollOffset: offset,
                  posterHeight: posterHeight,
                  imageScale: heroImageScale,
                  imageFit: BoxFit.cover,
                  imageAlignment: Alignment(
                    heroAdaptive.imageAlignX,
                    heroAdaptive.imageAlignY,
                  ),
                  parallaxFactor: 1.0,
                  fillGapsWithImage: false,
                  enableBottomFade: false,
                  useMonetTint: false,
                );
              },
            ),
            ValueListenableBuilder<double>(
              valueListenable: _scrollOffsetNotifier,
              builder: (context, offset, _) {
                final overlayShift = -offset.clamp(
                  0.0,
                  heroOverlayHeight,
                );
                return Positioned(
                  left: 0,
                  right: 0,
                  top: overlayShift,
                  height: heroOverlayHeight,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: heroOverlayGradient,
                      ),
                    ),
                  ),
                );
              },
            ),
            CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: SizedBox(height: topContentInset),
                ),
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        color: DetailTokens.pageBackground,
                        padding: const EdgeInsets.fromLTRB(
                          DetailTokens.screenHorizontalPadding,
                          0,
                          DetailTokens.screenHorizontalPadding,
                          24,
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: 0,
                              right: 0,
                              top: -posterBridgeOverlap - panelDropOffset,
                              child: Row(
                                crossAxisAlignment:
                                CrossAxisAlignment.end,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      18,
                                    ),
                                    child: SizedBox(
                                      width: posterWidth,
                                      height: posterCardHeight,
                                      child: DetailHeroImage(
                                        urls: posterUrls,
                                        token: provider.token,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 16,
                                      ),
                                      child: AnimatedBuilder(
                                        animation: _headerFadeController,
                                        builder: (context, child) {
                                          return Opacity(
                                            opacity:
                                            _headerMetaOpacity.value,
                                            child: child,
                                          );
                                        },
                                        child: Column(
                                          crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title,
                                              maxLines: 2,
                                              overflow:
                                              TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: DetailTokens
                                                    .textPrimary,
                                                fontSize: titleFontSize,
                                                fontWeight:
                                                FontWeight.w600,
                                                height: 1.2,
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            AppTransitions.crossFadeSwitch(
                                              switchKey:
                                              'meta-$_selectedSeasonGuid',
                                              duration:
                                              _seasonDataFadeDuration,
                                              child: Column(
                                                key: ValueKey<String>(
                                                  'meta-content-$_selectedSeasonGuid',
                                                ),
                                                crossAxisAlignment:
                                                CrossAxisAlignment
                                                    .start,
                                                children: [
                                                  _seasonNumberWidget(
                                                    season,
                                                  ),
                                                  const SizedBox(
                                                    height: 8,
                                                  ),
                                                  Row(
                                                    children: [
                                                      if (rating > 0)
                                                        Text(
                                                          _t(
                                                            'layout.rating.score',
                                                            '{score} 分',
                                                            params: {
                                                              'score': rating
                                                                  .toStringAsFixed(
                                                                1,
                                                              ),
                                                            },
                                                          ),
                                                          style: const TextStyle(
                                                            color: Color(
                                                              0xFFF2D34B,
                                                            ),
                                                            fontSize: 17,
                                                            fontWeight:
                                                            FontWeight
                                                                .w500,
                                                          ),
                                                        ),
                                                      if (rating > 0 &&
                                                          year.isNotEmpty)
                                                        const Text(
                                                          '  /  ',
                                                          style: TextStyle(
                                                            color: DetailTokens
                                                                .textSecondary,
                                                            fontSize: 17,
                                                          ),
                                                        ),
                                                      if (year.isNotEmpty)
                                                        Text(
                                                          year,
                                                          style: const TextStyle(
                                                            color: DetailTokens
                                                                .textSecondary,
                                                            fontSize: 17,
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.only(
                                top: headerBodyTopPadding,
                              ),
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: DetailPrimaryPlayButton(
                                          text: playLabel,
                                          textSwitchKey:
                                          'play-label-$playLabel',
                                          textStyle: TextStyle(
                                            fontSize: playLabelFontSize,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          onTap: _onPlayTap,
                                          backgroundColor:
                                          DetailTokens.primaryButton,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      DetailIconButton(
                                        iconAsset:
                                        'assets/icons/download.svg',
                                        onTap: () => _showTopTip(
                                          _t(
                                            'common.actions.download.placeholder',
                                            '下载接口已预留',
                                          ),
                                          const Color(0xFF3B4A5E),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      DetailIconButton(
                                        iconAsset:
                                        'assets/icons/check.svg',
                                        selected: _watched,
                                        onTap: _toggleWatched,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  AnimatedSize(
                                    duration: _seasonDataFadeDuration,
                                    curve: Curves.easeOut,
                                    alignment: Alignment.topCenter,
                                    child: Column(
                                      crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                      children: [
                                        AppTransitions.fadeDownSwitch(
                                          switchKey:
                                          'overview-$_selectedSeasonGuid-${hasOverview ? 1 : 0}-${_descriptionVisible ? 1 : 0}-${overview.hashCode}',
                                          duration:
                                          _seasonDataFadeDuration,
                                          child:
                                          (hasOverview &&
                                              _descriptionVisible)
                                              ? DetailDescriptionSection(
                                            text: overview,
                                            maxLines: 3,
                                            baseFontSize: 14,
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
                                          )
                                              : const SizedBox.shrink(),
                                        ),
                                        SizedBox(
                                          height: hasOverview ? 12 : 16,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_seasonItems.isNotEmpty)
                                    SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children: [
                                          for (
                                          int i = 0;
                                          i < _seasonItems.length;
                                          i++
                                          ) ...[
                                            if (i > 0)
                                              const Padding(
                                                padding:
                                                EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                ),
                                                child: Text(
                                                  '/',
                                                  style: TextStyle(
                                                    color: DetailTokens
                                                        .textSecondary,
                                                    fontSize: 17,
                                                    fontWeight:
                                                    FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            InkWell(
                                              onTap: () => _switchSeason(
                                                _seasonItems[i].guid,
                                              ),
                                              child: Text(
                                                _seasonLabel(
                                                  _seasonItems[i],
                                                ),
                                                style: TextStyle(
                                                  color:
                                                  _seasonItems[i]
                                                      .guid ==
                                                      _selectedSeasonGuid
                                                      ? const Color(
                                                    0xFF2D87FF,
                                                  )
                                                      : DetailTokens
                                                      .textSecondary,
                                                  fontSize: 17,
                                                  fontWeight:
                                                  FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  AppTransitions.crossFadeSwitch(
                                    switchKey:
                                    'season-body-${_episodesVisible ? 1 : 0}-${_episodeListSignature()}',
                                    duration: _seasonDataFadeDuration,
                                    child: Column(
                                      key: ValueKey<String>(
                                        'season-body-content-${_episodeListSignature()}',
                                      ),
                                      crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                      children: [
                                        if (_episodesVisible &&
                                            episodeRanges.length > 1) ...[
                                          const SizedBox(height: 12),
                                          SizedBox(
                                            height:
                                            episodeRangeChipHeight,
                                            child: ListView.separated(
                                              scrollDirection:
                                              Axis.horizontal,
                                              itemCount:
                                              episodeRanges.length,
                                              separatorBuilder: (_, __) =>
                                              const SizedBox(
                                                width: 8,
                                              ),
                                              itemBuilder: (context, i) {
                                                final start =
                                                    i * _episodePageSize +
                                                        1;
                                                final end =
                                                (start +
                                                    _episodePageSize -
                                                    1)
                                                    .clamp(
                                                  1,
                                                  _episodeItems
                                                      .length,
                                                );
                                                final selected =
                                                    i == safeRangeIndex;
                                                return InkWell(
                                                  onTap: () => setState(
                                                        () =>
                                                    _episodeRangeIndex =
                                                        i,
                                                  ),
                                                  child: AnimatedContainer(
                                                    duration: AppTransitions
                                                        .switchDuration,
                                                    curve: AppTransitions
                                                        .easeOut,
                                                    constraints:
                                                    BoxConstraints(
                                                      minHeight:
                                                      episodeRangeChipHeight,
                                                    ),
                                                    padding:
                                                    EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical:
                                                      episodeRangeChipVPadding,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: selected
                                                          ? const Color(
                                                        0x142D87FF,
                                                      )
                                                          : const Color(
                                                        0xFF101927,
                                                      ),
                                                      borderRadius:
                                                      BorderRadius.circular(
                                                        10,
                                                      ),
                                                      border: Border.all(
                                                        color: selected
                                                            ? const Color(
                                                          0xFF2D87FF,
                                                        )
                                                            : const Color(
                                                          0x2A6E8DB1,
                                                        ),
                                                      ),
                                                    ),
                                                    child: Text(
                                                      '$start - $end',
                                                      style: TextStyle(
                                                        color: selected
                                                            ? const Color(
                                                          0xFF2D87FF,
                                                        )
                                                            : DetailTokens
                                                            .textSecondary,
                                                        fontSize: 15,
                                                        fontWeight:
                                                        FontWeight
                                                            .w600,
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ],
                                        if (_episodesVisible &&
                                            visibleEpisodes
                                                .isNotEmpty) ...[
                                          const SizedBox(height: 12),
                                          SizedBox(
                                            height:
                                            episodeImageHeight +
                                                episodeCardExtraHeight,
                                            child: ListView.separated(
                                              scrollDirection:
                                              Axis.horizontal,
                                              cacheExtent: 520,
                                              itemCount:
                                              visibleEpisodes.length,
                                              separatorBuilder: (_, __) =>
                                              const SizedBox(
                                                width: 10,
                                              ),
                                              itemBuilder: (context, index) {
                                                final episode =
                                                visibleEpisodes[index];
                                                final absoluteIndex =
                                                _episodeItems.indexOf(
                                                  episode,
                                                );
                                                final titleText =
                                                _episodeTitle(
                                                  episode,
                                                  absoluteIndex >= 0
                                                      ? absoluteIndex
                                                      : index,
                                                );
                                                final summary = episode
                                                    .overview
                                                    .trim()
                                                    .replaceAll(
                                                  '\n',
                                                  ' ',
                                                );
                                                final hasSummary =
                                                _hasMeaningfulText(
                                                  summary,
                                                );
                                                return RepaintBoundary(
                                                  child: SizedBox(
                                                    width:
                                                    episodeCardWidth,
                                                    child: InkWell(
                                                      borderRadius:
                                                      BorderRadius.circular(
                                                        10,
                                                      ),
                                                      onTap: () =>
                                                          _openEpisodeDetail(
                                                            episode,
                                                          ),
                                                      child: Column(
                                                        crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                        children: [
                                                          ClipRRect(
                                                            borderRadius:
                                                            BorderRadius.circular(
                                                              10,
                                                            ),
                                                            child: SizedBox(
                                                              width: double
                                                                  .infinity,
                                                              height:
                                                              episodeImageHeight,
                                                              child: DetailHeroImage(
                                                                urls: _imageCandidates(
                                                                  episode
                                                                      .poster,
                                                                  width:
                                                                  720,
                                                                ),
                                                                token: provider
                                                                    .token,
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 8,
                                                          ),
                                                          Text(
                                                            titleText,
                                                            maxLines: 1,
                                                            overflow:
                                                            TextOverflow
                                                                .ellipsis,
                                                            style: TextStyle(
                                                              color: DetailTokens
                                                                  .textPrimary,
                                                              fontSize:
                                                              episodeTitleFontSize,
                                                              height:
                                                              episodeTitleLineFactor,
                                                              fontWeight:
                                                              FontWeight
                                                                  .w500,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 4,
                                                          ),
                                                          Expanded(
                                                            child: Column(
                                                              crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                              children: [
                                                                Expanded(
                                                                  child:
                                                                  hasSummary
                                                                      ? _EpisodeSummaryLine(
                                                                    summary: summary,
                                                                    fontSize: episodeMetaFontSize,
                                                                    detailText: _t(
                                                                      'layout.details.castAndCrew.showMore',
                                                                      '详情',
                                                                    ),
                                                                    onDetailTap: () => _openEpisodeIntro(
                                                                      episode,
                                                                      absoluteIndex >=
                                                                          0
                                                                          ? absoluteIndex
                                                                          : index,
                                                                    ),
                                                                  )
                                                                      : const SizedBox.shrink(),
                                                                ),
                                                                const SizedBox(
                                                                  height:
                                                                  2,
                                                                ),
                                                                Text(
                                                                  _durationText(
                                                                    episode
                                                                        .duration,
                                                                  ),
                                                                  maxLines:
                                                                  1,
                                                                  overflow:
                                                                  TextOverflow.ellipsis,
                                                                  style: TextStyle(
                                                                    color:
                                                                    DetailTokens.textSecondary,
                                                                    fontSize:
                                                                    episodeMetaFontSize,
                                                                    height:
                                                                    episodeMetaLineFactor,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  AnimatedSize(
                                    duration: _seasonDataFadeDuration,
                                    curve: Curves.easeOut,
                                    alignment: Alignment.topCenter,
                                    child: AppTransitions.fadeDownSwitch(
                                      switchKey:
                                      'credits-block-${_creditsVisible ? 1 : 0}-${_creditListSignature()}',
                                      duration: _seasonDataFadeDuration,
                                      child:
                                      (_creditsVisible &&
                                          creditItems.isNotEmpty)
                                          ? Column(
                                        key: ValueKey<String>(
                                          'credits-content-${_creditListSignature()}',
                                        ),
                                        crossAxisAlignment:
                                        CrossAxisAlignment
                                            .start,
                                        children: [
                                          const SizedBox(
                                            height: 20,
                                          ),
                                          CreditsSection(
                                            title: _t(
                                              'layout.details.castAndCrew.title',
                                              '演职人员',
                                            ),
                                            items: creditItems,
                                            token: provider.token,
                                            onTap:
                                            _openCreditPerson,
                                          ),
                                        ],
                                      )
                                          : const SizedBox.shrink(),
                                    ),
                                  ),
                                  if (_imdbId.trim().isNotEmpty ||
                                      _trimId.trim().isNotEmpty) ...[
                                    const SizedBox(height: 20),
                                    LinkSection(
                                      imdbId: _imdbId,
                                      tmdbId: _trimId,
                                      onImdbTap: _openImdb,
                                      onTmdbTap: _openTmdb,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            ValueListenableBuilder<double>(
              valueListenable: _scrollOffsetNotifier,
              builder: (context, offset, _) {
                final collapseT = (offset / collapseRange).clamp(
                  0.0,
                  1.0,
                );
                final centerTitleOpacity = ((collapseT - 0.82) / 0.16)
                    .clamp(0.0, 1.0);
                return DetailFloatingTopBar(
                  onBack: () => Navigator.of(context).maybePop(),
                  onMore: () {},
                  title: '$title ${_seasonLabel(season)}',
                  titleOpacity: centerTitleOpacity,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeSummaryLine extends StatelessWidget {
  final String summary;
  final double fontSize;
  final String detailText;
  final VoidCallback onDetailTap;

  const _EpisodeSummaryLine({
    required this.summary,
    required this.fontSize,
    required this.detailText,
    required this.onDetailTap,
  });

  bool _exceedsTwoLines({
    required BuildContext context,
    required double maxWidth,
    required InlineSpan text,
  }) {
    final painter = TextPainter(
      text: text,
      maxLines: 2,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: maxWidth);
    return painter.didExceedMaxLines;
  }

  @override
  Widget build(BuildContext context) {
    final normalStyle = TextStyle(
      color: DetailTokens.textSecondary,
      fontSize: fontSize,
      height: 1.2,
    );
    final detailStyle = TextStyle(
      color: const Color(0xFF2D87FF),
      fontWeight: FontWeight.w600,
      fontSize: fontSize - 1,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final safeWidth = maxWidth > 8 ? maxWidth - 8 : maxWidth;
        if (maxWidth <= 0) return const SizedBox.shrink();

        final plain = TextSpan(text: summary, style: normalStyle);
        final overflowed = _exceedsTwoLines(
          context: context,
          maxWidth: safeWidth,
          text: plain,
        );
        if (!overflowed) {
          return Text(
            summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: normalStyle,
          );
        }

        const suffixNormal = '...';
        final suffixDetail = detailText;

        int low = 0;
        int high = summary.length;
        int best = 0;
        while (low <= high) {
          final mid = (low + high) >> 1;
          final candidate = summary.substring(0, mid).trimRight();
          final span = TextSpan(
            children: [
              TextSpan(text: candidate, style: normalStyle),
              TextSpan(text: suffixNormal, style: normalStyle),
              TextSpan(text: suffixDetail, style: detailStyle),
            ],
          );
          final fits = !_exceedsTwoLines(
            context: context,
            maxWidth: safeWidth,
            text: span,
          );
          if (fits) {
            best = mid;
            low = mid + 1;
          } else {
            high = mid - 1;
          }
        }

        final fitted = summary.substring(0, best).trimRight();
        return GestureDetector(
          onTap: onDetailTap,
          child: RichText(
            maxLines: 2,
            overflow: TextOverflow.clip,
            text: TextSpan(
              children: [
                TextSpan(text: fitted, style: normalStyle),
                TextSpan(text: suffixNormal, style: normalStyle),
                TextSpan(text: suffixDetail, style: detailStyle),
              ],
            ),
          ),
        );
      },
    );
  }
}