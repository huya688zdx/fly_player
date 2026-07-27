import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../controllers/media_item_action_sheet_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../media_backend/action/media_library_item_action_target.dart';
import '../media_backend/detail/media_detail.dart';
import '../media_backend/media_backend.dart';
import '../media_backend/media_backend_kind.dart';
import '../media_backend/media_image_ref.dart';
import '../media_backend/media_item_card.dart';
import '../models/media_library_item.dart';
import '../models/person_detail_profile.dart';
import '../pages/long_text_overlay_page.dart';
import '../providers/app_theme_provider.dart';
import '../providers/backend_session_provider.dart';
import '../providers/media_backend_provider.dart';
import '../providers/nas_provider.dart';
import '../services/detail_runtime_cache.dart';
import '../services/embedded_detail_launcher.dart';
import '../theme/app_theme.dart';
import '../theme/detail_tokens.dart';
import '../ui/adaptive_detail_navigator.dart';
import '../ui/detail_presentation.dart';
import '../ui/layout_adaptive.dart';
import '../ui/media_poster_card.dart';
import '../ui/player_pane_host_scope.dart';
import '../utils/api_url_helper.dart';
import '../utils/app_exception.dart';
import '../utils/imdb_launcher.dart';
import '../ui/detail_artwork_resolver.dart';
import '../utils/swallowed_error_logger.dart';
import '../widgets/common/app_error_state.dart';
import '../widgets/detail/detail_header.dart';
import '../widgets/detail/detail_more_actions_sheet.dart';
import '../widgets/detail/dynamic_page_theme_scope.dart';
import '../widgets/detail/link_section.dart';
import '../widgets/detail/theme_save_name_helper.dart';

class PersonDetailScreen extends StatefulWidget {
  final String personGuid;
  final String initialName;
  final Map<String, dynamic> initialLocaleMap;
  final DetailPresentation presentation;

  const PersonDetailScreen({
    super.key,
    required this.personGuid,
    this.initialName = '',
    this.initialLocaleMap = const <String, dynamic>{},
    this.presentation = DetailPresentation.page,
  });

  @override
  State<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends State<PersonDetailScreen> {
  static const List<String> _jobs = <String>[
    'Actor',
    'Director',
    'Screenplay',
    'Producer',
  ];
  static const int _initialJobPrefetchCount = 2;
  static const double _jobLoadMoreTriggerOffset = 420;

  static const Map<String, String> _jobFallback = <String, String>{
    'actor': '\u6f14\u5458',
    'director': '\u5bfc\u6f14',
    'screenplay': '\u7f16\u5267',
    'writer': '\u7f16\u5267',
    'producer': '\u5236\u7247\u4eba',
  };

  PersonDetailProfile? _person;
  Map<String, ItemListPage> _jobPages = <String, ItemListPage>{};

  /// 中立展示态（非飞牛后端，如 Emby）：人物本身复用 [MediaBackend.getItemDetail]（姓名 /
  /// 简介 / 照片），作品走 [MediaBackend.getPersonItems]。飞牛态恒 false、原路径整段不变。
  bool _neutralDisplayOnly = false;
  MediaDetail? _neutralDetail;
  List<MediaItemCard> _neutralWorks = const <MediaItemCard>[];

  Map<String, dynamic> _localeMap = <String, dynamic>{};
  bool _isLoading = true;
  bool _favoriteUpdating = false;
  AppException? _error;
  int _jobLoadVersion = 0;
  int _nextJobIndex = 0;
  bool _jobLoading = false;
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _scrollOffsetNotifier = ValueNotifier<double>(0);

  bool get _isPane => widget.presentation == DetailPresentation.pane;
  bool get _useRuntimeCache => _isPane;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _localeMap = Map<String, dynamic>.from(widget.initialLocaleMap);
    _loadData();
  }

  @override
  void dispose() {
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
    unawaited(_loadMoreJobsIfNeeded());
  }

  String _year(MediaLibraryItem item) {
    final date = item.releaseDate.isNotEmpty
        ? item.releaseDate
        : item.firstAirDate;
    return date.length >= 4 ? date.substring(0, 4) : '';
  }

