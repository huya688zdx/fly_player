import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:flutter/material.dart';
import '../../media_backend/detail/media_season_summary.dart';

import '../../danmaku/models/danmaku_settings.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../playback/bookmarks/bookmark_store.dart';
import '../../playback/playback_file_uri.dart';
import '../../playback/playback_source.dart';
import '../../playback/settings/mpv_settings_l10n.dart';
import '../../playback/settings/mpv_settings_store.dart';
import 'desktop_semantics_safe_slider.dart';
import 'desktop_playback_chapters.dart';
import 'desktop_danmaku_segmenter.dart';

export 'desktop_playback_chapters.dart' show DesktopPlayerChapter;

class DesktopPlayerPanelOption {
  const DesktopPlayerPanelOption({
    required this.value,
    required this.title,
    this.subtitle = '',
    this.selected = false,
  });
  final Object value;
  final String title;
  final String subtitle;
  final bool selected;
}

class DesktopTrackPanel extends StatelessWidget {
  const DesktopTrackPanel({
    super.key,
    required this.title,
    required this.emptyLabel,
    required this.offLabel,
    required this.options,
    required this.onSelected,
    this.onOff,
  });
  final String title, emptyLabel, offLabel;
  final List<DesktopPlayerPanelOption> options;
  final ValueChanged<DesktopPlayerPanelOption> onSelected;
  final VoidCallback? onOff;
  @override
  Widget build(BuildContext context) => _PanelScroll(
    children: [
      _PanelTitle(title, AppLocalizations.of(context).playerTrackPanelSubtitle),
      const SizedBox(height: 16),
      if (onOff != null) ...[
        _OptionCard(offLabel, icon: Icons.block_rounded, onTap: onOff),
        const SizedBox(height: 8),
      ],
      if (options.isEmpty)
        _EmptyPanel(emptyLabel)
      else
        ...options.map(
          (option) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _OptionCard(
              option.title,
              subtitle: option.subtitle,
              selected: option.selected,
              onTap: () => onSelected(option),
            ),
          ),
        ),
    ],
  );
}

class DesktopEpisodePanel extends StatefulWidget {
  const DesktopEpisodePanel({
    super.key,
    required this.title,
    required this.emptyLabel,
    required this.episodes,
    required this.onSelected,
    this.currentItemGuid = '',
    this.seriesTitle = '',
    this.currentSeasonGuid = '',
    this.loadSeasons,
    this.loadSeasonEpisodes,
  });
  final String title, emptyLabel, currentItemGuid, seriesTitle;
  final List<Map<String, dynamic>> episodes;
  final String currentSeasonGuid;
  final Future<List<MediaSeasonSummary>> Function()? loadSeasons;
  final Future<List<Map<String, dynamic>>> Function(String)? loadSeasonEpisodes;
  final ValueChanged<Map<String, dynamic>>? onSelected;
  @override
  State<DesktopEpisodePanel> createState() => _DesktopEpisodePanelState();
}

