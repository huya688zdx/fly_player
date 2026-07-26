import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/feiniu_api.dart';
import '../../controllers/item_playback_launcher.dart';
import '../../controllers/tv_season_playback_launcher.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../media_backend/media_image_ref.dart';
import '../../media_backend/media_item_card.dart';
import '../../providers/app_theme_provider.dart';
import '../../providers/media_backend_provider.dart';
import '../../providers/nas_provider.dart';
import '../../theme/app_theme.dart';
import '../../ui/detail_artwork_resolver.dart';
import '../../ui/detail_theme_prewarmer.dart';
import '../../widgets/detail/dynamic_page_theme_scope.dart';
import '../../widgets/detail/immersive_detail_background.dart';
import '../play_detail_screen.dart';
import 'poster_browse_focus_throttle.dart';
import 'poster_browse_loader.dart';
import 'poster_browse_rows.dart';
import 'poster_browse_thumb_strip.dart';

/// 大屏海报浏览页：横屏全屏沉浸，聚焦条目 backdrop 铺底，底部多行分类缩略图条。
///
/// 页面为深色沉浸设计（非主题化文案色），前景文字统一用白色系；
/// 背景取色仍走 [DynamicPageThemeScope]，与详情页共享同一 pageKey 的 seed 缓存。
class PosterBrowseScreen extends StatefulWidget {
  const PosterBrowseScreen({super.key});

  @override
  State<PosterBrowseScreen> createState() => _PosterBrowseScreenState();
}

class _PosterBrowseScreenState extends State<PosterBrowseScreen> {
  static const int _rowItemLimit = 20;

  /// 背景大图解析宽度（全屏铺底，取 720p 级别足够且省流）。
  static const int _backdropWidth = 1280;

  /// 缩略图解析宽度（16:9 小图）。
  static const int _thumbWidth = 440;

  List<PosterBrowseRow> _rows = const <PosterBrowseRow>[];
  bool _loading = true;
  int _rowIndex = 0;

  /// 每行各自记忆焦点索引，切行回来不丢位置。
  final Map<int, int> _focusByRow = <int, int>{};

  /// 节流后的聚焦条目：驱动背景大图与动态取色（快速滑动时不逐帧换图）。
  MediaItemCard? _settled;