  bool _isNoDataError(AppException? error) {
    return error?.kind == AppExceptionKind.noData;
  }

  bool _isEpisodeItem(MediaLibraryItem item) {
    return item.type.trim().toLowerCase() == 'episode';
  }

  PersonDetailProfile _fallbackPersonProfile() {
    return PersonDetailProfile(
      guid: widget.personGuid,
      name: widget.initialName.trim(),
      originalName: '',
      profilePath: '',
      imdbId: '',
      trimId: '',
      biography: '',
      isFavorite: false,
    );
  }

  Future<void> _loadData() async {
    if (widget.personGuid.trim().isEmpty) {
      setState(() {
        _isLoading = false;
        _error = const AppException(
          kind: AppExceptionKind.noData,
          action: 'person detail',
          message: 'Invalid person guid',
        );
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _jobPages = <String, ItemListPage>{};
      _nextJobIndex = 0;
      _jobLoading = false;
    });

    // 分屏副引擎冷启动时后端会话可能未就绪，先等就绪再读后端（同 play_detail）。
    final session = context.read<BackendSessionProvider>();
    try {
      await session.ensureReady();
    } on BackendSessionUnavailableException catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _error = AppException.from(
          error,
          action: 'person detail',
          fallbackKind: AppExceptionKind.transient,
          stackTrace: stackTrace,
        );
        _isLoading = false;
      });
      return;
    }
    if (!mounted) return;

    // 非飞牛后端（Emby）：走中立路径（getItemDetail 取人物 + getPersonItems 取作品），
    // 不进飞牛的按职务分页路径。数据/导航层按 backend 能力分支，UI 渲染不写 if(isEmby)。
    final backend = context.read<MediaBackendProvider>().backend;
    if (backend.capabilities.kind != MediaBackendKind.feiniu) {
      await _loadNeutral(backend);
      return;
    }

    final api = FeiniuApi(context.read<NasProvider>());
    final loadVersion = ++_jobLoadVersion;
    final localeFuture = Future.value(_localeMap);
    try {
      final personFuture = _loadPersonDetail(api, widget.personGuid);

      final locale = await localeFuture;
      final person = await personFuture;
      if (!mounted || loadVersion != _jobLoadVersion) return;

      setState(() {
        _localeMap = locale;
        _person = person;
        _jobPages = <String, ItemListPage>{};
        _nextJobIndex = 0;
        _jobLoading = false;
        _isLoading = false;
      });
      unawaited(_loadInitialJobs(api, loadVersion));
    } catch (e) {
      final appError = AppException.from(
        e,
        action: 'person detail',
        fallbackKind: AppExceptionKind.transient,
      );
      final locale = await localeFuture.catchError(
        (_) => Map<String, dynamic>.from(_localeMap),
      );
      if (!mounted) return;
      if (appError.isNoData) {
        setState(() {
          _localeMap = locale;
          _person = _fallbackPersonProfile();
          _jobPages = <String, ItemListPage>{};
          _nextJobIndex = 0;
          _jobLoading = false;
          _isLoading = false;
          _error = null;
        });
        return;
      }
      setState(() {
        _localeMap = locale;
        _isLoading = false;
        _error = appError;
      });
    }
  }

  /// Emby 等公共后端的人物详情加载：并行取人物详情（姓名/简介/照片/外部 ID）+ 作品列表。
  Future<void> _loadNeutral(MediaBackend backend) async {
    _neutralDisplayOnly = true;
    try {
      final results = await Future.wait(<Future<Object>>[
        backend.getItemDetail(widget.personGuid),
        backend.getPersonItems(widget.personGuid),
      ]);
      if (!mounted) return;
      setState(() {
        _neutralDetail = results[0] as MediaDetail;
        _neutralWorks = results[1] as List<MediaItemCard>;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppException.from(
          e,
          action: 'person detail',
          fallbackKind: AppExceptionKind.transient,
        );
        _isLoading = false;
      });
    }
  }

  Future<void> _loadInitialJobs(FeiniuApi api, int loadVersion) async {
    for (var index = 0; index < _initialJobPrefetchCount; index += 1) {
      final loaded = await _loadNextPendingJob(api, loadVersion);
      if (!loaded) break;
    }
    _scheduleMoreJobsIfViewportNotFilled();
  }

  Future<void> _loadMoreJobsIfNeeded({bool force = false}) async {
    if (_jobLoading ||
        _isLoading ||
        _error != null ||
        _person == null ||
        _nextJobIndex >= _jobs.length) {
      return;
    }
    if (!force) {
      if (!_scrollController.hasClients) return;
      final remaining =
          _scrollController.position.maxScrollExtent - _scrollController.offset;
      if (remaining > _jobLoadMoreTriggerOffset) return;
    }
    await _loadNextPendingJob(
      FeiniuApi(context.read<NasProvider>()),
      _jobLoadVersion,
    );
    _scheduleMoreJobsIfViewportNotFilled();
  }

  Future<bool> _loadNextPendingJob(FeiniuApi api, int loadVersion) async {
    if (_jobLoading ||
        !mounted ||
        loadVersion != _jobLoadVersion ||
        _nextJobIndex >= _jobs.length) {
      return false;
    }
    final job = _jobs[_nextJobIndex];
    _jobLoading = true;
    _nextJobIndex += 1;
    try {
      final page = await _loadPersonJobPage(api, widget.personGuid, job);
      if (!mounted || loadVersion != _jobLoadVersion) return false;
      setState(() {
        _jobPages[job] = page;
      });
      return true;
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'load person job page',
        id: widget.personGuid,
        error: error,
        stackTrace: stackTrace,
        source: 'person_detail_screen',
        details: 'job=$job',
      );
      if (!mounted || loadVersion != _jobLoadVersion) return false;
      setState(() {
        _jobPages[job] = const ItemListPage(
          total: 0,
          items: <MediaLibraryItem>[],
        );
      });
      return true;
    } finally {
      _jobLoading = false;
    }
  }

  void _scheduleMoreJobsIfViewportNotFilled() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _jobLoading || _nextJobIndex >= _jobs.length) return;
      if (!_scrollController.hasClients) {
        unawaited(_loadMoreJobsIfNeeded(force: true));
        return;
      }
      if (_scrollController.position.maxScrollExtent <= 0) {
        unawaited(_loadMoreJobsIfNeeded(force: true));
      }
    });
  }

  Future<void> _toggleFavorite() async {
    final person = _person;
    if (person == null || _favoriteUpdating) return;
    setState(() => _favoriteUpdating = true);
    final target = !person.isFavorite;
    try {
      // 统一走中立后端：飞牛→FeiniuApi.setFavorite、Emby→FavoriteItems/{personId}。
      final backend = context.read<MediaBackendProvider>().backend;
      final state = await backend.setItemFavorite(
        person.guid,
        favorite: target,
      );
      if (!mounted) return;
      setState(() {
        _person = PersonDetailProfile(
          guid: person.guid,
          name: person.name,
          originalName: person.originalName,
          profilePath: person.profilePath,
          imdbId: person.imdbId,
          trimId: person.trimId,
          biography: person.biography,
          isFavorite: state,
        );
      });
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'toggle person favorite',
        id: person.guid,
        error: error,
        stackTrace: stackTrace,
        source: 'person_detail_screen',
      );
    } finally {
      if (mounted) {
        setState(() => _favoriteUpdating = false);
      }
    }
  }

  void _replaceWorkItemLocally(
    String itemGuid,
    MediaLibraryItem Function(MediaLibraryItem item) transform,
  ) {
    if (!mounted) return;
    setState(() {
      _jobPages = _jobPages.map((job, page) {
        final updatedItems = page.items
            .map((item) => item.guid == itemGuid ? transform(item) : item)
            .toList(growable: false);
        return MapEntry(
          job,
          ItemListPage(total: page.total, items: updatedItems),
        );
      });
    });
  }

  Future<void> _showWorkItemActions(MediaLibraryItem item) async {
    final l10n = AppLocalizations.of(context);
    final target = item.toActionTarget();
    await const MediaItemActionSheetController().show(
      context,
      target: target,
      title: MediaItemActionSheetController.defaultTitle(l10n, target),
      favoriteOnly: false,
      initialWatched: item.watched == 1,
      onChanged: (state) {
        _replaceWorkItemLocally(
          item.guid,
          (current) => current.copyWith(watched: state.watched ? 1 : 0),
        );
      },
    );
  }

  Future<PersonDetailProfile> _loadPersonDetail(
    FeiniuApi api,
    String personGuid,
  ) {
    if (!_useRuntimeCache) {
      return api.getPersonDetail(personGuid);
    }
    return DetailRuntimeCache.instance.getOrLoad<PersonDetailProfile>(
      bucket: 'person_detail',
      key: personGuid,
      loader: () => api.getPersonDetail(personGuid),
    );
  }

  Future<ItemListPage> _loadPersonJobPage(
    FeiniuApi api,
    String personGuid,
    String job,
  ) {
    if (!_useRuntimeCache) {
      return api.getPersonItemList(
        personGuid: personGuid,
        job: job,
        page: 1,
        pageSize: 200,
        sortColumn: 'update_time',
        sortType: 'desc',
      );
    }
    return DetailRuntimeCache.instance.getOrLoad<ItemListPage>(
      bucket: 'person_job_page',
      key: '$personGuid::$job',
      loader: () => api.getPersonItemList(
        personGuid: personGuid,
        job: job,
        page: 1,
        pageSize: 200,
        sortColumn: 'update_time',
        sortType: 'desc',
      ),
    );
  }

  String _jobTitle(String rawJob) {
    final key = rawJob.toLowerCase();
    final l10n = AppLocalizations.of(context);
    final jobText = switch (key) {
      'actor' => l10n.personJobActor,
      'director' => l10n.personJobDirector,
      'screenplay' => l10n.personJobScreenplay,
      'writer' => l10n.personJobWriter,
      'producer' => l10n.personJobProducer,
      _ => _jobFallback[key] ?? rawJob,
    };
    return l10n.personAsJob(jobText);
  }

  List<String> _imageCandidates(
    String baseUrl,
    String rawPath, {
    int width = 480,
  }) {
    return ApiUrlHelper.personImageCandidates(baseUrl, rawPath, width: width);
  }

  Future<void> _openImdb() async {
    final imdbId = _person?.imdbId ?? '';
    final result = await ImdbLauncher.openPersonExternal(imdbId);
    if (!mounted || result == ImdbLaunchResult.success) return;
    final l10n = AppLocalizations.of(context);
    final text = result == ImdbLaunchResult.empty
        ? l10n.detailImdbEmpty
        : l10n.detailImdbOpenFailed;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _openTmdb() async {
    final trimId = _person?.trimId ?? '';
    final result = await ImdbLauncher.openTmdbExternal(trimId);
    if (!mounted || result == ImdbLaunchResult.success) return;
    final l10n = AppLocalizations.of(context);
    final text = result == ImdbLaunchResult.empty
        ? l10n.detailTmdbEmpty
        : l10n.detailTmdbOpenFailed;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _openItemDetail(MediaLibraryItem item) async {
    if (item.guid.trim().isEmpty) return;
    final provider = context.read<NasProvider>();
    Map<String, dynamic>? initialDetail;
    try {
      initialDetail = await FeiniuApi(
        provider,
      ).getItemDetail(item.guid).timeout(const Duration(milliseconds: 240));
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'prefetch person item detail',
        id: item.guid,
        error: error,
        stackTrace: stackTrace,
        source: 'person_detail_screen',
      );
    }
    if (!mounted) return;
    AdaptiveDetailNavigator.open<void>(
      context,
      AdaptiveDetailRequest.item(
        itemGuid: item.guid,
        initialItemDetail: initialDetail,
      ),
      presentation: _isPane ? DetailPresentation.pane : DetailPresentation.page,
    );
  }

  Widget _buildProfileImage(MediaImageRequest images) {
    return _PersonProfileImage(
      images: images,
      fallback: _personPhotoFallback(),
    );
  }

  Widget _personPhotoFallback() {
    return Container(
      color: context.appColors.surfaceStrong,
      alignment: Alignment.center,
      child: Icon(Icons.person, color: context.appColors.textMuted, size: 42),
    );
  }

  /// Emby 人物照片：完整 api_key 直链（自鉴权），失败回退人物图标。
  /// F-034:与飞牛照片共用 [_PersonProfileImage],鉴权语义统一进请求对象。
  Widget _buildNeutralProfileImage(String url) {
    if (url.trim().isEmpty) return _personPhotoFallback();
    return _buildProfileImage(
      mediaImageRequestForUrls(<String>[url.trim()], token: ''),
    );
  }

  String _yearFromCard(MediaItemCard item) {
    final date = item.releaseDate.isNotEmpty
        ? item.releaseDate
        : item.firstAirDate;
    return date.length >= 4 ? date.substring(0, 4) : '';
  }

  void _openNeutralWork(MediaItemCard item) {
    if (item.id.trim().isEmpty) return;
    AdaptiveDetailNavigator.open<void>(
      context,
      AdaptiveDetailRequest.item(
        itemGuid: item.id,
        // Emby 直链引用：push 前预取详情 hero（背景图优先、海报兜底）。
        heroImageRefs: <MediaImageRef>[
          if (item.backdropImage.isNotEmpty) item.backdropImage,
          if (item.primaryImage.isNotEmpty) item.primaryImage,
        ],
      ),
      presentation: _isPane ? DetailPresentation.pane : DetailPresentation.page,
    );
  }

  Future<void> _openNeutralImdb(String imdbId) async {
    final result = await ImdbLauncher.openPersonExternal(imdbId);
    if (!mounted || result == ImdbLaunchResult.success) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result == ImdbLaunchResult.empty
              ? l10n.detailImdbEmpty
              : l10n.detailImdbOpenFailed,
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openNeutralTmdb(String tmdbId) async {
    final result = await ImdbLauncher.openTmdbExternal(tmdbId);
    if (!mounted || result == ImdbLaunchResult.success) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result == ImdbLaunchResult.empty
              ? l10n.detailTmdbEmpty
              : l10n.detailTmdbOpenFailed,
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Emby 人物详情中立体：照片 + 姓名 + 简介 + 参与作品栅格 + 外部链接。
  /// 飞牛态不进此路径（[build] 按 [_neutralDisplayOnly] 早分流）。
  Widget _buildNeutralBody({
    required AppThemeColors colors,
    required MediaLayoutProfile layout,
    required MediaQueryData media,
    required double topContentInset,
    required double profileWidth,
    required double profileHeight,
  }) {
    final detail = _neutralDetail!;
    final name = detail.title.trim().isNotEmpty
        ? detail.title.trim()
        : widget.initialName;
    final imdbId = detail.externalIds.imdbId.trim();
    final tmdbId = detail.externalIds.tmdbId.trim();
    return CustomScrollView(
      controller: _scrollController,
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, topContentInset, 16, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: profileWidth,
                    height: profileHeight,
                    child: _buildNeutralProfileImage(detail.primaryImage.url),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        name,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          height: 1.08,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _buildBiographyPreviewRaw(name, detail.overview),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_neutralWorks.isNotEmpty) ...<Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Text(
                AppLocalizations.of(context).personWorks,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate((context, index) {
                final item = _neutralWorks[index];
                final rating = double.tryParse(item.rating);
                final isEpisode = item.type.trim().toLowerCase() == 'episode';
                return MediaPosterCard(
                  images: mediaImageRequestForUrls(
                    item.primaryImage.url.trim().isNotEmpty
                        ? <String>[item.primaryImage.url.trim()]
                        : const <String>[],
                    token: '',
                  ),
                  title: item.displayTitle,
                  subtitle: _yearFromCard(item),
                  rating: rating,
                  watched: item.watched,
                  imageHeight: layout.categoryGridImageHeight,
                  titleFontSize: layout.homePosterTitleFontSize,
                  subtitleFontSize: layout.homePosterSubtitleFontSize,
                  imageFit: isEpisode ? BoxFit.contain : BoxFit.cover,
                  onTap: () => _openNeutralWork(item),
                );
              }, childCount: _neutralWorks.length),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: layout.categoryGridColumns,
                mainAxisSpacing: layout.itemGap,
                crossAxisSpacing: layout.itemGap,
                mainAxisExtent: layout.categoryGridRowHeight,
              ),
            ),
          ),
        ],
        if (imdbId.isNotEmpty || tmdbId.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: LinkSection(
                imdbId: imdbId,
                tmdbId: tmdbId,
                onImdbTap: () => _openNeutralImdb(imdbId),
                onTmdbTap: () => _openNeutralTmdb(tmdbId),
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 18)),
      ],
    );
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
    final provider = context.read<NasProvider>();
    final inPlayerPaneHost = PlayerPaneHostScope.maybeOf(context) != null;
    // 动态取色图源:Emby 用人物 Primary 完整直链(api_key 自鉴权);飞牛用 profilePath 相对路径。
    final dynamicThemeImages = _neutralDisplayOnly
        ? mediaImageRequestForUrls(
            (_neutralDetail?.primaryImage.url.trim().isNotEmpty ?? false)
                ? <String>[_neutralDetail!.primaryImage.url.trim()]
                : const <String>[],
            token: '',
          )
        : (_person == null || _person!.profilePath.trim().isEmpty
              ? MediaImageRequest.empty
              : mediaImageRequestForUrls(
                  _imageCandidates(
                    provider.baseUrl,
                    _person!.profilePath,
                    width: 240,
                  ),
                  token: provider.token,
                ));
    final syncGlobalTheme = dynamicThemeIntensity.allowsGlobalRuntimeThemeSync(
      inPlayerPaneHost: inPlayerPaneHost,
      isPane: _isPane,
    );

    return DynamicPageThemeScope(
      pageKey: widget.personGuid,
      imageUrl: dynamicThemeImages.urls.isNotEmpty
          ? dynamicThemeImages.urls.first
          : '',
      imageHeaders: dynamicThemeImages.headers,
      enabled: dynamicThemeEnabled,
      syncGlobalTheme: syncGlobalTheme,
      deferLocalThemeApplyUntilGlobalSync: _isPane && syncGlobalTheme,
      intensity: dynamicThemeIntensity,
      builder: (context, _) {
        final colors = context.appColors;
        final layout = MediaLayoutProfile.of(context);
        final person = _person;
        final media = MediaQuery.of(context);
        final screenWidth = media.size.width;
        final profileWidth = (screenWidth * 0.34).clamp(118.0, 148.0);
        final profileHeight = profileWidth * 1.42;
        final topContentInset = media.padding.top + kToolbarHeight + 8;
        final title = _neutralDisplayOnly
            ? ((_neutralDetail?.title.trim().isNotEmpty ?? false)
                  ? _neutralDetail!.title.trim()
                  : widget.initialName)
            : (person?.displayName ?? widget.initialName);
        final body = _isLoading
            ? Center(child: CircularProgressIndicator(color: colors.accent))
            : _neutralDisplayOnly
            ? (_error != null
                  ? AppErrorState(
                      error: _error!,
                      localeMap: _localeMap,
                      onRetry: _loadData,
                    )
                  : _buildNeutralBody(
                      colors: colors,
                      layout: layout,
                      media: media,
                      topContentInset: topContentInset,
                      profileWidth: profileWidth,
                      profileHeight: profileHeight,
                    ))
            : _error != null && !_isNoDataError(_error)
            ? AppErrorState(
                error: _error!,
                localeMap: _localeMap,
                onRetry: _loadData,
              )
            : _isNoDataError(_error) || person == null
            ? AppErrorState(
                error: const AppException(
                  kind: AppExceptionKind.noData,
                  action: 'person detail',
                  message: 'No data',
                ),
                localeMap: _localeMap,
              )
            : CustomScrollView(
                controller: _scrollController,
                slivers: <Widget>[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, topContentInset, 16, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: SizedBox(
                              width: profileWidth,
                              height: profileHeight,
                              child: _buildProfileImage(
                                mediaImageRequestForUrls(
                                  _imageCandidates(
                                    provider.baseUrl,
                                    person.profilePath,
                                    width: 260,
                                  ),
                                  token: provider.token,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  person.displayName,
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 42 / 2,
                                    fontWeight: FontWeight.w700,
                                    height: 1.08,
                                  ),
                                ),
                                if (person.originalName
                                    .trim()
                                    .isNotEmpty) ...<Widget>[
                                  const SizedBox(height: 4),
                                  Text(
                                    person.originalName,
                                    style: TextStyle(
                                      color: colors.textSecondary,
                                      fontSize: 32 / 2,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                _buildBiographyPreview(person),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: SizedBox(
                                    width: 54,
                                    height: 54,
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        shape: const CircleBorder(),
                                        side: BorderSide(
                                          color: colors.borderStrong,
                                        ),
                                      ),
                                      onPressed: _favoriteUpdating
                                          ? null
                                          : _toggleFavorite,
                                      child: Icon(
                                        person.isFavorite
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        color: person.isFavorite
                                            ? colors.danger
                                            : colors.textPrimary,
                                        size: 26,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  for (final job in _jobs) ...<Widget>[
                    if ((_jobPages[job]?.items.isNotEmpty ?? false))
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                          child: Text(
                            _jobTitle(job),
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 36 / 2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    if ((_jobPages[job]?.items.isNotEmpty ?? false))
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        sliver: SliverGrid(
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final list = _jobPages[job]!.items;
                            final item = list[index];
                            final rating = double.tryParse(item.voteAverage);
                            final resolutions = item.resolutions
                                .where((e) => e.trim().isNotEmpty)
                                .toList();
                            return MediaPosterCard(
                              images: mediaImageRequestForUrls(
                                _imageCandidates(
                                  provider.baseUrl,
                                  item.poster,
                                  width: layout.homePosterRequestWidth,
                                ),
                                token: provider.token,
                              ),
                              title: item.displayTitle,
                              subtitle: _year(item),
                              rating: rating,
                              resolutions: resolutions,
                              watched: item.watched == 1,
                              imageHeight: layout.categoryGridImageHeight,
                              titleFontSize: layout.homePosterTitleFontSize,
                              subtitleFontSize:
                                  layout.homePosterSubtitleFontSize,
                              imageFit: _isEpisodeItem(item)
                                  ? BoxFit.contain
                                  : BoxFit.cover,
                              onTap: () => _openItemDetail(item),
                              onLongPress: () {
                                _showWorkItemActions(item);
                              },
                            );
                          }, childCount: _jobPages[job]!.items.length),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: layout.categoryGridColumns,
                                mainAxisSpacing: layout.itemGap,
                                crossAxisSpacing: layout.itemGap,
                                mainAxisExtent: layout.categoryGridRowHeight,
                              ),
                        ),
                      ),
                  ],
                  if (_jobLoading)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: colors.accent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (person.imdbId.trim().isNotEmpty ||
                      person.trimId.trim().isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                        child: LinkSection(
                          imdbId: person.imdbId,
                          tmdbId: person.trimId,
                          onImdbTap: _openImdb,
                          onTmdbTap: _openTmdb,
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 18)),
                ],
              );

        return Scaffold(
          backgroundColor: DetailTokens.pageBackgroundOf(context),
          body: Stack(
            children: <Widget>[
              Positioned.fill(child: body),
              ValueListenableBuilder<double>(
                valueListenable: _scrollOffsetNotifier,
                builder: (context, offset, _) {
                  final titleOpacity = ((offset - 8.0) / 64.0).clamp(0.0, 1.0);
                  return DetailFloatingTopBar(
                    onBack: () => unawaited(
                      EmbeddedDetailLauncher.closeHostOrPop(context),
                    ),
                    onMore: () => unawaited(
                      showDetailMoreActionsSheet(
                        context,
                        pageKey: widget.personGuid,
                        pageTitle: title,
                        suggestedThemeName: context
                            .read<AppThemeProvider>()
                            .nextSavedThemeNameFromBase(
                              buildThemeSaveNameBase(
                                l10n: AppLocalizations.of(context),
                                title: title,
                              ),
                            ),
                        clearRuntimeBroadcastToMain: !inPlayerPaneHost,
                      ),
                    ),
                    title: title,
                    titleOpacity: titleOpacity,
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

  Widget _buildBiographyPreview(PersonDetailProfile person) =>
      _buildBiographyPreviewRaw(person.displayName, person.biography);

  Widget _buildBiographyPreviewRaw(String displayName, String biography) {
    final bio = biography.trim();
    final colors = context.appColors;
    final bodyStyle = TextStyle(
      color: colors.textSecondary,
      fontSize: 13.5,
      height: 1.22,
      fontWeight: FontWeight.w500,
    );
    final moreStyle = TextStyle(
      color: colors.link,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.0,
    );

    if (bio.isEmpty) {
      return Text(AppLocalizations.of(context).commonNone, style: bodyStyle);
    }

    final moreText = AppLocalizations.of(context).commonDetails;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final safeWidth = math.max(0.0, maxWidth - 10);
        final painter = TextPainter(
          textDirection: TextDirection.ltr,
          maxLines: 3,
        );
        painter.text = TextSpan(text: '', style: bodyStyle);
        painter.text = TextSpan(text: bio, style: bodyStyle);
        painter.layout(maxWidth: safeWidth);
        if (!painter.didExceedMaxLines) {
          return Text(
            bio,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: bodyStyle,
          );
        }

        int low = 0;
        int high = bio.length;
        int best = 0;
        while (low <= high) {
          final mid = (low + high) >> 1;
          final head = bio.substring(0, mid).trimRight();
          painter.text = TextSpan(
            children: <InlineSpan>[
              TextSpan(text: '$head...', style: bodyStyle),
              TextSpan(text: '', style: bodyStyle),
              TextSpan(text: moreText, style: moreStyle),
            ],
          );
          painter.layout(maxWidth: safeWidth);
          if (!painter.didExceedMaxLines) {
            best = mid;
            low = mid + 1;
          } else {
            high = mid - 1;
          }
        }

        final head = bio.substring(0, math.max(best, 1)).trimRight();
        return Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(text: '$head...', style: bodyStyle),
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => LongTextOverlayPage.show(
                    context,
                    title: displayName,
                    sectionTitle: AppLocalizations.of(
                      context,
                    ).personBiographyTitle,
                    content: biography,
                  ),
                  child: Text(moreText, style: moreStyle),
                ),
              ),
            ],
          ),
          maxLines: 3,
          overflow: TextOverflow.clip,
        );
      },
    );
  }
}

class _PersonProfileImage extends StatefulWidget {
  final MediaImageRequest images;
  final Widget fallback;

  const _PersonProfileImage({required this.images, required this.fallback});

  @override
  State<_PersonProfileImage> createState() => _PersonProfileImageState();
}

class _PersonProfileImageState extends State<_PersonProfileImage> {
  int _index = 0;

  @override
  void didUpdateWidget(covariant _PersonProfileImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final urlsChanged = !listEquals(oldWidget.images.urls, widget.images.urls);
    final headersChanged = !mapEquals(
      oldWidget.images.headers,
      widget.images.headers,
    );
    if (urlsChanged || headersChanged) {
      _index = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_index >= widget.images.urls.length || !widget.images.canLoad) {
      return widget.fallback;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.of(context).devicePixelRatio.clamp(1.0, 1.8);
        final cacheWidth = constraints.maxWidth.isFinite
            ? (constraints.maxWidth * dpr).round().clamp(160, 280)
            : 240;
        final cacheHeight = constraints.maxHeight.isFinite
            ? (constraints.maxHeight * dpr).round().clamp(220, 400)
            : 340;
        final currentUrl = widget.images.urls[_index];
        return Image.network(
          currentUrl,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
          cacheWidth: cacheWidth,
          cacheHeight: cacheHeight,
          headers: widget.images.headers,
          errorBuilder: (_, error, ___) {
            if (_index + 1 < widget.images.urls.length) {
              final nextUrl = widget.images.urls[_index + 1];
              debugPrint(
                '[IMG][PERSON_PROFILE] failed url=$currentUrl error=$error -> fallback=$nextUrl',
              );
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _index += 1);
              });
              return widget.fallback;
            }
            debugPrint(
              '[IMG][PERSON_PROFILE] failed url=$currentUrl error=$error -> no_more_fallback',
            );
            return widget.fallback;
          },
        );
      },
    );
  }
}
