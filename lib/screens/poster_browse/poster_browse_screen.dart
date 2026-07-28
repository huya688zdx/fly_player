import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/feiniu_api.dart';
import '../../controllers/item_playback_launcher.dart';
import '../../controllers/tv_season_playback_launcher.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../media_backend/media_backend.dart';
import '../../media_backend/media_item_card.dart';
import '../../providers/app_theme_provider.dart';
import '../../providers/media_backend_provider.dart';
import '../../providers/nas_provider.dart';
import '../../services/native_playback_reentry.dart';
import '../../services/native_player_bridge.dart';
import '../../theme/app_theme.dart';
import '../../ui/app_transitions.dart';
import '../../ui/detail_artwork_resolver.dart';
import '../../ui/detail_theme_prewarmer.dart';
import '../../utils/async_action_guard.dart';
import '../../utils/detail_top_tip.dart';
import '../../utils/swallowed_error_logger.dart';
import '../../widgets/detail/dynamic_page_theme_scope.dart';
import '../play_detail_screen.dart';
import 'poster_browse_artwork_enricher.dart';
import 'poster_browse_display_builder.dart';
import 'poster_browse_display_item.dart';
import 'poster_browse_focus_throttle.dart';
import 'poster_browse_large_layout.dart';
import 'poster_browse_loader.dart';
import 'poster_browse_mobile_layout.dart';
import 'poster_browse_orientation_controller.dart';
import 'poster_browse_rows.dart';
import 'poster_browse_selection_state.dart';
import 'poster_browse_text_presenter.dart';

/// 海报浏览页的会话边界。token 只取内存 hash，避免把原文带入日志或诊断输出。
@visibleForTesting
String buildPosterBrowseSessionKey({
  required Object backendKind,
  required String baseUrl,
  required String token,
}) {
  return '${backendKind.toString()}|${baseUrl.trim()}|${token.hashCode}';
}

@visibleForTesting
int clampPosterBrowseIndex(int index, int length) {
  if (length <= 0) return 0;
  if (index < 0) return 0;
  if (index >= length) return length - 1;
  return index;
}

/// 大屏/手机共享的沉浸海报浏览页编排层。
///
/// 本层只负责：会话加载、选择/吸附、懒补全、统一背景、方向恢复、播放/详情动作；
/// 横竖屏具体排版分别交给 [PosterBrowseLargeLayout] 与 [PosterBrowseMobileLayout]。
class PosterBrowseScreen extends StatefulWidget {
  const PosterBrowseScreen({super.key});

  @override
  State<PosterBrowseScreen> createState() => _PosterBrowseScreenState();
}

class _PosterBrowseScreenState extends State<PosterBrowseScreen> {
  static const int _rowItemLimit = 20;
  static const int _backdropWidth = 1280;
  static const int _logoWidth = 640;
  static const int _posterWidth = 360;

  final PosterBrowseSelectionState _selection = PosterBrowseSelectionState();
  final PosterBrowseDisplayBuilder _displayBuilder =
      const PosterBrowseDisplayBuilder();
  final PosterBrowseOrientationController _orientationController =
      const PosterBrowseOrientationController();
  final DetailTopTip _topTip = DetailTopTip();

  late final PosterBrowseFocusThrottle _focusThrottle;

  List<PosterBrowseRow> _rows = const <PosterBrowseRow>[];
  final Map<String, PosterBrowseDisplayItem> _displayById =
      <String, PosterBrowseDisplayItem>{};
  String? _settledItemId;
  int _focusGeneration = 0;
  int _loadGeneration = 0;
  bool _loading = true;
  bool? _isPhone;
  PosterBrowseArtworkEnricher? _enricher;
  String? _loadKey;
  Object? _reentryToken;

