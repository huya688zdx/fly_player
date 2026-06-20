import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../controllers/media_item_action_sheet_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/media_library_item.dart';
import '../models/person_detail_profile.dart';
import '../pages/long_text_overlay_page.dart';
import '../providers/app_theme_provider.dart';
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
import '../utils/app_localization_lookup.dart';
import '../utils/app_exception.dart';
import '../utils/imdb_launcher.dart';
import '../utils/nas_image_headers.dart';
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

  String _t(
    String path,
    String fallback, {
    Map<String, Object?> params = const <String, Object?>{},
  }) {
    return AppLocalizationLookup.text(
      AppLocalizations.of(context),
      path,
      fallback: fallback,
      params: params,
    );
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
    } catch (_) {
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
      await FeiniuApi(
        context.read<NasProvider>(),
      ).setFavorite(person.guid, favorite: target);
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
          isFavorite: target,
        );
      });
    } catch (_) {
      // Ignore favorite failure to keep UX smooth.
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
    await const MediaItemActionSheetController().show(
      context,
      item: item,
      title: MediaItemActionSheetController.defaultTitle(item),
      localeMap: _localeMap,
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
    final jobText = _t('common.person.job.$key', _jobFallback[key] ?? rawJob);
    return _t(
      'common.person.asJob',
      '\u4f5c\u4e3a{job}',
      params: {'job': jobText},
    );
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
    } catch (_) {}
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

  Widget _buildProfileImage(List<String> urls, String token) {
    return _PersonProfileImage(
      urls: urls,
      token: token,
      fallback: Container(
        color: context.appColors.surfaceStrong,
        alignment: Alignment.center,
        child: Icon(Icons.person, color: context.appColors.textMuted, size: 42),
      ),
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
    final dynamicThemeUrls =
        _person == null || _person!.profilePath.trim().isEmpty
        ? const <String>[]
        : _imageCandidates(provider.baseUrl, _person!.profilePath, width: 240);
    final syncGlobalTheme = dynamicThemeIntensity.allowsGlobalRuntimeThemeSync(
      inPlayerPaneHost: inPlayerPaneHost,
      isPane: _isPane,
    );

    return DynamicPageThemeScope(
      pageKey: widget.personGuid,
      imageUrl: dynamicThemeUrls.isNotEmpty ? dynamicThemeUrls.first : '',
      token: provider.token,
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
        final title = person?.displayName ?? widget.initialName;
        final body = _isLoading
            ? Center(child: CircularProgressIndicator(color: colors.accent))
            : _isNoDataError(_error) || person == null
            ? AppErrorState(
                error: const AppException(
                  kind: AppExceptionKind.noData,
                  action: 'person detail',
                  message: 'No data',
                ),
                localeMap: _localeMap,
              )
            : _error != null
            ? AppErrorState(
                error: _error!,
                localeMap: _localeMap,
                onRetry: _loadData,
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
                                _imageCandidates(
                                  provider.baseUrl,
                                  person.profilePath,
                                  width: 260,
                                ),
                                provider.token,
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
                              urls: _imageCandidates(
                                provider.baseUrl,
                                item.poster,
                                width: layout.homePosterRequestWidth,
                              ),
                              token: provider.token,
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

  Widget _buildBiographyPreview(PersonDetailProfile person) {
    final bio = person.biography.trim();
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
      return Text(_t('common.other.none', '\u65e0'), style: bodyStyle);
    }

    final moreText = _t('layout.details.castAndCrew.showMore', '\u66f4\u591a');
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
              TextSpan(
                text: moreText,
                style: moreStyle,
                recognizer: TapGestureRecognizer()
                  ..onTap = () => LongTextOverlayPage.show(
                    context,
                    title: person.displayName,
                    sectionTitle: _t(
                      'layout.details.castAndCrew.biography',
                      '\u6f14\u5458\u7b80\u4ecb',
                    ),
                    content: person.biography,
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
  final List<String> urls;
  final String token;
  final Widget fallback;

  const _PersonProfileImage({
    required this.urls,
    required this.token,
    required this.fallback,
  });

  @override
  State<_PersonProfileImage> createState() => _PersonProfileImageState();
}

class _PersonProfileImageState extends State<_PersonProfileImage> {
  int _index = 0;

  @override
  void didUpdateWidget(covariant _PersonProfileImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final urlsChanged = !listEquals(oldWidget.urls, widget.urls);
    final tokenChanged = oldWidget.token != widget.token;
    if (urlsChanged || tokenChanged) {
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.of(context).devicePixelRatio.clamp(1.0, 1.8);
        final cacheWidth = constraints.maxWidth.isFinite
            ? (constraints.maxWidth * dpr).round().clamp(160, 280)
            : 240;
        final cacheHeight = constraints.maxHeight.isFinite
            ? (constraints.maxHeight * dpr).round().clamp(220, 400)
            : 340;
        final currentUrl = widget.urls[_index];
        return Image.network(
          currentUrl,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
          cacheWidth: cacheWidth,
          cacheHeight: cacheHeight,
          headers: nasImageHeaders(widget.token, url: currentUrl),
          errorBuilder: (_, error, ___) {
            if (_index + 1 < widget.urls.length) {
              final nextUrl = widget.urls[_index + 1];
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
