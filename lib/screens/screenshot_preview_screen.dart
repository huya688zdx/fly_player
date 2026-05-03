import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/storage_access_service.dart';
import '../theme/app_theme.dart';
import '../ui/adaptive_text.dart';
import '../ui/app_transitions.dart';
import '../ui/player_pane_host_scope.dart';
import '../ui/secondary_host_navigation.dart';
import '../utils/app_confirm_dialog.dart';
import '../utils/app_top_tip.dart';
import '../services/parallel_host_bridge.dart';

class ScreenshotPreviewScreen extends StatefulWidget {
  const ScreenshotPreviewScreen({super.key});

  @override
  State<ScreenshotPreviewScreen> createState() =>
      _ScreenshotPreviewScreenState();
}

class ScreenshotLightboxRouteScreen extends StatelessWidget {
  static const String routePath = '/screen/screenshot/lightbox';
  static const String _payloadTokenKey = 'payloadToken';
  static const MethodChannel _embeddingChannel = MethodChannel(
    'fly_player/embedding',
  );

  final ScreenshotLibraryItem? item;
  final String? payloadToken;

  const ScreenshotLightboxRouteScreen({
    super.key,
    this.item,
    this.payloadToken,
  });

  static String routeNameForItem(ScreenshotLibraryItem item) {
    return Uri(
      path: routePath,
      queryParameters: <String, String>{
        'id': item.id,
        'name': item.name,
        'sourceKind': item.sourceKind,
        'locationLabel': item.locationLabel,
        'formatKind': item.formatKind,
        'isHdr': '${item.isHdr}',
        'sizeBytes': '${item.sizeBytes}',
        'modifiedAtMs': '${item.modifiedAt.millisecondsSinceEpoch}',
        'isScoped': '${item.isScoped}',
        'pathOrIdentifier': item.pathOrIdentifier,
      },
    ).toString();
  }

  static String routeNameForPayloadToken(String token) {
    return Uri(
      path: routePath,
      queryParameters: <String, String>{_payloadTokenKey: token},
    ).toString();
  }

  static String? payloadTokenFromUri(Uri uri) {
    final token = uri.queryParameters[_payloadTokenKey]?.trim() ?? '';
    return token.isEmpty ? null : token;
  }

  static ScreenshotLibraryItem? itemFromUri(Uri uri) {
    final pathOrIdentifier =
        uri.queryParameters['pathOrIdentifier']?.trim() ?? '';
    if (pathOrIdentifier.isEmpty) {
      return null;
    }
    final modifiedAtMs =
        int.tryParse(uri.queryParameters['modifiedAtMs'] ?? '') ?? 0;
    final sizeBytes = int.tryParse(uri.queryParameters['sizeBytes'] ?? '') ?? 0;
    return ScreenshotLibraryItem(
      id: uri.queryParameters['id']?.trim() ?? pathOrIdentifier,
      name: uri.queryParameters['name']?.trim().isNotEmpty == true
          ? uri.queryParameters['name']!.trim()
          : pathOrIdentifier.split(Platform.pathSeparator).last,
      sourceKind: uri.queryParameters['sourceKind']?.trim() ?? 'app',
      locationLabel: uri.queryParameters['locationLabel']?.trim() ?? '',
      formatKind: uri.queryParameters['formatKind']?.trim() ?? '',
      isHdr: uri.queryParameters['isHdr'] == 'true',
      sizeBytes: sizeBytes,
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(modifiedAtMs),
      isScoped: uri.queryParameters['isScoped'] == 'true',
      pathOrIdentifier: pathOrIdentifier,
    );
  }

  static Route<void> buildRoute({
    ScreenshotLibraryItem? item,
    String? payloadToken,
    RouteSettings? settings,
  }) {
    return _ScreenshotLightboxRoute(
      settings: settings,
      builder: (_) =>
          ScreenshotLightboxRouteScreen(item: item, payloadToken: payloadToken),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _ScreenshotLightboxRouteLoader(
      payloadToken: payloadToken,
      fallbackItem: item,
    );
  }
}

class _ScreenshotLightboxRouteLoader extends StatefulWidget {
  final String? payloadToken;
  final ScreenshotLibraryItem? fallbackItem;

  const _ScreenshotLightboxRouteLoader({
    required this.payloadToken,
    required this.fallbackItem,
  });

  @override
  State<_ScreenshotLightboxRouteLoader> createState() =>
      _ScreenshotLightboxRouteLoaderState();
}

class _ScreenshotLightboxRouteLoaderState
    extends State<_ScreenshotLightboxRouteLoader> {
  Future<_ScreenshotLightboxPayload?>? _payloadFuture;

  @override
  void initState() {
    super.initState();
    final token = widget.payloadToken?.trim() ?? '';
    if (token.isNotEmpty) {
      _payloadFuture = _loadPayload(token);
    }
  }

  Future<_ScreenshotLightboxPayload?> _loadPayload(String token) async {
    final raw = await ScreenshotLightboxRouteScreen._embeddingChannel
        .invokeMethod<Map<Object?, Object?>>(
          'consumeFullscreenScreenshotPayload',
          <String, Object?>{'token': token},
        );
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return _ScreenshotLightboxPayload.fromMap(raw);
  }

  @override
  Widget build(BuildContext context) {
    final fallbackItem = widget.fallbackItem;
    final payloadFuture = _payloadFuture;
    if (payloadFuture == null) {
      if (fallbackItem == null) {
        return const SizedBox.shrink();
      }
      return _ScreenshotLightbox(
        items: <ScreenshotLibraryItem>[fallbackItem],
        initialIndex: 0,
      );
    }
    return FutureBuilder<_ScreenshotLightboxPayload?>(
      future: payloadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final payload = snapshot.data;
        if (payload != null && payload.items.isNotEmpty) {
          return _ScreenshotLightbox(
            items: payload.items,
            initialIndex: payload.initialIndex.clamp(
              0,
              payload.items.length - 1,
            ),
          );
        }
        if (fallbackItem != null) {
          return _ScreenshotLightbox(
            items: <ScreenshotLibraryItem>[fallbackItem],
            initialIndex: 0,
          );
        }
        return const Scaffold(backgroundColor: Colors.black);
      },
    );
  }
}

class _ScreenshotLightboxPayload {
  final List<ScreenshotLibraryItem> items;
  final int initialIndex;

  const _ScreenshotLightboxPayload({
    required this.items,
    required this.initialIndex,
  });