  late final PageController _rowController;
  late final PosterBrowseFocusThrottle _throttle;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _rowController = PageController(viewportFraction: 0.62);
    _throttle = PosterBrowseFocusThrottle(onSettle: _onFocusSettled);
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    unawaited(_enterImmersiveLandscape());
    unawaited(_load());
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _throttle.dispose();
    _rowController.dispose();
    // 双保险：正常路径由 _openDetail 在推详情前就已恢复；异常 pop / 被系统回收时
    // 这里兜底解除横屏锁与沉浸模式，避免把整个 App 留在横屏全屏状态。
    unawaited(_exitImmersiveLandscape());
    super.dispose();
  }

  Future<void> _enterImmersiveLandscape() async {
    await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _exitImmersiveLandscape() async {
    await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> _load() async {
    // 首次进入 _loading 已是 true（initState 同步路径不触碰 setState）；重试才需刷新。
    if (!_loading) {
      setState(() => _loading = true);
    }
    final backend = context.read<MediaBackendProvider>().backend;
    final api = FeiniuApi(context.read<NasProvider>());
    final rows = await const PosterBrowseLoader().load(
      backend: backend,
      api: api,
      rowItemLimit: _rowItemLimit,
    );
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
      _rowIndex = 0;
      _focusByRow.clear();
      _settled = rows.isEmpty || rows.first.items.isEmpty
          ? null
          : rows.first.items.first;
    });
  }

  PosterBrowseRow? get _currentRow {
    if (_rows.isEmpty || _rowIndex < 0 || _rowIndex >= _rows.length) {
      return null;
    }
    return _rows[_rowIndex];
  }

  MediaItemCard? get _focusedItem {
    final row = _currentRow;
    if (row == null || row.items.isEmpty) return null;
    final index = (_focusByRow[_rowIndex] ?? 0).clamp(0, row.items.length - 1);
    return row.items[index];
  }

  /// 节流落定：核对仍是当前聚焦项才换背景（防快速切换后回调错位）。
  void _onFocusSettled(String itemId) {
    if (!mounted) return;
    final item = _focusedItem;
    if (item == null || item.id != itemId) return;
    setState(() => _settled = item);
    _precacheNeighbors();
  }

  /// 相邻 ±2 张 backdrop 预取，滑动到位时背景即刻可用。
  void _precacheNeighbors() {
    final row = _currentRow;
    if (row == null) return;
    final resolver = _resolver();
    final center = (_focusByRow[_rowIndex] ?? 0).clamp(0, row.items.length - 1);
    for (var i = center - 2; i <= center + 2; i++) {
      if (i < 0 || i >= row.items.length || i == center) continue;
      final artwork = _backdropOf(resolver, row.items[i]);
      if (artwork.isEmpty) continue;
      unawaited(
        precacheImage(
          NetworkImage(artwork.urls.first, headers: artwork.headers),
          context,
          onError: (_, __) {},
        ),
      );
    }
  }

  DetailArtworkResolver _resolver() {
    final nas = context.read<NasProvider>();
    return DetailArtworkResolver(baseUrl: nas.baseUrl, token: nas.token);
  }

  /// 背景候选链：backdrop 优先，退主海报。
  DetailArtwork _backdropOf(
    DetailArtworkResolver resolver,
    MediaItemCard item,
  ) {
    return resolver.resolveRefs(<MediaImageRef>[
      item.backdropImage,
      item.primaryImage,
    ], width: _backdropWidth);
  }

  DetailArtwork _thumbOf(DetailArtworkResolver resolver, MediaItemCard item) {
    return resolver.resolveRefs(<MediaImageRef>[
      item.backdropImage,
      item.primaryImage,
    ], width: _thumbWidth);
  }

  /// 整行共用一份鉴权 header（飞牛相对路径图需要；Emby 直链为空）。
  /// 同一行图源同主机，取首个非空即可。
  Map<String, String> _rowImageHeaders(
    DetailArtworkResolver resolver,
    PosterBrowseRow row,
  ) {
    for (final item in row.items) {
      final headers = _thumbOf(resolver, item).headers;
      if (headers.isNotEmpty) return headers;
    }
    return const <String, String>{};
  }

  void _onThumbTap(int rowIndex, int itemIndex) {
    final row = _rows[rowIndex];
    final item = row.items[itemIndex];
    final alreadyFocused =
        rowIndex == _rowIndex && (_focusByRow[rowIndex] ?? 0) == itemIndex;
    if (alreadyFocused) {
      // 再点已聚焦项 = 进详情。
      unawaited(_openDetail(item));
      return;
    }
    setState(() => _focusByRow[rowIndex] = itemIndex);
    _throttle.schedule(item.id);
  }

  Future<void> _openDetail(MediaItemCard item) async {
    final artwork = _backdropOf(_resolver(), item);
    await DetailThemePrewarmer.warmUp(
      context,
      pageKey: item.id,
      imageUrl: artwork.isNotEmpty ? artwork.urls.first : '',
    );
    if (!mounted) return;
    // 详情页按竖屏设计：进入前恢复竖屏 + edgeToEdge，返回后重回横屏沉浸。
    await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayDetailScreen(itemGuid: item.id),
      ),
    );
    if (!mounted) return;
    await _enterImmersiveLandscape();
  }

  /// 起播：剧集先解析可播目标（首集 / 续播集），其余走单条目拉起。
  /// 两个 launcher 内部已自带 reentry 绑定与原生壳启动，此处不重复绑定。
  Future<void> _play(MediaItemCard item) async {
    final type = item.type.trim().toLowerCase();
    if (type == 'series' || type == 'tv') {
      final backend = context.read<MediaBackendProvider>().backend;
      final target = await backend.resolveSeriesPlaybackTarget(item.id);
      if (!mounted || target.trim().isEmpty) return;
      await const TvSeasonPlaybackLauncher().open(
        context,
        itemGuid: target,
        seriesTitle: item.displayTitle,
        seriesGuid: item.id,
      );
      return;
    }
    await const ItemPlaybackLauncher().open(
      context,
      itemGuid: item.id,
      fallbackTitle: item.displayTitle,
    );
  }

  String _rowLabel(AppLocalizations l10n, PosterBrowseRow row) {
    switch (row.kind) {
      case PosterBrowseRowKind.continueWatching:
        return l10n.posterBrowseRowContinue;
      case PosterBrowseRowKind.latest:
        return l10n.posterBrowseRowLatest;
      case PosterBrowseRowKind.catalog:
        return row.catalogTitle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nas = context.read<NasProvider>();
    final dynamicThemeEnabled = context.select<AppThemeProvider, bool>(
      (themeProvider) => themeProvider.dynamicThemeEnabled,
    );
    final intensity = context
        .select<AppThemeProvider, AppDynamicThemeIntensity>(
          (themeProvider) => themeProvider.dynamicThemeIntensity,
        );
    final settled = _settled;
    final resolver = _resolver();
    final backdrop = settled == null
        ? DetailArtwork.empty
        : _backdropOf(resolver, settled);

    return DynamicPageThemeScope(
      // 与详情页同键：同一条目的取色 seed 缓存互通，进详情不再重算。
      pageKey: settled?.id ?? 'poster_browse_empty',
      imageUrl: backdrop.isNotEmpty ? backdrop.urls.first : '',
      token: nas.token,
      enabled: dynamicThemeEnabled && settled != null,
      intensity: intensity,
      builder: (context, ambientTint) {
        final size = MediaQuery.sizeOf(context);
        return Scaffold(
          backgroundColor: ambientTint ?? Colors.black,
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
              ? _buildError(l10n)
              : Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    // 背景交叉淡入：只在节流落定后换图，无低清铺底（垫底图与主图不同源会闪）。
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      child: KeyedSubtree(
                        key: ValueKey<String>(settled?.id ?? ''),
                        child: backdrop.isNotEmpty
                            ? ImmersiveDetailBackground(
                                urls: backdrop.urls,
                                token: nas.token,
                                scrollOffset: 0,
                                posterHeight: size.height,
                                imageAlignment: Alignment.center,
                                fillGapsWithImage: true,
                                parallaxFactor: 0,
                                overlayOpacity: 0.62,
                                ambientTintOverride: ambientTint,
                              )
                            : ColoredBox(color: ambientTint ?? Colors.black),
                      ),
                    ),
                    // 左侧渐变压暗，保证信息区可读。
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          stops: <double>[0, 0.38, 0.68, 1],
                          colors: <Color>[
                            Color(0xEE06080E),
                            Color(0x8C06080E),
                            Color(0x1406080E),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                    // 底部渐变压暗，托住缩略图行区。
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          stops: <double>[0, 0.35, 0.6],
                          colors: <Color>[
                            Color(0xF706080E),
                            Color(0xB806080E),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          _buildTopBar(context),
                          Expanded(child: _buildInfoArea(l10n, settled)),
                          SizedBox(
                            height: size.height * 0.36,
                            child: _buildRowPager(l10n, resolver),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => unawaited(Navigator.of(context).maybePop()),
          ),
          Text(
            TimeOfDay.now().format(context),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  /// 左下信息区：元数据缺失的行整块隐藏，不留占位。
  Widget _buildInfoArea(AppLocalizations l10n, MediaItemCard? item) {
    final row = _currentRow;
    if (item == null || row == null) return const SizedBox.shrink();
    final year = item.releaseDate.trim().length >= 4
        ? item.releaseDate.trim().substring(0, 4)
        : '';
    final genres = item.genres.where((g) => g.trim().isNotEmpty).take(3);
    final overview = item.overview.trim();
    final metaParts = <Widget>[
      if (item.rating.trim().isNotEmpty)
        Text(
          '★ ${item.rating.trim()}',
          style: const TextStyle(
            color: Color(0xFFFFD166),
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      if (year.isNotEmpty) _metaText(year),
      if (genres.isNotEmpty) _metaText(genres.join(' / ')),
      if (item.durationSeconds > 0)
        _metaText(l10n.detailDurationMinutes(item.durationSeconds ~/ 60)),
      for (final resolution in item.resolutions.take(2)) _metaChip(resolution),
    ];
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 36, right: 36, bottom: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _rowLabel(l10n, row).toUpperCase(),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (metaParts.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: metaParts,
              ),
            ],
            if (overview.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Text(
                  overview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                  ),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l10n.detailPlay),
                  onPressed: () => unawaited(_play(item)),
                ),
                const SizedBox(width: 10),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.16),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => unawaited(_openDetail(item)),
                  child: Text(l10n.posterBrowseDetail),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaText(String text) => Text(
    text,
    style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 13),
  );

  Widget _metaChip(String text) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.8),
          fontSize: 10.5,
          letterSpacing: 0.5,
        ),
      ),
    ),
  );

  /// 底部行区：垂直分页切行，下一行半露（viewportFraction 0.62）。
  Widget _buildRowPager(AppLocalizations l10n, DetailArtworkResolver resolver) {
    return PageView.builder(
      controller: _rowController,
      scrollDirection: Axis.vertical,
      itemCount: _rows.length,
      onPageChanged: (index) {
        setState(() => _rowIndex = index);
        final item = _focusedItem;
        if (item != null) _throttle.schedule(item.id);
      },
      itemBuilder: (context, rowIndex) {
        final row = _rows[rowIndex];
        final active = rowIndex == _rowIndex;
        final headers = _rowImageHeaders(resolver, row);
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: active ? 1 : 0.45,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(left: 36, bottom: 8),
                child: Row(
                  children: <Widget>[
                    Text(
                      _rowLabel(l10n, row),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      l10n.posterBrowseRowIndicator(rowIndex + 1, _rows.length),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: PosterBrowseThumbStrip(
                  items: row.items,
                  focusedIndex: _focusByRow[rowIndex] ?? 0,
                  showProgress:
                      row.kind == PosterBrowseRowKind.continueWatching,
                  imageHeaders: headers,
                  imageUrlOf: (item) {
                    final artwork = _thumbOf(resolver, item);
                    return artwork.isNotEmpty ? artwork.urls.first : '';
                  },
                  onItemTap: (itemIndex) => _onThumbTap(rowIndex, itemIndex),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildError(AppLocalizations l10n) {
    return Center(
      child: TextButton(
        onPressed: () => unawaited(_load()),
        child: Text(
          l10n.posterBrowseLoadFailed,
          style: const TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}
