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
import '../../providers/backend_session_provider.dart';
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
import 'poster_browse_artwork_prewarmer.dart';
import 'poster_browse_background_policy.dart';
import 'poster_browse_catalog_load_coordinator.dart';
import 'poster_browse_catalog_session.dart';
import 'poster_browse_display_builder.dart';
import 'poster_browse_display_item.dart';
import 'poster_browse_enrichment_commit_policy.dart';
import 'poster_browse_focus_throttle.dart';
import 'poster_browse_large_layout.dart';
import 'poster_browse_loader.dart';
import 'poster_browse_mobile_layout.dart';
import 'poster_browse_orientation_controller.dart';
import 'poster_browse_row_artwork_warmup.dart';
import 'poster_browse_rows.dart';
import 'poster_browse_screen_policy.dart';
import 'poster_browse_session_key.dart';
import 'poster_browse_selection_state.dart';
import 'poster_browse_text_presenter.dart';

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
  static const int _logoWidth = 640;
  static const int _posterWidth = 360;

  final PosterBrowseSelectionState _selection = PosterBrowseSelectionState();
  final _catalogLoadCoordinator =
      PosterBrowseCatalogLoadCoordinator<List<MediaItemCard>>();
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
  bool _immersiveModeEntered = false;
  MediaBackend? _backend;
  PosterBrowseCatalogSession? _catalogSession;
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

    if (!_immersiveModeEntered) {
      _immersiveModeEntered = true;
      unawaited(_enterImmersiveMode());
    }

    final backend = Provider.of<MediaBackendProvider>(context).backend;
    final nas = Provider.of<NasProvider>(context);
    final backendSession = Provider.of<BackendSessionProvider>(context);
    final connection = backendSession.currentConnection;
    final nextLoadKey = buildPosterBrowseBackendSessionKey(
      backendKind: backend.capabilities.kind,
      nasBaseUrl: nas.baseUrl,
      nasToken: nas.token,
      serverBaseUrl: connection?.serverUrl ?? '',
      serverToken: connection?.accessToken ?? '',
    );
    if (identical(_backend, backend) && _loadKey == nextLoadKey) return;

    _backend = backend;
    _loadKey = nextLoadKey;
    _catalogLoadCoordinator.clear();
    _catalogSession?.clear();
    _catalogSession = PosterBrowseCatalogSession(
      backend: backend,
      itemLimit: _rowItemLimit,
    );
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
    _catalogLoadCoordinator.clear();
    _catalogSession?.clear();
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

  Future<void> _enterImmersiveMode() async {
    try {
      await _orientationController.enter();
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
    _catalogLoadCoordinator.clear();

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
          final prewarmed = PosterBrowseArtworkPrewarmCache.shared.peek(
            sessionKey: loadKey,
            itemId: card.id,
          );
          displayById[card.id] = _displayBuilder.build(
            card: card,
            itemDetail: prewarmed?.itemDetail,
            seriesDetail: prewarmed?.seriesDetail,
            season: prewarmed?.season,
            resolvedSeriesId: prewarmed?.resolvedSeriesId ?? '',
          );
        }
      }

      _selection.reset();
      _selection.normalizeForRows(
        rows.map((row) => row.items.length).toList(growable: false),
      );

      final firstCatalogIndex = rows.indexWhere(
        (row) => row.kind == PosterBrowseRowKind.catalog,
      );
      final hasContinueWatching =
          rows.isNotEmpty &&
          rows.first.kind == PosterBrowseRowKind.continueWatching &&
          rows.first.items.isNotEmpty;

      setState(() {
        _rows = rows;
        _displayById
          ..clear()
          ..addAll(displayById);
        _loading = false;
        _settledItemId = null;
        if (!hasContinueWatching && firstCatalogIndex >= 0) {
          _selection.selectRow(firstCatalogIndex);
        }
      });

      if (hasContinueWatching) {
        unawaited(
          _warmContinueWatchingRow(
            rowIndex: 0,
            loadGeneration: generation,
            loadKey: loadKey,
          ),
        );
        unawaited(_settle(rowIndex: 0, itemIndex: 0));
        if (firstCatalogIndex >= 0) {
          unawaited(
            _ensureCatalogLoaded(firstCatalogIndex, selectWhenReady: false),
          );
        }
        return;
      }

      if (firstCatalogIndex >= 0) {
        unawaited(
          _ensureCatalogLoaded(firstCatalogIndex, selectWhenReady: true),
        );
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

  Future<void> _ensureCatalogLoaded(
    int rowIndex, {
    required bool selectWhenReady,
  }) async {
    if (rowIndex < 0 || rowIndex >= _rows.length) return;
    final row = _rows[rowIndex];
    if (row.kind != PosterBrowseRowKind.catalog) return;

    if (row.loadState == PosterBrowseRowLoadState.loaded) {
      if (selectWhenReady && row.items.isNotEmpty) {
        _catalogLoadCoordinator.select(row.catalogId);
        await _settle(rowIndex: rowIndex, itemIndex: 0);
      }
      return;
    }

    final session = _catalogSession;
    final loadKey = _loadKey;
    if (session == null || loadKey == null) return;
    final generation = _loadGeneration;
    final catalogId = row.catalogId;

    if (row.loadState != PosterBrowseRowLoadState.loading) {
      setState(() {
        _replaceRow(
          rowIndex,
          row.copyWith(loadState: PosterBrowseRowLoadState.loading),
        );
      });
    }

    final ticket = _catalogLoadCoordinator.acquire(
      catalogId: catalogId,
      selectWhenReady: selectWhenReady,
      load: () => session.load(row.catalogId),
    );
    if (!ticket.ownsCompletion) return;

    try {
      final items = await ticket.future;
      if (!_isCurrentCatalogLoad(
        generation: generation,
        loadKey: loadKey,
        session: session,
        rowIndex: rowIndex,
        catalogId: catalogId,
      )) {
        return;
      }

      setState(() {
        final currentRow = _rows[rowIndex];
        _replaceRow(
          rowIndex,
          currentRow.copyWith(
            items: items,
            loadState: PosterBrowseRowLoadState.loaded,
          ),
        );
        for (final card in items) {
          _displayById.putIfAbsent(
            card.id,
            () => _displayBuilder.build(card: card),
          );
        }
        _selection.normalizeForRows(
          _rows.map((item) => item.items.length).toList(growable: false),
        );
      });

      final shouldSelect = _catalogLoadCoordinator.shouldSelect(catalogId);
      _catalogLoadCoordinator.release(ticket);
      if (shouldSelect && items.isNotEmpty) {
        await _settle(rowIndex: rowIndex, itemIndex: 0);
      }
    } catch (error, stackTrace) {
      if (!_isCurrentCatalogLoad(
        generation: generation,
        loadKey: loadKey,
        session: session,
        rowIndex: rowIndex,
        catalogId: catalogId,
      )) {
        return;
      }
      setState(() {
        _replaceRow(
          rowIndex,
          _rows[rowIndex].copyWith(loadState: PosterBrowseRowLoadState.failed),
        );
      });
      _catalogLoadCoordinator.release(ticket);
      await logSwallowedError(
        action: 'poster browse load catalog',
        error: error,
        stackTrace: stackTrace,
        source: 'poster_browse_screen',
        id: catalogId,
      );
    } finally {
      _catalogLoadCoordinator.release(ticket);
    }
  }

  Future<void> _reloadCatalogsRow(int rowIndex) async {
    if (rowIndex < 0 || rowIndex >= _rows.length) return;
    final row = _rows[rowIndex];
    if (row.kind != PosterBrowseRowKind.catalogIndex ||
        row.loadState != PosterBrowseRowLoadState.failed) {
      return;
    }

    final backend = _backend;
    final loadKey = _loadKey;
    if (backend == null || loadKey == null) return;
    final generation = _loadGeneration;

    setState(() {
      _replaceRow(
        rowIndex,
        row.copyWith(loadState: PosterBrowseRowLoadState.loading),
      );
    });

    try {
      final catalogs = await const PosterBrowseLoader().loadCatalogs(backend);
      if (!_isCurrentCatalogIndexLoad(
        backend: backend,
        generation: generation,
        loadKey: loadKey,
        rowIndex: rowIndex,
      )) {
        return;
      }
      final shouldSelect = PosterBrowseScreenPolicy.shouldSelectReloadedCatalog(
        catalogIndexRow: rowIndex,
        currentSelectedRow: _selection.selectedRow,
      );

      setState(() {
        _rows = replacePosterBrowseCatalogIndexRow(
          rows: _rows,
          rowIndex: rowIndex,
          catalogs: catalogs,
        );
        _selection.normalizeForRows(
          _rows.map((item) => item.items.length).toList(growable: false),
        );
        if (catalogs.isNotEmpty && shouldSelect) {
          _selection.selectRow(rowIndex);
        }
      });

      if (catalogs.isNotEmpty) {
        await _ensureCatalogLoaded(rowIndex, selectWhenReady: shouldSelect);
      }
    } catch (error, stackTrace) {
      if (!_isCurrentCatalogIndexLoad(
        backend: backend,
        generation: generation,
        loadKey: loadKey,
        rowIndex: rowIndex,
      )) {
        return;
      }
      setState(() {
        _replaceRow(
          rowIndex,
          _rows[rowIndex].copyWith(loadState: PosterBrowseRowLoadState.failed),
        );
      });
      await logSwallowedError(
        action: 'poster browse reload catalogs',
        error: error,
        stackTrace: stackTrace,
        source: 'poster_browse_screen',
      );
    }
  }

  bool _isCurrentCatalogIndexLoad({
    required MediaBackend backend,
    required int generation,
    required String loadKey,
    required int rowIndex,
  }) {
    return identical(backend, _backend) &&
        _isCurrentLoad(generation: generation, loadKey: loadKey) &&
        rowIndex >= 0 &&
        rowIndex < _rows.length &&
        _rows[rowIndex].kind == PosterBrowseRowKind.catalogIndex &&
        _rows[rowIndex].loadState == PosterBrowseRowLoadState.loading;
  }

  bool _isCurrentCatalogLoad({
    required int generation,
    required String loadKey,
    required PosterBrowseCatalogSession session,
    required int rowIndex,
    required String catalogId,
  }) {
    return _isCurrentLoad(generation: generation, loadKey: loadKey) &&
        identical(session, _catalogSession) &&
        rowIndex >= 0 &&
        rowIndex < _rows.length &&
        _rows[rowIndex].kind == PosterBrowseRowKind.catalog &&
        _rows[rowIndex].catalogId == catalogId;
  }

  void _replaceRow(int rowIndex, PosterBrowseRow row) {
    final rows = List<PosterBrowseRow>.of(_rows);
    rows[rowIndex] = row;
    _rows = List<PosterBrowseRow>.unmodifiable(rows);
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

  Future<void> _warmContinueWatchingRow({
    required int rowIndex,
    required int loadGeneration,
    required String loadKey,
  }) async {
    if (rowIndex < 0 || rowIndex >= _rows.length) return;
    final row = _rows[rowIndex];
    if (row.kind != PosterBrowseRowKind.continueWatching || row.items.isEmpty) {
      return;
    }
    final enricher = _enricher;
    if (enricher == null) return;

    bool isActive() {
      return _isCurrentLoad(generation: loadGeneration, loadKey: loadKey) &&
          identical(enricher, _enricher);
    }

    await const PosterBrowseRowArtworkWarmup(maxConcurrent: 2).run(
      items: row.items,
      centerIndex: 0,
      load: (card) =>
          _loadEnrichment(enricher: enricher, card: card, loadKey: loadKey),
      isActive: isActive,
      onLoaded: (card, enrichment) {
        if (!isActive()) return;
        final display = _displayBuilder.build(
          card: card,
          itemDetail: enrichment.itemDetail,
          seriesDetail: enrichment.seriesDetail,
          season: enrichment.season,
          resolvedSeriesId: enrichment.resolvedSeriesId,
        );
        setState(() => _displayById[card.id] = display);
      },
      onError: (card, error, stackTrace) {
        unawaited(
          logSwallowedError(
            action: 'poster browse warm continue watching artwork',
            error: error,
            stackTrace: stackTrace,
            source: 'poster_browse_screen',
            id: card.id,
          ),
        );
      },
    );
  }

  Future<PosterBrowseEnrichment> _loadEnrichment({
    required PosterBrowseArtworkEnricher enricher,
    required MediaItemCard card,
    required String loadKey,
  }) {
    return PosterBrowseArtworkPrewarmCache.shared.futureFor(
          sessionKey: loadKey,
          itemId: card.id,
        ) ??
        enricher.enrich(card);
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
    final focused = _focusedItem;
    return PosterBrowseScreenPolicy.settledItemFor<PosterBrowseDisplayItem>(
      settledItemId: _settledItemId,
      focusedItemId: focused?.card.id,
      displayById: _displayById,
      focusedItem: focused,
    );
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
    final requestLoadGeneration = _loadGeneration;
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
    if (row.kind != PosterBrowseRowKind.continueWatching) {
      unawaited(
        enricher.prefetchWindow(
          row.items,
          normalized.itemIndex,
          radius: _backgroundSpec().prefetchRadius,
        ),
      );
    }

    try {
      final enrichment = await _loadEnrichment(
        enricher: enricher,
        card: card,
        loadKey: loadKey,
      );
      if (!mounted || loadKey != _loadKey) return;

      final enrichedDisplay = _displayBuilder.build(
        card: card,
        itemDetail: enrichment.itemDetail,
        seriesDetail: enrichment.seriesDetail,
        season: enrichment.season,
        resolvedSeriesId: enrichment.resolvedSeriesId,
      );

      final decision = PosterBrowseEnrichmentCommitPolicy.resolve(
        requestLoadGeneration: requestLoadGeneration,
        currentLoadGeneration: _loadGeneration,
        requestFocusGeneration: generation,
        currentFocusGeneration: _focusGeneration,
      );
      if (!decision.commitDisplay) return;
      setState(() => _displayById[card.id] = enrichedDisplay);
      if (decision.applyFocusEffects) {
        _precacheNeighbors(
          rowIndex: normalized.rowIndex,
          itemIndex: normalized.itemIndex,
        );
      }
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
    final spec = _backgroundSpec();
    final cacheWidth = spec.cacheWidth;
    for (
      var index = normalized.itemIndex - spec.prefetchRadius;
      index <= normalized.itemIndex + spec.prefetchRadius;
      index += 1
    ) {
      if (index < 0 ||
          index >= row.items.length ||
          index == normalized.itemIndex) {
        continue;
      }
      final display = _displayItemOf(row.items[index]);
      final request = _backgroundRequestOf(resolver, display, spec);
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

  PosterBrowseBackgroundSpec _backgroundSpec() {
    return PosterBrowseBackgroundPolicy.resolve(
      logicalSize: MediaQuery.sizeOf(context),
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
  }

  DetailArtworkResolver _resolver() {
    final nas = context.read<NasProvider>();
    return DetailArtworkResolver(baseUrl: nas.baseUrl, token: nas.token);
  }

  MediaImageRequest _backgroundRequestOf(
    DetailArtworkResolver resolver,
    PosterBrowseDisplayItem item,
    PosterBrowseBackgroundSpec spec,
  ) {
    final preferred = spec.usePosterImages
        ? item.posterImages
        : item.backgroundImages;
    final fallback = spec.usePosterImages
        ? item.backgroundImages
        : item.posterImages;
    return resolver.resolveRefs(
      preferred.isNotEmpty ? preferred : fallback,
      width: spec.requestWidth,
    );
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
    if (rowIndex < 0 || rowIndex >= _rows.length) return;
    final row = _rows[rowIndex];
    final decision = PosterBrowseScreenPolicy.selectionFor(row);

    if (row.kind == PosterBrowseRowKind.catalog) {
      _catalogLoadCoordinator.select(row.catalogId);
    } else {
      _catalogLoadCoordinator.clearSelection();
    }
    if (decision.selectImmediately) {
      setState(() {
        _selection.selectRow(rowIndex);
        if (decision.invalidateFocus) {
          _focusGeneration += 1;
          _settledItemId = null;
        }
      });
    }

    if (decision.reloadCatalogs) {
      unawaited(_reloadCatalogsRow(rowIndex));
      return;
    }

    if (decision.loadCatalog) {
      unawaited(_ensureCatalogLoaded(rowIndex, selectWhenReady: true));
      return;
    }
    if (!decision.settleItem) return;

    final normalized = _normalizeSelection(
      rowIndex: rowIndex,
      itemIndex: _selection.indexForRow(rowIndex),
    );
    if (normalized == null) return;
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
    final backendSession = context.read<BackendSessionProvider>();
    final connection = backendSession.currentConnection;
    final loadKey = buildPosterBrowseBackendSessionKey(
      backendKind: backend.capabilities.kind,
      nasBaseUrl: nas.baseUrl,
      nasToken: nas.token,
      serverBaseUrl: connection?.serverUrl ?? '',
      serverToken: connection?.accessToken ?? '',
    );
    _backend = backend;
    _loadKey = loadKey;
    _catalogLoadCoordinator.clear();
    _catalogSession?.clear();
    _catalogSession = PosterBrowseCatalogSession(
      backend: backend,
      itemLimit: _rowItemLimit,
    );
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
      final artwork = _backgroundRequestOf(
        _resolver(),
        item,
        _backgroundSpec(),
      );
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
          PlayDetailScreen(
            itemGuid: targetId,
            seriesGuid: item.isEpisode ? item.seriesId.trim() : '',
          ),
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
          await _enterImmersiveMode();
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
    final backgroundSpec = _backgroundSpec();
    final settledItem = _settledItem;
    final focusedItem = _focusedItem;
    final background = settledItem == null
        ? MediaImageRequest.empty
        : _backgroundRequestOf(resolver, settledItem, backgroundSpec);

    return DynamicPageThemeScope(
      pageKey: settledItem?.card.id ?? 'poster_browse_empty',
      imageUrl: background.isNotEmpty ? background.urls.first : '',
      imageHeaders: background.headers,
      enabled: dynamicThemeEnabled && settledItem != null,
      intensity: intensity,
      builder: (context, ambientTint) {
        return PopScope(
          onPopInvokedWithResult: (_, __) => unawaited(_restoreOrientation()),
          child: Scaffold(
            backgroundColor: ambientTint ?? Colors.black,
            body: switch (PosterBrowseScreenPolicy.bodyFor(
              loading: _loading,
              hasRows: _rows.isNotEmpty,
              hasFocusedItem: focusedItem != null,
            )) {
              PosterBrowseScreenBody.loading => const Center(
                child: CircularProgressIndicator(),
              ),
              PosterBrowseScreenBody.error => _buildError(l10n),
              PosterBrowseScreenBody.shell => _buildLoadedBody(
                context: context,
                ambientTint: ambientTint,
                resolver: resolver,
                focusedItem: focusedItem,
                settledItem: settledItem,
                background: background,
                backgroundSpec: backgroundSpec,
              ),
            },
          ),
        );
      },
    );
  }

  Widget _buildLoadedBody({
    required BuildContext context,
    required Color? ambientTint,
    required DetailArtworkResolver resolver,
    required PosterBrowseDisplayItem? focusedItem,
    required PosterBrowseDisplayItem? settledItem,
    required MediaImageRequest background,
    required PosterBrowseBackgroundSpec backgroundSpec,
  }) {
    final l10n = AppLocalizations.of(context);
    final presenter = PosterBrowseTextPresenter(l10n: l10n);
    final secondaryLabel = focusedItem == null
        ? ''
        : presenter.secondaryLabel(focusedItem);
    final metaWidgets = focusedItem == null
        ? const <Widget>[]
        : _buildMetaWidgets(presenter.metaTexts(focusedItem));
    final logoRequest = focusedItem == null
        ? MediaImageRequest.empty
        : _logoRequestOf(resolver, focusedItem);
    final selectedRow = clampPosterBrowseIndex(
      _selection.selectedRow,
      _rows.length,
    );
    final focusedIndex = _focusedIndexForRow(selectedRow);
    final useMobileLayout = PosterBrowseWindowProfile.useMobileLayout(
      MediaQuery.sizeOf(context),
    );

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: KeyedSubtree(
            key: ValueKey<String>(
              settledItem?.card.id ?? 'poster_browse_empty',
            ),
            child: background.isNotEmpty
                ? _buildBackdropImage(background, backgroundSpec)
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
        useMobileLayout
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
                onRetryCurrentRow: () => _handleSelectRow(selectedRow),
                onPlay: focusedItem == null
                    ? () {}
                    : () => unawaited(_play(focusedItem)),
                onDetail: focusedItem == null
                    ? () {}
                    : () => unawaited(_openDetail(focusedItem)),
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
                onRetryCurrentRow: () => _handleSelectRow(selectedRow),
                onPlay: focusedItem == null
                    ? () {}
                    : () => unawaited(_play(focusedItem)),
                onDetail: focusedItem == null
                    ? () {}
                    : () => unawaited(_openDetail(focusedItem)),
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

  Widget _buildBackdropImage(
    MediaImageRequest backdrop,
    PosterBrowseBackgroundSpec spec,
  ) {
    return _PosterBrowseBackdrop(
      urls: backdrop.urls,
      headers: backdrop.headers,
      cacheWidth: spec.cacheWidth,
      fit: spec.fit,
      alignment: spec.alignment,
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
    required this.fit,
    required this.alignment,
  });

  final List<String> urls;
  final Map<String, String> headers;
  final int cacheWidth;
  final BoxFit fit;
  final Alignment alignment;

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
        fit: widget.fit,
        alignment: widget.alignment,
        filterQuality: FilterQuality.medium,
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