  factory _ScreenshotLightboxPayload.fromMap(Map<Object?, Object?> raw) {
    final itemList = (raw['items'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map(
          (item) =>
              ScreenshotLibraryItem.fromMap(item.cast<Object?, Object?>()),
        )
        .toList(growable: false);
    final initialIndex = switch (raw['initialIndex']) {
      final int value => value,
      final num value => value.toInt(),
      _ => 0,
    };
    return _ScreenshotLightboxPayload(
      items: itemList,
      initialIndex: initialIndex,
    );
  }
}

class _ScreenshotPreviewScreenState extends State<ScreenshotPreviewScreen> {
  static const MethodChannel _embeddingChannel = MethodChannel(
    'fly_player/embedding',
  );
  final AppTopTip _topTip = AppTopTip();
  final TextEditingController _searchController = TextEditingController();

  List<ScreenshotLibraryItem> _items = const <ScreenshotLibraryItem>[];
  Set<String> _selectedIds = <String>{};
  String _filter = 'all';
  String _searchQuery = '';
  List<_ScreenshotSortRule> _sortRules = const <_ScreenshotSortRule>[
    _ScreenshotSortRule(
      field: _ScreenshotSortField.modifiedAt,
      descending: true,
    ),
    _ScreenshotSortRule(field: _ScreenshotSortField.fileName),
  ];
  final Map<String, _ScreenshotMetadata> _sortMetadata =
      <String, _ScreenshotMetadata>{};
  bool _loading = true;
  bool _deleting = false;
  bool _hasFileAccess = false;

  bool get _selectionMode => _selectedIds.isNotEmpty;

  List<ScreenshotLibraryItem> get _filteredItems {
    if (_filter == 'all') return _items;
    return _items.where((item) => item.sourceKind == _filter).toList();
  }

  List<ScreenshotLibraryItem> get _visibleItems {
    final normalizedQuery = _searchQuery.trim().toLowerCase();
    final visible = _filteredItems
        .where((item) {
          if (normalizedQuery.isEmpty) return true;
          final haystacks = <String>[
            item.name,
            item.locationLabel,
            item.pathOrIdentifier,
            item.sourceKind,
          ];
          return haystacks.any(
            (value) => value.toLowerCase().contains(normalizedQuery),
          );
        })
        .toList(growable: false);
    visible.sort(_compareItems);
    return visible;
  }

  List<_ScreenshotSection> get _visibleSections {
    final items = _visibleItems;
    if (items.isEmpty) {
      return const <_ScreenshotSection>[];
    }

    final primaryRule = _sortRules.first;
    final sections = <_ScreenshotSection>[];
    String? currentTitle;
    var currentItems = <ScreenshotLibraryItem>[];

    for (final item in items) {
      final title = _sectionTitleFor(item, primaryRule.field);
      if (currentTitle == null || currentTitle != title) {
        if (currentTitle != null) {
          sections.add(
            _ScreenshotSection(
              title: currentTitle,
              items: List<ScreenshotLibraryItem>.unmodifiable(currentItems),
            ),
          );
        }
        currentTitle = title;
        currentItems = <ScreenshotLibraryItem>[item];
      } else {
        currentItems.add(item);
      }
    }

    if (currentTitle != null) {
      sections.add(
        _ScreenshotSection(
          title: currentTitle,
          items: List<ScreenshotLibraryItem>.unmodifiable(currentItems),
        ),
      );
    }
    return sections;
  }

  bool get _needsResolutionMetadata =>
      _sortRules.any((rule) => rule.field == _ScreenshotSortField.resolution);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _topTip.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait<Object?>(<Future<Object?>>[
      StorageAccessService.listScreenshotLibrary(),
      StorageAccessService.hasFileAccess(),
    ]);
    if (!mounted) return;

    final items = results[0] as List<ScreenshotLibraryItem>;
    final selectedIds = _selectedIds.intersection(
      items.map((item) => item.id).toSet(),
    );

    setState(() {
      _items = items;
      _hasFileAccess = results[1] == true;
      _selectedIds = selectedIds;
      _loading = false;
    });
    unawaited(_warmSortMetadata());
  }

  Future<void> _requestFileAccess() async {
    await StorageAccessService.requestFileAccess();
    await _load();
  }

  Future<void> _warmSortMetadata() async {
    if (!_needsResolutionMetadata) {
      return;
    }
    final unresolved = _filteredItems
        .where((item) => !_sortMetadata.containsKey(item.id))
        .toList(growable: false);
    if (unresolved.isEmpty) {
      return;
    }
    final entries = await Future.wait(
      unresolved.map((item) async {
        final metadata = await _ScreenshotMetadataLoader.instance.load(item);
        return MapEntry(item.id, metadata);
      }),
    );
    if (!mounted) return;
    setState(() {
      for (final entry in entries) {
        _sortMetadata[entry.key] = entry.value;
      }
    });
  }

  Future<void> _openSortSheet() async {
    final nextRules = await showModalBottomSheet<List<_ScreenshotSortRule>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ScreenshotSortSheet(initialRules: _sortRules),
    );
    if (nextRules == null || nextRules.isEmpty) {
      return;
    }
    setState(() {
      _sortRules = List<_ScreenshotSortRule>.unmodifiable(nextRules);
    });
    unawaited(_warmSortMetadata());
  }