  @override
  void initState() {
    super.initState();
    _focusThrottle = PosterBrowseFocusThrottle(
      onSettle: _handleThrottledSettle,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final isPhone = PosterBrowseDeviceProfile.isPhone(
      MediaQuery.sizeOf(context),
    );
    if (_isPhone != isPhone) {
      _isPhone = isPhone;
      unawaited(_enterImmersiveMode(isPhone: isPhone));
    }

    final backend = Provider.of<MediaBackendProvider>(context).backend;
    final nas = Provider.of<NasProvider>(context);
    final nextLoadKey = buildPosterBrowseSessionKey(
      backendKind: backend.capabilities.kind,
      baseUrl: nas.baseUrl,
      token: nas.token,
    );
    if (_loadKey == nextLoadKey) return;

    _loadKey = nextLoadKey;
    _enricher?.clear();
    _enricher = PosterBrowseArtworkEnricher(
      backend: backend,
      sessionKey: nextLoadKey,
    );
    unawaited(_load(backend: backend, nas: nas, loadKey: nextLoadKey));
  }

  @override
  void dispose() {
    _focusThrottle.dispose();
    _topTip.dispose();
    _enricher?.clear();
    _loadGeneration += 1;
    _focusGeneration += 1;
    if (_reentryToken != null) {
      NativePlayerBridge.unbindReentry(_reentryToken!);
      _reentryToken = null;
    }
    unawaited(_orientationController.restore());
    super.dispose();
  }

  Future<void> _enterImmersiveMode({required bool isPhone}) async {
    try {
      await _orientationController.enter(isPhone: isPhone);
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'poster browse enter immersive mode',
        error: error,
        stackTrace: stackTrace,
        source: 'poster_browse_screen',
      );
    }
  }

