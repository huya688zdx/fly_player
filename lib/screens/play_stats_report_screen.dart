import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../l10n/generated/app_localizations.dart';
import '../providers/nas_provider.dart';
import '../services/play_stats/play_stats.dart';
import '../theme/app_theme.dart';
import '../ui/adaptive_detail_navigator.dart';
import '../ui/app_transitions.dart';
import '../ui/secondary_host_navigation.dart';
import '../utils/swallowed_error_logger.dart';
import 'play_stats_debug_page.dart';
import 'play_stats_report/play_stats_report_formatters.dart';
import 'play_stats_report/play_stats_report_widgets.dart';

class PlayStatsMetadataMaps {
  final Map<int, String> genreMap;
  final Map<String, String> countryMap;

  const PlayStatsMetadataMaps({
    required this.genreMap,
    required this.countryMap,
  });
}

enum _CollapsedToolbarDock { none, left, right }

class PlayStatsReportScreen extends StatefulWidget {
  final PlayStatsSummaryRepository? summaryRepository;
  final PlayStatsMetadataBackfillService? metadataBackfillService;
  final Future<PlayStatsMetadataMaps> Function(NasProvider provider)?
  metadataLoader;
  final PlayStatsRange initialRange;
  final WidgetBuilder? detailPageBuilder;

  const PlayStatsReportScreen({
    super.key,
    this.summaryRepository,
    this.metadataBackfillService,
    this.metadataLoader,
    this.initialRange = PlayStatsRange.days30,
    this.detailPageBuilder,
  });

  @override
  State<PlayStatsReportScreen> createState() => _PlayStatsReportScreenState();
}

class _PlayStatsReportScreenState extends State<PlayStatsReportScreen> {
  final ScrollController _scrollController = ScrollController();
  static const Size _collapsedToolbarSize = Size(86, 42);
  static const Size _collapsedToolbarDockedSize = Size(12, 64);
  static const double _expandedToolbarHorizontalInset = 16;
  static const double _expandedToolbarTopInset = 8;
  static const double _expandedToolbarVisualHeight = 106;
  static const double _expandedToolbarReservedHeight = 124;
  static const double _collapsedToolbarMargin = 16;
  static const double _collapsedToolbarDockedMargin = 6;
  static const double _collapsedToolbarDockThreshold = 32;
  double _lastScrollOffset = 0;
  Offset? _collapsedToolbarPosition;
  _CollapsedToolbarDock _collapsedToolbarDock = _CollapsedToolbarDock.none;

  late PlayStatsRange _selectedRange;
  PlayStatsReportSnapshot? _snapshot;
  Object? _loadError;
  int _snapshotVersion = 0;
  bool _isInitialLoading = true;
  bool _isRangeLoading = false;
  bool _isRangeToolbarVisible = true;
  bool _metadataBackfillRunning = false;
  Map<int, String> _genreMap = const <int, String>{};
  Map<String, String> _countryMap = const <String, String>{};
  ContentMetric _contentMetric = ContentMetric.genre;

  PlayStatsSummaryRepository get _summaryRepository =>
      widget.summaryRepository ?? PlayStatsService.instance.summaryRepository;

  PlayStatsMetadataBackfillService get _backfillService =>
      widget.metadataBackfillService ??
      PlayStatsService.instance.metadataBackfillService;

  bool get _isBusy => _isInitialLoading || _isRangeLoading;

  @override
  void initState() {
    super.initState();
    _selectedRange = widget.initialRange;
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_loadMetadataMaps());
      unawaited(_loadCurrentRange(initial: true));
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final offset = _scrollController.offset.clamp(0.0, double.infinity);
    final delta = offset - _lastScrollOffset;
    _lastScrollOffset = offset;

    if (offset <= 8) {
      if (!_isRangeToolbarVisible && mounted) {
        setState(() {
          _isRangeToolbarVisible = true;
        });
      }
      return;
    }

    if (delta.abs() < 6) {
      return;
    }