class _DesktopEpisodePanelState extends State<DesktopEpisodePanel> {
  bool _grid = false;
  final ScrollController _listScrollController = ScrollController();
  final ScrollController _gridScrollController = ScrollController();
  late List<Map<String, dynamic>> _episodes = widget.episodes;
  late String _seasonGuid = widget.currentSeasonGuid;
  List<MediaSeasonSummary> _seasons = const [];
  bool _loading = false;
  bool _positionCurrent = true;
  String? _loadError;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadSeasons();
  }

  @override
  void didUpdateWidget(covariant DesktopEpisodePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentItemGuid != widget.currentItemGuid) {
      _loadGeneration++;
      _seasonGuid = widget.currentSeasonGuid;
      _episodes = widget.episodes;
      _loading = false;
      _loadError = null;
      _positionCurrent = true;
    }
  }

  Future<void> _loadSeasons() async {
    final load = widget.loadSeasons;
    if (load == null) return;

    try {
      final seasons = await load();
      if (!mounted) return;
      setState(() {
        _seasons = seasons;
        _loadError = null;
      });
      if (_episodes.isEmpty && _seasonGuid.isNotEmpty) {
        await _selectSeason(_seasonGuid);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _loadError = AppLocalizations.of(
            context,
          ).playerSeasonListLoadFailedRetry,
        );
      }
    }
  }

  Future<void> _selectSeason(String guid) async {
    final load = widget.loadSeasonEpisodes;
    if (load == null) return;
    final generation = ++_loadGeneration;
    setState(() {
      _seasonGuid = guid;
      _loading = true;
      _loadError = null;
      _episodes = const [];
    });
    try {
      final episodes = await load(guid);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _episodes = episodes;
        _loading = false;
        _positionCurrent = true;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _loadError = AppLocalizations.of(
          context,
        ).playerEpisodeListLoadFailedRetry;
      });
    }
  }

  void _positionCurrentEpisode(BoxConstraints constraints) {
    if (!_positionCurrent || _episodes.isEmpty) return;
    _positionCurrent = false;
    final index = _episodes.indexWhere(_isCurrent);
    final columns = (constraints.maxWidth / 72).ceil().clamp(1, 1000);
    final extent = _grid ? (constraints.maxWidth + 8) / columns : 92.0;
    final row = _grid ? index ~/ columns : index;
    final controller = _grid ? _gridScrollController : _listScrollController;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) return;
      final target = index < 0
          ? 0.0
          : row * extent - (controller.position.viewportDimension - extent) / 2;
      controller.jumpTo(target.clamp(0.0, controller.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _listScrollController.dispose();
    _gridScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      // 浮层宿主已避开窗口标题栏，内部不再重复添加顶部安全区。
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _PanelTitle(widget.title, widget.seriesTitle)),
                _ViewToggle(
                  Icons.view_list_rounded,
                  !_grid,
                  () => setState(() {
                    _grid = false;
                    _positionCurrent = true;
                  }),
                ),
                _ViewToggle(
                  Icons.grid_view_rounded,
                  _grid,
                  () => setState(() {
                    _grid = true;
                    _positionCurrent = true;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_seasons.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                // 选季留在悬停面板内，避免独立菜单路由触发外层移出关闭。
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 76),
                  child: SingleChildScrollView(
                    primary: false,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final season in _seasons)
                          ChoiceChip(
                            label: Text(
                              season.seasonNumber == 0
                                  ? l10n.playerEpisodeSpecialSeason
                                  : l10n.playerEpisodeSeasonTemplate(
                                      season.seasonNumber,
                                    ),
                            ),
                            selected: season.id == _seasonGuid,
                            showCheckmark: false,
                            selectedColor: const Color(0x2963A0FF),
                            backgroundColor: const Color(0x0DFFFFFF),
                            side: BorderSide(
                              color: season.id == _seasonGuid
                                  ? const Color(0x8063A0FF)
                                  : const Color(0x20FFFFFF),
                            ),
                            labelStyle: TextStyle(
                              color: season.id == _seasonGuid
                                  ? const Color(0xFF9BC3FF)
                                  : Colors.white70,
                              fontSize: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            onSelected: (_) {
                              if (season.id != _seasonGuid) {
                                unawaited(_selectSeason(season.id));
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_loadError != null)
              TextButton(
                onPressed: () => unawaited(
                  _seasons.isEmpty
                      ? _loadSeasons()
                      : _selectSeason(_seasonGuid),
                ),
                child: Text(_loadError!),
              ),
            Expanded(
              child: TweenAnimationBuilder<double>(
                key: ValueKey<bool>(_grid),
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 6 * (1 - value)),
                    child: child,
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _positionCurrentEpisode(constraints);
                    return _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _episodes.isEmpty
                        ? _EmptyPanel(widget.emptyLabel)
                        : _grid
                        ? GridView.builder(
                            controller: _gridScrollController,
                            padding: EdgeInsets.zero,
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 64,
                                  childAspectRatio: 1,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                ),
                            itemCount: _episodes.length,
                            itemBuilder: (_, i) => _EpisodeNumberTile(
                              episode: _episodes[i],
                              fallbackNumber: i + 1,
                              current: _isCurrent(_episodes[i]),
                              enabled: widget.onSelected != null,
                              onTap: widget.onSelected == null
                                  ? null
                                  : () => widget.onSelected!(_episodes[i]),
                            ),
                          )
                        : ListView.builder(
                            controller: _listScrollController,
                            padding: EdgeInsets.zero,
                            itemCount: _episodes.length,
                            itemExtent: 92,
                            itemBuilder: (_, i) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _EpisodeCard(
                                _episodes[i],
                                _isCurrent(_episodes[i]),
                                widget.onSelected != null,
                                false,
                                widget.onSelected == null
                                    ? null
                                    : () => widget.onSelected!(_episodes[i]),
                              ),
                            ),
                          );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isCurrent(Map<String, dynamic> e) =>
      '${e['itemGuid'] ?? e['guid'] ?? ''}'.trim() ==
          widget.currentItemGuid.trim() &&
      widget.currentItemGuid.trim().isNotEmpty;
}

class _EpisodeNumberTile extends StatefulWidget {
  const _EpisodeNumberTile({
    required this.episode,
    required this.fallbackNumber,
    required this.current,
    required this.enabled,
    required this.onTap,
  });

  final Map<String, dynamic> episode;
  final int fallbackNumber;
  final bool current;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  State<_EpisodeNumberTile> createState() => _EpisodeNumberTileState();
}

class _EpisodeNumberTileState extends State<_EpisodeNumberTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final shortLabel = '${widget.episode['shortLabel'] ?? ''}'.trim();
    final episodeNumber = '${widget.episode['episodeNumber'] ?? ''}'.trim();
    final label = shortLabel.isNotEmpty
        ? shortLabel
        : (episodeNumber.isNotEmpty
              ? episodeNumber
              : '${widget.fallbackNumber}');
    final watched =
        widget.episode['watched'] == true || widget.episode['watched'] == 1;
    final active = widget.current || _hovered;

    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered && widget.enabled ? 1.04 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: widget.current
                ? const Color(0x2963A0FF)
                : (_hovered
                      ? const Color(0x1FFFFFFF)
                      : const Color(0x0DFFFFFF)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? const Color(0x8063A0FF) : const Color(0x20FFFFFF),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: widget.onTap,
              child: Stack(
                children: <Widget>[
                  Center(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.current
                            ? const Color(0xFF63A0FF)
                            : Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (watched)
                    Positioned(
                      right: 5,
                      bottom: 4,
                      child: Icon(
                        Icons.check_rounded,
                        size: 13,
                        color: widget.current
                            ? const Color(0xFF8DB9FF)
                            : Colors.white54,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DesktopDanmakuSettingsPanel extends StatefulWidget {
  const DesktopDanmakuSettingsPanel({
    super.key,
    required this.settings,
    required this.onChanged,
    this.embedded = false,
  });

  final DanmakuSettings settings;
  final Future<void> Function(DanmakuSettings settings) onChanged;
  final bool embedded;

  @override
  State<DesktopDanmakuSettingsPanel> createState() =>
      _DesktopDanmakuSettingsPanelState();
}

class _DesktopDanmakuSettingsPanelState
    extends State<DesktopDanmakuSettingsPanel> {
  late DanmakuSettings _settings = widget.settings;

  Future<void> _update(DanmakuSettings next) async {
    setState(() => _settings = next);
    await widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: widget.embedded
            ? EdgeInsets.zero
            : const EdgeInsets.fromLTRB(24, 18, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (!widget.embedded) ...<Widget>[
              _SettingsHeader(title: l10n.danmakuSettingsTitle),
              const SizedBox(height: 18),
            ],
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: <Widget>[
                  _SettingsSwitchTile(
                    title: l10n.danmakuScrollTitle,
                    subtitle: l10n.danmakuScrollSubtitle,
                    value: _settings.scrollEnabled,
                    onChanged: (value) =>
                        _update(_settings.copyWith(scrollEnabled: value)),
                  ),
                  const SizedBox(height: 10),
                  _SettingsSwitchTile(
                    title: l10n.danmakuTopTitle,
                    subtitle: l10n.danmakuTopSubtitle,
                    value: _settings.topEnabled,
                    onChanged: (value) =>
                        _update(_settings.copyWith(topEnabled: value)),
                  ),
                  const SizedBox(height: 10),
                  _SettingsSwitchTile(
                    title: l10n.danmakuBottomTitle,
                    subtitle: l10n.danmakuBottomSubtitle,
                    value: _settings.bottomEnabled,
                    onChanged: (value) =>
                        _update(_settings.copyWith(bottomEnabled: value)),
                  ),
                  const SizedBox(height: 10),
                  _SettingsSwitchTile(
                    title: l10n.danmakuKeepColorTitle,
                    subtitle: l10n.danmakuKeepColorSubtitle,
                    value: _settings.colorEnabled,
                    onChanged: (value) =>
                        _update(_settings.copyWith(colorEnabled: value)),
                  ),
                  const SizedBox(height: 10),
                  _SettingsSwitchTile(
                    title: l10n.danmakuHideDuplicateTitle,
                    subtitle: l10n.danmakuHideDuplicateOnceSubtitle,
                    value: _settings.hideDuplicate,
                    onChanged: (value) =>
                        _update(_settings.copyWith(hideDuplicate: value)),
                  ),
                  const SizedBox(height: 10),
                  _SettingsSwitchTile(
                    title: l10n.danmakuAvoidSubtitleArea,
                    subtitle: l10n.danmakuAvoidSubtitleAreaSubtitle,
                    value: _settings.avoidSubtitleArea,
                    onChanged: (value) =>
                        _update(_settings.copyWith(avoidSubtitleArea: value)),
                  ),
                  const SizedBox(height: 10),
                  if (!Platform.isWindows ||
                      DesktopDanmakuSegmenter.isSupported)
                    _SettingsSwitchTile(
                      title: Platform.isWindows
                          ? l10n.danmakuAvoidCenterTitle
                          : l10n.danmakuAvoidCenterAltTitle,
                      subtitle: Platform.isWindows
                          ? l10n.danmakuSubjectMaskSubtitle
                          : l10n.danmakuAvoidCenterAltSubtitle,
                      value: _settings.avoidCenterArea,
                      onChanged: (value) =>
                          _update(_settings.copyWith(avoidCenterArea: value)),
                    ),
                  const SizedBox(height: 10),
                  _SettingsSliderTile(
                    title: l10n.danmakuOpacity,
                    valueLabel: '${(_settings.opacity * 100).round()}%',
                    value: _settings.opacity,
                    min: 0.2,
                    max: 1,
                    divisions: 16,
                    onChanged: (value) => setState(
                      () => _settings = _settings.copyWith(opacity: value),
                    ),
                    onChangeEnd: (value) =>
                        _update(_settings.copyWith(opacity: value)),
                  ),
                  const SizedBox(height: 10),
                  _SettingsSliderTile(
                    title: l10n.danmakuDisplayDensity,
                    valueLabel: '${(_settings.density * 100).round()}%',
                    value: _settings.density,
                    min: 0.2,
                    max: 1,
                    divisions: 16,
                    onChanged: (value) => setState(
                      () => _settings = _settings.copyWith(density: value),
                    ),
                    onChangeEnd: (value) =>
                        _update(_settings.copyWith(density: value)),
                  ),
                  const SizedBox(height: 10),
                  _SettingsSliderTile(
                    title: l10n.danmakuFontSize,
                    valueLabel: '${(_settings.fontScale * 100).round()}%',
                    value: _settings.fontScale,
                    min: 0.6,
                    max: 1.4,
                    divisions: 16,
                    onChanged: (value) => setState(
                      () => _settings = _settings.copyWith(fontScale: value),
                    ),
                    onChangeEnd: (value) =>
                        _update(_settings.copyWith(fontScale: value)),
                  ),
                  const SizedBox(height: 10),
                  _SettingsSliderTile(
                    title: l10n.danmakuFontWeight,
                    valueLabel: _settings.fontThickness.toStringAsFixed(1),
                    value: _settings.fontThickness,
                    min: 0.8,
                    max: 1.4,
                    divisions: 6,
                    onChanged: (value) => setState(
                      () =>
                          _settings = _settings.copyWith(fontThickness: value),
                    ),
                    onChangeEnd: (value) =>
                        _update(_settings.copyWith(fontThickness: value)),
                  ),
                  const SizedBox(height: 10),
                  _SettingsSliderTile(
                    title: l10n.danmakuScrollSpeed,
                    valueLabel: '${_settings.speed.toStringAsFixed(2)}×',
                    value: _settings.speed,
                    min: danmakuSpeedMin,
                    max: danmakuSpeedMax,
                    divisions: danmakuSpeedDivisions,
                    onChanged: (value) => setState(
                      () => _settings = _settings.copyWith(speed: value),
                    ),
                    onChangeEnd: (value) =>
                        _update(_settings.copyWith(speed: value)),
                  ),
                  const SizedBox(height: 10),
                  _SettingsSliderTile(
                    title: l10n.danmakuDisplayArea,
                    valueLabel:
                        '${(_settings.displayAreaRatio * 100).round()}%',
                    value: _settings.displayAreaRatio,
                    min: 0.25,
                    max: 1,
                    divisions: 3,
                    onChanged: (value) => setState(
                      () => _settings = _settings.copyWith(
                        displayAreaRatio: value,
                      ),
                    ),
                    onChangeEnd: (value) =>
                        _update(_settings.copyWith(displayAreaRatio: value)),
                  ),
                  const SizedBox(height: 10),
                  _SettingsSliderTile(
                    title: l10n.danmakuRefreshRate,
                    valueLabel: '${_settings.targetFrameRateHz} Hz',
                    value: _settings.targetFrameRateHz.toDouble(),
                    min: 30,
                    max: 120,
                    divisions: 6,
                    onChanged: (value) => setState(
                      () => _settings = _settings.copyWith(
                        targetFrameRateHz: value.round(),
                      ),
                    ),
                    onChangeEnd: (value) => _update(
                      _settings.copyWith(targetFrameRateHz: value.round()),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DesktopDanmakuSourcePanel extends StatefulWidget {
  const DesktopDanmakuSourcePanel({
    super.key,
    required this.currentSourceLabel,
    required this.commentCount,
    required this.loading,
    required this.initialKeyword,
    this.currentTmdbId = '',
    required this.onLoadSavedSources,
    required this.onSearch,
    required this.onSelectSavedSource,
    required this.onSelectSearchResult,
    required this.onDeleteSavedSource,
    required this.onImportFile,
    this.embedded = false,
    this.onApplied,
  });

  final String currentSourceLabel;
  final int commentCount;
  final bool loading;
  final String initialKeyword;
  final String currentTmdbId;
  final Future<List<Map<String, dynamic>>> Function() onLoadSavedSources;
  final Future<List<Map<String, dynamic>>> Function(String keyword) onSearch;
  final Future<bool> Function(Map<String, dynamic> source) onSelectSavedSource;
  final Future<bool> Function(Map<String, dynamic> result) onSelectSearchResult;
  final Future<void> Function(Map<String, dynamic> source) onDeleteSavedSource;
  final Future<bool> Function() onImportFile;
  final bool embedded;
  final VoidCallback? onApplied;

  @override
  State<DesktopDanmakuSourcePanel> createState() =>
      _DesktopDanmakuSourcePanelState();
}

class _DesktopDanmakuSourcePanelState extends State<DesktopDanmakuSourcePanel> {
  late final TextEditingController _searchController = TextEditingController(
    text: widget.initialKeyword,
  );
  List<Map<String, dynamic>> _savedSources = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _searchResults = const <Map<String, dynamic>>[];
  bool _loadingSources = true;
  bool _searching = false;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSavedSources());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedSources() async {
    if (mounted) setState(() => _loadingSources = true);
    final sources = await widget.onLoadSavedSources();
    if (!mounted) return;
    setState(() {
      _savedSources = sources;
      _loadingSources = false;
    });
  }

  Future<void> _search() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty || _searching) return;
    setState(() => _searching = true);
    final results = await widget.onSearch(keyword);
    if (!mounted) return;
    setState(() {
      _searchResults = results;
      _searching = false;
    });
  }

  void _fillSearch(String value) {
    _searchController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  Future<void> _applySaved(Map<String, dynamic> source) async {
    if (_applying) return;
    setState(() => _applying = true);
    final applied = await widget.onSelectSavedSource(source);
    if (!mounted) return;
    if (applied) {
      _completeApplied();
      return;
    }
    setState(() => _applying = false);
  }

  Future<void> _applySearchResult(Map<String, dynamic> result) async {
    if (_applying) return;
    setState(() => _applying = true);
    final applied = await widget.onSelectSearchResult(result);
    if (!mounted) return;
    if (applied) {
      _completeApplied();
      return;
    }
    setState(() => _applying = false);
  }

  Future<void> _import() async {
    if (_applying) return;
    setState(() => _applying = true);
    final applied = await widget.onImportFile();
    if (!mounted) return;
    if (applied) {
      _completeApplied();
      return;
    }
    setState(() => _applying = false);
  }

  Future<void> _delete(Map<String, dynamic> source) async {
    if (_applying) return;
    await widget.onDeleteSavedSource(source);
    await _loadSavedSources();
  }

  void _completeApplied() {
    final onApplied = widget.onApplied;
    if (onApplied != null) {
      onApplied();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentSource = widget.currentSourceLabel.trim();
    final currentTitle = widget.initialKeyword.trim();
    final currentTmdb = int.tryParse(
      widget.currentTmdbId.trim().replaceFirst(
        RegExp(r'^(?:tm|tt)', caseSensitive: false),
        '',
      ),
    );
    final currentStatus = widget.loading
        ? l10n.danmakuStatusLoading
        : widget.commentCount > 0
        ? l10n.playerDanmakuCountShort(widget.commentCount)
        : l10n.danmakuNoneLoaded;
    return SafeArea(
      child: Padding(
        padding: widget.embedded
            ? EdgeInsets.zero
            : const EdgeInsets.fromLTRB(24, 18, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (!widget.embedded) ...<Widget>[
              _SettingsHeader(title: l10n.danmakuSourceTitle),
              const SizedBox(height: 18),
            ],
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: <Widget>[
                  _SettingsStatusCard(
                    title: l10n.danmakuCurrentSource,
                    value: currentSource.isEmpty
                        ? l10n.playerSourceUnselected
                        : currentSource,
                    description: currentStatus,
                  ),
                  const SizedBox(height: 10),
                  _SettingsMenuTile(
                    title: l10n.danmakuImportLocalTitle,
                    subtitle: l10n.danmakuImportLocalSubtitle,
                    icon: Icons.file_open_rounded,
                    onTap: () => unawaited(_import()),
                  ),
                  const SizedBox(height: 18),
                  _DanmakuSectionTitle(l10n.danmakuSearchSection),
                  const SizedBox(height: 8),
                  Material(
                    color: Colors.transparent,
                    child: TextField(
                      controller: _searchController,
                      onSubmitted: (_) => unawaited(_search()),
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: l10n.danmakuSearchPanelHint,
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: const Color(0x14FFFFFF),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: IconButton(
                          tooltip: l10n.danmakuSearchButton,
                          onPressed: _searching
                              ? null
                              : () => unawaited(_search()),
                          icon: _searching
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: <Widget>[
                      if (currentTitle.isNotEmpty)
                        TextButton(
                          onPressed: () => _fillSearch(currentTitle),
                          child: Text(l10n.danmakuFillCurrentTitle),
                        ),
                      if (currentTmdb != null && currentTmdb > 0)
                        TextButton(
                          onPressed: () => _fillSearch('TMDB:$currentTmdb'),
                          child: Text(l10n.danmakuFillCurrentTmdb),
                        ),
                    ],
                  ),
                  if (_searchResults.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    for (final result in _searchResults) ...<Widget>[
                      _DanmakuSourceTile(
                        title: '${result['title'] ?? '弹弹play'}',
                        subtitle: '${result['subtitle'] ?? ''}',
                        trailing: result['matchesCurrentEpisode'] == true
                            ? l10n.danmakuMatchCurrentEpisode
                            : '',
                        onTap: _applying || _searching
                            ? null
                            : () => unawaited(_applySearchResult(result)),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                  const SizedBox(height: 10),
                  _DanmakuSectionTitle(l10n.danmakuSavedSourcesSection),
                  const SizedBox(height: 8),
                  if (_loadingSources)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (_savedSources.isEmpty)
                    _SettingsStatusCard(
                      title: l10n.danmakuLibraryTitle,
                      value: l10n.danmakuLibraryEmpty,
                      description: l10n.danmakuLibraryHint,
                    )
                  else
                    for (final source in _savedSources) ...<Widget>[
                      _DanmakuSourceTile(
                        title:
                            '${source['label'] ?? source['sourceKey'] ?? ''}',
                        subtitle: _savedSourceSubtitle(source, l10n),
                        selected: source['active'] == true,
                        trailing: source['active'] == true
                            ? l10n.danmakuSourceInUse
                            : '',
                        onTap: _applying
                            ? null
                            : () => unawaited(_applySaved(source)),
                        onDelete: () => unawaited(_delete(source)),
                      ),
                      const SizedBox(height: 8),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _savedSourceSubtitle(
    Map<String, dynamic> source,
    AppLocalizations l10n,
  ) {
    final type = switch ('${source['type'] ?? ''}') {
      'danDanPlay' => l10n.danmakuSourceTypeDanDanPlay,
      'downloadedFile' => l10n.danmakuSourceTypeDownloaded,
      _ => l10n.danmakuSourceTypeLocal,
    };
    final count = (source['commentCount'] as num?)?.toInt() ?? 0;
    final detail = '${source['detail'] ?? ''}'.trim();
    return <String>[
      type,
      if (count > 0) l10n.playerDanmakuCountShort(count),
      if (detail.isNotEmpty) detail,
    ].join(' · ');
  }
}

class _DanmakuSectionTitle extends StatelessWidget {
  const _DanmakuSectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: const TextStyle(
      color: Colors.white60,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _DanmakuSourceTile extends StatelessWidget {
  const _DanmakuSourceTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing = '',
    this.selected = false,
    this.onDelete,
  });

  final String title;
  final String subtitle;
  final String trailing;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => _SettingsCard(
    selected: selected,
    onTap: onTap,
    child: Row(
      children: <Widget>[
        Icon(
          selected ? Icons.check_circle_rounded : Icons.comment_bank_outlined,
          color: selected ? const Color(0xFF9CC4FF) : Colors.white54,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SettingsTileText(title: title, subtitle: subtitle),
        ),
        if (trailing.trim().isNotEmpty) ...<Widget>[
          const SizedBox(width: 10),
          Text(
            trailing,
            style: const TextStyle(color: Color(0xFF9CC4FF), fontSize: 11),
          ),
        ],
        if (onDelete != null) ...<Widget>[
          const SizedBox(width: 6),
          IconButton(
            tooltip: AppLocalizations.of(context).danmakuDeleteSource,
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 19),
            color: Colors.white54,
          ),
        ],
      ],
    ),
  );
}

/// 播放设置面板的页面（层级对齐安卓原生播放页的分组结构）。
enum DesktopPlaybackSettingsPage {
  main,
  videoAdjust,
  advancedMpv,
  playbackBehavior,
  introOutro,
  chapters,
  subtitleStyle,
  bookmarks,
  trackInfo,
  audioAdjust,
  audioEq,
  picturePresets,
  audioPresets,
  danmakuSettings,
  danmakuSources,
}

class DesktopPlaybackSettingsPanel extends StatefulWidget {
  const DesktopPlaybackSettingsPanel({
    super.key,
    required this.source,
    required this.position,
    required this.duration,
    required this.autoPlayEnabled,
    required this.nextEpisodePreloadEnabled,
    required this.aspectRatioMode,
    required this.decoderMode,
    required this.mpvSettings,
    required this.videoAdjustments,
    required this.audioDelaySeconds,
    required this.bookmarks,
    required this.danmakuEnabled,
    required this.danmakuSourceLabel,
    required this.danmakuCommentCount,
    required this.chapters,
    required this.introOutroEnabled,
    required this.introMaxSeconds,
    required this.outroMaxSeconds,
    required this.fixedDurationSkipEnabled,
    required this.introOutroAutoSkip,
    required this.skipCountdownSeconds,
    required this.hasNextEpisode,
    required this.subtitleDelaySeconds,
    required this.subtitlePosition,
    required this.subtitleScale,
    required this.onIntroOutroChanged,
    required this.onSubtitleStyleChanged,
    required this.onSelectChapter,
    required this.onAutoPlayChanged,
    required this.onNextEpisodePreloadChanged,
    required this.onAspectRatioChanged,
    required this.onDecoderChanged,
    required this.onMpvAdvancedChanged,
    required this.onVideoAdjustmentChanged,
    required this.onAudioDelayChanged,
    required this.onLoadSavedPresets,
    required this.onApplySavedPreset,
    required this.onAddBookmark,
    required this.onDeleteBookmark,
    required this.onSelectBookmark,
    required this.danmakuSettingsPageBuilder,
    required this.danmakuSourcesPageBuilder,
    this.initialPage = DesktopPlaybackSettingsPage.main,
    this.reserveCloseButtonSpace = false,
  });

  final MpvMediaSource source;
  final bool reserveCloseButtonSpace;
  final Duration position;
  final Duration duration;
  final bool autoPlayEnabled;
  final bool nextEpisodePreloadEnabled;
  final String aspectRatioMode;
  final String decoderMode;
  final Map<String, String> mpvSettings;
  final Map<String, double> videoAdjustments;
  final double audioDelaySeconds;
  final List<PlayerBookmarkEntry> bookmarks;
  final List<DesktopPlayerChapter> chapters;
  final bool danmakuEnabled;
  final String danmakuSourceLabel;
  final int danmakuCommentCount;
  final bool introOutroEnabled;
  final int introMaxSeconds;
  final int outroMaxSeconds;
  final bool fixedDurationSkipEnabled;
  final bool introOutroAutoSkip;
  final int skipCountdownSeconds;
  final bool hasNextEpisode;
  final double subtitleDelaySeconds;
  final int subtitlePosition;
  final double subtitleScale;
  final Future<void> Function({
    required bool enabled,
    required int introMaxSeconds,
    required int outroMaxSeconds,
    required bool fixedDurationEnabled,
    bool? autoSkip,
    int? countdownSeconds,
  })
  onIntroOutroChanged;
  final Future<void> Function({
    required double delaySeconds,
    required int position,
    required double scale,
  })
  onSubtitleStyleChanged;
  final Future<void> Function(Duration position) onSelectChapter;
  final Future<void> Function(bool value) onAutoPlayChanged;
  final Future<void> Function(bool value) onNextEpisodePreloadChanged;
  final Future<void> Function(String value) onAspectRatioChanged;
  final Future<void> Function(String value) onDecoderChanged;
  final Future<void> Function(String key, String value) onMpvAdvancedChanged;
  final Future<void> Function(String key, double value)
  onVideoAdjustmentChanged;
  final Future<void> Function(double value) onAudioDelayChanged;
  final Future<List<SavedMpvPreset>> Function(SavedMpvPresetKind kind)
  onLoadSavedPresets;
  final Future<void> Function(SavedMpvPreset preset) onApplySavedPreset;
  final Future<List<PlayerBookmarkEntry>> Function() onAddBookmark;
  final Future<List<PlayerBookmarkEntry>> Function(PlayerBookmarkEntry entry)
  onDeleteBookmark;
  final Future<void> Function(PlayerBookmarkEntry entry) onSelectBookmark;
  final Widget Function(VoidCallback onApplied) danmakuSettingsPageBuilder;
  final Widget Function(VoidCallback onApplied) danmakuSourcesPageBuilder;
  final DesktopPlaybackSettingsPage initialPage;

  @override
  State<DesktopPlaybackSettingsPanel> createState() =>
      _DesktopPlaybackSettingsPanelState();
}

class _DesktopPlaybackSettingsPanelState
    extends State<DesktopPlaybackSettingsPanel> {
  late final List<DesktopPlaybackSettingsPage> _pages =
      <DesktopPlaybackSettingsPage>[widget.initialPage];
  late bool _autoPlayEnabled = widget.autoPlayEnabled;
  late bool _nextEpisodePreloadEnabled = widget.nextEpisodePreloadEnabled;
  late String _aspectRatioMode = widget.aspectRatioMode;
  late String _decoderMode = widget.decoderMode;
  late Map<String, String> _mpvSettings = Map<String, String>.from(
    widget.mpvSettings,
  );
  late Map<String, double> _videoAdjustments = Map<String, double>.from(
    widget.videoAdjustments,
  );
  late double _audioDelaySeconds = widget.audioDelaySeconds;
  late List<PlayerBookmarkEntry> _bookmarks = List<PlayerBookmarkEntry>.from(
    widget.bookmarks,
  );

  DesktopPlaybackSettingsPage get _page => _pages.last;
  // 页面切换方向：push 自右滑入，pop 自左滑回。
  bool _popping = false;
  // 主页滚动位置：进二级页会卸载主列表，返回时恢复到离开处。
  final ScrollController _mainScrollController = ScrollController();
  double _mainScrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _mainScrollController.addListener(() {
      if (_mainScrollController.hasClients) {
        _mainScrollOffset = _mainScrollController.offset;
      }
    });
  }

  @override
  void dispose() {
    _mainScrollController.dispose();
    super.dispose();
  }

  void _push(DesktopPlaybackSettingsPage page) => setState(() {
    _popping = false;
    _pages.add(page);
  });

  void _pop() {
    if (_pages.length <= 1) return;
    setState(() {
      _popping = true;
      _pages.removeLast();
    });
    if (_page == DesktopPlaybackSettingsPage.main) {
      // 主列表重新挂载后跳回离开时的位置（1 帧内完成，被转场动画盖住）。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final controller = _mainScrollController;
        if (!mounted || !controller.hasClients) return;
        controller.jumpTo(
          _mainScrollOffset.clamp(0.0, controller.position.maxScrollExtent),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      // 设置首页及子页共用浮层内边距，不重复消费窗口标题栏安全区。
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SettingsHeader(
              title: _pageTitle(l10n),
              reserveCloseButtonSpace: widget.reserveCloseButtonSpace,
              onBack: _pages.length > 1 ? _pop : null,
              action: switch (_page) {
                DesktopPlaybackSettingsPage.bookmarks => IconButton(
                  tooltip: l10n.playerBookmarkAddCurrent,
                  onPressed: _addBookmark,
                  icon: const Icon(Icons.add_rounded),
                  color: Colors.white70,
                ),
                DesktopPlaybackSettingsPage.videoAdjust => IconButton(
                  tooltip: l10n.commonReset,
                  onPressed: () => _resetVideoAdjustments(),
                  icon: const Icon(Icons.restart_alt_rounded),
                  color: Colors.white70,
                ),
                DesktopPlaybackSettingsPage.subtitleStyle => IconButton(
                  tooltip: l10n.commonReset,
                  onPressed: () => _setSubtitleStyle(
                    delaySeconds: 0,
                    position: 92,
                    scale: 1,
                  ),
                  icon: const Icon(Icons.restart_alt_rounded),
                  color: Colors.white70,
                ),
                _ => null,
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                ),
                transitionBuilder: (child, animation) {
                  final incoming =
                      child.key == ValueKey<DesktopPlaybackSettingsPage>(_page);
                  // push：新页自右入、旧页向左出；pop 反向。
                  final fromRight = incoming ? !_popping : _popping;
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: fromRight
                            ? const Offset(0.05, 0)
                            : const Offset(-0.05, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey<DesktopPlaybackSettingsPage>(_page),
                  child: _buildPage(l10n),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _pageTitle(AppLocalizations l10n) => switch (_page) {
    DesktopPlaybackSettingsPage.main => l10n.playerSettingsTitle,
    DesktopPlaybackSettingsPage.videoAdjust => l10n.mpvInstantAdjustTitle,
    DesktopPlaybackSettingsPage.advancedMpv => l10n.playerAdvancedSettingsTitle,
    DesktopPlaybackSettingsPage.playbackBehavior =>
      l10n.playerPlaybackBehaviorTitle,
    DesktopPlaybackSettingsPage.introOutro => l10n.playerIntroOutroEntryTitle,
    DesktopPlaybackSettingsPage.chapters => l10n.playerChaptersTitle,
    DesktopPlaybackSettingsPage.subtitleStyle => l10n.playerSubtitleStyleTitle,
    DesktopPlaybackSettingsPage.bookmarks => l10n.playerBookmarkTitle,
    DesktopPlaybackSettingsPage.trackInfo => l10n.playerVideoInfoTitle,
    DesktopPlaybackSettingsPage.audioAdjust => l10n.playerAudioAdjustTitle,
    DesktopPlaybackSettingsPage.audioEq => l10n.playerAudioEqTitle,
    DesktopPlaybackSettingsPage.picturePresets =>
      l10n.playerSavedPicturePresetsTitle,
    DesktopPlaybackSettingsPage.audioPresets =>
      l10n.playerSavedAudioPresetsTitle,
    DesktopPlaybackSettingsPage.danmakuSettings => l10n.danmakuSettingsTitle,
    DesktopPlaybackSettingsPage.danmakuSources => l10n.danmakuSourceTitle,
  };

  Widget _buildPage(AppLocalizations l10n) => switch (_page) {
    DesktopPlaybackSettingsPage.main => _buildMainPage(l10n),
    DesktopPlaybackSettingsPage.videoAdjust => _buildVideoAdjustPage(l10n),
    DesktopPlaybackSettingsPage.advancedMpv => _buildAdvancedMpvPage(l10n),
    DesktopPlaybackSettingsPage.playbackBehavior => _buildPlaybackBehaviorPage(
      l10n,
    ),
    DesktopPlaybackSettingsPage.introOutro => _buildIntroOutroPage(l10n),
    DesktopPlaybackSettingsPage.chapters => _buildChaptersPage(l10n),
    DesktopPlaybackSettingsPage.subtitleStyle => _buildSubtitleStylePage(l10n),
    DesktopPlaybackSettingsPage.bookmarks => _buildBookmarksPage(l10n),
    DesktopPlaybackSettingsPage.trackInfo => _buildTrackInfoPage(l10n),
    DesktopPlaybackSettingsPage.audioAdjust => _buildAudioAdjustPage(l10n),
    DesktopPlaybackSettingsPage.audioEq => _buildAudioEqPage(l10n),
    DesktopPlaybackSettingsPage.picturePresets => _buildSavedPresetsPage(
      SavedMpvPresetKind.picture,
    ),
    DesktopPlaybackSettingsPage.audioPresets => _buildSavedPresetsPage(
      SavedMpvPresetKind.audio,
    ),
    DesktopPlaybackSettingsPage.danmakuSettings =>
      widget.danmakuSettingsPageBuilder(_pop),
    DesktopPlaybackSettingsPage.danmakuSources =>
      widget.danmakuSourcesPageBuilder(_pop),
  };

  Widget _settingsList(List<Widget> children, {ScrollController? controller}) =>
      ListView.separated(
        padding: EdgeInsets.zero,
        controller: controller,
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, index) => children[index],
      );

  String _labelFor(AppLocalizations l10n, String key) =>
      MpvSettingsL10n.labelForSetting(l10n, key, _mpvSettings);

  bool get _passthroughActive =>
      (_mpvSettings[MpvSettingsCatalog.audioPassthroughKey] ?? 'off') != 'off';

  // 根页：对齐安卓设置根面板的分组（画面 / 弹幕 / 播放）。
  // 音轨/字幕/画质桌面走底栏悬停直达，不重复（安卓横屏同理）。
  Widget _buildMainPage(AppLocalizations l10n) => _settingsList(<Widget>[
    _SettingsSectionHeader(l10n.playerSectionPicture),
    _SettingsMenuTile(
      title: l10n.mpvInstantAdjustTitle,
      subtitle: l10n.mpvVideoAdjustDrawerDescription,
      trailing:
          MpvSettingsCatalog.videoAdjustmentChangedCount(_videoAdjustments) == 0
          ? l10n.mpvDefault
          : l10n.mpvChangedCount(
              MpvSettingsCatalog.videoAdjustmentChangedCount(_videoAdjustments),
            ),
      icon: Icons.display_settings_rounded,
      onTap: () => _push(DesktopPlaybackSettingsPage.videoAdjust),
    ),
    _SettingsMenuTile(
      title: l10n.playerAdvancedSettingsTitle,
      subtitle: 'media_kit / libmpv',
      trailing: _decoderMode == 'software'
          ? l10n.playerSoftwareDecoderTitle
          : l10n.playerHardwareDecoderTitle,
      icon: Icons.tune_rounded,
      onTap: () => _push(DesktopPlaybackSettingsPage.advancedMpv),
    ),
    _SettingsSectionHeader(l10n.playerSectionDanmaku),
    _SettingsMenuTile(
      title: l10n.danmakuSettingsTitle,
      subtitle: l10n.playerEntryDanmakuSubtitle,
      trailing: widget.danmakuEnabled
          ? l10n.playerEnabled
          : l10n.playerDisabled,
      icon: Icons.format_size_rounded,
      onTap: () => _push(DesktopPlaybackSettingsPage.danmakuSettings),
    ),
    _SettingsMenuTile(
      title: l10n.danmakuSourceTitle,
      subtitle: widget.danmakuSourceLabel.trim().isEmpty
          ? l10n.playerEntryDanmakuSourceSubtitle
          : widget.danmakuSourceLabel,
      trailing: widget.danmakuCommentCount > 0
          ? l10n.playerDanmakuCountShort(widget.danmakuCommentCount)
          : '',
      icon: Icons.comment_bank_outlined,
      onTap: () => _push(DesktopPlaybackSettingsPage.danmakuSources),
    ),
    _SettingsSectionHeader(l10n.playerSectionPlayback),
    _SettingsMenuTile(
      title: l10n.playerPlaybackBehaviorTitle,
      subtitle: l10n.playerPlaybackBehaviorSubtitle,
      trailing: _autoPlayEnabled ? l10n.playerEnabled : l10n.playerDisabled,
      icon: Icons.playlist_play_rounded,
      onTap: () => _push(DesktopPlaybackSettingsPage.playbackBehavior),
    ),
    _SettingsMenuTile(
      title: l10n.playerIntroOutroEntryTitle,
      subtitle: l10n.playerIntroOutroEntrySubtitle,
      trailing: widget.introOutroEnabled
          ? l10n.playerEnabled
          : l10n.playerDisabled,
      icon: Icons.skip_next_rounded,
      onTap: () => _push(DesktopPlaybackSettingsPage.introOutro),
    ),
    _SettingsMenuTile(
      title: l10n.playerChaptersTitle,
      subtitle: l10n.playerChaptersSubtitle,
      trailing: widget.chapters.isEmpty
          ? l10n.playerNoneLabel
          : '${widget.chapters.length}',
      icon: Icons.format_list_numbered_rounded,
      onTap: () => _push(DesktopPlaybackSettingsPage.chapters),
    ),
    _SettingsMenuTile(
      title: l10n.playerBookmarkTitle,
      subtitle: l10n.playerBookmarkSettingsSubtitle,
      trailing: _bookmarks.isEmpty
          ? l10n.playerBookmarkNone
          : l10n.playerBookmarkCount(_bookmarks.length),
      icon: Icons.bookmark_outline_rounded,
      onTap: () => _push(DesktopPlaybackSettingsPage.bookmarks),
    ),
    _SettingsMenuTile(
      title: l10n.playerTrackInfoEntryTitle,
      subtitle: l10n.playerVideoInfoSubtitle,
      icon: Icons.info_outline_rounded,
      onTap: () => _push(DesktopPlaybackSettingsPage.trackInfo),
    ),
  ], controller: _mainScrollController);

  // 画质与解码：对齐安卓 buildAdvancedMpvPage 的四段分组。
  Widget _buildAdvancedMpvPage(AppLocalizations l10n) => _settingsList(<Widget>[
    _SettingsSectionHeader(l10n.playerSectionPresets),
    _SettingsMenuTile(
      title: l10n.playerPresetSelectTitle,
      subtitle: l10n.playerPresetSelectPictureSubtitle,
      icon: Icons.bookmarks_rounded,
      onTap: () => _push(DesktopPlaybackSettingsPage.picturePresets),
    ),
    _SettingsSectionHeader(l10n.playerSectionDecodePicture),
    _SettingsSegmentTile(
      title: l10n.playerDecoderTitle,
      options: [
        ('hardware', l10n.playerHardwareDecoderTitle),
        ('software', l10n.playerSoftwareDecoderTitle),
      ],
      selectedValue: _decoderMode,
      onSelected: (value) => _setDecoder(value),
    ),
    _SettingsSegmentTile(
      title: l10n.playerAspectRatioTitle,
      options: [
        ('fit', l10n.playerAspectFit),
        ('fill', l10n.playerAspectFill),
        ('4:3', '4:3'),
        ('16:9', '16:9'),
        ('21:9', '21:9'),
      ],
      selectedValue: _aspectRatioMode,
      onSelected: (value) => _setAspectRatio(value),
    ),
    _SettingsSectionHeader(l10n.playerSectionQuality),
    for (final key in const <String>[
      MpvSettingsCatalog.deinterlaceKey,
      MpvSettingsCatalog.debandKey,
      MpvSettingsCatalog.sharpenKey,
      MpvSettingsCatalog.denoiseKey,
      MpvSettingsCatalog.scaleProfileKey,
      MpvSettingsCatalog.toneMappingKey,
      MpvSettingsCatalog.frameInterpolationKey,
    ])
      _definitionSegment(l10n, key),
    _SettingsSectionHeader(l10n.playerSectionSyncCache),
    for (final key in const <String>[
      MpvSettingsCatalog.videoSyncKey,
      MpvSettingsCatalog.cacheProfileKey,
      MpvSettingsCatalog.cacheSizeMbKey,
    ])
      _definitionSegment(l10n, key),
  ]);

  // 播放行为：对齐安卓 buildPlaybackBehaviorSettingsPage（仅保留桌面适用的项）。
  Widget _buildPlaybackBehaviorPage(AppLocalizations l10n) =>
      _settingsList(<Widget>[
        _SettingsSwitchTile(
          title: l10n.playerAutoPlayTitle,
          subtitle: _autoPlayEnabled
              ? l10n.playerAutoPlayEnabledSubtitle
              : l10n.playerAutoPlayDisabledSubtitle,
          value: _autoPlayEnabled,
          onChanged: _setAutoPlay,
        ),
        _SettingsSwitchTile(
          title: l10n.playerNextEpisodePreloadTitle,
          subtitle: !_autoPlayEnabled
              ? l10n.playerNextEpisodePreloadRequiresAutoPlay
              : _nextEpisodePreloadEnabled
              ? l10n.playerNextEpisodePreloadEnabledSubtitle
              : l10n.playerNextEpisodePreloadDisabledSubtitle,
          value: _nextEpisodePreloadEnabled,
          enabled: _autoPlayEnabled,
          onChanged: _setNextEpisodePreload,
        ),
      ]);

  Widget _buildIntroOutroPage(AppLocalizations l10n) {
    final bounds = desktopPlaybackSkipBounds(
      widget.chapters,
      widget.duration,
      chapterEnabled: widget.introOutroEnabled,
      fixedDurationEnabled: widget.fixedDurationSkipEnabled,
      introSeconds: widget.introMaxSeconds,
      outroSeconds: widget.outroMaxSeconds,
    );
    Widget statusCard({required bool intro}) {
      final label = intro ? l10n.playerIntroLabel : l10n.playerOutroLabel;
      final start = intro ? bounds.introStart : bounds.outroStart;
      final end = intro
          ? bounds.introEnd
          : (bounds.outroEnd ?? widget.duration);
      final fromChapter = intro
          ? bounds.introFromChapter
          : bounds.outroFromChapter;
      final fromPattern = intro
          ? bounds.introFromPattern
          : bounds.outroFromPattern;
      if (start == null || end == null) {
        final String reason;
        if (!widget.introOutroEnabled && !widget.fixedDurationSkipEnabled) {
          reason = l10n.playerIntroOutroDisabled;
        } else if (widget.duration <= Duration.zero) {
          reason = l10n.playerIntroOutroWaiting;
        } else if (!widget.fixedDurationSkipEnabled && !fromChapter) {
          reason = widget.chapters.isEmpty
              ? l10n.playerIntroOutroNoChapters
              : l10n.playerIntroOutroNoChapterMatch(label);
        } else {
          reason = l10n.playerIntroOutroInvalidRange;
        }
        return _SettingsStatusCard(
          title: l10n.playerIntroOutroCurrent(label),
          value: l10n.playerIntroOutroNoSkipLabel,
          description: reason,
        );
      }
      final basis = fromChapter
          ? l10n.playerIntroBasisChapter
          : fromPattern
          ? l10n.playerIntroBasisPattern
          : l10n.playerIntroBasisFixed;
      final target = intro
          ? l10n.playerSkipToLabel(_duration(end))
          : bounds.outroEnd != null
          ? l10n.playerSkipToLabel(_duration(end))
          : widget.hasNextEpisode
          ? l10n.playerIntroPlayNextLabel
          : l10n.playerSkipToEndLabel;
      return _SettingsStatusCard(
        title: l10n.playerIntroOutroCurrent(label),
        value: '$basis · ${_duration(start)}–${_duration(end)}',
        description: intro
            ? l10n.playerIntroActionTap(target)
            : bounds.outroEnd != null
            ? l10n.playerIntroActionOutroEnd(target)
            : l10n.playerIntroActionOutroSkipAll(target),
      );
    }

    final children = <Widget>[
      _SettingsSwitchTile(
        title: l10n.playerIntroByChapterTitle,
        subtitle: l10n.playerIntroByChapterSubtitle,
        value: widget.introOutroEnabled,
        onChanged: (value) => _setIntroOutro(enabled: value),
      ),
      _SettingsSwitchTile(
        title: l10n.playerFixedSkipTitle,
        subtitle: l10n.playerFixedSkipSubtitle,
        value: widget.fixedDurationSkipEnabled,
        onChanged: (value) => _setIntroOutro(fixedDurationEnabled: value),
      ),
    ];
    if (widget.fixedDurationSkipEnabled) {
      children.add(
        _SettingsSliderTile(
          title: l10n.playerFixedIntroLengthTitle,
          subtitle: l10n.playerFixedIntroLengthSubtitle,
          valueLabel: _skipSecondsLabel(widget.introMaxSeconds, l10n),
          value: widget.introMaxSeconds.toDouble(),
          min: 0,
          max: 600,
          divisions: 120,
          onChanged: (_) {},
          onChangeEnd: (value) =>
              _setIntroOutro(introMaxSeconds: value.round()),
        ),
      );
      children.add(
        _SettingsSliderTile(
          title: l10n.playerFixedOutroLengthTitle,
          subtitle: l10n.playerFixedOutroLengthSubtitle,
          valueLabel: _skipSecondsLabel(widget.outroMaxSeconds, l10n),
          value: widget.outroMaxSeconds.toDouble(),
          min: 0,
          max: 600,
          divisions: 120,
          onChanged: (_) {},
          onChangeEnd: (value) =>
              _setIntroOutro(outroMaxSeconds: value.round()),
        ),
      );
    }
    if (widget.introOutroEnabled || widget.fixedDurationSkipEnabled) {
      // 自动跳过子开关（默认开启，对齐安卓）：关闭后仅弹出提示，由用户手动点击跳过。
      children.add(
        _SettingsSwitchTile(
          title: l10n.playerAutoSkipTitle,
          subtitle: l10n.playerAutoSkipSubtitle,
          value: widget.introOutroAutoSkip,
          onChanged: (value) => _setIntroOutro(autoSkip: value),
        ),
      );
      if (widget.introOutroAutoSkip) {
        children.add(
          _SettingsSliderTile(
            title: l10n.playerSkipCountdownTitle,
            subtitle: l10n.playerSkipCountdownSubtitle,
            valueLabel: l10n.playerCountdownSecondsValue(
              widget.skipCountdownSeconds,
            ),
            value: widget.skipCountdownSeconds.toDouble(),
            min: 2,
            max: 10,
            divisions: 8,
            onChanged: (_) {},
            onChangeEnd: (value) =>
                _setIntroOutro(countdownSeconds: value.round()),
          ),
        );
      }
    }
    children.add(statusCard(intro: true));
    children.add(statusCard(intro: false));
    return _settingsList(children);
  }

  /// 固定时长按秒展示（与飞牛官方配置同单位）；0 表示该侧不提示。
  String _skipSecondsLabel(int seconds, AppLocalizations l10n) {
    if (seconds <= 0) return l10n.mpvOptionOff;
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    if (minutes == 0) return l10n.playerDurationSecondsValue(seconds);
    if (rest == 0) return l10n.playerDurationMinutesValue(minutes);
    return l10n.playerDurationMinSecValue(minutes, rest);
  }

  Future<void> _setIntroOutro({
    bool? enabled,
    int? introMaxSeconds,
    int? outroMaxSeconds,
    bool? fixedDurationEnabled,
    bool? autoSkip,
    int? countdownSeconds,
  }) async {
    await widget.onIntroOutroChanged(
      enabled: enabled ?? widget.introOutroEnabled,
      introMaxSeconds: introMaxSeconds ?? widget.introMaxSeconds,
      outroMaxSeconds: outroMaxSeconds ?? widget.outroMaxSeconds,
      fixedDurationEnabled:
          fixedDurationEnabled ?? widget.fixedDurationSkipEnabled,
      autoSkip: autoSkip ?? widget.introOutroAutoSkip,
      countdownSeconds: countdownSeconds ?? widget.skipCountdownSeconds,
    );
  }

  // 字幕样式：对齐安卓 buildSubtitleStylePage（延迟/位置/缩放 + 头部重置）。
  Widget _buildSubtitleStylePage(
    AppLocalizations l10n,
  ) => _settingsList(<Widget>[
    _SettingsSliderTile(
      title: l10n.playerSubtitleDelayTitle,
      subtitle: l10n.playerSubtitleDelaySubtitle,
      valueLabel: l10n.playerDelaySecondsValue(
        '${widget.subtitleDelaySeconds > 0 ? '+' : ''}${widget.subtitleDelaySeconds.toStringAsFixed(1)}',
      ),
      value: widget.subtitleDelaySeconds,
      min: -10,
      max: 10,
      divisions: 200,
      onChanged: (value) => widget.onSubtitleStyleChanged(
        delaySeconds: double.parse(value.toStringAsFixed(1)),
        position: widget.subtitlePosition,
        scale: widget.subtitleScale,
      ),
      onChangeEnd: (value) => _setSubtitleStyle(
        delaySeconds: double.parse(value.toStringAsFixed(1)),
      ),
    ),
    _SettingsSliderTile(
      title: l10n.playerSubtitlePositionTitle,
      subtitle: l10n.playerSubtitlePositionSubtitle,
      valueLabel: '${widget.subtitlePosition}',
      value: widget.subtitlePosition.toDouble(),
      min: 0,
      max: 100,
      divisions: 100,
      onChanged: (value) => widget.onSubtitleStyleChanged(
        delaySeconds: widget.subtitleDelaySeconds,
        position: value.round(),
        scale: widget.subtitleScale,
      ),
      onChangeEnd: (value) => _setSubtitleStyle(position: value.round()),
    ),
    _SettingsSliderTile(
      title: l10n.playerSubtitleScaleTitle,
      subtitle: l10n.playerSubtitleScaleSubtitle,
      valueLabel: '${widget.subtitleScale.toStringAsFixed(2)}x',
      value: widget.subtitleScale,
      min: 0.5,
      max: 2.5,
      divisions: 200,
      onChanged: (value) => widget.onSubtitleStyleChanged(
        delaySeconds: widget.subtitleDelaySeconds,
        position: widget.subtitlePosition,
        scale: double.parse(value.toStringAsFixed(2)),
      ),
      onChangeEnd: (value) =>
          _setSubtitleStyle(scale: double.parse(value.toStringAsFixed(2))),
    ),
  ]);

  Future<void> _setSubtitleStyle({
    double? delaySeconds,
    int? position,
    double? scale,
  }) async {
    await widget.onSubtitleStyleChanged(
      delaySeconds: delaySeconds ?? widget.subtitleDelaySeconds,
      position: position ?? widget.subtitlePosition,
      scale: scale ?? widget.subtitleScale,
    );
  }

  // 章节：对齐安卓 buildChapterPage（当前章节高亮，点击跳转）。
  Widget _buildChaptersPage(AppLocalizations l10n) {
    if (widget.chapters.isEmpty) {
      return _settingsList(<Widget>[
        _SettingsStatusCard(
          title: l10n.playerChaptersTitle,
          value: l10n.playerChaptersEmpty,
          description: l10n.playerChaptersEmptyHint,
        ),
      ]);
    }
    final position = widget.position;
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: widget.chapters.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        final chapter = widget.chapters[index];
        final next = index + 1 < widget.chapters.length
            ? widget.chapters[index + 1].position
            : null;
        final current =
            position >= chapter.position && (next == null || position < next);
        return _SettingsCard(
          onTap: () => widget.onSelectChapter(chapter.position),
          selected: current,
          child: Row(
            children: <Widget>[
              Expanded(
                child: _SettingsTileText(
                  title: chapter.title.trim().isEmpty
                      ? l10n.playerChapterN(index + 1)
                      : chapter.title,
                  subtitle: '',
                ),
              ),
              Text(
                _duration(chapter.position),
                style: TextStyle(
                  color: current ? const Color(0xFF9CC4FF) : Colors.white54,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 音频调整：对齐安卓 buildAudioPage 的分段结构（延迟 / 预设 / 输出 / 增益与音效 / 均衡器）。
  Widget _buildAudioAdjustPage(AppLocalizations l10n) => _settingsList(<Widget>[
    _SettingsSliderTile(
      title: l10n.playerAudioDelayTitle,
      subtitle: l10n.playerAudioDelaySubtitle,
      valueLabel: l10n.playerDelaySecondsValue(
        '${_audioDelaySeconds > 0 ? '+' : ''}${_audioDelaySeconds.toStringAsFixed(1)}',
      ),
      value: _audioDelaySeconds,
      min: -10,
      max: 10,
      divisions: 200,
      onChanged: (value) => setState(() => _audioDelaySeconds = value),
      onChangeEnd: _setAudioDelay,
    ),
    _SettingsSectionHeader(l10n.playerSectionPresets),
    _SettingsMenuTile(
      title: l10n.playerPresetSelectTitle,
      subtitle: l10n.playerPresetSelectAudioSubtitle,
      icon: Icons.library_music_rounded,
      onTap: () => _push(DesktopPlaybackSettingsPage.audioPresets),
    ),
    _SettingsSectionHeader(l10n.playerSectionOutput),
    _definitionSegment(l10n, MpvSettingsCatalog.audioPassthroughKey),
    if (_passthroughActive)
      _SettingsStatusCard(
        title: l10n.playerPassthroughTitle,
        value: l10n.playerEnabled,
        description: l10n.playerPassthroughDescription,
      ),
    _SettingsSectionHeader(l10n.playerSectionGainEffects),
    for (final key in const <String>[
      MpvSettingsCatalog.volumeGainKey,
      MpvSettingsCatalog.audioHighFidelityKey,
      MpvSettingsCatalog.dynamicRangeKey,
      MpvSettingsCatalog.audioLimiterKey,
      MpvSettingsCatalog.audioBassBoostKey,
      MpvSettingsCatalog.audioVoiceEnhanceKey,
      MpvSettingsCatalog.channelMixKey,
    ])
      _definitionSegment(l10n, key, enabled: !_passthroughActive),
    _SettingsSectionHeader(l10n.playerSectionEqualizer),
    _definitionSegment(
      l10n,
      MpvSettingsCatalog.audioEqKey,
      enabled: !_passthroughActive,
    ),
    _SettingsMenuTile(
      title: l10n.playerAudioEqTitle,
      subtitle: l10n.playerAudioEqSubtitle,
      trailing: _labelFor(l10n, MpvSettingsCatalog.audioEqKey),
      icon: Icons.equalizer_rounded,
      onTap:
          _mpvSettings[MpvSettingsCatalog.audioEqKey] ==
              MpvSettingsCatalog.audioEqCustomValue
          ? () => _push(DesktopPlaybackSettingsPage.audioEq)
          : null,
    ),
  ]);

  // 自定义均衡器：对齐安卓 buildEqualizerPage（频段滑条 + 重置）。
  Widget _buildAudioEqPage(AppLocalizations l10n) => _settingsList(<Widget>[
    for (final band in MpvSettingsCatalog.audioEqBands)
      _SettingsSliderTile(
        title: '${band.label} Hz',
        subtitle: l10n.playerAudioEqBandSubtitle,
        valueLabel: MpvSettingsCatalog.formatAudioEqBandValue(
          MpvSettingsCatalog.audioEqBandValue(band.key, _mpvSettings),
        ),
        value: MpvSettingsCatalog.audioEqBandValue(band.key, _mpvSettings),
        min: MpvSettingsCatalog.audioEqBandMinDb,
        max: MpvSettingsCatalog.audioEqBandMaxDb,
        divisions:
            ((MpvSettingsCatalog.audioEqBandMaxDb -
                        MpvSettingsCatalog.audioEqBandMinDb) /
                    MpvSettingsCatalog.audioEqBandStepDb)
                .round(),
        onChanged: (value) => setState(
          () => _mpvSettings = <String, String>{
            ..._mpvSettings,
            band.key: MpvSettingsCatalog.normalizeAudioEqBandValue(value),
          },
        ),
        onChangeEnd: (value) => _setMpvAdvanced(
          band.key,
          MpvSettingsCatalog.normalizeAudioEqBandValue(value),
        ),
      ),
  ]);

  Widget _buildSavedPresetsPage(SavedMpvPresetKind kind) => _SavedPresetsPage(
    kind: kind,
    onLoadSavedPresets: widget.onLoadSavedPresets,
    onApplySavedPreset: (preset) async {
      await widget.onApplySavedPreset(preset);
      if (mounted) _pop();
    },
  );

  Widget _definitionSegment(
    AppLocalizations l10n,
    String key, {
    bool enabled = true,
  }) {
    final definition = MpvSettingsL10n.definitionByKey(l10n, key);
    if (definition == null) return const SizedBox.shrink();
    final interpolationSync =
        key == MpvSettingsCatalog.videoSyncKey &&
        _mpvSettings[MpvSettingsCatalog.frameInterpolationKey] == 'on';
    return _SettingsSegmentTile(
      title: interpolationSync
          ? l10n.playerInterpolationSyncSuffix(definition.title)
          : definition.title,
      options: <(String, String)>[
        for (final option in definition.options) (option.value, option.label),
      ],
      selectedValue: interpolationSync
          ? 'auto'
          : _mpvSettings[key] ??
                MpvSettingsCatalog.defaults[key] ??
                definition.options.first.value,
      enabled: enabled && !interpolationSync,
      onSelected: (value) => _setMpvAdvanced(key, value),
    );
  }

  Widget _buildVideoAdjustPage(AppLocalizations l10n) => _settingsList(<Widget>[
    for (final key in MpvSettingsCatalog.videoAdjustmentDefaults.keys)
      _SettingsSliderTile(
        title: MpvSettingsL10n.videoAdjustmentTitle(l10n, key),
        subtitle: MpvSettingsL10n.videoAdjustmentSubtitle(l10n, key),
        valueLabel: MpvSettingsCatalog.formatVideoAdjustmentValue(
          _videoAdjustments[key] ?? 0,
        ),
        value: _videoAdjustments[key] ?? 0,
        min: -100,
        max: 100,
        divisions: 200,
        onChanged: (value) => setState(
          () => _videoAdjustments = <String, double>{
            ..._videoAdjustments,
            key: value,
          },
        ),
        onChangeEnd: (value) => _setVideoAdjustment(key, value),
      ),
  ]);

  Widget _buildTrackInfoPage(AppLocalizations l10n) {
    final source = widget.source;
    final dimensions = source.videoWidth > 0 && source.videoHeight > 0
        ? '${source.videoWidth} × ${source.videoHeight}'
        : source.resolution;
    final rows = <(String, String)>[
      (l10n.playerDiagnosticsTitleLabel, source.title),
      (l10n.playerInfoPosition, _duration(widget.position)),
      (
        l10n.playerInfoDuration,
        _duration(Duration(seconds: source.durationSeconds)),
      ),
      (l10n.playerDiagnosticsResolution, dimensions),
      (l10n.playerDiagnosticsVideoCodec, source.videoCodecName),
      (l10n.playerInfoVideoProfile, source.videoProfile),
      (
        l10n.playerInfoBitDepth,
        source.bitDepth > 0 ? '${source.bitDepth} bit' : '',
      ),
      (l10n.mediaDetailsFieldColorSpace, source.colorSpace),
      (l10n.playerInfoColorTransfer, source.colorTransfer),
      (
        l10n.mediaDetailsFieldBitrate,
        source.bitrate > 0
            ? '${(source.bitrate / 1000000).toStringAsFixed(1)} Mbps'
            : '',
      ),
      (l10n.playerInfoPlaybackMode, source.playbackMode.name),
    ].where((entry) => entry.$2.trim().isNotEmpty).toList(growable: false);
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(color: Color(0x18FFFFFF)),
      itemBuilder: (_, index) => _InfoRow(rows[index].$1, rows[index].$2),
    );
  }

  Widget _buildBookmarksPage(AppLocalizations l10n) {
    if (_bookmarks.isEmpty) {
      return _settingsList(<Widget>[
        _SettingsStatusCard(
          title: widget.source.title,
          value: l10n.playerBookmarkNone,
          description: l10n.playerBookmarkEmptyPrompt,
        ),
      ]);
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _bookmarks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, index) {
        final entry = _bookmarks[index];
        return _BookmarkTile(
          time: _duration(entry.position),
          note: entry.note,
          onTap: () => widget.onSelectBookmark(entry),
          onDelete: () => _deleteBookmark(entry),
        );
      },
    );
  }

  Future<void> _setAutoPlay(bool value) async {
    setState(() {
      _autoPlayEnabled = value;
      if (!value) _nextEpisodePreloadEnabled = false;
    });
    await widget.onAutoPlayChanged(value);
    if (!value) await widget.onNextEpisodePreloadChanged(false);
  }

  Future<void> _setNextEpisodePreload(bool value) async {
    if (!_autoPlayEnabled) return;
    setState(() => _nextEpisodePreloadEnabled = value);
    await widget.onNextEpisodePreloadChanged(value);
  }

  Future<void> _setAspectRatio(String value) async {
    setState(() => _aspectRatioMode = value);
    await widget.onAspectRatioChanged(value);
  }

  Future<void> _setDecoder(String value) async {
    setState(() => _decoderMode = value);
    await widget.onDecoderChanged(value);
  }

  Future<void> _setMpvAdvanced(String key, String value) async {
    setState(
      () => _mpvSettings = <String, String>{..._mpvSettings, key: value},
    );
    await widget.onMpvAdvancedChanged(key, value);
  }

  Future<void> _setVideoAdjustment(String key, double value) async {
    final next = Map<String, double>.from(_videoAdjustments)..[key] = value;
    final normalized = MpvSettingsCatalog.normalizeVideoAdjustments(next);
    setState(() => _videoAdjustments = normalized);
    await widget.onVideoAdjustmentChanged(key, normalized[key] ?? 0);
  }

  Future<void> _resetVideoAdjustments() async {
    final defaults = Map<String, double>.from(
      MpvSettingsCatalog.videoAdjustmentDefaults,
    );
    setState(() => _videoAdjustments = defaults);
    for (final entry in defaults.entries) {
      await widget.onVideoAdjustmentChanged(entry.key, entry.value);
    }
  }

  Future<void> _setAudioDelay(double value) async {
    final normalized = double.parse(
      value.clamp(-10.0, 10.0).toStringAsFixed(1),
    );
    setState(() => _audioDelaySeconds = normalized);
    await widget.onAudioDelayChanged(normalized);
  }

  Future<void> _addBookmark() async {
    final next = await widget.onAddBookmark();
    if (mounted) setState(() => _bookmarks = next);
  }

  Future<void> _deleteBookmark(PlayerBookmarkEntry entry) async {
    final next = await widget.onDeleteBookmark(entry);
    if (mounted) setState(() => _bookmarks = next);
  }

  String _duration(Duration value) {
    final safe = value < Duration.zero ? Duration.zero : value;
    final hours = safe.inHours;
    final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}

/// 已保存预设列表页：对齐安卓 buildSavedPresetListPage（仅有保存过的预设，空态给提示）。
class _SavedPresetsPage extends StatefulWidget {
  const _SavedPresetsPage({
    required this.kind,
    required this.onLoadSavedPresets,
    required this.onApplySavedPreset,
  });

  final SavedMpvPresetKind kind;
  final Future<List<SavedMpvPreset>> Function(SavedMpvPresetKind kind)
  onLoadSavedPresets;
  final Future<void> Function(SavedMpvPreset preset) onApplySavedPreset;

  @override
  State<_SavedPresetsPage> createState() => _SavedPresetsPageState();
}

class _SavedPresetsPageState extends State<_SavedPresetsPage> {
  List<SavedMpvPreset> _presets = const <SavedMpvPreset>[];
  bool _loading = true;
  String? _applyingId;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final presets = await widget.onLoadSavedPresets(widget.kind);
    if (!mounted) return;
    setState(() {
      _presets = presets;
      _loading = false;
    });
  }

  Future<void> _apply(SavedMpvPreset preset) async {
    if (_applyingId != null) return;
    setState(() => _applyingId = preset.id);
    await widget.onApplySavedPreset(preset);
    if (!mounted) return;
    setState(() => _applyingId = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_presets.isEmpty) {
      final l10n = AppLocalizations.of(context);
      return ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          _SettingsStatusCard(
            title: l10n.playerSavedPresetsTitle,
            value: l10n.playerSavedPresetsEmpty,
            description: l10n.playerSavedPresetsHint,
          ),
        ],
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _presets.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, index) {
        final preset = _presets[index];
        return _SettingsCard(
          onTap: _applyingId == null ? () => unawaited(_apply(preset)) : null,
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.tune_rounded,
                size: 20,
                color: Color(0xFF9CC4FF),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SettingsTileText(
                  title: preset.name,
                  subtitle: preset.description,
                ),
              ),
              if (_applyingId == preset.id)
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 分组标题：对齐安卓 panelSectionHeader。
class _SettingsSectionHeader extends StatelessWidget {
  const _SettingsSectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, left: 4),
    child: Text(
      title,
      style: const TextStyle(
        color: Colors.white60,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    ),
  );
}

/// 分段选项行：对齐安卓 panelSegment（标签 + 一行可选项）。
class _SettingsSegmentTile extends StatelessWidget {
  const _SettingsSegmentTile({
    required this.title,
    required this.options,
    required this.selectedValue,
    required this.onSelected,
    this.enabled = true,
  });

  final String title;
  final List<(String, String)> options;
  final String selectedValue;
  final ValueChanged<String> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : 0.45,
    child: _SettingsCard(
      onTap: null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final (value, label) in options)
                _SegmentChip(
                  label: label,
                  selected: value == selectedValue,
                  onTap: enabled && value != selectedValue
                      ? () => onSelected(value)
                      : null,
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? const Color(0x246EA8FF) : const Color(0x0DFFFFFF),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(9),
      side: BorderSide(
        color: selected ? const Color(0x806EA8FF) : const Color(0x14FFFFFF),
      ),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(9),
      hoverColor: const Color(0x1AFFFFFF),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF9CC4FF) : Colors.white70,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    ),
  );
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({
    required this.title,
    this.onBack,
    this.action,
    this.reserveCloseButtonSpace = false,
  });

  final String title;
  final VoidCallback? onBack;
  final Widget? action;
  final bool reserveCloseButtonSpace;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      if (onBack != null) ...<Widget>[
        IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          color: Colors.white,
          style: IconButton.styleFrom(
            fixedSize: const Size.square(34),
            padding: EdgeInsets.zero,
            backgroundColor: const Color(0x14FFFFFF),
            hoverColor: const Color(0x28FFFFFF),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        const SizedBox(width: 6),
      ],
      Expanded(
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      if (action != null) action!,
      if (reserveCloseButtonSpace) const SizedBox(width: 46),
    ],
  );
}

class _SettingsMenuTile extends StatelessWidget {
  const _SettingsMenuTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing = '',
    this.icon,
  });

  final String title;
  final String subtitle;
  final String trailing;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onTap == null ? 0.45 : 1,
    child: _SettingsCard(
      onTap: onTap,
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: const Color(0x1A6EA8FF),
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 17, color: const Color(0xFF9CC4FF)),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: _SettingsTileText(title: title, subtitle: subtitle),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 94,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    trailing,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 19,
                  color: Colors.white38,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _SettingsSwitchTile extends StatelessWidget {
  const _SettingsSwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : 0.52,
    child: _SettingsCard(
      onTap: enabled ? () => onChanged(!value) : null,
      child: Row(
        children: <Widget>[
          Expanded(
            child: _SettingsTileText(title: title, subtitle: subtitle),
          ),
          const SizedBox(width: 12),
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeThumbColor: const Color(0xFF9CC4FF),
            activeTrackColor: const Color(0x806EA8FF),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    ),
  );
}

class _SettingsSliderTile extends StatelessWidget {
  const _SettingsSliderTile({
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.onChangeEnd,
    this.subtitle = '',
  });

  final String title;
  final String subtitle;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) => _SettingsCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _SettingsTileText(title: title, subtitle: subtitle),
            ),
            const SizedBox(width: 12),
            Text(
              valueLabel,
              style: const TextStyle(
                color: Color(0xFF9CC4FF),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        DesktopSemanticsSafeSlider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
          activeColor: const Color(0xFF6EA8FF),
          inactiveColor: const Color(0x28FFFFFF),
          semanticsLabel: title,
          semanticsValue: valueLabel,
        ),
      ],
    ),
  );
}

class _SettingsStatusCard extends StatelessWidget {
  const _SettingsStatusCard({
    required this.title,
    required this.value,
    required this.description,
  });

  final String title;
  final String value;
  final String description;

  @override
  Widget build(BuildContext context) => _SettingsCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (description.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 7),
          Text(
            description,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ],
    ),
  );
}

class _SettingsTileText extends StatelessWidget {
  const _SettingsTileText({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      if (subtitle.trim().isNotEmpty) ...<Widget>[
        const SizedBox(height: 4),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
            height: 1.35,
          ),
        ),
      ],
    ],
  );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child, this.onTap, this.selected = false});

  final Widget child;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? const Color(0x246EA8FF) : const Color(0x121F2A3A),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: selected ? const Color(0x806EA8FF) : const Color(0x0FFFFFFF),
      ),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      hoverColor: const Color(0x1AFFFFFF),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: child,
      ),
    ),
  );
}

class _BookmarkTile extends StatelessWidget {
  const _BookmarkTile({
    required this.time,
    required this.note,
    required this.onTap,
    required this.onDelete,
  });

  final String time;
  final String note;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => _SettingsCard(
    onTap: onTap,
    child: Row(
      children: <Widget>[
        const Icon(Icons.bookmark_rounded, color: Color(0xFF9CC4FF)),
        const SizedBox(width: 13),
        Expanded(
          child: _SettingsTileText(
            title: time,
            subtitle: note.trim().isEmpty
                ? AppLocalizations.of(context).playerBookmarkJumpHint
                : note,
          ),
        ),
        IconButton(
          tooltip: AppLocalizations.of(context).commonDelete,
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline_rounded, size: 19),
          color: Colors.white54,
        ),
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class _PanelScroll extends StatelessWidget {
  const _PanelScroll({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext c) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle(this.title, this.subtitle);
  final String title, subtitle;
  @override
  Widget build(BuildContext c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      if (subtitle.trim().isNotEmpty)
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
    ],
  );
}

class _OptionCard extends StatelessWidget {
  const _OptionCard(
    this.title, {
    this.subtitle = '',
    this.icon,
    this.selected = false,
    this.onTap,
  });
  final String title, subtitle;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext c) => Material(
    color: selected ? const Color(0x2463A0FF) : const Color(0x121F2A3A),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(
        color: selected ? const Color(0x8063A0FF) : const Color(0x0FFFFFFF),
      ),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      hoverColor: const Color(0x1AFFFFFF),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white70, size: 20),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: onTap == null ? Colors.white38 : Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0x73FFFFFF),
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            _SelectionMark(selected),
          ],
        ),
      ),
    ),
  );
}

class _SelectionMark extends StatelessWidget {
  const _SelectionMark(this.selected);
  final bool selected;
  @override
  Widget build(BuildContext c) => Container(
    width: 18,
    height: 18,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: selected ? const Color(0xFF63A0FF) : Colors.transparent,
      border: Border.all(
        color: selected ? const Color(0xFF63A0FF) : Colors.white38,
        width: 1.5,
      ),
    ),
    child: selected
        ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
        : null,
  );
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel(this.label);
  final String label;
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 30),
    child: Center(
      child: Text(label, style: const TextStyle(color: Colors.white54)),
    ),
  );
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle(this.icon, this.selected, this.onTap);
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext c) {
    final l10n = AppLocalizations.of(c);
    return IconButton(
      icon: Icon(icon, size: 18),
      color: selected ? Colors.white : Colors.white38,
      tooltip: selected ? l10n.playerViewCurrent : l10n.playerViewSwitch,
      onPressed: onTap,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(34),
        padding: EdgeInsets.zero,
        backgroundColor: selected
            ? const Color(0x246EA8FF)
            : Colors.transparent,
        hoverColor: const Color(0x1AFFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard(
    this.episode,
    this.current,
    this.enabled,
    this.grid,
    this.onTap,
  );
  final Map<String, dynamic> episode;
  final bool current, enabled, grid;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext c) {
    final l10n = AppLocalizations.of(c);
    final shortLabel = '${episode['shortLabel'] ?? ''}'.trim();
    final episodeNumber = '${episode['episodeNumber'] ?? ''}'.trim();
    final numberLabel = shortLabel.isNotEmpty
        ? shortLabel
        : (episodeNumber.isNotEmpty ? episodeNumber : '—');
    final rawTitle = '${episode['title'] ?? ''}'.trim();
    final title = rawTitle.isNotEmpty
        ? rawTitle
        : l10n.playerEpisodeNumberTemplate(numberLabel);
    final poster = '${episode['poster'] ?? episode['posterPath'] ?? ''}'.trim();
    final headers = _stringMap(episode['imageHeaders']);
    final watched = episode['watched'] == true || episode['watched'] == 1,
        downloaded =
            episode['downloaded'] == true || episode['downloaded'] == 1;
    final duration = int.tryParse('${episode['duration'] ?? 0}') ?? 0;
    final resumeSeconds = int.tryParse('${episode['ts'] ?? 0}') ?? 0;
    final watchedSeconds = resumeSeconds > 0
        ? resumeSeconds
        : int.tryParse(
                '${episode['watchedTs'] ?? episode['watchedSeconds'] ?? episode['playedSeconds'] ?? 0}',
              ) ??
              0;
    final progress = duration > 0
        ? (watchedSeconds / duration).clamp(0, 1).toDouble()
        : 0.0;
    final image = DesktopEpisodePoster(
      poster,
      grid,
      headers: headers,
      current: current,
      watched: watched,
      progress: progress,
    );
    final content = grid
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: image),
              const SizedBox(height: 7),
              Text(
                l10n.playerEpisodeCardTitle(numberLabel, title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          )
        : Row(
            children: [
              // Flexible：面板宽度 morph（选集↔倍速等）时退场卡片会被临时
              // 压窄，固定宽海报会直接溢出报错；允许收缩即可优雅降级。
              Flexible(child: image),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.playerEpisodeCardTitle(numberLabel, title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (duration > 0)
                      Text(
                        _duration(duration),
                        style: const TextStyle(
                          color: Color(0x73FFFFFF),
                          fontSize: 11,
                        ),
                      ),
                    if (downloaded) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.download_rounded,
                            color: Colors.white70,
                            size: 13,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            l10n.playerDownloadedBadge,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
    return Opacity(
      opacity: enabled || current ? 1 : .5,
      child: Material(
        color: current ? const Color(0x2463A0FF) : const Color(0x121F2A3A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: current ? const Color(0x8063A0FF) : const Color(0x0FFFFFFF),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: const Color(0x1AFFFFFF),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(10), child: content),
        ),
      ),
    );
  }

  Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return const <String, String>{};
    return raw.map((key, value) => MapEntry(key.toString(), value.toString()));
  }

  String _duration(int s) =>
      '${s ~/ 3600 > 0 ? '${s ~/ 3600}:' : ''}${(s ~/ 60 % 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

class DesktopEpisodePoster extends StatelessWidget {
  const DesktopEpisodePoster(
    this.path,
    this.grid, {
    super.key,
    required this.headers,
    required this.current,
    this.gaplessPlayback = false,
    this.watched = false,
    this.progress = 0,
  });
  final String path;
  final bool grid;
  final Map<String, String> headers;
  final bool current;
  final bool gaplessPlayback;
  final bool watched;
  final double progress;
  @override
  Widget build(BuildContext c) {
    final l10n = AppLocalizations.of(c);
    final image = path.startsWith('http://') || path.startsWith('https://')
        ? Image.network(
            path,
            headers: headers,
            fit: BoxFit.cover,
            gaplessPlayback: gaplessPlayback,
            errorBuilder: (_, __, ___) => _placeholder(),
          )
        : path.isNotEmpty
        ? Image.file(
            File(playbackFilePath(path)),
            fit: BoxFit.cover,
            gaplessPlayback: gaplessPlayback,
            errorBuilder: (_, __, ___) => _placeholder(),
          )
        : _placeholder();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: grid ? double.infinity : 112,
        height: grid ? double.infinity : 64,
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            if (current)
              const ColoredBox(
                color: Color(0x42000000),
                child: Center(child: _NowPlayingIndicator()),
              ),
            if (watched)
              Positioned(
                right: 5,
                bottom: 5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xCC000000),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    child: Text(
                      l10n.playerEpisodeWatched,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
              )
            else if (progress > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  color: const Color(0xFF63A0FF),
                  backgroundColor: Colors.white24,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => const ColoredBox(
    color: Color(0x241F2A3A),
    child: Center(child: Icon(Icons.movie_outlined, color: Colors.white30)),
  );
}

class _NowPlayingIndicator extends StatefulWidget {
  const _NowPlayingIndicator();

  @override
  State<_NowPlayingIndicator> createState() => _NowPlayingIndicatorState();
}

class _NowPlayingIndicatorState extends State<_NowPlayingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List<Widget>.generate(5, (index) {
          final phase = (_controller.value + index * .17) % 1;
          final height = 6 + (phase < .5 ? phase : 1 - phase) * 24;
          return Container(
            width: 3,
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, Color(0xFF6EA8FF)],
              ),
              borderRadius: BorderRadius.circular(99),
            ),
          );
        }),
      ),
    );
  }
}
