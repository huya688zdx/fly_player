import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/feiniu_api.dart';
import '../l10n/generated/app_localizations.dart';
import '../media_backend/media_item_card.dart';
import '../providers/media_backend_provider.dart';
import '../providers/nas_provider.dart';
import '../services/embedded_detail_launcher.dart';
import '../theme/app_theme.dart';
import '../ui/app_motion.dart';
import '../ui/app_transitions.dart';
import '../ui/detail_artwork_resolver.dart';
import '../ui/media_episode_subtitle.dart';
import '../utils/api_url_helper.dart';
import '../utils/app_exception.dart';
import '../utils/async_action_guard.dart';
import '../widgets/common/app_error_state.dart';
import '../widgets/common/bird_loader.dart';
import '../screens/person_detail_screen.dart';
import '../screens/play_detail_screen.dart';
import 'desktop_floating_panel.dart';
import 'desktop_hover_region.dart';

/// 桌面搜索弹层（PC 专属）：搜索框从右上角按钮位置展开，结果小窗紧随其下。
///
/// 与 SearchScreen 共用同一后端搜索与历史存储（`search_history_v1::$baseUrl`），
/// 手机档仍走整页搜索，桌面档用本弹窗。数据口径与 SearchScreen 一致：
/// 后端一次返回混合结果，分类页签只做本地过滤，不重复请求。
///
/// 结果区复用 [DesktopFloatingPanel]；弹层仍位于内容区导航器内，侧栏保持可见。
///
/// [anchor] 为应用栏搜索图标本体的 [LayerLink]（`CompositedTransformTarget`）：
/// 提供时搜索框右缘钉在图标右缘、垂直居中对齐——展开动效读作「图标本体向左
/// 衍生」；为空（Ctrl+K 直开）时回退到右上角固定位置。
Future<void> showDesktopSearch(BuildContext context, {LayerLink? anchor}) {
  return Navigator.of(
    context,
  ).push<void>(_DesktopSearchRoute(navigationContext: context, anchor: anchor));
}

/// 保留路由级焦点与 Esc 返回，但遮罩不参与命中，让弹窗外的滚轮继续交给首页。
class _DesktopSearchRoute extends PopupRoute<void> {
  _DesktopSearchRoute({required this.navigationContext, this.anchor});

  final BuildContext navigationContext;

