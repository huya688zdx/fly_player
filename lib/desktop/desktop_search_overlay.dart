import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/feiniu_api.dart';
import '../l10n/generated/app_localizations.dart';
import '../media_backend/media_item_card.dart';
import '../providers/media_backend_provider.dart';
import '../providers/nas_provider.dart';
import '../services/embedded_detail_launcher.dart';
import '../theme/app_theme.dart';
import '../ui/app_centered_modal.dart';
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
import 'desktop_hover_region.dart';

/// 桌面搜索弹窗（PC 专属）：贴顶居中的主题面板，搜索框 + 分类页签 +
/// 「全部/电影/电视剧/人物/其他」本地过滤的结果列表。
///
/// 与 SearchScreen 共用同一后端搜索与历史存储（`search_history_v1::$baseUrl`），
/// 手机档仍走整页搜索，桌面档用本弹窗。数据口径与 SearchScreen 一致：
/// 后端一次返回混合结果，分类页签只做本地过滤，不重复请求。
///
/// 弹出在 [context] 所在导航器上（壳层内即内容区导航，侧栏保持可见）。
/// 选中结果由面板自行打开详情：面板 context 在弹窗路由内、必属于内容区
/// 导航器，经 [EmbeddedDetailLauncher] 分屏优先，避免调用方拿导航器自身
/// context 时误推到根导航器整窗覆盖侧栏。
Future<void> showDesktopSearch(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return AppCenteredModal.show<void>(
    context,
    alignment: Alignment.topCenter,
    insetPadding: EdgeInsets.fromLTRB(48, size.height * 0.08, 48, 48),
    barrierLabel: 'desktop-search-overlay',
    builder: (_) => const _DesktopSearchPanel(),
  );
}

/// 打开搜索结果条目详情（人物 → 人物页，其余 → 详情页）。
///
/// 打开顺序：分屏宿主优先（详情进右栏，[EmbeddedDetailLauncher] 与首页
/// 同链路），无宿主时回退直接推入当前导航器（内容区，侧栏常驻）。
/// [closeOverlay] 在详情受理后回调——面板用它收起自己；回退路径先关
/// 弹窗再推详情，保证关闭时它仍是栈顶。
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
      // 弹窗关闭后面板节点会失效：导航器与 provider 都在仍挂载时取好，
      // 之后的 await 一律不再摸 context。
      final navigator = Navigator.of(context);
      final nasProvider = context.read<NasProvider>();
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
          closeOverlay?.call();
          return;
        }
        closeOverlay?.call();
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
        closeOverlay?.call();
        return;
      }
      closeOverlay?.call();
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
  const _DesktopSearchPanel();

  @override
  State<_DesktopSearchPanel> createState() => _DesktopSearchPanelState();
}