  Future<void> _restoreOrientation() async {
    try {
      await _orientationController.restore();
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'poster browse restore orientation',
        error: error,
        stackTrace: stackTrace,
        source: 'poster_browse_screen',
      );
    }
  }

  void _showTopTip(String message, Color color) {
    if (!mounted) return;
    _topTip.show(context, message: message, color: color);
  }

  Future<void> _load({
    required MediaBackend backend,
    required NasProvider nas,
    required String loadKey,
  }) async {
    final generation = _loadGeneration + 1;
    _loadGeneration = generation;
    _focusGeneration += 1;

    if (mounted) {
      setState(() {
        _loading = true;
        _rows = const <PosterBrowseRow>[];
        _displayById.clear();
        _settledItemId = null;
        _selection.reset();
      });
    }

    try {
      final rows = await const PosterBrowseLoader().load(
        backend: backend,
        api: FeiniuApi(nas),
        rowItemLimit: _rowItemLimit,
      );
      if (!_isCurrentLoad(generation: generation, loadKey: loadKey)) return;

      final displayById = <String, PosterBrowseDisplayItem>{};
      for (final row in rows) {
        for (final card in row.items) {
          displayById[card.id] = _displayBuilder.build(card: card);
        }
      }

      _selection.reset();
      _selection.normalizeForRows(
        rows.map((row) => row.items.length).toList(growable: false),
      );

      setState(() {
        _rows = rows;
        _displayById
          ..clear()
          ..addAll(displayById);
        _loading = false;
        _settledItemId = null;
      });

      if (rows.isNotEmpty && rows.first.items.isNotEmpty) {
        unawaited(_settle(rowIndex: 0, itemIndex: 0));
      }
    } catch (error, stackTrace) {
      if (!_isCurrentLoad(generation: generation, loadKey: loadKey)) return;
      await logSwallowedError(
        action: 'poster browse load rows',
        error: error,
        stackTrace: stackTrace,
        source: 'poster_browse_screen',
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _rows = const <PosterBrowseRow>[];
        _displayById.clear();
        _settledItemId = null;
        _selection.reset();
      });
    }
  }

  bool _isCurrentLoad({required int generation, required String loadKey}) {
    return mounted && generation == _loadGeneration && loadKey == _loadKey;
  }

  _NormalizedSelection? _normalizeSelection({
    required int rowIndex,
    required int itemIndex,
  }) {
    if (_rows.isEmpty) return null;
    final safeRow = clampPosterBrowseIndex(rowIndex, _rows.length);
    final row = _rows[safeRow];
    if (row.items.isEmpty) return null;
    final safeItem = clampPosterBrowseIndex(itemIndex, row.items.length);
    return _NormalizedSelection(rowIndex: safeRow, itemIndex: safeItem);
  }

  PosterBrowseDisplayItem _displayItemOf(MediaItemCard card) {
    return _displayById[card.id] ?? _displayBuilder.build(card: card);
  }

  PosterBrowseDisplayItem? get _focusedItem {
    final normalized = _normalizeSelection(
      rowIndex: _selection.selectedRow,
      itemIndex: _selection.currentIndex,
    );
    if (normalized == null) return null;
    return _displayItemOf(
      _rows[normalized.rowIndex].items[normalized.itemIndex],
    );
  }

  PosterBrowseDisplayItem? get _settledItem {
    final id = _settledItemId;
    if (id != null) {
      final display = _displayById[id];
      if (display != null) return display;
    }
    return _focusedItem;
  }

  void _handleThrottledSettle(String itemId) {
    if (!mounted) return;
    final focused = _focusedItem;
    if (focused == null || focused.card.id != itemId) return;
    unawaited(
      _settle(
        rowIndex: _selection.selectedRow,
        itemIndex: _selection.currentIndex,
      ),
    );
  }

  Future<void> _settle({required int rowIndex, required int itemIndex}) async {
    final normalized = _normalizeSelection(
      rowIndex: rowIndex,
      itemIndex: itemIndex,
    );
    if (normalized == null) return;

    final row = _rows[normalized.rowIndex];
    final card = row.items[normalized.itemIndex];
    final generation = _focusGeneration + 1;
    _focusGeneration = generation;
    final loadKey = _loadKey;

    setState(() {
      _selection.select(
        rowIndex: normalized.rowIndex,
        itemIndex: normalized.itemIndex,
      );
      _settledItemId = card.id;
    });
    _precacheNeighbors(
      rowIndex: normalized.rowIndex,
      itemIndex: normalized.itemIndex,
    );

    final enricher = _enricher;
    if (enricher == null || loadKey == null) return;
    unawaited(enricher.prefetchWindow(row.items, normalized.itemIndex));

    try {
      final enrichment = await enricher.enrich(card);
      if (!mounted || loadKey != _loadKey) return;

      final enrichedDisplay = _displayBuilder.build(
        card: card,
        itemDetail: enrichment.itemDetail,
        seriesDetail: enrichment.seriesDetail,
        season: enrichment.season,
      );

      if (generation != _focusGeneration) {
        _displayById[card.id] = enrichedDisplay;
        return;
      }

      setState(() => _displayById[card.id] = enrichedDisplay);
      _precacheNeighbors(
        rowIndex: normalized.rowIndex,
        itemIndex: normalized.itemIndex,
      );
    } catch (error, stackTrace) {
      if (!mounted || loadKey != _loadKey) return;
      await logSwallowedError(
        action: 'poster browse enrich focused item',
        error: error,
        stackTrace: stackTrace,
        source: 'poster_browse_screen',
        id: card.id,
      );
    }
  }

  void _precacheNeighbors({required int rowIndex, required int itemIndex}) {
    if (!mounted) return;
    final normalized = _normalizeSelection(
      rowIndex: rowIndex,
      itemIndex: itemIndex,
    );
    if (normalized == null) return;

    final row = _rows[normalized.rowIndex];
    final resolver = _resolver();
    final cacheWidth = _backdropCacheWidth();
    for (
      var index = normalized.itemIndex - 2;
      index <= normalized.itemIndex + 2;
      index += 1
    ) {
      if (index < 0 ||
          index >= row.items.length ||
          index == normalized.itemIndex) {
        continue;
      }
      final display = _displayItemOf(row.items[index]);
      final request = _backgroundRequestOf(resolver, display);
      if (request.isEmpty) continue;
      unawaited(
        precacheImage(
          ResizeImage(
            NetworkImage(request.urls.first, headers: request.headers),
            width: cacheWidth,
          ),
          context,
          onError: (_, __) {},
        ),
      );
    }
  }

  int _backdropCacheWidth() {
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 1.6);
    return (MediaQuery.sizeOf(context).width * dpr).round().clamp(560, 1440);
  }

  DetailArtworkResolver _resolver() {
    final nas = context.read<NasProvider>();
    return DetailArtworkResolver(baseUrl: nas.baseUrl, token: nas.token);
  }

  MediaImageRequest _backgroundRequestOf(
    DetailArtworkResolver resolver,
    PosterBrowseDisplayItem item,
  ) {
    return resolver.resolveRefs(item.backgroundImages, width: _backdropWidth);
  }

  MediaImageRequest _logoRequestOf(
    DetailArtworkResolver resolver,
    PosterBrowseDisplayItem item,
  ) {
    return resolver.resolveRefs(item.logoImages, width: _logoWidth);
  }

  MediaImageRequest _posterRequestOf(
    DetailArtworkResolver resolver,
    PosterBrowseDisplayItem item,
  ) {
    return resolver.resolveRefs(item.posterImages, width: _posterWidth);
  }

  void _handleSelectRow(int rowIndex) {
    final normalized = _normalizeSelection(
      rowIndex: rowIndex,
      itemIndex: _selection.indexForRow(rowIndex),
    );
    if (normalized == null) return;
    _selection.selectRow(normalized.rowIndex);
    unawaited(
      _settle(rowIndex: normalized.rowIndex, itemIndex: normalized.itemIndex),
    );
  }

  void _handleLargeSelectItem(int itemIndex) {
    final normalized = _normalizeSelection(
      rowIndex: _selection.selectedRow,
      itemIndex: itemIndex,
    );
    if (normalized == null) return;

    final alreadyFocused =
        normalized.rowIndex == _selection.selectedRow &&
        normalized.itemIndex == _selection.currentIndex;
    if (alreadyFocused) {
      final item = _displayItemOf(
        _rows[normalized.rowIndex].items[normalized.itemIndex],
      );
      unawaited(_openDetail(item));
      return;
    }

    unawaited(
      _settle(rowIndex: normalized.rowIndex, itemIndex: normalized.itemIndex),
    );
  }

  void _handleMobileSettled(int itemIndex) {
    final normalized = _normalizeSelection(
      rowIndex: _selection.selectedRow,
      itemIndex: itemIndex,
    );
    if (normalized == null) return;
    unawaited(
      _settle(rowIndex: normalized.rowIndex, itemIndex: normalized.itemIndex),
    );
  }

  void _handleCenteredTap(int itemIndex) {
    final normalized = _normalizeSelection(
      rowIndex: _selection.selectedRow,
      itemIndex: itemIndex,
    );
    if (normalized == null) return;
    final item = _displayItemOf(
      _rows[normalized.rowIndex].items[normalized.itemIndex],
    );
    unawaited(_openDetail(item));
  }

  Future<void> _handleBack() async {
    await _restoreOrientation();
    if (!mounted) return;
    await Navigator.of(context).maybePop();
  }

  Future<void> _retryLoad() async {
    final backend = context.read<MediaBackendProvider>().backend;
    final nas = context.read<NasProvider>();
    final loadKey = buildPosterBrowseSessionKey(
      backendKind: backend.capabilities.kind,
      baseUrl: nas.baseUrl,
      token: nas.token,
    );
    _loadKey = loadKey;
    _enricher?.clear();
    _enricher = PosterBrowseArtworkEnricher(
      backend: backend,
      sessionKey: loadKey,
    );
    await _load(backend: backend, nas: nas, loadKey: loadKey);
  }

  /// 打开详情。条目展示可用父级详情目标；播放仍必须使用 [item.card] 真实条目。
  Future<void> _openDetail(PosterBrowseDisplayItem item) {
    final targetId = _detailTargetId(item);
    return AsyncActionGuard.run<void>(
      'poster_browse_detail:$targetId',
      settleDuration: const Duration(milliseconds: 450),
      action: () => _openDetailInner(item, targetId: targetId),
    );
  }

  Future<void> _openDetailInner(
    PosterBrowseDisplayItem item, {
    required String targetId,
  }) async {
    var orientationRestored = false;
    try {
      final artwork = _backgroundRequestOf(_resolver(), item);
      await DetailThemePrewarmer.warmUp(
        context,
        pageKey: targetId,
        imageUrl: artwork.isNotEmpty ? artwork.urls.first : '',
      );
      orientationRestored = true;
      await _restoreOrientation();
      if (!mounted) return;
      if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
      await Navigator.of(context).push(
        AppTransitions.leftToRightPageTurnRoute<void>(
          PlayDetailScreen(itemGuid: targetId),
        ),
      );
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'poster browse open detail',
        error: error,
        stackTrace: stackTrace,
        source: 'poster_browse_screen',
        id: targetId,
      );
    } finally {
      if (orientationRestored) {
        if (mounted) {
          await _enterImmersiveMode(isPhone: _isPhone ?? true);
        } else {
          await _restoreOrientation();
        }
      }
    }
  }

  String _detailTargetId(PosterBrowseDisplayItem item) {
    final target = item.detailTargetId.trim();
    if (target.isNotEmpty) return target;
    return item.card.id.trim();
  }

  /// 起播：剧集先解析可播目标（首集 / 续播集），其余走单条目拉起。
  ///
  /// [ItemPlaybackLauncher] 内部自带 reentry 绑定；[TvSeasonPlaybackLauncher] **不带**，
  /// 剧集分支须由本页按统一约定先 [NativePlaybackReentry.bind] 再 open，
  /// 否则原生壳的选集 / 进度回写 / 画质重解析全部失联。
  Future<void> _play(PosterBrowseDisplayItem displayItem) {
    final item = displayItem.card;
    return AsyncActionGuard.run<void>(
      'poster_browse_play:${item.id.trim()}',
      settleDuration: const Duration(milliseconds: 450),
      action: () => _playInner(item),
    );
  }

  Future<void> _playInner(MediaItemCard item) async {
    try {
      final type = item.type.trim().toLowerCase();
      if (type == 'series' || type == 'tv') {
        final nas = context.read<NasProvider>();
        final backend = context.read<MediaBackendProvider>().backend;
        final l10n = AppLocalizations.of(context);
        final seriesTitle = item.displayTitle;
        final seriesGuid = item.id;
        final target = await backend.resolveSeriesPlaybackTarget(seriesGuid);
        if (!mounted) return;
        if (target.trim().isEmpty) {
          _showTopTip(l10n.detailPlayInfoFailed, context.appColors.danger);
          return;
        }
        _reentryToken = NativePlaybackReentry.bind(
          backend: backend,
          nas: nas,
          l10n: l10n,
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
                  seriesGuid: seriesGuid,
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
        await const TvSeasonPlaybackLauncher().open(
          context,
          itemGuid: target,
          seriesTitle: seriesTitle,
          seriesGuid: seriesGuid,
        );
        return;
      }
      await const ItemPlaybackLauncher().open(
        context,
        itemGuid: item.id,
        fallbackTitle: item.displayTitle,
      );
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'poster browse play',
        error: error,
        stackTrace: stackTrace,
        source: 'poster_browse_screen',
        id: item.id,
      );
      if (!mounted) return;
      _showTopTip(
        AppLocalizations.of(context).detailPlayInfoFailed,
        context.appColors.danger,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final token = context.select<NasProvider, String>((nas) => nas.token);
    final baseUrl = context.select<NasProvider, String>((nas) => nas.baseUrl);
    final dynamicThemeEnabled = context.select<AppThemeProvider, bool>(
      (themeProvider) => themeProvider.dynamicThemeEnabled,
    );
    final intensity = context
        .select<AppThemeProvider, AppDynamicThemeIntensity>(
          (themeProvider) => themeProvider.dynamicThemeIntensity,
        );

    final resolver = DetailArtworkResolver(baseUrl: baseUrl, token: token);
    final settledItem = _settledItem;
    final focusedItem = _focusedItem;
    final background = settledItem == null
        ? MediaImageRequest.empty
        : _backgroundRequestOf(resolver, settledItem);

    return DynamicPageThemeScope(
      pageKey: _settledItemId ?? 'poster_browse_empty',
      imageUrl: background.isNotEmpty ? background.urls.first : '',
      imageHeaders: background.headers,
      enabled: dynamicThemeEnabled && settledItem != null,
      intensity: intensity,
      builder: (context, ambientTint) {
        return PopScope(
          onPopInvokedWithResult: (_, __) => unawaited(_restoreOrientation()),
          child: Scaffold(
            backgroundColor: ambientTint ?? Colors.black,
            body: _loading
                ? const Center(child: CircularProgressIndicator())
                : focusedItem == null
                ? _buildError(l10n)
                : _buildLoadedBody(
                    context: context,
                    ambientTint: ambientTint,
                    resolver: resolver,
                    focusedItem: focusedItem,
                    settledItem: settledItem ?? focusedItem,
                    background: background,
                  ),
          ),
        );
      },
    );
  }

  Widget _buildLoadedBody({
    required BuildContext context,
    required Color? ambientTint,
    required DetailArtworkResolver resolver,
    required PosterBrowseDisplayItem focusedItem,
    required PosterBrowseDisplayItem settledItem,
    required MediaImageRequest background,
  }) {
    final l10n = AppLocalizations.of(context);
    final presenter = PosterBrowseTextPresenter(l10n: l10n);
    final secondaryLabel = presenter.secondaryLabel(focusedItem);
    final metaWidgets = _buildMetaWidgets(presenter.metaTexts(focusedItem));
    final logoRequest = _logoRequestOf(resolver, focusedItem);
    final selectedRow = clampPosterBrowseIndex(
      _selection.selectedRow,
      _rows.length,
    );
    final focusedIndex = _focusedIndexForRow(selectedRow);
    final isPhone =
        _isPhone ??
        PosterBrowseDeviceProfile.isPhone(MediaQuery.sizeOf(context));

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: KeyedSubtree(
            key: ValueKey<String>(settledItem.card.id),
            child: background.isNotEmpty
                ? _buildBackdropImage(background)
                : SizedBox.expand(
                    child: ColoredBox(color: ambientTint ?? Colors.black),
                  ),
          ),
        ),
        const SizedBox.expand(child: ColoredBox(color: Color(0x5906080E))),
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
        isPhone
            ? PosterBrowseMobileLayout(
                rows: _rows,
                displayItemOf: _displayItemOf,
                selectedRow: selectedRow,
                focusedIndex: focusedIndex,
                focusedItem: focusedItem,
                logoRequest: logoRequest,
                secondaryLabel: secondaryLabel,
                metaWidgets: metaWidgets,
                imageOf: (item) => _posterRequestOf(resolver, item),
                secondaryLabelOf: presenter.secondaryLabel,
                onSelectRow: _handleSelectRow,
                onSelectItem: _handleMobileSettled,
                onCenteredTap: _handleCenteredTap,
                onPlay: () => unawaited(_play(focusedItem)),
                onDetail: () => unawaited(_openDetail(focusedItem)),
                onBack: () => unawaited(_handleBack()),
              )
            : PosterBrowseLargeLayout(
                rows: _rows,
                displayItemOf: _displayItemOf,
                selectedRow: selectedRow,
                focusedIndex: focusedIndex,
                focusedItem: focusedItem,
                logoRequest: logoRequest,
                secondaryLabel: secondaryLabel,
                metaWidgets: metaWidgets,
                imageOf: (item) => _posterRequestOf(resolver, item),
                secondaryLabelOf: presenter.secondaryLabel,
                onSelectRow: _handleSelectRow,
                onSelectItem: _handleLargeSelectItem,
                onPlay: () => unawaited(_play(focusedItem)),
                onDetail: () => unawaited(_openDetail(focusedItem)),
                onBack: () => unawaited(_handleBack()),
              ),
      ],
    );
  }

  int _focusedIndexForRow(int rowIndex) {
    if (_rows.isEmpty) return 0;
    final safeRow = clampPosterBrowseIndex(rowIndex, _rows.length);
    final row = _rows[safeRow];
    return clampPosterBrowseIndex(
      _selection.indexForRow(safeRow),
      row.items.length,
    );
  }

  List<Widget> _buildMetaWidgets(List<String> texts) {
    return texts.map(_buildMetaWidget).toList(growable: false);
  }

  Widget _buildMetaWidget(String rawText) {
    final text = rawText.trim();
    if (text.startsWith('★')) {
      return Text(
        text,
        style: const TextStyle(
          color: Color(0xFFFFD166),
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withValues(alpha: 0.08),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.82),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildBackdropImage(MediaImageRequest backdrop) {
    return _PosterBrowseBackdrop(
      urls: backdrop.urls,
      headers: backdrop.headers,
      cacheWidth: _backdropCacheWidth(),
    );
  }

  Widget _buildError(AppLocalizations l10n) {
    return Center(
      child: TextButton(
        onPressed: () => unawaited(_retryLoad()),
        child: Text(
          l10n.posterBrowseLoadFailed,
          style: const TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}

class _NormalizedSelection {
  final int rowIndex;
  final int itemIndex;

  const _NormalizedSelection({required this.rowIndex, required this.itemIndex});
}

/// 背景大图：铺满全屏的单张 `Image.network`，首选 URL 失败按候选链回退。
class _PosterBrowseBackdrop extends StatefulWidget {
  const _PosterBrowseBackdrop({
    required this.urls,
    required this.headers,
    required this.cacheWidth,
  });

  final List<String> urls;
  final Map<String, String> headers;
  final int cacheWidth;

  @override
  State<_PosterBrowseBackdrop> createState() => _PosterBrowseBackdropState();
}

class _PosterBrowseBackdropState extends State<_PosterBrowseBackdrop> {
  int _index = 0;

  @override
  void didUpdateWidget(covariant _PosterBrowseBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.urls, widget.urls)) {
      _index = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_index >= widget.urls.length) return const SizedBox.expand();
    return SizedBox.expand(
      child: Image.network(
        widget.urls[_index],
        fit: BoxFit.cover,
        gaplessPlayback: true,
        cacheWidth: widget.cacheWidth,
        headers: widget.headers.isEmpty ? null : widget.headers,
        errorBuilder: (_, __, ___) {
          if (_index + 1 < widget.urls.length) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _index += 1);
            });
          }
          return const SizedBox.expand();
        },
      ),
    );
  }
}