  /// 图标锚点；见 [showDesktopSearch]。
  final LayerLink? anchor;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => 'desktop-search-overlay';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 280);

  @override
  Widget buildModalBarrier() => const IgnorePointer(child: SizedBox.expand());

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Focus(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: SafeArea(
        child: anchor != null
            ? CompositedTransformFollower(
                link: anchor!,
                targetAnchor: Alignment.centerRight,
                followerAnchor: Alignment.centerRight,
                showWhenUnlinked: false,
                child: TapRegion(
                  onTapOutside: (_) => Navigator.of(context).pop(),
                  child: _DesktopSearchPanel(
                    navigationContext: navigationContext,
                  ),
                ),
              )
            : Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(48, 8, 66, 24),
                  child: TapRegion(
                    onTapOutside: (_) => Navigator.of(context).pop(),
                    child: _DesktopSearchPanel(
                      navigationContext: navigationContext,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final sizeCurve = CurvedAnimation(
      parent: animation,
      curve: AppMotion.sheetEnterCurve,
      reverseCurve: AppMotion.sheetExitCurve,
    );
    final fadeCurve = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    // 右缘锚定的宽度展开：右边缘钉在搜索图标处、左缘向左衍生；
    // 退出按原路向右收缩回图标，内容随展开/收缩快速淡入淡出。
    return SizeTransition(
      axis: Axis.horizontal,
      axisAlignment: 1,
      sizeFactor: sizeCurve,
      child: FadeTransition(opacity: fadeCurve, child: child),
    );
  }
}

/// 打开搜索结果条目详情（人物 → 人物页，其余 → 详情页）。
///
/// 打开顺序：分屏宿主优先（详情进右栏，[EmbeddedDetailLauncher] 与首页
/// 同链路），无宿主时回退直接推入当前导航器（内容区，侧栏常驻）。
/// [closeOverlay] 在导航前同步收起搜索层，避免随后压入的详情路由被误弹出。
Future<void> openSearchItemDetail(
  BuildContext context,
  MediaItemCard item, {
  VoidCallback? closeOverlay,
}) async {
  final isPerson = item.type.trim().toLowerCase() == 'person';
  final guid = item.id.trim();
  if (guid.isEmpty) {
    closeOverlay?.call();
    return;
  }
  await AsyncActionGuard.run<void>(
    'desktop_search_detail:$isPerson:$guid',
    settleDuration: const Duration(milliseconds: 450),
    action: () async {
      final navigator = Navigator.of(context);
      final nasProvider = context.read<NasProvider>();
      closeOverlay?.call();
      Map<String, dynamic>? initialDetail;
      if (!isPerson) {
        try {
          initialDetail = await FeiniuApi(
            nasProvider,
          ).getItemDetail(guid).timeout(const Duration(milliseconds: 240));
        } catch (_) {}
      }
      if (isPerson) {
        // 预取/等待期间弹窗可能已被 Esc 或遮罩关闭，面板失效就放弃打开。
        if (!context.mounted) return;
        if (await EmbeddedDetailLauncher.openPersonDetail(
          context: context,
          personGuid: guid,
          initialName: item.displayTitle,
        )) {
          return;
        }
        navigator.push(
          AppTransitions.leftToRightPageTurnRoute(
            PersonDetailScreen(
              personGuid: guid,
              initialName: item.displayTitle,
            ),
          ),
        );
        return;
      }
      if (!context.mounted) return;
      if (await EmbeddedDetailLauncher.openItemDetail(
        guid,
        context: context,
        initialItemDetail: initialDetail,
      )) {
        return;
      }
      navigator.push(
        AppTransitions.leftToRightPageTurnRoute(
          PlayDetailScreen(
            itemGuid: guid,
            heroTag: null,
            initialItemDetail: initialDetail,
          ),
        ),
      );
    },
  );
}

/// 结果分类页签：后端一次返回混合结果，这里按条目类型本地过滤。
enum _SearchCategory { all, movie, tv, person, other }

extension _SearchCategoryLabel on _SearchCategory {
  String label(AppLocalizations l10n) {
    return switch (this) {
      _SearchCategory.all => l10n.commonAll,
      _SearchCategory.movie => l10n.listTypeMovie,
      _SearchCategory.tv => l10n.listTypeTv,
      _SearchCategory.person => l10n.favoriteTabPeople,
      _SearchCategory.other => l10n.commonOther,
    };
  }

  bool matches(MediaItemCard item) {
    final type = item.type.trim().toLowerCase();
    return switch (this) {
      _SearchCategory.all => true,
      _SearchCategory.movie => type == 'movie',
      _SearchCategory.tv => type == 'tv' || type == 'series',
      _SearchCategory.person => type == 'person',
      _SearchCategory.other =>
        type != 'movie' && type != 'tv' && type != 'series' && type != 'person',
    };
  }
}

class _DesktopSearchPanel extends StatefulWidget {
  const _DesktopSearchPanel({required this.navigationContext});

  final BuildContext navigationContext;

  @override
  State<_DesktopSearchPanel> createState() => _DesktopSearchPanelState();
}

class _DesktopSearchPanelState extends State<_DesktopSearchPanel> {
  static const int _maxHistoryCount = 12;
  // 与 SearchScreen 同 key：桌面弹窗与手机搜索页共享历史。
  static const String _historyKeyPrefix = 'search_history_v1';

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<MediaItemCard> _results = const <MediaItemCard>[];
  List<String> _history = const <String>[];
  String _query = '';
  String _searchedQuery = '';
  _SearchCategory _category = _SearchCategory.all;
  bool _isSearching = false;
  AppException? _error;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
    unawaited(_loadHistory());
  }

  void _handleFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _historyKey() {
    final baseUrl = context.read<NasProvider>().baseUrl;
    return '$_historyKeyPrefix::$baseUrl';
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_historyKey()) ?? const <String>[];
    if (!mounted) return;
    setState(() {
      _history = values;
    });
  }

  Future<void> _saveHistoryEntry(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final nextHistory = <String>[
      trimmed,
      ..._history.where((entry) => entry != trimmed),
    ];
    if (nextHistory.length > _maxHistoryCount) {
      nextHistory.removeRange(_maxHistoryCount, nextHistory.length);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey(), nextHistory);
    if (!mounted) return;
    setState(() {
      _history = nextHistory;
    });
  }

  void _onQueryChanged(String value) {
    final trimmed = value.trim();
    setState(() {
      _query = value;
      _error = null;
      if (trimmed.isEmpty) {
        _isSearching = false;
        _results = const <MediaItemCard>[];
        _searchedQuery = '';
      }
    });
    if (trimmed.isEmpty) return;
    unawaited(_performSearch(trimmed));
  }

  Future<void> _performSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || !mounted) return;
    if (_isSearching && _searchedQuery == trimmed) return;
    setState(() {
      _isSearching = true;
      _searchedQuery = trimmed;
      _error = null;
    });
    try {
      final results = await context
          .read<MediaBackendProvider>()
          .backend
          .searchItems(trimmed);
      if (!mounted || trimmed != _controller.text.trim()) return;
      setState(() {
        _results = results;
        _searchedQuery = trimmed;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted || trimmed != _controller.text.trim()) return;
      setState(() {
        _error = AppException.from(
          e,
          action: 'search',
          fallbackKind: AppExceptionKind.transient,
        );
        _isSearching = false;
      });
    }
  }

  List<MediaItemCard> get _visibleResults =>
      _results.where(_category.matches).toList(growable: false);

  /// Enter：打开当前分类下的首个结果；无结果时立即补一次搜索。
  void _submitActive(String value) {
    final trimmed = value.trim();
    final visible = _visibleResults;
    if (_searchedQuery != trimmed || visible.isEmpty) {
      unawaited(_performSearch(trimmed));
      return;
    }
    _selectResult(visible.first);
  }

  void _selectResult(MediaItemCard item) {
    unawaited(_saveHistoryEntry(_controller.text));
    final dialogNavigator = Navigator.of(context);
    unawaited(
      openSearchItemDetail(
        widget.navigationContext,
        item,
        closeOverlay: dialogNavigator.pop,
      ),
    );
  }

  String _yearFromDate(String date) {
    return date.length >= 4 ? date.substring(0, 4) : '';
  }

  bool _isPersonItem(MediaItemCard item) {
    return item.type.trim().toLowerCase() == 'person';
  }

  /// 结果行副标题：剧集 → 集/季描述；人物 → 作品数；其余 → 季数/年份区间。
  /// 与 SearchScreen._cardSubtitle 同口径。
  String _rowSubtitle(MediaItemCard item) {
    final l10n = AppLocalizations.of(context);
    if (_isPersonItem(item)) {
      final count = item.numberOfItem;
      return count > 0 ? l10n.personItemCount(count) : l10n.commonEmpty;
    }
    if (item.type.trim().toLowerCase() == 'episode') {
      return mediaEpisodeSubtitle(
        l10n,
        item.seasonNumber,
        item.episodeNumber,
        item.title,
      );
    }
    final start = item.firstAirDate.isNotEmpty
        ? item.firstAirDate
        : item.releaseDate;
    final startYear = _yearFromDate(start);
    final endYear = item.lastAirDate.length >= 4
        ? item.lastAirDate.substring(0, 4)
        : '';
    final period =
        (startYear.isNotEmpty && endYear.isNotEmpty && endYear != startYear)
        ? '$startYear-$endYear'
        : startYear;
    final seasonCount = item.localNumberOfSeasons > 0
        ? item.localNumberOfSeasons
        : item.numberOfSeasons;
    final episodeCount = item.localNumberOfEpisodes > 0
        ? item.localNumberOfEpisodes
        : item.numberOfEpisodes;
    if (seasonCount == 1 && episodeCount > 0) {
      final epText = l10n.detailEpisodeTotal(episodeCount);
      return period.isEmpty ? epText : '$epText \u00b7 $period';
    }
    if (seasonCount > 0) {
      final seasonText = l10n.detailTvSeasonCount(seasonCount);
      return period.isEmpty ? seasonText : '$seasonText \u00b7 $period';
    }
    return period;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.appColors;
    final provider = context.read<NasProvider>();
    final imageCredentials = mediaImageCredentialsForBackend(
      backendKind: context
          .read<MediaBackendProvider>()
          .backend
          .capabilities
          .kind,
      token: provider.token,
      accessCode: provider.accessCode,
      baseUrl: provider.baseUrl,
    );
    final size = MediaQuery.sizeOf(context);
    final panelWidth = (size.width * 0.42).clamp(360.0, 520.0).toDouble();
    final panelHeight = (size.height * 0.68).clamp(320.0, 620.0).toDouble();
    final hasQuery = _query.trim().isNotEmpty;
    final showResults = hasQuery;

    return SizedBox(
      width: panelWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildSearchField(colors, l10n),
          AnimatedSize(
            duration: const Duration(milliseconds: 190),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: showResults
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: SizedBox(
                      height: panelHeight,
                      child: DesktopFloatingPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _buildCategoryTabs(colors, l10n),
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: colors.borderSubtle,
                            ),
                            Expanded(
                              child: _buildContent(
                                provider: provider,
                                credentials: imageCredentials,
                                colors: colors,
                                l10n: l10n,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(AppThemeColors colors, AppLocalizations l10n) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final focused = _focusNode.hasFocus;
    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            height: 48,
            decoration: BoxDecoration(
              color: isLight
                  ? Colors.white.withValues(alpha: 0.72)
                  : colors.surface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: focused
                    ? colors.accent.withValues(alpha: isLight ? 0.55 : 0.62)
                    : isLight
                    ? colors.borderStrong.withValues(alpha: 0.65)
                    : colors.borderSubtle,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: focused
                      ? colors.accent.withValues(alpha: isLight ? 0.18 : 0.26)
                      : isLight
                      ? colors.overlayScrim.withValues(alpha: 0.10)
                      : const Color(0x33000000),
                  blurRadius: focused ? 24 : 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: <Widget>[
                const SizedBox(width: 18),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: true,
                    onChanged: _onQueryChanged,
                    onSubmitted: _submitActive,
                    style: TextStyle(color: colors.textPrimary, fontSize: 16),
                    cursorColor: colors.textPrimary,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: l10n.searchPlaceholder,
                      hintStyle: TextStyle(
                        color: colors.textMuted,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 140),
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: _controller.text.isEmpty
                      ? const SizedBox.shrink(key: ValueKey<String>('empty'))
                      : IconButton(
                          key: const ValueKey<String>('clear'),
                          tooltip: l10n.commonDelete,
                          onPressed: () {
                            _controller.clear();
                            _onQueryChanged('');
                            _focusNode.requestFocus();
                          },
                          icon: Icon(
                            Icons.cancel_rounded,
                            color: colors.textMuted,
                            size: 22,
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                // 放大镜在输入框右端：与被锚定的应用栏图标本体位置重合，
                // 展开动效读作「图标自身向左衍生」而非另起一个搜索框。
                Icon(
                  Icons.search_rounded,
                  color: focused ? colors.accent : colors.textSecondary,
                  size: 25,
                ),
                const SizedBox(width: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryTabs(AppThemeColors colors, AppLocalizations l10n) {
    return SizedBox(
      height: 50,
      child: Row(
        children: <Widget>[
          for (final category in _SearchCategory.values)
            Expanded(
              child: _CategoryTab(
                label: category.label(l10n),
                selected: _category == category,
                accentColor: colors.accent,
                idleColor: colors.textSecondary,
                onTap: () {
                  if (_category == category) return;
                  setState(() => _category = category);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent({
    required NasProvider provider,
    required MediaImageCredentials credentials,
    required AppThemeColors colors,
    required AppLocalizations l10n,
  }) {
    if (_isSearching && _results.isEmpty) {
      return const Center(child: BirdLoader(size: 64));
    }
    if (_error != null) {
      return AppErrorState(
        error: _error!,
        localeMap: const <String, dynamic>{},
        onRetry: () => _performSearch(_controller.text),
      );
    }
    final visible = _visibleResults;
    if (visible.isEmpty) {
      return Center(
        child: Text(
          l10n.commonEmpty,
          style: TextStyle(color: colors.textMuted, fontSize: 14),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final item = visible[index];
        return _SearchResultRow(
          key: ValueKey<String>('${_category.name}:${item.type}:${item.id}'),
          item: item,
          credentials: credentials,
          baseUrl: provider.baseUrl,
          subtitle: _rowSubtitle(item),
          onTap: () => _selectResult(item),
        );
      },
    );
  }
}

/// 分类页签：文字 + 选中态底部短横线，淡入过渡。
class _CategoryTab extends StatelessWidget {
  const _CategoryTab({
    required this.label,
    required this.selected,
    required this.accentColor,
    required this.idleColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accentColor;
  final Color idleColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return DesktopHoverRegion(
      onTap: onTap,
      builder: (context, hovering) {
        final foreground = selected
            ? accentColor
            : hovering
            ? colors.textPrimary
            : idleColor;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 150),
                style: TextStyle(
                  color: foreground,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
                child: Text(label, textScaler: TextScaler.noScaling),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                height: 2.5,
                width: selected ? 18 : 0,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 结果行：缩略图 + 标题 + 评分 + 年份/季数/类型元信息，悬停/按下高亮。
class _SearchResultRow extends StatelessWidget {
  const _SearchResultRow({
    super.key,
    required this.item,
    required this.credentials,
    required this.baseUrl,
    required this.subtitle,
    required this.onTap,
  });

  final MediaItemCard item;
  final MediaImageCredentials credentials;
  final String baseUrl;
  final String subtitle;
  final VoidCallback onTap;

  bool get _isPerson => item.type.trim().toLowerCase() == 'person';

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final l10n = AppLocalizations.of(context);
    final rating = double.tryParse(item.rating);
    final images = mediaImageRequestForUrls(
      ApiUrlHelper.imageCandidates(baseUrl, item.primaryImage.url, width: 160),
      token: credentials.token,
      accessCode: credentials.accessCode,
      baseUrl: credentials.baseUrl,
    );
    final metaParts = <String>[
      if (subtitle.isNotEmpty) subtitle,
      if (!_isPerson && item.genres.isNotEmpty) item.genres.join(' '),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: DesktopHoverRegion(
        onTap: onTap,
        builder: (context, hovering) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: hovering
                  ? isLight
                        ? colors.selectionSoft
                        : colors.surface
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: <Widget>[
                _Thumbnail(
                  images: images,
                  isPerson: _isPerson,
                  fallbackColor: colors.surfaceSubtle,
                  fallbackIconColor: colors.textMuted,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        item.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (rating != null) ...<Widget>[
                        const SizedBox(height: 3),
                        Text(
                          l10n.detailRatingScore(rating.toStringAsFixed(1)),
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            color: colors.warning,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (metaParts.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 3),
                        Text(
                          metaParts.join(' / '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: colors.textMuted,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 行首缩略图：人物与影片/剧集统一使用海报规格；加载前/失败垫底色。
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.images,
    required this.isPerson,
    required this.fallbackColor,
    required this.fallbackIconColor,
  });

  final MediaImageRequest images;
  final bool isPerson;
  final Color fallbackColor;
  final Color fallbackIconColor;

  @override
  Widget build(BuildContext context) {
    const size = Size(54, 72);
    final radius = BorderRadius.circular(8);
    final url = images.urls.isNotEmpty ? images.urls.first : '';
    return ClipRRect(
      borderRadius: radius,
      child: ColoredBox(
        color: fallbackColor,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: url.isEmpty
              ? Center(
                  child: Icon(
                    isPerson ? Icons.person_rounded : Icons.movie_outlined,
                    size: 22,
                    color: fallbackIconColor,
                  ),
                )
              : Image.network(
                  url,
                  headers: images.headers,
                  fit: BoxFit.cover,
                  // 海报取上部保主体；人物头像居中裁切，避免切掉下颌。
                  alignment: isPerson ? Alignment.center : Alignment.topCenter,
                  cacheWidth: 160,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => Center(
                    child: Icon(
                      isPerson ? Icons.person_rounded : Icons.movie_outlined,
                      size: 22,
                      color: fallbackIconColor,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