  Future<void> _openSearchSheet() async {
    final nextQuery = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ScreenshotSearchSheet(initialQuery: _searchQuery),
    );
    if (nextQuery == null) {
      return;
    }
    _searchController.text = nextQuery;
    setState(() => _searchQuery = nextQuery);
  }

  Future<void> _openFilterSheet() async {
    final result = await showModalBottomSheet<_ScreenshotFilterSheetResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ScreenshotFilterSheet(
        filters: _filters(),
        selectedFilter: _filter,
        primarySortRule: _sortRules.first,
      ),
    );
    if (result == null) {
      return;
    }
    if (!mounted) return;
    if (result.openSortEditor) {
      await _openSortSheet();
      return;
    }
    setState(() => _filter = result.filter);
    unawaited(_warmSortMetadata());
  }

  int _compareItems(ScreenshotLibraryItem left, ScreenshotLibraryItem right) {
    for (final rule in _sortRules) {
      final result = _compareByRule(left, right, rule);
      if (result != 0) {
        return result;
      }
    }
    return right.modifiedAt.compareTo(left.modifiedAt);
  }

  int _compareByRule(
    ScreenshotLibraryItem left,
    ScreenshotLibraryItem right,
    _ScreenshotSortRule rule,
  ) {
    late final int base;
    switch (rule.field) {
      case _ScreenshotSortField.modifiedAt:
        base = left.modifiedAt.compareTo(right.modifiedAt);
      case _ScreenshotSortField.fileName:
        base = left.name.toLowerCase().compareTo(right.name.toLowerCase());
      case _ScreenshotSortField.sizeBytes:
        base = left.sizeBytes.compareTo(right.sizeBytes);
      case _ScreenshotSortField.resolution:
        return _compareResolution(left, right, rule.descending);
      case _ScreenshotSortField.directory:
        base = left.locationLabel.toLowerCase().compareTo(
          right.locationLabel.toLowerCase(),
        );
      case _ScreenshotSortField.source:
        base = left.sourceKind.compareTo(right.sourceKind);
    }
    return rule.descending ? -base : base;
  }

  int _compareResolution(
    ScreenshotLibraryItem left,
    ScreenshotLibraryItem right,
    bool descending,
  ) {
    final leftMeta = _sortMetadata[left.id];
    final rightMeta = _sortMetadata[right.id];
    final leftKnown = leftMeta?.hasDimensions == true;
    final rightKnown = rightMeta?.hasDimensions == true;
    if (leftKnown != rightKnown) {
      return leftKnown ? -1 : 1;
    }
    final leftPixels = leftKnown ? leftMeta!.width! * leftMeta.height! : -1;
    final rightPixels = rightKnown ? rightMeta!.width! * rightMeta.height! : -1;
    final base = leftPixels.compareTo(rightPixels);
    return descending ? -base : base;
  }

  String _sectionTitleFor(
    ScreenshotLibraryItem item,
    _ScreenshotSortField field,
  ) {
    switch (field) {
      case _ScreenshotSortField.modifiedAt:
        return _dateSectionLabel(AppLocalizations.of(context), item.modifiedAt);
      case _ScreenshotSortField.fileName:
        return _alphaSectionLabel(item.name);
      case _ScreenshotSortField.sizeBytes:
        return _sizeSectionLabel(AppLocalizations.of(context), item.sizeBytes);
      case _ScreenshotSortField.resolution:
        final metadata = _sortMetadata[item.id];
        if (metadata?.hasDimensions != true) {
          return AppLocalizations.of(context).screenshotUnknownResolution;
        }
        return '${metadata!.width} x ${metadata.height}';
      case _ScreenshotSortField.directory:
        return item.locationLabel;
      case _ScreenshotSortField.source:
        return _sourceLabel(AppLocalizations.of(context), item.sourceKind);
    }
  }

  void _toggleSelection(ScreenshotLibraryItem item) {
    setState(() {
      final next = Set<String>.from(_selectedIds);
      if (!next.add(item.id)) {
        next.remove(item.id);
      }
      _selectedIds = next;
    });
  }

  Future<void> _openViewer(ScreenshotLibraryItem item) async {
    final visibleItems = _visibleItems;
    final initialIndex = visibleItems.indexWhere(
      (entry) => entry.id == item.id,
    );
    if (initialIndex < 0) return;
    final overlayContext =
        Overlay.maybeOf(context, rootOverlay: true)?.context ?? context;
    final rootNavigator = Navigator.of(overlayContext, rootNavigator: true);
    final paneHost = PlayerPaneHostScope.maybeOf(context);
    final hostContext = await ParallelHostBridge.getHostContext();
    if (paneHost != null || hostContext.isSecondaryHost) {
      final handled =
          await _embeddingChannel
              .invokeMethod<bool>('openFullscreenScreenshot', <String, Object?>{
                'items': visibleItems
                    .map((entry) => entry.toMap())
                    .toList(growable: false),
                'initialIndex': initialIndex,
              }) ??
          false;
      if (handled) {
        return;
      }
    }

    await rootNavigator.push<void>(
      _ScreenshotLightboxRoute(
        builder: (_) => _ScreenshotLightbox(
          items: visibleItems,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  Future<void> _deleteSelected() async {
    if (_deleting || _selectedIds.isEmpty) return;

    final selectedItems = _items
        .where((item) => _selectedIds.contains(item.id))
        .toList(growable: false);
    final l10n = AppLocalizations.of(context);
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.screenshotDeleteTitle,
      content: l10n.screenshotDeleteContent(selectedItems.length),
      cancelText: l10n.commonCancel,
      confirmText: l10n.commonDelete,
      confirmColor: context.appColors.danger,
    );
    if (!confirmed || !mounted) return;

    setState(() => _deleting = true);
    try {
      final deletedCount = await StorageAccessService.deleteScreenshotFiles(
        selectedItems,
      );
      if (!mounted) return;

      final removedIds = _selectedIds;
      setState(() {
        _items = _items
            .where((item) => !removedIds.contains(item.id))
            .toList(growable: false);
        _selectedIds = <String>{};
      });

      _topTip.show(
        context,
        message: deletedCount > 0
            ? l10n.screenshotDeletedCount(deletedCount)
            : l10n.screenshotDeleteNone,
        color: deletedCount > 0
            ? context.appColors.success
            : context.appColors.warning,
      );
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
      }
    }
  }

  List<_ScreenshotFilter> _filters() {
    int countFor(String sourceKind) {
      if (sourceKind == 'all') return _items.length;
      return _items.where((item) => item.sourceKind == sourceKind).length;
    }

    return <_ScreenshotFilter>[
      _ScreenshotFilter(
        value: 'all',
        label: AppLocalizations.of(context).commonAll,
        count: countFor('all'),
      ),
      _ScreenshotFilter(
        value: 'pictures',
        label: AppLocalizations.of(context).screenshotSourcePictures,
        count: countFor('pictures'),
      ),
      _ScreenshotFilter(
        value: 'dcim',
        label: AppLocalizations.of(context).screenshotSourceDcim,
        count: countFor('dcim'),
      ),
      _ScreenshotFilter(
        value: 'app',
        label: AppLocalizations.of(context).screenshotSourceApp,
        count: countFor('app'),
      ),
      _ScreenshotFilter(
        value: 'custom',
        label: AppLocalizations.of(context).screenshotSourceCustom,
        count: countFor('custom'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final visibleItems = _visibleItems;
    final visibleSections = _visibleSections;

    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: buildSecondaryHostAppBar(
        context,
        title: Text(
          _selectionMode
              ? l10n.screenshotSelectedCount(_selectedIds.length)
              : l10n.screenshotGalleryTitle,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: AdaptiveText.roleSize(20, role: AdaptiveFontRole.title),
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: <Widget>[
          if (_selectionMode)
            IconButton(
              onPressed: _deleting ? null : _deleteSelected,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          if (_selectionMode)
            IconButton(
              onPressed: () => setState(() => _selectedIds = <String>{}),
              icon: const Icon(Icons.close_rounded),
            ),
          if (!_selectionMode)
            IconButton(
              onPressed: _openSearchSheet,
              icon: Icon(
                _searchQuery.trim().isEmpty
                    ? Icons.search_rounded
                    : Icons.manage_search_rounded,
              ),
            ),
          if (!_selectionMode)
            IconButton(
              onPressed: _openFilterSheet,
              icon: Icon(
                _filter == 'all'
                    ? Icons.tune_rounded
                    : Icons.filter_alt_rounded,
              ),
            ),
          if (!_selectionMode)
            IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              colors.backgroundElevated,
              colors.backgroundBase,
              colors.backgroundBase,
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          child: _loading
              ? Center(child: CircularProgressIndicator(color: colors.accent))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: colors.accent,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: <Widget>[
                      if (visibleItems.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _EmptyGalleryState(
                            hasFileAccess: _hasFileAccess,
                            filter: _filter,
                            searchQuery: _searchQuery,
                            onRequestFileAccess: _requestFileAccess,
                          ),
                        )
                      else
                        SliverList.separated(
                          itemCount: visibleSections.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 24),
                          itemBuilder: (context, index) {
                            final section = visibleSections[index];
                            return Padding(
                              padding: EdgeInsets.fromLTRB(
                                16,
                                index == 0 ? 10 : 0,
                                16,
                                index == visibleSections.length - 1 ? 28 : 0,
                              ),
                              child: _GallerySection(
                                title: section.title,
                                items: section.items,
                                selectedIds: _selectedIds,
                                selectionMode: _selectionMode,
                                onTap: (item) {
                                  if (_selectionMode) {
                                    _toggleSelection(item);
                                  } else {
                                    unawaited(_openViewer(item));
                                  }
                                },
                                onLongPress: _toggleSelection,
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _ScreenshotFilter {
  final String value;
  final String label;
  final int count;

  const _ScreenshotFilter({
    required this.value,
    required this.label,
    required this.count,
  });
}

enum _ScreenshotSortField {
  modifiedAt,
  fileName,
  sizeBytes,
  resolution,
  directory,
  source,
}

class _ScreenshotSortRule {
  final _ScreenshotSortField field;
  final bool descending;

  const _ScreenshotSortRule({required this.field, this.descending = false});

  _ScreenshotSortRule copyWith({
    _ScreenshotSortField? field,
    bool? descending,
  }) {
    return _ScreenshotSortRule(
      field: field ?? this.field,
      descending: descending ?? this.descending,
    );
  }
}

class _ScreenshotSection {
  final String title;
  final List<ScreenshotLibraryItem> items;

  const _ScreenshotSection({required this.title, required this.items});
}

class _ScreenshotFilterSheetResult {
  final String filter;
  final bool openSortEditor;

  const _ScreenshotFilterSheetResult({
    required this.filter,
    this.openSortEditor = false,
  });
}

class _ScreenshotSearchSheet extends StatefulWidget {
  final String initialQuery;

  const _ScreenshotSearchSheet({required this.initialQuery});

  @override
  State<_ScreenshotSearchSheet> createState() => _ScreenshotSearchSheetState();
}

class _ScreenshotSearchSheetState extends State<_ScreenshotSearchSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.only(bottom: bottomInset),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.backgroundElevated,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: colors.borderSubtle),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.borderSubtle,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  l10n.screenshotSearchTitle,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: AdaptiveText.roleSize(
                      18,
                      role: AdaptiveFontRole.title,
                    ),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (value) =>
                      Navigator.of(context).pop(value.trim()),
                  decoration: InputDecoration(
                    hintText: l10n.screenshotSearchHint,
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _controller.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    if (widget.initialQuery.trim().isNotEmpty)
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(''),
                        child: Text(l10n.screenshotClearSearch),
                      ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () =>
                          Navigator.of(context).pop(_controller.text.trim()),
                      child: Text(l10n.commonApply),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScreenshotFilterSheet extends StatelessWidget {
  final List<_ScreenshotFilter> filters;
  final String selectedFilter;
  final _ScreenshotSortRule primarySortRule;

  const _ScreenshotFilterSheet({
    required this.filters,
    required this.selectedFilter,
    required this.primarySortRule,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.backgroundElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.borderSubtle,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                l10n.screenshotFilterSortTitle,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: AdaptiveText.roleSize(
                    18,
                    role: AdaptiveFontRole.title,
                  ),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                l10n.screenshotSourceFilter,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: AdaptiveText.roleSize(
                    12,
                    role: AdaptiveFontRole.body,
                  ),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: filters
                    .map((filter) {
                      final selected = filter.value == selectedFilter;
                      return ChoiceChip(
                        label: Text('${filter.label} ${filter.count}'),
                        selected: selected,
                        onSelected: (_) {
                          Navigator.of(context).pop(
                            _ScreenshotFilterSheetResult(filter: filter.value),
                          );
                        },
                      );
                    })
                    .toList(growable: false),
              ),
              const SizedBox(height: 18),
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () {
                  Navigator.of(context).pop(
                    _ScreenshotFilterSheetResult(
                      filter: selectedFilter,
                      openSortEditor: true,
                    ),
                  );
                },
                child: Ink(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: colors.borderSubtle),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.tune_rounded, color: colors.textPrimary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              l10n.screenshotSortStandard,
                              style: TextStyle(
                                color: colors.textMuted,
                                fontSize: AdaptiveText.roleSize(
                                  11,
                                  role: AdaptiveFontRole.body,
                                ),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l10n.screenshotCurrentSortGroup(
                                _sortFieldLabel(
                                  AppLocalizations.of(context),
                                  primarySortRule.field,
                                ),
                                primarySortRule.descending
                                    ? l10n.commonDescending
                                    : l10n.commonAscending,
                              ),
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: AdaptiveText.roleSize(
                                  13,
                                  role: AdaptiveFontRole.body,
                                ),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: colors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GallerySection extends StatelessWidget {
  final String title;
  final List<ScreenshotLibraryItem> items;
  final Set<String> selectedIds;
  final bool selectionMode;
  final ValueChanged<ScreenshotLibraryItem> onTap;
  final ValueChanged<ScreenshotLibraryItem> onLongPress;

  const _GallerySection({
    required this.title,
    required this.items,
    required this.selectedIds,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 14.0;
        const minWidth = 156.0;
        final columns = (constraints.maxWidth / (minWidth + spacing))
            .floor()
            .clamp(2, 4);
        final cardWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                title,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: AdaptiveText.roleSize(
                    18,
                    role: AdaptiveFontRole.title,
                  ),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Wrap(
              spacing: spacing,
              runSpacing: 16,
              children: items
                  .map((item) {
                    return SizedBox(
                      width: cardWidth,
                      child: AspectRatio(
                        aspectRatio: 0.76,
                        child: _GalleryCard(
                          item: item,
                          selected: selectedIds.contains(item.id),
                          selectionMode: selectionMode,
                          onTap: () => onTap(item),
                          onLongPress: () => onLongPress(item),
                        ),
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
          ],
        );
      },
    );
  }
}

class _ScreenshotSortSheet extends StatefulWidget {
  final List<_ScreenshotSortRule> initialRules;

  const _ScreenshotSortSheet({required this.initialRules});

  @override
  State<_ScreenshotSortSheet> createState() => _ScreenshotSortSheetState();
}

class _ScreenshotSortSheetState extends State<_ScreenshotSortSheet> {
  late List<_ScreenshotSortRule> _rules;

  @override
  void initState() {
    super.initState();
    _rules = widget.initialRules.map((rule) => rule.copyWith()).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final availableFields = _ScreenshotSortField.values
        .where((field) => !_rules.any((rule) => rule.field == field))
        .toList(growable: false);

    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.backgroundElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.borderSubtle,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                l10n.screenshotSortStandard,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: AdaptiveText.roleSize(
                    18,
                    role: AdaptiveFontRole.title,
                  ),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.screenshotSortDescription,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: AdaptiveText.roleSize(
                    12,
                    role: AdaptiveFontRole.body,
                  ),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              ...List<Widget>.generate(_rules.length, (index) {
                final rule = _rules[index];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == _rules.length - 1 ? 0 : 12,
                  ),
                  child: _SortRuleCard(
                    index: index,
                    rule: rule,
                    canMoveUp: index > 0,
                    canMoveDown: index < _rules.length - 1,
                    onFieldChanged: (field) {
                      setState(() {
                        _rules[index] = _rules[index].copyWith(field: field);
                      });
                    },
                    onToggleDirection: () {
                      setState(() {
                        _rules[index] = _rules[index].copyWith(
                          descending: !_rules[index].descending,
                        );
                      });
                    },
                    onMoveUp: index > 0
                        ? () => setState(() {
                            final current = _rules.removeAt(index);
                            _rules.insert(index - 1, current);
                          })
                        : null,
                    onMoveDown: index < _rules.length - 1
                        ? () => setState(() {
                            final current = _rules.removeAt(index);
                            _rules.insert(index + 1, current);
                          })
                        : null,
                    onRemove: _rules.length == 1
                        ? null
                        : () => setState(() => _rules.removeAt(index)),
                    options: <_ScreenshotSortField>[
                      rule.field,
                      ...availableFields,
                    ],
                  ),
                );
              }),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  if (availableFields.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _rules.add(
                            _ScreenshotSortRule(field: availableFields.first),
                          );
                        });
                      },
                      icon: const Icon(Icons.add_rounded),
                      label: Text(l10n.screenshotAddSort),
                    ),
                  FilledButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(List<_ScreenshotSortRule>.unmodifiable(_rules)),
                    child: Text(l10n.screenshotApplySort),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SortRuleCard extends StatelessWidget {
  final int index;
  final _ScreenshotSortRule rule;
  final List<_ScreenshotSortField> options;
  final bool canMoveUp;
  final bool canMoveDown;
  final ValueChanged<_ScreenshotSortField> onFieldChanged;
  final VoidCallback onToggleDirection;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onRemove;

  const _SortRuleCard({
    required this.index,
    required this.rule,
    required this.options,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onFieldChanged,
    required this.onToggleDirection,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceSubtle,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.accent.withValues(alpha: 0.16),
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<_ScreenshotSortField>(
                  initialValue: rule.field,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: options
                      .map((field) {
                        return DropdownMenuItem<_ScreenshotSortField>(
                          value: field,
                          child: Text(_sortFieldLabel(l10n, field)),
                        );
                      })
                      .toList(growable: false),
                  onChanged: (field) {
                    if (field != null) {
                      onFieldChanged(field);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              FilledButton.tonalIcon(
                onPressed: onToggleDirection,
                icon: Icon(
                  rule.descending
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                ),
                label: Text(
                  rule.descending
                      ? l10n.commonDescending
                      : l10n.commonAscending,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: onMoveUp,
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
                tooltip: l10n.screenshotMoveUpPriority,
              ),
              IconButton(
                onPressed: onMoveDown,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                tooltip: l10n.screenshotMoveDownPriority,
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: l10n.screenshotDeleteRule,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyGalleryState extends StatelessWidget {
  final bool hasFileAccess;
  final String filter;
  final String searchQuery;
  final VoidCallback onRequestFileAccess;

  const _EmptyGalleryState({
    required this.hasFileAccess,
    required this.filter,
    required this.searchQuery,
    required this.onRequestFileAccess,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final message = searchQuery.trim().isNotEmpty
        ? l10n.screenshotSearchEmpty(searchQuery)
        : switch (filter) {
            'pictures' => l10n.screenshotEmptyPictures,
            'dcim' => l10n.screenshotEmptyDcim,
            'app' => l10n.screenshotEmptyApp,
            'custom' => l10n.screenshotEmptyCustom,
            _ => l10n.screenshotEmptyDefault,
          };

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.surfaceSubtle,
                border: Border.all(color: colors.borderSubtle),
              ),
              child: Icon(
                Icons.photo_library_outlined,
                size: 30,
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: AdaptiveText.roleSize(
                  14,
                  role: AdaptiveFontRole.body,
                ),
                height: 1.55,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.screenshotRefreshHint,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textMuted,
                fontSize: AdaptiveText.roleSize(
                  12,
                  role: AdaptiveFontRole.body,
                ),
              ),
            ),
            if (!hasFileAccess &&
                (filter == 'all' ||
                    filter == 'pictures' ||
                    filter == 'dcim')) ...<Widget>[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onRequestFileAccess,
                icon: const Icon(Icons.perm_media_outlined),
                label: Text(l10n.screenshotAuthorizePublicDirectories),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GalleryCard extends StatelessWidget {
  final ScreenshotLibraryItem item;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _GalleryCard({
    required this.item,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: colors.surfaceSubtle,
            border: Border.all(
              color: selected ? colors.accent : colors.borderSubtle,
              width: selected ? 1.8 : 1,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: colors.overlayScrim.withValues(alpha: 0.12),
                blurRadius: 22,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(27),
                child: _ScreenshotImage(item: item, fit: BoxFit.cover),
              ),
              if (item.isHdr)
                Positioned(
                  top: 12,
                  left: 12,
                  child: _MetaPill(label: _formatBadgeLabel(l10n, item)),
                ),
              Positioned(
                top: 12,
                right: 12,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? colors.accent
                        : colors.overlayScrim.withValues(
                            alpha: selectionMode ? 0.72 : 0.46,
                          ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.44),
                    ),
                  ),
                  child: Icon(
                    selected
                        ? Icons.check_rounded
                        : selectionMode
                        ? Icons.radio_button_unchecked_rounded
                        : Icons.open_in_full_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final String label;

  const _MetaPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withValues(alpha: 0.12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ScreenshotImage extends StatefulWidget {
  final ScreenshotLibraryItem item;
  final BoxFit fit;

  const _ScreenshotImage({required this.item, required this.fit});

  @override
  State<_ScreenshotImage> createState() => _ScreenshotImageState();
}

class _ScreenshotImageState extends State<_ScreenshotImage> {
  Future<Uint8List?>? _bytesFuture;

  @override
  void initState() {
    super.initState();
    if (widget.item.isScoped) {
      _bytesFuture = StorageAccessService.readScreenshotFileBytes(
        sourceKind: widget.item.sourceKind,
        pathOrIdentifier: widget.item.pathOrIdentifier,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    if (!widget.item.isScoped) {
      return Image.file(
        File(widget.item.pathOrIdentifier),
        fit: widget.fit,
        errorBuilder: (_, __, ___) => ColoredBox(color: colors.surfaceStrong),
      );
    }

    return FutureBuilder<Uint8List?>(
      future: _bytesFuture,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          return Image.memory(
            snapshot.data!,
            fit: widget.fit,
            gaplessPlayback: true,
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: colors.accent));
        }
        return ColoredBox(color: colors.surfaceStrong);
      },
    );
  }
}

class _ScreenshotLightboxRoute extends PageRouteBuilder<void> {
  _ScreenshotLightboxRoute({required WidgetBuilder builder, super.settings})
    : super(
        opaque: true,
        barrierDismissible: false,
        barrierColor: Colors.black,
        transitionDuration: AppTransitions.routeEnter,
        reverseTransitionDuration: AppTransitions.routeExit,
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          final scale = Tween<double>(begin: 0.96, end: 1).animate(curved);
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(scale: scale, child: child),
          );
        },
      );
}

class _ScreenshotLightbox extends StatefulWidget {
  final List<ScreenshotLibraryItem> items;
  final int initialIndex;

  const _ScreenshotLightbox({required this.items, required this.initialIndex});

  @override
  State<_ScreenshotLightbox> createState() => _ScreenshotLightboxState();
}

class _ScreenshotLightboxState extends State<_ScreenshotLightbox> {
  late final PageController _controller;
  late int _index;
  bool _chromeVisible = true;
  bool _pageLocked = false;
  bool _zoomLocked = false;
  bool _gestureLocked = false;
  bool _chromeHiddenByZoom = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
    unawaited(_setSystemChromeVisible(true));
  }

  @override
  void dispose() {
    unawaited(_setSystemChromeVisible(true));
    _controller.dispose();
    super.dispose();
  }

  Future<void> _setSystemChromeVisible(bool visible) {
    return SystemChrome.setEnabledSystemUIMode(
      visible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  void _toggleChrome() {
    final next = !_chromeVisible;
    setState(() {
      _chromeVisible = next;
      if (next) {
        _chromeHiddenByZoom = false;
      }
    });
    unawaited(_setSystemChromeVisible(next));
  }

  void _showInfo() {
    final item = widget.items[_index];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appColors.surface,
      builder: (context) {
        final colors = context.appColors;
        final l10n = AppLocalizations.of(context);
        return FutureBuilder<_ScreenshotMetadata>(
          future: _ScreenshotMetadataLoader.instance.load(item),
          builder: (context, snapshot) {
            final metadata = snapshot.data ?? const _ScreenshotMetadata.empty();
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.borderSubtle,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    item.name,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: AdaptiveText.roleSize(
                        18,
                        role: AdaptiveFontRole.title,
                      ),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      _InfoTile(
                        label: l10n.screenshotInfoCategory,
                        value: _sourceLabel(l10n, item.sourceKind),
                      ),
                      _InfoTile(
                        label: l10n.screenshotInfoFormat,
                        value: _formatLabel(l10n, item),
                      ),
                      _InfoTile(
                        label: l10n.screenshotInfoSourceDirectory,
                        value: item.locationLabel,
                      ),
                      _InfoTile(
                        label: l10n.screenshotInfoTakenAt,
                        value: _formatDate(item.modifiedAt),
                      ),
                      _InfoTile(
                        label: l10n.screenshotInfoFileSize,
                        value: _formatBytes(item.sizeBytes),
                      ),
                      _InfoTile(
                        label: l10n.screenshotInfoStorageType,
                        value: item.isScoped
                            ? l10n.screenshotManagedDirectory
                            : l10n.screenshotLocalFile,
                      ),
                      _InfoTile(
                        label: l10n.screenshotInfoResolution,
                        value: metadata.hasDimensions
                            ? '${metadata.width} x ${metadata.height}'
                            : l10n.screenshotLoading,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (item.isHdr)
                    Text(
                      l10n.screenshotUltraHdrNotice,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: AdaptiveText.roleSize(
                          12,
                          role: AdaptiveFontRole.body,
                        ),
                        height: 1.5,
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_index];
    final routeAnimation =
        ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation;
    final overlayAnimation = CurvedAnimation(
      parent: routeAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: overlayAnimation,
        builder: (context, child) {
          final topOffset = Tween<Offset>(
            begin: const Offset(0, -0.06),
            end: Offset.zero,
          ).evaluate(overlayAnimation);
          final bottomOffset = Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).evaluate(overlayAnimation);

          return ColoredBox(
            color: Colors.black.withValues(
              alpha: 0.96 * overlayAnimation.value,
            ),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: FadeTransition(
                    opacity: overlayAnimation,
                    child: PageView.builder(
                      controller: _controller,
                      physics: _pageLocked
                          ? const NeverScrollableScrollPhysics()
                          : const PageScrollPhysics(),
                      itemCount: widget.items.length,
                      onPageChanged: (value) => setState(() => _index = value),
                      itemBuilder: (context, index) {
                        final pageItem = widget.items[index];
                        return _LightboxImageViewport(
                          key: ValueKey<String>(pageItem.id),
                          item: pageItem,
                          onTap: _toggleChrome,
                          onDismissed: () => Navigator.of(context).maybePop(),
                          onInteractionLockChanged: (locked) {
                            if (_gestureLocked == locked) {
                              return;
                            }
                            setState(() {
                              _gestureLocked = locked;
                              _pageLocked = _zoomLocked || _gestureLocked;
                            });
                          },
                          onZoomChanged: (zoomed) {
                            final shouldAutoHide = zoomed && _chromeVisible;
                            final shouldAutoRestore =
                                !zoomed && _chromeHiddenByZoom;
                            if (_zoomLocked == zoomed &&
                                !shouldAutoHide &&
                                !shouldAutoRestore) {
                              return;
                            }
                            setState(() {
                              _zoomLocked = zoomed;
                              _pageLocked = _zoomLocked || _gestureLocked;
                              if (shouldAutoHide) {
                                _chromeVisible = false;
                                _chromeHiddenByZoom = true;
                              } else if (shouldAutoRestore) {
                                _chromeVisible = true;
                                _chromeHiddenByZoom = false;
                              }
                            });
                            if (shouldAutoHide) {
                              unawaited(_setSystemChromeVisible(false));
                            } else if (shouldAutoRestore) {
                              unawaited(_setSystemChromeVisible(true));
                            }
                          },
                        );
                      },
                    ),
                  ),
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 10,
                  left: 12,
                  right: 12,
                  child: IgnorePointer(
                    ignoring: !_chromeVisible,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      opacity: _chromeVisible ? overlayAnimation.value : 0,
                      child: Transform.translate(
                        offset: Offset(
                          0,
                          (_chromeVisible ? topOffset.dy : -0.08) * 140,
                        ),
                        child: Row(
                          children: <Widget>[
                            _LightboxButton(
                              icon: Icons.close_rounded,
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    item.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.locationLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFD0D4DB),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (item.isHdr) ...<Widget>[
                                    const SizedBox(height: 6),
                                    _MetaPill(
                                      label: _formatBadgeLabel(
                                        AppLocalizations.of(context),
                                        item,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            _LightboxButton(
                              icon: Icons.info_outline_rounded,
                              onPressed: _showInfo,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).padding.bottom + 18,
                  child: IgnorePointer(
                    ignoring: !_chromeVisible,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      opacity: _chromeVisible ? overlayAnimation.value : 0,
                      child: Transform.translate(
                        offset: Offset(
                          0,
                          (_chromeVisible ? bottomOffset.dy : 0.08) * 140,
                        ),
                        child: FutureBuilder<_ScreenshotMetadata>(
                          future: _ScreenshotMetadataLoader.instance.load(item),
                          builder: (context, snapshot) {
                            final metadata = snapshot.data;
                            final l10n = AppLocalizations.of(context);
                            return DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(22),
                                color: Colors.black.withValues(alpha: 0.42),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.12),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  12,
                                  14,
                                  14,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: <Widget>[
                                        _MetaPill(
                                          label: _sourceLabel(
                                            l10n,
                                            item.sourceKind,
                                          ),
                                        ),
                                        _MetaPill(
                                          label: _formatLabel(l10n, item),
                                        ),
                                        _MetaPill(
                                          label: _formatDate(item.modifiedAt),
                                        ),
                                        _MetaPill(
                                          label: _formatBytes(item.sizeBytes),
                                        ),
                                        if (metadata?.hasDimensions == true)
                                          _MetaPill(
                                            label:
                                                '${metadata!.width} x ${metadata.height}',
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      item.locationLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFFE6E9EF),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LightboxImageViewport extends StatefulWidget {
  final ScreenshotLibraryItem item;
  final VoidCallback onTap;
  final VoidCallback onDismissed;
  final ValueChanged<bool> onZoomChanged;
  final ValueChanged<bool> onInteractionLockChanged;

  const _LightboxImageViewport({
    super.key,
    required this.item,
    required this.onTap,
    required this.onDismissed,
    required this.onZoomChanged,
    required this.onInteractionLockChanged,
  });

  @override
  State<_LightboxImageViewport> createState() => _LightboxImageViewportState();
}

class _LightboxImageViewportState extends State<_LightboxImageViewport>
    with SingleTickerProviderStateMixin {
  late final TransformationController _transformController;
  late final AnimationController _zoomAnimationController;
  Animation<Matrix4>? _zoomAnimation;
  late final Future<_ScreenshotMetadata> _metadataFuture;
  TapDownDetails? _doubleTapDetails;
  Offset _dragOffset = Offset.zero;
  bool _isDraggingToDismiss = false;
  bool _isZoomed = false;
  bool _interactionLocked = false;
  int _activePointerCount = 0;
  Offset? _lastInteractionFocalPoint;

  @override
  void initState() {
    super.initState();
    _transformController = TransformationController();
    _metadataFuture = _ScreenshotMetadataLoader.instance.load(widget.item);
    _zoomAnimationController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addListener(() {
          final animation = _zoomAnimation;
          if (animation == null) return;
          _transformController.value = animation.value;
        });
    _transformController.addListener(_handleTransformChanged);
  }

  @override
  void dispose() {
    _transformController
      ..removeListener(_handleTransformChanged)
      ..dispose();
    _zoomAnimationController.dispose();
    super.dispose();
  }

  void _handleTransformChanged() {
    final zoomed = _transformController.value.getMaxScaleOnAxis() > 1.02;
    if (_isZoomed == zoomed) return;
    _isZoomed = zoomed;
    widget.onZoomChanged(zoomed);
  }

  void _setInteractionLocked(bool locked) {
    if (_interactionLocked == locked) return;
    _interactionLocked = locked;
    widget.onInteractionLockChanged(locked);
  }

  void _animateTo(Matrix4 target) {
    _zoomAnimationController.stop();
    _zoomAnimation =
        Matrix4Tween(begin: _transformController.value, end: target).animate(
          CurvedAnimation(
            parent: _zoomAnimationController,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );
    _zoomAnimationController
      ..reset()
      ..forward();
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  void _handleDoubleTap(_ScreenshotMetadata metadata, Size viewportSize) {
    if (_isZoomed) {
      _animateTo(Matrix4.identity());
      return;
    }
    final details = _doubleTapDetails;
    if (details == null) {
      _animateTo(Matrix4.identity()..scaleByDouble(2.2, 2.2, 1, 1));
      return;
    }
    final position = details.localPosition;
    const scale = 2.2;
    final target = _buildZoomTarget(
      viewportSize: viewportSize,
      metadata: metadata,
      focalPoint: position,
      scale: scale,
    );
    _animateTo(target);
  }

  Matrix4 _buildZoomTarget({
    required Size viewportSize,
    required _ScreenshotMetadata metadata,
    required Offset focalPoint,
    required double scale,
  }) {
    if (viewportSize.isEmpty || !metadata.hasDimensions) {
      return Matrix4.identity()..scaleByDouble(scale, scale, 1, 1);
    }
    final fitted = applyBoxFit(
      BoxFit.contain,
      Size(metadata.width!.toDouble(), metadata.height!.toDouble()),
      viewportSize,
    );
    final imageRect = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & viewportSize,
    );
    final clampedPoint = Offset(
      focalPoint.dx.clamp(imageRect.left, imageRect.right),
      focalPoint.dy.clamp(imageRect.top, imageRect.bottom),
    );
    final normalizedX = (clampedPoint.dx - imageRect.left) / imageRect.width;
    final normalizedY = (clampedPoint.dy - imageRect.top) / imageRect.height;
    final targetX =
        viewportSize.width / 2 -
        (imageRect.left + imageRect.width * normalizedX) * scale;
    final targetY =
        viewportSize.height / 2 -
        (imageRect.top + imageRect.height * normalizedY) * scale;
    final minX = viewportSize.width - viewportSize.width * scale;
    final minY = viewportSize.height - viewportSize.height * scale;

    return Matrix4.identity()
      ..translateByDouble(targetX.clamp(minX, 0), targetY.clamp(minY, 0), 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void _handlePointerDown(PointerDownEvent event) {
    _activePointerCount += 1;
    if (_activePointerCount > 1) {
      _setInteractionLocked(true);
      if (_isDraggingToDismiss || _dragOffset != Offset.zero) {
        setState(() {
          _isDraggingToDismiss = false;
          _dragOffset = Offset.zero;
        });
      }
    }
  }

  void _handlePointerUpOrCancel(PointerEvent event) {
    if (_activePointerCount > 0) {
      _activePointerCount -= 1;
    }
    if (_activePointerCount <= 1 && !_isDraggingToDismiss && !_isZoomed) {
      _setInteractionLocked(false);
    }
  }

  void _handleInteractionStart(ScaleStartDetails details) {
    _lastInteractionFocalPoint = details.focalPoint;
    if (_activePointerCount > 1 || _isZoomed) {
      _setInteractionLocked(true);
      if (_isDraggingToDismiss || _dragOffset != Offset.zero) {
        setState(() {
          _isDraggingToDismiss = false;
          _dragOffset = Offset.zero;
        });
      }
      return;
    }
    _setInteractionLocked(true);
    _isDraggingToDismiss = true;
  }

  void _handleInteractionUpdate(ScaleUpdateDetails details) {
    if (_activePointerCount > 1 || details.pointerCount > 1 || _isZoomed) {
      _setInteractionLocked(true);
      if (_isDraggingToDismiss || _dragOffset != Offset.zero) {
        setState(() {
          _isDraggingToDismiss = false;
          _dragOffset = Offset.zero;
        });
      }
      _lastInteractionFocalPoint = details.focalPoint;
      return;
    }
    if (!_isDraggingToDismiss) {
      _lastInteractionFocalPoint = details.focalPoint;
      return;
    }
    final previous = _lastInteractionFocalPoint;
    _lastInteractionFocalPoint = details.focalPoint;
    if (previous == null) return;
    final delta = details.focalPoint - previous;
    setState(() {
      _dragOffset += Offset(delta.dx * 0.1, delta.dy);
    });
  }

  void _handleInteractionEnd(ScaleEndDetails details) {
    _lastInteractionFocalPoint = null;
    if (!_isDraggingToDismiss) {
      if (_activePointerCount <= 1 && !_isZoomed) {
        _setInteractionLocked(false);
      }
      return;
    }
    _isDraggingToDismiss = false;
    final shouldDismiss =
        _dragOffset.dy.abs() > 96 ||
        details.velocity.pixelsPerSecond.dy.abs() > 700;
    _setInteractionLocked(false);
    if (shouldDismiss) {
      widget.onDismissed();
      return;
    }
    setState(() => _dragOffset = Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    final dragFraction = (_dragOffset.dy.abs() / 320).clamp(0.0, 1.0);
    final dragScale = 1 - dragFraction * 0.12;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = constraints.biggest;
        return FutureBuilder<_ScreenshotMetadata>(
          future: _metadataFuture,
          builder: (context, snapshot) {
            final metadata = snapshot.data ?? const _ScreenshotMetadata.empty();
            final imageChild = metadata.hasDimensions
                ? FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: metadata.width!.toDouble(),
                      height: metadata.height!.toDouble(),
                      child: _ScreenshotImage(
                        item: widget.item,
                        fit: BoxFit.fill,
                      ),
                    ),
                  )
                : _ScreenshotImage(item: widget.item, fit: BoxFit.contain);
            return Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _handlePointerDown,
              onPointerUp: _handlePointerUpOrCancel,
              onPointerCancel: _handlePointerUpOrCancel,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTap,
                onDoubleTapDown: _handleDoubleTapDown,
                onDoubleTap: () => _handleDoubleTap(metadata, viewportSize),
                child: Center(
                  child: AnimatedContainer(
                    duration: _isDraggingToDismiss
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    transform: Matrix4.identity()
                      ..translateByDouble(_dragOffset.dx, _dragOffset.dy, 0, 1)
                      ..scaleByDouble(dragScale, dragScale, 1, 1),
                    child: InteractiveViewer(
                      transformationController: _transformController,
                      constrained: false,
                      clipBehavior: Clip.none,
                      boundaryMargin: const EdgeInsets.all(240),
                      minScale: 1.0,
                      maxScale: 5.0,
                      onInteractionStart: _handleInteractionStart,
                      onInteractionUpdate: _handleInteractionUpdate,
                      onInteractionEnd: _handleInteractionEnd,
                      child: SizedBox(
                        width: viewportSize.width,
                        height: viewportSize.height,
                        child: Center(child: imageChild),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _LightboxButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _LightboxButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.34),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;

  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      constraints: const BoxConstraints(minWidth: 132, maxWidth: 220),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: colors.surfaceSubtle,
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: AdaptiveText.roleSize(11, role: AdaptiveFontRole.body),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: AdaptiveText.roleSize(13, role: AdaptiveFontRole.title),
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScreenshotMetadata {
  final int? width;
  final int? height;

  const _ScreenshotMetadata({required this.width, required this.height});

  const _ScreenshotMetadata.empty() : width = null, height = null;

  bool get hasDimensions => width != null && height != null;
}

class _ScreenshotMetadataLoader {
  _ScreenshotMetadataLoader._();

  static final _ScreenshotMetadataLoader instance =
      _ScreenshotMetadataLoader._();

  final Map<String, Future<_ScreenshotMetadata>> _cache =
      <String, Future<_ScreenshotMetadata>>{};

  Future<_ScreenshotMetadata> load(ScreenshotLibraryItem item) {
    return _cache.putIfAbsent(item.id, () => _read(item));
  }

  Future<_ScreenshotMetadata> _read(ScreenshotLibraryItem item) async {
    try {
      final Uint8List? bytes;
      if (item.isScoped) {
        bytes = await StorageAccessService.readScreenshotFileBytes(
          sourceKind: item.sourceKind,
          pathOrIdentifier: item.pathOrIdentifier,
        );
      } else {
        bytes = await File(item.pathOrIdentifier).readAsBytes();
      }

      if (bytes == null || bytes.isEmpty) {
        return const _ScreenshotMetadata.empty();
      }

      final image = await decodeImageFromList(bytes);
      final metadata = _ScreenshotMetadata(
        width: image.width,
        height: image.height,
      );
      image.dispose();
      return metadata;
    } catch (_) {
      return const _ScreenshotMetadata.empty();
    }
  }
}

String _sourceLabel(AppLocalizations l10n, String sourceKind) {
  return switch (sourceKind) {
    'pictures' => l10n.screenshotSourcePictures,
    'dcim' => l10n.screenshotSourceDcim,
    'custom' => l10n.screenshotSourceCustom,
    _ => l10n.screenshotSourceApp,
  };
}

String _formatLabel(AppLocalizations l10n, ScreenshotLibraryItem item) {
  if (item.isHdr) {
    return 'Ultra HDR JPEG';
  }
  return switch (item.formatKind.trim()) {
    'jpeg' => 'JPEG',
    'png' => 'PNG',
    'webp' => 'WebP',
    'bmp' => 'BMP',
    _ => l10n.screenshotFormatImage,
  };
}

String _formatBadgeLabel(AppLocalizations l10n, ScreenshotLibraryItem item) {
  if (item.isHdr) {
    return 'Ultra HDR';
  }
  return _formatLabel(l10n, item);
}

String _sortFieldLabel(AppLocalizations l10n, _ScreenshotSortField field) {
  return switch (field) {
    _ScreenshotSortField.modifiedAt => l10n.screenshotSortDate,
    _ScreenshotSortField.fileName => l10n.screenshotSortFileName,
    _ScreenshotSortField.sizeBytes => l10n.screenshotSortSize,
    _ScreenshotSortField.resolution => l10n.screenshotSortResolution,
    _ScreenshotSortField.directory => l10n.screenshotSortDirectory,
    _ScreenshotSortField.source => l10n.screenshotSortSource,
  };
}

String _dateSectionLabel(AppLocalizations l10n, DateTime value) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final current = DateTime(value.year, value.month, value.day);
  final diff = today.difference(current).inDays;
  if (diff == 0) return l10n.screenshotDateToday;
  if (diff == 1) return l10n.screenshotDateYesterday;
  if (diff == 2) return l10n.screenshotDateBeforeYesterday;
  return l10n.screenshotMonthDay(value.month, value.day);
}

String _alphaSectionLabel(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return '#';
  final head = trimmed[0].toUpperCase();
  return RegExp(r'[A-Z]').hasMatch(head) ? head : '#';
}

String _sizeSectionLabel(AppLocalizations l10n, int bytes) {
  if (bytes >= 1024 * 1024 * 10) return l10n.screenshotSizeOver10Mb;
  if (bytes >= 1024 * 1024) return '1 MB - 10 MB';
  if (bytes >= 1024 * 100) return '100 KB - 1 MB';
  return l10n.screenshotSizeUnder100Kb;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}

String _formatDate(DateTime value) {
  String two(int input) => input.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}
