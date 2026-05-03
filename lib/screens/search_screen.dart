import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/feiniu_api.dart';
import '../controllers/media_item_action_sheet_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/media_library_item.dart';
import '../providers/nas_provider.dart';
import '../services/embedded_detail_launcher.dart';
import '../theme/app_theme.dart';
import '../ui/app_transitions.dart';
import '../ui/layout_adaptive.dart';
import '../ui/media_poster_card.dart';
import '../utils/api_url_helper.dart';
import '../utils/app_localization_lookup.dart';
import '../utils/async_action_guard.dart';
import '../utils/app_exception.dart';
import '../widgets/common/app_error_state.dart';
import 'person_detail_screen.dart';
import 'play_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  final Map<String, dynamic> initialLocaleMap;
  final bool secondaryHost;

  const SearchScreen({
    super.key,
    this.initialLocaleMap = const <String, dynamic>{},
    this.secondaryHost = false,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const Duration _searchDebounce = Duration(milliseconds: 260);
  static const int _maxHistoryCount = 12;
  static const String _historyKeyPrefix = 'search_history_v1';

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  Timer? _debounceTimer;
  Map<String, dynamic> _localeMap = <String, dynamic>{};
  List<MediaLibraryItem> _results = const <MediaLibraryItem>[];
  List<String> _history = const <String>[];
  String _query = '';
  bool _isSearching = false;
  AppException? _error;

  @override
  void initState() {
    super.initState();
    _localeMap = Map<String, dynamic>.from(widget.initialLocaleMap);
    unawaited(_init());
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadLocaleIfNeeded();
    await _loadHistory();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
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

  Future<void> _loadLocaleIfNeeded() async {
    if (_localeMap.isNotEmpty) return;
    return;
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

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey());
    if (!mounted) return;
    setState(() {
      _history = const <String>[];
    });
  }

  void _onQueryChanged(String value) {
    final trimmed = value.trim();
    setState(() {
      _query = value;
      _error = null;
      if (trimmed.isEmpty) {
        _results = const <MediaLibraryItem>[];
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
    if (trimmed.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _isSearching = true;
      _error = null;
    });
    try {
      final results = await FeiniuApi(
        context.read<NasProvider>(),
      ).searchList(trimmed);
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

  void _replaceSearchItemLocally(
    String itemGuid,
    MediaLibraryItem Function(MediaLibraryItem item) transform,
  ) {
    if (!mounted) return;
    setState(() {
      _results = _results
          .map((item) => item.guid == itemGuid ? transform(item) : item)
          .toList(growable: false);
    });
  }

  Future<void> _showPosterItemActions(MediaLibraryItem item) async {
    await const MediaItemActionSheetController().show(
      context,
      item: item,
      title: MediaItemActionSheetController.defaultTitle(item),
      localeMap: _localeMap,
      favoriteOnly: _isPersonItem(item),
      initialWatched: item.watched == 1,
      onChanged: (state) {
        _replaceSearchItemLocally(
          item.guid,
          (current) => current.copyWith(watched: state.watched ? 1 : 0),
        );
      },
    );
  }

  bool _isPersonItem(MediaLibraryItem item) {
    return item.type.trim().toLowerCase() == 'person';
  }

  bool _isEpisodeItem(MediaLibraryItem item) {
    return item.type.trim().toLowerCase() == 'episode';
  }

  Future<void> _openItemDetail(MediaLibraryItem item) async {
    if (item.guid.trim().isEmpty) return;
    await AsyncActionGuard.run<void>(
      'search_detail:${item.type.trim().toLowerCase()}:${item.guid.trim()}',
      settleDuration: const Duration(milliseconds: 450),
      action: () async {
        await _saveHistoryEntry(_controller.text);
        if (!mounted) return;
        if (_isPersonItem(item)) {
          await Navigator.of(context).push(
            AppTransitions.leftToRightPageTurnRoute(
              PersonDetailScreen(
                personGuid: item.guid,
                initialName: item.displayTitle,
                initialLocaleMap: _localeMap,
              ),
            ),
          );
          return;
        }
        final provider = context.read<NasProvider>();
        Map<String, dynamic>? initialDetail;
        try {
          initialDetail = await FeiniuApi(
            provider,
          ).getItemDetail(item.guid).timeout(const Duration(milliseconds: 240));
        } catch (_) {}
        if (!mounted) return;
        await Navigator.of(context).push(
          AppTransitions.leftToRightPageTurnRoute(
            PlayDetailScreen(
              itemGuid: item.guid,
              heroTag: null,
              initialItemDetail: initialDetail,
            ),
          ),
        );
      },
    );
  }

  String _yearFromDate(String date) {
    return date.length >= 4 ? date.substring(0, 4) : '';
  }

  String _personSubtitle(MediaLibraryItem item) {
    final count = item.numberOfItem;
    if (count > 0) {
      return _t(
        'layout.subheading.person.items',
        '\u5171 {count} \u4e2a\u4f5c\u54c1',
        params: <String, Object?>{'count': count},
      );
    }
    return _t('common.other.empty', '\u6ca1\u6709\u5185\u5bb9');
  }

  String _cardSubtitle(MediaLibraryItem item) {
    if (_isPersonItem(item)) {
      return _personSubtitle(item);
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
      final epText = _t(
        'layout.subheading.tv.episodes',
        '\u5171 {count} \u96c6',
        params: <String, Object?>{'count': episodeCount},
      );
      return period.isEmpty ? epText : '$epText \u00b7 $period';
    }
    if (seasonCount > 0) {
      final seasonText = _t(
        'layout.subheading.tv.seasons',
        '\u5171 {count} \u5b63',
        params: <String, Object?>{'count': seasonCount},
      );
      return period.isEmpty ? seasonText : '$seasonText \u00b7 $period';
    }
    return period;
  }

  List<String> _posterCandidates(
    String baseUrl,
    String rawPath, {
    int width = 360,
  }) {
    return ApiUrlHelper.imageCandidates(baseUrl, rawPath, width: width);
  }

  Widget _buildHistorySection() {
    if (_history.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _t('layout.search.history', '\u641c\u7d22\u5386\u53f2'),
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              onPressed: _clearHistory,
              icon: Icon(Icons.delete_outline, color: colors.textSecondary),
            ),
          ],
        ),
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
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      entry,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 16,
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

  Widget _buildResultsGrid(NasProvider provider, MediaLayoutProfile layout) {
    final colors = context.appColors;
    if (_query.trim().isEmpty) {
      return _buildHistorySection();
    }
    if (_isSearching) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    if (_error != null) {
      return AppErrorState(
        error: _error!,
        localeMap: _localeMap,
        onRetry: () => _performSearch(_controller.text),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            _t(
              'layout.search.resultCount',
              '{count}\u4e2a\u641c\u7d22\u7ed3\u679c',
              params: <String, Object?>{'count': _results.length},
            ),
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: GridView.builder(
            padding: EdgeInsets.zero,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: layout.categoryGridColumns,
              mainAxisSpacing: layout.itemGap,
              crossAxisSpacing: layout.itemGap,
              mainAxisExtent: layout.categoryGridRowHeight,
            ),
            itemCount: _results.length,
            itemBuilder: (context, index) {
              final item = _results[index];
              final rating = double.tryParse(item.voteAverage);
              return MediaPosterCard(
                urls: _posterCandidates(
                  provider.baseUrl,
                  item.poster,
                  width: layout.categoryGridRequestWidth,
                ),
                token: provider.token,
                title: item.displayTitle,
                subtitle: _cardSubtitle(item),
                rating: rating,
                resolutions: item.resolutions,
                watched: item.watched == 1,
                imageHeight: layout.categoryGridImageHeight,
                titleFontSize: layout.homePosterTitleFontSize,
                subtitleFontSize: layout.homePosterSubtitleFontSize,
                expandImageToFit: false,
                imageFit: _isEpisodeItem(item) ? BoxFit.contain : BoxFit.cover,
                onTap: () => _openItemDetail(item),
                onLongPress: () {
                  _showPosterItemActions(item);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<NasProvider>();
    final layout = MediaLayoutProfile.of(context);
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: colors.backgroundElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.accent, width: 1.2),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          Icon(
                            Icons.search,
                            color: colors.textSecondary,
                            size: 24,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              onChanged: _onQueryChanged,
                              onSubmitted: (value) =>
                                  unawaited(_performSearch(value)),
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 18,
                              ),
                              decoration: InputDecoration(
                                isCollapsed: true,
                                border: InputBorder.none,
                                hintText: _t(
                                  'layout.search.placeholder',
                                  '\u641c\u7d22',
                                ),
                                hintStyle: TextStyle(
                                  color: colors.textMuted,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          ),
                          if (_controller.text.isNotEmpty)
                            IconButton(
                              onPressed: () {
                                _controller.clear();
                                _onQueryChanged('');
                              },
                              icon: Icon(
                                Icons.cancel,
                                color: colors.textSecondary,
                                size: 24,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: () {
                      unawaited(
                        widget.secondaryHost
                            ? EmbeddedDetailLauncher.closeHostOrPop(context)
                            : Navigator.of(context).maybePop(),
                      );
                    },
                    child: Text(
                      _t('common.actions.cancel', '\u53d6\u6d88'),
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(child: _buildResultsGrid(provider, layout)),
            ],
          ),
        ),
      ),
    );
  }
}