class _DesktopSearchPanelState extends State<_DesktopSearchPanel> {
  static const Duration _searchDebounce = Duration(milliseconds: 260);
  static const int _maxHistoryCount = 12;
  // 与 SearchScreen 同 key：桌面弹窗与手机搜索页共享历史。
  static const String _historyKeyPrefix = 'search_history_v1';

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  Timer? _debounceTimer;
  List<MediaItemCard> _results = const <MediaItemCard>[];
  List<String> _history = const <String>[];
  String _query = '';
  _SearchCategory _category = _SearchCategory.all;
  bool _isSearching = false;
  AppException? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadHistory());
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
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
        _results = const <MediaItemCard>[];
        _isSearching = false;
      }
    });
    _debounceTimer?.cancel();
    if (trimmed.isEmpty) return;
    _debounceTimer = Timer(_searchDebounce, () {
      unawaited(_performSearch(trimmed));
    });
  }

  Future<void> _performSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || !mounted) return;
    setState(() {
      _isSearching = true;
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
        _isSearching = false;
      });
      await _saveHistoryEntry(trimmed);
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
    final visible = _visibleResults;
    if (visible.isEmpty) {
      unawaited(_performSearch(value));
      return;
    }
    _selectResult(visible.first);
  }

  void _selectResult(MediaItemCard item) {
    unawaited(_saveHistoryEntry(_controller.text));
    // closeOverlay 前先取好弹窗所在导航器：回退路径「先关弹窗再推详情」
    // 时它还是栈顶；分屏路径详情进右栏后再关弹窗。
    final dialogNavigator = Navigator.of(context);
    unawaited(
      openSearchItemDetail(context, item, closeOverlay: dialogNavigator.pop),
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
    final panelWidth = (size.width * 0.52).clamp(600.0, 860.0).toDouble();
    final panelHeight = (size.height * 0.76).clamp(500.0, 740.0).toDouble();

    return SizedBox(
      width: panelWidth,
      height: panelHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: _buildSearchField(colors, l10n),
          ),
          const SizedBox(height: 12),
          _buildCategoryTabs(colors, l10n),
          Divider(height: 1, thickness: 1, color: colors.borderSubtle),
          Expanded(
            // 状态/分类切换整块淡入淡出，替代生硬的列表跳动。
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: KeyedSubtree(
                key: ValueKey<String>(_contentKey),
                child: _buildContent(
                  provider: provider,
                  credentials: imageCredentials,
                  colors: colors,
                  l10n: l10n,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _contentKey {
    if (_query.trim().isEmpty) return 'history';
    if (_isSearching) return 'loading';
    if (_error != null) return 'error';
    return 'results:${_category.name}:${_controller.text.trim()}';
  }

  Widget _buildSearchField(AppThemeColors colors, AppLocalizations l10n) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colors.accent.withValues(alpha: 0.55),
          width: 1.2,
        ),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(width: 18),
          Icon(Icons.search_rounded, color: colors.textSecondary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              onChanged: _onQueryChanged,
              onSubmitted: _submitActive,
              style: TextStyle(color: colors.textPrimary, fontSize: 16),
              cursorColor: colors.accent,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: l10n.searchPlaceholder,
                hintStyle: TextStyle(color: colors.textMuted, fontSize: 16),
              ),
            ),
          ),
          if (_controller.text.isNotEmpty)
            IconButton(
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
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs(AppThemeColors colors, AppLocalizations l10n) {
    return SizedBox(
      height: 44,
      child: Row(
        children: <Widget>[
          const SizedBox(width: 12),
          for (final category in _SearchCategory.values) ...<Widget>[
            _CategoryTab(
              label: category.label(l10n),
              selected: _category == category,
              accentColor: colors.accent,
              idleColor: colors.textSecondary,
              onTap: () {
                if (_category == category) return;
                setState(() => _category = category);
              },
            ),
            const SizedBox(width: 6),
          ],
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
    if (_query.trim().isEmpty) {
      return _buildHistory(colors, l10n);
    }
    if (_isSearching) {
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
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 14),
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

  Widget _buildHistory(AppThemeColors colors, AppLocalizations l10n) {
    if (_history.isEmpty) {
      return Center(
        child: Text(
          l10n.searchPlaceholder,
          style: TextStyle(color: colors.textMuted, fontSize: 14),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                l10n.searchHistory,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            IconButton(
              tooltip: l10n.commonDelete,
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove(_historyKey());
                if (!mounted) return;
                setState(() {
                  _history = const <String>[];
                });
              },
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              color: colors.textMuted,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _history
              .map(
                (entry) => InkWell(
                  onTap: () {
                    _controller.text = entry;
                    _controller.selection = TextSelection.fromPosition(
                      TextPosition(offset: entry.length),
                    );
                    _onQueryChanged(entry);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.borderSubtle),
                    ),
                    child: Text(
                      entry,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
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
              color: hovering ? colors.surface : Colors.transparent,
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

/// 行首缩略图：人物用方头像，其余用海报比例；加载前/失败垫底色。
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
    final size = isPerson ? const Size.square(54) : const Size(54, 72);
    final radius = BorderRadius.circular(isPerson ? 12 : 8);
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