    if (delta > 0 && _isRangeToolbarVisible && mounted) {
      setState(() {
        _isRangeToolbarVisible = false;
      });
    }
  }

  Future<void> _loadCurrentRange({
    bool initial = false,
    bool withBackfill = false,
  }) async {
    final requestRange = _selectedRange;
    final l10n = AppLocalizations.of(context);
    if (mounted) {
      setState(() {
        if (initial && _snapshot == null) {
          _isInitialLoading = true;
        } else {
          _isRangeLoading = true;
        }
        if (_snapshot == null) {
          _loadError = null;
        }
      });
    }

    try {
      final snapshot = await _summaryRepository.loadReportSnapshot(
        l10n: l10n,
        range: requestRange,
      );
      if (!mounted || requestRange != _selectedRange) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
        _loadError = null;
        _isInitialLoading = false;
        _isRangeLoading = false;
        _snapshotVersion += 1;
      });
      await _loadMetadataMaps();
      if (withBackfill) {
        await _runBackfillAndReload(l10n, snapshot, requestRange);
      } else {
        unawaited(_triggerMetadataBackfill(snapshot));
      }
    } catch (error) {
      if (!mounted || requestRange != _selectedRange) {
        return;
      }
      setState(() {
        _loadError = error;
        _isInitialLoading = false;
        _isRangeLoading = false;
      });
    }
  }

  Future<void> _runBackfillAndReload(
    AppLocalizations l10n,
    PlayStatsReportSnapshot snapshot,
    PlayStatsRange requestRange,
  ) async {
    await _triggerMetadataBackfill(snapshot);
    final refreshed = await _summaryRepository.loadReportSnapshot(
      l10n: l10n,
      range: requestRange,
    );
    if (!mounted || requestRange != _selectedRange) {
      return;
    }
    setState(() {
      _snapshot = refreshed;
      _snapshotVersion += 1;
    });
    await _loadMetadataMaps();
  }

  Future<void> _loadMetadataMaps() async {
    final provider = context.read<NasProvider?>();
    if (provider == null || !provider.isConfigured) {
      return;
    }
    try {
      final loader = widget.metadataLoader ?? _defaultMetadataLoader;
      final maps = await loader(provider);
      if (!mounted) {
        return;
      }
      setState(() {
        _genreMap = maps.genreMap;
        _countryMap = maps.countryMap;
      });
    } catch (error, stackTrace) {
      await logSwallowedError(
        action: 'load play stats metadata maps',
        error: error,
        stackTrace: stackTrace,
        source: 'play_stats_report_screen',
      );
    }
  }

  Future<PlayStatsMetadataMaps> _defaultMetadataLoader(
    NasProvider provider,
  ) async {
    final api = FeiniuApi(provider);
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      api.getTagGenresMap(lan: 'zh-CN'),
      api.getTagIso3166Map(lan: 'zh-CN'),
    ]);
    return PlayStatsMetadataMaps(
      genreMap: results[0] as Map<int, String>,
      countryMap: results[1] as Map<String, String>,
    );
  }

  Future<void> _refresh({bool withBackfill = false}) {
    return _loadCurrentRange(withBackfill: withBackfill);
  }

  Future<void> _triggerMetadataBackfill(
    PlayStatsReportSnapshot snapshot,
  ) async {
    final provider = context.read<NasProvider?>();
    if (provider == null ||
        !provider.isConfigured ||
        _metadataBackfillRunning) {
      return;
    }
    final ids = <String>{
      ...snapshot.topVideos.map((item) => item.videoId.trim()),
      ...snapshot.recentHistory.map((item) => item.videoId.trim()),
      ...snapshot.continueWatching.map((item) => item.videoId.trim()),
    }.where((item) => item.isNotEmpty).toList(growable: false);
    if (ids.isEmpty) {
      return;
    }
    setState(() => _metadataBackfillRunning = true);
    try {
      await _backfillService.backfillNow(
        provider: provider,
        preferredVideoIds: ids,
        limit: 12,
      );
    } finally {
      if (mounted) {
        setState(() => _metadataBackfillRunning = false);
      }
    }
  }

  void _openDetailPage() {
    final pageBuilder = widget.detailPageBuilder;
    Navigator.of(context).push(
      AppTransitions.paneCardRoute<void>(
        pageBuilder == null ? const PlayStatsDebugPage() : pageBuilder(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final formatters = PlayStatsReportFormatters(
      l10n: l10n,
      genreMap: _genreMap,
      countryMap: _countryMap,
    );

    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: buildSecondaryHostAppBar(
        context,
        title: Text(l10n.playStatsTitle),
        actions: <Widget>[
          TextButton.icon(
            onPressed: _openDetailPage,
            icon: const Icon(Icons.data_object_rounded, size: 18),
            label: Text(l10n.playStatsReportDetailData),
          ),
          IconButton(
            tooltip: l10n.commonRefresh,
            onPressed: () => _refresh(withBackfill: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[colors.backgroundElevated, colors.backgroundBase],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final collapsedPosition = _resolveCollapsedToolbarPosition(
              constraints.biggest,
            );
            return Stack(
              children: <Widget>[
                Positioned.fill(child: _buildBody(formatters)),
                _buildRangeToolbarOverlay(
                  constraints.biggest,
                  collapsedPosition,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildRangeToolbarOverlay(Size size, Offset collapsedPosition) {
    final colors = context.appColors;
    final isExpanded = _isRangeToolbarVisible;
    final isDocked = _collapsedToolbarDock != _CollapsedToolbarDock.none;
    final collapsedSize = _currentCollapsedToolbarVisualSize;
    final left = isExpanded
        ? _expandedToolbarHorizontalInset
        : collapsedPosition.dx;
    final top = isExpanded ? _expandedToolbarTopInset : collapsedPosition.dy;
    final width = isExpanded
        ? size.width - (_expandedToolbarHorizontalInset * 2)
        : collapsedSize.width;
    final height = isExpanded
        ? _expandedToolbarVisualHeight
        : collapsedSize.height;
    final alignment = isExpanded
        ? Alignment.topCenter
        : switch (_collapsedToolbarDock) {
            _CollapsedToolbarDock.left => Alignment.centerLeft,
            _CollapsedToolbarDock.right => Alignment.centerRight,
            _CollapsedToolbarDock.none => Alignment.center,
          };
    final content = AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      layoutBuilder: (currentChild, previousChildren) =>
          currentChild ?? const SizedBox.shrink(),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: isExpanded
          ? KeyedSubtree(
              key: const ValueKey<String>('range-toolbar-expanded-content'),
              child: _buildExpandedRangeToolbarContent(colors),
            )
          : KeyedSubtree(
              key: ValueKey<String>(
                'range-toolbar-collapsed-${_collapsedToolbarDock.name}',
              ),
              child: isDocked
                  ? _buildDockedCollapsedToolbar(colors)
                  : _buildFloatingCollapsedToolbar(colors),
            ),
    );
    final shell = Material(
      color: Colors.transparent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: alignment,
        clipBehavior: Clip.antiAlias,
        decoration: isExpanded
            ? BoxDecoration(
                color: colors.surface.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colors.borderSubtle),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: colors.overlayScrim.withValues(alpha: 0.1),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              )
            : BoxDecoration(
                gradient: isDocked
                    ? null
                    : LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          colors.surface.withValues(alpha: 0.98),
                          colors.surfaceStrong.withValues(alpha: 0.92),
                        ],
                      ),
                color: isDocked ? Colors.white.withValues(alpha: 0.84) : null,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: isDocked
                      ? Colors.white.withValues(alpha: 0.92)
                      : colors.accent.withValues(alpha: 0.14),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: colors.overlayScrim.withValues(
                      alpha: isDocked ? 0.1 : 0.08,
                    ),
                    blurRadius: isDocked ? 10 : 16,
                    offset: Offset(0, isDocked ? 3 : 6),
                  ),
                ],
              ),
        child: content,
      ),
    );
    final interactiveShell = isExpanded
        ? shell
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => _beginDraggingCollapsedToolbar(size),
            onPanUpdate: (details) {
              setState(() {
                _collapsedToolbarPosition = _clampCollapsedToolbarPosition(
                  size,
                  (_collapsedToolbarPosition ?? collapsedPosition) +
                      details.delta,
                );
              });
            },
            onPanEnd: (_) => _finishDraggingCollapsedToolbar(size),
            onTap: () {
              setState(() {
                _isRangeToolbarVisible = true;
              });
            },
            child: shell,
          );
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      left: left,
      top: top,
      width: width,
      height: height,
      child: interactiveShell,
    );
  }

  bool get _shouldReserveExpandedToolbarSpace {
    if (!_isRangeToolbarVisible) {
      return false;
    }
    if (!_scrollController.hasClients) {
      return true;
    }
    return _scrollController.offset <= 8;
  }

  Offset _resolveCollapsedToolbarPosition(Size size) {
    final collapsedSize = _currentCollapsedToolbarVisualSize;
    final defaultPosition = Offset(
      size.width - collapsedSize.width - _collapsedToolbarMargin,
      12,
    );
    return _clampCollapsedToolbarPosition(
      size,
      _collapsedToolbarPosition ?? defaultPosition,
    );
  }

  Offset _clampCollapsedToolbarPosition(Size size, Offset position) {
    final collapsedSize = _currentCollapsedToolbarVisualSize;
    final horizontalMargin = _collapsedToolbarDock == _CollapsedToolbarDock.none
        ? _collapsedToolbarMargin
        : _collapsedToolbarDockedMargin;
    final maxX = (size.width - collapsedSize.width - horizontalMargin).clamp(
      horizontalMargin,
      double.infinity,
    );
    final maxY =
        (size.height - collapsedSize.height - _collapsedToolbarMargin - 28)
            .clamp(12, double.infinity);
    return Offset(
      position.dx.clamp(horizontalMargin, maxX).toDouble(),
      position.dy.clamp(12, maxY).toDouble(),
    );
  }

  Size get _currentCollapsedToolbarVisualSize =>
      _collapsedToolbarDock == _CollapsedToolbarDock.none
      ? _collapsedToolbarSize
      : _collapsedToolbarDockedSize;

  void _beginDraggingCollapsedToolbar(Size size) {
    if (_collapsedToolbarDock == _CollapsedToolbarDock.none) {
      return;
    }
    setState(() {
      _collapsedToolbarDock = _CollapsedToolbarDock.none;
      _collapsedToolbarPosition = _clampCollapsedToolbarPosition(
        size,
        _expandedPositionForDock(size),
      );
    });
  }

  void _finishDraggingCollapsedToolbar(Size size) {
    final currentPosition =
        _collapsedToolbarPosition ?? _resolveCollapsedToolbarPosition(size);
    final snappedDock = _resolveCollapsedToolbarDock(size, currentPosition);
    setState(() {
      _collapsedToolbarDock = snappedDock;
      _collapsedToolbarPosition = _snapCollapsedToolbarPosition(
        size,
        currentPosition,
        snappedDock,
      );
    });
  }

  Offset _expandedPositionForDock(Size size) {
    final current =
        _collapsedToolbarPosition ?? _resolveCollapsedToolbarPosition(size);
    return switch (_collapsedToolbarDock) {
      _CollapsedToolbarDock.left => Offset(_collapsedToolbarMargin, current.dy),
      _CollapsedToolbarDock.right => Offset(
        size.width - _collapsedToolbarSize.width - _collapsedToolbarMargin,
        current.dy,
      ),
      _CollapsedToolbarDock.none => current,
    };
  }

  _CollapsedToolbarDock _resolveCollapsedToolbarDock(
    Size size,
    Offset position,
  ) {
    final leftDistance = position.dx;
    final rightDistance =
        size.width - position.dx - _collapsedToolbarSize.width;
    if (leftDistance <= _collapsedToolbarDockThreshold) {
      return _CollapsedToolbarDock.left;
    }
    if (rightDistance <= _collapsedToolbarDockThreshold) {
      return _CollapsedToolbarDock.right;
    }
    return _CollapsedToolbarDock.none;
  }

  Offset _snapCollapsedToolbarPosition(
    Size size,
    Offset position,
    _CollapsedToolbarDock dock,
  ) {
    final snapped = switch (dock) {
      _CollapsedToolbarDock.left => Offset(
        _collapsedToolbarDockedMargin,
        position.dy,
      ),
      _CollapsedToolbarDock.right => Offset(
        size.width -
            _collapsedToolbarDockedSize.width -
            _collapsedToolbarDockedMargin,
        position.dy,
      ),
      _CollapsedToolbarDock.none => position,
    };
    return _clampCollapsedToolbarPosition(size, snapped);
  }

  Widget _buildFloatingCollapsedToolbar(AppThemeColors colors) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      key: const ValueKey<String>('range-toolbar-float'),
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactHeight = constraints.maxHeight < 30;
          final tinyHeight = constraints.maxHeight < 24;
          return FittedBox(
            fit: BoxFit.scaleDown,
            child: tinyHeight
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        _selectedRange.label(l10n),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 10.8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 12,
                        color: colors.textSecondary,
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      if (!compactHeight)
                        Container(
                          width: 22,
                          height: 3.5,
                          decoration: BoxDecoration(
                            color: colors.textMuted.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      if (!compactHeight) const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            _selectedRange.label(l10n),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: compactHeight ? 10.8 : 11.4,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: compactHeight ? 12 : 14,
                            color: colors.textSecondary,
                          ),
                        ],
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _buildDockedCollapsedToolbar(AppThemeColors colors) {
    return Container(
      key: ValueKey<String>(
        'range-toolbar-docked-${_collapsedToolbarDock.name}',
      ),
      width: _collapsedToolbarDockedSize.width,
      height: _collapsedToolbarDockedSize.height,
      alignment: Alignment.center,
      child: Container(
        width: 3.5,
        height: 26,
        decoration: BoxDecoration(
          color: colors.backgroundBase.withValues(alpha: 0.38),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  Widget _buildExpandedRangeToolbarContent(AppThemeColors colors) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactHeader = constraints.maxWidth < 210;
          final height = constraints.maxHeight;
          if (height < 28) {
            return const SizedBox.shrink();
          }

          final showHeaderOnly = height < 54;
          final showHeaderAndSelector = height < 82;
          final reveal = ((height - 28) / 78).clamp(0.0, 1.0);
          final headerSelectorGap = height < 84 ? 4.0 : 8.0;
          final selectorHintGap = height < 92 ? 4.0 : 6.0;

          Widget header = Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.playStatsReportRangeTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: compactHeader ? 12 : 12.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                opacity: _isBusy ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !_isBusy,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: compactHeader ? 14 : 44,
                      maxWidth: compactHeader ? 14 : 58,
                    ),
                    child: compactHeader
                        ? SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                              color: colors.accent,
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.8,
                                  color: colors.accent,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  l10n.playStatsReportSwitching,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.textSecondary,
                                    fontSize: 10.8,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          );

          if (showHeaderOnly) {
            return Opacity(opacity: reveal, child: header);
          }

          Widget selector = PlayStatsRangeSelector(
            selectedRange: _selectedRange,
            onChanged: _handleRangeChanged,
            compact: true,
          );

          if (showHeaderAndSelector) {
            return ClipRect(
              child: Opacity(
                opacity: reveal,
                child: SizedBox.expand(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          header,
                          SizedBox(height: headerSelectorGap),
                          selector,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          return ClipRect(
            child: Opacity(
              opacity: reveal,
              child: SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        header,
                        SizedBox(height: headerSelectorGap),
                        selector,
                        SizedBox(height: selectorHintGap),
                        SizedBox(
                          height: 14,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            opacity: _metadataBackfillRunning ? 1 : 0,
                            child: AnimatedSlide(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOutCubic,
                              offset: _metadataBackfillRunning
                                  ? Offset.zero
                                  : const Offset(0, -0.18),
                              child: Row(
                                children: <Widget>[
                                  Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 11,
                                    color: colors.textSecondary,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      l10n.playStatsReportBackfillingMetadata,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: colors.textSecondary,
                                        fontSize: 10.2,
                                      ),
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
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(PlayStatsReportFormatters formatters) {
    if (_isInitialLoading && _snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final snapshot = _snapshot;
    if (snapshot == null) {
      return _buildErrorState();
    }

    return RefreshIndicator(
      onRefresh: () => _refresh(withBackfill: true),
      child: ListView(
        key: const PageStorageKey<String>('play-stats-report-list'),
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: snapshot.isEmpty
            ? <Widget>[
                _buildAnimatedTopSpacer(basePadding: 4),
                const SizedBox(height: 8),
                const PlayStatsEmptyState(),
              ]
            : <Widget>[
                _buildAnimatedTopSpacer(basePadding: 4),
                _buildAnimatedSlot(
                  'hero',
                  PlayStatsHeroCard(
                    overview: snapshot.overview,
                    selectedRange: _selectedRange,
                    formatters: formatters,
                  ),
                ),
                const SizedBox(height: 16),
                _buildAnimatedSlot(
                  'activity',
                  _buildActivitySection(snapshot, formatters),
                ),
                const SizedBox(height: 16),
                _buildAnimatedSlot(
                  'content',
                  _buildContentSection(snapshot, formatters),
                ),
                const SizedBox(height: 16),
                _buildAnimatedSlot(
                  'behavior',
                  _buildBehaviorSection(snapshot, formatters),
                ),
                const SizedBox(height: 16),
                _buildAnimatedSlot(
                  'ranking',
                  _buildRankingSection(snapshot, formatters),
                ),
              ],
      ),
    );
  }

  Widget _buildAnimatedSlot(String section, Widget child) {
    final switchKey = '$section-${_selectedRange.name}-$_snapshotVersion';
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      transitionBuilder: (widget, animation) =>
          FadeTransition(opacity: animation, child: widget),
      child: KeyedSubtree(key: ValueKey<String>(switchKey), child: child),
    );
  }

  Widget _buildErrorState() {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: <Widget>[
        _buildAnimatedTopSpacer(basePadding: 8),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colors.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.playStatsReportLoadFailedTitle,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.playStatsReportErrorMessage(
                  '${_loadError ?? l10n.playStatsReportUnknownError}',
                ),
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => _refresh(withBackfill: true),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l10n.commonRetry),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnimatedTopSpacer({required double basePadding}) {
    final targetHeight = _shouldReserveExpandedToolbarSpace
        ? (_expandedToolbarReservedHeight - basePadding).clamp(
            0,
            double.infinity,
          )
        : 0.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      height: targetHeight.toDouble(),
    );
  }

  Widget _buildActivitySection(
    PlayStatsReportSnapshot data,
    PlayStatsReportFormatters formatters,
  ) {
    final l10n = AppLocalizations.of(context);
    return PlayStatsReportSection(
      title: l10n.playStatsReportActivityTitle,
      subtitle: l10n.playStatsReportActivitySubtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _ActivitySubsection(
            title: l10n.playStatsReportDailyDurationTitle,
            subtitle: l10n.playStatsReportDailyDurationSubtitle,
          ),
          const SizedBox(height: 10),
          PlayStatsLineChartCard(points: data.trends, formatters: formatters),
        ],
      ),
    );
  }

  Widget _buildContentSection(
    PlayStatsReportSnapshot data,
    PlayStatsReportFormatters formatters,
  ) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final palette = PlayStatsReportPalette.of(context);
    final buckets = switch (_contentMetric) {
      ContentMetric.genre => data.genreBuckets,
      ContentMetric.country => data.countryBuckets,
      ContentMetric.year => data.yearBuckets,
    };
    return PlayStatsReportSection(
      title: l10n.playStatsReportContentTitle,
      subtitle: l10n.playStatsReportContentSubtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PlayStatsPieSummary(
            buckets: data.mediaTypeBuckets,
            palette: palette.mediaPieColors,
            centerLabel: l10n.playStatsReportContentShare,
            centerValue: formatters.duration(
              data.overview.totalPlayedMs,
              compact: true,
            ),
            centerValueChild: PlayStatsAnimatedMetricText(
              value: data.overview.totalPlayedMs.toDouble(),
              builder: (value) =>
                  formatters.duration(value.round(), compact: true),
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
              duration: const Duration(milliseconds: 520),
              pulseScale: 1.1,
            ),
            labelBuilder: (bucket) => bucket.label,
            selectedCenterValueBuilder: (bucket) =>
                formatters.duration(bucket.value, compact: true),
            selectedCenterDetailBuilder: (bucket) =>
                formatters.percent(bucket.share, fractionDigits: 0),
          ),
          const SizedBox(height: 18),
          _ContentMetricSelector(
            selected: _contentMetric,
            onChanged: _handleContentMetricChanged,
          ),
          const SizedBox(height: 14),
          AnimatedSize(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeOutCubic,
              transitionBuilder: (widget, animation) {
                final slide = Tween<Offset>(
                  begin: const Offset(0, 0.02),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: widget),
                );
              },
              layoutBuilder: (currentChild, previousChildren) {
                return currentChild ?? const SizedBox.shrink();
              },
              child: KeyedSubtree(
                key: ValueKey<String>(
                  'distribution-${_contentMetric.name}-$_snapshotVersion',
                ),
                child: PlayStatsDistributionBars(
                  buckets: buckets,
                  labelBuilder: (bucket) =>
                      formatters.distributionLabel(bucket, _contentMetric),
                  trailingBuilder: (bucket) =>
                      '${(bucket.share * 100).toStringAsFixed(0)}%',
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.playStatsReportAffinityTitle,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 12),
          PlayStatsRankList(
            items: affinityRankItems(
              data.affinityPeople,
              formatters,
              onTapBuilder: _buildAffinityPersonTap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBehaviorSection(
    PlayStatsReportSnapshot data,
    PlayStatsReportFormatters formatters,
  ) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final palette = PlayStatsReportPalette.of(context);
    return PlayStatsReportSection(
      title: l10n.playStatsReportBehaviorTitle,
      subtitle: l10n.playStatsReportBehaviorSubtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PlayStatsPieSummary(
            buckets: data.behavior.startSourceBuckets,
            palette: palette.behaviorPieColors,
            centerLabel: l10n.playStatsReportStartSource,
            centerValue: l10n.playStatsReportCountTimes(
              data.behavior.totalSessions,
            ),
            centerValueChild: PlayStatsAnimatedMetricText(
              value: data.behavior.totalSessions.toDouble(),
              builder: (value) => l10n.playStatsReportCountTimes(value.round()),
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
              duration: const Duration(milliseconds: 460),
              pulseScale: 1.08,
            ),
            labelBuilder: (bucket) => bucket.label,
            valueBuilder: (bucket) =>
                l10n.playStatsReportCountTimes(bucket.value),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceSubtle,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _BehaviorMetric(
                    label: l10n.playStatsReportCompletionRate,
                    value: formatters.percent(
                      data.behavior.completionRate,
                      fractionDigits: 0,
                    ),
                    subtitle: l10n.playStatsReportSessionRatio(
                      data.behavior.completedSessions,
                      data.behavior.totalSessions,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _BehaviorMetric(
                    label: l10n.playStatsReportTotalActions,
                    value:
                        '${data.behavior.forwardSeekCount + data.behavior.backwardSeekCount}',
                    subtitle: l10n.playStatsReportSeekSummary(
                      data.behavior.forwardSeekCount,
                      data.behavior.backwardSeekCount,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PlayStatsSeekComparison(
            forwardSeekCount: data.behavior.forwardSeekCount,
            backwardSeekCount: data.behavior.backwardSeekCount,
          ),
          const SizedBox(height: 16),
          PlayStatsOpEdRow(
            label: l10n.playStatsReportIntroOp,
            summary: data.behavior.intro,
          ),
          const SizedBox(height: 12),
          PlayStatsOpEdRow(
            label: l10n.playStatsReportOutroEd,
            summary: data.behavior.outro,
          ),
        ],
      ),
    );
  }

  Widget _buildRankingSection(
    PlayStatsReportSnapshot data,
    PlayStatsReportFormatters formatters,
  ) {
    final l10n = AppLocalizations.of(context);
    return PlayStatsReportSection(
      title: l10n.playStatsReportRankingTitle,
      subtitle: l10n.playStatsReportRankingSubtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PlayStatsContinueWatchingStrip(
            items: data.continueWatching,
            formatters: formatters,
          ),
          const SizedBox(height: 16),
          _RankingSubsection(
            title: l10n.playStatsReportAnimeRankingTitle,
            subtitle: l10n.playStatsReportAnimeRankingSubtitle,
          ),
          const SizedBox(height: 10),
          PlayStatsRankList(
            items: animeRankItems(
              data.topAnimes,
              formatters,
              onTapBuilder: _buildAnimeTap,
            ),
          ),
          const SizedBox(height: 16),
          _RankingSubsection(
            title: l10n.playStatsReportVideoRankingTitle,
            subtitle: l10n.playStatsReportVideoRankingSubtitle,
          ),
          const SizedBox(height: 10),
          PlayStatsRankList(
            items: videoRankItems(
              data.topVideos,
              formatters,
              onTapBuilder: _buildVideoTap,
            ),
          ),
          const SizedBox(height: 16),
          _RankingSubsection(
            title: l10n.playStatsReportRecentHistoryTitle,
            subtitle: l10n.playStatsReportRecentHistorySubtitle,
          ),
          const SizedBox(height: 10),
          PlayStatsPagedTimelineList(
            items: data.recentHistory,
            formatters: formatters,
          ),
        ],
      ),
    );
  }

  void _handleRangeChanged(PlayStatsRange range) {
    if (range == _selectedRange || _isRangeLoading) {
      return;
    }
    setState(() {
      _selectedRange = range;
    });
    unawaited(_loadCurrentRange());
  }

  void _handleContentMetricChanged(ContentMetric value) {
    if (value == _contentMetric) {
      return;
    }
    setState(() {
      _contentMetric = value;
    });
  }

  VoidCallback? _buildAffinityPersonTap(PlayStatsAffinityPerson person) {
    if (person.personId.trim().isEmpty) {
      return null;
    }
    return () {
      unawaited(_openAffinityPerson(person));
    };
  }

  Future<void> _openAffinityPerson(PlayStatsAffinityPerson person) {
    return AdaptiveDetailNavigator.open<void>(
      context,
      AdaptiveDetailRequest.person(
        personGuid: person.personId,
        initialName: person.name,
      ),
    );
  }

  VoidCallback? _buildAnimeTap(PlayStatsTopAnime anime) {
    final isMovie = anime.videoKind.trim().toLowerCase() == 'movie';
    if (isMovie && anime.videoId.trim().isEmpty) {
      return null;
    }
    if (!isMovie && anime.animeId.trim().isEmpty) {
      return null;
    }
    return () {
      unawaited(
        isMovie ? _openItemDetail(anime.videoId) : _openAnimeDetail(anime),
      );
    };
  }

  Future<void> _openAnimeDetail(PlayStatsTopAnime anime) {
    return AdaptiveDetailNavigator.open<void>(
      context,
      AdaptiveDetailRequest.item(itemGuid: anime.animeId),
    );
  }

  VoidCallback? _buildVideoTap(PlayStatsTopVideo video) {
    if (video.videoId.trim().isEmpty) {
      return null;
    }
    return () {
      unawaited(_openItemDetail(video.videoId));
    };
  }

  Future<void> _openItemDetail(String itemGuid) {
    return AdaptiveDetailNavigator.open<void>(
      context,
      AdaptiveDetailRequest.item(itemGuid: itemGuid),
    );
  }
}

class _ContentMetricSelector extends StatelessWidget {
  final ContentMetric selected;
  final ValueChanged<ContentMetric> onChanged;

  const _ContentMetricSelector({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return Row(
      children: ContentMetric.values
          .map((metric) {
            final active = metric == selected;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: metric == ContentMetric.values.last ? 0 : 8,
                ),
                child: InkWell(
                  onTap: () => onChanged(metric),
                  borderRadius: BorderRadius.circular(16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: active ? colors.accent : colors.surfaceSubtle,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      switch (metric) {
                        ContentMetric.genre => l10n.playStatsFieldGenreNames,
                        ContentMetric.country =>
                          l10n.playStatsFieldCountryNames,
                        ContentMetric.year => l10n.playStatsFieldYear,
                      },
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: active ? Colors.white : colors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.8,
                      ),
                    ),
                  ),
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

class _ActivitySubsection extends StatelessWidget {
  final String title;
  final String subtitle;

  const _ActivitySubsection({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 12.8,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _RankingSubsection extends StatelessWidget {
  final String title;
  final String subtitle;

  const _RankingSubsection({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
        ),
      ],
    );
  }
}

class _BehaviorMetric extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;

  const _BehaviorMetric({
    required this.label,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 12.4,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 12.2,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}
